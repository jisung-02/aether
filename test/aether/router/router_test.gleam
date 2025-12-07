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
import aether/router/params
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
  _params: params.Params,
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
) -> fn(request.ParsedRequest, params.Params, message.Message) ->
  Result(response.HttpResponse, router.RouteError) {
  fn(_req, _params, _data) {
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
  _params: params.Params,
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
    router.Matched(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn find_route_method_match_test() {
  let r =
    router.new()
    |> router.post("/test", ok_handler)

  case router.find_route(r, http.Post, "/test") {
    router.Matched(_, _) -> should.be_true(True)
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
    router.Matched(_, _) -> should.be_true(True)
    _ -> should.fail()
  }

  // Should match POST
  case router.find_route(r, http.Post, "/any") {
    router.Matched(_, _) -> should.be_true(True)
    _ -> should.fail()
  }

  // Should match DELETE
  case router.find_route(r, http.Delete, "/any") {
    router.Matched(_, _) -> should.be_true(True)
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
// Dynamic Route Matching Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn find_route_dynamic_pattern_test() {
  let r =
    router.new()
    |> router.get("/users/:id", ok_handler)

  case router.find_route(r, http.Get, "/users/123") {
    router.Matched(_, p) -> {
      params.get(p, "id")
      |> should.equal(option.Some("123"))
    }
    _ -> should.fail()
  }
}

pub fn find_route_multiple_dynamic_params_test() {
  let r =
    router.new()
    |> router.get("/users/:user_id/posts/:post_id", ok_handler)

  case router.find_route(r, http.Get, "/users/42/posts/7") {
    router.Matched(_, p) -> {
      params.get(p, "user_id")
      |> should.equal(option.Some("42"))

      params.get(p, "post_id")
      |> should.equal(option.Some("7"))
    }
    _ -> should.fail()
  }
}

pub fn find_route_wildcard_pattern_test() {
  let r =
    router.new()
    |> router.get("/files/*", ok_handler)

  case router.find_route(r, http.Get, "/files/docs/readme.txt") {
    router.Matched(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn find_route_static_over_dynamic_priority_test() {
  // Static routes should be checked first due to insertion order
  let r =
    router.new()
    |> router.get("/users/list", body_handler("static"))
    |> router.get("/users/:id", body_handler("dynamic"))

  // /users/list should match static route
  case router.find_route(r, http.Get, "/users/list") {
    router.Matched(_, _) -> should.be_true(True)
    _ -> should.fail()
  }

  // /users/123 should match dynamic route
  case router.find_route(r, http.Get, "/users/123") {
    router.Matched(_, p) -> {
      params.get(p, "id")
      |> should.equal(option.Some("123"))
    }
    _ -> should.fail()
  }
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
  let custom_404 = fn(_req, _params, _data) {
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
// Dynamic Dispatch Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn dispatch_dynamic_route_with_param_test() {
  // Handler that uses path parameters
  let user_handler = fn(_req, p, _data) {
    case params.get(p, "id") {
      option.Some(id) ->
        Ok(
          response.ok()
          |> response.text()
          |> response.with_string_body("User: " <> id),
        )
      option.None ->
        Ok(
          response.bad_request()
          |> response.text()
          |> response.with_string_body("Missing id"),
        )
    }
  }

  let r =
    router.new()
    |> router.get("/users/:id", user_handler)

  let req = test_request(http.Get, "/users/42")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(200)
    }
    Error(_) -> should.fail()
  }
}

pub fn dispatch_dynamic_route_with_int_param_test() {
  // Handler that uses integer path parameters
  let user_handler = fn(_req, p, _data) {
    case params.get_int(p, "id") {
      option.Some(id) ->
        Ok(
          response.ok()
          |> response.text()
          |> response.with_string_body("User ID: " <> string.inspect(id)),
        )
      option.None ->
        Ok(
          response.bad_request()
          |> response.text()
          |> response.with_string_body("Invalid id"),
        )
    }
  }

  let r =
    router.new()
    |> router.get("/users/:id", user_handler)

  let req = test_request(http.Get, "/users/123")
  let data = test_data()

  case router.dispatch(r, req, data) {
    Ok(resp) -> {
      resp.status
      |> should.equal(200)
    }
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Handler Adapter Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn adapt_handler_test() {
  // Old-style handler without params
  let old_handler = fn(_req: request.ParsedRequest, _data: message.Message) {
    Ok(
      response.ok()
      |> response.text()
      |> response.with_string_body("Adapted"),
    )
  }

  // Adapt it to new ParamHandler type
  let adapted = router.adapt_handler(old_handler)

  let r =
    router.new()
    |> router.get("/test", adapted)

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

pub fn to_stage_dynamic_route_test() {
  let user_handler = fn(_req, p, _data) {
    case params.get(p, "id") {
      option.Some(_) ->
        Ok(
          response.ok()
          |> response.text()
          |> response.with_string_body("Found user"),
        )
      option.None ->
        Ok(
          response.bad_request()
          |> response.text()
          |> response.with_string_body("Missing id"),
        )
    }
  }

  let r =
    router.new()
    |> router.get("/users/:id", user_handler)

  let router_stage = router.to_stage(r)

  let req = test_request(http.Get, "/users/42")
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
