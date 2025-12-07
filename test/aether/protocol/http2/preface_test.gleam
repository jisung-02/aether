// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Preface Module Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/http2/frame
import aether/protocol/http2/preface
import gleam/bit_array
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Client Preface Magic Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn client_preface_magic_size_test() {
  bit_array.byte_size(preface.client_preface_magic)
  |> should.equal(24)
}

pub fn client_preface_magic_content_test() {
  // "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  let expected = <<
    0x50, 0x52, 0x49, 0x20, 0x2a, 0x20, 0x48, 0x54, 0x54, 0x50, 0x2f, 0x32, 0x2e,
    0x30, 0x0d, 0x0a, 0x0d, 0x0a, 0x53, 0x4d, 0x0d, 0x0a, 0x0d, 0x0a,
  >>

  preface.client_preface_magic
  |> should.equal(expected)
}

pub fn client_preface_size_constant_test() {
  preface.client_preface_size
  |> should.equal(24)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Client Preface Validation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn validate_client_preface_valid_test() {
  let data = preface.client_preface_magic

  case preface.validate_client_preface(data) {
    preface.ValidPreface(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn validate_client_preface_with_extra_data_test() {
  let extra = <<"extra data":utf8>>
  let data = bit_array.concat([preface.client_preface_magic, extra])

  case preface.validate_client_preface(data) {
    preface.ValidPreface(remaining) -> remaining |> should.equal(extra)
    _ -> should.fail()
  }
}

pub fn validate_client_preface_insufficient_data_test() {
  let data = <<0x50, 0x52, 0x49>>
  // Only 3 bytes

  case preface.validate_client_preface(data) {
    preface.InsufficientData(needed, available) -> {
      needed |> should.equal(24)
      available |> should.equal(3)
    }
    _ -> should.fail()
  }
}

pub fn validate_client_preface_invalid_magic_test() {
  let data = <<
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  >>

  case preface.validate_client_preface(data) {
    preface.InvalidMagic -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn is_valid_client_preface_test() {
  preface.is_valid_client_preface(preface.client_preface_magic)
  |> should.be_true()

  preface.is_valid_client_preface(<<0, 0, 0>>)
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Client Preface Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn create_client_preface_default_test() {
  let preface_bytes = preface.create_client_preface_default()

  // Should start with magic string
  case bit_array.slice(preface_bytes, 0, 24) {
    Ok(magic) -> magic |> should.equal(preface.client_preface_magic)
    Error(_) -> should.fail()
  }

  // Should have at least magic (24) + settings header (9)
  { bit_array.byte_size(preface_bytes) >= 33 }
  |> should.be_true()
}

pub fn create_client_preface_with_settings_test() {
  let params = [
    frame.SettingsParameter(identifier: frame.MaxConcurrentStreams, value: 100),
  ]
  let preface_bytes = preface.create_client_preface(params)

  // Should start with magic
  case bit_array.slice(preface_bytes, 0, 24) {
    Ok(magic) -> magic |> should.equal(preface.client_preface_magic)
    Error(_) -> should.fail()
  }

  // Total size: magic (24) + settings header (9) + 1 param (6) = 39
  bit_array.byte_size(preface_bytes)
  |> should.equal(39)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Server Preface Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn create_server_preface_default_test() {
  let preface_bytes = preface.create_server_preface_default()

  // Server preface is just a SETTINGS frame, header is 9 bytes
  { bit_array.byte_size(preface_bytes) >= 9 }
  |> should.be_true()
}

pub fn create_server_preface_with_settings_test() {
  let params = [
    frame.SettingsParameter(identifier: frame.MaxFrameSize, value: 32_768),
    frame.SettingsParameter(identifier: frame.InitialWindowSize, value: 65_535),
  ]
  let preface_bytes = preface.create_server_preface(params)

  // Size: header (9) + 2 params (12) = 21
  bit_array.byte_size(preface_bytes)
  |> should.equal(21)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Settings Ack Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn create_settings_ack_test() {
  let ack_bytes = preface.create_settings_ack()

  // SETTINGS ACK is just 9 bytes (header only, no payload)
  bit_array.byte_size(ack_bytes)
  |> should.equal(9)
}

pub fn is_settings_ack_test() {
  let ack_frame =
    frame.SettingsF(
      frame.FrameHeader(
        length: 0,
        frame_type: frame.Settings,
        flags: frame.flag_ack,
        stream_id: 0,
      ),
      frame.SettingsFrame(ack: True, parameters: []),
    )

  preface.is_settings_ack(ack_frame)
  |> should.be_true()
}

pub fn is_settings_ack_not_ack_test() {
  let settings_frame =
    frame.SettingsF(
      frame.FrameHeader(
        length: 0,
        frame_type: frame.Settings,
        flags: 0,
        stream_id: 0,
      ),
      frame.SettingsFrame(ack: False, parameters: []),
    )

  preface.is_settings_ack(settings_frame)
  |> should.be_false()
}

pub fn is_settings_ack_wrong_type_test() {
  let data_frame =
    frame.DataF(
      frame.FrameHeader(
        length: 5,
        frame_type: frame.Data,
        flags: 0,
        stream_id: 1,
      ),
      frame.DataFrame(pad_length: 0, data: <<"hello":utf8>>),
    )

  preface.is_settings_ack(data_frame)
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Default Settings Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn default_settings_test() {
  let settings = preface.default_settings()

  // Should have 4 default settings
  list_length(settings)
  |> should.equal(4)
}

pub fn recommended_server_settings_test() {
  let settings = preface.recommended_server_settings()

  // Should have 3 recommended settings
  list_length(settings)
  |> should.equal(3)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Preface State Machine Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn after_client_magic_test() {
  preface.after_client_magic()
  |> should.equal(preface.AwaitingClientSettings)
}

pub fn after_client_settings_test() {
  preface.after_client_settings()
  |> should.equal(preface.AwaitingSettingsAck)
}

pub fn after_server_settings_test() {
  preface.after_server_settings()
  |> should.equal(preface.AwaitingSettingsAck)
}

pub fn after_settings_ack_test() {
  preface.after_settings_ack(preface.AwaitingSettingsAck)
  |> should.equal(preface.PrefaceComplete)

  // Other states don't change
  preface.after_settings_ack(preface.AwaitingClientMagic)
  |> should.equal(preface.AwaitingClientMagic)
}

pub fn is_preface_complete_test() {
  preface.is_preface_complete(preface.PrefaceComplete)
  |> should.be_true()

  preface.is_preface_complete(preface.AwaitingClientMagic)
  |> should.be_false()

  preface.is_preface_complete(preface.AwaitingSettingsAck)
  |> should.be_false()
}

pub fn state_to_string_test() {
  preface.state_to_string(preface.AwaitingClientMagic)
  |> should.equal("AwaitingClientMagic")

  preface.state_to_string(preface.AwaitingClientSettings)
  |> should.equal("AwaitingClientSettings")

  preface.state_to_string(preface.AwaitingServerSettings)
  |> should.equal("AwaitingServerSettings")

  preface.state_to_string(preface.AwaitingSettingsAck)
  |> should.equal("AwaitingSettingsAck")

  preface.state_to_string(preface.PrefaceComplete)
  |> should.equal("PrefaceComplete")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Process Client Preface Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn process_client_preface_valid_test() {
  // Create a complete client preface with magic + SETTINGS
  let client_preface = preface.create_client_preface_default()

  case preface.process_client_preface(client_preface) {
    Ok(#(_settings, _remaining)) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

pub fn process_client_preface_invalid_magic_test() {
  let bad_preface = <<
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  >>

  case preface.process_client_preface(bad_preface) {
    Ok(_) -> should.fail()
    Error(_) -> should.be_true(True)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Process Server Preface Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn process_server_preface_valid_test() {
  let server_preface = preface.create_server_preface_default()

  case preface.process_server_preface(server_preface) {
    Ok(#(_settings, _remaining)) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn list_length(items: List(a)) -> Int {
  list_length_helper(items, 0)
}

fn list_length_helper(items: List(a), acc: Int) -> Int {
  case items {
    [] -> acc
    [_, ..rest] -> list_length_helper(rest, acc + 1)
  }
}
