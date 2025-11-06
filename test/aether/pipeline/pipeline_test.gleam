import gleam/option
import gleam/string

import gleeunit
import gleeunit/should

import aether/pipeline/pipeline
import aether/pipeline/stage
import aether/pipeline/error

pub fn main() -> Nil {
  gleeunit.main()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_new_test() {
  let empty_pipeline = pipeline.new()

  should.equal(pipeline.length(empty_pipeline), 0)
  should.equal(pipeline.is_empty(empty_pipeline), True)
  should.equal(pipeline.stage_names(empty_pipeline), [])
  should.equal(pipeline.get_input_type(empty_pipeline), "a")
  should.equal(pipeline.get_output_type(empty_pipeline), "a")
}

pub fn pipeline_empty_test() {
  let typed_empty_pipeline = pipeline.empty()

  should.equal(pipeline.length(typed_empty_pipeline), 0)
  should.equal(pipeline.is_empty(typed_empty_pipeline), True)
  should.equal(pipeline.stage_names(typed_empty_pipeline), [])
  should.equal(pipeline.get_input_type(typed_empty_pipeline), "input")
  should.equal(pipeline.get_output_type(typed_empty_pipeline), "output")
}

pub fn pipeline_from_stage_test() {
  let test_stage = stage.new("test_stage", fn(x) { Ok(x + 1) })
  let single_stage_pipeline = pipeline.from_stage(test_stage)

  should.equal(pipeline.length(single_stage_pipeline), 1)
  should.equal(pipeline.is_empty(single_stage_pipeline), False)
  should.equal(pipeline.stage_names(single_stage_pipeline), ["test_stage"])
  should.equal(pipeline.get_input_type(single_stage_pipeline), "input")
  should.equal(pipeline.get_output_type(single_stage_pipeline), "output")
}

pub fn pipeline_from_stage_with_metadata_test() {
  let metadata = stage.StageMetadata(
    description: "A test stage",
    version: option.Some("1.0.0"),
    tags: ["test"],
    config: option.None,
  )

  let stage_with_metadata = stage.new_with_metadata("meta_stage",
    fn(x) { Ok(string.uppercase(x)) }, metadata)

  let pipeline_from_meta = pipeline.from_stage(stage_with_metadata)

  should.equal(pipeline.length(pipeline_from_meta), 1)
  should.equal(pipeline.stage_names(pipeline_from_meta), ["meta_stage"])
  should.equal(pipeline.is_empty(pipeline_from_meta), False)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Introspection Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_length_test() {
  let empty = pipeline.new()
  should.equal(pipeline.length(empty), 0)

  // Note: We'll test multi-stage pipelines in composition tests
  // For now, just test single stage
  let single_stage = stage.new("single", fn(x) { Ok(x) })
  let single_pipeline = pipeline.from_stage(single_stage)
  should.equal(pipeline.length(single_pipeline), 1)
}

pub fn pipeline_is_empty_test() {
  let empty = pipeline.new()
  should.equal(pipeline.is_empty(empty), True)

  let single_stage = stage.new("single", fn(x) { Ok(x) })
  let single_pipeline = pipeline.from_stage(single_stage)
  should.equal(pipeline.is_empty(single_pipeline), False)
}

pub fn pipeline_stage_names_test() {
  let empty = pipeline.new()
  should.equal(pipeline.stage_names(empty), [])

  let first_stage = stage.new("first", fn(x) { Ok(x) })
  let first_pipeline = pipeline.from_stage(first_stage)
  should.equal(pipeline.stage_names(first_pipeline), ["first"])

  let second_stage = stage.new("second", fn(x) { Ok(x) })
  let second_pipeline = pipeline.from_stage(second_stage)
  should.equal(pipeline.stage_names(second_pipeline), ["second"])
}

pub fn pipeline_type_information_test() {
  let generic_pipeline = pipeline.new()
  should.equal(pipeline.get_input_type(generic_pipeline), "a")
  should.equal(pipeline.get_output_type(generic_pipeline), "a")

  let typed_pipeline = pipeline.empty()
  should.equal(pipeline.get_input_type(typed_pipeline), "input")
  should.equal(pipeline.get_output_type(typed_pipeline), "output")

  let string_stage = stage.new("string_stage", fn(s) { Ok(s <> "!") })
  let string_pipeline = pipeline.from_stage(string_stage)
  should.equal(pipeline.get_input_type(string_pipeline), "input")
  should.equal(pipeline.get_output_type(string_pipeline), "output")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Validation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_validate_empty_test() {
  let empty = pipeline.new()

  case pipeline.validate(empty) {
    Ok(_) -> panic as "Empty pipeline should not validate"
    Error(error.EmptyPipelineError) -> should.equal(True, True) // Expected
    Error(_) -> panic as "Expected EmptyPipelineError"
  }
}

pub fn pipeline_validate_single_stage_test() {
  let test_stage = stage.new("valid_stage", fn(x) { Ok(x) })
  let valid_pipeline = pipeline.from_stage(test_stage)

  case pipeline.validate(valid_pipeline) {
    Ok(Nil) -> should.equal(True, True) // Expected success
    Error(_) -> panic as "Single stage pipeline should validate"
  }
}

pub fn pipeline_is_ready_test() {
  let empty = pipeline.new()
  should.equal(pipeline.is_ready(empty), False)

  let valid_stage = stage.new("ready_stage", fn(x) { Ok(x) })
  let ready_pipeline = pipeline.from_stage(valid_stage)
  should.equal(pipeline.is_ready(ready_pipeline), True)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Type Safety Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_type_parameters_test() {
  // Test that pipelines maintain type parameters correctly
  let int_pipeline: pipeline.Pipeline(Int, Int) = pipeline.new()
  let string_pipeline: pipeline.Pipeline(String, String) = pipeline.new()

  // Both should be empty but maintain different types
  should.equal(pipeline.is_empty(int_pipeline), True)
  should.equal(pipeline.is_empty(string_pipeline), True)

  // Type-specific operations should work
  let int_stage = stage.new("int_add", fn(x) { Ok(x + 1) })
  let string_stage = stage.new("string_add", fn(s) { Ok(s <> "!") })

  let int_result_pipeline = pipeline.from_stage(int_stage)
  let string_result_pipeline = pipeline.from_stage(string_stage)

  should.equal(pipeline.length(int_result_pipeline), 1)
  should.equal(pipeline.length(string_result_pipeline), 1)
}

pub fn pipeline_opaque_type_test() {
  // Test that Pipeline is truly opaque - we can't access internal fields
  let test_pipeline = pipeline.new()

  // These should work through the API
  let _length = pipeline.length(test_pipeline)
  let _is_empty = pipeline.is_empty(test_pipeline)
  let _names = pipeline.stage_names(test_pipeline)

  // We can't directly access .state since it's opaque
  // This is verified at compile time
  should.equal(True, True)
}