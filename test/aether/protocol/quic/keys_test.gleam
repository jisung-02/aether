import aether/protocol/quic/crypto.{Aes128Gcm, Chacha20Poly1305}
import aether/protocol/quic/keys.{PacketKeys}
import gleam/bit_array
import gleeunit/should

fn hex(string: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(string)
  bytes
}

// RFC 9001 Appendix A.1: full Initial key schedule for the client-chosen
// DCID 0x8394c8f03e515708.

pub fn initial_keys_client_test() {
  let #(client, _server) = keys.initial_keys(hex("8394c8f03e515708"))

  client
  |> should.equal(PacketKeys(
    aead: Aes128Gcm,
    key: hex("1f369613dd76d5467730efcbe3b1a22d"),
    iv: hex("fa044b2f42a3fd3b46fb255c"),
    hp: hex("9f50449e04a0e810283a1e9933adedd2"),
  ))
}

pub fn initial_keys_server_test() {
  let #(_client, server) = keys.initial_keys(hex("8394c8f03e515708"))

  server
  |> should.equal(PacketKeys(
    aead: Aes128Gcm,
    key: hex("cf3a5331653c364c88f0f379b6067e37"),
    iv: hex("0ac1493ca1905853b0bba03e"),
    hp: hex("c206b8d9b9f0f37644430b490eeaa314"),
  ))
}

// RFC 9001 Appendix A.5: ChaCha20-Poly1305 key derivation from an
// application write secret (32-byte key and hp key).

pub fn from_secret_chacha20_test() {
  keys.from_secret(
    Chacha20Poly1305,
    hex("9ac312a7f877468ebe69422748ad00a15443f18203a07d6060f688f30f21632b"),
  )
  |> should.equal(PacketKeys(
    aead: Chacha20Poly1305,
    key: hex("c6d98ff3441c3fe1b2182094f69caa2ed4b716b65488960a7a984979fb23e1c8"),
    iv: hex("e0459b3474bdd0e44a41c144"),
    hp: hex("25a282b9e82f06f21f488917a4fc8f1b73573685608597d0efcb076b0ab7a7a4"),
  ))
}

// RFC 9001 Appendix A.5: nonce for packet number 654360564.

pub fn nonce_xors_packet_number_test() {
  keys.nonce(hex("e0459b3474bdd0e44a41c144"), 654_360_564)
  |> should.equal(hex("e0459b3474bdd0e46d417eb0"))
}

pub fn nonce_zero_packet_number_test() {
  let iv = hex("fa044b2f42a3fd3b46fb255c")
  keys.nonce(iv, 0) |> should.equal(iv)
}
