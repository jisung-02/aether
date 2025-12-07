// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HPACK String Encoding/Decoding
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Implements HPACK string literal representation as per RFC 7541 Section 5.2.
// Strings can be encoded either as plain octets or using Huffman encoding.
//
// String Format:
// +---+---+---+---+---+---+---+---+
// | H |    String Length (7+)     |
// +---+---------------------------+
// |  String Data (Length octets)  |
// +-------------------------------+
//
// H: Huffman encoding flag (1 = Huffman encoded, 0 = plain)
//

import aether/protocol/http2/hpack/huffman
import aether/protocol/http2/hpack/integer
import gleam/bit_array
import gleam/int
import gleam/result

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Represents an HPACK encoded string
///
pub type HpackString {
  HpackString(value: String, huffman_encoded: Bool)
}

/// Errors that can occur during string encoding/decoding
///
pub type StringError {
  /// String length is invalid or exceeds limits
  InvalidLength(length: Int)

  /// Failed to decode Huffman-encoded string
  HuffmanDecodeError(message: String)

  /// Not enough data available to decode the string
  InsufficientData(needed: Int, available: Int)

  /// Invalid UTF-8 sequence in decoded string
  InvalidUtf8(message: String)

  /// Integer decoding error from the length prefix
  IntegerError(error: integer.IntegerError)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Maximum string length to prevent memory exhaustion attacks
pub const max_string_length = 1_048_576

// 1MB

/// Huffman encoding flag bit (bit 7 of first byte)
const huffman_flag = 0x80

/// Prefix bits available for string length (7 bits)
const string_length_prefix_bits = 7

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Encodes a string literal without Huffman encoding
///
/// This is the basic string encoding used when Huffman compression
/// is not applied (Phase 2A - before Huffman integration).
///
/// ## Examples
///
/// ```gleam
/// encode_string_literal("hello")
/// // Returns: <<0x05, 0x68, 0x65, 0x6c, 0x6c, 0x6f>>
/// // (length=5, "hello")
/// ```
///
pub fn encode_string_literal(value: String) -> BitArray {
  let value_bytes = bit_array.from_string(value)
  let length = bit_array.byte_size(value_bytes)

  // Encode length with 7-bit prefix (H bit = 0 for non-Huffman)
  let length_encoded =
    integer.encode_integer_with_prefix(length, string_length_prefix_bits, 0)

  bit_array.concat([length_encoded, value_bytes])
}

/// Encodes a string with optional Huffman encoding
///
/// If use_huffman is True, the string will be Huffman encoded.
///
pub fn encode_string(value: String, use_huffman: Bool) -> BitArray {
  case use_huffman {
    False -> encode_string_literal(value)
    True -> {
      // Huffman encode the string
      let huffman_encoded = huffman.encode_huffman(value)
      let length = bit_array.byte_size(huffman_encoded)

      // Encode length with H bit set (0x80)
      let length_encoded =
        integer.encode_integer_with_prefix(
          length,
          string_length_prefix_bits,
          huffman_flag,
        )

      bit_array.concat([length_encoded, huffman_encoded])
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Decodes an HPACK string literal from a BitArray
///
/// Returns the decoded HpackString and the remaining unconsumed data.
///
/// ## Examples
///
/// ```gleam
/// decode_string(<<0x05, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0xFF>>)
/// // Returns: Ok(#(HpackString("hello", False), <<0xFF>>))
/// ```
///
pub fn decode_string(
  data: BitArray,
) -> Result(#(HpackString, BitArray), StringError) {
  // First byte contains H flag and start of length
  case data {
    <<first_byte:8, rest:bits>> -> {
      // Extract Huffman flag (bit 7)
      let is_huffman = int.bitwise_and(first_byte, huffman_flag) == huffman_flag

      // Decode length integer with 7-bit prefix
      let length_data = <<first_byte:8, rest:bits>>

      case integer.decode_integer(length_data, string_length_prefix_bits) {
        Ok(#(length, remaining)) -> {
          // Validate length
          case length > max_string_length {
            True -> Error(InvalidLength(length))
            False -> {
              // Extract string data
              let string_bytes = bit_array.byte_size(remaining)

              case length <= string_bytes {
                True -> {
                  case bit_array.slice(remaining, 0, length) {
                    Ok(string_data) -> {
                      // Decode the string based on Huffman flag
                      case is_huffman {
                        False -> {
                          // Plain string decoding
                          case bit_array.to_string(string_data) {
                            Ok(value) -> {
                              let rest_data =
                                bit_array.slice(
                                  remaining,
                                  length,
                                  string_bytes - length,
                                )
                                |> result.unwrap(<<>>)

                              Ok(#(HpackString(value, False), rest_data))
                            }
                            Error(_) ->
                              Error(InvalidUtf8(
                                "Invalid UTF-8 sequence in string",
                              ))
                          }
                        }
                        True -> {
                          // Huffman-encoded string
                          case huffman.decode_huffman(string_data, length) {
                            Ok(value) -> {
                              let rest_data =
                                bit_array.slice(
                                  remaining,
                                  length,
                                  string_bytes - length,
                                )
                                |> result.unwrap(<<>>)

                              Ok(#(HpackString(value, True), rest_data))
                            }
                            Error(err) ->
                              Error(
                                HuffmanDecodeError(
                                  huffman.huffman_error_to_string(err),
                                ),
                              )
                          }
                        }
                      }
                    }
                    Error(_) ->
                      Error(InsufficientData(needed: length, available: 0))
                  }
                }
                False ->
                  Error(InsufficientData(
                    needed: length,
                    available: string_bytes,
                  ))
              }
            }
          }
        }
        Error(err) -> Error(IntegerError(err))
      }
    }
    _ -> Error(InsufficientData(needed: 1, available: 0))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a StringError to a human-readable string
///
pub fn string_error_to_string(error: StringError) -> String {
  case error {
    InvalidLength(length) ->
      "Invalid string length: "
      <> int.to_string(length)
      <> " (max: "
      <> int.to_string(max_string_length)
      <> ")"

    HuffmanDecodeError(message) -> "Huffman decode error: " <> message

    InsufficientData(needed, available) ->
      "Insufficient data: needed "
      <> int.to_string(needed)
      <> " bytes, available "
      <> int.to_string(available)

    InvalidUtf8(message) -> "Invalid UTF-8: " <> message

    IntegerError(err) ->
      "Integer decode error: " <> integer.error_to_string(err)
  }
}

/// Checks if a string should use Huffman encoding
///
/// This heuristic determines whether Huffman encoding would be beneficial.
///
pub fn should_use_huffman(value: String) -> Bool {
  huffman.should_huffman_encode(value)
}

/// Gets the encoded size of a string (for table size calculations)
///
pub fn get_encoded_size(value: String, use_huffman: Bool) -> Int {
  let encoded = encode_string(value, use_huffman)
  bit_array.byte_size(encoded)
}
