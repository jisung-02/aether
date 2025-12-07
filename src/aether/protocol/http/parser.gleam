// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Request Parser Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Parses HTTP/1.1 request messages according to RFC 7230.
//

import aether/protocol/http/request.{
  type HttpVersion, type ParsedRequest, Http10, Http11, ParsedRequest,
}
import gleam/bit_array
import gleam/http.{type Method}
import gleam/http/request as http_request
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Errors that can occur during HTTP request parsing
///
pub type ParseError {
  /// Input is too short to contain a valid HTTP request
  InvalidLength(expected: Int, actual: Int)
  /// Request line is malformed
  InvalidRequestLine(message: String)
  /// HTTP method is not recognized
  InvalidMethod(method: String)
  /// HTTP version is not supported
  InvalidVersion(version: String)
  /// Header parsing failed
  InvalidHeader(message: String)
  /// Content-Length value is invalid
  InvalidContentLength(value: String)
  /// Body length doesn't match Content-Length
  IncompleteBody(expected: Int, actual: Int)
  /// Chunked encoding parsing failed
  InvalidChunkedEncoding(message: String)
  /// General malformed request
  MalformedRequest(message: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Main Parsing Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses a complete HTTP request from bytes
///
/// Returns the parsed request and any remaining bytes (for HTTP pipelining).
///
/// ## Parameters
///
/// - `bytes`: Raw HTTP request bytes
///
/// ## Returns
///
/// A tuple of (ParsedRequest, remaining_bytes) or a ParseError
///
/// ## Examples
///
/// ```gleam
/// let request_bytes = <<"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8>>
/// case parse_request(request_bytes) {
///   Ok(#(request, remaining)) -> // use request
///   Error(err) -> // handle error
/// }
/// ```
///
pub fn parse_request(
  bytes: BitArray,
) -> Result(#(ParsedRequest, BitArray), ParseError) {
  // Parse request line
  use #(method, uri, version, after_line) <- result.try(parse_request_line(
    bytes,
  ))

  // Parse headers
  use #(headers, after_headers) <- result.try(parse_headers(after_line))

  // Determine body parsing strategy
  let content_length = get_content_length(headers)
  let is_chunked = is_transfer_chunked(headers)

  // Parse body
  use #(body, remaining) <- result.try(case is_chunked {
    True -> parse_chunked_body(after_headers)
    False ->
      case content_length {
        option.Some(length) -> parse_body(after_headers, length)
        option.None -> Ok(#(<<>>, after_headers))
      }
  })

  let request =
    ParsedRequest(
      method: method,
      uri: uri,
      version: version,
      headers: headers,
      body: body,
    )

  Ok(#(request, remaining))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Request Line Parsing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses the request line: "METHOD URI HTTP/VERSION\r\n"
///
/// ## Returns
///
/// A tuple of (Method, URI, HttpVersion, remaining_bytes) or a ParseError
///
pub fn parse_request_line(
  bytes: BitArray,
) -> Result(#(Method, String, HttpVersion, BitArray), ParseError) {
  // Find CRLF
  case find_crlf(bytes, 0) {
    Ok(crlf_pos) -> {
      // Extract request line
      case bytes {
        <<line:bytes-size(crlf_pos), 13, 10, rest:bits>> -> {
          case bit_array.to_string(line) {
            Ok(line_str) -> parse_request_line_string(line_str, rest)
            Error(_) ->
              Error(InvalidRequestLine(message: "Invalid UTF-8 in request line"))
          }
        }
        _ -> Error(InvalidRequestLine(message: "Failed to extract request line"))
      }
    }
    Error(_) -> Error(InvalidRequestLine(message: "No CRLF found in request"))
  }
}

fn parse_request_line_string(
  line: String,
  remaining: BitArray,
) -> Result(#(Method, String, HttpVersion, BitArray), ParseError) {
  let parts = string.split(line, " ")
  case parts {
    [method_str, uri, version_str] -> {
      use method <- result.try(parse_method(method_str))
      use version <- result.try(parse_version(version_str))
      Ok(#(method, uri, version, remaining))
    }
    _ ->
      Error(InvalidRequestLine(
        message: "Request line must have exactly 3 parts: METHOD URI VERSION",
      ))
  }
}

fn parse_method(s: String) -> Result(Method, ParseError) {
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
    other -> Ok(http.Other(other))
  }
}

fn parse_version(s: String) -> Result(HttpVersion, ParseError) {
  case s {
    "HTTP/1.0" -> Ok(Http10)
    "HTTP/1.1" -> Ok(Http11)
    _ -> Error(InvalidVersion(version: s))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Parsing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses HTTP headers until empty line
///
/// Headers end with CRLFCRLF (\r\n\r\n).
/// Header names are normalized to lowercase.
///
/// ## Returns
///
/// A tuple of (headers list, remaining_bytes) or a ParseError
///
pub fn parse_headers(
  bytes: BitArray,
) -> Result(#(List(#(String, String)), BitArray), ParseError) {
  do_parse_headers(bytes, [])
}

fn do_parse_headers(
  bytes: BitArray,
  acc: List(#(String, String)),
) -> Result(#(List(#(String, String)), BitArray), ParseError) {
  // Check for empty line (end of headers)
  case bytes {
    <<13, 10, rest:bits>> -> {
      // CRLF at start = empty line = end of headers
      Ok(#(list.reverse(acc), rest))
    }
    _ -> {
      // Parse one header line
      case parse_header_line(bytes) {
        Ok(#(name, value, remaining)) -> {
          do_parse_headers(remaining, [#(name, value), ..acc])
        }
        Error(e) -> Error(e)
      }
    }
  }
}

fn parse_header_line(
  bytes: BitArray,
) -> Result(#(String, String, BitArray), ParseError) {
  case find_crlf(bytes, 0) {
    Ok(crlf_pos) -> {
      case bytes {
        <<line:bytes-size(crlf_pos), 13, 10, rest:bits>> -> {
          case bit_array.to_string(line) {
            Ok(line_str) -> {
              case string.split_once(line_str, ":") {
                Ok(#(name, value)) -> {
                  let normalized_name = string.lowercase(string.trim(name))
                  let trimmed_value = string.trim(value)
                  Ok(#(normalized_name, trimmed_value, rest))
                }
                Error(_) ->
                  Error(InvalidHeader(
                    message: "Header line missing colon: " <> line_str,
                  ))
              }
            }
            Error(_) -> Error(InvalidHeader(message: "Invalid UTF-8 in header"))
          }
        }
        _ -> Error(InvalidHeader(message: "Failed to extract header line"))
      }
    }
    Error(_) -> Error(InvalidHeader(message: "No CRLF found in headers"))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Body Parsing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses body based on Content-Length
///
/// ## Parameters
///
/// - `bytes`: Bytes after headers
/// - `content_length`: Expected body length
///
/// ## Returns
///
/// A tuple of (body, remaining_bytes) or a ParseError
///
pub fn parse_body(
  bytes: BitArray,
  content_length: Int,
) -> Result(#(BitArray, BitArray), ParseError) {
  let available = bit_array.byte_size(bytes)
  case available >= content_length {
    True -> {
      case bytes {
        <<body:bytes-size(content_length), remaining:bits>> -> {
          Ok(#(body, remaining))
        }
        _ -> Error(MalformedRequest(message: "Failed to extract body"))
      }
    }
    False -> Error(IncompleteBody(expected: content_length, actual: available))
  }
}

/// Parses chunked transfer encoding body
///
/// Chunk format:
/// ```
/// size (hex) CRLF
/// data CRLF
/// ...
/// 0 CRLF
/// CRLF
/// ```
///
pub fn parse_chunked_body(
  bytes: BitArray,
) -> Result(#(BitArray, BitArray), ParseError) {
  do_parse_chunks(bytes, <<>>)
}

fn do_parse_chunks(
  bytes: BitArray,
  acc: BitArray,
) -> Result(#(BitArray, BitArray), ParseError) {
  // Parse chunk size line
  case find_crlf(bytes, 0) {
    Ok(size_line_end) -> {
      case bytes {
        <<size_line:bytes-size(size_line_end), 13, 10, rest:bits>> -> {
          case bit_array.to_string(size_line) {
            Ok(size_str) -> {
              // Parse hex size (ignore chunk extensions after ;)
              let size_part = case string.split_once(size_str, ";") {
                Ok(#(s, _)) -> string.trim(s)
                Error(_) -> string.trim(size_str)
              }
              case parse_hex_int(size_part) {
                Ok(0) -> {
                  // Last chunk - skip trailing CRLF
                  case rest {
                    <<13, 10, remaining:bits>> -> Ok(#(acc, remaining))
                    _ -> Ok(#(acc, rest))
                  }
                }
                Ok(chunk_size) -> {
                  // Read chunk data
                  case rest {
                    <<chunk_data:bytes-size(chunk_size), 13, 10, after_chunk:bits>> -> {
                      let new_acc = <<acc:bits, chunk_data:bits>>
                      do_parse_chunks(after_chunk, new_acc)
                    }
                    _ ->
                      Error(InvalidChunkedEncoding(
                        message: "Incomplete chunk data",
                      ))
                  }
                }
                Error(_) ->
                  Error(InvalidChunkedEncoding(
                    message: "Invalid chunk size: " <> size_part,
                  ))
              }
            }
            Error(_) ->
              Error(InvalidChunkedEncoding(
                message: "Invalid UTF-8 in chunk size",
              ))
          }
        }
        _ ->
          Error(InvalidChunkedEncoding(
            message: "Failed to extract chunk size line",
          ))
      }
    }
    Error(_) ->
      Error(InvalidChunkedEncoding(message: "No CRLF found in chunked body"))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Conversion Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a ParsedRequest to gleam_http Request
///
/// This allows integration with other gleam_http based libraries.
///
pub fn to_http_request(parsed: ParsedRequest) -> http_request.Request(BitArray) {
  // Extract path and query from URI
  let #(path, query) = case string.split_once(parsed.uri, "?") {
    Ok(#(p, q)) -> #(p, option.Some(q))
    Error(_) -> #(parsed.uri, option.None)
  }

  // Get host from headers
  let host = get_header_value(parsed.headers, "host")
  |> option.unwrap("")

  http_request.Request(
    method: parsed.method,
    headers: parsed.headers,
    body: parsed.body,
    scheme: http.Http,
    host: host,
    port: option.None,
    path: path,
    query: query,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a ParseError to a human-readable string
///
pub fn error_to_string(error: ParseError) -> String {
  case error {
    InvalidLength(expected, actual) ->
      "Invalid length: expected at least "
      <> int.to_string(expected)
      <> " bytes, got "
      <> int.to_string(actual)
    InvalidRequestLine(message) -> "Invalid request line: " <> message
    InvalidMethod(method) -> "Invalid HTTP method: " <> method
    InvalidVersion(version) -> "Invalid HTTP version: " <> version
    InvalidHeader(message) -> "Invalid header: " <> message
    InvalidContentLength(value) -> "Invalid Content-Length: " <> value
    IncompleteBody(expected, actual) ->
      "Incomplete body: expected "
      <> int.to_string(expected)
      <> " bytes, got "
      <> int.to_string(actual)
    InvalidChunkedEncoding(message) -> "Invalid chunked encoding: " <> message
    MalformedRequest(message) -> "Malformed request: " <> message
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Finds the position of CRLF in bytes starting from offset
///
fn find_crlf(bytes: BitArray, offset: Int) -> Result(Int, Nil) {
  let size = bit_array.byte_size(bytes)
  case offset + 1 >= size {
    True -> Error(Nil)
    False -> {
      case bytes {
        <<_:bytes-size(offset), 13, 10, _:bits>> -> Ok(offset)
        _ -> find_crlf(bytes, offset + 1)
      }
    }
  }
}

/// Gets Content-Length from headers
///
fn get_content_length(headers: List(#(String, String))) -> option.Option(Int) {
  case get_header_value(headers, "content-length") {
    option.Some(value) -> {
      case int.parse(value) {
        Ok(length) -> option.Some(length)
        Error(_) -> option.None
      }
    }
    option.None -> option.None
  }
}

/// Checks if Transfer-Encoding is chunked
///
fn is_transfer_chunked(headers: List(#(String, String))) -> Bool {
  case get_header_value(headers, "transfer-encoding") {
    option.Some(value) -> string.contains(string.lowercase(value), "chunked")
    option.None -> False
  }
}

/// Gets a header value by lowercase name
///
fn get_header_value(
  headers: List(#(String, String)),
  name: String,
) -> option.Option(String) {
  headers
  |> list.find(fn(h) { h.0 == name })
  |> option.from_result()
  |> option.map(fn(h) { h.1 })
}

/// Parses a hexadecimal string to an integer
///
fn parse_hex_int(s: String) -> Result(Int, Nil) {
  let chars = string.to_graphemes(string.lowercase(s))
  do_parse_hex(chars, 0)
}

fn do_parse_hex(chars: List(String), acc: Int) -> Result(Int, Nil) {
  case chars {
    [] -> Ok(acc)
    [c, ..rest] -> {
      case hex_char_value(c) {
        Ok(value) -> do_parse_hex(rest, acc * 16 + value)
        Error(_) -> Error(Nil)
      }
    }
  }
}

fn hex_char_value(c: String) -> Result(Int, Nil) {
  case c {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    "a" -> Ok(10)
    "b" -> Ok(11)
    "c" -> Ok(12)
    "d" -> Ok(13)
    "e" -> Ok(14)
    "f" -> Ok(15)
    _ -> Error(Nil)
  }
}
