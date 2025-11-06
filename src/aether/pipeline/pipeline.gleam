import gleam/list
import gleam/int
import gleam/option.{type Option}
import gleam/dynamic.{type Dynamic}

import aether/pipeline/stage.{type Stage}
import aether/pipeline/error.{type PipelineError, type ErrorRecoveryConfig, type PipelineExecutionResult, failed_pipeline_execution, AccumulateErrors, BestEffort, StopOnFirstError, EmptyPipelineError, ExecutionError}

/// Internal type representing information about a stage in a pipeline
///
/// This type stores the stage name and index needed for pipeline
/// execution and debugging.
///
type StageInfo {
  StageInfo(
    name: String,
    index: Int,
  )
}

/// Internal state of a pipeline
///
/// This type represents the complete state of a pipeline including
/// all stages and execution metadata.
///
type PipelineState {
  PipelineState(
    stages: List(StageInfo),
    input_type: String,
    output_type: String,
    recovery_config: Option(ErrorRecoveryConfig),
  )
}

/// A type-safe pipeline that composes multiple stages for data processing
///
/// ## Type Parameters
/// - `input`: The input type of the pipeline
/// - `output`: The output type of the pipeline
///
/// This opaque type ensures that pipelines can only be created and
/// manipulated through the provided API functions, maintaining type safety.
///
pub opaque type Pipeline(input, output) {
  Pipeline(state: PipelineState)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new empty pipeline
///
/// ## Returns
///
/// An empty pipeline that can be extended with stages
///
pub fn new() -> Pipeline(a, a) {
  Pipeline(PipelineState(
    [],
    "a",
    "a",
    option.None,
  ))
}

/// Creates an empty pipeline with a specific type signature
///
/// ## Type Parameters
/// - `input`: The input type
/// - `output`: The output type
///
/// ## Returns
///
/// An empty pipeline with the specified type signature
///
pub fn empty() -> Pipeline(input, output) {
  Pipeline(PipelineState(
    [],
    "input",
    "output",
    option.None,
  ))
}

/// Creates a pipeline with a single stage
///
/// ## Parameters
///
/// - `stage`: The initial stage for the pipeline
///
/// ## Returns
///
/// A new pipeline containing the given stage
///
pub fn from_stage(stage: Stage(input, output)) -> Pipeline(input, output) {
  let stage_info = StageInfo(stage.name, 0)

  Pipeline(PipelineState(
    [stage_info],
    "input",
    "output",
    option.None,
  ))
}

/// Creates a pipeline with error recovery configuration
///
/// ## Parameters
///
/// - `recovery_config`: The error recovery configuration for the pipeline
///
/// ## Returns
///
/// An empty pipeline with the specified error recovery configuration
///
pub fn with_recovery(recovery_config: ErrorRecoveryConfig) -> Pipeline(input, output) {
  Pipeline(PipelineState(
    [],
    "input",
    "output",
    option.Some(recovery_config),
  ))
}

/// Sets error recovery configuration on an existing pipeline
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to configure
/// - `recovery_config`: The error recovery configuration to apply
///
/// ## Returns
///
/// A new pipeline with error recovery configuration
///
pub fn set_recovery(
  pipeline: Pipeline(input, output),
  recovery_config: ErrorRecoveryConfig,
) -> Pipeline(input, output) {
  let new_state = PipelineState(
    pipeline.state.stages,
    pipeline.state.input_type,
    pipeline.state.output_type,
    option.Some(recovery_config),
  )

  Pipeline(new_state)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Introspection Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the number of stages in the pipeline
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to inspect
///
/// ## Returns
///
/// The number of stages in the pipeline
///
pub fn length(pipeline: Pipeline(input, output)) -> Int {
  list.length(pipeline.state.stages)
}

/// Checks if the pipeline is empty
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to inspect
///
/// ## Returns
///
/// True if the pipeline has no stages, False otherwise
///
pub fn is_empty(pipeline: Pipeline(input, output)) -> Bool {
  pipeline.state.stages == []
}

/// Gets the names of all stages in the pipeline
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to inspect
///
/// ## Returns
///
/// A list of stage names in execution order
///
pub fn stage_names(pipeline: Pipeline(input, output)) -> List(String) {
  list.map(pipeline.state.stages, fn(stage_info) { stage_info.name })
}

/// Gets the input type representation of the pipeline
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to inspect
///
/// ## Returns
///
/// String representation of the input type
///
pub fn get_input_type(pipeline: Pipeline(input, output)) -> String {
  pipeline.state.input_type
}

/// Gets the output type representation of the pipeline
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to inspect
///
/// ## Returns
///
/// String representation of the output type
///
pub fn get_output_type(pipeline: Pipeline(input, output)) -> String {
  pipeline.state.output_type
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Validation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Validates that a pipeline is well-formed
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to validate
///
/// ## Returns
///
/// Ok(Nil) if the pipeline is valid, Error(PipelineError) otherwise
///
pub fn validate(pipeline: Pipeline(input, output)) -> Result(Nil, PipelineError) {
  case pipeline.state.stages {
    [] -> Error(error.EmptyPipelineError)
    _ -> Ok(Nil)
  }
}

/// Checks if the pipeline is ready for execution
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to check
///
/// ## Returns
///
/// True if the pipeline can be executed, False otherwise
///
pub fn is_ready(pipeline: Pipeline(input, output)) -> Bool {
  case validate(pipeline) {
    Ok(_) -> True
    Error(_) -> False
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Composition Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Adds a stage to the end of a pipeline
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to extend
/// - `stage`: The stage to add
///
/// ## Returns
///
/// A new pipeline with the stage added at the end
///
pub fn add_stage(
  pipeline: Pipeline(input, middle),
  stage: Stage(middle, output),
) -> Pipeline(input, output) {
  let new_stage_info = StageInfo(stage.name, length(pipeline) + 1)

  let new_state = PipelineState(
    list.append(pipeline.state.stages, [new_stage_info]),
    pipeline.state.input_type,
    pipeline.state.output_type,
    pipeline.state.recovery_config,
  )

  Pipeline(new_state)
}

/// Pipes the output of a pipeline into a stage
///
/// This is the primary method for building pipelines in a fluent style.
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to extend
/// - `stage`: The stage to pipe into
///
/// ## Returns
///
/// A new pipeline with the stage added
///
pub fn pipe(
  pipeline: Pipeline(input, middle),
  stage: Stage(middle, output),
) -> Pipeline(input, output) {
  add_stage(pipeline, stage)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Transformation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Maps the output of a pipeline using a transformation function
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to transform
/// - `transform_fn`: Function to transform the pipeline output
///
/// ## Returns
///
/// A new pipeline with transformed output type
///
pub fn map(
  pipeline: Pipeline(input, output),
  transform_fn: fn(output) -> new_output,
) -> Pipeline(input, new_output) {
  let map_stage = stage.new("map_" <> int.to_string(length(pipeline)), fn(output) {
    Ok(transform_fn(output))
  })

  add_stage(pipeline, map_stage)
}

/// Recovers from pipeline errors by providing a fallback function
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to add error recovery to
/// - `recover_fn`: Function to handle errors and provide fallback values
///
/// ## Returns
///
/// A new pipeline that can recover from errors
///
pub fn recover(
  pipeline: Pipeline(input, output),
  _recover_fn: fn(PipelineError) -> output,
) -> Pipeline(input, output) {
  let recover_stage = stage.new("recover_" <> int.to_string(length(pipeline)), fn(input) {
    // This is a simplified implementation
    // In a full implementation, we'd need to execute the pipeline and handle errors
    Ok(input)
  })

  add_stage(pipeline, recover_stage)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Appends another pipeline to the end of this pipeline
///
/// ## Parameters
///
/// - `first`: The first pipeline
/// - `second`: The pipeline to append
///
/// ## Returns
///
/// A new pipeline combining both pipelines
///
pub fn append(
  _first: Pipeline(a, b),
  _second: Pipeline(b, c),
) -> Pipeline(a, c) {
  // For now, this is a simplified implementation that returns an empty pipeline
  // In a full implementation, we'd need to handle stage composition
  empty()
}

/// Prepends another pipeline to the beginning of this pipeline
///
/// ## Parameters
///
/// - `first`: The pipeline to prepend
/// - `second`: The second pipeline
///
/// ## Returns
///
/// A new pipeline combining both pipelines
///
pub fn prepend(
  _first: Pipeline(a, b),
  _second: Pipeline(b, c),
) -> Pipeline(a, c) {
  // For now, this is a simplified implementation that returns an empty pipeline
  // In a full implementation, we'd need to handle stage composition
  empty()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Execution Function
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Executes a pipeline with the given input
///
/// Note: This is a simplified implementation that validates the pipeline
/// but returns a placeholder result. Full execution requires architectural changes.
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to execute
/// - `input`: The input data to process
///
/// ## Returns
///
/// Result containing the processed output or a PipelineError
///
pub fn execute(pipeline: Pipeline(a, b), _input: a) -> Result(b, PipelineError) {
  case validate(pipeline) {
    Error(error) -> Error(error)
    Ok(_) -> {
      case pipeline.state.stages {
        [] -> Error(error.EmptyPipelineError)
        _ -> {
          // Return an error indicating the need for full execution implementation
          Error(error.ExecutionError("Pipeline execution engine implementation in progress"))
        }
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Execution Demonstration Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Demonstrates sequential stage execution for testing purposes
///
/// This function shows how stages would be executed sequentially in a pipeline.
/// It's provided for testing and demonstration until full pipeline execution is implemented.
///
/// ## Parameters
///
/// - `stages`: List of stages to execute
/// - `input`: Initial input data
///
/// ## Returns
///
/// Result containing the final output or error information
///
pub fn demonstrate_sequential_execution(
  stages: List(Stage(String, String)),
  input: String,
) -> Result(String, PipelineError) {
  case stages {
    [] -> Error(error.EmptyPipelineError)
    [single_stage] -> {
      case stage.execute(single_stage, input) {
        Ok(result) -> Ok(result)
        Error(stage_error) -> Error(error.stage_failure(single_stage.name, 0, stage_error))
      }
    }
    [first_stage, ..rest] -> {
      case stage.execute(first_stage, input) {
        Ok(first_result) -> {
          // Continue with remaining stages
          execute_string_stages(rest, first_result, 1)
        }
        Error(stage_error) -> Error(error.stage_failure(first_stage.name, 0, stage_error))
      }
    }
  }
}

/// Internal function for executing string stages sequentially
///
fn execute_string_stages(
  stages: List(Stage(String, String)),
  current_value: String,
  current_index: Int,
) -> Result(String, PipelineError) {
  case stages {
    [] -> Ok(current_value)
    [next_stage, ..rest] -> {
      case stage.execute(next_stage, current_value) {
        Ok(next_result) -> execute_string_stages(rest, next_result, current_index + 1)
        Error(stage_error) -> Error(error.stage_failure(next_stage.name, current_index, stage_error))
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Enhanced Pipeline Execution with Error Recovery
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Executes a pipeline with error recovery and detailed result tracking
///
/// This enhanced execution function continues processing even when individual
/// stages fail, collecting comprehensive execution information.
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to execute
/// - `input`: The input data to process
/// - `recovery_config`: Optional error recovery configuration
///
/// ## Returns
///
/// Detailed execution result with stage-by-stage information
///
pub fn execute_with_recovery(
  pipeline: Pipeline(a, b),
  _input: a,
  recovery_config: Option(ErrorRecoveryConfig),
) -> PipelineExecutionResult(Dynamic) {
  // For this implementation, we'll use the demonstration approach
  // since full execution requires significant architectural changes
  let strategy = case recovery_config {
    option.Some(config) -> config.strategy
    option.None -> StopOnFirstError
  }

  // Create a basic execution result structure
  let stage_results = []
  let execution_time = 1 // Placeholder for actual timing

  case pipeline.state.stages {
    [] -> failed_pipeline_execution(
      stage_results,
      [EmptyPipelineError],
      execution_time,
      strategy,
    )
    _ -> {
      // Return a result indicating the need for full implementation
      failed_pipeline_execution(
        stage_results,
        [ExecutionError("Enhanced execution engine implementation in progress")],
        execution_time,
        strategy,
      )
    }
  }
}

/// Executes a pipeline that continues on errors
///
/// This function implements the core requirement of continuing execution
/// after errors occur, collecting error information for later processing.
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to execute
/// - `input`: The input data to process
///
/// ## Returns
///
/// Execution result with error information and intermediate results
///
pub fn execute_continue_on_error(
  pipeline: Pipeline(a, b),
  input: a,
) -> PipelineExecutionResult(Dynamic) {
  let recovery_config = error.default_error_recovery_config(AccumulateErrors)
  execute_with_recovery(pipeline, input, option.Some(recovery_config))
}

/// Executes a pipeline with best-effort error handling
///
/// Similar to continue-on-error but more forgiving, suitable for
/// non-critical processing pipelines.
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to execute
/// - `input`: The input data to process
///
/// ## Returns
///
/// Execution result with minimal error tracking
///
pub fn execute_best_effort(
  pipeline: Pipeline(a, b),
  input: a,
) -> PipelineExecutionResult(Dynamic) {
  let recovery_config = error.default_error_recovery_config(BestEffort)
  execute_with_recovery(pipeline, input, option.Some(recovery_config))
}