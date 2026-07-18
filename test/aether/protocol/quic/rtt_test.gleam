import aether/protocol/quic/rtt
import gleeunit/should

// All expectations below are computed by hand per RFC 9002 Section 5,
// using pure integer arithmetic (truncating division), matching the
// module's implementation exactly.

pub fn new_seeds_initial_estimate_test() {
  // smoothed = initial_rtt = 333_000
  // rttvar = initial_rtt / 2 = 166_500
  // has_sample = False, min = 0, latest = 0
  let r = rtt.new()
  rtt.smoothed(r) |> should.equal(333_000)
  rtt.rttvar(r) |> should.equal(166_500)
  rtt.has_sample(r) |> should.equal(False)
  rtt.min(r) |> should.equal(0)
  rtt.latest(r) |> should.equal(0)
}

pub fn first_sample_sets_min_and_smoothed_directly_test() {
  // First sample: min = smoothed = latest = 30_000, rttvar = latest / 2 = 15_000
  let r = rtt.update(rtt.new(), 30_000, 0, 25_000, False)
  rtt.min(r) |> should.equal(30_000)
  rtt.smoothed(r) |> should.equal(30_000)
  rtt.rttvar(r) |> should.equal(15_000)
  rtt.latest(r) |> should.equal(30_000)
  rtt.has_sample(r) |> should.equal(True)
}

pub fn second_sample_applies_ack_delay_and_ewma_test() {
  // Starting from the first-sample state above (min=30_000, smoothed=30_000,
  // rttvar=15_000), apply a second sample:
  //   latest = 40_000, ack_delay = 5_000, max_ack_delay = 25_000,
  //   handshake_confirmed = True
  //
  // min' = min(30_000, 40_000) = 30_000
  // handshake_confirmed caps ack_delay: min(5_000, 25_000) = 5_000 (no change)
  // adjustment guard: latest (40_000) >= min + ack_delay (30_000+5_000=35_000)
  //   -> true, so adjusted = 40_000 - 5_000 = 35_000
  // rttvar' = 15_000 - 15_000/4 + |30_000 - 35_000|/4
  //         = 15_000 - 3_750 + 1_250 = 12_500
  // smoothed' = 30_000 - 30_000/8 + 35_000/8
  //           = 30_000 - 3_750 + 4_375 = 30_625
  let first = rtt.update(rtt.new(), 30_000, 0, 25_000, False)
  let second = rtt.update(first, 40_000, 5000, 25_000, True)
  rtt.min(second) |> should.equal(30_000)
  rtt.smoothed(second) |> should.equal(30_625)
  rtt.rttvar(second) |> should.equal(12_500)
  rtt.latest(second) |> should.equal(40_000)
}

pub fn ack_delay_not_subtracted_when_latest_below_min_plus_delay_test() {
  // From the first-sample state (min=30_000, smoothed=30_000, rttvar=15_000),
  // apply a sample with a small latest so the guard fails:
  //   latest = 31_000, ack_delay = 5_000, max_ack_delay = 25_000,
  //   handshake_confirmed = False
  //
  // min' = min(30_000, 31_000) = 30_000  (unchanged by a larger latest)
  // guard: latest (31_000) >= min + ack_delay (35_000)? false
  //   -> adjusted = latest = 31_000 (ack_delay NOT subtracted)
  // rttvar' = 15_000 - 3_750 + |30_000 - 31_000|/4 = 15_000 - 3_750 + 250 = 11_500
  // smoothed' = 30_000 - 3_750 + 31_000/8 = 30_000 - 3_750 + 3_875 = 30_125
  let first = rtt.update(rtt.new(), 30_000, 0, 25_000, False)
  let second = rtt.update(first, 31_000, 5000, 25_000, False)
  rtt.min(second) |> should.equal(30_000)
  rtt.smoothed(second) |> should.equal(30_125)
  rtt.rttvar(second) |> should.equal(11_500)
  rtt.latest(second) |> should.equal(31_000)
}

pub fn handshake_not_confirmed_does_not_cap_ack_delay_test() {
  // From the first-sample state (min=30_000, smoothed=30_000, rttvar=15_000),
  // apply a sample with ack_delay far above max_ack_delay while
  // handshake_confirmed is False:
  //   latest = 80_000, ack_delay = 30_000, max_ack_delay = 10_000,
  //   handshake_confirmed = False
  //
  // ack_delay is NOT capped (would be 10_000 if it were), so it stays 30_000.
  // min' = min(30_000, 80_000) = 30_000
  // guard: latest (80_000) >= min + ack_delay (30_000+30_000=60_000)? true
  //   -> adjusted = 80_000 - 30_000 = 50_000 (full, uncapped ack_delay used)
  // rttvar' = 15_000 - 3_750 + |30_000 - 50_000|/4 = 15_000 - 3_750 + 5_000 = 16_250
  // smoothed' = 30_000 - 3_750 + 50_000/8 = 30_000 - 3_750 + 6_250 = 32_500
  let first = rtt.update(rtt.new(), 30_000, 0, 25_000, False)
  let second = rtt.update(first, 80_000, 30_000, 10_000, False)
  rtt.min(second) |> should.equal(30_000)
  rtt.smoothed(second) |> should.equal(32_500)
  rtt.rttvar(second) |> should.equal(16_250)
  rtt.latest(second) |> should.equal(80_000)
}

pub fn pto_duration_before_any_sample_test() {
  // pto_duration = smoothed + max(4*rttvar, granularity)
  //   = 333_000 + max(4 * 166_500, 1_000)
  //   = 333_000 + max(666_000, 1_000)
  //   = 333_000 + 666_000 = 999_000
  rtt.pto_duration(rtt.new()) |> should.equal(999_000)
}

pub fn pto_duration_after_sample_test() {
  // After the first sample (smoothed=30_000, rttvar=15_000):
  // pto_duration = 30_000 + max(4*15_000, 1_000) = 30_000 + 60_000 = 90_000
  let r = rtt.update(rtt.new(), 30_000, 0, 25_000, False)
  rtt.pto_duration(r) |> should.equal(90_000)
}
