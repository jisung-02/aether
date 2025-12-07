// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Stage Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides HTTP/2 decoder and encoder stages for pipeline integration.
// Integrates the HTTP/2 frame layer with Aether's pipeline system.
//
// This module bridges the low-level HTTP/2 framing (frames, streams,
// flow control) with the high-level pipeline abstraction.
//

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import aether/core/data.{type Data}
import aether/core/message
import aether/pipeline/error.{ProcessingError}
import aether/pipeline/stage.{type Stage}
import aether/protocol/protocol.{type Protocol}
import aether/protocol/registry.{type Registry}

import aether/protocol/http2/error as http2_error
import aether/protocol/http2/flow_control.{type FlowController}
import aether/protocol/http2/frame.{
  type Frame, DataF, GoawayF, HeadersF,
  PingF, RstStreamF, SettingsF,
  WindowUpdateF, ContinuationF, PriorityF, PushPromiseF, UnknownF,
  default_max_frame_size,
}
import aether/protocol/http2/frame_builder
import aether/protocol/http2/frame_parser
import aether/protocol/http2/hpack/decoder as hpack_decoder
import aether/protocol/http2/hpack/encoder as hpack_encoder
import aether/protocol/http2/stream_manager.{type Role, type StreamManager}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// FFI for Type Coercion
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@external(erlang, "erlang", "hd")
fn coerce_via_hd(list: List(a)) -> b

fn to_dynamic(value: a) -> Dynamic {
  coerce_via_hd([value])
}

