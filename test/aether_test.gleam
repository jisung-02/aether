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
