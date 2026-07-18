//// Connection-level flow control (RFC 9000 Section 4.1).
////
//// Two independent limits track flow control for a single direction of a
//// connection: `SendLimit` bounds how much we may send, governed by the
//// peer's MAX_DATA; `RecvLimit` bounds how much the peer may send us, and
//// decides when to grant more credit via an outgoing MAX_DATA frame. All
//// values are absolute byte counts (offsets), as `Int`.

import gleam/int
import gleam/option.{type Option, None, Some}

/// The send-side flow control state: the absolute limit granted by the
/// peer (`max_data`) and the absolute number of bytes sent so far
/// (`data_sent`). Invariant: `data_sent <= max_data`.
pub opaque type SendLimit {
  SendLimit(max_data: Int, data_sent: Int)
}

/// Creates a new send limit with no bytes sent yet, bounded by the peer's
/// initial MAX_DATA transport parameter.
pub fn new_send(initial_max: Int) -> SendLimit {
  SendLimit(max_data: initial_max, data_sent: 0)
}

/// Applies a MAX_DATA frame from the peer. MAX_DATA values are only ever
/// increasing per RFC 9000 Section 4.1; a value lower than the current
/// limit is ignored rather than shrinking the window.
pub fn on_max_data(s: SendLimit, max_data: Int) -> SendLimit {
  SendLimit(..s, max_data: int.max(s.max_data, max_data))
}

/// Records that `bytes` more have been sent. Returns `Error(Nil)` without
/// updating the state if doing so would exceed `max_data`.
pub fn record_sent(s: SendLimit, bytes: Int) -> Result(SendLimit, Nil) {
  case s.data_sent + bytes > s.max_data {
    True -> Error(Nil)
    False -> Ok(SendLimit(..s, data_sent: s.data_sent + bytes))
  }
}

/// The number of bytes still available to send before hitting the peer's
/// limit.
pub fn send_available(s: SendLimit) -> Int {
  s.max_data - s.data_sent
}

/// The receive-side flow control state: the absolute limit we've granted
/// the peer (`max_data`), the highest absolute offset seen so far in
/// received data (`highest_received`), the absolute number of bytes
/// delivered to the application (`consumed`), and the credit window size
/// used to decide when to extend `max_data`.
pub opaque type RecvLimit {
  RecvLimit(max_data: Int, highest_received: Int, consumed: Int, window: Int)
}

/// Creates a new receive limit granting `initial_max` bytes of credit, and
/// using that same amount as the auto-credit window size for later
/// extensions.
pub fn new_recv(initial_max: Int) -> RecvLimit {
  RecvLimit(
    max_data: initial_max,
    highest_received: 0,
    consumed: 0,
    window: initial_max,
  )
}

/// Records the highest absolute offset seen in data received from the
/// peer. Returns `Error(Nil)` (a `FlowControlError` in RFC 9000 terms)
/// without updating the state if `highest_offset` exceeds the granted
/// `max_data`.
pub fn record_received(
  r: RecvLimit,
  highest_offset: Int,
) -> Result(RecvLimit, Nil) {
  case highest_offset > r.max_data {
    True -> Error(Nil)
    False ->
      Ok(
        RecvLimit(
          ..r,
          highest_received: int.max(r.highest_received, highest_offset),
        ),
      )
  }
}

/// Marks `bytes` more as delivered to the application. Drives
/// `maybe_extend`'s decision to grant more credit.
pub fn consume(r: RecvLimit, bytes: Int) -> RecvLimit {
  RecvLimit(..r, consumed: r.consumed + bytes)
}

/// Decides whether to extend the receive credit window. Once `consumed`
/// passes half the window since the last grant, grants a new window of
/// `window` bytes ahead of `consumed` and returns the updated limit plus
/// `Some(new_max)` to send in a MAX_DATA frame. Otherwise returns the
/// limit unchanged and `None`.
pub fn maybe_extend(r: RecvLimit) -> #(RecvLimit, Option(Int)) {
  case r.consumed > r.max_data - r.window / 2 {
    True -> {
      let new_max = r.consumed + r.window
      #(RecvLimit(..r, max_data: new_max), Some(new_max))
    }
    False -> #(r, None)
  }
}

/// The absolute limit currently granted to the peer.
pub fn recv_max_data(r: RecvLimit) -> Int {
  r.max_data
}
