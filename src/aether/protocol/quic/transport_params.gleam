//// QUIC transport parameters (RFC 9000 Section 18).
////
//// Transport parameters are exchanged inside the TLS handshake as a
//// sequence of TLV-encoded values: a varint identifier, a varint length,
//// and `length` bytes of value. Unknown identifiers — including GREASE
//// values of the form `31 * N + 27` (RFC 9000 Section 18.1) — are ignored
//// on decode so the wire format can be extended without breaking existing
//// implementations.

import aether/protocol/quic/error.{type WireError, Malformed}
import aether/protocol/quic/varint
import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Largest permitted value for `initial_max_streams_bidi` and
/// `initial_max_streams_uni` (RFC 9000 Section 18.2): 2^60.
const max_streams_limit = 1_152_921_504_606_846_976

/// Transport parameters as defined by RFC 9000 Section 18.2.
///
/// `original_destination_connection_id`, `stateless_reset_token`, and
/// `retry_source_connection_id` are sent by servers only. The
/// `preferred_address` parameter (id 0x0d) is not modeled: its bytes are
/// skipped on decode and it is never produced by `encode`.
pub type TransportParams {
  TransportParams(
    original_destination_connection_id: Option(BitArray),
    max_idle_timeout: Option(Int),
    stateless_reset_token: Option(BitArray),
    max_udp_payload_size: Option(Int),
    initial_max_data: Option(Int),
    initial_max_stream_data_bidi_local: Option(Int),
    initial_max_stream_data_bidi_remote: Option(Int),
    initial_max_stream_data_uni: Option(Int),
    initial_max_streams_bidi: Option(Int),
    initial_max_streams_uni: Option(Int),
    ack_delay_exponent: Option(Int),
    max_ack_delay: Option(Int),
    disable_active_migration: Bool,
    active_connection_id_limit: Option(Int),
    initial_source_connection_id: Option(BitArray),
    retry_source_connection_id: Option(BitArray),
  )
}

/// An empty parameter set: every optional field is `None` and
/// `disable_active_migration` is `False`.
pub fn new() -> TransportParams {
  TransportParams(
    original_destination_connection_id: None,
    max_idle_timeout: None,
    stateless_reset_token: None,
    max_udp_payload_size: None,
    initial_max_data: None,
    initial_max_stream_data_bidi_local: None,
    initial_max_stream_data_bidi_remote: None,
    initial_max_stream_data_uni: None,
    initial_max_streams_bidi: None,
    initial_max_streams_uni: None,
    ack_delay_exponent: None,
    max_ack_delay: None,
    disable_active_migration: False,
    active_connection_id_limit: None,
    initial_source_connection_id: None,
    retry_source_connection_id: None,
  )
}

/// Decodes a transport parameters extension body: a back-to-back sequence
/// of TLV entries with no outer length prefix.
///
/// Unknown parameter ids are skipped. A parameter id that appears more than
/// once, a TLV that runs past the end of `data`, or a value that violates
/// an RFC 9000 Section 18.2 constraint all yield `Malformed`.
pub fn decode(data: BitArray) -> Result(TransportParams, WireError) {
  decode_loop(data, new(), [])
}

fn decode_loop(
  data: BitArray,
  acc: TransportParams,
  seen: List(Int),
) -> Result(TransportParams, WireError) {
  case data {
    <<>> -> Ok(acc)
    _ -> {
      use #(id, after_id) <- result.try(require(varint.decode(data)))
      use #(length, after_length) <- result.try(require(varint.decode(
        after_id,
      )))
      use #(value, after_value) <- result.try(require(split(
        after_length,
        length,
      )))
      case list.contains(seen, id) {
        True ->
          Error(Malformed(
            "duplicate transport parameter id " <> int_to_hex(id),
          ))
        False -> {
          use next_acc <- result.try(apply_param(acc, id, value))
          decode_loop(after_value, next_acc, [id, ..seen])
        }
      }
    }
  }
}

