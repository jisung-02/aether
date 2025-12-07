import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/io
import gleam/list
import gleam/string

import aether/pipeline/error.{type StageError}
import aether/pipeline/pipeline.{type Pipeline, type StageExecutor}
import aether/util/time

// FFI for type coercion - used for Dynamic type conversions
@external(erlang, "gleam_stdlib", "identity")
fn unsafe_coerce(value: a) -> b

@external(erlang, "gleam_stdlib", "identity")
fn to_dynamic(value: a) -> Dynamic

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Execution Context Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Execution context for tracking pipeline state
///
/// This type captures the complete execution state of a pipeline,
/// including timing information and intermediate results.
///
pub type ExecutionContext {
  ExecutionContext(
    started_at: Int,
    stage_timings: List(StageTiming),
    intermediate_results: List(Dynamic),
  )
}

/// Timing information for a single stage execution
///
pub type StageTiming {
  StageTiming(
    stage_name: String,
    start_time: Int,
    end_time: Int,
    duration_microseconds: Int,
  )
}

/// Result of pipeline execution with full context
///
pub type ExecutionResult(output) {
  ExecutionResult(output: output, context: ExecutionContext)
}

/// Error that occurred during pipeline execution with context
///
pub type ExecutionError {
  StageExecutionError(
    stage_name: String,
    stage_index: Int,
    error: StageError,
    context: ExecutionContext,
  )
  EmptyPipelineExecutionError
}

