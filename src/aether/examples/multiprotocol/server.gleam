import gleam/http.{type Scheme, Http, Https}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}
import glisten
import mist
import mist/internal/handler as mist_handler
import mist/internal/http as internal_http

pub type TlsConfig {
  TlsConfig(cert_path: String, key_path: String)
}

pub type ServerConfig {
  ServerConfig(
    port: Int,
    interface: String,
    ipv6: Bool,
    enable_http2: Bool,
    tls: Option(TlsConfig),
  )
}

pub fn new_config() -> ServerConfig {
  ServerConfig(
    port: 3000,
    interface: "localhost",
    ipv6: False,
    enable_http2: True,
    tls: None,
  )
}

pub fn with_port(config: ServerConfig, port: Int) -> ServerConfig {
  ServerConfig(..config, port: port)
}

pub fn with_interface(config: ServerConfig, interface: String) -> ServerConfig {
  ServerConfig(..config, interface: interface)
}

pub fn with_ipv6(config: ServerConfig, ipv6: Bool) -> ServerConfig {
  ServerConfig(..config, ipv6: ipv6)
}

pub fn with_http2(config: ServerConfig, enabled: Bool) -> ServerConfig {
  ServerConfig(..config, enable_http2: enabled)
}

pub fn with_tls(
  config: ServerConfig,
  cert_path: String,
  key_path: String,
) -> ServerConfig {
  ServerConfig(
    ..config,
    tls: Some(TlsConfig(cert_path: cert_path, key_path: key_path)),
  )
}

pub fn scheme(config: ServerConfig) -> Scheme {
  case config.tls {
    Some(_) -> Https
    None -> Http
  }
}

pub fn advertised_protocols(config: ServerConfig) -> List(String) {
  case config.tls, config.enable_http2 {
    Some(_), True -> ["h2", "http/1.1"]
    _, True -> ["h2c", "http/1.1"]
    _, False -> ["http/1.1"]
  }
}

pub fn start(
  config: ServerConfig,
  handler: fn(Request(mist.Connection)) -> Response(mist.ResponseData),
) -> Result(actor.Started(Supervisor), actor.StartError) {
  let internal_loop =
    fn(req) { convert_body_types(handler(req)) }
    |> mist_handler.with_func

  glisten.new(mist_handler.init, internal_loop)
  |> glisten.bind(config.interface)
  |> apply_ipv6(config)
  |> apply_tls(config)
  |> apply_http2(config)
  |> glisten.start(config.port)
}

fn apply_ipv6(
  builder: glisten.Builder(state, user_message),
  config: ServerConfig,
) -> glisten.Builder(state, user_message) {
  case config.ipv6 {
    True -> glisten.with_ipv6(builder)
    False -> builder
  }
}

fn apply_tls(
  builder: glisten.Builder(state, user_message),
  config: ServerConfig,
) -> glisten.Builder(state, user_message) {
  case config.tls {
    Some(tls) -> glisten.with_tls(builder, tls.cert_path, tls.key_path)
    None -> builder
  }
}

fn apply_http2(
  builder: glisten.Builder(state, user_message),
  config: ServerConfig,
) -> glisten.Builder(state, user_message) {
  case config.enable_http2 {
    True -> with_http2_support(builder)
    False -> builder
  }
}

fn convert_body_types(
  resp: Response(mist.ResponseData),
) -> Response(internal_http.ResponseData) {
  let new_body = case resp.body {
    mist.Websocket(selector) -> internal_http.Websocket(selector)
    mist.Bytes(data) -> internal_http.Bytes(data)
    mist.File(descriptor, offset, length) ->
      internal_http.File(descriptor, offset, length)
    mist.Chunked(iter) -> internal_http.Chunked(iter)
    mist.ServerSentEvents(selector) -> internal_http.ServerSentEvents(selector)
  }

  response.set_body(resp, new_body)
}

@external(erlang, "glisten", "with_http2")
fn with_http2_support(
  builder: glisten.Builder(state, user_message),
) -> glisten.Builder(state, user_message)
