//// The TLS 1.3 server handshake state machine as used by QUIC
//// (RFC 8446 + RFC 9001 Section 4). Consumes plaintext handshake
//// messages from CRYPTO streams (tagged with their encryption level)
//// and emits the messages to send back, the traffic secrets to install,
//// and the negotiated ALPN protocol and peer transport parameters.
//// QUIC packet protection is the caller's job; there is no record layer.
////
//// Supported: TLS_AES_128_GCM_SHA256, x25519, server authentication
//// with ecdsa_secp256r1_sha256 or rsa_pss_rsae_sha256, ALPN, and the
//// quic_transport_parameters extension. No HelloRetryRequest, PSK,
//// 0-RTT, or client certificates.

import aether/protocol/tls/client_hello.{type ClientHello}
import aether/protocol/tls/extensions
import aether/protocol/tls/handshake_message.{type HandshakeMessage}
import aether/protocol/tls/key_schedule.{type Transcript}
import aether/protocol/tls/server
import aether/protocol/tls/tls_crypto.{type SigningKey}
import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// QUIC encryption levels for CRYPTO data (RFC 9001 Section 4.1.3).
pub type Level {
  InitialLevel
  HandshakeLevel
  ApplicationLevel
}

/// Server configuration: a DER certificate chain (leaf first), its
/// signing key, ALPN protocols in server preference order, and the
/// already-encoded QUIC transport parameters to offer.
pub type Config {
  Config(
    certificate_chain: List(BitArray),
    private_key: SigningKey,
    alpn: List(String),
    transport_params: BitArray,
  )
}

/// Deterministic stand-ins for the random inputs, used by tests to
/// reproduce known handshakes. Production code uses `new`, which draws
/// both from a CSPRNG.
pub type Overrides {
  Overrides(
    server_random: Option(BitArray),
    ephemeral_private: Option(BitArray),
  )
}

/// TLS alerts this server can raise (RFC 8446 Section 6). The QUIC
/// layer maps them to CRYPTO_ERROR codes (0x100 + `alert_code`).
pub type Alert {
  UnexpectedMessage
  DecodeError
  DecryptError
  IllegalParameter
  HandshakeFailure
  ProtocolVersion
  MissingExtension
  NoApplicationProtocol
  InternalError
}

/// The wire code of an alert.
pub fn alert_code(alert: Alert) -> Int {
  case alert {
    UnexpectedMessage -> 10
    DecodeError -> 50
    DecryptError -> 51
    IllegalParameter -> 47
    HandshakeFailure -> 40
    ProtocolVersion -> 70
    MissingExtension -> 109
    NoApplicationProtocol -> 120
    InternalError -> 80
  }
}

/// What the QUIC layer must do in response to processed CRYPTO data,
/// in order.
pub type Event {
  /// Send these bytes on the CRYPTO stream of the given level.
  SendHandshakeData(level: Level, data: BitArray)
  /// Install handshake-level traffic secrets (derive packet keys with
  /// `quic/keys.from_secret`, AEAD is always Aes128Gcm here).
  HandshakeSecrets(client: BitArray, server: BitArray)
  /// Install application-level (1-RTT) traffic secrets.
  ApplicationSecrets(client: BitArray, server: BitArray)
  /// The handshake finished: the negotiated ALPN protocol and the
  /// client's raw quic_transport_parameters extension data.
  HandshakeComplete(alpn: String, client_transport_params: BitArray)
}

type State {
  AwaitClientHello
  AwaitFinished(
    expected_verify_data: BitArray,
    alpn: String,
    client_transport_params: BitArray,
  )
  Complete
}

/// An in-progress server handshake.
pub opaque type Handshake {
  Handshake(
    config: Config,
    overrides: Overrides,
    initial_buffer: handshake_message.Buffer,
    handshake_buffer: handshake_message.Buffer,
    state: State,
  )
}

/// Creates a server handshake awaiting a ClientHello.
pub fn new(config: Config) -> Handshake {
  new_with_overrides(config, Overrides(None, None))
}

/// Creates a server handshake with deterministic random inputs (tests).
pub fn new_with_overrides(config: Config, overrides: Overrides) -> Handshake {
  Handshake(
    config: config,
    overrides: overrides,
    initial_buffer: handshake_message.new_buffer(),
    handshake_buffer: handshake_message.new_buffer(),
    state: AwaitClientHello,
  )
}

