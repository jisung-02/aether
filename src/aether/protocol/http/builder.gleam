// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Request/Response Builder Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Builds HTTP/1.1 request and response messages.
// Serializes requests and responses to bytes for network transmission.
//

import aether/protocol/http/request.{
  type HttpVersion, type ParsedRequest, Http10, Http11, ParsedRequest,
}
import aether/protocol/http/response.{type HttpResponse}
import gleam/bit_array
import gleam/http.{type Method}
import gleam/http/request as http_request
import gleam/int
import gleam/list
import gleam/option
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Main Build Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds a complete HTTP request from ParsedRequest
///
/// Creates the full HTTP message including request line, headers, and body.
///
/// ## Parameters
///
/// - `request`: The ParsedRequest to build
///
/// ## Returns
///
/// A BitArray containing the complete HTTP request
///
/// ## Examples
///
/// ```gleam
/// let req = request.get("/api/users")
///   |> request.set_header("Host", "example.com")
/// let bytes = build_request(req)
/// // <<"GET /api/users HTTP/1.1\r\nhost: example.com\r\n\r\n":utf8>>
/// ```
///
pub fn build_request(request: ParsedRequest) -> BitArray {
  let request_line =
    build_request_line(request.method, request.uri, request.version)
  let headers_bytes = build_headers(request.headers)
  let body = request.body

  // Add Content-Length header if body is present and header is missing
  let final_headers = case bit_array.byte_size(body) > 0 {
    True -> {
      case has_header(request.headers, "content-length") {
        True -> headers_bytes
        False -> {
          let content_length_header =
            build_header_line("content-length", int.to_string(bit_array.byte_size(body)))
          <<headers_bytes:bits, content_length_header:bits>>
        }
      }
    }
    False -> headers_bytes
  }

  // Combine: request_line + headers + CRLF + body
  <<request_line:bits, final_headers:bits, "\r\n":utf8, body:bits>>
}

/// Builds the request line: "METHOD URI HTTP/VERSION\r\n"
///
/// ## Parameters
///
/// - `method`: HTTP method
/// - `uri`: Request URI
/// - `version`: HTTP version
///
/// ## Returns
///
/// A BitArray containing the request line
///
pub fn build_request_line(
  method: Method,
  uri: String,
  version: HttpVersion,
) -> BitArray {
  let method_str = method_to_string(method)
  let version_str = version_to_string(version)
  <<method_str:utf8, " ":utf8, uri:utf8, " ":utf8, version_str:utf8, "\r\n":utf8>>
}

