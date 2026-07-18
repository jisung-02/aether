//// End-to-end connection test: a test-only QUIC + TLS 1.3 client, built
//// from the same primitives as the server, drives a full handshake and an
//// HTTP/3 request against `connection`, proving the whole phase 1-6 stack
//// interoperates with itself.

import aether/protocol/http3/frame as h3
import aether/protocol/http3/qpack
import aether/protocol/quic/assembly
import aether/protocol/quic/connection
import aether/protocol/quic/crypto.{Aes128Gcm}
import aether/protocol/quic/frame.{Crypto, Stream}
import aether/protocol/quic/frame_builder
import aether/protocol/quic/frame_parser
import aether/protocol/quic/keys.{type PacketKeys}
import aether/protocol/quic/packet.{Handshake, Initial, OneRtt}
import aether/protocol/quic/packet_protection
import aether/protocol/tls/extensions
import aether/protocol/tls/handshake
import aether/protocol/tls/handshake_message
import aether/protocol/tls/key_schedule
import aether/protocol/tls/tls_crypto
import gleam/bit_array
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleeunit/should

const dcid = <<1, 2, 3, 4, 5, 6, 7, 8>>

const server_scid = <<0xa, 0xb, 0xc, 0xd, 0xe, 0xf, 0x1, 0x2>>

const client_scid = <<9, 9, 9, 9, 9, 9, 9, 9>>

@external(erlang, "aether_tls_ffi", "read_file")
fn read_file(path: String) -> Result(BitArray, Nil)

fn make_server() -> connection.Connection {
  let assert Ok(cert_pem) = read_file("test/fixtures/tls/cert.pem")
  let assert Ok(key_pem) = read_file("test/fixtures/tls/key.pem")
  let assert Ok(chain) = tls_crypto.decode_pem_certificates(cert_pem)
  let assert Ok(key) = tls_crypto.decode_pem_private_key(key_pem)
  let config =
    handshake.Config(
      certificate_chain: chain,
      private_key: key,
      alpn: ["h3"],
      transport_params: <<7, 7, 7>>,
    )
  connection.new(config, server_scid, handler)
}

fn handler(req: Request(BitArray)) -> Response(BitArray) {
  response.new(200)
  |> response.set_header("content-type", "text/plain")
  |> response.set_body(<<"path=":utf8, req.path:utf8>>)
}

