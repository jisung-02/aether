import aether/protocol/http/builder
import aether/protocol/http/parser
import aether/protocol/http/request
import gleam/bit_array
import gleam/http
import gleam/option
import gleam/result
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Simple GET Request Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_simple_get_request_test() {
  let request_bytes = <<"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8>>

  let assert Ok(#(parsed, remaining)) = parser.parse_request(request_bytes)

  parsed.method |> should.equal(http.Get)
  parsed.uri |> should.equal("/")
  parsed.version |> should.equal(request.Http11)
  parsed.body |> should.equal(<<>>)
  remaining |> should.equal(<<>>)
}

pub fn parse_get_with_path_test() {
  let request_bytes = <<
    "GET /api/users HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.uri |> should.equal("/api/users")
}

pub fn parse_get_with_query_test() {
  let request_bytes = <<
    "GET /api/users?page=1&limit=10 HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.uri |> should.equal("/api/users?page=1&limit=10")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// POST Request with Body Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_post_with_body_test() {
  let body = <<"Hello, World!":utf8>>
  let body_len = bit_array.byte_size(body)
  let request_bytes = <<
    "POST /api/messages HTTP/1.1\r\nHost: example.com\r\nContent-Length: ":utf8,
    { body_len |> int_to_string }:utf8,
    "\r\n\r\n":utf8,
    body:bits,
  >>

  let assert Ok(#(parsed, remaining)) = parser.parse_request(request_bytes)

  parsed.method |> should.equal(http.Post)
  parsed.uri |> should.equal("/api/messages")
  parsed.body |> should.equal(body)
  remaining |> should.equal(<<>>)
}

pub fn parse_post_json_body_test() {
  let body = <<"{\"name\": \"test\"}":utf8>>
  let request_bytes = <<
    "POST /api/data HTTP/1.1\r\nHost: example.com\r\nContent-Type: application/json\r\nContent-Length: ":utf8,
    { bit_array.byte_size(body) |> int_to_string }:utf8,
    "\r\n\r\n":utf8,
    body:bits,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.body |> should.equal(body)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Methods Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_put_method_test() {
  let request_bytes = <<
    "PUT /api/users/1 HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.method |> should.equal(http.Put)
}

pub fn parse_delete_method_test() {
  let request_bytes = <<
    "DELETE /api/users/1 HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.method |> should.equal(http.Delete)
}

pub fn parse_patch_method_test() {
  let request_bytes = <<
    "PATCH /api/users/1 HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.method |> should.equal(http.Patch)
}

pub fn parse_head_method_test() {
  let request_bytes = <<
    "HEAD /api/users HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.method |> should.equal(http.Head)
}

pub fn parse_options_method_test() {
  let request_bytes = <<
    "OPTIONS /api HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.method |> should.equal(http.Options)
}

pub fn parse_custom_method_test() {
  let request_bytes = <<
    "CUSTOM /api HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.method |> should.equal(http.Other("CUSTOM"))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Version Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_http10_version_test() {
  let request_bytes = <<"GET / HTTP/1.0\r\nHost: example.com\r\n\r\n":utf8>>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.version |> should.equal(request.Http10)
}

pub fn parse_http11_version_test() {
  let request_bytes = <<"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8>>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.version |> should.equal(request.Http11)
}

pub fn parse_invalid_version_test() {
  let request_bytes = <<"GET / HTTP/2.0\r\nHost: example.com\r\n\r\n":utf8>>

  parser.parse_request(request_bytes)
  |> result.is_error()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_headers_case_insensitive_test() {
  let request_bytes = <<
    "GET / HTTP/1.1\r\nHOST: example.com\r\nContent-TYPE: text/html\r\n\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  // Headers should be normalized to lowercase
  request.get_header(parsed, "host") |> should.equal(option.Some("example.com"))
  request.get_header(parsed, "content-type")
  |> should.equal(option.Some("text/html"))
}

pub fn parse_multiple_headers_test() {
  let request_bytes = <<
    "GET / HTTP/1.1\r\n":utf8,
    "Host: example.com\r\n":utf8,
    "Accept: application/json\r\n":utf8,
    "User-Agent: Test/1.0\r\n":utf8,
    "\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  request.get_header(parsed, "host") |> should.equal(option.Some("example.com"))
  request.get_header(parsed, "accept")
  |> should.equal(option.Some("application/json"))
  request.get_header(parsed, "user-agent")
  |> should.equal(option.Some("Test/1.0"))
}

pub fn parse_header_with_spaces_test() {
  let request_bytes = <<"GET / HTTP/1.1\r\nHost:   example.com  \r\n\r\n":utf8>>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  // Leading/trailing spaces should be trimmed
  request.get_header(parsed, "host") |> should.equal(option.Some("example.com"))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Chunked Body Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_chunked_body_test() {
  let request_bytes = <<
    "POST /api HTTP/1.1\r\n":utf8,
    "Host: example.com\r\n":utf8,
    "Transfer-Encoding: chunked\r\n":utf8,
    "\r\n":utf8,
    "5\r\n":utf8,
    "Hello":utf8,
    "\r\n":utf8,
    "6\r\n":utf8,
    " World":utf8,
    "\r\n":utf8,
    "0\r\n":utf8,
    "\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.body |> should.equal(<<"Hello World":utf8>>)
}

pub fn parse_chunked_single_chunk_test() {
  let request_bytes = <<
    "POST /api HTTP/1.1\r\n":utf8,
    "Host: example.com\r\n":utf8,
    "Transfer-Encoding: chunked\r\n":utf8,
    "\r\n":utf8,
    "d\r\n":utf8,
    "Hello, World!":utf8,
    "\r\n":utf8,
    "0\r\n":utf8,
    "\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.body |> should.equal(<<"Hello, World!":utf8>>)
}

pub fn parse_chunked_empty_body_test() {
  let request_bytes = <<
    "POST /api HTTP/1.1\r\n":utf8,
    "Host: example.com\r\n":utf8,
    "Transfer-Encoding: chunked\r\n":utf8,
    "\r\n":utf8,
    "0\r\n":utf8,
    "\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)

  parsed.body |> should.equal(<<>>)
}

pub fn parse_chunked_body_with_trailers_test() {
  let request_bytes = <<
    "POST /api HTTP/1.1\r\n":utf8,
    "Host: example.com\r\n":utf8,
    "Transfer-Encoding: chunked\r\n":utf8,
    "\r\n":utf8,
    "5\r\n":utf8,
    "Hello":utf8,
    "\r\n":utf8,
    "0\r\n":utf8,
    "X-Trace-Id: abc123\r\n":utf8,
    "X-Checksum: ok\r\n":utf8,
    "\r\n":utf8,
    "GET /next HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let assert Ok(#(parsed, remaining)) = parser.parse_request(request_bytes)
  parsed.body |> should.equal(<<"Hello":utf8>>)

  let assert Ok(#(next, final_remaining)) = parser.parse_request(remaining)
  next.uri |> should.equal("/next")
  final_remaining |> should.equal(<<>>)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Pipelining Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_pipelining_test() {
  let request_bytes = <<
    "GET /first HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
    "GET /second HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  // Parse first request
  let assert Ok(#(first, remaining)) = parser.parse_request(request_bytes)
  first.uri |> should.equal("/first")

  // Parse second request from remaining bytes
  let assert Ok(#(second, final_remaining)) = parser.parse_request(remaining)
  second.uri |> should.equal("/second")
  final_remaining |> should.equal(<<>>)
}

pub fn parse_pipelining_with_body_test() {
  let body = <<"test":utf8>>
  let request_bytes = <<
    "POST /first HTTP/1.1\r\nHost: example.com\r\nContent-Length: 4\r\n\r\ntest":utf8,
    "GET /second HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  // Parse first request (with body)
  let assert Ok(#(first, remaining)) = parser.parse_request(request_bytes)
  first.uri |> should.equal("/first")
  first.body |> should.equal(body)

  // Parse second request from remaining bytes
  let assert Ok(#(second, _)) = parser.parse_request(remaining)
  second.uri |> should.equal("/second")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Cases Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_invalid_request_line_test() {
  let request_bytes = <<"INVALID":utf8>>

  parser.parse_request(request_bytes)
  |> result.is_error()
  |> should.be_true()
}

pub fn parse_incomplete_headers_test() {
  let request_bytes = <<"GET / HTTP/1.1\r\nHost":utf8>>

  parser.parse_request(request_bytes)
  |> result.is_error()
  |> should.be_true()
}

pub fn parse_incomplete_body_test() {
  let request_bytes = <<
    "POST /api HTTP/1.1\r\n":utf8,
    "Host: example.com\r\n":utf8,
    "Content-Length: 100\r\n":utf8,
    "\r\n":utf8,
    "short":utf8,
  >>

  parser.parse_request(request_bytes)
  |> result.is_error()
  |> should.be_true()
}

pub fn parse_invalid_content_length_test() {
  let request_bytes = <<
    "POST /api HTTP/1.1\r\n":utf8,
    "Host: example.com\r\n":utf8,
    "Content-Length: abc\r\n":utf8,
    "\r\n":utf8,
    "body":utf8,
  >>

  parser.parse_request(request_bytes)
  |> should.equal(Error(parser.InvalidContentLength(value: "abc")))
}

pub fn parse_negative_content_length_test() {
  let request_bytes = <<
    "POST /api HTTP/1.1\r\n":utf8,
    "Host: example.com\r\n":utf8,
    "Content-Length: -1\r\n":utf8,
    "\r\n":utf8,
  >>

  parser.parse_request(request_bytes)
  |> should.equal(Error(parser.InvalidContentLength(value: "-1")))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Conversion to gleam_http Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn to_http_request_test() {
  let request_bytes = <<
    "GET /api/users?page=1 HTTP/1.1\r\n":utf8,
    "Host: example.com\r\n":utf8,
    "\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)
  let http_req = parser.to_http_request(parsed)

  http_req.method |> should.equal(http.Get)
  http_req.path |> should.equal("/api/users")
  http_req.query |> should.equal(option.Some("page=1"))
  http_req.host |> should.equal("example.com")
}

pub fn to_http_request_no_query_test() {
  let request_bytes = <<
    "GET /api/users HTTP/1.1\r\n":utf8,
    "Host: example.com\r\n":utf8,
    "\r\n":utf8,
  >>

  let assert Ok(#(parsed, _)) = parser.parse_request(request_bytes)
  let http_req = parser.to_http_request(parsed)

  http_req.path |> should.equal("/api/users")
  http_req.query |> should.equal(option.None)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Roundtrip Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn roundtrip_simple_request_test() {
  let original =
    request.get("/api/users")
    |> request.set_header("Host", "example.com")

  let bytes = builder.build_request(original)
  let assert Ok(#(parsed, _)) = parser.parse_request(bytes)

  parsed.method |> should.equal(original.method)
  parsed.uri |> should.equal(original.uri)
  parsed.version |> should.equal(original.version)
}

pub fn roundtrip_post_with_body_test() {
  let body = <<"test body":utf8>>
  let original =
    request.post("/api/data")
    |> request.set_header("Host", "example.com")
    |> request.set_header("Content-Type", "text/plain")
    |> request.set_body(body)

  let bytes = builder.build_request(original)
  let assert Ok(#(parsed, _)) = parser.parse_request(bytes)

  parsed.method |> should.equal(original.method)
  parsed.uri |> should.equal(original.uri)
  parsed.body |> should.equal(body)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_to_string_test() {
  parser.error_to_string(parser.InvalidRequestLine(message: "test"))
  |> should.equal("Invalid request line: test")

  parser.error_to_string(parser.InvalidVersion(version: "HTTP/2.0"))
  |> should.equal("Invalid HTTP version: HTTP/2.0")

  parser.error_to_string(parser.IncompleteBody(expected: 100, actual: 10))
  |> should.equal("Incomplete body: expected 100 bytes, got 10")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(n: Int) -> String
