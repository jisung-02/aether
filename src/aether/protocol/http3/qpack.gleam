//// QPACK field line compression (RFC 9204), static-table-only.
////
//// The server advertises `SETTINGS_QPACK_MAX_TABLE_CAPACITY = 0`, so no
//// dynamic table is ever granted or used in either direction. Every
//// encoded field section therefore has a Required Insert Count of 0 and a
//// Base of 0, and every field line is either an Indexed Field Line
//// referencing the static table or a literal (with a static name
//// reference or a fully literal name). Dynamic-table and post-base
//// representations are rejected as malformed, since this decoder never
//// grants any dynamic table capacity.
////
//// The prefixed-integer codec is reused from `http2/hpack/integer` (RFC
//// 7541 Section 5.1, identical in QPACK) and the Huffman codec from
//// `http2/hpack/huffman` (RFC 7541 Appendix B, also reused unchanged by
//// QPACK).

import aether/protocol/http2/hpack/huffman
import aether/protocol/http2/hpack/integer
import aether/protocol/http3/qpack_static
import aether/protocol/quic/error.{type WireError, Malformed}
import gleam/bit_array
import gleam/int
import gleam/list

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Bit flags (RFC 9204 Section 4.5)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Indexed Field Line: `1Txxxxxx`, 6-bit prefix index.
const indexed_prefix = 0xC0

/// Literal Field Line with Name Reference: `01NTxxxx`, 4-bit prefix index.
const literal_name_ref_prefix = 0x50

/// Literal Field Line with Literal Name: `001NHxxx`, 3-bit prefix length.
const literal_literal_name_prefix = 0x20

/// Huffman flag for the literal name's length byte (the `H` in `001NHxxx`).
const literal_name_huffman_flag = 0x08

/// The static-table flag `T` in the Indexed Field Line (`1Txxxxxx`): the
/// second-highest bit.
const indexed_static_flag = 0x40

/// The static-table flag `T` in the Literal Field Line with Name
/// Reference (`01NTxxxx`): the fourth bit, distinct from
/// `indexed_static_flag` because the top two bits there are the fixed
/// `01` pattern marker, not `T`.
const name_ref_static_flag = 0x10

