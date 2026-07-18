//// Round-trip time estimation (RFC 9002 Section 5).
////
//// All times and durations are microseconds represented as `Int`. Estimation
//// uses only integer arithmetic (the standard RFC 9002 EWMA forms), never
//// floats.

import gleam/int

/// The initial RTT estimate used before any sample has been observed
/// (333 ms, in microseconds).
pub const initial_rtt = 333_000

/// The system timer granularity used as a floor for the PTO calculation
/// (1 ms, in microseconds).
pub const granularity = 1000

/// A round-trip time estimator: the latest sample, the minimum observed
/// RTT, the smoothed RTT, and the RTT variation, all in microseconds.
pub opaque type Rtt {
  Rtt(latest: Int, min: Int, smoothed: Int, rttvar: Int, has_sample: Bool)
}

/// Creates a new estimator with no samples yet, seeded with `initial_rtt`
/// per RFC 9002 Section 5.1.
pub fn new() -> Rtt {
  Rtt(
    latest: 0,
    min: 0,
    smoothed: initial_rtt,
    rttvar: initial_rtt / 2,
    has_sample: False,
  )
}

/// Records a new RTT sample (RFC 9002 Section 5.3).
///
/// `latest` is the measured round-trip time for the acknowledged packet,
/// `ack_delay` is the peer-reported delay before sending the ack, and
/// `max_ack_delay` is the peer's advertised maximum ack delay. Once the
/// handshake is confirmed, `ack_delay` is capped by `max_ack_delay` per the
/// RFC; before that, the peer's ack delay is trusted as reported.
///
/// The first sample seeds `min` and `smoothed` directly. Later samples
/// update `min`, adjust for ack delay (guarded so the adjustment can never
/// push the sample below `min`), and fold the result into `smoothed` and
/// `rttvar` via the RFC's integer EWMAs.
pub fn update(
  rtt: Rtt,
  latest: Int,
  ack_delay: Int,
  max_ack_delay: Int,
  handshake_confirmed: Bool,
) -> Rtt {
  case rtt.has_sample {
    False ->
      Rtt(
        latest: latest,
        min: latest,
        smoothed: latest,
        rttvar: latest / 2,
        has_sample: True,
      )
    True -> {
      let min = int.min(rtt.min, latest)
      let ack_delay = case handshake_confirmed {
        True -> int.min(ack_delay, max_ack_delay)
        False -> ack_delay
      }
      let adjusted = case latest >= min + ack_delay {
        True -> latest - ack_delay
        False -> latest
      }
      let rttvar =
        rtt.rttvar
        - rtt.rttvar
        / 4
        + int.absolute_value(rtt.smoothed - adjusted)
        / 4
      let smoothed = rtt.smoothed - rtt.smoothed / 8 + adjusted / 8
      Rtt(
        latest: latest,
        min: min,
        smoothed: smoothed,
        rttvar: rttvar,
        has_sample: True,
      )
    }
  }
}

/// The smoothed round-trip time estimate, in microseconds.
pub fn smoothed(rtt: Rtt) -> Int {
  rtt.smoothed
}

/// The round-trip time variation estimate, in microseconds.
pub fn rttvar(rtt: Rtt) -> Int {
  rtt.rttvar
}

/// The minimum round-trip time observed so far, in microseconds.
pub fn min(rtt: Rtt) -> Int {
  rtt.min
}

/// The most recently recorded round-trip time sample, in microseconds.
pub fn latest(rtt: Rtt) -> Int {
  rtt.latest
}

/// Whether at least one RTT sample has been recorded.
pub fn has_sample(rtt: Rtt) -> Bool {
  rtt.has_sample
}

/// The base probe timeout duration (RFC 9002 Section 6.2.1), in
/// microseconds: `smoothed + max(4 * rttvar, granularity)`. The caller adds
/// `max_ack_delay` and applies the `2^pto_count` backoff.
pub fn pto_duration(rtt: Rtt) -> Int {
  rtt.smoothed + int.max(4 * rtt.rttvar, granularity)
}
