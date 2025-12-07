import gleam/int
import gleam/list
import gleam/option

import gleeunit
import gleeunit/should

import aether/pipeline/compose
import aether/pipeline/error
import aether/pipeline/pipeline
import aether/pipeline/stage

pub fn main() -> Nil {
  gleeunit.main()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// compose() Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn compose_two_pipelines_test() {
  let pipe1 =
    pipeline.new()
    |> pipeline.pipe(stage.new("add1", fn(x: Int) { Ok(x + 1) }))

  let pipe2 =
    pipeline.new()
    |> pipeline.pipe(stage.new("double", fn(x: Int) { Ok(x * 2) }))

  let combined = compose.compose(pipe1, pipe2)

  // (5 + 1) * 2 = 12
  pipeline.execute(combined, 5)
  |> should.equal(Ok(12))
}

pub fn compose_three_pipelines_test() {
  let pipe1 =
    pipeline.from_stage(stage.new("add1", fn(x: Int) { Ok(x + 1) }))
  let pipe2 =
    pipeline.from_stage(stage.new("double", fn(x: Int) { Ok(x * 2) }))
  let pipe3 =
    pipeline.from_stage(stage.new("square", fn(x: Int) { Ok(x * x) }))

  let combined =
    pipe1
    |> compose.compose(pipe2)
    |> compose.compose(pipe3)

  // ((5 + 1) * 2)^2 = 144
  pipeline.execute(combined, 5)
  |> should.equal(Ok(144))
}

pub fn compose_preserves_stage_count_test() {
  let pipe1 =
    pipeline.new()
    |> pipeline.pipe(stage.new("s1", fn(x: Int) { Ok(x) }))
    |> pipeline.pipe(stage.new("s2", fn(x: Int) { Ok(x) }))

  let pipe2 =
    pipeline.new()
    |> pipeline.pipe(stage.new("s3", fn(x: Int) { Ok(x) }))

  let combined = compose.compose(pipe1, pipe2)

  should.equal(pipeline.length(combined), 3)
  should.equal(pipeline.stage_names(combined), ["s1", "s2", "s3"])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// branch() Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn branch_true_path_test() {
  let is_even = fn(x: Int) { x % 2 == 0 }

  let even_branch =
    pipeline.from_stage(stage.new("halve", fn(x: Int) { Ok(x / 2) }))

  let odd_branch =
    pipeline.from_stage(stage.new("triple", fn(x: Int) { Ok(x * 3) }))

  let branched =
    pipeline.new()
    |> compose.branch(is_even, even_branch, odd_branch)

  // Even: 4 / 2 = 2
  pipeline.execute(branched, 4)
  |> should.equal(Ok(2))
}

pub fn branch_false_path_test() {
  let is_even = fn(x: Int) { x % 2 == 0 }

  let even_branch =
    pipeline.from_stage(stage.new("halve", fn(x: Int) { Ok(x / 2) }))

  let odd_branch =
    pipeline.from_stage(stage.new("triple", fn(x: Int) { Ok(x * 3) }))

  let branched =
    pipeline.new()
    |> compose.branch(is_even, even_branch, odd_branch)

  // Odd: 5 * 3 = 15
  pipeline.execute(branched, 5)
  |> should.equal(Ok(15))
}

pub fn branch_with_preprocessing_test() {
  let is_positive = fn(x: Int) { x > 0 }

  let positive_branch =
    pipeline.from_stage(stage.new("square", fn(x: Int) { Ok(x * x) }))

  let negative_branch =
    pipeline.from_stage(stage.new("negate", fn(x: Int) { Ok(-x) }))

  let branched =
    pipeline.new()
    |> pipeline.pipe(stage.new("add10", fn(x: Int) { Ok(x + 10) }))
    |> compose.branch(is_positive, positive_branch, negative_branch)

  // -5 + 10 = 5, 5 > 0, so square: 25
  pipeline.execute(branched, -5)
  |> should.equal(Ok(25))
}

