// HTTP/2 Connection Integration Tests
// Tests for the complete connection handler

import gleam/bit_array
import gleam/string

import aether/protocol/http2/connection
import aether/protocol/http2/error as http2_error
import aether/protocol/http2/frame.{
  Continuation, ContinuationF, ContinuationFrame, Data, DataF, DataFrame,
  FrameHeader, Goaway, GoawayF, GoawayFrame, Headers, HeadersF, HeadersFrame,
  MaxConcurrentStreams, Ping, PingF, PingFrame, Settings, SettingsF,
  SettingsFrame, SettingsParameter, WindowUpdate, WindowUpdateF,
  WindowUpdateFrame, flag_ack, flag_end_headers, flag_end_stream,
}
import aether/protocol/http2/hpack/encoder as hpack_encoder
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_server_creates_valid_connection_test() {
  let conn = connection.new_server()

  // Server connection should start without preface
  connection.is_preface_complete(conn)
  |> should.be_false()

  // Should not be going away
  connection.is_going_away(conn)
  |> should.be_false()

  // Should have no pending requests
  connection.pending_request_count(conn)
  |> should.equal(0)
}

pub fn new_client_creates_valid_connection_test() {
  let conn = connection.new_client()

  connection.is_preface_complete(conn)
  |> should.be_false()

  connection.is_going_away(conn)
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Preface Handling Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn mark_preface_sent_test() {
  let conn = connection.new_server()
  let updated = connection.mark_preface_sent(conn)

  // Preface not complete until both sent and received
  connection.is_preface_complete(updated)
  |> should.be_false()
}

pub fn mark_preface_received_test() {
  let conn = connection.new_server()
  let updated = connection.mark_preface_received(conn)

  connection.is_preface_complete(updated)
  |> should.be_false()
}

pub fn preface_complete_after_both_test() {
  let conn =
    connection.new_server()
    |> connection.mark_preface_sent
    |> connection.mark_preface_received

  connection.is_preface_complete(conn)
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Settings Frame Handling Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn handle_settings_triggers_ack_test() {
  let conn = connection.new_server()

  let settings_frame =
    SettingsF(
      FrameHeader(length: 12, frame_type: Settings, flags: 0, stream_id: 0),
      SettingsFrame(ack: False, parameters: [
        SettingsParameter(identifier: MaxConcurrentStreams, value: 100),
      ]),
    )

  case connection.handle_frame(conn, settings_frame) {
    connection.SendFrames(new_conn, frames) -> {
      // Should send SETTINGS ACK
      list_length(frames) |> should.equal(1)

      // Preface should be marked as received
      new_conn.preface_received |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn handle_settings_ack_no_response_test() {
  let conn = connection.new_server()

  let ack_frame =
    SettingsF(
      FrameHeader(
        length: 0,
        frame_type: Settings,
        flags: flag_ack,
        stream_id: 0,
      ),
      SettingsFrame(ack: True, parameters: []),
    )

  case connection.handle_frame(conn, ack_frame) {
    connection.HandleOk(_new_conn, _frames) -> should.be_true(True)
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Ping Frame Handling Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn handle_ping_triggers_ack_test() {
  let conn = connection.new_server()
  let opaque_data = <<1, 2, 3, 4, 5, 6, 7, 8>>

  let ping_frame =
    PingF(
      FrameHeader(length: 8, frame_type: Ping, flags: 0, stream_id: 0),
      PingFrame(ack: False, opaque_data: opaque_data),
    )

  case connection.handle_frame(conn, ping_frame) {
    connection.SendFrames(_new_conn, frames) -> {
      // Should send PING ACK
      list_length(frames) |> should.equal(1)

      case frames {
        [PingF(header, payload)] -> {
          // Should have ACK flag
          frame.is_ack(header.flags) |> should.be_true()
          // Should echo opaque data
          payload.opaque_data |> should.equal(opaque_data)
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn handle_ping_ack_no_response_test() {
  let conn = connection.new_server()

  let ack_frame =
    PingF(
      FrameHeader(length: 8, frame_type: Ping, flags: flag_ack, stream_id: 0),
      PingFrame(ack: True, opaque_data: <<1, 2, 3, 4, 5, 6, 7, 8>>),
    )

  case connection.handle_frame(conn, ack_frame) {
    connection.HandleOk(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GoAway Frame Handling Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn handle_goaway_sets_going_away_test() {
  let conn = connection.new_server()

  let goaway_frame =
    GoawayF(
      FrameHeader(length: 8, frame_type: Goaway, flags: 0, stream_id: 0),
      GoawayFrame(last_stream_id: 5, error_code: 0, debug_data: <<>>),
    )

  case connection.handle_frame(conn, goaway_frame) {
    connection.HandleOk(new_conn, _frames) -> {
      connection.is_going_away(new_conn) |> should.be_true()
      connection.get_last_stream_id(new_conn) |> should.equal(5)
    }
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Window Update Frame Handling Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn handle_window_update_connection_level_test() {
  let conn = connection.new_server()

  let window_update =
    WindowUpdateF(
      FrameHeader(length: 4, frame_type: WindowUpdate, flags: 0, stream_id: 0),
      WindowUpdateFrame(window_size_increment: 32_768),
    )

  case connection.handle_frame(conn, window_update) {
    connection.HandleOk(_new_conn, _frames) -> should.be_true(True)
    connection.HandleError(_, _) -> should.fail()
    _ -> should.fail()
  }
}

pub fn handle_window_update_stream_level_test() {
  let conn = connection.new_server()

  let window_update =
    WindowUpdateF(
      FrameHeader(length: 4, frame_type: WindowUpdate, flags: 0, stream_id: 1),
      WindowUpdateFrame(window_size_increment: 16_384),
    )

  case connection.handle_frame(conn, window_update) {
    connection.HandleOk(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CONTINUATION Frame Handling Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn continuation_completes_headers_test() {
  let conn = connection.new_server()

  // Encode a small header list and split the block in two so it must be
  // delivered as HEADERS (no END_HEADERS) + CONTINUATION (END_HEADERS).
  let header_fields = [
    hpack_encoder.HeaderField(name: ":method", value: "GET"),
    hpack_encoder.HeaderField(name: ":path", value: "/"),
  ]
  let assert Ok(#(full_block, _)) =
    hpack_encoder.encode_headers(
      hpack_encoder.new_encoder(4096, True),
      header_fields,
    )

  let total = bit_array.byte_size(full_block)
  let split = total / 2
  let assert Ok(first_part) = bit_array.slice(full_block, 0, split)
  let assert Ok(second_part) = bit_array.slice(full_block, split, total - split)

  // HEADERS with END_STREAM but WITHOUT END_HEADERS
  let headers_frame =
    HeadersF(
      FrameHeader(
        length: bit_array.byte_size(first_part),
        frame_type: Headers,
        flags: flag_end_stream,
        stream_id: 1,
      ),
      HeadersFrame(
        pad_length: 0,
        has_priority: False,
        stream_dependency: 0,
        exclusive: False,
        weight: 16,
        header_block: first_part,
      ),
    )

  case connection.handle_frame(conn, headers_frame) {
    connection.HandleOk(conn2, _frames) -> {
      // Should be pending, waiting on CONTINUATION
      connection.pending_request_count(conn2) |> should.equal(1)

      let continuation_frame =
        ContinuationF(
          FrameHeader(
            length: bit_array.byte_size(second_part),
            frame_type: Continuation,
            flags: flag_end_headers,
            stream_id: 1,
          ),
          ContinuationFrame(header_block: second_part),
        )

      case connection.handle_frame(conn2, continuation_frame) {
        connection.RequestComplete(conn3, stream_id, headers, body) -> {
          stream_id |> should.equal(1)
          headers |> should.equal([#(":method", "GET"), #(":path", "/")])
          body |> should.equal(<<>>)
          connection.pending_request_count(conn3) |> should.equal(0)
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn continuation_without_pending_headers_is_protocol_error_test() {
  let conn = connection.new_server()

  let continuation_frame =
    ContinuationF(
      FrameHeader(
        length: 0,
        frame_type: Continuation,
        flags: flag_end_headers,
        stream_id: 1,
      ),
      ContinuationFrame(header_block: <<>>),
    )

  case connection.handle_frame(conn, continuation_frame) {
    connection.HandleError(_conn, error) -> {
      case error {
        http2_error.Protocol(code, _message) ->
          code |> should.equal(http2_error.ProtocolError)
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// DATA Frame / Flow Control Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn data_over_threshold_flushes_window_update_test() {
  let conn = connection.new_server()

  // Set up a pending request (HEADERS, no END_STREAM) so DATA has somewhere
  // to accumulate.
  let assert Ok(#(header_block, _)) =
    hpack_encoder.encode_headers(hpack_encoder.new_encoder(4096, True), [
      hpack_encoder.HeaderField(name: ":method", value: "POST"),
    ])

  let headers_frame =
    HeadersF(
      FrameHeader(
        length: bit_array.byte_size(header_block),
        frame_type: Headers,
        flags: flag_end_headers,
        stream_id: 1,
      ),
      HeadersFrame(
        pad_length: 0,
        has_priority: False,
        stream_dependency: 0,
        exclusive: False,
        weight: 16,
        header_block: header_block,
      ),
    )

  let assert connection.HandleOk(conn1, _) =
    connection.handle_frame(conn, headers_frame)

  // Feed DATA frames totalling more than 65535 bytes across multiple frames
  // (none of them carrying END_STREAM) and confirm a WINDOW_UPDATE surfaces.
  let chunk = make_bytes(20_000)
  let #(_final_conn, saw_update) =
    feed_data_frames(conn1, 1, [chunk, chunk, chunk, chunk], False)

  saw_update |> should.be_true()
}

fn feed_data_frames(
  conn: connection.Connection,
  stream_id: Int,
  chunks: List(BitArray),
  saw_update: Bool,
) -> #(connection.Connection, Bool) {
  case chunks {
    [] -> #(conn, saw_update)
    [chunk, ..rest] -> {
      let data_frame =
        DataF(
          FrameHeader(
            length: bit_array.byte_size(chunk),
            frame_type: Data,
            flags: 0,
            stream_id: stream_id,
          ),
          DataFrame(pad_length: 0, data: chunk),
        )

      case connection.handle_frame(conn, data_frame) {
        connection.HandleOk(new_conn, frames) -> {
          let has_update = contains_window_update(frames)
          feed_data_frames(new_conn, stream_id, rest, saw_update || has_update)
        }
        connection.HandleError(_, _) -> {
          should.fail()
          #(conn, saw_update)
        }
        _ -> {
          should.fail()
          #(conn, saw_update)
        }
      }
    }
  }
}

fn contains_window_update(frames: List(frame.Frame)) -> Bool {
  case frames {
    [] -> False
    [WindowUpdateF(_, _), ..] -> True
    [_, ..rest] -> contains_window_update(rest)
  }
}

fn make_bytes(size: Int) -> BitArray {
  bit_array.from_string(string.repeat("a", size))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Default Settings Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn default_settings_values_test() {
  let settings = connection.default_settings()

  settings.header_table_size |> should.equal(4096)
  settings.enable_push |> should.be_true()
  settings.max_concurrent_streams |> should.equal(100)
  settings.initial_window_size |> should.equal(65_535)
  settings.max_frame_size |> should.equal(16_384)
  settings.max_header_list_size |> should.equal(16_384)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build Response Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_response_no_body_test() {
  let conn = connection.new_server()

  let #(_new_conn, frames) =
    connection.build_response(
      conn,
      1,
      // stream_id
      200,
      // status
      [#("content-type", "text/plain")],
      <<>>,
      // empty body
    )

  // Should have only HEADERS frame (no body)
  list_length(frames) |> should.equal(1)

  case frames {
    [HeadersF(header, _payload)] -> {
      header.stream_id |> should.equal(1)
    }
    _ -> should.fail()
  }
}

pub fn build_response_with_body_test() {
  let conn = connection.new_server()

  let body = <<"Hello, World!":utf8>>
  let #(_new_conn, frames) =
    connection.build_response(
      conn,
      1,
      // stream_id
      200,
      // status
      [#("content-type", "text/plain")],
      body,
    )

  // Should have HEADERS + DATA frames
  list_length(frames) |> should.equal(2)

  case frames {
    [HeadersF(_, _), DataF(header, payload)] -> {
      header.stream_id |> should.equal(1)
      payload.data |> should.equal(body)
    }
    _ -> should.fail()
  }
}

pub fn build_response_chunks_large_body_test() {
  let conn = connection.new_server()

  // 40 KiB body: with the default 16384 max_frame_size this must split into
  // three DATA frames of 16384 + 16384 + 8192 bytes.
  let body_size = 40_960
  let body = make_bytes(body_size)

  let #(_new_conn, frames) = connection.build_response(conn, 1, 200, [], body)

  // 1 HEADERS + 3 DATA frames
  list_length(frames) |> should.equal(4)

  case frames {
    [HeadersF(_, _), DataF(h1, p1), DataF(h2, p2), DataF(h3, p3)] -> {
      bit_array.byte_size(p1.data) |> should.equal(16_384)
      bit_array.byte_size(p2.data) |> should.equal(16_384)
      bit_array.byte_size(p3.data) |> should.equal(8192)

      h1.length |> should.equal(16_384)
      h2.length |> should.equal(16_384)
      h3.length |> should.equal(8192)

      // Every frame must respect the max frame size
      { h1.length <= 16_384 } |> should.be_true()
      { h2.length <= 16_384 } |> should.be_true()
      { h3.length <= 16_384 } |> should.be_true()

      // END_STREAM only on the last DATA frame
      frame.has_flag(h1.flags, flag_end_stream) |> should.be_false()
      frame.has_flag(h2.flags, flag_end_stream) |> should.be_false()
      frame.has_flag(h3.flags, flag_end_stream) |> should.be_true()

      // Reassembled body should match the original
      bit_array.concat([p1.data, p2.data, p3.data]) |> should.equal(body)
    }
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection to_string Test
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn connection_to_string_test() {
  let conn = connection.new_server()
  let str = connection.to_string(conn)

  // Should contain key info
  str |> should_contain("Connection(")
  str |> should_contain("role=server")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn list_length(items: List(a)) -> Int {
  list_length_acc(items, 0)
}

fn list_length_acc(items: List(a), acc: Int) -> Int {
  case items {
    [] -> acc
    [_, ..rest] -> list_length_acc(rest, acc + 1)
  }
}

fn should_contain(haystack: String, needle: String) -> Nil {
  case string_contains(haystack, needle) {
    True -> Nil
    False -> should.fail()
  }
}

fn string_contains(haystack: String, needle: String) -> Bool {
  // Simple contains check
  do_string_contains(haystack, needle, 0)
}

fn do_string_contains(haystack: String, needle: String, pos: Int) -> Bool {
  case haystack {
    "" -> False
    _ -> {
      case string_starts_with(haystack, needle) {
        True -> True
        False -> {
          case string_tail(haystack) {
            "" -> False
            rest -> do_string_contains(rest, needle, pos + 1)
          }
        }
      }
    }
  }
}

fn string_starts_with(str: String, prefix: String) -> Bool {
  case str, prefix {
    _, "" -> True
    "", _ -> False
    _, _ -> {
      // Use simple comparison
      string_slice(str, 0, string_length(prefix)) == prefix
    }
  }
}

@external(erlang, "string", "slice")
fn string_slice(str: String, start: Int, length: Int) -> String

@external(erlang, "string", "length")
fn string_length(str: String) -> Int

fn string_tail(str: String) -> String {
  string_slice(str, 1, string_length(str) - 1)
}
