// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Options Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/option.{type Option}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Socket options configuration using builder pattern
///
/// Provides comprehensive socket configuration options following
/// POSIX socket options and Erlang/OTP conventions.
///
/// ## Examples
///
/// ```gleam
/// // Create options for a high-performance TCP server
/// let server_opts = socket_options.new()
///   |> socket_options.with_reuseaddr(True)
///   |> socket_options.with_nodelay(True)
///   |> socket_options.with_backlog(1024)
///   |> socket_options.with_recv_buffer(65536)
///
/// // Create options for a client with timeout
/// let client_opts = socket_options.new()
///   |> socket_options.with_send_timeout(5000)
///   |> socket_options.with_active_mode(Once)
/// ```
///
pub type SocketOptions {
  SocketOptions(
    /// SO_REUSEADDR - Allow reuse of local addresses
    reuseaddr: Bool,
    /// SO_REUSEPORT - Allow multiple sockets to bind to same port
    reuseport: Bool,
    /// TCP_NODELAY - Disable Nagle's algorithm for TCP
    nodelay: Bool,
    /// SO_KEEPALIVE - Enable TCP keepalive probes
    keepalive: Bool,
    /// SO_RCVBUF - Receive buffer size in bytes
    recbuf: Option(Int),
    /// SO_SNDBUF - Send buffer size in bytes
    sndbuf: Option(Int),
    /// Internal buffer size for socket
    buffer: Option(Int),
    /// Send timeout in milliseconds
    send_timeout: Option(Int),
    /// Close socket on send timeout
    send_timeout_close: Bool,
    /// Listen backlog queue size
    backlog: Int,
    /// Active mode for async I/O
    active_mode: ActiveMode,
    /// SO_LINGER - Linger on close configuration
    linger: Option(LingerConfig),
    /// Interface to bind to
    interface: Interface,
    /// Enable IPv6 support
    ipv6: Bool,
  )
}

/// Active mode configuration for socket I/O
///
/// Controls how data is delivered from the socket to the owning process.
///
/// ## Variants
///
/// - `Passive`: Data must be explicitly read using recv()
/// - `Once`: Receive one message then switch to Passive
/// - `Count(n)`: Receive n messages then switch to Passive
/// - `Active`: Continuously receive messages (use with caution)
///
pub type ActiveMode {
  /// Data must be explicitly read using recv()
  Passive
  /// Receive one message then switch to Passive
  Once
  /// Receive n messages then switch to Passive
  Count(Int)
  /// Continuously receive messages (use with caution for flow control)
  Active
}

/// SO_LINGER configuration
///
/// Controls socket behavior on close when unsent data exists.
///
pub type LingerConfig {
  LingerConfig(
    /// Whether linger is enabled
    enabled: Bool,
    /// Timeout in seconds to wait for data to be sent
    timeout_seconds: Int,
  )
}

/// Interface binding configuration
///
/// Specifies which network interface to bind the socket to.
///
pub type Interface {
  /// Bind to a specific IP address
  Address(IpAddress)
  /// Bind to all available interfaces (0.0.0.0 or ::)
  Any
  /// Bind to localhost only (127.0.0.1 or ::1)
  Loopback
}

