import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}

import aether/pipeline/error.{
  type ErrorRecoveryConfig, type StageError, type StageResult, AccumulateErrors,
  BestEffort, FallbackToDefault, ProcessingError, StopOnFirstError,
  ValidationError,
}

pub type StageMetadata {
  StageMetadata(
    description: String,
    version: Option(String),
    tags: List(String),
    config: Option(String),
  )
}

pub type Stage(input, output) {
  Stage(
    name: String,
    process: fn(input) -> Result(output, StageError),
    metadata: Option(StageMetadata),
  )
}

pub type ResilientStage(input, output) {
  ResilientStage(
    name: String,
    stage: Stage(input, output),
    recovery_config: ErrorRecoveryConfig,
    metadata: Option(StageMetadata),
  )
}

pub type ErrorRecoveryStage(input, output) {
  ErrorRecoveryStage(
    name: String,
    error_handler: fn(List(StageResult(Dynamic))) -> Result(output, StageError),
    filter_errors: fn(StageError) -> Bool,
    metadata: Option(StageMetadata),
  )
}

pub fn new(
  name: String,
  process: fn(input) -> Result(output, StageError),
) -> Stage(input, output) {
  Stage(name, process, option.None)
}

pub fn new_with_metadata(
  name: String,
  process: fn(input) -> Result(output, StageError),
  metadata: StageMetadata,
) -> Stage(input, output) {
  Stage(name, process, option.Some(metadata))
}

pub fn with_metadata(
  stage: Stage(input, output),
  metadata: StageMetadata,
) -> Stage(input, output) {
  Stage(stage.name, stage.process, option.Some(metadata))
}

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

pub fn get_name(stage: Stage(input, output)) -> String {
  stage.name
}

pub fn get_metadata(stage: Stage(input, output)) -> Option(StageMetadata) {
  stage.metadata
}

pub fn get_description(stage: Stage(input, output)) -> Option(String) {
  case stage.metadata {
    option.Some(metadata) -> option.Some(metadata.description)
    option.None -> option.None
  }
}

pub fn get_version(stage: Stage(input, output)) -> Option(String) {
  case stage.metadata {
    option.Some(metadata) -> metadata.version
    option.None -> option.None
  }
}

pub fn get_tags(stage: Stage(input, output)) -> List(String) {
  case stage.metadata {
    option.Some(metadata) -> metadata.tags
    option.None -> []
  }
}

pub fn get_config(stage: Stage(input, output)) -> Option(String) {
  case stage.metadata {
    option.Some(metadata) -> metadata.config
    option.None -> option.None
  }
}

pub fn execute(
  stage: Stage(input, output),
  input: input,
) -> Result(output, StageError) {
  stage.process(input)
}

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
