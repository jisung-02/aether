// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Router Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Comprehensive tests for the HTTP router module.
//

import aether/core/message
import aether/pipeline/stage
import aether/protocol/http/request
import aether/protocol/http/response
import aether/protocol/http/stage as http_stage
import aether/router/router
import gleam/http
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Test Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a simple OK handler for testing
fn ok_handler(
  _req: request.ParsedRequest,
  _data: message.Message,
) -> Result(response.HttpResponse, router.RouteError) {
  Ok(
    response.ok()
    |> response.text()
    |> response.with_string_body("OK"),
  )
}

/// Creates a handler that returns a specific body
fn body_handler(
  body: String,
) -> fn(request.ParsedRequest, message.Message) ->
  Result(response.HttpResponse, router.RouteError) {
  fn(_req, _data) {
    Ok(
      response.ok()
      |> response.text()
      |> response.with_string_body(body),
    )
  }
}

/// Creates a handler that returns an error
fn error_handler(
  _req: request.ParsedRequest,
  _data: message.Message,
) -> Result(response.HttpResponse, router.RouteError) {
  Error(router.HandlerError("Handler failed"))
}

/// Creates a test ParsedRequest
fn test_request(method: http.Method, uri: String) -> request.ParsedRequest {
  request.ParsedRequest(
    method: method,
    uri: uri,
    version: request.Http11,
    headers: [],
    body: <<>>,
  )
}

