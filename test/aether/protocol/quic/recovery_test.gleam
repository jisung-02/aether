import aether/protocol/quic/congestion
import aether/protocol/quic/packet_space.{
  ApplicationSpace, HandshakeSpace, InitialSpace,
}
import aether/protocol/quic/recovery.{LossResult}
import aether/protocol/quic/rtt
import aether/protocol/quic/sent_packet.{type SentPacket, SentPacket}
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

const mds = 1200

const max_ack_delay = 25_000

fn packet(pn: Int, time_sent: Int) -> SentPacket {
  SentPacket(
    packet_number: pn,
    time_sent: time_sent,
    ack_eliciting: True,
    in_flight: True,
    sent_bytes: 1200,
    frames: [],
  )
}

// ── Acknowledgement removes packets and updates RTT ──────────────────────

pub fn ack_removes_and_updates_rtt_test() {
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(InitialSpace, packet(0, 0))
    |> recovery.on_packet_sent(InitialSpace, packet(1, 1000))

  // ACK largest 1 at now=31_000 → RTT sample 30_000 from packet 1.
  let LossResult(r, acked, lost) =
    recovery.on_ack_received(
      r,
      InitialSpace,
      1,
      0,
      [#(0, 1)],
      31_000,
      max_ack_delay,
      False,
    )

  list.length(acked) |> should.equal(2)
  lost |> should.equal([])
  rtt.smoothed(recovery.rtt(r)) |> should.equal(30_000)
  recovery.bytes_in_flight(r) |> should.equal(0)
}

pub fn rtt_not_updated_when_largest_not_acked_test() {
  // Largest acked (5) is not among our sent packets; RTT must stay at its
  // initial value even though packet 0 is acked.
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(InitialSpace, packet(0, 0))
    |> recovery.on_packet_sent(InitialSpace, packet(1, 1000))

  let LossResult(r, _, _) =
    recovery.on_ack_received(
      r,
      InitialSpace,
      5,
      0,
      [#(0, 0)],
      31_000,
      max_ack_delay,
      False,
    )

  rtt.has_sample(recovery.rtt(r)) |> should.equal(False)
  rtt.smoothed(recovery.rtt(r)) |> should.equal(rtt.initial_rtt)
}

// ── Packet-threshold loss ────────────────────────────────────────────────

pub fn packet_threshold_loss_test() {
  // Packets 0..3 sent close together; ACK of 3 makes 0 lost
  // (3 - 0 >= kPacketThreshold 3), while 1 and 2 are still only reordered.
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(InitialSpace, packet(0, 0))
    |> recovery.on_packet_sent(InitialSpace, packet(1, 100))
    |> recovery.on_packet_sent(InitialSpace, packet(2, 200))
    |> recovery.on_packet_sent(InitialSpace, packet(3, 300))

  let LossResult(_, acked, lost) =
    recovery.on_ack_received(
      r,
      InitialSpace,
      3,
      0,
      [#(3, 3)],
      1000,
      max_ack_delay,
      False,
    )

  list.map(acked, fn(p) { p.packet_number }) |> should.equal([3])
  list.map(lost, fn(p) { p.packet_number }) |> should.equal([0])
}

// ── Time-threshold loss and the loss timer ───────────────────────────────

pub fn time_threshold_loss_test() {
  // Establish an RTT of 10_000µs, then check a packet far in the past is
  // lost by time threshold when a later packet is acked.
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(ApplicationSpace, packet(0, 0))
    |> recovery.on_packet_sent(ApplicationSpace, packet(1, 100_000))

  // ACK only packet 1 at now=110_000 → RTT 10_000. loss_delay =
  // max(9/8 * 10_000, 1000) = 11_250. Packet 0 sent at 0 <= 110_000 -
  // 11_250 = 98_750 → lost by time.
  let LossResult(_, acked, lost) =
    recovery.on_ack_received(
      r,
      ApplicationSpace,
      1,
      0,
      [#(1, 1)],
      110_000,
      max_ack_delay,
      False,
    )

  list.map(acked, fn(p) { p.packet_number }) |> should.equal([1])
  list.map(lost, fn(p) { p.packet_number }) |> should.equal([0])
}

pub fn reordered_packet_schedules_loss_time_test() {
  // Packets close together: on ACK of 1, packet 0 is neither threshold-lost
  // nor time-lost, so a loss_time is armed. The inter-packet gap (1000)
  // must be under RTT/8 (1250) for packet 0 to survive the ACK.
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(ApplicationSpace, packet(0, 99_000))
    |> recovery.on_packet_sent(ApplicationSpace, packet(1, 100_000))

  // ACK 1 at now=110_000 → first RTT sample 10_000, loss_delay 11_250.
  // Packet 0 at 99_000 > 110_000 - 11_250 = 98_750 → not yet lost;
  // loss_time = 99_000 + 11_250 = 110_250.
  let LossResult(r, _, lost) =
    recovery.on_ack_received(
      r,
      ApplicationSpace,
      1,
      0,
      [#(1, 1)],
      110_000,
      max_ack_delay,
      False,
    )
  lost |> should.equal([])

  recovery.loss_detection_timer(r, max_ack_delay, True)
  |> should.equal(Some(110_250))
}

pub fn loss_timeout_detects_scheduled_loss_test() {
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(ApplicationSpace, packet(0, 99_000))
    |> recovery.on_packet_sent(ApplicationSpace, packet(1, 100_000))
  let LossResult(r, _, _) =
    recovery.on_ack_received(
      r,
      ApplicationSpace,
      1,
      0,
      [#(1, 1)],
      110_000,
      max_ack_delay,
      False,
    )

  // Fire the timer at the scheduled loss_time; packet 0 becomes lost.
  let LossResult(_, _, lost) = recovery.on_loss_timeout(r, 110_250)
  list.map(lost, fn(p) { p.packet_number }) |> should.equal([0])
}

// ── PTO timer and backoff ────────────────────────────────────────────────

pub fn pto_timer_before_rtt_sample_test() {
  // One ack-eliciting Initial packet in flight, no RTT sample: PTO =
  // pto_duration(new rtt) = 333_000 + max(4*166_500, 1000) = 999_000,
  // from time_of_last_ack_eliciting 500.
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(InitialSpace, packet(0, 500))

  recovery.loss_detection_timer(r, max_ack_delay, False)
  |> should.equal(Some(500 + 999_000))
}

pub fn pto_backoff_doubles_after_timeout_test() {
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(InitialSpace, packet(0, 500))

  // First PTO expiry bumps pto_count to 1; no packets lost.
  let LossResult(r, _, lost) = recovery.on_loss_timeout(r, 1_000_000)
  lost |> should.equal([])
  recovery.pto_count(r) |> should.equal(1)

  // Timer now uses 2^1 backoff: 500 + 2*999_000.
  recovery.loss_detection_timer(r, max_ack_delay, False)
  |> should.equal(Some(500 + 2 * 999_000))
}

pub fn timer_none_without_ack_eliciting_in_flight_test() {
  // A non-ack-eliciting (ACK-only) packet in flight arms no timer for a
  // server whose peer address is validated.
  let ack_only =
    SentPacket(
      packet_number: 0,
      time_sent: 500,
      ack_eliciting: False,
      in_flight: False,
      sent_bytes: 40,
      frames: [],
    )
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(ApplicationSpace, ack_only)

  recovery.loss_detection_timer(r, max_ack_delay, True)
  |> should.equal(None)
}

// ── Discarding a space ───────────────────────────────────────────────────

pub fn discard_space_clears_bytes_in_flight_test() {
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(InitialSpace, packet(0, 0))
    |> recovery.on_packet_sent(HandshakeSpace, packet(0, 100))

  recovery.bytes_in_flight(r) |> should.equal(2400)

  let r = recovery.discard_space(r, InitialSpace)
  recovery.bytes_in_flight(r) |> should.equal(1200)
  recovery.pto_count(r) |> should.equal(0)
}

// ── Congestion integration on loss ───────────────────────────────────────

pub fn loss_reduces_congestion_window_test() {
  // Times are > 0 so the loss's congestion event is not masked by the
  // initial recovery_start_time of 0.
  let r =
    recovery.new(mds)
    |> recovery.on_packet_sent(ApplicationSpace, packet(0, 1000))
    |> recovery.on_packet_sent(ApplicationSpace, packet(1, 1100))
    |> recovery.on_packet_sent(ApplicationSpace, packet(2, 1200))
    |> recovery.on_packet_sent(ApplicationSpace, packet(3, 1300))

  // ACK 3 first credits its 1200 bytes in slow start (window 12_000 →
  // 13_200), then loses packet 0 by packet threshold → congestion event
  // halves the window to 6600.
  let LossResult(r, _, lost) =
    recovery.on_ack_received(
      r,
      ApplicationSpace,
      3,
      0,
      [#(3, 3)],
      2000,
      max_ack_delay,
      False,
    )
  list.map(lost, fn(p) { p.packet_number }) |> should.equal([0])
  congestion.window(recovery.congestion(r)) |> should.equal(6600)
}
