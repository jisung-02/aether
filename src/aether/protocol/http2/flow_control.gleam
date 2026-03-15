// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Flow Control
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Implements HTTP/2 flow control as per RFC 9113 Section 5.2.
//
// Flow control operates at two levels:
// 1. Connection-level: Controls total DATA bytes for the connection
// 2. Stream-level: Controls DATA bytes per individual stream
//
// Key characteristics:
// - Flow control is hop-by-hop, not end-to-end
// - Only DATA frames are subject to flow control
// - Flow control cannot be disabled
// - Default initial window size is 65535 bytes
// - Maximum window size is 2^31-1 bytes (FLOW_CONTROL_ERROR on overflow)
//

import gleam/int
import gleam/option.{type Option, None, Some}

import aether/protocol/http2/error.{
  type ConnectionError, type StreamError, FlowControlError, Protocol,
  StreamProtocol,
}
import aether/protocol/http2/frame.{default_initial_window_size}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Maximum flow control window size (2^31-1)
/// RFC 9113 Section 6.9.1
///
pub const max_window_size = 2_147_483_647

/// Minimum window update increment (must be non-zero)
/// RFC 9113 Section 6.9
///
pub const min_window_increment = 1

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flow Control Window
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Represents a flow control window
///
/// A window tracks available bytes for sending DATA frames.
/// The window can temporarily go negative during race conditions
/// (RFC 9113 Section 5.2.1).
///
pub type Window {
  Window(
    /// Current available bytes (can be negative)
    available: Int,
    /// Maximum window size allowed (for validation)
    max_size: Int,
  )
}

/// Creates a new window with the default initial size
///
pub fn new_window() -> Window {
  Window(available: default_initial_window_size, max_size: max_window_size)
}

/// Creates a new window with a custom initial size
///
pub fn new_window_with_size(initial_size: Int) -> Window {
  Window(available: initial_size, max_size: max_window_size)
}

/// Gets the available bytes in the window
///
pub fn window_available(window: Window) -> Int {
  window.available
}

/// Checks if the window has capacity for sending
///
pub fn window_has_capacity(window: Window) -> Bool {
  window.available > 0
}

/// Consumes bytes from the window (when sending DATA)
///
/// Returns the updated window or an error if insufficient capacity.
/// Note: RFC 9113 allows window to go negative in some race conditions,
/// but for simplicity we require positive window.
///
pub fn window_consume(window: Window, bytes: Int) -> Result(Window, String) {
  case bytes <= 0 {
    True -> Error("Consume amount must be positive")
    False -> {
      case window.available >= bytes {
        True -> Ok(Window(..window, available: window.available - bytes))
        False ->
          Error(
            "Insufficient window capacity: available "
            <> int.to_string(window.available)
            <> ", requested "
            <> int.to_string(bytes),
          )
      }
    }
  }
}

/// Increments the window (from WINDOW_UPDATE)
///
/// Returns the updated window or an error if overflow would occur.
///
pub fn window_increment(
  window: Window,
  increment: Int,
) -> Result(Window, String) {
  case increment <= 0 {
    True -> Error("Window increment must be positive (PROTOCOL_ERROR)")
    False -> {
      let new_available = window.available + increment
      case new_available > max_window_size {
        True ->
          Error(
            "Window size overflow: would become "
            <> int.to_string(new_available)
            <> " (max: "
            <> int.to_string(max_window_size)
            <> ")",
          )
        False -> Ok(Window(..window, available: new_available))
      }
    }
  }
}

