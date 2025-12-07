// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HPACK Integer Encoding/Decoding
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Implements variable-length integer encoding as per RFC 7541 Section 5.1.
// Integers are used in HPACK for representing header indexes, string lengths,
// and dynamic table size updates.
//
// The encoding uses an N-bit prefix (1-7 bits) followed by optional
// continuation bytes for larger values.
//

import gleam/bit_array
import gleam/int

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Errors that can occur during integer encoding/decoding
///
pub type IntegerError {
  /// Not enough data to decode the integer
  InsufficientData(needed: Int, available: Int)

  /// Integer value too large to represent safely
  Overflow(message: String)

  /// Invalid prefix bits value
  InvalidPrefixBits(bits: Int)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Maximum integer value we'll decode to prevent overflow attacks
pub const max_integer_value = 1_073_741_823

// 2^30 - 1

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Encodes an integer using HPACK variable-length encoding
///
/// The prefix_bits parameter specifies how many bits are available
/// in the first byte for the integer (1-7).
///
/// Returns the encoded bytes without the prefix mask - caller must
/// OR the first byte with their prefix bits.
///
pub fn encode_integer(value: Int, prefix_bits: Int) -> BitArray {
  let max_prefix = int.bitwise_shift_left(1, prefix_bits) - 1

  case value < max_prefix {
    True -> <<value:8>>
    False -> {
      let remaining = value - max_prefix
      let first_byte = <<max_prefix:8>>
      let extension = encode_extension(remaining, <<>>)
      bit_array.concat([first_byte, extension])
    }
  }
}

/// Encodes an integer with a specific prefix value already set
///
/// This is useful when the prefix bits contain other information
/// (like representation type flags).
///
pub fn encode_integer_with_prefix(
  value: Int,
  prefix_bits: Int,
  prefix_value: Int,
) -> BitArray {
  let max_prefix = int.bitwise_shift_left(1, prefix_bits) - 1
  let prefix_mask = int.bitwise_shift_left(0xFF, prefix_bits)
  let prefix_part = int.bitwise_and(prefix_value, prefix_mask)

  case value < max_prefix {
    True -> <<{ int.bitwise_or(prefix_part, value) }:8>>
    False -> {
      let first_byte = <<{ int.bitwise_or(prefix_part, max_prefix) }:8>>
      let remaining = value - max_prefix
      let extension = encode_extension(remaining, <<>>)
      bit_array.concat([first_byte, extension])
    }
  }
}

/// Encodes the extension bytes for values that don't fit in the prefix
///
fn encode_extension(value: Int, acc: BitArray) -> BitArray {
  case value < 128 {
    True -> bit_array.concat([acc, <<value:8>>])
    False -> {
      let byte = int.bitwise_or(int.bitwise_and(value, 0x7F), 0x80)
      let remaining = int.bitwise_shift_right(value, 7)
      encode_extension(remaining, bit_array.concat([acc, <<byte:8>>]))
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Decodes an integer from HPACK variable-length encoding
///
/// The prefix_bits parameter specifies how many bits in the first byte
/// contain the integer value (1-7).
///
/// Returns the decoded integer and remaining data.
///
pub fn decode_integer(
  data: BitArray,
  prefix_bits: Int,
) -> Result(#(Int, BitArray), IntegerError) {
  case prefix_bits < 1 || prefix_bits > 8 {
    True -> Error(InvalidPrefixBits(prefix_bits))
    False -> {
      case data {
        <<first_byte:8, rest:bits>> -> {
          let max_prefix = int.bitwise_shift_left(1, prefix_bits) - 1
          let prefix_mask = max_prefix
          let value = int.bitwise_and(first_byte, prefix_mask)

          case value < max_prefix {
            True -> Ok(#(value, rest))
            False -> decode_extension(rest, value, 0)
          }
        }
        _ -> Error(InsufficientData(1, bit_array.byte_size(data)))
      }
    }
  }
}

/// Decodes an integer and returns the first byte separately
///
/// This is useful when the first byte contains prefix information
/// that the caller needs to process.
///
pub fn decode_integer_with_first_byte(
  data: BitArray,
  prefix_bits: Int,
) -> Result(#(Int, Int, BitArray), IntegerError) {
  case prefix_bits < 1 || prefix_bits > 8 {
    True -> Error(InvalidPrefixBits(prefix_bits))
    False -> {
      case data {
        <<first_byte:8, rest:bits>> -> {
          let max_prefix = int.bitwise_shift_left(1, prefix_bits) - 1
          let prefix_mask = max_prefix
          let value = int.bitwise_and(first_byte, prefix_mask)

          case value < max_prefix {
            True -> Ok(#(value, first_byte, rest))
            False -> {
              case decode_extension(rest, value, 0) {
                Ok(#(final_value, remaining)) ->
                  Ok(#(final_value, first_byte, remaining))
                Error(e) -> Error(e)
              }
            }
          }
        }
        _ -> Error(InsufficientData(1, bit_array.byte_size(data)))
      }
    }
  }
}

/// Decodes extension bytes for multi-byte integers
///
fn decode_extension(
  data: BitArray,
  value: Int,
  shift: Int,
) -> Result(#(Int, BitArray), IntegerError) {
  case data {
    <<byte:8, rest:bits>> -> {
      let contribution = int.bitwise_and(byte, 0x7F)
      let shifted = int.bitwise_shift_left(contribution, shift)
      let new_value = value + shifted

      // Check for overflow
      case new_value > max_integer_value {
        True -> Error(Overflow("Integer value exceeds maximum"))
        False -> {
          // Check continuation bit
          case int.bitwise_and(byte, 0x80) == 0 {
            True -> Ok(#(new_value, rest))
            False -> decode_extension(rest, new_value, shift + 7)
          }
        }
      }
    }
    _ -> Error(InsufficientData(1, bit_array.byte_size(data)))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Calculates the maximum value that fits in a given prefix
///
pub fn max_prefix_value(prefix_bits: Int) -> Int {
  int.bitwise_shift_left(1, prefix_bits) - 1
}

/// Calculates how many bytes are needed to encode a value
///
pub fn encoded_length(value: Int, prefix_bits: Int) -> Int {
  let max_prefix = int.bitwise_shift_left(1, prefix_bits) - 1

  case value < max_prefix {
    True -> 1
    False -> 1 + extension_length(value - max_prefix)
  }
}

/// Calculates bytes needed for extension
///
fn extension_length(value: Int) -> Int {
  case value < 128 {
    True -> 1
    False -> 1 + extension_length(int.bitwise_shift_right(value, 7))
  }
}

/// Formats an IntegerError as a human-readable string
///
pub fn error_to_string(error: IntegerError) -> String {
  case error {
    InsufficientData(needed, available) ->
      "Insufficient data: need "
      <> int.to_string(needed)
      <> " bytes, have "
      <> int.to_string(available)
    Overflow(message) -> "Integer overflow: " <> message
    InvalidPrefixBits(bits) ->
      "Invalid prefix bits: " <> int.to_string(bits) <> " (must be 1-8)"
  }
}
