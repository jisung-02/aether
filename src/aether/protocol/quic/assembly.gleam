//// Packet assembly (RFC 9000 Section 17, RFC 9001 Section 5.3): builds
//// unprotected packet headers with a tag-inclusive `Length` field and
//// applies packet protection (AEAD sealing and header protection) to
//// produce the final wire bytes of Initial, Handshake, and 1-RTT packets.
////
//// The phase-1 builders in `packet.gleam` (`build_initial`,
//// `build_handshake`, `build_one_rtt`) emit fully unprotected packets with
//// a tag-*exclusive* `Length`, since there was no crypto layer yet to
//// produce a tag. A real packet needs `Length` to include the 16-byte AEAD
//// tag, and then header and payload protection applied on top. This
//// module therefore builds the header bytes directly — rather than
//// reusing those builders — and hands them to `packet_protection.protect`.

import aether/protocol/quic/keys.{type PacketKeys}
import aether/protocol/quic/packet.{quic_v1}
import aether/protocol/quic/packet_protection.{type ProtectionError, TooShort}
import aether/protocol/quic/varint
import gleam/bit_array
import gleam/int
import gleam/list

/// AEAD authentication tag length, in bytes (RFC 9001 Section 5.3).
const tag_length = 16

/// Builds and protects an Initial packet.
///
/// `token` is the Initial token (empty for a server-sent Initial). `pn` is
/// the full packet number; `pn_length` is the number of bytes used to
/// encode it on the wire (1-4). `payload` is the already-serialized frame
/// bytes (unprotected, unpadded).
pub fn initial_packet(
  keys: PacketKeys,
  dcid: BitArray,
  scid: BitArray,
  token: BitArray,
  pn: Int,
  pn_length: Int,
  payload: BitArray,
) -> Result(BitArray, ProtectionError) {
  case
    encode_packet_number(pn, pn_length),
    varint.encode(bit_array.byte_size(token)),
    varint.encode(pn_length + bit_array.byte_size(payload) + tag_length)
  {
    Ok(pn_bytes), Ok(token_len_bytes), Ok(length_bytes) -> {
      let first_byte = int.bitwise_or(0xc0, pn_length - 1)
      let header =
        bit_array.concat([
          <<first_byte:8>>,
          <<quic_v1:32>>,
          cid_field(dcid),
          cid_field(scid),
          token_len_bytes,
          token,
          length_bytes,
          pn_bytes,
        ])
      packet_protection.protect(keys, header, pn_length, pn, payload)
    }
    _, _, _ -> Error(TooShort)
  }
}

/// Builds and protects a Handshake packet. Same conventions as
/// `initial_packet`, minus the token fields (Handshake packets never carry
/// one).
pub fn handshake_packet(
  keys: PacketKeys,
  dcid: BitArray,
  scid: BitArray,
  pn: Int,
  pn_length: Int,
  payload: BitArray,
) -> Result(BitArray, ProtectionError) {
  case
    encode_packet_number(pn, pn_length),
    varint.encode(pn_length + bit_array.byte_size(payload) + tag_length)
  {
    Ok(pn_bytes), Ok(length_bytes) -> {
      let first_byte = int.bitwise_or(0xe0, pn_length - 1)
      let header =
        bit_array.concat([
          <<first_byte:8>>,
          <<quic_v1:32>>,
          cid_field(dcid),
          cid_field(scid),
          length_bytes,
          pn_bytes,
        ])
      packet_protection.protect(keys, header, pn_length, pn, payload)
    }
    _, _ -> Error(TooShort)
  }
}

/// Builds and protects a 1-RTT (short header) packet. The spin bit and key
/// phase bit are always sent as 0 (ponytail: spin bit tracking and key
/// update are out of scope). Short header packets carry no `Length` field
/// and so must be the last packet in a datagram.
pub fn one_rtt_packet(
  keys: PacketKeys,
  dcid: BitArray,
  pn: Int,
  pn_length: Int,
  payload: BitArray,
) -> Result(BitArray, ProtectionError) {
  case encode_packet_number(pn, pn_length) {
    Ok(pn_bytes) -> {
      let first_byte = int.bitwise_or(0x40, pn_length - 1)
      let header = bit_array.concat([<<first_byte:8>>, dcid, pn_bytes])
      packet_protection.protect(keys, header, pn_length, pn, payload)
    }
    Error(_) -> Error(TooShort)
  }
}

/// Pads `datagram` with zero bytes (PADDING frames) so it reaches
/// `min_size`. Returns `datagram` unchanged if it is already at least that
/// large. Client Initial datagrams must reach 1200 bytes (RFC 9000 Section
/// 14.1); servers pad the datagram carrying their first Initial similarly,
/// for anti-amplification headroom.
pub fn pad_datagram(datagram: BitArray, min_size: Int) -> BitArray {
  let size = bit_array.byte_size(datagram)
  case size < min_size {
    True -> bit_array.concat([datagram, zero_bytes(min_size - size)])
    False -> datagram
  }
}

fn zero_bytes(count: Int) -> BitArray {
  list.repeat(<<0:8>>, count)
  |> bit_array.concat
}

fn cid_field(cid: BitArray) -> BitArray {
  bit_array.concat([<<bit_array.byte_size(cid):8>>, cid])
}

/// Encodes a packet number into exactly `pn_length` big-endian bytes (RFC
/// 9000 Section 17.1). `pn_length` must be 1-4 and `value` must fit; both
/// always hold for callers of this module, but the `Result` return keeps
/// the module panic-free.
fn encode_packet_number(
  value: Int,
  pn_length: Int,
) -> Result(BitArray, ProtectionError) {
  case pn_length {
    1 if value >= 0 && value < 256 -> Ok(<<value:8>>)
    2 if value >= 0 && value < 65_536 -> Ok(<<value:16>>)
    3 if value >= 0 && value < 16_777_216 -> Ok(<<value:24>>)
    4 if value >= 0 && value < 4_294_967_296 -> Ok(<<value:32>>)
    1 | 2 | 3 | 4 -> Error(TooShort)
    _ -> Error(TooShort)
  }
}
