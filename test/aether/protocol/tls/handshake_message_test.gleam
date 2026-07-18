import aether/protocol/quic/error.{Malformed}
import aether/protocol/tls/handshake_message.{
  HandshakeMessage, buffered_size, client_hello_type, encode, finished_type,
  new_buffer, push,
}
import aether/protocol/tls/rfc8448_vectors
import gleam/bit_array
import gleeunit/should

fn hex(input: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(input)
  bytes
}

fn split_at(data: BitArray, at: Int) -> #(BitArray, BitArray) {
  let assert Ok(head) = bit_array.slice(data, 0, at)
  let assert Ok(tail) =
    bit_array.slice(data, at, bit_array.byte_size(data) - at)
  #(head, tail)
}

pub fn push_whole_message_at_once_test() {
  let ch = hex(rfc8448_vectors.client_hello)
  let assert Ok(#(buffer, messages)) = push(new_buffer(), ch)
  let assert Ok(body) = bit_array.slice(ch, 4, bit_array.byte_size(ch) - 4)
  messages |> should.equal([HandshakeMessage(client_hello_type, body)])
  buffered_size(buffer) |> should.equal(0)
}

pub fn push_splits_the_4_byte_header_test() {
  // Split after byte 3 - inside the 4-byte header, only one length byte
  // has arrived so far.
  let ch = hex(rfc8448_vectors.client_hello)
  let #(chunk1, chunk2) = split_at(ch, 3)

  let assert Ok(#(buffer, first_messages)) = push(new_buffer(), chunk1)
  first_messages |> should.equal([])
  buffered_size(buffer) |> should.equal(3)

  let assert Ok(#(buffer, second_messages)) = push(buffer, chunk2)
  let assert Ok(body) = bit_array.slice(ch, 4, bit_array.byte_size(ch) - 4)
  second_messages
  |> should.equal([HandshakeMessage(client_hello_type, body)])
  buffered_size(buffer) |> should.equal(0)
}

pub fn push_splits_mid_body_test() {
  let ch = hex(rfc8448_vectors.client_hello)
  let #(chunk1, chunk2) = split_at(ch, 20)

  let assert Ok(#(buffer, first_messages)) = push(new_buffer(), chunk1)
  first_messages |> should.equal([])

  let assert Ok(#(buffer, second_messages)) = push(buffer, chunk2)
  let assert Ok(body) = bit_array.slice(ch, 4, bit_array.byte_size(ch) - 4)
  second_messages
  |> should.equal([HandshakeMessage(client_hello_type, body)])
  buffered_size(buffer) |> should.equal(0)
}

pub fn push_two_concatenated_messages_test() {
  let first = encode(finished_type, <<1, 2, 3, 4>>)
  let second = encode(finished_type, <<5, 6>>)
  let assert Ok(#(buffer, messages)) =
    push(new_buffer(), bit_array.concat([first, second]))
  messages
  |> should.equal([
    HandshakeMessage(finished_type, <<1, 2, 3, 4>>),
    HandshakeMessage(finished_type, <<5, 6>>),
  ])
  buffered_size(buffer) |> should.equal(0)
}

pub fn push_retains_partial_tail_across_calls_test() {
  let first = encode(finished_type, <<1, 2, 3, 4>>)
  let second = encode(finished_type, <<5, 6>>)
  let #(second_head, second_tail) = split_at(second, 5)

  let assert Ok(#(buffer, messages1)) =
    push(new_buffer(), bit_array.concat([first, second_head]))
  messages1 |> should.equal([HandshakeMessage(finished_type, <<1, 2, 3, 4>>)])

  let assert Ok(#(buffer, messages2)) = push(buffer, second_tail)
  messages2 |> should.equal([HandshakeMessage(finished_type, <<5, 6>>)])
  buffered_size(buffer) |> should.equal(0)
}

pub fn encode_round_trips_through_push_test() {
  let body = <<0x01, 0x02, 0x03, 0x04, 0x05>>
  let encoded = encode(client_hello_type, body)
  let assert Ok(#(_buffer, messages)) = push(new_buffer(), encoded)
  messages |> should.equal([HandshakeMessage(client_hello_type, body)])
}

pub fn encode_produces_1_byte_type_3_byte_length_header_test() {
  let body = <<1, 2, 3>>
  encode(client_hello_type, body)
  |> should.equal(<<client_hello_type:8, 3:24, 1, 2, 3>>)
}

pub fn push_rejects_body_over_2_pow_17_test() {
  // Declares a body length one byte over the 2^17 sanity cap; the body
  // itself need not actually be present for the check to trigger.
  let oversized_header = <<1:8, 131_073:24>>
  push(new_buffer(), oversized_header)
  |> should.equal(Error(Malformed("handshake message body exceeds 2^17 bytes")))
}

pub fn push_accepts_body_at_2_pow_17_test() {
  // 131_072 bytes (2^17) of zeros - exactly at the sanity cap.
  let body = <<0:size(1_048_576)>>
  let encoded = encode(client_hello_type, body)
  let assert Ok(#(_buffer, messages)) = push(new_buffer(), encoded)
  messages |> should.equal([HandshakeMessage(client_hello_type, body)])
}

pub fn buffered_size_of_new_buffer_is_zero_test() {
  buffered_size(new_buffer()) |> should.equal(0)
}
