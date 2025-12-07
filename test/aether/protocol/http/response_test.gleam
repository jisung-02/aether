import aether/protocol/http/request.{Http10, Http11}
import aether/protocol/http/response
import gleam/bit_array
import gleam/json
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_response_test() {
  let resp = response.new(200)

  resp.status |> should.equal(200)
  resp.reason |> should.equal("OK")
  resp.version |> should.equal(Http11)
  resp.headers |> should.equal([])
  resp.body |> should.equal(<<>>)
}

pub fn ok_response_test() {
  let resp = response.ok()

  resp.status |> should.equal(200)
  resp.reason |> should.equal("OK")
}

pub fn created_response_test() {
  let resp = response.created()

  resp.status |> should.equal(201)
  resp.reason |> should.equal("Created")
}

pub fn no_content_response_test() {
  let resp = response.no_content()

  resp.status |> should.equal(204)
  resp.reason |> should.equal("No Content")
}

pub fn bad_request_response_test() {
  let resp = response.bad_request()

  resp.status |> should.equal(400)
  resp.reason |> should.equal("Bad Request")
}

pub fn unauthorized_response_test() {
  let resp = response.unauthorized()

  resp.status |> should.equal(401)
  resp.reason |> should.equal("Unauthorized")
}

pub fn forbidden_response_test() {
  let resp = response.forbidden()

  resp.status |> should.equal(403)
  resp.reason |> should.equal("Forbidden")
}

pub fn not_found_response_test() {
  let resp = response.not_found()

  resp.status |> should.equal(404)
  resp.reason |> should.equal("Not Found")
}

pub fn internal_server_error_response_test() {
  let resp = response.internal_server_error()

  resp.status |> should.equal(500)
  resp.reason |> should.equal("Internal Server Error")
}

