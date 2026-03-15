// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Manager Module - Main Connection Pool Manager
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// This module implements the main Connection Manager actor that handles:
// - Accept loop for incoming connections
// - Connection pool management with size limits
// - Connection lifecycle tracking
// - Graceful and force shutdown
// - Statistics collection
//

import aether/network/connection.{
  type ConnectionHandler, type ConnectionId, type ConnectionInfo,
  type ConnectionMessage, type ManagerNotification,
}
import aether/network/connection_config.{type ConnectionConfig}
import aether/network/socket.{type ListenSocket}
import aether/network/socket_error.{type SocketError}
import aether/network/tcp
import gleam/dict.{type Dict}
import gleam/erlang/process.{
  type Subject, map_selector, merge_selector, new_selector, new_subject, select,
}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Status of the Connection Manager
pub type ManagerStatus {
  /// Manager is running and accepting connections
  Running
  /// Manager is draining connections (not accepting new ones)
  Draining
  /// Manager is in the process of shutting down
  ShuttingDown
  /// Manager has stopped
  Stopped
}

/// Statistics about the connection manager
pub type ManagerStats {
  ManagerStats(
    /// Total connections accepted since start
    total_accepted: Int,
    /// Total connections that have been closed
    total_closed: Int,
    /// Total connections rejected (due to limits)
    total_rejected: Int,
    /// Current number of active connections
    active_connections: Int,
    /// Peak number of concurrent connections
    peak_connections: Int,
  )
}

/// Error types for Connection Manager operations
pub type ManagerError {
  /// Failed to start the manager actor
  StartFailed(reason: String)
  /// Failed to bind to the listen address
  BindFailed(error: SocketError)
  /// Shutdown timed out
  ShutdownTimedOut
  /// Manager is not in a valid state for the operation
  InvalidState(status: ManagerStatus)
}

/// Messages handled by the Connection Manager actor
pub type ManagerMessage {
  /// Internal: Accept a new connection
  AcceptConnection
  /// Notification from a Connection actor
  ConnectionNotification(notification: ManagerNotification)
  /// Get current statistics
  GetStats(reply_to: Subject(ManagerStats))
  /// Get current status
  GetStatus(reply_to: Subject(ManagerStatus))
  /// Get info about a specific connection
  GetConnectionInfo(id: ConnectionId, reply_to: Subject(Option(ConnectionInfo)))
  /// Get all connection IDs
  GetConnectionIds(reply_to: Subject(List(ConnectionId)))
  /// Close a specific connection
  CloseConnection(id: ConnectionId)
  /// Close all connections
  CloseAllConnections
  /// Initiate graceful shutdown
  Shutdown(reply_to: Subject(Result(Nil, ManagerError)))
  /// Force immediate shutdown
  ForceShutdown
  /// Internal: Shutdown timeout reached
  ShutdownTimeout
}

