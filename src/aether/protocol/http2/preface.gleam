// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Connection Preface
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Handles HTTP/2 connection initialization as per RFC 9113 Section 3.4.
// The connection preface is the first bytes sent by both client and server.
//
// Client Preface:
//   1. The 24-byte magic string "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
//   2. A SETTINGS frame (may be empty)
//
// Server Preface:
//   1. A SETTINGS frame (may be empty)
//

import aether/protocol/http2/error.{
  type ConnectionError, InvalidPreface, Protocol,
}
import aether/protocol/http2/frame.{
  type Frame, type SettingsFrame, type SettingsParameter, SettingsF,
}
import aether/protocol/http2/frame_builder
import aether/protocol/http2/frame_parser
import gleam/bit_array

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// The HTTP/2 client connection preface magic string
/// "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
///
pub const client_preface_magic = <<
  // "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  0x50, 0x52, 0x49, 0x20, 0x2a, 0x20, 0x48, 0x54, 0x54, 0x50, 0x2f, 0x32, 0x2e,
  0x30, 0x0d, 0x0a, 0x0d, 0x0a, 0x53, 0x4d, 0x0d, 0x0a, 0x0d, 0x0a,
>>

/// Size of the client preface magic string (24 bytes)
pub const client_preface_size = 24

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Result of validating the client preface
///
pub type PrefaceResult {
  /// Valid preface with remaining data after the magic string
  ValidPreface(remaining: BitArray)

  /// Not enough data to validate preface
  InsufficientData(needed: Int, available: Int)

  /// Invalid preface magic string
  InvalidMagic
}

