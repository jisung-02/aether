import gleam/option
import gleam/string

import gleeunit
import gleeunit/should

import aether/pipeline/stage
import aether/pipeline/error

pub fn main() -> Nil {
  gleeunit.main()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_creation_test() {
  let simple_stage = stage.new("uppercase", fn(input) { Ok(string.uppercase(input)) })

  should.equal(simple_stage.name, "uppercase")
  should.equal(simple_stage.metadata, option.None)

  // Test the stage function works
  let result = simple_stage.process("hello")
  should.equal(result, Ok("HELLO"))
}

pub fn stage_with_metadata_creation_test() {
  let metadata = stage.StageMetadata(
    description: "Converts string to uppercase",
    version: option.Some("1.0.0"),
    tags: ["string", "transformation"],
    config: option.None,
  )

  let stage_with_metadata = stage.new_with_metadata("uppercase",
    fn(input) { Ok(string.uppercase(input)) }, metadata)

  should.equal(stage_with_metadata.name, "uppercase")
  should.equal(stage_with_metadata.metadata, option.Some(metadata))

  // Test the stage function works
  let result = stage_with_metadata.process("hello")
  should.equal(result, Ok("HELLO"))
}

pub fn stage_with_added_metadata_test() {
  let simple_stage = stage.new("trim", fn(input) { Ok(string.trim(input)) })

  let metadata = stage.StageMetadata(
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
  let failing_stage = stage.new("failing", fn(_input) {
    Error(error.validation_error("Always fails"))
  })

  let result = failing_stage.process("anything")
  case result {
    Ok(_) -> panic as "Expected error but got success"
    Error(error.ValidationError(message)) -> should.equal(message, "Always fails")
    Error(_) -> panic as "Expected ValidationError but got different error"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Metadata Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_metadata_creation_test() {
  let metadata = stage.StageMetadata(
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
  let minimal_metadata = stage.StageMetadata(
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

  let metadata = stage.StageMetadata(
    description: "Test metadata",
    version: option.Some("2.0.0"),
    tags: ["test"],
    config: option.None,
  )

  let stage_with_metadata = stage.new_with_metadata("meta", fn(x) { Ok(x) }, metadata)
  should.equal(stage.get_metadata(stage_with_metadata), option.Some(metadata))
}

pub fn stage_get_description_test() {
  let simple_stage = stage.new("simple", fn(x) { Ok(x) })
  should.equal(stage.get_description(simple_stage), option.None)

  let metadata = stage.StageMetadata(
    description: "A test stage for testing",
    version: option.Some("1.0.0"),
    tags: ["test"],
    config: option.None,
  )

  let stage_with_metadata = stage.new_with_metadata("test", fn(x) { Ok(x) }, metadata)
  should.equal(stage.get_description(stage_with_metadata), option.Some("A test stage for testing"))
}

pub fn stage_get_version_test() {
  let simple_stage = stage.new("simple", fn(x) { Ok(x) })
  should.equal(stage.get_version(simple_stage), option.None)

  let metadata_with_version = stage.StageMetadata(
    description: "Versioned stage",
    version: option.Some("3.2.1"),
    tags: ["versioned"],
    config: option.None,
  )

  let stage_with_version = stage.new_with_metadata("versioned", fn(x) { Ok(x) }, metadata_with_version)
  should.equal(stage.get_version(stage_with_version), option.Some("3.2.1"))

  let metadata_without_version = stage.StageMetadata(
    description: "Unversioned stage",
    version: option.None,
    tags: ["unversioned"],
    config: option.None,
  )

  let stage_without_version = stage.new_with_metadata("unversioned", fn(x) { Ok(x) }, metadata_without_version)
  should.equal(stage.get_version(stage_without_version), option.None)
}

pub fn stage_get_tags_test() {
  let simple_stage = stage.new("simple", fn(x) { Ok(x) })
  should.equal(stage.get_tags(simple_stage), [])

  let metadata_with_tags = stage.StageMetadata(
    description: "Tagged stage",
    version: option.Some("1.0.0"),
    tags: ["string", "processing", "utility"],
    config: option.None,
  )

  let stage_with_tags = stage.new_with_metadata("tagged", fn(x) { Ok(x) }, metadata_with_tags)
  should.equal(stage.get_tags(stage_with_tags), ["string", "processing", "utility"])

  let metadata_empty_tags = stage.StageMetadata(
    description: "Empty tags stage",
    version: option.Some("1.0.0"),
    tags: [],
    config: option.None,
  )

  let stage_empty_tags = stage.new_with_metadata("empty_tags", fn(x) { Ok(x) }, metadata_empty_tags)
  should.equal(stage.get_tags(stage_empty_tags), [])
}

pub fn stage_get_config_test() {
  let simple_stage = stage.new("simple", fn(x) { Ok(x) })
  should.equal(stage.get_config(simple_stage), option.None)

  let metadata_with_config = stage.StageMetadata(
    description: "Configured stage",
    version: option.Some("1.0.0"),
    tags: ["configured"],
    config: option.Some("timeout=5000; retries=3"),
  )

  let stage_with_config = stage.new_with_metadata("configured", fn(x) { Ok(x) }, metadata_with_config)
  should.equal(stage.get_config(stage_with_config), option.Some("timeout=5000; retries=3"))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Complex Stage Scenarios
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stage_chaining_test() {
  let trim_stage = stage.new("trim", fn(input) { Ok(string.trim(input)) })
  let uppercase_stage = stage.new("uppercase", fn(input) { Ok(string.uppercase(input)) })

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
  let validate_stage = stage.new("validate", fn(input) {
    case input {
      "" -> Error(error.validation_error("Input cannot be empty"))
      _ -> Ok(input)
    }
  })

  let process_stage = stage.new("process", fn(input) { Ok("processed: " <> input) })

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
    Error(error.ValidationError(message)) -> should.equal(message, "Input cannot be empty")
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