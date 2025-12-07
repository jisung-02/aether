// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Supervisor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Unit tests for Connection Supervisor helper functions and types.
// Integration tests for supervised managers are in separate test file.
//

import aether/network/connection_supervisor
import gleeunit/should

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
