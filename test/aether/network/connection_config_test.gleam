// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Config Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/network/connection_config
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_returns_default_values_test() {
  let config = connection_config.new()

  connection_config.get_max_connections(config)
  |> should.equal(1000)

  connection_config.get_accept_timeout(config)
  |> should.equal(5000)

  connection_config.get_connection_timeout(config)
  |> should.equal(60_000)

  connection_config.is_keep_alive_enabled(config)
  |> should.equal(True)

  connection_config.get_keep_alive_interval(config)
  |> should.equal(30_000)

  connection_config.get_shutdown_timeout(config)
  |> should.equal(30_000)
}

pub fn default_is_alias_for_new_test() {
  let config = connection_config.default()

  connection_config.get_max_connections(config)
  |> should.equal(1000)
}

pub fn high_throughput_preset_test() {
  let config = connection_config.high_throughput()

  connection_config.get_max_connections(config)
  |> should.equal(10_000)

  connection_config.get_accept_timeout(config)
  |> should.equal(1000)

  connection_config.get_connection_timeout(config)
  |> should.equal(30_000)

  connection_config.is_keep_alive_enabled(config)
  |> should.equal(False)
}

pub fn long_lived_preset_test() {
  let config = connection_config.long_lived()

  connection_config.get_max_connections(config)
  |> should.equal(100)

  connection_config.get_connection_timeout(config)
  |> should.equal(0)

  connection_config.is_keep_alive_enabled(config)
  |> should.equal(True)

  connection_config.get_keep_alive_interval(config)
  |> should.equal(15_000)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Builder Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn with_max_connections_test() {
  let config =
    connection_config.new()
    |> connection_config.with_max_connections(500)

  connection_config.get_max_connections(config)
  |> should.equal(500)
}

pub fn with_max_connections_validates_positive_test() {
  // Should default to 1 if given 0 or negative
  let config =
    connection_config.new()
    |> connection_config.with_max_connections(0)

  connection_config.get_max_connections(config)
  |> should.equal(1)

  let config2 =
    connection_config.new()
    |> connection_config.with_max_connections(-5)

  connection_config.get_max_connections(config2)
  |> should.equal(1)
}

pub fn with_accept_timeout_test() {
  let config =
    connection_config.new()
    |> connection_config.with_accept_timeout(10_000)

  connection_config.get_accept_timeout(config)
  |> should.equal(10_000)
}

pub fn with_accept_timeout_validates_positive_test() {
  let config =
    connection_config.new()
    |> connection_config.with_accept_timeout(0)

  // Should default to 1000 if given 0 or negative
  connection_config.get_accept_timeout(config)
  |> should.equal(1000)
}

pub fn with_connection_timeout_test() {
  let config =
    connection_config.new()
    |> connection_config.with_connection_timeout(120_000)

  connection_config.get_connection_timeout(config)
  |> should.equal(120_000)
}

pub fn with_connection_timeout_allows_zero_test() {
  // Zero means no timeout
  let config =
    connection_config.new()
    |> connection_config.with_connection_timeout(0)

  connection_config.get_connection_timeout(config)
  |> should.equal(0)
}

pub fn with_keep_alive_test() {
  let config =
    connection_config.new()
    |> connection_config.with_keep_alive(False)

  connection_config.is_keep_alive_enabled(config)
  |> should.equal(False)

  let config2 =
    config
    |> connection_config.with_keep_alive(True)

  connection_config.is_keep_alive_enabled(config2)
  |> should.equal(True)
}

pub fn with_keep_alive_interval_test() {
  let config =
    connection_config.new()
    |> connection_config.with_keep_alive_interval(60_000)

  connection_config.get_keep_alive_interval(config)
  |> should.equal(60_000)
}

pub fn with_shutdown_timeout_test() {
  let config =
    connection_config.new()
    |> connection_config.with_shutdown_timeout(60_000)

  connection_config.get_shutdown_timeout(config)
  |> should.equal(60_000)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Chained Builder Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn chained_builder_test() {
  let config =
    connection_config.new()
    |> connection_config.with_max_connections(2000)
    |> connection_config.with_accept_timeout(2000)
    |> connection_config.with_connection_timeout(90_000)
    |> connection_config.with_keep_alive(True)
    |> connection_config.with_keep_alive_interval(45_000)
    |> connection_config.with_shutdown_timeout(60_000)

  connection_config.get_max_connections(config)
  |> should.equal(2000)

  connection_config.get_accept_timeout(config)
  |> should.equal(2000)

  connection_config.get_connection_timeout(config)
  |> should.equal(90_000)

  connection_config.is_keep_alive_enabled(config)
  |> should.equal(True)

  connection_config.get_keep_alive_interval(config)
  |> should.equal(45_000)

  connection_config.get_shutdown_timeout(config)
  |> should.equal(60_000)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Validation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn validate_valid_config_test() {
  let config = connection_config.new()

  connection_config.validate(config)
  |> should.be_ok
}

pub fn validate_valid_custom_config_test() {
  let config =
    connection_config.new()
    |> connection_config.with_max_connections(500)
    |> connection_config.with_connection_timeout(0)

  connection_config.validate(config)
  |> should.be_ok
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error String Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_to_string_invalid_max_connections_test() {
  let error = connection_config.InvalidMaxConnections(0)

  connection_config.error_to_string(error)
  |> should.equal("Invalid max_connections: 0 (must be > 0)")
}

pub fn error_to_string_invalid_timeout_test() {
  let error = connection_config.InvalidTimeout("accept_timeout_ms", -1)

  connection_config.error_to_string(error)
  |> should.equal("Invalid accept_timeout_ms: -1")
}
