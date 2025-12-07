// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Request Type Definitions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// This module defines types for HTTP/1.1 request parsing.
// It reuses gleam_http types (Method, Request) where appropriate.
//

import gleam/http.{type Method}
import gleam/list
import gleam/option.{type Option}
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// HTTP protocol version
///
/// Represents the HTTP version from the request line.
///
pub type HttpVersion {
  /// HTTP/1.0
  Http10
  /// HTTP/1.1
  Http11
}

/// Raw HTTP request parsed from bytes
///
/// This type represents the direct result of parsing HTTP request bytes.
/// It can be converted to a gleam_http Request type for further processing.
///
/// ## Fields
///
/// - `method`: HTTP method (GET, POST, etc.) from gleam_http
/// - `uri`: Raw request URI including path and query string
/// - `version`: HTTP protocol version
/// - `headers`: List of header name-value pairs (names are lowercase)
/// - `body`: Request body as raw bytes
///
pub type ParsedRequest {
  ParsedRequest(
    method: Method,
    uri: String,
    version: HttpVersion,
    headers: List(#(String, String)),
    body: BitArray,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new ParsedRequest with default values
///
/// ## Parameters
///
/// - `method`: The HTTP method
/// - `uri`: The request URI
///
/// ## Returns
///
/// A new ParsedRequest with HTTP/1.1 version and empty headers/body
///
pub fn new(method: Method, uri: String) -> ParsedRequest {
  ParsedRequest(
    method: method,
    uri: uri,
    version: Http11,
    headers: [],
    body: <<>>,
  )
}

/// Creates a GET request
///
pub fn get(uri: String) -> ParsedRequest {
  new(http.Get, uri)
}

/// Creates a POST request
///
pub fn post(uri: String) -> ParsedRequest {
  new(http.Post, uri)
}

/// Creates a PUT request
///
pub fn put(uri: String) -> ParsedRequest {
  new(http.Put, uri)
}

/// Creates a DELETE request
///
pub fn delete(uri: String) -> ParsedRequest {
  new(http.Delete, uri)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Modifier Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the HTTP version
///
pub fn set_version(request: ParsedRequest, version: HttpVersion) -> ParsedRequest {
  ParsedRequest(..request, version: version)
}

/// Sets the request body
///
pub fn set_body(request: ParsedRequest, body: BitArray) -> ParsedRequest {
  ParsedRequest(..request, body: body)
}

/// Sets a header value, replacing any existing value with the same name
///
/// Header names are normalized to lowercase.
///
pub fn set_header(
  request: ParsedRequest,
  name: String,
  value: String,
) -> ParsedRequest {
  let lowercase_name = string.lowercase(name)
  let new_headers =
    request.headers
    |> list.filter(fn(h) { h.0 != lowercase_name })
    |> list.append([#(lowercase_name, value)])
  ParsedRequest(..request, headers: new_headers)
}

/// Adds a header value, allowing multiple values for the same name
///
/// Header names are normalized to lowercase.
///
pub fn add_header(
  request: ParsedRequest,
  name: String,
  value: String,
) -> ParsedRequest {
  let lowercase_name = string.lowercase(name)
  ParsedRequest(
    ..request,
    headers: list.append(request.headers, [#(lowercase_name, value)]),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accessor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets a header value by name (case-insensitive)
///
/// Returns the first matching header value if multiple exist.
///
pub fn get_header(request: ParsedRequest, name: String) -> Option(String) {
  let lowercase_name = string.lowercase(name)
  request.headers
  |> list.find(fn(h) { h.0 == lowercase_name })
  |> option.from_result()
  |> option.map(fn(h) { h.1 })
}

/// Gets all header values by name (case-insensitive)
///
/// Returns all values for headers with the given name.
///
pub fn get_header_values(request: ParsedRequest, name: String) -> List(String) {
  let lowercase_name = string.lowercase(name)
  request.headers
  |> list.filter(fn(h) { h.0 == lowercase_name })
  |> list.map(fn(h) { h.1 })
}

/// Checks if a header exists (case-insensitive)
///
pub fn has_header(request: ParsedRequest, name: String) -> Bool {
  let lowercase_name = string.lowercase(name)
  list.any(request.headers, fn(h) { h.0 == lowercase_name })
}

/// Gets the Content-Length header value as an integer
///
pub fn content_length(request: ParsedRequest) -> Option(Int) {
  case get_header(request, "content-length") {
    option.Some(value) -> {
      case parse_int(value) {
        Ok(length) -> option.Some(length)
        Error(_) -> option.None
      }
    }
    option.None -> option.None
  }
}

/// Checks if the request uses chunked transfer encoding
///
pub fn is_chunked(request: ParsedRequest) -> Bool {
  case get_header(request, "transfer-encoding") {
    option.Some(value) -> string.contains(string.lowercase(value), "chunked")
    option.None -> False
  }
}

/// Gets the Host header value
///
pub fn host(request: ParsedRequest) -> Option(String) {
  get_header(request, "host")
}

/// Gets the Content-Type header value
///
pub fn content_type(request: ParsedRequest) -> Option(String) {
  get_header(request, "content-type")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Version Conversion Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts HttpVersion to a string
///
pub fn version_to_string(version: HttpVersion) -> String {
  case version {
    Http10 -> "HTTP/1.0"
    Http11 -> "HTTP/1.1"
  }
}

/// Parses a version string to HttpVersion
///
pub fn version_from_string(s: String) -> Result(HttpVersion, Nil) {
  case s {
    "HTTP/1.0" -> Ok(Http10)
    "HTTP/1.1" -> Ok(Http11)
    _ -> Error(Nil)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Method Conversion Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts Method to a string
///
pub fn method_to_string(method: Method) -> String {
  case method {
    http.Get -> "GET"
    http.Post -> "POST"
    http.Put -> "PUT"
    http.Delete -> "DELETE"
    http.Patch -> "PATCH"
    http.Head -> "HEAD"
    http.Options -> "OPTIONS"
    http.Connect -> "CONNECT"
    http.Trace -> "TRACE"
    http.Other(s) -> s
  }
}

/// Parses a method string to Method
///
pub fn method_from_string(s: String) -> Result(Method, Nil) {
  case string.uppercase(s) {
    "GET" -> Ok(http.Get)
    "POST" -> Ok(http.Post)
    "PUT" -> Ok(http.Put)
    "DELETE" -> Ok(http.Delete)
    "PATCH" -> Ok(http.Patch)
    "HEAD" -> Ok(http.Head)
    "OPTIONS" -> Ok(http.Options)
    "CONNECT" -> Ok(http.Connect)
    "TRACE" -> Ok(http.Trace)
    _ -> Ok(http.Other(s))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// URI Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Extracts the path from the URI (without query string)
///
pub fn path(request: ParsedRequest) -> String {
  case string.split_once(request.uri, "?") {
    Ok(#(path, _query)) -> path
    Error(_) -> request.uri
  }
}

/// Extracts the query string from the URI (without leading ?)
///
pub fn query(request: ParsedRequest) -> Option(String) {
  case string.split_once(request.uri, "?") {
    Ok(#(_path, query)) -> option.Some(query)
    Error(_) -> option.None
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/int

fn parse_int(s: String) -> Result(Int, Nil) {
  int.parse(s)
}
