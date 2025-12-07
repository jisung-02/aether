// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Header Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/option.{type Option}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// TCP header structure (20 bytes minimum)
///
/// The TCP header contains all the control information needed for
/// reliable, ordered data transmission. This structure represents
/// the parsed form of a TCP header.
///
/// ## Fields
///
/// - `source_port`: 16-bit source port number
/// - `destination_port`: 16-bit destination port number
/// - `sequence_number`: 32-bit sequence number
/// - `acknowledgment_number`: 32-bit acknowledgment number
/// - `data_offset`: 4-bit data offset (header length in 32-bit words)
/// - `flags`: TCP control flags
/// - `window_size`: 16-bit receive window size
/// - `checksum`: 16-bit checksum
/// - `urgent_pointer`: 16-bit urgent pointer
/// - `options`: Variable length options (if data_offset > 5)
///
pub type TcpHeader {
  TcpHeader(
    source_port: Int,
    destination_port: Int,
    sequence_number: Int,
    acknowledgment_number: Int,
    data_offset: Int,
    flags: TcpFlags,
    window_size: Int,
    checksum: Int,
    urgent_pointer: Int,
    options: Option(BitArray),
  )
}

/// TCP control flags
///
/// These flags control the behavior of TCP connections and are used
/// for connection establishment, data transfer, and connection termination.
///
/// ## Flag Descriptions
///
/// - `ns`: ECN-nonce concealment protection
/// - `cwr`: Congestion Window Reduced
/// - `ece`: ECN-Echo
/// - `urg`: Urgent pointer field is significant
/// - `ack`: Acknowledgment field is significant
/// - `psh`: Push function - asks to push the buffered data
/// - `rst`: Reset the connection
/// - `syn`: Synchronize sequence numbers
/// - `fin`: No more data from sender
///
pub type TcpFlags {
  TcpFlags(
    ns: Bool,
    cwr: Bool,
    ece: Bool,
    urg: Bool,
    ack: Bool,
    psh: Bool,
    rst: Bool,
    syn: Bool,
    fin: Bool,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flag Constructors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates default flags with all values set to False
///
/// ## Returns
///
/// A TcpFlags instance with all flags disabled
///
/// ## Examples
///
/// ```gleam
/// let flags = default_flags()
/// // All flags are False
/// ```
///
pub fn default_flags() -> TcpFlags {
  TcpFlags(
    ns: False,
    cwr: False,
    ece: False,
    urg: False,
    ack: False,
    psh: False,
    rst: False,
    syn: False,
    fin: False,
  )
}

/// Creates SYN flag for initiating a connection
///
/// Used by the client to initiate a TCP connection (first step of 3-way handshake).
///
/// ## Returns
///
/// A TcpFlags instance with only the SYN flag set
///
/// ## Examples
///
/// ```gleam
/// let flags = syn_flags()
/// flags.syn  // True
/// flags.ack  // False
/// ```
///
pub fn syn_flags() -> TcpFlags {
  TcpFlags(..default_flags(), syn: True)
}

/// Creates SYN-ACK flags for connection acknowledgment
///
/// Used by the server to acknowledge a SYN and synchronize (second step of 3-way handshake).
///
/// ## Returns
///
/// A TcpFlags instance with SYN and ACK flags set
///
/// ## Examples
///
/// ```gleam
/// let flags = syn_ack_flags()
/// flags.syn  // True
/// flags.ack  // True
/// ```
///
pub fn syn_ack_flags() -> TcpFlags {
  TcpFlags(..default_flags(), syn: True, ack: True)
}

/// Creates ACK flag for acknowledgment
///
/// Used to acknowledge received data or complete connection establishment
/// (third step of 3-way handshake).
///
/// ## Returns
///
/// A TcpFlags instance with only the ACK flag set
///
/// ## Examples
///
/// ```gleam
/// let flags = ack_flags()
/// flags.ack  // True
/// flags.syn  // False
/// ```
///
pub fn ack_flags() -> TcpFlags {
  TcpFlags(..default_flags(), ack: True)
}

/// Creates FIN-ACK flags for connection termination
///
/// Used to gracefully close a TCP connection.
///
/// ## Returns
///
/// A TcpFlags instance with FIN and ACK flags set
///
/// ## Examples
///
/// ```gleam
/// let flags = fin_ack_flags()
/// flags.fin  // True
/// flags.ack  // True
/// ```
///
pub fn fin_ack_flags() -> TcpFlags {
  TcpFlags(..default_flags(), fin: True, ack: True)
}

/// Creates FIN flag for initiating connection termination
///
/// Used to signal that the sender has finished sending data.
///
/// ## Returns
///
/// A TcpFlags instance with only the FIN flag set
///
pub fn fin_flags() -> TcpFlags {
  TcpFlags(..default_flags(), fin: True)
}

/// Creates RST flag for connection reset
///
/// Used to abort a connection immediately.
///
/// ## Returns
///
/// A TcpFlags instance with only the RST flag set
///
pub fn rst_flags() -> TcpFlags {
  TcpFlags(..default_flags(), rst: True)
}

/// Creates PSH-ACK flags for pushing data
///
/// Used to request immediate delivery of data to the application.
///
/// ## Returns
///
/// A TcpFlags instance with PSH and ACK flags set
///
pub fn psh_ack_flags() -> TcpFlags {
  TcpFlags(..default_flags(), psh: True, ack: True)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Constructors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new TCP header with default values
///
/// ## Parameters
///
/// - `source_port`: The source port number
/// - `destination_port`: The destination port number
///
/// ## Returns
///
/// A TcpHeader with default flags and standard values
///
pub fn new(source_port: Int, destination_port: Int) -> TcpHeader {
  TcpHeader(
    source_port: source_port,
    destination_port: destination_port,
    sequence_number: 0,
    acknowledgment_number: 0,
    data_offset: 5,
    flags: default_flags(),
    window_size: 65_535,
    checksum: 0,
    urgent_pointer: 0,
    options: option.None,
  )
}

/// Creates a TCP header with specified flags
///
/// ## Parameters
///
/// - `source_port`: The source port number
/// - `destination_port`: The destination port number
/// - `flags`: The TCP control flags
///
/// ## Returns
///
/// A TcpHeader with the specified flags
///
pub fn with_flags(
  source_port: Int,
  destination_port: Int,
  flags: TcpFlags,
) -> TcpHeader {
  TcpHeader(..new(source_port, destination_port), flags: flags)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Modifier Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the sequence number
///
pub fn set_sequence_number(header: TcpHeader, seq: Int) -> TcpHeader {
  TcpHeader(..header, sequence_number: seq)
}

/// Sets the acknowledgment number
///
pub fn set_acknowledgment_number(header: TcpHeader, ack: Int) -> TcpHeader {
  TcpHeader(..header, acknowledgment_number: ack)
}

/// Sets the window size
///
pub fn set_window_size(header: TcpHeader, size: Int) -> TcpHeader {
  TcpHeader(..header, window_size: size)
}

/// Sets the checksum
///
pub fn set_checksum(header: TcpHeader, checksum: Int) -> TcpHeader {
  TcpHeader(..header, checksum: checksum)
}

/// Sets the flags
///
pub fn set_flags(header: TcpHeader, flags: TcpFlags) -> TcpHeader {
  TcpHeader(..header, flags: flags)
}

/// Sets the options
///
pub fn set_options(header: TcpHeader, options: BitArray) -> TcpHeader {
  let options_size = bit_array_byte_size(options)
  let padding_needed = case options_size % 4 {
    0 -> 0
    remainder -> 4 - remainder
  }
  let data_offset = 5 + { options_size + padding_needed } / 4
  TcpHeader(..header, options: option.Some(options), data_offset: data_offset)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flag Accessor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks if the SYN flag is set
///
pub fn is_syn(header: TcpHeader) -> Bool {
  header.flags.syn
}

/// Checks if the ACK flag is set
///
pub fn is_ack(header: TcpHeader) -> Bool {
  header.flags.ack
}

/// Checks if the FIN flag is set
///
pub fn is_fin(header: TcpHeader) -> Bool {
  header.flags.fin
}

/// Checks if the RST flag is set
///
pub fn is_rst(header: TcpHeader) -> Bool {
  header.flags.rst
}

/// Checks if the PSH flag is set
///
pub fn is_psh(header: TcpHeader) -> Bool {
  header.flags.psh
}

/// Checks if this is a SYN-ACK packet
///
pub fn is_syn_ack(header: TcpHeader) -> Bool {
  header.flags.syn && header.flags.ack
}

/// Checks if this is a FIN-ACK packet
///
pub fn is_fin_ack(header: TcpHeader) -> Bool {
  header.flags.fin && header.flags.ack
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Returns the header length in bytes
///
pub fn header_length(header: TcpHeader) -> Int {
  header.data_offset * 4
}

/// Returns the minimum TCP header size (20 bytes)
///
pub fn min_header_size() -> Int {
  20
}

/// Returns the maximum TCP header size (60 bytes)
///
pub fn max_header_size() -> Int {
  60
}

@external(erlang, "erlang", "byte_size")
fn bit_array_byte_size(data: BitArray) -> Int
