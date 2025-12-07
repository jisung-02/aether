// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Path Pattern Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides path pattern parsing and matching for dynamic routes.
//
// ## Features
//
// - Static segment matching (exact string match)
// - Dynamic segment matching (`:param` extracts value)
// - Wildcard matching (`*` matches remaining path)
//
// ## Pattern Syntax
//
// - `/users` - static path
// - `/users/:id` - dynamic segment, captures "id"
// - `/users/:id/posts/:post_id` - multiple dynamic segments
// - `/files/*` - wildcard, matches everything after
//
// ## Usage
//
// ```gleam
// let pattern = pattern.parse("/users/:id")
// case pattern.match(pattern, "/users/42") {
//   option.Some(params) -> params.get(params, "id")  // Some("42")
//   option.None -> // no match
// }
// ```
//

import aether/router/params.{type Params}
import gleam/list
import gleam/option.{type Option}
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// A parsed path pattern
///
/// Contains a list of segments that define how to match
/// and extract parameters from request paths.
///
pub type PathPattern {
  PathPattern(segments: List(Segment))
}

/// A single segment in a path pattern
///
/// ## Variants
///
/// - `Static`: Matches an exact string value
/// - `Dynamic`: Matches any value and captures it with the given name
/// - `Wildcard`: Matches any remaining path segments
///
pub type Segment {
  Static(value: String)
  Dynamic(name: String)
  Wildcard
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pattern Parsing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses a path pattern string into a PathPattern
///
/// ## Parameters
///
/// - `pattern`: The pattern string (e.g., "/users/:id")
///
/// ## Returns
///
/// A PathPattern containing the parsed segments
///
/// ## Examples
///
/// ```gleam
/// pattern.parse("/users/:id")
/// // PathPattern([Static("users"), Dynamic("id")])
///
/// pattern.parse("/files/*")
/// // PathPattern([Static("files"), Wildcard])
/// ```
///
pub fn parse(pattern: String) -> PathPattern {
  let segments =
    pattern
    |> string.split("/")
    |> list.filter(fn(s) { !string.is_empty(s) })
    |> list.map(parse_segment)

  PathPattern(segments: segments)
}

/// Parses a single segment string into a Segment
///
fn parse_segment(segment: String) -> Segment {
  case segment {
    "*" -> Wildcard
    _ -> {
      case string.starts_with(segment, ":") {
        True -> {
          let name = string.drop_start(segment, 1)
          Dynamic(name)
        }
        False -> Static(segment)
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pattern Matching
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Matches a request path against a pattern
///
/// Returns extracted parameters if the path matches the pattern,
/// or None if the path doesn't match.
///
/// ## Parameters
///
/// - `pattern`: The pattern to match against
/// - `path`: The request path to match
///
/// ## Returns
///
/// Option containing the extracted Params if matched
///
/// ## Examples
///
/// ```gleam
/// let pat = pattern.parse("/users/:id")
///
/// pattern.match(pat, "/users/42")
/// // Some(Params with path["id"] = "42")
///
/// pattern.match(pat, "/posts/42")
/// // None
/// ```
///
pub fn match(pattern: PathPattern, path: String) -> Option(Params) {
  // Check trailing slash mismatch (unless pattern has wildcard)
  let pattern_has_trailing = has_wildcard(pattern)
  let path_has_trailing = string.ends_with(path, "/") && path != "/"

  let path_segments =
    path
    |> string.split("/")
    |> list.filter(fn(s) { !string.is_empty(s) })

  // If path has trailing slash but pattern doesn't have wildcard,
  // and path is not empty, this is a mismatch for non-wildcard patterns
  case path_has_trailing, pattern_has_trailing, path_segments {
    // Path has trailing slash, but pattern doesn't have wildcard
    // and path has segments - this should NOT match
    True, False, [_, ..] -> option.None
    // Otherwise, proceed with normal matching
    _, _, _ -> do_match_segments(pattern.segments, path_segments, params.new())
  }
}

/// Recursively matches pattern segments against path segments
///
fn do_match_segments(
  pattern_segments: List(Segment),
  path_segments: List(String),
  acc: Params,
) -> Option(Params) {
  case pattern_segments, path_segments {
    // Both exhausted - successful match
    [], [] -> option.Some(acc)

    // Pattern exhausted but path has more - no match
    [], _ -> option.None

    // Path exhausted but pattern has more - no match
    // (unless pattern only has wildcard remaining)
    [Wildcard], [] -> option.Some(acc)
    _, [] -> option.None

    // Wildcard matches everything remaining
    [Wildcard, ..], _ -> option.Some(acc)

    // Static segment - must match exactly
    [Static(expected), ..rest_pattern], [actual, ..rest_path] -> {
      case expected == actual {
        True -> do_match_segments(rest_pattern, rest_path, acc)
        False -> option.None
      }
    }

    // Dynamic segment - capture the value
    [Dynamic(name), ..rest_pattern], [value, ..rest_path] -> {
      let new_params = params.set(acc, name, value)
      do_match_segments(rest_pattern, rest_path, new_params)
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pattern Inspection
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks if a pattern is static (has no dynamic segments or wildcards)
///
/// ## Parameters
///
/// - `pattern`: The pattern to check
///
/// ## Returns
///
/// True if all segments are static
///
pub fn is_static(pattern: PathPattern) -> Bool {
  list.all(pattern.segments, fn(seg) {
    case seg {
      Static(_) -> True
      _ -> False
    }
  })
}

/// Checks if a pattern has a wildcard
///
/// ## Parameters
///
/// - `pattern`: The pattern to check
///
/// ## Returns
///
/// True if the pattern contains a wildcard
///
pub fn has_wildcard(pattern: PathPattern) -> Bool {
  list.any(pattern.segments, fn(seg) {
    case seg {
      Wildcard -> True
      _ -> False
    }
  })
}

/// Gets the names of all dynamic parameters in a pattern
///
/// ## Parameters
///
/// - `pattern`: The pattern to inspect
///
/// ## Returns
///
/// List of parameter names
///
/// ## Examples
///
/// ```gleam
/// let pat = pattern.parse("/users/:id/posts/:post_id")
/// pattern.param_names(pat)  // ["id", "post_id"]
/// ```
///
pub fn param_names(pattern: PathPattern) -> List(String) {
  list.filter_map(pattern.segments, fn(seg) {
    case seg {
      Dynamic(name) -> Ok(name)
      _ -> Error(Nil)
    }
  })
}

/// Gets the number of segments in a pattern
///
pub fn segment_count(pattern: PathPattern) -> Int {
  list.length(pattern.segments)
}

/// Converts a pattern back to a string representation
///
/// ## Parameters
///
/// - `pattern`: The pattern to convert
///
/// ## Returns
///
/// String representation of the pattern
///
/// ## Examples
///
/// ```gleam
/// let pat = pattern.parse("/users/:id")
/// pattern.to_string(pat)  // "/users/:id"
/// ```
///
pub fn to_string(pattern: PathPattern) -> String {
  let parts =
    list.map(pattern.segments, fn(seg) {
      case seg {
        Static(value) -> value
        Dynamic(name) -> ":" <> name
        Wildcard -> "*"
      }
    })

  "/" <> string.join(parts, "/")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pattern Comparison
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Compares two patterns for specificity
///
/// Returns a comparison value for sorting patterns by specificity:
/// - Static segments are more specific than dynamic
/// - Dynamic segments are more specific than wildcards
/// - More segments are more specific
///
/// ## Parameters
///
/// - `a`: First pattern
/// - `b`: Second pattern
///
/// ## Returns
///
/// - Negative if `a` is more specific than `b`
/// - Positive if `b` is more specific than `a`
/// - Zero if equally specific
///
pub fn compare_specificity(a: PathPattern, b: PathPattern) -> Int {
  let a_score = calculate_specificity(a)
  let b_score = calculate_specificity(b)
  b_score - a_score
}

/// Calculates a specificity score for a pattern
/// Higher score = more specific
///
fn calculate_specificity(pattern: PathPattern) -> Int {
  list.fold(pattern.segments, 0, fn(score, seg) {
    case seg {
      Static(_) -> score + 3
      Dynamic(_) -> score + 2
      Wildcard -> score + 1
    }
  })
}
