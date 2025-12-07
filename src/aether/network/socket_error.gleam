// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Error Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/string
import glisten/socket as glisten_socket

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Comprehensive socket error type
///
/// Maps errors from various socket operations including connection errors,
/// address errors, network errors, and operation errors.
///
/// ## Examples
///
/// ```gleam
/// case tcp.connect("localhost", 8080, options) {
///   Ok(socket) -> handle_socket(socket)
///   Error(ConnectionRefused) -> io.println("Server not running")
///   Error(Timeout) -> io.println("Connection timed out")
///   Error(err) -> io.println("Error: " <> socket_error.to_string(err))
/// }
/// ```
///
pub type SocketError {
  // Connection errors
  /// The remote host actively refused the connection
  ConnectionRefused
  /// The connection was reset by the remote host
  ConnectionReset
  /// The connection was aborted by the network
  ConnectionAborted
  /// The socket has been closed
  ConnectionClosed

  // Address errors
  /// The address is already in use
  AddressInUse
  /// The requested address is not available
  AddressNotAvailable
  /// The address family is not supported
  AddressFamilyNotSupported

  // Network errors
  /// The network is unreachable
  NetworkUnreachable
  /// The destination host is unreachable
  HostUnreachable
  /// The destination host is down
  HostDown
  /// The network is down
  NetworkDown

  // Operation errors
  /// The operation timed out
  Timeout
  /// The operation would block (non-blocking mode)
  WouldBlock
  /// The socket is not connected
  NotConnected
  /// The socket is already connected
  AlreadyConnected
  /// The operation is already in progress
  AlreadyInProgress

  // Resource errors
  /// No buffer space available
  NoBufferSpace
  /// Too many open files
  TooManyOpenFiles

  // Permission errors
  /// Permission denied for the operation
  PermissionDenied

  // Protocol errors
  /// A protocol error occurred
  ProtocolError
  /// The protocol is not supported
  ProtocolNotSupported
  /// The socket type is not supported
  SocketTypeNotSupported

  // Argument errors
  /// Invalid argument provided
  InvalidArgument(message: String)
  /// Bad file descriptor
  BadFileDescriptor

  // Unknown/other error
  /// An unknown error occurred
  Unknown(reason: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Conversion Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a glisten SocketReason to an Aether SocketError
///
/// This function maps the comprehensive POSIX error codes from glisten
/// to Aether's semantic error types.
///
/// ## Parameters
///
/// - `reason`: The glisten SocketReason to convert
///
/// ## Returns
///
/// The corresponding Aether SocketError
///
pub fn from_glisten_reason(reason: glisten_socket.SocketReason) -> SocketError {
  case reason {
    // Connection errors
    glisten_socket.Econnrefused -> ConnectionRefused
    glisten_socket.Econnreset -> ConnectionReset
    glisten_socket.Econnaborted -> ConnectionAborted
    glisten_socket.Closed -> ConnectionClosed

    // Address errors
    glisten_socket.Eaddrinuse -> AddressInUse
    glisten_socket.Eaddrnotavail -> AddressNotAvailable
    glisten_socket.Eafnosupport -> AddressFamilyNotSupported

    // Network errors
    glisten_socket.Enetunreach -> NetworkUnreachable
    glisten_socket.Ehostunreach -> HostUnreachable
    glisten_socket.Ehostdown -> HostDown
    glisten_socket.Enetdown -> NetworkDown

    // Operation errors
    glisten_socket.Timeout -> Timeout
    glisten_socket.Ewouldblock -> WouldBlock
    glisten_socket.Enotconn -> NotConnected
    glisten_socket.Eisconn -> AlreadyConnected
    glisten_socket.Ealready -> AlreadyInProgress
    glisten_socket.Einprogress -> AlreadyInProgress

    // Resource errors
    glisten_socket.Enobufs -> NoBufferSpace
    glisten_socket.Emfile -> TooManyOpenFiles
    glisten_socket.Enfile -> TooManyOpenFiles

    // Permission errors
    glisten_socket.Eacces -> PermissionDenied
    glisten_socket.Eperm -> PermissionDenied

    // Protocol errors
    glisten_socket.Eproto -> ProtocolError
    glisten_socket.Eprotonosupport -> ProtocolNotSupported
    glisten_socket.Esocktnosupport -> SocketTypeNotSupported
    glisten_socket.Eprototype -> ProtocolNotSupported

    // Argument errors
    glisten_socket.Badarg -> InvalidArgument("Bad argument")
    glisten_socket.Einval -> InvalidArgument("Invalid value")
    glisten_socket.Ebadf -> BadFileDescriptor
    glisten_socket.Enotsock -> BadFileDescriptor

    // Terminated/shutdown
    glisten_socket.Terminated -> ConnectionClosed
    glisten_socket.Etimedout -> Timeout

    // Message/data errors
    glisten_socket.Emsgsize -> InvalidArgument("Message too large")
    glisten_socket.Edestaddrreq ->
      InvalidArgument("Destination address required")

    // Other mapped errors
    glisten_socket.Enopkg -> ProtocolNotSupported
    glisten_socket.Enoprotoopt ->
      InvalidArgument("Protocol option not supported")
    glisten_socket.Enotty -> InvalidArgument("Not a terminal")
    glisten_socket.Exbadport -> BadFileDescriptor
    glisten_socket.Exbadseq -> ProtocolError

    // File system errors (less common for sockets)
    glisten_socket.Eagain -> WouldBlock
    glisten_socket.Ebadmsg -> ProtocolError
    glisten_socket.Ebusy -> Unknown("Resource busy")
    glisten_socket.Edeadlk -> Unknown("Deadlock detected")
    glisten_socket.Edeadlock -> Unknown("Deadlock detected")
    glisten_socket.Edquot -> Unknown("Quota exceeded")
    glisten_socket.Eexist -> AddressInUse
    glisten_socket.Efault -> InvalidArgument("Bad address")
    glisten_socket.Efbig -> InvalidArgument("File too large")
    glisten_socket.Eftype -> InvalidArgument("Invalid file type")
    glisten_socket.Eintr -> Unknown("Interrupted system call")
    glisten_socket.Eio -> Unknown("I/O error")
    glisten_socket.Eisdir -> InvalidArgument("Is a directory")
    glisten_socket.Eloop -> InvalidArgument("Too many symbolic links")
    glisten_socket.Emlink -> Unknown("Too many links")
    glisten_socket.Emultihop -> Unknown("Multihop attempted")
    glisten_socket.Enametoolong -> InvalidArgument("Name too long")
    glisten_socket.Enodev -> Unknown("No such device")
    glisten_socket.Enolck -> Unknown("No locks available")
    glisten_socket.Enolink -> Unknown("Link has been severed")
    glisten_socket.Enoent -> Unknown("No such file or directory")
    glisten_socket.Enomem -> NoBufferSpace
    glisten_socket.Enospc -> NoBufferSpace
    glisten_socket.Enosr -> NoBufferSpace
    glisten_socket.Enostr -> InvalidArgument("Not a stream")
    glisten_socket.Enosys -> Unknown("Function not implemented")
    glisten_socket.Enotblk -> InvalidArgument("Not a block device")
    glisten_socket.Enotdir -> InvalidArgument("Not a directory")
    glisten_socket.Enotsup -> Unknown("Operation not supported")
    glisten_socket.Enxio -> Unknown("No such device or address")
    glisten_socket.Eopnotsupp -> Unknown("Operation not supported")
    glisten_socket.Eoverflow -> InvalidArgument("Value too large")
    glisten_socket.Epipe -> ConnectionClosed
    glisten_socket.Erange -> InvalidArgument("Result too large")
    glisten_socket.Erofs -> Unknown("Read-only file system")
    glisten_socket.Espipe -> InvalidArgument("Illegal seek")
    glisten_socket.Esrch -> Unknown("No such process")
    glisten_socket.Estale -> Unknown("Stale file handle")
    glisten_socket.Etxtbsy -> Unknown("Text file busy")
    glisten_socket.Exdev -> Unknown("Cross-device link")
  }
}

/// Converts a SocketError to a human-readable string
///
/// ## Parameters
///
/// - `error`: The socket error to convert
///
/// ## Returns
///
/// A human-readable description of the error
///
pub fn to_string(error: SocketError) -> String {
  case error {
    ConnectionRefused -> "Connection refused"
    ConnectionReset -> "Connection reset by peer"
    ConnectionAborted -> "Connection aborted"
    ConnectionClosed -> "Connection closed"
    AddressInUse -> "Address already in use"
    AddressNotAvailable -> "Address not available"
    AddressFamilyNotSupported -> "Address family not supported"
    NetworkUnreachable -> "Network unreachable"
    HostUnreachable -> "Host unreachable"
    HostDown -> "Host is down"
    NetworkDown -> "Network is down"
    Timeout -> "Operation timed out"
    WouldBlock -> "Operation would block"
    NotConnected -> "Socket is not connected"
    AlreadyConnected -> "Socket is already connected"
    AlreadyInProgress -> "Operation already in progress"
    NoBufferSpace -> "No buffer space available"
    TooManyOpenFiles -> "Too many open files"
    PermissionDenied -> "Permission denied"
    ProtocolError -> "Protocol error"
    ProtocolNotSupported -> "Protocol not supported"
    SocketTypeNotSupported -> "Socket type not supported"
    InvalidArgument(message) -> "Invalid argument: " <> message
    BadFileDescriptor -> "Bad file descriptor"
    Unknown(reason) -> "Unknown error: " <> reason
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Classification Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks if the error indicates the connection is closed
///
/// ## Parameters
///
/// - `error`: The socket error to check
///
/// ## Returns
///
/// True if the error indicates a closed connection
///
pub fn is_closed(error: SocketError) -> Bool {
  case error {
    ConnectionClosed -> True
    ConnectionReset -> True
    ConnectionAborted -> True
    _ -> False
  }
}

/// Checks if the error is retriable
///
/// Retriable errors are those that may succeed if the operation
/// is attempted again, such as timeouts or would-block conditions.
///
/// ## Parameters
///
/// - `error`: The socket error to check
///
/// ## Returns
///
/// True if the operation may succeed on retry
///
pub fn is_retriable(error: SocketError) -> Bool {
  case error {
    Timeout -> True
    WouldBlock -> True
    AlreadyInProgress -> True
    _ -> False
  }
}

/// Checks if the error is related to network connectivity
///
/// ## Parameters
///
/// - `error`: The socket error to check
///
/// ## Returns
///
/// True if the error is a network-related error
///
pub fn is_network_error(error: SocketError) -> Bool {
  case error {
    NetworkUnreachable -> True
    HostUnreachable -> True
    HostDown -> True
    NetworkDown -> True
    ConnectionRefused -> True
    _ -> False
  }
}

/// Checks if the error is related to address/binding issues
///
/// ## Parameters
///
/// - `error`: The socket error to check
///
/// ## Returns
///
/// True if the error is an address-related error
///
pub fn is_address_error(error: SocketError) -> Bool {
  case error {
    AddressInUse -> True
    AddressNotAvailable -> True
    AddressFamilyNotSupported -> True
    _ -> False
  }
}

/// Checks if the error is a permission/access error
///
/// ## Parameters
///
/// - `error`: The socket error to check
///
/// ## Returns
///
/// True if the error is a permission-related error
///
pub fn is_permission_error(error: SocketError) -> Bool {
  case error {
    PermissionDenied -> True
    _ -> False
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Creation Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates an InvalidArgument error with a message
///
pub fn invalid_argument(message: String) -> SocketError {
  InvalidArgument(message)
}

/// Creates an Unknown error with a reason
///
pub fn unknown(reason: String) -> SocketError {
  Unknown(reason)
}

/// Converts a dynamic error reason to a SocketError
///
/// This is useful when handling errors from Erlang FFI that
/// return dynamic error values.
///
pub fn from_dynamic_reason(reason: String) -> SocketError {
  case string.lowercase(reason) {
    "closed" -> ConnectionClosed
    "timeout" -> Timeout
    "econnrefused" -> ConnectionRefused
    "econnreset" -> ConnectionReset
    "eaddrinuse" -> AddressInUse
    "enotconn" -> NotConnected
    "eagain" -> WouldBlock
    "ewouldblock" -> WouldBlock
    other -> Unknown(other)
  }
}
