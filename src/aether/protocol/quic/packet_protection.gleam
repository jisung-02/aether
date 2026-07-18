//// QUIC packet protection and unprotection (RFC 9001 Sections 5.3-5.4):
//// header protection mask application, packet number recovery, and AEAD
//// sealing/opening with the packet header as associated data. Also the
//// Retry integrity tag (Section 5.8).

import aether/protocol/quic/crypto.{Aes128Gcm}
import aether/protocol/quic/keys.{type PacketKeys}
import aether/protocol/quic/packet.{type PacketNumberInfo, PacketNumberInfo}
import aether/protocol/quic/packet_number
import gleam/bit_array
import gleam/int

/// Errors from packet protection removal or application. Either way the
/// correct response is to drop the packet, not close the connection
/// (RFC 9001 Section 5.4 and RFC 9000 Section 12.2).
pub type ProtectionError {
  /// The protected region is too short to contain a header protection
  /// sample, packet number, and authentication tag.
  TooShort
  /// AEAD authentication failed: the packet is forged, corrupted, or
  /// keyed differently.
  DecryptFailed
}

/// Removes packet protection.
///
/// `header` must be the raw header bytes exactly as received — from the
/// (still protected) first byte up to but excluding the protected
/// region — so the AAD is byte-exact even for non-minimal varint
/// encodings. `protected` is the packet's protected region (packet
/// number and ciphertext, e.g. `packet.Initial`'s `protected` field).
/// `largest_pn` is the largest packet number received so far in this
/// packet number space, or -1 for none.
///
/// Returns the revealed packet number info (with the *full* reconstructed
/// packet number) and the decrypted payload.
pub fn unprotect(
  packet_keys: PacketKeys,
  header: BitArray,
  protected: BitArray,
  largest_pn: Int,
) -> Result(#(PacketNumberInfo, BitArray), ProtectionError) {
  case header, bit_array.slice(protected, 4, 16) {
    <<first_byte:8, header_rest:bits>>, Ok(sample) -> {
      let mask = crypto.hp_mask(packet_keys.aead, packet_keys.hp, sample)
      case mask {
        <<mask0:8, pn_mask:bits>> -> {
          let unprotected_first =
            int.bitwise_exclusive_or(
              first_byte,
              int.bitwise_and(mask0, first_byte_mask(first_byte)),
            )
          let pn_length = packet.packet_number_length(unprotected_first)
          case bit_array.slice(protected, 0, pn_length) {
            Ok(protected_pn) -> {
              case xor_packet_number(protected_pn, pn_mask) {
                Ok(pn_bytes) ->
                  open(
                    packet_keys,
                    unprotected_first,
                    header_rest,
                    pn_bytes,
                    pn_length,
                    protected,
                    largest_pn,
                  )
                Error(error) -> Error(error)
              }
            }
            Error(Nil) -> Error(TooShort)
          }
        }
        _ -> Error(TooShort)
      }
    }
    _, _ -> Error(TooShort)
  }
}

fn open(
  packet_keys: PacketKeys,
  unprotected_first: Int,
  header_rest: BitArray,
  pn_bytes: BitArray,
  pn_length: Int,
  protected: BitArray,
  largest_pn: Int,
) -> Result(#(PacketNumberInfo, BitArray), ProtectionError) {
  let ciphertext_size =
    bit_array.byte_size(protected) - pn_length - crypto.tag_length
  case ciphertext_size < 0 {
    True -> Error(TooShort)
    False -> {
      case protected {
        <<
          _:bytes-size(pn_length),
          ciphertext:bytes-size(ciphertext_size),
          tag:bytes-size(16),
        >> -> {
          case packet.finish_header(unprotected_first, pn_bytes) {
            Ok(info) -> {
              let full_pn =
                packet_number.decode(
                  info.packet_number,
                  pn_length * 8,
                  largest_pn,
                )
              let aad = <<unprotected_first:8, header_rest:bits, pn_bytes:bits>>
              let nonce = keys.nonce(packet_keys.iv, full_pn)
              case
                crypto.aead_decrypt(
                  packet_keys.aead,
                  packet_keys.key,
                  nonce,
                  aad,
                  ciphertext,
                  tag,
                )
              {
                Ok(plaintext) ->
                  Ok(#(
                    PacketNumberInfo(..info, packet_number: full_pn),
                    plaintext,
                  ))
                Error(Nil) -> Error(DecryptFailed)
              }
            }
            Error(_) -> Error(TooShort)
          }
        }
        _ -> Error(TooShort)
      }
    }
  }
}

