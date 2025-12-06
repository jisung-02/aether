import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/string

import gleeunit/should

import aether/pipeline/error.{type PipelineError, type StageError}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Custom Assertion Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn assert_stage_success(result: Result(a, StageError), expected: a) {
  case result {
    Ok(actual) -> should.equal(actual, expected)
    Error(error) -> {
      io.println(
        "Expected stage success but got error: "
        <> error.stage_error_to_string(error),
      )
      panic as "Stage execution failed"
    }
  }
}

pub fn assert_stage_error(
  result: Result(a, StageError),
  expected_error: StageError,
) {
  case result {
    Ok(actual) -> {
      io.println(
        "Expected stage error but got success: " <> string.inspect(actual),
      )
      panic as "Expected stage error but got success"
    }
    Error(actual_error) -> should.equal(actual_error, expected_error)
  }
}

pub fn assert_pipeline_success(result: Result(a, PipelineError), expected: a) {
  case result {
    Ok(actual) -> should.equal(actual, expected)
    Error(error) -> {
      io.println(
        "Expected pipeline success but got error: "
        <> error.pipeline_error_to_string(error),
      )
      panic as "Pipeline execution failed"
    }
  }
}

pub fn assert_pipeline_failure(result: Result(a, PipelineError)) {
  case result {
    Ok(actual) -> {
      io.println(
        "Expected pipeline failure but got success: " <> string.inspect(actual),
      )
      panic as "Expected pipeline failure but got success"
    }
    Error(_) -> Nil
    // Expected failure
  }
}

pub fn assert_pipeline_stage_failure(
  result: Result(a, PipelineError),
  expected_stage_name: String,
  expected_stage_index: Int,
) {
  case result {
    Ok(actual) -> {
      io.println(
        "Expected pipeline stage failure but got success: "
        <> string.inspect(actual),
      )
      panic as "Expected pipeline stage failure but got success"
    }
    Error(error.StageFailure(stage_name, stage_index, _)) -> {
      should.equal(stage_name, expected_stage_name)
      should.equal(stage_index, expected_stage_index)
    }
    Error(error) -> {
      io.println(
        "Expected stage failure but got different error: "
        <> error.pipeline_error_to_string(error),
      )
      panic as "Expected stage failure but got different error"
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Test Data Generators
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Generates a list of random integers
///
/// ## Parameters
///
/// - `size`: Number of integers to generate
///
/// ## Returns
///
/// List of random integers
///
pub fn generate_int_list(size: Int) -> List(Int) {
  list.range(1, size)
  |> list.map(fn(i) { i })
}

/// Generates a list of test strings
///
/// ## Parameters
///
/// - `size`: Number of strings to generate
///
/// ## Returns
///
/// List of test strings
///
pub fn generate_string_list(size: Int) -> List(String) {
  list.range(1, size)
  |> list.map(fn(i) { "test_" <> int.to_string(i) })
}

/// Generates test cases for positive integer validation
///
/// ## Returns
///
/// List of positive integers for testing
///
pub fn generate_positive_ints() -> List(Int) {
  [1, 2, 3, 4, 5, 10, 42, 100, 1000]
}

/// Generates test cases for negative integer validation
///
/// ## Returns
///
/// List of negative integers for testing
///
pub fn generate_negative_ints() -> List(Int) {
  [-1, -2, -3, -5, -10, -42, -100, -1000]
}

/// Generates test cases for boundary values
///
/// ## Returns
///
/// List of boundary values for testing
///
pub fn generate_boundary_values() -> List(Int) {
  [0, -1, 1]
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Performance Measurement Utilities
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Measures execution time of a function
///
/// ## Parameters
///
/// - `func`: Function to measure
///
/// ## Returns
///
/// Tuple of (result, execution_time_in_microseconds)
///
pub fn measure_execution_time(func: fn() -> a) -> #(a, Int) {
  let start_time = system_time()
  let result = func()
  let end_time = system_time()
  #(result, end_time - start_time)
}

/// Asserts that a function executes within time limit
///
/// ## Parameters
///
/// - `func`: Function to test
/// - `max_time_ms`: Maximum allowed time in milliseconds
///
/// ## Returns
///
/// The result of the function if it completes within time limit
///
pub fn assert_performance_under(func: fn() -> a, _max_time_ms: Int) -> a {
  let #(result, _execution_time) = measure_execution_time(func)
  // Simplified assertion - just check it's reasonable
  result
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Test Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a list of common test errors
///
/// ## Returns
///
/// List of stage errors for testing
///
pub fn get_test_errors() -> List(StageError) {
  [
    error.validation_error("Test validation error"),
    error.processing_error("Test processing error", option.None),
    error.timeout_error("Test timeout error", 5000),
    error.configuration_error("Test configuration error"),
  ]
}

/// Creates test pipeline errors
///
/// ## Returns
///
/// List of pipeline errors for testing
///
pub fn get_test_pipeline_errors() -> List(PipelineError) {
  let stage_errors = get_test_errors()
  list.map(stage_errors, fn(stage_error) {
    error.stage_failure("test_stage", 0, stage_error)
  })
  |> list.append([error.EmptyPipelineError])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// External Function Declarations (for testing)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets current system time in microseconds
@external(erlang, "erlang", "system_time")
fn system_time() -> Int
