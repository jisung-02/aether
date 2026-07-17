// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Supervisor Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// This module provides supervisor setup for the Connection Manager.
// It creates a supervision tree that ensures fault tolerance:
//
// ConnectionSupervisor (static_supervisor)
// └── ConnectionManager actor
//     └── Manages individual Connection actors
//
// The ConnectionManager is registered as a `Permanent` worker child under a
// stable process name. When it crashes, the supervisor restarts it and the
// new process re-registers under that same name, so `supervised.manager`
// (built from the name, not a fixed pid) keeps working transparently after
// a restart.
//
// What this does NOT guarantee: individual Connection actors are not part
// of this supervision tree. If the manager crashes, any connections it was
// tracking are lost from its state - the restarted manager starts with an
// empty connection pool, and those connection actors' notification subject
// still points at the dead manager process, so they will not be tracked or
// drained again. Only the manager itself (and its ability to keep accepting
// new connections on the same listen socket) survives a crash.
//

import aether/network/connection.{type ConnectionHandler}
import aether/network/connection_config.{type ConnectionConfig}
import aether/network/connection_manager.{type ManagerMessage}
import aether/network/socket.{type ListenSocket}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}
import gleam/otp/static_supervisor
import gleam/otp/supervision

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Error types for supervisor operations
pub type SupervisorError {
  /// Failed to start the supervisor
  SupervisorStartFailed(reason: String)
  /// Failed to start the connection manager
  ManagerStartFailed(reason: String)
}

/// Result of starting the supervised connection manager
pub type SupervisedManager {
  SupervisedManager(
    /// Reference to the supervisor process
    supervisor: static_supervisor.Supervisor,
    /// Subject to communicate with the Connection Manager
    manager: Subject(ManagerMessage),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Supervisor API
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Starts a Connection Manager under supervision
///
/// This registers the Connection Manager as a `Permanent` worker child of a
/// `static_supervisor` using a `OneForOne` strategy, so the supervisor
/// actually restarts the manager if it crashes. The manager is started
/// under a stable process name (see `connection_manager.start_named`), and
/// `supervised.manager` is a `Subject` built from that name, so it keeps
/// working after a restart without the caller needing to fetch a new
/// `Subject`.
///
/// Restart does NOT preserve in-flight connections: they are not children of
/// this supervisor, so a manager crash loses track of them. See the module
/// documentation for the exact guarantees.
///
/// ## Parameters
///
/// - `listen_socket`: The listen socket for accepting connections
/// - `config`: Configuration for the manager
/// - `handler`: Optional handler for processing received data
///
/// ## Returns
///
/// SupervisedManager containing references to supervisor and manager
///
/// ## Example
///
/// ```gleam
/// let config = connection_config.new()
///   |> connection_config.with_max_connections(500)
///
/// case tcp.listen(8080, []) {
///   Ok(listen_socket) -> {
///     case connection_supervisor.start_supervised(listen_socket, config, None) {
///       Ok(supervised) -> {
///         // Use supervised.manager to interact with the manager
///         let stats = connection_manager.get_stats(supervised.manager, 5000)
///         io.println("Active: " <> int.to_string(stats.active_connections))
///       }
///       Error(err) -> io.println("Failed to start supervisor")
///     }
///   }
///   Error(_) -> io.println("Failed to listen")
/// }
/// ```
///
pub fn start_supervised(
  listen_socket: ListenSocket,
  config: ConnectionConfig,
  handler: Option(ConnectionHandler),
) -> Result(SupervisedManager, SupervisorError) {
  // A stable name lets the manager re-register itself after a restart, so
  // `process.named_subject(name)` keeps routing to whichever process
  // currently holds the name instead of a pid that died with the old one.
  let name = process.new_name(prefix: "aether_connection_manager")
  let start_manager = fn() {
    connection_manager.start_named_child(listen_socket, config, handler, name)
  }

  case
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(3, 5)
    |> static_supervisor.add(supervision.worker(start_manager))
    |> static_supervisor.start
  {
    Ok(started) -> {
      Ok(SupervisedManager(
        supervisor: started.data,
        manager: process.named_subject(name),
      ))
    }
    Error(_err) -> {
      Error(SupervisorStartFailed("Failed to start supervisor"))
    }
  }
}

/// Starts a Connection Manager without supervision
///
/// This is a convenience function for cases where supervision is not needed,
/// such as testing or simple applications.
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
pub fn start_unsupervised(
  listen_socket: ListenSocket,
  config: ConnectionConfig,
  handler: Option(ConnectionHandler),
) -> Result(Subject(ManagerMessage), SupervisorError) {
  case connection_manager.start(listen_socket, config, handler) {
    Ok(manager_subject) -> Ok(manager_subject)
    Error(_err) ->
      Error(ManagerStartFailed("Failed to start connection manager"))
  }
}

/// Shuts down a supervised manager
///
/// Initiates graceful shutdown of the Connection Manager and then
/// stops the supervisor.
///
/// ## Parameters
///
/// - `supervised`: The supervised manager to shut down
/// - `timeout_ms`: Timeout in milliseconds to wait for graceful shutdown
///
/// ## Returns
///
/// Ok(Nil) on success, Error with reason on failure
///
pub fn shutdown(
  supervised: SupervisedManager,
  timeout_ms: Int,
) -> Result(Nil, connection_manager.ManagerError) {
  // Initiate graceful shutdown of the manager
  connection_manager.shutdown(supervised.manager, timeout_ms)
}

/// Forces immediate shutdown of a supervised manager
///
/// Immediately closes all connections and stops the manager.
///
pub fn force_shutdown(supervised: SupervisedManager) -> Nil {
  connection_manager.force_shutdown(supervised.manager)
}

/// Gets the manager subject from a supervised manager
///
pub fn get_manager(supervised: SupervisedManager) -> Subject(ManagerMessage) {
  supervised.manager
}

/// Gets the supervisor reference from a supervised manager
///
pub fn get_supervisor(
  supervised: SupervisedManager,
) -> static_supervisor.Supervisor {
  supervised.supervisor
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a supervisor error to string
pub fn error_to_string(error: SupervisorError) -> String {
  case error {
    SupervisorStartFailed(reason) -> "Supervisor start failed: " <> reason
    ManagerStartFailed(reason) -> "Manager start failed: " <> reason
  }
}
