import aether/protocol/tls/handshake.{
  Config, HandshakeComplete, HandshakeLevel, HandshakeSecrets, InitialLevel,
  SendHandshakeData,
}
import aether/protocol/tls/handshake_message
import aether/protocol/tls/key_schedule
import aether/protocol/tls/rfc8448_vectors as v
import aether/protocol/tls/server
import aether/protocol/tls/tls_crypto
import gleam/bit_array
import gleam/list
import gleeunit/should

fn hex(string: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(string)
  bytes
}

// ── ServerHello construction is byte-exact against RFC 8448 §3 ───────────
//
// The RFC 8448 trace is plain TLS 1.3 (no ALPN, no QUIC transport
// parameters), so it cannot drive the QUIC `process` flow, but the
// ServerHello bytes depend only on the server random, the echoed session
// id (empty here), and the server's x25519 key share.

pub fn build_server_hello_matches_rfc8448_test() {
  let assert Ok(random) = bit_array.slice(hex(v.server_hello), 6, 32)
  server.build_server_hello(random, <<>>, hex(v.server_ephemeral_public))
  |> should.equal(hex(v.server_hello))
}

// ── End-to-end QUIC handshake against the EC P-256 fixture ───────────────
//
// A minimal test-only client runs a full handshake with the committed
// certificate fixture, exercising the ECDSA signature path, ALPN, QUIC
// transport parameters, and the client Finished verification.

