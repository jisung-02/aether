// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Transport Module - Unified Socket Interface
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// This module provides a protocol-agnostic interface for socket operations.
// It abstracts over TCP and UDP transports, allowing code to be written
// once and work with either protocol.
//
// ## Usage
//
// ```gleam
// // Create a transport for TCP client
// let transport = transport.tcp_client("localhost", 8080, socket_options.tcp_defaults())
//
// // Or for UDP
// let transport = transport.udp_client("localhost", 9000, socket_options.udp_defaults())
//
// // Use the same send/recv interface
// case transport.connect(transport) {
//   Ok(connected) -> {
//     let assert Ok(Nil) = transport.send(connected, <<"Hello">>)
//     let assert Ok(data) = transport.recv(connected, 1024)
//   }
//   Error(err) -> handle_error(err)
// }
// ```
//

import aether/network/socket.{
  type ListenSocket, type Socket, type SocketAddress, type SocketMessage,
  type SocketTransport, Tcp, Udp,
}
import aether/network/socket_error.{type SocketError}
import aether/network/socket_options.{type ActiveMode, type SocketOptions}
import aether/network/tcp
import aether/network/udp
import gleam/erlang/process.{type Subject}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Transport configuration for creating connections
///
/// This represents the configuration for a transport before connection.
/// Use `connect` to establish the connection and get a ConnectedTransport.
///
pub type Transport {
  /// TCP client transport configuration
  TcpClient(host: String, port: Int, options: SocketOptions)
  /// TCP server transport configuration
  TcpServer(port: Int, options: SocketOptions)
  /// UDP bound transport configuration
  UdpBound(port: Int, options: SocketOptions)
  /// UDP connected transport configuration
  UdpConnected(host: String, port: Int, options: SocketOptions)
}

/// A connected transport ready for I/O operations
///
/// This wraps an active socket connection, providing a unified
/// interface for send/recv operations across TCP and UDP.
///
pub type ConnectedTransport {
  ConnectedTransport(socket: Socket, protocol: SocketTransport)
}

/// A listening transport ready to accept connections
///
/// This wraps a TCP listen socket or UDP bound socket.
///
pub type ListeningTransport {
  /// TCP listening socket that can accept connections
  TcpListening(listen_socket: ListenSocket)
  /// UDP bound socket ready to receive datagrams
  UdpListening(socket: Socket)
}

