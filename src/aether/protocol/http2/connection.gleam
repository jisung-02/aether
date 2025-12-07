// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Connection Handler Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Manages HTTP/2 connections, handling stream multiplexing,
// request dispatch, and response assembly.
//
// This module provides the core connection management for HTTP/2,
// coordinating between the frame layer and the application layer.
//

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import aether/protocol/http2/error as http2_error
import aether/protocol/http2/flow_control.{type FlowController}
import aether/protocol/http2/frame.{
  type Frame, DataF, GoawayF, HeadersF, PingF, RstStreamF, SettingsF,
  WindowUpdateF, default_initial_window_size, default_max_frame_size,
  flag_end_headers, flag_end_stream,
}
import aether/protocol/http2/frame_builder
import aether/protocol/http2/hpack/decoder as hpack_decoder
import aether/protocol/http2/hpack/encoder as hpack_encoder
import aether/protocol/http2/stream_manager.{type Role, type StreamManager}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// HTTP/2 connection state
///
pub type Connection {
  Connection(
    /// Role: Client or Server
    role: Role,
    /// Stream manager
    stream_manager: StreamManager,
    /// Flow controller
    flow_controller: FlowController,
    /// HPACK decoder
    hpack_decoder: hpack_decoder.DecoderState,
    /// HPACK encoder
    hpack_encoder: hpack_encoder.EncoderState,
    /// Local settings
    local_settings: ConnectionSettings,
    /// Remote settings (peer's advertised settings)
    remote_settings: ConnectionSettings,
    /// Connection preface received
    preface_received: Bool,
    /// Connection preface sent
    preface_sent: Bool,
    /// Pending incoming requests (stream_id -> accumulated data)
    pending_requests: Dict(Int, PendingRequest),
    /// Last received stream ID (for GOAWAY)
    last_stream_id: Int,
    /// Connection going away
    going_away: Bool,
    /// GOAWAY error code (if going away)
    goaway_error: Int,
  )
}

/// Connection settings (RFC 9113 Section 6.5.2)
///
pub type ConnectionSettings {
  ConnectionSettings(
    /// SETTINGS_HEADER_TABLE_SIZE (0x01)
    header_table_size: Int,
    /// SETTINGS_ENABLE_PUSH (0x02)
    enable_push: Bool,
    /// SETTINGS_MAX_CONCURRENT_STREAMS (0x03)
    max_concurrent_streams: Int,
    /// SETTINGS_INITIAL_WINDOW_SIZE (0x04)
    initial_window_size: Int,
    /// SETTINGS_MAX_FRAME_SIZE (0x05)
    max_frame_size: Int,
    /// SETTINGS_MAX_HEADER_LIST_SIZE (0x06)
    max_header_list_size: Int,
  )
}

