// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/3 Frame Layer Tests (RFC 9114 Section 7)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/http3/frame.{
  CancelPush, Data, GoAway, Headers, MaxPushId, Settings, Unknown,
}
import aether/protocol/quic/error.{Malformed}
import aether/protocol/quic/varint
import gleam/bit_array
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Round-trip helper: build a frame, parse it back, expect the original
// with an empty tail.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn round_trip(f: frame.Http3Frame) -> Nil {
  frame.parse(frame.build(f)) |> should.equal(Ok(#([f], <<>>)))
}

pub fn data_round_trip_test() {
  round_trip(Data(<<1, 2, 3>>))
}

pub fn headers_round_trip_test() {
  round_trip(Headers(<<0x00, 0x00, 0xc1, 0xc5>>))
}

pub fn settings_round_trip_test() {
  round_trip(Settings([#(1, 0), #(6, 16_384)]))
}

pub fn goaway_round_trip_test() {
  round_trip(GoAway(0))
}

pub fn max_push_id_round_trip_test() {
  round_trip(MaxPushId(100))
}

pub fn cancel_push_round_trip_test() {
  round_trip(CancelPush(3))
}

pub fn unknown_round_trip_test() {
  round_trip(Unknown(0x21, <<9, 9>>))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Exact wire bytes
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn data_wire_bytes_test() {
  // type=0x00 (1-byte varint), length=1 (1-byte varint), payload=0xff.
  frame.build(Data(<<0xff>>)) |> should.equal(<<0x00, 0x01, 0xff>>)
}

pub fn settings_wire_bytes_test() {
  let built = frame.build(Settings([#(6, 0x4000)]))
  // type=0x04, length=5 (1-byte id + 4-byte value), id=6 (1-byte varint),
  // value=0x4000 (needs the 4-byte varint form since it exceeds the
  // 2-byte range of 0x3fff).
  built |> should.equal(<<0x04, 0x05, 0x06, 0x80, 0x00, 0x40, 0x00>>)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Multi-frame buffers and partial tails
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parses_two_concatenated_frames_test() {
  let first = Data(<<1, 2>>)
  let second = GoAway(5)
  let buffer = <<frame.build(first):bits, frame.build(second):bits>>

  frame.parse(buffer) |> should.equal(Ok(#([first, second], <<>>)))
}

pub fn partial_payload_leaves_tail_test() {
  let first = Data(<<1, 2>>)
  let second_whole = frame.build(Headers(<<0xaa, 0xbb, 0xcc>>))
  // Truncate the second frame in the middle of its payload (header is
  // type=0x01, length=0x03, so the first 3 bytes are the whole header
  // plus nothing of the payload yet... take 3 bytes total: header (2
  // bytes) + 1 payload byte).
  let assert Ok(second_partial) = bit_array.slice(second_whole, 0, 3)
  let buffer = <<frame.build(first):bits, second_partial:bits>>

  frame.parse(buffer) |> should.equal(Ok(#([first], second_partial)))
}

pub fn partial_length_varint_leaves_tail_test() {
  let first = Data(<<1, 2>>)
  // A lone type byte for HEADERS with no length varint following it yet.
  let second_partial = <<0x01>>
  let buffer = <<frame.build(first):bits, second_partial:bits>>

  frame.parse(buffer) |> should.equal(Ok(#([first], second_partial)))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SETTINGS validation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn settings_duplicate_identifier_is_malformed_test() {
  // type=0x04, length=4, then two id=1 entries with values 0 and 1.
  frame.parse(<<0x04, 0x04, 0x01, 0x00, 0x01, 0x01>>)
  |> should.equal(Error(Malformed("duplicate SETTINGS identifier 1")))
}

pub fn settings_dangling_identifier_is_malformed_test() {
  // type=0x04, length=1, a lone identifier byte with no value.
  frame.parse(<<0x04, 0x01, 0x01>>)
  |> should.equal(Error(Malformed("truncated SETTINGS value")))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GOAWAY validation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn goaway_trailing_bytes_is_malformed_test() {
  // type=0x07, length=2: a valid one-byte varint (0) plus one extra byte.
  frame.parse(<<0x07, 0x02, 0x00, 0xff>>)
  |> should.equal(Error(Malformed("trailing bytes after varint frame payload")))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Grease / unknown types (RFC 9114 Section 7.2.8: 0x1f * N + 0x21)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn grease_type_round_trips_as_unknown_test() {
  let grease_type = 0x1f * 2 + 0x21
  round_trip(Unknown(grease_type, <<0x01, 0x02>>))
}

pub fn grease_type_parses_to_unknown_test() {
  let grease_type = 0x1f * 2 + 0x21
  let assert Ok(type_bytes) = varint.encode(grease_type)
  let buffer = <<type_bytes:bits, 0x02, 0xaa, 0xbb>>

  frame.parse(buffer)
  |> should.equal(Ok(#([Unknown(grease_type, <<0xaa, 0xbb>>)], <<>>)))
}
