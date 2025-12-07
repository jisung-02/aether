// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Header Builder Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/tcp/header.{type TcpFlags, type TcpHeader}
import gleam/bit_array
import gleam/option

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Building Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds a TCP header into a BitArray
///
/// Converts a TcpHeader structure into its binary representation
/// suitable for network transmission.
///
/// ## Parameters
///
/// - `hdr`: The TCP header to build
///
/// ## Returns
///
/// A BitArray containing the serialized TCP header
///
/// ## Examples
///
/// ```gleam
/// let hdr = header.new(8080, 80)
///   |> header.set_flags(header.syn_flags())
///   |> header.set_sequence_number(1000)
///
/// let bytes = build_header(hdr)
/// // bytes is a 20-byte BitArray representing the TCP header
/// ```
///
pub fn build_header(hdr: TcpHeader) -> BitArray {
  let flags_bits = flags_to_bits(hdr.flags)

  let base_header = <<
    hdr.source_port:size(16),
    hdr.destination_port:size(16),
    hdr.sequence_number:size(32),
    hdr.acknowledgment_number:size(32),
    hdr.data_offset:size(4),
    0:size(3),
    flags_bits:bits,
    hdr.window_size:size(16),
    hdr.checksum:size(16),
    hdr.urgent_pointer:size(16),
  >>

  // Append options if present
  case hdr.options {
    option.Some(opts) -> {
      let padded_opts = pad_options(opts)
      bit_array.append(base_header, padded_opts)
    }
    option.None -> base_header
  }
}

/// Builds a TCP header with a zero checksum for checksum calculation
///
/// This is useful when calculating the checksum, as the checksum field
/// should be zero during calculation.
///
/// ## Parameters
///
/// - `hdr`: The TCP header to build
///
/// ## Returns
///
/// A BitArray with the checksum field set to zero
///
pub fn build_header_for_checksum(hdr: TcpHeader) -> BitArray {
  build_header(header.set_checksum(hdr, 0))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Segment Building Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Builds a complete TCP segment (header + payload)
///
/// ## Parameters
///
/// - `hdr`: The TCP header
/// - `payload`: The data payload
///
/// ## Returns
///
/// A BitArray containing the complete TCP segment
///
pub fn build_segment(hdr: TcpHeader, payload: BitArray) -> BitArray {
  let header_bytes = build_header(hdr)
  bit_array.append(header_bytes, payload)
}

/// Builds a TCP segment with payload for checksum calculation
///
/// ## Parameters
///
/// - `hdr`: The TCP header
/// - `payload`: The data payload
///
/// ## Returns
///
/// A BitArray with checksum field set to zero
///
pub fn build_segment_for_checksum(hdr: TcpHeader, payload: BitArray) -> BitArray {
  let header_bytes = build_header_for_checksum(hdr)
  bit_array.append(header_bytes, payload)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flag Conversion Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts TCP flags to a 9-bit BitArray
///
fn flags_to_bits(flags: TcpFlags) -> BitArray {
  let ns = bool_to_int(flags.ns)
  let cwr = bool_to_int(flags.cwr)
  let ece = bool_to_int(flags.ece)
  let urg = bool_to_int(flags.urg)
  let ack = bool_to_int(flags.ack)
  let psh = bool_to_int(flags.psh)
  let rst = bool_to_int(flags.rst)
  let syn = bool_to_int(flags.syn)
  let fin = bool_to_int(flags.fin)

  <<
    ns:size(1),
    cwr:size(1),
    ece:size(1),
    urg:size(1),
    ack:size(1),
    psh:size(1),
    rst:size(1),
    syn:size(1),
    fin:size(1),
  >>
}

/// Converts TCP flags to a 9-bit integer
///
/// The flags are packed in the following order (MSB to LSB):
/// NS, CWR, ECE, URG, ACK, PSH, RST, SYN, FIN
///
/// ## Parameters
///
/// - `flags`: The TCP flags to convert
///
/// ## Returns
///
/// An integer representing the packed flags
///
pub fn flags_to_int(flags: TcpFlags) -> Int {
  let ns = bool_to_int(flags.ns)
  let cwr = bool_to_int(flags.cwr)
  let ece = bool_to_int(flags.ece)
  let urg = bool_to_int(flags.urg)
  let ack = bool_to_int(flags.ack)
  let psh = bool_to_int(flags.psh)
  let rst = bool_to_int(flags.rst)
  let syn = bool_to_int(flags.syn)
  let fin = bool_to_int(flags.fin)

  ns
  * 256
  + cwr
  * 128
  + ece
  * 64
  + urg
  * 32
  + ack
  * 16
  + psh
  * 8
  + rst
  * 4
  + syn
  * 2
  + fin
}

/// Converts a boolean to an integer (True = 1, False = 0)
///
fn bool_to_int(b: Bool) -> Int {
  case b {
    True -> 1
    False -> 0
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Options Padding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Pads TCP options to a 32-bit boundary
///
/// TCP options must be padded to end on a 32-bit boundary.
/// This function adds zero padding as needed.
///
fn pad_options(opts: BitArray) -> BitArray {
  let size = bit_array.byte_size(opts)
  let padding_needed = case size % 4 {
    0 -> 0
    remainder -> 4 - remainder
  }

  case padding_needed {
    0 -> opts
    1 -> bit_array.append(opts, <<0:size(8)>>)
    2 -> bit_array.append(opts, <<0:size(16)>>)
    3 -> bit_array.append(opts, <<0:size(24)>>)
    _ -> opts
  }
}
