import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}

import aether/pipeline/error.{
  type ErrorRecoveryConfig, type StageError, type StageResult, AccumulateErrors,
  BestEffort, FallbackToDefault, ProcessingError, StopOnFirstError,
  ValidationError,
}

/// Metadata associated with a stage for documentation and debugging
///
/// This type provides additional information about a stage that can be
/// useful for understanding its purpose, configuration, and behavior.
///
pub type StageMetadata {
  /// Creates new stage metadata
  ///
  /// ## Parameters
  /// - `description`: Human-readable description of what the stage does
  /// - `version`: Optional version identifier for the stage implementation
  /// - `tags`: List of tags for categorization and searching
  /// - `config`: Optional configuration data as a string
  ///
  StageMetadata(
    description: String,
    version: Option(String),
    tags: List(String),
    config: Option(String),
  )
}

/// A processing stage that transforms input data to output data
///
/// ## Type Parameters
/// - `input`: The type of data this stage accepts as input
/// - `output`: The type of data this stage produces as output
///
/// ## Fields
/// - `name`: Unique identifier for this stage instance
/// - `process`: Function that performs the actual data transformation
/// - `metadata`: Optional metadata about the stage
///
pub type Stage(input, output) {
  /// Creates a new stage with name, processing function, and optional metadata
  ///
  /// ## Parameters
  /// - `name`: Unique name/identifier for this stage
  /// - `process`: Function that transforms input to Result(output, StageError)
  /// - `metadata`: Optional metadata about the stage
  ///
  Stage(
    name: String,
    process: fn(input) -> Result(output, StageError),
    metadata: Option(StageMetadata),
  )
}

/// A resilient stage that can handle errors according to a recovery strategy
///
/// ## Type Parameters
/// - `input`: The type of data this stage accepts as input
/// - `output`: The type of data this stage produces as output
///
/// ## Fields
/// - `name`: Unique identifier for this resilient stage instance
/// - `stage`: The underlying stage to execute
/// - `recovery_config`: Configuration for error recovery behavior
/// - `metadata`: Optional metadata about the resilient stage
///
pub type ResilientStage(input, output) {
  ResilientStage(
    name: String,
    stage: Stage(input, output),
    recovery_config: ErrorRecoveryConfig,
    metadata: Option(StageMetadata),
  )
}

