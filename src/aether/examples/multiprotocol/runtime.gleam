import aether/examples/multiprotocol/server
import gleam/int
import gleam/option.{type Option, None, Some, from_result}
import gleam/result

pub type LaunchMode {
  CleartextH2c
  TlsAlpn
}

pub type RuntimeConfig {
  RuntimeConfig(server_config: server.ServerConfig, mode: LaunchMode)
}

pub type RuntimeConfigError {
  InvalidPort(value: String)
  PartialTlsConfiguration(missing: String)
}

pub fn load_from_env() -> Result(RuntimeConfig, RuntimeConfigError) {
  build_runtime_config(
    env_var("AETHER_TLS_CERT"),
    env_var("AETHER_TLS_KEY"),
    env_var("AETHER_PORT"),
  )
}

pub fn build_runtime_config(
  cert_path: Option(String),
  key_path: Option(String),
  port_value: Option(String),
) -> Result(RuntimeConfig, RuntimeConfigError) {
  case cert_path, key_path {
    Some(cert), Some(key) -> {
      let port =
        parse_port(port_value, default_port(TlsAlpn))
        |> result.map_error(InvalidPort)

      port
      |> result.map(fn(port) {
        RuntimeConfig(
          server_config: server.new_config()
            |> server.with_port(port)
            |> server.with_tls(cert, key),
          mode: TlsAlpn,
        )
      })
    }
    None, None -> {
      parse_port(port_value, default_port(CleartextH2c))
      |> result.map_error(InvalidPort)
      |> result.map(fn(port) {
        RuntimeConfig(
          server_config: server.new_config() |> server.with_port(port),
          mode: CleartextH2c,
        )
      })
    }
    Some(_), None -> Error(PartialTlsConfiguration(missing: "AETHER_TLS_KEY"))
    None, Some(_) -> Error(PartialTlsConfiguration(missing: "AETHER_TLS_CERT"))
  }
}

pub fn default_port(mode: LaunchMode) -> Int {
  case mode {
    CleartextH2c -> 3000
    TlsAlpn -> 3443
  }
}

pub fn mode_to_string(mode: LaunchMode) -> String {
  case mode {
    CleartextH2c -> "cleartext HTTP/1.1 + h2c"
    TlsAlpn -> "TLS ALPN HTTP/1.1 + HTTP/2"
  }
}

pub fn error_to_string(error: RuntimeConfigError) -> String {
  case error {
    InvalidPort(value) -> "Invalid port in AETHER_PORT: " <> value
    PartialTlsConfiguration(missing) ->
      "TLS configuration is incomplete. Missing " <> missing
  }
}

fn parse_port(port_value: Option(String), fallback: Int) -> Result(Int, String) {
  case port_value {
    Some(value) -> {
      case int.parse(value) {
        Ok(port) -> Ok(port)
        Error(_) -> Error(value)
      }
    }
    None -> Ok(fallback)
  }
}

fn env_var(name: String) -> Option(String) {
  getenv(name)
  |> from_result()
}

@external(erlang, "aether_examples_runtime_ffi", "getenv")
fn getenv(name: String) -> Result(String, Nil)