fn from_dynamic(value: Dynamic) -> a {
  coerce_via_hd([value])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// HTTP/2 connection state for pipeline stages
///
pub type Http2ConnectionState {
  Http2ConnectionState(
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
    /// Max frame size
    max_frame_size: Int,
    /// Connection preface received
    preface_received: Bool,
    /// Connection preface sent
    preface_sent: Bool,
  )
}

/// HTTP/2 request data container for pipeline stages
///
pub type Http2RequestData {
  Http2RequestData(
    /// Stream ID
    stream_id: Int,
    /// HTTP/2 headers (pseudo-headers + regular headers)
    headers: List(#(String, String)),
    /// Request body (accumulated from DATA frames)
    body: BitArray,
    /// END_STREAM received
    end_stream: Bool,
    /// Trailers (if any)
    trailers: Option(List(#(String, String))),
  )
}

/// HTTP/2 response data container for pipeline stages
///
pub type Http2ResponseData {
  Http2ResponseData(
    /// Stream ID
    stream_id: Int,
    /// HTTP/2 status (from :status pseudo-header)
    status: Int,
    /// HTTP/2 headers
    headers: List(#(String, String)),
    /// Response body
    body: BitArray,
    /// END_STREAM to send
    end_stream: Bool,
  )
}

/// Decoded HTTP/2 frame with metadata
///
pub type DecodedFrame {
  DecodedFrame(
    /// The parsed frame
    frame: Frame,
    /// Stream ID
    stream_id: Int,
    /// Frame flags
    flags: Int,
    /// Remaining bytes after this frame
    remaining: BitArray,
  )
}

/// Metadata keys for HTTP/2 stage data
///
pub const state_metadata_key = "http2:state"

pub const request_metadata_key = "http2:request"

pub const response_metadata_key = "http2:response"

pub const frame_metadata_key = "http2:frame"

pub const frames_metadata_key = "http2:frames"

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection State Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new HTTP/2 connection state for a server
///
pub fn new_server_state() -> Http2ConnectionState {
  Http2ConnectionState(
    role: stream_manager.Server,
    stream_manager: stream_manager.new_server(),
    flow_controller: flow_control.new(),
    hpack_decoder: hpack_decoder.new_decoder(4096),
    hpack_encoder: hpack_encoder.new_encoder(4096, True),
    max_frame_size: default_max_frame_size,
    preface_received: False,
    preface_sent: False,
  )
}

/// Creates a new HTTP/2 connection state for a client
///
pub fn new_client_state() -> Http2ConnectionState {
  Http2ConnectionState(
    role: stream_manager.Client,
    stream_manager: stream_manager.new_client(),
    flow_controller: flow_control.new(),
    hpack_decoder: hpack_decoder.new_decoder(4096),
    hpack_encoder: hpack_encoder.new_encoder(4096, True),
    max_frame_size: default_max_frame_size,
    preface_received: False,
    preface_sent: False,
  )
}

/// Gets the connection state from Data metadata
///
pub fn get_state(data: Data) -> Option(Http2ConnectionState) {
  case message.get_metadata(data, state_metadata_key) {
    Some(state_dynamic) -> {
      let state: Http2ConnectionState = from_dynamic(state_dynamic)
      Some(state)
    }
    None -> None
  }
}

/// Sets the connection state in Data metadata
///
pub fn set_state(data: Data, state: Http2ConnectionState) -> Data {
  message.set_metadata(data, state_metadata_key, to_dynamic(state))
}

/// Gets the HTTP/2 request data from Data metadata
///
pub fn get_request(data: Data) -> Option(Http2RequestData) {
  case message.get_metadata(data, request_metadata_key) {
    Some(req_dynamic) -> {
      let req: Http2RequestData = from_dynamic(req_dynamic)
      Some(req)
    }
    None -> None
  }
}

/// Sets the HTTP/2 request data in Data metadata
///
pub fn set_request(data: Data, request: Http2RequestData) -> Data {
  message.set_metadata(data, request_metadata_key, to_dynamic(request))
}

/// Gets the HTTP/2 response data from Data metadata
///
pub fn get_response(data: Data) -> Option(Http2ResponseData) {
  case message.get_metadata(data, response_metadata_key) {
    Some(resp_dynamic) -> {
      let resp: Http2ResponseData = from_dynamic(resp_dynamic)
      Some(resp)
    }
    None -> None
  }
}

/// Sets the HTTP/2 response data in Data metadata
///
pub fn set_response(data: Data, response: Http2ResponseData) -> Data {
  message.set_metadata(data, response_metadata_key, to_dynamic(response))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Extracts stream ID and flags from a Frame
///
fn extract_frame_info(frame: Frame) -> #(Int, Int) {
  case frame {
    DataF(header, _) -> #(header.stream_id, header.flags)
    HeadersF(header, _) -> #(header.stream_id, header.flags)
    PriorityF(header, _) -> #(header.stream_id, header.flags)
    RstStreamF(header, _) -> #(header.stream_id, header.flags)
    SettingsF(header, _) -> #(header.stream_id, header.flags)
    PushPromiseF(header, _) -> #(header.stream_id, header.flags)
    PingF(header, _) -> #(header.stream_id, header.flags)
    GoawayF(header, _) -> #(header.stream_id, header.flags)
    WindowUpdateF(header, _) -> #(header.stream_id, header.flags)
    ContinuationF(header, _) -> #(header.stream_id, header.flags)
    UnknownF(header, _) -> #(header.stream_id, header.flags)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Decoding Stage
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates an HTTP/2 frame decoder stage
///
/// This stage parses raw bytes into HTTP/2 frames.
/// Multiple frames may be parsed from a single input.
///
pub fn decode_frame() -> Stage(Data, Data) {
  stage.new("http2:decode_frame", fn(data: Data) {
    let bytes = message.bytes(data)

    case frame_parser.parse_frame(bytes) {
      Ok(parse_result) -> {
        let frame = parse_result.frame
        let remaining = parse_result.remaining
        let #(stream_id, flags) = extract_frame_info(frame)

        let decoded =
          DecodedFrame(
            frame: frame,
            stream_id: stream_id,
            flags: flags,
            remaining: remaining,
          )

        data
        |> message.set_metadata(frame_metadata_key, to_dynamic(decoded))
        |> message.set_bytes(remaining)
        |> Ok
      }
      Error(parse_error) -> {
        Error(ProcessingError(
          "HTTP/2 frame parse error: "
            <> http2_error.parse_error_to_string(parse_error),
          None,
        ))
      }
    }
  })
}

/// Gets the decoded frame from Data metadata
///
pub fn get_decoded_frame(data: Data) -> Option(DecodedFrame) {
  case message.get_metadata(data, frame_metadata_key) {
    Some(frame_dynamic) -> {
      let decoded: DecodedFrame = from_dynamic(frame_dynamic)
      Some(decoded)
    }
    None -> None
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Encoding Stage
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates an HTTP/2 frame encoder stage
///
/// This stage builds raw bytes from HTTP/2 frames stored in metadata.
///
pub fn encode_frame() -> Stage(Data, Data) {
  stage.new("http2:encode_frame", fn(data: Data) {
    case get_frames_to_send(data) {
      Some(frames) -> {
        let bytes = encode_frames_to_bytes(frames)
        data
        |> message.set_bytes(bytes)
        |> Ok
      }
      None -> {
        Error(ProcessingError("No HTTP/2 frames to encode", None))
      }
    }
  })
}

/// Encodes a list of frames to bytes
///
fn encode_frames_to_bytes(frames: List(Frame)) -> BitArray {
  frames
  |> list.map(frame_builder.build_frame)
  |> bit_array.concat
}

/// Gets frames to send from Data metadata
///
pub fn get_frames_to_send(data: Data) -> Option(List(Frame)) {
  case message.get_metadata(data, frames_metadata_key) {
    Some(frames_dynamic) -> {
      let frames: List(Frame) = from_dynamic(frames_dynamic)
      Some(frames)
    }
    None -> None
  }
}

/// Sets frames to send in Data metadata
///
pub fn set_frames_to_send(data: Data, frames: List(Frame)) -> Data {
  message.set_metadata(data, frames_metadata_key, to_dynamic(frames))
}

/// Adds a frame to the list of frames to send
///
pub fn add_frame_to_send(data: Data, frame: Frame) -> Data {
  let current = case get_frames_to_send(data) {
    Some(frames) -> frames
    None -> []
  }
  set_frames_to_send(data, list.append(current, [frame]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Request Assembly Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new HTTP/2 request data
///
pub fn new_request_data(
  stream_id: Int,
  headers: List(#(String, String)),
) -> Http2RequestData {
  Http2RequestData(
    stream_id: stream_id,
    headers: headers,
    body: <<>>,
    end_stream: False,
    trailers: None,
  )
}

/// Appends body data to an HTTP/2 request
///
pub fn append_body(request: Http2RequestData, data: BitArray) -> Http2RequestData {
  Http2RequestData(
    ..request,
    body: bit_array.append(request.body, data),
  )
}

/// Marks the request as having received END_STREAM
///
pub fn mark_end_stream(request: Http2RequestData) -> Http2RequestData {
  Http2RequestData(..request, end_stream: True)
}

/// Adds trailers to the request
///
pub fn add_trailers(
  request: Http2RequestData,
  trailers: List(#(String, String)),
) -> Http2RequestData {
  Http2RequestData(..request, trailers: Some(trailers))
}

/// Gets the :method pseudo-header from request
///
pub fn get_method(request: Http2RequestData) -> Option(String) {
  list.find(request.headers, fn(h) { h.0 == ":method" })
  |> result.map(fn(h) { h.1 })
  |> option.from_result
}

/// Gets the :path pseudo-header from request
///
pub fn get_path(request: Http2RequestData) -> Option(String) {
  list.find(request.headers, fn(h) { h.0 == ":path" })
  |> result.map(fn(h) { h.1 })
  |> option.from_result
}

/// Gets the :scheme pseudo-header from request
///
pub fn get_scheme(request: Http2RequestData) -> Option(String) {
  list.find(request.headers, fn(h) { h.0 == ":scheme" })
  |> result.map(fn(h) { h.1 })
  |> option.from_result
}

/// Gets the :authority pseudo-header from request
///
pub fn get_authority(request: Http2RequestData) -> Option(String) {
  list.find(request.headers, fn(h) { h.0 == ":authority" })
  |> result.map(fn(h) { h.1 })
  |> option.from_result
}

/// Gets a regular header value
///
pub fn get_header(request: Http2RequestData, name: String) -> Option(String) {
  list.find(request.headers, fn(h) { h.0 == name })
  |> result.map(fn(h) { h.1 })
  |> option.from_result
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Response Building Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new HTTP/2 response data
///
pub fn new_response_data(
  stream_id: Int,
  status: Int,
) -> Http2ResponseData {
  Http2ResponseData(
    stream_id: stream_id,
    status: status,
    headers: [],
    body: <<>>,
    end_stream: True,
  )
}

/// Adds a header to the response
///
pub fn add_response_header(
  response: Http2ResponseData,
  name: String,
  value: String,
) -> Http2ResponseData {
  Http2ResponseData(
    ..response,
    headers: list.append(response.headers, [#(name, value)]),
  )
}

/// Sets the response body
///
pub fn set_response_body(
  response: Http2ResponseData,
  body: BitArray,
) -> Http2ResponseData {
  Http2ResponseData(..response, body: body)
}

/// Sets the response body from a string
///
pub fn set_response_string_body(
  response: Http2ResponseData,
  body: String,
) -> Http2ResponseData {
  Http2ResponseData(..response, body: bit_array.from_string(body))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Common Response Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a 200 OK response
///
pub fn ok_response(stream_id: Int) -> Http2ResponseData {
  new_response_data(stream_id, 200)
}

/// Creates a 404 Not Found response
///
pub fn not_found_response(stream_id: Int) -> Http2ResponseData {
  new_response_data(stream_id, 404)
  |> add_response_header("content-type", "text/plain")
  |> set_response_string_body("Not Found")
}

/// Creates a 500 Internal Server Error response
///
pub fn internal_error_response(stream_id: Int) -> Http2ResponseData {
  new_response_data(stream_id, 500)
  |> add_response_header("content-type", "text/plain")
  |> set_response_string_body("Internal Server Error")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol Definition
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates the HTTP/2 protocol definition
///
pub fn http2_protocol() -> Protocol {
  protocol.new("http2")
  |> protocol.with_tag("application")
  |> protocol.with_tag("layer7")
  |> protocol.with_tag("binary")
  |> protocol.with_tag("multiplexed")
  |> protocol.with_decoder(decode_frame())
  |> protocol.with_encoder(encode_frame())
  |> protocol.with_version("2.0")
  |> protocol.with_description("Hypertext Transfer Protocol Version 2")
  |> protocol.with_author("Aether")
}

/// Registers the HTTP/2 protocol in a registry
///
pub fn register_http2(reg: Registry) -> Registry {
  registry.register(reg, http2_protocol())
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Type Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks if a frame is a HEADERS frame
///
pub fn is_headers_frame(frame: Frame) -> Bool {
  case frame {
    HeadersF(_, _) -> True
    _ -> False
  }
}

/// Checks if a frame is a DATA frame
///
pub fn is_data_frame(frame: Frame) -> Bool {
  case frame {
    DataF(_, _) -> True
    _ -> False
  }
}

/// Checks if a frame is a SETTINGS frame
///
pub fn is_settings_frame(frame: Frame) -> Bool {
  case frame {
    SettingsF(_, _) -> True
    _ -> False
  }
}

/// Checks if a frame is a GOAWAY frame
///
pub fn is_goaway_frame(frame: Frame) -> Bool {
  case frame {
    GoawayF(_, _) -> True
    _ -> False
  }
}

/// Checks if a frame is a PING frame
///
pub fn is_ping_frame(frame: Frame) -> Bool {
  case frame {
    PingF(_, _) -> True
    _ -> False
  }
}

/// Checks if a frame is a WINDOW_UPDATE frame
///
pub fn is_window_update_frame(frame: Frame) -> Bool {
  case frame {
    WindowUpdateF(_, _) -> True
    _ -> False
  }
}

/// Checks if a frame is an RST_STREAM frame
///
pub fn is_rst_stream_frame(frame: Frame) -> Bool {
  case frame {
    RstStreamF(_, _) -> True
    _ -> False
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Debug Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts connection state to string for debugging
///
pub fn state_to_string(state: Http2ConnectionState) -> String {
  "Http2ConnectionState("
  <> "role="
  <> case state.role {
    stream_manager.Client -> "client"
    stream_manager.Server -> "server"
  }
  <> ", streams="
  <> int.to_string(stream_manager.active_count(state.stream_manager))
  <> ", preface_recv="
  <> case state.preface_received {
    True -> "true"
    False -> "false"
  }
  <> ", preface_sent="
  <> case state.preface_sent {
    True -> "true"
    False -> "false"
  }
  <> ")"
}

/// Converts request data to string for debugging
///
pub fn request_to_string(request: Http2RequestData) -> String {
  let method = case get_method(request) {
    Some(m) -> m
    None -> "?"
  }
  let path = case get_path(request) {
    Some(p) -> p
    None -> "?"
  }

  "Http2Request("
  <> "stream="
  <> int.to_string(request.stream_id)
  <> ", method="
  <> method
  <> ", path="
  <> path
  <> ", body_size="
  <> int.to_string(bit_array.byte_size(request.body))
  <> ", end_stream="
  <> case request.end_stream {
    True -> "true"
    False -> "false"
  }
  <> ")"
}

/// Converts response data to string for debugging
///
pub fn response_to_string(response: Http2ResponseData) -> String {
  "Http2Response("
  <> "stream="
  <> int.to_string(response.stream_id)
  <> ", status="
  <> int.to_string(response.status)
  <> ", body_size="
  <> int.to_string(bit_array.byte_size(response.body))
  <> ")"
}