/// Creates test Data
fn test_data() -> message.Message {
  message.new(<<>>)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Router Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_router_empty_test() {
  let r = router.new()

  router.route_count(r)
  |> should.equal(0)

  router.is_empty(r)
  |> should.be_true()
}

pub fn add_get_route_test() {
  let r =
    router.new()
    |> router.get("/test", ok_handler)

  router.route_count(r)
  |> should.equal(1)

  router.is_empty(r)
  |> should.be_false()
}

pub fn add_post_route_test() {
  let r =
    router.new()
    |> router.post("/test", ok_handler)

  router.route_count(r)
  |> should.equal(1)
}

pub fn add_put_route_test() {
  let r =
    router.new()
    |> router.put("/test", ok_handler)

  router.route_count(r)
  |> should.equal(1)
}

pub fn add_delete_route_test() {
  let r =
    router.new()
    |> router.delete("/test", ok_handler)

  router.route_count(r)
  |> should.equal(1)
}

pub fn add_patch_route_test() {
  let r =
    router.new()
    |> router.patch("/test", ok_handler)

  router.route_count(r)
  |> should.equal(1)
}

pub fn add_head_route_test() {
  let r =
    router.new()
    |> router.head("/test", ok_handler)

  router.route_count(r)
  |> should.equal(1)
}

pub fn add_options_route_test() {
  let r =
    router.new()
    |> router.options("/test", ok_handler)

  router.route_count(r)
  |> should.equal(1)
}

pub fn add_any_route_test() {
  let r =
    router.new()
    |> router.any("/test", ok_handler)

  router.route_count(r)
  |> should.equal(1)
}

pub fn add_multiple_routes_test() {
  let r =
    router.new()
    |> router.get("/", ok_handler)
    |> router.get("/users", ok_handler)
    |> router.post("/users", ok_handler)
    |> router.delete("/users/:id", ok_handler)

  router.route_count(r)
  |> should.equal(4)
}

pub fn get_paths_test() {
  let r =
    router.new()
    |> router.get("/", ok_handler)
    |> router.get("/users", ok_handler)
    |> router.post("/users", ok_handler)

  let paths = router.get_paths(r)

  list.contains(paths, "/")
  |> should.be_true()

  list.contains(paths, "/users")
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Route Matching Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn find_route_exact_path_match_test() {
  let r =
    router.new()
    |> router.get("/test", ok_handler)

  case router.find_route(r, http.Get, "/test") {
    router.Matched(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn find_route_method_match_test() {
  let r =
    router.new()
    |> router.post("/test", ok_handler)

  case router.find_route(r, http.Post, "/test") {
    router.Matched(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn find_route_not_found_test() {
  let r =
    router.new()
    |> router.get("/exists", ok_handler)

  case router.find_route(r, http.Get, "/not-exists") {
    router.NotFound -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn find_route_method_not_allowed_test() {
  let r =
    router.new()
    |> router.get("/test", ok_handler)

  case router.find_route(r, http.Post, "/test") {
    router.PathMatchedMethodNotAllowed(allowed) -> {
      list.contains(allowed, http.Get)
      |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn find_route_any_method_test() {
  let r =
    router.new()
    |> router.any("/any", ok_handler)

  // Should match GET
  case router.find_route(r, http.Get, "/any") {
    router.Matched(_) -> should.be_true(True)
    _ -> should.fail()
  }

  // Should match POST
  case router.find_route(r, http.Post, "/any") {
    router.Matched(_) -> should.be_true(True)
    _ -> should.fail()
  }

  // Should match DELETE
  case router.find_route(r, http.Delete, "/any") {
    router.Matched(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn get_allowed_methods_test() {
  let r =
    router.new()
    |> router.get("/test", ok_handler)
    |> router.post("/test", ok_handler)
    |> router.put("/test", ok_handler)

  let allowed = router.get_allowed_methods(r, "/test")

  list.length(allowed)
  |> should.equal(3)

  list.contains(allowed, http.Get)
  |> should.be_true()

  list.contains(allowed, http.Post)
  |> should.be_true()

  list.contains(allowed, http.Put)
  |> should.be_true()
}

pub fn get_allowed_methods_empty_test() {
  let r = router.new()

  let allowed = router.get_allowed_methods(r, "/test")

  list.length(allowed)
  |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Dispatch Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn dispatch_matched_route_test() {
  let r =
    router.new()
    |> router.get("/test", body_handler("Hello"))

  let req = test_request(http.Get, "/test")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(200)
    }
    Error(_) -> should.fail()
  }
}

pub fn dispatch_not_found_default_test() {
  let r =
    router.new()
    |> router.get("/exists", ok_handler)

  let req = test_request(http.Get, "/not-exists")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(404)
    }
    Error(_) -> should.fail()
  }
}

pub fn dispatch_not_found_custom_test() {
  let custom_404 = fn(_req, _data) {
    Ok(
      response.not_found()
      |> response.json()
      |> response.with_string_body("{\"error\": \"Custom 404\"}"),
    )
  }

  let r =
    router.new()
    |> router.get("/exists", ok_handler)
    |> router.not_found(custom_404)

  let req = test_request(http.Get, "/not-exists")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(404)

      case response.get_content_type(resp) {
        Ok(ct) ->
          string.contains(ct, "application/json")
          |> should.be_true()
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn dispatch_method_not_allowed_test() {
  let r =
    router.new()
    |> router.get("/test", ok_handler)

  let req = test_request(http.Post, "/test")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(405)

      case response.get_header(resp, "allow") {
        Ok(allow) ->
          string.contains(allow, "GET")
          |> should.be_true()
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn dispatch_method_not_allowed_multiple_methods_test() {
  let r =
    router.new()
    |> router.get("/test", ok_handler)
    |> router.post("/test", ok_handler)

  let req = test_request(http.Delete, "/test")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(405)

      case response.get_header(resp, "allow") {
        Ok(allow) -> {
          string.contains(allow, "GET")
          |> should.be_true()

          string.contains(allow, "POST")
          |> should.be_true()
        }
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn dispatch_handler_error_test() {
  let r =
    router.new()
    |> router.get("/error", error_handler)

  let req = test_request(http.Get, "/error")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(_) -> should.fail()
    Error(router.HandlerError(msg)) ->
      string.contains(msg, "Handler failed")
      |> should.be_true()
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Stage Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn to_stage_matched_route_test() {
  let r =
    router.new()
    |> router.get("/test", body_handler("Stage Test"))

  let router_stage = router.to_stage(r)

  // Create data with a parsed request in metadata
  let req = test_request(http.Get, "/test")
  let data =
    test_data()
    |> http_stage.set_request(http_stage.new_request_data(req, <<>>))

  case stage.execute(router_stage, data) {
    Ok(result_data) -> {
      case http_stage.get_response_status(result_data) {
        option.Some(status) ->
          status
          |> should.equal(200)
        option.None -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn to_stage_not_found_test() {
  let r =
    router.new()
    |> router.get("/exists", ok_handler)

  let router_stage = router.to_stage(r)

  let req = test_request(http.Get, "/not-exists")
  let data =
    test_data()
    |> http_stage.set_request(http_stage.new_request_data(req, <<>>))

  case stage.execute(router_stage, data) {
    Ok(result_data) -> {
      case http_stage.get_response_status(result_data) {
        option.Some(status) ->
          status
          |> should.equal(404)
        option.None -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn to_stage_method_not_allowed_test() {
  let r =
    router.new()
    |> router.get("/test", ok_handler)

  let router_stage = router.to_stage(r)

  let req = test_request(http.Post, "/test")
  let data =
    test_data()
    |> http_stage.set_request(http_stage.new_request_data(req, <<>>))

  case stage.execute(router_stage, data) {
    Ok(result_data) -> {
      case http_stage.get_response_status(result_data) {
        option.Some(status) ->
          status
          |> should.equal(405)
        option.None -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn to_stage_no_request_error_test() {
  let r =
    router.new()
    |> router.get("/test", ok_handler)

  let router_stage = router.to_stage(r)

  // Data without HTTP request in metadata
  let data = test_data()

  case stage.execute(router_stage, data) {
    Ok(_) -> should.fail()
    Error(_) -> should.be_true(True)
  }
}

pub fn to_stage_handler_error_test() {
  let r =
    router.new()
    |> router.get("/error", error_handler)

  let router_stage = router.to_stage(r)

  let req = test_request(http.Get, "/error")
  let data =
    test_data()
    |> http_stage.set_request(http_stage.new_request_data(req, <<>>))

  case stage.execute(router_stage, data) {
    Ok(_) -> should.fail()
    Error(_) -> should.be_true(True)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Edge Case Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn path_with_query_string_test() {
  let r =
    router.new()
    |> router.get("/test", ok_handler)

  // Request with query string
  let req = test_request(http.Get, "/test?foo=bar&baz=qux")
  let data = test_data()

  // The path() function should strip query string
  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(200)
    }
    Error(_) -> should.fail()
  }
}

pub fn empty_router_not_found_test() {
  let r = router.new()

  let req = test_request(http.Get, "/anything")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(404)
    }
    Error(_) -> should.fail()
  }
}

pub fn multiple_routes_same_path_test() {
  let r =
    router.new()
    |> router.get("/api", body_handler("GET"))
    |> router.post("/api", body_handler("POST"))
    |> router.put("/api", body_handler("PUT"))

  // GET should work
  let get_req = test_request(http.Get, "/api")
  case router.dispatch(r, get_req, test_data()) {
    Ok(resp) ->
      resp.status
      |> should.equal(200)
    Error(_) -> should.fail()
  }

  // POST should work
  let post_req = test_request(http.Post, "/api")
  case router.dispatch(r, post_req, test_data()) {
    Ok(resp) ->
      resp.status
      |> should.equal(200)
    Error(_) -> should.fail()
  }

  // DELETE should return 405
  let delete_req = test_request(http.Delete, "/api")
  case router.dispatch(r, delete_req, test_data()) {
    Ok(resp) ->
      resp.status
      |> should.equal(405)
    Error(_) -> should.fail()
  }
}

pub fn route_order_priority_test() {
  // First matching route should win
  let r =
    router.new()
    |> router.get("/test", body_handler("First"))
    |> router.get("/test", body_handler("Second"))

  let req = test_request(http.Get, "/test")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(200)
      // First handler should be executed (body would be "First")
    }
    Error(_) -> should.fail()
  }
}

pub fn root_path_test() {
  let r =
    router.new()
    |> router.get("/", body_handler("Root"))

  let req = test_request(http.Get, "/")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(200)
    }
    Error(_) -> should.fail()
  }
}

pub fn trailing_slash_exact_match_test() {
  let r =
    router.new()
    |> router.get("/test", ok_handler)

  // Without trailing slash - should match
  let req1 = test_request(http.Get, "/test")
  case router.dispatch(r, req1, test_data()) {
    Ok(resp) ->
      resp.status
      |> should.equal(200)
    Error(_) -> should.fail()
  }

  // With trailing slash - should NOT match (exact matching)
  let req2 = test_request(http.Get, "/test/")
  case router.dispatch(r, req2, test_data()) {
    Ok(resp) ->
      resp.status
      |> should.equal(404)
    Error(_) -> should.fail()
  }
}
