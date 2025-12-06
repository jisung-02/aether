import gleam/int
import gleam/option
import gleam/string

import gleeunit
import gleeunit/should

import aether/pipeline/error
import aether/pipeline/stage

pub fn main() -> Nil {
  gleeunit.main()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_creation_test() {
  let simple_stage =
    stage.new("uppercase", fn(input) { Ok(string.uppercase(input)) })

  should.equal(simple_stage.name, "uppercase")
  should.equal(simple_stage.metadata, option.None)

  // Test the stage function works
  let result = simple_stage.process("hello")
  should.equal(result, Ok("HELLO"))
}

pub fn stage_with_metadata_creation_test() {
  let metadata =
    stage.StageMetadata(
      description: "Converts string to uppercase",
      version: option.Some("1.0.0"),
      tags: ["string", "transformation"],
      config: option.None,
    )

  let stage_with_metadata =
    stage.new_with_metadata(
      "uppercase",
      fn(input) { Ok(string.uppercase(input)) },
      metadata,
    )

  should.equal(stage_with_metadata.name, "uppercase")
  should.equal(stage_with_metadata.metadata, option.Some(metadata))

  // Test the stage function works
  let result = stage_with_metadata.process("hello")
  should.equal(result, Ok("HELLO"))
}

pub fn stage_with_added_metadata_test() {
  let simple_stage = stage.new("trim", fn(input) { Ok(string.trim(input)) })

  let metadata =
    stage.StageMetadata(
      description: "Trims whitespace from strings",
      version: option.Some("1.0.0"),
      tags: ["string", "utility"],
      config: option.Some("strict=true"),
    )

  let stage_with_metadata = stage.with_metadata(simple_stage, metadata)

  should.equal(stage_with_metadata.name, "trim")
  should.equal(stage_with_metadata.metadata, option.Some(metadata))

  // Test the stage function still works after adding metadata
  let result = stage_with_metadata.process("  hello  ")
  should.equal(result, Ok("hello"))
}

pub fn stage_with_processing_error_test() {
  let failing_stage =
    stage.new("failing", fn(_input) {
      Error(error.validation_error("Always fails"))
    })

  let result = failing_stage.process("anything")
  case result {
    Ok(_) -> panic as "Expected error but got success"
    Error(error.ValidationError(message)) ->
      should.equal(message, "Always fails")
    Error(_) -> panic as "Expected ValidationError but got different error"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Metadata Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_metadata_creation_test() {
  let metadata =
    stage.StageMetadata(
      description: "Test stage",
      version: option.Some("1.0.0"),
      tags: ["test", "example"],
      config: option.Some("test=true"),
    )

  should.equal(metadata.description, "Test stage")
  should.equal(metadata.version, option.Some("1.0.0"))
  should.equal(metadata.tags, ["test", "example"])
  should.equal(metadata.config, option.Some("test=true"))
}

pub fn stage_metadata_minimal_test() {
  let minimal_metadata =
    stage.StageMetadata(
      description: "Minimal stage",
      version: option.None,
      tags: [],
      config: option.None,
    )

  should.equal(minimal_metadata.description, "Minimal stage")
  should.equal(minimal_metadata.version, option.None)
  should.equal(minimal_metadata.tags, [])
  should.equal(minimal_metadata.config, option.None)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Access Function Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_get_name_test() {
  let test_stage = stage.new("test_stage", fn(x) { Ok(x) })
  should.equal(stage.get_name(test_stage), "test_stage")
}

pub fn stage_get_metadata_test() {
  let simple_stage = stage.new("simple", fn(x) { Ok(x) })
  should.equal(stage.get_metadata(simple_stage), option.None)

  let metadata =
    stage.StageMetadata(
      description: "Test metadata",
      version: option.Some("2.0.0"),
      tags: ["test"],
      config: option.None,
    )

  let stage_with_metadata =
    stage.new_with_metadata("meta", fn(x) { Ok(x) }, metadata)
  should.equal(stage.get_metadata(stage_with_metadata), option.Some(metadata))
}

pub fn stage_get_description_test() {
  let simple_stage = stage.new("simple", fn(x) { Ok(x) })
  should.equal(stage.get_description(simple_stage), option.None)

  let metadata =
    stage.StageMetadata(
      description: "A test stage for testing",
      version: option.Some("1.0.0"),
      tags: ["test"],
      config: option.None,
    )

  let stage_with_metadata =
    stage.new_with_metadata("test", fn(x) { Ok(x) }, metadata)
  should.equal(
    stage.get_description(stage_with_metadata),
    option.Some("A test stage for testing"),
  )
}

pub fn stage_get_version_test() {
  let simple_stage = stage.new("simple", fn(x) { Ok(x) })
  should.equal(stage.get_version(simple_stage), option.None)

  let metadata_with_version =
    stage.StageMetadata(
      description: "Versioned stage",
      version: option.Some("3.2.1"),
      tags: ["versioned"],
      config: option.None,
    )

  let stage_with_version =
    stage.new_with_metadata("versioned", fn(x) { Ok(x) }, metadata_with_version)
  should.equal(stage.get_version(stage_with_version), option.Some("3.2.1"))

  let metadata_without_version =
    stage.StageMetadata(
      description: "Unversioned stage",
      version: option.None,
      tags: ["unversioned"],
      config: option.None,
    )

  let stage_without_version =
    stage.new_with_metadata(
      "unversioned",
      fn(x) { Ok(x) },
      metadata_without_version,
    )
  should.equal(stage.get_version(stage_without_version), option.None)
}

pub fn stage_get_tags_test() {
  let simple_stage = stage.new("simple", fn(x) { Ok(x) })
  should.equal(stage.get_tags(simple_stage), [])

  let metadata_with_tags =
    stage.StageMetadata(
      description: "Tagged stage",
      version: option.Some("1.0.0"),
      tags: ["string", "processing", "utility"],
      config: option.None,
    )

  let stage_with_tags =
    stage.new_with_metadata("tagged", fn(x) { Ok(x) }, metadata_with_tags)
  should.equal(stage.get_tags(stage_with_tags), [
    "string",
    "processing",
    "utility",
  ])

  let metadata_empty_tags =
    stage.StageMetadata(
      description: "Empty tags stage",
      version: option.Some("1.0.0"),
      tags: [],
      config: option.None,
    )

  let stage_empty_tags =
    stage.new_with_metadata("empty_tags", fn(x) { Ok(x) }, metadata_empty_tags)
  should.equal(stage.get_tags(stage_empty_tags), [])
}

pub fn stage_get_config_test() {
  let simple_stage = stage.new("simple", fn(x) { Ok(x) })
  should.equal(stage.get_config(simple_stage), option.None)

  let metadata_with_config =
    stage.StageMetadata(
      description: "Configured stage",
      version: option.Some("1.0.0"),
      tags: ["configured"],
      config: option.Some("timeout=5000; retries=3"),
    )

  let stage_with_config =
    stage.new_with_metadata("configured", fn(x) { Ok(x) }, metadata_with_config)
  should.equal(
    stage.get_config(stage_with_config),
    option.Some("timeout=5000; retries=3"),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Complex Stage Scenarios
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_chaining_test() {
  let trim_stage = stage.new("trim", fn(input) { Ok(string.trim(input)) })
  let uppercase_stage =
    stage.new("uppercase", fn(input) { Ok(string.uppercase(input)) })

  // Simulate manual chaining
  let trimmed_result = trim_stage.process("  hello world  ")
  case trimmed_result {
    Ok(trimmed) -> {
      let final_result = uppercase_stage.process(trimmed)
      should.equal(final_result, Ok("HELLO WORLD"))
    }
    Error(_) -> panic as "Trim stage should not fail"
  }
}

pub fn stage_error_propagation_test() {
  let validate_stage =
    stage.new("validate", fn(input) {
      case input {
        "" -> Error(error.validation_error("Input cannot be empty"))
        _ -> Ok(input)
      }
    })

  let process_stage =
    stage.new("process", fn(input) { Ok("processed: " <> input) })

  // Test with valid input
  let valid_result = validate_stage.process("hello")
  case valid_result {
    Ok(valid) -> {
      let final_result = process_stage.process(valid)
      should.equal(final_result, Ok("processed: hello"))
    }
    Error(_) -> panic as "Validation should pass for non-empty input"
  }

  // Test with invalid input
  let invalid_result = validate_stage.process("")
  case invalid_result {
    Ok(_) -> panic as "Validation should fail for empty input"
    Error(error.ValidationError(message)) ->
      should.equal(message, "Input cannot be empty")
    Error(_) -> panic as "Expected ValidationError"
  }
}

pub fn stage_type_inference_test() {
  // Test that the compiler correctly infers types
  let int_stage = stage.new("add_one", fn(x) { Ok(x + 1) })
  let string_stage = stage.new("exclaim", fn(s) { Ok(s <> "!") })

  let int_result = int_stage.process(41)
  should.equal(int_result, Ok(42))

  let string_result = string_stage.process("hello")
  should.equal(string_result, Ok("hello!"))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Execution Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_execute_test() {
  let add_stage = stage.new("add_five", fn(x) { Ok(x + 5) })

  let result = stage.execute(add_stage, 10)
  should.equal(result, Ok(15))

  let zero_result = stage.execute(add_stage, 0)
  should.equal(zero_result, Ok(5))
}

pub fn stage_execute_with_error_test() {
  let validate_stage =
    stage.new("validate_positive", fn(x) {
      case x > 0 {
        True -> Ok(x)
        False -> Error(error.validation_error("Number must be positive"))
      }
    })

  let success_result = stage.execute(validate_stage, 5)
  should.equal(success_result, Ok(5))

  let error_result = stage.execute(validate_stage, -1)
  case error_result {
    Ok(_) -> panic as "Expected error for negative input"
    Error(error.ValidationError(message)) ->
      should.equal(message, "Number must be positive")
    Error(_) -> panic as "Expected ValidationError"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Transformation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_map_output_test() {
  let double_stage = stage.new("double", fn(x) { Ok(x * 2) })

  let stringified_stage =
    stage.map_output(double_stage, fn(x) { int.to_string(x) })

  should.equal(stringified_stage.name, "double_mapped")

  let result = stage.execute(stringified_stage, 5)
  should.equal(result, Ok("10"))
}

pub fn stage_map_output_preserves_error_test() {
  let failing_stage =
    stage.new("failing", fn(_x) {
      Error(error.processing_error("Always fails", option.None))
    })

  let mapped_stage = stage.map_output(failing_stage, fn(x) { x + 1 })

  let result = stage.execute(mapped_stage, 42)
  case result {
    Ok(_) -> panic as "Expected error to be preserved"
    Error(error.ProcessingError(message, _)) ->
      should.equal(message, "Always fails")
    Error(_) -> panic as "Expected ProcessingError"
  }
}

pub fn stage_map_error_test() {
  let validate_stage =
    stage.new("validate", fn(x) {
      case x >= 0 {
        True -> Ok(x)
        False -> Error(error.validation_error("Negative number"))
      }
    })

  let error_converter =
    stage.map_error(validate_stage, fn(err) {
      case err {
        error.ValidationError(msg) -> "Validation failed: " <> msg
        _ -> "Unknown error"
      }
    })

  should.equal(error_converter.name, "validate_error_mapped")

  // Test success case - errors are wrapped in Result
  let success_result = stage.execute(error_converter, 5)
  should.equal(success_result, Ok(Ok(5)))

  // Test error case - errors are transformed and wrapped
  let error_result = stage.execute(error_converter, -1)
  should.equal(error_result, Ok(Error("Validation failed: Negative number")))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Composition Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_compose_test() {
  let add_one = stage.new("add_one", fn(x) { Ok(x + 1) })
  let multiply_by_two = stage.new("multiply_by_two", fn(x) { Ok(x * 2) })

  let composed_stage = stage.compose(add_one, multiply_by_two)

  should.equal(composed_stage.name, "add_one_then_multiply_by_two")
  should.equal(composed_stage.metadata, option.None)

  // Test composition: (input + 1) * 2
  let result = stage.execute(composed_stage, 5)
  should.equal(result, Ok(12))
  // (5 + 1) * 2 = 12
}

pub fn stage_compose_error_propagation_test() {
  let validate_stage =
    stage.new("validate_positive", fn(x) {
      case x > 0 {
        True -> Ok(x)
        False -> Error(error.validation_error("Must be positive"))
      }
    })

  let double_stage = stage.new("double", fn(x) { Ok(x * 2) })

  let composed_stage = stage.compose(validate_stage, double_stage)

  // Test successful composition
  let success_result = stage.execute(composed_stage, 5)
  should.equal(success_result, Ok(10))

  // Test error propagation - first stage fails
  let error_result = stage.execute(composed_stage, -1)
  case error_result {
    Ok(_) -> panic as "Expected error to propagate"
    Error(error.ValidationError(message)) ->
      should.equal(message, "Must be positive")
    Error(_) -> panic as "Expected ValidationError"
  }
}

pub fn stage_compose_with_types_test() {
  let string_to_int =
    stage.new("to_int", fn(s) {
      case int.parse(s) {
        Ok(num) -> Ok(num)
        Error(_) -> Error(error.validation_error("Invalid number"))
      }
    })

  let int_to_string = stage.new("to_string", fn(i) { Ok(int.to_string(i)) })

  let composed_stage = stage.compose(string_to_int, int_to_string)

  // Test successful round-trip
  let result = stage.execute(composed_stage, "42")
  should.equal(result, Ok("42"))

  // Test error in first stage
  let error_result = stage.execute(composed_stage, "invalid")
  case error_result {
    Ok(_) -> panic as "Expected error"
    Error(error.ValidationError(message)) ->
      should.equal(message, "Invalid number")
    Error(_) -> panic as "Expected ValidationError"
  }
}

pub fn stage_and_then_test() {
  let parse_stage =
    stage.new("parse", fn(s) {
      case int.parse(s) {
        Ok(num) -> Ok(num)
        Error(_) -> Error(error.validation_error("Parse error"))
      }
    })

  let conditional_stage =
    stage.and_then(parse_stage, fn(parsed_num) {
      case parsed_num % 2 == 0 {
        True -> stage.new("double_even", fn(x) { Ok(x * 2) })
        False -> stage.new("triple_odd", fn(x) { Ok(x * 3) })
      }
    })

  should.equal(conditional_stage.name, "parse_and_then")

  // Test even number - gets doubled
  let even_result = stage.execute(conditional_stage, "4")
  should.equal(even_result, Ok(8))
  // 4 * 2

  // Test odd number - gets tripled
  let odd_result = stage.execute(conditional_stage, "3")
  should.equal(odd_result, Ok(9))
  // 3 * 3

  // Test parse error
  let error_result = stage.execute(conditional_stage, "invalid")
  case error_result {
    Ok(_) -> panic as "Expected parse error"
    Error(error.ValidationError(message)) ->
      should.equal(message, "Parse error")
    Error(_) -> panic as "Expected ValidationError"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Advanced Scenarios
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_complex_pipeline_test() {
  let trim_stage = stage.new("trim", fn(s) { Ok(string.trim(s)) })
  let to_upper = stage.new("upper", fn(s) { Ok(string.uppercase(s)) })
  let reverse_stage = stage.new("reverse", fn(s) { Ok(string.reverse(s)) })

  // Build complex pipeline using composition
  let step1 = stage.compose(trim_stage, to_upper)
  let full_pipeline = stage.compose(step1, reverse_stage)

  // Test full pipeline: "  hello  " -> "HELLO" -> "OLLEH"
  let result = stage.execute(full_pipeline, "  hello  ")
  should.equal(result, Ok("OLLEH"))

  should.equal(full_pipeline.name, "trim_then_upper_then_reverse")
}

pub fn stage_error_handling_pipeline_test() {
  let validate_non_empty =
    stage.new("validate_non_empty", fn(s) {
      case string.length(s) > 0 {
        True -> Ok(s)
        False -> Error(error.validation_error("Empty string"))
      }
    })

  let validate_max_length =
    stage.new("validate_max_length", fn(s) {
      case string.length(s) <= 10 {
        True -> Ok(s)
        False -> Error(error.validation_error("String too long"))
      }
    })

  let process_stage = stage.new("process", fn(s) { Ok("processed: " <> s) })

  let validation_pipeline =
    stage.compose(validate_non_empty, validate_max_length)
  let full_pipeline = stage.compose(validation_pipeline, process_stage)

  // Test successful validation
  let valid_result = stage.execute(full_pipeline, "hello")
  should.equal(valid_result, Ok("processed: hello"))

  // Test empty string failure
  let empty_result = stage.execute(full_pipeline, "")
  case empty_result {
    Ok(_) -> panic as "Expected validation error"
    Error(error.ValidationError(message)) ->
      should.equal(message, "Empty string")
    Error(_) -> panic as "Expected ValidationError"
  }

  // Test too long string failure
  let long_result = stage.execute(full_pipeline, "this is way too long")
  case long_result {
    Ok(_) -> panic as "Expected validation error"
    Error(error.ValidationError(message)) ->
      should.equal(message, "String too long")
    Error(_) -> panic as "Expected ValidationError"
  }
}
