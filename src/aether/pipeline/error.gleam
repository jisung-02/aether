import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/option.{type Option}

pub type StageError {
  ProcessingError(message: String, cause: Option(Dynamic))
  ValidationError(message: String)
  TimeoutError(message: String, timeout_ms: Int)
  ConfigurationError(message: String)
}

pub type PipelineError {
  StageFailure(stage_name: String, stage_index: Int, error: StageError)
  CompositionError(message: String, expected_type: String, actual_type: String)
  EmptyPipelineError
  ExecutionError(message: String)
}

pub type RecoveryStrategy {
  StopOnFirstError
  AccumulateErrors
  BestEffort
  FallbackToDefault(default_value: Dynamic)
  RetryWithBackoff(max_retries: Int, base_delay_ms: Int)
}

pub type ErrorRecoveryConfig {
  ErrorRecoveryConfig(
    strategy: RecoveryStrategy,
    continue_on_error: Bool,
    collect_intermediate_results: Bool,
    max_errors: Option(Int),
  )
}

pub type StageResult(output) {
  StageResult(
    stage_name: String,
    stage_index: Int,
    output: Option(output),
    error: Option(StageError),
    execution_time_ms: Int,
    metadata: Option(Dynamic),
  )
}

pub type PipelineExecutionResult(output) {
  PipelineExecutionResult(
    final_output: Option(output),
    stage_results: List(StageResult(Dynamic)),
    errors: List(PipelineError),
    total_execution_time_ms: Int,
    recovery_strategy: RecoveryStrategy,
    success: Bool,
  )
}

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
    TimeoutError(message: message, timeout_ms: timeout) ->
      "TimeoutError: " <> message <> " (" <> int.to_string(timeout) <> "ms)"
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
    StageFailure(
      stage_name: stage_name,
      stage_index: stage_index,
      error: stage_error,
    ) -> {
      "StageFailure at '"
      <> stage_name
      <> "' (index "
      <> int.to_string(stage_index)
      <> "): "
      <> stage_error_to_string(stage_error)
    }
    CompositionError(
      message: message,
      expected_type: expected,
      actual_type: actual,
    ) -> {
      "CompositionError: "
      <> message
      <> " (expected: "
      <> expected
      <> ", actual: "
      <> actual
      <> ")"
    }
    EmptyPipelineError -> "EmptyPipelineError: Cannot execute an empty pipeline"
    ExecutionError(message: message) -> "ExecutionError: " <> message
  }
}

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
pub fn stage_failure(
  stage_name: String,
  stage_index: Int,
  stage_error: StageError,
) -> PipelineError {
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
pub fn composition_error(
  message: String,
  expected_type: String,
  actual_type: String,
) -> PipelineError {
  CompositionError(message, expected_type, actual_type)
}

/// Creates a recovery strategy that stops on first error
///
pub fn stop_on_first_error() -> RecoveryStrategy {
  StopOnFirstError
}

/// Creates a recovery strategy that accumulates all errors
///
pub fn accumulate_errors() -> RecoveryStrategy {
  AccumulateErrors
}

/// Creates a recovery strategy that continues execution despite errors
///
pub fn best_effort() -> RecoveryStrategy {
  BestEffort
}

/// Creates a recovery strategy that provides default values for failures
///
pub fn fallback_to_default(default_value: Dynamic) -> RecoveryStrategy {
  FallbackToDefault(default_value)
}

/// Creates a recovery strategy that retries with exponential backoff
///
pub fn retry_with_backoff(
  max_retries: Int,
  base_delay_ms: Int,
) -> RecoveryStrategy {
  RetryWithBackoff(max_retries, base_delay_ms)
}

/// Creates error recovery configuration with default settings
///
pub fn default_error_recovery_config(
  strategy: RecoveryStrategy,
) -> ErrorRecoveryConfig {
  ErrorRecoveryConfig(
    strategy: strategy,
    continue_on_error: True,
    collect_intermediate_results: True,
    max_errors: option.None,
  )
}

/// Creates error recovery configuration with custom settings
///
pub fn error_recovery_config(
  strategy: RecoveryStrategy,
  continue_on_error: Bool,
  collect_intermediate_results: Bool,
  max_errors: Option(Int),
) -> ErrorRecoveryConfig {
  ErrorRecoveryConfig(
    strategy: strategy,
    continue_on_error: continue_on_error,
    collect_intermediate_results: collect_intermediate_results,
    max_errors: max_errors,
  )
}

/// Creates a successful stage result
///
pub fn successful_stage_result(
  stage_name: String,
  stage_index: Int,
  output: output,
  execution_time_ms: Int,
) -> StageResult(output) {
  StageResult(
    stage_name: stage_name,
    stage_index: stage_index,
    output: option.Some(output),
    error: option.None,
    execution_time_ms: execution_time_ms,
    metadata: option.None,
  )
}

/// Creates a failed stage result
///
pub fn failed_stage_result(
  stage_name: String,
  stage_index: Int,
  error: StageError,
  execution_time_ms: Int,
) -> StageResult(a) {
  StageResult(
    stage_name: stage_name,
    stage_index: stage_index,
    output: option.None,
    error: option.Some(error),
    execution_time_ms: execution_time_ms,
    metadata: option.None,
  )
}

/// Creates a successful pipeline execution result
///
pub fn successful_pipeline_execution(
  final_output: output,
  stage_results: List(StageResult(Dynamic)),
  execution_time_ms: Int,
  recovery_strategy: RecoveryStrategy,
) -> PipelineExecutionResult(output) {
  PipelineExecutionResult(
    final_output: option.Some(final_output),
    stage_results: stage_results,
    errors: [],
    total_execution_time_ms: execution_time_ms,
    recovery_strategy: recovery_strategy,
    success: True,
  )
}

/// Creates a failed pipeline execution result
///
pub fn failed_pipeline_execution(
  stage_results: List(StageResult(Dynamic)),
  errors: List(PipelineError),
  execution_time_ms: Int,
  recovery_strategy: RecoveryStrategy,
) -> PipelineExecutionResult(a) {
  PipelineExecutionResult(
    final_output: option.None,
    stage_results: stage_results,
    errors: errors,
    total_execution_time_ms: execution_time_ms,
    recovery_strategy: recovery_strategy,
    success: False,
  )
}
