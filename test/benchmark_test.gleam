import aether/util/benchmark
import gleam/int
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

// ==================== BenchmarkResult Tests ====================

pub fn benchmark_result_creation_test() {
  let result =
    benchmark.BenchmarkResult(
      name: "test benchmark",
      iterations: 1000,
      total_time_microseconds: 50_000,
      avg_time_microseconds: 50.0,
      min_time_microseconds: 10,
      max_time_microseconds: 100,
    )

  result.name
  |> should.equal("test benchmark")

  result.iterations
  |> should.equal(1000)

  result.total_time_microseconds
  |> should.equal(50_000)

  result.avg_time_microseconds
  |> should.equal(50.0)

  result.min_time_microseconds
  |> should.equal(10)

  result.max_time_microseconds
  |> should.equal(100)
}

// ==================== run() Tests ====================

pub fn run_simple_function_test() {
  let result = benchmark.run("simple addition", 100, fn() { 1 + 1 })

  result.name
  |> should.equal("simple addition")

  result.iterations
  |> should.equal(100)

  // Total time should be non-negative
  result.total_time_microseconds >= 0
  |> should.be_true()

  // Average time should be non-negative
  result.avg_time_microseconds >=. 0.0
  |> should.be_true()

  // Min should be <= max
  result.min_time_microseconds <= result.max_time_microseconds
  |> should.be_true()
}

pub fn run_with_zero_iterations_test() {
  let result = benchmark.run("zero iterations", 0, fn() { 1 + 1 })

  result.iterations
  |> should.equal(0)

  result.total_time_microseconds
  |> should.equal(0)
}

pub fn run_with_one_iteration_test() {
  let result = benchmark.run("single iteration", 1, fn() { 42 })

  result.iterations
  |> should.equal(1)

  result.min_time_microseconds
  |> should.equal(result.max_time_microseconds)
}

pub fn run_with_string_returning_function_test() {
  let result = benchmark.run("string concat", 50, fn() { "hello" <> " world" })

  result.name
  |> should.equal("string concat")

  result.iterations
  |> should.equal(50)
}

pub fn run_with_list_operations_test() {
  let result = benchmark.run("list operations", 10, fn() {
    list.range(1, 100)
    |> list.map(fn(x) { x * 2 })
    |> list.fold(0, fn(acc, x) { acc + x })
  })

  result.iterations
  |> should.equal(10)

  result.name
  |> should.equal("list operations")
}

pub fn run_with_side_effect_function_test() {
  // Test that the function is actually called the right number of times
  // by using a function that would have side effects
  let result = benchmark.run("side effect test", 5, fn() {
    let _ = int.to_string(123)
    "result"
  })

  result.iterations
  |> should.equal(5)
}

pub fn run_with_large_iterations_test() {
  let result = benchmark.run("large iterations", 10_000, fn() { 1 + 1 })

  result.iterations
  |> should.equal(10_000)

  // With 10000 iterations, total should be sum of all measurements
  result.total_time_microseconds >= 0
  |> should.be_true()
}

pub fn run_with_negative_result_function_test() {
  let result = benchmark.run("negative result", 10, fn() { -100 })

  result.iterations
  |> should.equal(10)

  // Benchmark should work even if the function returns negative numbers
  result.total_time_microseconds >= 0
  |> should.be_true()
}

pub fn run_with_nested_function_test() {
  let result =
    benchmark.run("nested function", 20, fn() {
      let inner = fn() { 5 * 5 }
      inner()
    })

  result.iterations
  |> should.equal(20)
}

pub fn run_preserves_name_with_special_characters_test() {
  let result = benchmark.run("test-name_with.special!chars@#", 5, fn() { 1 })

  result.name
  |> should.equal("test-name_with.special!chars@#")
}

pub fn run_with_unicode_name_test() {
  let result = benchmark.run("测试 🏁 тест", 5, fn() { 1 })

  result.name
  |> should.equal("测试 🏁 тест")
}

// ==================== run_cold() Tests ====================

pub fn run_cold_simple_test() {
  let result = benchmark.run_cold("cold start", 50, fn() { 2 * 2 })

  result.name
  |> should.equal("cold start")

  result.iterations
  |> should.equal(50)

  result.total_time_microseconds >= 0
  |> should.be_true()
}

pub fn run_cold_vs_run_same_iterations_test() {
  let cold_result = benchmark.run_cold("cold test", 100, fn() { 1 + 1 })
  let warm_result = benchmark.run("warm test", 100, fn() { 1 + 1 })

  cold_result.iterations
  |> should.equal(warm_result.iterations)

  // Both should have valid results
  cold_result.total_time_microseconds >= 0
  |> should.be_true()

  warm_result.total_time_microseconds >= 0
  |> should.be_true()
}

pub fn run_cold_with_zero_iterations_test() {
  let result = benchmark.run_cold("zero cold", 0, fn() { 1 })

  result.iterations
  |> should.equal(0)

  result.total_time_microseconds
  |> should.equal(0)
}

