import aether/protocol/http/request
import gleam/http
import gleam/option
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_request_test() {
  let req = request.new(http.Get, "/api/users")

  req.method |> should.equal(http.Get)
  req.uri |> should.equal("/api/users")
  req.version |> should.equal(request.Http11)
  req.headers |> should.equal([])
  req.body |> should.equal(<<>>)
}

pub fn get_request_test() {
  let req = request.get("/api/users")

  req.method |> should.equal(http.Get)
  req.uri |> should.equal("/api/users")
}

pub fn post_request_test() {
  let req = request.post("/api/users")

  req.method |> should.equal(http.Post)
  req.uri |> should.equal("/api/users")
}

pub fn put_request_test() {
  let req = request.put("/api/users/1")

  req.method |> should.equal(http.Put)
  req.uri |> should.equal("/api/users/1")
}

pub fn delete_request_test() {
  let req = request.delete("/api/users/1")

  req.method |> should.equal(http.Delete)
  req.uri |> should.equal("/api/users/1")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Modifier Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn set_version_test() {
  let req =
    request.get("/")
    |> request.set_version(request.Http10)

  req.version |> should.equal(request.Http10)
}

pub fn set_body_test() {
  let body = <<"Hello, World!":utf8>>
  let req =
    request.post("/api/messages")
    |> request.set_body(body)

  req.body |> should.equal(body)
}

pub fn set_header_test() {
  let req =
    request.get("/")
    |> request.set_header("Host", "example.com")
    |> request.set_header("Accept", "application/json")

  req.headers |> should.equal([#("host", "example.com"), #("accept", "application/json")])
}

pub fn set_header_replaces_existing_test() {
  let req =
    request.get("/")
    |> request.set_header("Host", "example.com")
    |> request.set_header("Host", "other.com")

  req.headers |> should.equal([#("host", "other.com")])
}

pub fn set_header_normalizes_name_test() {
  let req =
    request.get("/")
    |> request.set_header("Content-Type", "text/html")

  req.headers |> should.equal([#("content-type", "text/html")])
}

pub fn add_header_test() {
  let req =
    request.get("/")
    |> request.add_header("Accept", "application/json")
    |> request.add_header("Accept", "text/html")

  req.headers |> should.equal([#("accept", "application/json"), #("accept", "text/html")])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accessor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn get_header_test() {
  let req =
    request.get("/")
    |> request.set_header("Host", "example.com")

  request.get_header(req, "host") |> should.equal(option.Some("example.com"))
  request.get_header(req, "Host") |> should.equal(option.Some("example.com"))
  request.get_header(req, "HOST") |> should.equal(option.Some("example.com"))
  request.get_header(req, "accept") |> should.equal(option.None)
}

pub fn get_header_values_test() {
  let req =
    request.get("/")
    |> request.add_header("Accept", "application/json")
    |> request.add_header("Accept", "text/html")

  request.get_header_values(req, "accept")
  |> should.equal(["application/json", "text/html"])
}

pub fn get_header_values_empty_test() {
  let req = request.get("/")

  request.get_header_values(req, "accept") |> should.equal([])
}

pub fn has_header_test() {
  let req =
    request.get("/")
    |> request.set_header("Host", "example.com")

  request.has_header(req, "host") |> should.be_true()
  request.has_header(req, "Host") |> should.be_true()
  request.has_header(req, "accept") |> should.be_false()
}

pub fn content_length_test() {
  let req =
    request.post("/")
    |> request.set_header("Content-Length", "42")

  request.content_length(req) |> should.equal(option.Some(42))
}

pub fn content_length_invalid_test() {
  let req =
    request.post("/")
    |> request.set_header("Content-Length", "invalid")

  request.content_length(req) |> should.equal(option.None)
}

pub fn content_length_missing_test() {
  let req = request.post("/")

  request.content_length(req) |> should.equal(option.None)
}

pub fn is_chunked_test() {
  let req =
    request.post("/")
    |> request.set_header("Transfer-Encoding", "chunked")

  request.is_chunked(req) |> should.be_true()
}

pub fn is_chunked_with_other_values_test() {
  let req =
    request.post("/")
    |> request.set_header("Transfer-Encoding", "gzip, chunked")

  request.is_chunked(req) |> should.be_true()
}

pub fn is_not_chunked_test() {
  let req =
    request.post("/")
    |> request.set_header("Transfer-Encoding", "gzip")

  request.is_chunked(req) |> should.be_false()
}

pub fn host_test() {
  let req =
    request.get("/")
    |> request.set_header("Host", "example.com:8080")

  request.host(req) |> should.equal(option.Some("example.com:8080"))
}

pub fn content_type_test() {
  let req =
    request.post("/")
    |> request.set_header("Content-Type", "application/json")

  request.content_type(req) |> should.equal(option.Some("application/json"))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Version Conversion Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn version_to_string_test() {
  request.version_to_string(request.Http10) |> should.equal("HTTP/1.0")
  request.version_to_string(request.Http11) |> should.equal("HTTP/1.1")
}

pub fn version_from_string_test() {
  request.version_from_string("HTTP/1.0") |> should.equal(Ok(request.Http10))
  request.version_from_string("HTTP/1.1") |> should.equal(Ok(request.Http11))
  request.version_from_string("HTTP/2.0") |> should.be_error()
  request.version_from_string("invalid") |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Method Conversion Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn method_to_string_test() {
  request.method_to_string(http.Get) |> should.equal("GET")
  request.method_to_string(http.Post) |> should.equal("POST")
  request.method_to_string(http.Put) |> should.equal("PUT")
  request.method_to_string(http.Delete) |> should.equal("DELETE")
  request.method_to_string(http.Patch) |> should.equal("PATCH")
  request.method_to_string(http.Head) |> should.equal("HEAD")
  request.method_to_string(http.Options) |> should.equal("OPTIONS")
  request.method_to_string(http.Connect) |> should.equal("CONNECT")
  request.method_to_string(http.Trace) |> should.equal("TRACE")
  request.method_to_string(http.Other("CUSTOM")) |> should.equal("CUSTOM")
}

pub fn method_from_string_test() {
  request.method_from_string("GET") |> should.equal(Ok(http.Get))
  request.method_from_string("get") |> should.equal(Ok(http.Get))
  request.method_from_string("POST") |> should.equal(Ok(http.Post))
  request.method_from_string("CUSTOM") |> should.equal(Ok(http.Other("CUSTOM")))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// URI Helper Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn path_without_query_test() {
  let req = request.get("/api/users")

  request.path(req) |> should.equal("/api/users")
}

pub fn path_with_query_test() {
  let req = request.get("/api/users?page=1&limit=10")

  request.path(req) |> should.equal("/api/users")
}

pub fn query_present_test() {
  let req = request.get("/api/users?page=1&limit=10")

  request.query(req) |> should.equal(option.Some("page=1&limit=10"))
}

pub fn query_absent_test() {
  let req = request.get("/api/users")

  request.query(req) |> should.equal(option.None)
}
