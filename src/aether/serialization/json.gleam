// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// JSON Serialization Stage Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides JSON decoder and encoder stages for pipeline integration.
// Supports type-safe JSON parsing and encoding with gleam_json.
//
// ## Features
//
// - JSON decode stage (bytes -> metadata)
// - JSON encode stage (metadata -> bytes)
// - Type-safe decoding with gleam/dynamic/decode
// - Content-Type auto-setting
// - Configurable encoding options
//
// ## Usage
//
// ```gleam
// // Pipeline integration
// pipeline.new()
//   |> pipeline.pipe(http_stage.decode())
//   |> pipeline.pipe(json.decode())
//   // ... business logic ...
//   |> pipeline.pipe(json.encode())
//   |> pipeline.pipe(http_stage.encode_response())
//
// // Type-safe decoding in handler
// case json.decode_as(data, user_decoder) {
//   Ok(user) -> // handle user
//   Error(err) -> // return error response
// }
// ```
//

import aether/core/data.{type Data}
import aether/core/message
import aether/pipeline/error.{ProcessingError}
import aether/pipeline/stage.{type Stage}
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// FFI for Type Coercion
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Coerces any value to Dynamic (safe on BEAM as types are erased at runtime)
@external(erlang, "erlang", "hd")
fn coerce_via_hd(list: List(a)) -> b

fn to_dynamic(value: a) -> Dynamic {
  coerce_via_hd([value])
}