/// Applies one decoded (id, value) pair to the accumulator, validating the
/// value against the constraints in RFC 9000 Section 18.2.
fn apply_param(
  acc: TransportParams,
  id: Int,
  value: BitArray,
) -> Result(TransportParams, WireError) {
  case id {
    0x00 ->
      Ok(
        TransportParams(
          ..acc,
          original_destination_connection_id: Some(value),
        ),
      )
    0x01 -> {
      use n <- result.try(decode_int_value(value))
      Ok(TransportParams(..acc, max_idle_timeout: Some(n)))
    }
    0x02 ->
      case bit_array.byte_size(value) {
        16 -> Ok(TransportParams(..acc, stateless_reset_token: Some(value)))
        _ -> Error(Malformed("stateless_reset_token must be exactly 16 bytes"))
      }
    0x03 -> {
      use n <- result.try(decode_int_value(value))
      case n < 1200 {
        True -> Error(Malformed("max_udp_payload_size must be at least 1200"))
        False -> Ok(TransportParams(..acc, max_udp_payload_size: Some(n)))
      }
    }
    0x04 -> {
      use n <- result.try(decode_int_value(value))
      Ok(TransportParams(..acc, initial_max_data: Some(n)))
    }
    0x05 -> {
      use n <- result.try(decode_int_value(value))
      Ok(TransportParams(..acc, initial_max_stream_data_bidi_local: Some(n)))
    }
    0x06 -> {
      use n <- result.try(decode_int_value(value))
      Ok(TransportParams(..acc, initial_max_stream_data_bidi_remote: Some(n)))
    }
    0x07 -> {
      use n <- result.try(decode_int_value(value))
      Ok(TransportParams(..acc, initial_max_stream_data_uni: Some(n)))
    }
    0x08 -> {
      use n <- result.try(decode_int_value(value))
      case n > max_streams_limit {
        True -> Error(Malformed("initial_max_streams_bidi exceeds 2^60"))
        False -> Ok(TransportParams(..acc, initial_max_streams_bidi: Some(n)))
      }
    }
    0x09 -> {
      use n <- result.try(decode_int_value(value))
      case n > max_streams_limit {
        True -> Error(Malformed("initial_max_streams_uni exceeds 2^60"))
        False -> Ok(TransportParams(..acc, initial_max_streams_uni: Some(n)))
      }
    }
    0x0a -> {
      use n <- result.try(decode_int_value(value))
      case n > 20 {
        True -> Error(Malformed("ack_delay_exponent must not exceed 20"))
        False -> Ok(TransportParams(..acc, ack_delay_exponent: Some(n)))
      }
    }
    0x0b -> {
      use n <- result.try(decode_int_value(value))
      case n >= 16_384 {
        True -> Error(Malformed("max_ack_delay must be less than 2^14"))
        False -> Ok(TransportParams(..acc, max_ack_delay: Some(n)))
      }
    }
    0x0c ->
      case bit_array.byte_size(value) {
        0 -> Ok(TransportParams(..acc, disable_active_migration: True))
        _ -> Error(Malformed("disable_active_migration must have length 0"))
      }
    // preferred_address (0x0d) is not modeled; skip its bytes.
    0x0d -> Ok(acc)
    0x0e -> {
      use n <- result.try(decode_int_value(value))
      Ok(TransportParams(..acc, active_connection_id_limit: Some(n)))
    }
    0x0f ->
      Ok(TransportParams(..acc, initial_source_connection_id: Some(value)))
    0x10 ->
      Ok(TransportParams(..acc, retry_source_connection_id: Some(value)))
    // Unknown ids, including GREASE (31 * N + 27), are ignored.
    _ -> Ok(acc)
  }
}

