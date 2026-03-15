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
import aether/examples/multiprotocol/runtime as multiprotocol_runtime
import aether/examples/multiprotocol/server as multiprotocol_server
import aether/protocol/http/request as aether_request
import aether/protocol/http/response.{type HttpResponse, HttpResponse}
import aether/router/router as aether_router
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request as http_request
import gleam/http/response as http_response
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some, from_result}
import gleam/string
import mist

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Mist Integration
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Handles incoming HTTP requests through the Aether pipeline
/// Aether 파이프라인을 통한 HTTP 요청 처리
///
fn handle_request(
  req: http_request.Request(mist.Connection),
  router: aether_router.Router,
) -> http_response.Response(mist.ResponseData) {
  // Read request body
  let body_result = mist.read_body(req, 1024 * 1024)

  case body_result {
    Ok(mist_req) -> {
      let parsed_request = to_parsed_request(mist_req)
      let input_data = message.new(parsed_request.body)

      case aether_router.dispatch(router, parsed_request, input_data) {
        Ok(resp) -> to_mist_response(resp)
        Error(err) -> {
          io.println("Router error: " <> string.inspect(err))
          internal_server_error()
        }
      }
    }
    Error(_) -> bad_request_response()
  }
}

fn to_parsed_request(
  req: http_request.Request(BitArray),
) -> aether_request.ParsedRequest {
  let method = effective_method(req)
  let uri = effective_uri(req)

  aether_request.ParsedRequest(
    method: method,
    uri: uri,
    version: aether_request.Http11,
    headers: ensure_host_header(req),
    body: req.body,
  )
}

fn effective_method(req: http_request.Request(BitArray)) -> http.Method {
  case find_header(req.headers, ":method") {
    Some(method) -> {
      case http.parse_method(method) {
        Ok(parsed) -> parsed
        Error(_) -> req.method
      }
    }
    None -> req.method
  }
}

fn effective_uri(req: http_request.Request(BitArray)) -> String {
  case find_header(req.headers, ":path") {
    Some(path) -> normalize_path(path)
    None -> {
      let path = normalize_path(req.path)
      case req.query {
        Some(q) -> path <> "?" <> q
        None -> path
      }
    }
  }
}

fn normalize_path(path: String) -> String {
  case string.starts_with(path, "/") {
    True -> path
    False -> "/" <> path
  }
}

fn ensure_host_header(
  req: http_request.Request(BitArray),
) -> List(#(String, String)) {
  case list.any(req.headers, fn(header) { header.0 == "host" }) {
    True -> req.headers
    False -> {
      let host = case find_header(req.headers, ":authority") {
        Some(authority) -> authority
        None -> req.host
      }
      [#("host", host), ..req.headers]
    }
  }
}

fn find_header(headers: List(#(String, String)), name: String) -> Option(String) {
  headers
  |> list.key_find(name)
  |> from_result()
}

fn to_mist_response(
  resp: HttpResponse,
) -> http_response.Response(mist.ResponseData) {
  let HttpResponse(status:, headers:, body:, ..) = resp

  http_response.Response(
    status: status,
    headers: headers,
    body: mist.Bytes(bytes_tree.from_bit_array(body)),
  )
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
  case multiprotocol_runtime.load_from_env() {
    Ok(runtime) -> {
      let scheme = multiprotocol_server.scheme(runtime.server_config)
      let scheme_label = case scheme {
        http.Http -> "http"
        http.Https -> "https"
      }
      let port = runtime.server_config.port

      io.println(
        "  🌐 Server starting on: "
        <> scheme_label
        <> "://localhost:"
        <> int.to_string(port),
      )
      io.println(
        "  서버 시작: " <> scheme_label <> "://localhost:" <> int.to_string(port),
      )
      io.println("")
      io.println("  📮 Test with Postman or curl:")
      io.println("  Postman 또는 curl로 테스트:")
      io.println("")

      case runtime.mode {
        multiprotocol_runtime.CleartextH2c -> {
          io.println(
            "    curl http://localhost:" <> int.to_string(port) <> "/api/users",
          )
          io.println(
            "    curl --http2-prior-knowledge http://localhost:"
            <> int.to_string(port)
            <> "/api/users",
          )
        }
        multiprotocol_runtime.TlsAlpn -> {
          io.println(
            "    curl -k --http1.1 https://localhost:"
            <> int.to_string(port)
            <> "/api/users",
          )
          io.println(
            "    curl -k --http2 https://localhost:"
            <> int.to_string(port)
            <> "/api/users",
          )
        }
      }

      io.println("")
      io.println(
        "════════════════════════════════════════════════════════════\n",
      )
      let router = http1_server.create_router()

      let assert Ok(_) =
        multiprotocol_server.start(runtime.server_config, fn(req) {
          handle_request(req, router)
        })

      io.println(
        "✅ Server is running in "
        <> multiprotocol_runtime.mode_to_string(runtime.mode)
        <> " mode. Press Ctrl+C to stop.",
      )
      io.println("✅ 서버가 실행 중입니다! Ctrl+C로 종료하세요.\n")

      process.sleep_forever()
    }
    Error(err) -> {
      panic as multiprotocol_runtime.error_to_string(err)
    }
  }
}
