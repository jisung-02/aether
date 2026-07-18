//// QUIC packet number spaces (RFC 9000 Section 12.3, RFC 9002 Section 2).
////
//// Each space tracks packet numbers, acknowledgements, and loss detection
//// state independently: Initial, Handshake, and Application data (0-RTT and
//// 1-RTT share the Application space for recovery purposes).

/// The three packet number spaces a QUIC connection tracks.
pub type Space {
  InitialSpace
  HandshakeSpace
  ApplicationSpace
}

/// Returns the three spaces in the order they are established:
/// Initial, then Handshake, then Application.
pub fn spaces() -> List(Space) {
  [InitialSpace, HandshakeSpace, ApplicationSpace]
}
