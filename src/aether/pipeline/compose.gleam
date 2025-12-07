import gleam/list
import gleam/option

import aether/pipeline/error.{
  type PipelineError, type StageError, CompositionError, ConfigurationError,
  EmptyPipelineError, ExecutionError, ProcessingError, StageFailure,
}
import aether/pipeline/pipeline.{type Pipeline}
import aether/pipeline/stage.{type Stage}

fn pipeline_error_to_stage_error(err: PipelineError) -> StageError {
  case err {
    StageFailure(_, _, stage_err) -> stage_err
    EmptyPipelineError ->
      ProcessingError("Empty pipeline execution", option.None)
    ExecutionError(msg) -> ProcessingError(msg, option.None)
    CompositionError(msg, _, _) -> ConfigurationError(msg)
  }
}

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

pub fn compose(first: Pipeline(a, b), second: Pipeline(b, c)) -> Pipeline(a, c) {
  pipeline.append(first, second)
}

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

pub fn merge(pipelines: List(Pipeline(a, b))) -> Pipeline(a, List(b)) {
  parallel(pipelines, fn(results) { results })
}

pub fn when(condition: fn(a) -> Bool, stg: Stage(a, a)) -> Stage(a, a) {
  let stage_name = "when:" <> stage.get_name(stg)

  stage.new(stage_name, fn(input: a) {
    case condition(input) {
      True -> stage.execute(stg, input)
      False -> Ok(input)
    }
  })
}

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

pub fn try_or(primary: Stage(a, b), fallback: Stage(a, b)) -> Stage(a, b) {
  stage.new("try_or", fn(input: a) {
    case stage.execute(primary, input) {
      Ok(result) -> Ok(result)
      Error(_) -> stage.execute(fallback, input)
    }
  })
}

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
