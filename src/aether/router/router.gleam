// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Router Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides HTTP routing with static path matching and method-based filtering.
// Integrates with the Aether pipeline system as a Stage.
//
// ## Features
//
// - Static path matching (exact string match)
// - HTTP method filtering (GET, POST, PUT, DELETE, PATCH, etc.)
// - Custom 404 Not Found handlers
// - 405 Method Not Allowed with Allow header
// - Pipeline stage integration
//
// ## Usage
//
// ```gleam
// let router = router.new()
//   |> router.get("/", home_handler)
//   |> router.get("/users", list_users)
//   |> router.post("/users", create_user)
//   |> router.not_found(custom_404)
//
// let stage = router.to_stage(router)
// ```
//

import aether/core/data.{type Data}
import aether/pipeline/error.{type StageError, ProcessingError}
import aether/pipeline/stage.{type Stage}
import aether/protocol/http/request.{type ParsedRequest}
import aether/protocol/http/response.{type HttpResponse}
import aether/protocol/http/stage as http_stage
import gleam/http.{type Method}
import gleam/list
import gleam/option.{type Option}
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Error type for route handling
///
/// ## Variants
///
/// - `HandlerError`: Error from a route handler with message
/// - `InternalError`: Internal routing error
///
pub type RouteError {
  HandlerError(message: String)
  InternalError(message: String)
}

/// Handler function type
///
/// A handler receives the parsed request and pipeline data,
/// returning either an HttpResponse or a RouteError.
///
pub type Handler =
  fn(ParsedRequest, Data) -> Result(HttpResponse, RouteError)

/// A single route definition
///
/// ## Fields
///
/// - `method`: Optional HTTP method filter (None matches any method)
/// - `path`: The path to match (exact string match)
/// - `handler`: The handler function to execute
///
pub type Route {
  Route(method: Option(Method), path: String, handler: Handler)
}

/// Result of route matching
///
/// ## Variants
///
/// - `Matched`: Route matched with the matching route
/// - `PathMatchedMethodNotAllowed`: Path matched but method didn't
/// - `NotFound`: No route matched the path
///
pub type MatchResult {
  Matched(route: Route)
  PathMatchedMethodNotAllowed(allowed_methods: List(Method))
  NotFound
}

