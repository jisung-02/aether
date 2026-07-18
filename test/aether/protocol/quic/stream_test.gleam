import aether/protocol/quic/stream
import gleeunit/should

// -- stream_kind / is_bidi / is_client_initiated ----------------------------

pub fn stream_kind_client_bidi_test() {
  stream.stream_kind(0) |> should.equal(stream.ClientBidi)
  stream.stream_kind(4) |> should.equal(stream.ClientBidi)
}

pub fn stream_kind_server_bidi_test() {
  stream.stream_kind(1) |> should.equal(stream.ServerBidi)
  stream.stream_kind(5) |> should.equal(stream.ServerBidi)
}

pub fn stream_kind_client_uni_test() {
  stream.stream_kind(2) |> should.equal(stream.ClientUni)
  stream.stream_kind(6) |> should.equal(stream.ClientUni)
}

pub fn stream_kind_server_uni_test() {
  stream.stream_kind(3) |> should.equal(stream.ServerUni)
  stream.stream_kind(7) |> should.equal(stream.ServerUni)
}

pub fn is_bidi_test() {
  stream.is_bidi(0) |> should.be_true
  stream.is_bidi(1) |> should.be_true
  stream.is_bidi(2) |> should.be_false
  stream.is_bidi(3) |> should.be_false
  stream.is_bidi(4) |> should.be_true
  stream.is_bidi(7) |> should.be_false
}

pub fn is_client_initiated_test() {
  stream.is_client_initiated(0) |> should.be_true
  stream.is_client_initiated(1) |> should.be_false
  stream.is_client_initiated(2) |> should.be_true
  stream.is_client_initiated(3) |> should.be_false
  stream.is_client_initiated(4) |> should.be_true
  stream.is_client_initiated(7) |> should.be_false
}

// -- ReceiveBuffer: in-order -------------------------------------------------

pub fn receive_in_order_two_chunks_then_read_test() {
  let assert Ok(b) =
    stream.new_receive() |> stream.receive(0, <<"hello">>, False)
  let assert Ok(b) = b |> stream.receive(5, <<" world">>, False)
  let #(b, bytes) = stream.read(b)
  bytes |> should.equal(<<"hello world">>)

  let #(_, more) = stream.read(b)
  more |> should.equal(<<>>)
}

// -- ReceiveBuffer: out-of-order ---------------------------------------------

pub fn receive_out_of_order_test() {
  let assert Ok(b) =
    stream.new_receive() |> stream.receive(5, <<"world">>, False)

  // Nothing contiguous from 0 yet.
  let #(b, bytes) = stream.read(b)
  bytes |> should.equal(<<>>)

  let assert Ok(b) = b |> stream.receive(0, <<"hello">>, False)
  let #(_, bytes) = stream.read(b)
  bytes |> should.equal(<<"helloworld">>)
}

// -- ReceiveBuffer: duplicate -------------------------------------------------

pub fn receive_duplicate_chunk_test() {
  let assert Ok(b) =
    stream.new_receive() |> stream.receive(0, <<"hello">>, False)
  let assert Ok(b) = b |> stream.receive(0, <<"hello">>, False)
  let #(_, bytes) = stream.read(b)
  bytes |> should.equal(<<"hello">>)
}

// -- ReceiveBuffer: overlapping -----------------------------------------------

pub fn receive_overlapping_chunks_test() {
  // offset 0 len 4 ("abcd"), then offset 2 len 4 ("cdef") -> "abcdef"
  let assert Ok(b) =
    stream.new_receive() |> stream.receive(0, <<"abcd">>, False)
  let assert Ok(b) = b |> stream.receive(2, <<"cdef">>, False)
  let #(_, bytes) = stream.read(b)
  bytes |> should.equal(<<"abcdef">>)
}

// -- ReceiveBuffer: fin --------------------------------------------------------

pub fn receive_fin_test() {
  let assert Ok(b) = stream.new_receive() |> stream.receive(0, <<"hi">>, False)
  stream.is_finished(b) |> should.be_false

  let assert Ok(b) = b |> stream.receive(2, <<"!">>, True)
  stream.is_finished(b) |> should.be_false

  let #(b, bytes) = stream.read(b)
  bytes |> should.equal(<<"hi!">>)
  stream.is_finished(b) |> should.be_true
}

// -- ReceiveBuffer: final-size violations --------------------------------------

pub fn receive_data_past_known_final_size_is_error_test() {
  let assert Ok(b) = stream.new_receive() |> stream.receive(0, <<"abcd">>, True)
  // final size is now 4; data starting at 5 lands past it.
  b |> stream.receive(5, <<"x">>, False) |> should.equal(Error(Nil))
}

pub fn receive_fin_below_existing_data_is_error_test() {
  let assert Ok(b) =
    stream.new_receive() |> stream.receive(10, <<"hello">>, False)
  // highest_offset is now 15; a FIN claiming final size 4 is a violation.
  b |> stream.receive(3, <<"x">>, True) |> should.equal(Error(Nil))
}

// -- ReceiveBuffer: highest_offset ---------------------------------------------

pub fn highest_offset_tracks_max_test() {
  let assert Ok(b) =
    stream.new_receive() |> stream.receive(0, <<"abcd">>, False)
  stream.highest_offset(b) |> should.equal(4)

  let assert Ok(b) = b |> stream.receive(10, <<"xy">>, False)
  stream.highest_offset(b) |> should.equal(12)

  // A smaller, earlier chunk does not lower it.
  let assert Ok(b) = b |> stream.receive(4, <<"z">>, False)
  stream.highest_offset(b) |> should.equal(12)
}

// -- SendBuffer -----------------------------------------------------------------

pub fn send_buffer_chunking_test() {
  let b =
    stream.new_send() |> stream.write(<<"hello">>) |> stream.write(<<"world">>)

  let #(b, offset, chunk, fin) = stream.next_chunk(b, 3)
  offset |> should.equal(0)
  chunk |> should.equal(<<"hel">>)
  fin |> should.be_false

  let #(b, offset, chunk, fin) = stream.next_chunk(b, 100)
  offset |> should.equal(3)
  chunk |> should.equal(<<"loworld">>)
  fin |> should.be_false

  let b = stream.close(b)
  let #(b, offset, chunk, fin) = stream.next_chunk(b, 100)
  offset |> should.equal(10)
  chunk |> should.equal(<<>>)
  fin |> should.be_true

  // The final empty chunk keeps reporting the FIN once the buffer is
  // drained and closed.
  let #(_, offset, chunk, fin) = stream.next_chunk(b, 100)
  offset |> should.equal(10)
  chunk |> should.equal(<<>>)
  fin |> should.be_true
}

pub fn send_buffer_empty_closed_buffer_test() {
  let b = stream.new_send() |> stream.close
  let #(_, offset, chunk, fin) = stream.next_chunk(b, 10)
  offset |> should.equal(0)
  chunk |> should.equal(<<>>)
  fin |> should.be_true
}