pub fn full_handshake_and_request_test() {
  let server = make_server()
  let #(client_public, client_private) = tls_crypto.x25519_generate()
  let #(client_initial_keys, server_initial_keys) = keys.initial_keys(dcid)

  // ---- Client Initial: ClientHello in a CRYPTO frame, padded to 1200 ----
  let client_hello = build_client_hello(client_public)
  let assert Ok(ch_payload) =
    frame_builder.build_frames([Crypto(0, client_hello)])
  let assert Ok(initial_packet) =
    assembly.initial_packet(
      client_initial_keys,
      dcid,
      client_scid,
      <<>>,
      0,
      4,
      ch_payload,
    )
  let client_initial = assembly.pad_datagram(initial_packet, 1200)

  let #(server, out1) = connection.receive(server, client_initial, 1000)
  { list.length(out1) >= 1 } |> should.equal(True)

  // ---- Client reads the server flight (Initial ServerHello, then the
  // coalesced Handshake packet decrypted with keys derived from it) ----
  let assert Ok(server_flight) = list.first(out1)
  let assert Ok(#(Initial(protected: initial_protected, ..), after_initial)) =
    packet.parse_long(server_flight)
  let initial_header =
    header_of(server_flight, after_initial, initial_protected)
  let assert Ok(#(_, initial_plain)) =
    packet_protection.unprotect(
      server_initial_keys,
      initial_header,
      initial_protected,
      -1,
    )
  let server_hello = crypto_bytes(initial_plain)

  // Client key schedule.
  let assert Ok(server_share) = server_hello_key_share(server_hello)
  let assert Ok(shared) = tls_crypto.x25519_shared(server_share, client_private)
  let transcript =
    key_schedule.new_transcript()
    |> key_schedule.add(client_hello)
    |> key_schedule.add(server_hello)
  let handshake_secret =
    key_schedule.handshake_secret(key_schedule.early_secret(), shared)
  let hello_hash = key_schedule.hash(transcript)
  let client_hs = key_schedule.client_hs_traffic(handshake_secret, hello_hash)
  let server_hs = key_schedule.server_hs_traffic(handshake_secret, hello_hash)
  let handshake_read = keys.from_secret(Aes128Gcm, server_hs)
  let handshake_write = keys.from_secret(Aes128Gcm, client_hs)

  // Decrypt the coalesced Handshake packet with the server handshake keys.
  // `after_initial` still has the datagram's trailing PADDING, so use the
  // remainder parse_long reports to size the header correctly.
  let assert Ok(#(Handshake(protected: hs_protected, ..), hs_rest)) =
    packet.parse_long(after_initial)
  let hs_header = header_of(after_initial, hs_rest, hs_protected)
  let assert Ok(#(_, hs_plain)) =
    packet_protection.unprotect(handshake_read, hs_header, hs_protected, -1)
  let handshake_crypto = crypto_bytes(hs_plain)

  // Application secrets and the client Finished (over the full transcript).
  let transcript = add_messages(transcript, handshake_crypto)
  let finished_hash = key_schedule.hash(transcript)
  let master = key_schedule.master_secret(handshake_secret)
  let server_ap = key_schedule.server_ap_traffic(master, finished_hash)
  let client_ap = key_schedule.client_ap_traffic(master, finished_hash)
  let client_finished =
    handshake_message.encode(
      handshake_message.finished_type,
      key_schedule.finished_verify_data(client_hs, finished_hash),
    )

  // ---- Client Handshake packet carrying the client Finished ----
  let assert Ok(fin_payload) =
    frame_builder.build_frames([Crypto(0, client_finished)])
  let assert Ok(client_handshake) =
    assembly.handshake_packet(
      handshake_write,
      dcid,
      client_scid,
      0,
      4,
      fin_payload,
    )
  let #(server, _out2) = connection.receive(server, client_handshake, 2000)
  connection.is_established(server) |> should.equal(True)
  connection.negotiated_alpn(server) |> should.equal(Ok("h3"))

  // ---- HTTP/3 GET on a 1-RTT request stream ----
  let app_write = keys.from_secret(Aes128Gcm, client_ap)
  let app_read = keys.from_secret(Aes128Gcm, server_ap)
  let header_block =
    qpack.encode([
      #(":method", "GET"),
      #(":scheme", "https"),
      #(":authority", "localhost"),
      #(":path", "/hi"),
    ])
  let request_bytes = h3.build(h3.Headers(header_block))
  let assert Ok(request_payload) =
    frame_builder.build_frames([Stream(0, 0, request_bytes, True)])
  let assert Ok(client_1rtt) =
    assembly.one_rtt_packet(app_write, dcid, 0, 4, request_payload)

  let #(_server, out3) = connection.receive(server, client_1rtt, 3000)
  extract_response_body(out3, app_read) |> should.equal(<<"path=/hi":utf8>>)
}

// ── client helpers ───────────────────────────────────────────────────────

fn header_of(
  datagram: BitArray,
  remaining: BitArray,
  protected: BitArray,
) -> BitArray {
  let len =
    bit_array.byte_size(datagram)
    - bit_array.byte_size(remaining)
    - bit_array.byte_size(protected)
  let assert Ok(header) = bit_array.slice(datagram, 0, len)
  header
}

fn crypto_bytes(plaintext: BitArray) -> BitArray {
  let assert Ok(frames) = frame_parser.parse_frames(plaintext)
  list.fold(frames, <<>>, fn(acc, f) {
    case f {
      Crypto(_, data) -> <<acc:bits, data:bits>>
      _ -> acc
    }
  })
}

fn add_messages(
  transcript: key_schedule.Transcript,
  bytes: BitArray,
) -> key_schedule.Transcript {
  let assert Ok(#(_, messages)) =
    handshake_message.push(handshake_message.new_buffer(), bytes)
  list.fold(messages, transcript, fn(t, m) {
    key_schedule.add(t, handshake_message.encode(m.msg_type, m.body))
  })
}

fn server_hello_key_share(server_hello: BitArray) -> Result(BitArray, Nil) {
  case server_hello {
    <<
      _type_len:32,
      _legacy_version:16,
      _random:bytes-size(32),
      session_id_len:8,
      _session_id:bytes-size(session_id_len),
      _cipher:16,
      _comp:8,
      _ext_len:16,
      exts:bits,
    >> ->
      case extensions.parse_list(prefix_length(exts)) {
        Ok(items) ->
          case extensions.find(items, extensions.key_share_ext) {
            Ok(<<_group:16, _len:16, key:bytes-size(32)>>) -> Ok(key)
            _ -> Error(Nil)
          }
        Error(_) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn prefix_length(exts: BitArray) -> BitArray {
  <<bit_array.byte_size(exts):16, exts:bits>>
}

fn extract_response_body(
  datagrams: List(BitArray),
  app_read: PacketKeys,
) -> BitArray {
  list.fold(datagrams, <<>>, fn(acc, datagram) {
    case bit_array.byte_size(acc) > 0 {
      True -> acc
      False -> decrypt_response(datagram, app_read)
    }
  })
}

fn decrypt_response(datagram: BitArray, app_read: PacketKeys) -> BitArray {
  case packet.parse_short(datagram, 8) {
    Ok(#(OneRtt(protected: protected, ..), _)) -> {
      let header = header_of(datagram, <<>>, protected)
      case packet_protection.unprotect(app_read, header, protected, -1) {
        Ok(#(_, plaintext)) -> response_body_from_frames(plaintext)
        Error(_) -> <<>>
      }
    }
    _ -> <<>>
  }
}

fn response_body_from_frames(plaintext: BitArray) -> BitArray {
  case frame_parser.parse_frames(plaintext) {
    Ok(frames) ->
      list.fold(frames, <<>>, fn(acc, f) {
        case f {
          Stream(0, _, data, _) -> <<acc:bits, decode_h3_body(data):bits>>
          _ -> acc
        }
      })
    Error(_) -> <<>>
  }
}

fn decode_h3_body(stream_bytes: BitArray) -> BitArray {
  case h3.parse(stream_bytes) {
    Ok(#(frames, _)) ->
      list.fold(frames, <<>>, fn(acc, f) {
        case f {
          h3.Data(d) -> <<acc:bits, d:bits>>
          _ -> acc
        }
      })
    Error(_) -> <<>>
  }
}

fn build_client_hello(x25519_public: BitArray) -> BitArray {
  let exts =
    ext(43, <<2:8, 0x0304:16>>)
    |> app(ext(10, <<2:16, 0x001d:16>>))
    |> app(ext(13, <<4:16, 0x0403:16, 0x0804:16>>))
    |> app(ext(51, <<36:16, 0x001d:16, 32:16, x25519_public:bits>>))
    |> app(ext(16, <<3:16, 2:8, "h3":utf8>>))
    |> app(ext(0x39, <<9, 9, 9>>))

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

fn app(a: BitArray, b: BitArray) -> BitArray {
  <<a:bits, b:bits>>
}