/// The Huffman flag `H` on a string literal's length byte.
const string_huffman_flag = 0x80

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decoding
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Decodes a complete QPACK-encoded field section into an ordered list of
/// `#(name, value)` pairs.
///
/// A field section arrives complete inside a single HEADERS frame, so any
/// truncation is treated as `Malformed` rather than `NeedMoreData`. A
/// nonzero Required Insert Count, a nonzero Base, any reference to the
/// dynamic table (indexed or by name), any post-base representation, or a
/// Huffman decode failure are all `Malformed`.
///
pub fn decode(data: BitArray) -> Result(List(#(String, String)), WireError) {
  case decode_prefix(data) {
    Error(err) -> Error(err)
    Ok(rest) -> decode_field_lines(rest, [])
  }
}

/// Parses the Encoded Field Section Prefix (RFC 9204 Section 4.5.1):
/// Required Insert Count (8-bit prefix integer), then a sign bit and Delta
/// Base (7-bit prefix integer). Since the dynamic table capacity is always
/// 0, both must decode to zero.
///
fn decode_prefix(data: BitArray) -> Result(BitArray, WireError) {
  case integer.decode_integer(data, 8) {
    Error(_) ->
      Error(Malformed(
        "truncated qpack field section prefix (required insert count)",
      ))
    Ok(#(required_insert_count, rest)) ->
      case required_insert_count != 0 {
        True ->
          Error(Malformed(
            "nonzero required insert count: no dynamic table capacity was granted",
          ))
        False -> decode_delta_base(rest)
      }
  }
}

fn decode_delta_base(data: BitArray) -> Result(BitArray, WireError) {
  case integer.decode_integer_with_first_byte(data, 7) {
    Error(_) ->
      Error(Malformed("truncated qpack field section prefix (delta base)"))
    Ok(#(delta_base, first_byte, rest)) -> {
      let sign_bit_set = int.bitwise_and(first_byte, 0x80) != 0
      case sign_bit_set || delta_base != 0 {
        True ->
          Error(Malformed("nonzero base: no dynamic table capacity was granted"))
        False -> Ok(rest)
      }
    }
  }
}

/// Parses zero or more field lines from the remainder of the field
/// section, in order.
///
fn decode_field_lines(
  data: BitArray,
  acc: List(#(String, String)),
) -> Result(List(#(String, String)), WireError) {
  case data {
    <<>> -> Ok(list.reverse(acc))
    _ ->
      case decode_field_line(data) {
        Error(err) -> Error(err)
        Ok(#(field, rest)) -> decode_field_lines(rest, [field, ..acc])
      }
  }
}

/// Dispatches on the top bits of the next field line's first byte (RFC
/// 9204 Section 4.5).
///
fn decode_field_line(
  data: BitArray,
) -> Result(#(#(String, String), BitArray), WireError) {
  case data {
    <<first_byte:8, _:bits>> ->
      case int.bitwise_and(first_byte, 0x80) {
        0 ->
          case int.bitwise_and(first_byte, 0x40) {
            0 ->
              case int.bitwise_and(first_byte, 0x20) {
                0 ->
                  Error(Malformed(
                    "post-base field line representation requires a dynamic table",
                  ))
                _ -> decode_literal_literal_name(data)
              }
            _ -> decode_literal_name_ref(data)
          }
        _ -> decode_indexed(data)
      }
    _ -> Error(Malformed("truncated field line"))
  }
}

/// Indexed Field Line (`1Txxxxxx`, 6-bit prefix index). `T` must be 1
/// (static); this decoder never has a dynamic table.
///
fn decode_indexed(
  data: BitArray,
) -> Result(#(#(String, String), BitArray), WireError) {
  case integer.decode_integer_with_first_byte(data, 6) {
    Error(_) -> Error(Malformed("truncated indexed field line"))
    Ok(#(index, first_byte, rest)) ->
      case int.bitwise_and(first_byte, indexed_static_flag) {
        0 -> Error(Malformed("indexed field line references the dynamic table"))
        _ ->
          case qpack_static.entry(index) {
            Error(Nil) ->
              Error(Malformed("indexed field line: static index out of range"))
            Ok(pair) -> Ok(#(pair, rest))
          }
      }
  }
}

/// Literal Field Line with Name Reference (`01NTxxxx`, 4-bit prefix name
/// index). `T` must be 1 (static); the value is a string literal.
///
fn decode_literal_name_ref(
  data: BitArray,
) -> Result(#(#(String, String), BitArray), WireError) {
  case integer.decode_integer_with_first_byte(data, 4) {
    Error(_) ->
      Error(Malformed("truncated literal field line with name reference"))
    Ok(#(name_index, first_byte, rest)) ->
      case int.bitwise_and(first_byte, name_ref_static_flag) {
        0 ->
          Error(Malformed(
            "literal field line with name reference: dynamic table not supported",
          ))
        _ ->
          case qpack_static.entry(name_index) {
            Error(Nil) ->
              Error(Malformed(
                "literal field line: static name index out of range",
              ))
            Ok(#(name, _)) ->
              case decode_string_literal(rest) {
                Error(err) -> Error(err)
                Ok(#(value, rest2)) -> Ok(#(#(name, value), rest2))
              }
          }
      }
  }
}

/// Literal Field Line with Literal Name (`001NHxxx`, 3-bit prefix name
/// length). The name is Huffman-or-raw per `H`, followed by a value
/// string literal.
///
fn decode_literal_literal_name(
  data: BitArray,
) -> Result(#(#(String, String), BitArray), WireError) {
  case integer.decode_integer_with_first_byte(data, 3) {
    Error(_) ->
      Error(Malformed("truncated literal field line with literal name"))
    Ok(#(name_length, first_byte, rest)) -> {
      let name_is_huffman =
        int.bitwise_and(first_byte, literal_name_huffman_flag) != 0
      case take_bytes(rest, name_length) {
        Error(Nil) -> Error(Malformed("truncated literal name string"))
        Ok(#(name_bytes, rest2)) ->
          case decode_maybe_huffman(name_bytes, name_is_huffman) {
            Error(err) -> Error(err)
            Ok(name) ->
              case decode_string_literal(rest2) {
                Error(err) -> Error(err)
                Ok(#(value, rest3)) -> Ok(#(#(name, value), rest3))
              }
          }
      }
    }
  }
}

/// A String Literal (RFC 9204 Section 4.5, shared with HPACK RFC 7541
/// Section 5.2): an `H` flag then a 7-bit prefix length, then that many
/// bytes, Huffman-decoded if `H` is set.
///
fn decode_string_literal(
  data: BitArray,
) -> Result(#(String, BitArray), WireError) {
  case integer.decode_integer_with_first_byte(data, 7) {
    Error(_) -> Error(Malformed("truncated string literal length"))
    Ok(#(length, first_byte, rest)) -> {
      let is_huffman = int.bitwise_and(first_byte, string_huffman_flag) != 0
      case take_bytes(rest, length) {
        Error(Nil) -> Error(Malformed("truncated string literal data"))
        Ok(#(bytes, rest2)) ->
          case decode_maybe_huffman(bytes, is_huffman) {
            Error(err) -> Error(err)
            Ok(value) -> Ok(#(value, rest2))
          }
      }
    }
  }
}

fn decode_maybe_huffman(
  bytes: BitArray,
  is_huffman: Bool,
) -> Result(String, WireError) {
  case is_huffman {
    True ->
      case huffman.decode_huffman_bytes(bytes) {
        Error(_) -> Error(Malformed("huffman decode failed"))
        Ok(decoded) ->
          case bit_array.to_string(decoded) {
            Ok(value) -> Ok(value)
            Error(_) ->
              Error(Malformed("huffman-decoded field is not valid utf-8"))
          }
      }
    False ->
      case bit_array.to_string(bytes) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(Malformed("field is not valid utf-8"))
      }
  }
}

/// Splits off the first `n` bytes of `data`, or `Error(Nil)` if `data` is
/// shorter than `n` bytes.
///
fn take_bytes(data: BitArray, n: Int) -> Result(#(BitArray, BitArray), Nil) {
  let size = bit_array.byte_size(data)
  case n >= 0 && n <= size {
    False -> Error(Nil)
    True ->
      case bit_array.slice(data, 0, n), bit_array.slice(data, n, size - n) {
        Ok(head), Ok(tail) -> Ok(#(head, tail))
        _, _ -> Error(Nil)
      }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encoding
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Encodes an ordered list of `#(name, value)` pairs as a QPACK field
/// section.
///
/// Emits the `0x00 0x00` prefix (Required Insert Count 0, Base 0), then
/// for each field: an Indexed Field Line on a static full match, else a
/// Literal Field Line with a static Name Reference on a name-only match,
/// else a Literal Field Line with a Literal Name. Every string (name or
/// value) is Huffman-encoded when `should_huffman_encode` recommends it
/// and doing so is actually shorter, else emitted raw.
///
pub fn encode(fields: List(#(String, String))) -> BitArray {
  let prefix = <<0:8, 0:8>>
  bit_array.concat([prefix, encode_fields(fields)])
}

fn encode_fields(fields: List(#(String, String))) -> BitArray {
  case fields {
    [] -> <<>>
    [#(name, value), ..rest] ->
      bit_array.concat([encode_field(name, value), encode_fields(rest)])
  }
}

fn encode_field(name: String, value: String) -> BitArray {
  case qpack_static.find(name, value) {
    qpack_static.FullMatch(index) -> encode_indexed(index)
    qpack_static.NameMatch(index) -> encode_literal_name_ref(index, value)
    qpack_static.NoMatch -> encode_literal_literal_name(name, value)
  }
}

fn encode_indexed(index: Int) -> BitArray {
  integer.encode_integer_with_prefix(index, 6, indexed_prefix)
}

fn encode_literal_name_ref(index: Int, value: String) -> BitArray {
  let head =
    integer.encode_integer_with_prefix(index, 4, literal_name_ref_prefix)
  bit_array.concat([head, encode_string_literal(value)])
}

fn encode_literal_literal_name(name: String, value: String) -> BitArray {
  let #(name_bytes, name_is_huffman) = choose_encoding(name)
  let name_length = bit_array.byte_size(name_bytes)
  let prefix_value = case name_is_huffman {
    True -> literal_literal_name_prefix + literal_name_huffman_flag
    False -> literal_literal_name_prefix
  }
  let head = integer.encode_integer_with_prefix(name_length, 3, prefix_value)
  bit_array.concat([head, name_bytes, encode_string_literal(value)])
}

/// Encodes a value as a String Literal: `H` flag + 7-bit prefix length +
/// the (Huffman-or-raw) bytes.
///
fn encode_string_literal(value: String) -> BitArray {
  let #(bytes, is_huffman) = choose_encoding(value)
  let length = bit_array.byte_size(bytes)
  let prefix_value = case is_huffman {
    True -> string_huffman_flag
    False -> 0
  }
  let head = integer.encode_integer_with_prefix(length, 7, prefix_value)
  bit_array.concat([head, bytes])
}

/// Picks Huffman or raw encoding for a string, preferring Huffman only
/// when the heuristic recommends it and the Huffman encoding is actually
/// shorter than the raw bytes.
///
fn choose_encoding(value: String) -> #(BitArray, Bool) {
  let raw = bit_array.from_string(value)
  case huffman.should_huffman_encode(value) {
    False -> #(raw, False)
    True -> {
      let huffman_encoded = huffman.encode_huffman_bytes(raw)
      case bit_array.byte_size(huffman_encoded) < bit_array.byte_size(raw) {
        True -> #(huffman_encoded, True)
        False -> #(raw, False)
      }
    }
  }
}
