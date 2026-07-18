//// HKDF with SHA-256 (RFC 5869) and the TLS 1.3 HKDF-Expand-Label
//// construction (RFC 8446 Section 7.1), as used by QUIC key derivation
//// (RFC 9001 Section 5.1). Pure Gleam over `gleam/crypto.hmac`.

import gleam/bit_array
import gleam/crypto

/// HKDF-Extract: derives a pseudorandom key from `salt` and input keying
/// material.
pub fn extract(salt salt: BitArray, ikm ikm: BitArray) -> BitArray {
  crypto.hmac(ikm, crypto.Sha256, salt)
}

/// HKDF-Expand: derives `length` bytes of output keying material from a
/// pseudorandom key. `length` must be at most 255 * 32.
pub fn expand(prk prk: BitArray, info info: BitArray, length length: Int) -> BitArray {
  expand_loop(prk, info, length, 1, <<>>, <<>>)
}

fn expand_loop(
  prk: BitArray,
  info: BitArray,
  length: Int,
  counter: Int,
  previous: BitArray,
  acc: BitArray,
) -> BitArray {
  case bit_array.byte_size(acc) >= length {
    True -> {
      case bit_array.slice(acc, 0, length) {
        Ok(okm) -> okm
        // Unreachable: acc is always at least `length` bytes here.
        Error(Nil) -> acc
      }
    }
    False -> {
      let block =
        crypto.hmac(
          <<previous:bits, info:bits, counter:8>>,
          crypto.Sha256,
          prk,
        )
      expand_loop(prk, info, length, counter + 1, block, <<
        acc:bits,
        block:bits,
      >>)
    }
  }
}

/// TLS 1.3 HKDF-Expand-Label: expands with the HkdfLabel structure
/// `length || "tls13 " + label || context`.
pub fn expand_label(
  secret secret: BitArray,
  label label: String,
  context context: BitArray,
  length length: Int,
) -> BitArray {
  expand(secret, hkdf_label(label, context, length), length)
}

/// Builds the serialized HkdfLabel structure (exposed for testing
/// against the RFC 9001 A.1 label bytes).
pub fn hkdf_label(label: String, context: BitArray, length: Int) -> BitArray {
  let label_bytes = bit_array.from_string("tls13 " <> label)
  <<
    length:16,
    bit_array.byte_size(label_bytes):8,
    label_bytes:bits,
    bit_array.byte_size(context):8,
    context:bits,
  >>
}
