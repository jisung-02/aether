import aether/protocol/quic/crypto.{Chacha20Poly1305}
import aether/protocol/quic/keys
import aether/protocol/quic/packet
import aether/protocol/quic/packet_protection.{DecryptFailed, TooShort}
import aether/protocol/quic/rfc9001_vectors as vectors
import gleam/bit_array
import gleam/int
import gleeunit/should

fn hex(string: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(string)
  bytes
}

fn client_initial_keys() -> keys.PacketKeys {
  keys.initial_keys(hex("8394c8f03e515708")).0
}

fn server_initial_keys() -> keys.PacketKeys {
  keys.initial_keys(hex("8394c8f03e515708")).1
}

/// Parses a protected Initial datagram and returns the raw header bytes
/// (the AAD prefix) alongside the protected region.
fn split_initial(datagram: BitArray) -> #(BitArray, BitArray) {
  let assert Ok(#(packet.Initial(protected: protected, ..), <<>>)) =
    packet.parse_long(datagram)
  let header_size =
    bit_array.byte_size(datagram) - bit_array.byte_size(protected)
  let assert Ok(header) = bit_array.slice(datagram, 0, header_size)
  #(header, protected)
}

/// The client Initial plaintext: the ClientHello CRYPTO frame padded
/// with PADDING frames to 1162 bytes (RFC 9001 A.2).
fn client_initial_plaintext() -> BitArray {
  let frames = hex(vectors.client_initial_payload)
  let padding = 1162 - bit_array.byte_size(frames)
  <<frames:bits, 0:size({ padding * 8 })>>
}

// ── RFC 9001 A.2: client Initial ─────────────────────────────────────────

pub fn unprotect_client_initial_test() {
  let #(header, protected) = split_initial(hex(vectors.client_initial_packet))

  let assert Ok(#(info, plaintext)) =
    packet_protection.unprotect(client_initial_keys(), header, protected, -1)

  info.packet_number |> should.equal(2)
  info.pn_length |> should.equal(4)
  plaintext |> should.equal(client_initial_plaintext())
}

pub fn protect_client_initial_test() {
  packet_protection.protect(
    client_initial_keys(),
    hex(vectors.client_initial_header),
    4,
    2,
    client_initial_plaintext(),
  )
  |> should.equal(Ok(hex(vectors.client_initial_packet)))
}

// ── RFC 9001 A.3: server Initial ─────────────────────────────────────────

pub fn unprotect_server_initial_test() {
  let #(header, protected) = split_initial(hex(vectors.server_initial_packet))

  let assert Ok(#(info, plaintext)) =
    packet_protection.unprotect(server_initial_keys(), header, protected, -1)

  info.packet_number |> should.equal(1)
  info.pn_length |> should.equal(2)
  plaintext |> should.equal(hex(vectors.server_initial_payload))
}

pub fn protect_server_initial_test() {
  packet_protection.protect(
    server_initial_keys(),
    hex(vectors.server_initial_header),
    2,
    1,
    hex(vectors.server_initial_payload),
  )
  |> should.equal(Ok(hex(vectors.server_initial_packet)))
}

// ── RFC 9001 A.5: ChaCha20-Poly1305 short header packet ──────────────────

fn chacha_keys() -> keys.PacketKeys {
  keys.from_secret(
    Chacha20Poly1305,
    hex("9ac312a7f877468ebe69422748ad00a15443f18203a07d6060f688f30f21632b"),
  )
}

pub fn unprotect_chacha_short_header_test() {
  let datagram = hex("4cfe4189655e5cd55c41f69080575d7999c25a5bfb")
  let assert Ok(#(packet.OneRtt(protected: protected, ..), <<>>)) =
    packet.parse_short(datagram, 0)

  let assert Ok(#(info, plaintext)) =
    packet_protection.unprotect(chacha_keys(), <<0x4c>>, protected, 654_360_563)

  info.packet_number |> should.equal(654_360_564)
  info.pn_length |> should.equal(3)
  info.key_phase |> should.equal(False)
  plaintext |> should.equal(<<0x01>>)
}

pub fn protect_chacha_short_header_test() {
  packet_protection.protect(chacha_keys(), hex("4200bff4"), 3, 654_360_564, <<
    0x01,
  >>)
  |> should.equal(Ok(hex("4cfe4189655e5cd55c41f69080575d7999c25a5bfb")))
}

// ── RFC 9001 A.4: Retry integrity tag ────────────────────────────────────

pub fn retry_integrity_tag_test() {
  let retry = hex(vectors.retry_packet)
  let without_tag_size = bit_array.byte_size(retry) - 16
  let assert Ok(without_tag) = bit_array.slice(retry, 0, without_tag_size)
  let assert Ok(tag) = bit_array.slice(retry, without_tag_size, 16)

  packet_protection.retry_integrity_tag(hex("8394c8f03e515708"), without_tag)
  |> should.equal(tag)
}

// ── Failure paths ────────────────────────────────────────────────────────

pub fn unprotect_tampered_ciphertext_test() {
  let #(header, protected) = split_initial(hex(vectors.client_initial_packet))
  let assert Ok(prefix) = bit_array.slice(protected, 0, 100)
  let assert Ok(<<byte:8, suffix:bits>>) =
    bit_array.slice(protected, 100, bit_array.byte_size(protected) - 100)
  let tampered = <<
    prefix:bits,
    int.bitwise_exclusive_or(byte, 0xff):8,
    suffix:bits,
  >>

  packet_protection.unprotect(client_initial_keys(), header, tampered, -1)
  |> should.equal(Error(DecryptFailed))
}

pub fn unprotect_wrong_keys_test() {
  let #(header, protected) = split_initial(hex(vectors.client_initial_packet))

  packet_protection.unprotect(server_initial_keys(), header, protected, -1)
  |> should.equal(Error(DecryptFailed))
}

pub fn unprotect_too_short_test() {
  packet_protection.unprotect(
    client_initial_keys(),
    hex(vectors.client_initial_header),
    <<1, 2, 3, 4, 5>>,
    -1,
  )
  |> should.equal(Error(TooShort))
}
