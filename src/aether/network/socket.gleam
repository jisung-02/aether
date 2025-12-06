// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Module - Core Types and Operations
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/network/socket_error.{type SocketError}
import aether/network/socket_options.{type IpAddress, type SocketOptions}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Core Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Represents a network socket for TCP or UDP connections
///
/// This is the main socket type used throughout the Aether networking layer.
/// It wraps the underlying platform socket and provides a unified interface
/// for both TCP and UDP operations.
///
/// ## Examples
///
/// ```gleam
/// // Create a TCP connection
/// let assert Ok(socket) = tcp.connect("localhost", 8080, socket_options.tcp_defaults())
///
/// // Send data
/// let assert Ok(Nil) = socket.send(socket, <<"Hello">>)
///
/// // Receive data
/// let assert Ok(data) = socket.recv(socket, 1024)
/// ```
///
pub type Socket {
  Socket(
    /// The underlying platform socket
    inner: InnerSocket,
    /// Transport protocol type
    transport: SocketTransport,
    /// Current socket state
    state: SocketState,
    /// Applied socket options
    options: SocketOptions,
    /// Subject for receiving async messages (when in active mode)
    subject: Option(Subject(SocketMessage)),
  )
}

/// Internal socket representation
///
/// This is an opaque type that wraps the platform-specific socket handle.
/// For TCP, this wraps glisten's Socket type.
/// For UDP, this wraps the Erlang gen_udp socket.
///
pub type InnerSocket

/// Represents a listening socket that can accept connections
///
/// Listening sockets are created by calling `tcp.listen()` and are used
/// to accept incoming client connections.
///
pub type ListenSocket {
  ListenSocket(
    /// The underlying platform listen socket
    inner: InnerListenSocket,
    /// Transport protocol type
    transport: SocketTransport,
    /// Port the socket is listening on
    port: Int,
    /// Applied socket options
    options: SocketOptions,
  )
}

/// Internal listen socket representation
///
pub type InnerListenSocket

/// Transport protocol types
///
pub type SocketTransport {
  /// TCP (Transmission Control Protocol) - reliable, ordered, connection-based
  Tcp
  /// UDP (User Datagram Protocol) - unreliable, unordered, connectionless
  Udp
}

/// Socket connection states
///
pub type SocketState {
  /// Socket has been created but not yet configured
  Created
  /// Socket is in the process of connecting
  Connecting
  /// Socket is connected and ready for I/O
  Connected
  /// Socket is bound to a local address (UDP)
  Bound
  /// Socket is listening for incoming connections (TCP server)
  Listening
  /// Socket has been closed
  Closed
}

/// Messages received from sockets in active mode
///
/// When a socket is in active mode (Once, Count, or Active), incoming
/// data and events are delivered as messages to the socket's Subject.
///
pub type SocketMessage {
  /// Data received from the socket
  Data(BitArray)
  /// The socket has been closed
  SocketClosed
  /// An error occurred on the socket
  SocketError(SocketError)
}

/// Socket address with Unix domain socket support
///
/// Represents an endpoint for socket communication, supporting both
/// IP-based addresses and Unix domain socket paths.
///
pub type SocketAddress {
  /// IP address with port
  IpAddr(ip: IpAddress, port: Int)
  /// Unix domain socket path
  UnixPath(path: String)
}