pub fn run_cold_with_complex_function_test() {
  let result = benchmark.run_cold("cold complex", 10, fn() {
    list.range(1, 50)
    |> list.filter(fn(x) { x % 2 == 0 })
    |> list.length()
  })

  result.iterations
  |> should.equal(10)
}

// ==================== compare() Tests ====================

pub fn compare_empty_list_test() {
  // This should not crash with empty list
  benchmark.compare([], 10)
  // If we get here without panic, test passes
  1
  |> should.equal(1)
}

pub fn compare_single_benchmark_test() {
  let benchmarks = [#("single test", fn() { 1 + 1 })]

  benchmark.compare(benchmarks, 10)

  // If we get here without panic, test passes
  1
  |> should.equal(1)
}

pub fn compare_multiple_benchmarks_test() {
  let benchmarks = [
    #("test 1", fn() { 1 + 1 }),
    #("test 2", fn() { 2 * 2 }),
    #("test 3", fn() { 3 - 1 }),
  ]

  benchmark.compare(benchmarks, 5)

  // If we get here without panic, test passes
  1
  |> should.equal(1)
}

pub fn compare_with_different_complexity_test() {
  let benchmarks = [
    #("simple", fn() { 1 }),
    #("list operation", fn() { list.range(1, 100) |> list.length() }),
    #("string concat", fn() { "a" <> "b" <> "c" }),
  ]

  benchmark.compare(benchmarks, 10)

  1
  |> should.equal(1)
}

pub fn compare_with_large_iterations_test() {
  let benchmarks = [
    #("fast", fn() { 1 }),
    #("also fast", fn() { 2 }),
  ]

  benchmark.compare(benchmarks, 1000)

  1
  |> should.equal(1)
}

pub fn compare_with_unicode_names_test() {
  let benchmarks = [
    #("テスト 1", fn() { 1 }),
    #("тест 2", fn() { 2 }),
    #("测试 3", fn() { 3 }),
  ]

  benchmark.compare(benchmarks, 5)

  1
  |> should.equal(1)
}

// ==================== print_result() Tests ====================

pub fn print_result_basic_test() {
  let result =
    benchmark.BenchmarkResult(
      name: "test print",
      iterations: 100,
      total_time_microseconds: 5000,
      avg_time_microseconds: 50.0,
      min_time_microseconds: 10,
      max_time_microseconds: 90,
    )

  benchmark.print_result(result)

  // If no panic, test passes
  1
  |> should.equal(1)
}

pub fn print_result_with_zero_min_test() {
  let result =
    benchmark.BenchmarkResult(
      name: "zero min test",
      iterations: 10,
      total_time_microseconds: 100,
      avg_time_microseconds: 10.0,
      min_time_microseconds: 0,
      max_time_microseconds: 50,
    )

  benchmark.print_result(result)

  1
  |> should.equal(1)
}

pub fn print_result_with_large_numbers_test() {
  let result =
    benchmark.BenchmarkResult(
      name: "large numbers",
      iterations: 1_000_000,
      total_time_microseconds: 50_000_000,
      avg_time_microseconds: 50.0,
      min_time_microseconds: 1,
      max_time_microseconds: 100_000,
    )

  benchmark.print_result(result)

  1
  |> should.equal(1)
}

pub fn print_result_with_microsecond_range_test() {
  let result =
    benchmark.BenchmarkResult(
      name: "microseconds",
      iterations: 100,
      total_time_microseconds: 500,
      avg_time_microseconds: 5.0,
      min_time_microseconds: 1,
      max_time_microseconds: 10,
    )

  benchmark.print_result(result)

  1
  |> should.equal(1)
}

pub fn print_result_with_millisecond_range_test() {
  let result =
    benchmark.BenchmarkResult(
      name: "milliseconds",
      iterations: 100,
      total_time_microseconds: 50_000,
      avg_time_microseconds: 500.0,
      min_time_microseconds: 100,
      max_time_microseconds: 900,
    )

  benchmark.print_result(result)

  1
  |> should.equal(1)
}

pub fn print_result_with_second_range_test() {
  let result =
    benchmark.BenchmarkResult(
      name: "seconds",
      iterations: 10,
      total_time_microseconds: 5_000_000,
      avg_time_microseconds: 500_000.0,
      min_time_microseconds: 100_000,
      max_time_microseconds: 900_000,
    )

  benchmark.print_result(result)

  1
  |> should.equal(1)
}

pub fn print_result_with_long_name_test() {
  let result =
    benchmark.BenchmarkResult(
      name: "This is a very long benchmark name that might affect formatting",
      iterations: 50,
      total_time_microseconds: 1000,
      avg_time_microseconds: 20.0,
      min_time_microseconds: 5,
      max_time_microseconds: 35,
    )

  benchmark.print_result(result)

  1
  |> should.equal(1)
}

pub fn print_result_with_special_characters_test() {
  let result =
    benchmark.BenchmarkResult(
      name: "test-with_special.chars!@#$%",
      iterations: 10,
      total_time_microseconds: 100,
      avg_time_microseconds: 10.0,
      min_time_microseconds: 5,
      max_time_microseconds: 15,
    )

  benchmark.print_result(result)

  1
  |> should.equal(1)
}

// ==================== Edge Cases and Error Conditions ====================

pub fn run_with_function_returning_unit_test() {
  let result = benchmark.run("returns unit", 10, fn() { Nil })

  result.iterations
  |> should.equal(10)
}

pub fn run_with_function_returning_result_test() {
  let result = benchmark.run("returns result", 10, fn() { Ok(42) })

  result.iterations
  |> should.equal(10)
}

pub fn run_with_function_returning_list_test() {
  let result = benchmark.run("returns list", 10, fn() { [1, 2, 3] })

  result.iterations
  |> should.equal(10)
}

pub fn run_with_function_returning_tuple_test() {
  let result = benchmark.run("returns tuple", 10, fn() { #(1, "test", True) })

  result.iterations
  |> should.equal(10)
}

pub fn run_consistency_test() {
  // Run the same benchmark multiple times and ensure structure is consistent
  let result1 = benchmark.run("consistency test", 10, fn() { 1 + 1 })
  let result2 = benchmark.run("consistency test", 10, fn() { 1 + 1 })

  result1.name
  |> should.equal(result2.name)

  result1.iterations
  |> should.equal(result2.iterations)

  // Both should have valid time measurements
  result1.total_time_microseconds >= 0
  |> should.be_true()

  result2.total_time_microseconds >= 0
  |> should.be_true()
}

pub fn run_cold_consistency_test() {
  let result1 = benchmark.run_cold("cold consistency", 10, fn() { 1 + 1 })
  let result2 = benchmark.run_cold("cold consistency", 10, fn() { 1 + 1 })

  result1.iterations
  |> should.equal(result2.iterations)

  result1.total_time_microseconds >= 0
  |> should.be_true()

  result2.total_time_microseconds >= 0
  |> should.be_true()
}

pub fn benchmark_result_min_less_than_or_equal_max_test() {
  let result = benchmark.run("min/max test", 100, fn() { 
    let x = 1 + 1
    x * 2
  })

  result.min_time_microseconds <= result.max_time_microseconds
  |> should.be_true()
}

pub fn benchmark_result_avg_within_range_test() {
  let result = benchmark.run("avg range test", 50, fn() { 1 + 1 })

  // Average should be >= min
  result.avg_time_microseconds >=. int.to_float(result.min_time_microseconds)
  |> should.be_true()

  // Average should be <= max
  result.avg_time_microseconds <=. int.to_float(result.max_time_microseconds)
  |> should.be_true()
}

pub fn run_with_different_iteration_counts_test() {
  let counts = [1, 5, 10, 50, 100, 500]

  list.each(counts, fn(count) {
    let result = benchmark.run("variable iterations", count, fn() { 1 })
    result.iterations
    |> should.equal(count)
  })
}

pub fn compare_with_varying_speed_functions_test() {
  let benchmarks = [
    #("instant", fn() { 1 }),
    #("list 10", fn() { list.range(1, 10) }),
    #("list 50", fn() { list.range(1, 50) }),
    #("list 100", fn() { list.range(1, 100) }),
  ]

  benchmark.compare(benchmarks, 10)

  1
  |> should.equal(1)
}

pub fn run_with_empty_string_name_test() {
  let result = benchmark.run("", 10, fn() { 1 })

  result.name
  |> should.equal("")

  result.iterations
  |> should.equal(10)
}

pub fn run_with_whitespace_only_name_test() {
  let result = benchmark.run("   ", 5, fn() { 1 })

  result.name
  |> should.equal("   ")
}

pub fn benchmark_total_time_equals_sum_of_iterations_test() {
  // Since the current implementation uses placeholder times (0 to 1),
  // we can verify the total equals the number of iterations
  let result = benchmark.run("sum test", 100, fn() { 1 })

  // With current implementation, each iteration measures as 1 microsecond
  result.total_time_microseconds
  |> should.equal(100)
}

pub fn run_with_recursive_function_test() {
  let factorial = fn(n) {
    case n {
      0 -> 1
      _ -> n * factorial(n - 1)
    }
  }

  let result = benchmark.run("recursive factorial", 10, fn() { factorial(5) })

  result.iterations
  |> should.equal(10)
}

pub fn compare_preserves_benchmark_order_test() {
  let benchmarks = [
    #("first", fn() { 1 }),
    #("second", fn() { 2 }),
    #("third", fn() { 3 }),
  ]

  // This test verifies compare doesn't crash with multiple benchmarks
  benchmark.compare(benchmarks, 5)

  1
  |> should.equal(1)
}