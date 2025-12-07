// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Frame Types and Structures
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Implements HTTP/2 frame definitions as per RFC 9113 Section 4.
// All HTTP/2 connections use binary framing with a 9-byte header.
//
// Frame Header Format:
// +-----------------------------------------------+
// |                 Length (24)                   |
// +---------------+---------------+---------------+
// |   Type (8)    |   Flags (8)   |
// +-+-------------+---------------+-------------------------------+
// |R|                 Stream Identifier (31)                      |
// +-+-------------------------------------------------------------+
// |                   Frame Payload (0...)                      ...
// +---------------------------------------------------------------+
//

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Types (RFC 9113 Section 4)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// HTTP/2 frame types as defined in RFC 9113
///
pub type FrameType {
  /// DATA frames (type=0x0) convey arbitrary, variable-length sequences of
  /// octets associated with a stream.
  Data

  /// HEADERS frames (type=0x1) are used to open a stream and additionally
  /// carry a header block fragment.
  Headers

  /// PRIORITY frames (type=0x2) specify the sender-advised priority of a stream.
  /// Note: Deprecated in RFC 9113 but still must be parsed.
  Priority

  /// RST_STREAM frames (type=0x3) allow immediate termination of a stream.
  RstStream

  /// SETTINGS frames (type=0x4) convey configuration parameters that affect
  /// how endpoints communicate.
  Settings

  /// PUSH_PROMISE frames (type=0x5) are used to notify the peer endpoint
  /// in advance of streams the sender intends to initiate.
  PushPromise

  /// PING frames (type=0x6) are a mechanism for measuring minimal RTT
  /// and determining whether an idle connection is still functional.
  Ping

  /// GOAWAY frames (type=0x7) are used to initiate shutdown of a connection
  /// or to signal serious error conditions.
  Goaway

  /// WINDOW_UPDATE frames (type=0x8) are used to implement flow control.
  WindowUpdate

  /// CONTINUATION frames (type=0x9) are used to continue a sequence of
  /// header block fragments.
  Continuation

  /// Unknown frame type for forward compatibility
  Unknown(type_code: Int)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Type Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Frame type code for DATA frames
pub const frame_type_data = 0x0

/// Frame type code for HEADERS frames
pub const frame_type_headers = 0x1

/// Frame type code for PRIORITY frames
pub const frame_type_priority = 0x2

/// Frame type code for RST_STREAM frames
pub const frame_type_rst_stream = 0x3

/// Frame type code for SETTINGS frames
pub const frame_type_settings = 0x4

/// Frame type code for PUSH_PROMISE frames
pub const frame_type_push_promise = 0x5

/// Frame type code for PING frames
pub const frame_type_ping = 0x6

/// Frame type code for GOAWAY frames
pub const frame_type_goaway = 0x7

/// Frame type code for WINDOW_UPDATE frames
pub const frame_type_window_update = 0x8

/// Frame type code for CONTINUATION frames
pub const frame_type_continuation = 0x9

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Flags
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// END_STREAM flag (0x1) - indicates this is the last frame for the stream
pub const flag_end_stream = 0x1

/// END_HEADERS flag (0x4) - indicates the end of header block
pub const flag_end_headers = 0x4

/// PADDED flag (0x8) - indicates the frame is padded
pub const flag_padded = 0x8

/// PRIORITY flag (0x20) - indicates priority information is present
pub const flag_priority = 0x20

/// ACK flag (0x1) - used in SETTINGS and PING frames
pub const flag_ack = 0x1

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Header
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// The size of an HTTP/2 frame header in bytes
pub const frame_header_size = 9

/// Maximum frame payload size (default: 16384, max: 16777215)
pub const default_max_frame_size = 16_384

/// Absolute maximum frame size allowed by protocol
pub const max_frame_size_limit = 16_777_215

/// HTTP/2 frame header containing metadata for every frame
///
pub type FrameHeader {
  FrameHeader(
    /// Length of the frame payload (24 bits, max 16777215)
    length: Int,
    /// Type of the frame
    frame_type: FrameType,
    /// Frame-specific flags
    flags: Int,
    /// Stream identifier (31 bits, 0 for connection-level frames)
    stream_id: Int,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Payloads
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// DATA frame payload
///
pub type DataFrame {
  DataFrame(
    /// Optional padding length
    pad_length: Int,
    /// Actual data payload
    data: BitArray,
  )
}

/// HEADERS frame payload
///
pub type HeadersFrame {
  HeadersFrame(
    /// Optional padding length
    pad_length: Int,
    /// Whether priority information is present
    has_priority: Bool,
    /// Stream dependency (if priority present)
    stream_dependency: Int,
    /// Exclusive dependency flag
    exclusive: Bool,
    /// Weight (1-256, if priority present)
    weight: Int,
    /// Header block fragment (HPACK encoded)
    header_block: BitArray,
  )
}

/// PRIORITY frame payload (4 bytes + 1 byte weight)
///
pub type PriorityFrame {
  PriorityFrame(
    /// Stream dependency
    stream_dependency: Int,
    /// Exclusive dependency flag
    exclusive: Bool,
    /// Weight (1-256)
    weight: Int,
  )
}

/// RST_STREAM frame payload (4 bytes)
///
pub type RstStreamFrame {
  RstStreamFrame(
    /// Error code indicating why the stream is being terminated
    error_code: Int,
  )
}

/// SETTINGS frame parameter
///
pub type SettingsParameter {
  SettingsParameter(
    /// Setting identifier
    identifier: SettingsId,
    /// Setting value
    value: Int,
  )
}

/// SETTINGS parameter identifiers
///
pub type SettingsId {
  /// Allows the sender to inform the remote endpoint of the
  /// maximum size of the header compression table
  HeaderTableSize

  /// Can be used to disable server push
  EnablePush

  /// Maximum number of concurrent streams
  MaxConcurrentStreams

  /// Initial window size for stream-level flow control
  InitialWindowSize

  /// Maximum frame size the sender is willing to receive
  MaxFrameSize

  /// Maximum size of header list the sender is willing to accept
  MaxHeaderListSize

  /// Unknown setting for forward compatibility
  UnknownSetting(id: Int)
}

/// SETTINGS frame payload
///
pub type SettingsFrame {
  SettingsFrame(
    /// Whether this is an acknowledgment
    ack: Bool,
    /// List of settings parameters
    parameters: List(SettingsParameter),
  )
}

/// PUSH_PROMISE frame payload
///
pub type PushPromiseFrame {
  PushPromiseFrame(
    /// Optional padding length
    pad_length: Int,
    /// Promised stream ID
    promised_stream_id: Int,
    /// Header block fragment
    header_block: BitArray,
  )
}

/// PING frame payload (8 bytes)
///
pub type PingFrame {
  PingFrame(
    /// Whether this is an acknowledgment
    ack: Bool,
    /// Opaque 8-byte data
    opaque_data: BitArray,
  )
}

/// GOAWAY frame payload
///
pub type GoawayFrame {
  GoawayFrame(
    /// Last stream ID that was or might be processed
    last_stream_id: Int,
    /// Error code
    error_code: Int,
    /// Additional debug data
    debug_data: BitArray,
  )
}

/// WINDOW_UPDATE frame payload (4 bytes)
///
pub type WindowUpdateFrame {
  WindowUpdateFrame(
    /// Window size increment (1 to 2^31-1)
    window_size_increment: Int,
  )
}

/// CONTINUATION frame payload
///
pub type ContinuationFrame {
  ContinuationFrame(
    /// Header block fragment
    header_block: BitArray,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Complete Frame
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Complete HTTP/2 frame with header and typed payload
///
pub type Frame {
  /// DATA frame for transmitting stream data
  DataF(header: FrameHeader, payload: DataFrame)

  /// HEADERS frame for opening streams and sending headers
  HeadersF(header: FrameHeader, payload: HeadersFrame)

  /// PRIORITY frame for stream prioritization
  PriorityF(header: FrameHeader, payload: PriorityFrame)

  /// RST_STREAM frame for stream termination
  RstStreamF(header: FrameHeader, payload: RstStreamFrame)

  /// SETTINGS frame for connection configuration
  SettingsF(header: FrameHeader, payload: SettingsFrame)

  /// PUSH_PROMISE frame for server push
  PushPromiseF(header: FrameHeader, payload: PushPromiseFrame)

  /// PING frame for connection health check
  PingF(header: FrameHeader, payload: PingFrame)

  /// GOAWAY frame for connection shutdown
  GoawayF(header: FrameHeader, payload: GoawayFrame)

  /// WINDOW_UPDATE frame for flow control
  WindowUpdateF(header: FrameHeader, payload: WindowUpdateFrame)

  /// CONTINUATION frame for header continuation
  ContinuationF(header: FrameHeader, payload: ContinuationFrame)

  /// Unknown frame type for forward compatibility
  UnknownF(header: FrameHeader, payload: BitArray)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Type Conversion Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a frame type code to FrameType
///
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

/// Converts a FrameType to its integer code
///
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

/// Converts a settings ID code to SettingsId
///
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

/// Converts a SettingsId to its integer code
///
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

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flag Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/int

/// Checks if a flag is set in the flags byte
///
pub fn has_flag(flags: Int, flag: Int) -> Bool {
  int.bitwise_and(flags, flag) == flag
}

/// Sets a flag in the flags byte
///
pub fn set_flag(flags: Int, flag: Int) -> Int {
  int.bitwise_or(flags, flag)
}

/// Clears a flag in the flags byte
///
pub fn clear_flag(flags: Int, flag: Int) -> Int {
  int.bitwise_and(flags, int.bitwise_not(flag))
}

/// Checks if END_STREAM flag is set
///
pub fn is_end_stream(flags: Int) -> Bool {
  has_flag(flags, flag_end_stream)
}

/// Checks if END_HEADERS flag is set
///
pub fn is_end_headers(flags: Int) -> Bool {
  has_flag(flags, flag_end_headers)
}

/// Checks if PADDED flag is set
///
pub fn is_padded(flags: Int) -> Bool {
  has_flag(flags, flag_padded)
}

/// Checks if PRIORITY flag is set
///
pub fn is_priority(flags: Int) -> Bool {
  has_flag(flags, flag_priority)
}

/// Checks if ACK flag is set
///
pub fn is_ack(flags: Int) -> Bool {
  has_flag(flags, flag_ack)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Validation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Validates frame header constraints
///
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

/// Validates that stream ID is appropriate for the frame type
///
fn validate_stream_id_for_type(frame_type: FrameType, stream_id: Int) -> Bool {
  case frame_type {
    // Connection-level frames must have stream ID 0
    Settings | Ping | Goaway -> stream_id == 0

    // Stream-level frames must have non-zero stream ID
    Data
    | Headers
    | Priority
    | RstStream
    | PushPromise
    | WindowUpdate
    | Continuation ->
      // WindowUpdate can be 0 for connection-level flow control
      case frame_type {
        WindowUpdate -> True
        _ -> stream_id > 0
      }

    // Unknown frames - allow any stream ID
    Unknown(_) -> True
  }
}

/// Returns the frame type name as a string
///
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

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Default Settings Values (RFC 9113 Section 6.5.2)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Default header table size (4096 bytes)
pub const default_header_table_size = 4096

/// Default enable push (1 = enabled)
pub const default_enable_push = 1

/// Default max concurrent streams (unlimited)
pub const default_max_concurrent_streams = 0x7FFFFFFF

/// Default initial window size (65535 bytes)
pub const default_initial_window_size = 65_535

/// Default max header list size (unlimited)
pub const default_max_header_list_size = 0x7FFFFFFF
