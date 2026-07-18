//// TLS 1.3 ClientHello parsing (RFC 8446 Section 4.1.2).
////
//// `parse` decodes the handshake message body with the 4-byte handshake
//// header already stripped by `handshake_message`. Every field here
//// arrives as part of a fully-buffered handshake message, so a truncated
//// or over-long field is always `Malformed`, never `NeedMoreData`.

import aether/protocol/quic/error.{type WireError, Malformed}
import aether/protocol/tls/extensions.{type Extension}
import gleam/bit_array
import gleam/bool
import gleam/result

/// A parsed ClientHello. `legacy_version` and the content of
/// `legacy_compression_methods` are validated for shape (present, and
/// non-empty respectively) but not retained — this server only speaks
/// TLS 1.3, negotiated via the `supported_versions` extension.
pub type ClientHello {
  ClientHello(
    random: BitArray,
    legacy_session_id: BitArray,
    cipher_suites: List(Int),
    extensions: List(Extension),
  )
}

/// Parses a ClientHello body (message header already stripped).
///
/// Validates, in order: `legacy_version` (2 bytes, present but not
/// enforced to be 0x0303), `random` (32 bytes), `legacy_session_id`
/// (1-byte length, at most 32 bytes), `cipher_suites` (2-byte length,
/// 2-byte entries, non-empty), `legacy_compression_methods` (1-byte
/// length, at least 1 byte, content ignored), and finally the extensions
/// block, which must consume the remainder of `body` exactly.
pub fn parse(body: BitArray) -> Result(ClientHello, WireError) {
  case body {
    <<_legacy_version:16, random:bytes-size(32), rest:bits>> -> {
      use #(session_id, rest) <- result.try(parse_session_id(rest))
      use #(cipher_suites, rest) <- result.try(parse_cipher_suites(rest))
      use rest <- result.try(parse_compression_methods(rest))
      use extension_list <- result.try(extensions.parse_list(rest))
      Ok(ClientHello(random, session_id, cipher_suites, extension_list))
    }
    _ ->
      Error(Malformed("truncated ClientHello: missing legacy_version or random"))
  }
}

fn parse_session_id(
  data: BitArray,
) -> Result(#(BitArray, BitArray), WireError) {
  case data {
    <<len:8, rest:bits>> -> {
      use <- bool.guard(
        len > 32,
        Error(Malformed("legacy_session_id longer than 32 bytes")),
      )
      case bit_array.byte_size(rest) < len {
        True -> Error(Malformed("truncated legacy_session_id"))
        False ->
          case
            bit_array.slice(rest, 0, len),
            bit_array.slice(rest, len, bit_array.byte_size(rest) - len)
          {
            Ok(session_id), Ok(tail) -> Ok(#(session_id, tail))
            _, _ -> Error(Malformed("failed to slice legacy_session_id"))
          }
      }
    }
    _ -> Error(Malformed("truncated ClientHello: missing legacy_session_id"))
  }
}

fn parse_cipher_suites(
  data: BitArray,
) -> Result(#(List(Int), BitArray), WireError) {
  case data {
    <<list_len:16, rest:bits>> -> {
      use <- bool.guard(
        list_len == 0,
        Error(Malformed("cipher_suites must not be empty")),
      )
      use <- bool.guard(
        list_len % 2 != 0,
        Error(Malformed("cipher_suites length must be even")),
      )
      case bit_array.byte_size(rest) < list_len {
        True -> Error(Malformed("truncated cipher_suites"))
        False ->
          case
            bit_array.slice(rest, 0, list_len),
            bit_array.slice(
              rest,
              list_len,
              bit_array.byte_size(rest) - list_len,
            )
          {
            Ok(suite_bytes), Ok(tail) ->
              Ok(#(parse_u16_list(suite_bytes), tail))
            _, _ -> Error(Malformed("failed to slice cipher_suites"))
          }
      }
    }
    _ -> Error(Malformed("truncated ClientHello: missing cipher_suites"))
  }
}

fn parse_u16_list(data: BitArray) -> List(Int) {
  case data {
    <<value:16, rest:bits>> -> [value, ..parse_u16_list(rest)]
    _ -> []
  }
}

fn parse_compression_methods(data: BitArray) -> Result(BitArray, WireError) {
  case data {
    <<len:8, rest:bits>> -> {
      use <- bool.guard(
        len == 0,
        Error(Malformed("legacy_compression_methods must not be empty")),
      )
      case bit_array.byte_size(rest) < len {
        True -> Error(Malformed("truncated legacy_compression_methods"))
        False ->
          case
            bit_array.slice(rest, 0, len),
            bit_array.slice(rest, len, bit_array.byte_size(rest) - len)
          {
            Ok(_compression_methods), Ok(tail) -> Ok(tail)
            _, _ ->
              Error(Malformed("failed to slice legacy_compression_methods"))
          }
      }
    }
    _ ->
      Error(Malformed(
        "truncated ClientHello: missing legacy_compression_methods",
      ))
  }
}
