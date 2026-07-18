//// A record of a packet this endpoint has sent, retained for loss
//// detection (RFC 9002). On loss, `frames` is what to retransmit; ACK-
//// only packets carry no frames and are not ack-eliciting.

import aether/protocol/quic/frame.{type Frame}

/// One sent packet awaiting acknowledgement.
///
/// `in_flight` is true when the packet counts toward bytes-in-flight (it
/// carried an ack-eliciting or PADDING frame); `sent_bytes` is its size
/// including QUIC header and AEAD overhead but not IP/UDP overhead.
pub type SentPacket {
  SentPacket(
    packet_number: Int,
    time_sent: Int,
    ack_eliciting: Bool,
    in_flight: Bool,
    sent_bytes: Int,
    frames: List(Frame),
  )
}
