// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol Pipeline Builder Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/core/data.{type Data}
import aether/pipeline/pipeline.{type Pipeline}
import aether/pipeline/stage.{type Stage}
import aether/protocol/protocol.{type Protocol}
import aether/protocol/registry.{type Registry}
import aether/protocol/validator.{type ValidationError}
import gleam/list
import gleam/option

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Direction for building the pipeline
///
pub type Direction {
  /// Build a decoder pipeline (processes incoming data)
  Decode
  /// Build an encoder pipeline (processes outgoing data, reverse order)
  Encode
}

/// Errors that can occur when building a pipeline
///
pub type BuildError {
  /// Validation failed for the protocol pipeline
  ValidationFailed(errors: List(ValidationError))
  /// A protocol is missing its decoder stage
  MissingDecoder(protocol: String)
  /// A protocol is missing its encoder stage
  MissingEncoder(protocol: String)
  /// No protocols specified
  EmptyProtocolList
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Building Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds a decoder pipeline from a list of protocol names
///
/// The pipeline will decode data through each protocol in the specified order.
/// For example, for ["tcp", "tls", "http"], data flows:
/// TCP decode -> TLS decode -> HTTP decode
///
/// ## Parameters
///
/// - `reg`: The registry containing protocol definitions
/// - `protocol_names`: List of protocol names in processing order
///
/// ## Returns
///
/// Result containing the Pipeline or a BuildError
///
/// ## Examples
///
/// ```gleam
/// case build_decoder_pipeline(registry, ["tcp", "tls", "http"]) {
///   Ok(pipeline) -> pipeline.execute(pipeline, data)
///   Error(ValidationFailed(errors)) -> // handle validation errors
///   Error(MissingDecoder(name)) -> // protocol lacks decoder
/// }
/// ```
///
pub fn build_decoder_pipeline(
  reg: Registry,
  protocol_names: List(String),
) -> Result(Pipeline(Data, Data), BuildError) {
  build_pipeline(reg, protocol_names, Decode)
}

/// Builds an encoder pipeline from a list of protocol names
///
/// The pipeline will encode data through each protocol in reverse order.
/// For example, for ["tcp", "tls", "http"], data flows:
/// HTTP encode -> TLS encode -> TCP encode
///
/// ## Parameters
///
/// - `reg`: The registry containing protocol definitions
/// - `protocol_names`: List of protocol names (will be reversed for encoding)
///
/// ## Returns
///
/// Result containing the Pipeline or a BuildError
///
pub fn build_encoder_pipeline(
  reg: Registry,
  protocol_names: List(String),
) -> Result(Pipeline(Data, Data), BuildError) {
  build_pipeline(reg, protocol_names, Encode)
}

/// Builds a pipeline from protocols with specified direction
///
/// ## Parameters
///
/// - `reg`: The registry containing protocol definitions
/// - `protocol_names`: List of protocol names
/// - `direction`: Whether to build decoder or encoder pipeline
///
/// ## Returns
///
/// Result containing the Pipeline or a BuildError
///
pub fn build_pipeline(
  reg: Registry,
  protocol_names: List(String),
  direction: Direction,
) -> Result(Pipeline(Data, Data), BuildError) {
  // Check for empty list
  case protocol_names {
    [] -> Error(EmptyProtocolList)
    _ -> {
      // Validate the protocol order first
      case validator.validate_pipeline(reg, protocol_names) {
        Error(validation_errors) -> Error(ValidationFailed(validation_errors))
        Ok(_) -> {
          // Get protocols in the correct order
          let protocols = registry.get_many(reg, protocol_names)

          // For encoding, reverse the protocol order
          let ordered_protocols = case direction {
            Decode -> protocols
            Encode -> list.reverse(protocols)
          }

          // Extract stages
          extract_and_build_pipeline(ordered_protocols, direction)
        }
      }
    }
  }
}

/// Builds a pipeline that combines decoding and encoding
///
/// Creates a pipeline that first decodes through all protocols (in order),
/// then encodes through all protocols (in reverse order).
///
/// ## Parameters
///
/// - `reg`: The registry containing protocol definitions
/// - `protocol_names`: List of protocol names
///
/// ## Returns
///
/// Result containing the combined Pipeline or a BuildError
///
pub fn build_roundtrip_pipeline(
  reg: Registry,
  protocol_names: List(String),
) -> Result(Pipeline(Data, Data), BuildError) {
  // First build decoder pipeline
  case build_decoder_pipeline(reg, protocol_names) {
    Error(err) -> Error(err)
    Ok(decode_pipeline) -> {
      // Then build encoder pipeline
      case build_encoder_pipeline(reg, protocol_names) {
        Error(err) -> Error(err)
        Ok(encode_pipeline) -> {
          // Combine them
          Ok(pipeline.append(decode_pipeline, encode_pipeline))
        }
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Extracts stages from protocols and builds the pipeline
///
fn extract_and_build_pipeline(
  protocols: List(Protocol),
  direction: Direction,
) -> Result(Pipeline(Data, Data), BuildError) {
  // Extract stages based on direction
  let stage_results = case direction {
    Decode -> extract_decoder_stages(protocols)
    Encode -> extract_encoder_stages(protocols)
  }

  case stage_results {
    Error(err) -> Error(err)
    Ok(stages) -> {
      // Build the pipeline from stages
      case stages {
        [] -> Error(EmptyProtocolList)
        [first, ..rest] -> {
          let initial_pipeline = pipeline.from_stage(first)
          let final_pipeline =
            list.fold(rest, initial_pipeline, fn(pipe, stg) {
              pipeline.pipe(pipe, stg)
            })
          Ok(final_pipeline)
        }
      }
    }
  }
}

/// Extracts decoder stages from a list of protocols
///
fn extract_decoder_stages(
  protocols: List(Protocol),
) -> Result(List(Stage(Data, Data)), BuildError) {
  extract_stages(protocols, protocol.get_decoder, MissingDecoder)
}

/// Extracts encoder stages from a list of protocols
///
fn extract_encoder_stages(
  protocols: List(Protocol),
) -> Result(List(Stage(Data, Data)), BuildError) {
  extract_stages(protocols, protocol.get_encoder, MissingEncoder)
}

/// Generic stage extraction helper
///
fn extract_stages(
  protocols: List(Protocol),
  get_stage: fn(Protocol) -> option.Option(Stage(Data, Data)),
  error_fn: fn(String) -> BuildError,
) -> Result(List(Stage(Data, Data)), BuildError) {
  list.try_map(protocols, fn(proto) {
    case get_stage(proto) {
      option.Some(stg) -> Ok(stg)
      option.None -> Error(error_fn(protocol.get_name(proto)))
    }
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a build error to a human-readable string
///
pub fn error_to_string(error: BuildError) -> String {
  case error {
    ValidationFailed(errors) -> {
      let error_strs = validator.errors_to_strings(errors)
      "ValidationFailed: " <> string_join(error_strs, "; ")
    }
    MissingDecoder(protocol:) ->
      "MissingDecoder: protocol '" <> protocol <> "' has no decoder stage"
    MissingEncoder(protocol:) ->
      "MissingEncoder: protocol '" <> protocol <> "' has no encoder stage"
    EmptyProtocolList -> "EmptyProtocolList: no protocols specified"
  }
}

/// Simple string join helper
///
fn string_join(strings: List(String), separator: String) -> String {
  case strings {
    [] -> ""
    [only] -> only
    [first, ..rest] ->
      list.fold(rest, first, fn(acc, s) { acc <> separator <> s })
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the stages that would be used for a protocol pipeline
///
/// Useful for inspection and debugging without actually building the pipeline.
///
/// ## Parameters
///
/// - `reg`: The registry containing protocol definitions
/// - `protocol_names`: List of protocol names
/// - `direction`: Whether to get decoder or encoder stages
///
/// ## Returns
///
/// Result containing list of stages or a BuildError
///
pub fn get_stages(
  reg: Registry,
  protocol_names: List(String),
  direction: Direction,
) -> Result(List(Stage(Data, Data)), BuildError) {
  case protocol_names {
    [] -> Error(EmptyProtocolList)
    _ -> {
      let protocols = registry.get_many(reg, protocol_names)
      let ordered_protocols = case direction {
        Decode -> protocols
        Encode -> list.reverse(protocols)
      }

      case direction {
        Decode -> extract_decoder_stages(ordered_protocols)
        Encode -> extract_encoder_stages(ordered_protocols)
      }
    }
  }
}

/// Checks if a protocol pipeline can be built
///
/// Validates the protocol order and checks that all required stages exist.
///
/// ## Parameters
///
/// - `reg`: The registry containing protocol definitions
/// - `protocol_names`: List of protocol names
/// - `direction`: Whether to check for decoder or encoder stages
///
/// ## Returns
///
/// True if the pipeline can be built, False otherwise
///
pub fn can_build(
  reg: Registry,
  protocol_names: List(String),
  direction: Direction,
) -> Bool {
  case build_pipeline(reg, protocol_names, direction) {
    Ok(_) -> True
    Error(_) -> False
  }
}
