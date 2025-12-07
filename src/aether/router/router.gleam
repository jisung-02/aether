// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Router Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides HTTP routing with dynamic path matching and method-based filtering.
// Integrates with the Aether pipeline system as a Stage.
//
// ## Features
//
// - Dynamic path matching (`/users/:id`)
// - Wildcard routes (`/files/*`)
// - Query parameter parsing
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
//   |> router.get("/users/:id", get_user)
//   |> router.post("/users", create_user)
//   |> router.get("/files/*", serve_file)
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
import aether/router/params.{type Params}
import aether/router/pattern.{type PathPattern}
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

/// Handler function type (legacy, without params)
///
/// A handler receives the parsed request and pipeline data,
/// returning either an HttpResponse or a RouteError.
///
/// @deprecated Use ParamHandler for new code
///
pub type Handler =
  fn(ParsedRequest, Data) -> Result(HttpResponse, RouteError)

/// Handler function type with params
///
/// A handler receives the parsed request, extracted route parameters,
/// and pipeline data, returning either an HttpResponse or a RouteError.
///
/// ## Example
///
/// ```gleam
/// fn user_handler(req, params, data) {
///   case params.get_int(params, "id") {
///     option.Some(user_id) -> // handle user
///     option.None -> // invalid id
///   }
/// }
/// ```
///
pub type ParamHandler =
  fn(ParsedRequest, Params, Data) -> Result(HttpResponse, RouteError)

/// A single route definition
///
/// ## Fields
///
/// - `method`: Optional HTTP method filter (None matches any method)
/// - `pattern`: The path pattern to match (supports dynamic segments)
/// - `handler`: The handler function to execute
///
pub type Route {
  Route(method: Option(Method), pattern: PathPattern, handler: ParamHandler)
}

