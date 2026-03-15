// HTTP/2 frame type and payload definitions (RFC 9113)

pub type FrameType {
  Data

  Headers

  Priority

  RstStream

  Settings

  PushPromise

  Ping

  Goaway

  WindowUpdate

  Continuation

  Unknown(type_code: Int)
}

pub const frame_type_data = 0x0

pub const frame_type_headers = 0x1

pub const frame_type_priority = 0x2

pub const frame_type_rst_stream = 0x3

pub const frame_type_settings = 0x4

pub const frame_type_push_promise = 0x5

pub const frame_type_ping = 0x6

pub const frame_type_goaway = 0x7

pub const frame_type_window_update = 0x8

pub const frame_type_continuation = 0x9

pub const flag_end_stream = 0x1

pub const flag_end_headers = 0x4

pub const flag_padded = 0x8

pub const flag_priority = 0x20

pub const flag_ack = 0x1

pub const frame_header_size = 9

pub const default_max_frame_size = 16_384

pub const max_frame_size_limit = 16_777_215

pub type FrameHeader {
  FrameHeader(length: Int, frame_type: FrameType, flags: Int, stream_id: Int)
}

pub type DataFrame {
  DataFrame(pad_length: Int, data: BitArray)
}

pub type HeadersFrame {
  HeadersFrame(
    pad_length: Int,
    has_priority: Bool,
    stream_dependency: Int,
    exclusive: Bool,
    weight: Int,
    header_block: BitArray,
  )
}

pub type PriorityFrame {
  PriorityFrame(stream_dependency: Int, exclusive: Bool, weight: Int)
}

pub type RstStreamFrame {
  RstStreamFrame(error_code: Int)
}

pub type SettingsParameter {
  SettingsParameter(identifier: SettingsId, value: Int)
}

pub type SettingsId {
  HeaderTableSize

  EnablePush

  MaxConcurrentStreams

  InitialWindowSize

  MaxFrameSize

  MaxHeaderListSize

  UnknownSetting(id: Int)
}

pub type SettingsFrame {
  SettingsFrame(ack: Bool, parameters: List(SettingsParameter))
}

pub type PushPromiseFrame {
  PushPromiseFrame(
    pad_length: Int,
    promised_stream_id: Int,
    header_block: BitArray,
  )
}

pub type PingFrame {
  PingFrame(ack: Bool, opaque_data: BitArray)
}

pub type GoawayFrame {
  GoawayFrame(last_stream_id: Int, error_code: Int, debug_data: BitArray)
}

pub type WindowUpdateFrame {
  WindowUpdateFrame(window_size_increment: Int)
}

pub type ContinuationFrame {
  ContinuationFrame(header_block: BitArray)
}

pub type Frame {
  DataF(header: FrameHeader, payload: DataFrame)

  HeadersF(header: FrameHeader, payload: HeadersFrame)

  PriorityF(header: FrameHeader, payload: PriorityFrame)

  RstStreamF(header: FrameHeader, payload: RstStreamFrame)

  SettingsF(header: FrameHeader, payload: SettingsFrame)

  PushPromiseF(header: FrameHeader, payload: PushPromiseFrame)

  PingF(header: FrameHeader, payload: PingFrame)

  GoawayF(header: FrameHeader, payload: GoawayFrame)

  WindowUpdateF(header: FrameHeader, payload: WindowUpdateFrame)

  ContinuationF(header: FrameHeader, payload: ContinuationFrame)

  UnknownF(header: FrameHeader, payload: BitArray)
}

pub fn frame_type_from_int(code: Int) -> FrameType {
  case code {
    0 -> Data
    1 -> Headers
    2 -> Priority
    3 -> RstStream
    4 -> Settings
    5 -> PushPromise
    6 -> Ping
    7 -> Goaway
    8 -> WindowUpdate
    9 -> Continuation
    _ -> Unknown(code)
  }
}

pub fn frame_type_to_int(frame_type: FrameType) -> Int {
  case frame_type {
    Data -> 0
    Headers -> 1
    Priority -> 2
    RstStream -> 3
    Settings -> 4
    PushPromise -> 5
    Ping -> 6
    Goaway -> 7
    WindowUpdate -> 8
    Continuation -> 9
    Unknown(code) -> code
  }
}

pub fn settings_id_from_int(code: Int) -> SettingsId {
  case code {
    1 -> HeaderTableSize
    2 -> EnablePush
    3 -> MaxConcurrentStreams
    4 -> InitialWindowSize
    5 -> MaxFrameSize
    6 -> MaxHeaderListSize
    _ -> UnknownSetting(code)
  }
}

pub fn settings_id_to_int(id: SettingsId) -> Int {
  case id {
    HeaderTableSize -> 1
    EnablePush -> 2
    MaxConcurrentStreams -> 3
    InitialWindowSize -> 4
    MaxFrameSize -> 5
    MaxHeaderListSize -> 6
    UnknownSetting(code) -> code
  }
}

import gleam/int

pub fn has_flag(flags: Int, flag: Int) -> Bool {
  int.bitwise_and(flags, flag) == flag
}

pub fn set_flag(flags: Int, flag: Int) -> Int {
  int.bitwise_or(flags, flag)
}

pub fn clear_flag(flags: Int, flag: Int) -> Int {
  int.bitwise_and(flags, int.bitwise_not(flag))
}

pub fn is_end_stream(flags: Int) -> Bool {
  has_flag(flags, flag_end_stream)
}

pub fn is_end_headers(flags: Int) -> Bool {
  has_flag(flags, flag_end_headers)
}

pub fn is_padded(flags: Int) -> Bool {
  has_flag(flags, flag_padded)
}

pub fn is_priority(flags: Int) -> Bool {
  has_flag(flags, flag_priority)
}

pub fn is_ack(flags: Int) -> Bool {
  has_flag(flags, flag_ack)
}

pub fn validate_frame_header(
  header: FrameHeader,
  max_frame_size: Int,
) -> Result(Nil, String) {
  case header.length > max_frame_size {
    True -> Error("Frame size exceeds maximum")
    False ->
      case header.stream_id < 0 {
        True -> Error("Invalid stream ID")
        False ->
          case
            validate_stream_id_for_type(header.frame_type, header.stream_id)
          {
            False -> Error("Invalid stream ID for frame type")
            True -> Ok(Nil)
          }
      }
  }
}

fn validate_stream_id_for_type(frame_type: FrameType, stream_id: Int) -> Bool {
  case frame_type {
    Settings | Ping | Goaway -> stream_id == 0

    Data
    | Headers
    | Priority
    | RstStream
    | PushPromise
    | WindowUpdate
    | Continuation ->
      case frame_type {
        WindowUpdate -> True
        _ -> stream_id > 0
      }

    Unknown(_) -> True
  }
}

pub fn frame_type_to_string(frame_type: FrameType) -> String {
  case frame_type {
    Data -> "DATA"
    Headers -> "HEADERS"
    Priority -> "PRIORITY"
    RstStream -> "RST_STREAM"
    Settings -> "SETTINGS"
    PushPromise -> "PUSH_PROMISE"
    Ping -> "PING"
    Goaway -> "GOAWAY"
    WindowUpdate -> "WINDOW_UPDATE"
    Continuation -> "CONTINUATION"
    Unknown(code) -> "UNKNOWN(" <> int.to_string(code) <> ")"
  }
}

pub const default_header_table_size = 4096

pub const default_enable_push = 1

pub const default_max_concurrent_streams = 0x7FFFFFFF

pub const default_initial_window_size = 65_535

pub const default_max_header_list_size = 0x7FFFFFFF
