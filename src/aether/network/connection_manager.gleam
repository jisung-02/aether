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
  type Down, type Monitor, type Name, type Pid, type Subject, PortDown,
  ProcessDown, demonitor_process, map_selector, merge_selector, monitor,
  new_selector, new_subject, select, select_monitors, send_after, subject_owner,
  unlink,
}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

/// Delay before retrying `AcceptConnection` after hitting `max_connections`,
/// so the manager doesn't busy-loop resending the message to itself.
const accept_retry_delay_ms = 50

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
  /// Internal: a monitored connection process has exited unexpectedly
  ConnectionDown(down: Down)
  /// Get current statistics
  GetStats(reply_to: Subject(ManagerStats))
  /// Get current status
  GetStatus(reply_to: Subject(ManagerStatus))
  /// Get info about a specific connection
  GetConnectionInfo(id: ConnectionId, reply_to: Subject(Option(ConnectionInfo)))
  /// Get all connection IDs
  GetConnectionIds(reply_to: Subject(List(ConnectionId)))
  /// Get the pid of a specific connection's actor process (mainly useful
  /// for tests and diagnostics, e.g. simulating a crash with `process.kill`)
  GetConnectionPid(id: ConnectionId, reply_to: Subject(Option(Pid)))
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
    /// Map of connection ID to the process monitor watching its actor
    monitors: Dict(ConnectionId, Monitor),
    /// Reverse lookup from a monitored connection process to its ID, used to
    /// resolve `Down` messages back to the connection they belong to
    pid_to_id: Dict(Pid, ConnectionId),
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
  case start_internal(listen_socket, config, handler, None) {
    Ok(started) -> Ok(started.data)
    Error(err) -> Error(err)
  }
}

/// Starts a new Connection Manager registered under a stable process name
///
/// This is what allows `connection_supervisor` to supervise the manager:
/// the manager registers itself under `name` on start, so if the supervisor
/// restarts it after a crash the new process re-registers under the same
/// name. A `Subject` built from that name with `process.named_subject`
/// keeps working transparently across restarts.
///
/// ## Parameters
///
/// - `listen_socket`: The listen socket for accepting connections
/// - `config`: Configuration for the manager
/// - `handler`: Optional handler for processing received data
/// - `name`: The stable process name to register the manager under
///
/// ## Returns
///
/// Subject to communicate with the Connection Manager
///
pub fn start_named(
  listen_socket: ListenSocket,
  config: ConnectionConfig,
  handler: Option(ConnectionHandler),
  name: Name(ManagerMessage),
) -> Result(Subject(ManagerMessage), actor.StartError) {
  case start_internal(listen_socket, config, handler, Some(name)) {
    Ok(started) -> Ok(started.data)
    Error(err) -> Error(err)
  }
}

/// Starts a new Connection Manager registered under a stable process name,
/// returning the full `actor.Started` value (pid and subject).
///
/// This is used by `connection_supervisor` to register the manager as a
/// supervised child, since a supervisor's `ChildSpecification` needs the
/// child's pid, not just its `Subject`.
///
pub fn start_named_child(
  listen_socket: ListenSocket,
  config: ConnectionConfig,
  handler: Option(ConnectionHandler),
  name: Name(ManagerMessage),
) -> Result(actor.Started(Subject(ManagerMessage)), actor.StartError) {
  start_internal(listen_socket, config, handler, Some(name))
}

