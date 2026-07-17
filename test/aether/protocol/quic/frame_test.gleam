// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// QUIC Frame Layer Tests (RFC 9000 Section 19)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/quic/error.{Malformed}
import aether/protocol/quic/frame.{
  Ack, ConnectionClose, Crypto, DataBlocked, HandshakeDone, MaxData,
  MaxStreamData, MaxStreams, NewConnectionId, NewToken, Padding, PathChallenge,
  PathResponse, Ping, ResetStream, RetireConnectionId, StopSending, Stream,
  StreamDataBlocked, StreamsBlocked,
}
import aether/protocol/quic/frame_builder
import aether/protocol/quic/frame_parser
import gleam/option.{None, Some}
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Round-trip helper: build a frame, parse it back, expect the original.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn round_trip(f: frame.Frame) -> Nil {
  let assert Ok(built) = frame_builder.build_frame(f)
  frame_parser.parse_frames(built) |> should.equal(Ok([f]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PADDING / PING
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn padding_round_trip_test() {
  round_trip(Padding(5))
}

pub fn padding_coalesces_runs_test() {
  // Three PADDING bytes followed by a PING must collapse to one Padding(3).
  frame_parser.parse_frames(<<0, 0, 0, 1>>)
  |> should.equal(Ok([Padding(3), Ping]))
}

pub fn ping_round_trip_test() {
  round_trip(Ping)
}

pub fn ping_wire_bytes_test() {
  frame_builder.build_frame(Ping) |> should.equal(Ok(<<0x01>>))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ACK (hand-computed wire bytes)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn ack_multiple_ranges_wire_bytes_test() {
  // largest_acked=100 (2-byte varint 0x4064), ack_delay=5, range_count=2,
  // first_range=10, ranges [(gap=0,len=3), (gap=1,len=2)].
  let f = Ack(100, 5, 10, [#(0, 3), #(1, 2)], None)
  let wire = <<
    0x02, 0x40, 0x64, 0x05, 0x02, 0x0a, 0x00, 0x03, 0x01, 0x02,
  >>

  frame_builder.build_frame(f) |> should.equal(Ok(wire))
  frame_parser.parse_frames(wire) |> should.equal(Ok([f]))
}

pub fn ack_with_ecn_wire_bytes_test() {
  // largest_acked=50, ack_delay=2, range_count=0, first_range=5,
  // ecn=(ect0=1, ect1=0, ce=2).
  let f = Ack(50, 2, 5, [], Some(#(1, 0, 2)))
  let wire = <<0x03, 0x32, 0x02, 0x00, 0x05, 0x01, 0x00, 0x02>>

  frame_builder.build_frame(f) |> should.equal(Ok(wire))
  frame_parser.parse_frames(wire) |> should.equal(Ok([f]))
}

pub fn ack_no_ranges_no_ecn_round_trip_test() {
  round_trip(Ack(20, 0, 20, [], None))
}

pub fn ack_range_underflow_is_malformed_test() {
  // largest_acked=5, ack_delay=0, range_count=1, first_range=5
  // (smallest=0), then gap=0, len=0 -> next_largest = 0 - 0 - 2 = -2.
  let wire = <<0x02, 0x05, 0x00, 0x01, 0x05, 0x00, 0x00>>

  frame_parser.parse_frames(wire) |> should.equal(Error(Malformed(
    "ACK range gap underflows below 0",
  )))
}

pub fn ack_first_range_underflow_is_malformed_test() {
  // largest_acked=5, first_range=10 -> smallest = 5 - 10 < 0.
  let wire = <<0x02, 0x05, 0x00, 0x00, 0x0a>>

  let assert Malformed(_) = should.be_error(frame_parser.parse_frames(wire))
  Nil
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RESET_STREAM / STOP_SENDING
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn reset_stream_round_trip_test() {
  round_trip(ResetStream(4, 1, 1000))
}

pub fn stop_sending_round_trip_test() {
  round_trip(StopSending(4, 2))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CRYPTO / NEW_TOKEN (hand-computed wire bytes)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn crypto_wire_bytes_test() {
  // offset=0, length=3, data="ABC".
  let f = Crypto(0, <<0x41, 0x42, 0x43>>)
  let wire = <<0x06, 0x00, 0x03, 0x41, 0x42, 0x43>>

  frame_builder.build_frame(f) |> should.equal(Ok(wire))
  frame_parser.parse_frames(wire) |> should.equal(Ok([f]))
}

pub fn crypto_nonzero_offset_round_trip_test() {
  round_trip(Crypto(50, <<1, 2, 3, 4>>))
}

pub fn new_token_round_trip_test() {
  round_trip(NewToken(<<1, 2, 3>>))
}

pub fn new_token_empty_is_malformed_test() {
  // type=0x07, token length=0.
  frame_parser.parse_frames(<<0x07, 0x00>>)
  |> should.equal(Error(Malformed("NEW_TOKEN token must not be empty")))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// STREAM: builder round-trips plus every OFF/LEN/FIN wire permutation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stream_builder_sets_len_and_off_test() {
  // offset=0: OFF bit must be clear even though LEN is always set.
  let f = Stream(4, 0, <<1, 2, 3>>, False)
  let wire = <<0x0a, 0x04, 0x03, 1, 2, 3>>

  frame_builder.build_frame(f) |> should.equal(Ok(wire))
  frame_parser.parse_frames(wire) |> should.equal(Ok([f]))
}

pub fn stream_builder_sets_off_when_offset_positive_test() {
  let f = Stream(1, 100, <<9, 9>>, True)
  let wire = <<0x0f, 0x01, 0x40, 0x64, 0x02, 9, 9>>

  frame_builder.build_frame(f) |> should.equal(Ok(wire))
  frame_parser.parse_frames(wire) |> should.equal(Ok([f]))
}

pub fn stream_type_0x08_no_off_no_len_no_fin_test() {
  // No LEN bit: data runs to the end of the payload.
  frame_parser.parse_frames(<<0x08, 0x05, 0xaa, 0xbb>>)
  |> should.equal(Ok([Stream(5, 0, <<0xaa, 0xbb>>, False)]))
}

pub fn stream_type_0x09_fin_only_test() {
  frame_parser.parse_frames(<<0x09, 0x05, 0xaa, 0xbb>>)
  |> should.equal(Ok([Stream(5, 0, <<0xaa, 0xbb>>, True)]))
}

pub fn stream_type_0x0a_len_only_test() {
  frame_parser.parse_frames(<<0x0a, 0x05, 0x02, 0xaa, 0xbb>>)
  |> should.equal(Ok([Stream(5, 0, <<0xaa, 0xbb>>, False)]))
}

pub fn stream_type_0x0b_len_and_fin_test() {
  frame_parser.parse_frames(<<0x0b, 0x05, 0x02, 0xaa, 0xbb>>)
  |> should.equal(Ok([Stream(5, 0, <<0xaa, 0xbb>>, True)]))
}

pub fn stream_type_0x0c_off_only_test() {
  frame_parser.parse_frames(<<0x0c, 0x05, 0x0a, 0xaa, 0xbb>>)
  |> should.equal(Ok([Stream(5, 10, <<0xaa, 0xbb>>, False)]))
}

pub fn stream_type_0x0d_off_and_fin_test() {
  frame_parser.parse_frames(<<0x0d, 0x05, 0x0a, 0xaa, 0xbb>>)
  |> should.equal(Ok([Stream(5, 10, <<0xaa, 0xbb>>, True)]))
}

pub fn stream_type_0x0e_off_and_len_test() {
  frame_parser.parse_frames(<<0x0e, 0x05, 0x0a, 0x02, 0xaa, 0xbb>>)
  |> should.equal(Ok([Stream(5, 10, <<0xaa, 0xbb>>, False)]))
}

pub fn stream_type_0x0f_off_len_and_fin_test() {
  frame_parser.parse_frames(<<0x0f, 0x05, 0x0a, 0x02, 0xaa, 0xbb>>)
  |> should.equal(Ok([Stream(5, 10, <<0xaa, 0xbb>>, True)]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flow control frames
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn max_data_round_trip_test() {
  round_trip(MaxData(1_000_000))
}

pub fn max_stream_data_round_trip_test() {
  round_trip(MaxStreamData(4, 65_535))
}

pub fn max_streams_bidirectional_round_trip_test() {
  round_trip(MaxStreams(True, 100))
}

pub fn max_streams_unidirectional_round_trip_test() {
  round_trip(MaxStreams(False, 50))
}

pub fn max_streams_uses_distinct_type_codes_test() {
  frame_builder.build_frame(MaxStreams(True, 1))
  |> should.equal(Ok(<<0x12, 0x01>>))
  frame_builder.build_frame(MaxStreams(False, 1))
  |> should.equal(Ok(<<0x13, 0x01>>))
}

pub fn data_blocked_round_trip_test() {
  round_trip(DataBlocked(2048))
}

pub fn stream_data_blocked_round_trip_test() {
  round_trip(StreamDataBlocked(4, 2048))
}

pub fn streams_blocked_bidirectional_round_trip_test() {
  round_trip(StreamsBlocked(True, 10))
}

pub fn streams_blocked_unidirectional_round_trip_test() {
  round_trip(StreamsBlocked(False, 10))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection IDs / paths
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_connection_id_round_trip_test() {
  round_trip(NewConnectionId(
    1,
    0,
    <<1, 2, 3, 4, 5, 6, 7, 8>>,
    <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>,
  ))
}

pub fn new_connection_id_21_byte_cid_is_malformed_test() {
  // seq=1, retire_prior_to=0, cid_len=21 (too long), 21 cid bytes, then a
  // 16-byte token. The length check must fire before those bytes are read.
  let cid_21 = <<
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
  >>
  let token = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>
  let wire = <<<<0x18, 0x01, 0x00, 21>>:bits, cid_21:bits, token:bits>>

  let assert Malformed(_) = should.be_error(frame_parser.parse_frames(wire))
  Nil
}

pub fn new_connection_id_builder_rejects_long_cid_test() {
  let assert Malformed(_) =
    should.be_error(frame_builder.build_frame(NewConnectionId(
      1,
      0,
      cid_of_length(21),
      <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>,
    )))
  Nil
}

pub fn retire_connection_id_round_trip_test() {
  round_trip(RetireConnectionId(3))
}

pub fn path_challenge_round_trip_test() {
  round_trip(PathChallenge(<<1, 2, 3, 4, 5, 6, 7, 8>>))
}

pub fn path_response_round_trip_test() {
  round_trip(PathResponse(<<8, 7, 6, 5, 4, 3, 2, 1>>))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CONNECTION_CLOSE (transport 0x1c / application 0x1d)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn connection_close_transport_round_trip_test() {
  round_trip(ConnectionClose(10, Some(0x04), "bad state"))
}

pub fn connection_close_application_round_trip_test() {
  round_trip(ConnectionClose(1, None, ""))
}

pub fn connection_close_transport_uses_0x1c_test() {
  let assert Ok(<<type_byte, _rest:bits>>) =
    frame_builder.build_frame(ConnectionClose(0, Some(0), ""))
  type_byte |> should.equal(0x1c)
}

pub fn connection_close_application_uses_0x1d_test() {
  let assert Ok(<<type_byte, _rest:bits>>) =
    frame_builder.build_frame(ConnectionClose(0, None, ""))
  type_byte |> should.equal(0x1d)
}

pub fn connection_close_invalid_utf8_reason_is_malformed_test() {
  // error_code=0, no frame_type field (application, 0x1d), reason
  // length=1, reason byte=0xff (not valid UTF-8 on its own).
  frame_parser.parse_frames(<<0x1d, 0x00, 0x01, 0xff>>)
  |> should.equal(Error(Malformed(
    "CONNECTION_CLOSE reason is not valid UTF-8",
  )))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HANDSHAKE_DONE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn handshake_done_round_trip_test() {
  round_trip(HandshakeDone)
}

pub fn handshake_done_wire_bytes_test() {
  frame_builder.build_frame(HandshakeDone) |> should.equal(Ok(<<0x1e>>))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Multi-frame payloads and error handling
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_frames_multiple_frames_in_one_payload_test() {
  let assert Ok(bytes) =
    frame_builder.build_frames([Ping, MaxData(10), HandshakeDone])
  frame_parser.parse_frames(bytes)
  |> should.equal(Ok([Ping, MaxData(10), HandshakeDone]))
}

pub fn unknown_frame_type_is_malformed_test() {
  frame_parser.parse_frames(<<0x21>>)
  |> should.equal(Error(Malformed("unknown frame type 33")))
}

pub fn truncated_varint_inside_payload_is_malformed_not_need_more_data_test() {
  // MAX_DATA (0x10) followed by a 4-byte varint prefix but only 1 byte of
  // it: this must NOT be treated as "come back with more bytes" since the
  // payload is already fully decrypted.
  let assert Malformed(_) =
    should.be_error(frame_parser.parse_frames(<<0x10, 0x90>>))
  Nil
}

fn cid_of_length(n: Int) -> BitArray {
  case n {
    0 -> <<>>
    _ -> <<cid_of_length(n - 1):bits, 0:8>>
  }
}