/// Builds all headers as bytes
///
/// Each header is formatted as "name: value\r\n".
/// Note: This does NOT include the final empty line (CRLF).
///
/// ## Parameters
///
/// - `headers`: List of header name-value pairs
///
/// ## Returns
///
/// A BitArray containing all headers
///
pub fn build_headers(headers: List(#(String, String))) -> BitArray {
  headers
  |> list.fold(<<>>, fn(acc, header) {
    let header_line = build_header_line(header.0, header.1)
    <<acc:bits, header_line:bits>>
  })
}

/// Builds a single header line: "name: value\r\n"
///
/// ## Parameters
///
/// - `name`: Header name
/// - `value`: Header value
///
/// ## Returns
///
/// A BitArray containing the header line
///
pub fn build_header_line(name: String, value: String) -> BitArray {
  <<name:utf8, ": ":utf8, value:utf8, "\r\n":utf8>>
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Conversion from gleam_http Request
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds HTTP bytes from a gleam_http Request
///
/// Converts a gleam_http Request to raw HTTP bytes.
/// This allows building requests using the gleam_http API.
///
/// ## Parameters
///
/// - `request`: A gleam_http Request with BitArray body
///
/// ## Returns
///
/// A BitArray containing the complete HTTP request
///
/// ## Examples
///
/// ```gleam
/// let req = gleam_http_request.new()
///   |> gleam_http_request.set_method(http.Get)
///   |> gleam_http_request.set_path("/api")
///   |> gleam_http_request.set_host("example.com")
/// let bytes = from_http_request(req)
/// ```
///
pub fn from_http_request(req: http_request.Request(BitArray)) -> BitArray {
  // Build URI from path and query
  let uri = case req.query {
    option.Some(q) -> req.path <> "?" <> q
    option.None -> req.path
  }

  // Ensure Host header is present
  let headers = case has_header(req.headers, "host") {
    True -> req.headers
    False -> [#("host", req.host), ..req.headers]
  }

  let parsed =
    ParsedRequest(
      method: req.method,
      uri: uri,
      version: Http11,
      headers: headers,
      body: req.body,
    )

  build_request(parsed)
}

/// Converts a ParsedRequest back to HTTP bytes (alias for build_request)
///
/// This is useful when you've modified a ParsedRequest and want to
/// serialize it back to bytes.
///
pub fn to_bytes(request: ParsedRequest) -> BitArray {
  build_request(request)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Chunked Encoding Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds a chunked-encoded body from raw body bytes
///
/// Wraps the body in chunked transfer encoding format.
///
/// ## Parameters
///
/// - `body`: The raw body bytes
///
/// ## Returns
///
/// A BitArray containing the chunked-encoded body
///
pub fn build_chunked_body(body: BitArray) -> BitArray {
  let size = bit_array.byte_size(body)
  case size {
    0 -> <<"0\r\n\r\n":utf8>>
    _ -> {
      let size_hex = int_to_hex_string(size)
      <<size_hex:utf8, "\r\n":utf8, body:bits, "\r\n0\r\n\r\n":utf8>>
    }
  }
}

/// Builds a request with chunked transfer encoding
///
/// Sets Transfer-Encoding: chunked and encodes the body.
///
/// ## Parameters
///
/// - `request`: The ParsedRequest to build
///
/// ## Returns
///
/// A BitArray containing the complete HTTP request with chunked body
///
pub fn build_chunked_request(req: ParsedRequest) -> BitArray {
  // Remove Content-Length if present, add Transfer-Encoding
  let headers =
    req.headers
    |> list.filter(fn(h) { h.0 != "content-length" })
    |> list.append([#("transfer-encoding", "chunked")])

  let request_line = build_request_line(req.method, req.uri, req.version)
  let headers_bytes = build_headers(headers)
  let chunked_body = build_chunked_body(req.body)

  <<request_line:bits, headers_bytes:bits, "\r\n":utf8, chunked_body:bits>>
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts Method to string
///
fn method_to_string(method: Method) -> String {
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

/// Converts HttpVersion to string
///
fn version_to_string(version: HttpVersion) -> String {
  case version {
    Http10 -> "HTTP/1.0"
    Http11 -> "HTTP/1.1"
  }
}

/// Checks if a header exists (case-insensitive)
///
fn has_header(headers: List(#(String, String)), name: String) -> Bool {
  let lowercase_name = string.lowercase(name)
  list.any(headers, fn(h) { string.lowercase(h.0) == lowercase_name })
}

/// Converts an integer to lowercase hex string
///
fn int_to_hex_string(n: Int) -> String {
  case n {
    0 -> "0"
    _ -> do_int_to_hex(n, "")
  }
}

fn do_int_to_hex(n: Int, acc: String) -> String {
  case n {
    0 -> acc
    _ -> {
      let digit = n % 16
      let char = hex_digit_to_char(digit)
      do_int_to_hex(n / 16, char <> acc)
    }
  }
}

fn hex_digit_to_char(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    10 -> "a"
    11 -> "b"
    12 -> "c"
    13 -> "d"
    14 -> "e"
    15 -> "f"
    _ -> "0"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Response Builder Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds a complete HTTP response from HttpResponse
///
/// Creates the full HTTP response message including status line, headers, and body.
///
/// ## Parameters
///
/// - `resp`: The HttpResponse to build
///
/// ## Returns
///
/// A BitArray containing the complete HTTP response
///
/// ## Examples
///
/// ```gleam
/// let resp = response.ok()
///   |> response.text()
///   |> response.with_string_body("Hello, World!")
/// let bytes = build_response(resp)
/// // <<"HTTP/1.1 200 OK\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 13\r\n\r\nHello, World!":utf8>>
/// ```
///
pub fn build_response(resp: HttpResponse) -> BitArray {
  let status_line = build_status_line(resp)
  let headers_bytes = build_headers(resp.headers)

  // Combine: status_line + headers + CRLF + body
  <<status_line:bits, headers_bytes:bits, "\r\n":utf8, resp.body:bits>>
}

/// Builds the status line: "HTTP/VERSION STATUS REASON\r\n"
///
/// ## Parameters
///
/// - `resp`: The HttpResponse
///
/// ## Returns
///
/// A BitArray containing the status line
///
/// ## Examples
///
/// ```gleam
/// let resp = response.ok()
/// build_status_line(resp)
/// // <<"HTTP/1.1 200 OK\r\n":utf8>>
/// ```
///
pub fn build_status_line(resp: HttpResponse) -> BitArray {
  let version_str = version_to_string(resp.version)
  let status_str = int.to_string(resp.status)
  <<version_str:utf8, " ":utf8, status_str:utf8, " ":utf8, resp.reason:utf8, "\r\n":utf8>>
}

/// Converts an HttpResponse to HTTP bytes (alias for build_response)
///
pub fn response_to_bytes(resp: HttpResponse) -> BitArray {
  build_response(resp)
}

/// Builds a chunked transfer encoding response
///
/// Creates an HTTP response with Transfer-Encoding: chunked header
/// and properly formatted chunked body.
///
/// ## Parameters
///
/// - `resp`: The HttpResponse (body will be replaced)
/// - `chunks`: List of body chunks
///
/// ## Returns
///
/// A BitArray containing the complete chunked HTTP response
///
/// ## Examples
///
/// ```gleam
/// let resp = response.ok() |> response.text()
/// let chunks = [<<"Hello":utf8>>, <<" ":utf8>>, <<"World":utf8>>]
/// let bytes = build_chunked_response(resp, chunks)
/// ```
///
pub fn build_chunked_response(
  resp: HttpResponse,
  chunks: List(BitArray),
) -> BitArray {
  // Remove Content-Length if present, add Transfer-Encoding
  let headers =
    resp.headers
    |> list.filter(fn(h) { h.0 != "content-length" })
    |> list.append([#("transfer-encoding", "chunked")])

  let status_line = build_status_line(resp)
  let headers_bytes = build_headers(headers)
  let chunked_body = build_chunks(chunks)

  <<status_line:bits, headers_bytes:bits, "\r\n":utf8, chunked_body:bits>>
}

/// Builds chunked body from a list of chunks
///
/// Each chunk is formatted as: size (hex)\r\ndata\r\n
/// Final chunk: 0\r\n\r\n
///
fn build_chunks(chunks: List(BitArray)) -> BitArray {
  let chunk_parts =
    list.map(chunks, fn(chunk) {
      let size = bit_array.byte_size(chunk)
      let size_hex = int_to_hex_string(size)
      let size_line = bit_array.from_string(size_hex <> "\r\n")
      let crlf = bit_array.from_string("\r\n")

      size_line
      |> bit_array.append(chunk)
      |> bit_array.append(crlf)
    })

  // Add final chunk (size 0)
  let final_chunk = bit_array.from_string("0\r\n\r\n")

  list.fold(chunk_parts, <<>>, bit_array.append)
  |> bit_array.append(final_chunk)
}
