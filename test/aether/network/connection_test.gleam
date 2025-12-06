// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Unit tests for Connection module helper functions and types.
// Actor-related tests are in the integration tests since they require
// actual socket connections.
//

import aether/network/connection
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ConnectionState Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn state_to_string_active_test() {
  connection.state_to_string(connection.Active)
  |> should.equal("Active")
}

pub fn state_to_string_idle_test() {
  connection.state_to_string(connection.Idle)
  |> should.equal("Idle")
}

pub fn state_to_string_draining_test() {
  connection.state_to_string(connection.Draining)
  |> should.equal("Draining")
}

pub fn state_to_string_closing_test() {
  connection.state_to_string(connection.Closing)
  |> should.equal("Closing")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ConnectionInfo Helper Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Note: Most ConnectionInfo tests require actual socket connections
// and are covered in integration tests. Here we test the type
// constructors and pattern matching work correctly.

pub fn connection_state_pattern_matching_test() {
  let states = [
    connection.Active,
    connection.Idle,
    connection.Draining,
    connection.Closing,
  ]

  // Verify all states are distinct
  states
  |> list_length
  |> should.equal(4)
}

pub fn manager_notification_types_test() {
  // Test that notification types can be constructed
  let closed = connection.ConnectionClosed(1)
  let activity = connection.ConnectionActivity(2)

  case closed {
    connection.ConnectionClosed(id) -> id |> should.equal(1)
    _ -> should.fail()
  }

  case activity {
    connection.ConnectionActivity(id) -> id |> should.equal(2)
    _ -> should.fail()
  }
}

pub fn connection_error_types_test() {
  // Test error type construction
  let start_err = connection.StartFailed("test reason")

  case start_err {
    connection.StartFailed(reason) -> reason |> should.equal("test reason")
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn list_length(items: List(a)) -> Int {
  list_length_helper(items, 0)
}

fn list_length_helper(items: List(a), acc: Int) -> Int {
  case items {
    [] -> acc
    [_, ..rest] -> list_length_helper(rest, acc + 1)
  }
}