/// State of preface exchange
///
pub type PrefaceState {
  /// Awaiting client preface magic
  AwaitingClientMagic

  /// Awaiting client SETTINGS frame
  AwaitingClientSettings

  /// Awaiting server SETTINGS frame
  AwaitingServerSettings

  /// Awaiting SETTINGS acknowledgment from peer
  AwaitingSettingsAck

  /// Preface exchange complete
  PrefaceComplete
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Client Preface Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates the complete client connection preface
///
/// Returns the 24-byte magic string followed by a SETTINGS frame
/// with the provided parameters.
///
pub fn create_client_preface(settings: List(SettingsParameter)) -> BitArray {
  let settings_frame = frame_builder.create_settings_frame(settings)
  let settings_bytes = frame_builder.build_frame(settings_frame)

  bit_array.concat([client_preface_magic, settings_bytes])
}

/// Creates the complete client connection preface with default settings
///
pub fn create_client_preface_default() -> BitArray {
  create_client_preface([])
}

/// Validates the client preface magic string
///
/// Returns the remaining data after the magic string if valid.
///
pub fn validate_client_preface(data: BitArray) -> PrefaceResult {
  let available = bit_array.byte_size(data)

  case available < client_preface_size {
    True -> InsufficientData(client_preface_size, available)
    False -> {
      case bit_array.slice(data, 0, client_preface_size) {
        Error(_) -> InvalidMagic
        Ok(magic) -> {
          case magic == client_preface_magic {
            False -> InvalidMagic
            True -> {
              case
                bit_array.slice(
                  data,
                  client_preface_size,
                  available - client_preface_size,
                )
              {
                Error(_) -> ValidPreface(<<>>)
                Ok(remaining) -> ValidPreface(remaining)
              }
            }
          }
        }
      }
    }
  }
}

/// Checks if data starts with a valid client preface
///
pub fn is_valid_client_preface(data: BitArray) -> Bool {
  case validate_client_preface(data) {
    ValidPreface(_) -> True
    _ -> False
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Server Preface Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates the server connection preface
///
/// The server preface consists of only a SETTINGS frame.
///
pub fn create_server_preface(settings: List(SettingsParameter)) -> BitArray {
  let settings_frame = frame_builder.create_settings_frame(settings)
  frame_builder.build_frame(settings_frame)
}

/// Creates the server connection preface with default settings
///
pub fn create_server_preface_default() -> BitArray {
  create_server_preface([])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Preface Exchange Handling
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Processes the client preface on the server side
///
/// Validates the magic string and extracts the initial SETTINGS frame.
///
pub fn process_client_preface(
  data: BitArray,
) -> Result(#(SettingsFrame, BitArray), ConnectionError) {
  case validate_client_preface(data) {
    InsufficientData(needed, available) ->
      Error(InvalidPreface(
        "Need "
        <> int_to_string(needed)
        <> " bytes, have "
        <> int_to_string(available),
      ))

    InvalidMagic -> Error(InvalidPreface("Invalid client preface magic"))

    ValidPreface(remaining) -> {
      // Parse the SETTINGS frame that follows the magic
      case frame_parser.parse_frame(remaining) {
        Error(e) ->
          Error(InvalidPreface(
            "Failed to parse SETTINGS: " <> error.parse_error_to_string(e),
          ))

        Ok(result) -> {
          case result.frame {
            SettingsF(_, settings) -> Ok(#(settings, result.remaining))
            _ ->
              Error(Protocol(
                error.ProtocolError,
                "First frame must be SETTINGS",
              ))
          }
        }
      }
    }
  }
}

/// Processes the server preface on the client side
///
/// Validates that the first frame is a SETTINGS frame.
///
pub fn process_server_preface(
  data: BitArray,
) -> Result(#(SettingsFrame, BitArray), ConnectionError) {
  case frame_parser.parse_frame(data) {
    Error(e) ->
      Error(InvalidPreface(
        "Failed to parse SETTINGS: " <> error.parse_error_to_string(e),
      ))

    Ok(result) -> {
      case result.frame {
        SettingsF(_, settings) -> Ok(#(settings, result.remaining))
        _ ->
          Error(Protocol(error.ProtocolError, "First frame must be SETTINGS"))
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Settings Acknowledgment
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a SETTINGS acknowledgment frame
///
pub fn create_settings_ack() -> BitArray {
  let ack_frame = frame_builder.create_settings_ack_frame()
  frame_builder.build_frame(ack_frame)
}

/// Validates that a frame is a SETTINGS acknowledgment
///
pub fn is_settings_ack(frame: Frame) -> Bool {
  case frame {
    SettingsF(_, settings) -> settings.ack
    _ -> False
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Default Settings
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates default settings for a new connection
///
pub fn default_settings() -> List(SettingsParameter) {
  [
    // Default header table size: 4096
    frame.SettingsParameter(
      identifier: frame.HeaderTableSize,
      value: frame.default_header_table_size,
    ),
    // Enable push: enabled
    frame.SettingsParameter(
      identifier: frame.EnablePush,
      value: frame.default_enable_push,
    ),
    // Initial window size: 65535
    frame.SettingsParameter(
      identifier: frame.InitialWindowSize,
      value: frame.default_initial_window_size,
    ),
    // Max frame size: 16384
    frame.SettingsParameter(
      identifier: frame.MaxFrameSize,
      value: frame.default_max_frame_size,
    ),
  ]
}

/// Creates recommended server settings
///
pub fn recommended_server_settings() -> List(SettingsParameter) {
  [
    // Larger initial window for better performance
    frame.SettingsParameter(identifier: frame.InitialWindowSize, value: 65_535),
    // Allow concurrent streams
    frame.SettingsParameter(identifier: frame.MaxConcurrentStreams, value: 100),
    // Standard max frame size
    frame.SettingsParameter(
      identifier: frame.MaxFrameSize,
      value: frame.default_max_frame_size,
    ),
  ]
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn int_to_string(n: Int) -> String {
  case n < 0 {
    True -> "-" <> int_to_string_positive(-n)
    False -> int_to_string_positive(n)
  }
}

fn int_to_string_positive(n: Int) -> String {
  case n < 10 {
    True -> digit_to_string(n)
    False -> int_to_string_positive(n / 10) <> digit_to_string(n % 10)
  }
}

fn digit_to_string(d: Int) -> String {
  case d {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    _ -> "?"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Preface State Machine
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the next state after processing client magic
///
pub fn after_client_magic() -> PrefaceState {
  AwaitingClientSettings
}

/// Gets the next state after receiving client SETTINGS
///
pub fn after_client_settings() -> PrefaceState {
  AwaitingSettingsAck
}

/// Gets the next state after receiving server SETTINGS
///
pub fn after_server_settings() -> PrefaceState {
  AwaitingSettingsAck
}

/// Gets the next state after receiving SETTINGS ACK
///
pub fn after_settings_ack(current: PrefaceState) -> PrefaceState {
  case current {
    AwaitingSettingsAck -> PrefaceComplete
    _ -> current
  }
}

/// Checks if preface exchange is complete
///
pub fn is_preface_complete(state: PrefaceState) -> Bool {
  case state {
    PrefaceComplete -> True
    _ -> False
  }
}

/// Returns a string representation of the preface state
///
pub fn state_to_string(state: PrefaceState) -> String {
  case state {
    AwaitingClientMagic -> "AwaitingClientMagic"
    AwaitingClientSettings -> "AwaitingClientSettings"
    AwaitingServerSettings -> "AwaitingServerSettings"
    AwaitingSettingsAck -> "AwaitingSettingsAck"
    PrefaceComplete -> "PrefaceComplete"
  }
}
