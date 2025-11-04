import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string

pub type BenchmarkResult {
  BenchmarkResult(
    name: String,
    iterations: Int,
    total_time_microseconds: Int,
    avg_time_microseconds: Float,
    min_time_microseconds: Int,
    max_time_microseconds: Int,
  )
}

pub fn run(name: String, iterations: Int, f: fn() -> a) -> BenchmarkResult {
  run_internal(name, iterations, True, f)
}

pub fn run_cold(name: String, iterations: Int, f: fn() -> a) -> BenchmarkResult {
  run_internal(name, iterations, False, f)
}

fn run_internal(
  name: String,
  iterations: Int,
  use_warmup: Bool,
  f: fn() -> a,
) -> BenchmarkResult {
  case use_warmup {
    True -> do_warmup(int.min(iterations / 10, 100), f)
    False -> Nil
  }

  let times = measure_iterations(iterations, f, [])

  let total = list.fold(times, 0, fn(acc, t) { acc + t })
  let avg = int.to_float(total) /. int.to_float(iterations)
  let min = list.fold(times, 999_999_999, int.min)
  let max = list.fold(times, 0, int.max)

  BenchmarkResult(
    name: name,
    iterations: iterations,
    total_time_microseconds: total,
    avg_time_microseconds: avg,
    min_time_microseconds: min,
    max_time_microseconds: max,
  )
}

fn do_warmup(n: Int, f: fn() -> a) -> Nil {
  case n {
    0 -> Nil
    _ -> {
      let _ = f()
      do_warmup(n - 1, f)
    }
  }
}

fn measure_iterations(n: Int, f: fn() -> a, acc: List(Int)) -> List(Int) {
  case n {
    0 -> acc
    _ -> {
      // TODO: Add accurate time measurement functionality
      let start = 0
      let _ = f()
      let end = 1
      measure_iterations(n - 1, f, [end - start, ..acc])
    }
  }
}

pub fn compare(benchmarks: List(#(String, fn() -> a)), iterations: Int) -> Nil {
  io.println("\n" <> string.repeat("=", 60))
  io.println("🏁 Benchmark Comparison")
  io.println(string.repeat("=", 60))

  let results =
    list.map(benchmarks, fn(bench) {
      let #(name, f) = bench
      run(name, iterations, f)
    })

  list.each(results, print_result)
  print_comparison(results)
}

pub fn print_result(result: BenchmarkResult) -> Nil {
  io.println("\n" <> string.repeat("-", 60))
  io.println("📊 " <> result.name)
  io.println(string.repeat("-", 60))
  io.println("Iterations:  " <> format_number(result.iterations))
  io.println("Total time:  " <> format_time(result.total_time_microseconds))
  io.println(
    "Avg time:    " <> format_time_precise(result.avg_time_microseconds),
  )

  case result.min_time_microseconds {
    0 -> Nil
    _ -> {
      io.println("Min time:    " <> format_time(result.min_time_microseconds))
      io.println("Max time:    " <> format_time(result.max_time_microseconds))
    }
  }
}

fn format_time(microseconds: Int) -> String {
  case microseconds {
    t if t < 1000 -> int.to_string(t) <> " μs"
    t if t < 1_000_000 -> {
      let ms = int.to_float(t) /. 1000.0
      float.to_string(ms) <> " ms"
    }
    t -> {
      let s = int.to_float(t) /. 1_000_000.0
      float.to_string(s) <> " s"
    }
  }
}

fn format_time_precise(microseconds: Float) -> String {
  case microseconds {
    t if t <. 1000.0 -> float.to_string(t) <> " μs"
    t if t <. 1_000_000.0 -> {
      let ms = t /. 1000.0
      float.to_string(ms) <> " ms"
    }
    t -> {
      let s = t /. 1_000_000.0
      float.to_string(s) <> " s"
    }
  }
}

fn format_number(n: Int) -> String {
  let str = int.to_string(n)
  let len = string.length(str)
  case len > 3 {
    True -> {
      let groups = split_by_thousands(str, len)
      string.join(groups, ",")
    }
    False -> str
  }
}

fn split_by_thousands(str: String, len: Int) -> List(String) {
  case len > 3 {
    True -> {
      let split_at = len - 3
      let head = string.slice(str, 0, split_at)
      let tail = string.slice(str, split_at, string.length(str) - split_at)
      [head, ..split_by_thousands(tail, 3)]
    }
    False -> [str]
  }
}

fn print_comparison(results: List(BenchmarkResult)) -> Nil {
  case results {
    [] -> Nil
    _ -> {
      io.println("\n" <> string.repeat("=", 60))
      io.println("🏆 Performance Ranking (fastest to slowest)")
      io.println(string.repeat("=", 60))

      let sorted =
        list.sort(results, fn(a, b) {
          float.compare(a.avg_time_microseconds, b.avg_time_microseconds)
        })

      let fastest = case list.first(sorted) {
        Ok(r) -> r.avg_time_microseconds
        Error(_) -> 1.0
      }

      print_rankings(sorted, fastest, 0)
    }
  }
}

fn print_rankings(
  results: List(BenchmarkResult),
  fastest: Float,
  index: Int,
) -> Nil {
  case results {
    [] -> Nil
    [result, ..rest] -> {
      let ratio = result.avg_time_microseconds /. fastest
      let medal = case index {
        0 -> "🥇"
        1 -> "🥈"
        2 -> "🥉"
        _ -> "  "
      }

      io.println(
        medal
        <> " "
        <> string.pad_end(result.name, to: 30, with: " ")
        <> format_time_precise(result.avg_time_microseconds)
        <> "  ("
        <> float.to_string(ratio)
        <> "x)",
      )
      print_rankings(rest, fastest, index + 1)
    }
  }
}
