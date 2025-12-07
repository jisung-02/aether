// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/1.x CRUD Server - Postman 테스트용
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Run server:
//   gleam run -m aether/examples/server_main
//
// Test with curl or Postman:
//   GET    http://localhost:3000/api/users
//   GET    http://localhost:3000/api/users/1
//   POST   http://localhost:3000/api/users
//   PUT    http://localhost:3000/api/users/1
//   DELETE http://localhost:3000/api/users/1
//

import aether/core/message
import aether/examples/http1/server as http1_server
import aether/protocol/http/stage as http_stage
import aether/pipeline/pipeline
import gleam/bit_array
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request as http_request
import gleam/http/response as http_response
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import mist

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pipeline Setup
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates the HTTP processing pipeline
/// HTTP 처리 파이프라인 생성
///
fn create_pipeline() -> pipeline.Pipeline(message.Message, message.Message) {
  pipeline.new()
  |> pipeline.pipe(http_stage.decode())
  |> pipeline.pipe(http1_server.to_stage())
  |> pipeline.pipe(http_stage.encode_response())
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Mist Integration
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Handles incoming HTTP requests through the Aether pipeline
/// Aether 파이프라인을 통한 HTTP 요청 처리
///
fn handle_request(
  req: http_request.Request(mist.Connection),
  processing_pipeline: pipeline.Pipeline(message.Message, message.Message),
) -> http_response.Response(mist.ResponseData) {
  // Read request body
  let body_result = mist.read_body(req, 1024 * 1024)

  case body_result {
    Ok(mist_req) -> {
      // Convert mist request to raw HTTP bytes
      let raw_request = build_raw_request(mist_req)
      let input_message = message.new(raw_request)

      // Process through pipeline
      case pipeline.execute(processing_pipeline, input_message) {
        Ok(result_message) -> {
          let response_bytes = message.bytes(result_message)
          parse_response_bytes(response_bytes)
        }
        Error(err) -> {
          io.println("Pipeline error: " <> string.inspect(err))
          internal_server_error()
        }
      }
    }
    Error(_) -> bad_request_response()
  }
}

/// Builds raw HTTP request bytes from mist request
/// Mist 요청을 원시 HTTP 바이트로 변환
///
fn build_raw_request(req: http_request.Request(BitArray)) -> BitArray {
  let method = case req.method {
    http.Get -> "GET"
    http.Post -> "POST"
    http.Put -> "PUT"
    http.Delete -> "DELETE"
    http.Patch -> "PATCH"
    http.Head -> "HEAD"
    http.Options -> "OPTIONS"
    _ -> "GET"
  }

  let path = req.path
  let query = case req.query {
    Some(q) -> "?" <> q
    None -> ""
  }

  let headers_str =
    req.headers
    |> list.map(fn(h: #(String, String)) { h.0 <> ": " <> h.1 })
    |> string.join("\r\n")

  let body = req.body

  let request_line = method <> " " <> path <> query <> " HTTP/1.1\r\n"
  let full_request = request_line <> headers_str <> "\r\n\r\n"

  <<full_request:utf8, body:bits>>
}

/// Parses response bytes back to mist response
/// 응답 바이트를 Mist 응답으로 파싱
///
fn parse_response_bytes(
  bytes: BitArray,
) -> http_response.Response(mist.ResponseData) {
  case bit_array.to_string(bytes) {
    Ok(response_str) -> {
      case string.split_once(response_str, "\r\n\r\n") {
        Ok(#(headers_part, body_str)) -> {
          let status = extract_status(headers_part)
          let headers = extract_headers(headers_part)

          http_response.Response(
            status: status,
            headers: headers,
            body: mist.Bytes(bytes_tree.from_string(body_str)),
          )
        }
        Error(_) -> internal_server_error()
      }
    }
    Error(_) -> internal_server_error()
  }
}

/// Extracts status code from response headers
/// 응답 헤더에서 상태 코드 추출
///
fn extract_status(headers_part: String) -> Int {
  case string.split_once(headers_part, "\r\n") {
    Ok(#(status_line, _)) -> {
      let parts = string.split(status_line, " ")
      case parts {
        [_, status_str, ..] -> {
          case int.parse(status_str) {
            Ok(status) -> status
            Error(_) -> 500
          }
        }
        _ -> 500
      }
    }
    Error(_) -> 500
  }
}

/// Extracts headers from response
/// 응답에서 헤더 추출
///
fn extract_headers(headers_part: String) -> List(#(String, String)) {
  case string.split_once(headers_part, "\r\n") {
    Ok(#(_, rest)) -> {
      rest
      |> string.split("\r\n")
      |> list.filter_map(fn(line) {
        case string.split_once(line, ": ") {
          Ok(#(name, value)) -> Ok(#(string.lowercase(name), value))
          Error(_) -> Error(Nil)
        }
      })
    }
    Error(_) -> []
  }
}

fn internal_server_error() -> http_response.Response(mist.ResponseData) {
  let body = "{\"error\":\"Internal Server Error\"}"

  http_response.Response(
    status: 500,
    headers: [#("content-type", "application/json")],
    body: mist.Bytes(bytes_tree.from_string(body)),
  )
}

fn bad_request_response() -> http_response.Response(mist.ResponseData) {
  let body = "{\"error\":\"Bad Request\"}"

  http_response.Response(
    status: 400,
    headers: [#("content-type", "application/json")],
    body: mist.Bytes(bytes_tree.from_string(body)),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Main Entry Point
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn main() {
  io.println("\n════════════════════════════════════════════════════════════")
  io.println("  🚀 Aether HTTP/1.x CRUD Server")
  io.println("  Aether HTTP/1.x CRUD 서버")
  io.println("════════════════════════════════════════════════════════════")
  io.println("")
  io.println("  📡 Available Endpoints:")
  io.println("  사용 가능한 엔드포인트:")
  io.println("")
  io.println("  ┌─ HTTP/1.x Endpoints:")
  io.println("  │")
  io.println("  │  GET    /api/users        - List all users (모든 사용자 조회)")
  io.println("  │  GET    /api/users/:id    - Get user by ID (ID로 사용자 조회)")
  io.println("  │  POST   /api/users        - Create new user (새 사용자 생성)")
  io.println("  │  PUT    /api/users/:id    - Update user (사용자 수정)")
  io.println("  │  DELETE /api/users/:id    - Delete user (사용자 삭제)")
  io.println("  │")
  io.println("  └─ HTTP/2-style Endpoints:")
  io.println("")
  io.println("     GET    /api/http2/users        - List all users (HTTP/2)")
  io.println("     GET    /api/http2/users/:id    - Get user by ID (HTTP/2)")
  io.println("     POST   /api/http2/users        - Create new user (HTTP/2)")
  io.println("     PUT    /api/http2/users/:id    - Update user (HTTP/2)")
  io.println("     DELETE /api/http2/users/:id    - Delete user (HTTP/2)")
  io.println("")
  io.println("  🌐 Server starting on: http://localhost:3000")
  io.println("  서버 시작: http://localhost:3000")
  io.println("")
  io.println("  📮 Test with Postman or curl:")
  io.println("  Postman 또는 curl로 테스트:")
  io.println("")
  io.println("    curl http://localhost:3000/api/users")
  io.println("    curl -X POST http://localhost:3000/api/users \\")
  io.println("      -H 'Content-Type: application/json' \\")
  io.println("      -d '{\"name\":\"John\",\"email\":\"john@example.com\"}'")
  io.println("")
  io.println("════════════════════════════════════════════════════════════\n")

  let processing_pipeline = create_pipeline()

  let assert Ok(_) =
    fn(req) { handle_request(req, processing_pipeline) }
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  io.println("✅ Server is running! Press Ctrl+C to stop.")
  io.println("✅ 서버가 실행 중입니다! Ctrl+C로 종료하세요.\n")

  process.sleep_forever()
}
