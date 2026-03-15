// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Stream State Machine
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Implements HTTP/2 stream lifecycle as per RFC 9113 Section 5.
// 
// Stream State Diagram (RFC 9113 Section 5.1):
//
//                          +--------+
//                  send PP |        | recv PP
//                 ,--------|  idle  |--------.
//                /         |        |         \
//               v          +--------+          v
//        +----------+          |          +----------+
//        |          |          | send H   |          |
// ,------| reserved |          | recv H   | reserved |------.
// |      | (local)  |          |          | (remote) |      |
// |      +----------+          v          +----------+      |
// |          |            +--------+            |           |
// |          |    send ES |        | recv ES    |           |
// |  send H  |   ,--------|  open  |--------.   |  recv H   |
// |          |  /         |        |         \  |           |
// |          v v          +--------+          v v           |
// |      +----------+          |          +----------+      |
// |      |   half   |          |          |   half   |      |
// |      |  closed  |          | send R   |  closed  |      |
// |      | (remote) |          | recv R   | (local)  |      |
// |      +----------+          |          +----------+      |
// |           |                |                 |          |
// |           | send ES        |        recv ES  |          |
// |           | send R         v         send R  |          |
// |           | recv R     +--------+    recv R  |          |
// |  send R   |            |        |            |  recv R  |
// `-----------+----------->|  closed |<---------++-----------'
//                          |        |
//                          +--------+
//
// PP = PUSH_PROMISE, H = HEADERS, ES = END_STREAM, R = RST_STREAM
//

import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result

