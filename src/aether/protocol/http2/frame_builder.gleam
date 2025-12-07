// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Serializes HTTP/2 frames to binary wire format as per RFC 9113.
// Handles the 9-byte frame header and all frame payload types.
//

import aether/protocol/http2/frame.{
  type ContinuationFrame, type DataFrame, type Frame, type FrameHeader,
  type GoawayFrame, type HeadersFrame, type PingFrame, type PriorityFrame,
  type PushPromiseFrame, type RstStreamFrame, type SettingsFrame,
  type SettingsParameter, type WindowUpdateFrame, Continuation, ContinuationF,
  ContinuationFrame, Data, DataF, DataFrame, FrameHeader, Goaway, GoawayF,
  GoawayFrame, Headers, HeadersF, HeadersFrame, Ping, PingF, PingFrame, Priority,
  PriorityF, PriorityFrame, PushPromise, PushPromiseF, PushPromiseFrame,
  RstStream, RstStreamF, RstStreamFrame, Settings, SettingsF, SettingsFrame,
  SettingsParameter, Unknown, UnknownF, WindowUpdate, WindowUpdateF,
  WindowUpdateFrame, flag_ack, flag_end_headers, flag_end_stream, flag_padded,
  flag_priority, frame_type_to_int, has_flag, settings_id_to_int,
}
import gleam/bit_array
import gleam/int
import gleam/list

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Main Builder Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds a complete HTTP/2 frame to binary format
///
pub fn build_frame(frame: Frame) -> BitArray {
  case frame {
    DataF(header, payload) -> build_data_frame(header, payload)
    HeadersF(header, payload) -> build_headers_frame(header, payload)
    PriorityF(header, payload) -> build_priority_frame(header, payload)
    RstStreamF(header, payload) -> build_rst_stream_frame(header, payload)
    SettingsF(header, payload) -> build_settings_frame(header, payload)
    PushPromiseF(header, payload) -> build_push_promise_frame(header, payload)
    PingF(header, payload) -> build_ping_frame(header, payload)
    GoawayF(header, payload) -> build_goaway_frame(header, payload)
    WindowUpdateF(header, payload) -> build_window_update_frame(header, payload)
    ContinuationF(header, payload) -> build_continuation_frame(header, payload)
    UnknownF(header, payload) -> build_unknown_frame(header, payload)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Header Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds the 9-byte frame header
///
pub fn build_header(header: FrameHeader) -> BitArray {
  let length_high =
    int.bitwise_and(int.bitwise_shift_right(header.length, 16), 0xFF)
  let length_mid =
    int.bitwise_and(int.bitwise_shift_right(header.length, 8), 0xFF)
  let length_low = int.bitwise_and(header.length, 0xFF)
  let frame_type = frame_type_to_int(header.frame_type)

  <<
    length_high:8,
    length_mid:8,
    length_low:8,
    frame_type:8,
    header.flags:8,
    0:1,
    header.stream_id:31,
  >>
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// DATA Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_data_frame(header: FrameHeader, payload: DataFrame) -> BitArray {
  case has_flag(header.flags, flag_padded) {
    False -> {
      // No padding
      let frame_header = build_header(header)
      bit_array.concat([frame_header, payload.data])
    }
    True -> {
      // With padding
      let padding = create_padding(payload.pad_length)
      let frame_header = build_header(header)
      bit_array.concat([
        frame_header,
        <<payload.pad_length:8>>,
        payload.data,
        padding,
      ])
    }
  }
}

/// Creates a DATA frame
///
pub fn create_data_frame(
  stream_id: Int,
  data: BitArray,
  end_stream: Bool,
) -> Frame {
  let flags = case end_stream {
    True -> flag_end_stream
    False -> 0
  }
  let header =
    FrameHeader(
      length: bit_array.byte_size(data),
      frame_type: Data,
      flags: flags,
      stream_id: stream_id,
    )
  DataF(header, DataFrame(pad_length: 0, data: data))
}

/// Creates a DATA frame with padding
///
pub fn create_data_frame_with_padding(
  stream_id: Int,
  data: BitArray,
  pad_length: Int,
  end_stream: Bool,
) -> Frame {
  let flags = case end_stream {
    True -> int.bitwise_or(flag_end_stream, flag_padded)
    False -> flag_padded
  }
  let total_length = 1 + bit_array.byte_size(data) + pad_length
  let header =
    FrameHeader(
      length: total_length,
      frame_type: Data,
      flags: flags,
      stream_id: stream_id,
    )
  DataF(header, DataFrame(pad_length: pad_length, data: data))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HEADERS Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_headers_frame(header: FrameHeader, payload: HeadersFrame) -> BitArray {
  let padded = has_flag(header.flags, flag_padded)
  let has_priority = has_flag(header.flags, flag_priority)

  let priority_data = case has_priority {
    False -> <<>>
    True -> {
      let exclusive_bit = case payload.exclusive {
        True -> 1
        False -> 0
      }
      let weight = payload.weight - 1
      <<exclusive_bit:1, payload.stream_dependency:31, weight:8>>
    }
  }

  let frame_header = build_header(header)

  case padded {
    False ->
      bit_array.concat([frame_header, priority_data, payload.header_block])
    True -> {
      let padding = create_padding(payload.pad_length)
      bit_array.concat([
        frame_header,
        <<payload.pad_length:8>>,
        priority_data,
        payload.header_block,
        padding,
      ])
    }
  }
}

/// Creates a HEADERS frame
///
pub fn create_headers_frame(
  stream_id: Int,
  header_block: BitArray,
  end_stream: Bool,
  end_headers: Bool,
) -> Frame {
  let flags =
    0
    |> set_flag_if(end_stream, flag_end_stream)
    |> set_flag_if(end_headers, flag_end_headers)

  let header =
    FrameHeader(
      length: bit_array.byte_size(header_block),
      frame_type: Headers,
      flags: flags,
      stream_id: stream_id,
    )

  HeadersF(
    header,
    HeadersFrame(
      pad_length: 0,
      has_priority: False,
      stream_dependency: 0,
      exclusive: False,
      weight: 16,
      header_block: header_block,
    ),
  )
}

/// Creates a HEADERS frame with priority
///
pub fn create_headers_frame_with_priority(
  stream_id: Int,
  header_block: BitArray,
  stream_dependency: Int,
  exclusive: Bool,
  weight: Int,
  end_stream: Bool,
  end_headers: Bool,
) -> Frame {
  let flags =
    flag_priority
    |> set_flag_if(end_stream, flag_end_stream)
    |> set_flag_if(end_headers, flag_end_headers)

  let header =
    FrameHeader(
      length: 5 + bit_array.byte_size(header_block),
      frame_type: Headers,
      flags: flags,
      stream_id: stream_id,
    )

  HeadersF(
    header,
    HeadersFrame(
      pad_length: 0,
      has_priority: True,
      stream_dependency: stream_dependency,
      exclusive: exclusive,
      weight: weight,
      header_block: header_block,
    ),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PRIORITY Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_priority_frame(header: FrameHeader, payload: PriorityFrame) -> BitArray {
  let exclusive_bit = case payload.exclusive {
    True -> 1
    False -> 0
  }
  let weight = payload.weight - 1
  let payload_bytes = <<
    exclusive_bit:1,
    payload.stream_dependency:31,
    weight:8,
  >>

  let frame_header = build_header(header)
  bit_array.concat([frame_header, payload_bytes])
}

/// Creates a PRIORITY frame
///
pub fn create_priority_frame(
  stream_id: Int,
  stream_dependency: Int,
  exclusive: Bool,
  weight: Int,
) -> Frame {
  let header =
    FrameHeader(length: 5, frame_type: Priority, flags: 0, stream_id: stream_id)

  PriorityF(
    header,
    PriorityFrame(
      stream_dependency: stream_dependency,
      exclusive: exclusive,
      weight: weight,
    ),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RST_STREAM Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_rst_stream_frame(
  header: FrameHeader,
  payload: RstStreamFrame,
) -> BitArray {
  let frame_header = build_header(header)
  bit_array.concat([frame_header, <<payload.error_code:32>>])
}

/// Creates a RST_STREAM frame
///
pub fn create_rst_stream_frame(stream_id: Int, error_code: Int) -> Frame {
  let header =
    FrameHeader(
      length: 4,
      frame_type: RstStream,
      flags: 0,
      stream_id: stream_id,
    )

  RstStreamF(header, RstStreamFrame(error_code: error_code))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SETTINGS Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_settings_frame(header: FrameHeader, payload: SettingsFrame) -> BitArray {
  let frame_header = build_header(header)

  case payload.ack {
    True -> frame_header
    False -> {
      let params_bytes = build_settings_parameters(payload.parameters)
      bit_array.concat([frame_header, params_bytes])
    }
  }
}

fn build_settings_parameters(params: List(SettingsParameter)) -> BitArray {
  params
  |> list.map(fn(param) {
    let id = settings_id_to_int(param.identifier)
    <<id:16, param.value:32>>
  })
  |> bit_array.concat()
}

/// Creates a SETTINGS frame
///
pub fn create_settings_frame(parameters: List(SettingsParameter)) -> Frame {
  let length = list.length(parameters) * 6
  let header =
    FrameHeader(length: length, frame_type: Settings, flags: 0, stream_id: 0)

  SettingsF(header, SettingsFrame(ack: False, parameters: parameters))
}

/// Creates a SETTINGS ACK frame
///
pub fn create_settings_ack_frame() -> Frame {
  let header =
    FrameHeader(length: 0, frame_type: Settings, flags: flag_ack, stream_id: 0)

  SettingsF(header, SettingsFrame(ack: True, parameters: []))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PUSH_PROMISE Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_push_promise_frame(
  header: FrameHeader,
  payload: PushPromiseFrame,
) -> BitArray {
  let padded = has_flag(header.flags, flag_padded)
  let promised_stream = <<0:1, payload.promised_stream_id:31>>

  let frame_header = build_header(header)

  case padded {
    False ->
      bit_array.concat([frame_header, promised_stream, payload.header_block])
    True -> {
      let padding = create_padding(payload.pad_length)
      bit_array.concat([
        frame_header,
        <<payload.pad_length:8>>,
        promised_stream,
        payload.header_block,
        padding,
      ])
    }
  }
}

/// Creates a PUSH_PROMISE frame
///
pub fn create_push_promise_frame(
  stream_id: Int,
  promised_stream_id: Int,
  header_block: BitArray,
  end_headers: Bool,
) -> Frame {
  let flags = case end_headers {
    True -> flag_end_headers
    False -> 0
  }
  let header =
    FrameHeader(
      length: 4 + bit_array.byte_size(header_block),
      frame_type: PushPromise,
      flags: flags,
      stream_id: stream_id,
    )

  PushPromiseF(
    header,
    PushPromiseFrame(
      pad_length: 0,
      promised_stream_id: promised_stream_id,
      header_block: header_block,
    ),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PING Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_ping_frame(header: FrameHeader, payload: PingFrame) -> BitArray {
  let frame_header = build_header(header)
  bit_array.concat([frame_header, payload.opaque_data])
}

/// Creates a PING frame
///
pub fn create_ping_frame(opaque_data: BitArray) -> Frame {
  let header = FrameHeader(length: 8, frame_type: Ping, flags: 0, stream_id: 0)

  PingF(header, PingFrame(ack: False, opaque_data: opaque_data))
}

/// Creates a PING ACK frame
///
pub fn create_ping_ack_frame(opaque_data: BitArray) -> Frame {
  let header =
    FrameHeader(length: 8, frame_type: Ping, flags: flag_ack, stream_id: 0)

  PingF(header, PingFrame(ack: True, opaque_data: opaque_data))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GOAWAY Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_goaway_frame(header: FrameHeader, payload: GoawayFrame) -> BitArray {
  let frame_header = build_header(header)
  bit_array.concat([
    frame_header,
    <<0:1, payload.last_stream_id:31, payload.error_code:32>>,
    payload.debug_data,
  ])
}

/// Creates a GOAWAY frame
///
pub fn create_goaway_frame(
  last_stream_id: Int,
  error_code: Int,
  debug_data: BitArray,
) -> Frame {
  let header =
    FrameHeader(
      length: 8 + bit_array.byte_size(debug_data),
      frame_type: Goaway,
      flags: 0,
      stream_id: 0,
    )

  GoawayF(
    header,
    GoawayFrame(
      last_stream_id: last_stream_id,
      error_code: error_code,
      debug_data: debug_data,
    ),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// WINDOW_UPDATE Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_window_update_frame(
  header: FrameHeader,
  payload: WindowUpdateFrame,
) -> BitArray {
  let frame_header = build_header(header)
  bit_array.concat([
    frame_header,
    <<0:1, payload.window_size_increment:31>>,
  ])
}

/// Creates a WINDOW_UPDATE frame for a stream
///
pub fn create_window_update_frame(
  stream_id: Int,
  window_size_increment: Int,
) -> Frame {
  let header =
    FrameHeader(
      length: 4,
      frame_type: WindowUpdate,
      flags: 0,
      stream_id: stream_id,
    )

  WindowUpdateF(
    header,
    WindowUpdateFrame(window_size_increment: window_size_increment),
  )
}

/// Creates a connection-level WINDOW_UPDATE frame
///
pub fn create_connection_window_update_frame(
  window_size_increment: Int,
) -> Frame {
  create_window_update_frame(0, window_size_increment)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CONTINUATION Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_continuation_frame(
  header: FrameHeader,
  payload: ContinuationFrame,
) -> BitArray {
  let frame_header = build_header(header)
  bit_array.concat([frame_header, payload.header_block])
}

/// Creates a CONTINUATION frame
///
pub fn create_continuation_frame(
  stream_id: Int,
  header_block: BitArray,
  end_headers: Bool,
) -> Frame {
  let flags = case end_headers {
    True -> flag_end_headers
    False -> 0
  }
  let header =
    FrameHeader(
      length: bit_array.byte_size(header_block),
      frame_type: Continuation,
      flags: flags,
      stream_id: stream_id,
    )

  ContinuationF(header, ContinuationFrame(header_block: header_block))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Unknown Frame Builder
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_unknown_frame(header: FrameHeader, payload: BitArray) -> BitArray {
  let frame_header = build_header(header)
  bit_array.concat([frame_header, payload])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates padding bytes (all zeros)
///
fn create_padding(length: Int) -> BitArray {
  create_padding_loop(length, <<>>)
}

fn create_padding_loop(remaining: Int, acc: BitArray) -> BitArray {
  case remaining <= 0 {
    True -> acc
    False -> create_padding_loop(remaining - 1, <<acc:bits, 0:8>>)
  }
}

/// Conditionally sets a flag
///
fn set_flag_if(flags: Int, condition: Bool, flag: Int) -> Int {
  case condition {
    True -> int.bitwise_or(flags, flag)
    False -> flags
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Bulk Frame Building
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds multiple frames into a single BitArray
///
pub fn build_frames(frames: List(Frame)) -> BitArray {
  frames
  |> list.map(build_frame)
  |> bit_array.concat()
}
