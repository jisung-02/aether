//// AEAD and header protection primitives for QUIC packet protection
//// (RFC 9001 Section 5), backed by the OTP crypto application via
//// `aether_quic_crypto_ffi`. This module is the only crypto FFI surface;
//// all protocol logic stays in pure Gleam.

/// The AEAD ciphers usable for QUIC v1 packet protection (RFC 9001
/// Section 5.3). AES-128-CCM is deliberately unsupported.
pub type Aead {
  Aes128Gcm
  Aes256Gcm
  Chacha20Poly1305
}

/// Key length in bytes for both the AEAD key and the header protection
/// key of a cipher.
pub fn key_length(aead: Aead) -> Int {
  case aead {
    Aes128Gcm -> 16
    Aes256Gcm -> 32
    Chacha20Poly1305 -> 32
  }
}

/// AEAD authentication tag length in bytes (16 for all QUIC ciphers).
pub const tag_length = 16

/// Seals `plaintext`, returning `#(ciphertext, tag)`.
@external(erlang, "aether_quic_crypto_ffi", "aead_encrypt")
pub fn aead_encrypt(
  aead: Aead,
  key: BitArray,
  nonce: BitArray,
  aad: BitArray,
  plaintext: BitArray,
) -> #(BitArray, BitArray)

/// Opens `ciphertext`, verifying `tag`. Fails on authentication failure.
@external(erlang, "aether_quic_crypto_ffi", "aead_decrypt")
pub fn aead_decrypt(
  aead: Aead,
  key: BitArray,
  nonce: BitArray,
  aad: BitArray,
  ciphertext: BitArray,
  tag: BitArray,
) -> Result(BitArray, Nil)

/// Computes the 5-byte header protection mask from a 16-byte sample of
/// protected payload (RFC 9001 Section 5.4).
@external(erlang, "aether_quic_crypto_ffi", "hp_mask")
pub fn hp_mask(aead: Aead, hp_key: BitArray, sample: BitArray) -> BitArray
