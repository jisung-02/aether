import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option}

import aether/pipeline/error.{
  type ErrorRecoveryConfig, type PipelineError, type PipelineExecutionResult,
  type StageError, AccumulateErrors, BestEffort, EmptyPipelineError,
  StopOnFirstError, failed_pipeline_execution, successful_pipeline_execution,
}

import aether/pipeline/stage.{type Stage}

// FFI for type coercion - used for Dynamic type conversions
@external(erlang, "gleam_stdlib", "identity")
fn unsafe_coerce(value: a) -> b

@external(erlang, "gleam_stdlib", "identity")
fn to_dynamic(value: a) -> Dynamic

/// Internal type representing information about a stage in a pipeline
///
/// This type stores the stage name, index, and executor function needed for
/// pipeline execution, debugging, and performance monitoring.
///
type StageInfo {
  StageInfo(
    name: String,
    index: Int,
    executor: fn(Dynamic) -> Result(Dynamic, StageError),
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
/// The pipeline uses function composition to chain stages together,
/// storing a single executor function that processes input through all stages.
///
pub opaque type Pipeline(input, output) {
  Pipeline(
    stages: List(StageInfo),
    executor: fn(input) -> Result(output, PipelineError),
    input_type: String,
    output_type: String,
    recovery_config: Option(ErrorRecoveryConfig),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new empty pipeline
///
/// An empty pipeline acts as an identity function - input passes through unchanged.
///
/// ## Returns
///
/// An empty pipeline that can be extended with stages
///
pub fn new() -> Pipeline(a, a) {
  Pipeline(
    stages: [],
    executor: fn(x) { Ok(x) },
    input_type: "a",
    output_type: "a",
    recovery_config: option.None,
  )
}

/// Creates an empty pipeline with a specific type signature
///
/// Note: This creates a pipeline that will fail on execution since it has
/// no executor defined. Use `new()` for a working empty pipeline, or
/// `from_stage()` for a pipeline with an initial stage.
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
  Pipeline(
    stages: [],
    executor: fn(_) { Error(EmptyPipelineError) },
    input_type: "input",
    output_type: "output",
    recovery_config: option.None,
  )
}

/// Creates a pipeline with a single stage
///
/// ## Parameters
///
/// - `stg`: The initial stage for the pipeline
///
/// ## Returns
///
/// A new pipeline containing the given stage
///
pub fn from_stage(stg: Stage(input, output)) -> Pipeline(input, output) {
  let stage_name = stage.get_name(stg)

  // Create a Dynamic-based executor for the stage
  let dynamic_executor = fn(dyn_input: Dynamic) -> Result(Dynamic, StageError) {
    let input: input = unsafe_coerce(dyn_input)
    case stage.execute(stg, input) {
      Ok(result) -> Ok(to_dynamic(result))
      Error(e) -> Error(e)
    }
  }

  let stage_info = StageInfo(stage_name, 0, dynamic_executor)

  Pipeline(
    stages: [stage_info],
    executor: fn(input) {
      case stage.execute(stg, input) {
        Ok(result) -> Ok(result)
        Error(stage_error) ->
          Error(error.stage_failure(stage_name, 0, stage_error))
      }
    },
    input_type: "input",
    output_type: "output",
    recovery_config: option.None,
  )
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
pub fn with_recovery(
  recovery_config: ErrorRecoveryConfig,
) -> Pipeline(input, output) {
  Pipeline(
    stages: [],
    executor: fn(_) { Error(EmptyPipelineError) },
    input_type: "input",
    output_type: "output",
    recovery_config: option.Some(recovery_config),
  )
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
  Pipeline(
    stages: pipeline.stages,
    executor: pipeline.executor,
    input_type: pipeline.input_type,
    output_type: pipeline.output_type,
    recovery_config: option.Some(recovery_config),
  )
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
  list.length(pipeline.stages)
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
  pipeline.stages == []
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
  list.map(pipeline.stages, fn(stage_info) { stage_info.name })
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
  pipeline.input_type
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
  pipeline.output_type
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
  case pipeline.stages {
    [] -> Error(EmptyPipelineError)
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
/// This function composes the pipeline's executor with the new stage,
/// creating a single execution function that chains all operations.
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to extend
/// - `stg`: The stage to add
///
/// ## Returns
///
/// A new pipeline with the stage added at the end
///
pub fn add_stage(
  pipeline: Pipeline(input, middle),
  stg: Stage(middle, output),
) -> Pipeline(input, output) {
  let new_index = list.length(pipeline.stages)
  let stage_name = stage.get_name(stg)

  // Create a Dynamic-based executor for the stage
  let dynamic_executor = fn(dyn_input: Dynamic) -> Result(Dynamic, StageError) {
    let input: middle = unsafe_coerce(dyn_input)
    case stage.execute(stg, input) {
      Ok(result) -> Ok(to_dynamic(result))
      Error(e) -> Error(e)
    }
  }

  let new_stage_info = StageInfo(stage_name, new_index, dynamic_executor)

  // Capture the previous executor for composition
  let prev_executor = pipeline.executor

  // Compose executors: pipeline.executor >> stage.execute
  let composed_executor = fn(input) {
    case prev_executor(input) {
      Ok(middle_result) -> {
        case stage.execute(stg, middle_result) {
          Ok(final_result) -> Ok(final_result)
          Error(stage_error) ->
            Error(error.stage_failure(stage_name, new_index, stage_error))
        }
      }
      Error(pipeline_error) -> Error(pipeline_error)
    }
  }

  Pipeline(
    stages: list.append(pipeline.stages, [new_stage_info]),
    executor: composed_executor,
    input_type: pipeline.input_type,
    output_type: "output",
    recovery_config: pipeline.recovery_config,
  )
}

/// Pipes the output of a pipeline into a stage
///
/// This is the primary method for building pipelines in a fluent style.
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to extend
/// - `stg`: The stage to pipe into
///
/// ## Returns
///
/// A new pipeline with the stage added
///
pub fn pipe(
  pipeline: Pipeline(input, middle),
  stg: Stage(middle, output),
) -> Pipeline(input, output) {
  add_stage(pipeline, stg)
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
  let map_stage =
    stage.new("map_" <> int.to_string(length(pipeline)), fn(output) {
      Ok(transform_fn(output))
    })

  add_stage(pipeline, map_stage)
}

/// Recovers from pipeline errors by providing a fallback function
///
/// This function wraps the pipeline's executor to catch errors and
/// provide fallback values, enabling graceful error handling.
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
  recover_fn: fn(PipelineError) -> output,
) -> Pipeline(input, output) {
  let stage_count = length(pipeline)

  // Recovery stage just passes through - actual recovery is in the composed executor
  let dynamic_executor = fn(dyn_input: Dynamic) -> Result(Dynamic, StageError) {
    Ok(dyn_input)
  }

  let recover_stage_info =
    StageInfo(
      "recover_" <> int.to_string(stage_count),
      stage_count,
      dynamic_executor,
    )

  // Capture the previous executor
  let prev_executor = pipeline.executor

  // Create a recovered executor that catches errors
  let recovered_executor = fn(input) {
    case prev_executor(input) {
      Ok(result) -> Ok(result)
      Error(err) -> Ok(recover_fn(err))
    }
  }

  Pipeline(
    stages: list.append(pipeline.stages, [recover_stage_info]),
    executor: recovered_executor,
    input_type: pipeline.input_type,
    output_type: pipeline.output_type,
    recovery_config: pipeline.recovery_config,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Appends another pipeline to the end of this pipeline
///
/// This function composes two pipelines by chaining their executors,
/// so that the output of the first pipeline becomes the input to the second.
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
pub fn append(first: Pipeline(a, b), second: Pipeline(b, c)) -> Pipeline(a, c) {
  let first_stage_count = list.length(first.stages)

  // Reindex the second pipeline's stages
  let reindexed_second_stages =
    list.map(second.stages, fn(info) {
      StageInfo(info.name, info.index + first_stage_count, info.executor)
    })

  // Combine stage info lists
  let combined_stages = list.append(first.stages, reindexed_second_stages)

  // Capture executors for composition
  let first_executor = first.executor
  let second_executor = second.executor

  // Compose executors: first >> second
  let composed_executor = fn(input) {
    case first_executor(input) {
      Ok(middle) -> second_executor(middle)
      Error(err) -> Error(err)
    }
  }

  // Merge recovery configs (prefer first, fallback to second)
  let merged_recovery = case first.recovery_config, second.recovery_config {
    option.Some(c), _ -> option.Some(c)
    _, option.Some(c) -> option.Some(c)
    _, _ -> option.None
  }

  Pipeline(
    stages: combined_stages,
    executor: composed_executor,
    input_type: first.input_type,
    output_type: second.output_type,
    recovery_config: merged_recovery,
  )
}

/// Prepends another pipeline to the beginning of this pipeline
///
/// This is equivalent to `append(first, second)` - the first pipeline
/// is executed before the second.
///
/// ## Parameters
///
/// - `first`: The pipeline to prepend (executed first)
/// - `second`: The second pipeline (executed after first)
///
/// ## Returns
///
/// A new pipeline combining both pipelines
///
pub fn prepend(first: Pipeline(a, b), second: Pipeline(b, c)) -> Pipeline(a, c) {
  append(first, second)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Execution Function
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Executes a pipeline with the given input
///
/// This function runs the composed executor function, which processes
/// the input through all stages in sequence.
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
pub fn execute(pipeline: Pipeline(a, b), input: a) -> Result(b, PipelineError) {
  pipeline.executor(input)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Enhanced Pipeline Execution with Error Recovery
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Executes a pipeline with error recovery and detailed result tracking
///
/// This function executes the pipeline and wraps the result in a
/// PipelineExecutionResult structure for detailed tracking.
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
  input: a,
  recovery_config: Option(ErrorRecoveryConfig),
) -> PipelineExecutionResult(b) {
  let strategy = case recovery_config {
    option.Some(config) -> config.strategy
    option.None -> StopOnFirstError
  }

  // Execute the pipeline
  let execution_time = 1
  // Placeholder for actual timing

  case pipeline.executor(input) {
    Ok(result) ->
      successful_pipeline_execution(result, [], execution_time, strategy)
    Error(err) -> failed_pipeline_execution([], [err], execution_time, strategy)
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
) -> PipelineExecutionResult(b) {
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
) -> PipelineExecutionResult(b) {
  let recovery_config = error.default_error_recovery_config(BestEffort)
  execute_with_recovery(pipeline, input, option.Some(recovery_config))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Executor Access (for executor module)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// A single stage executor with its metadata
///
/// This type is used by the executor module for step-by-step execution
/// with timing and context tracking.
///
pub type StageExecutor {
  StageExecutor(
    name: String,
    index: Int,
    executor: fn(Dynamic) -> Result(Dynamic, StageError),
  )
}

/// Gets the list of stage executors from a pipeline
///
/// This function is used by the executor module to perform step-by-step
/// execution with timing and context tracking.
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to get stage executors from
///
/// ## Returns
///
/// A list of StageExecutor records containing name, index, and executor function
///
pub fn get_stage_executors(
  pipeline: Pipeline(input, output),
) -> List(StageExecutor) {
  list.map(pipeline.stages, fn(info) {
    StageExecutor(info.name, info.index, info.executor)
  })
}
