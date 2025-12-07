// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Frame Module Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/http2/frame
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Type Conversion Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn frame_type_from_int_data_test() {
  frame.frame_type_from_int(0)
  |> should.equal(frame.Data)
}

pub fn frame_type_from_int_headers_test() {
  frame.frame_type_from_int(1)
  |> should.equal(frame.Headers)
}

pub fn frame_type_from_int_priority_test() {
  frame.frame_type_from_int(2)
  |> should.equal(frame.Priority)
}

pub fn frame_type_from_int_rst_stream_test() {
  frame.frame_type_from_int(3)
  |> should.equal(frame.RstStream)
}

pub fn frame_type_from_int_settings_test() {
  frame.frame_type_from_int(4)
  |> should.equal(frame.Settings)
}

pub fn frame_type_from_int_push_promise_test() {
  frame.frame_type_from_int(5)
  |> should.equal(frame.PushPromise)
}

pub fn frame_type_from_int_ping_test() {
  frame.frame_type_from_int(6)
  |> should.equal(frame.Ping)
}

pub fn frame_type_from_int_goaway_test() {
  frame.frame_type_from_int(7)
  |> should.equal(frame.Goaway)
}

pub fn frame_type_from_int_window_update_test() {
  frame.frame_type_from_int(8)
  |> should.equal(frame.WindowUpdate)
}

pub fn frame_type_from_int_continuation_test() {
  frame.frame_type_from_int(9)
  |> should.equal(frame.Continuation)
}

pub fn frame_type_from_int_unknown_test() {
  frame.frame_type_from_int(255)
  |> should.equal(frame.Unknown(255))
}

