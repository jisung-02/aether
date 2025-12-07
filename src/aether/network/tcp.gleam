// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Socket Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/network/socket.{
  type ListenSocket, type ShutdownHow, type Socket, type SocketAddress,
  Connected, Tcp,
}
import aether/network/socket_error.{type SocketError}
import aether/network/socket_options.{
  type ActiveMode, type SocketOptions, Active, Count, Once, Passive,
}
import gleam/bytes_tree.{type BytesTree}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/option
import glisten/socket as glisten_socket
import glisten/socket/options as glisten_options
import glisten/tcp as glisten_tcp

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a TCP connection to the specified host and port
///
/// ## Parameters
///
/// - `host`: The hostname or IP address to connect to
/// - `port`: The port number to connect to
/// - `options`: Socket options for the connection
///
/// ## Returns
///
/// A connected Socket on success, or a SocketError on failure
///
/// ## Examples
///
/// ```gleam
/// let opts = socket_options.tcp_defaults()
/// case tcp.connect("localhost", 8080, opts) {
///   Ok(socket) -> {
///     // Use the socket...
///     let assert Ok(Nil) = tcp.close(socket)
///   }
///   Error(err) -> io.println("Failed: " <> socket_error.to_string(err))
/// }
/// ```
///
pub fn connect(
  host: String,
  port: Int,
  options: SocketOptions,
) -> Result(Socket, SocketError) {
  case
    ffi_connect(
      host,
      port,
      options.reuseaddr,
      options.nodelay,
      options.keepalive,
    )
  {
    Ok(inner_socket) -> {
      let inner = socket.coerce_to_inner_socket(inner_socket)
      Ok(socket.from_inner(inner, Tcp, Connected, options))
    }
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

/// Creates a TCP connection with a timeout
///
/// ## Parameters
///
/// - `host`: The hostname or IP address to connect to
/// - `port`: The port number to connect to
/// - `options`: Socket options for the connection
/// - `timeout_ms`: Connection timeout in milliseconds
///
/// ## Returns
///
/// A connected Socket on success, or a SocketError on failure
///
pub fn connect_timeout(
  host: String,
  port: Int,
  options: SocketOptions,
  timeout_ms: Int,
) -> Result(Socket, SocketError) {
  case
    ffi_connect_timeout(
      host,
      port,
      options.reuseaddr,
      options.nodelay,
      options.keepalive,
      timeout_ms,
    )
  {
    Ok(inner_socket) -> {
      let inner = socket.coerce_to_inner_socket(inner_socket)
      Ok(socket.from_inner(inner, Tcp, Connected, options))
    }
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Server Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a listening TCP socket bound to the specified port
///
/// ## Parameters
///
/// - `port`: The port number to listen on (0 for random available port)
/// - `options`: Socket options for the listener
///
/// ## Returns
///
/// A listening socket on success, or a SocketError on failure
///
/// ## Examples
///
/// ```gleam
/// let opts = socket_options.server_defaults()
/// case tcp.listen(8080, opts) {
///   Ok(listen_socket) -> {
///     // Accept connections...
///     case tcp.accept(listen_socket) {
///       Ok(client) -> handle_client(client)
///       Error(err) -> io.println("Accept failed")
///     }
///   }
///   Error(err) -> io.println("Listen failed")
/// }
/// ```
///
pub fn listen(
  port: Int,
  options: SocketOptions,
) -> Result(ListenSocket, SocketError) {
  let glisten_opts = to_glisten_options(options)

  case glisten_tcp.listen(port, glisten_opts) {
    Ok(inner_socket) -> {
      let inner = socket.coerce_to_inner_listen_socket(inner_socket)
      Ok(socket.listen_socket_from_inner(inner, Tcp, port, options))
    }
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

/// Accepts a connection on a listening socket
///
/// This function blocks until a connection is available.
///
/// ## Parameters
///
/// - `listen_socket`: The listening socket to accept on
///
/// ## Returns
///
/// A connected Socket for the new client, or a SocketError on failure
///
pub fn accept(listen_socket: ListenSocket) -> Result(Socket, SocketError) {
  let inner =
    socket.coerce_inner_listen_socket(socket.get_listen_inner(listen_socket))

  case glisten_tcp.accept(inner) {
    Ok(client_socket) -> {
      let inner = socket.coerce_to_inner_socket(client_socket)
      Ok(socket.from_inner(inner, Tcp, Connected, listen_socket.options))
    }
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

/// Accepts a connection with a timeout
///
/// ## Parameters
///
/// - `listen_socket`: The listening socket to accept on
/// - `timeout_ms`: Timeout in milliseconds
///
/// ## Returns
///
/// A connected Socket for the new client, or a SocketError on failure
///
pub fn accept_timeout(
  listen_socket: ListenSocket,
  timeout_ms: Int,
) -> Result(Socket, SocketError) {
  let inner =
    socket.coerce_inner_listen_socket(socket.get_listen_inner(listen_socket))

  case glisten_tcp.accept_timeout(inner, timeout_ms) {
    Ok(client_socket) -> {
      let inner = socket.coerce_to_inner_socket(client_socket)
      Ok(socket.from_inner(inner, Tcp, Connected, listen_socket.options))
    }
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

/// Gets the actual port a listen socket is bound to
///
/// This is useful when listening on port 0 to get the assigned port.
///
/// ## Parameters
///
/// - `listen_socket`: The listening socket
///
/// ## Returns
///
/// The port number on success, or a SocketError on failure
///
pub fn get_port(listen_socket: ListenSocket) -> Result(Int, SocketError) {
  let inner =
    socket.coerce_inner_listen_socket(socket.get_listen_inner(listen_socket))

  case glisten_tcp.sockname(inner) {
    Ok(#(_, port)) -> Ok(port)
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// I/O Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sends data over the socket
///
/// ## Parameters
///
/// - `sock`: The socket to send on
/// - `data`: The data to send as a BitArray
///
/// ## Returns
///
/// Ok(Nil) on success, or a SocketError on failure
///
pub fn send(sock: Socket, data: BitArray) -> Result(Nil, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))
  let bytes = bytes_tree.from_bit_array(data)

  case glisten_tcp.send(inner, bytes) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

/// Sends a BytesTree over the socket
///
/// This is more efficient for sending multiple chunks of data.
///
/// ## Parameters
///
/// - `sock`: The socket to send on
/// - `data`: The data to send as a BytesTree
///
/// ## Returns
///
/// Ok(Nil) on success, or a SocketError on failure
///
pub fn send_bytes_tree(
  sock: Socket,
  data: BytesTree,
) -> Result(Nil, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case glisten_tcp.send(inner, data) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

/// Receives data from the socket
///
/// This function blocks until data is available or the socket is closed.
///
/// ## Parameters
///
/// - `sock`: The socket to receive from
/// - `length`: The maximum number of bytes to receive (0 for any available)
///
/// ## Returns
///
/// The received data on success, or a SocketError on failure
///
pub fn recv(sock: Socket, length: Int) -> Result(BitArray, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case glisten_tcp.receive(inner, length) {
    Ok(data) -> Ok(data)
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

/// Receives data from the socket with a timeout
///
/// ## Parameters
///
/// - `sock`: The socket to receive from
/// - `length`: The maximum number of bytes to receive (0 for any available)
/// - `timeout_ms`: Timeout in milliseconds
///
/// ## Returns
///
/// The received data on success, or a SocketError on failure
///
pub fn recv_timeout(
  sock: Socket,
  length: Int,
  timeout_ms: Int,
) -> Result(BitArray, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case glisten_tcp.receive_timeout(inner, length, timeout_ms) {
    Ok(data) -> Ok(data)
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Control Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Closes the socket
///
/// ## Parameters
///
/// - `sock`: The socket to close
///
/// ## Returns
///
/// Ok(Nil) on success, or a SocketError on failure
///
pub fn close(sock: Socket) -> Result(Nil, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case glisten_tcp.close(inner) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

/// Closes a listening socket
///
/// ## Parameters
///
/// - `sock`: The listening socket to close
///
/// ## Returns
///
/// Ok(Nil) on success, or a SocketError on failure
///
pub fn close_listen(sock: ListenSocket) -> Result(Nil, SocketError) {
  let inner = socket.coerce_inner_listen_socket(socket.get_listen_inner(sock))

  case glisten_tcp.close(inner) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> Error(socket_error.from_glisten_reason(reason))
  }
}

/// Gracefully shuts down the socket
///
/// ## Parameters
///
/// - `sock`: The socket to shutdown
/// - `how`: The shutdown direction (Read, Write, or Both)
///
/// ## Returns
///
/// Ok(Nil) on success, or a SocketError on failure
///
pub fn shutdown(sock: Socket, how: ShutdownHow) -> Result(Nil, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  // glisten's shutdown only supports write direction
  case how {
    socket.Write | socket.Both -> {
      case glisten_tcp.shutdown(inner) {
        Ok(Nil) -> Ok(Nil)
        Error(reason) -> Error(socket_error.from_glisten_reason(reason))
      }
    }
    socket.Read -> {
      // Read shutdown not directly supported, return ok
      Ok(Nil)
    }
  }
}

/// Sets the controlling process for the socket
///
/// The controlling process receives active mode messages.
///
/// ## Parameters
///
/// - `sock`: The socket to modify
/// - `pid`: The new controlling process
///
/// ## Returns
///
/// Ok(Nil) on success, or a SocketError on failure
///
pub fn set_controlling_process(
  sock: Socket,
  pid: Pid,
) -> Result(Nil, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case glisten_tcp.controlling_process(inner, pid) {
    Ok(Nil) -> Ok(Nil)
    Error(_atom) -> Error(socket_error.PermissionDenied)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Options Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets socket options on an existing socket
///
/// ## Parameters
///
/// - `sock`: The socket to modify
/// - `options`: The new options to apply
///
/// ## Returns
///
/// The updated Socket on success, or a SocketError on failure
///
pub fn set_options(
  sock: Socket,
  options: SocketOptions,
) -> Result(Socket, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))
  let glisten_opts = to_glisten_options(options)

  case glisten_tcp.set_opts(inner, glisten_opts) {
    Ok(Nil) -> Ok(socket.set_socket_options(sock, options))
    Error(Nil) -> Error(socket_error.InvalidArgument("Failed to set options"))
  }
}

/// Sets the socket to the specified active mode
///
/// ## Parameters
///
/// - `sock`: The socket to modify
/// - `mode`: The active mode to set
///
/// ## Returns
///
/// The updated Socket on success, or a SocketError on failure
///
pub fn set_active(sock: Socket, mode: ActiveMode) -> Result(Socket, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))
  let glisten_mode = case mode {
    Passive -> glisten_options.ActiveMode(glisten_options.Passive)
    Once -> glisten_options.ActiveMode(glisten_options.Once)
    Count(n) -> glisten_options.ActiveMode(glisten_options.Count(n))
    Active -> glisten_options.ActiveMode(glisten_options.Active)
  }

  case glisten_tcp.set_opts(inner, [glisten_mode]) {
    Ok(Nil) -> {
      let new_opts =
        socket_options.with_active_mode(socket.get_options(sock), mode)
      Ok(socket.set_socket_options(sock, new_opts))
    }
    Error(Nil) ->
      Error(socket_error.InvalidArgument("Failed to set active mode"))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Address Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the remote address of a connected socket
///
/// ## Parameters
///
/// - `sock`: The connected socket
///
/// ## Returns
///
/// The remote SocketAddress on success, or a SocketError on failure
///
pub fn peer_address(sock: Socket) -> Result(SocketAddress, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case glisten_tcp.peername(inner) {
    Ok(#(ip_dynamic, port)) -> {
      case decode_ip_address(ip_dynamic) {
        Ok(ip) -> Ok(socket.IpAddr(ip: ip, port: port))
        Error(Nil) ->
          Error(socket_error.InvalidArgument("Failed to decode address"))
      }
    }
    Error(Nil) -> Error(socket_error.NotConnected)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Internal Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts Aether SocketOptions to glisten TcpOptions
fn to_glisten_options(opts: SocketOptions) -> List(glisten_options.TcpOption) {
  let base_opts = [
    glisten_options.Reuseaddr(opts.reuseaddr),
    glisten_options.Nodelay(opts.nodelay),
    glisten_options.Backlog(opts.backlog),
    glisten_options.Mode(glisten_options.Binary),
    case opts.active_mode {
      Passive -> glisten_options.ActiveMode(glisten_options.Passive)
      Once -> glisten_options.ActiveMode(glisten_options.Once)
      Count(n) -> glisten_options.ActiveMode(glisten_options.Count(n))
      Active -> glisten_options.ActiveMode(glisten_options.Active)
    },
  ]

  let with_send_timeout = case opts.send_timeout {
    option.Some(timeout) -> [
      glisten_options.SendTimeout(timeout),
      glisten_options.SendTimeoutClose(opts.send_timeout_close),
      ..base_opts
    ]
    option.None -> base_opts
  }

  let with_linger = case opts.linger {
    option.Some(config) -> [
      glisten_options.Linger(#(config.enabled, config.timeout_seconds)),
      ..with_send_timeout
    ]
    option.None -> with_send_timeout
  }

  let with_buffer = case opts.buffer {
    option.Some(size) -> [glisten_options.Buffer(size), ..with_linger]
    option.None -> with_linger
  }

  let with_interface = case opts.interface {
    socket_options.Any -> with_buffer
    socket_options.Loopback -> [
      glisten_options.Ip(glisten_options.Loopback),
      ..with_buffer
    ]
    socket_options.Address(ip) -> {
      let glisten_ip = case ip {
        socket_options.IpV4(a, b, c, d) ->
          glisten_options.Address(glisten_options.IpV4(a, b, c, d))
        socket_options.IpV6(a, b, c, d, e, f, g, h) ->
          glisten_options.Address(glisten_options.IpV6(a, b, c, d, e, f, g, h))
      }
      [glisten_options.Ip(glisten_ip), ..with_buffer]
    }
  }

  case opts.ipv6 {
    True -> [glisten_options.Ipv6, ..with_interface]
    False -> with_interface
  }
}

/// Decodes a dynamic IP address from Erlang
fn decode_ip_address(ip: Dynamic) -> Result(socket_options.IpAddress, Nil) {
  // Try IPv4 first (4-tuple)
  case decode_ipv4_tuple(ip) {
    Ok(#(a, b, c, d)) -> Ok(socket_options.IpV4(a, b, c, d))
    Error(_) -> {
      // Try IPv6 (8-tuple) - need custom decoder
      Error(Nil)
    }
  }
}

/// Decodes a 4-element tuple for IPv4 addresses
@external(erlang, "aether_tcp_ffi", "decode_ipv4_tuple")
fn decode_ipv4_tuple(tuple: Dynamic) -> Result(#(Int, Int, Int, Int), Nil)

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Erlang FFI Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Connects to a remote host using FFI
@external(erlang, "aether_tcp_ffi", "connect")
fn ffi_connect(
  host: String,
  port: Int,
  reuseaddr: Bool,
  nodelay: Bool,
  keepalive: Bool,
) -> Result(glisten_socket.Socket, glisten_socket.SocketReason)

/// Connects to a remote host with timeout using FFI
@external(erlang, "aether_tcp_ffi", "connect_timeout")
fn ffi_connect_timeout(
  host: String,
  port: Int,
  reuseaddr: Bool,
  nodelay: Bool,
  keepalive: Bool,
  timeout: Int,
) -> Result(glisten_socket.Socket, glisten_socket.SocketReason)
