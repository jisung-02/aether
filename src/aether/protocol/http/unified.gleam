// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Unified HTTP Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides protocol-agnostic request and response types that work
// for both HTTP/1.1 and HTTP/2. This enables handlers to be written
// once and work with either protocol.
//

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Unified Request Type
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// HTTP method (protocol-agnostic)
///
pub type Method {
  Get
  Post
  Put
  Delete
  Patch
  Head
  Options
  Connect
  Trace
  Other(String)
}

/// Unified HTTP request that works for HTTP/1.1 and HTTP/2
///
/// This type abstracts the differences between HTTP/1.1 and HTTP/2
/// request formats, providing a common interface for handlers.
///
pub type UnifiedRequest {
  UnifiedRequest(
    /// HTTP method
    method: Method,
    /// Request path (e.g., "/api/users")
    path: String,
    /// Query string (without leading ?)
    query: Option(String),
    /// Scheme (http or https)
    scheme: String,
    /// Host/Authority
    host: String,
    /// Request headers (lowercase names)
    headers: List(#(String, String)),
    /// Request body
    body: BitArray,
    /// Protocol version info
    protocol: ProtocolInfo,
    /// Stream ID for HTTP/2 (0 for HTTP/1.1)
    stream_id: Int,
    /// Extension data for protocol-specific info
    extensions: Dict(String, String),
  )
}

/// Protocol version information
///
pub type ProtocolInfo {
  Http11
  Http2
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Unified Response Type
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Unified HTTP response that works for HTTP/1.1 and HTTP/2
///
pub type UnifiedResponse {
  UnifiedResponse(
    /// HTTP status code (200, 404, etc.)
    status: Int,
    /// Response headers (lowercase names)
    headers: List(#(String, String)),
    /// Response body
    body: BitArray,
    /// Stream ID for HTTP/2 (0 for HTTP/1.1)
    stream_id: Int,
    /// Whether to close the connection (HTTP/1.1) or stream (HTTP/2)
    close: Bool,
    /// Trailers (optional, mainly for HTTP/2)
    trailers: Option(List(#(String, String))),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Request Constructors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new unified request
///
pub fn new_request(method: Method, path: String) -> UnifiedRequest {
  UnifiedRequest(
    method: method,
    path: path,
    query: None,
    scheme: "http",
    host: "",
    headers: [],
    body: <<>>,
    protocol: Http11,
    stream_id: 0,
    extensions: dict.new(),
  )
}

/// Creates a GET request
///
pub fn get(path: String) -> UnifiedRequest {
  new_request(Get, path)
}

/// Creates a POST request
///
pub fn post(path: String) -> UnifiedRequest {
  new_request(Post, path)
}

/// Creates a PUT request
///
pub fn put(path: String) -> UnifiedRequest {
  new_request(Put, path)
}

/// Creates a DELETE request
///
pub fn delete(path: String) -> UnifiedRequest {
  new_request(Delete, path)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Request Builder Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the request host
///
pub fn with_host(request: UnifiedRequest, host: String) -> UnifiedRequest {
  UnifiedRequest(..request, host: host)
}

/// Sets the request scheme
///
pub fn with_scheme(request: UnifiedRequest, scheme: String) -> UnifiedRequest {
  UnifiedRequest(..request, scheme: scheme)
}

/// Sets the query string
///
pub fn with_query(request: UnifiedRequest, query: String) -> UnifiedRequest {
  UnifiedRequest(..request, query: Some(query))
}

/// Adds a header to the request
///
pub fn with_header(
  request: UnifiedRequest,
  name: String,
  value: String,
) -> UnifiedRequest {
  let lowercase_name = string.lowercase(name)
  UnifiedRequest(
    ..request,
    headers: list.append(request.headers, [#(lowercase_name, value)]),
  )
}

/// Sets the request body
///
pub fn with_body(request: UnifiedRequest, body: BitArray) -> UnifiedRequest {
  UnifiedRequest(..request, body: body)
}

/// Sets the request body from a string
///
pub fn with_string_body(request: UnifiedRequest, body: String) -> UnifiedRequest {
  UnifiedRequest(..request, body: bit_array.from_string(body))
}

/// Sets the protocol info
///
pub fn with_protocol(
  request: UnifiedRequest,
  protocol: ProtocolInfo,
) -> UnifiedRequest {
  UnifiedRequest(..request, protocol: protocol)
}

/// Sets the stream ID (for HTTP/2)
///
pub fn with_stream_id(request: UnifiedRequest, stream_id: Int) -> UnifiedRequest {
  UnifiedRequest(..request, stream_id: stream_id)
}

/// Sets an extension value
///
pub fn with_extension(
  request: UnifiedRequest,
  key: String,
  value: String,
) -> UnifiedRequest {
  UnifiedRequest(
    ..request,
    extensions: dict.insert(request.extensions, key, value),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Request Accessor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets a header value by name (case-insensitive)
///
pub fn get_header(request: UnifiedRequest, name: String) -> Option(String) {
  let lowercase_name = string.lowercase(name)
  list.find(request.headers, fn(h) { h.0 == lowercase_name })
  |> option.from_result
  |> option.map(fn(h) { h.1 })
}

/// Gets the Content-Type header
///
pub fn get_content_type(request: UnifiedRequest) -> Option(String) {
  get_header(request, "content-type")
}

/// Gets the Content-Length header
///
pub fn get_content_length(request: UnifiedRequest) -> Option(Int) {
  case get_header(request, "content-length") {
    Some(value) -> {
      case int.parse(value) {
        Ok(length) -> Some(length)
        Error(_) -> None
      }
    }
    None -> None
  }
}

/// Checks if request is HTTP/2
///
pub fn is_http2(request: UnifiedRequest) -> Bool {
  case request.protocol {
    Http2 -> True
    Http11 -> False
  }
}

/// Gets the full URI
///
pub fn get_uri(request: UnifiedRequest) -> String {
  request.scheme
  <> "://"
  <> request.host
  <> request.path
  <> case request.query {
    Some(q) -> "?" <> q
    None -> ""
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Response Constructors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new unified response
///
pub fn new_response(status: Int) -> UnifiedResponse {
  UnifiedResponse(
    status: status,
    headers: [],
    body: <<>>,
    stream_id: 0,
    close: False,
    trailers: None,
  )
}

/// Creates a 200 OK response
///
pub fn ok() -> UnifiedResponse {
  new_response(200)
}

/// Creates a 201 Created response
///
pub fn created() -> UnifiedResponse {
  new_response(201)
}

/// Creates a 204 No Content response
///
pub fn no_content() -> UnifiedResponse {
  new_response(204)
}

/// Creates a 400 Bad Request response
///
pub fn bad_request() -> UnifiedResponse {
  new_response(400)
}

/// Creates a 401 Unauthorized response
///
pub fn unauthorized() -> UnifiedResponse {
  new_response(401)
}

/// Creates a 403 Forbidden response
///
pub fn forbidden() -> UnifiedResponse {
  new_response(403)
}

/// Creates a 404 Not Found response
///
pub fn not_found() -> UnifiedResponse {
  new_response(404)
}

/// Creates a 500 Internal Server Error response
///
pub fn internal_server_error() -> UnifiedResponse {
  new_response(500)
}

/// Creates a 503 Service Unavailable response
///
pub fn service_unavailable() -> UnifiedResponse {
  new_response(503)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Response Builder Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Adds a header to the response
///
pub fn response_with_header(
  response: UnifiedResponse,
  name: String,
  value: String,
) -> UnifiedResponse {
  let lowercase_name = string.lowercase(name)
  UnifiedResponse(
    ..response,
    headers: list.append(response.headers, [#(lowercase_name, value)]),
  )
}

/// Sets the response body
///
pub fn response_with_body(
  response: UnifiedResponse,
  body: BitArray,
) -> UnifiedResponse {
  UnifiedResponse(..response, body: body)
}

/// Sets the response body from a string
///
pub fn response_with_string_body(
  response: UnifiedResponse,
  body: String,
) -> UnifiedResponse {
  UnifiedResponse(..response, body: bit_array.from_string(body))
}

/// Sets the Content-Type header
///
pub fn response_with_content_type(
  response: UnifiedResponse,
  content_type: String,
) -> UnifiedResponse {
  response_with_header(response, "content-type", content_type)
}

/// Sets as plain text response
///
pub fn text(response: UnifiedResponse) -> UnifiedResponse {
  response_with_content_type(response, "text/plain; charset=utf-8")
}

/// Sets as HTML response
///
pub fn html(response: UnifiedResponse) -> UnifiedResponse {
  response_with_content_type(response, "text/html; charset=utf-8")
}

/// Sets as JSON response
///
pub fn json(response: UnifiedResponse) -> UnifiedResponse {
  response_with_content_type(response, "application/json; charset=utf-8")
}

/// Sets the stream ID (for HTTP/2)
///
pub fn response_with_stream_id(
  response: UnifiedResponse,
  stream_id: Int,
) -> UnifiedResponse {
  UnifiedResponse(..response, stream_id: stream_id)
}

/// Marks the connection/stream for close
///
pub fn response_with_close(response: UnifiedResponse) -> UnifiedResponse {
  UnifiedResponse(..response, close: True)
}

/// Sets trailers
///
pub fn response_with_trailers(
  response: UnifiedResponse,
  trailers: List(#(String, String)),
) -> UnifiedResponse {
  UnifiedResponse(..response, trailers: Some(trailers))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Method Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses a method string to Method type
///
pub fn method_from_string(s: String) -> Method {
  case string.uppercase(s) {
    "GET" -> Get
    "POST" -> Post
    "PUT" -> Put
    "DELETE" -> Delete
    "PATCH" -> Patch
    "HEAD" -> Head
    "OPTIONS" -> Options
    "CONNECT" -> Connect
    "TRACE" -> Trace
    _ -> Other(s)
  }
}

/// Converts Method to string
///
pub fn method_to_string(method: Method) -> String {
  case method {
    Get -> "GET"
    Post -> "POST"
    Put -> "PUT"
    Delete -> "DELETE"
    Patch -> "PATCH"
    Head -> "HEAD"
    Options -> "OPTIONS"
    Connect -> "CONNECT"
    Trace -> "TRACE"
    Other(s) -> s
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Status Code Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the reason phrase for a status code
///
pub fn status_reason(status: Int) -> String {
  case status {
    100 -> "Continue"
    101 -> "Switching Protocols"
    200 -> "OK"
    201 -> "Created"
    202 -> "Accepted"
    204 -> "No Content"
    301 -> "Moved Permanently"
    302 -> "Found"
    303 -> "See Other"
    304 -> "Not Modified"
    307 -> "Temporary Redirect"
    308 -> "Permanent Redirect"
    400 -> "Bad Request"
    401 -> "Unauthorized"
    403 -> "Forbidden"
    404 -> "Not Found"
    405 -> "Method Not Allowed"
    408 -> "Request Timeout"
    409 -> "Conflict"
    410 -> "Gone"
    413 -> "Payload Too Large"
    414 -> "URI Too Long"
    415 -> "Unsupported Media Type"
    429 -> "Too Many Requests"
    500 -> "Internal Server Error"
    501 -> "Not Implemented"
    502 -> "Bad Gateway"
    503 -> "Service Unavailable"
    504 -> "Gateway Timeout"
    _ -> "Unknown"
  }
}

/// Checks if status is in 1xx range (informational)
///
pub fn is_informational(status: Int) -> Bool {
  status >= 100 && status < 200
}

/// Checks if status is in 2xx range (success)
///
pub fn is_success(status: Int) -> Bool {
  status >= 200 && status < 300
}

/// Checks if status is in 3xx range (redirect)
///
pub fn is_redirect(status: Int) -> Bool {
  status >= 300 && status < 400
}

/// Checks if status is in 4xx range (client error)
///
pub fn is_client_error(status: Int) -> Bool {
  status >= 400 && status < 500
}

/// Checks if status is in 5xx range (server error)
///
pub fn is_server_error(status: Int) -> Bool {
  status >= 500 && status < 600
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Debug Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts request to string for debugging
///
pub fn request_to_string(request: UnifiedRequest) -> String {
  method_to_string(request.method)
  <> " "
  <> request.path
  <> " "
  <> case request.protocol {
    Http11 -> "HTTP/1.1"
    Http2 -> "HTTP/2"
  }
  <> " (host="
  <> request.host
  <> ", body_size="
  <> int.to_string(bit_array.byte_size(request.body))
  <> ")"
}

/// Converts response to string for debugging
///
pub fn response_to_string(response: UnifiedResponse) -> String {
  int.to_string(response.status)
  <> " "
  <> status_reason(response.status)
  <> " (headers="
  <> int.to_string(list.length(response.headers))
  <> ", body_size="
  <> int.to_string(bit_array.byte_size(response.body))
  <> ")"
}
