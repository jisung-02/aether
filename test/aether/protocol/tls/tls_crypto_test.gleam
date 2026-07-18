//// Tests for `aether/protocol/tls/tls_crypto`: x25519 key exchange
//// against the RFC 8448 trace, RSA-PSS and ECDSA sign/verify against
//// both the RFC 8448 RSA key and the committed EC P-256 fixture, and
//// PEM decoding (both the happy path and the "wrong content" cases).

import aether/protocol/tls/rfc8448_vectors
import aether/protocol/tls/tls_crypto.{EcdsaSecp256r1Sha256, RsaPssRsaeSha256}
import gleam/bit_array
import gleeunit/should

fn hex(s: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(s)
  bytes
}

@external(erlang, "aether_tls_ffi", "read_file")
fn read_file(path: String) -> Result(BitArray, Nil)

fn read_fixture(path: String) -> BitArray {
  let assert Ok(bytes) = read_file(path)
  bytes
}

// RFC 8448 Section 3 Certificate message is: 4-byte handshake header,
// 1-byte request context length (0), 3-byte certificate_list length,
// 3-byte cert_data length, the DER certificate itself (tag + length +
// content, 432 bytes), then 2 trailing per-certificate extensions-length
// bytes (0000). The DER cert therefore starts at offset 11.
fn rfc8448_certificate_der() -> BitArray {
  let assert Ok(der) =
    bit_array.slice(hex(rfc8448_vectors.certificate), 11, 432)
  der
}

pub fn x25519_public_from_client_private_test() {
  tls_crypto.x25519_public(hex(rfc8448_vectors.client_ephemeral_private))
  |> should.equal(hex(rfc8448_vectors.client_ephemeral_public))
}

pub fn x25519_public_from_server_private_test() {
  tls_crypto.x25519_public(hex(rfc8448_vectors.server_ephemeral_private))
  |> should.equal(hex(rfc8448_vectors.server_ephemeral_public))
}

pub fn x25519_shared_client_side_test() {
  tls_crypto.x25519_shared(
    hex(rfc8448_vectors.server_ephemeral_public),
    hex(rfc8448_vectors.client_ephemeral_private),
  )
  |> should.equal(Ok(hex(rfc8448_vectors.ecdhe_shared_secret)))
}

pub fn x25519_shared_server_side_test() {
  tls_crypto.x25519_shared(
    hex(rfc8448_vectors.client_ephemeral_public),
    hex(rfc8448_vectors.server_ephemeral_private),
  )
  |> should.equal(Ok(hex(rfc8448_vectors.ecdhe_shared_secret)))
}

pub fn x25519_shared_low_order_point_is_error_test() {
  let all_zero = <<
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
  >>
  tls_crypto.x25519_shared(
    all_zero,
    hex(rfc8448_vectors.client_ephemeral_private),
  )
  |> should.equal(Error(Nil))
}

fn rfc8448_rsa_key() {
  tls_crypto.rsa_key_from_components(
    hex(rfc8448_vectors.rsa_n),
    hex(rfc8448_vectors.rsa_e),
    hex(rfc8448_vectors.rsa_d),
    hex(rfc8448_vectors.rsa_p),
    hex(rfc8448_vectors.rsa_q),
    hex(rfc8448_vectors.rsa_e1),
    hex(rfc8448_vectors.rsa_e2),
    hex(rfc8448_vectors.rsa_c),
  )
}

pub fn rsa_key_from_components_scheme_test() {
  tls_crypto.key_scheme(rfc8448_rsa_key())
  |> should.equal(RsaPssRsaeSha256)
}

pub fn rsa_sign_verify_round_trip_test() {
  let key = rfc8448_rsa_key()
  let message = <<"the quick brown fox":utf8>>
  let signature = tls_crypto.sign(key, message)
  tls_crypto.verify_with_certificate(
    rfc8448_certificate_der(),
    RsaPssRsaeSha256,
    message,
    signature,
  )
  |> should.be_true()
}

pub fn rsa_sign_verify_tampered_message_is_false_test() {
  let key = rfc8448_rsa_key()
  let signature = tls_crypto.sign(key, <<"the quick brown fox":utf8>>)
  tls_crypto.verify_with_certificate(
    rfc8448_certificate_der(),
    RsaPssRsaeSha256,
    <<"the quick brown FOX":utf8>>,
    signature,
  )
  |> should.be_false()
}

pub fn decode_pem_certificates_fixture_test() {
  let cert_pem = read_fixture("test/fixtures/tls/cert.pem")
  let assert Ok(certs) = tls_crypto.decode_pem_certificates(cert_pem)
  certs |> should.equal([extract_ec_fixture_der(certs)])
}

// Sanity helper: asserts there is exactly one certificate and returns
// it, so the equality check above is also a length check.
fn extract_ec_fixture_der(certs: List(BitArray)) -> BitArray {
  case certs {
    [only] -> only
    _ -> panic as "expected exactly one certificate in cert.pem"
  }
}

pub fn decode_pem_private_key_fixture_scheme_test() {
  let key_pem = read_fixture("test/fixtures/tls/key.pem")
  let assert Ok(key) = tls_crypto.decode_pem_private_key(key_pem)
  tls_crypto.key_scheme(key) |> should.equal(EcdsaSecp256r1Sha256)
}

pub fn ecdsa_sign_verify_round_trip_test() {
  let key_pem = read_fixture("test/fixtures/tls/key.pem")
  let cert_pem = read_fixture("test/fixtures/tls/cert.pem")
  let assert Ok(key) = tls_crypto.decode_pem_private_key(key_pem)
  let assert Ok([cert_der]) = tls_crypto.decode_pem_certificates(cert_pem)
  let message = <<"the quick brown fox":utf8>>
  let signature = tls_crypto.sign(key, message)
  tls_crypto.verify_with_certificate(
    cert_der,
    EcdsaSecp256r1Sha256,
    message,
    signature,
  )
  |> should.be_true()
}

pub fn ecdsa_sign_verify_tampered_message_is_false_test() {
  let key_pem = read_fixture("test/fixtures/tls/key.pem")
  let cert_pem = read_fixture("test/fixtures/tls/cert.pem")
  let assert Ok(key) = tls_crypto.decode_pem_private_key(key_pem)
  let assert Ok([cert_der]) = tls_crypto.decode_pem_certificates(cert_pem)
  let signature = tls_crypto.sign(key, <<"the quick brown fox":utf8>>)
  tls_crypto.verify_with_certificate(
    cert_der,
    EcdsaSecp256r1Sha256,
    <<"the quick brown FOX":utf8>>,
    signature,
  )
  |> should.be_false()
}

pub fn decode_pem_private_key_rejects_non_pem_test() {
  tls_crypto.decode_pem_private_key(bit_array.from_string("not pem"))
  |> should.equal(Error(Nil))
}

pub fn decode_pem_certificates_rejects_private_key_pem_test() {
  let key_pem = read_fixture("test/fixtures/tls/key.pem")
  tls_crypto.decode_pem_certificates(key_pem)
  |> should.equal(Error(Nil))
}
