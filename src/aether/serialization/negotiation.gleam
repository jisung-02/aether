// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Content Negotiation Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides HTTP Content Negotiation based on Accept header.
// Supports media type parsing, quality value handling, and
// automatic serializer selection for response formatting.
//
// ## Features
//
// - Accept header parsing with quality values (q=)
// - Wildcard matching (*/* and type/*)
// - Serializer registry for multiple formats
// - Pipeline stage integration
// - 406 Not Acceptable handling
//
// ## Usage
//
// ```gleam
// // Create registry with serializers
// let registry = new_registry()
//   |> register_json_serializer()
//   |> register_text_serializer()
//   |> with_default("application/json")
//
// // Use in pipeline
// pipeline.new()
//   |> pipeline.pipe(http_stage.decode())
//   |> pipeline.pipe(negotiation_stage(registry))
//   // ... handler ...
//   |> pipeline.pipe(serialize_response_stage())
//   |> pipeline.pipe(http_stage.encode_response())
// ```
//

import aether/core/data.{type Data}
import aether/core/message
import aether/pipeline/error.{ProcessingError}
import aether/pipeline/stage.{type Stage}
import aether/protocol/http/response.{type HttpResponse}
import aether/protocol/http/stage as http_stage
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/float
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

/// Parsed media type from Accept header
///
/// ## Fields
///
/// - `type_`: Main type (e.g., "application", "text", "*")
/// - `subtype`: Subtype (e.g., "json", "html", "*")
/// - `parameters`: Additional parameters (e.g., charset)
/// - `quality`: Quality value from q= parameter (0.0 to 1.0, default 1.0)
///
pub type MediaType {
  MediaType(
    type_: String,
    subtype: String,
    parameters: Dict(String, String),
    quality: Float,
  )
}

/// Serializer for a specific content type
///
/// ## Fields
///
/// - `content_type`: The MIME type this serializer handles
/// - `serialize`: Function to convert Dynamic data to string
///
pub type Serializer {
  Serializer(
    content_type: String,
    serialize: fn(Dynamic) -> Result(String, String),
  )
}

/// Registry of available serializers
///
/// ## Fields
///
/// - `serializers`: Map of content type to serializer
/// - `default_type`: Optional default content type for wildcard matches
///
pub type SerializerRegistry {
  SerializerRegistry(
    serializers: Dict(String, Serializer),
    default_type: Option(String),
  )
}

