import gleam/int
import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}

/// Errors that can occur during stage execution
///
/// These errors provide detailed context about what went wrong during
/// the processing of individual stages in a pipeline.
///
pub type StageError {
  /// A general processing error with optional cause information
  ///
  /// ## Parameters
  /// - `message`: Human-readable error description
  /// - `cause`: Optional dynamic value that caused the error
  ProcessingError(message: String, cause: Option(Dynamic))

  /// A validation error when input doesn't meet requirements
  ///
  /// ## Parameters
  /// - `message`: Description of validation failure
  ValidationError(message: String)

  /// A timeout error when stage execution exceeds time limit
  ///
  /// ## Parameters
  /// - `message`: Description of timeout scenario
  /// - `timeout_ms`: The timeout duration in milliseconds
  TimeoutError(message: String, timeout_ms: Int)

  /// A configuration error when stage is improperly configured
  ///
  /// ## Parameters
  /// - `message`: Description of configuration issue
  ConfigurationError(message: String)
}

/// Errors that can occur during pipeline execution
///
/// These errors provide comprehensive context about pipeline failures,
/// including which stage failed and why.
///
pub type PipelineError {
  /// Error when a specific stage in the pipeline fails
  ///
  /// ## Parameters
  /// - `stage_name`: Name of the failing stage
  /// - `stage_index`: Index of the failing stage in the pipeline
  /// - `error`: The specific stage error that occurred
  StageFailure(stage_name: String, stage_index: Int, error: StageError)

  /// Error when pipeline composition fails due to type mismatches
  ///
  /// ## Parameters
  /// - `message`: Description of composition failure
  /// - `expected_type`: Expected type for composition
  /// - `actual_type`: Actual type that was provided
  CompositionError(message: String, expected_type: String, actual_type: String)

  /// Error when attempting to execute an empty pipeline
  EmptyPipelineError

  /// General pipeline execution error
  ///
  /// ## Parameters
  /// - `message`: Description of execution error
  ExecutionError(message: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Conversion Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts stage errors to strings for logging and debugging
///
/// ## Parameters
///
/// - `error`: The stage error to convert
///
/// ## Returns
///
/// A human-readable string representation of the error
///
pub fn stage_error_to_string(error: StageError) -> String {
  case error {
    ProcessingError(message: message, cause: cause) -> {
      let cause_str = case cause {
        option.Some(_dynamic_value) -> " (cause: dynamic_value)"
        option.None -> ""
      }
      "ProcessingError: " <> message <> cause_str
    }
    ValidationError(message: message) -> "ValidationError: " <> message
    TimeoutError(message: message, timeout_ms: timeout) -> "TimeoutError: " <> message <> " (" <> int.to_string(timeout) <> "ms)"
    ConfigurationError(message: message) -> "ConfigurationError: " <> message
  }
}

/// Converts pipeline errors to strings for logging and debugging
///
/// ## Parameters
///
/// - `error`: The pipeline error to convert
///
/// ## Returns
///
/// A human-readable string representation of the error
///
pub fn pipeline_error_to_string(error: PipelineError) -> String {
  case error {
    StageFailure(stage_name: stage_name, stage_index: stage_index, error: stage_error) -> {
      "StageFailure at '" <> stage_name <> "' (index " <> int.to_string(stage_index) <> "): " <> stage_error_to_string(stage_error)
    }
    CompositionError(message: message, expected_type: expected, actual_type: actual) -> {
      "CompositionError: " <> message <> " (expected: " <> expected <> ", actual: " <> actual <> ")"
    }
    EmptyPipelineError -> "EmptyPipelineError: Cannot execute an empty pipeline"
    ExecutionError(message: message) -> "ExecutionError: " <> message
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Creation Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a processing error with optional cause
///
/// ## Parameters
///
/// - `message`: Error description
/// - `cause`: Optional cause value
///
/// ## Returns
///
/// A new ProcessingError
///
pub fn processing_error(message: String, cause: Option(Dynamic)) -> StageError {
  ProcessingError(message, cause)
}

/// Creates a validation error
///
/// ## Parameters
///
/// - `message`: Validation failure description
///
/// ## Returns
///
/// A new ValidationError
///
pub fn validation_error(message: String) -> StageError {
  ValidationError(message)
}

/// Creates a timeout error
///
/// ## Parameters
///
/// - `message`: Timeout description
/// - `timeout_ms`: Timeout duration in milliseconds
///
/// ## Returns
///
/// A new TimeoutError
///
pub fn timeout_error(message: String, timeout_ms: Int) -> StageError {
  TimeoutError(message, timeout_ms)
}

/// Creates a configuration error
///
/// ## Parameters
///
/// - `message`: Configuration issue description
///
/// ## Returns
///
/// A new ConfigurationError
///
pub fn configuration_error(message: String) -> StageError {
  ConfigurationError(message)
}

/// Creates a stage failure error
///
/// ## Parameters
///
/// - `stage_name`: Name of the failing stage
/// - `stage_index`: Index in pipeline
/// - `stage_error`: The underlying stage error
///
/// ## Returns
///
/// A new StageFailure error
///
pub fn stage_failure(stage_name: String, stage_index: Int, stage_error: StageError) -> PipelineError {
  StageFailure(stage_name, stage_index, stage_error)
}

/// Creates a composition error
///
/// ## Parameters
///
/// - `message`: Description of composition issue
/// - `expected_type`: Expected type
/// - `actual_type`: Actual type provided
///
/// ## Returns
///
/// A new CompositionError
///
pub fn composition_error(message: String, expected_type: String, actual_type: String) -> PipelineError {
  CompositionError(message, expected_type, actual_type)
}