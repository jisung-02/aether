import aether/protocol/quic/congestion
import gleeunit/should

// max_datagram_size 1200: initial_window = min(12000, max(2400, 14720))
// = min(12000, 14720) = 12000. minimum_window = 2400.
const mds = 1200

pub fn initial_window_formula_test() {
  // Small MDS floors at 14720 unless 10*mds is smaller.
  congestion.initial_window(1200) |> should.equal(12_000)
  // 1472: 10*1472 = 14720, max(2944, 14720) = 14720, min = 14720.
  congestion.initial_window(1472) |> should.equal(14_720)
  // Above 1472 the 14720 floor caps the window: min(20000, 14720) = 14720.
  congestion.initial_window(2000) |> should.equal(14_720)
}

pub fn new_starts_in_slow_start_test() {
  let c = congestion.new(mds)
  congestion.window(c) |> should.equal(12_000)
  congestion.bytes_in_flight(c) |> should.equal(0)
  congestion.ssthresh(c) |> should.equal(-1)
  congestion.available(c) |> should.equal(12_000)
}

pub fn on_sent_tracks_bytes_in_flight_test() {
  let c = congestion.new(mds) |> congestion.on_sent(1200)
  congestion.bytes_in_flight(c) |> should.equal(1200)
  congestion.available(c) |> should.equal(10_800)
}

pub fn slow_start_grows_by_acked_bytes_test() {
  // Sent at t=1000, acked at t=2000 (after recovery_start_time 0, so grows).
  let c =
    congestion.new(mds)
    |> congestion.on_sent(1200)
    |> congestion.on_acked(1200, 1000, False)
  congestion.window(c) |> should.equal(13_200)
  congestion.bytes_in_flight(c) |> should.equal(0)
}

pub fn app_limited_suppresses_growth_test() {
  let c =
    congestion.new(mds)
    |> congestion.on_sent(1200)
    |> congestion.on_acked(1200, 1000, True)
  congestion.window(c) |> should.equal(12_000)
  congestion.bytes_in_flight(c) |> should.equal(0)
}

pub fn loss_halves_window_and_sets_ssthresh_test() {
  // Lose a 1200-byte packet sent at t=5000; window 12000 -> ssthresh 6000,
  // window max(6000, 2400) = 6000.
  let c =
    congestion.new(mds)
    |> congestion.on_sent(1200)
    |> congestion.on_lost(1200, 5000, 6000)
  congestion.ssthresh(c) |> should.equal(6000)
  congestion.window(c) |> should.equal(6000)
  congestion.bytes_in_flight(c) |> should.equal(0)
}

pub fn no_double_reduction_within_recovery_test() {
  // First loss at t=5000 enters recovery at now=6000. A second loss of a
  // packet also sent at t=5000 (<= recovery_start_time 6000) must not
  // reduce again.
  let c =
    congestion.new(mds)
    |> congestion.on_sent(2400)
    |> congestion.on_lost(1200, 5000, 6000)
  let window_after_first = congestion.window(c)
  let c = congestion.on_lost(c, 1200, 5000, 7000)
  congestion.window(c) |> should.equal(window_after_first)
}

pub fn congestion_avoidance_increment_test() {
  // Drive window below a small ssthresh by a loss, then ack to grow in CA.
  // Start window 12000; loss of packet sent t=5000 -> ssthresh 6000,
  // window 6000. Now window (6000) >= ssthresh (6000) -> congestion
  // avoidance. Ack a 1200-byte packet sent at t=8000 (after recovery start
  // 6000): window += 1200*1200/6000 = 240.
  let c =
    congestion.new(mds)
    |> congestion.on_sent(1200)
    |> congestion.on_lost(1200, 5000, 6000)
    |> congestion.on_sent(1200)
    |> congestion.on_acked(1200, 8000, False)
  congestion.window(c) |> should.equal(6240)
}
