//// TLS 1.3 extension list framing and the typed decoders/encoders needed
//// for a minimal ClientHello/ServerHello/EncryptedExtensions exchange
//// (RFC 8446 Section 4.2).
////
//// Every extension body handled here arrives as part of a fully-buffered
//// handshake message (see `handshake_message`), so a truncated or
//// over-long field is always a protocol violation (`Malformed`), never
//// `NeedMoreData` — there is nothing left to wait for.

import aether/protocol/quic/error.{type WireError, Malformed}
import gleam/bit_array
import gleam/bool
import gleam/list

/// `server_name` extension type (RFC 6066).
pub const server_name_ext = 0

/// `supported_groups` extension type (RFC 8446 Section 4.2.7).
pub const supported_groups_ext = 10

/// `signature_algorithms` extension type (RFC 8446 Section 4.2.3).
pub const signature_algorithms_ext = 13

/// `application_layer_protocol_negotiation` extension type (RFC 7301).
pub const alpn_ext = 16

/// `supported_versions` extension type (RFC 8446 Section 4.2.1).
pub const supported_versions_ext = 43

/// `key_share` extension type (RFC 8446 Section 4.2.8).
pub const key_share_ext = 51

/// `quic_transport_parameters` extension type (RFC 9001 Section 8.2).
pub const quic_transport_parameters_ext = 0x39

/// The x25519 named group code point (RFC 8446 Section 4.2.7).
pub const x25519_group = 0x001d

/// The TLS 1.3 protocol version code point.
pub const tls13_version = 0x0304

/// A single extension: its type and raw (still-encoded) body.
pub type Extension {
  Extension(ext_type: Int, data: BitArray)
}

/// Parses an extension list, including its leading 2-byte total length.
/// The declared length must account for exactly the rest of `data` — a
/// short read (truncated) or a long one (trailing garbage) is both
/// `Malformed`.
pub fn parse_list(data: BitArray) -> Result(List(Extension), WireError) {
  case data {
    <<total_len:16, rest:bits>> -> {
      use <- bool.guard(
        bit_array.byte_size(rest) != total_len,
        Error(Malformed("extensions list length mismatch")),
      )
      parse_entries(rest, [])
    }
    _ -> Error(Malformed("truncated extensions list"))
  }
}

fn parse_entries(
  data: BitArray,
  acc: List(Extension),
) -> Result(List(Extension), WireError) {
  case data {
    <<>> -> Ok(list.reverse(acc))
    <<ext_type:16, ext_len:16, rest:bits>> ->
      case bit_array.byte_size(rest) < ext_len {
        True -> Error(Malformed("truncated extension data"))
        False ->
          case
            bit_array.slice(rest, 0, ext_len),
            bit_array.slice(rest, ext_len, bit_array.byte_size(rest) - ext_len)
          {
            Ok(ext_data), Ok(tail) ->
              parse_entries(tail, [Extension(ext_type, ext_data), ..acc])
            _, _ -> Error(Malformed("failed to slice extension data"))
          }
      }
    _ -> Error(Malformed("truncated extension header"))
  }
}

/// Encodes an extension list with its leading 2-byte total length.
pub fn encode_list(extensions: List(Extension)) -> BitArray {
  let body = bit_array.concat(list.map(extensions, encode_one))
  bit_array.concat([<<bit_array.byte_size(body):16>>, body])
}

fn encode_one(extension: Extension) -> BitArray {
  bit_array.concat([
    <<extension.ext_type:16, bit_array.byte_size(extension.data):16>>,
    extension.data,
  ])
}

/// Returns the raw body of the first extension with the given type.
pub fn find(
  extensions: List(Extension),
  ext_type: Int,
) -> Result(BitArray, Nil) {
  case list.find(extensions, fn(ext) { ext.ext_type == ext_type }) {
    Ok(extension) -> Ok(extension.data)
    Error(Nil) -> Error(Nil)
  }
}

