// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Error Module Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/http2/error
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Code Conversion Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_code_from_int_no_error_test() {
  error.error_code_from_int(0)
  |> should.equal(error.NoError)
}

pub fn error_code_from_int_protocol_error_test() {
  error.error_code_from_int(1)
  |> should.equal(error.ProtocolError)
}

pub fn error_code_from_int_internal_error_test() {
  error.error_code_from_int(2)
  |> should.equal(error.InternalError)
}

pub fn error_code_from_int_flow_control_error_test() {
  error.error_code_from_int(3)
  |> should.equal(error.FlowControlError)
}

pub fn error_code_from_int_settings_timeout_test() {
  error.error_code_from_int(4)
  |> should.equal(error.SettingsTimeout)
}

pub fn error_code_from_int_stream_closed_test() {
  error.error_code_from_int(5)
  |> should.equal(error.StreamClosed)
}

pub fn error_code_from_int_frame_size_error_test() {
  error.error_code_from_int(6)
  |> should.equal(error.FrameSizeError)
}

pub fn error_code_from_int_refused_stream_test() {
  error.error_code_from_int(7)
  |> should.equal(error.RefusedStream)
}

pub fn error_code_from_int_cancel_test() {
  error.error_code_from_int(8)
  |> should.equal(error.Cancel)
}

pub fn error_code_from_int_compression_error_test() {
  error.error_code_from_int(9)
  |> should.equal(error.CompressionError)
}

pub fn error_code_from_int_connect_error_test() {
  error.error_code_from_int(10)
  |> should.equal(error.ConnectError)
}

pub fn error_code_from_int_enhance_your_calm_test() {
  error.error_code_from_int(11)
  |> should.equal(error.EnhanceYourCalm)
}

pub fn error_code_from_int_inadequate_security_test() {
  error.error_code_from_int(12)
  |> should.equal(error.InadequateSecurity)
}

pub fn error_code_from_int_http_1_1_required_test() {
  error.error_code_from_int(13)
  |> should.equal(error.Http11Required)
}

pub fn error_code_from_int_unknown_test() {
  error.error_code_from_int(99)
  |> should.equal(error.UnknownError(99))
}

