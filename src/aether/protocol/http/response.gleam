// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Response Type Definitions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// This module defines types for HTTP/1.1 response generation.
// It reuses HttpVersion from request.gleam for consistency.
//

import aether/protocol/http/request.{type HttpVersion, Http10, Http11}
import gleam/bit_array
import gleam/int
import gleam/json
import gleam/list
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// HTTP response structure
///
/// Represents a complete HTTP response with status, headers, and body.
///
/// ## Fields
///
/// - `version`: HTTP protocol version (HTTP/1.0 or HTTP/1.1)
/// - `status`: HTTP status code (e.g., 200, 404, 500)
/// - `reason`: Reason phrase (e.g., "OK", "Not Found")
/// - `headers`: List of header name-value pairs
/// - `body`: Response body as raw bytes
///
pub type HttpResponse {
  HttpResponse(
    version: HttpVersion,
    status: Int,
    reason: String,
    headers: List(#(String, String)),
    body: BitArray,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new HttpResponse with the given status code
///
/// The reason phrase is automatically set based on the status code.
/// Uses HTTP/1.1 by default with empty headers and body.
///
/// ## Parameters
///
/// - `status`: HTTP status code
///
/// ## Returns
///
/// A new HttpResponse
///
/// ## Examples
///
/// ```gleam
/// let resp = new(200)
/// // HttpResponse with status 200, reason "OK"
/// ```
///
pub fn new(status: Int) -> HttpResponse {
  HttpResponse(
    version: Http11,
    status: status,
    reason: default_reason_phrase(status),
    headers: [],
    body: <<>>,
  )
}

/// Creates a 200 OK response
///
pub fn ok() -> HttpResponse {
  new(200)
}

/// Creates a 201 Created response
///
pub fn created() -> HttpResponse {
  new(201)
}

/// Creates a 202 Accepted response
///
pub fn accepted() -> HttpResponse {
  new(202)
}

/// Creates a 204 No Content response
///
pub fn no_content() -> HttpResponse {
  new(204)
}

/// Creates a 301 Moved Permanently response
///
pub fn moved_permanently() -> HttpResponse {
  new(301)
}

/// Creates a 302 Found response
///
pub fn found() -> HttpResponse {
  new(302)
}

/// Creates a 304 Not Modified response
///
pub fn not_modified() -> HttpResponse {
  new(304)
}

/// Creates a 400 Bad Request response
///
pub fn bad_request() -> HttpResponse {
  new(400)
}

/// Creates a 401 Unauthorized response
///
pub fn unauthorized() -> HttpResponse {
  new(401)
}

/// Creates a 403 Forbidden response
///
pub fn forbidden() -> HttpResponse {
  new(403)
}

/// Creates a 404 Not Found response
///
pub fn not_found() -> HttpResponse {
  new(404)
}

/// Creates a 405 Method Not Allowed response
///
pub fn method_not_allowed() -> HttpResponse {
  new(405)
}

/// Creates a 409 Conflict response
///
pub fn conflict() -> HttpResponse {
  new(409)
}

/// Creates a 413 Payload Too Large response
///
pub fn payload_too_large() -> HttpResponse {
  new(413)
}

/// Creates a 415 Unsupported Media Type response
///
pub fn unsupported_media_type() -> HttpResponse {
  new(415)
}

/// Creates a 429 Too Many Requests response
///
pub fn too_many_requests() -> HttpResponse {
  new(429)
}

/// Creates a 500 Internal Server Error response
///
pub fn internal_server_error() -> HttpResponse {
  new(500)
}

/// Creates a 501 Not Implemented response
///
pub fn not_implemented() -> HttpResponse {
  new(501)
}

/// Creates a 502 Bad Gateway response
///
pub fn bad_gateway() -> HttpResponse {
  new(502)
}

/// Creates a 503 Service Unavailable response
///
pub fn service_unavailable() -> HttpResponse {
  new(503)
}

/// Creates a 504 Gateway Timeout response
///
pub fn gateway_timeout() -> HttpResponse {
  new(504)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Builder Pattern Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the HTTP version
///
pub fn set_version(response: HttpResponse, version: HttpVersion) -> HttpResponse {
  HttpResponse(..response, version: version)
}

/// Sets the response body and automatically adds Content-Length header
///
/// ## Parameters
///
/// - `response`: The response to modify
/// - `body`: The body bytes
///
/// ## Returns
///
/// The response with body set and Content-Length header added
///
pub fn with_body(response: HttpResponse, body: BitArray) -> HttpResponse {
  HttpResponse(..response, body: body)
  |> with_content_length()
}

/// Sets the response body from a string
///
/// Converts the string to UTF-8 bytes and sets Content-Length.
///
pub fn with_string_body(response: HttpResponse, body: String) -> HttpResponse {
  with_body(response, bit_array.from_string(body))
}

/// Sets a header value, replacing any existing value with the same name
///
/// Header names are normalized to lowercase.
///
pub fn with_header(
  response: HttpResponse,
  name: String,
  value: String,
) -> HttpResponse {
  let lowercase_name = string.lowercase(name)
  let new_headers =
    response.headers
    |> list.filter(fn(h) { h.0 != lowercase_name })
    |> list.append([#(lowercase_name, value)])
  HttpResponse(..response, headers: new_headers)
}

/// Adds multiple headers
///
/// Existing headers with the same names are replaced.
///
pub fn with_headers(
  response: HttpResponse,
  headers: List(#(String, String)),
) -> HttpResponse {
  list.fold(headers, response, fn(resp, pair) {
    with_header(resp, pair.0, pair.1)
  })
}

/// Sets the Content-Type header
///
pub fn with_content_type(
  response: HttpResponse,
  content_type: String,
) -> HttpResponse {
  with_header(response, "content-type", content_type)
}

/// Sets Content-Type to application/json; charset=utf-8
///
pub fn json(response: HttpResponse) -> HttpResponse {
  with_content_type(response, "application/json; charset=utf-8")
}

/// Sets Content-Type to text/html; charset=utf-8
///
pub fn html(response: HttpResponse) -> HttpResponse {
  with_content_type(response, "text/html; charset=utf-8")
}

/// Sets Content-Type to text/plain; charset=utf-8
///
pub fn text(response: HttpResponse) -> HttpResponse {
  with_content_type(response, "text/plain; charset=utf-8")
}

/// Automatically sets Content-Length header based on body size
///
fn with_content_length(response: HttpResponse) -> HttpResponse {
  let length = bit_array.byte_size(response.body)
  with_header(response, "content-length", int.to_string(length))
}

/// Sets a custom reason phrase
///
pub fn with_reason(response: HttpResponse, reason: String) -> HttpResponse {
  HttpResponse(..response, reason: reason)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Response Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a JSON response with the given status and data
///
/// ## Parameters
///
/// - `status`: HTTP status code
/// - `data`: JSON data to encode
///
/// ## Returns
///
/// An HttpResponse with JSON content type and body
///
/// ## Examples
///
/// ```gleam
/// let data = json.object([#("id", json.int(1))])
/// let resp = json_response(200, data)
/// ```
///
pub fn json_response(status: Int, data: json.Json) -> HttpResponse {
  new(status)
  |> json()
  |> with_string_body(json.to_string(data))
}

/// Creates an HTML response with the given status and content
///
pub fn html_response(status: Int, content: String) -> HttpResponse {
  new(status)
  |> html()
  |> with_string_body(content)
}

/// Creates a plain text response with the given status and content
///
pub fn text_response(status: Int, content: String) -> HttpResponse {
  new(status)
  |> text()
  |> with_string_body(content)
}

/// Creates a redirect response
///
/// ## Parameters
///
/// - `location`: The URL to redirect to
/// - `permanent`: If True, uses 301 (Moved Permanently); otherwise 302 (Found)
///
/// ## Returns
///
/// An HttpResponse with Location header set
///
pub fn redirect(location: String, permanent: Bool) -> HttpResponse {
  let status = case permanent {
    True -> 301
    False -> 302
  }
  new(status)
  |> with_header("location", location)
}

/// Adds CORS headers to a response
///
/// ## Parameters
///
/// - `response`: The response to modify
/// - `origin`: Allowed origin (e.g., "*" or "https://example.com")
/// - `methods`: List of allowed HTTP methods
///
/// ## Returns
///
/// The response with CORS headers added
///
pub fn with_cors(
  response: HttpResponse,
  origin: String,
  methods: List(String),
) -> HttpResponse {
  response
  |> with_header("access-control-allow-origin", origin)
  |> with_header("access-control-allow-methods", string.join(methods, ", "))
  |> with_header("access-control-allow-headers", "Content-Type, Authorization")
}

/// Creates an error response with JSON body
///
/// ## Parameters
///
/// - `status`: HTTP status code
/// - `message`: Error message
///
/// ## Returns
///
/// An HttpResponse with JSON error body
///
/// ## Examples
///
/// ```gleam
/// let resp = error_response(404, "User not found")
/// // Body: {"error":"User not found","status":404}
/// ```
///
pub fn error_response(status: Int, message: String) -> HttpResponse {
  let error_json =
    json.object([
      #("error", json.string(message)),
      #("status", json.int(status)),
    ])
  json_response(status, error_json)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accessor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets a header value by name (case-insensitive)
///
/// Returns the first matching header value.
///
pub fn get_header(response: HttpResponse, name: String) -> Result(String, Nil) {
  let lowercase_name = string.lowercase(name)
  response.headers
  |> list.find(fn(h) { h.0 == lowercase_name })
  |> result.map(fn(h) { h.1 })
}

/// Checks if a header exists (case-insensitive)
///
pub fn has_header(response: HttpResponse, name: String) -> Bool {
  let lowercase_name = string.lowercase(name)
  list.any(response.headers, fn(h) { h.0 == lowercase_name })
}

/// Gets the Content-Type header value
///
pub fn get_content_type(response: HttpResponse) -> Result(String, Nil) {
  get_header(response, "content-type")
}

/// Gets the Content-Length header value as an integer
///
pub fn get_content_length(response: HttpResponse) -> Result(Int, Nil) {
  case get_header(response, "content-length") {
    Ok(value) -> int.parse(value)
    Error(_) -> Error(Nil)
  }
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

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Status Code Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the default reason phrase for a status code
///
/// Returns the standard HTTP reason phrase for known status codes,
/// or "Unknown" for unrecognized codes.
///
pub fn default_reason_phrase(status: Int) -> String {
  case status {
    // 1xx Informational
    100 -> "Continue"
    101 -> "Switching Protocols"

    // 2xx Success
    200 -> "OK"
    201 -> "Created"
    202 -> "Accepted"
    203 -> "Non-Authoritative Information"
    204 -> "No Content"
    205 -> "Reset Content"
    206 -> "Partial Content"

    // 3xx Redirection
    300 -> "Multiple Choices"
    301 -> "Moved Permanently"
    302 -> "Found"
    303 -> "See Other"
    304 -> "Not Modified"
    305 -> "Use Proxy"
    307 -> "Temporary Redirect"
    308 -> "Permanent Redirect"

    // 4xx Client Error
    400 -> "Bad Request"
    401 -> "Unauthorized"
    402 -> "Payment Required"
    403 -> "Forbidden"
    404 -> "Not Found"
    405 -> "Method Not Allowed"
    406 -> "Not Acceptable"
    407 -> "Proxy Authentication Required"
    408 -> "Request Timeout"
    409 -> "Conflict"
    410 -> "Gone"
    411 -> "Length Required"
    412 -> "Precondition Failed"
    413 -> "Payload Too Large"
    414 -> "URI Too Long"
    415 -> "Unsupported Media Type"
    416 -> "Range Not Satisfiable"
    417 -> "Expectation Failed"
    418 -> "I'm a teapot"
    422 -> "Unprocessable Entity"
    429 -> "Too Many Requests"

    // 5xx Server Error
    500 -> "Internal Server Error"
    501 -> "Not Implemented"
    502 -> "Bad Gateway"
    503 -> "Service Unavailable"
    504 -> "Gateway Timeout"
    505 -> "HTTP Version Not Supported"

    _ -> "Unknown"
  }
}

/// Checks if the status code indicates success (2xx)
///
pub fn is_success(status: Int) -> Bool {
  status >= 200 && status < 300
}

/// Checks if the status code indicates redirection (3xx)
///
pub fn is_redirect(status: Int) -> Bool {
  status >= 300 && status < 400
}

/// Checks if the status code indicates client error (4xx)
///
pub fn is_client_error(status: Int) -> Bool {
  status >= 400 && status < 500
}

/// Checks if the status code indicates server error (5xx)
///
pub fn is_server_error(status: Int) -> Bool {
  status >= 500 && status < 600
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Internal Imports
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/result