/// HTTP Router holding routes and fallback handlers
///
/// ## Fields
///
/// - `routes`: List of registered routes (checked in order)
/// - `not_found_handler`: Optional custom 404 handler
///
pub type Router {
  Router(routes: List(Route), not_found_handler: Option(Handler))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Router Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new empty router
///
/// ## Returns
///
/// A new Router with no routes and default 404 handler
///
/// ## Examples
///
/// ```gleam
/// let router = router.new()
/// ```
///
pub fn new() -> Router {
  Router(routes: [], not_found_handler: option.None)
}

/// Adds a route with a specific HTTP method
///
/// ## Parameters
///
/// - `router`: The router to add the route to
/// - `method`: The HTTP method to match
/// - `path`: The path to match (exact match)
/// - `handler`: The handler function
///
/// ## Returns
///
/// The updated router with the new route appended
///
pub fn route(
  router: Router,
  method: Method,
  path: String,
  handler: Handler,
) -> Router {
  let new_route = Route(method: option.Some(method), path: path, handler: handler)
  Router(..router, routes: list.append(router.routes, [new_route]))
}

/// Adds a GET route
///
/// ## Parameters
///
/// - `router`: The router to add the route to
/// - `path`: The path to match
/// - `handler`: The handler function
///
/// ## Returns
///
/// The updated router
///
/// ## Examples
///
/// ```gleam
/// let router = router.new()
///   |> router.get("/", home_handler)
/// ```
///
pub fn get(router: Router, path: String, handler: Handler) -> Router {
  route(router, http.Get, path, handler)
}

/// Adds a POST route
///
pub fn post(router: Router, path: String, handler: Handler) -> Router {
  route(router, http.Post, path, handler)
}

/// Adds a PUT route
///
pub fn put(router: Router, path: String, handler: Handler) -> Router {
  route(router, http.Put, path, handler)
}

/// Adds a DELETE route
///
pub fn delete(router: Router, path: String, handler: Handler) -> Router {
  route(router, http.Delete, path, handler)
}

/// Adds a PATCH route
///
pub fn patch(router: Router, path: String, handler: Handler) -> Router {
  route(router, http.Patch, path, handler)
}

/// Adds a HEAD route
///
pub fn head(router: Router, path: String, handler: Handler) -> Router {
  route(router, http.Head, path, handler)
}

/// Adds an OPTIONS route
///
pub fn options(router: Router, path: String, handler: Handler) -> Router {
  route(router, http.Options, path, handler)
}

/// Adds a route that matches any HTTP method
///
/// ## Parameters
///
/// - `router`: The router to add the route to
/// - `path`: The path to match
/// - `handler`: The handler function
///
/// ## Returns
///
/// The updated router with the new route
///
/// ## Examples
///
/// ```gleam
/// let router = router.new()
///   |> router.any("/health", health_handler)
/// ```
///
pub fn any(router: Router, path: String, handler: Handler) -> Router {
  let new_route = Route(method: option.None, path: path, handler: handler)
  Router(..router, routes: list.append(router.routes, [new_route]))
}

/// Sets a custom 404 Not Found handler
///
/// ## Parameters
///
/// - `router`: The router to configure
/// - `handler`: The custom 404 handler
///
/// ## Returns
///
/// The updated router with custom 404 handler
///
/// ## Examples
///
/// ```gleam
/// let router = router.new()
///   |> router.not_found(fn(req, data) {
///     Ok(response.not_found()
///       |> response.json()
///       |> response.with_string_body("{\"error\": \"Not Found\"}"))
///   })
/// ```
///
pub fn not_found(router: Router, handler: Handler) -> Router {
  Router(..router, not_found_handler: option.Some(handler))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Route Matching Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks if a route's path matches the request path
///
/// Uses exact string matching on paths.
///
fn matches_path(route: Route, request_path: String) -> Bool {
  route.path == request_path
}

/// Checks if a route's method matches the request method
///
/// Returns True if route has no method filter (matches any)
/// or if the methods match exactly.
///
fn matches_method(route: Route, request_method: Method) -> Bool {
  case route.method {
    option.None -> True
    option.Some(route_method) -> route_method == request_method
  }
}

/// Gets all HTTP methods allowed for a given path
///
/// ## Parameters
///
/// - `router`: The router to check
/// - `path`: The path to find allowed methods for
///
/// ## Returns
///
/// List of HTTP methods that have routes for this path
///
pub fn get_allowed_methods(router: Router, path: String) -> List(Method) {
  router.routes
  |> list.filter(fn(r) { matches_path(r, path) })
  |> list.filter_map(fn(r) { r.method |> option.to_result(Nil) })
}

/// Finds a matching route for a request
///
/// ## Parameters
///
/// - `router`: The router to search
/// - `method`: The request HTTP method
/// - `path`: The request path
///
/// ## Returns
///
/// A MatchResult indicating the result of route matching
///
/// ## Examples
///
/// ```gleam
/// case find_route(router, http.Get, "/users") {
///   Matched(route) -> // Execute handler
///   PathMatchedMethodNotAllowed(allowed) -> // Return 405
///   NotFound -> // Return 404
/// }
/// ```
///
pub fn find_route(router: Router, method: Method, path: String) -> MatchResult {
  // First, find routes that match the path
  let path_matches =
    router.routes
    |> list.filter(fn(r) { matches_path(r, path) })

  case list.is_empty(path_matches) {
    True -> NotFound
    False -> {
      // Find a route that also matches the method
      let method_match =
        path_matches
        |> list.find(fn(r) { matches_method(r, method) })

      case method_match {
        Ok(matched_route) -> Matched(matched_route)
        Error(_) -> {
          // Path matched but method didn't
          let allowed = get_allowed_methods(router, path)
          PathMatchedMethodNotAllowed(allowed)
        }
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Dispatch Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a RouteError to a StageError
///
fn route_error_to_stage_error(error: RouteError) -> StageError {
  case error {
    HandlerError(message) -> ProcessingError(message, option.None)
    InternalError(message) ->
      ProcessingError("Internal: " <> message, option.None)
  }
}

/// Formats allowed methods for Allow header
///
fn format_allowed_methods(methods: List(Method)) -> String {
  methods
  |> list.map(request.method_to_string)
  |> string.join(", ")
}

/// Default 404 handler
///
fn default_not_found_handler(
  _request: ParsedRequest,
  _data: Data,
) -> Result(HttpResponse, RouteError) {
  Ok(
    response.not_found()
    |> response.text()
    |> response.with_string_body("Not Found"),
  )
}

/// Default 405 handler with Allow header
///
fn default_method_not_allowed_handler(allowed_methods: List(Method)) -> HttpResponse {
  response.method_not_allowed()
  |> response.text()
  |> response.with_header("allow", format_allowed_methods(allowed_methods))
  |> response.with_string_body("Method Not Allowed")
}

/// Dispatches a request to the appropriate handler
///
/// ## Parameters
///
/// - `router`: The router with registered routes
/// - `req`: The parsed HTTP request
/// - `data`: The pipeline Data
///
/// ## Returns
///
/// Result containing the HttpResponse or a RouteError
///
/// ## Examples
///
/// ```gleam
/// case dispatch(router, request, data) {
///   Ok(response) -> // Send response
///   Error(HandlerError(msg)) -> // Handle error
/// }
/// ```
///
pub fn dispatch(
  router: Router,
  req: ParsedRequest,
  data: Data,
) -> Result(HttpResponse, RouteError) {
  let path = request.path(req)
  let method = req.method

  case find_route(router, method, path) {
    Matched(matched_route) -> matched_route.handler(req, data)
    PathMatchedMethodNotAllowed(allowed_methods) ->
      Ok(default_method_not_allowed_handler(allowed_methods))
    NotFound -> {
      case router.not_found_handler {
        option.Some(handler) -> handler(req, data)
        option.None -> default_not_found_handler(req, data)
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Stage Integration
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a pipeline stage from a router
///
/// This stage extracts the ParsedRequest from the Data metadata,
/// dispatches to the appropriate handler, and sets the response
/// in the Data metadata for subsequent stages.
///
/// ## Parameters
///
/// - `router`: The configured router
///
/// ## Returns
///
/// A Stage(Data, Data) that can be composed into a pipeline
///
/// ## Examples
///
/// ```gleam
/// let my_router = router.new()
///   |> router.get("/", home_handler)
///   |> router.post("/api/users", create_user)
///
/// let pipeline = pipeline.new()
///   |> pipeline.pipe(http_stage.decode())
///   |> pipeline.pipe(router.to_stage(my_router))
///   |> pipeline.pipe(http_stage.encode_response())
/// ```
///
pub fn to_stage(router: Router) -> Stage(Data, Data) {
  stage.new("router", fn(data: Data) {
    case http_stage.get_parsed_request(data) {
      option.Some(req) -> {
        case dispatch(router, req, data) {
          Ok(resp) -> Ok(http_stage.create_response_for_request(data, resp))
          Error(route_error) -> Error(route_error_to_stage_error(route_error))
        }
      }
      option.None ->
        Error(ProcessingError("No HTTP request in metadata", option.None))
    }
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the number of routes in the router
///
pub fn route_count(router: Router) -> Int {
  list.length(router.routes)
}

/// Checks if the router has any routes
///
pub fn is_empty(router: Router) -> Bool {
  list.is_empty(router.routes)
}

/// Gets all registered paths in the router
///
pub fn get_paths(router: Router) -> List(String) {
  router.routes
  |> list.map(fn(r) { r.path })
  |> list.unique()
}