/// Shutdown direction for graceful socket shutdown
///
pub type ShutdownHow {
  /// Shutdown reading from the socket
  Read
  /// Shutdown writing to the socket
  Write
  /// Shutdown both reading and writing
  Both
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Creation Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new Socket from an inner socket handle
///
/// This is an internal function used by tcp.gleam and udp.gleam
/// to construct Socket values after successful connection/binding.
///
pub fn from_inner(
  inner: InnerSocket,
  transport: SocketTransport,
  state: SocketState,
  options: SocketOptions,
) -> Socket {
  Socket(
    inner: inner,
    transport: transport,
    state: state,
    options: options,
    subject: option.None,
  )
}

/// Creates a new ListenSocket from an inner socket handle
///
pub fn listen_socket_from_inner(
  inner: InnerListenSocket,
  transport: SocketTransport,
  port: Int,
  options: SocketOptions,
) -> ListenSocket {
  ListenSocket(
    inner: inner,
    transport: transport,
    port: port,
    options: options,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Subject-based Async I/O
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Associates a Subject with a socket for receiving async messages
///
/// When a socket is in active mode, incoming data and events are
/// delivered to this Subject.
///
/// ## Parameters
///
/// - `socket`: The socket to associate with the Subject
/// - `subject`: The Subject to receive messages
///
/// ## Returns
///
/// A new Socket with the Subject associated
///
/// ## Examples
///
/// ```gleam
/// // Create a subject for receiving socket messages
/// let subject = process.new_subject()
///
/// // Associate it with the socket
/// let socket = socket.with_subject(socket, subject)
///
/// // Set to active mode to start receiving messages
/// let assert Ok(socket) = socket.set_active(socket, Once)
///
/// // Receive messages
/// case process.receive(subject, 5000) {
///   Ok(Data(bytes)) -> handle_data(bytes)
///   Ok(SocketClosed) -> handle_close()
///   Ok(SocketError(err)) -> handle_error(err)
///   Error(Nil) -> handle_timeout()
/// }
/// ```
///
pub fn with_subject(
  socket: Socket,
  subject: Subject(SocketMessage),
) -> Socket {
  Socket(..socket, subject: option.Some(subject))
}

/// Gets the Subject associated with a socket
///
/// ## Parameters
///
/// - `socket`: The socket to get the Subject from
///
/// ## Returns
///
/// The Subject if one is associated, None otherwise
///
pub fn get_subject(socket: Socket) -> Option(Subject(SocketMessage)) {
  socket.subject
}

/// Removes the Subject association from a socket
///
/// ## Parameters
///
/// - `socket`: The socket to remove the Subject from
///
/// ## Returns
///
/// A new Socket without a Subject
///
pub fn without_subject(socket: Socket) -> Socket {
  Socket(..socket, subject: option.None)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket State Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the current state of a socket
///
pub fn get_state(socket: Socket) -> SocketState {
  socket.state
}

/// Gets the transport type of a socket
///
pub fn get_transport(socket: Socket) -> SocketTransport {
  socket.transport
}

/// Gets the options of a socket
///
pub fn get_options(socket: Socket) -> SocketOptions {
  socket.options
}

/// Gets the inner socket handle
///
/// This is an internal function for use by transport modules.
///
pub fn get_inner(socket: Socket) -> InnerSocket {
  socket.inner
}

/// Gets the inner listen socket handle
///
pub fn get_listen_inner(socket: ListenSocket) -> InnerListenSocket {
  socket.inner
}

/// Gets the port of a listen socket
///
pub fn get_listen_port(socket: ListenSocket) -> Int {
  socket.port
}

/// Checks if a socket is connected
///
pub fn is_connected(socket: Socket) -> Bool {
  case socket.state {
    Connected -> True
    _ -> False
  }
}

/// Checks if a socket is closed
///
pub fn is_closed(socket: Socket) -> Bool {
  case socket.state {
    Closed -> True
    _ -> False
  }
}

/// Updates the socket state
///
/// This is an internal function for use by transport modules.
///
pub fn set_state(socket: Socket, state: SocketState) -> Socket {
  Socket(..socket, state: state)
}

/// Updates the socket options
///
/// This is an internal function for use by transport modules.
///
pub fn set_socket_options(socket: Socket, options: SocketOptions) -> Socket {
  Socket(..socket, options: options)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Address Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates an IP socket address
///
/// ## Parameters
///
/// - `ip`: The IP address
/// - `port`: The port number
///
/// ## Returns
///
/// A SocketAddress for the IP and port
///
pub fn ip_address(ip: IpAddress, port: Int) -> SocketAddress {
  IpAddr(ip: ip, port: port)
}

/// Creates an IPv4 socket address
///
/// ## Parameters
///
/// - `a`, `b`, `c`, `d`: The four octets of the IPv4 address
/// - `port`: The port number
///
/// ## Returns
///
/// A SocketAddress for the IPv4 address and port
///
pub fn ipv4_address(
  a: Int,
  b: Int,
  c: Int,
  d: Int,
  port: Int,
) -> SocketAddress {
  IpAddr(ip: socket_options.IpV4(a, b, c, d), port: port)
}

/// Creates a Unix domain socket address
///
/// ## Parameters
///
/// - `path`: The file system path to the Unix socket
///
/// ## Returns
///
/// A SocketAddress for the Unix socket path
///
pub fn unix_address(path: String) -> SocketAddress {
  UnixPath(path: path)
}

/// Creates a localhost IPv4 address with port
///
pub fn localhost_address(port: Int) -> SocketAddress {
  IpAddr(ip: socket_options.localhost(), port: port)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Type Conversion Utilities
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a transport type to a string
///
pub fn transport_to_string(transport: SocketTransport) -> String {
  case transport {
    Tcp -> "TCP"
    Udp -> "UDP"
  }
}

/// Converts a socket state to a string
///
pub fn state_to_string(state: SocketState) -> String {
  case state {
    Created -> "Created"
    Connecting -> "Connecting"
    Connected -> "Connected"
    Bound -> "Bound"
    Listening -> "Listening"
    Closed -> "Closed"
  }
}

/// Converts a shutdown direction to a string
///
pub fn shutdown_to_string(how: ShutdownHow) -> String {
  case how {
    Read -> "Read"
    Write -> "Write"
    Both -> "Both"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// FFI Type Coercion
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Coerces a value to InnerSocket type
///
/// This is used internally to wrap platform socket handles.
/// SAFETY: Only call with valid socket handles from Erlang FFI.
///
@external(erlang, "gleam@function", "identity")
pub fn coerce_to_inner_socket(value: a) -> InnerSocket

/// Coerces a value to InnerListenSocket type
///
@external(erlang, "gleam@function", "identity")
pub fn coerce_to_inner_listen_socket(value: a) -> InnerListenSocket

/// Coerces InnerSocket to a specific type for FFI calls
///
@external(erlang, "gleam@function", "identity")
pub fn coerce_inner_socket(socket: InnerSocket) -> a

/// Coerces InnerListenSocket to a specific type for FFI calls
///
@external(erlang, "gleam@function", "identity")
pub fn coerce_inner_listen_socket(socket: InnerListenSocket) -> a
