//// QUIC v1 packet headers (RFC 9000 Section 17): long header forms
//// (Initial, 0-RTT, Handshake, Retry, Version Negotiation) and the short
//// header (1-RTT).
////
//// Header protection (RFC 9001 Section 5.4) encrypts the reserved/packet
//// number-length bits of the first byte and the packet number field
//// itself, so a packet cannot be fully parsed before that protection is
//// removed. This module therefore splits parsing into two stages:
////
//// - `parse_long` / `parse_short` read everything that is in the clear on
////   a protected packet: header form, long packet type, version, DCID,
////   SCID, token (Initial only), and the `Length` field. They return the
////   still-protected bytes (packet number + payload) as an opaque
////   `BitArray`, plus any bytes left over in the datagram for coalesced
////   packets. Version Negotiation and Retry carry no protection and are
////   fully parsed by `parse_long`.
//// - `finish_header` is called after a later crypto phase removes header
////   protection; it decodes the now-visible packet number length, packet
////   number value, and (for short headers) key phase bit.
////
//// Builders produce full, unprotected packets (this phase has no crypto),
//// with the packet number written out at an explicit length so callers
//// (and tests) can drive both parsing stages without needing real header
//// protection.

import aether/protocol/quic/error.{type WireError, Malformed, NeedMoreData}
import aether/protocol/quic/varint
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result

/// Maximum length, in bytes, of a QUIC connection ID (RFC 9000 Section
/// 17.2).
pub const max_cid_len = 20

/// The only version this module speaks the wire format of.
pub const quic_v1 = 0x00000001

const long_type_initial = 0

const long_type_zero_rtt = 1

const long_type_handshake = 2

const long_type_retry = 3

/// A packet as read from a datagram before header protection has been
/// removed.
///
/// `Initial`, `ZeroRtt`, and `Handshake` carry `first_byte` (with its low
/// bits still protected) and `protected` (the packet number and payload
/// region, sliced to exactly `length` bytes per the wire `Length` field).
/// `Retry` and `VersionNegotiation` are never protected and are parsed
/// completely. `OneRtt` is the short header; its DCID length is not
/// self-describing on the wire, so callers must supply it (see
/// `parse_short`).
pub type ProtectedPacket {
  VersionNegotiation(
    dcid: BitArray,
    scid: BitArray,
    supported_versions: List(Int),
  )

  Initial(
    version: Int,
    dcid: BitArray,
    scid: BitArray,
    token: BitArray,
    length: Int,
    first_byte: Int,
    protected: BitArray,
  )

  ZeroRtt(
    version: Int,
    dcid: BitArray,
    scid: BitArray,
    length: Int,
    first_byte: Int,
    protected: BitArray,
  )

  Handshake(
    version: Int,
    dcid: BitArray,
    scid: BitArray,
    length: Int,
    first_byte: Int,
    protected: BitArray,
  )

  Retry(
    version: Int,
    dcid: BitArray,
    scid: BitArray,
    retry_token: BitArray,
    integrity_tag: BitArray,
  )

  OneRtt(dcid: BitArray, spin_bit: Bool, first_byte: Int, protected: BitArray)
}

/// The packet number fields revealed once header protection is removed.
pub type PacketNumberInfo {
  PacketNumberInfo(pn_length: Int, packet_number: Int, key_phase: Bool)
}

// ─────────────────────────────────────────────────────────────────────────
// Stage 1: protected parsing
// ─────────────────────────────────────────────────────────────────────────

