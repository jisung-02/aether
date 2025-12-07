// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pattern Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Unit tests for the path pattern module.
//

import aether/router/params
import aether/router/pattern
import gleam/list
import gleam/option
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pattern Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_static_pattern_test() {
  let pat = pattern.parse("/users/list")

  pattern.segment_count(pat)
  |> should.equal(2)

  pattern.is_static(pat)
  |> should.be_true()
}

pub fn parse_single_dynamic_pattern_test() {
  let pat = pattern.parse("/users/:id")

  pattern.segment_count(pat)
  |> should.equal(2)

  pattern.is_static(pat)
  |> should.be_false()

  pattern.param_names(pat)
  |> should.equal(["id"])
}

pub fn parse_multiple_dynamic_pattern_test() {
  let pat = pattern.parse("/users/:user_id/posts/:post_id")

  pattern.segment_count(pat)
  |> should.equal(4)

  pattern.param_names(pat)
  |> should.equal(["user_id", "post_id"])
}

pub fn parse_wildcard_pattern_test() {
  let pat = pattern.parse("/files/*")

  pattern.segment_count(pat)
  |> should.equal(2)

  pattern.has_wildcard(pat)
  |> should.be_true()
}

pub fn parse_root_pattern_test() {
  let pat = pattern.parse("/")

  pattern.segment_count(pat)
  |> should.equal(0)

  pattern.is_static(pat)
  |> should.be_true()
}

pub fn parse_empty_pattern_test() {
  let pat = pattern.parse("")

  pattern.segment_count(pat)
  |> should.equal(0)
}