/// Content negotiation errors
///
/// ## Variants
///
/// - `NotAcceptable`: No serializer matches the Accept header
/// - `NoSerializerFound`: Registry has no serializers
/// - `SerializationFailed`: Serializer returned an error
///
pub type NegotiationError {
  NotAcceptable(available: List(String))
  NoSerializerFound
  SerializationFailed(message: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Metadata key for storing selected serializer in context
pub const serializer_key = "negotiation:serializer"

/// Metadata key for storing selected content type
pub const content_type_key = "negotiation:content_type"

/// Metadata key for storing response data to serialize
pub const response_data_key = "negotiation:response_data"

/// Default content type when Accept is */* or missing
pub const default_content_type = "application/json"

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accept Header Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses an Accept header into a list of MediaTypes
///
/// The result is sorted by quality value in descending order.
///
/// ## Parameters
///
/// - `accept_header`: The Accept header value
///
/// ## Returns
///
/// List of MediaType sorted by quality (highest first)
///
/// ## Examples
///
/// ```gleam
/// parse_accept("application/json, text/html; q=0.9")
/// // [MediaType("application", "json", {}, 1.0),
/// //  MediaType("text", "html", {}, 0.9)]
/// ```
///
pub fn parse_accept(accept_header: String) -> List(MediaType) {
  accept_header
  |> string.split(",")
  |> list.filter_map(parse_media_type)
  |> list.sort(fn(a, b) {
    // Sort by quality descending (higher quality first)
    float.compare(b.quality, a.quality)
  })
}

/// Parses a single media type string
///
/// ## Parameters
///
/// - `media_type_str`: A media type like "application/json; q=0.8"
///
/// ## Returns
///
/// Result with parsed MediaType or error
///
fn parse_media_type(media_type_str: String) -> Result(MediaType, Nil) {
  let trimmed = string.trim(media_type_str)

  case string.split_once(trimmed, ";") {
    Ok(#(type_part, params_part)) -> {
      case parse_type_subtype(type_part) {
        Ok(#(type_, subtype)) -> {
          let params = parse_parameters(params_part)
          let quality = get_quality(params)

          Ok(MediaType(
            type_: type_,
            subtype: subtype,
            parameters: dict.delete(params, "q"),
            quality: quality,
          ))
        }
        Error(_) -> Error(Nil)
      }
    }
    Error(_) -> {
      // No parameters
      case parse_type_subtype(trimmed) {
        Ok(#(type_, subtype)) -> {
          Ok(MediaType(
            type_: type_,
            subtype: subtype,
            parameters: dict.new(),
            quality: 1.0,
          ))
        }
        Error(_) -> Error(Nil)
      }
    }
  }
}

/// Parses type/subtype from a string
///
fn parse_type_subtype(type_str: String) -> Result(#(String, String), Nil) {
  let trimmed = string.trim(type_str)

  case string.split_once(trimmed, "/") {
    Ok(#(type_, subtype)) -> {
      let type_trimmed = string.trim(type_)
      let subtype_trimmed = string.trim(subtype)

      case type_trimmed, subtype_trimmed {
        "", _ -> Error(Nil)
        _, "" -> Error(Nil)
        t, s -> Ok(#(t, s))
      }
    }
    Error(_) -> Error(Nil)
  }
}

/// Parses parameters from the part after the first semicolon
///
fn parse_parameters(params_str: String) -> Dict(String, String) {
  params_str
  |> string.split(";")
  |> list.filter_map(fn(param) {
    let trimmed = string.trim(param)
    case string.split_once(trimmed, "=") {
      Ok(#(key, value)) -> {
        let key_trimmed = string.trim(key) |> string.lowercase()
        let value_trimmed = string.trim(value)
        Ok(#(key_trimmed, value_trimmed))
      }
      Error(_) -> Error(Nil)
    }
  })
  |> dict.from_list()
}

/// Extracts quality value from parameters
///
/// Returns 1.0 if q parameter is not present or invalid.
///
fn get_quality(params: Dict(String, String)) -> Float {
  case dict.get(params, "q") {
    Ok(q_str) -> {
      case float.parse(q_str) {
        Ok(q) if q >=. 0.0 && q <=. 1.0 -> q
        _ -> 1.0
      }
    }
    Error(_) -> 1.0
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Content-Type Matching
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Negotiates the best content type based on Accept header
///
/// ## Parameters
///
/// - `accept_header`: The Accept header value
/// - `available`: List of available content types
///
/// ## Returns
///
/// Option with the best matching content type
///
/// ## Examples
///
/// ```gleam
/// negotiate("application/json, text/*; q=0.5", ["text/html", "application/json"])
/// // option.Some("application/json")
///
/// negotiate("application/xml", ["application/json", "text/plain"])
/// // option.None
/// ```
///
pub fn negotiate(
  accept_header: String,
  available: List(String),
) -> Option(String) {
  let requested = parse_accept(accept_header)

  // Find first matching available type by iterating through requested types
  list.find_map(requested, fn(media_type) {
    find_matching_type(media_type, available)
  })
  |> option.from_result()
}

/// Finds a matching available type for a media type
///
fn find_matching_type(
  media_type: MediaType,
  available: List(String),
) -> Result(String, Nil) {
  list.find(available, fn(content_type) {
    matches_media_type(media_type, content_type)
  })
}

/// Checks if a media type matches a content type string
///
/// Supports wildcard matching:
/// - */* matches any type
/// - type/* matches any subtype of type
/// - type/subtype matches exactly
///
pub fn matches_media_type(media_type: MediaType, content_type: String) -> Bool {
  case parse_type_subtype(content_type) {
    Ok(#(type_, subtype)) -> {
      let type_matches =
        media_type.type_ == "*" || media_type.type_ == type_
      let subtype_matches =
        media_type.subtype == "*" || media_type.subtype == subtype

      type_matches && subtype_matches
    }
    Error(_) -> False
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Serializer Registry
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new empty serializer registry
///
/// ## Returns
///
/// A new SerializerRegistry with no serializers
///
pub fn new_registry() -> SerializerRegistry {
  SerializerRegistry(serializers: dict.new(), default_type: option.None)
}

/// Registers a serializer for a content type
///
/// ## Parameters
///
/// - `registry`: The registry to add the serializer to
/// - `content_type`: The content type to register for
/// - `serializer`: The serializer to register
///
/// ## Returns
///
/// Updated registry with the new serializer
///
pub fn register(
  registry: SerializerRegistry,
  content_type: String,
  serializer: Serializer,
) -> SerializerRegistry {
  SerializerRegistry(
    ..registry,
    serializers: dict.insert(registry.serializers, content_type, serializer),
  )
}

/// Sets the default content type for the registry
///
/// This is used when Accept header is */* or missing.
///
/// ## Parameters
///
/// - `registry`: The registry to configure
/// - `content_type`: The default content type
///
/// ## Returns
///
/// Updated registry with default type set
///
pub fn with_default(
  registry: SerializerRegistry,
  content_type: String,
) -> SerializerRegistry {
  SerializerRegistry(..registry, default_type: option.Some(content_type))
}

/// Gets all available content types from the registry
///
/// ## Parameters
///
/// - `registry`: The registry to query
///
/// ## Returns
///
/// List of registered content types
///
pub fn get_available_types(registry: SerializerRegistry) -> List(String) {
  dict.keys(registry.serializers)
}

/// Selects the best serializer based on Accept header
///
/// ## Parameters
///
/// - `registry`: The serializer registry
/// - `accept_header`: The Accept header value
///
/// ## Returns
///
/// Result with tuple of (content_type, serializer) or NegotiationError
///
/// ## Examples
///
/// ```gleam
/// let registry = new_registry()
///   |> register("application/json", json_serializer)
///   |> with_default("application/json")
///
/// select_serializer(registry, "application/json")
/// // Ok(#("application/json", json_serializer))
///
/// select_serializer(registry, "application/xml")
/// // Error(NotAcceptable(["application/json"]))
/// ```
///
pub fn select_serializer(
  registry: SerializerRegistry,
  accept_header: String,
) -> Result(#(String, Serializer), NegotiationError) {
  let available = get_available_types(registry)

  case list.is_empty(available) {
    True -> Error(NoSerializerFound)
    False -> {
      // Handle empty or wildcard Accept header with default
      let effective_accept = case string.trim(accept_header) {
        "" -> "*/*"
        other -> other
      }

      case negotiate(effective_accept, available) {
        option.Some(content_type) -> {
          case dict.get(registry.serializers, content_type) {
            Ok(serializer) -> Ok(#(content_type, serializer))
            Error(_) -> Error(NotAcceptable(available))
          }
        }
        option.None -> {
          // Try default type for */* requests
          case is_wildcard_accept(effective_accept), registry.default_type {
            True, option.Some(default_ct) -> {
              case dict.get(registry.serializers, default_ct) {
                Ok(serializer) -> Ok(#(default_ct, serializer))
                Error(_) -> Error(NotAcceptable(available))
              }
            }
            _, _ -> Error(NotAcceptable(available))
          }
        }
      }
    }
  }
}

/// Checks if Accept header is a wildcard
///
fn is_wildcard_accept(accept_header: String) -> Bool {
  let parsed = parse_accept(accept_header)
  case parsed {
    [first, ..] -> first.type_ == "*" && first.subtype == "*"
    [] -> True
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Built-in Serializers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a JSON serializer
///
/// Note: This serializer expects the data to already be a JSON string
/// stored in Dynamic. For complex serialization, integrate with json.gleam.
///
pub fn json_serializer() -> Serializer {
  Serializer(content_type: "application/json", serialize: fn(data) {
    // Data should already be a string representation
    let result: String = from_dynamic(data)
    Ok(result)
  })
}

/// Creates a plain text serializer
///
pub fn text_serializer() -> Serializer {
  Serializer(content_type: "text/plain", serialize: fn(data) {
    let result: String = from_dynamic(data)
    Ok(result)
  })
}

/// Registers JSON serializer with the registry
///
pub fn register_json_serializer(
  registry: SerializerRegistry,
) -> SerializerRegistry {
  register(registry, "application/json", json_serializer())
}

/// Registers plain text serializer with the registry
///
pub fn register_text_serializer(
  registry: SerializerRegistry,
) -> SerializerRegistry {
  register(registry, "text/plain", text_serializer())
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Integration
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a content negotiation stage
///
/// This stage reads the Accept header from the request and selects
/// the appropriate serializer, storing it in the context for later use.
///
/// ## Parameters
///
/// - `registry`: The serializer registry to use
///
/// ## Returns
///
/// A Stage that performs content negotiation
///
/// ## Error Handling
///
/// Returns ProcessingError if no acceptable content type is found (406).
///
pub fn negotiation_stage(registry: SerializerRegistry) -> Stage(Data, Data) {
  stage.new("content_negotiation", fn(data: Data) {
    // Get Accept header from request
    let accept =
      http_stage.get_header(data, "accept")
      |> option.unwrap("*/*")

    // Select serializer
    case select_serializer(registry, accept) {
      Ok(#(content_type, serializer)) -> {
        // Store in context for later use
        data
        |> message.set_context_data(content_type_key, to_dynamic(content_type))
        |> message.set_context_data(serializer_key, to_dynamic(serializer))
        |> Ok
      }
      Error(NotAcceptable(available)) -> {
        Error(ProcessingError(
          "406 Not Acceptable: Available types: "
            <> string.join(available, ", "),
          option.None,
        ))
      }
      Error(NoSerializerFound) -> {
        Error(ProcessingError("No serializers registered", option.None))
      }
      Error(SerializationFailed(msg)) -> {
        Error(ProcessingError("Serialization failed: " <> msg, option.None))
      }
    }
  })
}

/// Creates a response serialization stage
///
/// This stage serializes response data using the serializer selected
/// by the negotiation stage and sets the Content-Type header.
///
/// ## Returns
///
/// A Stage that serializes response data
///
/// ## Usage
///
/// Before this stage runs, set the response data using `set_response_data()`.
///
pub fn serialize_response_stage() -> Stage(Data, Data) {
  stage.new("serialize_response", fn(data: Data) {
    // Get selected serializer from context
    case get_selected_serializer(data), get_response_data(data) {
      option.Some(serializer), option.Some(response_data) -> {
        case serializer.serialize(response_data) {
          Ok(serialized) -> {
            // Get content type from context
            let content_type =
              get_selected_content_type(data)
              |> option.unwrap(serializer.content_type)

            // Update response with serialized body and Content-Type
            case http_stage.get_http_response(data) {
              option.Some(resp) -> {
                let updated_resp =
                  resp
                  |> response.with_content_type(content_type)
                  |> response.with_string_body(serialized)

                data
                |> http_stage.set_response(http_stage.new_response_data(
                  updated_resp,
                  option.None,
                ))
                |> Ok
              }
              option.None -> {
                // Create new response
                let resp =
                  response.ok()
                  |> response.with_content_type(content_type)
                  |> response.with_string_body(serialized)

                data
                |> http_stage.set_response(http_stage.new_response_data(
                  resp,
                  option.None,
                ))
                |> Ok
              }
            }
          }
          Error(err) -> {
            Error(ProcessingError("Serialization failed: " <> err, option.None))
          }
        }
      }
      option.None, _ -> {
        Error(ProcessingError("No serializer selected", option.None))
      }
      _, option.None -> {
        // No response data to serialize, pass through
        Ok(data)
      }
    }
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the selected serializer from context
///
pub fn get_selected_serializer(data: Data) -> Option(Serializer) {
  case message.get_context_data(data, serializer_key) {
    option.Some(dyn) -> {
      let serializer: Serializer = from_dynamic(dyn)
      option.Some(serializer)
    }
    option.None -> option.None
  }
}

/// Gets the selected content type from context
///
pub fn get_selected_content_type(data: Data) -> Option(String) {
  case message.get_context_data(data, content_type_key) {
    option.Some(dyn) -> {
      let ct: String = from_dynamic(dyn)
      option.Some(ct)
    }
    option.None -> option.None
  }
}

/// Sets the response data to be serialized
///
/// ## Parameters
///
/// - `data`: The Data to store response data in
/// - `response_data`: The data to serialize (as Dynamic)
///
/// ## Returns
///
/// Updated Data with response data stored
///
pub fn set_response_data(data: Data, response_data: Dynamic) -> Data {
  message.set_context_data(data, response_data_key, response_data)
}

/// Sets the response data from a string
///
pub fn set_string_response(data: Data, response_str: String) -> Data {
  set_response_data(data, to_dynamic(response_str))
}

/// Gets the response data to be serialized
///
pub fn get_response_data(data: Data) -> Option(Dynamic) {
  message.get_context_data(data, response_data_key)
}

/// Checks if content negotiation has been performed
///
pub fn has_negotiation(data: Data) -> Bool {
  message.has_context_data(data, serializer_key)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Response Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a 406 Not Acceptable response
///
/// ## Parameters
///
/// - `available`: List of available content types
///
/// ## Returns
///
/// An HttpResponse with 406 status
///
pub fn not_acceptable_response(available: List(String)) -> HttpResponse {
  response.new(406)
  |> response.with_content_type("text/plain")
  |> response.with_string_body(
    "Not Acceptable. Available types: " <> string.join(available, ", "),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a NegotiationError to a human-readable string
///
pub fn error_to_string(error: NegotiationError) -> String {
  case error {
    NotAcceptable(available) ->
      "Not Acceptable. Available: " <> string.join(available, ", ")
    NoSerializerFound -> "No serializers registered in registry"
    SerializationFailed(msg) -> "Serialization failed: " <> msg
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MediaType Utilities
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a MediaType to a string
///
pub fn media_type_to_string(media_type: MediaType) -> String {
  media_type.type_ <> "/" <> media_type.subtype
}

/// Creates a MediaType from type and subtype strings
///
pub fn new_media_type(type_: String, subtype: String) -> MediaType {
  MediaType(type_: type_, subtype: subtype, parameters: dict.new(), quality: 1.0)
}

/// Creates a MediaType with a quality value
///
pub fn new_media_type_with_quality(
  type_: String,
  subtype: String,
  quality: Float,
) -> MediaType {
  MediaType(
    type_: type_,
    subtype: subtype,
    parameters: dict.new(),
    quality: quality,
  )
}
