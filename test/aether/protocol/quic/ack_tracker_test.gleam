import aether/protocol/quic/ack_tracker
import aether/protocol/quic/frame.{Ack}
import gleam/option
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Single packet.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn single_packet_builds_ack_with_no_ranges_test() {
  let t = ack_tracker.new() |> ack_tracker.record(7, True, 1000)
  ack_tracker.largest(t) |> should.equal(Ok(7))

  let assert Ok(Ack(largest_acked, _ack_delay, first_range, ranges, ecn)) =
    ack_tracker.build_ack(t, 1000, 0)
  largest_acked |> should.equal(7)
  first_range |> should.equal(0)
  ranges |> should.equal([])
  ecn |> should.equal(option.None)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Contiguous run coalesces into a single range.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn contiguous_run_coalesces_to_one_range_test() {
  // Recorded out of order: 7, 5, 8, 6 -> single range [5, 8].
  let t =
    ack_tracker.new()
    |> ack_tracker.record(7, True, 1000)
    |> ack_tracker.record(5, True, 1000)
    |> ack_tracker.record(8, True, 1000)
    |> ack_tracker.record(6, True, 1000)

  ack_tracker.largest(t) |> should.equal(Ok(8))

  let assert Ok(Ack(largest_acked, _, first_range, ranges, _)) =
    ack_tracker.build_ack(t, 1000, 0)
  largest_acked |> should.equal(8)
  // first_range = highest - low = 8 - 5 = 3
  first_range |> should.equal(3)
  ranges |> should.equal([])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Two disjoint clusters produce one gap/length pair.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn two_disjoint_clusters_test() {
  // Clusters {10, 11} and {5, 6, 7}.
  // largest = 11, first_range = 11 - 10 = 1.
  // Second range: prev_low (top range's low) = 10, current = (5, 7).
  //   gap = prev_low - current_high - 2 = 10 - 7 - 2 = 1
  //   length = current_high - current_low = 7 - 5 = 2
  let t =
    ack_tracker.new()
    |> ack_tracker.record(10, True, 1000)
    |> ack_tracker.record(11, True, 1000)
    |> ack_tracker.record(5, True, 1000)
    |> ack_tracker.record(6, True, 1000)
    |> ack_tracker.record(7, True, 1000)

  ack_tracker.largest(t) |> should.equal(Ok(11))

  let assert Ok(Ack(largest_acked, _, first_range, ranges, _)) =
    ack_tracker.build_ack(t, 1000, 0)
  largest_acked |> should.equal(11)
  first_range |> should.equal(1)
  ranges |> should.equal([#(1, 2)])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Three clusters: multiple gap/length pairs.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn three_disjoint_clusters_test() {
  // Clusters {20, 21}, {15, 16, 17}, {5, 6}.
  // largest = 21, first_range = 21 - 20 = 1.
  // Range 1: prev_low = 20, current = (15, 17)
  //   gap = 20 - 17 - 2 = 1, length = 17 - 15 = 2
  // Range 2: prev_low = 15, current = (5, 6)
  //   gap = 15 - 6 - 2 = 7, length = 6 - 5 = 1
  let t =
    ack_tracker.new()
    |> ack_tracker.record(20, True, 1000)
    |> ack_tracker.record(21, True, 1000)
    |> ack_tracker.record(15, True, 1000)
    |> ack_tracker.record(16, True, 1000)
    |> ack_tracker.record(17, True, 1000)
    |> ack_tracker.record(5, True, 1000)
    |> ack_tracker.record(6, True, 1000)

  ack_tracker.largest(t) |> should.equal(Ok(21))

  let assert Ok(Ack(largest_acked, _, first_range, ranges, _)) =
    ack_tracker.build_ack(t, 1000, 0)
  largest_acked |> should.equal(21)
  first_range |> should.equal(1)
  ranges |> should.equal([#(1, 2), #(7, 1)])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Out-of-order and duplicate inserts agree with sorted, unique inserts.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn out_of_order_and_duplicates_match_sorted_unique_test() {
  let sorted =
    ack_tracker.new()
    |> ack_tracker.record(5, True, 1000)
    |> ack_tracker.record(6, True, 1000)
    |> ack_tracker.record(7, True, 1000)
    |> ack_tracker.record(15, True, 1000)
    |> ack_tracker.record(16, True, 1000)
    |> ack_tracker.record(20, True, 1000)

  let shuffled_with_dupes =
    ack_tracker.new()
    |> ack_tracker.record(20, True, 1000)
    |> ack_tracker.record(6, True, 1000)
    |> ack_tracker.record(20, True, 1000)
    |> ack_tracker.record(16, True, 1000)
    |> ack_tracker.record(5, True, 1000)
    |> ack_tracker.record(15, True, 1000)
    |> ack_tracker.record(7, True, 1000)
    |> ack_tracker.record(7, True, 1000)
    |> ack_tracker.record(15, True, 1000)

  let assert Ok(expected) = ack_tracker.build_ack(sorted, 1000, 0)
  let assert Ok(actual) = ack_tracker.build_ack(shuffled_with_dupes, 1000, 0)
  actual |> should.equal(expected)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ack_delay encoding.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn ack_delay_rescaled_by_exponent_test() {
  // Largest received at now=1000; build_ack at now=1000+8000=9000 with
  // ack_delay_exponent=3 -> ack_delay = 8000 / 2^3 = 8000 / 8 = 1000.
  let t = ack_tracker.new() |> ack_tracker.record(1, True, 1000)

  let assert Ok(Ack(_, ack_delay, _, _, _)) = ack_tracker.build_ack(t, 9000, 3)
  ack_delay |> should.equal(1000)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ack_needed lifecycle.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn ack_needed_after_ack_eliciting_and_cleared_by_on_ack_sent_test() {
  let t = ack_tracker.new() |> ack_tracker.record(1, True, 1000)
  ack_tracker.ack_needed(t) |> should.equal(True)

  let t = ack_tracker.on_ack_sent(t)
  ack_tracker.ack_needed(t) |> should.equal(False)
}

pub fn non_ack_eliciting_record_does_not_set_ack_needed_test() {
  let t = ack_tracker.new() |> ack_tracker.record(1, False, 1000)
  ack_tracker.ack_needed(t) |> should.equal(False)
}

pub fn ack_needed_survives_mixed_records_until_sent_test() {
  let t =
    ack_tracker.new()
    |> ack_tracker.record(1, False, 1000)
    |> ack_tracker.record(2, True, 1000)
    |> ack_tracker.record(3, False, 1000)
  ack_tracker.ack_needed(t) |> should.equal(True)

  let t = ack_tracker.on_ack_sent(t)
  ack_tracker.ack_needed(t) |> should.equal(False)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Nothing received yet.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_ack_on_empty_tracker_is_error_test() {
  ack_tracker.build_ack(ack_tracker.new(), 1000, 0) |> should.equal(Error(Nil))
}

pub fn largest_on_empty_tracker_is_error_test() {
  ack_tracker.largest(ack_tracker.new()) |> should.equal(Error(Nil))
}