/// Feeds CRYPTO stream bytes received at `level` into the handshake.
/// Returns the advanced handshake and the events to act on, or the
/// alert to send (which is fatal to the connection, RFC 9001 4.8).
pub fn process(
  handshake: Handshake,
  level: Level,
  data: BitArray,
) -> Result(#(Handshake, List(Event)), Alert) {
  use #(handshake, messages) <- result.try(buffer_push(handshake, level, data))
  use #(handshake, events) <- result.try(
    list.try_fold(messages, #(handshake, []), fn(acc, message) {
      let #(handshake, events) = acc
      use #(handshake, new_events) <- result.try(handle_message(
        handshake,
        level,
        message,
      ))
      Ok(#(handshake, list.append(events, new_events)))
    }),
  )
  Ok(#(handshake, events))
}

fn buffer_push(
  handshake: Handshake,
  level: Level,
  data: BitArray,
) -> Result(#(Handshake, List(HandshakeMessage)), Alert) {
  case level {
    InitialLevel ->
      case handshake_message.push(handshake.initial_buffer, data) {
        Ok(#(buffer, messages)) ->
          Ok(#(Handshake(..handshake, initial_buffer: buffer), messages))
        Error(_) -> Error(DecodeError)
      }
    HandshakeLevel ->
      case handshake_message.push(handshake.handshake_buffer, data) {
        Ok(#(buffer, messages)) ->
          Ok(#(Handshake(..handshake, handshake_buffer: buffer), messages))
        Error(_) -> Error(DecodeError)
      }
    // Clients send no CRYPTO data at the application level that we
    // accept (NewSessionTicket is server-to-client only).
    ApplicationLevel -> Error(UnexpectedMessage)
  }
}

fn handle_message(
  handshake: Handshake,
  level: Level,
  message: HandshakeMessage,
) -> Result(#(Handshake, List(Event)), Alert) {
  case handshake.state, level, message.msg_type {
    AwaitClientHello, InitialLevel, t
      if t == handshake_message.client_hello_type
    -> handle_client_hello(handshake, message.body)

    AwaitFinished(expected, alpn, client_tp), HandshakeLevel, t
      if t == handshake_message.finished_type
    ->
      case crypto.secure_compare(message.body, expected) {
        True ->
          Ok(
            #(Handshake(..handshake, state: Complete), [
              HandshakeComplete(alpn, client_tp),
            ]),
          )
        False -> Error(DecryptError)
      }

    _, _, _ -> Error(UnexpectedMessage)
  }
}

fn handle_client_hello(
  handshake: Handshake,
  body: BitArray,
) -> Result(#(Handshake, List(Event)), Alert) {
  use hello <- result.try(
    client_hello.parse(body) |> result.replace_error(DecodeError),
  )
  use Nil <- result.try(check_offers_tls13(hello))
  use Nil <- result.try(check_offers_suite(hello))
  use client_share <- result.try(find_x25519_share(hello))
  use scheme <- result.try(check_signature_algorithms(
    hello,
    handshake.config.private_key,
  ))
  use alpn <- result.try(negotiate_alpn(hello, handshake.config.alpn))
  use client_tp <- result.try(
    extensions.find(hello.extensions, extensions.quic_transport_parameters_ext)
    |> result.replace_error(MissingExtension),
  )
  use #(public_key, shared_secret) <- result.try(key_exchange(
    handshake.overrides,
    client_share,
  ))

  let server_random = case handshake.overrides.server_random {
    Some(random) -> random
    None -> crypto.strong_random_bytes(32)
  }

  let client_hello_bytes =
    handshake_message.encode(handshake_message.client_hello_type, body)
  let server_hello =
    server.build_server_hello(
      server_random,
      hello.legacy_session_id,
      public_key,
    )

  let transcript =
    key_schedule.new_transcript()
    |> key_schedule.add(client_hello_bytes)
    |> key_schedule.add(server_hello)
  let hello_hash = key_schedule.hash(transcript)

  let handshake_secret =
    key_schedule.handshake_secret(key_schedule.early_secret(), shared_secret)
  let client_hs = key_schedule.client_hs_traffic(handshake_secret, hello_hash)
  let server_hs = key_schedule.server_hs_traffic(handshake_secret, hello_hash)

  let #(flight, transcript) =
    build_server_flight(handshake.config, scheme, alpn, transcript, server_hs)

  let finished_hash = key_schedule.hash(transcript)
  let master = key_schedule.master_secret(handshake_secret)
  let client_ap = key_schedule.client_ap_traffic(master, finished_hash)
  let server_ap = key_schedule.server_ap_traffic(master, finished_hash)
  let expected_verify_data =
    key_schedule.finished_verify_data(client_hs, finished_hash)

  Ok(
    #(
      Handshake(
        ..handshake,
        state: AwaitFinished(expected_verify_data, alpn, client_tp),
      ),
      [
        SendHandshakeData(InitialLevel, server_hello),
        HandshakeSecrets(client: client_hs, server: server_hs),
        SendHandshakeData(HandshakeLevel, flight),
        ApplicationSecrets(client: client_ap, server: server_ap),
      ],
    ),
  )
}

