// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP State Machine Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/tcp/header.{type TcpHeader}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// TCP connection states as defined in RFC 793
///
/// The TCP state machine defines 11 states that a connection can be in.
/// State transitions are triggered by receiving TCP segments or by
/// application-layer requests.
///
pub type TcpState {
  /// No connection exists
  Closed
  /// Waiting for connection request from remote TCP
  Listen
  /// Waiting for matching connection request after having sent one
  SynSent
  /// Waiting for confirming connection request acknowledgment
  SynReceived
  /// Connection is open, data transfer is possible
  Established
  /// Waiting for connection termination request from remote TCP
  FinWait1
  /// Waiting for connection termination request from remote TCP
  FinWait2
  /// Waiting for connection termination request from local user
  CloseWait
  /// Waiting for connection termination request acknowledgment
  Closing
  /// Waiting for acknowledgment of connection termination request
  LastAck
  /// Waiting for enough time to ensure remote TCP received acknowledgment
  TimeWait
}

/// TCP connection control block
///
/// Contains all the state information for a TCP connection including
/// sequence numbers, window sizes, and port numbers.
///
pub type TcpConnection {
  TcpConnection(
    /// Current state of the connection
    state: TcpState,
    /// Local port number
    local_port: Int,
    /// Remote port number
    remote_port: Int,
    /// Next sequence number to send (SND.NXT)
    local_seq: Int,
    /// Next expected sequence number to receive (RCV.NXT)
    remote_seq: Int,
    /// Initial sequence number sent (ISS)
    initial_local_seq: Int,
    /// Initial sequence number received (IRS)
    initial_remote_seq: Int,
    /// Local receive window size (RCV.WND)
    local_window: Int,
    /// Remote receive window size (SND.WND)
    remote_window: Int,
    /// Oldest unacknowledged sequence number (SND.UNA)
    unacked_seq: Int,
  )
}

