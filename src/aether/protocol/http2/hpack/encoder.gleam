// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HPACK Encoder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Implements HPACK header field compression as per RFC 7541 Section 6.
//
// Encoding Strategy:
// 1. Check if (name, value) exists in table → Indexed
// 2. Check if name exists → Literal with Incremental Indexing (new value)
// 3. Otherwise → Literal with Incremental Indexing (new name + value)
// 4. For sensitive headers → Literal Never Indexed
//

import aether/protocol/http2/hpack/integer
import aether/protocol/http2/hpack/string as hpack_string
import aether/protocol/http2/hpack/table
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Encoder state (maintains dynamic table across header blocks)
///
pub type EncoderState {
  EncoderState(dynamic_table: table.DynamicTable, huffman_encoding: Bool)
}

/// Header field (name-value pair)
///
pub type HeaderField {
  HeaderField(name: String, value: String)
}

/// Errors that can occur during encoding
///
pub type EncodeError {
  /// Table operation error
  TableError(error: table.TableError)

  /// Invalid header field
  InvalidHeader(message: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sensitive header names that should never be indexed
const sensitive_headers = [
  "authorization", "cookie", "set-cookie", "proxy-authorization",
  "proxy-authenticate",
]

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encoder State Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new encoder state
///
pub fn new_encoder(
  max_dynamic_table_size: Int,
  use_huffman: Bool,
) -> EncoderState {
  EncoderState(
    dynamic_table: table.new_dynamic_table(max_dynamic_table_size),
    huffman_encoding: use_huffman,
  )
}

/// Enables or disables Huffman encoding
///
pub fn set_huffman_encoding(state: EncoderState, enabled: Bool) -> EncoderState {
  EncoderState(..state, huffman_encoding: enabled)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Main Encoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Encodes a list of header fields
///
/// Returns the encoded header block and updated encoder state.
///
pub fn encode_headers(
  state: EncoderState,
  headers: List(HeaderField),
) -> Result(#(BitArray, EncoderState), EncodeError) {
  encode_header_fields(state, headers, <<>>)
}

/// Recursively encodes header fields
///
fn encode_header_fields(
  state: EncoderState,
  headers: List(HeaderField),
  acc: BitArray,
) -> Result(#(BitArray, EncoderState), EncodeError) {
  case headers {
    [] -> Ok(#(acc, state))
    [field, ..rest] -> {
      case encode_header_field(state, field) {
        Ok(#(encoded, new_state)) -> {
          let new_acc = bit_array.concat([acc, encoded])
          encode_header_fields(new_state, rest, new_acc)
        }
        Error(err) -> Error(err)
      }
    }
  }
}

/// Encodes a single header field using optimal strategy
///
fn encode_header_field(
  state: EncoderState,
  field: HeaderField,
) -> Result(#(BitArray, EncoderState), EncodeError) {
  // Check if this is a sensitive header
  let is_sensitive = is_sensitive_header(field.name)

  case is_sensitive {
    True -> {
      // Use literal never indexed for sensitive headers
      Ok(encode_literal_never_indexed(state, field))
    }
    False -> {
      // Try to find exact match in tables
      case
        table.find_by_name_value(state.dynamic_table, field.name, field.value)
      {
        Some(index) -> {
          // Found exact match - use indexed representation
          Ok(#(encode_indexed(index), state))
        }
        None -> {
          // No exact match - check if name exists
          case table.find_by_name_only(state.dynamic_table, field.name) {
            Some(name_index) -> {
              // Name exists - use literal with incremental indexing
              encode_literal_incremental_with_name_index(
                state,
                field,
                name_index,
              )
            }
            None -> {
              // New name - use literal with incremental indexing
              encode_literal_incremental_new_name(state, field)
            }
          }
        }
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Representation-Specific Encoders
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Encodes indexed header field (1xxxxxxx)
///
fn encode_indexed(index: Int) -> BitArray {
  integer.encode_integer_with_prefix(index, 7, 0x80)
}

/// Encodes literal with incremental indexing - indexed name (01xxxxxx)
///
fn encode_literal_incremental_with_name_index(
  state: EncoderState,
  field: HeaderField,
  name_index: Int,
) -> Result(#(BitArray, EncoderState), EncodeError) {
  // Encode name index with 6-bit prefix, 01 pattern
  let name_encoded = integer.encode_integer_with_prefix(name_index, 6, 0x40)

  // Encode value as string
  let value_encoded =
    hpack_string.encode_string(field.value, state.huffman_encoding)

  let encoded = bit_array.concat([name_encoded, value_encoded])

  // Add to dynamic table
  let new_table =
    table.insert_entry(state.dynamic_table, field.name, field.value)
  let new_state = EncoderState(..state, dynamic_table: new_table)

  Ok(#(encoded, new_state))
}

/// Encodes literal with incremental indexing - new name (01xxxxxx)
///
fn encode_literal_incremental_new_name(
  state: EncoderState,
  field: HeaderField,
) -> Result(#(BitArray, EncoderState), EncodeError) {
  // Name index 0 means literal name, with 6-bit prefix, 01 pattern
  let name_index_encoded = integer.encode_integer_with_prefix(0, 6, 0x40)

  // Encode name as string
  let name_encoded =
    hpack_string.encode_string(field.name, state.huffman_encoding)

  // Encode value as string
  let value_encoded =
    hpack_string.encode_string(field.value, state.huffman_encoding)

  let encoded =
    bit_array.concat([name_index_encoded, name_encoded, value_encoded])

  // Add to dynamic table
  let new_table =
    table.insert_entry(state.dynamic_table, field.name, field.value)
  let new_state = EncoderState(..state, dynamic_table: new_table)

  Ok(#(encoded, new_state))
}

/// Encodes literal never indexed (0001xxxx)
///
fn encode_literal_never_indexed(
  state: EncoderState,
  field: HeaderField,
) -> #(BitArray, EncoderState) {
  // Check if name exists in tables
  case table.find_by_name_only(state.dynamic_table, field.name) {
    Some(name_index) -> {
      // Name indexed, 4-bit prefix, 0001 pattern
      let name_encoded = integer.encode_integer_with_prefix(name_index, 4, 0x10)
      let value_encoded =
        hpack_string.encode_string(field.value, state.huffman_encoding)
      let encoded = bit_array.concat([name_encoded, value_encoded])
      #(encoded, state)
    }
    None -> {
      // New name, index 0, 4-bit prefix, 0001 pattern
      let name_index_encoded = integer.encode_integer_with_prefix(0, 4, 0x10)
      let name_encoded =
        hpack_string.encode_string(field.name, state.huffman_encoding)
      let value_encoded =
        hpack_string.encode_string(field.value, state.huffman_encoding)
      let encoded =
        bit_array.concat([name_index_encoded, name_encoded, value_encoded])
      #(encoded, state)
    }
  }
}

/// Encodes dynamic table size update (001xxxxx)
///
pub fn encode_table_size_update(new_size: Int) -> BitArray {
  integer.encode_integer_with_prefix(new_size, 5, 0x20)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks if a header name is sensitive (should never be indexed)
///
fn is_sensitive_header(name: String) -> Bool {
  let lowercase_name = string.lowercase(name)
  list.contains(sensitive_headers, lowercase_name)
}

/// Converts EncodeError to string
///
pub fn encode_error_to_string(error: EncodeError) -> String {
  case error {
    TableError(err) -> "Table error: " <> table.table_error_to_string(err)
    InvalidHeader(msg) -> "Invalid header: " <> msg
  }
}

/// Gets the current dynamic table from encoder state
///
pub fn get_dynamic_table(state: EncoderState) -> table.DynamicTable {
  state.dynamic_table
}

/// Updates the dynamic table in encoder state
///
pub fn set_dynamic_table(
  state: EncoderState,
  new_table: table.DynamicTable,
) -> EncoderState {
  EncoderState(..state, dynamic_table: new_table)
}

/// Updates the maximum dynamic table size
///
pub fn update_max_table_size(
  state: EncoderState,
  new_max_size: Int,
) -> EncoderState {
  let new_table = table.update_max_size(state.dynamic_table, new_max_size)
  EncoderState(..state, dynamic_table: new_table)
}