/// Log levels for pipeline execution logging
///
pub type LogLevel {
  Debug
  Info
  ErrorOnly
  Silent
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Core Execution Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Executes a pipeline with full context tracking
///
/// This function executes each stage individually, collecting timing
/// information and intermediate results along the way.
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to execute
/// - `input`: The input data to process
///
/// ## Returns
///
/// Result containing ExecutionResult with output and context, or ExecutionError
///
pub fn execute_with_context(
  pipeline: Pipeline(input, output),
  input: input,
) -> Result(ExecutionResult(output), ExecutionError) {
  let stages = pipeline.get_stage_executors(pipeline)

  case stages {
    [] -> Error(EmptyPipelineExecutionError)
    _ -> {
      let context =
        ExecutionContext(
          started_at: time.now_microseconds(),
          stage_timings: [],
          intermediate_results: [],
        )

      do_execute_stages(stages, to_dynamic(input), context, 0)
    }
  }
}

/// Executes a pipeline with logging enabled
///
/// ## Parameters
///
/// - `pipeline`: The pipeline to execute
/// - `input`: The input data to process
/// - `log_level`: The logging level to use
///
/// ## Returns
///
/// Result containing the output or ExecutionError
///
pub fn execute_with_logging(
  pipeline: Pipeline(input, output),
  input: input,
  log_level: LogLevel,
) -> Result(output, ExecutionError) {
  case log_level {
    Debug -> log_pipeline_start(pipeline)
    _ -> Nil
  }

  let result = execute_with_context(pipeline, input)

  case result {
    Ok(exec_result) -> {
      case log_level {
        Debug -> log_pipeline_success(exec_result.context)
        Info -> log_pipeline_summary(exec_result.context)
        _ -> Nil
      }
      Ok(exec_result.output)
    }
    Error(e) -> {
      case log_level {
        Debug | Info | ErrorOnly -> log_pipeline_error(e)
        Silent -> Nil
      }
      Error(e)
    }
  }
}

/// Simple execution without logging (convenience function)
///
pub fn run(
  pipeline: Pipeline(input, output),
  input: input,
) -> Result(output, ExecutionError) {
  case execute_with_context(pipeline, input) {
    Ok(exec_result) -> Ok(exec_result.output)
    Error(e) -> Error(e)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Internal Execution Logic
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn do_execute_stages(
  stages: List(StageExecutor),
  input: Dynamic,
  context: ExecutionContext,
  index: Int,
) -> Result(ExecutionResult(output), ExecutionError) {
  case stages {
    [] -> {
      // All stages completed successfully
      // unsafe_coerce is needed because we're working with Dynamic internally
      let output: output = unsafe_coerce(input)
      Ok(ExecutionResult(output: output, context: context))
    }

    [stage, ..rest] -> {
      // Record stage start time
      let start_time = time.now_microseconds()

      // Execute the stage
      case stage.executor(input) {
        Ok(output) -> {
          // Record stage end time and duration
          let end_time = time.now_microseconds()
          let duration = time.duration_microseconds(start_time, end_time)

          let timing =
            StageTiming(
              stage_name: stage.name,
              start_time: start_time,
              end_time: end_time,
              duration_microseconds: duration,
            )

          // Update context
          let new_context =
            ExecutionContext(
              ..context,
              stage_timings: list.append(context.stage_timings, [timing]),
              intermediate_results: list.append(
                context.intermediate_results,
                [output],
              ),
            )

          // Continue to next stage
          do_execute_stages(rest, output, new_context, index + 1)
        }

        Error(e) -> {
          // Stage failed - return error with context
          Error(StageExecutionError(
            stage_name: stage.name,
            stage_index: index,
            error: e,
            context: context,
          ))
        }
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Logging Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn log_pipeline_start(pipeline: Pipeline(input, output)) -> Nil {
  let stage_names = pipeline.stage_names(pipeline)
  let stage_count = pipeline.length(pipeline)

  io.println("\n=== Pipeline Execution Start ===")
  io.println("Stages: " <> int.to_string(stage_count))
  io.println("Stage names: " <> string.join(stage_names, " -> "))
  io.println("")
}

fn log_pipeline_success(context: ExecutionContext) -> Nil {
  let total_stages = list.length(context.stage_timings)

  let total_duration =
    list.fold(context.stage_timings, 0, fn(acc, timing) {
      acc + timing.duration_microseconds
    })

  io.println("\n=== Pipeline Execution Success ===")
  io.println("Total stages: " <> int.to_string(total_stages))
  io.println("Total duration: " <> int.to_string(total_duration) <> " us")
  io.println("\nStage timings:")

  list.each(context.stage_timings, fn(timing) {
    io.println(
      "  "
      <> timing.stage_name
      <> ": "
      <> int.to_string(timing.duration_microseconds)
      <> " us",
    )
  })

  io.println("")
}

fn log_pipeline_summary(context: ExecutionContext) -> Nil {
  let total_stages = list.length(context.stage_timings)
  let total_duration =
    list.fold(context.stage_timings, 0, fn(acc, timing) {
      acc + timing.duration_microseconds
    })

  io.println(
    "[Pipeline] Completed "
    <> int.to_string(total_stages)
    <> " stages in "
    <> int.to_string(total_duration)
    <> " us",
  )
}

fn log_pipeline_error(error: ExecutionError) -> Nil {
  io.println("\n=== Pipeline Execution Error ===")

  case error {
    StageExecutionError(name, index, stage_error, context) -> {
      io.println(
        "Failed at stage: "
        <> name
        <> " (index: "
        <> int.to_string(index)
        <> ")",
      )
      io.println("Error: " <> stage_error_to_string(stage_error))
      io.println(
        "\nCompleted stages: "
        <> int.to_string(list.length(context.stage_timings)),
      )
    }
    EmptyPipelineExecutionError -> {
      io.println("Error: Cannot execute an empty pipeline")
    }
  }

  io.println("")
}

fn stage_error_to_string(error: StageError) -> String {
  error.stage_error_to_string(error)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Context Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the total execution time from a context in microseconds
///
pub fn total_duration(context: ExecutionContext) -> Int {
  list.fold(context.stage_timings, 0, fn(acc, timing) {
    acc + timing.duration_microseconds
  })
}

/// Gets the total execution time from a context in milliseconds
///
pub fn total_duration_ms(context: ExecutionContext) -> Int {
  time.microseconds_to_milliseconds(total_duration(context))
}

/// Gets the number of completed stages from a context
///
pub fn completed_stages_count(context: ExecutionContext) -> Int {
  list.length(context.stage_timings)
}

/// Gets timing for a specific stage by name
///
pub fn get_stage_timing(
  context: ExecutionContext,
  stage_name: String,
) -> Result(StageTiming, Nil) {
  list.find(context.stage_timings, fn(timing) { timing.stage_name == stage_name })
}

/// Gets the slowest stage from a context
///
pub fn slowest_stage(context: ExecutionContext) -> Result(StageTiming, Nil) {
  case context.stage_timings {
    [] -> Error(Nil)
    [first, ..rest] -> {
      Ok(
        list.fold(rest, first, fn(slowest, timing) {
          case timing.duration_microseconds > slowest.duration_microseconds {
            True -> timing
            False -> slowest
          }
        }),
      )
    }
  }
}

/// Creates an empty execution context (for testing)
///
pub fn empty_context() -> ExecutionContext {
  ExecutionContext(
    started_at: time.now_microseconds(),
    stage_timings: [],
    intermediate_results: [],
  )
}
