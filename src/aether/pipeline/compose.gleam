import gleam/list
import gleam/option

import aether/pipeline/error.{
  type PipelineError, type StageError, CompositionError, ConfigurationError,
  EmptyPipelineError, ExecutionError, ProcessingError, StageFailure,
}
import aether/pipeline/pipeline.{type Pipeline}
import aether/pipeline/stage.{type Stage}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a PipelineError to a StageError for use within stage functions
///
/// This is necessary because pipeline execution returns PipelineError,
/// but stage processing functions must return StageError.
///
fn pipeline_error_to_stage_error(err: PipelineError) -> StageError {
  case err {
    StageFailure(_, _, stage_err) -> stage_err
    EmptyPipelineError ->
      ProcessingError("Empty pipeline execution", option.None)
    ExecutionError(msg) -> ProcessingError(msg, option.None)
    CompositionError(msg, _, _) -> ConfigurationError(msg)
  }
}

/// Collects a list of Results into a Result of list
///
/// Returns Ok with all values if all Results are Ok,
/// otherwise returns the first Error encountered.
///
fn all_ok(
  results: List(Result(a, PipelineError)),
) -> Result(List(a), PipelineError) {
  list.try_fold(results, [], fn(acc, result) {
    case result {
      Ok(value) -> Ok(list.append(acc, [value]))
      Error(e) -> Error(e)
    }
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Composition Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Composes two pipelines into one sequential pipeline
///
/// The output of the first pipeline becomes the input of the second.
/// This is equivalent to `pipeline.append()`.
///
/// ## Examples
///
/// ```gleam
/// let parse_pipeline = pipeline.new()
///   |> pipeline.pipe(parse_json)
///   |> pipeline.pipe(validate_schema)
///
/// let process_pipeline = pipeline.new()
///   |> pipeline.pipe(transform_data)
///   |> pipeline.pipe(enrich_data)
///
/// let full_pipeline = compose(parse_pipeline, process_pipeline)
/// ```
///
pub fn compose(first: Pipeline(a, b), second: Pipeline(b, c)) -> Pipeline(a, c) {
  pipeline.append(first, second)
}

/// Creates a conditional branch in the pipeline
///
/// After executing the input pipeline, evaluates the condition on the result.
/// If true, executes true_branch; otherwise executes false_branch.
/// Both branches must produce the same output type.
///
/// ## Examples
///
/// ```gleam
/// let main_pipeline =
///   pipeline.new()
///   |> pipeline.pipe(auth_check)
///   |> branch(
///     is_admin,
///     admin_pipeline,
///     user_pipeline,
///   )
/// ```
///
pub fn branch(
  base_pipeline: Pipeline(a, b),
  condition: fn(b) -> Bool,
  true_branch: Pipeline(b, c),
  false_branch: Pipeline(b, c),
) -> Pipeline(a, c) {
  let branch_stage =
    stage.new("branch", fn(input: b) {
      case condition(input) {
        True ->
          case pipeline.execute(true_branch, input) {
            Ok(result) -> Ok(result)
            Error(e) -> Error(pipeline_error_to_stage_error(e))
          }
        False ->
          case pipeline.execute(false_branch, input) {
            Ok(result) -> Ok(result)
            Error(e) -> Error(pipeline_error_to_stage_error(e))
          }
      }
    })

  pipeline.pipe(base_pipeline, branch_stage)
}

/// Executes multiple pipelines with the same input and merges their results
///
/// All pipelines receive the same input and are executed sequentially.
/// The merge function combines all outputs into a single result.
/// If any pipeline fails, the entire operation fails.
///
/// Note: This implementation executes sequentially. For true parallel
/// execution with OTP processes, use `parallel_async` (future feature).
///
/// ## Examples
///
/// ```gleam
/// let combined = parallel(
///   [fetch_user, fetch_posts, fetch_comments],
///   fn(results) { combine_user_data(results) },
/// )
/// ```
///
pub fn parallel(
  pipelines: List(Pipeline(a, b)),
  merge_fn: fn(List(b)) -> c,
) -> Pipeline(a, c) {
  let parallel_stage =
    stage.new("parallel", fn(input: a) {
      let results = list.map(pipelines, fn(p) { pipeline.execute(p, input) })

      case all_ok(results) {
        Ok(values) -> Ok(merge_fn(values))
        Error(e) -> Error(pipeline_error_to_stage_error(e))
      }
    })

  pipeline.from_stage(parallel_stage)
}

/// Merges multiple pipelines by executing them and combining results into a list
///
/// This is a simplified version of `parallel` that returns results as a list.
///
/// ## Examples
///
/// ```gleam
/// let merged = merge([pipeline1, pipeline2, pipeline3])
/// // Returns Pipeline(a, List(b))
/// ```
///
pub fn merge(pipelines: List(Pipeline(a, b))) -> Pipeline(a, List(b)) {
  parallel(pipelines, fn(results) { results })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Conditional Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a stage that only executes if the condition is true
///
/// If the condition is false, the input passes through unchanged.
/// Note: Input and output types must be the same for pass-through semantics.
///
/// ## Examples
///
/// ```gleam
/// let should_cache = fn(data) { data.size > 1000 }
/// let cache_stage = stage.new("cache", fn(data) { ... })
///
/// let conditional_cache = when(should_cache, cache_stage)
/// ```
///
pub fn when(condition: fn(a) -> Bool, stg: Stage(a, a)) -> Stage(a, a) {
  let stage_name = "when:" <> stage.get_name(stg)

  stage.new(stage_name, fn(input: a) {
    case condition(input) {
      True -> stage.execute(stg, input)
      False -> Ok(input)
    }
  })
}

/// Creates a stage that executes different logic based on a condition
///
/// If the condition is true, executes true_stage; otherwise executes false_stage.
/// Both stages must have the same input and output types.
///
/// ## Examples
///
/// ```gleam
/// let is_premium = fn(user) { user.plan == "premium" }
/// let premium_handler = stage.new("premium", ...)
/// let standard_handler = stage.new("standard", ...)
///
/// let handler = if_else(is_premium, premium_handler, standard_handler)
/// ```
///
pub fn if_else(
  condition: fn(a) -> Bool,
  true_stage: Stage(a, b),
  false_stage: Stage(a, b),
) -> Stage(a, b) {
  stage.new("if_else", fn(input: a) {
    case condition(input) {
      True -> stage.execute(true_stage, input)
      False -> stage.execute(false_stage, input)
    }
  })
}

/// Repeats a stage until a condition is met or max iterations is reached
///
/// The stage is executed repeatedly, passing its output as the next input,
/// until either:
/// - The condition returns True for the current value
/// - The maximum number of iterations is reached
///
/// ## Examples
///
/// ```gleam
/// let increment = stage.new("inc", fn(x) { Ok(x + 1) })
/// let is_ten = fn(x) { x >= 10 }
///
/// let repeated = repeat_until(increment, is_ten, 100)
/// // stage.execute(repeated, 0) returns Ok(10)
/// ```
///
pub fn repeat_until(
  stg: Stage(a, a),
  condition: fn(a) -> Bool,
  max_iterations: Int,
) -> Stage(a, a) {
  let stage_name = "repeat:" <> stage.get_name(stg)

  stage.new(stage_name, fn(input: a) {
    do_repeat(stg, condition, input, 0, max_iterations)
  })
}

fn do_repeat(
  stg: Stage(a, a),
  condition: fn(a) -> Bool,
  current: a,
  iteration: Int,
  max: Int,
) -> Result(a, StageError) {
  case condition(current) || iteration >= max {
    True -> Ok(current)
    False -> {
      case stage.execute(stg, current) {
        Ok(next) -> do_repeat(stg, condition, next, iteration + 1, max)
        Error(e) -> Error(e)
      }
    }
  }
}

/// Tries a primary stage, falling back to another stage on error
///
/// If the primary stage succeeds, returns its result.
/// If the primary stage fails, executes the fallback stage instead.
///
/// ## Examples
///
/// ```gleam
/// let primary_api = stage.new("primary", fn(req) { call_primary(req) })
/// let fallback_api = stage.new("fallback", fn(req) { call_fallback(req) })
///
/// let resilient = try_or(primary_api, fallback_api)
/// ```
///
pub fn try_or(primary: Stage(a, b), fallback: Stage(a, b)) -> Stage(a, b) {
  stage.new("try_or", fn(input: a) {
    case stage.execute(primary, input) {
      Ok(result) -> Ok(result)
      Error(_) -> stage.execute(fallback, input)
    }
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Advanced Composition Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a stage from a pipeline
///
/// This is useful when you want to embed a pipeline within a stage-level
/// composition or use pipeline semantics within stage operations.
///
/// ## Examples
///
/// ```gleam
/// let inner_pipeline = pipeline.new()
///   |> pipeline.pipe(stage1)
///   |> pipeline.pipe(stage2)
///
/// let embedded = pipeline_to_stage("embedded", inner_pipeline)
/// ```
///
pub fn pipeline_to_stage(
  name: String,
  inner_pipeline: Pipeline(a, b),
) -> Stage(a, b) {
  stage.new(name, fn(input: a) {
    case pipeline.execute(inner_pipeline, input) {
      Ok(result) -> Ok(result)
      Error(e) -> Error(pipeline_error_to_stage_error(e))
    }
  })
}

/// Creates a fan-out stage that applies multiple stages to the same input
///
/// Each stage receives the same input and produces its own output.
/// Results are collected in a list in the same order as the input stages.
///
/// ## Examples
///
/// ```gleam
/// let fan_out_stage = fan_out([
///   stage.new("extract_name", fn(user) { Ok(user.name) }),
///   stage.new("extract_email", fn(user) { Ok(user.email) }),
/// ])
/// ```
///
pub fn fan_out(stages: List(Stage(a, b))) -> Stage(a, List(b)) {
  stage.new("fan_out", fn(input: a) {
    let results = list.map(stages, fn(s) { stage.execute(s, input) })

    list.try_fold(results, [], fn(acc, result) {
      case result {
        Ok(value) -> Ok(list.append(acc, [value]))
        Error(e) -> Error(e)
      }
    })
  })
}