/// Parses a long header packet (Initial, 0-RTT, Handshake, Retry, or
/// Version Negotiation) from the front of `datagram`.
///
/// Returns the parsed packet and any bytes left over in the datagram
/// (non-empty only for Initial/0-RTT/Handshake, which carry a `Length`
/// field and so support coalescing further packets after them).
pub fn parse_long(
  datagram: BitArray,
) -> Result(#(ProtectedPacket, BitArray), WireError) {
  case datagram {
    <<first_byte:8, version:32, after_version:bits>> -> {
      case is_long_header(first_byte) {
        False -> Error(Malformed("not a long header packet"))
        True ->
          case version == 0 {
            True -> parse_version_negotiation(after_version)
            False ->
              case has_fixed_bit(first_byte) {
                False -> Error(Malformed("fixed bit must be 1"))
                True ->
                  parse_long_typed(first_byte, version, after_version)
              }
          }
      }
    }
    _ -> Error(NeedMoreData)
  }
}

fn parse_long_typed(
  first_byte: Int,
  version: Int,
  data: BitArray,
) -> Result(#(ProtectedPacket, BitArray), WireError) {
  use #(dcid, after_dcid) <- result.try(read_cid(data))
  use #(scid, after_scid) <- result.try(read_cid(after_dcid))

  case long_packet_type(first_byte) {
    t if t == long_type_retry -> parse_retry(version, dcid, scid, after_scid)
    t if t == long_type_initial ->
      parse_initial(first_byte, version, dcid, scid, after_scid)
    t if t == long_type_zero_rtt ->
      parse_zero_rtt_or_handshake(
        first_byte,
        version,
        dcid,
        scid,
        after_scid,
        ZeroRtt,
      )
    _ ->
      parse_zero_rtt_or_handshake(
        first_byte,
        version,
        dcid,
        scid,
        after_scid,
        Handshake,
      )
  }
}

fn parse_version_negotiation(
  data: BitArray,
) -> Result(#(ProtectedPacket, BitArray), WireError) {
  use #(dcid, after_dcid) <- result.try(read_cid(data))
  use #(scid, after_scid) <- result.try(read_cid(after_dcid))

  case bit_array.byte_size(after_scid) % 4 == 0 {
    False -> Error(Malformed("version list length must be a multiple of 4"))
    True -> {
      use versions <- result.try(read_versions(after_scid, []))
      Ok(#(VersionNegotiation(dcid, scid, versions), <<>>))
    }
  }
}

fn read_versions(
  data: BitArray,
  acc: List(Int),
) -> Result(List(Int), WireError) {
  case data {
    <<>> -> Ok(list.reverse(acc))
    <<version:32, rest:bits>> -> read_versions(rest, [version, ..acc])
    _ -> Error(Malformed("version list length must be a multiple of 4"))
  }
}

fn parse_initial(
  first_byte: Int,
  version: Int,
  dcid: BitArray,
  scid: BitArray,
  data: BitArray,
) -> Result(#(ProtectedPacket, BitArray), WireError) {
  use #(token_len, after_token_len) <- result.try(varint.decode(data))
  use #(token, after_token) <- result.try(take_bytes(
    after_token_len,
    token_len,
  ))
  use #(length, after_length) <- result.try(varint.decode(after_token))
  use #(protected, remaining) <- result.try(take_bytes(after_length, length))

  Ok(#(
    Initial(version, dcid, scid, token, length, first_byte, protected),
    remaining,
  ))
}

fn parse_zero_rtt_or_handshake(
  first_byte: Int,
  version: Int,
  dcid: BitArray,
  scid: BitArray,
  data: BitArray,
  make: fn(Int, BitArray, BitArray, Int, Int, BitArray) -> ProtectedPacket,
) -> Result(#(ProtectedPacket, BitArray), WireError) {
  use #(length, after_length) <- result.try(varint.decode(data))
  use #(protected, remaining) <- result.try(take_bytes(after_length, length))

  Ok(#(make(version, dcid, scid, length, first_byte, protected), remaining))
}

fn parse_retry(
  version: Int,
  dcid: BitArray,
  scid: BitArray,
  data: BitArray,
) -> Result(#(ProtectedPacket, BitArray), WireError) {
  let total = bit_array.byte_size(data)
  let token_len = total - 16

  case token_len < 0 {
    True -> Error(NeedMoreData)
    False ->
      case data {
        <<retry_token:bytes-size(token_len), integrity_tag:bytes-size(16)>> ->
          Ok(#(
            Retry(version, dcid, scid, retry_token, integrity_tag),
            <<>>,
          ))
        _ -> Error(NeedMoreData)
      }
  }
}