/// Errors that can occur during state transitions
///
pub type StateError {
  /// The operation is not valid in the current state
  InvalidStateTransition(current_state: TcpState, message: String)
  /// The acknowledgment number is invalid
  InvalidAckNumber(expected: Int, actual: Int)
  /// The sequence number is out of window
  SequenceOutOfWindow(seq: Int, window_start: Int, window_end: Int)
  /// RST received
  ConnectionReset
  /// Connection timed out
  ConnectionTimeout
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new connection in Listen state (server)
///
/// This is used when a server wants to accept incoming connections
/// on a specific port.
///
/// ## Parameters
///
/// - `local_port`: The port to listen on
///
/// ## Returns
///
/// A TcpConnection in the Listen state
///
/// ## Examples
///
/// ```gleam
/// let server = new_listener(8080)
/// server.state  // Listen
/// ```
///
pub fn new_listener(local_port: Int) -> TcpConnection {
  TcpConnection(
    state: Listen,
    local_port: local_port,
    remote_port: 0,
    local_seq: generate_initial_seq(),
    remote_seq: 0,
    initial_local_seq: 0,
    initial_remote_seq: 0,
    local_window: 65_535,
    remote_window: 0,
    unacked_seq: 0,
  )
}

/// Creates a new connection for active open (client)
///
/// This is used when a client wants to initiate a connection
/// to a remote server.
///
/// ## Parameters
///
/// - `local_port`: The local port to use
/// - `remote_port`: The remote port to connect to
///
/// ## Returns
///
/// A TcpConnection in the Closed state, ready for active open
///
pub fn new_client(local_port: Int, remote_port: Int) -> TcpConnection {
  let iss = generate_initial_seq()
  TcpConnection(
    state: Closed,
    local_port: local_port,
    remote_port: remote_port,
    local_seq: iss,
    remote_seq: 0,
    initial_local_seq: iss,
    initial_remote_seq: 0,
    local_window: 65_535,
    remote_window: 0,
    unacked_seq: iss,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Active Open (Client) Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Initiates an active open (sends SYN)
///
/// Transitions from Closed to SynSent state.
///
/// ## Parameters
///
/// - `conn`: The connection to initiate
///
/// ## Returns
///
/// The updated connection in SynSent state
///
pub fn initiate_connection(
  conn: TcpConnection,
) -> Result(TcpConnection, StateError) {
  case conn.state {
    Closed -> {
      Ok(TcpConnection(..conn, state: SynSent, local_seq: conn.local_seq + 1))
    }
    _ ->
      Error(InvalidStateTransition(
        current_state: conn.state,
        message: "Can only initiate connection from Closed state",
      ))
  }
}

/// Handles SYN-ACK response (client side)
///
/// Transitions from SynSent to Established state.
///
/// ## Parameters
///
/// - `conn`: The connection
/// - `remote_seq`: The sequence number from the SYN-ACK
/// - `ack_num`: The acknowledgment number from the SYN-ACK
/// - `remote_window`: The window size from the SYN-ACK
///
/// ## Returns
///
/// The updated connection in Established state
///
pub fn handle_syn_ack(
  conn: TcpConnection,
  remote_seq: Int,
  ack_num: Int,
  remote_window: Int,
) -> Result(TcpConnection, StateError) {
  case conn.state {
    SynSent -> {
      // Verify ACK acknowledges our SYN
      case ack_num == conn.initial_local_seq + 1 {
        True ->
          Ok(
            TcpConnection(
              ..conn,
              state: Established,
              remote_port: conn.remote_port,
              remote_seq: remote_seq + 1,
              initial_remote_seq: remote_seq,
              remote_window: remote_window,
              unacked_seq: ack_num,
            ),
          )
        False ->
          Error(InvalidAckNumber(
            expected: conn.initial_local_seq + 1,
            actual: ack_num,
          ))
      }
    }
    _ ->
      Error(InvalidStateTransition(
        current_state: conn.state,
        message: "Can only handle SYN-ACK in SynSent state",
      ))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Passive Open (Server) Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Handles incoming SYN packet (server side)
///
/// Transitions from Listen to SynReceived state.
///
/// ## Parameters
///
/// - `conn`: The listening connection
/// - `remote_port`: The source port of the SYN sender
/// - `remote_seq`: The sequence number from the SYN
/// - `remote_window`: The window size from the SYN
///
/// ## Returns
///
/// The updated connection in SynReceived state
///
/// ## Examples
///
/// ```gleam
/// let server = new_listener(8080)
/// let assert Ok(server) = handle_syn(server, 12345, 1000, 65535)
/// server.state  // SynReceived
/// ```
///
pub fn handle_syn(
  conn: TcpConnection,
  remote_port: Int,
  remote_seq: Int,
  remote_window: Int,
) -> Result(TcpConnection, StateError) {
  case conn.state {
    Listen -> {
      let iss = conn.local_seq
      Ok(
        TcpConnection(
          ..conn,
          state: SynReceived,
          remote_port: remote_port,
          remote_seq: remote_seq + 1,
          initial_local_seq: iss,
          initial_remote_seq: remote_seq,
          remote_window: remote_window,
          local_seq: iss + 1,
          unacked_seq: iss,
        ),
      )
    }
    _ ->
      Error(InvalidStateTransition(
        current_state: conn.state,
        message: "Cannot handle SYN in state: " <> state_name(conn.state),
      ))
  }
}

/// Handles ACK packet completing the handshake (server side)
///
/// Transitions from SynReceived to Established state.
///
/// ## Parameters
///
/// - `conn`: The connection in SynReceived state
/// - `ack_num`: The acknowledgment number from the ACK
///
/// ## Returns
///
/// The updated connection in Established state
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(server) = handle_ack(server, server.local_seq)
/// server.state  // Established
/// ```
///
pub fn handle_ack(
  conn: TcpConnection,
  ack_num: Int,
) -> Result(TcpConnection, StateError) {
  case conn.state {
    SynReceived -> {
      // ACK should acknowledge our SYN-ACK
      case ack_num == conn.initial_local_seq + 1 {
        True ->
          Ok(TcpConnection(..conn, state: Established, unacked_seq: ack_num))
        False ->
          Error(InvalidAckNumber(
            expected: conn.initial_local_seq + 1,
            actual: ack_num,
          ))
      }
    }
    Established -> {
      // In established state, update unacked sequence
      Ok(TcpConnection(..conn, unacked_seq: ack_num))
    }
    FinWait1 -> {
      // ACK of our FIN
      case ack_num == conn.local_seq {
        True -> Ok(TcpConnection(..conn, state: FinWait2, unacked_seq: ack_num))
        False -> Ok(TcpConnection(..conn, unacked_seq: ack_num))
      }
    }
    Closing -> {
      // ACK of our FIN in simultaneous close
      case ack_num == conn.local_seq {
        True -> Ok(TcpConnection(..conn, state: TimeWait, unacked_seq: ack_num))
        False ->
          Error(InvalidAckNumber(expected: conn.local_seq, actual: ack_num))
      }
    }
    LastAck -> {
      // Final ACK in passive close
      case ack_num == conn.local_seq {
        True -> Ok(TcpConnection(..conn, state: Closed, unacked_seq: ack_num))
        False ->
          Error(InvalidAckNumber(expected: conn.local_seq, actual: ack_num))
      }
    }
    _ ->
      Error(InvalidStateTransition(
        current_state: conn.state,
        message: "Cannot handle ACK in state: " <> state_name(conn.state),
      ))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Termination Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Handles FIN packet
///
/// Handles connection termination initiated by the remote peer.
///
/// ## Parameters
///
/// - `conn`: The connection
///
/// ## Returns
///
/// The updated connection in the appropriate closing state
///
pub fn handle_fin(conn: TcpConnection) -> Result(TcpConnection, StateError) {
  case conn.state {
    Established ->
      Ok(
        TcpConnection(..conn, state: CloseWait, remote_seq: conn.remote_seq + 1),
      )
    FinWait1 ->
      // Simultaneous close
      Ok(TcpConnection(..conn, state: Closing, remote_seq: conn.remote_seq + 1))
    FinWait2 ->
      Ok(
        TcpConnection(..conn, state: TimeWait, remote_seq: conn.remote_seq + 1),
      )
    _ ->
      Error(InvalidStateTransition(
        current_state: conn.state,
        message: "Cannot handle FIN in state: " <> state_name(conn.state),
      ))
  }
}

/// Initiates connection close (sends FIN)
///
/// Called when the local application wants to close the connection.
///
/// ## Parameters
///
/// - `conn`: The connection to close
///
/// ## Returns
///
/// The updated connection in the appropriate closing state
///
pub fn close_connection(
  conn: TcpConnection,
) -> Result(TcpConnection, StateError) {
  case conn.state {
    Established ->
      Ok(TcpConnection(..conn, state: FinWait1, local_seq: conn.local_seq + 1))
    CloseWait ->
      Ok(TcpConnection(..conn, state: LastAck, local_seq: conn.local_seq + 1))
    _ ->
      Error(InvalidStateTransition(
        current_state: conn.state,
        message: "Cannot close connection in state: " <> state_name(conn.state),
      ))
  }
}

/// Handles RST packet
///
/// RST immediately terminates the connection regardless of state.
///
/// ## Parameters
///
/// - `conn`: The connection
///
/// ## Returns
///
/// The connection in Closed state or an error
///
pub fn handle_rst(conn: TcpConnection) -> Result(TcpConnection, StateError) {
  case conn.state {
    Closed -> Error(ConnectionReset)
    Listen -> Ok(conn)
    _ -> Ok(TcpConnection(..conn, state: Closed))
  }
}

/// Transitions from TimeWait to Closed after timeout
///
/// After 2*MSL (Maximum Segment Lifetime), the connection can be closed.
///
/// ## Parameters
///
/// - `conn`: The connection in TimeWait state
///
/// ## Returns
///
/// The connection in Closed state
///
pub fn time_wait_expired(
  conn: TcpConnection,
) -> Result(TcpConnection, StateError) {
  case conn.state {
    TimeWait -> Ok(TcpConnection(..conn, state: Closed))
    _ ->
      Error(InvalidStateTransition(
        current_state: conn.state,
        message: "TimeWait expiry only valid in TimeWait state",
      ))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Data Transfer Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Updates connection state after sending data
///
/// ## Parameters
///
/// - `conn`: The connection
/// - `data_length`: The length of data sent
///
/// ## Returns
///
/// The updated connection with incremented sequence number
///
pub fn data_sent(
  conn: TcpConnection,
  data_length: Int,
) -> Result(TcpConnection, StateError) {
  case conn.state {
    Established ->
      Ok(TcpConnection(..conn, local_seq: conn.local_seq + data_length))
    _ ->
      Error(InvalidStateTransition(
        current_state: conn.state,
        message: "Cannot send data in state: " <> state_name(conn.state),
      ))
  }
}

/// Updates connection state after receiving data
///
/// ## Parameters
///
/// - `conn`: The connection
/// - `data_length`: The length of data received
///
/// ## Returns
///
/// The updated connection with incremented acknowledgment number
///
pub fn data_received(
  conn: TcpConnection,
  data_length: Int,
) -> Result(TcpConnection, StateError) {
  case conn.state {
    Established ->
      Ok(TcpConnection(..conn, remote_seq: conn.remote_seq + data_length))
    _ ->
      Error(InvalidStateTransition(
        current_state: conn.state,
        message: "Cannot receive data in state: " <> state_name(conn.state),
      ))
  }
}

/// Updates the remote window size
///
pub fn update_remote_window(conn: TcpConnection, window: Int) -> TcpConnection {
  TcpConnection(..conn, remote_window: window)
}

/// Updates the local window size
///
pub fn update_local_window(conn: TcpConnection, window: Int) -> TcpConnection {
  TcpConnection(..conn, local_window: window)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Processing Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Processes an incoming TCP header and updates connection state
///
/// This is a convenience function that dispatches to the appropriate
/// handler based on the flags in the header.
///
/// ## Parameters
///
/// - `conn`: The connection
/// - `hdr`: The received TCP header
///
/// ## Returns
///
/// The updated connection state
///
pub fn process_header(
  conn: TcpConnection,
  hdr: TcpHeader,
) -> Result(TcpConnection, StateError) {
  case header.is_rst(hdr) {
    True -> handle_rst(conn)
    False -> {
      case header.is_syn(hdr) && header.is_ack(hdr) {
        True ->
          handle_syn_ack(
            conn,
            hdr.sequence_number,
            hdr.acknowledgment_number,
            hdr.window_size,
          )
        False -> {
          case header.is_syn(hdr) {
            True ->
              handle_syn(
                conn,
                hdr.source_port,
                hdr.sequence_number,
                hdr.window_size,
              )
            False -> {
              case header.is_fin(hdr) {
                True -> {
                  // First handle ACK if present
                  let conn_after_ack = case header.is_ack(hdr) {
                    True ->
                      case handle_ack(conn, hdr.acknowledgment_number) {
                        Ok(c) -> c
                        Error(_) -> conn
                      }
                    False -> conn
                  }
                  handle_fin(conn_after_ack)
                }
                False -> {
                  case header.is_ack(hdr) {
                    True -> handle_ack(conn, hdr.acknowledgment_number)
                    False ->
                      Error(InvalidStateTransition(
                        current_state: conn.state,
                        message: "Unexpected packet with no recognizable flags",
                      ))
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a TcpState to a human-readable string
///
pub fn state_name(state: TcpState) -> String {
  case state {
    Closed -> "Closed"
    Listen -> "Listen"
    SynSent -> "SynSent"
    SynReceived -> "SynReceived"
    Established -> "Established"
    FinWait1 -> "FinWait1"
    FinWait2 -> "FinWait2"
    CloseWait -> "CloseWait"
    Closing -> "Closing"
    LastAck -> "LastAck"
    TimeWait -> "TimeWait"
  }
}

/// Checks if the connection is in a state that can send data
///
pub fn can_send_data(conn: TcpConnection) -> Bool {
  case conn.state {
    Established -> True
    CloseWait -> True
    _ -> False
  }
}

/// Checks if the connection is in a state that can receive data
///
pub fn can_receive_data(conn: TcpConnection) -> Bool {
  case conn.state {
    Established -> True
    FinWait1 -> True
    FinWait2 -> True
    _ -> False
  }
}

/// Generates an initial sequence number
///
/// Uses a random 32-bit value as specified in RFC 793.
///
fn generate_initial_seq() -> Int {
  random_int(4_294_967_295)
}

/// Converts a StateError to a human-readable string
///
pub fn error_to_string(error: StateError) -> String {
  case error {
    InvalidStateTransition(state, message) ->
      "Invalid state transition in " <> state_name(state) <> ": " <> message
    InvalidAckNumber(expected, actual) ->
      "Invalid ACK number: expected "
      <> int_to_string(expected)
      <> ", got "
      <> int_to_string(actual)
    SequenceOutOfWindow(seq, start, end) ->
      "Sequence "
      <> int_to_string(seq)
      <> " out of window ["
      <> int_to_string(start)
      <> ", "
      <> int_to_string(end)
      <> "]"
    ConnectionReset -> "Connection reset by peer"
    ConnectionTimeout -> "Connection timed out"
  }
}

@external(erlang, "rand", "uniform")
fn random_int(max: Int) -> Int

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(i: Int) -> String
