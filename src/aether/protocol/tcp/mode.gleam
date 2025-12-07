// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Mode Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides mode switching between OS socket (production) and
// custom TCP (learning/testing) implementations.
//

import aether/core/data.{type Data}
import aether/core/message
import aether/network/socket.{type Socket}
import aether/network/socket_error
import aether/network/tcp
import aether/pipeline/error.{ProcessingError}
import aether/pipeline/stage.{type Stage}
import aether/protocol/tcp/stage as tcp_stage
import gleam/option

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// TCP operation modes
///
/// Determines whether to use the OS TCP stack or custom TCP
/// implementation for processing.
///
/// ## Variants
///
/// - `OsSocket`: Use the OS TCP stack (production mode)
///   - Fast and reliable
///   - Uses kernel-level TCP implementation
///   - No access to raw TCP headers
///
/// - `CustomTcp`: Use custom TCP implementation (learning/testing mode)
///   - Parses and builds TCP headers
///   - Allows inspection and modification of TCP state
///   - Useful for protocol learning and debugging
///
pub type TcpMode {
  OsSocket
  CustomTcp
}

/// Configuration for socket-based stages
///
pub type SocketConfig {
  SocketConfig(
    /// Buffer size for read operations (default: 8192)
    buffer_size: Int,
    /// Timeout for read operations in milliseconds (default: 5000)
    read_timeout: Int,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Configuration Constructors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates default socket configuration
///
/// ## Returns
///
/// A SocketConfig with default values:
/// - buffer_size: 8192 bytes
/// - read_timeout: 5000 ms
///
pub fn default_config() -> SocketConfig {
  SocketConfig(buffer_size: 8192, read_timeout: 5000)
}

/// Creates socket configuration with custom buffer size
///
pub fn with_buffer_size(config: SocketConfig, size: Int) -> SocketConfig {
  SocketConfig(..config, buffer_size: size)
}

/// Creates socket configuration with custom read timeout
///
pub fn with_read_timeout(config: SocketConfig, timeout_ms: Int) -> SocketConfig {
  SocketConfig(..config, read_timeout: timeout_ms)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// OS Socket Stages
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates an OS socket read stage
///
/// This stage reads data from an OS-managed TCP socket. It uses the
/// kernel TCP stack, so TCP headers are already processed.
///
/// ## Parameters
///
/// - `sock`: The connected TCP socket
/// - `config`: Socket configuration
///
/// ## Returns
///
/// A Stage that reads from the socket and updates Data bytes
///
/// ## Examples
///
/// ```gleam
/// let read_stage = os_socket_read(client_socket, default_config())
///
/// case stage.execute(read_stage, data.new(<<>>)) {
///   Ok(received) -> {
///     // received.bytes contains data from socket
///   }
///   Error(err) -> // handle socket error
/// }
/// ```
///
pub fn os_socket_read(sock: Socket, config: SocketConfig) -> Stage(Data, Data) {
  stage.new("os:tcp:read", fn(data: Data) {
    case tcp.recv_timeout(sock, config.buffer_size, config.read_timeout) {
      Ok(bytes) -> {
        data
        |> message.set_bytes(bytes)
        |> Ok
      }
      Error(socket_error) -> {
        Error(ProcessingError(
          "Socket read error: " <> socket_error_to_string(socket_error),
          option.None,
        ))
      }
    }
  })
}

/// Creates an OS socket read stage with default configuration
///
pub fn os_socket_read_default(sock: Socket) -> Stage(Data, Data) {
  os_socket_read(sock, default_config())
}

/// Creates an OS socket write stage
///
/// This stage writes data to an OS-managed TCP socket. It uses the
/// kernel TCP stack for reliable delivery.
///
/// ## Parameters
///
/// - `sock`: The connected TCP socket
///
/// ## Returns
///
/// A Stage that writes Data bytes to the socket
///
/// ## Examples
///
/// ```gleam
/// let write_stage = os_socket_write(client_socket)
/// let response = data.new(<<"HTTP/1.1 200 OK\r\n":utf8>>)
///
/// case stage.execute(write_stage, response) {
///   Ok(_) -> // data sent successfully
///   Error(err) -> // handle socket error
/// }
/// ```
///
pub fn os_socket_write(sock: Socket) -> Stage(Data, Data) {
  stage.new("os:tcp:write", fn(data: Data) {
    case tcp.send(sock, message.bytes(data)) {
      Ok(Nil) -> Ok(data)
      Error(socket_error) -> {
        Error(ProcessingError(
          "Socket write error: " <> socket_error_to_string(socket_error),
          option.None,
        ))
      }
    }
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Custom TCP Stages
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a raw socket read stage for custom TCP processing
///
/// This stage reads raw data from a socket configured for raw TCP
/// processing. Unlike OS socket read, this expects to receive data
/// that includes TCP headers.
///
/// Note: For true raw socket access, the underlying socket must be
/// configured with appropriate options. This stage is primarily for
/// learning and testing purposes.
///
/// ## Parameters
///
/// - `sock`: The socket for raw data reading
/// - `config`: Socket configuration
///
/// ## Returns
///
/// A Stage that reads raw TCP data including headers
///
pub fn raw_socket_read(sock: Socket, config: SocketConfig) -> Stage(Data, Data) {
  stage.new("raw:tcp:read", fn(data: Data) {
    case tcp.recv_timeout(sock, config.buffer_size, config.read_timeout) {
      Ok(bytes) -> {
        data
        |> message.set_bytes(bytes)
        |> Ok
      }
      Error(socket_error) -> {
        Error(ProcessingError(
          "Raw socket read error: " <> socket_error_to_string(socket_error),
          option.None,
        ))
      }
    }
  })
}

/// Creates a raw socket write stage for custom TCP processing
///
/// This stage writes raw TCP segment data including headers to a socket.
///
/// ## Parameters
///
/// - `sock`: The socket for raw data writing
///
/// ## Returns
///
/// A Stage that writes raw TCP data including headers
///
pub fn raw_socket_write(sock: Socket) -> Stage(Data, Data) {
  stage.new("raw:tcp:write", fn(data: Data) {
    case tcp.send(sock, message.bytes(data)) {
      Ok(Nil) -> Ok(data)
      Error(socket_error) -> {
        Error(ProcessingError(
          "Raw socket write error: " <> socket_error_to_string(socket_error),
          option.None,
        ))
      }
    }
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Lists for Pipeline Building
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Returns stages for OS socket inbound processing
///
/// These stages are used when receiving data from an OS-managed TCP socket.
///
/// ## Parameters
///
/// - `sock`: The connected TCP socket
/// - `config`: Socket configuration
///
/// ## Returns
///
/// A list of stages for inbound processing: [read]
///
pub fn os_inbound_stages(
  sock: Socket,
  config: SocketConfig,
) -> List(Stage(Data, Data)) {
  [os_socket_read(sock, config)]
}

/// Returns stages for OS socket outbound processing
///
/// These stages are used when sending data to an OS-managed TCP socket.
///
/// ## Parameters
///
/// - `sock`: The connected TCP socket
///
/// ## Returns
///
/// A list of stages for outbound processing: [write]
///
pub fn os_outbound_stages(sock: Socket) -> List(Stage(Data, Data)) {
  [os_socket_write(sock)]
}

/// Returns stages for custom TCP inbound processing
///
/// These stages are used when receiving and parsing raw TCP data.
/// The decode stage extracts the payload and stores the full segment
/// in metadata.
///
/// ## Parameters
///
/// - `sock`: The socket for raw data
/// - `config`: Socket configuration
///
/// ## Returns
///
/// A list of stages for inbound processing: [raw_read, tcp_decode]
///
pub fn custom_inbound_stages(
  sock: Socket,
  config: SocketConfig,
) -> List(Stage(Data, Data)) {
  [raw_socket_read(sock, config), tcp_stage.decode()]
}

/// Returns stages for custom TCP outbound processing
///
/// These stages are used when encoding and sending raw TCP data.
/// The encode stage builds the full TCP segment from payload and
/// stored header information.
///
/// ## Parameters
///
/// - `sock`: The socket for raw data
///
/// ## Returns
///
/// A list of stages for outbound processing: [tcp_encode, raw_write]
///
pub fn custom_outbound_stages(sock: Socket) -> List(Stage(Data, Data)) {
  [tcp_stage.encode(), raw_socket_write(sock)]
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Mode Selection Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Returns inbound stages based on the selected mode
///
/// ## Parameters
///
/// - `mode`: The TCP mode to use
/// - `sock`: The socket for data transfer
/// - `config`: Socket configuration
///
/// ## Returns
///
/// A list of stages appropriate for the selected mode
///
pub fn inbound_stages_for_mode(
  mode: TcpMode,
  sock: Socket,
  config: SocketConfig,
) -> List(Stage(Data, Data)) {
  case mode {
    OsSocket -> os_inbound_stages(sock, config)
    CustomTcp -> custom_inbound_stages(sock, config)
  }
}

/// Returns outbound stages based on the selected mode
///
/// ## Parameters
///
/// - `mode`: The TCP mode to use
/// - `sock`: The socket for data transfer
///
/// ## Returns
///
/// A list of stages appropriate for the selected mode
///
pub fn outbound_stages_for_mode(
  mode: TcpMode,
  sock: Socket,
) -> List(Stage(Data, Data)) {
  case mode {
    OsSocket -> os_outbound_stages(sock)
    CustomTcp -> custom_outbound_stages(sock)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Hybrid Mode Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a hybrid read stage that uses OS socket but decodes TCP headers
///
/// This is useful when you want to inspect TCP headers for logging or
/// debugging while still using the OS TCP stack for transport.
///
/// Note: This assumes the input data already contains TCP segment bytes,
/// which is useful for testing or when receiving from a custom source.
///
/// ## Parameters
///
/// - `sock`: The connected TCP socket
/// - `config`: Socket configuration
///
/// ## Returns
///
/// A list of stages: [os_read, tcp_decode]
///
pub fn hybrid_read_stages(
  sock: Socket,
  config: SocketConfig,
) -> List(Stage(Data, Data)) {
  [os_socket_read(sock, config), tcp_stage.decode()]
}

/// Creates a stage that logs TCP segment information
///
/// This stage reads TCP segment from metadata and can be used
/// for debugging or monitoring purposes. It passes through data
/// unchanged.
///
/// ## Returns
///
/// A Stage that inspects TCP segment metadata without modifying data
///
pub fn tcp_inspect_stage() -> Stage(Data, Data) {
  stage.new("tcp:inspect", fn(data: Data) {
    // Simply pass through, inspection can be done by caller
    // using tcp_stage.get_segment()
    Ok(data)
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts socket error to string (simplified)
///
fn socket_error_to_string(error: socket_error.SocketError) -> String {
  socket_error.to_string(error)
}

/// Returns a description of the TCP mode
///
pub fn mode_description(mode: TcpMode) -> String {
  case mode {
    OsSocket -> "OS Socket (production mode using kernel TCP stack)"
    CustomTcp -> "Custom TCP (learning mode with header parsing)"
  }
}
