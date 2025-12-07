// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 CRUD Handlers
// HTTP/2 CRUD 핸들러
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Handler functions for CRUD operations using Aether's HTTP/2 stack.
// Aether의 HTTP/2 스택을 사용한 CRUD 연산 핸들러 함수들
//
// Uses: aether/protocol/http2/connection
// Uses: aether/protocol/http2/frame
//

import aether/examples/common/store.{type Store}
import aether/examples/common/user
import aether/protocol/http2/connection.{type Connection}
import aether/protocol/http2/frame.{type Frame}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// HTTP/2 request data extracted from frames
///
pub type Http2Request {
  Http2Request(
    stream_id: Int,
    method: String,
    path: String,
    headers: List(#(String, String)),
    body: BitArray,
  )
}

/// HTTP/2 response data to be converted to frames
///
pub type Http2Response {
  Http2Response(
    status: Int,
    headers: List(#(String, String)),
    body: BitArray,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Request Parsing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates an Http2Request from headers and body
///
pub fn new_request(
  stream_id: Int,
  headers: List(#(String, String)),
  body: BitArray,
) -> Http2Request {
  let method = find_header(headers, ":method") |> option.unwrap("GET")
  let path = find_header(headers, ":path") |> option.unwrap("/")
  
  Http2Request(
    stream_id: stream_id,
    method: method,
    path: path,
    headers: headers,
    body: body,
  )
}

/// Finds a header value by name
///
fn find_header(headers: List(#(String, String)), name: String) -> Option(String) {
  case list.find(headers, fn(h) { h.0 == name }) {
    Ok(#(_, value)) -> Some(value)
    Error(_) -> None
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Request Routing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Handles an HTTP/2 request and returns response with updated store
///
pub fn handle_request(
  request: Http2Request,
  store: Store,
) -> #(Http2Response, Store) {
  case request.method, request.path {
    // GET /api/users - List all users
    "GET", "/api/users" -> {
      list_users(store)
    }
    
    // GET /api/users/:id - Get single user
    "GET", path -> {
      case parse_user_id_from_path(path) {
        Some(id) -> get_user(store, id)
        None -> not_found(store)
      }
    }

    // POST /api/users - Create user
    "POST", "/api/users" -> {
      create_user(store, request.body)
    }

    // PUT /api/users/:id - Update user
    "PUT", path -> {
      case parse_user_id_from_path(path) {
        Some(id) -> update_user(store, id, request.body)
        None -> not_found(store)
      }
    }

    // DELETE /api/users/:id - Delete user
    "DELETE", path -> {
      case parse_user_id_from_path(path) {
        Some(id) -> delete_user(store, id)
        None -> not_found(store)
      }
    }

    // 404 for unknown routes
    _, _ -> not_found(store)
  }
}

/// Parses user ID from path like "/api/users/123"
///
fn parse_user_id_from_path(path: String) -> Option(Int) {
  case string.split(path, "/") {
    ["", "api", "users", id_str] -> {
      case int.parse(id_str) {
        Ok(id) -> Some(id)
        Error(_) -> None
      }
    }
    _ -> None
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CRUD Handler Implementations
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// GET /api/users - List all users
///
fn list_users(store: Store) -> #(Http2Response, Store) {
  let users = store.get_all(store)
  let json = user.list_to_json(users)
  
  let response = Http2Response(
    status: 200,
    headers: [#("content-type", "application/json")],
    body: bit_array.from_string(json),
  )
  
  #(response, store)
}

/// GET /api/users/:id - Get single user
///
fn get_user(store: Store, id: Int) -> #(Http2Response, Store) {
  case store.get_one(store, id) {
    Some(found_user) -> {
      let json = user.to_json(found_user)
      let response = Http2Response(
        status: 200,
        headers: [#("content-type", "application/json")],
        body: bit_array.from_string(json),
      )
      #(response, store)
    }
    None -> not_found_with_store(store)
  }
}

/// POST /api/users - Create user
///
fn create_user(store: Store, body: BitArray) -> #(Http2Response, Store) {
  case bit_array.to_string(body) {
    Ok(body_str) -> {
      case user.parse_create_request(body_str) {
        Ok(create_req) -> {
          let #(new_store, created_user) = store.create(
            store,
            create_req.name,
            create_req.email,
          )
          
          let json = user.to_json(created_user)
          let response = Http2Response(
            status: 201,
            headers: [#("content-type", "application/json")],
            body: bit_array.from_string(json),
          )
          #(response, new_store)
        }
        Error(msg) -> bad_request_with_store(store, msg)
      }
    }
    Error(_) -> bad_request_with_store(store, "Invalid request body")
  }
}

/// PUT /api/users/:id - Update user
///
fn update_user(store: Store, id: Int, body: BitArray) -> #(Http2Response, Store) {
  case bit_array.to_string(body) {
    Ok(body_str) -> {
      case user.parse_update_request(body_str) {
        Ok(update_req) -> {
          let #(new_store, result) = store.update(
            store,
            id,
            update_req.name,
            update_req.email,
          )
          
          case result {
            Some(updated_user) -> {
              let json = user.to_json(updated_user)
              let response = Http2Response(
                status: 200,
                headers: [#("content-type", "application/json")],
                body: bit_array.from_string(json),
              )
              #(response, new_store)
            }
            None -> not_found_with_store(store)
          }
        }
        Error(msg) -> bad_request_with_store(store, msg)
      }
    }
    Error(_) -> bad_request_with_store(store, "Invalid request body")
  }
}

/// DELETE /api/users/:id - Delete user
///
fn delete_user(store: Store, id: Int) -> #(Http2Response, Store) {
  let #(new_store, deleted) = store.delete(store, id)
  
  case deleted {
    True -> {
      let response = Http2Response(
        status: 204,
        headers: [],
        body: <<>>,
      )
      #(response, new_store)
    }
    False -> not_found_with_store(store)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Responses
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a 404 not found error response
/// 404 Not Found 에러 응답 생성 (경로를 찾을 수 없음)
///
fn not_found(store: Store) -> #(Http2Response, Store) {
  let response = Http2Response(
    status: 404,
    headers: [#("content-type", "application/json")],
    body: bit_array.from_string(user.error_json("Not found")),
  )
  #(response, store)
}

fn not_found_with_store(store: Store) -> #(Http2Response, Store) {
  let response = Http2Response(
    status: 404,
    headers: [#("content-type", "application/json")],
    body: bit_array.from_string(user.error_json("User not found")),
  )
  #(response, store)
}

fn bad_request_with_store(store: Store, message: String) -> #(Http2Response, Store) {
  let response = Http2Response(
    status: 400,
    headers: [#("content-type", "application/json")],
    body: bit_array.from_string(user.error_json(message)),
  )
  #(response, store)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Response to Frames
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds HTTP/2 response frames
///
pub fn build_response_frames(
  conn: Connection,
  stream_id: Int,
  response: Http2Response,
) -> #(Connection, List(Frame)) {
  // Add :status pseudo-header
  let headers = [
    #(":status", int.to_string(response.status)),
    ..response.headers
  ]
  
  connection.build_response(conn, stream_id, response.status, headers, response.body)
}
