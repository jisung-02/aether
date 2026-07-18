//// TLS 1.3 handshake crypto primitives backed by the OTP `crypto` and
//// `public_key` applications via `aether_tls_ffi`: x25519 key exchange
//// (RFC 8446 Section 4.2.8.2, RFC 7748) and certificate-key signing and
//// verification for the two supported server signature schemes
//// (RFC 8446 Section 4.2.3). All protocol logic outside these
//// primitives stays in pure Gleam.

/// An opaque handle around an Erlang `public_key` private key record
/// (`#'ECPrivateKey'{}` or `#'RSAPrivateKey'{}`), as produced by
/// `decode_pem_private_key` or `rsa_key_from_components`.
pub type SigningKey

/// The server signature schemes this implementation supports
/// (RFC 8446 Section 4.2.3), chosen by the configured key's type.
pub type SignatureScheme {
  EcdsaSecp256r1Sha256
  RsaPssRsaeSha256
}

/// The TLS `SignatureScheme` wire code (RFC 8446 Section 4.2.3).
pub fn scheme_code(scheme: SignatureScheme) -> Int {
  case scheme {
    EcdsaSecp256r1Sha256 -> 0x0403
    RsaPssRsaeSha256 -> 0x0804
  }
}

/// Generates a fresh x25519 key pair. Returns `#(public, private)`.
@external(erlang, "aether_tls_ffi", "x25519_generate")
pub fn x25519_generate() -> #(BitArray, BitArray)

/// Derives the public key for an existing x25519 private key.
@external(erlang, "aether_tls_ffi", "x25519_public")
pub fn x25519_public(private: BitArray) -> BitArray

/// Computes the x25519 shared secret between `peer_public` and
/// `private`. Fails if `peer_public` is not a valid point encoding, or
/// if the resulting shared secret is all-zero — the low-order point
/// check required by RFC 8446 Section 7.4.2.
pub fn x25519_shared(
  peer_public: BitArray,
  private: BitArray,
) -> Result(BitArray, Nil) {
  case x25519_shared_ffi(peer_public, private) {
    Ok(shared) ->
      case is_all_zero(shared) {
        True -> Error(Nil)
        False -> Ok(shared)
      }
    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "aether_tls_ffi", "x25519_shared")
fn x25519_shared_ffi(
  peer_public: BitArray,
  private: BitArray,
) -> Result(BitArray, Nil)

fn is_all_zero(data: BitArray) -> Bool {
  case data {
    <<>> -> True
    <<0, rest:bits>> -> is_all_zero(rest)
    _ -> False
  }
}

/// Returns the signature scheme matching `key`'s type (by Erlang record
/// tag: `#'ECPrivateKey'{}` or `#'RSAPrivateKey'{}`).
@external(erlang, "aether_tls_ffi", "key_scheme")
pub fn key_scheme(key: SigningKey) -> SignatureScheme

/// Signs `message` with `key`. ECDSA keys produce a DER-encoded ECDSA
/// signature over sha256 (TLS scheme `ecdsa_secp256r1_sha256`, 0x0403).
/// RSA keys produce an RSASSA-PSS signature with sha256/MGF1-sha256 and
/// salt length equal to the digest length (TLS scheme
/// `rsa_pss_rsae_sha256`, 0x0804).
@external(erlang, "aether_tls_ffi", "sign")
pub fn sign(key: SigningKey, message: BitArray) -> BitArray

/// Verifies `signature` over `message` against the public key embedded
/// in the DER-encoded certificate `cert_der`, under `scheme`. Any decode
/// failure, algorithm mismatch, or verification failure returns `False`.
@external(erlang, "aether_tls_ffi", "verify_with_certificate")
pub fn verify_with_certificate(
  cert_der: BitArray,
  scheme: SignatureScheme,
  message: BitArray,
  signature: BitArray,
) -> Bool

/// Decodes every certificate entry from a PEM file, in file order, as
/// raw DER bytes. `Error(Nil)` if the PEM contains no certificates.
@external(erlang, "aether_tls_ffi", "decode_pem_certificates")
pub fn decode_pem_certificates(pem: BitArray) -> Result(List(BitArray), Nil)

/// Decodes the first unencrypted private key entry from a PEM file —
/// PKCS#8 (`PrivateKeyInfo`) or legacy EC/RSA PEM are all accepted.
/// `Error(Nil)` on any decode failure or if the PEM holds no private
/// key.
@external(erlang, "aether_tls_ffi", "decode_pem_private_key")
pub fn decode_pem_private_key(pem: BitArray) -> Result(SigningKey, Nil)

/// Builds an RSA signing key from its raw components. Test support
/// only: used to construct the RFC 8448 server key from the RFC's
/// published RSA parameters, which are not distributed as a PEM file.
@external(erlang, "aether_tls_ffi", "rsa_key_from_components")
pub fn rsa_key_from_components(
  n: BitArray,
  e: BitArray,
  d: BitArray,
  p: BitArray,
  q: BitArray,
  e1: BitArray,
  e2: BitArray,
  c: BitArray,
) -> SigningKey
