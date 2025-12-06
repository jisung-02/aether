// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Manager Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Unit tests for Connection Manager helper functions and types.
// Actor-related tests are in the integration tests since they require
// actual socket connections.
//

import aether/network/connection_manager
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ManagerStatus Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn status_to_string_running_test() {
  connection_manager.status_to_string(connection_manager.Running)
  |> should.equal("Running")
}

pub fn status_to_string_draining_test() {
  connection_manager.status_to_string(connection_manager.Draining)
  |> should.equal("Draining")
}

pub fn status_to_string_shutting_down_test() {
  connection_manager.status_to_string(connection_manager.ShuttingDown)
  |> should.equal("ShuttingDown")
}

pub fn status_to_string_stopped_test() {
  connection_manager.status_to_string(connection_manager.Stopped)
  |> should.equal("Stopped")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ManagerStats Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn empty_stats_test() {
  let stats = connection_manager.empty_stats()

  connection_manager.active_count(stats)
  |> should.equal(0)

  connection_manager.total_accepted(stats)
  |> should.equal(0)

  connection_manager.total_closed(stats)
  |> should.equal(0)

  connection_manager.total_rejected(stats)
  |> should.equal(0)

  connection_manager.peak_connections(stats)
  |> should.equal(0)
}

pub fn stats_accessors_test() {
  let stats =
    connection_manager.ManagerStats(
      total_accepted: 100,
      total_closed: 50,
      total_rejected: 5,
      active_connections: 50,
      peak_connections: 75,
    )

  connection_manager.active_count(stats)
  |> should.equal(50)

  connection_manager.total_accepted(stats)
  |> should.equal(100)

  connection_manager.total_closed(stats)
  |> should.equal(50)

  connection_manager.total_rejected(stats)
  |> should.equal(5)

  connection_manager.peak_connections(stats)
  |> should.equal(75)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ManagerError Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn manager_error_start_failed_test() {
  let error = connection_manager.StartFailed("test reason")

  case error {
    connection_manager.StartFailed(reason) ->
      reason |> should.equal("test reason")
    _ -> should.fail()
  }
}

pub fn manager_error_invalid_state_test() {
  let error = connection_manager.InvalidState(connection_manager.Draining)

  case error {
    connection_manager.InvalidState(status) ->
      status |> should.equal(connection_manager.Draining)
    _ -> should.fail()
  }
}

pub fn manager_error_shutdown_timed_out_test() {
  let error = connection_manager.ShutdownTimedOut

  case error {
    connection_manager.ShutdownTimedOut -> should.be_true(True)
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ManagerMessage Type Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn manager_message_accept_connection_test() {
  let msg = connection_manager.AcceptConnection

  case msg {
    connection_manager.AcceptConnection -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn manager_message_close_connection_test() {
  let msg = connection_manager.CloseConnection(42)

  case msg {
    connection_manager.CloseConnection(id) -> id |> should.equal(42)
    _ -> should.fail()
  }
}

pub fn manager_message_close_all_connections_test() {
  let msg = connection_manager.CloseAllConnections

  case msg {
    connection_manager.CloseAllConnections -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn manager_message_force_shutdown_test() {
  let msg = connection_manager.ForceShutdown

  case msg {
    connection_manager.ForceShutdown -> should.be_true(True)
    _ -> should.fail()
  }
}