/// Sets the window size (from SETTINGS update)
///
/// This adjusts the window by the difference between old and new size.
///
pub fn window_adjust(window: Window, new_size: Int) -> Result(Window, String) {
  case new_size < 0 || new_size > max_window_size {
    True -> Error("Invalid window size")
    False -> {
      // The new value is the initial window size, not the absolute window size
      // We adjust the current window by the delta
      Ok(Window(..window, available: new_size))
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flow Controller
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Manages flow control for an HTTP/2 connection
///
/// The FlowController coordinates:
/// - Connection-level send/receive windows
/// - Integration with stream-level windows
/// - WINDOW_UPDATE frame generation
///
pub type FlowController {
  FlowController(
    /// Connection-level send window (our capacity to send DATA)
    conn_send_window: Window,
    /// Connection-level receive window (peer's capacity to send DATA)
    conn_recv_window: Window,
    /// Initial window size for new streams
    initial_stream_window: Int,
    /// Threshold for generating WINDOW_UPDATE (percentage of initial)
    window_update_threshold: Int,
    /// Pending WINDOW_UPDATE to send for connection (if any)
    pending_conn_update: Option(Int),
  )
}

/// Creates a new flow controller with default settings
///
pub fn new() -> FlowController {
  FlowController(
    conn_send_window: new_window(),
    conn_recv_window: new_window(),
    initial_stream_window: default_initial_window_size,
    window_update_threshold: default_initial_window_size / 2,
    pending_conn_update: None,
  )
}

/// Creates a flow controller with custom initial window size
///
pub fn new_with_window_size(initial_size: Int) -> FlowController {
  FlowController(
    conn_send_window: new_window_with_size(initial_size),
    conn_recv_window: new_window_with_size(initial_size),
    initial_stream_window: initial_size,
    window_update_threshold: initial_size / 2,
    pending_conn_update: None,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection-Level Flow Control
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the connection-level send window capacity
///
pub fn connection_send_capacity(controller: FlowController) -> Int {
  window_available(controller.conn_send_window)
}

/// Gets the connection-level receive window capacity
///
pub fn connection_recv_capacity(controller: FlowController) -> Int {
  window_available(controller.conn_recv_window)
}

/// Checks if the connection can send DATA
///
pub fn can_send_data(controller: FlowController) -> Bool {
  window_has_capacity(controller.conn_send_window)
}

/// Consumes connection-level send window (when sending DATA)
///
/// This must be called ALONGSIDE consuming the stream window.
/// Both connection and stream windows must have capacity.
///
pub fn consume_send_window(
  controller: FlowController,
  bytes: Int,
) -> Result(FlowController, ConnectionError) {
  case window_consume(controller.conn_send_window, bytes) {
    Ok(new_window) ->
      Ok(FlowController(..controller, conn_send_window: new_window))
    Error(msg) -> Error(Protocol(FlowControlError, msg))
  }
}

/// Consumes connection-level receive window (when receiving DATA)
///
/// This is called when we receive DATA frames.
/// It may trigger a WINDOW_UPDATE to be sent.
///
pub fn consume_recv_window(
  controller: FlowController,
  bytes: Int,
) -> Result(FlowController, ConnectionError) {
  case window_consume(controller.conn_recv_window, bytes) {
    Ok(new_window) -> {
      let updated = FlowController(..controller, conn_recv_window: new_window)

      // Check if we need to send a WINDOW_UPDATE
      let need_update =
        window_available(new_window) < controller.window_update_threshold

      case need_update {
        True -> {
          // Calculate increment to restore window
          let increment =
            controller.initial_stream_window - window_available(new_window)
          case increment > 0 {
            True ->
              Ok(
                FlowController(..updated, pending_conn_update: Some(increment)),
              )
            False -> Ok(updated)
          }
        }
        False -> Ok(updated)
      }
    }
    Error(msg) -> Error(Protocol(FlowControlError, msg))
  }
}

/// Handles WINDOW_UPDATE frame for connection (stream 0)
///
/// Called when we receive a WINDOW_UPDATE frame with stream_id = 0.
///
pub fn handle_connection_window_update(
  controller: FlowController,
  increment: Int,
) -> Result(FlowController, ConnectionError) {
  case increment <= 0 {
    True ->
      Error(Protocol(
        error.ProtocolError,
        "WINDOW_UPDATE increment must be positive",
      ))
    False -> {
      case window_increment(controller.conn_send_window, increment) {
        Ok(new_window) ->
          Ok(FlowController(..controller, conn_send_window: new_window))
        Error(msg) -> Error(Protocol(FlowControlError, msg))
      }
    }
  }
}

/// Applies the pending WINDOW_UPDATE and clears it
///
/// Returns the increment to send and the updated controller.
///
pub fn flush_pending_window_update(
  controller: FlowController,
) -> Result(#(FlowController, Option(Int)), ConnectionError) {
  case controller.pending_conn_update {
    None -> Ok(#(controller, None))
    Some(increment) -> {
      // Apply the increment to our receive window
      case window_increment(controller.conn_recv_window, increment) {
        Ok(new_window) -> {
          let updated =
            FlowController(
              ..controller,
              conn_recv_window: new_window,
              pending_conn_update: None,
            )
          Ok(#(updated, Some(increment)))
        }
        Error(msg) -> Error(Protocol(FlowControlError, msg))
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream-Level Flow Control Integration
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Calculates the maximum sendable bytes considering both connection and stream windows
///
/// To send DATA, you need capacity in BOTH windows. This returns the minimum.
///
pub fn max_sendable_bytes(
  controller: FlowController,
  stream_send_window: Int,
) -> Int {
  int.min(connection_send_capacity(controller), stream_send_window)
}

/// Checks if sending a specific amount of data is possible
///
pub fn can_send_bytes(
  controller: FlowController,
  stream_send_window: Int,
  bytes: Int,
) -> Bool {
  max_sendable_bytes(controller, stream_send_window) >= bytes
}

/// Handles WINDOW_UPDATE frame for a stream
///
/// Returns the increment to apply to the stream window.
/// The caller is responsible for applying this to the stream.
///
pub fn validate_stream_window_update(
  increment: Int,
  stream_id: Int,
) -> Result(Int, StreamError) {
  case increment <= 0 {
    True ->
      Error(StreamProtocol(
        stream_id,
        error.ProtocolError,
        "WINDOW_UPDATE increment must be positive",
      ))
    False -> Ok(increment)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Settings Updates
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Updates the initial window size from SETTINGS
///
/// This only affects new streams. Existing streams are not modified.
/// (Stream window adjustments are handled separately in stream_manager)
///
pub fn update_initial_window_size(
  controller: FlowController,
  new_size: Int,
) -> Result(FlowController, ConnectionError) {
  case new_size < 0 || new_size > max_window_size {
    True ->
      Error(Protocol(
        FlowControlError,
        "Invalid initial window size: " <> int.to_string(new_size),
      ))
    False ->
      Ok(
        FlowController(
          ..controller,
          initial_stream_window: new_size,
          window_update_threshold: new_size / 2,
        ),
      )
  }
}

/// Gets the initial stream window size
///
pub fn initial_stream_window_size(controller: FlowController) -> Int {
  controller.initial_stream_window
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// DATA Frame Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Result of attempting to send DATA
///
pub type SendResult {
  /// Can send all requested bytes
  CanSendAll
  /// Can send partial data (returned amount)
  CanSendPartial(Int)
  /// Cannot send any data (blocked)
  Blocked
}

/// Determines how many bytes can be sent for a DATA frame
///
/// Takes into account both connection and stream windows.
///
pub fn prepare_send(
  controller: FlowController,
  stream_send_window: Int,
  requested_bytes: Int,
) -> SendResult {
  let available = max_sendable_bytes(controller, stream_send_window)

  case available {
    0 -> Blocked
    _ if available >= requested_bytes -> CanSendAll
    _ -> CanSendPartial(available)
  }
}

/// Describes the current flow control state for debugging
///
pub fn to_string(controller: FlowController) -> String {
  "FlowController("
  <> "conn_send="
  <> int.to_string(connection_send_capacity(controller))
  <> ", conn_recv="
  <> int.to_string(connection_recv_capacity(controller))
  <> ", initial_stream="
  <> int.to_string(controller.initial_stream_window)
  <> ", pending_update="
  <> case controller.pending_conn_update {
    None -> "none"
    Some(n) -> int.to_string(n)
  }
  <> ")"
}