pub fn branch_error_in_true_branch_test() {
  let is_even = fn(x: Int) { x % 2 == 0 }

  let failing_branch =
    pipeline.from_stage(
      stage.new("fail", fn(_x: Int) {
        Error(error.validation_error("Even numbers not allowed"))
      }),
    )

  let ok_branch =
    pipeline.from_stage(stage.new("ok", fn(x: Int) { Ok(x) }))

  let branched =
    pipeline.new()
    |> compose.branch(is_even, failing_branch, ok_branch)

  case pipeline.execute(branched, 4) {
    Ok(_) -> should.fail()
    Error(error.StageFailure("branch", _, _)) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// parallel() Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parallel_all_succeed_test() {
  let double_pipe =
    pipeline.from_stage(stage.new("double", fn(x: Int) { Ok(x * 2) }))
  let triple_pipe =
    pipeline.from_stage(stage.new("triple", fn(x: Int) { Ok(x * 3) }))
  let square_pipe =
    pipeline.from_stage(stage.new("square", fn(x: Int) { Ok(x * x) }))

  let merge_fn = fn(results: List(Int)) {
    list.fold(results, 0, fn(acc, x) { acc + x })
  }

  let parallel_pipeline =
    compose.parallel([double_pipe, triple_pipe, square_pipe], merge_fn)

  // 5*2 + 5*3 + 5*5 = 10 + 15 + 25 = 50
  pipeline.execute(parallel_pipeline, 5)
  |> should.equal(Ok(50))
}

pub fn parallel_one_fails_test() {
  let ok_pipe =
    pipeline.from_stage(stage.new("ok", fn(x: Int) { Ok(x) }))
  let fail_pipe =
    pipeline.from_stage(
      stage.new("fail", fn(_x: Int) {
        Error(error.validation_error("Always fails"))
      }),
    )

  let merge_fn = fn(results: List(Int)) { list.first(results) }

  let parallel_pipeline = compose.parallel([ok_pipe, fail_pipe], merge_fn)

  case pipeline.execute(parallel_pipeline, 5) {
    Ok(_) -> should.fail()
    Error(error.StageFailure("parallel", _, _)) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

pub fn parallel_empty_list_test() {
  let merge_fn = fn(_results: List(Int)) { 0 }
  let parallel_pipeline = compose.parallel([], merge_fn)

  // Empty list of pipelines should produce empty results
  pipeline.execute(parallel_pipeline, 5)
  |> should.equal(Ok(0))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// merge() Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn merge_pipelines_test() {
  let pipe1 =
    pipeline.from_stage(stage.new("add1", fn(x: Int) { Ok(x + 1) }))
  let pipe2 =
    pipeline.from_stage(stage.new("add2", fn(x: Int) { Ok(x + 2) }))
  let pipe3 =
    pipeline.from_stage(stage.new("add3", fn(x: Int) { Ok(x + 3) }))

  let merged = compose.merge([pipe1, pipe2, pipe3])

  // Input 10: [11, 12, 13]
  pipeline.execute(merged, 10)
  |> should.equal(Ok([11, 12, 13]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// when() Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn when_condition_true_test() {
  let is_positive = fn(x: Int) { x > 0 }
  let double_stage = stage.new("double", fn(x: Int) { Ok(x * 2) })

  let conditional = compose.when(is_positive, double_stage)

  // Positive: doubled
  stage.execute(conditional, 5)
  |> should.equal(Ok(10))
}

pub fn when_condition_false_test() {
  let is_positive = fn(x: Int) { x > 0 }
  let double_stage = stage.new("double", fn(x: Int) { Ok(x * 2) })

  let conditional = compose.when(is_positive, double_stage)

  // Negative: pass-through unchanged
  stage.execute(conditional, -5)
  |> should.equal(Ok(-5))
}

pub fn when_stage_name_test() {
  let is_positive = fn(x: Int) { x > 0 }
  let double_stage = stage.new("double", fn(x: Int) { Ok(x * 2) })

  let conditional = compose.when(is_positive, double_stage)

  should.equal(stage.get_name(conditional), "when:double")
}

pub fn when_in_pipeline_test() {
  let is_large = fn(x: Int) { x > 100 }
  let cap_stage = stage.new("cap", fn(_x: Int) { Ok(100) })

  let test_pipeline =
    pipeline.new()
    |> pipeline.pipe(stage.new("double", fn(x: Int) { Ok(x * 2) }))
    |> pipeline.pipe(compose.when(is_large, cap_stage))

  // 30 * 2 = 60, not > 100, so pass-through: 60
  pipeline.execute(test_pipeline, 30)
  |> should.equal(Ok(60))

  // 60 * 2 = 120, > 100, so capped: 100
  pipeline.execute(test_pipeline, 60)
  |> should.equal(Ok(100))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// if_else() Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn if_else_true_branch_test() {
  let is_even = fn(x: Int) { x % 2 == 0 }
  let halve_stage = stage.new("halve", fn(x: Int) { Ok(x / 2) })
  let triple_stage = stage.new("triple", fn(x: Int) { Ok(x * 3) })

  let conditional = compose.if_else(is_even, halve_stage, triple_stage)

  // Even: 10 / 2 = 5
  stage.execute(conditional, 10)
  |> should.equal(Ok(5))
}

pub fn if_else_false_branch_test() {
  let is_even = fn(x: Int) { x % 2 == 0 }
  let halve_stage = stage.new("halve", fn(x: Int) { Ok(x / 2) })
  let triple_stage = stage.new("triple", fn(x: Int) { Ok(x * 3) })

  let conditional = compose.if_else(is_even, halve_stage, triple_stage)

  // Odd: 5 * 3 = 15
  stage.execute(conditional, 5)
  |> should.equal(Ok(15))
}

pub fn if_else_stage_name_test() {
  let condition = fn(_x: Int) { True }
  let true_stage = stage.new("true", fn(x: Int) { Ok(x) })
  let false_stage = stage.new("false", fn(x: Int) { Ok(x) })

  let conditional = compose.if_else(condition, true_stage, false_stage)

  should.equal(stage.get_name(conditional), "if_else")
}

pub fn if_else_type_transformation_test() {
  let is_positive = fn(x: Int) { x > 0 }
  let to_positive_string =
    stage.new("positive", fn(x: Int) { Ok("positive: " <> int.to_string(x)) })
  let to_negative_string =
    stage.new("negative", fn(x: Int) { Ok("negative: " <> int.to_string(x)) })

  let conditional =
    compose.if_else(is_positive, to_positive_string, to_negative_string)

  stage.execute(conditional, 5)
  |> should.equal(Ok("positive: 5"))

  stage.execute(conditional, -5)
  |> should.equal(Ok("negative: -5"))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// repeat_until() Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn repeat_until_terminates_test() {
  let increment = stage.new("inc", fn(x: Int) { Ok(x + 1) })
  let is_ten = fn(x: Int) { x >= 10 }

  let repeated = compose.repeat_until(increment, is_ten, 100)

  // 0 -> 1 -> 2 -> ... -> 10 (stop)
  stage.execute(repeated, 0)
  |> should.equal(Ok(10))
}

pub fn repeat_until_already_satisfied_test() {
  let increment = stage.new("inc", fn(x: Int) { Ok(x + 1) })
  let is_ten = fn(x: Int) { x >= 10 }

  let repeated = compose.repeat_until(increment, is_ten, 100)

  // Already >= 10, so no iterations
  stage.execute(repeated, 15)
  |> should.equal(Ok(15))
}

pub fn repeat_until_max_iterations_test() {
  let increment = stage.new("inc", fn(x: Int) { Ok(x + 1) })
  let never_true = fn(_x: Int) { False }

  let repeated = compose.repeat_until(increment, never_true, 5)

  // Will hit max iterations at 5
  stage.execute(repeated, 0)
  |> should.equal(Ok(5))
}

pub fn repeat_until_stage_name_test() {
  let increment = stage.new("increment", fn(x: Int) { Ok(x + 1) })
  let is_ten = fn(x: Int) { x >= 10 }

  let repeated = compose.repeat_until(increment, is_ten, 100)

  should.equal(stage.get_name(repeated), "repeat:increment")
}

pub fn repeat_until_with_error_test() {
  let fail_at_5 =
    stage.new("fail_at_5", fn(x: Int) {
      case x >= 5 {
        True -> Error(error.validation_error("Reached 5"))
        False -> Ok(x + 1)
      }
    })
  let is_ten = fn(x: Int) { x >= 10 }

  let repeated = compose.repeat_until(fail_at_5, is_ten, 100)

  case stage.execute(repeated, 0) {
    Ok(_) -> should.fail()
    Error(error.ValidationError("Reached 5")) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// try_or() Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn try_or_primary_succeeds_test() {
  let primary = stage.new("primary", fn(x: Int) { Ok(x * 2) })
  let fallback = stage.new("fallback", fn(x: Int) { Ok(x * 10) })

  let resilient = compose.try_or(primary, fallback)

  // Primary succeeds: 5 * 2 = 10
  stage.execute(resilient, 5)
  |> should.equal(Ok(10))
}

pub fn try_or_fallback_executes_test() {
  let primary =
    stage.new("primary", fn(_x: Int) {
      Error(error.processing_error("Primary failed", option.None))
    })
  let fallback = stage.new("fallback", fn(x: Int) { Ok(x * 10) })

  let resilient = compose.try_or(primary, fallback)

  // Primary fails, fallback: 5 * 10 = 50
  stage.execute(resilient, 5)
  |> should.equal(Ok(50))
}

pub fn try_or_both_fail_test() {
  let primary =
    stage.new("primary", fn(_x: Int) {
      Error(error.processing_error("Primary failed", option.None))
    })
  let fallback =
    stage.new("fallback", fn(_x: Int) {
      Error(error.validation_error("Fallback failed"))
    })

  let resilient = compose.try_or(primary, fallback)

  case stage.execute(resilient, 5) {
    Ok(_) -> should.fail()
    Error(error.ValidationError("Fallback failed")) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

pub fn try_or_stage_name_test() {
  let primary = stage.new("primary", fn(x: Int) { Ok(x) })
  let fallback = stage.new("fallback", fn(x: Int) { Ok(x) })

  let resilient = compose.try_or(primary, fallback)

  should.equal(stage.get_name(resilient), "try_or")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// pipeline_to_stage() Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn pipeline_to_stage_test() {
  let inner_pipeline =
    pipeline.new()
    |> pipeline.pipe(stage.new("add1", fn(x: Int) { Ok(x + 1) }))
    |> pipeline.pipe(stage.new("double", fn(x: Int) { Ok(x * 2) }))

  let embedded = compose.pipeline_to_stage("embedded", inner_pipeline)

  // (5 + 1) * 2 = 12
  stage.execute(embedded, 5)
  |> should.equal(Ok(12))

  should.equal(stage.get_name(embedded), "embedded")
}

pub fn pipeline_to_stage_error_propagation_test() {
  let failing_pipeline =
    pipeline.from_stage(
      stage.new("fail", fn(_x: Int) {
        Error(error.validation_error("Inner failure"))
      }),
    )

  let embedded = compose.pipeline_to_stage("embedded", failing_pipeline)

  case stage.execute(embedded, 5) {
    Ok(_) -> should.fail()
    Error(error.ValidationError("Inner failure")) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// fan_out() Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn fan_out_test() {
  let double = stage.new("double", fn(x: Int) { Ok(x * 2) })
  let triple = stage.new("triple", fn(x: Int) { Ok(x * 3) })
  let square = stage.new("square", fn(x: Int) { Ok(x * x) })

  let fan_out_stage = compose.fan_out([double, triple, square])

  // Input 5: [10, 15, 25]
  stage.execute(fan_out_stage, 5)
  |> should.equal(Ok([10, 15, 25]))
}

pub fn fan_out_empty_test() {
  let fan_out_stage = compose.fan_out([])

  stage.execute(fan_out_stage, 5)
  |> should.equal(Ok([]))
}

pub fn fan_out_with_error_test() {
  let ok_stage = stage.new("ok", fn(x: Int) { Ok(x) })
  let fail_stage =
    stage.new("fail", fn(_x: Int) {
      Error(error.validation_error("Stage failed"))
    })

  let fan_out_stage = compose.fan_out([ok_stage, fail_stage])

  case stage.execute(fan_out_stage, 5) {
    Ok(_) -> should.fail()
    Error(error.ValidationError("Stage failed")) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Nested Composition Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn nested_branch_test() {
  let is_positive = fn(x: Int) { x > 0 }
  let is_even = fn(x: Int) { x % 2 == 0 }

  let even_handler =
    pipeline.from_stage(stage.new("even", fn(x: Int) { Ok(x / 2) }))
  let odd_handler =
    pipeline.from_stage(stage.new("odd", fn(x: Int) { Ok(x * 3 + 1) }))

  let positive_branch =
    pipeline.new()
    |> compose.branch(is_even, even_handler, odd_handler)

  let negative_handler =
    pipeline.from_stage(stage.new("negate", fn(x: Int) { Ok(-x) }))

  let nested =
    pipeline.new()
    |> compose.branch(is_positive, positive_branch, negative_handler)

  // Positive, even: 10 / 2 = 5
  pipeline.execute(nested, 10)
  |> should.equal(Ok(5))

  // Positive, odd: 5 * 3 + 1 = 16
  pipeline.execute(nested, 5)
  |> should.equal(Ok(16))

  // Negative: -(-5) = 5
  pipeline.execute(nested, -5)
  |> should.equal(Ok(5))
}

pub fn complex_composition_test() {
  // Build a complex pipeline:
  // 1. Double the input
  // 2. If > 100, cap to 100
  // 3. Branch: even -> halve, odd -> add 1
  // 4. Retry with fallback

  let double_stage = stage.new("double", fn(x: Int) { Ok(x * 2) })

  let is_large = fn(x: Int) { x > 100 }
  let cap_stage = stage.new("cap", fn(_x: Int) { Ok(100) })
  let conditional_cap = compose.when(is_large, cap_stage)

  let is_even = fn(x: Int) { x % 2 == 0 }
  let halve_stage = stage.new("halve", fn(x: Int) { Ok(x / 2) })
  let add_one_stage = stage.new("add_one", fn(x: Int) { Ok(x + 1) })
  let even_odd_stage = compose.if_else(is_even, halve_stage, add_one_stage)

  let complex_pipeline =
    pipeline.new()
    |> pipeline.pipe(double_stage)
    |> pipeline.pipe(conditional_cap)
    |> pipeline.pipe(even_odd_stage)

  // 30 * 2 = 60, not > 100, even: 60 / 2 = 30
  pipeline.execute(complex_pipeline, 30)
  |> should.equal(Ok(30))

  // 60 * 2 = 120, > 100 -> 100, even: 100 / 2 = 50
  pipeline.execute(complex_pipeline, 60)
  |> should.equal(Ok(50))

  // 15 * 2 = 30, not > 100, even: 30 / 2 = 15
  pipeline.execute(complex_pipeline, 15)
  |> should.equal(Ok(15))

  // 17 * 2 = 34, not > 100, even: 34 / 2 = 17
  pipeline.execute(complex_pipeline, 17)
  |> should.equal(Ok(17))
}
