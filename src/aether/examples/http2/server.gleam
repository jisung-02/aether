// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 CRUD Server
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Server setup and connection handling for HTTP/2 CRUD API.
// Uses: aether/protocol/http2/connection for connection management
// Uses: aether/protocol/http2/frame_parser for frame parsing
// Uses: aether/protocol/http2/frame_builder for frame building
//

import aether/examples/common/store.{type Store}
import aether/examples/http2/handlers
import aether/protocol/http2/connection.{type Connection}
import aether/protocol/http2/frame.{type Frame}
import aether/protocol/http2/frame_builder
import aether/protocol/http2/frame_parser
import gleam/int
import gleam/io
import gleam/list

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Server State
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// HTTP/2 server state
///
pub type ServerState {
  ServerState(connection: Connection, store: Store)
}

/// Creates initial server state
///
pub fn new_server_state() -> ServerState {
  ServerState(
    connection: connection.new_server(),
    store: store.with_sample_data(),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Processing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Processes incoming raw data and returns response frames
///
pub fn process_raw_data(
  state: ServerState,
  raw_data: BitArray,
) -> #(ServerState, List(BitArray)) {
  case frame_parser.parse_frame(raw_data) {
    Ok(result) -> {
      let #(new_state, response_frames) = process_frame(state, result.frame)

      // Serialize response frames
      let response_bytes = list.map(response_frames, frame_builder.build_frame)

      #(new_state, response_bytes)
    }
    Error(_) -> {
      // Parse error - return empty response
      #(state, [])
    }
  }
}

/// Processes a single frame and returns response frames
///
pub fn process_frame(
  state: ServerState,
  frame: Frame,
) -> #(ServerState, List(Frame)) {
  case connection.handle_frame(state.connection, frame) {
    // Request complete - dispatch to handler
    connection.RequestComplete(conn, stream_id, headers, body) -> {
      let request = handlers.new_request(stream_id, headers, body)
      let #(response, new_store) = handlers.handle_request(request, state.store)
      let #(final_conn, response_frames) =
        handlers.build_response_frames(conn, stream_id, response)

      let new_state = ServerState(connection: final_conn, store: new_store)

      #(new_state, response_frames)
    }

    // Connection frame - send response frames
    connection.SendFrames(conn, frames) -> {
      let new_state = ServerState(..state, connection: conn)
      #(new_state, frames)
    }

    // Just update connection state
    connection.HandleOk(conn) -> {
      let new_state = ServerState(..state, connection: conn)
      #(new_state, [])
    }

    // Connection error
    connection.HandleError(conn, _error) -> {
      let new_state = ServerState(..state, connection: conn)
      #(new_state, [])
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Demo Function
// 데모 함수
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/bit_array

/// Demonstrates HTTP/2 CRUD operations
/// HTTP/2 CRUD 연산 데모
///
/// This function simulates handling HTTP/2 requests at the frame level
/// without actually starting a server.
/// 이 함수는 프레임 레벨에서 HTTP/2 요청 처리를 시뮬레이션합니다 (서버 실행 없이).
///
pub fn demo() {
  io.println("=== HTTP/2 CRUD Demo ===\n")

  let initial_state = new_server_state()

  // Demo 1: List users (simulated request)
  io.println("1. GET /api/users (HTTP/2)")
  let request1 =
    handlers.new_request(
      1,
      // stream_id
      [
        #(":method", "GET"),
        #(":path", "/api/users"),
        #(":scheme", "https"),
        #(":authority", "localhost"),
      ],
      <<>>,
    )
  let #(response1, store1) =
    handlers.handle_request(request1, initial_state.store)
  io.println("   Status: " <> int.to_string(response1.status))
  io.println("   Body: " <> body_to_string(response1.body))
  io.println("")

  // Demo 2: Get single user
  io.println("2. GET /api/users/1 (HTTP/2)")
  let request2 =
    handlers.new_request(
      3,
      // stream_id (odd for client-initiated)
      [
        #(":method", "GET"),
        #(":path", "/api/users/1"),
        #(":scheme", "https"),
        #(":authority", "localhost"),
      ],
      <<>>,
    )
  let #(response2, store2) = handlers.handle_request(request2, store1)
  io.println("   Status: " <> int.to_string(response2.status))
  io.println("   Body: " <> body_to_string(response2.body))
  io.println("")

  // Demo 3: Create user
  io.println("3. POST /api/users (HTTP/2)")
  let create_body = <<"{\"name\":\"Eve\",\"email\":\"eve@example.com\"}":utf8>>
  let request3 =
    handlers.new_request(
      5,
      [
        #(":method", "POST"),
        #(":path", "/api/users"),
        #(":scheme", "https"),
        #(":authority", "localhost"),
        #("content-type", "application/json"),
      ],
      create_body,
    )
  let #(response3, store3) = handlers.handle_request(request3, store2)
  io.println("   Status: " <> int.to_string(response3.status))
  io.println("   Body: " <> body_to_string(response3.body))
  io.println("")

  // Demo 4: Delete user
  io.println("4. DELETE /api/users/2 (HTTP/2)")
  let request4 =
    handlers.new_request(
      7,
      [
        #(":method", "DELETE"),
        #(":path", "/api/users/2"),
        #(":scheme", "https"),
        #(":authority", "localhost"),
      ],
      <<>>,
    )
  let #(response4, store4) = handlers.handle_request(request4, store3)
  io.println("   Status: " <> int.to_string(response4.status))
  case response4.status {
    204 -> io.println("   Body: <no content>")
    _ -> io.println("   Body: " <> body_to_string(response4.body))
  }
  io.println("")

  // Demo 5: Not found
  io.println("5. GET /api/users/999 (HTTP/2)")
  let request5 =
    handlers.new_request(
      9,
      [
        #(":method", "GET"),
        #(":path", "/api/users/999"),
        #(":scheme", "https"),
        #(":authority", "localhost"),
      ],
      <<>>,
    )
  let #(response5, _store5) = handlers.handle_request(request5, store4)
  io.println("   Status: " <> int.to_string(response5.status))
  io.println("   Body: " <> body_to_string(response5.body))
  io.println("")

  io.println("=== Demo Complete ===")
  io.println("")
  io.println("Note: HTTP/2 uses binary framing and stream multiplexing.")
  io.println("Each request has a unique stream_id (odd for client-initiated).")
}

fn body_to_string(body: BitArray) -> String {
  case bit_array.to_string(body) {
    Ok(s) -> s
    Error(_) -> "<binary>"
  }
}
