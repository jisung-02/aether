// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Route Group Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides hierarchical routing with route groups, nested routers,
// and middleware scoping for the Aether HTTP router.
//
// ## Features
//
// - Route groups with common path prefixes
// - Middleware application at group level
// - Nested group support for hierarchical routing
// - Flatten at mount time for optimal runtime performance
//
// ## Usage
//
// ```gleam
// let api = group.new("/api/v1")
//   |> group.use_middleware(auth_middleware)
//   |> group.get("/users", list_users)
//   |> group.get("/users/:id", get_user)
//   |> group.post("/users", create_user)
//
// let router = router.new()
//   |> router.mount(api)
// ```
//

import aether/core/data.{type Data}
import aether/protocol/http/request.{type ParsedRequest}
import aether/protocol/http/response.{type HttpResponse}
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
/// Note: This type mirrors the RouteError in router.gleam.
/// Both modules define identical error types to avoid circular imports.
///
pub type RouteError {
  HandlerError(message: String)
  InternalError(message: String)
}

/// Handler function type with params
///
/// A handler receives the parsed request, extracted route parameters,
/// and pipeline data, returning either an HttpResponse or a RouteError.
///
pub type ParamHandler =
  fn(ParsedRequest, Params, Data) -> Result(HttpResponse, RouteError)

/// A single route definition
///
/// Note: This type mirrors the Route in router.gleam.
/// During mount, routes are converted between the two types.
///
pub type Route {
  Route(method: Option(Method), pattern: PathPattern, handler: ParamHandler)
}

/// Middleware type - transforms a handler into another handler
///
/// Enables pre/post processing around route handlers.
/// Middlewares wrap handlers in an "onion" pattern - first added
/// is outermost (runs first on request, last on response).
///
/// ## Example
///
/// ```gleam
/// let logging: Middleware = fn(next) {
///   fn(req, params, data) {
///     io.println("Request: " <> request.path(req))
///     let result = next(req, params, data)
///     io.println("Response sent")
///     result
///   }
/// }
/// ```
///
pub type Middleware =
  fn(ParamHandler) -> ParamHandler

