// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Supervisor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Unit tests for Connection Supervisor helper functions and types.
// Integration tests for supervised managers are in separate test file.
//

import aether/network/connection_config
import aether/network/connection_manager
import aether/network/connection_supervisor
import aether/network/socket_options
import aether/network/tcp
import gleam/erlang/process
import gleam/option.{None}
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn get_available_port() -> Int {
  49_152 + erlang_unique_integer() % 1000
}

@external(erlang, "erlang", "unique_integer")
fn erlang_unique_integer() -> Int

fn sleep(ms: Int) -> Nil {
  process.sleep(ms)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SupervisorError Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn supervisor_start_failed_error_test() {
  let error = connection_supervisor.SupervisorStartFailed("test reason")

  let connection_supervisor.SupervisorStartFailed(reason) = error
  reason |> should.equal("test reason")
}

pub fn manager_start_failed_error_test() {
  let error = connection_supervisor.ManagerStartFailed("test reason")

  let connection_supervisor.ManagerStartFailed(reason) = error
  reason |> should.equal("test reason")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error String Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_to_string_supervisor_failed_test() {
  let error = connection_supervisor.SupervisorStartFailed("init failed")

  connection_supervisor.error_to_string(error)
  |> should.equal("Supervisor start failed: init failed")
}

pub fn error_to_string_manager_failed_test() {
  let error = connection_supervisor.ManagerStartFailed("bind failed")

  connection_supervisor.error_to_string(error)
  |> should.equal("Manager start failed: bind failed")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Restart Integration Test
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn supervised_manager_restarts_after_crash_test() {
  let port = get_available_port()
  let config =
    connection_config.new()
    |> connection_config.with_max_connections(10)
    |> connection_config.with_accept_timeout(1000)

  case tcp.listen(port, socket_options.new()) {
    Ok(listen_socket) -> {
      case connection_supervisor.start_supervised(listen_socket, config, None) {
        Ok(supervised) -> {
          sleep(50)

          let manager = connection_supervisor.get_manager(supervised)

          // Manager should be up and running
          connection_manager.get_status(manager, 5000)
          |> should.equal(connection_manager.Running)

          case process.subject_owner(manager) {
            Ok(pid_before) -> {
              // Kill the manager actor directly to simulate a crash
              process.kill(pid_before)
              sleep(300)

              case process.subject_owner(manager) {
                Ok(pid_after) -> {
                  // The supervisor should have restarted the manager as a
                  // new process registered under the same stable name, so
                  // the same `manager` subject now points at a new pid
                  should.not_equal(pid_before, pid_after)

                  // And the restarted manager should be responsive again,
                  // through the very same subject captured before the crash
                  connection_manager.get_status(manager, 5000)
                  |> should.equal(connection_manager.Running)

                  connection_supervisor.force_shutdown(supervised)
                  sleep(100)
                }
                Error(_) -> should.fail()
              }
            }
            Error(_) -> should.fail()
          }
        }
        Error(_) -> should.fail()
      }
    }
    Error(_) -> {
      // Port might be in use, skip test
      should.be_true(True)
    }
  }
}