pub fn full_handshake_with_fixture_test() {
  let assert Ok(server_hs) = fixture_server(["h3"])

  let #(client_public, client_private) = tls_crypto.x25519_generate()
  let client_hello = test_client_hello(client_public)

  let assert Ok(#(server_hs, events)) =
    handshake.process(server_hs, InitialLevel, client_hello)

  let assert Ok(SendHandshakeData(InitialLevel, server_hello)) =
    find_send(events, InitialLevel)
  let assert Ok(SendHandshakeData(HandshakeLevel, flight)) =
    find_send(events, HandshakeLevel)
  let assert Ok(HandshakeSecrets(client_hs_secret, server_hs_secret)) =
    list.find(events, is_hs_secrets)

  // Client reproduces the handshake traffic secrets from its own view.
  let assert Ok(sh_public) = server_hello_key_share(server_hello)
  let assert Ok(shared) = tls_crypto.x25519_shared(sh_public, client_private)
  let transcript =
    key_schedule.new_transcript()
    |> key_schedule.add(client_hello)
    |> key_schedule.add(server_hello)
  let handshake_secret =
    key_schedule.handshake_secret(key_schedule.early_secret(), shared)
  key_schedule.client_hs_traffic(
    handshake_secret,
    key_schedule.hash(transcript),
  )
  |> should.equal(client_hs_secret)
  key_schedule.server_hs_traffic(
    handshake_secret,
    key_schedule.hash(transcript),
  )
  |> should.equal(server_hs_secret)

  // Build the client Finished over the full transcript and complete.
  let transcript = add_flight(transcript, flight)
  let client_finished =
    server.build_finished(key_schedule.finished_verify_data(
      client_hs_secret,
      key_schedule.hash(transcript),
    ))

  let assert Ok(#(_server, complete_events)) =
    handshake.process(server_hs, HandshakeLevel, client_finished)
  let assert Ok(HandshakeComplete(alpn, transport_params)) =
    list.find(complete_events, is_complete)
  alpn |> should.equal("h3")
  transport_params |> should.equal(<<9, 9, 9>>)
}

pub fn rejects_bad_client_finished_test() {
  let assert Ok(server_hs) = fixture_server(["h3"])
  let #(client_public, _) = tls_crypto.x25519_generate()
  let assert Ok(#(server_hs, _)) =
    handshake.process(server_hs, InitialLevel, test_client_hello(client_public))

  handshake.process(server_hs, HandshakeLevel, server.build_finished(<<0:256>>))
  |> should.be_error
}

pub fn rejects_no_common_alpn_test() {
  let assert Ok(server_hs) = fixture_server(["h2"])
  let #(client_public, _) = tls_crypto.x25519_generate()
  handshake.process(server_hs, InitialLevel, test_client_hello(client_public))
  |> should.be_error
}

pub fn rejects_client_hello_at_wrong_level_test() {
  let assert Ok(server_hs) = fixture_server(["h3"])
  let #(client_public, _) = tls_crypto.x25519_generate()
  handshake.process(server_hs, HandshakeLevel, test_client_hello(client_public))
  |> should.be_error
}

// ── helpers ─────────────────────────────────────────────────────────────

fn find_send(events, level) {
  list.find(events, fn(e) {
    case e {
      SendHandshakeData(l, _) if l == level -> True
      _ -> False
    }
  })
}

fn is_hs_secrets(e) {
  case e {
    HandshakeSecrets(_, _) -> True
    _ -> False
  }
}

fn is_complete(e) {
  case e {
    HandshakeComplete(_, _) -> True
    _ -> False
  }
}

fn add_flight(transcript, flight) {
  let assert Ok(#(_, messages)) =
    handshake_message.push(handshake_message.new_buffer(), flight)
  list.fold(messages, transcript, fn(t, m) {
    key_schedule.add(t, handshake_message.encode(m.msg_type, m.body))
  })
}

/// Extracts the x25519 public key from our ServerHello: it is the last
/// 32 bytes of the key_share extension, which precedes the 6-byte
/// supported_versions extension that ends the message.
fn server_hello_key_share(server_hello: BitArray) -> Result(BitArray, Nil) {
  let size = bit_array.byte_size(server_hello)
  bit_array.slice(server_hello, size - 32 - 6, 32)
}

fn fixture_server(alpn: List(String)) -> Result(handshake.Handshake, Nil) {
  use cert_pem <- result_try(read_fixture("test/fixtures/tls/cert.pem"))
  use key_pem <- result_try(read_fixture("test/fixtures/tls/key.pem"))
  use chain <- result_try(tls_crypto.decode_pem_certificates(cert_pem))
  use key <- result_try(tls_crypto.decode_pem_private_key(key_pem))
  Ok(
    handshake.new(
      Config(
        certificate_chain: chain,
        private_key: key,
        alpn: alpn,
        transport_params: <<7, 7, 7>>,
      ),
    ),
  )
}

fn result_try(r: Result(a, Nil), f: fn(a) -> Result(b, Nil)) -> Result(b, Nil) {
  case r {
    Ok(v) -> f(v)
    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "aether_tls_ffi", "read_file")
fn read_fixture(path: String) -> Result(BitArray, Nil)

/// Builds a complete (framed) ClientHello offering TLS 1.3, x25519 with
/// the given public key, ecdsa+rsa signatures, ALPN h3, and QUIC
/// transport parameters 0x090909.
fn test_client_hello(x25519_public: BitArray) -> BitArray {
  let exts =
    ext(43, <<2:8, 0x0304:16>>)
    |> bappend(ext(10, <<2:16, 0x001d:16>>))
    |> bappend(ext(13, <<4:16, 0x0403:16, 0x0804:16>>))
    |> bappend(ext(51, <<36:16, 0x001d:16, 32:16, x25519_public:bits>>))
    |> bappend(ext(16, alpn_ext_body(["h3"])))
    |> bappend(ext(0x39, <<9, 9, 9>>))

  let body = <<
    0x0303:16,
    0:256,
    0:8,
    2:16,
    0x1301:16,
    1:8,
    0:8,
    bit_array.byte_size(exts):16,
    exts:bits,
  >>
  handshake_message.encode(handshake_message.client_hello_type, body)
}

fn ext(ext_type: Int, data: BitArray) -> BitArray {
  <<ext_type:16, bit_array.byte_size(data):16, data:bits>>
}

fn bappend(a: BitArray, b: BitArray) -> BitArray {
  <<a:bits, b:bits>>
}

fn alpn_ext_body(protocols: List(String)) -> BitArray {
  let list_bytes =
    list.fold(protocols, <<>>, fn(acc, p) {
      let bytes = bit_array.from_string(p)
      <<acc:bits, bit_array.byte_size(bytes):8, bytes:bits>>
    })
  <<bit_array.byte_size(list_bytes):16, list_bytes:bits>>
}
