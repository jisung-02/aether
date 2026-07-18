//// Tracks received QUIC packet numbers and turns them into ACK frames
//// (RFC 9000 Section 19.3).
////
//// Received packet numbers are kept as a sorted list of inclusive
//// `#(low, high)` ranges, largest first, coalescing on insert so the list
//// stays non-overlapping and non-adjacent. `build_ack` walks that list to
//// produce the `largest_acked`/`first_range`/`ranges` triple the wire
//// format expects: each subsequent range is encoded as a `#(gap, length)`
//// pair, where `gap` counts the unacked packets strictly between it and
//// the previous (higher) range, and `length` is the size of the range
//// beyond its first packet.

import aether/protocol/quic/frame.{type Frame, Ack}
import gleam/int
import gleam/option

/// The set of received packet numbers (as coalesced inclusive ranges,
/// largest first), the time the current largest was received (monotonic
/// microseconds), and whether an ack-eliciting packet is pending
/// acknowledgement.
pub opaque type AckTracker {
  AckTracker(ranges: List(#(Int, Int)), largest_time: Int, ack_pending: Bool)
}

/// Creates a tracker with nothing received yet.
pub fn new() -> AckTracker {
  AckTracker(ranges: [], largest_time: 0, ack_pending: False)
}

/// Records that `packet_number` was received at `now` (monotonic
/// microseconds). Coalesces it into the tracked ranges (adjacent and
/// overlapping ranges merge into one); a duplicate packet number is a
/// no-op on the ranges themselves. The largest-received time only advances
/// when `packet_number` is strictly greater than the previous largest.
/// `ack_eliciting` packets mark the tracker as needing to send an ACK, even
/// if the packet number was already recorded.
pub fn record(
  t: AckTracker,
  packet_number: Int,
  ack_eliciting: Bool,
  now: Int,
) -> AckTracker {
  let becomes_new_largest = case t.ranges {
    [] -> True
    [#(_, high), ..] -> packet_number > high
  }
  let largest_time = case becomes_new_largest {
    True -> now
    False -> t.largest_time
  }
  AckTracker(
    ranges: insert(t.ranges, packet_number),
    largest_time: largest_time,
    ack_pending: t.ack_pending || ack_eliciting,
  )
}

/// Inserts `pn` into `ranges` (sorted descending by high, non-overlapping,
/// non-adjacent), merging with any range it touches or falls inside.
fn insert(ranges: List(#(Int, Int)), pn: Int) -> List(#(Int, Int)) {
  insert_loop(ranges, pn, pn)
}

fn insert_loop(
  ranges: List(#(Int, Int)),
  low: Int,
  high: Int,
) -> List(#(Int, Int)) {
  case ranges {
    [] -> [#(low, high)]
    [#(rlow, rhigh), ..rest] ->
      case True {
        _ if rlow > high + 1 -> [#(rlow, rhigh), ..insert_loop(rest, low, high)]
        _ if rhigh < low - 1 -> [#(low, high), #(rlow, rhigh), ..rest]
        _ -> insert_loop(rest, int.min(low, rlow), int.max(high, rhigh))
      }
  }
}

/// Whether an ack-eliciting packet has been received since the last
/// `on_ack_sent`.
pub fn ack_needed(t: AckTracker) -> Bool {
  t.ack_pending
}

/// The highest packet number received so far. `Error(Nil)` if nothing has
/// been received yet.
pub fn largest(t: AckTracker) -> Result(Int, Nil) {
  case t.ranges {
    [] -> Error(Nil)
    [#(_, high), ..] -> Ok(high)
  }
}

/// Builds an ACK frame (RFC 9000 Section 19.3) covering everything
/// received so far. `ack_delay` is `now` minus the time the largest packet
/// was received, rescaled by `ack_delay_exponent` (divided by
/// `2^ack_delay_exponent`, per the wire encoding). `Error(Nil)` if nothing
/// has been received yet.
pub fn build_ack(
  t: AckTracker,
  now: Int,
  ack_delay_exponent: Int,
) -> Result(Frame, Nil) {
  case t.ranges {
    [] -> Error(Nil)
    [#(low, high), ..rest] -> {
      let ack_delay =
        int.bitwise_shift_right(now - t.largest_time, ack_delay_exponent)
      let first_range = high - low
      let ranges = build_ranges(low, rest)
      Ok(Ack(high, ack_delay, first_range, ranges, option.None))
    }
  }
}

/// Turns the ranges below the top one into `#(gap, length)` pairs.
/// `prev_low` is the low end of the range immediately above (starting with
/// the top range's low).
fn build_ranges(prev_low: Int, ranges: List(#(Int, Int))) -> List(#(Int, Int)) {
  case ranges {
    [] -> []
    [#(low, high), ..rest] -> {
      let gap = prev_low - high - 2
      let length = high - low
      [#(gap, length), ..build_ranges(low, rest)]
    }
  }
}

/// Clears the ack-needed flag after an ACK has been sent.
pub fn on_ack_sent(t: AckTracker) -> AckTracker {
  AckTracker(..t, ack_pending: False)
}
