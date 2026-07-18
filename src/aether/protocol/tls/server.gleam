//// Builders for the TLS 1.3 server handshake flight (RFC 8446 Section 4):
//// ServerHello, EncryptedExtensions, Certificate, CertificateVerify, and
//// Finished, plus the CertificateVerify signature content. Pure byte
//// construction; the driving logic lives in `handshake.gleam`.

import aether/protocol/tls/extensions.{Extension}
import aether/protocol/tls/handshake_message
import gleam/bit_array
import gleam/list
import gleam/string

/// Builds a complete ServerHello message (with handshake header)
/// selecting TLS 1.3, TLS_AES_128_GCM_SHA256, and the given x25519
/// public key. `legacy_session_id` must echo the client's.
pub fn build_server_hello(
  random: BitArray,
  legacy_session_id: BitArray,
  public_key: BitArray,
) -> BitArray {
  let exts =
    extensions.encode_list([
      Extension(
        extensions.key_share_ext,
        extensions.encode_key_share(extensions.x25519_group, public_key),
      ),
      Extension(
        extensions.supported_versions_ext,
        extensions.encode_supported_versions_selected(),
      ),
    ])
  let body = <<
    0x0303:16,
    random:bits,
    bit_array.byte_size(legacy_session_id):8,
    legacy_session_id:bits,
    0x1301:16,
    0:8,
    exts:bits,
  >>
  handshake_message.encode(handshake_message.server_hello_type, body)
}

/// Builds an EncryptedExtensions message carrying the negotiated ALPN
/// protocol and this server's QUIC transport parameters.
pub fn build_encrypted_extensions(
  alpn: String,
  transport_params: BitArray,
) -> BitArray {
  let exts =
    extensions.encode_list([
      Extension(extensions.alpn_ext, extensions.encode_alpn(alpn)),
      Extension(extensions.quic_transport_parameters_ext, transport_params),
    ])
  handshake_message.encode(handshake_message.encrypted_extensions_type, exts)
}

/// Builds a Certificate message from a DER certificate chain, leaf
/// first, with an empty certificate_request_context and no per-entry
/// extensions.
pub fn build_certificate(chain: List(BitArray)) -> BitArray {
  let entries =
    list.fold(chain, <<>>, fn(acc, der) {
      <<acc:bits, bit_array.byte_size(der):24, der:bits, 0:16>>
    })
  let body = <<0:8, bit_array.byte_size(entries):24, entries:bits>>
  handshake_message.encode(handshake_message.certificate_type, body)
}

/// Builds a CertificateVerify message from a signature scheme code and
/// signature bytes.
pub fn build_certificate_verify(
  scheme_code: Int,
  signature: BitArray,
) -> BitArray {
  let body = <<
    scheme_code:16,
    bit_array.byte_size(signature):16,
    signature:bits,
  >>
  handshake_message.encode(handshake_message.certificate_verify_type, body)
}

/// Builds a Finished message from computed verify data.
pub fn build_finished(verify_data: BitArray) -> BitArray {
  handshake_message.encode(handshake_message.finished_type, verify_data)
}

/// The bytes a server signs for CertificateVerify (RFC 8446
/// Section 4.4.3): 64 spaces, a context string, a zero byte, and the
/// transcript hash.
pub fn certificate_verify_content(transcript_hash: BitArray) -> BitArray {
  <<
    bit_array.from_string(string.repeat(" ", 64)):bits,
    "TLS 1.3, server CertificateVerify":utf8,
    0:8,
    transcript_hash:bits,
  >>
}