/// Builds EncryptedExtensions ‖ Certificate ‖ CertificateVerify ‖
/// Finished, returning the concatenated flight and the transcript with
/// all four added.
fn build_server_flight(
  config: Config,
  scheme: tls_crypto.SignatureScheme,
  alpn: String,
  transcript: Transcript,
  server_hs_secret: BitArray,
) -> #(BitArray, Transcript) {
  let encrypted_extensions =
    server.build_encrypted_extensions(alpn, config.transport_params)
  let certificate = server.build_certificate(config.certificate_chain)
  let transcript =
    transcript
    |> key_schedule.add(encrypted_extensions)
    |> key_schedule.add(certificate)

  let signature =
    tls_crypto.sign(
      config.private_key,
      server.certificate_verify_content(key_schedule.hash(transcript)),
    )
  let certificate_verify =
    server.build_certificate_verify(tls_crypto.scheme_code(scheme), signature)
  let transcript = key_schedule.add(transcript, certificate_verify)

  let finished =
    server.build_finished(key_schedule.finished_verify_data(
      server_hs_secret,
      key_schedule.hash(transcript),
    ))
  let transcript = key_schedule.add(transcript, finished)

  #(
    <<
      encrypted_extensions:bits,
      certificate:bits,
      certificate_verify:bits,
      finished:bits,
    >>,
    transcript,
  )
}

fn check_offers_tls13(hello: ClientHello) -> Result(Nil, Alert) {
  use data <- result.try(
    extensions.find(hello.extensions, extensions.supported_versions_ext)
    |> result.replace_error(ProtocolVersion),
  )
  use versions <- result.try(
    extensions.parse_supported_versions(data)
    |> result.replace_error(DecodeError),
  )
  case list.contains(versions, extensions.tls13_version) {
    True -> Ok(Nil)
    False -> Error(ProtocolVersion)
  }
}

fn check_offers_suite(hello: ClientHello) -> Result(Nil, Alert) {
  // TLS_AES_128_GCM_SHA256, the only suite this server implements.
  case list.contains(hello.cipher_suites, 0x1301) {
    True -> Ok(Nil)
    False -> Error(HandshakeFailure)
  }
}

fn find_x25519_share(hello: ClientHello) -> Result(BitArray, Alert) {
  use data <- result.try(
    extensions.find(hello.extensions, extensions.key_share_ext)
    |> result.replace_error(MissingExtension),
  )
  use shares <- result.try(
    extensions.parse_key_shares(data) |> result.replace_error(DecodeError),
  )
  // No HelloRetryRequest support: the client must have guessed x25519,
  // which every mainstream QUIC client offers.
  case list.key_find(shares, extensions.x25519_group) {
    Ok(key) ->
      case bit_array.byte_size(key) == 32 {
        True -> Ok(key)
        False -> Error(IllegalParameter)
      }
    Error(Nil) -> Error(HandshakeFailure)
  }
}

fn check_signature_algorithms(
  hello: ClientHello,
  key: SigningKey,
) -> Result(tls_crypto.SignatureScheme, Alert) {
  use data <- result.try(
    extensions.find(hello.extensions, extensions.signature_algorithms_ext)
    |> result.replace_error(MissingExtension),
  )
  use schemes <- result.try(
    extensions.parse_signature_algorithms(data)
    |> result.replace_error(DecodeError),
  )
  let scheme = tls_crypto.key_scheme(key)
  case list.contains(schemes, tls_crypto.scheme_code(scheme)) {
    True -> Ok(scheme)
    False -> Error(HandshakeFailure)
  }
}

fn negotiate_alpn(
  hello: ClientHello,
  supported: List(String),
) -> Result(String, Alert) {
  use data <- result.try(
    extensions.find(hello.extensions, extensions.alpn_ext)
    |> result.replace_error(NoApplicationProtocol),
  )
  use offered <- result.try(
    extensions.parse_alpn(data) |> result.replace_error(DecodeError),
  )
  // Server preference order.
  list.find(supported, fn(protocol) { list.contains(offered, protocol) })
  |> result.replace_error(NoApplicationProtocol)
}

fn key_exchange(
  overrides: Overrides,
  client_share: BitArray,
) -> Result(#(BitArray, BitArray), Alert) {
  let #(public_key, private_key) = case overrides.ephemeral_private {
    Some(private) -> #(tls_crypto.x25519_public(private), private)
    None -> tls_crypto.x25519_generate()
  }
  case tls_crypto.x25519_shared(client_share, private_key) {
    Ok(shared) -> Ok(#(public_key, shared))
    Error(Nil) -> Error(IllegalParameter)
  }
}
