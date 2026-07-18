//// A runnable HTTP/3-over-QUIC example server.
////
//// Loads the repo's dev TLS fixtures, offers the `h3` ALPN protocol, and
//// answers every request with a fixed "Hello from Aether HTTP/3" body.
//// Run with `gleam run -m aether/examples/http3/server` from the repo
//// root (the certificate paths are relative to the current directory).
////
//// ponytail: one handler for every path/method — see
//// `aether/protocol/quic/server` for the runtime this drives.

import aether/protocol/quic/server
import aether/protocol/quic/transport_params
import aether/protocol/tls/handshake.{Config}
import aether/protocol/tls/tls_crypto
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io

/// The default port the example listens on.
pub const default_port = 4433

/// Loads the dev TLS fixtures, builds the QUIC/TLS config, and starts the
/// UDP runtime on `default_port`.
pub fn start() -> Result(server.Server, String) {
  use config <- result_try(load_config())
  server.start(default_port, config, handle_request)
}

/// Entry point for `gleam run`: starts the server and blocks forever.
pub fn main() -> Nil {
  case start() {
    Ok(started) -> {
      io.println(
        "aether http3 example listening on udp/"
        <> int.to_string(server.port(started)),
      )
      process.sleep_forever()
    }
    Error(reason) -> io.println("failed to start http3 example: " <> reason)
  }
}

fn handle_request(_req: Request(BitArray)) -> Response(BitArray) {
  response.new(200)
  |> response.set_header("content-type", "text/plain")
  |> response.set_body(<<"Hello from Aether HTTP/3\n":utf8>>)
}

// ─────────────────────────────────────────────────────────────────────────
// TLS config
// ─────────────────────────────────────────────────────────────────────────

fn load_config() -> Result(handshake.Config, String) {
  use cert_pem <- result_try(read_fixture("test/fixtures/tls/cert.pem"))
  use key_pem <- result_try(read_fixture("test/fixtures/tls/key.pem"))
  use chain <- result_try(
    tls_crypto.decode_pem_certificates(cert_pem)
    |> nil_to_string("could not decode test/fixtures/tls/cert.pem"),
  )
  use key <- result_try(
    tls_crypto.decode_pem_private_key(key_pem)
    |> nil_to_string("could not decode test/fixtures/tls/key.pem"),
  )
  use params <- result_try(
    transport_params.encode(transport_params.new())
    |> wire_error_to_string,
  )
  Ok(Config(
    certificate_chain: chain,
    private_key: key,
    alpn: ["h3"],
    transport_params: params,
  ))
}

fn read_fixture(path: String) -> Result(BitArray, String) {
  case read_file(path) {
    Ok(bytes) -> Ok(bytes)
    Error(Nil) -> Error("could not read " <> path)
  }
}

@external(erlang, "aether_tls_ffi", "read_file")
fn read_file(path: String) -> Result(BitArray, Nil)

fn nil_to_string(result: Result(a, Nil), message: String) -> Result(a, String) {
  case result {
    Ok(value) -> Ok(value)
    Error(Nil) -> Error(message)
  }
}

fn wire_error_to_string(result: Result(a, e)) -> Result(a, String) {
  case result {
    Ok(value) -> Ok(value)
    Error(_) -> Error("could not encode transport parameters")
  }
}

fn result_try(
  result: Result(a, String),
  next: fn(a) -> Result(b, String),
) -> Result(b, String) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}
