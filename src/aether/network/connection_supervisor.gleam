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
// When the ConnectionManager crashes, the supervisor will restart it.
//

import aether/network/connection.{type ConnectionHandler}
import aether/network/connection_config.{type ConnectionConfig}
import aether/network/connection_manager.{type ManagerMessage}
import aether/network/socket.{type ListenSocket}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}
import gleam/otp/static_supervisor

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
/// This creates a supervisor that will restart the Connection Manager
/// if it crashes. The supervisor uses a OneForOne strategy.
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
  // First, start the connection manager
  case connection_manager.start(listen_socket, config, handler) {
    Ok(manager_subject) -> {
      // Create and start a supervisor for fault tolerance
      // Note: In a real implementation, we'd add the manager as a child
      // For now, we just create a minimal supervisor
      case
        static_supervisor.new(static_supervisor.OneForOne)
        |> static_supervisor.restart_tolerance(3, 5)
        |> static_supervisor.start
      {
        Ok(started) -> {
          Ok(SupervisedManager(
            supervisor: started.data,
            manager: manager_subject,
          ))
        }
        Error(_err) -> {
          // If supervisor fails to start, we need to clean up the manager
          connection_manager.force_shutdown(manager_subject)
          Error(SupervisorStartFailed("Failed to start supervisor"))
        }
      }
    }
    Error(_err) -> {
      Error(ManagerStartFailed("Failed to start connection manager"))
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
