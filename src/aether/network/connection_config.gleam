// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Configuration Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// This module provides configuration types and builder functions for
// the Connection Manager. It follows a builder pattern for flexible
// and readable configuration.
//

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Configuration for the Connection Manager
///
/// Controls connection pool behavior, timeouts, and lifecycle management.
///
/// ## Examples
///
/// ```gleam
/// // Create a custom configuration
/// let config = connection_config.new()
///   |> connection_config.with_max_connections(500)
///   |> connection_config.with_connection_timeout(120_000)
///
/// // Or use a preset
/// let config = connection_config.high_throughput()
/// ```
///
pub type ConnectionConfig {
  ConnectionConfig(
    /// Maximum number of concurrent connections allowed
    max_connections: Int,
    /// Timeout for accepting new connections in milliseconds
    accept_timeout_ms: Int,
    /// Idle timeout for connections in milliseconds (0 = no timeout)
    connection_timeout_ms: Int,
    /// Enable TCP keepalive probes
    keep_alive: Bool,
    /// Interval between keepalive probes in milliseconds
    keep_alive_interval_ms: Int,
    /// Maximum time to wait for graceful shutdown in milliseconds
    shutdown_timeout_ms: Int,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new ConnectionConfig with sensible defaults
///
/// Default values:
/// - max_connections: 1000
/// - accept_timeout_ms: 5000 (5 seconds)
/// - connection_timeout_ms: 60000 (60 seconds)
/// - keep_alive: True
/// - keep_alive_interval_ms: 30000 (30 seconds)
/// - shutdown_timeout_ms: 30000 (30 seconds)
///
/// ## Returns
///
/// A ConnectionConfig with default values
///
pub fn new() -> ConnectionConfig {
  ConnectionConfig(
    max_connections: 1000,
    accept_timeout_ms: 5000,
    connection_timeout_ms: 60_000,
    keep_alive: True,
    keep_alive_interval_ms: 30_000,
    shutdown_timeout_ms: 30_000,
  )
}

/// Alias for new() - creates default configuration
///
pub fn default() -> ConnectionConfig {
  new()
}

/// Creates a configuration optimized for high throughput
///
/// Designed for scenarios with many short-lived connections:
/// - max_connections: 10000
/// - accept_timeout_ms: 1000 (1 second)
/// - connection_timeout_ms: 30000 (30 seconds)
/// - Keepalive disabled to reduce overhead
///
pub fn high_throughput() -> ConnectionConfig {
  ConnectionConfig(
    max_connections: 10_000,
    accept_timeout_ms: 1000,
    connection_timeout_ms: 30_000,
    keep_alive: False,
    keep_alive_interval_ms: 0,
    shutdown_timeout_ms: 10_000,
  )
}

/// Creates a configuration for long-lived connections
///
/// Designed for scenarios with persistent connections:
/// - max_connections: 100
/// - connection_timeout_ms: 0 (no timeout)
/// - Aggressive keepalive settings
///
pub fn long_lived() -> ConnectionConfig {
  ConnectionConfig(
    max_connections: 100,
    accept_timeout_ms: 10_000,
    connection_timeout_ms: 0,
    keep_alive: True,
    keep_alive_interval_ms: 15_000,
    shutdown_timeout_ms: 60_000,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Builder Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the maximum number of concurrent connections
///
/// ## Parameters
///
/// - `config`: The configuration to modify
/// - `max`: Maximum connection count (must be > 0)
///
/// ## Returns
///
/// Updated ConnectionConfig
///
pub fn with_max_connections(
  config: ConnectionConfig,
  max: Int,
) -> ConnectionConfig {
  let validated_max = case max > 0 {
    True -> max
    False -> 1
  }
  ConnectionConfig(..config, max_connections: validated_max)
}

/// Sets the accept timeout
///
/// ## Parameters
///
/// - `config`: The configuration to modify
/// - `timeout_ms`: Timeout in milliseconds (must be > 0)
///
/// ## Returns
///
/// Updated ConnectionConfig
///
pub fn with_accept_timeout(
  config: ConnectionConfig,
  timeout_ms: Int,
) -> ConnectionConfig {
  let validated_timeout = case timeout_ms > 0 {
    True -> timeout_ms
    False -> 1000
  }
  ConnectionConfig(..config, accept_timeout_ms: validated_timeout)
}

/// Sets the connection idle timeout
///
/// Set to 0 to disable idle timeout (connections never expire due to inactivity).
///
/// ## Parameters
///
/// - `config`: The configuration to modify
/// - `timeout_ms`: Timeout in milliseconds (0 = no timeout)
///
/// ## Returns
///
/// Updated ConnectionConfig
///
pub fn with_connection_timeout(
  config: ConnectionConfig,
  timeout_ms: Int,
) -> ConnectionConfig {
  let validated_timeout = case timeout_ms >= 0 {
    True -> timeout_ms
    False -> 0
  }
  ConnectionConfig(..config, connection_timeout_ms: validated_timeout)
}

/// Enables or disables TCP keepalive
///
/// ## Parameters
///
/// - `config`: The configuration to modify
/// - `enabled`: Whether keepalive is enabled
///
/// ## Returns
///
/// Updated ConnectionConfig
///
pub fn with_keep_alive(
  config: ConnectionConfig,
  enabled: Bool,
) -> ConnectionConfig {
  ConnectionConfig(..config, keep_alive: enabled)
}

/// Sets the keepalive probe interval
///
/// ## Parameters
///
/// - `config`: The configuration to modify
/// - `interval_ms`: Interval in milliseconds
///
/// ## Returns
///
/// Updated ConnectionConfig
///
pub fn with_keep_alive_interval(
  config: ConnectionConfig,
  interval_ms: Int,
) -> ConnectionConfig {
  let validated_interval = case interval_ms > 0 {
    True -> interval_ms
    False -> 30_000
  }
  ConnectionConfig(..config, keep_alive_interval_ms: validated_interval)
}

/// Sets the graceful shutdown timeout
///
/// ## Parameters
///
/// - `config`: The configuration to modify
/// - `timeout_ms`: Timeout in milliseconds
///
/// ## Returns
///
/// Updated ConnectionConfig
///
pub fn with_shutdown_timeout(
  config: ConnectionConfig,
  timeout_ms: Int,
) -> ConnectionConfig {
  let validated_timeout = case timeout_ms > 0 {
    True -> timeout_ms
    False -> 30_000
  }
  ConnectionConfig(..config, shutdown_timeout_ms: validated_timeout)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accessor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the maximum connections setting
///
pub fn get_max_connections(config: ConnectionConfig) -> Int {
  config.max_connections
}

/// Gets the accept timeout setting
///
pub fn get_accept_timeout(config: ConnectionConfig) -> Int {
  config.accept_timeout_ms
}

/// Gets the connection timeout setting
///
pub fn get_connection_timeout(config: ConnectionConfig) -> Int {
  config.connection_timeout_ms
}

/// Checks if keepalive is enabled
///
pub fn is_keep_alive_enabled(config: ConnectionConfig) -> Bool {
  config.keep_alive
}

/// Gets the keepalive interval setting
///
pub fn get_keep_alive_interval(config: ConnectionConfig) -> Int {
  config.keep_alive_interval_ms
}

/// Gets the shutdown timeout setting
///
pub fn get_shutdown_timeout(config: ConnectionConfig) -> Int {
  config.shutdown_timeout_ms
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Validation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Configuration validation error
///
pub type ConfigError {
  InvalidMaxConnections(value: Int)
  InvalidTimeout(field: String, value: Int)
}

/// Validates the configuration and returns any errors
///
/// ## Parameters
///
/// - `config`: The configuration to validate
///
/// ## Returns
///
/// Ok(config) if valid, Error(ConfigError) otherwise
///
pub fn validate(
  config: ConnectionConfig,
) -> Result(ConnectionConfig, ConfigError) {
  case config.max_connections > 0 {
    False -> Error(InvalidMaxConnections(config.max_connections))
    True ->
      case config.accept_timeout_ms > 0 {
        False -> Error(InvalidTimeout("accept_timeout_ms", config.accept_timeout_ms))
        True ->
          case config.connection_timeout_ms >= 0 {
            False ->
              Error(InvalidTimeout(
                "connection_timeout_ms",
                config.connection_timeout_ms,
              ))
            True -> Ok(config)
          }
      }
  }
}

/// Converts a ConfigError to a human-readable string
///
pub fn error_to_string(error: ConfigError) -> String {
  case error {
    InvalidMaxConnections(value) ->
      "Invalid max_connections: " <> int_to_string(value) <> " (must be > 0)"
    InvalidTimeout(field, value) ->
      "Invalid " <> field <> ": " <> int_to_string(value)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(n: Int) -> String