/// Internal state of the Connection Manager
type State {
  State(
    /// Current manager status
    status: ManagerStatus,
    /// Configuration
    config: ConnectionConfig,
    /// Listen socket for accepting connections
    listen_socket: ListenSocket,
    /// Map of connection ID to connection actor subject
    connections: Dict(ConnectionId, Subject(ConnectionMessage)),
    /// Next connection ID to assign
    next_id: ConnectionId,
    /// Statistics
    stats: ManagerStats,
    /// Optional connection handler
    handler: Option(ConnectionHandler),
    /// Self subject for sending messages to self
    self_subject: Option(Subject(ManagerMessage)),
    /// Subject for receiving connection notifications
    notification_subject: Option(Subject(ManagerNotification)),
    /// Shutdown reply subject (to respond when shutdown completes)
    shutdown_reply: Option(Subject(Result(Nil, ManagerError))),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Manager API
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Starts a new Connection Manager
///
/// ## Parameters
///
/// - `listen_socket`: The listen socket for accepting connections
/// - `config`: Configuration for the manager
/// - `handler`: Optional handler for processing received data
///
/// ## Returns
///
/// Subject to communicate with the Connection Manager
///
pub fn start(
  listen_socket: ListenSocket,
  config: ConnectionConfig,
  handler: Option(ConnectionHandler),
) -> Result(Subject(ManagerMessage), actor.StartError) {
  case
    actor.new_with_initialiser(1000, fn(subject) {
      let notification_subject = new_subject()
      let selector =
        new_selector()
        |> select(subject)
        |> merge_selector(
          new_selector()
          |> select(notification_subject)
          |> map_selector(ConnectionNotification),
        )

      let initial_stats =
        ManagerStats(
          total_accepted: 0,
          total_closed: 0,
          total_rejected: 0,
          active_connections: 0,
          peak_connections: 0,
        )

      State(
        status: Running,
        config: config,
        listen_socket: listen_socket,
        connections: dict.new(),
        next_id: 1,
        stats: initial_stats,
        handler: handler,
        self_subject: Some(subject),
        notification_subject: Some(notification_subject),
        shutdown_reply: None,
      )
      |> actor.initialised
      |> actor.selecting(selector)
      |> actor.returning(subject)
      |> Ok
    })
    |> actor.on_message(handle_message)
    |> actor.start
  {
    Ok(started) -> {
      // Send initial AcceptConnection message to start the accept loop
      actor.send(started.data, AcceptConnection)
      Ok(started.data)
    }
    Error(err) -> Error(err)
  }
}

/// Gets current statistics from the manager
///
pub fn get_stats(
  manager: Subject(ManagerMessage),
  timeout_ms: Int,
) -> ManagerStats {
  actor.call(manager, timeout_ms, fn(reply_to) { GetStats(reply_to) })
}

/// Gets current status of the manager
///
pub fn get_status(
  manager: Subject(ManagerMessage),
  timeout_ms: Int,
) -> ManagerStatus {
  actor.call(manager, timeout_ms, fn(reply_to) { GetStatus(reply_to) })
}

/// Gets info about a specific connection
///
pub fn get_connection_info(
  manager: Subject(ManagerMessage),
  id: ConnectionId,
  timeout_ms: Int,
) -> Option(ConnectionInfo) {
  actor.call(manager, timeout_ms, fn(reply_to) {
    GetConnectionInfo(id, reply_to)
  })
}

/// Gets all active connection IDs
///
pub fn get_connection_ids(
  manager: Subject(ManagerMessage),
  timeout_ms: Int,
) -> List(ConnectionId) {
  actor.call(manager, timeout_ms, fn(reply_to) { GetConnectionIds(reply_to) })
}

/// Closes a specific connection
///
pub fn close_connection(
  manager: Subject(ManagerMessage),
  id: ConnectionId,
) -> Nil {
  actor.send(manager, CloseConnection(id))
}

/// Closes all connections
///
pub fn close_all_connections(manager: Subject(ManagerMessage)) -> Nil {
  actor.send(manager, CloseAllConnections)
}

/// Initiates graceful shutdown
///
/// Drains all connections and waits for them to close.
///
pub fn shutdown(
  manager: Subject(ManagerMessage),
  timeout_ms: Int,
) -> Result(Nil, ManagerError) {
  actor.call(manager, timeout_ms, fn(reply_to) { Shutdown(reply_to) })
}

/// Forces immediate shutdown
///
/// Closes all connections immediately without waiting.
///
pub fn force_shutdown(manager: Subject(ManagerMessage)) -> Nil {
  actor.send(manager, ForceShutdown)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Message Handler
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn handle_message(
  state: State,
  message: ManagerMessage,
) -> actor.Next(State, ManagerMessage) {
  case message {
    AcceptConnection -> handle_accept_connection(state)

    ConnectionNotification(notification) ->
      handle_connection_notification(state, notification)

    GetStats(reply_to) -> handle_get_stats(state, reply_to)

    GetStatus(reply_to) -> handle_get_status(state, reply_to)

    GetConnectionInfo(id, reply_to) ->
      handle_get_connection_info(state, id, reply_to)

    GetConnectionIds(reply_to) -> handle_get_connection_ids(state, reply_to)

    CloseConnection(id) -> handle_close_connection(state, id)

    CloseAllConnections -> handle_close_all_connections(state)

    Shutdown(reply_to) -> handle_shutdown(state, reply_to)

    ForceShutdown -> handle_force_shutdown(state)

    ShutdownTimeout -> handle_shutdown_timeout(state)
  }
}

fn handle_accept_connection(state: State) -> actor.Next(State, ManagerMessage) {
  case state.status {
    Running -> {
      // Check if we've reached max connections
      let current_count = dict.size(state.connections)
      let max_connections = connection_config.get_max_connections(state.config)

      case current_count >= max_connections {
        True -> {
          // At capacity, update stats and schedule retry
          let new_stats =
            ManagerStats(
              ..state.stats,
              total_rejected: state.stats.total_rejected + 1,
            )
          let new_state = State(..state, stats: new_stats)

          // Schedule retry after a delay
          schedule_accept_retry(state)
          actor.continue(new_state)
        }
        False -> {
          // Try to accept a connection
          let accept_timeout =
            connection_config.get_accept_timeout(state.config)

          case tcp.accept_timeout(state.listen_socket, accept_timeout) {
            Ok(client_socket) -> {
              // Start a new Connection actor
              let conn_id = state.next_id
              let manager_subject = get_self_subject(state)

              case
                connection.start(
                  client_socket,
                  conn_id,
                  manager_subject,
                  state.handler,
                )
              {
                Ok(conn_subject) -> {
                  // Add to connections dict
                  let new_connections =
                    dict.insert(state.connections, conn_id, conn_subject)

                  // Update stats
                  let new_active = dict.size(new_connections)
                  let new_peak =
                    int.max(state.stats.peak_connections, new_active)
                  let new_stats =
                    ManagerStats(
                      ..state.stats,
                      total_accepted: state.stats.total_accepted + 1,
                      active_connections: new_active,
                      peak_connections: new_peak,
                    )

                  let new_state =
                    State(
                      ..state,
                      connections: new_connections,
                      next_id: conn_id + 1,
                      stats: new_stats,
                    )

                  // Continue accepting
                  schedule_accept(new_state)
                  actor.continue(new_state)
                }
                Error(_) -> {
                  // Failed to start connection actor, close socket
                  let _ = tcp.close(client_socket)
                  schedule_accept(state)
                  actor.continue(state)
                }
              }
            }
            Error(err) -> {
              // Accept failed or timed out
              case err {
                socket_error.Timeout -> {
                  // Timeout is normal, just retry
                  schedule_accept(state)
                  actor.continue(state)
                }
                _ -> {
                  // Real error, log and continue
                  schedule_accept(state)
                  actor.continue(state)
                }
              }
            }
          }
        }
      }
    }
    _ -> {
      // Not running, don't accept new connections
      actor.continue(state)
    }
  }
}

fn handle_connection_notification(
  state: State,
  notification: ManagerNotification,
) -> actor.Next(State, ManagerMessage) {
  case notification {
    connection.ConnectionClosed(id) -> {
      // Remove from connections dict
      let new_connections = dict.delete(state.connections, id)
      let new_active = dict.size(new_connections)
      let new_stats =
        ManagerStats(
          ..state.stats,
          total_closed: state.stats.total_closed + 1,
          active_connections: new_active,
        )

      let new_state =
        State(..state, connections: new_connections, stats: new_stats)

      // Check if we're draining and all connections are closed
      case state.status {
        Draining | ShuttingDown -> {
          case new_active == 0 {
            True -> complete_shutdown(new_state)
            False -> actor.continue(new_state)
          }
        }
        _ -> actor.continue(new_state)
      }
    }
    connection.ConnectionError(id, _error) -> {
      // Connection error, remove from dict
      let new_connections = dict.delete(state.connections, id)
      let new_active = dict.size(new_connections)
      let new_stats =
        ManagerStats(
          ..state.stats,
          total_closed: state.stats.total_closed + 1,
          active_connections: new_active,
        )

      let new_state =
        State(..state, connections: new_connections, stats: new_stats)
      actor.continue(new_state)
    }
    connection.ConnectionActivity(_id) -> {
      // Activity notification, no action needed for now
      actor.continue(state)
    }
  }
}

fn handle_get_stats(
  state: State,
  reply_to: Subject(ManagerStats),
) -> actor.Next(State, ManagerMessage) {
  actor.send(reply_to, state.stats)
  actor.continue(state)
}

fn handle_get_status(
  state: State,
  reply_to: Subject(ManagerStatus),
) -> actor.Next(State, ManagerMessage) {
  actor.send(reply_to, state.status)
  actor.continue(state)
}

fn handle_get_connection_info(
  state: State,
  id: ConnectionId,
  reply_to: Subject(Option(ConnectionInfo)),
) -> actor.Next(State, ManagerMessage) {
  case dict.get(state.connections, id) {
    Ok(conn_subject) -> {
      let info = connection.get_info(conn_subject, 5000)
      actor.send(reply_to, Some(info))
    }
    Error(_) -> {
      actor.send(reply_to, None)
    }
  }
  actor.continue(state)
}

fn handle_get_connection_ids(
  state: State,
  reply_to: Subject(List(ConnectionId)),
) -> actor.Next(State, ManagerMessage) {
  let ids = dict.keys(state.connections)
  actor.send(reply_to, ids)
  actor.continue(state)
}

fn handle_close_connection(
  state: State,
  id: ConnectionId,
) -> actor.Next(State, ManagerMessage) {
  case dict.get(state.connections, id) {
    Ok(conn_subject) -> {
      connection.close(conn_subject)
    }
    Error(_) -> Nil
  }
  actor.continue(state)
}

fn handle_close_all_connections(
  state: State,
) -> actor.Next(State, ManagerMessage) {
  // Send close to all connections
  dict.each(state.connections, fn(_id, conn_subject) {
    connection.close(conn_subject)
  })
  actor.continue(state)
}

fn handle_shutdown(
  state: State,
  reply_to: Subject(Result(Nil, ManagerError)),
) -> actor.Next(State, ManagerMessage) {
  case state.status {
    Running -> {
      // Update status to draining
      let new_state =
        State(..state, status: Draining, shutdown_reply: Some(reply_to))

      // Check if there are any connections
      case dict.size(state.connections) == 0 {
        True -> {
          // No connections, complete shutdown immediately
          complete_shutdown(new_state)
        }
        False -> {
          // Drain all connections
          dict.each(state.connections, fn(_id, conn_subject) {
            connection.drain(conn_subject)
          })

          // Schedule shutdown timeout (placeholder - not yet implemented)
          let _ = schedule_shutdown_timeout(new_state)
          actor.continue(new_state)
        }
      }
    }
    _ -> {
      // Already shutting down or stopped
      actor.send(reply_to, Error(InvalidState(state.status)))
      actor.continue(state)
    }
  }
}

fn handle_force_shutdown(state: State) -> actor.Next(State, ManagerMessage) {
  // Close all connections immediately
  dict.each(state.connections, fn(_id, conn_subject) {
    connection.close(conn_subject)
  })

  // Close listen socket
  let _ = tcp.close_listen(state.listen_socket)

  // Reply to shutdown if pending
  case state.shutdown_reply {
    Some(reply_to) -> actor.send(reply_to, Ok(Nil))
    None -> Nil
  }

  actor.stop()
}

fn handle_shutdown_timeout(state: State) -> actor.Next(State, ManagerMessage) {
  case state.status {
    Draining | ShuttingDown -> {
      // Force close remaining connections
      dict.each(state.connections, fn(_id, conn_subject) {
        connection.close(conn_subject)
      })

      // Reply with timeout error
      case state.shutdown_reply {
        Some(reply_to) -> actor.send(reply_to, Error(ShutdownTimedOut))
        None -> Nil
      }

      // Close listen socket
      let _ = tcp.close_listen(state.listen_socket)

      actor.stop()
    }
    _ -> actor.continue(state)
  }
}

fn complete_shutdown(state: State) -> actor.Next(State, ManagerMessage) {
  // Close listen socket
  let _ = tcp.close_listen(state.listen_socket)

  // Reply to shutdown
  case state.shutdown_reply {
    Some(reply_to) -> actor.send(reply_to, Ok(Nil))
    None -> Nil
  }

  actor.stop()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Schedules the next accept attempt
fn schedule_accept(state: State) -> Nil {
  case state.self_subject {
    Some(subject) -> {
      actor.send(subject, AcceptConnection)
    }
    None -> Nil
  }
}

/// Schedules a retry after hitting connection limit
fn schedule_accept_retry(state: State) -> Nil {
  case state.self_subject {
    Some(subject) -> {
      // In a real implementation, we'd use a timer here
      // For now, just immediately retry
      actor.send(subject, AcceptConnection)
    }
    None -> Nil
  }
}

/// Schedules the shutdown timeout
fn schedule_shutdown_timeout(_state: State) -> Nil {
  // In a real implementation, we'd use process.send_after here
  // For now, this is a placeholder - shutdown timeout is not implemented
  Nil
}

/// Gets or creates the self subject for sending messages to self
fn get_self_subject(state: State) -> Subject(ManagerNotification) {
  let assert Some(subject) = state.notification_subject
  subject
}

/// Converts manager status to string
pub fn status_to_string(status: ManagerStatus) -> String {
  case status {
    Running -> "Running"
    Draining -> "Draining"
    ShuttingDown -> "ShuttingDown"
    Stopped -> "Stopped"
  }
}

/// Creates empty stats
pub fn empty_stats() -> ManagerStats {
  ManagerStats(
    total_accepted: 0,
    total_closed: 0,
    total_rejected: 0,
    active_connections: 0,
    peak_connections: 0,
  )
}

/// Gets the active connection count from stats
pub fn active_count(stats: ManagerStats) -> Int {
  stats.active_connections
}

/// Gets the total accepted count from stats
pub fn total_accepted(stats: ManagerStats) -> Int {
  stats.total_accepted
}

/// Gets the total closed count from stats
pub fn total_closed(stats: ManagerStats) -> Int {
  stats.total_closed
}

/// Gets the total rejected count from stats
pub fn total_rejected(stats: ManagerStats) -> Int {
  stats.total_rejected
}

/// Gets the peak connections from stats
pub fn peak_connections(stats: ManagerStats) -> Int {
  stats.peak_connections
}
