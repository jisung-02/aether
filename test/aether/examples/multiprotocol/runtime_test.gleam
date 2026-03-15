import aether/examples/multiprotocol/runtime
import aether/examples/multiprotocol/server
import gleam/option.{None, Some}
import gleeunit/should

pub fn build_runtime_config_defaults_to_cleartext_test() {
  let assert Ok(config) = runtime.build_runtime_config(None, None, None)

  config.mode
  |> should.equal(runtime.CleartextH2c)

  config.server_config.port
  |> should.equal(3000)

  config.server_config.tls
  |> should.equal(None)
}

pub fn build_runtime_config_uses_tls_when_cert_and_key_exist_test() {
  let assert Ok(config) =
    runtime.build_runtime_config(
      Some("/tmp/cert.pem"),
      Some("/tmp/key.pem"),
      Some("3443"),
    )

  config.mode
  |> should.equal(runtime.TlsAlpn)

  config.server_config.port
  |> should.equal(3443)

  case config.server_config.tls {
    Some(server.TlsConfig(cert_path:, key_path:)) -> {
      cert_path |> should.equal("/tmp/cert.pem")
      key_path |> should.equal("/tmp/key.pem")
    }
    None -> panic as "Expected TLS config"
  }
}

pub fn build_runtime_config_rejects_invalid_port_test() {
  runtime.build_runtime_config(None, None, Some("abc"))
  |> should.equal(Error(runtime.InvalidPort("abc")))
}

pub fn build_runtime_config_rejects_partial_tls_config_test() {
  runtime.build_runtime_config(Some("/tmp/cert.pem"), None, None)
  |> should.equal(
    Error(runtime.PartialTlsConfiguration(missing: "AETHER_TLS_KEY")),
  )
}
