import gleam/int
import gleam/option
import gleam/string

import gleeunit
import gleeunit/should

import aether/pipeline/error
import aether/pipeline/pipeline
import aether/pipeline/stage

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
  let metadata =
    stage.StageMetadata(
      description: "A test stage",
      version: option.Some("1.0.0"),
      tags: ["test"],
      config: option.None,
    )

  let stage_with_metadata =
    stage.new_with_metadata(
      "meta_stage",
      fn(x) { Ok(string.uppercase(x)) },
      metadata,
    )

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
    Error(error.EmptyPipelineError) -> should.equal(True, True)
    // Expected
    Error(_) -> panic as "Expected EmptyPipelineError"
  }
}

pub fn pipeline_validate_single_stage_test() {
  let test_stage = stage.new("valid_stage", fn(x) { Ok(x) })
  let valid_pipeline = pipeline.from_stage(test_stage)

  case pipeline.validate(valid_pipeline) {
    Ok(Nil) -> should.equal(True, True)
    // Expected success
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

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Composition Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_add_stage_test() {
  let empty_pipeline = pipeline.new()
  let test_stage = stage.new("test_stage", fn(x) { Ok(x + 1) })

  let extended_pipeline = pipeline.add_stage(empty_pipeline, test_stage)

  should.equal(pipeline.length(extended_pipeline), 1)
  should.equal(pipeline.is_empty(extended_pipeline), False)
  should.equal(pipeline.stage_names(extended_pipeline), ["test_stage"])
  should.equal(pipeline.is_ready(extended_pipeline), True)
}

pub fn pipeline_pipe_test() {
  let empty_pipeline = pipeline.new()
  let first_stage = stage.new("first", fn(x) { Ok(x + 1) })
  let second_stage = stage.new("second", fn(x) { Ok(x * 2) })

  let pipeline1 = pipeline.pipe(empty_pipeline, first_stage)
  should.equal(pipeline.length(pipeline1), 1)
  should.equal(pipeline.stage_names(pipeline1), ["first"])

  let pipeline2 = pipeline.pipe(pipeline1, second_stage)
  should.equal(pipeline.length(pipeline2), 2)
  should.equal(pipeline.stage_names(pipeline2), ["first", "second"])
}

pub fn pipeline_multiple_pipe_test() {
  let initial_pipeline = pipeline.new()

  let result_pipeline =
    initial_pipeline
    |> pipeline.pipe(stage.new("add_one", fn(x) { Ok(x + 1) }))
    |> pipeline.pipe(stage.new("double", fn(x) { Ok(x * 2) }))
    |> pipeline.pipe(stage.new("square", fn(x) { Ok(x * x) }))

  should.equal(pipeline.length(result_pipeline), 3)
  should.equal(pipeline.stage_names(result_pipeline), [
    "add_one",
    "double",
    "square",
  ])
  should.equal(pipeline.is_ready(result_pipeline), True)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Transformation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_map_test() {
  let base_pipeline =
    pipeline.from_stage(stage.new("base", fn(x) { Ok(x + 1) }))

  let mapped_pipeline = pipeline.map(base_pipeline, fn(x) { x * 2 })

  should.equal(pipeline.length(mapped_pipeline), 2)
  should.equal(pipeline.stage_names(mapped_pipeline), ["base", "map_1"])
}

pub fn pipeline_map_string_test() {
  let string_pipeline =
    pipeline.from_stage(stage.new("to_string", fn(x) { Ok(int.to_string(x)) }))

  let mapped_pipeline = pipeline.map(string_pipeline, fn(s) { s <> "!" })

  should.equal(pipeline.length(mapped_pipeline), 2)
  should.equal(pipeline.stage_names(mapped_pipeline), ["to_string", "map_1"])
}

pub fn pipeline_recover_test() {
  let base_pipeline =
    pipeline.from_stage(stage.new("base", fn(x) { Ok(x + 1) }))

  let recovered_pipeline = pipeline.recover(base_pipeline, fn(_error) { 0 })

  should.equal(pipeline.length(recovered_pipeline), 2)
  should.equal(pipeline.stage_names(recovered_pipeline), ["base", "recover_1"])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Utility Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_append_test() {
  let first_pipeline =
    pipeline.from_stage(stage.new("first", fn(x) { Ok(x + 1) }))
  let second_pipeline =
    pipeline.from_stage(stage.new("second", fn(x) { Ok(x * 2) }))

  let combined_pipeline = pipeline.append(first_pipeline, second_pipeline)

  should.equal(pipeline.length(combined_pipeline), 2)
  should.equal(pipeline.is_empty(combined_pipeline), False)
  should.equal(pipeline.stage_names(combined_pipeline), ["first", "second"])
}

pub fn pipeline_prepend_test() {
  let first_pipeline =
    pipeline.from_stage(stage.new("first", fn(x) { Ok(x + 1) }))
  let second_pipeline =
    pipeline.from_stage(stage.new("second", fn(x) { Ok(x * 2) }))

  let combined_pipeline = pipeline.prepend(first_pipeline, second_pipeline)

  should.equal(pipeline.length(combined_pipeline), 2)
  should.equal(pipeline.is_empty(combined_pipeline), False)
  should.equal(pipeline.stage_names(combined_pipeline), ["first", "second"])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Execution Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_execute_empty_test() {
  // new() creates an identity pipeline, which passes input through
  let empty_pipeline = pipeline.new()
  let result = pipeline.execute(empty_pipeline, 42)
  should.equal(result, Ok(42))
}

pub fn pipeline_execute_single_stage_test() {
  let test_stage = stage.new("add_five", fn(x) { Ok(x + 5) })
  let single_pipeline = pipeline.from_stage(test_stage)

  let result = pipeline.execute(single_pipeline, 10)
  should.equal(result, Ok(15))
}

pub fn pipeline_execute_multiple_stages_test() {
  let multi_stage_pipeline =
    pipeline.new()
    |> pipeline.pipe(stage.new("add_one", fn(x) { Ok(x + 1) }))
    |> pipeline.pipe(stage.new("double", fn(x) { Ok(x * 2) }))

  // (5 + 1) * 2 = 12
  let result = pipeline.execute(multi_stage_pipeline, 5)
  should.equal(result, Ok(12))
}

pub fn pipeline_execute_validation_test() {
  let valid_pipeline = pipeline.from_stage(stage.new("valid", fn(x) { Ok(x) }))
  let valid_result = pipeline.execute(valid_pipeline, "test")
  should.equal(valid_result, Ok("test"))

  // empty() creates a pipeline that fails on execution
  let empty_result = pipeline.execute(pipeline.empty(), "test")
  case empty_result {
    Ok(_) -> panic as "Empty pipeline should fail"
    Error(error.EmptyPipelineError) -> should.equal(True, True)
    // Expected
    Error(_) -> panic as "Expected EmptyPipelineError"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline String Processing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_string_processing_test() {
  let processing_pipeline =
    pipeline.new()
    |> pipeline.pipe(stage.new("trim", fn(s) { Ok(string.trim(s)) }))
    |> pipeline.pipe(stage.new("upper", fn(s) { Ok(string.uppercase(s)) }))
    |> pipeline.pipe(stage.new("exclaim", fn(s) { Ok(s <> "!") }))

  let result = pipeline.execute(processing_pipeline, "  hello world  ")
  should.equal(result, Ok("HELLO WORLD!"))
}

pub fn pipeline_single_stage_string_test() {
  let double_pipeline =
    pipeline.from_stage(stage.new("double", fn(s) { Ok(s <> s) }))

  let result = pipeline.execute(double_pipeline, "test")
  should.equal(result, Ok("testtest"))
}

pub fn pipeline_stage_error_test() {
  let failing_pipeline =
    pipeline.from_stage(
      stage.new("failing", fn(_s) {
        Error(error.validation_error("Always fails"))
      }),
    )

  let result = pipeline.execute(failing_pipeline, "test")

  case result {
    Ok(_) -> panic as "Expected error"
    Error(error.StageFailure(stage_name, stage_index, stage_error)) -> {
      should.equal(stage_name, "failing")
      should.equal(stage_index, 0)
      should.equal(stage_error, error.validation_error("Always fails"))
    }
    Error(_) -> panic as "Expected StageFailure"
  }
}

pub fn pipeline_middle_stage_error_test() {
  let pipeline_with_error =
    pipeline.new()
    |> pipeline.pipe(stage.new("first", fn(s) { Ok(s <> "_1") }))
    |> pipeline.pipe(
      stage.new("failing", fn(_s) {
        Error(error.processing_error("Middle stage failed", option.None))
      }),
    )
    |> pipeline.pipe(stage.new("last", fn(s) { Ok(s <> "_3") }))

  let result = pipeline.execute(pipeline_with_error, "test")

  case result {
    Ok(_) -> panic as "Expected error"
    Error(error.StageFailure(stage_name, stage_index, stage_error)) -> {
      should.equal(stage_name, "failing")
      should.equal(stage_index, 1)
      // Second stage (index 1)
      should.equal(
        stage_error,
        error.processing_error("Middle stage failed", option.None),
      )
    }
    Error(_) -> panic as "Expected StageFailure"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Complex Pipeline Scenarios
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_complex_composition_test() {
  let processing_pipeline =
    pipeline.new()
    |> pipeline.pipe(stage.new("trim", fn(s) { Ok(string.trim(s)) }))
    |> pipeline.pipe(stage.new("upper", fn(s) { Ok(string.uppercase(s)) }))
    |> pipeline.pipe(stage.new("add_exclamation", fn(s) { Ok(s <> "!") }))
    |> pipeline.map(fn(s) { "Result: " <> s })

  should.equal(pipeline.length(processing_pipeline), 4)
  should.equal(pipeline.stage_names(processing_pipeline), [
    "trim",
    "upper",
    "add_exclamation",
    "map_3",
  ])
  should.equal(pipeline.is_ready(processing_pipeline), True)

  let result = pipeline.execute(processing_pipeline, "  hello  ")
  should.equal(result, Ok("Result: HELLO!"))
}

pub fn pipeline_type_safe_composition_test() {
  // Test that pipeline composition maintains type safety
  let int_pipeline: pipeline.Pipeline(Int, Int) =
    pipeline.new()
    |> pipeline.pipe(stage.new("add_one", fn(x) { Ok(x + 1) }))
    |> pipeline.pipe(stage.new("multiply_by_two", fn(x) { Ok(x * 2) }))

  let string_pipeline: pipeline.Pipeline(String, String) =
    pipeline.new()
    |> pipeline.pipe(stage.new("exclaim", fn(s) { Ok(s <> "!") }))
    |> pipeline.pipe(stage.new("bracket", fn(s) { Ok("[" <> s <> "]") }))

  should.equal(pipeline.length(int_pipeline), 2)
  should.equal(pipeline.length(string_pipeline), 2)

  // (5 + 1) * 2 = 12
  let int_result = pipeline.execute(int_pipeline, 5)
  should.equal(int_result, Ok(12))

  // "[hello!]"
  let string_result = pipeline.execute(string_pipeline, "hello")
  should.equal(string_result, Ok("[hello!]"))
}

pub fn pipeline_append_test_with_execution() {
  let first_pipeline =
    pipeline.from_stage(stage.new("add_one", fn(x) { Ok(x + 1) }))
  let second_pipeline =
    pipeline.from_stage(stage.new("double", fn(x) { Ok(x * 2) }))

  let combined_pipeline = pipeline.append(first_pipeline, second_pipeline)

  should.equal(pipeline.length(combined_pipeline), 2)
  should.equal(pipeline.stage_names(combined_pipeline), ["add_one", "double"])

  // (5 + 1) * 2 = 12
  let result = pipeline.execute(combined_pipeline, 5)
  should.equal(result, Ok(12))
}

pub fn pipeline_recover_test_with_execution() {
  let failing_pipeline =
    pipeline.from_stage(
      stage.new("failing", fn(_x: Int) {
        Error(error.validation_error("Always fails"))
      }),
    )

  let recovered_pipeline = pipeline.recover(failing_pipeline, fn(_err) { -1 })

  let result = pipeline.execute(recovered_pipeline, 42)
  should.equal(result, Ok(-1))
}

pub fn pipeline_type_transformation_test() {
  // Test Int -> String -> Int type transformation
  let transform_pipeline =
    pipeline.new()
    |> pipeline.pipe(stage.new("double", fn(x) { Ok(x * 2) }))
    |> pipeline.pipe(stage.new("to_string", fn(x) { Ok(int.to_string(x)) }))
    |> pipeline.pipe(stage.new("length", fn(s) { Ok(string.length(s)) }))

  // 12345 * 2 = 24690 -> "24690" -> length 5
  let result = pipeline.execute(transform_pipeline, 12_345)
  should.equal(result, Ok(5))
}
