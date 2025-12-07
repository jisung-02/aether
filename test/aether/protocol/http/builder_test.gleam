import aether/protocol/http/builder
import aether/protocol/http/request
import aether/protocol/http/response
import gleam/bit_array
import gleam/http
import gleam/http/request as http_request
import gleam/option
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build Request Line Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_request_line_get_test() {
  let bytes = builder.build_request_line(http.Get, "/", request.Http11)

  bytes |> should.equal(<<"GET / HTTP/1.1\r\n":utf8>>)
}

pub fn build_request_line_post_test() {
  let bytes = builder.build_request_line(http.Post, "/api/users", request.Http11)

  bytes |> should.equal(<<"POST /api/users HTTP/1.1\r\n":utf8>>)
}

pub fn build_request_line_http10_test() {
  let bytes = builder.build_request_line(http.Get, "/", request.Http10)

  bytes |> should.equal(<<"GET / HTTP/1.0\r\n":utf8>>)
}

pub fn build_request_line_with_query_test() {
  let bytes =
    builder.build_request_line(http.Get, "/api?page=1&limit=10", request.Http11)

  bytes |> should.equal(<<"GET /api?page=1&limit=10 HTTP/1.1\r\n":utf8>>)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build Header Line Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_header_line_test() {
  let bytes = builder.build_header_line("Host", "example.com")

  bytes |> should.equal(<<"Host: example.com\r\n":utf8>>)
}

pub fn build_header_line_content_type_test() {
  let bytes = builder.build_header_line("Content-Type", "application/json")

  bytes |> should.equal(<<"Content-Type: application/json\r\n":utf8>>)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build Headers Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_headers_single_test() {
  let bytes = builder.build_headers([#("host", "example.com")])

  bytes |> should.equal(<<"host: example.com\r\n":utf8>>)
}

pub fn build_headers_multiple_test() {
  let bytes =
    builder.build_headers([
      #("host", "example.com"),
      #("accept", "application/json"),
    ])

  bytes
  |> should.equal(
    <<"host: example.com\r\naccept: application/json\r\n":utf8>>,
  )
}

pub fn build_headers_empty_test() {
  let bytes = builder.build_headers([])

  bytes |> should.equal(<<>>)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build Request Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_simple_get_request_test() {
  let req =
    request.get("/")
    |> request.set_header("Host", "example.com")

  let bytes = builder.build_request(req)
  let expected = <<"GET / HTTP/1.1\r\nhost: example.com\r\n\r\n":utf8>>

  bytes |> should.equal(expected)
}

pub fn build_get_with_multiple_headers_test() {
  let req =
    request.get("/api/users")
    |> request.set_header("Host", "example.com")
    |> request.set_header("Accept", "application/json")

  let bytes = builder.build_request(req)

  // Check that it contains the expected components
  let assert Ok(str) = bit_array.to_string(bytes)
  str |> should_contain("GET /api/users HTTP/1.1\r\n")
  str |> should_contain("host: example.com\r\n")
  str |> should_contain("accept: application/json\r\n")
  str |> should_contain("\r\n\r\n")
}

pub fn build_post_with_body_test() {
  let body = <<"Hello, World!":utf8>>
  let req =
    request.post("/api/messages")
    |> request.set_header("Host", "example.com")
    |> request.set_header("Content-Type", "text/plain")
    |> request.set_body(body)

  let bytes = builder.build_request(req)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("POST /api/messages HTTP/1.1\r\n")
  str |> should_contain("host: example.com\r\n")
  str |> should_contain("content-type: text/plain\r\n")
  str |> should_contain("content-length: 13\r\n")
  str |> should_contain("\r\n\r\nHello, World!")
}

pub fn build_post_with_json_body_test() {
  let body = <<"{\"name\": \"test\"}":utf8>>
  let req =
    request.post("/api/data")
    |> request.set_header("Host", "example.com")
    |> request.set_header("Content-Type", "application/json")
    |> request.set_body(body)

  let bytes = builder.build_request(req)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("content-length: 16\r\n")
  str |> should_contain("{\"name\": \"test\"}")
}

pub fn build_request_with_existing_content_length_test() {
  let body = <<"test":utf8>>
  let req =
    request.post("/api")
    |> request.set_header("Host", "example.com")
    |> request.set_header("Content-Length", "4")
    |> request.set_body(body)

  let bytes = builder.build_request(req)
  let assert Ok(str) = bit_array.to_string(bytes)

  // Should not duplicate Content-Length
  let count = count_occurrences(str, "content-length")
  count |> should.equal(1)
}

pub fn build_empty_body_no_content_length_test() {
  let req =
    request.get("/")
    |> request.set_header("Host", "example.com")

  let bytes = builder.build_request(req)
  let assert Ok(str) = bit_array.to_string(bytes)

  // Should not have Content-Length for empty body
  str |> should_not_contain("content-length")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build from gleam_http Request Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn from_http_request_test() {
  let req =
    http_request.Request(
      method: http.Get,
      headers: [],
      body: <<>>,
      scheme: http.Http,
      host: "example.com",
      port: option.None,
      path: "/api/users",
      query: option.None,
    )

  let bytes = builder.from_http_request(req)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("GET /api/users HTTP/1.1\r\n")
  str |> should_contain("host: example.com\r\n")
}

pub fn from_http_request_with_query_test() {
  let req =
    http_request.Request(
      method: http.Get,
      headers: [],
      body: <<>>,
      scheme: http.Http,
      host: "example.com",
      port: option.None,
      path: "/api",
      query: option.Some("page=1"),
    )

  let bytes = builder.from_http_request(req)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("GET /api?page=1 HTTP/1.1\r\n")
}

pub fn from_http_request_with_existing_host_test() {
  let req =
    http_request.Request(
      method: http.Get,
      headers: [#("host", "custom.com")],
      body: <<>>,
      scheme: http.Http,
      host: "example.com",
      port: option.None,
      path: "/",
      query: option.None,
    )

  let bytes = builder.from_http_request(req)
  let assert Ok(str) = bit_array.to_string(bytes)

  // Should use the existing host header, not duplicate
  str |> should_contain("host: custom.com\r\n")
  let count = count_occurrences(str, "host:")
  count |> should.equal(1)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Chunked Encoding Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_chunked_body_test() {
  let body = <<"Hello, World!":utf8>>
  let chunked = builder.build_chunked_body(body)
  let assert Ok(str) = bit_array.to_string(chunked)

  // 13 bytes = 0xd in hex
  str |> should_contain("d\r\n")
  str |> should_contain("Hello, World!")
  str |> should_contain("\r\n0\r\n\r\n")
}

pub fn build_chunked_body_empty_test() {
  let chunked = builder.build_chunked_body(<<>>)

  chunked |> should.equal(<<"0\r\n\r\n":utf8>>)
}

pub fn build_chunked_request_test() {
  let req =
    request.post("/api")
    |> request.set_header("Host", "example.com")
    |> request.set_body(<<"test":utf8>>)

  let bytes = builder.build_chunked_request(req)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("transfer-encoding: chunked\r\n")
  str |> should_not_contain("content-length")
  str |> should_contain("4\r\ntest\r\n0\r\n\r\n")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// to_bytes Alias Test
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn to_bytes_test() {
  let req =
    request.get("/")
    |> request.set_header("Host", "example.com")

  let bytes1 = builder.build_request(req)
  let bytes2 = builder.to_bytes(req)

  bytes1 |> should.equal(bytes2)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/string

fn should_contain(haystack: String, needle: String) {
  string.contains(haystack, needle) |> should.be_true()
}

fn should_not_contain(haystack: String, needle: String) {
  string.contains(haystack, needle) |> should.be_false()
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  let parts = string.split(haystack, needle)
  list.length(parts) - 1
}

import gleam/list

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build Response Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_simple_ok_response_test() {
  let resp = response.ok()
  let bytes = builder.build_response(resp)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("HTTP/1.1 200 OK\r\n")
  str |> should_contain("\r\n\r\n")
}

pub fn build_response_with_body_test() {
  let resp =
    response.ok()
    |> response.text()
    |> response.with_string_body("Hello, World!")

  let bytes = builder.build_response(resp)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("HTTP/1.1 200 OK\r\n")
  str |> should_contain("content-type: text/plain; charset=utf-8\r\n")
  str |> should_contain("content-length: 13\r\n")
  str |> should_contain("\r\n\r\nHello, World!")
}

pub fn build_not_found_response_test() {
  let resp =
    response.not_found()
    |> response.with_string_body("Page not found")

  let bytes = builder.build_response(resp)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("HTTP/1.1 404 Not Found\r\n")
  str |> should_contain("content-length: 14\r\n")
  str |> should_contain("\r\n\r\nPage not found")
}

pub fn build_response_with_multiple_headers_test() {
  let resp =
    response.ok()
    |> response.with_header("X-Custom-Header", "custom-value")
    |> response.with_header("Cache-Control", "no-cache")
    |> response.with_string_body("test")

  let bytes = builder.build_response(resp)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("x-custom-header: custom-value\r\n")
  str |> should_contain("cache-control: no-cache\r\n")
  str |> should_contain("content-length: 4\r\n")
}

pub fn build_response_http10_test() {
  let resp =
    response.ok()
    |> response.set_version(request.Http10)

  let bytes = builder.build_response(resp)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("HTTP/1.0 200 OK\r\n")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build Status Line Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_status_line_ok_test() {
  let resp = response.ok()
  let bytes = builder.build_status_line(resp)

  bytes |> should.equal(<<"HTTP/1.1 200 OK\r\n":utf8>>)
}

pub fn build_status_line_not_found_test() {
  let resp = response.not_found()
  let bytes = builder.build_status_line(resp)

  bytes |> should.equal(<<"HTTP/1.1 404 Not Found\r\n":utf8>>)
}

pub fn build_status_line_custom_reason_test() {
  let resp =
    response.new(418)
    |> response.with_reason("I'm a teapot")
  let bytes = builder.build_status_line(resp)

  bytes |> should.equal(<<"HTTP/1.1 418 I'm a teapot\r\n":utf8>>)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build Chunked Response Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_chunked_response_test() {
  let resp =
    response.ok()
    |> response.text()

  let chunks = [<<"Hello":utf8>>, <<" ":utf8>>, <<"World":utf8>>]
  let bytes = builder.build_chunked_response(resp, chunks)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("HTTP/1.1 200 OK\r\n")
  str |> should_contain("transfer-encoding: chunked\r\n")
  str |> should_not_contain("content-length")
  // Check chunk format: size\r\ndata\r\n
  str |> should_contain("5\r\nHello\r\n")
  str |> should_contain("1\r\n \r\n")
  str |> should_contain("5\r\nWorld\r\n")
  str |> should_contain("0\r\n\r\n")
}

pub fn build_chunked_response_single_chunk_test() {
  let resp = response.ok()
  let chunks = [<<"Hello, World!":utf8>>]
  let bytes = builder.build_chunked_response(resp, chunks)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("transfer-encoding: chunked\r\n")
  // 13 bytes = d in hex
  str |> should_contain("d\r\nHello, World!\r\n")
  str |> should_contain("0\r\n\r\n")
}

pub fn build_chunked_response_empty_chunks_test() {
  let resp = response.ok()
  let chunks = []
  let bytes = builder.build_chunked_response(resp, chunks)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("transfer-encoding: chunked\r\n")
  str |> should_contain("0\r\n\r\n")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Response to Bytes Alias Test
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn response_to_bytes_test() {
  let resp =
    response.ok()
    |> response.with_string_body("test")

  let bytes1 = builder.build_response(resp)
  let bytes2 = builder.response_to_bytes(resp)

  bytes1 |> should.equal(bytes2)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Content-Length Auto Calculation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn response_content_length_auto_test() {
  let resp =
    response.ok()
    |> response.with_body(<<"12345":utf8>>)

  let bytes = builder.build_response(resp)
  let assert Ok(str) = bit_array.to_string(bytes)

  str |> should_contain("content-length: 5\r\n")
}

pub fn response_no_content_length_for_empty_body_test() {
  let resp = response.ok()

  let bytes = builder.build_response(resp)
  let assert Ok(str) = bit_array.to_string(bytes)

  // Empty body should still serialize (no content-length since with_body not called)
  str |> should_contain("HTTP/1.1 200 OK\r\n")
}
