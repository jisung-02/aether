// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Error Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Defines error codes and error types for HTTP/2 protocol as per
// RFC 9113 Section 7.
//

import gleam/int

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Error Codes (RFC 9113 Section 7)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// HTTP/2 error codes as defined in RFC 9113
///
pub type ErrorCode {
  /// Graceful shutdown
  NoError

  /// Protocol error detected
  ProtocolError

  /// Implementation fault
  InternalError

  /// Flow control limits exceeded
  FlowControlError

  /// Settings not acknowledged
  SettingsTimeout

  /// Frame received for closed stream
  StreamClosed

  /// Frame size incorrect
  FrameSizeError

  /// Stream not processed
  RefusedStream

  /// Stream cancelled
  Cancel

  /// Compression state not updated
  CompressionError

  /// TCP connection error
  ConnectError

  /// Processing capacity exceeded
  EnhanceYourCalm

  /// Negotiated TLS requirements not met
  InadequateSecurity

  /// Use HTTP/1.1 for the request
  Http11Required

  /// Unknown error code for forward compatibility
  UnknownError(code: Int)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Code Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub const error_no_error = 0x0

pub const error_protocol_error = 0x1

pub const error_internal_error = 0x2

pub const error_flow_control_error = 0x3

pub const error_settings_timeout = 0x4

pub const error_stream_closed = 0x5

pub const error_frame_size_error = 0x6

pub const error_refused_stream = 0x7

pub const error_cancel = 0x8

pub const error_compression_error = 0x9

pub const error_connect_error = 0xA

pub const error_enhance_your_calm = 0xB

pub const error_inadequate_security = 0xC

pub const error_http_1_1_required = 0xD

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Parse Error Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Errors that can occur while parsing HTTP/2 frames
///
pub type ParseError {
  /// Not enough data to parse frame header
  InsufficientData(needed: Int, available: Int)

  /// Frame payload is incomplete
  IncompletePayload(expected: Int, actual: Int)

  /// Frame size exceeds maximum allowed
  FrameTooLarge(size: Int, max: Int)

  /// Invalid frame structure
  InvalidFrame(message: String)

  /// Invalid padding in frame
  InvalidPadding(message: String)

  /// Invalid stream ID for the frame type
  InvalidStreamId(stream_id: Int, frame_type: String)

  /// Invalid flags for the frame type
  InvalidFlags(flags: Int, frame_type: String)

  /// Invalid settings parameter
  InvalidSettings(message: String)

  /// HPACK decompression error
  HpackError(message: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Error Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Connection-level errors that require sending GOAWAY
///
pub type ConnectionError {
  /// Invalid connection preface
  InvalidPreface(message: String)

  /// Protocol violation requiring connection termination
  Protocol(code: ErrorCode, message: String)

  /// Flow control error at connection level
  FlowControl(message: String)

  /// Settings acknowledgment timeout
  SettingsAckTimeout

  /// Compression context error
  Compression(message: String)

  /// Connection closed by peer
  ConnectionClosed

  /// I/O error during communication
  IoError(message: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Error Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Stream-level errors that require RST_STREAM
///
pub type StreamError {
  /// Stream protocol violation
  StreamProtocol(stream_id: Int, code: ErrorCode, message: String)

  /// Stream flow control error
  StreamFlowControl(stream_id: Int, message: String)

  /// Stream was reset by peer
  StreamReset(stream_id: Int, code: ErrorCode)

  /// Stream was refused
  StreamRefused(stream_id: Int)

  /// Stream was cancelled
  StreamCancelled(stream_id: Int)

  /// Invalid stream state for operation
  InvalidStreamState(stream_id: Int, state: String, operation: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Conversion Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts an error code integer to ErrorCode type
///
pub fn error_code_from_int(code: Int) -> ErrorCode {
  case code {
    0 -> NoError
    1 -> ProtocolError
    2 -> InternalError
    3 -> FlowControlError
    4 -> SettingsTimeout
    5 -> StreamClosed
    6 -> FrameSizeError
    7 -> RefusedStream
    8 -> Cancel
    9 -> CompressionError
    10 -> ConnectError
    11 -> EnhanceYourCalm
    12 -> InadequateSecurity
    13 -> Http11Required
    _ -> UnknownError(code)
  }
}

/// Converts an ErrorCode to its integer code
///
pub fn error_code_to_int(error: ErrorCode) -> Int {
  case error {
    NoError -> 0
    ProtocolError -> 1
    InternalError -> 2
    FlowControlError -> 3
    SettingsTimeout -> 4
    StreamClosed -> 5
    FrameSizeError -> 6
    RefusedStream -> 7
    Cancel -> 8
    CompressionError -> 9
    ConnectError -> 10
    EnhanceYourCalm -> 11
    InadequateSecurity -> 12
    Http11Required -> 13
    UnknownError(code) -> code
  }
}

/// Returns the error code name as a string
///
pub fn error_code_to_string(error: ErrorCode) -> String {
  case error {
    NoError -> "NO_ERROR"
    ProtocolError -> "PROTOCOL_ERROR"
    InternalError -> "INTERNAL_ERROR"
    FlowControlError -> "FLOW_CONTROL_ERROR"
    SettingsTimeout -> "SETTINGS_TIMEOUT"
    StreamClosed -> "STREAM_CLOSED"
    FrameSizeError -> "FRAME_SIZE_ERROR"
    RefusedStream -> "REFUSED_STREAM"
    Cancel -> "CANCEL"
    CompressionError -> "COMPRESSION_ERROR"
    ConnectError -> "CONNECT_ERROR"
    EnhanceYourCalm -> "ENHANCE_YOUR_CALM"
    InadequateSecurity -> "INADEQUATE_SECURITY"
    Http11Required -> "HTTP_1_1_REQUIRED"
    UnknownError(code) -> "UNKNOWN_ERROR(" <> int.to_string(code) <> ")"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Message Formatting
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Formats a ParseError as a human-readable string
///
pub fn parse_error_to_string(error: ParseError) -> String {
  case error {
    InsufficientData(needed, available) ->
      "Insufficient data: need "
      <> int.to_string(needed)
      <> " bytes, have "
      <> int.to_string(available)

    IncompletePayload(expected, actual) ->
      "Incomplete payload: expected "
      <> int.to_string(expected)
      <> " bytes, got "
      <> int.to_string(actual)

    FrameTooLarge(size, max) ->
      "Frame too large: "
      <> int.to_string(size)
      <> " bytes exceeds max "
      <> int.to_string(max)

    InvalidFrame(message) -> "Invalid frame: " <> message

    InvalidPadding(message) -> "Invalid padding: " <> message

    InvalidStreamId(stream_id, frame_type) ->
      "Invalid stream ID "
      <> int.to_string(stream_id)
      <> " for "
      <> frame_type
      <> " frame"

    InvalidFlags(flags, frame_type) ->
      "Invalid flags 0x"
      <> int.to_base16(flags)
      <> " for "
      <> frame_type
      <> " frame"

    InvalidSettings(message) -> "Invalid settings: " <> message

    HpackError(message) -> "HPACK error: " <> message
  }
}

/// Formats a ConnectionError as a human-readable string
///
pub fn connection_error_to_string(error: ConnectionError) -> String {
  case error {
    InvalidPreface(message) -> "Invalid connection preface: " <> message

    Protocol(code, message) ->
      "Protocol error (" <> error_code_to_string(code) <> "): " <> message

    FlowControl(message) -> "Flow control error: " <> message

    SettingsAckTimeout -> "Settings acknowledgment timeout"

    Compression(message) -> "Compression error: " <> message

    ConnectionClosed -> "Connection closed by peer"

    IoError(message) -> "I/O error: " <> message
  }
}

/// Formats a StreamError as a human-readable string
///
pub fn stream_error_to_string(error: StreamError) -> String {
  case error {
    StreamProtocol(stream_id, code, message) ->
      "Stream "
      <> int.to_string(stream_id)
      <> " protocol error ("
      <> error_code_to_string(code)
      <> "): "
      <> message

    StreamFlowControl(stream_id, message) ->
      "Stream "
      <> int.to_string(stream_id)
      <> " flow control error: "
      <> message

    StreamReset(stream_id, code) ->
      "Stream "
      <> int.to_string(stream_id)
      <> " reset with "
      <> error_code_to_string(code)

    StreamRefused(stream_id) ->
      "Stream " <> int.to_string(stream_id) <> " refused"

    StreamCancelled(stream_id) ->
      "Stream " <> int.to_string(stream_id) <> " cancelled"

    InvalidStreamState(stream_id, state, operation) ->
      "Stream "
      <> int.to_string(stream_id)
      <> " in state "
      <> state
      <> " cannot perform "
      <> operation
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Classification
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Determines if an error code indicates a connection-level error
///
pub fn is_connection_error(code: ErrorCode) -> Bool {
  case code {
    ProtocolError
    | InternalError
    | FlowControlError
    | SettingsTimeout
    | CompressionError
    | EnhanceYourCalm
    | InadequateSecurity
    | Http11Required -> True
    _ -> False
  }
}

/// Determines if an error code indicates a recoverable error
///
pub fn is_recoverable(code: ErrorCode) -> Bool {
  case code {
    NoError | RefusedStream | Cancel -> True
    _ -> False
  }
}

/// Gets the appropriate error code for a parse error
///
pub fn parse_error_to_error_code(error: ParseError) -> ErrorCode {
  case error {
    FrameTooLarge(_, _) -> FrameSizeError
    InvalidPadding(_) -> ProtocolError
    InvalidStreamId(_, _) -> ProtocolError
    InvalidFlags(_, _) -> ProtocolError
    InvalidSettings(_) -> ProtocolError
    HpackError(_) -> CompressionError
    _ -> ProtocolError
  }
}
