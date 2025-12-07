import gleam/int
import gleam/list
import gleam/option

import gleeunit
import gleeunit/should

import aether/pipeline/error
import aether/pipeline/executor
import aether/pipeline/pipeline
import aether/pipeline/stage

pub fn main() -> Nil {
  gleeunit.main()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Basic Execution Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn execute_with_context_single_stage_test() {
  let add_one = stage.new("add_one", fn(x: Int) { Ok(x + 1) })

  let pipe = pipeline.from_stage(add_one)

  let assert Ok(result) = executor.execute_with_context(pipe, 5)

  result.output
  |> should.equal(6)

  list.length(result.context.stage_timings)
  |> should.equal(1)
}

pub fn execute_with_context_multiple_stages_test() {
  let add_one = stage.new("add_one", fn(x: Int) { Ok(x + 1) })
  let double = stage.new("double", fn(x: Int) { Ok(x * 2) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(add_one)
    |> pipeline.pipe(double)

  let assert Ok(result) = executor.execute_with_context(pipe, 5)

  // (5 + 1) * 2 = 12
  result.output
  |> should.equal(12)

  list.length(result.context.stage_timings)
  |> should.equal(2)
}

pub fn execute_with_context_three_stages_test() {
  let add_one = stage.new("add_one", fn(x: Int) { Ok(x + 1) })
  let double = stage.new("double", fn(x: Int) { Ok(x * 2) })
  let to_string = stage.new("to_string", fn(x: Int) { Ok(int.to_string(x)) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(add_one)
    |> pipeline.pipe(double)
    |> pipeline.pipe(to_string)

  let assert Ok(result) = executor.execute_with_context(pipe, 5)

  // (5 + 1) * 2 = 12 -> "12"
  result.output
  |> should.equal("12")

  list.length(result.context.stage_timings)
  |> should.equal(3)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Timing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn execution_timing_recorded_test() {
  let simple_stage = stage.new("simple", fn(x: Int) { Ok(x) })

  let pipe = pipeline.from_stage(simple_stage)

  let assert Ok(result) = executor.execute_with_context(pipe, 42)

  let assert [timing] = result.context.stage_timings

  timing.stage_name
  |> should.equal("simple")

  // Duration should be non-negative
  { timing.duration_microseconds >= 0 }
  |> should.be_true()

  // End time should be >= start time
  { timing.end_time >= timing.start_time }
  |> should.be_true()
}

pub fn execution_timing_multiple_stages_test() {
  let stage1 = stage.new("stage1", fn(x: Int) { Ok(x + 1) })
  let stage2 = stage.new("stage2", fn(x: Int) { Ok(x * 2) })
  let stage3 = stage.new("stage3", fn(x: Int) { Ok(x - 1) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(stage1)
    |> pipeline.pipe(stage2)
    |> pipeline.pipe(stage3)

  let assert Ok(result) = executor.execute_with_context(pipe, 10)

  // Verify all timings are recorded
  let timings = result.context.stage_timings

  list.length(timings)
  |> should.equal(3)

  // Check stage names in order
  list.map(timings, fn(t) { t.stage_name })
  |> should.equal(["stage1", "stage2", "stage3"])

  // Check all durations are non-negative
  should.be_true(list.all(timings, fn(t) { t.duration_microseconds >= 0 }))
}

pub fn total_duration_test() {
  let stage1 = stage.new("stage1", fn(x: Int) { Ok(x + 1) })
  let stage2 = stage.new("stage2", fn(x: Int) { Ok(x * 2) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(stage1)
    |> pipeline.pipe(stage2)

  let assert Ok(result) = executor.execute_with_context(pipe, 5)

  // Total duration should be sum of all stage durations
  let manual_total =
    list.fold(result.context.stage_timings, 0, fn(acc, t) {
      acc + t.duration_microseconds
    })

  executor.total_duration(result.context)
  |> should.equal(manual_total)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Context Preservation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_context_preservation_test() {
  let ok_stage = stage.new("ok", fn(x: Int) { Ok(x + 1) })
  let error_stage =
    stage.new("error", fn(_: Int) {
      Error(error.processing_error("Intentional error", option.None))
    })
  let never_reached = stage.new("never", fn(x: Int) { Ok(x) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(ok_stage)
    |> pipeline.pipe(error_stage)
    |> pipeline.pipe(never_reached)

  let assert Error(exec_error) = executor.execute_with_context(pipe, 5)

  case exec_error {
    executor.StageExecutionError(name, index, _, context) -> {
      name
      |> should.equal("error")

      index
      |> should.equal(1)

      // Context should have timing for first stage only
      list.length(context.stage_timings)
      |> should.equal(1)

      // First stage should have been recorded
      let assert [timing] = context.stage_timings
      timing.stage_name
      |> should.equal("ok")
    }
    executor.EmptyPipelineExecutionError -> {
      panic as "Expected StageExecutionError"
    }
  }
}

pub fn error_at_first_stage_test() {
  let error_stage =
    stage.new("failing", fn(_: Int) {
      Error(error.validation_error("Validation failed"))
    })
  let never_reached = stage.new("never", fn(x: Int) { Ok(x) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(error_stage)
    |> pipeline.pipe(never_reached)

  let assert Error(exec_error) = executor.execute_with_context(pipe, 42)

  case exec_error {
    executor.StageExecutionError(name, index, _, context) -> {
      name
      |> should.equal("failing")

      index
      |> should.equal(0)

      // No stages completed
      list.length(context.stage_timings)
      |> should.equal(0)
    }
    executor.EmptyPipelineExecutionError -> {
      panic as "Expected StageExecutionError"
    }
  }
}

pub fn empty_pipeline_error_test() {
  let empty_pipe = pipeline.new()

  let assert Error(exec_error) = executor.execute_with_context(empty_pipe, 42)

  case exec_error {
    executor.EmptyPipelineExecutionError -> should.be_true(True)
    _ -> panic as "Expected EmptyPipelineExecutionError"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Intermediate Results Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn intermediate_results_tracked_test() {
  let add_one = stage.new("add_one", fn(x: Int) { Ok(x + 1) })
  let double = stage.new("double", fn(x: Int) { Ok(x * 2) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(add_one)
    |> pipeline.pipe(double)

  let assert Ok(result) = executor.execute_with_context(pipe, 5)

  // Should have 2 intermediate results
  list.length(result.context.intermediate_results)
  |> should.equal(2)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Context Utility Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn completed_stages_count_test() {
  let stage1 = stage.new("stage1", fn(x: Int) { Ok(x + 1) })
  let stage2 = stage.new("stage2", fn(x: Int) { Ok(x * 2) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(stage1)
    |> pipeline.pipe(stage2)

  let assert Ok(result) = executor.execute_with_context(pipe, 5)

  executor.completed_stages_count(result.context)
  |> should.equal(2)
}

pub fn get_stage_timing_found_test() {
  let stage1 = stage.new("stage1", fn(x: Int) { Ok(x + 1) })
  let stage2 = stage.new("target", fn(x: Int) { Ok(x * 2) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(stage1)
    |> pipeline.pipe(stage2)

  let assert Ok(result) = executor.execute_with_context(pipe, 5)

  let assert Ok(timing) = executor.get_stage_timing(result.context, "target")

  timing.stage_name
  |> should.equal("target")
}

pub fn get_stage_timing_not_found_test() {
  let stage1 = stage.new("stage1", fn(x: Int) { Ok(x + 1) })

  let pipe = pipeline.from_stage(stage1)

  let assert Ok(result) = executor.execute_with_context(pipe, 5)

  let assert Error(Nil) =
    executor.get_stage_timing(result.context, "nonexistent")

  should.be_true(True)
}

pub fn empty_context_test() {
  let context = executor.empty_context()

  list.length(context.stage_timings)
  |> should.equal(0)

  list.length(context.intermediate_results)
  |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Run Function Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn run_success_test() {
  let add_one = stage.new("add_one", fn(x: Int) { Ok(x + 1) })
  let double = stage.new("double", fn(x: Int) { Ok(x * 2) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(add_one)
    |> pipeline.pipe(double)

  let assert Ok(result) = executor.run(pipe, 5)

  // (5 + 1) * 2 = 12
  result
  |> should.equal(12)
}

pub fn run_error_test() {
  let error_stage =
    stage.new("failing", fn(_: Int) {
      Error(error.validation_error("Always fails"))
    })

  let pipe = pipeline.from_stage(error_stage)

  let assert Error(exec_error) = executor.run(pipe, 42)

  case exec_error {
    executor.StageExecutionError(name, _, _, _) -> {
      name
      |> should.equal("failing")
    }
    _ -> panic as "Expected StageExecutionError"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Logging Tests (Basic Verification)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn execute_with_logging_silent_test() {
  let add_one = stage.new("add_one", fn(x: Int) { Ok(x + 1) })

  let pipe = pipeline.from_stage(add_one)

  // Silent mode should not print anything, just return result
  let assert Ok(result) = executor.execute_with_logging(pipe, 5, executor.Silent)

  result
  |> should.equal(6)
}

pub fn execute_with_logging_error_test() {
  let error_stage =
    stage.new("failing", fn(_: Int) {
      Error(error.validation_error("Test error"))
    })

  let pipe = pipeline.from_stage(error_stage)

  // ErrorOnly mode should log error (we're just verifying it doesn't crash)
  let assert Error(_) =
    executor.execute_with_logging(pipe, 42, executor.ErrorOnly)

  should.be_true(True)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Type Transformation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn type_transformation_test() {
  // Int -> String transformation
  let to_string = stage.new("to_string", fn(x: Int) { Ok(int.to_string(x)) })

  let pipe = pipeline.from_stage(to_string)

  let assert Ok(result) = executor.execute_with_context(pipe, 42)

  result.output
  |> should.equal("42")
}

pub fn complex_type_transformation_test() {
  // Int -> String -> Int transformation
  let double = stage.new("double", fn(x: Int) { Ok(x * 2) })
  let to_string = stage.new("to_string", fn(x: Int) { Ok(int.to_string(x)) })
  let length = stage.new("length", fn(s: String) { Ok(string_length(s)) })

  let pipe =
    pipeline.new()
    |> pipeline.pipe(double)
    |> pipeline.pipe(to_string)
    |> pipeline.pipe(length)

  let assert Ok(result) = executor.execute_with_context(pipe, 12345)

  // 12345 * 2 = 24690 -> "24690" -> length 5
  result.output
  |> should.equal(5)
}

// Helper function
fn string_length(s: String) -> Int {
  string_byte_size(s)
}

@external(erlang, "erlang", "byte_size")
fn string_byte_size(s: String) -> Int