pub fn error_code_to_int_roundtrip_test() {
  let codes = [
    error.NoError,
    error.ProtocolError,
    error.InternalError,
    error.FlowControlError,
    error.SettingsTimeout,
    error.StreamClosed,
    error.FrameSizeError,
    error.RefusedStream,
    error.Cancel,
    error.CompressionError,
    error.ConnectError,
    error.EnhanceYourCalm,
    error.InadequateSecurity,
    error.Http11Required,
  ]

  codes
  |> list_all(fn(code) {
    error.error_code_from_int(error.error_code_to_int(code)) == code
  })
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Code String Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_code_to_string_no_error_test() {
  error.error_code_to_string(error.NoError)
  |> should.equal("NO_ERROR")
}

pub fn error_code_to_string_protocol_error_test() {
  error.error_code_to_string(error.ProtocolError)
  |> should.equal("PROTOCOL_ERROR")
}

pub fn error_code_to_string_cancel_test() {
  error.error_code_to_string(error.Cancel)
  |> should.equal("CANCEL")
}

pub fn error_code_to_string_unknown_test() {
  error.error_code_to_string(error.UnknownError(42))
  |> should.equal("UNKNOWN_ERROR(42)")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Parse Error String Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_error_to_string_insufficient_data_test() {
  error.parse_error_to_string(error.InsufficientData(9, 5))
  |> should.equal("Insufficient data: need 9 bytes, have 5")
}

pub fn parse_error_to_string_incomplete_payload_test() {
  error.parse_error_to_string(error.IncompletePayload(100, 50))
  |> should.equal("Incomplete payload: expected 100 bytes, got 50")
}

pub fn parse_error_to_string_frame_too_large_test() {
  error.parse_error_to_string(error.FrameTooLarge(20_000, 16_384))
  |> should.equal("Frame too large: 20000 bytes exceeds max 16384")
}

pub fn parse_error_to_string_invalid_frame_test() {
  error.parse_error_to_string(error.InvalidFrame("test message"))
  |> should.equal("Invalid frame: test message")
}

pub fn parse_error_to_string_invalid_padding_test() {
  error.parse_error_to_string(error.InvalidPadding("bad padding"))
  |> should.equal("Invalid padding: bad padding")
}

pub fn parse_error_to_string_invalid_stream_id_test() {
  error.parse_error_to_string(error.InvalidStreamId(0, "DATA"))
  |> should.equal("Invalid stream ID 0 for DATA frame")
}

pub fn parse_error_to_string_hpack_error_test() {
  error.parse_error_to_string(error.HpackError("decode failed"))
  |> should.equal("HPACK error: decode failed")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Error String Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn connection_error_to_string_invalid_preface_test() {
  error.connection_error_to_string(error.InvalidPreface("bad magic"))
  |> should.equal("Invalid connection preface: bad magic")
}

pub fn connection_error_to_string_protocol_test() {
  error.connection_error_to_string(error.Protocol(
    error.ProtocolError,
    "invalid frame",
  ))
  |> should.equal("Protocol error (PROTOCOL_ERROR): invalid frame")
}

pub fn connection_error_to_string_flow_control_test() {
  error.connection_error_to_string(error.FlowControl("window exceeded"))
  |> should.equal("Flow control error: window exceeded")
}

pub fn connection_error_to_string_settings_ack_timeout_test() {
  error.connection_error_to_string(error.SettingsAckTimeout)
  |> should.equal("Settings acknowledgment timeout")
}

pub fn connection_error_to_string_connection_closed_test() {
  error.connection_error_to_string(error.ConnectionClosed)
  |> should.equal("Connection closed by peer")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Error String Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stream_error_to_string_protocol_test() {
  error.stream_error_to_string(error.StreamProtocol(
    1,
    error.ProtocolError,
    "bad frame",
  ))
  |> should.equal("Stream 1 protocol error (PROTOCOL_ERROR): bad frame")
}

pub fn stream_error_to_string_flow_control_test() {
  error.stream_error_to_string(error.StreamFlowControl(5, "window negative"))
  |> should.equal("Stream 5 flow control error: window negative")
}

pub fn stream_error_to_string_reset_test() {
  error.stream_error_to_string(error.StreamReset(3, error.Cancel))
  |> should.equal("Stream 3 reset with CANCEL")
}

pub fn stream_error_to_string_refused_test() {
  error.stream_error_to_string(error.StreamRefused(7))
  |> should.equal("Stream 7 refused")
}

pub fn stream_error_to_string_cancelled_test() {
  error.stream_error_to_string(error.StreamCancelled(9))
  |> should.equal("Stream 9 cancelled")
}

pub fn stream_error_to_string_invalid_state_test() {
  error.stream_error_to_string(error.InvalidStreamState(1, "closed", "send"))
  |> should.equal("Stream 1 in state closed cannot perform send")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Classification Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn is_connection_error_protocol_error_test() {
  error.is_connection_error(error.ProtocolError)
  |> should.be_true()
}

pub fn is_connection_error_internal_error_test() {
  error.is_connection_error(error.InternalError)
  |> should.be_true()
}

pub fn is_connection_error_compression_error_test() {
  error.is_connection_error(error.CompressionError)
  |> should.be_true()
}

pub fn is_connection_error_cancel_test() {
  error.is_connection_error(error.Cancel)
  |> should.be_false()
}

pub fn is_connection_error_refused_stream_test() {
  error.is_connection_error(error.RefusedStream)
  |> should.be_false()
}

pub fn is_recoverable_no_error_test() {
  error.is_recoverable(error.NoError)
  |> should.be_true()
}

pub fn is_recoverable_cancel_test() {
  error.is_recoverable(error.Cancel)
  |> should.be_true()
}

pub fn is_recoverable_refused_stream_test() {
  error.is_recoverable(error.RefusedStream)
  |> should.be_true()
}

pub fn is_recoverable_protocol_error_test() {
  error.is_recoverable(error.ProtocolError)
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Parse Error to Error Code Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_error_to_error_code_frame_too_large_test() {
  error.parse_error_to_error_code(error.FrameTooLarge(20_000, 16_384))
  |> should.equal(error.FrameSizeError)
}

pub fn parse_error_to_error_code_invalid_padding_test() {
  error.parse_error_to_error_code(error.InvalidPadding("bad"))
  |> should.equal(error.ProtocolError)
}

pub fn parse_error_to_error_code_hpack_error_test() {
  error.parse_error_to_error_code(error.HpackError("decode failed"))
  |> should.equal(error.CompressionError)
}

pub fn parse_error_to_error_code_invalid_frame_test() {
  error.parse_error_to_error_code(error.InvalidFrame("bad"))
  |> should.equal(error.ProtocolError)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Code Constants Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_constants_test() {
  error.error_no_error |> should.equal(0)
  error.error_protocol_error |> should.equal(1)
  error.error_internal_error |> should.equal(2)
  error.error_flow_control_error |> should.equal(3)
  error.error_settings_timeout |> should.equal(4)
  error.error_stream_closed |> should.equal(5)
  error.error_frame_size_error |> should.equal(6)
  error.error_refused_stream |> should.equal(7)
  error.error_cancel |> should.equal(8)
  error.error_compression_error |> should.equal(9)
  error.error_connect_error |> should.equal(10)
  error.error_enhance_your_calm |> should.equal(11)
  error.error_inadequate_security |> should.equal(12)
  error.error_http_1_1_required |> should.equal(13)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn list_all(items: List(a), predicate: fn(a) -> Bool) -> Bool {
  case items {
    [] -> True
    [first, ..rest] ->
      case predicate(first) {
        False -> False
        True -> list_all(rest, predicate)
      }
  }
}