/// Decodes a `key_share` extension body into its (group, key_exchange)
/// entries (RFC 8446 Section 4.2.8, client shape: a 2-byte list length).
pub fn parse_key_shares(
  data: BitArray,
) -> Result(List(#(Int, BitArray)), WireError) {
  case data {
    <<list_len:16, rest:bits>> -> {
      use <- bool.guard(
        bit_array.byte_size(rest) != list_len,
        Error(Malformed("key_share list length mismatch")),
      )
      parse_key_share_entries(rest, [])
    }
    _ -> Error(Malformed("truncated key_share extension"))
  }
}

fn parse_key_share_entries(
  data: BitArray,
  acc: List(#(Int, BitArray)),
) -> Result(List(#(Int, BitArray)), WireError) {
  case data {
    <<>> -> Ok(list.reverse(acc))
    <<group:16, len:16, rest:bits>> ->
      case bit_array.byte_size(rest) < len {
        True -> Error(Malformed("truncated key_share entry"))
        False ->
          case
            bit_array.slice(rest, 0, len),
            bit_array.slice(rest, len, bit_array.byte_size(rest) - len)
          {
            Ok(key), Ok(tail) ->
              parse_key_share_entries(tail, [#(group, key), ..acc])
            _, _ -> Error(Malformed("failed to slice key_share entry"))
          }
      }
    _ -> Error(Malformed("truncated key_share entry header"))
  }
}

/// Decodes a `supported_versions` extension body in its client shape (a
/// 1-byte list length followed by 2-byte version entries).
pub fn parse_supported_versions(
  data: BitArray,
) -> Result(List(Int), WireError) {
  case data {
    <<list_len:8, rest:bits>> -> {
      use <- bool.guard(
        bit_array.byte_size(rest) != list_len,
        Error(Malformed("supported_versions length mismatch")),
      )
      use <- bool.guard(
        list_len % 2 != 0,
        Error(Malformed("supported_versions length must be even")),
      )
      Ok(parse_u16_list(rest))
    }
    _ -> Error(Malformed("truncated supported_versions extension"))
  }
}

/// Decodes a `supported_groups` extension body (a 2-byte list length
/// followed by 2-byte named group entries).
pub fn parse_supported_groups(data: BitArray) -> Result(List(Int), WireError) {
  case data {
    <<list_len:16, rest:bits>> -> {
      use <- bool.guard(
        bit_array.byte_size(rest) != list_len,
        Error(Malformed("supported_groups length mismatch")),
      )
      use <- bool.guard(
        list_len % 2 != 0,
        Error(Malformed("supported_groups length must be even")),
      )
      Ok(parse_u16_list(rest))
    }
    _ -> Error(Malformed("truncated supported_groups extension"))
  }
}

/// Decodes a `signature_algorithms` extension body (a 2-byte list length
/// followed by 2-byte signature scheme entries).
pub fn parse_signature_algorithms(
  data: BitArray,
) -> Result(List(Int), WireError) {
  case data {
    <<list_len:16, rest:bits>> -> {
      use <- bool.guard(
        bit_array.byte_size(rest) != list_len,
        Error(Malformed("signature_algorithms length mismatch")),
      )
      use <- bool.guard(
        list_len % 2 != 0,
        Error(Malformed("signature_algorithms length must be even")),
      )
      Ok(parse_u16_list(rest))
    }
    _ -> Error(Malformed("truncated signature_algorithms extension"))
  }
}

fn parse_u16_list(data: BitArray) -> List(Int) {
  case data {
    <<value:16, rest:bits>> -> [value, ..parse_u16_list(rest)]
    _ -> []
  }
}

/// Decodes an `application_layer_protocol_negotiation` extension body
/// (RFC 7301): a 2-byte list length, then 1-byte length-prefixed protocol
/// names. Empty names are rejected.
pub fn parse_alpn(data: BitArray) -> Result(List(String), WireError) {
  case data {
    <<list_len:16, rest:bits>> -> {
      use <- bool.guard(
        bit_array.byte_size(rest) != list_len,
        Error(Malformed("ALPN protocol list length mismatch")),
      )
      parse_alpn_entries(rest, [])
    }
    _ -> Error(Malformed("truncated ALPN extension"))
  }
}

fn parse_alpn_entries(
  data: BitArray,
  acc: List(String),
) -> Result(List(String), WireError) {
  case data {
    <<>> -> Ok(list.reverse(acc))
    <<len:8, rest:bits>> -> {
      use <- bool.guard(
        len == 0,
        Error(Malformed("ALPN protocol name must not be empty")),
      )
      case bit_array.byte_size(rest) < len {
        True -> Error(Malformed("truncated ALPN protocol name"))
        False ->
          case
            bit_array.slice(rest, 0, len),
            bit_array.slice(rest, len, bit_array.byte_size(rest) - len)
          {
            Ok(name_bytes), Ok(tail) ->
              case bit_array.to_string(name_bytes) {
                Ok(name) -> parse_alpn_entries(tail, [name, ..acc])
                Error(Nil) ->
                  Error(Malformed("ALPN protocol name is not valid UTF-8"))
              }
            _, _ -> Error(Malformed("failed to slice ALPN protocol name"))
          }
      }
    }
    _ -> Error(Malformed("truncated ALPN protocol name header"))
  }
}

/// Decodes a `server_name` extension body (RFC 6066): a 2-byte
/// server_name_list length, then entries of a 1-byte name type and a
/// 2-byte length-prefixed name. Returns the first `host_name` (type 0)
/// entry; an empty or host_name-less list is `Malformed`.
pub fn parse_server_name(data: BitArray) -> Result(String, WireError) {
  case data {
    <<list_len:16, rest:bits>> -> {
      use <- bool.guard(
        bit_array.byte_size(rest) != list_len,
        Error(Malformed("server_name list length mismatch")),
      )
      find_host_name(rest)
    }
    _ -> Error(Malformed("truncated server_name extension"))
  }
}

fn find_host_name(data: BitArray) -> Result(String, WireError) {
  case data {
    <<>> -> Error(Malformed("server_name list has no host_name entry"))
    <<name_type:8, len:16, rest:bits>> ->
      case bit_array.byte_size(rest) < len {
        True -> Error(Malformed("truncated server_name entry"))
        False ->
          case
            bit_array.slice(rest, 0, len),
            bit_array.slice(rest, len, bit_array.byte_size(rest) - len)
          {
            Ok(name_bytes), Ok(tail) ->
              case name_type {
                0 ->
                  case bit_array.to_string(name_bytes) {
                    Ok(name) -> Ok(name)
                    Error(Nil) ->
                      Error(Malformed(
                        "server_name host_name is not valid UTF-8",
                      ))
                  }
                _ -> find_host_name(tail)
              }
            _, _ -> Error(Malformed("failed to slice server_name entry"))
          }
      }
    _ -> Error(Malformed("truncated server_name entry header"))
  }
}

/// Encodes a single `key_share` entry as a ServerHello extension body
/// (RFC 8446 Section 4.2.8, server shape: one entry, not a list).
pub fn encode_key_share(group: Int, key: BitArray) -> BitArray {
  bit_array.concat([<<group:16, bit_array.byte_size(key):16>>, key])
}

/// Encodes the `supported_versions` extension body as sent by a server
/// (a single 2-byte selected version, always TLS 1.3).
pub fn encode_supported_versions_selected() -> BitArray {
  <<tls13_version:16>>
}

/// Encodes an `application_layer_protocol_negotiation` extension body
/// carrying a single negotiated protocol.
pub fn encode_alpn(protocol: String) -> BitArray {
  let name_bytes = bit_array.from_string(protocol)
  let entry =
    bit_array.concat([<<bit_array.byte_size(name_bytes):8>>, name_bytes])
  bit_array.concat([<<bit_array.byte_size(entry):16>>, entry])
}