fn start_internal(
  listen_socket: ListenSocket,
  config: ConnectionConfig,
  handler: Option(ConnectionHandler),
  name: Option(Name(ManagerMessage)),
) -> Result(actor.Started(Subject(ManagerMessage)), actor.StartError) {
  let builder =
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
        |> select_monitors(ConnectionDown)

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
        monitors: dict.new(),
        pid_to_id: dict.new(),
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

  let builder = case name {
    Some(actor_name) -> actor.named(builder, actor_name)
    None -> builder
  }

  case actor.start(builder) {
    Ok(started) -> {
      // Send initial AcceptConnection message to start the accept loop
      actor.send(started.data, AcceptConnection)
      Ok(started)
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

/// Gets the pid of a specific connection's actor process
///
/// Mainly useful for tests and diagnostics, e.g. simulating a crash with
/// `process.kill` to verify the manager notices and cleans up state.
///
pub fn get_connection_pid(
  manager: Subject(ManagerMessage),
  id: ConnectionId,
  timeout_ms: Int,
) -> Option(Pid) {
  actor.call(manager, timeout_ms, fn(reply_to) {
    GetConnectionPid(id, reply_to)
  })
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

    ConnectionDown(down) -> handle_connection_down(state, down)

    GetStats(reply_to) -> handle_get_stats(state, reply_to)

    GetStatus(reply_to) -> handle_get_status(state, reply_to)

    GetConnectionInfo(id, reply_to) ->
      handle_get_connection_info(state, id, reply_to)

    GetConnectionIds(reply_to) -> handle_get_connection_ids(state, reply_to)

    GetConnectionPid(id, reply_to) ->
      handle_get_connection_pid(state, id, reply_to)

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
                  // Monitor the connection process so that if it crashes
                  // without sending a notification, we still notice and
                  // remove it from state instead of leaving a zombie entry.
                  //
                  // `connection.start` links the new process to us (that's
                  // baked into `actor.start`), which would otherwise take the
                  // whole manager down if a connection crashes abnormally,
                  // since the manager does not trap exits. Unlink it so that
                  // the monitor above is the only thing tying its lifecycle
                  // to ours.
                  let new_connections =
                    dict.insert(state.connections, conn_id, conn_subject)
                  let #(new_monitors, new_pid_to_id) = case
                    subject_owner(conn_subject)
                  {
                    Ok(conn_pid) -> {
                      unlink(conn_pid)
                      #(
                        dict.insert(state.monitors, conn_id, monitor(conn_pid)),
                        dict.insert(state.pid_to_id, conn_pid, conn_id),
                      )
                    }
                    Error(_) -> #(state.monitors, state.pid_to_id)
                  }

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
                      monitors: new_monitors,
                      pid_to_id: new_pid_to_id,
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
    connection.ConnectionClosed(id) -> handle_connection_closed(state, id)

    connection.ConnectionError(id, _error) -> {
      // Connection error, remove from dict (this connection actor also stops
      // itself on a fatal error, so make sure its monitor and pid mapping are
      // cleaned up too, otherwise the later `Down` message would try to
      // remove an already-removed connection)
      let new_state = remove_connection(state, id)
      let new_active = dict.size(new_state.connections)
      let new_stats =
        ManagerStats(
          ..new_state.stats,
          total_closed: new_state.stats.total_closed + 1,
          active_connections: new_active,
        )

      actor.continue(State(..new_state, stats: new_stats))
    }
    connection.ConnectionActivity(_id) -> {
      // Activity notification, no action needed for now
      actor.continue(state)
    }
  }
}

/// Handles a connection actor exiting without (or before) sending a
/// `ConnectionClosed`/`ConnectionError` notification, e.g. because it
/// crashed. Removes it from state exactly as a normal `ConnectionClosed`
/// notification would.
fn handle_connection_down(
  state: State,
  down: Down,
) -> actor.Next(State, ManagerMessage) {
  case down {
    ProcessDown(_monitor, pid, _reason) -> {
      case dict.get(state.pid_to_id, pid) {
        Ok(id) -> handle_connection_closed(state, id)
        Error(_) -> actor.continue(state)
      }
    }
    PortDown(_, _, _) -> actor.continue(state)
  }
}

/// Removes a closed connection from state, updates stats, and completes
/// shutdown if we were draining and this was the last active connection.
fn handle_connection_closed(
  state: State,
  id: ConnectionId,
) -> actor.Next(State, ManagerMessage) {
  let new_state = remove_connection(state, id)
  let new_active = dict.size(new_state.connections)
  let new_stats =
    ManagerStats(
      ..new_state.stats,
      total_closed: new_state.stats.total_closed + 1,
      active_connections: new_active,
    )

  let new_state = State(..new_state, stats: new_stats)

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

/// Removes a connection's subject, monitor, and pid mapping from state
/// without touching stats or manager status.
fn remove_connection(state: State, id: ConnectionId) -> State {
  case dict.get(state.monitors, id) {
    Ok(conn_monitor) -> demonitor_process(conn_monitor)
    Error(_) -> Nil
  }

  let new_pid_to_id = case dict.get(state.connections, id) {
    Ok(conn_subject) -> {
      case subject_owner(conn_subject) {
        Ok(pid) -> dict.delete(state.pid_to_id, pid)
        Error(_) -> state.pid_to_id
      }
    }
    Error(_) -> state.pid_to_id
  }

  State(
    ..state,
    connections: dict.delete(state.connections, id),
    monitors: dict.delete(state.monitors, id),
    pid_to_id: new_pid_to_id,
  )
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

fn handle_get_connection_pid(
  state: State,
  id: ConnectionId,
  reply_to: Subject(Option(Pid)),
) -> actor.Next(State, ManagerMessage) {
  case dict.get(state.connections, id) {
    Ok(conn_subject) -> {
      case subject_owner(conn_subject) {
        Ok(pid) -> actor.send(reply_to, Some(pid))
        Error(_) -> actor.send(reply_to, None)
      }
    }
    Error(_) -> actor.send(reply_to, None)
  }
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
///
/// Retries after a short delay rather than immediately, so that a manager
/// stuck at `max_connections` doesn't busy-loop resending `AcceptConnection`
/// to itself and pegging a scheduler.
fn schedule_accept_retry(state: State) -> Nil {
  case state.self_subject {
    Some(subject) -> {
      let _ = send_after(subject, accept_retry_delay_ms, AcceptConnection)
      Nil
    }
    None -> Nil
  }
}

/// Schedules the shutdown timeout
///
/// If graceful shutdown is still draining connections when this fires, it
/// forces the remaining connections closed instead of waiting forever.
fn schedule_shutdown_timeout(state: State) -> Nil {
  case state.self_subject {
    Some(subject) -> {
      let timeout_ms = connection_config.get_shutdown_timeout(state.config)
      let _ = send_after(subject, timeout_ms, ShutdownTimeout)
      Nil
    }
    None -> Nil
  }
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
