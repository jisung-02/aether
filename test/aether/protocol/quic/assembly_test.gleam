import aether/protocol/quic/assembly
import aether/protocol/quic/keys
import aether/protocol/quic/packet
import aether/protocol/quic/packet_protection
import aether/protocol/quic/rfc9001_vectors as vectors
import gleam/bit_array
import gleeunit/should

fn hex(string: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(string)
  bytes
}

// ── RFC 9001 A.3: byte-exact server Initial ──────────────────────────────

pub fn initial_packet_matches_rfc9001_a3_test() {
  let #(_client_keys, server_keys) = keys.initial_keys(hex("8394c8f03e515708"))

  assembly.initial_packet(
    server_keys,
    <<>>,
    hex("f067a5502a4262b5"),
    <<>>,
    1,
    2,
    hex(vectors.server_initial_payload),
  )
  |> should.equal(Ok(hex(vectors.server_initial_packet)))
}

// ── Handshake round-trip ──────────────────────────────────────────────────

pub fn handshake_packet_round_trips_test() {
  let #(_client_keys, server_keys) = keys.initial_keys(hex("8394c8f03e515708"))
  let dcid = hex("f067a5502a4262b5")
  let scid = hex("8394c8f03e515708")
  let payload = hex("060040f1010000ed0303ebf8fa56f12939b9584a")

  let assert Ok(datagram) =
    assembly.handshake_packet(server_keys, dcid, scid, 7, 2, payload)

  let assert Ok(#(packet.Handshake(protected: protected, ..), <<>>)) =
    packet.parse_long(datagram)
  let header_size =
    bit_array.byte_size(datagram) - bit_array.byte_size(protected)
  let assert Ok(header) = bit_array.slice(datagram, 0, header_size)

  let assert Ok(#(info, recovered)) =
    packet_protection.unprotect(server_keys, header, protected, -1)

  info.packet_number |> should.equal(7)
  recovered |> should.equal(payload)
}

// ── 1-RTT round-trip ──────────────────────────────────────────────────────

pub fn one_rtt_packet_round_trips_test() {
  let #(client_keys, _server_keys) = keys.initial_keys(hex("8394c8f03e515708"))
  let dcid = hex("f067a5502a4262b5")
  let payload = hex("00010203040506070809")

  let assert Ok(datagram) =
    assembly.one_rtt_packet(client_keys, dcid, 3, 1, payload)

  let assert Ok(#(packet.OneRtt(protected: protected, ..), <<>>)) =
    packet.parse_short(datagram, bit_array.byte_size(dcid))
  let header_size =
    bit_array.byte_size(datagram) - bit_array.byte_size(protected)
  let assert Ok(header) = bit_array.slice(datagram, 0, header_size)

  let assert Ok(#(info, recovered)) =
    packet_protection.unprotect(client_keys, header, protected, -1)

  info.packet_number |> should.equal(3)
  recovered |> should.equal(payload)
}

// ── pad_datagram ───────────────────────────────────────────────────────────

pub fn pad_datagram_pads_short_datagrams_test() {
  let datagram = hex("aabbcc")
  let padded = assembly.pad_datagram(datagram, 1200)

  bit_array.byte_size(padded) |> should.equal(1200)
  bit_array.slice(padded, 0, 3) |> should.equal(Ok(datagram))
}

pub fn pad_datagram_leaves_large_datagrams_unchanged_test() {
  let datagram = hex(vectors.server_initial_packet)
  let size = bit_array.byte_size(datagram)

  assembly.pad_datagram(datagram, size)
  |> should.equal(datagram)

  assembly.pad_datagram(datagram, size - 10)
  |> should.equal(datagram)
}
