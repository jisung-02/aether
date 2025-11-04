import gleam/io
import gleam/string

pub fn assert_ok(result: Result(a, e)) -> a {
  case result {
    Ok(value) -> value
    Error(e) -> {
      io.println("Expected Ok, but got Error: " <> string.inspect(e))
      panic as "assert_ok failed"
    }
  }
}

pub fn assert_error(result: Result(a, e)) -> e {
  case result {
    Error(e) -> e
    Ok(value) -> {
      io.println("Expected Error, but got Ok: " <> string.inspect(value))
      panic as "assert_error failed"
    }
  }
}

pub fn assert_equal(actual: a, expected: a) -> Nil {
  case actual == expected {
    True -> Nil
    False -> {
      io.println("Assertion failed!")
      io.println("Expected: " <> string.inspect(expected))
      io.println("Actual:   " <> string.inspect(actual))
      panic as "assert_equal failed"
    }
  }
}
