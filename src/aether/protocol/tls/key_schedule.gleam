//// TLS 1.3 key schedule (RFC 8446 Section 7.1), SHA-256 only, built on
//// the phase 2 QUIC HKDF primitives in `aether/protocol/quic/hkdf`.
////
//// QUIC carries the TLS handshake without a record layer, but the key
//// schedule itself is unchanged from RFC 8446: a chain of HKDF-Extract
//// and Derive-Secret (HKDF-Expand-Label) calls threaded through a
//// running transcript hash of the handshake messages.

import aether/protocol/quic/hkdf
import gleam/crypto

/// A running SHA-256 hash of the handshake messages seen so far, used as
/// the `transcript_hash` input to `derive_secret`. Wraps `gleam/crypto`'s
/// incremental hasher.
pub type Transcript {
  Transcript(hasher: crypto.Hasher)
}

/// Starts a new, empty transcript.
pub fn new_transcript() -> Transcript {
  Transcript(crypto.new_hasher(crypto.Sha256))
}

/// Appends a handshake message to the transcript. `message` is the full
/// handshake message encoding, including the 4-byte
/// type/length header (see `handshake_message.encode`).
pub fn add(transcript: Transcript, message: BitArray) -> Transcript {
  Transcript(crypto.hash_chunk(transcript.hasher, message))
}

/// Returns the transcript hash so far. Does not consume the transcript:
/// more messages can still be added afterwards.
pub fn hash(transcript: Transcript) -> BitArray {
  crypto.digest(transcript.hasher)
}

/// SHA-256 of the empty string, the transcript hash context used when
/// deriving the `derived` secrets that chain the early/handshake/master
/// secrets together (RFC 8446 Section 7.1).
fn empty_hash() -> BitArray {
  crypto.hash(crypto.Sha256, <<>>)
}

/// RFC 8446 Section 7.1 Derive-Secret:
/// `Derive-Secret(Secret, Label, Messages) =
///   HKDF-Expand-Label(Secret, Label, Transcript-Hash(Messages), 32)`.
pub fn derive_secret(
  secret: BitArray,
  label: String,
  transcript_hash: BitArray,
) -> BitArray {
  hkdf.expand_label(
    secret: secret,
    label: label,
    context: transcript_hash,
    length: 32,
  )
}

/// The early secret, with no external or resumption PSK:
/// `Extract(salt: 00.., ikm: 00..)` over 32 zero bytes.
pub fn early_secret() -> BitArray {
  hkdf.extract(salt: <<0:size(256)>>, ikm: <<0:size(256)>>)
}

/// The handshake secret:
/// `Extract(Derive-Secret(early, "derived", ""), ecdhe)`.
pub fn handshake_secret(early: BitArray, ecdhe: BitArray) -> BitArray {
  hkdf.extract(salt: derive_secret(early, "derived", empty_hash()), ikm: ecdhe)
}

/// The master secret:
/// `Extract(Derive-Secret(handshake, "derived", ""), 00..)` over 32 zero
/// bytes.
pub fn master_secret(handshake: BitArray) -> BitArray {
  hkdf.extract(salt: derive_secret(handshake, "derived", empty_hash()), ikm: <<
    0:size(256),
  >>)
}

/// Client handshake traffic secret:
/// `Derive-Secret(handshake, "c hs traffic", Transcript(CH..SH))`.
pub fn client_hs_traffic(
  secret: BitArray,
  transcript_hash: BitArray,
) -> BitArray {
  derive_secret(secret, "c hs traffic", transcript_hash)
}

/// Server handshake traffic secret:
/// `Derive-Secret(handshake, "s hs traffic", Transcript(CH..SH))`.
pub fn server_hs_traffic(
  secret: BitArray,
  transcript_hash: BitArray,
) -> BitArray {
  derive_secret(secret, "s hs traffic", transcript_hash)
}

/// Client application traffic secret:
/// `Derive-Secret(master, "c ap traffic", Transcript(CH..server Finished))`.
pub fn client_ap_traffic(
  secret: BitArray,
  transcript_hash: BitArray,
) -> BitArray {
  derive_secret(secret, "c ap traffic", transcript_hash)
}

/// Server application traffic secret:
/// `Derive-Secret(master, "s ap traffic", Transcript(CH..server Finished))`.
pub fn server_ap_traffic(
  secret: BitArray,
  transcript_hash: BitArray,
) -> BitArray {
  derive_secret(secret, "s ap traffic", transcript_hash)
}

/// The per-message MAC key for a Finished message:
/// `Expand-Label(traffic_secret, "finished", "", 32)`.
pub fn finished_key(traffic_secret: BitArray) -> BitArray {
  hkdf.expand_label(
    secret: traffic_secret,
    label: "finished",
    context: <<>>,
    length: 32,
  )
}

/// The Finished message `verify_data`:
/// `HMAC(finished_key(traffic_secret), transcript_hash)`.
pub fn finished_verify_data(
  traffic_secret: BitArray,
  transcript_hash: BitArray,
) -> BitArray {
  crypto.hmac(transcript_hash, crypto.Sha256, finished_key(traffic_secret))
}
