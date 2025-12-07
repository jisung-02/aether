// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/1.x CRUD Server
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Server setup and router configuration for HTTP/1.x CRUD API.
// Uses: aether/router for URL routing
// Uses: aether/protocol/http for request/response handling
//

import aether/examples/http1/handlers
import aether/router/router.{type Router}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Router Configuration
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates the CRUD router with all endpoints
///
/// ## Endpoints
///
/// - `GET /api/users` - List all users
/// - `GET /api/users/:id` - Get a single user by ID
/// - `POST /api/users` - Create a new user
/// - `PUT /api/users/:id` - Update an existing user
/// - `DELETE /api/users/:id` - Delete a user
///
/// ## Example
///
/// ```gleam
/// let router = create_router()
/// let stage = router.to_stage(router)
/// // Use stage in pipeline
/// ```
///
pub fn create_router() -> Router {
  router.new()
  |> router.get("/api/users", handlers.list_users)
  |> router.get("/api/users/:id", handlers.get_user)
  |> router.post("/api/users", handlers.create_user)
  |> router.put("/api/users/:id", handlers.update_user)
  |> router.delete("/api/users/:id", handlers.delete_user)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Server Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/pipeline/stage
import aether/core/data.{type Data}

/// Converts the router to a pipeline stage
/// 라우터를 파이프라인 스테이지로 변환
///
/// This stage can be used in an Aether pipeline to handle
/// HTTP requests and route them to the appropriate handlers.
/// 이 스테이지는 Aether 파이프라인에서 HTTP 요청을 처리하고
/// 적절한 핸들러로 라우팅하는데 사용됩니다.
///
pub fn to_stage() -> stage.Stage(Data, Data) {
  let router = create_router()
  router.to_stage(router)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Demo Function
// 데모 함수
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/core/message
import aether/protocol/http/request
import gleam/io
import gleam/int

/// Demonstrates HTTP/1.x CRUD operations
/// HTTP/1.x CRUD 연산 데모
///
/// This function simulates handling various CRUD requests
/// without actually starting a server.
/// 이 함수는 실제 서버를 시작하지 않고 다양한 CRUD 요청 처리를 시뮬레이션합니다.
///
pub fn demo() {
  io.println("=== HTTP/1.x CRUD Demo ===\n")

  let router = create_router()
  let initial_data = message.new(<<>>)
  
  // Demo: GET /api/users
  io.println("1. GET /api/users")
  let get_all_req = request.get("/api/users")
  case router.dispatch(router, get_all_req, initial_data) {
    Ok(resp) -> {
      io.println("   Status: " <> int.to_string(resp.status))
      io.println("   Body: " <> body_to_string(resp.body))
    }
    Error(err) -> io.println("   Error: " <> error_to_string(err))
  }
  io.println("")
  
  // Demo: GET /api/users/1
  io.println("2. GET /api/users/1")
  let get_one_req = request.get("/api/users/1")
  case router.dispatch(router, get_one_req, initial_data) {
    Ok(resp) -> {
      io.println("   Status: " <> int.to_string(resp.status))
      io.println("   Body: " <> body_to_string(resp.body))
    }
    Error(err) -> io.println("   Error: " <> error_to_string(err))
  }
  io.println("")
  
  // Demo: POST /api/users
  io.println("3. POST /api/users")
  let create_body = <<"{\"name\":\"Dave\",\"email\":\"dave@example.com\"}":utf8>>
  let post_req = request.post("/api/users")
    |> request.set_body(create_body)
    |> request.set_header("content-type", "application/json")
  case router.dispatch(router, post_req, initial_data) {
    Ok(resp) -> {
      io.println("   Status: " <> int.to_string(resp.status))
      io.println("   Body: " <> body_to_string(resp.body))
    }
    Error(err) -> io.println("   Error: " <> error_to_string(err))
  }
  io.println("")
  
  // Demo: GET /api/users/999 (not found)
  io.println("4. GET /api/users/999 (not found)")
  let get_missing_req = request.get("/api/users/999")
  case router.dispatch(router, get_missing_req, initial_data) {
    Ok(resp) -> {
      io.println("   Status: " <> int.to_string(resp.status))
      io.println("   Body: " <> body_to_string(resp.body))
    }
    Error(err) -> io.println("   Error: " <> error_to_string(err))
  }
  io.println("")
  
  io.println("=== Demo Complete ===")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/bit_array

fn body_to_string(body: BitArray) -> String {
  case bit_array.to_string(body) {
    Ok(s) -> s
    Error(_) -> "<binary>"
  }
}

fn error_to_string(err: router.RouteError) -> String {
  case err {
    router.HandlerError(msg) -> "HandlerError: " <> msg
    router.InternalError(msg) -> "InternalError: " <> msg
  }
}