fn from_dynamic(value: Dynamic) -> a {
  coerce_via_hd([value])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Configuration for JSON encoding
///
/// ## Fields
///
/// - `set_content_type`: Whether to set Content-Type header automatically
/// - `content_type`: Content-Type value to use
///
pub type JsonConfig {
  JsonConfig(set_content_type: Bool, content_type: String)
}

/// JSON-related errors
///
/// ## Variants
///
/// - `ParseError`: Error when parsing JSON from bytes
/// - `EncodeError`: Error when encoding to JSON
/// - `InvalidContentType`: Error when Content-Type is not JSON
/// - `DecodeError`: Error when decoding JSON to a specific type
///
pub type JsonError {
  ParseError(message: String)
  EncodeError(message: String)
  InvalidContentType(expected: String, actual: String)
  DecodeError(message: String)
}

/// Container for parsed JSON stored in metadata
///
/// ## Fields
///
/// - `value`: The raw JSON value as Dynamic
/// - `raw_string`: Original string representation
///
pub type JsonData {
  JsonData(value: Dynamic, raw_string: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Metadata key for storing parsed JSON in Data
pub const metadata_key = "json:parsed"

/// Metadata key for JSON to encode (output)
pub const encode_metadata_key = "json:encode"

/// Default Content-Type for JSON responses
pub const default_content_type = "application/json; charset=utf-8"

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Configuration Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates default JSON configuration
///
/// ## Returns
///
/// JsonConfig with Content-Type auto-setting enabled
///
pub fn default_config() -> JsonConfig {
  JsonConfig(set_content_type: True, content_type: default_content_type)
}

/// Creates configuration without Content-Type auto-setting
///
pub fn config_no_content_type() -> JsonConfig {
  JsonConfig(set_content_type: False, content_type: default_content_type)
}

/// Creates configuration with custom Content-Type
///
/// ## Parameters
///
/// - `content_type`: The Content-Type value to use
///
pub fn config_with_content_type(content_type: String) -> JsonConfig {
  JsonConfig(set_content_type: True, content_type: content_type)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a JSON decoder stage
///
/// This stage parses JSON from the request body (Data.bytes) and stores
/// the parsed JSON in metadata under the key "json:parsed".
///
/// The Data's bytes remain unchanged (original JSON bytes).
///
/// ## Returns
///
/// A Stage that parses JSON from body bytes and stores in metadata.
///
/// ## Error Handling
///
/// Returns ProcessingError if:
/// - The body bytes are not valid UTF-8
/// - The body is not valid JSON
///
/// ## Examples
///
/// ```gleam
/// let decoder = decode()
/// let json_bytes = <<"{\"name\": \"Alice\"}":utf8>>
/// let input_data = message.new(json_bytes)
///
/// case stage.execute(decoder, input_data) {
///   Ok(decoded) -> {
///     // JSON is stored in metadata["json:parsed"]
///     case get_json(decoded) {
///       Some(json_data) -> // use json_data.value
///       None -> // shouldn't happen after successful decode
///     }
///   }
///   Error(err) -> // handle parse error
/// }
/// ```
///
pub fn decode() -> Stage(Data, Data) {
  stage.new("json:decode", fn(data: Data) {
    let body_bytes = message.bytes(data)

    case bit_array.to_string(body_bytes) {
      Ok(body_string) -> {
        // Use decode.dynamic to parse any JSON value
        case json.parse(from: body_string, using: decode.dynamic) {
          Ok(parsed) -> {
            let json_data = JsonData(value: parsed, raw_string: body_string)
            data
            |> message.set_metadata(metadata_key, to_dynamic(json_data))
            |> Ok
          }
          Error(json_error) -> {
            Error(ProcessingError(
              "JSON parse error: " <> json_decode_error_to_string(json_error),
              option.None,
            ))
          }
        }
      }
      Error(_) -> {
        Error(ProcessingError("Invalid UTF-8 in request body", option.None))
      }
    }
  })
}

/// Creates a JSON encoder stage
///
/// This stage encodes a json.Json value stored in metadata to the Data's bytes.
/// The json.Json value should be set using `set_json_for_encode()`.
///
/// ## Returns
///
/// A Stage that encodes JSON from metadata to body bytes.
///
/// ## Error Handling
///
/// Returns ProcessingError if no JSON value is in metadata under "json:encode".
///
/// ## Examples
///
/// ```gleam
/// let encoder = encode()
/// let json_value = json.object([#("status", json.string("ok"))])
/// let input_data = message.new(<<>>)
///   |> set_json_for_encode(json_value)
///
/// case stage.execute(encoder, input_data) {
///   Ok(encoded) -> {
///     // encoded.bytes contains: {"status":"ok"}
///   }
///   Error(err) -> // handle error
/// }
/// ```
///
pub fn encode() -> Stage(Data, Data) {
  encode_with_config(default_config())
}

/// Creates a JSON encoder stage with custom configuration
///
/// ## Parameters
///
/// - `config`: JsonConfig for encoding options
///
pub fn encode_with_config(config: JsonConfig) -> Stage(Data, Data) {
  stage.new("json:encode", fn(data: Data) {
    case get_json_for_encode(data) {
      option.Some(json_value) -> {
        let json_string = json.to_string(json_value)
        let json_bytes = bit_array.from_string(json_string)

        let updated_data =
          data
          |> message.set_bytes(json_bytes)

        // Set Content-Type in metadata if configured
        case config.set_content_type {
          True ->
            updated_data
            |> message.set_metadata(
              "content-type",
              to_dynamic(config.content_type),
            )
            |> Ok
          False -> Ok(updated_data)
        }
      }
      option.None -> {
        Error(ProcessingError(
          "No JSON value in metadata for encoding",
          option.None,
        ))
      }
    }
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions - JSON Data Access
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the parsed JsonData from Data metadata if present
///
/// ## Parameters
///
/// - `data`: The Data to get JSON from
///
/// ## Returns
///
/// Option containing the JsonData if present
///
pub fn get_json(data: Data) -> Option(JsonData) {
  case message.get_metadata(data, metadata_key) {
    option.Some(json_dynamic) -> {
      let json_data: JsonData = from_dynamic(json_dynamic)
      option.Some(json_data)
    }
    option.None -> option.None
  }
}

/// Sets a JsonData in Data metadata
///
/// ## Parameters
///
/// - `data`: The Data to set JSON in
/// - `json_data`: The JsonData to store
///
/// ## Returns
///
/// The updated Data with JSON in metadata
///
pub fn set_json(data: Data, json_data: JsonData) -> Data {
  message.set_metadata(data, metadata_key, to_dynamic(json_data))
}

/// Gets the parsed Dynamic value from Data metadata if present
///
/// This is a convenience function that extracts just the Dynamic value
/// from the JsonData.
///
/// ## Parameters
///
/// - `data`: The Data to get JSON value from
///
/// ## Returns
///
/// Option containing the Dynamic value if present
///
pub fn get_json_value(data: Data) -> Option(Dynamic) {
  case get_json(data) {
    option.Some(json_data) -> option.Some(json_data.value)
    option.None -> option.None
  }
}

/// Gets the raw JSON string from Data metadata if present
///
/// ## Parameters
///
/// - `data`: The Data to get raw JSON string from
///
/// ## Returns
///
/// Option containing the raw string if present
///
pub fn get_raw_json_string(data: Data) -> Option(String) {
  case get_json(data) {
    option.Some(json_data) -> option.Some(json_data.raw_string)
    option.None -> option.None
  }
}

/// Gets the json.Json value for encoding from Data metadata
///
/// ## Parameters
///
/// - `data`: The Data to get JSON for encoding from
///
/// ## Returns
///
/// Option containing the json.Json value if present
///
pub fn get_json_for_encode(data: Data) -> Option(json.Json) {
  case message.get_metadata(data, encode_metadata_key) {
    option.Some(json_dynamic) -> {
      let json_value: json.Json = from_dynamic(json_dynamic)
      option.Some(json_value)
    }
    option.None -> option.None
  }
}

/// Sets a json.Json value in Data metadata for encoding
///
/// ## Parameters
///
/// - `data`: The Data to set JSON in
/// - `json_value`: The json.Json value to encode
///
/// ## Returns
///
/// The updated Data with JSON value ready for encoding
///
pub fn set_json_for_encode(data: Data, json_value: json.Json) -> Data {
  message.set_metadata(data, encode_metadata_key, to_dynamic(json_value))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Type-Safe Decoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Decodes the parsed JSON to a specific type using a decoder
///
/// ## Parameters
///
/// - `data`: The Data containing parsed JSON
/// - `decoder`: A gleam/dynamic/decode Decoder
///
/// ## Returns
///
/// Result with the decoded value or a JsonError
///
/// ## Examples
///
/// ```gleam
/// // Define a decoder using gleam/dynamic/decode
/// let user_decoder = {
///   use name <- decode.field("name", decode.string)
///   use age <- decode.field("age", decode.int)
///   decode.success(User(name:, age:))
/// }
///
/// case decode_as(data, user_decoder) {
///   Ok(user) -> // use user
///   Error(err) -> // handle decode error
/// }
/// ```
///
pub fn decode_as(
  data: Data,
  decoder: decode.Decoder(a),
) -> Result(a, JsonError) {
  case get_json(data) {
    option.Some(json_data) -> {
      case decode.run(json_data.value, decoder) {
        Ok(value) -> Ok(value)
        Error(errors) -> {
          let error_msg = decode_errors_to_string(errors)
          Error(DecodeError(error_msg))
        }
      }
    }
    option.None -> {
      Error(DecodeError("No JSON data in metadata"))
    }
  }
}

/// Decodes JSON from raw string to a specific type
///
/// This is a convenience function that parses and decodes in one step.
///
/// ## Parameters
///
/// - `json_string`: The JSON string to parse and decode
/// - `decoder`: A gleam/dynamic/decode Decoder
///
/// ## Returns
///
/// Result with the decoded value or a JsonError
///
pub fn decode_string_as(
  json_string: String,
  decoder: decode.Decoder(a),
) -> Result(a, JsonError) {
  case json.parse(from: json_string, using: decoder) {
    Ok(value) -> Ok(value)
    Error(json_error) -> {
      Error(ParseError(json_decode_error_to_string(json_error)))
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Content-Type Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks if the Content-Type metadata indicates JSON
///
/// ## Parameters
///
/// - `data`: The Data to check
///
/// ## Returns
///
/// True if Content-Type contains "application/json"
///
pub fn is_json_content_type(data: Data) -> Bool {
  case message.get_metadata(data, "content-type") {
    option.Some(ct_dynamic) -> {
      let content_type: String = from_dynamic(ct_dynamic)
      string.contains(string.lowercase(content_type), "application/json")
    }
    option.None -> False
  }
}

/// Validates that Content-Type is JSON, returning error if not
///
/// ## Parameters
///
/// - `data`: The Data to validate
///
/// ## Returns
///
/// Ok(data) if Content-Type is JSON, Error otherwise
///
pub fn require_json_content_type(data: Data) -> Result(Data, JsonError) {
  case message.get_metadata(data, "content-type") {
    option.Some(ct_dynamic) -> {
      let content_type: String = from_dynamic(ct_dynamic)
      case string.contains(string.lowercase(content_type), "application/json") {
        True -> Ok(data)
        False ->
          Error(InvalidContentType(
            expected: "application/json",
            actual: content_type,
          ))
      }
    }
    option.None ->
      Error(InvalidContentType(expected: "application/json", actual: "(not set)"))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a JsonError to a human-readable string
///
/// ## Parameters
///
/// - `error`: The JsonError to format
///
/// ## Returns
///
/// A string description of the error
///
pub fn error_to_string(error: JsonError) -> String {
  case error {
    ParseError(msg) -> "JSON Parse Error: " <> msg
    EncodeError(msg) -> "JSON Encode Error: " <> msg
    InvalidContentType(expected, actual) ->
      "Invalid Content-Type: expected " <> expected <> ", got " <> actual
    DecodeError(msg) -> "JSON Decode Error: " <> msg
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Internal Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts JSON decode error to string
fn json_decode_error_to_string(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "Unexpected end of input"
    json.UnexpectedByte(byte) -> "Unexpected byte: " <> byte
    json.UnexpectedSequence(seq) -> "Unexpected sequence: " <> seq
    json.UnableToDecode(errs) ->
      "Unable to decode: " <> decode_errors_to_string(errs)
  }
}

/// Converts decode errors list to string
fn decode_errors_to_string(errors: List(decode.DecodeError)) -> String {
  errors
  |> list.map(fn(err: decode.DecodeError) {
    "Expected " <> err.expected <> " at " <> string.join(err.path, ".")
  })
  |> string.join(", ")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Convenience Functions for Handlers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a JsonData from a Dynamic value
///
/// ## Parameters
///
/// - `value`: The Dynamic value
/// - `raw_string`: The original JSON string (optional, empty if not available)
///
pub fn new_json_data(value: Dynamic, raw_string: String) -> JsonData {
  JsonData(value: value, raw_string: raw_string)
}

/// Checks if Data has parsed JSON in metadata
///
/// ## Parameters
///
/// - `data`: The Data to check
///
/// ## Returns
///
/// True if JSON data is present in metadata
///
pub fn has_json(data: Data) -> Bool {
  message.has_metadata(data, metadata_key)
}

/// Checks if Data has JSON value ready for encoding
///
/// ## Parameters
///
/// - `data`: The Data to check
///
/// ## Returns
///
/// True if JSON value is present for encoding
///
pub fn has_json_for_encode(data: Data) -> Bool {
  message.has_metadata(data, encode_metadata_key)
}
