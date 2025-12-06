import gleam/list
import gleam/option

import gleeunit
import gleeunit/should

import aether/pipeline/error

pub fn main() -> Nil {
  gleeunit.main()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Error Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_error_creation_test() {
  let processing_error = error.ProcessingError("Test error", option.None)
  let validation_error = error.ValidationError("Invalid input")
  let timeout_error = error.TimeoutError("Operation timed out", 5000)
  let config_error = error.ConfigurationError("Missing parameter")

  // Test error creation
  processing_error
  |> should.equal(error.ProcessingError("Test error", option.None))
  validation_error |> should.equal(error.ValidationError("Invalid input"))
  timeout_error |> should.equal(error.TimeoutError("Operation timed out", 5000))
  config_error |> should.equal(error.ConfigurationError("Missing parameter"))
}

pub fn stage_error_string_conversion_test() {
  let processing_error_no_cause =
    error.ProcessingError("Test error", option.None)
  let validation_error = error.ValidationError("Invalid input")
  let timeout_error = error.TimeoutError("Operation timed out", 5000)
  let config_error = error.ConfigurationError("Missing parameter")

  error.stage_error_to_string(processing_error_no_cause)
  |> should.equal("ProcessingError: Test error")

  error.stage_error_to_string(validation_error)
  |> should.equal("ValidationError: Invalid input")

  error.stage_error_to_string(timeout_error)
  |> should.equal("TimeoutError: Operation timed out (5000ms)")

  error.stage_error_to_string(config_error)
  |> should.equal("ConfigurationError: Missing parameter")
}

pub fn stage_error_helper_functions_test() {
  let processing_error = error.processing_error("Test error", option.None)
  let validation_error = error.validation_error("Invalid input")
  let timeout_error = error.timeout_error("Timeout", 1000)
  let config_error = error.configuration_error("Bad config")

  processing_error
  |> should.equal(error.ProcessingError("Test error", option.None))

  validation_error
  |> should.equal(error.ValidationError("Invalid input"))

  timeout_error
  |> should.equal(error.TimeoutError("Timeout", 1000))

  config_error
  |> should.equal(error.ConfigurationError("Bad config"))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Error Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_error_creation_test() {
  let stage_error = error.ValidationError("Stage failed")
  let stage_failure = error.StageFailure("test_stage", 0, stage_error)
  let composition_error =
    error.CompositionError("Type mismatch", "String", "Int")
  let empty_error = error.EmptyPipelineError
  let execution_error = error.ExecutionError("General failure")

  stage_failure
  |> should.equal(error.StageFailure(
    "test_stage",
    0,
    error.ValidationError("Stage failed"),
  ))

  composition_error
  |> should.equal(error.CompositionError("Type mismatch", "String", "Int"))

  empty_error |> should.equal(error.EmptyPipelineError)
  execution_error |> should.equal(error.ExecutionError("General failure"))
}

pub fn pipeline_error_string_conversion_test() {
  let stage_error = error.ValidationError("Invalid data")
  let stage_failure = error.StageFailure("validate", 0, stage_error)
  let composition_error =
    error.CompositionError("Type mismatch", "String", "Int")
  let empty_error = error.EmptyPipelineError
  let execution_error = error.ExecutionError("Something went wrong")

  error.pipeline_error_to_string(stage_failure)
  |> should.equal(
    "StageFailure at 'validate' (index 0): ValidationError: Invalid data",
  )

  error.pipeline_error_to_string(composition_error)
  |> should.equal(
    "CompositionError: Type mismatch (expected: String, actual: Int)",
  )

  error.pipeline_error_to_string(empty_error)
  |> should.equal("EmptyPipelineError: Cannot execute an empty pipeline")

  error.pipeline_error_to_string(execution_error)
  |> should.equal("ExecutionError: Something went wrong")
}

pub fn pipeline_error_helper_functions_test() {
  let stage_err = error.validation_error("Bad input")
  let stage_failure = error.stage_failure("process", 1, stage_err)
  let composition_error = error.composition_error("Bad types", "Int", "String")

  stage_failure
  |> should.equal(error.StageFailure(
    "process",
    1,
    error.ValidationError("Bad input"),
  ))

  composition_error
  |> should.equal(error.CompositionError("Bad types", "Int", "String"))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Complex Error Scenarios
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn nested_error_scenarios_test() {
  // Test stage failure with processing error
  let processing_error =
    error.ProcessingError("Database operation failed", option.None)
  let stage_failure = error.StageFailure("save_to_db", 2, processing_error)

  error.pipeline_error_to_string(stage_failure)
  |> should.equal(
    "StageFailure at 'save_to_db' (index 2): ProcessingError: Database operation failed",
  )

  // Test composition error with detailed type information
  let complex_composition_error =
    error.CompositionError(
      "Cannot compose stages",
      "Pipeline(String, User)",
      "Pipeline(Int, User)",
    )

  error.pipeline_error_to_string(complex_composition_error)
  |> should.equal(
    "CompositionError: Cannot compose stages (expected: Pipeline(String, User), actual: Pipeline(Int, User))",
  )
}

pub fn error_pattern_matching_test() {
  let errors = [
    error.ValidationError("Invalid input"),
    error.ProcessingError("Processing failed", option.None),
    error.TimeoutError("Too slow", 5000),
    error.ConfigurationError("Bad config"),
  ]

  let validation_count =
    list.fold(errors, 0, fn(acc, err) {
      case err {
        error.ValidationError(_) -> acc + 1
        _ -> acc
      }
    })

  let processing_count =
    list.fold(errors, 0, fn(acc, err) {
      case err {
        error.ProcessingError(_, _) -> acc + 1
        _ -> acc
      }
    })

  validation_count |> should.equal(1)
  processing_count |> should.equal(1)
}