/// A group of routes sharing a common prefix and middlewares
///
/// Route groups provide hierarchical organization of routes with:
/// - Shared path prefix (e.g., "/api/v1")
/// - Shared middlewares (applied to all routes in group)
/// - Nested sub-groups for deeper hierarchies
///
/// ## Fields
///
/// - `prefix`: Path prefix applied to all routes
/// - `middlewares`: List of middlewares applied to all routes
/// - `routes`: Routes defined directly in this group
/// - `groups`: Nested sub-groups
///
pub type RouteGroup {
  RouteGroup(
    prefix: String,
    middlewares: List(Middleware),
    routes: List(Route),
    groups: List(RouteGroup),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Group Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new route group with a prefix
///
/// ## Parameters
///
/// - `prefix`: Path prefix for all routes in this group
///
/// ## Returns
///
/// A new empty RouteGroup with the given prefix
///
/// ## Examples
///
/// ```gleam
/// let api = group.new("/api/v1")
///   |> group.get("/users", list_users)
/// // Route will match: GET /api/v1/users
/// ```
///
pub fn new(prefix: String) -> RouteGroup {
  RouteGroup(
    prefix: normalize_prefix(prefix),
    middlewares: [],
    routes: [],
    groups: [],
  )
}

/// Creates a route group without a prefix
///
/// Useful for grouping routes that share middlewares
/// but don't share a common path prefix.
///
/// ## Returns
///
/// A new empty RouteGroup with no prefix
///
/// ## Examples
///
/// ```gleam
/// let protected = group.without_prefix()
///   |> group.use_middleware(require_auth)
///   |> group.get("/profile", get_profile)
///   |> group.get("/settings", get_settings)
/// ```
///
pub fn without_prefix() -> RouteGroup {
  RouteGroup(prefix: "", middlewares: [], routes: [], groups: [])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Middleware Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Adds a middleware to the group
///
/// Middlewares are applied in order - first added is outermost.
/// This means the first middleware runs first on the request
/// and last on the response (onion pattern).
///
/// ## Parameters
///
/// - `grp`: The route group to add middleware to
/// - `middleware`: The middleware to add
///
/// ## Returns
///
/// The updated route group with the middleware added
///
/// ## Examples
///
/// ```gleam
/// let api = group.new("/api")
///   |> group.use_middleware(logging)  // Runs 1st on req, 2nd on resp
///   |> group.use_middleware(auth)     // Runs 2nd on req, 1st on resp
/// ```
///
pub fn use_middleware(grp: RouteGroup, middleware: Middleware) -> RouteGroup {
  RouteGroup(..grp, middlewares: list.append(grp.middlewares, [middleware]))
}

/// Adds multiple middlewares to the group
///
/// ## Parameters
///
/// - `grp`: The route group to add middlewares to
/// - `middlewares`: List of middlewares to add
///
/// ## Returns
///
/// The updated route group with all middlewares added
///
pub fn use_middlewares(
  grp: RouteGroup,
  middlewares: List(Middleware),
) -> RouteGroup {
  RouteGroup(..grp, middlewares: list.append(grp.middlewares, middlewares))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Route Addition Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Adds a route with a specific HTTP method
///
/// Note: The path is relative to the group's prefix.
/// An empty path "" matches the prefix exactly.
///
/// ## Parameters
///
/// - `grp`: The route group to add the route to
/// - `method`: The HTTP method to match
/// - `path`: The path pattern relative to group prefix
/// - `handler`: The handler function
///
/// ## Returns
///
/// The updated route group with the new route added
///
pub fn route(
  grp: RouteGroup,
  method: Method,
  path: String,
  handler: ParamHandler,
) -> RouteGroup {
  let pat = pattern.parse(path)
  let new_route = Route(method: option.Some(method), pattern: pat, handler: handler)
  RouteGroup(..grp, routes: list.append(grp.routes, [new_route]))
}

/// Adds a GET route
///
/// ## Examples
///
/// ```gleam
/// group.new("/api")
///   |> group.get("/users", list_users)
///   |> group.get("/users/:id", get_user)
/// ```
///
pub fn get(grp: RouteGroup, path: String, handler: ParamHandler) -> RouteGroup {
  route(grp, http.Get, path, handler)
}

/// Adds a POST route
///
pub fn post(grp: RouteGroup, path: String, handler: ParamHandler) -> RouteGroup {
  route(grp, http.Post, path, handler)
}

/// Adds a PUT route
///
pub fn put(grp: RouteGroup, path: String, handler: ParamHandler) -> RouteGroup {
  route(grp, http.Put, path, handler)
}

/// Adds a DELETE route
///
pub fn delete(
  grp: RouteGroup,
  path: String,
  handler: ParamHandler,
) -> RouteGroup {
  route(grp, http.Delete, path, handler)
}

/// Adds a PATCH route
///
pub fn patch(grp: RouteGroup, path: String, handler: ParamHandler) -> RouteGroup {
  route(grp, http.Patch, path, handler)
}

/// Adds a HEAD route
///
pub fn head(grp: RouteGroup, path: String, handler: ParamHandler) -> RouteGroup {
  route(grp, http.Head, path, handler)
}

/// Adds an OPTIONS route
///
pub fn options(
  grp: RouteGroup,
  path: String,
  handler: ParamHandler,
) -> RouteGroup {
  route(grp, http.Options, path, handler)
}

/// Adds a route matching any HTTP method
///
/// ## Examples
///
/// ```gleam
/// group.new("/api")
///   |> group.any("/health", health_check)
/// ```
///
pub fn any(grp: RouteGroup, path: String, handler: ParamHandler) -> RouteGroup {
  let pat = pattern.parse(path)
  let new_route = Route(method: option.None, pattern: pat, handler: handler)
  RouteGroup(..grp, routes: list.append(grp.routes, [new_route]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Nesting Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Nests a sub-group within this group
///
/// The sub-group inherits the parent's prefix (prepended)
/// and middlewares (applied before sub-group's middlewares).
///
/// ## Parameters
///
/// - `grp`: The parent route group
/// - `sub_group`: The child route group to nest
///
/// ## Returns
///
/// The updated parent group with the sub-group nested
///
/// ## Examples
///
/// ```gleam
/// let users = group.new("/users")
///   |> group.get("", list_users)
///   |> group.get("/:id", get_user)
///
/// let api = group.new("/api")
///   |> group.use_middleware(auth)
///   |> group.nest(users)
///
/// // Results in:
/// // GET /api/users (with auth middleware)
/// // GET /api/users/:id (with auth middleware)
/// ```
///
pub fn nest(grp: RouteGroup, sub_group: RouteGroup) -> RouteGroup {
  RouteGroup(..grp, groups: list.append(grp.groups, [sub_group]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Prefix Handling
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Normalizes a path prefix
///
/// - Trims whitespace
/// - Ensures leading slash (unless empty)
/// - Removes trailing slash (unless root "/")
///
/// ## Examples
///
/// ```gleam
/// normalize_prefix("/api/")   // "/api"
/// normalize_prefix("api")     // "/api"
/// normalize_prefix("")        // ""
/// normalize_prefix("/")       // "/"
/// ```
///
pub fn normalize_prefix(prefix: String) -> String {
  let trimmed = string.trim(prefix)

  case string.is_empty(trimmed) {
    True -> ""
    False -> {
      // Ensure leading slash
      let with_leading = case string.starts_with(trimmed, "/") {
        True -> trimmed
        False -> "/" <> trimmed
      }

      // Remove trailing slash (unless it's just "/")
      case with_leading {
        "/" -> "/"
        _ ->
          case string.ends_with(with_leading, "/") {
            True -> string.drop_end(with_leading, 1)
            False -> with_leading
          }
      }
    }
  }
}

/// Combines two path prefixes correctly
///
/// Handles edge cases like empty prefixes and double slashes.
///
/// ## Examples
///
/// ```gleam
/// combine_prefixes("/api", "/users")   // "/api/users"
/// combine_prefixes("/api/", "/users")  // "/api/users"
/// combine_prefixes("", "/users")       // "/users"
/// combine_prefixes("/api", "")         // "/api"
/// ```
///
pub fn combine_prefixes(parent: String, child: String) -> String {
  let normalized_parent = normalize_prefix(parent)
  let normalized_child = normalize_prefix(child)

  case normalized_parent, normalized_child {
    "", "" -> ""
    "", c -> c
    p, "" -> p
    "/", c -> c
    p, c -> p <> c
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flatten Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Flattens a route group into a list of routes
///
/// Applies all prefixes and middlewares, converting the hierarchical
/// group structure into a flat list suitable for the router.
///
/// ## Parameters
///
/// - `grp`: The route group to flatten
///
/// ## Returns
///
/// A list of Route with all prefixes and middlewares applied
///
pub fn flatten(grp: RouteGroup) -> List(Route) {
  flatten_with_context(grp, "", [])
}

/// Internal function to flatten with accumulated context
///
fn flatten_with_context(
  grp: RouteGroup,
  accumulated_prefix: String,
  accumulated_middlewares: List(Middleware),
) -> List(Route) {
  // Combine prefix with accumulated prefix
  let full_prefix = combine_prefixes(accumulated_prefix, grp.prefix)

  // Combine middlewares (parent's first, then group's)
  let full_middlewares = list.append(accumulated_middlewares, grp.middlewares)

  // Transform this group's routes
  let own_routes =
    list.map(grp.routes, fn(r) {
      let new_pattern = pattern.prepend_prefix(full_prefix, r.pattern)
      let new_handler = apply_middlewares(full_middlewares, r.handler)
      Route(method: r.method, pattern: new_pattern, handler: new_handler)
    })

  // Recursively flatten nested groups
  let nested_routes =
    list.flat_map(grp.groups, fn(sub_group) {
      flatten_with_context(sub_group, full_prefix, full_middlewares)
    })

  // Combine own routes with nested routes
  list.append(own_routes, nested_routes)
}

/// Applies middlewares to a handler in onion order
///
/// First middleware in list wraps outermost (runs first on request).
///
fn apply_middlewares(
  middlewares: List(Middleware),
  handler: ParamHandler,
) -> ParamHandler {
  // Fold right: first middleware in list wraps outermost
  // fold_right signature: fn(list, initial, fn(acc, item) -> acc)
  list.fold_right(middlewares, handler, fn(acc_handler, middleware) {
    middleware(acc_handler)
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the total route count including nested groups
///
pub fn route_count(grp: RouteGroup) -> Int {
  let own_count = list.length(grp.routes)
  let nested_count =
    list.fold(grp.groups, 0, fn(acc, sub_group) { acc + route_count(sub_group) })
  own_count + nested_count
}

/// Checks if the group is empty (no routes or nested groups)
///
pub fn is_empty(grp: RouteGroup) -> Bool {
  list.is_empty(grp.routes) && list.is_empty(grp.groups)
}

/// Gets the group's prefix
///
pub fn prefix(grp: RouteGroup) -> String {
  grp.prefix
}

/// Gets the number of middlewares in the group
///
pub fn middleware_count(grp: RouteGroup) -> Int {
  list.length(grp.middlewares)
}