/// IP address representation
///
pub type IpAddress {
  /// IPv4 address (4 octets)
  IpV4(Int, Int, Int, Int)
  /// IPv6 address (8 groups of 16 bits)
  IpV6(Int, Int, Int, Int, Int, Int, Int, Int)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates new socket options with minimal defaults
///
/// ## Returns
///
/// SocketOptions with conservative default values
///
pub fn new() -> SocketOptions {
  SocketOptions(
    reuseaddr: False,
    reuseport: False,
    nodelay: False,
    keepalive: False,
    recbuf: option.None,
    sndbuf: option.None,
    buffer: option.None,
    send_timeout: option.None,
    send_timeout_close: False,
    backlog: 128,
    active_mode: Passive,
    linger: option.None,
    interface: Any,
    ipv6: False,
  )
}

/// Creates default options optimized for TCP sockets
///
/// Enables common TCP optimizations like nodelay and keepalive.
///
/// ## Returns
///
/// SocketOptions configured for TCP usage
///
pub fn tcp_defaults() -> SocketOptions {
  SocketOptions(
    reuseaddr: True,
    reuseport: False,
    nodelay: True,
    keepalive: True,
    recbuf: option.None,
    sndbuf: option.None,
    buffer: option.None,
    send_timeout: option.Some(30_000),
    send_timeout_close: True,
    backlog: 128,
    active_mode: Passive,
    linger: option.None,
    interface: Any,
    ipv6: False,
  )
}

/// Creates default options optimized for UDP sockets
///
/// ## Returns
///
/// SocketOptions configured for UDP usage
///
pub fn udp_defaults() -> SocketOptions {
  SocketOptions(
    reuseaddr: True,
    reuseport: False,
    nodelay: False,
    keepalive: False,
    recbuf: option.None,
    sndbuf: option.None,
    buffer: option.None,
    send_timeout: option.None,
    send_timeout_close: False,
    backlog: 0,
    active_mode: Passive,
    linger: option.None,
    interface: Any,
    ipv6: False,
  )
}

/// Creates default options optimized for server sockets
///
/// Enables options commonly needed for server applications like
/// reuseaddr and larger backlog.
///
/// ## Returns
///
/// SocketOptions configured for server usage
///
pub fn server_defaults() -> SocketOptions {
  SocketOptions(
    reuseaddr: True,
    reuseport: False,
    nodelay: True,
    keepalive: True,
    recbuf: option.None,
    sndbuf: option.None,
    buffer: option.None,
    send_timeout: option.Some(30_000),
    send_timeout_close: True,
    backlog: 1024,
    active_mode: Passive,
    linger: option.None,
    interface: Any,
    ipv6: False,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Builder Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the SO_REUSEADDR option
///
/// When enabled, allows binding to an address that is already in use.
/// This is commonly needed for servers to restart quickly.
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `enabled`: Whether to enable the option
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_reuseaddr(opts: SocketOptions, enabled: Bool) -> SocketOptions {
  SocketOptions(..opts, reuseaddr: enabled)
}

/// Sets the SO_REUSEPORT option
///
/// When enabled, allows multiple sockets to bind to the same port.
/// This enables load balancing across multiple processes.
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `enabled`: Whether to enable the option
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_reuseport(opts: SocketOptions, enabled: Bool) -> SocketOptions {
  SocketOptions(..opts, reuseport: enabled)
}

/// Sets the TCP_NODELAY option
///
/// When enabled, disables Nagle's algorithm, sending data immediately
/// without waiting to coalesce small packets. Recommended for
/// low-latency applications.
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `enabled`: Whether to enable the option
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_nodelay(opts: SocketOptions, enabled: Bool) -> SocketOptions {
  SocketOptions(..opts, nodelay: enabled)
}

/// Sets the SO_KEEPALIVE option
///
/// When enabled, the system sends periodic keepalive probes on idle
/// connections to detect dead peers.
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `enabled`: Whether to enable the option
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_keepalive(opts: SocketOptions, enabled: Bool) -> SocketOptions {
  SocketOptions(..opts, keepalive: enabled)
}

/// Sets both receive and send buffer sizes
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `size`: Buffer size in bytes
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_buffer_size(opts: SocketOptions, size: Int) -> SocketOptions {
  SocketOptions(
    ..opts,
    recbuf: option.Some(size),
    sndbuf: option.Some(size),
    buffer: option.Some(size),
  )
}

/// Sets the receive buffer size (SO_RCVBUF)
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `size`: Receive buffer size in bytes
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_recv_buffer(opts: SocketOptions, size: Int) -> SocketOptions {
  SocketOptions(..opts, recbuf: option.Some(size))
}

/// Sets the send buffer size (SO_SNDBUF)
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `size`: Send buffer size in bytes
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_send_buffer(opts: SocketOptions, size: Int) -> SocketOptions {
  SocketOptions(..opts, sndbuf: option.Some(size))
}

/// Sets the internal buffer size
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `size`: Internal buffer size in bytes
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_buffer(opts: SocketOptions, size: Int) -> SocketOptions {
  SocketOptions(..opts, buffer: option.Some(size))
}

/// Sets the send timeout
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `timeout_ms`: Timeout in milliseconds
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_send_timeout(opts: SocketOptions, timeout_ms: Int) -> SocketOptions {
  SocketOptions(..opts, send_timeout: option.Some(timeout_ms))
}

/// Sets whether to close socket on send timeout
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `close`: Whether to close on timeout
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_send_timeout_close(opts: SocketOptions, close: Bool) -> SocketOptions {
  SocketOptions(..opts, send_timeout_close: close)
}

/// Sets the listen backlog queue size
///
/// This determines how many pending connections can be queued
/// before new connections are refused.
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `size`: Maximum queue size
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_backlog(opts: SocketOptions, size: Int) -> SocketOptions {
  SocketOptions(..opts, backlog: size)
}

/// Sets the active mode for async I/O
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `mode`: The active mode to use
///
/// ## Returns
///
/// Updated SocketOptions
///
/// ## Examples
///
/// ```gleam
/// // Receive one message at a time (recommended)
/// let opts = socket_options.new()
///   |> socket_options.with_active_mode(Once)
///
/// // Receive up to 10 messages before switching to passive
/// let opts = socket_options.new()
///   |> socket_options.with_active_mode(Count(10))
/// ```
///
pub fn with_active_mode(opts: SocketOptions, mode: ActiveMode) -> SocketOptions {
  SocketOptions(..opts, active_mode: mode)
}

/// Sets the SO_LINGER option
///
/// Controls socket behavior on close when unsent data exists.
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `config`: The linger configuration
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_linger(opts: SocketOptions, config: LingerConfig) -> SocketOptions {
  SocketOptions(..opts, linger: option.Some(config))
}

/// Sets the interface to bind to
///
/// ## Parameters
///
/// - `opts`: The options to modify
/// - `iface`: The interface configuration
///
/// ## Returns
///
/// Updated SocketOptions
///
pub fn with_interface(opts: SocketOptions, iface: Interface) -> SocketOptions {
  SocketOptions(..opts, interface: iface)
}

/// Enables IPv6 support
///
/// ## Parameters
///
/// - `opts`: The options to modify
///
/// ## Returns
///
/// Updated SocketOptions with IPv6 enabled
///
pub fn with_ipv6(opts: SocketOptions) -> SocketOptions {
  SocketOptions(..opts, ipv6: True)
}

/// Disables IPv6 support
///
/// ## Parameters
///
/// - `opts`: The options to modify
///
/// ## Returns
///
/// Updated SocketOptions with IPv6 disabled
///
pub fn without_ipv6(opts: SocketOptions) -> SocketOptions {
  SocketOptions(..opts, ipv6: False)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accessor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the reuseaddr setting
///
pub fn get_reuseaddr(opts: SocketOptions) -> Bool {
  opts.reuseaddr
}

/// Gets the nodelay setting
///
pub fn get_nodelay(opts: SocketOptions) -> Bool {
  opts.nodelay
}

/// Gets the keepalive setting
///
pub fn get_keepalive(opts: SocketOptions) -> Bool {
  opts.keepalive
}

/// Gets the backlog setting
///
pub fn get_backlog(opts: SocketOptions) -> Int {
  opts.backlog
}

/// Gets the active mode setting
///
pub fn get_active_mode(opts: SocketOptions) -> ActiveMode {
  opts.active_mode
}

/// Gets the interface setting
///
pub fn get_interface(opts: SocketOptions) -> Interface {
  opts.interface
}

/// Checks if IPv6 is enabled
///
pub fn is_ipv6(opts: SocketOptions) -> Bool {
  opts.ipv6
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a LingerConfig
///
/// ## Parameters
///
/// - `timeout_seconds`: Time to wait for data to be sent on close
///
/// ## Returns
///
/// A LingerConfig with linger enabled
///
pub fn linger_config(timeout_seconds: Int) -> LingerConfig {
  LingerConfig(enabled: True, timeout_seconds: timeout_seconds)
}

/// Creates a disabled LingerConfig
///
/// ## Returns
///
/// A LingerConfig with linger disabled
///
pub fn linger_disabled() -> LingerConfig {
  LingerConfig(enabled: False, timeout_seconds: 0)
}

/// Creates an IPv4 address
///
/// ## Parameters
///
/// - `a`, `b`, `c`, `d`: The four octets of the IPv4 address
///
/// ## Returns
///
/// An IpAddress representing the IPv4 address
///
pub fn ipv4(a: Int, b: Int, c: Int, d: Int) -> IpAddress {
  IpV4(a, b, c, d)
}

/// Creates an IPv6 address
///
/// ## Parameters
///
/// - 8 groups of 16-bit values
///
/// ## Returns
///
/// An IpAddress representing the IPv6 address
///
pub fn ipv6(
  a: Int,
  b: Int,
  c: Int,
  d: Int,
  e: Int,
  f: Int,
  g: Int,
  h: Int,
) -> IpAddress {
  IpV6(a, b, c, d, e, f, g, h)
}

/// Returns the localhost IPv4 address (127.0.0.1)
///
pub fn localhost() -> IpAddress {
  IpV4(127, 0, 0, 1)
}

/// Returns the any IPv4 address (0.0.0.0)
///
pub fn any_address() -> IpAddress {
  IpV4(0, 0, 0, 0)
}

/// Returns the localhost IPv6 address (::1)
///
pub fn localhost_v6() -> IpAddress {
  IpV6(0, 0, 0, 0, 0, 0, 0, 1)
}

/// Returns the any IPv6 address (::)
///
pub fn any_address_v6() -> IpAddress {
  IpV6(0, 0, 0, 0, 0, 0, 0, 0)
}

/// Converts an IP address to a string representation
///
/// ## Examples
///
/// ```gleam
/// ip_to_string(IpV4(127, 0, 0, 1)) // -> "127.0.0.1"
/// ip_to_string(IpV6(0, 0, 0, 0, 0, 0, 0, 1)) // -> "::1" (simplified)
/// ```
///
pub fn ip_to_string(ip: IpAddress) -> String {
  case ip {
    IpV4(a, b, c, d) ->
      int_to_string(a)
      <> "."
      <> int_to_string(b)
      <> "."
      <> int_to_string(c)
      <> "."
      <> int_to_string(d)
    IpV6(a, b, c, d, e, f, g, h) ->
      hex_to_string(a)
      <> ":"
      <> hex_to_string(b)
      <> ":"
      <> hex_to_string(c)
      <> ":"
      <> hex_to_string(d)
      <> ":"
      <> hex_to_string(e)
      <> ":"
      <> hex_to_string(f)
      <> ":"
      <> hex_to_string(g)
      <> ":"
      <> hex_to_string(h)
  }
}

/// Internal function to convert an integer to string
@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(n: Int) -> String

/// Internal function to convert an integer to hex string
fn hex_to_string(n: Int) -> String {
  do_hex_to_string(n)
}

@external(erlang, "erlang", "integer_to_binary")
fn do_hex_to_string(n: Int) -> String
