// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Module - Per-Connection Actor
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// This module implements the per-connection actor that manages the
// lifecycle of a single client connection. Each connection gets its
// own actor process for isolated failure handling and state management.
//

import aether/network/socket.{type Socket}
import aether/network/socket_error.{type SocketError}
import aether/network/tcp
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/option.{type Option, None, Some}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Unique identifier for a connection
pub type ConnectionId =
  Int

/// State of a connection in its lifecycle
pub type ConnectionState {
  /// Connection is active and ready for I/O
  Active
  /// Connection is idle (no recent activity)
  Idle
  /// Connection is being drained (finishing current work)
  Draining
  /// Connection is in the process of closing
  Closing
}

/// Information about a connection
pub type ConnectionInfo {
  ConnectionInfo(
    /// Unique connection identifier
    id: ConnectionId,
    /// The underlying socket
    socket: Socket,
    /// Current connection state
    state: ConnectionState,
    /// Monotonic timestamp when connection was created (milliseconds)
    created_at: Int,
    /// Monotonic timestamp of last activity (milliseconds)
    last_activity_at: Int,
    /// Total bytes received on this connection
    bytes_received: Int,
    /// Total bytes sent on this connection
    bytes_sent: Int,
  )
}

/// Messages handled by the Connection actor
pub type ConnectionMessage {
  /// Data received from the socket (in active mode)
  SocketData(data: BitArray)
  /// Socket has been closed by peer
  SocketClosed
  /// Socket error occurred
  SocketError(error: SocketError)
  /// Send data to the peer
  Send(data: BitArray, reply_to: Subject(Result(Nil, SocketError)))
  /// Receive data from the peer (blocking)
  Recv(length: Int, timeout_ms: Int, reply_to: Subject(Result(BitArray, SocketError)))
  /// Get connection information
  GetInfo(reply_to: Subject(ConnectionInfo))
  /// Start draining (stop accepting new work)
  Drain
  /// Close the connection
  Close
  /// Internal: keep-alive check
  KeepAliveCheck
}

/// Notifications sent from Connection to Manager
pub type ManagerNotification {
  /// Connection has been closed
  ConnectionClosed(id: ConnectionId)
  /// Error occurred on connection
  ConnectionError(id: ConnectionId, error: SocketError)
  /// Connection had activity
  ConnectionActivity(id: ConnectionId)
}

/// Handler function type for processing received data
///
/// The handler receives the connection ID and received data,
/// and returns optional response data to send back.
///
pub type ConnectionHandler =
  fn(ConnectionId, BitArray) -> Result(Option(BitArray), String)

/// Connection actor error type
pub type ConnectionError {
  /// Failed to start the actor
  StartFailed(reason: String)
  /// Socket operation failed
  SocketOperationFailed(error: SocketError)
}

