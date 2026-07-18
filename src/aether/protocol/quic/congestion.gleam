//// NewReno congestion control (RFC 9002 Section 7 and Appendix B).
//// Pure state transitions over integer byte counts and microsecond
//// times; the caller supplies `now` and decides when to send.

import gleam/int

/// The minimum permitted max_datagram_size (RFC 9002 B.2).
pub const min_datagram_size = 1200

/// Sentinel for an infinite slow-start threshold (before the first loss).
const ssthresh_infinite = -1

/// NewReno controller state.
pub opaque type Congestion {
  Congestion(
    window: Int,
    bytes_in_flight: Int,
    ssthresh: Int,
    recovery_start_time: Int,
    max_datagram_size: Int,
  )
}

/// The initial congestion window (RFC 9002 Section 7.2):
/// min(10*mds, max(2*mds, 14720)).
pub fn initial_window(max_datagram_size: Int) -> Int {
  int.min(10 * max_datagram_size, int.max(2 * max_datagram_size, 14_720))
}

/// The minimum congestion window (RFC 9002 Section 7.2): 2*mds.
pub fn minimum_window(max_datagram_size: Int) -> Int {
  2 * max_datagram_size
}

/// A fresh controller for the given path max datagram size.
pub fn new(max_datagram_size: Int) -> Congestion {
  Congestion(
    window: initial_window(max_datagram_size),
    bytes_in_flight: 0,
    ssthresh: ssthresh_infinite,
    recovery_start_time: 0,
    max_datagram_size: max_datagram_size,
  )
}

/// Records that an in-flight packet of `sent_bytes` was sent.
pub fn on_sent(c: Congestion, sent_bytes: Int) -> Congestion {
  Congestion(..c, bytes_in_flight: c.bytes_in_flight + sent_bytes)
}

/// Applies acknowledgement of one in-flight packet (RFC 9002 B.5). Only
/// call this for packets with `in_flight` true. `app_limited` suppresses
/// window growth when the sender was not actually cwnd-limited.
pub fn on_acked(
  c: Congestion,
  sent_bytes: Int,
  time_sent: Int,
  app_limited: Bool,
) -> Congestion {
  let c = Congestion(..c, bytes_in_flight: c.bytes_in_flight - sent_bytes)
  case app_limited || in_recovery(c, time_sent) {
    True -> c
    False ->
      case c.window < effective_ssthresh(c) {
        // Slow start.
        True -> Congestion(..c, window: c.window + sent_bytes)
        // Congestion avoidance.
        False ->
          Congestion(
            ..c,
            window: c.window + c.max_datagram_size * sent_bytes / c.window,
          )
      }
  }
}

/// Enters a recovery period on a new congestion event (RFC 9002 B.6):
/// halves ssthresh and the window. No effect if `sent_time` is within the
/// current recovery period.
pub fn on_congestion_event(
  c: Congestion,
  sent_time: Int,
  now: Int,
) -> Congestion {
  case in_recovery(c, sent_time) {
    True -> c
    False -> {
      let ssthresh = c.window / 2
      Congestion(
        ..c,
        recovery_start_time: now,
        ssthresh: ssthresh,
        window: int.max(ssthresh, minimum_window(c.max_datagram_size)),
      )
    }
  }
}

/// Removes lost in-flight bytes and, if any in-flight packet was lost,
/// triggers a congestion event at the latest lost packet's send time
/// (RFC 9002 B.8). Pass `lost_bytes`/`latest_loss_time` of 0 when nothing
/// in-flight was lost.
pub fn on_lost(
  c: Congestion,
  lost_bytes: Int,
  latest_loss_time: Int,
  now: Int,
) -> Congestion {
  let c = Congestion(..c, bytes_in_flight: c.bytes_in_flight - lost_bytes)
  case latest_loss_time == 0 {
    True -> c
    False -> on_congestion_event(c, latest_loss_time, now)
  }
}

/// The current congestion window in bytes.
pub fn window(c: Congestion) -> Int {
  c.window
}

/// Bytes currently in flight.
pub fn bytes_in_flight(c: Congestion) -> Int {
  c.bytes_in_flight
}

/// Bytes that may still be sent under the window.
pub fn available(c: Congestion) -> Int {
  int.max(0, c.window - c.bytes_in_flight)
}

/// The slow-start threshold, or -1 if still infinite.
pub fn ssthresh(c: Congestion) -> Int {
  c.ssthresh
}

fn in_recovery(c: Congestion, sent_time: Int) -> Bool {
  sent_time <= c.recovery_start_time
}

// Infinite ssthresh means we are always below it (always slow start).
fn effective_ssthresh(c: Congestion) -> Int {
  case c.ssthresh == ssthresh_infinite {
    True -> c.window + 1
    False -> c.ssthresh
  }
}
