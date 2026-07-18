import aether/protocol/quic/server
import aether/protocol/tls/handshake.{Config}
import aether/protocol/tls/tls_crypto
import gleam/bit_array
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleeunit/should

// ─────────────────────────────────────────────────────────────────────────
// Lifecycle: start on an ephemeral port, check it landed on a real port,
// stop it. This drives the actual UDP socket (bind + close); it does not
// exercise a datagram round-trip, which is covered at the connection level.
// ─────────────────────────────────────────────────────────────────────────

pub fn start_stop_smoke_test() {
  let assert Ok(config) = fixture_config(["h3"])
  let assert Ok(started) = server.start(0, config, echo_handler)

  { server.port(started) > 0 } |> should.be_true()

  server.stop(started)
}

pub fn start_on_two_servers_gets_different_ports_test() {
  let assert Ok(config) = fixture_config(["h3"])
  let assert Ok(a) = server.start(0, config, echo_handler)
  let assert Ok(b) = server.start(0, config, echo_handler)

  { server.port(a) != server.port(b) } |> should.be_true()

  server.stop(a)
  server.stop(b)
}

fn echo_handler(_req: Request(BitArray)) -> Response(BitArray) {
  response.new(200) |> response.set_body(<<>>)
}

fn fixture_config(alpn: List(String)) -> Result(handshake.Config, Nil) {
  use cert_pem <- result_try(read_fixture("test/fixtures/tls/cert.pem"))
  use key_pem <- result_try(read_fixture("test/fixtures/tls/key.pem"))
  use chain <- result_try(tls_crypto.decode_pem_certificates(cert_pem))
  use key <- result_try(tls_crypto.decode_pem_private_key(key_pem))
  Ok(
    Config(
      certificate_chain: chain,
      private_key: key,
      alpn: alpn,
      transport_params: <<>>,
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

// ─────────────────────────────────────────────────────────────────────────
// route_key: DCID extraction used to look up (or start) a connection.
// ─────────────────────────────────────────────────────────────────────────

pub fn route_key_long_header_test() {
  let dcid = <<1, 2, 3, 4, 5, 6, 7, 8>>
  let datagram =
    bit_array.concat([
      // first byte: form=1 fixed=1 type=Initial(00) reserved=00 pn_len=00
      <<0xc0:8>>,
      // version
      <<0x00000001:32>>,
      // dcid length + dcid
      <<8:8>>,
      dcid,
      // scid length 0, token length varint 0, a couple of payload bytes
      <<0:8>>,
      <<0:8>>,
      <<0, 0, 0, 0>>,
    ])

  server.route_key(datagram) |> should.equal(Ok(dcid))
}

pub fn route_key_long_header_with_nonzero_scid_test() {
  let dcid = <<0xaa, 0xbb, 0xcc, 0xdd>>
  let scid = <<9, 9, 9, 9, 9, 9, 9, 9>>
  let datagram =
    bit_array.concat([
      <<0xc3:8>>,
      <<0x00000001:32>>,
      <<4:8>>,
      dcid,
      <<8:8>>,
      scid,
      <<0:8>>,
    ])

  server.route_key(datagram) |> should.equal(Ok(dcid))
}

pub fn route_key_short_header_test() {
  let dcid = <<10, 20, 30, 40, 50, 60, 70, 80>>
  // first byte: form=0 (short header), fixed=1, remaining bits arbitrary
  let datagram = bit_array.concat([<<0x40:8>>, dcid, <<1, 2, 3>>])

  server.route_key(datagram) |> should.equal(Ok(dcid))
}

pub fn route_key_too_short_is_error_test() {
  server.route_key(<<0xc0:8, 0, 0>>) |> should.equal(Error(Nil))
  server.route_key(<<>>) |> should.equal(Error(Nil))
}