/// Decodes an integer-valued parameter: the value bytes must contain
/// exactly one varint with no leftover bytes.
fn decode_int_value(value: BitArray) -> Result(Int, WireError) {
  case varint.decode(value) {
    Error(_) -> Error(Malformed("malformed integer transport parameter"))
    Ok(#(n, <<>>)) -> Ok(n)
    Ok(#(_, _)) ->
      Error(Malformed("trailing bytes in integer transport parameter"))
  }
}

/// Splits `data` into its first `length` bytes and the remainder.
fn split(data: BitArray, length: Int) -> Result(#(BitArray, BitArray), Nil) {
  let available = bit_array.byte_size(data)
  case length < 0 || length > available {
    True -> Error(Nil)
    False -> {
      case bit_array.slice(data, 0, length) {
        Error(_) -> Error(Nil)
        Ok(value) ->
          case bit_array.slice(data, length, available - length) {
            Error(_) -> Error(Nil)
            Ok(rest) -> Ok(#(value, rest))
          }
      }
    }
  }
}

/// Maps any error from a lower-level result to `Malformed`. Transport
/// parameters are decoded from a complete, already-reassembled extension
/// body, so there is no streaming concept here: a short read is a protocol
/// violation, not a request for more data.
fn require(result: Result(a, e)) -> Result(a, WireError) {
  case result {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Malformed("truncated transport parameter"))
  }
}

/// Renders an id as `0x`-prefixed hex for error messages, without pulling
/// in `gleam/int` for a single call site.
fn int_to_hex(value: Int) -> String {
  case value {
    v if v < 16 -> "0x0" <> hex_digit(v)
    v -> int_to_hex(v / 16) <> hex_digit(v % 16)
  }
}

fn hex_digit(value: Int) -> String {
  case value {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    10 -> "a"
    11 -> "b"
    12 -> "c"
    13 -> "d"
    14 -> "e"
    _ -> "f"
  }
}

/// Encodes `params` as a transport parameters extension body: only
/// `Some`/`True` fields are emitted, each as a (varint id, varint length,
/// value) TLV, in field declaration order.
pub fn encode(params: TransportParams) -> Result(BitArray, WireError) {
  use p0 <- result.try(maybe_bytes_param(
    0x00,
    params.original_destination_connection_id,
  ))
  use p1 <- result.try(maybe_int_param(0x01, params.max_idle_timeout))
  use p2 <- result.try(maybe_bytes_param(0x02, params.stateless_reset_token))
  use p3 <- result.try(maybe_int_param(0x03, params.max_udp_payload_size))
  use p4 <- result.try(maybe_int_param(0x04, params.initial_max_data))
  use p5 <- result.try(maybe_int_param(
    0x05,
    params.initial_max_stream_data_bidi_local,
  ))
  use p6 <- result.try(maybe_int_param(
    0x06,
    params.initial_max_stream_data_bidi_remote,
  ))
  use p7 <- result.try(maybe_int_param(
    0x07,
    params.initial_max_stream_data_uni,
  ))
  use p8 <- result.try(maybe_int_param(0x08, params.initial_max_streams_bidi))
  use p9 <- result.try(maybe_int_param(0x09, params.initial_max_streams_uni))
  use p10 <- result.try(maybe_int_param(0x0a, params.ack_delay_exponent))
  use p11 <- result.try(maybe_int_param(0x0b, params.max_ack_delay))
  use p12 <- result.try(case params.disable_active_migration {
    True -> encode_bytes_param(0x0c, <<>>)
    False -> Ok(<<>>)
  })
  use p14 <- result.try(maybe_int_param(
    0x0e,
    params.active_connection_id_limit,
  ))
  use p15 <- result.try(maybe_bytes_param(
    0x0f,
    params.initial_source_connection_id,
  ))
  use p16 <- result.try(maybe_bytes_param(
    0x10,
    params.retry_source_connection_id,
  ))
  Ok(
    bit_array.concat([
      p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p14, p15, p16,
    ]),
  )
}

/// Encodes one TLV entry, or `<<>>` if the field is absent.
fn maybe_int_param(id: Int, value: Option(Int)) -> Result(BitArray, WireError) {
  case value {
    None -> Ok(<<>>)
    Some(n) -> encode_int_param(id, n)
  }
}

/// Encodes one TLV entry, or `<<>>` if the field is absent.
fn maybe_bytes_param(
  id: Int,
  value: Option(BitArray),
) -> Result(BitArray, WireError) {
  case value {
    None -> Ok(<<>>)
    Some(bytes) -> encode_bytes_param(id, bytes)
  }
}

/// Encodes a single (varint id, varint length, value) TLV for an
/// integer-valued parameter.
fn encode_int_param(id: Int, value: Int) -> Result(BitArray, WireError) {
  use value_bytes <- result.try(varint.encode(value))
  encode_bytes_param(id, value_bytes)
}

/// Encodes a single (varint id, varint length, value) TLV for a raw byte
/// value.
fn encode_bytes_param(id: Int, value: BitArray) -> Result(BitArray, WireError) {
  use id_bytes <- result.try(varint.encode(id))
  use length_bytes <- result.try(varint.encode(bit_array.byte_size(value)))
  Ok(bit_array.concat([id_bytes, length_bytes, value]))
}
