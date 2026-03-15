// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2-style CRUD Handlers (via HTTP/1.x)
// HTTP/2 스타일 CRUD 핸들러 (HTTP/1.x를 통해)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// These handlers provide HTTP/2-style endpoints (/api/http2/users)
// served over HTTP/1.x protocol for testing purposes.
// 테스트 목적으로 HTTP/1.x 프로토콜을 통해 제공되는 HTTP/2 스타일 엔드포인트
//

import aether/core/data.{type Data}
import aether/examples/common/store.{type Store}
import aether/examples/common/user
import aether/protocol/http/request.{type ParsedRequest}
import aether/protocol/http/response.{type HttpResponse}
import aether/router/params.{type Params}
import aether/router/router.{type RouteError}
import gleam/bit_array
import gleam/option.{None, Some}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Handler Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// GET /api/http2/users - List all users (HTTP/2 스타일)
///
pub fn list_users(
  _req: ParsedRequest,
  _params: Params,
  data: Data,
) -> Result(HttpResponse, RouteError) {
  let store = get_store_from_data(data)
  let users = store.get_all(store)
  let json = user.list_to_json(users)

  Ok(
    response.ok()
    |> response.json()
    |> response.with_string_body(json)
    |> response.with_header("x-protocol", "http2-style"),
  )
}

/// GET /api/http2/users/:id - Get a single user (HTTP/2 스타일)
///
pub fn get_user(
  _req: ParsedRequest,
  params: Params,
  data: Data,
) -> Result(HttpResponse, RouteError) {
  let store = get_store_from_data(data)

  case params.get_int(params, "id") {
    Some(id) -> {
      case store.get_one(store, id) {
        Some(found_user) -> {
          Ok(
            response.ok()
            |> response.json()
            |> response.with_string_body(user.to_json(found_user))
            |> response.with_header("x-protocol", "http2-style"),
          )
        }
        None -> {
          Ok(
            response.not_found()
            |> response.json()
            |> response.with_string_body(user.error_json("User not found"))
            |> response.with_header("x-protocol", "http2-style"),
          )
        }
      }
    }
    None -> {
      Ok(
        response.bad_request()
        |> response.json()
        |> response.with_string_body(user.error_json("Invalid user ID"))
        |> response.with_header("x-protocol", "http2-style"),
      )
    }
  }
}

/// POST /api/http2/users - Create a new user (HTTP/2 스타일)
///
pub fn create_user(
  req: ParsedRequest,
  _params: Params,
  data: Data,
) -> Result(HttpResponse, RouteError) {
  let store = get_store_from_data(data)

  case bit_array.to_string(req.body) {
    Ok(body_str) -> {
      case user.parse_create_request(body_str) {
        Ok(create_req) -> {
          let #(_new_store, created_user) =
            store.create(store, create_req.name, create_req.email)

          Ok(
            response.created()
            |> response.json()
            |> response.with_string_body(user.to_json(created_user))
            |> response.with_header("x-protocol", "http2-style"),
          )
        }
        Error(msg) -> {
          Ok(
            response.bad_request()
            |> response.json()
            |> response.with_string_body(user.error_json(msg))
            |> response.with_header("x-protocol", "http2-style"),
          )
        }
      }
    }
    Error(_) -> {
      Ok(
        response.bad_request()
        |> response.json()
        |> response.with_string_body(user.error_json("Invalid request body"))
        |> response.with_header("x-protocol", "http2-style"),
      )
    }
  }
}

/// PUT /api/http2/users/:id - Update a user (HTTP/2 스타일)
///
pub fn update_user(
  req: ParsedRequest,
  params: Params,
  data: Data,
) -> Result(HttpResponse, RouteError) {
  let store = get_store_from_data(data)

  case params.get_int(params, "id") {
    Some(id) -> {
      case bit_array.to_string(req.body) {
        Ok(body_str) -> {
          case user.parse_update_request(body_str) {
            Ok(update_req) -> {
              let #(_new_store, result) =
                store.update(store, id, update_req.name, update_req.email)

              case result {
                Some(updated_user) -> {
                  Ok(
                    response.ok()
                    |> response.json()
                    |> response.with_string_body(user.to_json(updated_user))
                    |> response.with_header("x-protocol", "http2-style"),
                  )
                }
                None -> {
                  Ok(
                    response.not_found()
                    |> response.json()
                    |> response.with_string_body(user.error_json(
                      "User not found",
                    ))
                    |> response.with_header("x-protocol", "http2-style"),
                  )
                }
              }
            }
            Error(msg) -> {
              Ok(
                response.bad_request()
                |> response.json()
                |> response.with_string_body(user.error_json(msg))
                |> response.with_header("x-protocol", "http2-style"),
              )
            }
          }
        }
        Error(_) -> {
          Ok(
            response.bad_request()
            |> response.json()
            |> response.with_string_body(user.error_json("Invalid request body"))
            |> response.with_header("x-protocol", "http2-style"),
          )
        }
      }
    }
    None -> {
      Ok(
        response.bad_request()
        |> response.json()
        |> response.with_string_body(user.error_json("Invalid user ID"))
        |> response.with_header("x-protocol", "http2-style"),
      )
    }
  }
}

/// DELETE /api/http2/users/:id - Delete a user (HTTP/2 스타일)
///
pub fn delete_user(
  _req: ParsedRequest,
  params: Params,
  data: Data,
) -> Result(HttpResponse, RouteError) {
  let store = get_store_from_data(data)

  case params.get_int(params, "id") {
    Some(id) -> {
      let #(_new_store, deleted) = store.delete(store, id)

      case deleted {
        True -> {
          Ok(
            response.no_content()
            |> response.with_header("x-protocol", "http2-style"),
          )
        }
        False -> {
          Ok(
            response.not_found()
            |> response.json()
            |> response.with_string_body(user.error_json("User not found"))
            |> response.with_header("x-protocol", "http2-style"),
          )
        }
      }
    }
    None -> {
      Ok(
        response.bad_request()
        |> response.json()
        |> response.with_string_body(user.error_json("Invalid user ID"))
        |> response.with_header("x-protocol", "http2-style"),
      )
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the store from pipeline data
/// 파이프라인 데이터에서 Store 가져오기
///
/// ⚠️ 주의: 현재는 매 요청마다 새로운 샘플 데이터로 초기화됨
/// 실제 운영 환경에서는 Actor나 ETS를 사용하여 전역 상태를 관리해야 함
///
fn get_store_from_data(_data: Data) -> Store {
  // 간단한 예제를 위해 샘플 데이터 반환
  // 프로덕션에서는 Actor 또는 ETS 테이블을 사용해야 함
  store.with_sample_data()
}
