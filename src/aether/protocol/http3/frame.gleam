//// HTTP/3 frame layer (RFC 9114 Section 7).
////
//// Every frame is `Type (varint) | Length (varint) | Payload (Length
//// bytes)`. `parse` only ever consumes whole frames: a type/length header
//// or a payload that has not fully arrived yet is left untouched in the
//// returned tail rather than erroring, since HTTP/3 frames stream in
//// incrementally over a QUIC stream. Reserved "grease" type codes (Section
//// 7.2.8, `0x1f * N + 0x21`) and any other type this module does not
//// otherwise construct decode to `Unknown` and are ignored by callers.

import aether/protocol/quic/error.{type WireError, Malformed}
import aether/protocol/quic/varint
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result

/// A parsed HTTP/3 frame (RFC 9114 Section 7.2).
pub type Http3Frame {
  /// DATA (Section 7.2.1): raw payload bytes carrying message body content.
  Data(BitArray)
  /// HEADERS (Section 7.2.2): a QPACK-encoded field section.
  Headers(BitArray)
  /// SETTINGS (Section 7.2.4): identifier/value pairs.
  Settings(List(#(Int, Int)))
  /// GOAWAY (Section 7.2.6): the last processed stream or push ID.
  GoAway(Int)
  /// MAX_PUSH_ID (Section 7.2.7): the largest push ID the client permits.
  MaxPushId(Int)
  /// CANCEL_PUSH (Section 7.2.3): a push ID being cancelled.
  CancelPush(Int)
  /// Any frame type this module does not otherwise construct: reserved
  /// grease types (Section 7.2.8), PUSH_PROMISE (Section 7.2.5, out of
  /// scope for this phase), and anything else unrecognised. Carries the
  /// raw payload untouched so it can be ignored or re-emitted as-is.
  Unknown(frame_type: Int, payload: BitArray)
}

/// DATA frame type (RFC 9114 Section 7.2.1).
pub const data_type = 0x00

/// HEADERS frame type (RFC 9114 Section 7.2.2).
pub const headers_type = 0x01

/// CANCEL_PUSH frame type (RFC 9114 Section 7.2.3).
pub const cancel_push_type = 0x03

/// SETTINGS frame type (RFC 9114 Section 7.2.4).
pub const settings_type = 0x04

/// GOAWAY frame type (RFC 9114 Section 7.2.6).
pub const goaway_type = 0x07

/// MAX_PUSH_ID frame type (RFC 9114 Section 7.2.7).
pub const max_push_id_type = 0x0d

/// SETTINGS_QPACK_MAX_TABLE_CAPACITY identifier (RFC 9204 Section 5).
pub const qpack_max_table_capacity = 0x01

/// SETTINGS_MAX_FIELD_SECTION_SIZE identifier (RFC 9114 Section 7.2.4.1).
pub const max_field_section_size = 0x06

/// SETTINGS_QPACK_BLOCKED_STREAMS identifier (RFC 9204 Section 5).
pub const qpack_blocked_streams = 0x07

/// Parses as many complete frames as `data` holds, returning them in wire
/// order together with whatever unconsumed bytes remain (a partial
/// type/length header, or a payload still in flight). The tail is never an
/// error: callers should buffer it and retry once more bytes have arrived.
/// A structurally invalid frame that is fully present (e.g. a malformed
/// SETTINGS payload) still fails with `Malformed`.
pub fn parse(
  data: BitArray,
) -> Result(#(List(Http3Frame), BitArray), WireError) {
  parse_loop(data, [])
}

fn parse_loop(
  data: BitArray,
  acc: List(Http3Frame),
) -> Result(#(List(Http3Frame), BitArray), WireError) {
  case read_header(data) {
    Error(Nil) -> Ok(#(list.reverse(acc), data))
    Ok(#(frame_type, length, rest)) ->
      case take_bytes(rest, length) {
        Error(Nil) -> Ok(#(list.reverse(acc), data))
        Ok(#(payload, tail)) -> {
          use frame <- result.try(decode_payload(frame_type, payload))
          parse_loop(tail, [frame, ..acc])
        }
      }
  }
}

/// Reads the `Type | Length` header, if both varints are fully present.
fn read_header(data: BitArray) -> Result(#(Int, Int, BitArray), Nil) {
  case varint.decode(data) {
    Error(_) -> Error(Nil)
    Ok(#(frame_type, rest)) ->
      case varint.decode(rest) {
        Error(_) -> Error(Nil)
        Ok(#(length, rest)) -> Ok(#(frame_type, length, rest))
      }
  }
}

/// Takes exactly `count` bytes off the front of `data`, or fails if fewer
/// than `count` bytes are available.
fn take_bytes(
  data: BitArray,
  count: Int,
) -> Result(#(BitArray, BitArray), Nil) {
  case bit_array.byte_size(data) < count {
    True -> Error(Nil)
    False ->
      case
        bit_array.slice(data, 0, count),
        bit_array.slice(data, count, bit_array.byte_size(data) - count)
      {
        Ok(taken), Ok(remaining) -> Ok(#(taken, remaining))
        _, _ -> Error(Nil)
      }
  }
}

fn decode_payload(
  frame_type: Int,
  payload: BitArray,
) -> Result(Http3Frame, WireError) {
  case frame_type {
    t if t == data_type -> Ok(Data(payload))
    t if t == headers_type -> Ok(Headers(payload))
    t if t == settings_type -> decode_settings(payload) |> result.map(Settings)
    t if t == goaway_type -> decode_single_varint(payload) |> result.map(GoAway)
    t if t == max_push_id_type ->
      decode_single_varint(payload) |> result.map(MaxPushId)
    t if t == cancel_push_type ->
      decode_single_varint(payload) |> result.map(CancelPush)
    _ -> Ok(Unknown(frame_type, payload))
  }
}

/// Decodes a payload that must be exactly one varint and nothing else
/// (GOAWAY, MAX_PUSH_ID, CANCEL_PUSH).
fn decode_single_varint(payload: BitArray) -> Result(Int, WireError) {
  case varint.decode(payload) {
    Error(_) -> Error(Malformed("truncated varint frame payload"))
    Ok(#(value, <<>>)) -> Ok(value)
    Ok(#(_, _)) -> Error(Malformed("trailing bytes after varint frame payload"))
  }
}

/// Decodes SETTINGS identifier/value pairs (RFC 9114 Section 7.2.4). A
/// dangling identifier with no matching value, or a repeated identifier
/// (Section 7.2.4.1), is malformed.
fn decode_settings(payload: BitArray) -> Result(List(#(Int, Int)), WireError) {
  decode_settings_loop(payload, [], [])
}

fn decode_settings_loop(
  data: BitArray,
  seen: List(Int),
  acc: List(#(Int, Int)),
) -> Result(List(#(Int, Int)), WireError) {
  case data {
    <<>> -> Ok(list.reverse(acc))
    _ ->
      case varint.decode(data) {
        Error(_) -> Error(Malformed("truncated SETTINGS identifier"))
        Ok(#(id, rest)) ->
          case varint.decode(rest) {
            Error(_) -> Error(Malformed("truncated SETTINGS value"))
            Ok(#(value, rest)) ->
              case list.contains(seen, id) {
                True ->
                  Error(Malformed(
                    "duplicate SETTINGS identifier " <> int.to_string(id),
                  ))
                False ->
                  decode_settings_loop(rest, [id, ..seen], [#(id, value), ..acc])
              }
          }
      }
  }
}

/// Encodes a frame to its wire representation.
pub fn build(frame: Http3Frame) -> BitArray {
  case frame {
    Data(payload) -> build_framed(data_type, payload)
    Headers(payload) -> build_framed(headers_type, payload)
    Settings(pairs) ->
      build_framed(settings_type, build_settings_payload(pairs))
    GoAway(id) -> build_framed(goaway_type, varint_bytes(id))
    MaxPushId(id) -> build_framed(max_push_id_type, varint_bytes(id))
    CancelPush(id) -> build_framed(cancel_push_type, varint_bytes(id))
    Unknown(frame_type, payload) -> build_framed(frame_type, payload)
  }
}

/// Encodes the `Type | Length | Payload` wire layout common to every frame.
fn build_framed(frame_type: Int, payload: BitArray) -> BitArray {
  bit_array.concat([
    varint_bytes(frame_type),
    varint_bytes(bit_array.byte_size(payload)),
    payload,
  ])
}

fn build_settings_payload(pairs: List(#(Int, Int))) -> BitArray {
  case pairs {
    [] -> <<>>
    [#(id, value), ..rest] ->
      bit_array.concat([
        varint_bytes(id),
        varint_bytes(value),
        build_settings_payload(rest),
      ])
  }
}

/// Encodes `value` as a `quic/varint`. Frame types, lengths, and the
/// identifiers/values this module builds are always within the varint
/// range (0 to 2^62 - 1) in practice; the fallback to an empty encoding
/// only matters for a caller-constructed frame carrying an out-of-range
/// value, which has no valid wire form to produce anyway.
fn varint_bytes(value: Int) -> BitArray {
  case varint.encode(value) {
    Ok(bytes) -> bytes
    Error(_) -> <<>>
  }
}
