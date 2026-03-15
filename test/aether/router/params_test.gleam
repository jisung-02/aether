// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Params Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Unit tests for the route parameters module.
//

import aether/router/params
import gleam/dict
import gleam/option
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_creates_empty_params_test() {
  let p = params.new()

  params.is_empty(p)
  |> should.be_true()

  params.path_count(p)
  |> should.equal(0)

  params.query_count(p)
  |> should.equal(0)
}

pub fn from_path_creates_params_with_path_test() {
  let path_dict = dict.from_list([#("id", "42"), #("name", "test")])
  let p = params.from_path(path_dict)

  params.path_count(p)
  |> should.equal(2)

  params.query_count(p)
  |> should.equal(0)
}

pub fn from_both_creates_params_with_both_test() {
  let path_dict = dict.from_list([#("id", "42")])
  let query_dict = dict.from_list([#("page", "1")])
  let p = params.from_both(path_dict, query_dict)

  params.path_count(p)
  |> should.equal(1)

  params.query_count(p)
  |> should.equal(1)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Path Parameter Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn get_returns_existing_param_test() {
  let p =
    params.new()
    |> params.set("id", "42")

  params.get(p, "id")
  |> should.equal(option.Some("42"))
}

pub fn get_returns_none_for_missing_param_test() {
  let p = params.new()

  params.get(p, "id")
  |> should.equal(option.None)
}

pub fn get_int_returns_parsed_int_test() {
  let p =
    params.new()
    |> params.set("id", "42")

  params.get_int(p, "id")
  |> should.equal(option.Some(42))
}

pub fn get_int_returns_none_for_invalid_int_test() {
  let p =
    params.new()
    |> params.set("id", "not-a-number")

  params.get_int(p, "id")
  |> should.equal(option.None)
}

pub fn get_int_returns_none_for_missing_param_test() {
  let p = params.new()

  params.get_int(p, "id")
  |> should.equal(option.None)
}

pub fn get_int_handles_negative_numbers_test() {
  let p =
    params.new()
    |> params.set("offset", "-10")

  params.get_int(p, "offset")
  |> should.equal(option.Some(-10))
}

pub fn get_int_handles_zero_test() {
  let p =
    params.new()
    |> params.set("page", "0")

  params.get_int(p, "page")
  |> should.equal(option.Some(0))
}

pub fn set_updates_param_test() {
  let p =
    params.new()
    |> params.set("id", "42")
    |> params.set("id", "100")

  params.get(p, "id")
  |> should.equal(option.Some("100"))
}

pub fn has_returns_true_for_existing_param_test() {
  let p =
    params.new()
    |> params.set("id", "42")

  params.has(p, "id")
  |> should.be_true()
}

pub fn has_returns_false_for_missing_param_test() {
  let p = params.new()

  params.has(p, "id")
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Query Parameter Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn get_query_returns_existing_param_test() {
  let p =
    params.new()
    |> params.set_query("page", "5")

  params.get_query(p, "page")
  |> should.equal(option.Some("5"))
}

pub fn get_query_returns_none_for_missing_param_test() {
  let p = params.new()

  params.get_query(p, "page")
  |> should.equal(option.None)
}

pub fn get_query_int_returns_parsed_int_test() {
  let p =
    params.new()
    |> params.set_query("page", "5")

  params.get_query_int(p, "page")
  |> should.equal(option.Some(5))
}

pub fn get_query_int_returns_none_for_invalid_int_test() {
  let p =
    params.new()
    |> params.set_query("page", "invalid")

  params.get_query_int(p, "page")
  |> should.equal(option.None)
}

pub fn has_query_returns_true_for_existing_param_test() {
  let p =
    params.new()
    |> params.set_query("page", "5")

  params.has_query(p, "page")
  |> should.be_true()
}

pub fn has_query_returns_false_for_missing_param_test() {
  let p = params.new()

  params.has_query(p, "page")
  |> should.be_false()
}

pub fn with_query_replaces_query_params_test() {
  let p =
    params.new()
    |> params.set_query("old", "value")

  let new_query = dict.from_list([#("new", "value")])
  let p2 = params.with_query(p, new_query)

  params.has_query(p2, "old")
  |> should.be_false()

  params.has_query(p2, "new")
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Query String Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_query_parses_simple_params_test() {
  let parsed = params.parse_query("name=Alice&age=30")

  dict.get(parsed, "name")
  |> should.equal(Ok("Alice"))

  dict.get(parsed, "age")
  |> should.equal(Ok("30"))
}

pub fn parse_query_handles_empty_string_test() {
  let parsed = params.parse_query("")

  dict.size(parsed)
  |> should.equal(0)
}

pub fn parse_query_handles_single_param_test() {
  let parsed = params.parse_query("key=value")

  dict.get(parsed, "key")
  |> should.equal(Ok("value"))

  dict.size(parsed)
  |> should.equal(1)
}

pub fn parse_query_handles_url_encoded_values_test() {
  let parsed = params.parse_query("q=hello%20world")

  dict.get(parsed, "q")
  |> should.equal(Ok("hello world"))
}

pub fn parse_query_handles_url_encoded_special_chars_test() {
  let parsed = params.parse_query("filter=type%3Apost")

  dict.get(parsed, "filter")
  |> should.equal(Ok("type:post"))
}

pub fn parse_query_handles_plus_as_space_test() {
  let parsed = params.parse_query("q=hello+world")

  dict.get(parsed, "q")
  |> should.equal(Ok("hello world"))
}

pub fn parse_query_handles_empty_value_test() {
  let parsed = params.parse_query("key=")

  dict.get(parsed, "key")
  |> should.equal(Ok(""))
}

pub fn parse_query_handles_key_without_value_test() {
  let parsed = params.parse_query("flag")

  dict.get(parsed, "flag")
  |> should.equal(Ok(""))
}

pub fn parse_query_handles_multiple_params_with_empty_test() {
  let parsed = params.parse_query("a=1&b=&c=3")

  dict.get(parsed, "a")
  |> should.equal(Ok("1"))

  dict.get(parsed, "b")
  |> should.equal(Ok(""))

  dict.get(parsed, "c")
  |> should.equal(Ok("3"))
}

pub fn parse_query_skips_empty_pairs_test() {
  let parsed = params.parse_query("a=1&&b=2")

  dict.size(parsed)
  |> should.equal(2)

  dict.get(parsed, "a")
  |> should.equal(Ok("1"))

  dict.get(parsed, "b")
  |> should.equal(Ok("2"))
}

pub fn parse_query_handles_equals_in_value_test() {
  // Only split on first equals sign
  let parsed = params.parse_query("equation=1+1=2")

  dict.get(parsed, "equation")
  |> should.equal(Ok("1 1=2"))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Utility Function Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn path_keys_returns_all_path_param_names_test() {
  let p =
    params.new()
    |> params.set("id", "1")
    |> params.set("name", "test")

  let keys = params.path_keys(p)

  keys
  |> should.equal(["id", "name"])
}

pub fn query_keys_returns_all_query_param_names_test() {
  let p =
    params.new()
    |> params.set_query("page", "1")
    |> params.set_query("limit", "10")

  let keys = params.query_keys(p)

  keys
  |> should.equal(["limit", "page"])
}

pub fn is_empty_returns_true_for_empty_params_test() {
  let p = params.new()

  params.is_empty(p)
  |> should.be_true()
}

pub fn is_empty_returns_false_when_path_params_exist_test() {
  let p =
    params.new()
    |> params.set("id", "1")

  params.is_empty(p)
  |> should.be_false()
}

pub fn is_empty_returns_false_when_query_params_exist_test() {
  let p =
    params.new()
    |> params.set_query("page", "1")

  params.is_empty(p)
  |> should.be_false()
}
