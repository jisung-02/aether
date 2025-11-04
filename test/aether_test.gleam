import gleeunit
import gleeunit/should
import test_helper

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn basic_math_test() {
  1 + 1
  |> should.equal(2)
}

pub fn test_helper_assert_ok_test() {
  Ok(42)
  |> test_helper.assert_ok()
  |> should.equal(42)
}

// ==================== test_helper.assert_ok Tests ====================

pub fn assert_ok_with_int_test() {
  Ok(100)
  |> test_helper.assert_ok()
  |> should.equal(100)
}

pub fn assert_ok_with_string_test() {
  Ok("success")
  |> test_helper.assert_ok()
  |> should.equal("success")
}

pub fn assert_ok_with_list_test() {
  Ok([1, 2, 3])
  |> test_helper.assert_ok()
  |> should.equal([1, 2, 3])
}

pub fn assert_ok_with_tuple_test() {
  Ok(#(1, "test"))
  |> test_helper.assert_ok()
  |> should.equal(#(1, "test"))
}

pub fn assert_ok_with_bool_test() {
  Ok(True)
  |> test_helper.assert_ok()
  |> should.equal(True)
}

pub fn assert_ok_with_nil_test() {
  Ok(Nil)
  |> test_helper.assert_ok()
  |> should.equal(Nil)
}

pub fn assert_ok_with_nested_result_test() {
  Ok(Ok(42))
  |> test_helper.assert_ok()
  |> should.equal(Ok(42))
}

pub fn assert_ok_with_float_test() {
  Ok(3.14)
  |> test_helper.assert_ok()
  |> should.equal(3.14)
}

pub fn assert_ok_with_negative_number_test() {
  Ok(-42)
  |> test_helper.assert_ok()
  |> should.equal(-42)
}

pub fn assert_ok_with_empty_list_test() {
  Ok([])
  |> test_helper.assert_ok()
  |> should.equal([])
}

pub fn assert_ok_with_complex_tuple_test() {
  Ok(#(1, "test", True, [1, 2]))
  |> test_helper.assert_ok()
  |> should.equal(#(1, "test", True, [1, 2]))
}

// ==================== test_helper.assert_error Tests ====================

pub fn assert_error_with_string_error_test() {
  Error("failure")
  |> test_helper.assert_error()
  |> should.equal("failure")
}

pub fn assert_error_with_int_error_test() {
  Error(404)
  |> test_helper.assert_error()
  |> should.equal(404)
}

pub fn assert_error_with_nil_error_test() {
  Error(Nil)
  |> test_helper.assert_error()
  |> should.equal(Nil)
}

pub fn assert_error_with_tuple_error_test() {
  Error(#("error", 500))
  |> test_helper.assert_error()
  |> should.equal(#("error", 500))
}

pub fn assert_error_with_list_error_test() {
  Error(["error1", "error2"])
  |> test_helper.assert_error()
  |> should.equal(["error1", "error2"])
}

pub fn assert_error_with_nested_result_test() {
  Error(Error("nested"))
  |> test_helper.assert_error()
  |> should.equal(Error("nested"))
}

pub fn assert_error_with_bool_error_test() {
  Error(False)
  |> test_helper.assert_error()
  |> should.equal(False)
}

pub fn assert_error_with_empty_string_error_test() {
  Error("")
  |> test_helper.assert_error()
  |> should.equal("")
}

// ==================== test_helper.assert_equal Tests ====================

pub fn assert_equal_integers_test() {
  test_helper.assert_equal(42, 42)
  // If we get here without panic, test passes
  1
  |> should.equal(1)
}

pub fn assert_equal_strings_test() {
  test_helper.assert_equal("hello", "hello")
  1
  |> should.equal(1)
}

pub fn assert_equal_bools_true_test() {
  test_helper.assert_equal(True, True)
  1
  |> should.equal(1)
}

pub fn assert_equal_bools_false_test() {
  test_helper.assert_equal(False, False)
  1
  |> should.equal(1)
}

pub fn assert_equal_nil_test() {
  test_helper.assert_equal(Nil, Nil)
  1
  |> should.equal(1)
}

pub fn assert_equal_lists_test() {
  test_helper.assert_equal([1, 2, 3], [1, 2, 3])
  1
  |> should.equal(1)
}

pub fn assert_equal_empty_lists_test() {
  test_helper.assert_equal([], [])
  1
  |> should.equal(1)
}

pub fn assert_equal_tuples_test() {
  test_helper.assert_equal(#(1, "test"), #(1, "test"))
  1
  |> should.equal(1)
}

pub fn assert_equal_nested_tuples_test() {
  test_helper.assert_equal(#(1, #(2, 3)), #(1, #(2, 3)))
  1
  |> should.equal(1)
}

pub fn assert_equal_floats_test() {
  test_helper.assert_equal(3.14, 3.14)
  1
  |> should.equal(1)
}

pub fn assert_equal_negative_numbers_test() {
  test_helper.assert_equal(-42, -42)
  1
  |> should.equal(1)
}

pub fn assert_equal_zero_test() {
  test_helper.assert_equal(0, 0)
  1
  |> should.equal(1)
}

pub fn assert_equal_empty_strings_test() {
  test_helper.assert_equal("", "")
  1
  |> should.equal(1)
}

pub fn assert_equal_unicode_strings_test() {
  test_helper.assert_equal("hello 世界 🌍", "hello 世界 🌍")
  1
  |> should.equal(1)
}

pub fn assert_equal_ok_results_test() {
  test_helper.assert_equal(Ok(42), Ok(42))
  1
  |> should.equal(1)
}

pub fn assert_equal_error_results_test() {
  test_helper.assert_equal(Error("fail"), Error("fail"))
  1
  |> should.equal(1)
}

pub fn assert_equal_nested_lists_test() {
  test_helper.assert_equal([[1, 2], [3, 4]], [[1, 2], [3, 4]])
  1
  |> should.equal(1)
}

pub fn assert_equal_complex_structure_test() {
  let value = #(Ok([1, 2]), "test", True)
  test_helper.assert_equal(value, value)
  1
  |> should.equal(1)
}

// ==================== Integration Tests ====================

pub fn assert_ok_then_assert_equal_test() {
  let value =
    Ok(42)
    |> test_helper.assert_ok()

  test_helper.assert_equal(value, 42)
  1
  |> should.equal(1)
}

pub fn assert_error_then_assert_equal_test() {
  let error =
    Error("fail")
    |> test_helper.assert_error()

  test_helper.assert_equal(error, "fail")
  1
  |> should.equal(1)
}

pub fn chained_assert_ok_test() {
  Ok(Ok(42))
  |> test_helper.assert_ok()
  |> test_helper.assert_ok()
  |> should.equal(42)
}

pub fn assert_ok_with_should_equal_test() {
  Ok(100)
  |> test_helper.assert_ok()
  |> should.equal(100)
}

pub fn assert_error_with_should_equal_test() {
  Error(404)
  |> test_helper.assert_error()
  |> should.equal(404)
}

// ==================== Edge Cases ====================

pub fn assert_equal_large_numbers_test() {
  test_helper.assert_equal(999_999_999, 999_999_999)
  1
  |> should.equal(1)
}

pub fn assert_equal_very_small_floats_test() {
  test_helper.assert_equal(0.0000001, 0.0000001)
  1
  |> should.equal(1)
}

pub fn assert_equal_long_strings_test() {
  let long_string =
    "This is a very long string that contains many characters and should still work correctly with assert_equal"
  test_helper.assert_equal(long_string, long_string)
  1
  |> should.equal(1)
}

pub fn assert_equal_list_with_many_elements_test() {
  let long_list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  test_helper.assert_equal(long_list, long_list)
  1
  |> should.equal(1)
}

pub fn assert_ok_preserves_type_test() {
  // Ensure assert_ok returns the exact type
  let result: String =
    Ok("test")
    |> test_helper.assert_ok()

  result
  |> should.equal("test")
}

pub fn assert_error_preserves_type_test() {
  // Ensure assert_error returns the exact error type
  let error: Int =
    Error(404)
    |> test_helper.assert_error()

  error
  |> should.equal(404)
}

pub fn multiple_assert_ok_in_sequence_test() {
  Ok(1)
  |> test_helper.assert_ok()
  |> should.equal(1)

  Ok(2)
  |> test_helper.assert_ok()
  |> should.equal(2)

  Ok(3)
  |> test_helper.assert_ok()
  |> should.equal(3)
}

pub fn multiple_assert_error_in_sequence_test() {
  Error("a")
  |> test_helper.assert_error()
  |> should.equal("a")

  Error("b")
  |> test_helper.assert_error()
  |> should.equal("b")

  Error("c")
  |> test_helper.assert_error()
  |> should.equal("c")
}

pub fn assert_equal_after_computation_test() {
  let result = 10 * 5
  test_helper.assert_equal(result, 50)
  1
  |> should.equal(1)
}

pub fn assert_ok_with_computation_test() {
  Ok(10 + 20)
  |> test_helper.assert_ok()
  |> should.equal(30)
}