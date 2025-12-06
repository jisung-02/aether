// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// UDP Socket Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/network/socket.{
  type Socket, type SocketAddress, Bound, Connected, Udp,
}
import aether/network/socket_error.{type SocketError}
import aether/network/socket_options.{type ActiveMode, type SocketOptions}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Represents a received UDP datagram with sender information
///
pub type UdpDatagram {
  UdpDatagram(
    /// The sender's IP address
    from_ip: socket_options.IpAddress,
    /// The sender's port
    from_port: Int,
    /// The received data
    data: BitArray,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Opens a UDP socket bound to the specified port
///
/// Use port 0 to bind to a random available port.
///
pub fn bind(port: Int, options: SocketOptions) -> Result(Socket, SocketError) {
  case ffi_open(port, options.reuseaddr) {
    Ok(inner_socket) -> {
      let inner = socket.coerce_to_inner_socket(inner_socket)
      Ok(socket.from_inner(inner, Udp, Bound, options))
    }
    Error(reason) -> Error(map_error(reason))
  }
}

/// Creates a "connected" UDP socket to the specified host and port
///
/// A connected UDP socket can use send/2 instead of send_to/4 and will
/// only receive datagrams from the connected address.
///
pub fn connect(
  host: String,
  port: Int,
  options: SocketOptions,
) -> Result(Socket, SocketError) {
  // First, open a socket with port 0 (random)
  case ffi_open(0, options.reuseaddr) {
    Ok(inner_socket) -> {
      // Then connect to the destination
      case ffi_connect(inner_socket, host, port) {
        Ok(Nil) -> {
          let inner = socket.coerce_to_inner_socket(inner_socket)
          Ok(socket.from_inner(inner, Udp, Connected, options))
        }
        Error(reason) -> {
          // Clean up the socket on connect failure
          let _ = ffi_close(inner_socket)
          Error(map_error(reason))
        }
      }
    }
    Error(reason) -> Error(map_error(reason))
  }
}

/// Opens a UDP socket bound to a specific port and connected to a destination
///
pub fn connect_from(
  local_port: Int,
  host: String,
  remote_port: Int,
  options: SocketOptions,
) -> Result(Socket, SocketError) {
  case ffi_open(local_port, options.reuseaddr) {
    Ok(inner_socket) -> {
      case ffi_connect(inner_socket, host, remote_port) {
        Ok(Nil) -> {
          let inner = socket.coerce_to_inner_socket(inner_socket)
          Ok(socket.from_inner(inner, Udp, Connected, options))
        }
        Error(reason) -> {
          let _ = ffi_close(inner_socket)
          Error(map_error(reason))
        }
      }
    }
    Error(reason) -> Error(map_error(reason))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Sending Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sends data on a connected UDP socket
///
pub fn send(sock: Socket, data: BitArray) -> Result(Nil, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case ffi_send(inner, data) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> Error(map_error(reason))
  }
}

/// Sends data to a specific destination (connectionless UDP)
///
pub fn send_to(
  sock: Socket,
  host: String,
  port: Int,
  data: BitArray,
) -> Result(Nil, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case ffi_send_to(inner, host, port, data) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> Error(map_error(reason))
  }
}

/// Sends data to a socket address
///
pub fn send_to_address(
  sock: Socket,
  address: SocketAddress,
  data: BitArray,
) -> Result(Nil, SocketError) {
  case address {
    socket.IpAddr(ip, port) -> {
      let host = socket_options.ip_to_string(ip)
      send_to(sock, host, port, data)
    }
    socket.UnixPath(_) -> {
      Error(socket_error.InvalidArgument("Unix sockets not supported for UDP"))
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Receiving Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Receives data from a UDP socket (blocking, infinite timeout)
///
pub fn recv_from(sock: Socket, length: Int) -> Result(UdpDatagram, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case ffi_recv(inner, length) {
    Ok(#(ip_tuple, port, data)) -> {
      case decode_ip_tuple(ip_tuple) {
        Ok(ip) -> Ok(UdpDatagram(from_ip: ip, from_port: port, data: data))
        Error(Nil) ->
          Error(socket_error.InvalidArgument("Failed to decode sender address"))
      }
    }
    Error(reason) -> Error(map_error(reason))
  }
}

/// Receives data from a UDP socket with a timeout
///
pub fn recv_from_timeout(
  sock: Socket,
  length: Int,
  timeout_ms: Int,
) -> Result(UdpDatagram, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case ffi_recv_timeout(inner, length, timeout_ms) {
    Ok(#(ip_tuple, port, data)) -> {
      case decode_ip_tuple(ip_tuple) {
        Ok(ip) -> Ok(UdpDatagram(from_ip: ip, from_port: port, data: data))
        Error(Nil) ->
          Error(socket_error.InvalidArgument("Failed to decode sender address"))
      }
    }
    Error(reason) -> Error(map_error(reason))
  }
}

/// Receives data from a connected UDP socket (data only)
///
pub fn recv(sock: Socket, length: Int) -> Result(BitArray, SocketError) {
  case recv_from(sock, length) {
    Ok(datagram) -> Ok(datagram.data)
    Error(err) -> Error(err)
  }
}

/// Receives data from a connected UDP socket with timeout
///
pub fn recv_timeout(
  sock: Socket,
  length: Int,
  timeout_ms: Int,
) -> Result(BitArray, SocketError) {
  case recv_from_timeout(sock, length, timeout_ms) {
    Ok(datagram) -> Ok(datagram.data)
    Error(err) -> Error(err)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Control Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Closes a UDP socket
///
pub fn close(sock: Socket) -> Result(Nil, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))
  Ok(ffi_close(inner))
}

/// Sets the controlling process for the socket
///
pub fn set_controlling_process(
  sock: Socket,
  pid: Pid,
) -> Result(Nil, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case ffi_controlling_process(inner, pid) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> Error(map_error(reason))
  }
}

/// Gets the local address and port of the socket
///
pub fn local_address(sock: Socket) -> Result(SocketAddress, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case ffi_sockname(inner) {
    Ok(#(ip_tuple, port)) -> {
      case decode_ip_tuple(ip_tuple) {
        Ok(ip) -> Ok(socket.IpAddr(ip: ip, port: port))
        Error(Nil) ->
          Error(socket_error.InvalidArgument("Failed to decode local address"))
      }
    }
    Error(reason) -> Error(map_error(reason))
  }
}

/// Gets the port number a socket is bound to
///
pub fn get_port(sock: Socket) -> Result(Int, SocketError) {
  case local_address(sock) {
    Ok(socket.IpAddr(_, port)) -> Ok(port)
    Ok(_) -> Error(socket_error.InvalidArgument("Not an IP socket"))
    Error(err) -> Error(err)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Options Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the socket to the specified active mode
///
pub fn set_active(
  sock: Socket,
  mode: ActiveMode,
) -> Result(Socket, SocketError) {
  let inner = socket.coerce_inner_socket(socket.get_inner(sock))

  case ffi_set_active(inner, mode) {
    Ok(Nil) -> {
      let new_opts =
        socket_options.with_active_mode(socket.get_options(sock), mode)
      Ok(socket.set_socket_options(sock, new_opts))
    }
    Error(reason) -> Error(map_error(reason))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Internal Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Maps Erlang error atoms to SocketError
fn map_error(reason: Atom) -> SocketError {
  let reason_str = atom.to_string(reason)
  socket_error.from_dynamic_reason(reason_str)
}

/// Decodes an Erlang IP address tuple to IpAddress
fn decode_ip_tuple(ip: Dynamic) -> Result(socket_options.IpAddress, Nil) {
  case ffi_decode_ipv4(ip) {
    Ok(#(a, b, c, d)) -> Ok(socket_options.IpV4(a, b, c, d))
    Error(Nil) -> {
      case ffi_decode_ipv6(ip) {
        Ok(#(a, b, c, d, e, f, g, h)) ->
          Ok(socket_options.IpV6(a, b, c, d, e, f, g, h))
        Error(Nil) -> Error(Nil)
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Erlang FFI Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Opens a UDP socket with simplified options
@external(erlang, "aether_udp_ffi", "open_simple")
fn ffi_open(port: Int, reuseaddr: Bool) -> Result(Dynamic, Atom)

/// Connects a UDP socket to a remote address
@external(erlang, "aether_udp_ffi", "connect")
fn ffi_connect(socket: Dynamic, host: String, port: Int) -> Result(Nil, Atom)

/// Sends data on a connected socket
@external(erlang, "aether_udp_ffi", "send")
fn ffi_send(socket: Dynamic, data: BitArray) -> Result(Nil, Atom)

/// Sends data to a specific address
@external(erlang, "aether_udp_ffi", "send_to")
fn ffi_send_to(
  socket: Dynamic,
  host: String,
  port: Int,
  data: BitArray,
) -> Result(Nil, Atom)

/// Receives data (blocking)
@external(erlang, "aether_udp_ffi", "recv")
fn ffi_recv(
  socket: Dynamic,
  length: Int,
) -> Result(#(Dynamic, Int, BitArray), Atom)

/// Receives data with timeout
@external(erlang, "aether_udp_ffi", "recv_timeout")
fn ffi_recv_timeout(
  socket: Dynamic,
  length: Int,
  timeout: Int,
) -> Result(#(Dynamic, Int, BitArray), Atom)

/// Closes a socket
@external(erlang, "aether_udp_ffi", "close")
fn ffi_close(socket: Dynamic) -> Nil

/// Sets the controlling process
@external(erlang, "aether_udp_ffi", "controlling_process")
fn ffi_controlling_process(socket: Dynamic, pid: Pid) -> Result(Nil, Atom)

/// Gets the local address
@external(erlang, "aether_udp_ffi", "sockname")
fn ffi_sockname(socket: Dynamic) -> Result(#(Dynamic, Int), Atom)

/// Sets active mode
@external(erlang, "aether_udp_ffi", "set_active")
fn ffi_set_active(socket: Dynamic, mode: ActiveMode) -> Result(Nil, Atom)

/// Decodes IPv4 tuple
@external(erlang, "aether_udp_ffi", "decode_ipv4_tuple")
fn ffi_decode_ipv4(tuple: Dynamic) -> Result(#(Int, Int, Int, Int), Nil)

/// Decodes IPv6 tuple
@external(erlang, "aether_udp_ffi", "decode_8_tuple")
fn ffi_decode_ipv6(
  tuple: Dynamic,
) -> Result(#(Int, Int, Int, Int, Int, Int, Int, Int), Nil)
