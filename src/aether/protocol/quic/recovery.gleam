//// QUIC loss detection, PTO, and congestion integration
//// (RFC 9002 Sections 6 and Appendix A). Holds per-packet-number-space
//// sent-packet tracking plus a shared RTT estimator and NewReno
//// controller. Pure and deterministic: every time-dependent function
//// takes `now` (monotonic microseconds) and returns timer deadlines for
//// the I/O layer to schedule.
////
//// Server simplification: a server's peer address is always validated
//// (RFC 9002 A.5 PeerCompletedAddressValidation), so `pto_count` resets
//// on every ACK and the client-only anti-deadlock branches never fire.

import aether/protocol/quic/congestion.{type Congestion}
import aether/protocol/quic/packet_space.{type Space}
import aether/protocol/quic/rtt.{type Rtt}
import aether/protocol/quic/sent_packet.{type SentPacket}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

const packet_threshold = 3

/// Time-threshold multiplier kTimeThreshold = 9/8, applied as a rational
/// to stay in integer arithmetic.
const time_threshold_num = 9

const time_threshold_den = 8

type SpaceState {
  SpaceState(
    sent: Dict(Int, SentPacket),
    largest_acked: Option(Int),
    loss_time: Int,
    time_of_last_ack_eliciting: Int,
  )
}

fn empty_space() -> SpaceState {
  SpaceState(
    sent: dict.new(),
    largest_acked: None,
    loss_time: 0,
    time_of_last_ack_eliciting: 0,
  )
}

/// Loss-recovery state across all three packet number spaces.
pub opaque type Recovery {
  Recovery(
    initial: SpaceState,
    handshake: SpaceState,
    application: SpaceState,
    rtt: Rtt,
    congestion: Congestion,
    pto_count: Int,
  )
}

/// The result of an event that may acknowledge or lose packets.
pub type LossResult {
  LossResult(
    recovery: Recovery,
    acked: List(SentPacket),
    lost: List(SentPacket),
  )
}

/// A fresh recovery state for the given path max datagram size.
pub fn new(max_datagram_size: Int) -> Recovery {
  Recovery(
    initial: empty_space(),
    handshake: empty_space(),
    application: empty_space(),
    rtt: rtt.new(),
    congestion: congestion.new(max_datagram_size),
    pto_count: 0,
  )
}

/// The current RTT estimator.
pub fn rtt(r: Recovery) -> Rtt {
  r.rtt
}

/// The current congestion controller.
pub fn congestion(r: Recovery) -> Congestion {
  r.congestion
}

/// The current PTO backoff count.
pub fn pto_count(r: Recovery) -> Int {
  r.pto_count
}

/// Bytes currently in flight across all spaces.
pub fn bytes_in_flight(r: Recovery) -> Int {
  congestion.bytes_in_flight(r.congestion)
}

// ─────────────────────────────────────────────────────────────────────────
// Sending
// ─────────────────────────────────────────────────────────────────────────