/// Result of route matching
///
/// ## Variants
///
/// - `Matched`: Route matched with the matching route and extracted params
/// - `PathMatchedMethodNotAllowed`: Path matched but method didn't
/// - `NotFound`: No route matched the path
///
pub type MatchResult {
  Matched(route: Route, params: Params)
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
  Router(routes: List(Route), not_found_handler: Option(ParamHandler))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Handler Adapter
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Adapts a legacy Handler to a ParamHandler
///
/// Use this to migrate existing handlers that don't use params.
///
/// ## Parameters
///
/// - `handler`: The legacy handler function
///
/// ## Returns
///
/// A ParamHandler that ignores the params argument
///
/// ## Examples
///
/// ```gleam
/// // Legacy handler
/// fn old_handler(req, data) { ... }
///
/// // Use with new router
/// router.new()
///   |> router.get("/", router.adapt_handler(old_handler))
/// ```
///
pub fn adapt_handler(handler: Handler) -> ParamHandler {
  fn(req, _params, data) { handler(req, data) }
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
/// - `path`: The path pattern to match (supports :param and *)
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
  handler: ParamHandler,
) -> Router {
  let pat = pattern.parse(path)
  let new_route = Route(method: option.Some(method), pattern: pat, handler: handler)
  Router(..router, routes: list.append(router.routes, [new_route]))
}

/// Adds a GET route
///
/// ## Parameters
///
/// - `router`: The router to add the route to
/// - `path`: The path pattern to match
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
///   |> router.get("/users/:id", fn(req, params, data) {
///     let user_id = params.get_int(params, "id")
///     // ...
///   })
/// ```
///
pub fn get(router: Router, path: String, handler: ParamHandler) -> Router {
  route(router, http.Get, path, handler)
}

/// Adds a POST route
///
pub fn post(router: Router, path: String, handler: ParamHandler) -> Router {
  route(router, http.Post, path, handler)
}

/// Adds a PUT route
///
pub fn put(router: Router, path: String, handler: ParamHandler) -> Router {
  route(router, http.Put, path, handler)
}

/// Adds a DELETE route
///
pub fn delete(router: Router, path: String, handler: ParamHandler) -> Router {
  route(router, http.Delete, path, handler)
}

/// Adds a PATCH route
///
pub fn patch(router: Router, path: String, handler: ParamHandler) -> Router {
  route(router, http.Patch, path, handler)
}

/// Adds a HEAD route
///
pub fn head(router: Router, path: String, handler: ParamHandler) -> Router {
  route(router, http.Head, path, handler)
}

/// Adds an OPTIONS route
///
pub fn options(router: Router, path: String, handler: ParamHandler) -> Router {
  route(router, http.Options, path, handler)
}

/// Adds a route that matches any HTTP method
///
/// ## Parameters
///
/// - `router`: The router to add the route to
/// - `path`: The path pattern to match
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
///   |> router.any("/health", fn(req, params, data) {
///     Ok(response.ok() |> response.text() |> response.with_string_body("OK"))
///   })
/// ```
///
pub fn any(router: Router, path: String, handler: ParamHandler) -> Router {
  let pat = pattern.parse(path)
  let new_route = Route(method: option.None, pattern: pat, handler: handler)
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
///   |> router.not_found(fn(req, params, data) {
///     Ok(response.not_found()
///       |> response.json()
///       |> response.with_string_body("{\"error\": \"Not Found\"}"))
///   })
/// ```
///
pub fn not_found(router: Router, handler: ParamHandler) -> Router {
  Router(..router, not_found_handler: option.Some(handler))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Route Matching Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

/// Tries to match a route against a path, returning params if matched
///
fn try_match_route(route: Route, path: String) -> Option(Params) {
  pattern.match(route.pattern, path)
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
  |> list.filter(fn(r) { option.is_some(try_match_route(r, path)) })
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
/// case find_route(router, http.Get, "/users/42") {
///   Matched(route, params) -> // Execute handler with params
///   PathMatchedMethodNotAllowed(allowed) -> // Return 405
///   NotFound -> // Return 404
/// }
/// ```
///
pub fn find_route(router: Router, method: Method, path: String) -> MatchResult {
  // Try to find a route that matches both path and method
  let result =
    list.find_map(router.routes, fn(r) {
      case try_match_route(r, path) {
        option.Some(path_params) -> {
          case matches_method(r, method) {
            True -> Ok(#(r, path_params))
            False -> Error(Nil)
          }
        }
        option.None -> Error(Nil)
      }
    })

  case result {
    Ok(#(matched_route, path_params)) -> Matched(matched_route, path_params)
    Error(_) -> {
      // Check if any route matches the path (for 405 response)
      let path_matches =
        router.routes
        |> list.filter(fn(r) { option.is_some(try_match_route(r, path)) })

      case list.is_empty(path_matches) {
        True -> NotFound
        False -> {
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
  _params: Params,
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

/// Parses query parameters from a request and adds them to params
///
fn add_query_params(p: Params, req: ParsedRequest) -> Params {
  case request.query(req) {
    option.Some(query_string) -> {
      let query_params = params.parse_query(query_string)
      params.with_query(p, query_params)
    }
    option.None -> p
  }
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
    Matched(matched_route, path_params) -> {
      // Add query parameters to the params
      let full_params = add_query_params(path_params, req)
      matched_route.handler(req, full_params, data)
    }
    PathMatchedMethodNotAllowed(allowed_methods) ->
      Ok(default_method_not_allowed_handler(allowed_methods))
    NotFound -> {
      let empty_params = params.new()
      case router.not_found_handler {
        option.Some(handler) -> handler(req, empty_params, data)
        option.None -> default_not_found_handler(req, empty_params, data)
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
///   |> router.get("/users/:id", get_user)
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

/// Gets all registered path patterns in the router as strings
///
pub fn get_paths(router: Router) -> List(String) {
  router.routes
  |> list.map(fn(r) { pattern.to_string(r.pattern) })
  |> list.unique()
}
