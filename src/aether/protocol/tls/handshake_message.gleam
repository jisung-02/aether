//// TLS 1.3 handshake message framing (RFC 8446 Section 4).
////
//// There is no TLS record layer here: QUIC carries handshake messages
//// directly as the payload of CRYPTO frames (RFC 9001 Section 4). This
//// module only handles the message framing itself — a 1-byte type, a
//// 3-byte big-endian length, then the body — and `Buffer` reassembles
//// whole messages from a byte stream that the transport may deliver
//// split across multiple chunks or merged into one.

import aether/protocol/quic/error.{type WireError, Malformed}
import gleam/bit_array
import gleam/bool
import gleam/list

/// ClientHello handshake message type (RFC 8446 Section 4.1.2).
pub const client_hello_type = 1

/// ServerHello handshake message type (RFC 8446 Section 4.1.3).
pub const server_hello_type = 2

/// EncryptedExtensions handshake message type (RFC 8446 Section 4.3.1).
pub const encrypted_extensions_type = 8

/// Certificate handshake message type (RFC 8446 Section 4.4.2).
pub const certificate_type = 11

/// CertificateVerify handshake message type (RFC 8446 Section 4.4.3).
pub const certificate_verify_type = 15

/// Finished handshake message type (RFC 8446 Section 4.4.4).
pub const finished_type = 20

/// Largest accepted handshake message body, in bytes (2^17). This is a
/// sanity cap only: no legitimate handshake message this server sends or
/// accepts is anywhere near this size.
const max_body_size = 131_072

/// A single decoded handshake message with its 4-byte header stripped.
pub type HandshakeMessage {
  HandshakeMessage(msg_type: Int, body: BitArray)
}

/// Encodes a handshake message: 1-byte type, 3-byte big-endian length,
/// then `body`.
pub fn encode(msg_type: Int, body: BitArray) -> BitArray {
  let length = bit_array.byte_size(body)
  bit_array.concat([<<msg_type:8, length:24>>, body])
}

/// Accumulates bytes from a CRYPTO byte stream and reassembles the
/// handshake messages within it, which may be split or merged arbitrarily
/// across `push` calls.
pub type Buffer {
  Buffer(pending: BitArray)
}

/// Creates an empty buffer.
pub fn new_buffer() -> Buffer {
  Buffer(pending: <<>>)
}

/// Appends `data` to the buffer and returns every handshake message that
/// is now complete, in wire order, together with the buffer holding
/// whatever partial tail remains. A declared body length greater than
/// 2^17 bytes is `Malformed`.
pub fn push(
  buffer: Buffer,
  data: BitArray,
) -> Result(#(Buffer, List(HandshakeMessage)), WireError) {
  drain(bit_array.concat([buffer.pending, data]), [])
}

/// Returns the number of bytes currently held as an incomplete tail.
pub fn buffered_size(buffer: Buffer) -> Int {
  bit_array.byte_size(buffer.pending)
}

fn drain(
  data: BitArray,
  acc: List(HandshakeMessage),
) -> Result(#(Buffer, List(HandshakeMessage)), WireError) {
  case data {
    <<msg_type:8, length:24, rest:bits>> -> {
      use <- bool.guard(
        length > max_body_size,
        Error(Malformed("handshake message body exceeds 2^17 bytes")),
      )
      case bit_array.byte_size(rest) >= length {
        True ->
          case
            bit_array.slice(rest, 0, length),
            bit_array.slice(rest, length, bit_array.byte_size(rest) - length)
          {
            Ok(body), Ok(tail) ->
              drain(tail, [HandshakeMessage(msg_type, body), ..acc])
            _, _ -> Error(Malformed("failed to slice handshake message body"))
          }
        False -> Ok(#(Buffer(pending: data), list.reverse(acc)))
      }
    }
    _ -> Ok(#(Buffer(pending: data), list.reverse(acc)))
  }
}