/// A specialized stage for handling errors from pipeline execution
///
/// This stage receives intermediate results and errors, allowing for
/// custom error processing and recovery logic.
///
/// ## Type Parameters
/// - `input`: The type of data for processing (typically intermediate results)
/// - `output`: The type of data this error handler produces
///
/// ## Fields
/// - `name`: Unique identifier for this error recovery stage
/// - `error_handler`: Function that processes stage results and errors
/// - `filter_errors`: Function to determine which errors to handle
/// - `metadata`: Optional metadata about the error handler
///
pub type ErrorRecoveryStage(input, output) {
  ErrorRecoveryStage(
    name: String,
    error_handler: fn(List(StageResult(Dynamic))) -> Result(output, StageError),
    filter_errors: fn(StageError) -> Bool,
    metadata: Option(StageMetadata),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new stage with the given name and processing function
///
/// ## Parameters
///
/// - `name`: The name of the stage
/// - `process`: The processing function that transforms input to output
///
/// ## Returns
///
/// A new Stage instance with no metadata
///
pub fn new(
  name: String,
  process: fn(input) -> Result(output, StageError),
) -> Stage(input, output) {
  Stage(name, process, option.None)
}

/// Creates a new stage with the given name, processing function, and metadata
///
/// ## Parameters
///
/// - `name`: The name of the stage
/// - `process`: The processing function that transforms input to output
/// - `metadata`: The metadata for the stage
///
/// ## Returns
///
/// A new Stage instance with the specified metadata
///
pub fn new_with_metadata(
  name: String,
  process: fn(input) -> Result(output, StageError),
  metadata: StageMetadata,
) -> Stage(input, output) {
  Stage(name, process, option.Some(metadata))
}

/// Adds metadata to an existing stage
///
/// ## Parameters
///
/// - `stage`: The stage to add metadata to
/// - `metadata`: The metadata to add
///
/// ## Returns
///
/// A new Stage instance with the specified metadata
///
pub fn with_metadata(
  stage: Stage(input, output),
  metadata: StageMetadata,
) -> Stage(input, output) {
  Stage(stage.name, stage.process, option.Some(metadata))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ResilientStage Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new resilient stage with the given recovery configuration
///
/// ## Parameters
///
/// - `name`: The name of the resilient stage
/// - `stage`: The underlying stage to execute
/// - `recovery_config`: The error recovery configuration
///
/// ## Returns
///
/// A new ResilientStage instance
///
pub fn new_resilient(
  name: String,
  stage: Stage(input, output),
  recovery_config: ErrorRecoveryConfig,
) -> ResilientStage(input, output) {
  ResilientStage(name, stage, recovery_config, option.None)
}

/// Creates a resilient stage that stops on first error
///
pub fn resilient_stop_on_error(
  name: String,
  stage: Stage(input, output),
) -> ResilientStage(input, output) {
  let config = error.default_error_recovery_config(StopOnFirstError)
  new_resilient(name <> "_resilient", stage, config)
}

/// Creates a resilient stage that accumulates errors
///
pub fn resilient_accumulate_errors(
  name: String,
  stage: Stage(input, output),
) -> ResilientStage(input, output) {
  let config = error.default_error_recovery_config(AccumulateErrors)
  new_resilient(name <> "_resilient", stage, config)
}

/// Creates a resilient stage that continues despite errors
///
pub fn resilient_best_effort(
  name: String,
  stage: Stage(input, output),
) -> ResilientStage(input, output) {
  let config = error.default_error_recovery_config(BestEffort)
  new_resilient(name <> "_resilient", stage, config)
}

/// Creates a resilient stage with fallback value
///
pub fn resilient_with_fallback(
  name: String,
  stage: Stage(input, output),
  fallback_value: Dynamic,
) -> ResilientStage(input, output) {
  let config =
    error.default_error_recovery_config(FallbackToDefault(fallback_value))
  new_resilient(name <> "_resilient", stage, config)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ErrorRecoveryStage Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new error recovery stage
///
/// ## Parameters
///
/// - `name`: The name of the error recovery stage
/// - `error_handler`: Function to process stage results and errors
/// - `filter_errors`: Function to determine which errors to handle
///
/// ## Returns
///
/// A new ErrorRecoveryStage instance
///
pub fn new_error_recovery(
  name: String,
  error_handler: fn(List(StageResult(Dynamic))) -> Result(output, StageError),
  filter_errors: fn(StageError) -> Bool,
) -> ErrorRecoveryStage(input, output) {
  ErrorRecoveryStage(name, error_handler, filter_errors, option.None)
}

/// Creates an error recovery stage that handles all errors
///
pub fn handle_all_errors(
  name: String,
  error_handler: fn(List(StageResult(Dynamic))) -> Result(output, StageError),
) -> ErrorRecoveryStage(input, output) {
  new_error_recovery(name, error_handler, fn(_error) { True })
}

/// Creates an error recovery stage that handles only validation errors
///
pub fn handle_validation_errors(
  name: String,
  error_handler: fn(List(StageResult(Dynamic))) -> Result(output, StageError),
) -> ErrorRecoveryStage(input, output) {
  new_error_recovery(name, error_handler, fn(error) {
    case error {
      ValidationError(_) -> True
      _ -> False
    }
  })
}

/// Creates an error recovery stage that handles only processing errors
///
pub fn handle_processing_errors(
  name: String,
  error_handler: fn(List(StageResult(Dynamic))) -> Result(output, StageError),
) -> ErrorRecoveryStage(input, output) {
  new_error_recovery(name, error_handler, fn(error) {
    case error {
      ProcessingError(_, _) -> True
      _ -> False
    }
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Metadata Access Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the name of a stage
///
/// ## Parameters
///
/// - `stage`: The stage to get the name from
///
/// ## Returns
///
/// The name of the stage
///
pub fn get_name(stage: Stage(input, output)) -> String {
  stage.name
}

/// Gets the metadata of a stage
///
/// ## Parameters
///
/// - `stage`: The stage to get metadata from
///
/// ## Returns
///
/// An Option containing the metadata if present, or None if no metadata
///
pub fn get_metadata(stage: Stage(input, output)) -> Option(StageMetadata) {
  stage.metadata
}

/// Gets the description from a stage's metadata
///
/// ## Parameters
///
/// - `stage`: The stage to get the description from
///
/// ## Returns
///
/// An Option containing the description if metadata exists, or None
///
pub fn get_description(stage: Stage(input, output)) -> Option(String) {
  case stage.metadata {
    option.Some(metadata) -> option.Some(metadata.description)
    option.None -> option.None
  }
}

/// Gets the version from a stage's metadata
///
/// ## Parameters
///
/// - `stage`: The stage to get the version from
///
/// ## Returns
///
/// An Option containing the version if metadata exists and has a version, or None
///
pub fn get_version(stage: Stage(input, output)) -> Option(String) {
  case stage.metadata {
    option.Some(metadata) -> metadata.version
    option.None -> option.None
  }
}

/// Gets the tags from a stage's metadata
///
/// ## Parameters
///
/// - `stage`: The stage to get the tags from
///
/// ## Returns
///
/// A List containing the tags if metadata exists, or an empty list
///
pub fn get_tags(stage: Stage(input, output)) -> List(String) {
  case stage.metadata {
    option.Some(metadata) -> metadata.tags
    option.None -> []
  }
}

/// Gets the config from a stage's metadata
///
/// ## Parameters
///
/// - `stage`: The stage to get the config from
///
/// ## Returns
///
/// An Option containing the config if metadata exists, or None
///
pub fn get_config(stage: Stage(input, output)) -> Option(String) {
  case stage.metadata {
    option.Some(metadata) -> metadata.config
    option.None -> option.None
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Execution Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Executes a stage with the given input
///
/// ## Parameters
///
/// - `stage`: The stage to execute
/// - `input`: The input data to process
///
/// ## Returns
///
/// Result containing the processed output or a StageError
///
pub fn execute(
  stage: Stage(input, output),
  input: input,
) -> Result(output, StageError) {
  stage.process(input)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Transformation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Maps the output of a stage using a transformation function
///
/// ## Parameters
///
/// - `stage`: The stage to transform
/// - `transform_fn`: Function to transform the output
///
/// ## Returns
///
/// A new stage with transformed output type
///
pub fn map_output(
  stage: Stage(input, inner_output),
  transform_fn: fn(inner_output) -> new_output,
) -> Stage(input, new_output) {
  Stage(
    stage.name <> "_mapped",
    fn(input) {
      case execute(stage, input) {
        Ok(inner_result) -> Ok(transform_fn(inner_result))
        Error(error) -> Error(error)
      }
    },
    stage.metadata,
  )
}

/// Maps the error of a stage using a transformation function
///
/// ## Parameters
///
/// - `stage`: The stage to transform
/// - `error_transform_fn`: Function to transform the error
///
/// ## Returns
///
/// A new stage with transformed error type
///
pub fn map_error(
  stage: Stage(input, output),
  error_transform_fn: fn(StageError) -> new_error,
) -> Stage(input, Result(output, new_error)) {
  Stage(
    stage.name <> "_error_mapped",
    fn(input) {
      case execute(stage, input) {
        Ok(result) -> Ok(Ok(result))
        Error(error) -> Ok(Error(error_transform_fn(error)))
      }
    },
    stage.metadata,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Composition Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Composes two stages where the output of the first becomes the input of the second
///
/// ## Parameters
///
/// - `first`: The first stage to execute
/// - `second`: The second stage to execute (receives first's output)
///
/// ## Returns
///
/// A new composed stage that chains the two stages
///
pub fn compose(
  first: Stage(input, middle),
  second: Stage(middle, output),
) -> Stage(input, output) {
  Stage(
    first.name <> "_then_" <> second.name,
    fn(input) {
      case execute(first, input) {
        Ok(middle_result) -> execute(second, middle_result)
        Error(error) -> Error(error)
      }
    },
    option.None,
    // Composed stages don't inherit metadata
  )
}

/// Chains stage execution with and_then semantics
///
/// ## Parameters
///
/// - `stage`: The initial stage
/// - `next_fn`: Function that takes the output and returns the next stage
///
/// ## Returns
///
/// A new stage that applies the function and executes the resulting stage
///
pub fn and_then(
  stage: Stage(input, middle),
  next_fn: fn(middle) -> Stage(middle, output),
) -> Stage(input, output) {
  Stage(
    stage.name <> "_and_then",
    fn(input) {
      case execute(stage, input) {
        Ok(middle_result) -> {
          let next_stage = next_fn(middle_result)
          execute(next_stage, middle_result)
        }
        Error(error) -> Error(error)
      }
    },
    option.None,
  )
}