/// Parses a short header (1-RTT) packet from the front of `datagram`.
///
/// The short header's DCID is not length-prefixed on the wire, so the
/// caller must supply `dcid_len` (the length of DCIDs this endpoint
/// issued). Short header packets have no `Length` field and must be the
/// last packet in a datagram, so the leftover bytes are always empty.
pub fn parse_short(
  datagram: BitArray,
  dcid_len: Int,
) -> Result(#(ProtectedPacket, BitArray), WireError) {
  case dcid_len < 0 || dcid_len > max_cid_len {
    True -> Error(Malformed("dcid length exceeds 20 bytes"))
    False ->
      case datagram {
        <<first_byte:8, rest:bits>> -> {
          case is_long_header(first_byte) {
            True -> Error(Malformed("not a short header packet"))
            False ->
              case has_fixed_bit(first_byte) {
                False -> Error(Malformed("fixed bit must be 1"))
                True ->
                  case rest {
                    <<dcid:bytes-size(dcid_len), protected:bits>> ->
                      Ok(#(
                        OneRtt(dcid, spin_bit(first_byte), first_byte, protected),
                        <<>>,
                      ))
                    _ -> Error(NeedMoreData)
                  }
              }
          }
        }
        _ -> Error(NeedMoreData)
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Stage 2: revealing the packet number after header protection removal
// ─────────────────────────────────────────────────────────────────────────

/// Extracts the packet number length (1-4) encoded in the two least
/// significant bits of an unprotected first byte.
pub fn packet_number_length(first_byte: Int) -> Int {
  int.bitwise_and(first_byte, 0x03) + 1
}

/// Extracts the short header key phase bit from an unprotected first byte.
/// Meaningless for long headers, which have no key phase.
pub fn key_phase(first_byte: Int) -> Bool {
  int.bitwise_and(first_byte, 0x04) != 0
}

/// Completes header parsing once header protection has been removed:
/// decodes the packet number length, the packet number itself (from the
/// already-length-matching `pn_bytes`), and the key phase bit.
///
/// `first_byte` must be the unprotected first byte; `pn_bytes` must be
/// exactly `packet_number_length(first_byte)` bytes, sliced from the front
/// of the packet's protected region.
pub fn finish_header(
  first_byte: Int,
  pn_bytes: BitArray,
) -> Result(PacketNumberInfo, WireError) {
  let pn_length = packet_number_length(first_byte)
  use packet_number <- result.try(decode_packet_number(pn_bytes, pn_length))

  Ok(PacketNumberInfo(
    pn_length: pn_length,
    packet_number: packet_number,
    key_phase: key_phase(first_byte),
  ))
}

fn decode_packet_number(
  pn_bytes: BitArray,
  pn_length: Int,
) -> Result(Int, WireError) {
  case pn_length, pn_bytes {
    1, <<value:8>> -> Ok(value)
    2, <<value:16>> -> Ok(value)
    3, <<value:24>> -> Ok(value)
    4, <<value:32>> -> Ok(value)
    _, _ -> Error(NeedMoreData)
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Builders
// ─────────────────────────────────────────────────────────────────────────

/// Builds a Version Negotiation packet. The header form bit is set, the
/// remaining seven bits of the first byte are left unset, and `version` is
/// forced to 0, per RFC 9000 Section 17.2.1. Version Negotiation has no
/// fixed-bit requirement.
pub fn build_version_negotiation(
  dcid: BitArray,
  scid: BitArray,
  supported_versions: List(Int),
) -> Result(BitArray, WireError) {
  use _ <- result.try(validate_cid(dcid, "dcid"))
  use _ <- result.try(validate_cid(scid, "scid"))

  let versions_bytes =
    supported_versions
    |> list.map(fn(v) { <<v:32>> })
    |> bit_array.concat()

  Ok(
    bit_array.concat([
      <<0x80:8>>,
      <<0:32>>,
      cid_field(dcid),
      cid_field(scid),
      versions_bytes,
    ]),
  )
}

/// Builds an Initial packet with an explicit packet number length. The
/// packet number and payload are written out as given: this phase applies
/// no header protection or AEAD encryption.
pub fn build_initial(
  version: Int,
  dcid: BitArray,
  scid: BitArray,
  token: BitArray,
  packet_number: Int,
  pn_length: Int,
  payload: BitArray,
) -> Result(BitArray, WireError) {
  use _ <- result.try(validate_cid(dcid, "dcid"))
  use _ <- result.try(validate_cid(scid, "scid"))
  use pn_bytes <- result.try(encode_packet_number(packet_number, pn_length))
  use token_len_bytes <- result.try(varint.encode(bit_array.byte_size(token)))
  use length_bytes <- result.try(varint.encode(
    pn_length + bit_array.byte_size(payload),
  ))

  let first_byte = long_first_byte(long_type_initial, pn_length - 1)

  Ok(
    bit_array.concat([
      <<first_byte:8>>,
      <<version:32>>,
      cid_field(dcid),
      cid_field(scid),
      token_len_bytes,
      token,
      length_bytes,
      pn_bytes,
      payload,
    ]),
  )
}

/// Builds a 0-RTT packet with an explicit packet number length.
pub fn build_zero_rtt(
  version: Int,
  dcid: BitArray,
  scid: BitArray,
  packet_number: Int,
  pn_length: Int,
  payload: BitArray,
) -> Result(BitArray, WireError) {
  build_long_no_token(
    long_type_zero_rtt,
    version,
    dcid,
    scid,
    packet_number,
    pn_length,
    payload,
  )
}

/// Builds a Handshake packet with an explicit packet number length.
pub fn build_handshake(
  version: Int,
  dcid: BitArray,
  scid: BitArray,
  packet_number: Int,
  pn_length: Int,
  payload: BitArray,
) -> Result(BitArray, WireError) {
  build_long_no_token(
    long_type_handshake,
    version,
    dcid,
    scid,
    packet_number,
    pn_length,
    payload,
  )
}

fn build_long_no_token(
  long_type: Int,
  version: Int,
  dcid: BitArray,
  scid: BitArray,
  packet_number: Int,
  pn_length: Int,
  payload: BitArray,
) -> Result(BitArray, WireError) {
  use _ <- result.try(validate_cid(dcid, "dcid"))
  use _ <- result.try(validate_cid(scid, "scid"))
  use pn_bytes <- result.try(encode_packet_number(packet_number, pn_length))
  use length_bytes <- result.try(varint.encode(
    pn_length + bit_array.byte_size(payload),
  ))

  let first_byte = long_first_byte(long_type, pn_length - 1)

  Ok(
    bit_array.concat([
      <<first_byte:8>>,
      <<version:32>>,
      cid_field(dcid),
      cid_field(scid),
      length_bytes,
      pn_bytes,
      payload,
    ]),
  )
}

/// Builds a Retry packet. `integrity_tag` must be exactly 16 bytes (RFC
/// 9001 Section 5.8).
pub fn build_retry(
  version: Int,
  dcid: BitArray,
  scid: BitArray,
  retry_token: BitArray,
  integrity_tag: BitArray,
) -> Result(BitArray, WireError) {
  use _ <- result.try(validate_cid(dcid, "dcid"))
  use _ <- result.try(validate_cid(scid, "scid"))

  case bit_array.byte_size(integrity_tag) == 16 {
    False -> Error(Malformed("retry integrity tag must be 16 bytes"))
    True -> {
      let first_byte = long_first_byte(long_type_retry, 0)
      Ok(
        bit_array.concat([
          <<first_byte:8>>,
          <<version:32>>,
          cid_field(dcid),
          cid_field(scid),
          retry_token,
          integrity_tag,
        ]),
      )
    }
  }
}

/// Builds a short header (1-RTT) packet with an explicit packet number
/// length.
pub fn build_one_rtt(
  dcid: BitArray,
  spin_bit: Bool,
  key_phase: Bool,
  packet_number: Int,
  pn_length: Int,
  payload: BitArray,
) -> Result(BitArray, WireError) {
  use _ <- result.try(validate_cid(dcid, "dcid"))
  use pn_bytes <- result.try(encode_packet_number(packet_number, pn_length))

  let first_byte =
    0x40
    |> int.bitwise_or(int.bitwise_shift_left(bool_bit(spin_bit), 5))
    |> int.bitwise_or(int.bitwise_shift_left(bool_bit(key_phase), 2))
    |> int.bitwise_or(pn_length - 1)

  Ok(bit_array.concat([<<first_byte:8>>, dcid, pn_bytes, payload]))
}

// ─────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────

fn is_long_header(first_byte: Int) -> Bool {
  int.bitwise_and(first_byte, 0x80) != 0
}

fn has_fixed_bit(first_byte: Int) -> Bool {
  int.bitwise_and(first_byte, 0x40) != 0
}

fn long_packet_type(first_byte: Int) -> Int {
  int.bitwise_and(int.bitwise_shift_right(first_byte, 4), 0x03)
}

fn spin_bit(first_byte: Int) -> Bool {
  int.bitwise_and(first_byte, 0x20) != 0
}

fn long_first_byte(long_type: Int, low4: Int) -> Int {
  0xc0
  |> int.bitwise_or(int.bitwise_shift_left(long_type, 4))
  |> int.bitwise_or(low4)
}

fn bool_bit(b: Bool) -> Int {
  case b {
    True -> 1
    False -> 0
  }
}

fn cid_field(cid: BitArray) -> BitArray {
  bit_array.concat([<<bit_array.byte_size(cid):8>>, cid])
}

fn validate_cid(cid: BitArray, name: String) -> Result(Nil, WireError) {
  case bit_array.byte_size(cid) > max_cid_len {
    True -> Error(Malformed(name <> " exceeds 20 bytes"))
    False -> Ok(Nil)
  }
}

fn read_cid(data: BitArray) -> Result(#(BitArray, BitArray), WireError) {
  case data {
    <<cid_len:8, rest:bits>> ->
      case cid_len > max_cid_len {
        True -> Error(Malformed("connection id length exceeds 20 bytes"))
        False ->
          case rest {
            <<cid:bytes-size(cid_len), after_cid:bits>> -> Ok(#(cid, after_cid))
            _ -> Error(NeedMoreData)
          }
      }
    _ -> Error(NeedMoreData)
  }
}

fn take_bytes(
  data: BitArray,
  count: Int,
) -> Result(#(BitArray, BitArray), WireError) {
  case count < 0 {
    True -> Error(Malformed("negative length"))
    False ->
      case data {
        <<taken:bytes-size(count), rest:bits>> -> Ok(#(taken, rest))
        _ -> Error(NeedMoreData)
      }
  }
}

fn encode_packet_number(
  value: Int,
  pn_length: Int,
) -> Result(BitArray, WireError) {
  case pn_length {
    1 if value >= 0 && value < 256 -> Ok(<<value:8>>)
    2 if value >= 0 && value < 65_536 -> Ok(<<value:16>>)
    3 if value >= 0 && value < 16_777_216 -> Ok(<<value:24>>)
    4 if value >= 0 && value < 4_294_967_296 -> Ok(<<value:32>>)
    1 | 2 | 3 | 4 -> Error(Malformed("packet number does not fit in pn_length"))
    _ -> Error(Malformed("packet number length must be 1-4"))
  }
}
