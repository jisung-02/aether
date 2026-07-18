import aether/protocol/quic/error.{Malformed}
import aether/protocol/tls/client_hello.{parse}
import aether/protocol/tls/extensions.{
  alpn_ext, find, key_share_ext, parse_alpn, parse_key_shares, parse_server_name,
  parse_signature_algorithms, parse_supported_groups, parse_supported_versions,
  server_name_ext, signature_algorithms_ext, supported_groups_ext,
  supported_versions_ext,
}
import aether/protocol/tls/rfc8448_vectors
import gleam/bit_array
import gleam/list
import gleeunit/should

fn hex(input: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(input)
  bytes
}

/// The RFC 8448 ClientHello with its 4-byte handshake header stripped.
fn rfc_client_hello_body() -> BitArray {
  let message = hex(rfc8448_vectors.client_hello)
  let assert Ok(body) =
    bit_array.slice(message, 4, bit_array.byte_size(message) - 4)
  body
}

pub fn parse_rfc8448_client_hello_random_test() {
  let message = hex(rfc8448_vectors.client_hello)
  let assert Ok(expected_random) = bit_array.slice(message, 6, 32)
  let assert Ok(hello) = parse(rfc_client_hello_body())
  hello.random |> should.equal(expected_random)
}

pub fn parse_rfc8448_client_hello_session_id_is_empty_test() {
  let assert Ok(hello) = parse(rfc_client_hello_body())
  hello.legacy_session_id |> should.equal(<<>>)
}

pub fn parse_rfc8448_client_hello_cipher_suites_test() {
  let assert Ok(hello) = parse(rfc_client_hello_body())
  hello.cipher_suites |> should.equal([0x1301, 0x1303, 0x1302])
}

pub fn parse_rfc8448_client_hello_sni_test() {
  let assert Ok(hello) = parse(rfc_client_hello_body())
  let assert Ok(sni_data) = find(hello.extensions, server_name_ext)
  parse_server_name(sni_data) |> should.equal(Ok("server"))
}

pub fn parse_rfc8448_client_hello_supported_versions_test() {
  let assert Ok(hello) = parse(rfc_client_hello_body())
  let assert Ok(data) = find(hello.extensions, supported_versions_ext)
  let assert Ok(versions) = parse_supported_versions(data)
  list.contains(versions, 0x0304) |> should.be_true()
}

pub fn parse_rfc8448_client_hello_supported_groups_test() {
  let assert Ok(hello) = parse(rfc_client_hello_body())
  let assert Ok(data) = find(hello.extensions, supported_groups_ext)
  let assert Ok(groups) = parse_supported_groups(data)
  case groups {
    [first, ..] -> first |> should.equal(0x001d)
    [] -> should.fail()
  }
}

pub fn parse_rfc8448_client_hello_key_shares_test() {
  let assert Ok(hello) = parse(rfc_client_hello_body())
  let assert Ok(data) = find(hello.extensions, key_share_ext)
  let assert Ok(shares) = parse_key_shares(data)
  let expected_key = hex(rfc8448_vectors.client_ephemeral_public)
  list.contains(shares, #(0x001d, expected_key)) |> should.be_true()
}

pub fn parse_rfc8448_client_hello_signature_algorithms_test() {
  let assert Ok(hello) = parse(rfc_client_hello_body())
  let assert Ok(data) = find(hello.extensions, signature_algorithms_ext)
  let assert Ok(schemes) = parse_signature_algorithms(data)
  list.contains(schemes, 0x0403) |> should.be_true()
  list.contains(schemes, 0x0804) |> should.be_true()
}

pub fn parse_rejects_truncated_legacy_version_and_random_test() {
  case parse(<<0x03, 0x03, 0x01, 0x02>>) {
    Error(Malformed(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_rejects_session_id_over_32_bytes_test() {
  let random = <<0:size(256)>>
  let body =
    bit_array.concat([<<0x03, 0x03>>, random, <<33:8>>, <<0:size(264)>>])
  case parse(body) {
    Error(Malformed(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_rejects_empty_cipher_suites_test() {
  let random = <<0:size(256)>>
  let body = bit_array.concat([<<0x03, 0x03>>, random, <<0:8>>, <<0:16>>])
  parse(body)
  |> should.equal(Error(Malformed("cipher_suites must not be empty")))
}

pub fn parse_rejects_empty_compression_methods_test() {
  let random = <<0:size(256)>>
  let body =
    bit_array.concat([
      <<0x03, 0x03>>,
      random,
      <<0:8>>,
      // session id
      <<2:16, 0x13, 0x01>>,
      // cipher_suites: one entry
      <<0:8>>,
      // compression methods: empty (invalid)
    ])
  parse(body)
  |> should.equal(
    Error(Malformed("legacy_compression_methods must not be empty")),
  )
}

pub fn parse_requires_extensions_to_consume_the_rest_exactly_test() {
  let random = <<0:size(256)>>
  let body =
    bit_array.concat([
      <<0x03, 0x03>>,
      random,
      <<0:8>>,
      // session id
      <<2:16, 0x13, 0x01>>,
      // cipher_suites
      <<1:8, 0:8>>,
      // compression methods
      <<0:16>>,
      // extensions: declares zero length
      <<0xff, 0xff>>,
      // trailing garbage
    ])
  case parse(body) {
    Error(Malformed(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_client_hello_with_alpn_extension_test() {
  // A minimal ClientHello carrying only an ALPN extension.
  let random = <<0:size(256)>>
  let alpn_data = extensions.encode_alpn("h3")
  let ext =
    bit_array.concat([
      <<alpn_ext:16, bit_array.byte_size(alpn_data):16>>,
      alpn_data,
    ])
  let body =
    bit_array.concat([
      <<0x03, 0x03>>,
      random,
      <<0:8>>,
      <<2:16, 0x13, 0x01>>,
      <<1:8, 0:8>>,
      bit_array.concat([<<bit_array.byte_size(ext):16>>, ext]),
    ])
  let assert Ok(hello) = parse(body)
  let assert Ok(data) = find(hello.extensions, alpn_ext)
  parse_alpn(data) |> should.equal(Ok(["h3"]))
}