/// Pending request being assembled from frames
///
pub type PendingRequest {
  PendingRequest(
    /// Stream ID
    stream_id: Int,
    /// Accumulated headers
    headers: List(#(String, String)),
    /// Header block fragments (for CONTINUATION)
    header_fragments: BitArray,
    /// Headers complete (END_HEADERS received)
    headers_complete: Bool,
    /// Accumulated body data
    body: BitArray,
    /// END_STREAM received
    end_stream: Bool,
  )
}

/// Result of handling an incoming frame
///
pub type HandleResult {
  /// No action needed
  HandleOk(connection: Connection)
  /// Request is complete and ready for dispatch
  RequestComplete(connection: Connection, stream_id: Int, headers: List(#(String, String)), body: BitArray)
  /// Response frames to send
  SendFrames(connection: Connection, frames: List(Frame))
  /// Connection error occurred
  HandleError(connection: Connection, error: http2_error.ConnectionError)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Constructors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Default connection settings
///
pub fn default_settings() -> ConnectionSettings {
  ConnectionSettings(
    header_table_size: 4096,
    enable_push: True,
    max_concurrent_streams: 100,
    initial_window_size: default_initial_window_size,
    max_frame_size: default_max_frame_size,
    max_header_list_size: 16_384,
  )
}

/// Creates a new server connection
///
pub fn new_server() -> Connection {
  Connection(
    role: stream_manager.Server,
    stream_manager: stream_manager.new_server(),
    flow_controller: flow_control.new(),
    hpack_decoder: hpack_decoder.new_decoder(4096),
    hpack_encoder: hpack_encoder.new_encoder(4096, True),
    local_settings: default_settings(),
    remote_settings: default_settings(),
    preface_received: False,
    preface_sent: False,
    pending_requests: dict.new(),
    last_stream_id: 0,
    going_away: False,
    goaway_error: 0,
  )
}

/// Creates a new client connection
///
pub fn new_client() -> Connection {
  Connection(
    role: stream_manager.Client,
    stream_manager: stream_manager.new_client(),
    flow_controller: flow_control.new(),
    hpack_decoder: hpack_decoder.new_decoder(4096),
    hpack_encoder: hpack_encoder.new_encoder(4096, True),
    local_settings: default_settings(),
    remote_settings: default_settings(),
    preface_received: False,
    preface_sent: False,
    pending_requests: dict.new(),
    last_stream_id: 0,
    going_away: False,
    goaway_error: 0,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Handling
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Handles an incoming frame
///
pub fn handle_frame(conn: Connection, frame: Frame) -> HandleResult {
  case frame {
    HeadersF(header, payload) -> handle_headers(conn, header, payload)
    DataF(header, payload) -> handle_data(conn, header, payload)
    SettingsF(header, payload) -> handle_settings(conn, header, payload)
    PingF(header, payload) -> handle_ping(conn, header, payload)
    WindowUpdateF(header, payload) -> handle_window_update(conn, header, payload)
    RstStreamF(header, payload) -> handle_rst_stream(conn, header, payload)
    GoawayF(header, payload) -> handle_goaway(conn, header, payload)
    _ -> HandleOk(connection: conn)
  }
}

/// Handles HEADERS frame
///
fn handle_headers(
  conn: Connection,
  header: frame.FrameHeader,
  payload: frame.HeadersFrame,
) -> HandleResult {
  let stream_id = header.stream_id
  let end_headers = frame.has_flag(header.flags, flag_end_headers)
  let end_stream = frame.has_flag(header.flags, flag_end_stream)

  // Decode headers using HPACK
  case hpack_decoder.decode_header_block(conn.hpack_decoder, payload.header_block) {
    Ok(#(headers, new_decoder)) -> {
      let new_conn = Connection(..conn, hpack_decoder: new_decoder)

      // Convert headers to tuples
      let header_tuples = list.map(headers, fn(h) { #(h.name, h.value) })

      case end_headers {
        True -> {
          // Headers complete
          case end_stream {
            True -> {
              // Complete request with no body
              RequestComplete(
                connection: new_conn,
                stream_id: stream_id,
                headers: header_tuples,
                body: <<>>,
              )
            }
            False -> {
              // More data coming
              let pending = PendingRequest(
                stream_id: stream_id,
                headers: header_tuples,
                header_fragments: <<>>,
                headers_complete: True,
                body: <<>>,
                end_stream: False,
              )
              HandleOk(connection: Connection(
                ..new_conn,
                pending_requests: dict.insert(new_conn.pending_requests, stream_id, pending),
              ))
            }
          }
        }
        False -> {
          // Need CONTINUATION frames
          let pending = PendingRequest(
            stream_id: stream_id,
            headers: header_tuples,
            header_fragments: payload.header_block,
            headers_complete: False,
            body: <<>>,
            end_stream: end_stream,
          )
          HandleOk(connection: Connection(
            ..new_conn,
            pending_requests: dict.insert(new_conn.pending_requests, stream_id, pending),
          ))
        }
      }
    }
    Error(_) -> {
      HandleError(connection: conn, error: http2_error.Compression("HPACK decode error"))
    }
  }
}

/// Handles DATA frame
///
fn handle_data(
  conn: Connection,
  header: frame.FrameHeader,
  payload: frame.DataFrame,
) -> HandleResult {
  let stream_id = header.stream_id
  let end_stream = frame.has_flag(header.flags, flag_end_stream)

  // Update flow control
  let data_size = bit_array.byte_size(payload.data)
  case flow_control.consume_recv_window(conn.flow_controller, data_size) {
    Ok(new_fc) -> {
      let new_conn = Connection(..conn, flow_controller: new_fc)

      case dict.get(new_conn.pending_requests, stream_id) {
        Ok(pending) -> {
          let new_body = bit_array.append(pending.body, payload.data)
          case end_stream {
            True -> {
              // Complete request
              let new_pending = dict.delete(new_conn.pending_requests, stream_id)
              RequestComplete(
                connection: Connection(..new_conn, pending_requests: new_pending),
                stream_id: stream_id,
                headers: pending.headers,
                body: new_body,
              )
            }
            False -> {
              // More data coming
              let updated_pending = PendingRequest(..pending, body: new_body)
              HandleOk(connection: Connection(
                ..new_conn,
                pending_requests: dict.insert(new_conn.pending_requests, stream_id, updated_pending),
              ))
            }
          }
        }
        Error(_) -> {
          // DATA on unknown stream
          HandleError(connection: new_conn, error: http2_error.Protocol(http2_error.StreamClosed, "DATA on unknown stream"))
        }
      }
    }
    Error(_err) -> {
      HandleError(connection: conn, error: http2_error.FlowControl("Recv window exceeded"))
    }
  }
}

/// Handles SETTINGS frame
///
fn handle_settings(
  conn: Connection,
  header: frame.FrameHeader,
  payload: frame.SettingsFrame,
) -> HandleResult {
  case payload.ack {
    True -> {
      // ACK - settings acknowledged
      HandleOk(connection: conn)
    }
    False -> {
      // Apply settings and send ACK
      let new_settings = apply_settings(conn.remote_settings, payload.parameters)
      let new_conn = Connection(
        ..conn,
        remote_settings: new_settings,
        preface_received: True,
      )

      // Build SETTINGS ACK frame
      let ack_header = frame.FrameHeader(
        length: 0,
        frame_type: frame.Settings,
        flags: frame.flag_ack,
        stream_id: 0,
      )
      let ack_frame = SettingsF(ack_header, frame.SettingsFrame(ack: True, parameters: []))
      SendFrames(connection: new_conn, frames: [ack_frame])
    }
  }
}

/// Applies settings parameters
///
fn apply_settings(
  settings: ConnectionSettings,
  params: List(frame.SettingsParameter),
) -> ConnectionSettings {
  list.fold(params, settings, fn(s, p) {
    case p.identifier {
      frame.HeaderTableSize -> ConnectionSettings(..s, header_table_size: p.value)
      frame.EnablePush ->
        ConnectionSettings(..s, enable_push: p.value != 0)
      frame.MaxConcurrentStreams ->
        ConnectionSettings(..s, max_concurrent_streams: p.value)
      frame.InitialWindowSize ->
        ConnectionSettings(..s, initial_window_size: p.value)
      frame.MaxFrameSize -> ConnectionSettings(..s, max_frame_size: p.value)
      frame.MaxHeaderListSize ->
        ConnectionSettings(..s, max_header_list_size: p.value)
      _ -> s
    }
  })
}

/// Handles PING frame
///
fn handle_ping(
  conn: Connection,
  header: frame.FrameHeader,
  payload: frame.PingFrame,
) -> HandleResult {
  case payload.ack {
    True -> {
      // PING ACK received
      HandleOk(connection: conn)
    }
    False -> {
      // Send PING ACK
      let ack_header = frame.FrameHeader(
        length: 8,
        frame_type: frame.Ping,
        flags: frame.flag_ack,
        stream_id: 0,
      )
      let ack_frame = PingF(ack_header, frame.PingFrame(ack: True, opaque_data: payload.opaque_data))
      SendFrames(connection: conn, frames: [ack_frame])
    }
  }
}

/// Handles WINDOW_UPDATE frame
///
fn handle_window_update(
  conn: Connection,
  header: frame.FrameHeader,
  payload: frame.WindowUpdateFrame,
) -> HandleResult {
  let stream_id = header.stream_id

  case stream_id {
    0 -> {
      // Connection-level window update
      case flow_control.handle_connection_window_update(
        conn.flow_controller,
        payload.window_size_increment,
      ) {
        Ok(new_fc) -> HandleOk(connection: Connection(..conn, flow_controller: new_fc))
        Error(_) -> HandleError(connection: conn, error: http2_error.FlowControl("Window update overflow"))
      }
    }
    _ -> {
      // Stream-level window update (handled by stream manager)
      HandleOk(connection: conn)
    }
  }
}

/// Handles RST_STREAM frame
///
fn handle_rst_stream(
  conn: Connection,
  header: frame.FrameHeader,
  payload: frame.RstStreamFrame,
) -> HandleResult {
  let stream_id = header.stream_id
  // Remove pending request for this stream
  let new_pending = dict.delete(conn.pending_requests, stream_id)
  HandleOk(connection: Connection(..conn, pending_requests: new_pending))
}

/// Handles GOAWAY frame
///
fn handle_goaway(
  conn: Connection,
  header: frame.FrameHeader,
  payload: frame.GoawayFrame,
) -> HandleResult {
  HandleOk(connection: Connection(
    ..conn,
    going_away: True,
    goaway_error: payload.error_code,
    last_stream_id: payload.last_stream_id,
  ))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Response Building
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds response frames for a given stream
///
pub fn build_response(
  conn: Connection,
  stream_id: Int,
  status: Int,
  headers: List(#(String, String)),
  body: BitArray,
) -> #(Connection, List(Frame)) {
  // Build header list with :status pseudo-header
  let all_headers = [#(":status", int.to_string(status)), ..headers]

  // Encode headers using HPACK
  let header_fields =
    list.map(all_headers, fn(h) {
      hpack_encoder.HeaderField(name: h.0, value: h.1)
    })

  case hpack_encoder.encode_headers(conn.hpack_encoder, header_fields) {
    Ok(#(header_block, new_encoder)) -> {
      let new_conn = Connection(..conn, hpack_encoder: new_encoder)

      // Build HEADERS frame
      let header_block_size = bit_array.byte_size(header_block)
      let end_stream_flag = case bit_array.byte_size(body) == 0 {
        True -> frame.flag_end_stream
        False -> 0
      }
      let headers_header = frame.FrameHeader(
        length: header_block_size,
        frame_type: frame.Headers,
        flags: int.bitwise_or(frame.flag_end_headers, end_stream_flag),
        stream_id: stream_id,
      )
      let headers_frame = HeadersF(headers_header, frame.HeadersFrame(
        pad_length: 0,
        has_priority: False,
        stream_dependency: 0,
        exclusive: False,
        weight: 16,
        header_block: header_block,
      ))

      case bit_array.byte_size(body) > 0 {
        True -> {
          // Build DATA frame
          let body_size = bit_array.byte_size(body)
          let data_header = frame.FrameHeader(
            length: body_size,
            frame_type: frame.Data,
            flags: frame.flag_end_stream,
            stream_id: stream_id,
          )
          let data_frame = DataF(data_header, frame.DataFrame(pad_length: 0, data: body))
          #(new_conn, [headers_frame, data_frame])
        }
        False -> {
          #(new_conn, [headers_frame])
        }
      }
    }
    Error(_) -> {
      // Encoding error - return empty frames
      #(conn, [])
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection State Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks if connection is going away
///
pub fn is_going_away(conn: Connection) -> Bool {
  conn.going_away
}

/// Gets the last stream ID
///
pub fn get_last_stream_id(conn: Connection) -> Int {
  conn.last_stream_id
}

/// Gets the number of pending requests
///
pub fn pending_request_count(conn: Connection) -> Int {
  dict.size(conn.pending_requests)
}

/// Marks preface as sent
///
pub fn mark_preface_sent(conn: Connection) -> Connection {
  Connection(..conn, preface_sent: True)
}

/// Marks preface as received
///
pub fn mark_preface_received(conn: Connection) -> Connection {
  Connection(..conn, preface_received: True)
}

/// Checks if preface handshake is complete
///
pub fn is_preface_complete(conn: Connection) -> Bool {
  conn.preface_sent && conn.preface_received
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Debug Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts connection to string for debugging
///
pub fn to_string(conn: Connection) -> String {
  "Connection("
  <> "role="
  <> case conn.role {
    stream_manager.Server -> "server"
    stream_manager.Client -> "client"
  }
  <> ", pending="
  <> int.to_string(pending_request_count(conn))
  <> ", preface_sent="
  <> case conn.preface_sent {
    True -> "true"
    False -> "false"
  }
  <> ", preface_recv="
  <> case conn.preface_received {
    True -> "true"
    False -> "false"
  }
  <> ", going_away="
  <> case conn.going_away {
    True -> "true"
    False -> "false"
  }
  <> ")"
}