pub fn frame_type_to_int_roundtrip_test() {
  // Test all known frame types round-trip correctly
  let types = [
    frame.Data,
    frame.Headers,
    frame.Priority,
    frame.RstStream,
    frame.Settings,
    frame.PushPromise,
    frame.Ping,
    frame.Goaway,
    frame.WindowUpdate,
    frame.Continuation,
  ]

  types
  |> list_all(fn(ft) {
    frame.frame_type_from_int(frame.frame_type_to_int(ft)) == ft
  })
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Settings ID Conversion Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn settings_id_from_int_header_table_size_test() {
  frame.settings_id_from_int(1)
  |> should.equal(frame.HeaderTableSize)
}

pub fn settings_id_from_int_enable_push_test() {
  frame.settings_id_from_int(2)
  |> should.equal(frame.EnablePush)
}

pub fn settings_id_from_int_max_concurrent_streams_test() {
  frame.settings_id_from_int(3)
  |> should.equal(frame.MaxConcurrentStreams)
}

pub fn settings_id_from_int_initial_window_size_test() {
  frame.settings_id_from_int(4)
  |> should.equal(frame.InitialWindowSize)
}

pub fn settings_id_from_int_max_frame_size_test() {
  frame.settings_id_from_int(5)
  |> should.equal(frame.MaxFrameSize)
}

pub fn settings_id_from_int_max_header_list_size_test() {
  frame.settings_id_from_int(6)
  |> should.equal(frame.MaxHeaderListSize)
}

pub fn settings_id_from_int_unknown_test() {
  frame.settings_id_from_int(99)
  |> should.equal(frame.UnknownSetting(99))
}

pub fn settings_id_to_int_roundtrip_test() {
  let ids = [
    frame.HeaderTableSize,
    frame.EnablePush,
    frame.MaxConcurrentStreams,
    frame.InitialWindowSize,
    frame.MaxFrameSize,
    frame.MaxHeaderListSize,
  ]

  ids
  |> list_all(fn(id) {
    frame.settings_id_from_int(frame.settings_id_to_int(id)) == id
  })
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flag Helper Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn has_flag_test() {
  frame.has_flag(0x0F, 0x01)
  |> should.be_true()

  frame.has_flag(0x0F, 0x04)
  |> should.be_true()

  frame.has_flag(0x0F, 0x10)
  |> should.be_false()
}

pub fn set_flag_test() {
  frame.set_flag(0x00, 0x01)
  |> should.equal(0x01)

  frame.set_flag(0x01, 0x04)
  |> should.equal(0x05)

  frame.set_flag(0x05, 0x01)
  |> should.equal(0x05)
}

pub fn clear_flag_test() {
  frame.clear_flag(0x0F, 0x01)
  |> should.equal(0x0E)

  frame.clear_flag(0x0F, 0x10)
  |> should.equal(0x0F)
}

pub fn is_end_stream_test() {
  frame.is_end_stream(0x01)
  |> should.be_true()

  frame.is_end_stream(0x05)
  |> should.be_true()

  frame.is_end_stream(0x04)
  |> should.be_false()
}

pub fn is_end_headers_test() {
  frame.is_end_headers(0x04)
  |> should.be_true()

  frame.is_end_headers(0x05)
  |> should.be_true()

  frame.is_end_headers(0x01)
  |> should.be_false()
}

pub fn is_padded_test() {
  frame.is_padded(0x08)
  |> should.be_true()

  frame.is_padded(0x09)
  |> should.be_true()

  frame.is_padded(0x01)
  |> should.be_false()
}

pub fn is_priority_test() {
  frame.is_priority(0x20)
  |> should.be_true()

  frame.is_priority(0x21)
  |> should.be_true()

  frame.is_priority(0x01)
  |> should.be_false()
}

pub fn is_ack_test() {
  frame.is_ack(0x01)
  |> should.be_true()

  frame.is_ack(0x05)
  |> should.be_true()

  frame.is_ack(0x04)
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Type String Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn frame_type_to_string_test() {
  frame.frame_type_to_string(frame.Data)
  |> should.equal("DATA")

  frame.frame_type_to_string(frame.Headers)
  |> should.equal("HEADERS")

  frame.frame_type_to_string(frame.Settings)
  |> should.equal("SETTINGS")

  frame.frame_type_to_string(frame.Unknown(42))
  |> should.equal("UNKNOWN(42)")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Frame Header Validation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn validate_frame_header_valid_test() {
  let header =
    frame.FrameHeader(
      length: 100,
      frame_type: frame.Data,
      flags: 0,
      stream_id: 1,
    )

  frame.validate_frame_header(header, 16_384)
  |> should.be_ok()
}

pub fn validate_frame_header_too_large_test() {
  let header =
    frame.FrameHeader(
      length: 20_000,
      frame_type: frame.Data,
      flags: 0,
      stream_id: 1,
    )

  frame.validate_frame_header(header, 16_384)
  |> should.be_error()
}

pub fn validate_frame_header_settings_stream_zero_test() {
  let header =
    frame.FrameHeader(
      length: 0,
      frame_type: frame.Settings,
      flags: 0,
      stream_id: 0,
    )

  frame.validate_frame_header(header, 16_384)
  |> should.be_ok()
}

pub fn validate_frame_header_settings_invalid_stream_test() {
  let header =
    frame.FrameHeader(
      length: 0,
      frame_type: frame.Settings,
      flags: 0,
      stream_id: 1,
    )

  frame.validate_frame_header(header, 16_384)
  |> should.be_error()
}

pub fn validate_frame_header_data_stream_zero_test() {
  let header =
    frame.FrameHeader(
      length: 100,
      frame_type: frame.Data,
      flags: 0,
      stream_id: 0,
    )

  frame.validate_frame_header(header, 16_384)
  |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn frame_header_size_test() {
  frame.frame_header_size
  |> should.equal(9)
}

pub fn default_max_frame_size_test() {
  frame.default_max_frame_size
  |> should.equal(16_384)
}

pub fn max_frame_size_limit_test() {
  frame.max_frame_size_limit
  |> should.equal(16_777_215)
}

pub fn default_initial_window_size_test() {
  frame.default_initial_window_size
  |> should.equal(65_535)
}

pub fn default_header_table_size_test() {
  frame.default_header_table_size
  |> should.equal(4096)
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
