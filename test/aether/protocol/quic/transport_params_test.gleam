import aether/protocol/quic/error.{Malformed}
import aether/protocol/quic/transport_params.{TransportParams}
import aether/protocol/quic/varint
import gleam/bit_array
import gleam/option.{None, Some}
import gleeunit/should

// Builds a single (varint id, varint length, value) TLV for hand-assembled
// test fixtures.
fn tlv(id: Int, value: BitArray) -> BitArray {
  let assert Ok(id_bytes) = varint.encode(id)
  let assert Ok(length_bytes) = varint.encode(bit_array.byte_size(value))
  bit_array.concat([id_bytes, length_bytes, value])
}

fn varint_bytes(value: Int) -> BitArray {
  let assert Ok(bytes) = varint.encode(value)
  bytes
}

pub fn new_is_all_absent_test() {
  let params = transport_params.new()
  params.max_idle_timeout |> should.equal(None)
  params.disable_active_migration |> should.equal(False)
}

pub fn encode_decode_empty_round_trip_test() {
  let params = transport_params.new()
  let assert Ok(encoded) = transport_params.encode(params)
  encoded |> should.equal(<<>>)
  transport_params.decode(encoded) |> should.equal(Ok(params))
}

pub fn encode_decode_all_fields_round_trip_test() {
  let params =
    TransportParams(
      original_destination_connection_id: Some(<<1, 2, 3, 4>>),
      max_idle_timeout: Some(30_000),
      stateless_reset_token: Some(<<
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
      >>),
      max_udp_payload_size: Some(1452),
      initial_max_data: Some(100_000),
      initial_max_stream_data_bidi_local: Some(65_536),
      initial_max_stream_data_bidi_remote: Some(65_536),
      initial_max_stream_data_uni: Some(65_536),
      initial_max_streams_bidi: Some(100),
      initial_max_streams_uni: Some(100),
      ack_delay_exponent: Some(3),
      max_ack_delay: Some(25),
      disable_active_migration: True,
      active_connection_id_limit: Some(4),
      initial_source_connection_id: Some(<<5, 6, 7, 8>>),
      retry_source_connection_id: Some(<<9, 10, 11, 12>>),
    )

  let assert Ok(encoded) = transport_params.encode(params)
  transport_params.decode(encoded) |> should.equal(Ok(params))
}

pub fn encode_decode_sparse_fields_round_trip_test() {
  let params =
    TransportParams(
      ..transport_params.new(),
      initial_max_data: Some(42),
      initial_max_streams_bidi: Some(7),
    )

  let assert Ok(encoded) = transport_params.encode(params)
  transport_params.decode(encoded) |> should.equal(Ok(params))
}

pub fn decode_unknown_and_grease_id_skipped_test() {
  // GREASE id 31*0+27 = 27, carrying arbitrary bytes that must be ignored,
  // followed by a real parameter that must still be picked up.
  let raw =
    bit_array.concat([
      tlv(27, <<0xaa, 0xbb, 0xcc>>),
      tlv(0x01, varint_bytes(30)),
    ])

  transport_params.decode(raw)
  |> should.equal(Ok(
    TransportParams(..transport_params.new(), max_idle_timeout: Some(30)),
  ))
}

pub fn decode_duplicate_id_is_malformed_test() {
  let raw =
    bit_array.concat([tlv(0x01, varint_bytes(5)), tlv(0x01, varint_bytes(6))])

  transport_params.decode(raw)
  |> should.equal(Error(Malformed("duplicate transport parameter id 0x01")))
}

pub fn decode_ack_delay_exponent_too_large_is_malformed_test() {
  let raw = tlv(0x0a, varint_bytes(21))

  transport_params.decode(raw)
  |> should.equal(Error(Malformed("ack_delay_exponent must not exceed 20")))
}

pub fn decode_max_udp_payload_size_too_small_is_malformed_test() {
  let raw = tlv(0x03, varint_bytes(1199))

  transport_params.decode(raw)
  |> should.equal(
    Error(Malformed("max_udp_payload_size must be at least 1200")),
  )
}

pub fn decode_max_ack_delay_too_large_is_malformed_test() {
  let raw = tlv(0x0b, varint_bytes(16_384))

  transport_params.decode(raw)
  |> should.equal(Error(Malformed("max_ack_delay must be less than 2^14")))
}

pub fn decode_initial_max_streams_bidi_exceeds_limit_is_malformed_test() {
  let raw = tlv(0x08, varint_bytes(1_152_921_504_606_846_977))

  transport_params.decode(raw)
  |> should.equal(Error(Malformed("initial_max_streams_bidi exceeds 2^60")))
}

pub fn decode_disable_active_migration_nonzero_length_is_malformed_test() {
  let raw = tlv(0x0c, <<1>>)

  transport_params.decode(raw)
  |> should.equal(
    Error(Malformed("disable_active_migration must have length 0")),
  )
}

pub fn decode_stateless_reset_token_wrong_length_is_malformed_test() {
  let raw = tlv(0x02, <<1, 2, 3>>)

  transport_params.decode(raw)
  |> should.equal(
    Error(Malformed("stateless_reset_token must be exactly 16 bytes")),
  )
}

pub fn decode_truncated_tlv_is_malformed_test() {
  // Declares a length of 4 but only supplies 2 bytes of value.
  let raw = <<0x04, 0x04, 0x01, 0x02>>

  transport_params.decode(raw)
  |> should.equal(Error(Malformed("truncated transport parameter")))
}

pub fn decode_trailing_bytes_in_integer_value_is_malformed_test() {
  // Length says 2 bytes but a 1-byte varint only consumes the first,
  // leaving a stray trailing byte inside the declared value.
  let raw = tlv(0x01, <<0x05, 0x00>>)

  transport_params.decode(raw)
  |> should.equal(
    Error(Malformed("trailing bytes in integer transport parameter")),
  )
}

pub fn wire_bytes_for_initial_max_data_test() {
  let params =
    TransportParams(..transport_params.new(), initial_max_data: Some(100_000))

  let assert Ok(encoded) = transport_params.encode(params)
  encoded |> should.equal(<<0x04, 0x04, 0x80, 0x01, 0x86, 0xa0>>)

  transport_params.decode(<<0x04, 0x04, 0x80, 0x01, 0x86, 0xa0>>)
  |> should.equal(Ok(params))
}