/// Result of a receive operation that may include sender info
///
pub type RecvResult {
  /// Data received (TCP or connected UDP)
  DataOnly(data: BitArray)
  /// Data with sender information (UDP)
  DataFrom(data: BitArray, from_ip: socket_options.IpAddress, from_port: Int)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Transport Creation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a TCP client transport configuration
///
/// ## Parameters
///
/// - `host`: The hostname or IP address to connect to
/// - `port`: The port number to connect to
/// - `options`: Socket options for the connection
///
/// ## Returns
///
/// A Transport configuration ready to be connected
///
pub fn tcp_client(host: String, port: Int, options: SocketOptions) -> Transport {
  TcpClient(host: host, port: port, options: options)
}

/// Creates a TCP server transport configuration
///
/// ## Parameters
///
/// - `port`: The port number to listen on
/// - `options`: Socket options for the server
///
/// ## Returns
///
/// A Transport configuration ready to be bound
///
pub fn tcp_server(port: Int, options: SocketOptions) -> Transport {
  TcpServer(port: port, options: options)
}

/// Creates a UDP bound transport configuration
///
/// ## Parameters
///
/// - `port`: The port number to bind to (0 for random)
/// - `options`: Socket options
///
/// ## Returns
///
/// A Transport configuration ready to be bound
///
pub fn udp_bound(port: Int, options: SocketOptions) -> Transport {
  UdpBound(port: port, options: options)
}

/// Creates a UDP connected transport configuration
///
/// ## Parameters
///
/// - `host`: The destination hostname or IP address
/// - `port`: The destination port number
/// - `options`: Socket options
///
/// ## Returns
///
/// A Transport configuration ready to be connected
///
pub fn udp_connected(host: String, port: Int, options: SocketOptions) -> Transport {
  UdpConnected(host: host, port: port, options: options)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Connects a client transport
///
/// For TCP, this establishes a connection to the remote host.
/// For UDP connected, this creates a connected UDP socket.
///
/// ## Parameters
///
/// - `transport`: The transport configuration to connect
///
/// ## Returns
///
/// A ConnectedTransport on success, or a SocketError on failure
///
pub fn connect(transport: Transport) -> Result(ConnectedTransport, SocketError) {
  case transport {
    TcpClient(host, port, options) -> {
      case tcp.connect(host, port, options) {
        Ok(sock) -> Ok(ConnectedTransport(socket: sock, protocol: Tcp))
        Error(err) -> Error(err)
      }
    }
    UdpConnected(host, port, options) -> {
      case udp.connect(host, port, options) {
        Ok(sock) -> Ok(ConnectedTransport(socket: sock, protocol: Udp))
        Error(err) -> Error(err)
      }
    }
    TcpServer(_, _) -> {
      Error(socket_error.InvalidArgument(
        "Use listen() for server transports, not connect()",
      ))
    }
    UdpBound(_, _) -> {
      Error(socket_error.InvalidArgument(
        "Use listen() for bound transports, not connect()",
      ))
    }
  }
}

/// Connects a client transport with a timeout
///
/// ## Parameters
///
/// - `transport`: The transport configuration to connect
/// - `timeout_ms`: Connection timeout in milliseconds
///
/// ## Returns
///
/// A ConnectedTransport on success, or a SocketError on failure
///
pub fn connect_timeout(
  transport: Transport,
  timeout_ms: Int,
) -> Result(ConnectedTransport, SocketError) {
  case transport {
    TcpClient(host, port, options) -> {
      case tcp.connect_timeout(host, port, options, timeout_ms) {
        Ok(sock) -> Ok(ConnectedTransport(socket: sock, protocol: Tcp))
        Error(err) -> Error(err)
      }
    }
    UdpConnected(host, port, options) -> {
      // UDP connect is instant, timeout doesn't apply
      case udp.connect(host, port, options) {
        Ok(sock) -> Ok(ConnectedTransport(socket: sock, protocol: Udp))
        Error(err) -> Error(err)
      }
    }
    TcpServer(_, _) | UdpBound(_, _) -> {
      Error(socket_error.InvalidArgument(
        "Use listen() for server/bound transports",
      ))
    }
  }
}

/// Binds a server transport and starts listening
///
/// For TCP, creates a listening socket.
/// For UDP, creates a bound socket ready to receive.
///
/// ## Parameters
///
/// - `transport`: The server transport configuration
///
/// ## Returns
///
/// A ListeningTransport on success, or a SocketError on failure
///
pub fn listen(transport: Transport) -> Result(ListeningTransport, SocketError) {
  case transport {
    TcpServer(port, options) -> {
      case tcp.listen(port, options) {
        Ok(listen_sock) -> Ok(TcpListening(listen_socket: listen_sock))
        Error(err) -> Error(err)
      }
    }
    UdpBound(port, options) -> {
      case udp.bind(port, options) {
        Ok(sock) -> Ok(UdpListening(socket: sock))
        Error(err) -> Error(err)
      }
    }
    TcpClient(_, _, _) | UdpConnected(_, _, _) -> {
      Error(socket_error.InvalidArgument(
        "Use connect() for client transports, not listen()",
      ))
    }
  }
}

/// Accepts a connection on a listening transport (TCP only)
///
/// ## Parameters
///
/// - `listening`: The listening transport
///
/// ## Returns
///
/// A ConnectedTransport for the new client, or a SocketError on failure
///
pub fn accept(
  listening: ListeningTransport,
) -> Result(ConnectedTransport, SocketError) {
  case listening {
    TcpListening(listen_socket) -> {
      case tcp.accept(listen_socket) {
        Ok(client_sock) ->
          Ok(ConnectedTransport(socket: client_sock, protocol: Tcp))
        Error(err) -> Error(err)
      }
    }
    UdpListening(_) -> {
      Error(socket_error.InvalidArgument(
        "UDP does not support accept(), use recv_from() instead",
      ))
    }
  }
}

/// Accepts a connection with timeout (TCP only)
///
/// ## Parameters
///
/// - `listening`: The listening transport
/// - `timeout_ms`: Accept timeout in milliseconds
///
/// ## Returns
///
/// A ConnectedTransport for the new client, or a SocketError on failure
///
pub fn accept_timeout(
  listening: ListeningTransport,
  timeout_ms: Int,
) -> Result(ConnectedTransport, SocketError) {
  case listening {
    TcpListening(listen_socket) -> {
      case tcp.accept_timeout(listen_socket, timeout_ms) {
        Ok(client_sock) ->
          Ok(ConnectedTransport(socket: client_sock, protocol: Tcp))
        Error(err) -> Error(err)
      }
    }
    UdpListening(_) -> {
      Error(socket_error.InvalidArgument(
        "UDP does not support accept()",
      ))
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// I/O Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sends data over a connected transport
///
/// ## Parameters
///
/// - `transport`: The connected transport
/// - `data`: The data to send
///
/// ## Returns
///
/// Ok(Nil) on success, or a SocketError on failure
///
pub fn send(
  transport: ConnectedTransport,
  data: BitArray,
) -> Result(Nil, SocketError) {
  case transport.protocol {
    Tcp -> tcp.send(transport.socket, data)
    Udp -> udp.send(transport.socket, data)
  }
}

/// Sends data to a specific address (UDP listening transports)
///
/// ## Parameters
///
/// - `listening`: The UDP listening transport
/// - `host`: The destination hostname or IP address
/// - `port`: The destination port number
/// - `data`: The data to send
///
/// ## Returns
///
/// Ok(Nil) on success, or a SocketError on failure
///
pub fn send_to(
  listening: ListeningTransport,
  host: String,
  port: Int,
  data: BitArray,
) -> Result(Nil, SocketError) {
  case listening {
    UdpListening(sock) -> udp.send_to(sock, host, port, data)
    TcpListening(_) ->
      Error(socket_error.InvalidArgument(
        "TCP does not support send_to(), use connected transport send()",
      ))
  }
}

/// Receives data from a connected transport
///
/// ## Parameters
///
/// - `transport`: The connected transport
/// - `length`: Maximum bytes to receive (0 for any available)
///
/// ## Returns
///
/// The received data on success, or a SocketError on failure
///
pub fn recv(
  transport: ConnectedTransport,
  length: Int,
) -> Result(BitArray, SocketError) {
  case transport.protocol {
    Tcp -> tcp.recv(transport.socket, length)
    Udp -> udp.recv(transport.socket, length)
  }
}

/// Receives data from a connected transport with timeout
///
/// ## Parameters
///
/// - `transport`: The connected transport
/// - `length`: Maximum bytes to receive
/// - `timeout_ms`: Receive timeout in milliseconds
///
/// ## Returns
///
/// The received data on success, or a SocketError on failure
///
pub fn recv_timeout(
  transport: ConnectedTransport,
  length: Int,
  timeout_ms: Int,
) -> Result(BitArray, SocketError) {
  case transport.protocol {
    Tcp -> tcp.recv_timeout(transport.socket, length, timeout_ms)
    Udp -> udp.recv_timeout(transport.socket, length, timeout_ms)
  }
}

/// Receives data from a listening transport (with sender info for UDP)
///
/// For TCP, this is not supported (use accept() instead).
/// For UDP, returns data with sender address information.
///
/// ## Parameters
///
/// - `listening`: The listening transport
/// - `length`: Maximum bytes to receive
///
/// ## Returns
///
/// A RecvResult with data and optional sender info
///
pub fn recv_from(
  listening: ListeningTransport,
  length: Int,
) -> Result(RecvResult, SocketError) {
  case listening {
    UdpListening(sock) -> {
      case udp.recv_from(sock, length) {
        Ok(datagram) ->
          Ok(DataFrom(
            data: datagram.data,
            from_ip: datagram.from_ip,
            from_port: datagram.from_port,
          ))
        Error(err) -> Error(err)
      }
    }
    TcpListening(_) ->
      Error(socket_error.InvalidArgument(
        "TCP servers should use accept() to get connected transports",
      ))
  }
}

/// Receives data from a listening transport with timeout
///
/// ## Parameters
///
/// - `listening`: The listening transport
/// - `length`: Maximum bytes to receive
/// - `timeout_ms`: Receive timeout in milliseconds
///
/// ## Returns
///
/// A RecvResult with data and optional sender info
///
pub fn recv_from_timeout(
  listening: ListeningTransport,
  length: Int,
  timeout_ms: Int,
) -> Result(RecvResult, SocketError) {
  case listening {
    UdpListening(sock) -> {
      case udp.recv_from_timeout(sock, length, timeout_ms) {
        Ok(datagram) ->
          Ok(DataFrom(
            data: datagram.data,
            from_ip: datagram.from_ip,
            from_port: datagram.from_port,
          ))
        Error(err) -> Error(err)
      }
    }
    TcpListening(_) ->
      Error(socket_error.InvalidArgument(
        "TCP servers should use accept() to get connected transports",
      ))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Control Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Closes a connected transport
///
/// ## Parameters
///
/// - `transport`: The connected transport to close
///
/// ## Returns
///
/// Ok(Nil) on success, or a SocketError on failure
///
pub fn close(transport: ConnectedTransport) -> Result(Nil, SocketError) {
  case transport.protocol {
    Tcp -> tcp.close(transport.socket)
    Udp -> udp.close(transport.socket)
  }
}

/// Closes a listening transport
///
/// ## Parameters
///
/// - `listening`: The listening transport to close
///
/// ## Returns
///
/// Ok(Nil) on success, or a SocketError on failure
///
pub fn close_listening(listening: ListeningTransport) -> Result(Nil, SocketError) {
  case listening {
    TcpListening(listen_sock) -> tcp.close_listen(listen_sock)
    UdpListening(sock) -> udp.close(sock)
  }
}

/// Gets the underlying socket from a connected transport
///
/// This is useful for protocol-specific operations.
///
/// ## Parameters
///
/// - `transport`: The connected transport
///
/// ## Returns
///
/// The underlying Socket
///
pub fn get_socket(transport: ConnectedTransport) -> Socket {
  transport.socket
}

/// Gets the protocol type of a connected transport
///
/// ## Parameters
///
/// - `transport`: The connected transport
///
/// ## Returns
///
/// The SocketTransport (Tcp or Udp)
///
pub fn get_protocol(transport: ConnectedTransport) -> SocketTransport {
  transport.protocol
}

/// Checks if a transport is TCP
///
pub fn is_tcp(transport: ConnectedTransport) -> Bool {
  transport.protocol == Tcp
}

/// Checks if a transport is UDP
///
pub fn is_udp(transport: ConnectedTransport) -> Bool {
  transport.protocol == Udp
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Active Mode Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the active mode for a connected transport
///
/// ## Parameters
///
/// - `transport`: The connected transport
/// - `mode`: The active mode to set
///
/// ## Returns
///
/// The updated ConnectedTransport on success
///
pub fn set_active(
  transport: ConnectedTransport,
  mode: ActiveMode,
) -> Result(ConnectedTransport, SocketError) {
  case transport.protocol {
    Tcp -> {
      case tcp.set_active(transport.socket, mode) {
        Ok(sock) -> Ok(ConnectedTransport(socket: sock, protocol: Tcp))
        Error(err) -> Error(err)
      }
    }
    Udp -> {
      case udp.set_active(transport.socket, mode) {
        Ok(sock) -> Ok(ConnectedTransport(socket: sock, protocol: Udp))
        Error(err) -> Error(err)
      }
    }
  }
}

/// Associates a Subject with a transport for receiving async messages
///
/// ## Parameters
///
/// - `transport`: The connected transport
/// - `subject`: The Subject to receive SocketMessage
///
/// ## Returns
///
/// The updated ConnectedTransport
///
pub fn with_subject(
  transport: ConnectedTransport,
  subject: Subject(SocketMessage),
) -> ConnectedTransport {
  let new_socket = socket.with_subject(transport.socket, subject)
  ConnectedTransport(socket: new_socket, protocol: transport.protocol)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Address Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the local address of a connected transport
///
/// ## Parameters
///
/// - `transport`: The connected transport
///
/// ## Returns
///
/// The local SocketAddress on success
///
pub fn local_address(
  transport: ConnectedTransport,
) -> Result(SocketAddress, SocketError) {
  case transport.protocol {
    Udp -> udp.local_address(transport.socket)
    Tcp -> {
      // TCP doesn't expose local address easily through glisten
      Error(socket_error.InvalidArgument("TCP local address not available"))
    }
  }
}

/// Gets the remote address of a connected TCP transport
///
/// ## Parameters
///
/// - `transport`: The connected transport
///
/// ## Returns
///
/// The remote SocketAddress on success
///
pub fn peer_address(
  transport: ConnectedTransport,
) -> Result(SocketAddress, SocketError) {
  case transport.protocol {
    Tcp -> tcp.peer_address(transport.socket)
    Udp -> {
      Error(socket_error.InvalidArgument(
        "Use recv_from() to get sender address for UDP",
      ))
    }
  }
}

/// Gets the port a listening transport is bound to
///
/// ## Parameters
///
/// - `listening`: The listening transport
///
/// ## Returns
///
/// The port number on success
///
pub fn get_listening_port(
  listening: ListeningTransport,
) -> Result(Int, SocketError) {
  case listening {
    TcpListening(listen_sock) -> tcp.get_port(listen_sock)
    UdpListening(sock) -> udp.get_port(sock)
  }
}
