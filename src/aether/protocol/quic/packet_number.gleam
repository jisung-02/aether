//// QUIC packet number truncation and reconstruction (RFC 9000 Appendix A.2
//// and A.3).
////
//// On the wire, packet numbers are sent truncated to the smallest number of
//// bytes that still lets the peer recover the full value, given the
//// largest packet number it has already acknowledged. These functions are
//// pure: no I/O, no crypto, just the arithmetic from the RFC's pseudocode.

import gleam/int

/// Largest packet number representable in a QUIC packet number space
/// (2^62 - 1, RFC 9000 Section 12.3).
pub const max_packet_number = 4_611_686_018_427_387_903

/// 2^62, used as the wraparound boundary in `decode`.
const packet_number_space = 4_611_686_018_427_387_904

/// Truncates `full_pn` for the wire, given the largest packet number the
/// peer has acknowledged (RFC 9000 Appendix A.2).
///
/// Pass `-1` for `largest_acked` when nothing has been acknowledged yet
/// (mirrors the RFC pseudocode's `None` case, since `full_pn - -1` is
/// `full_pn + 1`).
///
/// Returns `#(truncated_value, byte_length)` where `byte_length` is in
/// `1..4`, the number of bytes the encoded packet number occupies.
pub fn truncate(full_pn: Int, largest_acked: Int) -> #(Int, Int) {
  let num_unacked = case full_pn - largest_acked {
    n if n < 1 -> 1
    n -> n
  }

  // At least one more bit than needed to represent num_unacked distinct
  // values.
  let min_bits = bit_length(num_unacked) + 1
  let num_bytes = case { min_bits + 7 } / 8 {
    n if n > 4 -> 4
    n if n < 1 -> 1
    n -> n
  }

  let mask = int.bitwise_shift_left(1, num_bytes * 8) - 1
  let truncated = int.bitwise_and(full_pn, mask)
  #(truncated, num_bytes)
}

/// Reconstructs a full packet number from its truncated wire form (RFC 9000
/// Appendix A.3).
///
/// - `truncated`: the value carried on the wire.
/// - `pn_nbits`: the width of that value in bits (8 * byte length).
/// - `largest_pn`: the largest packet number decoded so far in this packet
///   number space.
pub fn decode(truncated: Int, pn_nbits: Int, largest_pn: Int) -> Int {
  let expected_pn = largest_pn + 1
  let pn_win = int.bitwise_shift_left(1, pn_nbits)
  let pn_hwin = pn_win / 2
  let pn_mask = pn_win - 1

  let candidate_pn =
    int.bitwise_or(
      int.bitwise_and(expected_pn, int.bitwise_not(pn_mask)),
      truncated,
    )

  case
    candidate_pn <= expected_pn - pn_hwin
    && candidate_pn < packet_number_space - pn_win
  {
    True -> candidate_pn + pn_win
    False ->
      case candidate_pn > expected_pn + pn_hwin && candidate_pn >= pn_win {
        True -> candidate_pn - pn_win
        False -> candidate_pn
      }
  }
}

/// Number of bits needed to represent `n` in unsigned binary (0 for `n <=
/// 0`), i.e. `floor(log2(n)) + 1` for positive `n`.
fn bit_length(n: Int) -> Int {
  bit_length_loop(n, 0)
}

fn bit_length_loop(n: Int, acc: Int) -> Int {
  case n <= 0 {
    True -> acc
    False -> bit_length_loop(int.bitwise_shift_right(n, 1), acc + 1)
  }
}
