// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Route Parameters Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides type-safe access to path and query parameters extracted
// from HTTP requests during routing.
//
// ## Features
//
// - Path parameter extraction from dynamic routes (`/users/:id`)
// - Query string parsing (`?q=term&page=1`)
// - Type-safe accessors with int conversion
// - URL percent-decoding support
//
// ## Usage
//
// ```gleam
// // In a route handler
// fn user_handler(req, params, data) {
//   case params.get_int(params, "id") {
//     option.Some(user_id) -> // use user_id
//     option.None -> // invalid or missing id
//   }
// }
// ```
//

import aether/protocol/http/url
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Route parameters container
///
/// Holds both path parameters (from dynamic route segments) and
/// query parameters (from the query string).
///
/// ## Fields
///
/// - `path`: Parameters extracted from path segments (e.g., `:id`)
/// - `query`: Parameters parsed from query string (e.g., `?key=value`)
///
pub type Params {
  Params(path: Dict(String, String), query: Dict(String, String))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates empty params
///
/// ## Returns
///
/// A new Params with empty path and query dictionaries
///
/// ## Examples
///
/// ```gleam
/// let params = params.new()
/// params.get(params, "id")  // None
/// ```
///
pub fn new() -> Params {
  Params(path: dict.new(), query: dict.new())
}

/// Creates params with path parameters only
///
/// ## Parameters
///
/// - `path_params`: Dictionary of path parameters
///
/// ## Returns
///
/// A new Params with the given path parameters and empty query
///
pub fn from_path(path_params: Dict(String, String)) -> Params {
  Params(path: path_params, query: dict.new())
}

/// Creates params with both path and query parameters
///
/// ## Parameters
///
/// - `path_params`: Dictionary of path parameters
/// - `query_params`: Dictionary of query parameters
///
/// ## Returns
///
/// A new Params with both path and query parameters
///
pub fn from_both(
  path_params: Dict(String, String),
  query_params: Dict(String, String),
) -> Params {
  Params(path: path_params, query: query_params)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Path Parameter Accessors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets a path parameter by name
///
/// ## Parameters
///
/// - `p`: The Params to get from
/// - `name`: The parameter name
///
/// ## Returns
///
/// Option containing the parameter value if present
///
/// ## Examples
///
/// ```gleam
/// // For route /users/:id matched against /users/42
/// params.get(params, "id")  // Some("42")
/// params.get(params, "missing")  // None
/// ```
///
pub fn get(p: Params, name: String) -> Option(String) {
  dict.get(p.path, name)
  |> option.from_result()
}

/// Gets a path parameter as an integer
///
/// ## Parameters
///
/// - `p`: The Params to get from
/// - `name`: The parameter name
///
/// ## Returns
///
/// Option containing the integer value if present and valid
///
/// ## Examples
///
/// ```gleam
/// // For route /users/:id matched against /users/42
/// params.get_int(params, "id")  // Some(42)
/// // For route matched against /users/invalid
/// params.get_int(params, "id")  // None
/// ```
///
pub fn get_int(p: Params, name: String) -> Option(Int) {
  case get(p, name) {
    option.Some(value) -> {
      case int.parse(value) {
        Ok(i) -> option.Some(i)
        Error(_) -> option.None
      }
    }
    option.None -> option.None
  }
}

/// Sets a path parameter
///
/// ## Parameters
///
/// - `p`: The Params to update
/// - `name`: The parameter name
/// - `value`: The parameter value
///
/// ## Returns
///
/// A new Params with the parameter set
///
pub fn set(p: Params, name: String, value: String) -> Params {
  Params(..p, path: dict.insert(p.path, name, value))
}

/// Checks if a path parameter exists
///
/// ## Parameters
///
/// - `p`: The Params to check
/// - `name`: The parameter name
///
/// ## Returns
///
/// True if the parameter exists
///
pub fn has(p: Params, name: String) -> Bool {
  dict.has_key(p.path, name)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Query Parameter Accessors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets a query parameter by name
///
/// ## Parameters
///
/// - `p`: The Params to get from
/// - `name`: The parameter name
///
/// ## Returns
///
/// Option containing the query parameter value if present
///
/// ## Examples
///
/// ```gleam
/// // For URL /search?q=gleam&page=1
/// params.get_query(params, "q")  // Some("gleam")
/// params.get_query(params, "page")  // Some("1")
/// ```
///
pub fn get_query(p: Params, name: String) -> Option(String) {
  dict.get(p.query, name)
  |> option.from_result()
}

/// Gets a query parameter as an integer
///
/// ## Parameters
///
/// - `p`: The Params to get from
/// - `name`: The parameter name
///
/// ## Returns
///
/// Option containing the integer value if present and valid
///
/// ## Examples
///
/// ```gleam
/// // For URL /search?page=5
/// params.get_query_int(params, "page")  // Some(5)
/// // For URL /search?page=invalid
/// params.get_query_int(params, "page")  // None
/// ```
///
pub fn get_query_int(p: Params, name: String) -> Option(Int) {
  case get_query(p, name) {
    option.Some(value) -> {
      case int.parse(value) {
        Ok(i) -> option.Some(i)
        Error(_) -> option.None
      }
    }
    option.None -> option.None
  }
}

/// Sets a query parameter
///
/// ## Parameters
///
/// - `p`: The Params to update
/// - `name`: The parameter name
/// - `value`: The parameter value
///
/// ## Returns
///
/// A new Params with the query parameter set
///
pub fn set_query(p: Params, name: String, value: String) -> Params {
  Params(..p, query: dict.insert(p.query, name, value))
}

/// Checks if a query parameter exists
///
/// ## Parameters
///
/// - `p`: The Params to check
/// - `name`: The parameter name
///
/// ## Returns
///
/// True if the query parameter exists
///
pub fn has_query(p: Params, name: String) -> Bool {
  dict.has_key(p.query, name)
}

/// Sets the query parameters from a dictionary
///
/// ## Parameters
///
/// - `p`: The Params to update
/// - `query_params`: Dictionary of query parameters
///
/// ## Returns
///
/// A new Params with the query parameters set
///
pub fn with_query(p: Params, query_params: Dict(String, String)) -> Params {
  Params(..p, query: query_params)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Query String Parsing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses a query string into a dictionary
///
/// Handles URL percent-decoding for both keys and values.
/// Empty strings return an empty dictionary.
///
/// ## Parameters
///
/// - `query_string`: The query string (without leading ?)
///
/// ## Returns
///
/// Dictionary of parsed query parameters
///
/// ## Examples
///
/// ```gleam
/// params.parse_query("name=Alice&age=30")
/// // dict.from_list([#("name", "Alice"), #("age", "30")])
///
/// params.parse_query("q=hello%20world")
/// // dict.from_list([#("q", "hello world")])
///
/// params.parse_query("")
/// // dict.new()
/// ```
///
pub fn parse_query(query_string: String) -> Dict(String, String) {
  case string.is_empty(query_string) {
    True -> dict.new()
    False -> {
      string.split(query_string, "&")
      |> list.filter_map(parse_query_pair)
      |> dict.from_list()
    }
  }
}

/// Parses a single query parameter pair (key=value)
///
fn parse_query_pair(pair: String) -> Result(#(String, String), Nil) {
  case string.is_empty(pair) {
    True -> Error(Nil)
    False -> {
      case string.split_once(pair, "=") {
        Ok(#(key, value)) -> {
          let decoded_key = decode_query_component(key)
          let decoded_value = decode_query_component(value)

          case decoded_key, decoded_value {
            Ok(k), Ok(v) -> Ok(#(k, v))
            _, _ -> Error(Nil)
          }
        }
        // Handle keys without values (e.g., "flag" in "flag&other=value")
        Error(_) -> {
          case decode_query_component(pair) {
            Ok(k) -> Ok(#(k, ""))
            Error(_) -> Error(Nil)
          }
        }
      }
    }
  }
}

fn decode_query_component(component: String) -> Result(String, Nil) {
  case url.percent_decode(component) {
    Ok(decoded) -> Ok(decoded)
    Error(_) -> Error(Nil)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the number of path parameters
///
pub fn path_count(p: Params) -> Int {
  dict.size(p.path)
}

/// Gets the number of query parameters
///
pub fn query_count(p: Params) -> Int {
  dict.size(p.query)
}

/// Checks if params is empty (no path or query parameters)
///
pub fn is_empty(p: Params) -> Bool {
  dict.is_empty(p.path) && dict.is_empty(p.query)
}

/// Gets all path parameter names
///
pub fn path_keys(p: Params) -> List(String) {
  dict.keys(p.path)
}

/// Gets all query parameter names
///
pub fn query_keys(p: Params) -> List(String) {
  dict.keys(p.query)
}