pub fn service_unavailable_response_test() {
  let resp = response.service_unavailable()

  resp.status |> should.equal(503)
  resp.reason |> should.equal("Service Unavailable")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Builder Pattern Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn set_version_test() {
  let resp =
    response.ok()
    |> response.set_version(Http10)

  resp.version |> should.equal(Http10)
}

pub fn with_body_test() {
  let body = <<"Hello, World!":utf8>>
  let resp =
    response.ok()
    |> response.with_body(body)

  resp.body |> should.equal(body)
}

pub fn with_body_sets_content_length_test() {
  let body = <<"Hello":utf8>>
  let resp =
    response.ok()
    |> response.with_body(body)

  response.get_content_length(resp) |> should.equal(Ok(5))
}

pub fn with_string_body_test() {
  let resp =
    response.ok()
    |> response.with_string_body("Hello, World!")

  resp.body |> should.equal(<<"Hello, World!":utf8>>)
}

pub fn with_header_test() {
  let resp =
    response.ok()
    |> response.with_header("X-Custom", "value")

  response.get_header(resp, "x-custom") |> should.equal(Ok("value"))
}

pub fn with_header_case_insensitive_test() {
  let resp =
    response.ok()
    |> response.with_header("Content-Type", "text/plain")

  // Header name should be lowercase
  response.get_header(resp, "CONTENT-TYPE") |> should.equal(Ok("text/plain"))
}

pub fn with_header_replaces_existing_test() {
  let resp =
    response.ok()
    |> response.with_header("X-Custom", "old")
    |> response.with_header("X-Custom", "new")

  response.get_header(resp, "x-custom") |> should.equal(Ok("new"))

  // Should only have one header
  resp.headers
  |> list.length()
  |> should.equal(1)
}

pub fn with_headers_test() {
  let resp =
    response.ok()
    |> response.with_headers([
      #("X-One", "1"),
      #("X-Two", "2"),
    ])

  response.get_header(resp, "x-one") |> should.equal(Ok("1"))
  response.get_header(resp, "x-two") |> should.equal(Ok("2"))
}

pub fn with_content_type_test() {
  let resp =
    response.ok()
    |> response.with_content_type("application/json")

  response.get_content_type(resp) |> should.equal(Ok("application/json"))
}

pub fn json_content_type_test() {
  let resp =
    response.ok()
    |> response.json()

  response.get_content_type(resp)
  |> should.equal(Ok("application/json; charset=utf-8"))
}

pub fn html_content_type_test() {
  let resp =
    response.ok()
    |> response.html()

  response.get_content_type(resp)
  |> should.equal(Ok("text/html; charset=utf-8"))
}

pub fn text_content_type_test() {
  let resp =
    response.ok()
    |> response.text()

  response.get_content_type(resp)
  |> should.equal(Ok("text/plain; charset=utf-8"))
}

pub fn with_reason_test() {
  let resp =
    response.new(418)
    |> response.with_reason("I'm a teapot")

  resp.reason |> should.equal("I'm a teapot")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Response Helper Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn json_response_test() {
  let data = json.object([#("id", json.int(1)), #("name", json.string("test"))])
  let resp = response.json_response(200, data)

  resp.status |> should.equal(200)
  response.get_content_type(resp)
  |> should.equal(Ok("application/json; charset=utf-8"))

  let assert Ok(body_str) = bit_array.to_string(resp.body)
  body_str |> should_contain("{")
  body_str |> should_contain("\"id\"")
}

pub fn html_response_test() {
  let html = "<html><body>Hello</body></html>"
  let resp = response.html_response(200, html)

  resp.status |> should.equal(200)
  response.get_content_type(resp)
  |> should.equal(Ok("text/html; charset=utf-8"))
  resp.body |> should.equal(<<html:utf8>>)
}

pub fn text_response_test() {
  let text = "Hello, World!"
  let resp = response.text_response(200, text)

  resp.status |> should.equal(200)
  response.get_content_type(resp)
  |> should.equal(Ok("text/plain; charset=utf-8"))
  resp.body |> should.equal(<<text:utf8>>)
}

pub fn redirect_permanent_test() {
  let resp = response.redirect("/new-location", True)

  resp.status |> should.equal(301)
  response.get_header(resp, "location") |> should.equal(Ok("/new-location"))
}

pub fn redirect_temporary_test() {
  let resp = response.redirect("/new-location", False)

  resp.status |> should.equal(302)
  response.get_header(resp, "location") |> should.equal(Ok("/new-location"))
}

pub fn with_cors_test() {
  let resp =
    response.ok()
    |> response.with_cors("*", ["GET", "POST", "OPTIONS"])

  response.get_header(resp, "access-control-allow-origin")
  |> should.equal(Ok("*"))
  response.get_header(resp, "access-control-allow-methods")
  |> should.equal(Ok("GET, POST, OPTIONS"))
  response.get_header(resp, "access-control-allow-headers")
  |> should.equal(Ok("Content-Type, Authorization"))
}

pub fn error_response_test() {
  let resp = response.error_response(404, "User not found")

  resp.status |> should.equal(404)
  response.get_content_type(resp)
  |> should.equal(Ok("application/json; charset=utf-8"))

  let assert Ok(body_str) = bit_array.to_string(resp.body)
  body_str |> should_contain("\"error\"")
  body_str |> should_contain("User not found")
  body_str |> should_contain("\"status\"")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accessor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn get_header_not_found_test() {
  let resp = response.ok()

  response.get_header(resp, "x-missing") |> should.equal(Error(Nil))
}

pub fn has_header_true_test() {
  let resp =
    response.ok()
    |> response.with_header("X-Custom", "value")

  response.has_header(resp, "x-custom") |> should.be_true()
}

pub fn has_header_false_test() {
  let resp = response.ok()

  response.has_header(resp, "x-missing") |> should.be_false()
}

pub fn get_content_length_not_present_test() {
  let resp = response.ok()

  response.get_content_length(resp) |> should.equal(Error(Nil))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Status Code Helper Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn default_reason_phrase_test() {
  response.default_reason_phrase(200) |> should.equal("OK")
  response.default_reason_phrase(404) |> should.equal("Not Found")
  response.default_reason_phrase(500) |> should.equal("Internal Server Error")
  response.default_reason_phrase(999) |> should.equal("Unknown")
}

pub fn is_success_test() {
  response.is_success(200) |> should.be_true()
  response.is_success(201) |> should.be_true()
  response.is_success(204) |> should.be_true()
  response.is_success(199) |> should.be_false()
  response.is_success(300) |> should.be_false()
}

pub fn is_redirect_test() {
  response.is_redirect(301) |> should.be_true()
  response.is_redirect(302) |> should.be_true()
  response.is_redirect(307) |> should.be_true()
  response.is_redirect(200) |> should.be_false()
  response.is_redirect(400) |> should.be_false()
}

pub fn is_client_error_test() {
  response.is_client_error(400) |> should.be_true()
  response.is_client_error(404) |> should.be_true()
  response.is_client_error(499) |> should.be_true()
  response.is_client_error(200) |> should.be_false()
  response.is_client_error(500) |> should.be_false()
}

pub fn is_server_error_test() {
  response.is_server_error(500) |> should.be_true()
  response.is_server_error(503) |> should.be_true()
  response.is_server_error(599) |> should.be_true()
  response.is_server_error(200) |> should.be_false()
  response.is_server_error(400) |> should.be_false()
}

pub fn version_to_string_test() {
  response.version_to_string(Http11) |> should.equal("HTTP/1.1")
  response.version_to_string(Http10) |> should.equal("HTTP/1.0")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/list
import gleam/string

fn should_contain(haystack: String, needle: String) {
  string.contains(haystack, needle) |> should.be_true()
}