pub fn parse_no_leading_slash_test() {
  let pat = pattern.parse("users/:id")

  pattern.segment_count(pat)
  |> should.equal(2)

  pattern.param_names(pat)
  |> should.equal(["id"])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Static Matching Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn match_static_path_exact_test() {
  let pat = pattern.parse("/users/list")

  pattern.match(pat, "/users/list")
  |> option.is_some()
  |> should.be_true()
}

pub fn match_static_path_mismatch_test() {
  let pat = pattern.parse("/users/list")

  pattern.match(pat, "/users/other")
  |> option.is_none()
  |> should.be_true()
}

pub fn match_root_path_test() {
  let pat = pattern.parse("/")

  pattern.match(pat, "/")
  |> option.is_some()
  |> should.be_true()
}

pub fn match_root_path_mismatch_test() {
  let pat = pattern.parse("/")

  pattern.match(pat, "/users")
  |> option.is_none()
  |> should.be_true()
}

pub fn match_static_shorter_path_test() {
  let pat = pattern.parse("/users/list/all")

  pattern.match(pat, "/users/list")
  |> option.is_none()
  |> should.be_true()
}

pub fn match_static_longer_path_test() {
  let pat = pattern.parse("/users")

  pattern.match(pat, "/users/list")
  |> option.is_none()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Dynamic Matching Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn match_dynamic_extracts_param_test() {
  let pat = pattern.parse("/users/:id")

  let result = pattern.match(pat, "/users/123")

  result
  |> option.is_some()
  |> should.be_true()

  case result {
    option.Some(p) -> {
      params.get(p, "id")
      |> should.equal(option.Some("123"))
    }
    option.None -> should.fail()
  }
}

pub fn match_dynamic_extracts_string_param_test() {
  let pat = pattern.parse("/users/:username")

  case pattern.match(pat, "/users/alice") {
    option.Some(p) -> {
      params.get(p, "username")
      |> should.equal(option.Some("alice"))
    }
    option.None -> should.fail()
  }
}

pub fn match_multiple_dynamic_params_test() {
  let pat = pattern.parse("/users/:user_id/posts/:post_id")

  case pattern.match(pat, "/users/42/posts/7") {
    option.Some(p) -> {
      params.get(p, "user_id")
      |> should.equal(option.Some("42"))

      params.get(p, "post_id")
      |> should.equal(option.Some("7"))
    }
    option.None -> should.fail()
  }
}

pub fn match_mixed_static_dynamic_test() {
  let pat = pattern.parse("/api/v1/users/:id/profile")

  case pattern.match(pat, "/api/v1/users/123/profile") {
    option.Some(p) -> {
      params.get(p, "id")
      |> should.equal(option.Some("123"))
    }
    option.None -> should.fail()
  }
}

pub fn match_dynamic_wrong_static_segment_test() {
  let pat = pattern.parse("/users/:id")

  pattern.match(pat, "/posts/123")
  |> option.is_none()
  |> should.be_true()
}

pub fn match_dynamic_missing_segment_test() {
  let pat = pattern.parse("/users/:id/posts")

  pattern.match(pat, "/users/123")
  |> option.is_none()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Wildcard Matching Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn wildcard_matches_single_segment_test() {
  let pat = pattern.parse("/files/*")

  pattern.match(pat, "/files/readme.txt")
  |> option.is_some()
  |> should.be_true()
}

pub fn wildcard_matches_multiple_segments_test() {
  let pat = pattern.parse("/files/*")

  pattern.match(pat, "/files/docs/api/readme.txt")
  |> option.is_some()
  |> should.be_true()
}

pub fn wildcard_matches_empty_remaining_test() {
  let pat = pattern.parse("/files/*")

  // /files/ with nothing after - wildcard matches empty
  pattern.match(pat, "/files/")
  |> option.is_some()
  |> should.be_true()
}

pub fn wildcard_requires_prefix_match_test() {
  let pat = pattern.parse("/files/*")

  pattern.match(pat, "/docs/readme.txt")
  |> option.is_none()
  |> should.be_true()
}

pub fn wildcard_at_root_matches_everything_test() {
  let pat = pattern.parse("/*")

  pattern.match(pat, "/anything/goes/here")
  |> option.is_some()
  |> should.be_true()
}

pub fn wildcard_with_dynamic_prefix_test() {
  let pat = pattern.parse("/users/:id/files/*")

  case pattern.match(pat, "/users/42/files/docs/readme.txt") {
    option.Some(p) -> {
      params.get(p, "id")
      |> should.equal(option.Some("42"))
    }
    option.None -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Edge Case Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn match_trailing_slash_mismatch_test() {
  let pat = pattern.parse("/users")

  // Without trailing slash handling, these should not match
  pattern.match(pat, "/users/")
  |> option.is_none()
  |> should.be_true()
}

pub fn match_case_sensitive_test() {
  let pat = pattern.parse("/Users")

  pattern.match(pat, "/users")
  |> option.is_none()
  |> should.be_true()
}

pub fn match_special_characters_in_param_test() {
  let pat = pattern.parse("/files/:filename")

  case pattern.match(pat, "/files/my-file_v2.0.txt") {
    option.Some(p) -> {
      params.get(p, "filename")
      |> should.equal(option.Some("my-file_v2.0.txt"))
    }
    option.None -> should.fail()
  }
}

pub fn match_numeric_static_segment_test() {
  let pat = pattern.parse("/api/v1/users")

  pattern.match(pat, "/api/v1/users")
  |> option.is_some()
  |> should.be_true()
}

pub fn match_empty_dynamic_value_not_allowed_test() {
  // Empty segment should not match - the segment would just be missing
  let pat = pattern.parse("/users/:id/posts")

  pattern.match(pat, "/users//posts")
  |> option.is_none()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pattern Inspection Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn is_static_for_static_pattern_test() {
  let pat = pattern.parse("/users/list")

  pattern.is_static(pat)
  |> should.be_true()
}

pub fn is_static_for_dynamic_pattern_test() {
  let pat = pattern.parse("/users/:id")

  pattern.is_static(pat)
  |> should.be_false()
}

pub fn is_static_for_wildcard_pattern_test() {
  let pat = pattern.parse("/files/*")

  pattern.is_static(pat)
  |> should.be_false()
}

pub fn has_wildcard_positive_test() {
  let pat = pattern.parse("/files/*")

  pattern.has_wildcard(pat)
  |> should.be_true()
}

pub fn has_wildcard_negative_test() {
  let pat = pattern.parse("/users/:id")

  pattern.has_wildcard(pat)
  |> should.be_false()
}

pub fn param_names_empty_for_static_test() {
  let pat = pattern.parse("/users/list")

  pattern.param_names(pat)
  |> list.length()
  |> should.equal(0)
}

pub fn param_names_for_dynamic_test() {
  let pat = pattern.parse("/users/:id")

  pattern.param_names(pat)
  |> should.equal(["id"])
}

pub fn param_names_preserves_order_test() {
  let pat = pattern.parse("/a/:first/b/:second/c/:third")

  pattern.param_names(pat)
  |> should.equal(["first", "second", "third"])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pattern to_string Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn to_string_static_test() {
  let pat = pattern.parse("/users/list")

  pattern.to_string(pat)
  |> should.equal("/users/list")
}

pub fn to_string_dynamic_test() {
  let pat = pattern.parse("/users/:id")

  pattern.to_string(pat)
  |> should.equal("/users/:id")
}

pub fn to_string_wildcard_test() {
  let pat = pattern.parse("/files/*")

  pattern.to_string(pat)
  |> should.equal("/files/*")
}

pub fn to_string_root_test() {
  let pat = pattern.parse("/")

  pattern.to_string(pat)
  |> should.equal("/")
}

pub fn to_string_complex_test() {
  let pat = pattern.parse("/api/v1/users/:id/files/*")

  pattern.to_string(pat)
  |> should.equal("/api/v1/users/:id/files/*")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Specificity Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn compare_specificity_static_more_specific_than_dynamic_test() {
  let static_pat = pattern.parse("/users/list")
  let dynamic_pat = pattern.parse("/users/:id")

  // Negative means first is more specific
  let result = pattern.compare_specificity(static_pat, dynamic_pat)

  { result < 0 }
  |> should.be_true()
}

pub fn compare_specificity_dynamic_more_specific_than_wildcard_test() {
  let dynamic_pat = pattern.parse("/files/:id")
  let wildcard_pat = pattern.parse("/files/*")

  let result = pattern.compare_specificity(dynamic_pat, wildcard_pat)

  { result < 0 }
  |> should.be_true()
}

pub fn compare_specificity_longer_more_specific_test() {
  let short_pat = pattern.parse("/users")
  let long_pat = pattern.parse("/users/list/all")

  let result = pattern.compare_specificity(long_pat, short_pat)

  { result < 0 }
  |> should.be_true()
}