/// Internal state for the Connection actor
type State {
  State(
    info: ConnectionInfo,
    manager: Subject(ManagerNotification),
    handler: Option(ConnectionHandler),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Actor API
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Starts a new Connection actor for the given socket
///
/// ## Parameters
///
/// - `sock`: The connected socket for this connection
/// - `id`: Unique identifier for this connection
/// - `manager`: Subject to notify the manager of events
/// - `handler`: Optional handler for processing received data
///
/// ## Returns
///
/// Subject to communicate with the Connection actor
///
pub fn start(
  sock: Socket,
  id: ConnectionId,
  manager: Subject(ManagerNotification),
  handler: Option(ConnectionHandler),
) -> Result(Subject(ConnectionMessage), actor.StartError) {
  let now = monotonic_time_ms()
  let initial_info =
    ConnectionInfo(
      id: id,
      socket: sock,
      state: Active,
      created_at: now,
      last_activity_at: now,
      bytes_received: 0,
      bytes_sent: 0,
    )

  let initial_state = State(info: initial_info, manager: manager, handler: handler)

  case
    actor.new(initial_state)
    |> actor.on_message(handle_message)
    |> actor.start
  {
    Ok(started) -> Ok(started.data)
    Error(err) -> Error(err)
  }
}

/// Sends data over the connection
///
/// ## Parameters
///
/// - `connection`: The connection actor subject
/// - `data`: Data to send
/// - `timeout_ms`: Timeout in milliseconds
///
/// ## Returns
///
/// Ok(Nil) on success, Error with SocketError on failure
///
pub fn send(
  connection: Subject(ConnectionMessage),
  data: BitArray,
  timeout_ms: Int,
) -> Result(Nil, SocketError) {
  actor.call(connection, timeout_ms, fn(reply_to) { Send(data, reply_to) })
}

/// Receives data from the connection
///
/// ## Parameters
///
/// - `connection`: The connection actor subject
/// - `length`: Maximum bytes to receive (0 for any)
/// - `timeout_ms`: Timeout in milliseconds
///
/// ## Returns
///
/// Received data or SocketError
///
pub fn recv(
  connection: Subject(ConnectionMessage),
  length: Int,
  timeout_ms: Int,
) -> Result(BitArray, SocketError) {
  actor.call(
    connection,
    timeout_ms + 100,
    fn(reply_to) { Recv(length, timeout_ms, reply_to) },
  )
}

/// Gets information about the connection
///
/// ## Parameters
///
/// - `connection`: The connection actor subject
/// - `timeout_ms`: Timeout in milliseconds
///
/// ## Returns
///
/// ConnectionInfo or Nil on timeout
///
pub fn get_info(
  connection: Subject(ConnectionMessage),
  timeout_ms: Int,
) -> ConnectionInfo {
  actor.call(connection, timeout_ms, fn(reply_to) { GetInfo(reply_to) })
}

/// Initiates connection draining
///
/// The connection will finish current work but not accept new requests.
///
pub fn drain(connection: Subject(ConnectionMessage)) -> Nil {
  actor.send(connection, Drain)
}

/// Closes the connection
///
pub fn close(connection: Subject(ConnectionMessage)) -> Nil {
  actor.send(connection, Close)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Message Handler
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn handle_message(
  state: State,
  message: ConnectionMessage,
) -> actor.Next(State, ConnectionMessage) {
  case message {
    SocketData(data) -> handle_socket_data(state, data)

    SocketClosed -> handle_socket_closed(state)

    SocketError(error) -> handle_socket_error(state, error)

    Send(data, reply_to) -> handle_send(state, data, reply_to)

    Recv(length, timeout_ms, reply_to) ->
      handle_recv(state, length, timeout_ms, reply_to)

    GetInfo(reply_to) -> handle_get_info(state, reply_to)

    Drain -> handle_drain(state)

    Close -> handle_close(state)

    KeepAliveCheck -> handle_keep_alive_check(state)
  }
}

fn handle_socket_data(state: State, data: BitArray) -> actor.Next(State, ConnectionMessage) {
  let data_size = bit_array_byte_size(data)
  let now = monotonic_time_ms()

  // Update connection info
  let new_info =
    ConnectionInfo(
      ..state.info,
      last_activity_at: now,
      bytes_received: state.info.bytes_received + data_size,
      state: Active,
    )

  // Notify manager of activity
  actor.send(state.manager, ConnectionActivity(state.info.id))

  // Process with handler if present
  case state.handler {
    Some(handler) -> {
      case handler(state.info.id, data) {
        Ok(Some(response)) -> {
          // Send response back
          let _ = tcp.send(state.info.socket, response)
          Nil
        }
        Ok(None) -> Nil
        Error(_reason) -> Nil
      }
    }
    None -> Nil
  }

  actor.continue(State(..state, info: new_info))
}

fn handle_socket_closed(state: State) -> actor.Next(State, ConnectionMessage) {
  // Notify manager
  actor.send(state.manager, ConnectionClosed(state.info.id))

  // Close socket just in case
  let _ = tcp.close(state.info.socket)

  actor.stop()
}

fn handle_socket_error(
  state: State,
  error: SocketError,
) -> actor.Next(State, ConnectionMessage) {
  // Notify manager of error
  actor.send(state.manager, ConnectionError(state.info.id, error))

  // Check if we should close
  case socket_error.is_closed(error) {
    True -> {
      let _ = tcp.close(state.info.socket)
      actor.stop()
    }
    False -> {
      // Non-fatal error, continue
      actor.continue(state)
    }
  }
}

fn handle_send(
  state: State,
  data: BitArray,
  reply_to: Subject(Result(Nil, SocketError)),
) -> actor.Next(State, ConnectionMessage) {
  case state.info.state {
    Closing | Draining -> {
      actor.send(reply_to, Error(socket_error.NotConnected))
      actor.continue(state)
    }
    _ -> {
      let result = tcp.send(state.info.socket, data)

      case result {
        Ok(Nil) -> {
          let data_size = bit_array_byte_size(data)
          let now = monotonic_time_ms()
          let new_info =
            ConnectionInfo(
              ..state.info,
              last_activity_at: now,
              bytes_sent: state.info.bytes_sent + data_size,
            )
          actor.send(reply_to, Ok(Nil))
          actor.continue(State(..state, info: new_info))
        }
        Error(error) -> {
          actor.send(reply_to, Error(error))
          // Check if connection is broken
          case socket_error.is_closed(error) {
            True -> {
              actor.send(state.manager, ConnectionClosed(state.info.id))
              actor.stop()
            }
            False -> actor.continue(state)
          }
        }
      }
    }
  }
}

fn handle_recv(
  state: State,
  length: Int,
  timeout_ms: Int,
  reply_to: Subject(Result(BitArray, SocketError)),
) -> actor.Next(State, ConnectionMessage) {
  case state.info.state {
    Closing -> {
      actor.send(reply_to, Error(socket_error.NotConnected))
      actor.continue(state)
    }
    _ -> {
      let result = tcp.recv_timeout(state.info.socket, length, timeout_ms)

      case result {
        Ok(data) -> {
          let data_size = bit_array_byte_size(data)
          let now = monotonic_time_ms()
          let new_info =
            ConnectionInfo(
              ..state.info,
              last_activity_at: now,
              bytes_received: state.info.bytes_received + data_size,
            )
          actor.send(reply_to, Ok(data))
          actor.continue(State(..state, info: new_info))
        }
        Error(error) -> {
          actor.send(reply_to, Error(error))
          case socket_error.is_closed(error) {
            True -> {
              actor.send(state.manager, ConnectionClosed(state.info.id))
              actor.stop()
            }
            False -> actor.continue(state)
          }
        }
      }
    }
  }
}

fn handle_get_info(
  state: State,
  reply_to: Subject(ConnectionInfo),
) -> actor.Next(State, ConnectionMessage) {
  actor.send(reply_to, state.info)
  actor.continue(state)
}

fn handle_drain(state: State) -> actor.Next(State, ConnectionMessage) {
  let new_info = ConnectionInfo(..state.info, state: Draining)
  actor.continue(State(..state, info: new_info))
}

fn handle_close(state: State) -> actor.Next(State, ConnectionMessage) {
  // Close the socket
  let _ = tcp.close(state.info.socket)

  // Notify manager
  actor.send(state.manager, ConnectionClosed(state.info.id))

  actor.stop()
}

fn handle_keep_alive_check(state: State) -> actor.Next(State, ConnectionMessage) {
  // For now, just continue - keep-alive probe logic can be added later
  actor.continue(state)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the current connection ID from info
pub fn get_id(info: ConnectionInfo) -> ConnectionId {
  info.id
}

/// Gets the connection state
pub fn get_state(info: ConnectionInfo) -> ConnectionState {
  info.state
}

/// Checks if connection is active
pub fn is_active(info: ConnectionInfo) -> Bool {
  case info.state {
    Active -> True
    _ -> False
  }
}

/// Checks if connection is draining
pub fn is_draining(info: ConnectionInfo) -> Bool {
  case info.state {
    Draining -> True
    _ -> False
  }
}

/// Converts connection state to string
pub fn state_to_string(conn_state: ConnectionState) -> String {
  case conn_state {
    Active -> "Active"
    Idle -> "Idle"
    Draining -> "Draining"
    Closing -> "Closing"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// FFI Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets monotonic time in milliseconds
@external(erlang, "erlang", "monotonic_time")
fn erlang_monotonic_time(unit: a) -> Int

fn monotonic_time_ms() -> Int {
  erlang_monotonic_time(Millisecond)
}

type TimeUnit {
  Millisecond
}

/// Gets the byte size of a bit array
@external(erlang, "erlang", "byte_size")
fn bit_array_byte_size(data: BitArray) -> Int