import aether/protocol/http2/error.{
  type ErrorCode, type StreamError, ProtocolError, StreamClosed, StreamProtocol,
}
import aether/protocol/http2/frame.{default_initial_window_size}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream States (RFC 9113 Section 5.1)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// HTTP/2 stream states as defined in RFC 9113 Section 5.1
///
/// All streams start in the "idle" state. A stream can transition between
/// states based on the frames sent and received.
///
pub type StreamState {
  /// Initial state of all streams.
  /// Streams in "idle" state are not counted toward the concurrent stream limit.
  Idle

  /// Reserved (local) - A stream in this state is one that has been promised
  /// by sending a PUSH_PROMISE frame. The endpoint can send HEADERS to begin.
  ReservedLocal

  /// Reserved (remote) - A stream in this state is one that has been reserved
  /// by a remote peer with a PUSH_PROMISE frame.
  ReservedRemote

  /// Open - Both endpoints can send frames.
  /// A stream transitions to "open" when HEADERS is sent/received on an idle stream.
  Open

  /// Half-closed (local) - The local endpoint has sent END_STREAM.
  /// The endpoint cannot send frames other than WINDOW_UPDATE, PRIORITY, RST_STREAM.
  HalfClosedLocal

  /// Half-closed (remote) - The remote endpoint has sent END_STREAM.
  /// The endpoint cannot receive frames other than WINDOW_UPDATE, PRIORITY, RST_STREAM.
  HalfClosedRemote

  /// Closed - The stream is completely closed.
  /// Both endpoints cannot send frames other than PRIORITY.
  Closed
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Events (Actions that trigger transitions)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Events that can trigger stream state transitions
///
pub type StreamEvent {
  /// Sent HEADERS frame (without END_STREAM)
  SendHeaders

  /// Sent HEADERS frame with END_STREAM flag
  SendHeadersEndStream

  /// Received HEADERS frame (without END_STREAM)
  RecvHeaders

  /// Received HEADERS frame with END_STREAM flag
  RecvHeadersEndStream

  /// Sent DATA frame with END_STREAM flag
  SendEndStream

  /// Received END_STREAM flag
  RecvEndStream

  /// Sent PUSH_PROMISE frame (creates reserved local stream)
  SendPushPromise

  /// Received PUSH_PROMISE frame (creates reserved remote stream)
  RecvPushPromise

  /// Sent RST_STREAM frame
  SendRstStream

  /// Received RST_STREAM frame
  RecvRstStream
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Priority (RFC 9113 - Note: Deprecated but still parsed)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Stream priority information (deprecated in RFC 9113)
///
/// Note: While priority is deprecated in RFC 9113, we still need to parse
/// and handle it for backward compatibility with HTTP/2 implementations
/// that use priority.
///
pub type StreamPriority {
  StreamPriority(
    /// Parent stream dependency (0 = root)
    dependency: Int,
    /// Exclusive dependency flag
    exclusive: Bool,
    /// Weight (1-256, default 16)
    weight: Int,
  )
}

/// Default stream priority
///
pub const default_priority = StreamPriority(
  dependency: 0,
  exclusive: False,
  weight: 16,
)

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Type
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Represents a single HTTP/2 stream
///
/// A stream is a bidirectional flow of frames within an HTTP/2 connection.
/// Each stream has a unique identifier and maintains its own flow control
/// windows.
///
pub type Stream {
  Stream(
    /// Unique stream identifier
    /// - Odd IDs: Client-initiated streams
    /// - Even IDs: Server-initiated streams (PUSH_PROMISE)
    /// - 0: Connection-level (not a real stream)
    id: Int,
    /// Current state of the stream
    state: StreamState,
    /// Flow control window for sending (bytes available to send)
    send_window: Int,
    /// Flow control window for receiving (bytes available to receive)
    recv_window: Int,
    /// Stream priority information
    priority: StreamPriority,
    /// Whether the stream was reset (received RST_STREAM)
    reset: Bool,
    /// Error code if stream was reset
    reset_code: Option(ErrorCode),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Creation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new stream with the given ID
///
/// The stream starts in the Idle state with default flow control windows.
///
pub fn new(id: Int) -> Stream {
  Stream(
    id: id,
    state: Idle,
    send_window: default_initial_window_size,
    recv_window: default_initial_window_size,
    priority: default_priority,
    reset: False,
    reset_code: None,
  )
}

/// Creates a new stream with custom initial window sizes
///
pub fn new_with_windows(
  id: Int,
  initial_send_window: Int,
  initial_recv_window: Int,
) -> Stream {
  Stream(
    id: id,
    state: Idle,
    send_window: initial_send_window,
    recv_window: initial_recv_window,
    priority: default_priority,
    reset: False,
    reset_code: None,
  )
}

/// Creates a new stream in Reserved (local) state
/// Used when sending PUSH_PROMISE
///
pub fn new_reserved_local(id: Int) -> Stream {
  Stream(..new(id), state: ReservedLocal)
}

/// Creates a new stream in Reserved (remote) state
/// Used when receiving PUSH_PROMISE
///
pub fn new_reserved_remote(id: Int) -> Stream {
  Stream(..new(id), state: ReservedRemote)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// State Transitions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Applies a state transition event to a stream
///
/// Returns the updated stream or an error if the transition is invalid.
///
pub fn apply_event(
  stream: Stream,
  event: StreamEvent,
) -> Result(Stream, StreamError) {
  case transition(stream.state, event) {
    Ok(new_state) -> {
      // Check if stream is being reset
      case event {
        SendRstStream -> Ok(Stream(..stream, state: new_state, reset: True))
        RecvRstStream -> Ok(Stream(..stream, state: new_state, reset: True))
        _ -> Ok(Stream(..stream, state: new_state))
      }
    }
    Error(err) -> Error(err)
  }
  |> result.map_error(fn(err) {
    case err {
      StreamProtocol(_, code, msg) -> StreamProtocol(stream.id, code, msg)
      _ -> err
    }
  })
}

/// Computes the next state given current state and event
///
/// This implements the state machine from RFC 9113 Section 5.1
///
fn transition(
  state: StreamState,
  event: StreamEvent,
) -> Result(StreamState, StreamError) {
  case state, event {
    // ── Idle State Transitions ──
    Idle, SendHeaders -> Ok(Open)
    Idle, SendHeadersEndStream -> Ok(HalfClosedLocal)
    Idle, RecvHeaders -> Ok(Open)
    Idle, RecvHeadersEndStream -> Ok(HalfClosedRemote)
    Idle, SendPushPromise -> Ok(ReservedLocal)
    Idle, RecvPushPromise -> Ok(ReservedRemote)

    // ── Reserved (local) State Transitions ──
    ReservedLocal, SendHeaders -> Ok(HalfClosedRemote)
    ReservedLocal, SendHeadersEndStream -> Ok(Closed)
    ReservedLocal, SendRstStream -> Ok(Closed)
    ReservedLocal, RecvRstStream -> Ok(Closed)

    // ── Reserved (remote) State Transitions ──
    ReservedRemote, RecvHeaders -> Ok(HalfClosedLocal)
    ReservedRemote, RecvHeadersEndStream -> Ok(Closed)
    ReservedRemote, SendRstStream -> Ok(Closed)
    ReservedRemote, RecvRstStream -> Ok(Closed)

    // ── Open State Transitions ──
    Open, SendEndStream -> Ok(HalfClosedLocal)
    Open, SendHeadersEndStream -> Ok(HalfClosedLocal)
    Open, RecvEndStream -> Ok(HalfClosedRemote)
    Open, RecvHeadersEndStream -> Ok(HalfClosedRemote)
    Open, SendRstStream -> Ok(Closed)
    Open, RecvRstStream -> Ok(Closed)

    // ── Half-Closed (local) State Transitions ──
    HalfClosedLocal, RecvEndStream -> Ok(Closed)
    HalfClosedLocal, RecvHeadersEndStream -> Ok(Closed)
    HalfClosedLocal, SendRstStream -> Ok(Closed)
    HalfClosedLocal, RecvRstStream -> Ok(Closed)

    // ── Half-Closed (remote) State Transitions ──
    HalfClosedRemote, SendEndStream -> Ok(Closed)
    HalfClosedRemote, SendHeadersEndStream -> Ok(Closed)
    HalfClosedRemote, SendRstStream -> Ok(Closed)
    HalfClosedRemote, RecvRstStream -> Ok(Closed)

    // ── Closed State Transitions ──
    // No valid transitions out of closed
    Closed, _ ->
      Error(StreamProtocol(
        0,
        StreamClosed,
        "Cannot transition from closed state",
      ))

    // ── Invalid Transitions ──
    _, _ ->
      Error(StreamProtocol(
        0,
        ProtocolError,
        "Invalid state transition from "
          <> state_to_string(state)
          <> " on event "
          <> event_to_string(event),
      ))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// State Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks if the stream can send data
///
pub fn can_send(stream: Stream) -> Bool {
  case stream.state {
    Open | HalfClosedRemote -> True
    _ -> False
  }
}

/// Checks if the stream can receive data
///
pub fn can_receive(stream: Stream) -> Bool {
  case stream.state {
    Open | HalfClosedLocal -> True
    _ -> False
  }
}

/// Checks if the stream is active (not idle or closed)
///
pub fn is_active(stream: Stream) -> Bool {
  case stream.state {
    Idle | Closed -> False
    _ -> True
  }
}

/// Checks if the stream is closed
///
pub fn is_closed(stream: Stream) -> Bool {
  stream.state == Closed
}

/// Checks if the stream was reset
///
pub fn is_reset(stream: Stream) -> Bool {
  stream.reset
}

/// Checks if stream ID is client-initiated (odd)
///
pub fn is_client_initiated(stream_id: Int) -> Bool {
  stream_id > 0 && int.bitwise_and(stream_id, 1) == 1
}

/// Checks if stream ID is server-initiated (even)
///
pub fn is_server_initiated(stream_id: Int) -> Bool {
  stream_id > 0 && int.bitwise_and(stream_id, 1) == 0
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flow Control
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Updates the send window (consume bytes when sending)
///
pub fn consume_send_window(
  stream: Stream,
  bytes: Int,
) -> Result(Stream, StreamError) {
  case stream.send_window >= bytes {
    True -> Ok(Stream(..stream, send_window: stream.send_window - bytes))
    False ->
      Error(StreamProtocol(
        stream.id,
        error.FlowControlError,
        "Insufficient send window: available "
          <> int.to_string(stream.send_window)
          <> ", requested "
          <> int.to_string(bytes),
      ))
  }
}

/// Updates the recv window (consume bytes when receiving)
///
pub fn consume_recv_window(
  stream: Stream,
  bytes: Int,
) -> Result(Stream, StreamError) {
  case stream.recv_window >= bytes {
    True -> Ok(Stream(..stream, recv_window: stream.recv_window - bytes))
    False ->
      Error(StreamProtocol(
        stream.id,
        error.FlowControlError,
        "Flow control violation: received "
          <> int.to_string(bytes)
          <> " bytes, window is "
          <> int.to_string(stream.recv_window),
      ))
  }
}

/// Increments the send window (from WINDOW_UPDATE)
///
pub fn increment_send_window(
  stream: Stream,
  increment: Int,
) -> Result(Stream, StreamError) {
  let new_window = stream.send_window + increment
  // Maximum window size is 2^31-1 (RFC 9113 Section 6.9.1)
  case new_window > 2_147_483_647 {
    True ->
      Error(StreamProtocol(
        stream.id,
        error.FlowControlError,
        "Window size overflow",
      ))
    False -> Ok(Stream(..stream, send_window: new_window))
  }
}

/// Increments the recv window (for sending WINDOW_UPDATE)
///
pub fn increment_recv_window(
  stream: Stream,
  increment: Int,
) -> Result(Stream, StreamError) {
  let new_window = stream.recv_window + increment
  case new_window > 2_147_483_647 {
    True ->
      Error(StreamProtocol(
        stream.id,
        error.FlowControlError,
        "Window size overflow",
      ))
    False -> Ok(Stream(..stream, recv_window: new_window))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Priority Management
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the stream priority
///
pub fn set_priority(stream: Stream, priority: StreamPriority) -> Stream {
  Stream(..stream, priority: priority)
}

/// Sets stream dependency
///
pub fn set_dependency(
  stream: Stream,
  dependency: Int,
  exclusive: Bool,
) -> Stream {
  Stream(
    ..stream,
    priority: StreamPriority(
      dependency: dependency,
      exclusive: exclusive,
      weight: stream.priority.weight,
    ),
  )
}

/// Sets stream weight
///
pub fn set_weight(stream: Stream, weight: Int) -> Stream {
  // Weight must be 1-256
  let clamped_weight = case weight {
    w if w < 1 -> 1
    w if w > 256 -> 256
    w -> w
  }
  Stream(
    ..stream,
    priority: StreamPriority(..stream.priority, weight: clamped_weight),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Reset Stream
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Marks a stream as reset with the given error code
///
pub fn reset_stream(stream: Stream, code: ErrorCode) -> Stream {
  Stream(..stream, state: Closed, reset: True, reset_code: Some(code))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// String Conversion
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a StreamState to its string representation
///
pub fn state_to_string(state: StreamState) -> String {
  case state {
    Idle -> "idle"
    ReservedLocal -> "reserved (local)"
    ReservedRemote -> "reserved (remote)"
    Open -> "open"
    HalfClosedLocal -> "half-closed (local)"
    HalfClosedRemote -> "half-closed (remote)"
    Closed -> "closed"
  }
}

/// Converts a StreamEvent to its string representation
///
pub fn event_to_string(event: StreamEvent) -> String {
  case event {
    SendHeaders -> "send HEADERS"
    SendHeadersEndStream -> "send HEADERS+END_STREAM"
    RecvHeaders -> "recv HEADERS"
    RecvHeadersEndStream -> "recv HEADERS+END_STREAM"
    SendEndStream -> "send END_STREAM"
    RecvEndStream -> "recv END_STREAM"
    SendPushPromise -> "send PUSH_PROMISE"
    RecvPushPromise -> "recv PUSH_PROMISE"
    SendRstStream -> "send RST_STREAM"
    RecvRstStream -> "recv RST_STREAM"
  }
}

/// Formats a stream for debugging
///
pub fn to_string(stream: Stream) -> String {
  "Stream("
  <> "id="
  <> int.to_string(stream.id)
  <> ", state="
  <> state_to_string(stream.state)
  <> ", send_window="
  <> int.to_string(stream.send_window)
  <> ", recv_window="
  <> int.to_string(stream.recv_window)
  <> case stream.reset {
    True -> ", reset=true"
    False -> ""
  }
  <> ")"
}
