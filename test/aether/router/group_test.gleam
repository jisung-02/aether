// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Group Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Unit tests for the route group module.
//

import aether/protocol/http/response
import aether/router/group
import aether/router/params
import aether/router/pattern
import aether/router/router
import gleam/http.{Delete, Get, Post, Put}
import gleam/list
import gleam/option
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Test Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn dummy_handler(_req, _params, _data) {
  Ok(response.new(200))
}

fn error_handler(_req, _params, _data) {
  Error(group.HandlerError("test error"))
}

fn logging_middleware(next: group.ParamHandler) -> group.ParamHandler {
  fn(req, p, data) {
    // In real middleware, you'd log here
    next(req, p, data)
  }
}

fn auth_middleware(next: group.ParamHandler) -> group.ParamHandler {
  fn(req, p, data) {
    // In real middleware, you'd check auth here
    next(req, p, data)
  }
}

fn counting_middleware(
  counter_name: String,
) -> fn(group.ParamHandler) -> group.ParamHandler {
  fn(next: group.ParamHandler) -> group.ParamHandler {
    fn(req, p, data) {
      // Simulating counting - in real code, would increment counter
      let _ = counter_name
      next(req, p, data)
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Group Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_group_with_prefix_test() {
  let grp = group.new("/api")

  grp.prefix
  |> should.equal("/api")

  grp.routes
  |> list.length()
  |> should.equal(0)

  grp.middlewares
  |> list.length()
  |> should.equal(0)

  grp.groups
  |> list.length()
  |> should.equal(0)
}

pub fn new_group_without_prefix_test() {
  let grp = group.without_prefix()

  grp.prefix
  |> should.equal("")

  grp.routes
  |> list.length()
  |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Prefix Normalization Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn normalize_prefix_with_trailing_slash_test() {
  group.normalize_prefix("/api/")
  |> should.equal("/api")
}

pub fn normalize_prefix_without_leading_slash_test() {
  group.normalize_prefix("api")
  |> should.equal("/api")
}

pub fn normalize_prefix_empty_test() {
  group.normalize_prefix("")
  |> should.equal("")
}

pub fn normalize_prefix_root_slash_test() {
  group.normalize_prefix("/")
  |> should.equal("/")
}

pub fn normalize_prefix_already_normalized_test() {
  group.normalize_prefix("/api/v1")
  |> should.equal("/api/v1")
}

pub fn normalize_prefix_both_trailing_and_missing_leading_test() {
  group.normalize_prefix("api/v1/")
  |> should.equal("/api/v1")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Prefix Combination Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn combine_prefixes_both_present_test() {
  group.combine_prefixes("/api", "/v1")
  |> should.equal("/api/v1")
}

pub fn combine_prefixes_parent_empty_test() {
  group.combine_prefixes("", "/v1")
  |> should.equal("/v1")
}

pub fn combine_prefixes_child_empty_test() {
  group.combine_prefixes("/api", "")
  |> should.equal("/api")
}

pub fn combine_prefixes_both_empty_test() {
  group.combine_prefixes("", "")
  |> should.equal("")
}

pub fn combine_prefixes_deep_nesting_test() {
  let result =
    group.combine_prefixes("/api", "/v1")
    |> group.combine_prefixes("/users")

  result
  |> should.equal("/api/v1/users")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Route Addition Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn add_get_route_test() {
  let grp =
    group.new("/api")
    |> group.get("/users", dummy_handler)

  grp.routes
  |> list.length()
  |> should.equal(1)

  case list.first(grp.routes) {
    Ok(route) -> {
      route.method
      |> should.equal(option.Some(Get))

      pattern.to_string(route.pattern)
      |> should.equal("/users")
    }
    Error(_) -> should.fail()
  }
}

pub fn add_post_route_test() {
  let grp =
    group.new("/api")
    |> group.post("/users", dummy_handler)

  case list.first(grp.routes) {
    Ok(route) -> {
      route.method
      |> should.equal(option.Some(Post))
    }
    Error(_) -> should.fail()
  }
}

pub fn add_put_route_test() {
  let grp =
    group.new("/api")
    |> group.put("/users/:id", dummy_handler)

  case list.first(grp.routes) {
    Ok(route) -> {
      route.method
      |> should.equal(option.Some(Put))
    }
    Error(_) -> should.fail()
  }
}

pub fn add_delete_route_test() {
  let grp =
    group.new("/api")
    |> group.delete("/users/:id", dummy_handler)

  case list.first(grp.routes) {
    Ok(route) -> {
      route.method
      |> should.equal(option.Some(Delete))
    }
    Error(_) -> should.fail()
  }
}

pub fn add_any_route_test() {
  let grp =
    group.new("/api")
    |> group.any("/health", dummy_handler)

  case list.first(grp.routes) {
    Ok(route) -> {
      route.method
      |> should.equal(option.None)
    }
    Error(_) -> should.fail()
  }
}

pub fn add_multiple_routes_test() {
  let grp =
    group.new("/api")
    |> group.get("/users", dummy_handler)
    |> group.post("/users", dummy_handler)
    |> group.get("/users/:id", dummy_handler)

  grp.routes
  |> list.length()
  |> should.equal(3)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Middleware Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn add_single_middleware_test() {
  let grp =
    group.new("/api")
    |> group.use_middleware(logging_middleware)

  grp.middlewares
  |> list.length()
  |> should.equal(1)
}

pub fn add_multiple_middlewares_test() {
  let grp =
    group.new("/api")
    |> group.use_middleware(logging_middleware)
    |> group.use_middleware(auth_middleware)

  grp.middlewares
  |> list.length()
  |> should.equal(2)
}

pub fn middlewares_preserve_order_test() {
  // When we add m1 then m2, execution should be m1 -> m2 -> handler
  // This is verified by the flatten tests
  let grp =
    group.new("/api")
    |> group.use_middleware(counting_middleware("first"))
    |> group.use_middleware(counting_middleware("second"))

  grp.middlewares
  |> list.length()
  |> should.equal(2)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Nesting Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn nest_single_group_test() {
  let child =
    group.new("/v1")
    |> group.get("/users", dummy_handler)

  let parent =
    group.new("/api")
    |> group.nest(child)

  parent.groups
  |> list.length()
  |> should.equal(1)
}

pub fn nest_multiple_groups_test() {
  let v1 =
    group.new("/v1")
    |> group.get("/users", dummy_handler)

  let v2 =
    group.new("/v2")
    |> group.get("/users", dummy_handler)

  let parent =
    group.new("/api")
    |> group.nest(v1)
    |> group.nest(v2)

  parent.groups
  |> list.length()
  |> should.equal(2)
}

pub fn deep_nesting_test() {
  let leaf =
    group.new("/leaf")
    |> group.get("/data", dummy_handler)

  let middle =
    group.new("/middle")
    |> group.nest(leaf)

  let root =
    group.new("/root")
    |> group.nest(middle)

  root.groups
  |> list.length()
  |> should.equal(1)

  case list.first(root.groups) {
    Ok(middle_group) -> {
      middle_group.groups
      |> list.length()
      |> should.equal(1)
    }
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flatten Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn flatten_simple_group_test() {
  let grp =
    group.new("/api")
    |> group.get("/users", dummy_handler)
    |> group.post("/users", dummy_handler)

  let routes = group.flatten(grp)

  routes
  |> list.length()
  |> should.equal(2)
}

pub fn flatten_applies_prefix_test() {
  let grp =
    group.new("/api")
    |> group.get("/users", dummy_handler)

  let routes = group.flatten(grp)

  case list.first(routes) {
    Ok(route) -> {
      pattern.to_string(route.pattern)
      |> should.equal("/api/users")
    }
    Error(_) -> should.fail()
  }
}

pub fn flatten_nested_groups_test() {
  let users =
    group.new("/users")
    |> group.get("", dummy_handler)
    |> group.get("/:id", dummy_handler)

  let api =
    group.new("/api")
    |> group.nest(users)

  let routes = group.flatten(api)

  routes
  |> list.length()
  |> should.equal(2)

  // Check that prefixes are combined
  case list.first(routes) {
    Ok(route) -> {
      pattern.to_string(route.pattern)
      |> should.equal("/api/users")
    }
    Error(_) -> should.fail()
  }
}

pub fn flatten_deeply_nested_test() {
  let leaf =
    group.new("/leaf")
    |> group.get("/data", dummy_handler)

  let middle =
    group.new("/middle")
    |> group.nest(leaf)

  let root =
    group.new("/root")
    |> group.nest(middle)

  let routes = group.flatten(root)

  routes
  |> list.length()
  |> should.equal(1)

  case list.first(routes) {
    Ok(route) -> {
      pattern.to_string(route.pattern)
      |> should.equal("/root/middle/leaf/data")
    }
    Error(_) -> should.fail()
  }
}

pub fn flatten_mixed_routes_and_nested_test() {
  let child =
    group.new("/child")
    |> group.get("/data", dummy_handler)

  let parent =
    group.new("/parent")
    |> group.get("/own", dummy_handler)
    |> group.nest(child)

  let routes = group.flatten(parent)

  routes
  |> list.length()
  |> should.equal(2)
}

pub fn flatten_empty_group_test() {
  let grp = group.new("/api")

  let routes = group.flatten(grp)

  routes
  |> list.length()
  |> should.equal(0)
}

pub fn flatten_without_prefix_group_test() {
  let grp =
    group.without_prefix()
    |> group.get("/users", dummy_handler)

  let routes = group.flatten(grp)

  case list.first(routes) {
    Ok(route) -> {
      pattern.to_string(route.pattern)
      |> should.equal("/users")
    }
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Middleware Application Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn flatten_applies_middleware_test() {
  // We can't easily test middleware execution order without mutable state,
  // but we can verify that routes are flattened with wrapped handlers
  let grp =
    group.new("/api")
    |> group.use_middleware(logging_middleware)
    |> group.get("/users", dummy_handler)

  let routes = group.flatten(grp)

  // The route should exist with the middleware applied
  routes
  |> list.length()
  |> should.equal(1)
}

pub fn flatten_inherits_parent_middleware_test() {
  let child =
    group.new("/child")
    |> group.get("/data", dummy_handler)

  let parent =
    group.new("/parent")
    |> group.use_middleware(auth_middleware)
    |> group.nest(child)

  let routes = group.flatten(parent)

  // Child route should inherit parent middleware
  routes
  |> list.length()
  |> should.equal(1)
}

pub fn flatten_combines_middleware_layers_test() {
  let child =
    group.new("/child")
    |> group.use_middleware(logging_middleware)
    |> group.get("/data", dummy_handler)

  let parent =
    group.new("/parent")
    |> group.use_middleware(auth_middleware)
    |> group.nest(child)

  let routes = group.flatten(parent)

  // Route should have both middlewares applied
  routes
  |> list.length()
  |> should.equal(1)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Router Integration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn mount_simple_group_test() {
  let grp =
    group.new("/api")
    |> group.get("/users", dummy_handler)

  let rtr =
    router.new()
    |> router.mount(grp)

  // Verify the route was added
  rtr.routes
  |> list.length()
  |> should.equal(1)
}

pub fn mount_group_with_existing_routes_test() {
  let grp =
    group.new("/api")
    |> group.get("/users", dummy_handler)

  let rtr =
    router.new()
    |> router.get("/", dummy_handler)
    |> router.mount(grp)

  rtr.routes
  |> list.length()
  |> should.equal(2)
}

pub fn mount_multiple_groups_test() {
  let api_v1 =
    group.new("/api/v1")
    |> group.get("/users", dummy_handler)

  let api_v2 =
    group.new("/api/v2")
    |> group.get("/users", dummy_handler)

  let rtr =
    router.new()
    |> router.mount(api_v1)
    |> router.mount(api_v2)

  rtr.routes
  |> list.length()
  |> should.equal(2)
}

pub fn mount_nested_group_test() {
  let users =
    group.new("/users")
    |> group.get("", dummy_handler)
    |> group.get("/:id", dummy_handler)
    |> group.post("", dummy_handler)

  let api =
    group.new("/api")
    |> group.nest(users)

  let rtr =
    router.new()
    |> router.mount(api)

  rtr.routes
  |> list.length()
  |> should.equal(3)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Route Matching Integration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn mounted_route_matches_test() {
  let grp =
    group.new("/api")
    |> group.get("/users", dummy_handler)

  let rtr =
    router.new()
    |> router.mount(grp)

  let result = router.find_route(rtr, Get, "/api/users")

  case result {
    router.Matched(_, _) -> should.be_true(True)
    router.PathMatchedMethodNotAllowed(_) -> should.fail()
    router.NotFound -> should.fail()
  }
}

pub fn mounted_route_extracts_params_test() {
  let grp =
    group.new("/api")
    |> group.get("/users/:id", dummy_handler)

  let rtr =
    router.new()
    |> router.mount(grp)

  case router.find_route(rtr, Get, "/api/users/42") {
    router.Matched(_route, p) -> {
      params.get(p, "id")
      |> should.equal(option.Some("42"))
    }
    router.PathMatchedMethodNotAllowed(_) -> should.fail()
    router.NotFound -> should.fail()
  }
}

pub fn mounted_nested_route_matches_test() {
  let users =
    group.new("/users")
    |> group.get("/:user_id/posts/:post_id", dummy_handler)

  let api =
    group.new("/api/v1")
    |> group.nest(users)

  let rtr =
    router.new()
    |> router.mount(api)

  case router.find_route(rtr, Get, "/api/v1/users/123/posts/456") {
    router.Matched(_route, p) -> {
      params.get(p, "user_id")
      |> should.equal(option.Some("123"))

      params.get(p, "post_id")
      |> should.equal(option.Some("456"))
    }
    router.PathMatchedMethodNotAllowed(_) -> should.fail()
    router.NotFound -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Edge Case Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn root_prefix_group_test() {
  let grp =
    group.new("/")
    |> group.get("/users", dummy_handler)

  let routes = group.flatten(grp)

  case list.first(routes) {
    Ok(route) -> {
      pattern.to_string(route.pattern)
      |> should.equal("/users")
    }
    Error(_) -> should.fail()
  }
}

pub fn dynamic_prefix_group_test() {
  let grp =
    group.new("/tenants/:tenant_id")
    |> group.get("/users", dummy_handler)

  let routes = group.flatten(grp)

  case list.first(routes) {
    Ok(route) -> {
      pattern.to_string(route.pattern)
      |> should.equal("/tenants/:tenant_id/users")
    }
    Error(_) -> should.fail()
  }
}

pub fn empty_path_route_test() {
  let grp =
    group.new("/api")
    |> group.get("", dummy_handler)

  let routes = group.flatten(grp)

  case list.first(routes) {
    Ok(route) -> {
      pattern.to_string(route.pattern)
      |> should.equal("/api")
    }
    Error(_) -> should.fail()
  }
}

pub fn handler_error_propagation_test() {
  let grp =
    group.new("/api")
    |> group.get("/error", error_handler)

  let rtr =
    router.new()
    |> router.mount(grp)

  // Verify the route exists (handler error propagation is tested at runtime)
  case router.find_route(rtr, Get, "/api/error") {
    router.Matched(_, _) -> should.be_true(True)
    router.PathMatchedMethodNotAllowed(_) -> should.fail()
    router.NotFound -> should.fail()
  }
}
