//// QUIC packet protection key derivation (RFC 9001 Section 5.1-5.2):
//// per-direction key/IV/header-protection-key sets, the v1 Initial
//// secrets, and AEAD nonce construction.

import aether/protocol/quic/crypto.{type Aead, Aes128Gcm}
import aether/protocol/quic/hkdf
import gleam/int

/// The keys protecting packets in one direction at one encryption level.
pub type PacketKeys {
  PacketKeys(aead: Aead, key: BitArray, iv: BitArray, hp: BitArray)
}

/// The QUIC v1 initial salt (RFC 9001 Section 5.2).
pub const initial_salt = <<
  0x38, 0x76, 0x2c, 0xf7, 0xf5, 0x59, 0x34, 0xb3, 0x4d, 0x17, 0x9a, 0xe6, 0xa4,
  0xc8, 0x0c, 0xad, 0xcc, 0xbb, 0x7f, 0x0a,
>>

/// Derives the client and server Initial packet keys from the client's
/// first Destination Connection ID. Returns `#(client_keys, server_keys)`.
/// Initial packets always use AES-128-GCM.
pub fn initial_keys(dcid: BitArray) -> #(PacketKeys, PacketKeys) {
  let initial_secret = hkdf.extract(salt: initial_salt, ikm: dcid)
  let client_secret = hkdf.expand_label(initial_secret, "client in", <<>>, 32)
  let server_secret = hkdf.expand_label(initial_secret, "server in", <<>>, 32)
  #(
    from_secret(Aes128Gcm, client_secret),
    from_secret(Aes128Gcm, server_secret),
  )
}

/// Derives a key/IV/header-protection-key set from a traffic secret
/// using the "quic key" / "quic iv" / "quic hp" labels (RFC 9001
/// Section 5.1).
pub fn from_secret(aead: Aead, secret: BitArray) -> PacketKeys {
  let key_len = crypto.key_length(aead)
  PacketKeys(
    aead: aead,
    key: hkdf.expand_label(secret, "quic key", <<>>, key_len),
    iv: hkdf.expand_label(secret, "quic iv", <<>>, 12),
    hp: hkdf.expand_label(secret, "quic hp", <<>>, key_len),
  )
}

/// Builds the AEAD nonce for a packet: the 12-byte IV XORed with the
/// full packet number in network byte order (RFC 9001 Section 5.3).
pub fn nonce(iv: BitArray, packet_number: Int) -> BitArray {
  case iv {
    <<iv_int:96>> -> <<int.bitwise_exclusive_or(iv_int, packet_number):96>>
    // IVs are always 12 bytes by construction in `from_secret`.
    _ -> iv
  }
}
