// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HPACK Decoder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Implements HPACK header field decompression as per RFC 7541 Section 6.
//
// Header Field Representations:
// 1. Indexed Header Field (1xxxxxxx)
// 2. Literal with Incremental Indexing (01xxxxxx)
// 3. Literal without Indexing (0000xxxx)
// 4. Literal Never Indexed (0001xxxx)
// 5. Dynamic Table Size Update (001xxxxx)
//

import aether/protocol/http2/hpack/integer
import aether/protocol/http2/hpack/string as hpack_string
import aether/protocol/http2/hpack/table
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Decoder state (maintains dynamic table across header blocks)
///
pub type DecoderState {
  DecoderState(dynamic_table: table.DynamicTable, max_header_list_size: Int)
}

/// Header field (name-value pair)
///
pub type HeaderField {
  HeaderField(name: String, value: String)
}

/// Errors that can occur during decoding
///
pub type DecodeError {
  /// Integer decoding error
  IntegerError(error: integer.IntegerError)

  /// String decoding error
  StringError(error: hpack_string.StringError)

  /// Table error
  TableError(error: table.TableError)

  /// Invalid header representation
  InvalidRepresentation(message: String)

  /// Header list size exceeded
  HeaderListSizeExceeded(current: Int, max: Int)

  /// Not enough data to decode
  InsufficientData(message: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Default maximum header list size (unlimited)
pub const default_max_header_list_size = 0

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decoder State Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new decoder state
///
pub fn new_decoder(max_dynamic_table_size: Int) -> DecoderState {
  DecoderState(
    dynamic_table: table.new_dynamic_table(max_dynamic_table_size),
    max_header_list_size: default_max_header_list_size,
  )
}

/// Updates the maximum header list size
///
pub fn set_max_header_list_size(
  state: DecoderState,
  max_size: Int,
) -> DecoderState {
  DecoderState(..state, max_header_list_size: max_size)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Main Decoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Decodes a complete header block
///
/// Returns the decoded header fields and updated decoder state.
///
pub fn decode_header_block(
  state: DecoderState,
  block: BitArray,
) -> Result(#(List(HeaderField), DecoderState), DecodeError) {
  decode_header_fields(state, block, [])
}

/// Recursively decodes header field representations
///
fn decode_header_fields(
  state: DecoderState,
  data: BitArray,
  acc: List(HeaderField),
) -> Result(#(List(HeaderField), DecoderState), DecodeError) {
  case bit_array.byte_size(data) {
    0 -> {
      // No more data - return accumulated headers
      Ok(#(list.reverse(acc), state))
    }
    _ -> {
      // Decode next header field representation
      case decode_header_field(state, data) {
        Ok(#(Some(field), new_state, remaining)) -> {
          // Check header list size if limit is set
          case state.max_header_list_size > 0 {
            True -> {
              let current_size = calculate_header_list_size([field, ..acc])
              case current_size > state.max_header_list_size {
                True ->
                  Error(HeaderListSizeExceeded(
                    current_size,
                    state.max_header_list_size,
                  ))
                False ->
                  decode_header_fields(new_state, remaining, [field, ..acc])
              }
            }
            False -> decode_header_fields(new_state, remaining, [field, ..acc])
          }
        }
        Ok(#(None, new_state, remaining)) -> {
          // Table size update (no field emitted)
          decode_header_fields(new_state, remaining, acc)
        }
        Error(err) -> Error(err)
      }
    }
  }
}

/// Decodes a single header field representation
///
/// Returns optional header field, updated state, and remaining data.
///
fn decode_header_field(
  state: DecoderState,
  data: BitArray,
) -> Result(#(option.Option(HeaderField), DecoderState, BitArray), DecodeError) {
  case data {
    <<first_byte:8, _rest:bits>> -> {
      // Determine representation type from first byte pattern
      // Check bit patterns in order of specificity
      let indexed = int.bitwise_and(first_byte, 0x80) == 0x80
      let literal_incr = int.bitwise_and(first_byte, 0xC0) == 0x40
      let table_size = int.bitwise_and(first_byte, 0xE0) == 0x20
      let never_indexed = int.bitwise_and(first_byte, 0xF0) == 0x10
      let no_index = int.bitwise_and(first_byte, 0xF0) == 0x00

      case indexed, literal_incr, table_size, never_indexed, no_index {
        True, _, _, _, _ -> decode_indexed(state, data)
        False, True, _, _, _ -> decode_literal_incremental(state, data)
        False, False, True, _, _ -> decode_table_size_update(state, data)
        False, False, False, True, _ ->
          decode_literal_never_indexed(state, data)
        False, False, False, False, True -> decode_literal_no_index(state, data)
        _, _, _, _, _ ->
          Error(InvalidRepresentation(
            "Unknown header field representation: " <> int.to_string(first_byte),
          ))
      }
    }
    _ -> Error(InsufficientData("Empty header block"))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Representation-Specific Decoders
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Decodes indexed header field (1xxxxxxx)
///
fn decode_indexed(
  state: DecoderState,
  data: BitArray,
) -> Result(#(option.Option(HeaderField), DecoderState, BitArray), DecodeError) {
  // Decode index with 7-bit prefix
  case integer.decode_integer(data, 7) {
    Ok(#(index, remaining)) -> {
      case index {
        0 ->
          Error(InvalidRepresentation("Index 0 is not valid for indexed header"))
        _ -> {
          // Look up in table
          case table.get_entry(state.dynamic_table, index) {
            Ok(#(name, value)) -> {
              let field = HeaderField(name, value)
              Ok(#(Some(field), state, remaining))
            }
            Error(err) -> Error(TableError(err))
          }
        }
      }
    }
    Error(err) -> Error(IntegerError(err))
  }
}

/// Decodes literal with incremental indexing (01xxxxxx)
///
fn decode_literal_incremental(
  state: DecoderState,
  data: BitArray,
) -> Result(#(option.Option(HeaderField), DecoderState, BitArray), DecodeError) {
  // Decode name (either indexed or literal)
  decode_literal_common(state, data, 6, True)
}

/// Decodes literal without indexing (0000xxxx)
///
fn decode_literal_no_index(
  state: DecoderState,
  data: BitArray,
) -> Result(#(option.Option(HeaderField), DecoderState, BitArray), DecodeError) {
  decode_literal_common(state, data, 4, False)
}

/// Decodes literal never indexed (0001xxxx)
///
fn decode_literal_never_indexed(
  state: DecoderState,
  data: BitArray,
) -> Result(#(option.Option(HeaderField), DecoderState, BitArray), DecodeError) {
  // Same as literal without indexing, but signals sensitive data
  decode_literal_common(state, data, 4, False)
}

/// Common logic for literal header field representations
///
fn decode_literal_common(
  state: DecoderState,
  data: BitArray,
  prefix_bits: Int,
  add_to_table: Bool,
) -> Result(#(option.Option(HeaderField), DecoderState, BitArray), DecodeError) {
  // Decode name index
  case integer.decode_integer(data, prefix_bits) {
    Ok(#(name_index, remaining1)) -> {
      case name_index {
        0 -> {
          // Name is literal string
          case hpack_string.decode_string(remaining1) {
            Ok(#(name_str, remaining2)) -> {
              // Decode value as literal string
              case hpack_string.decode_string(remaining2) {
                Ok(#(value_str, remaining3)) -> {
                  let field = HeaderField(name_str.value, value_str.value)

                  // Add to table if incremental indexing
                  case add_to_table {
                    True -> {
                      let new_table =
                        table.insert_entry(
                          state.dynamic_table,
                          name_str.value,
                          value_str.value,
                        )
                      let new_state =
                        DecoderState(..state, dynamic_table: new_table)
                      Ok(#(Some(field), new_state, remaining3))
                    }
                    False -> Ok(#(Some(field), state, remaining3))
                  }
                }
                Error(err) -> Error(StringError(err))
              }
            }
            Error(err) -> Error(StringError(err))
          }
        }
        _ -> {
          // Name is indexed from table
          case table.get_entry(state.dynamic_table, name_index) {
            Ok(#(name, _)) -> {
              // Decode value as literal string
              case hpack_string.decode_string(remaining1) {
                Ok(#(value_str, remaining2)) -> {
                  let field = HeaderField(name, value_str.value)

                  // Add to table if incremental indexing
                  case add_to_table {
                    True -> {
                      let new_table =
                        table.insert_entry(
                          state.dynamic_table,
                          name,
                          value_str.value,
                        )
                      let new_state =
                        DecoderState(..state, dynamic_table: new_table)
                      Ok(#(Some(field), new_state, remaining2))
                    }
                    False -> Ok(#(Some(field), state, remaining2))
                  }
                }
                Error(err) -> Error(StringError(err))
              }
            }
            Error(err) -> Error(TableError(err))
          }
        }
      }
    }
    Error(err) -> Error(IntegerError(err))
  }
}

/// Decodes dynamic table size update (001xxxxx)
///
fn decode_table_size_update(
  state: DecoderState,
  data: BitArray,
) -> Result(#(option.Option(HeaderField), DecoderState, BitArray), DecodeError) {
  // Decode new size with 5-bit prefix
  case integer.decode_integer(data, 5) {
    Ok(#(new_size, remaining)) -> {
      // Update dynamic table max size
      let new_table = table.update_max_size(state.dynamic_table, new_size)
      let new_state = DecoderState(..state, dynamic_table: new_table)

      // No header field emitted for table size update
      Ok(#(None, new_state, remaining))
    }
    Error(err) -> Error(IntegerError(err))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Calculates the size of a header list (RFC 7541 Section 4.1)
///
fn calculate_header_list_size(headers: List(HeaderField)) -> Int {
  list.fold(headers, 0, fn(acc, field) {
    acc + table.calculate_entry_size(field.name, field.value)
  })
}

/// Converts DecodeError to string
///
pub fn decode_error_to_string(error: DecodeError) -> String {
  case error {
    IntegerError(err) -> "Integer error: " <> integer.error_to_string(err)
    StringError(err) ->
      "String error: " <> hpack_string.string_error_to_string(err)
    TableError(err) -> "Table error: " <> table.table_error_to_string(err)
    InvalidRepresentation(msg) -> "Invalid representation: " <> msg
    HeaderListSizeExceeded(current, max) ->
      "Header list size exceeded: "
      <> int.to_string(current)
      <> " > "
      <> int.to_string(max)
    InsufficientData(msg) -> "Insufficient data: " <> msg
  }
}

/// Gets the current dynamic table from decoder state
///
pub fn get_dynamic_table(state: DecoderState) -> table.DynamicTable {
  state.dynamic_table
}

/// Updates the dynamic table in decoder state
///
pub fn set_dynamic_table(
  state: DecoderState,
  new_table: table.DynamicTable,
) -> DecoderState {
  DecoderState(..state, dynamic_table: new_table)
}
