// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Checksum Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/bit_array

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// TCP protocol number for pseudo header
const tcp_protocol: Int = 6

/// Maximum 16-bit value
const max_16bit: Int = 65_535

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Checksum Calculation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Calculates the TCP checksum for a segment
///
/// The TCP checksum covers the pseudo header and the entire TCP segment
/// (header + data). This implements the Internet checksum algorithm
/// as defined in RFC 793.
///
/// ## Parameters
///
/// - `pseudo_header`: The IP pseudo header (12 bytes for IPv4)
/// - `tcp_segment`: The complete TCP segment (header + payload)
///
/// ## Returns
///
/// The 16-bit checksum value
///
/// ## Algorithm
///
/// 1. Combine pseudo header and TCP segment
/// 2. Sum all 16-bit words
/// 3. Fold any carry bits back into the 16-bit sum
/// 4. Take the one's complement
///
/// ## Examples
///
/// ```gleam
/// let pseudo = ipv4_pseudo_header(src_ip, dst_ip, segment_length)
/// let checksum = calculate_checksum(pseudo, segment)
/// ```
///
pub fn calculate_checksum(
  pseudo_header: BitArray,
  tcp_segment: BitArray,
) -> Int {
  let combined = bit_array.append(pseudo_header, tcp_segment)

  // Convert to 16-bit words and sum
  let sum = sum_16bit_words(combined, 0)

  // Fold carry bits
  let folded = fold_carry(sum)

  // One's complement
  ones_complement(folded)
}

/// Verifies a TCP checksum
///
/// When the checksum is computed over data that includes a valid checksum,
/// the result should be 0xFFFF (or 0 after one's complement).
///
/// ## Parameters
///
/// - `pseudo_header`: The IP pseudo header
/// - `tcp_segment`: The complete TCP segment including checksum
///
/// ## Returns
///
/// True if the checksum is valid, False otherwise
///
pub fn verify_checksum(pseudo_header: BitArray, tcp_segment: BitArray) -> Bool {
  let combined = bit_array.append(pseudo_header, tcp_segment)
  let sum = sum_16bit_words(combined, 0)
  let folded = fold_carry(sum)

  // If checksum is valid, folded sum should be 0xFFFF
  folded == max_16bit
}

/// Verifies a TCP checksum against an expected value
///
/// ## Parameters
///
/// - `pseudo_header`: The IP pseudo header
/// - `tcp_segment`: The TCP segment (with checksum field zeroed)
/// - `expected_checksum`: The expected checksum value
///
/// ## Returns
///
/// True if the calculated checksum matches the expected value
///
pub fn verify_checksum_value(
  pseudo_header: BitArray,
  tcp_segment: BitArray,
  expected_checksum: Int,
) -> Bool {
  let calculated = calculate_checksum(pseudo_header, tcp_segment)
  calculated == expected_checksum
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pseudo Header Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates an IPv4 pseudo header for checksum calculation
///
/// The pseudo header is used in TCP checksum calculation to protect
/// against misrouted segments. It includes:
/// - Source IP address (4 bytes)
/// - Destination IP address (4 bytes)
/// - Reserved byte (1 byte, always 0)
/// - Protocol number (1 byte, 6 for TCP)
/// - TCP length (2 bytes)
///
/// ## Parameters
///
/// - `source_ip`: Source IP address as 4-byte BitArray
/// - `dest_ip`: Destination IP address as 4-byte BitArray
/// - `tcp_length`: Total length of TCP segment (header + payload)
///
/// ## Returns
///
/// A 12-byte pseudo header BitArray
///
/// ## Examples
///
/// ```gleam
/// let src = <<192, 168, 1, 1>>
/// let dst = <<192, 168, 1, 2>>
/// let pseudo = ipv4_pseudo_header(src, dst, 40)
/// ```
///
pub fn ipv4_pseudo_header(
  source_ip: BitArray,
  dest_ip: BitArray,
  tcp_length: Int,
) -> BitArray {
  <<
    source_ip:bits,
    dest_ip:bits,
    0:size(8),
    tcp_protocol:size(8),
    tcp_length:size(16),
  >>
}

/// Creates an IPv6 pseudo header for checksum calculation
///
/// The IPv6 pseudo header is larger than IPv4:
/// - Source IP address (16 bytes)
/// - Destination IP address (16 bytes)
/// - TCP length (4 bytes)
/// - Zero padding (3 bytes)
/// - Next header (1 byte, 6 for TCP)
///
/// ## Parameters
///
/// - `source_ip`: Source IP address as 16-byte BitArray
/// - `dest_ip`: Destination IP address as 16-byte BitArray
/// - `tcp_length`: Total length of TCP segment
///
/// ## Returns
///
/// A 40-byte pseudo header BitArray
///
pub fn ipv6_pseudo_header(
  source_ip: BitArray,
  dest_ip: BitArray,
  tcp_length: Int,
) -> BitArray {
  <<
    source_ip:bits,
    dest_ip:bits,
    tcp_length:size(32),
    0:size(24),
    tcp_protocol:size(8),
  >>
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sums all 16-bit words in a BitArray
///
/// Handles odd-length data by padding the last byte with zeros.
///
fn sum_16bit_words(data: BitArray, acc: Int) -> Int {
  case data {
    <<word:size(16), rest:bits>> -> sum_16bit_words(rest, acc + word)
    <<byte:size(8)>> ->
      // Pad last byte with zeros (shift left 8 bits)
      acc + byte * 256
    <<>> -> acc
    _ -> acc
  }
}

/// Folds carry bits back into the 16-bit sum
///
/// Repeatedly adds the carry (bits above 16) to the lower 16 bits
/// until no carry remains.
///
fn fold_carry(sum: Int) -> Int {
  let carry = sum / 65_536
  let lower = sum % 65_536

  case carry {
    0 -> lower
    _ -> fold_carry(lower + carry)
  }
}

/// Returns the one's complement of a 16-bit value
///
fn ones_complement(value: Int) -> Int {
  max_16bit - value
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates an IP address BitArray from four octets
///
/// ## Parameters
///
/// - `a`, `b`, `c`, `d`: The four octets of the IP address
///
/// ## Returns
///
/// A 4-byte BitArray representing the IP address
///
/// ## Examples
///
/// ```gleam
/// let ip = ipv4_address(192, 168, 1, 1)
/// // <<192, 168, 1, 1>>
/// ```
///
pub fn ipv4_address(a: Int, b: Int, c: Int, d: Int) -> BitArray {
  <<a:size(8), b:size(8), c:size(8), d:size(8)>>
}

/// Parses an IP address from a BitArray
///
/// ## Parameters
///
/// - `data`: A 4-byte BitArray
///
/// ## Returns
///
/// A tuple of four octets, or an error if parsing fails
///
pub fn parse_ipv4_address(data: BitArray) -> Result(#(Int, Int, Int, Int), Nil) {
  case data {
    <<a:size(8), b:size(8), c:size(8), d:size(8)>> -> Ok(#(a, b, c, d))
    _ -> Error(Nil)
  }
}