/// Records a sent packet (RFC 9002 A.5).
pub fn on_packet_sent(
  r: Recovery,
  space: Space,
  packet: SentPacket,
) -> Recovery {
  let state = get_space(r, space)
  let state =
    SpaceState(
      ..state,
      sent: dict.insert(state.sent, packet.packet_number, packet),
      time_of_last_ack_eliciting: case packet.ack_eliciting {
        True -> packet.time_sent
        False -> state.time_of_last_ack_eliciting
      },
    )
  let r = set_space(r, space, state)
  case packet.in_flight {
    True ->
      Recovery(
        ..r,
        congestion: congestion.on_sent(r.congestion, packet.sent_bytes),
      )
    False -> r
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Receiving an acknowledgement
// ─────────────────────────────────────────────────────────────────────────

/// Processes an ACK (RFC 9002 A.7). `acked_ranges` are inclusive
/// `#(low, high)` packet-number ranges decoded from the ACK frame.
/// Returns the newly acknowledged and newly lost packets.
pub fn on_ack_received(
  r: Recovery,
  space: Space,
  largest_acked: Int,
  ack_delay: Int,
  acked_ranges: List(#(Int, Int)),
  now: Int,
  max_ack_delay: Int,
  handshake_confirmed: Bool,
) -> LossResult {
  let state = get_space(r, space)
  let new_largest = case state.largest_acked {
    Some(existing) -> int.max(existing, largest_acked)
    None -> largest_acked
  }

  let #(acked, remaining) = partition_acked(state.sent, acked_ranges)

  case acked {
    [] -> {
      let state = SpaceState(..state, largest_acked: Some(new_largest))
      LossResult(set_space(r, space, state), [], [])
    }
    _ -> {
      // RTT update when the largest acked is newly acked and ack-eliciting.
      let rtt = case largest_newly_acked(acked, largest_acked) {
        Some(packet) ->
          rtt.update(
            r.rtt,
            now - packet.time_sent,
            ack_delay,
            max_ack_delay,
            handshake_confirmed,
          )
        None -> r.rtt
      }

      let state =
        SpaceState(..state, sent: remaining, largest_acked: Some(new_largest))
      let r = Recovery(..r, rtt: rtt)
      let r = set_space(r, space, state)

      // Congestion: credit each in-flight acked packet.
      let congestion =
        list.fold(acked, r.congestion, fn(c, packet) {
          case packet.in_flight {
            True ->
              congestion.on_acked(c, packet.sent_bytes, packet.time_sent, False)
            False -> c
          }
        })
      let r = Recovery(..r, congestion: congestion)

      let #(r, lost) = detect_and_remove_lost(r, space, now)
      // Reset PTO backoff (server: peer address always validated).
      let r = Recovery(..r, pto_count: 0)
      LossResult(r, acked, lost)
    }
  }
}

fn partition_acked(
  sent: Dict(Int, SentPacket),
  ranges: List(#(Int, Int)),
) -> #(List(SentPacket), Dict(Int, SentPacket)) {
  dict.fold(sent, #([], dict.new()), fn(acc, pn, packet) {
    let #(acked, remaining) = acc
    case in_ranges(pn, ranges) {
      True -> #([packet, ..acked], remaining)
      False -> #(acked, dict.insert(remaining, pn, packet))
    }
  })
}

fn in_ranges(pn: Int, ranges: List(#(Int, Int))) -> Bool {
  list.any(ranges, fn(range) {
    let #(low, high) = range
    pn >= low && pn <= high
  })
}

fn largest_newly_acked(
  acked: List(SentPacket),
  largest_acked: Int,
) -> Option(SentPacket) {
  case list.find(acked, fn(p) { p.packet_number == largest_acked }) {
    Ok(packet) ->
      case packet.ack_eliciting {
        True -> Some(packet)
        False -> None
      }
    Error(Nil) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Loss detection
// ─────────────────────────────────────────────────────────────────────────

fn detect_and_remove_lost(
  r: Recovery,
  space: Space,
  now: Int,
) -> #(Recovery, List(SentPacket)) {
  let state = get_space(r, space)
  case state.largest_acked {
    None -> #(r, [])
    Some(largest_acked) -> {
      let loss_delay = loss_delay(r.rtt)
      let lost_send_time = now - loss_delay

      let #(lost, remaining, next_loss_time) =
        dict.fold(state.sent, #([], dict.new(), 0), fn(acc, pn, packet) {
          let #(lost, remaining, loss_time) = acc
          case pn > largest_acked {
            True -> #(lost, dict.insert(remaining, pn, packet), loss_time)
            False ->
              case
                packet.time_sent <= lost_send_time
                || largest_acked >= pn + packet_threshold
              {
                True -> #([packet, ..lost], remaining, loss_time)
                False -> {
                  let candidate = packet.time_sent + loss_delay
                  let loss_time = case loss_time == 0 {
                    True -> candidate
                    False -> int.min(loss_time, candidate)
                  }
                  #(lost, dict.insert(remaining, pn, packet), loss_time)
                }
              }
          }
        })

      let state =
        SpaceState(..state, sent: remaining, loss_time: next_loss_time)
      let r = set_space(r, space, state)
      let r = apply_lost_to_congestion(r, lost, now)
      #(r, lost)
    }
  }
}

fn apply_lost_to_congestion(
  r: Recovery,
  lost: List(SentPacket),
  now: Int,
) -> Recovery {
  let #(lost_bytes, latest_loss_time) =
    list.fold(lost, #(0, 0), fn(acc, packet) {
      let #(bytes, latest) = acc
      case packet.in_flight {
        True -> #(bytes + packet.sent_bytes, int.max(latest, packet.time_sent))
        False -> acc
      }
    })
  Recovery(
    ..r,
    congestion: congestion.on_lost(
      r.congestion,
      lost_bytes,
      latest_loss_time,
      now,
    ),
  )
}

fn loss_delay(r: Rtt) -> Int {
  let base = int.max(rtt.latest(r), rtt.smoothed(r))
  int.max(base * time_threshold_num / time_threshold_den, rtt.granularity)
}

// ─────────────────────────────────────────────────────────────────────────
// Timers
// ─────────────────────────────────────────────────────────────────────────

/// The loss detection timer deadline (RFC 9002 A.8), or `None` when no
/// timer should be armed. Returns the earliest set loss_time if any, else
/// the PTO deadline when ack-eliciting packets are in flight.
pub fn loss_detection_timer(
  r: Recovery,
  max_ack_delay: Int,
  handshake_confirmed: Bool,
) -> Option(Int) {
  case earliest_loss_time(r) {
    Some(time) -> Some(time)
    None ->
      case has_ack_eliciting_in_flight(r) {
        False -> None
        True -> pto_time(r, max_ack_delay, handshake_confirmed)
      }
  }
}

/// Handles loss detection timer expiry (RFC 9002 A.9). If a loss_time was
/// set, detects lost packets in the earliest space. Otherwise it is a PTO:
/// `pto_count` is incremented and no packets are marked lost (the caller
/// (re)sends probe data).
pub fn on_loss_timeout(r: Recovery, now: Int) -> LossResult {
  case earliest_loss_time_and_space(r) {
    Some(#(_, space)) -> {
      let #(r, lost) = detect_and_remove_lost(r, space, now)
      LossResult(r, [], lost)
    }
    None -> LossResult(Recovery(..r, pto_count: r.pto_count + 1), [], [])
  }
}

fn earliest_loss_time(r: Recovery) -> Option(Int) {
  case earliest_loss_time_and_space(r) {
    Some(#(time, _)) -> Some(time)
    None -> None
  }
}

fn earliest_loss_time_and_space(r: Recovery) -> Option(#(Int, Space)) {
  list.fold(packet_space.spaces(), None, fn(acc, space) {
    let loss_time = get_space(r, space).loss_time
    case loss_time == 0 {
      True -> acc
      False ->
        case acc {
          Some(#(best, _)) if best <= loss_time -> acc
          _ -> Some(#(loss_time, space))
        }
    }
  })
}

fn pto_time(
  r: Recovery,
  max_ack_delay: Int,
  handshake_confirmed: Bool,
) -> Option(Int) {
  let base = rtt.pto_duration(r.rtt) * pow2(r.pto_count)
  list.fold(packet_space.spaces(), None, fn(acc, space) {
    let state = get_space(r, space)
    case has_ack_eliciting(state), space {
      False, _ -> acc
      // Application Data PTO waits until the handshake is confirmed.
      True, packet_space.ApplicationSpace if !handshake_confirmed -> acc
      True, packet_space.ApplicationSpace -> {
        let duration = base + max_ack_delay * pow2(r.pto_count)
        earlier(acc, state.time_of_last_ack_eliciting + duration)
      }
      True, _ -> earlier(acc, state.time_of_last_ack_eliciting + base)
    }
  })
}

fn earlier(acc: Option(Int), candidate: Int) -> Option(Int) {
  case acc {
    Some(best) -> Some(int.min(best, candidate))
    None -> Some(candidate)
  }
}

fn has_ack_eliciting_in_flight(r: Recovery) -> Bool {
  list.any(packet_space.spaces(), fn(space) {
    has_ack_eliciting(get_space(r, space))
  })
}

fn has_ack_eliciting(state: SpaceState) -> Bool {
  dict.fold(state.sent, False, fn(found, _, packet) {
    found || { packet.in_flight && packet.ack_eliciting }
  })
}

// ─────────────────────────────────────────────────────────────────────────
// Discarding a packet number space (RFC 9002 A.11)
// ─────────────────────────────────────────────────────────────────────────

/// Drops all tracking for a packet number space (on discarding Initial or
/// Handshake keys), removing its packets from bytes-in-flight and resetting
/// the PTO backoff.
pub fn discard_space(r: Recovery, space: Space) -> Recovery {
  let state = get_space(r, space)
  let in_flight_bytes =
    dict.fold(state.sent, 0, fn(acc, _, packet) {
      case packet.in_flight {
        True -> acc + packet.sent_bytes
        False -> acc
      }
    })
  let r =
    Recovery(
      ..r,
      congestion: congestion.on_lost(r.congestion, in_flight_bytes, 0, 0),
      pto_count: 0,
    )
  set_space(r, space, empty_space())
}

// ─────────────────────────────────────────────────────────────────────────
// Space accessors
// ─────────────────────────────────────────────────────────────────────────

fn get_space(r: Recovery, space: Space) -> SpaceState {
  case space {
    packet_space.InitialSpace -> r.initial
    packet_space.HandshakeSpace -> r.handshake
    packet_space.ApplicationSpace -> r.application
  }
}

fn set_space(r: Recovery, space: Space, state: SpaceState) -> Recovery {
  case space {
    packet_space.InitialSpace -> Recovery(..r, initial: state)
    packet_space.HandshakeSpace -> Recovery(..r, handshake: state)
    packet_space.ApplicationSpace -> Recovery(..r, application: state)
  }
}

fn pow2(n: Int) -> Int {
  int.bitwise_shift_left(1, n)
}
