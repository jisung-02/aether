import aether/protocol/quic/hkdf
import gleam/bit_array
import gleam/crypto
import gleeunit/should

fn hex(string: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(string)
  bytes
}

// RFC 9001 Appendix A.1 lists the exact serialized HkdfLabel bytes fed to
// HKDF-Expand for each derivation.

pub fn hkdf_label_client_in_test() {
  hkdf.hkdf_label("client in", <<>>, 32)
  |> should.equal(hex("00200f746c73313320636c69656e7420696e00"))
}

pub fn hkdf_label_server_in_test() {
  hkdf.hkdf_label("server in", <<>>, 32)
  |> should.equal(hex("00200f746c7331332073657276657220696e00"))
}

pub fn hkdf_label_quic_key_test() {
  hkdf.hkdf_label("quic key", <<>>, 16)
  |> should.equal(hex("00100e746c7331332071756963206b657900"))
}

pub fn hkdf_label_quic_iv_test() {
  hkdf.hkdf_label("quic iv", <<>>, 12)
  |> should.equal(hex("000c0d746c733133207175696320697600"))
}

pub fn hkdf_label_quic_hp_test() {
  hkdf.hkdf_label("quic hp", <<>>, 16)
  |> should.equal(hex("00100d746c733133207175696320687000"))
}

// RFC 9001 A.1: initial_secret = HKDF-Extract(initial_salt, client dcid).

pub fn extract_initial_secret_test() {
  hkdf.extract(
    salt: hex("38762cf7f55934b34d179ae6a4c80cadccbb7f0a"),
    ikm: hex("8394c8f03e515708"),
  )
  |> should.equal(hex(
    "7db5df06e7a69e432496adedb00851923595221596ae2ae9fb8115c1e9ed0a44",
  ))
}

// Multi-block expand, checked against the RFC 5869 block chaining
// definition computed directly with HMAC.

pub fn expand_multi_block_test() {
  let prk = hkdf.extract(salt: <<1, 2, 3>>, ikm: <<4, 5, 6>>)
  let info = <<"some info":utf8>>

  let block1 = crypto.hmac(<<info:bits, 1:8>>, crypto.Sha256, prk)
  let block2 =
    crypto.hmac(<<block1:bits, info:bits, 2:8>>, crypto.Sha256, prk)

  hkdf.expand(prk: prk, info: info, length: 64)
  |> should.equal(<<block1:bits, block2:bits>>)
}

pub fn expand_truncates_final_block_test() {
  let prk = hkdf.extract(salt: <<1>>, ikm: <<2>>)
  let okm = hkdf.expand(prk: prk, info: <<>>, length: 42)

  bit_array.byte_size(okm) |> should.equal(42)
  bit_array.slice(hkdf.expand(prk: prk, info: <<>>, length: 64), 0, 42)
  |> should.equal(Ok(okm))
}