/// Applies packet protection.
///
/// `header` must be the complete unprotected header, ending with the
/// `pn_length` bytes of truncated packet number. `packet_number` is the
/// full packet number (used for the AEAD nonce). Returns the wire bytes
/// of the protected packet (header, ciphertext, and tag).
pub fn protect(
  packet_keys: PacketKeys,
  header: BitArray,
  pn_length: Int,
  packet_number: Int,
  payload: BitArray,
) -> Result(BitArray, ProtectionError) {
  let #(ciphertext, tag) =
    crypto.aead_encrypt(
      packet_keys.aead,
      packet_keys.key,
      keys.nonce(packet_keys.iv, packet_number),
      header,
      payload,
    )
  let protected_payload = <<ciphertext:bits, tag:bits>>
  let head_size = bit_array.byte_size(header) - 1 - pn_length
  case
    header,
    head_size < 0,
    bit_array.slice(protected_payload, 4 - pn_length, 16)
  {
    <<first_byte:8, head:bytes-size(head_size), pn_bytes:bytes-size(pn_length)>>,
      False,
      Ok(sample)
    -> {
      let mask = crypto.hp_mask(packet_keys.aead, packet_keys.hp, sample)
      case mask {
        <<mask0:8, pn_mask:bits>> -> {
          let masked_first =
            int.bitwise_exclusive_or(
              first_byte,
              int.bitwise_and(mask0, first_byte_mask(first_byte)),
            )
          case xor_packet_number(pn_bytes, pn_mask) {
            Ok(masked_pn) ->
              Ok(<<
                masked_first:8,
                head:bits,
                masked_pn:bits,
                protected_payload:bits,
              >>)
            Error(error) -> Error(error)
          }
        }
        _ -> Error(TooShort)
      }
    }
    _, _, _ -> Error(TooShort)
  }
}

/// The fixed key for Retry integrity tags in QUIC v1 (RFC 9001
/// Section 5.8).
const retry_key = <<
  0xbe, 0x0c, 0x69, 0x0b, 0x9f, 0x66, 0x57, 0x5a, 0x1d, 0x76, 0x6b, 0x54,
  0xe3, 0x68, 0xc8, 0x4e,
>>

const retry_nonce = <<
  0x46, 0x15, 0x99, 0xd3, 0x5d, 0x63, 0x2b, 0xf2, 0x23, 0x98, 0x25, 0xbb,
>>

/// Computes the 16-byte Retry integrity tag over the Retry pseudo-packet
/// (RFC 9001 Section 5.8): the original Destination Connection ID from
/// the client's Initial, followed by the transmitted Retry packet with
/// its tag removed.
pub fn retry_integrity_tag(
  original_dcid: BitArray,
  retry_without_tag: BitArray,
) -> BitArray {
  let pseudo = <<
    bit_array.byte_size(original_dcid):8,
    original_dcid:bits,
    retry_without_tag:bits,
  >>
  let #(_, tag) =
    crypto.aead_encrypt(Aes128Gcm, retry_key, retry_nonce, pseudo, <<>>)
  tag
}

/// Long headers protect the low 4 bits of the first byte; short headers
/// protect the low 5 (RFC 9001 Section 5.4.1).
fn first_byte_mask(first_byte: Int) -> Int {
  case int.bitwise_and(first_byte, 0x80) != 0 {
    True -> 0x0f
    False -> 0x1f
  }
}

fn xor_packet_number(
  pn: BitArray,
  mask: BitArray,
) -> Result(BitArray, ProtectionError) {
  case pn, mask {
    <<p:8>>, <<m:8, _:bits>> -> Ok(<<int.bitwise_exclusive_or(p, m):8>>)
    <<p:16>>, <<m:16, _:bits>> -> Ok(<<int.bitwise_exclusive_or(p, m):16>>)
    <<p:24>>, <<m:24, _:bits>> -> Ok(<<int.bitwise_exclusive_or(p, m):24>>)
    <<p:32>>, <<m:32, _:bits>> -> Ok(<<int.bitwise_exclusive_or(p, m):32>>)
    _, _ -> Error(TooShort)
  }
}
