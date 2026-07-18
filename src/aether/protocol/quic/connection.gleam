//// The per-connection QUIC + HTTP/3 orchestrator (server side). Ties
//// together packet protection keys, the TLS 1.3 handshake, ACK/loss
//// accounting, streams, and the HTTP/3 request/response flow. Feed it a
//// received UDP datagram with `receive`; it returns the datagrams to send
//// back.
////
//// Scope (ponytail): the localhost happy path — one client, in-order
//// delivery, server authentication only. Retry, Version Negotiation,
//// 0-RTT, key update, migration, and active PTO retransmission are
//// deferred (see the phase-6 design). The recovery engine is wired for
//// RTT/ACK/loss accounting but the runtime does not arm timers, which is
//// sound on a loopback that does not drop packets.

import aether/protocol/http3/frame as h3
import aether/protocol/http3/message
import aether/protocol/quic/ack_tracker.{type AckTracker}
import aether/protocol/quic/assembly
import aether/protocol/quic/crypto.{Aes128Gcm}
import aether/protocol/quic/frame.{
  type Frame, Ack, ConnectionClose, Crypto, HandshakeDone, Ping, Stream,
}
import aether/protocol/quic/frame_builder
import aether/protocol/quic/frame_parser
import aether/protocol/quic/keys.{type PacketKeys}
import aether/protocol/quic/packet.{Handshake, Initial, OneRtt}
import aether/protocol/quic/packet_protection
import aether/protocol/quic/stream.{type ReceiveBuffer}
import aether/protocol/tls/handshake
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

// A fixed packet-number length for everything we send. Small packet
// numbers fit in one byte, but 4 keeps header-protection sampling trivial
// and costs three bytes per packet — a fine trade for a dev server.
const send_pn_length = 4

const ack_delay_exponent = 3

/// The server's request handler.
pub type Handler =
  fn(Request(BitArray)) -> Response(BitArray)

type SpaceState {
  SpaceState(
    read_keys: Option(PacketKeys),
    write_keys: Option(PacketKeys),
    crypto_recv: ReceiveBuffer,
    crypto_send_offset: Int,
    next_pn: Int,
    largest_recv_pn: Int,
    acks: AckTracker,
  )
}

fn new_space() -> SpaceState {
  SpaceState(
    read_keys: None,
    write_keys: None,
    crypto_recv: stream.new_receive(),
    crypto_send_offset: 0,
    next_pn: 0,
    largest_recv_pn: -1,
    acks: ack_tracker.new(),
  )
}

type StreamState {
  StreamState(recv: ReceiveBuffer, responded: Bool)
}

/// An in-progress server connection.
pub opaque type Connection {
  Connection(
    scid: BitArray,
    dcid: BitArray,
    odcid_seen: Bool,
    handler: Handler,
    tls: handshake.Handshake,
    initial: SpaceState,
    handshake_space: SpaceState,
    application: SpaceState,
    streams: Dict(Int, StreamState),
    control_stream_opened: Bool,
    next_server_uni: Int,
    handshake_confirmed: Bool,
    alpn: Result(String, Nil),
    closed: Bool,
  )
}

/// Creates a server connection. `scid` is the connection ID the server
/// issues (clients address it as the Destination Connection ID). The
/// client's original DCID, used to derive Initial keys, is learned from
/// the first Initial packet.
pub fn new(
  tls_config: handshake.Config,
  scid: BitArray,
  handler: Handler,
) -> Connection {
  Connection(
    scid: scid,
    dcid: <<>>,
    odcid_seen: False,
    handler: handler,
    tls: handshake.new(tls_config),
    initial: new_space(),
    handshake_space: new_space(),
    application: new_space(),
    streams: dict.new(),
    control_stream_opened: False,
    next_server_uni: 3,
    handshake_confirmed: False,
    alpn: Error(Nil),
    closed: False,
  )
}

/// True once the TLS handshake has completed on this connection.
pub fn is_established(conn: Connection) -> Bool {
  conn.handshake_confirmed
}

/// True once the connection has been closed (by us or the peer).
pub fn is_closed(conn: Connection) -> Bool {
  conn.closed
}

/// The ALPN protocol negotiated during the handshake, if complete.
pub fn negotiated_alpn(conn: Connection) -> Result(String, Nil) {
  conn.alpn
}

// Outgoing frames accumulated per space while processing a datagram.
type Outbox {
  Outbox(initial: List(Frame), handshake: List(Frame), application: List(Frame))
}

fn empty_outbox() -> Outbox {
  Outbox([], [], [])
}

/// Processes one received UDP datagram and returns the UDP datagrams to
/// send back to the peer.
pub fn receive(
  conn: Connection,
  datagram: BitArray,
  now: Int,
) -> #(Connection, List(BitArray)) {
  case conn.closed {
    True -> #(conn, [])
    False -> {
      let #(conn, outbox) = process_packets(conn, datagram, empty_outbox(), now)
      flush(conn, outbox, now)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Packet processing
// ─────────────────────────────────────────────────────────────────────────

fn process_packets(
  conn: Connection,
  bytes: BitArray,
  outbox: Outbox,
  now: Int,
) -> #(Connection, Outbox) {
  case bytes {
    <<>> -> #(conn, outbox)
    <<first_byte:8, _:bits>> ->
      case is_long_header(first_byte) {
        True ->
          case packet.parse_long(bytes) {
            Ok(#(parsed, remaining)) -> {
              let header = header_bytes(bytes, remaining, parsed)
              let #(conn, outbox) =
                process_packet(conn, parsed, header, outbox, now)
              process_packets(conn, remaining, outbox, now)
            }
            Error(_) -> #(conn, outbox)
          }
        False ->
          case packet.parse_short(bytes, bit_array.byte_size(conn.scid)) {
            Ok(#(parsed, _)) -> {
              let header = header_bytes(bytes, <<>>, parsed)
              process_packet(conn, parsed, header, outbox, now)
            }
            Error(_) -> #(conn, outbox)
          }
      }
    _ -> #(conn, outbox)
  }
}

// The raw header is the packet's bytes before its protected region.
fn header_bytes(
  bytes: BitArray,
  remaining: BitArray,
  parsed: packet.ProtectedPacket,
) -> BitArray {
  let packet_len = bit_array.byte_size(bytes) - bit_array.byte_size(remaining)
  let header_len = packet_len - bit_array.byte_size(protected_of(parsed))
  case bit_array.slice(bytes, 0, header_len) {
    Ok(header) -> header
    Error(Nil) -> <<>>
  }
}

fn protected_of(parsed: packet.ProtectedPacket) -> BitArray {
  case parsed {
    Initial(protected: p, ..) -> p
    Handshake(protected: p, ..) -> p
    OneRtt(protected: p, ..) -> p
    _ -> <<>>
  }
}

fn process_packet(
  conn: Connection,
  parsed: packet.ProtectedPacket,
  header: BitArray,
  outbox: Outbox,
  now: Int,
) -> #(Connection, Outbox) {
  case parsed {
    Initial(dcid: dcid, ..) -> {
      let conn = ensure_initial_keys(conn, dcid)
      decrypt_and_handle(
        conn,
        Space(0),
        header,
        protected_of(parsed),
        outbox,
        now,
      )
    }
    Handshake(..) ->
      decrypt_and_handle(
        conn,
        Space(1),
        header,
        protected_of(parsed),
        outbox,
        now,
      )
    OneRtt(..) ->
      decrypt_and_handle(
        conn,
        Space(2),
        header,
        protected_of(parsed),
        outbox,
        now,
      )
    _ -> #(conn, outbox)
  }
}

// A small tag to select a packet number space without importing the
// packet_space type into every helper signature.
type Space {
  Space(index: Int)
}

fn space_state(conn: Connection, space: Space) -> SpaceState {
  case space.index {
    0 -> conn.initial
    1 -> conn.handshake_space
    _ -> conn.application
  }
}

fn put_space(conn: Connection, space: Space, state: SpaceState) -> Connection {
  case space.index {
    0 -> Connection(..conn, initial: state)
    1 -> Connection(..conn, handshake_space: state)
    _ -> Connection(..conn, application: state)
  }
}

fn ensure_initial_keys(conn: Connection, dcid: BitArray) -> Connection {
  case conn.odcid_seen {
    True -> conn
    False -> {
      let #(client_keys, server_keys) = keys.initial_keys(dcid)
      let initial =
        SpaceState(
          ..conn.initial,
          read_keys: Some(client_keys),
          write_keys: Some(server_keys),
        )
      Connection(..conn, dcid: dcid, odcid_seen: True, initial: initial)
    }
  }
}

fn decrypt_and_handle(
  conn: Connection,
  space: Space,
  header: BitArray,
  protected: BitArray,
  outbox: Outbox,
  now: Int,
) -> #(Connection, Outbox) {
  let state = space_state(conn, space)
  case state.read_keys {
    None -> #(conn, outbox)
    Some(read_keys) ->
      case
        packet_protection.unprotect(
          read_keys,
          header,
          protected,
          state.largest_recv_pn,
        )
      {
        Error(_) -> #(conn, outbox)
        Ok(#(info, plaintext)) ->
          case frame_parser.parse_frames(plaintext) {
            Error(_) -> #(conn, outbox)
            Ok(frames) -> {
              let largest = int.max(state.largest_recv_pn, info.packet_number)
              let ack_eliciting = list.any(frames, is_ack_eliciting)
              let acks =
                ack_tracker.record(
                  state.acks,
                  info.packet_number,
                  ack_eliciting,
                  now,
                )
              let state =
                SpaceState(..state, largest_recv_pn: largest, acks: acks)
              let conn = put_space(conn, space, state)
              handle_frames(conn, space, frames, outbox, now)
            }
          }
      }
  }
}

fn is_ack_eliciting(f: Frame) -> Bool {
  case f {
    Ack(..) -> False
    frame.Padding(..) -> False
    ConnectionClose(..) -> False
    _ -> True
  }
}

fn handle_frames(
  conn: Connection,
  space: Space,
  frames: List(Frame),
  outbox: Outbox,
  now: Int,
) -> #(Connection, Outbox) {
  list.fold(frames, #(conn, outbox), fn(acc, f) {
    let #(conn, outbox) = acc
    handle_frame(conn, space, f, outbox, now)
  })
}

fn handle_frame(
  conn: Connection,
  space: Space,
  f: Frame,
  outbox: Outbox,
  now: Int,
) -> #(Connection, Outbox) {
  case f {
    Crypto(offset, data) ->
      handle_crypto(conn, space, offset, data, outbox, now)
    Stream(id, offset, data, fin) ->
      handle_stream(conn, id, offset, data, fin, outbox)
    ConnectionClose(..) -> #(Connection(..conn, closed: True), outbox)
    Ping -> #(conn, outbox)
    // ACK/flow-control/other frames: no runtime action this phase (loss is
    // accounted for elsewhere; localhost does not drop).
    _ -> #(conn, outbox)
  }
}

// ─────────────────────────────────────────────────────────────────────────
// CRYPTO → TLS handshake
// ─────────────────────────────────────────────────────────────────────────

fn handle_crypto(
  conn: Connection,
  space: Space,
  offset: Int,
  data: BitArray,
  outbox: Outbox,
  now: Int,
) -> #(Connection, Outbox) {
  let state = space_state(conn, space)
  case stream.receive(state.crypto_recv, offset, data, False) {
    Error(_) -> #(conn, outbox)
    Ok(recv) -> {
      let #(recv, contiguous) = stream.read(recv)
      let state = SpaceState(..state, crypto_recv: recv)
      let conn = put_space(conn, space, state)
      case bit_array.byte_size(contiguous) == 0 {
        True -> #(conn, outbox)
        False ->
          case handshake.process(conn.tls, tls_level(space), contiguous) {
            Error(alert) -> #(close_with_alert(conn, alert), outbox)
            Ok(#(tls, events)) -> {
              let conn = Connection(..conn, tls: tls)
              apply_events(conn, events, outbox, now)
            }
          }
      }
    }
  }
}

fn tls_level(space: Space) -> handshake.Level {
  case space.index {
    0 -> handshake.InitialLevel
    1 -> handshake.HandshakeLevel
    _ -> handshake.ApplicationLevel
  }
}

fn apply_events(
  conn: Connection,
  events: List(handshake.Event),
  outbox: Outbox,
  now: Int,
) -> #(Connection, Outbox) {
  list.fold(events, #(conn, outbox), fn(acc, event) {
    let #(conn, outbox) = acc
    apply_event(conn, event, outbox, now)
  })
}

fn apply_event(
  conn: Connection,
  event: handshake.Event,
  outbox: Outbox,
  _now: Int,
) -> #(Connection, Outbox) {
  case event {
    handshake.SendHandshakeData(level, data) ->
      queue_crypto(conn, space_of_tls_level(level), data, outbox)

    handshake.HandshakeSecrets(client, server) -> {
      let read = keys.from_secret(Aes128Gcm, client)
      let write = keys.from_secret(Aes128Gcm, server)
      let hs =
        SpaceState(
          ..conn.handshake_space,
          read_keys: Some(read),
          write_keys: Some(write),
        )
      #(Connection(..conn, handshake_space: hs), outbox)
    }

    handshake.ApplicationSecrets(client, server) -> {
      let read = keys.from_secret(Aes128Gcm, client)
      let write = keys.from_secret(Aes128Gcm, server)
      let app =
        SpaceState(
          ..conn.application,
          read_keys: Some(read),
          write_keys: Some(write),
        )
      #(Connection(..conn, application: app), outbox)
    }

    handshake.HandshakeComplete(alpn, _client_tp) -> {
      let conn = Connection(..conn, handshake_confirmed: True, alpn: Ok(alpn))
      // Signal completion to the client and open our HTTP/3 control stream.
      let outbox = push(outbox, Space(2), HandshakeDone)
      open_control_stream(conn, outbox)
    }
  }
}

fn space_of_tls_level(level: handshake.Level) -> Space {
  case level {
    handshake.InitialLevel -> Space(0)
    handshake.HandshakeLevel -> Space(1)
    handshake.ApplicationLevel -> Space(2)
  }
}

fn queue_crypto(
  conn: Connection,
  space: Space,
  data: BitArray,
  outbox: Outbox,
) -> #(Connection, Outbox) {
  let state = space_state(conn, space)
  let frame = Crypto(state.crypto_send_offset, data)
  let state =
    SpaceState(
      ..state,
      crypto_send_offset: state.crypto_send_offset + bit_array.byte_size(data),
    )
  let conn = put_space(conn, space, state)
  #(conn, push(outbox, space, frame))
}

fn close_with_alert(conn: Connection, alert: handshake.Alert) -> Connection {
  let _ = alert
  Connection(..conn, closed: True)
}

// ─────────────────────────────────────────────────────────────────────────
// HTTP/3 streams
// ─────────────────────────────────────────────────────────────────────────

fn open_control_stream(
  conn: Connection,
  outbox: Outbox,
) -> #(Connection, Outbox) {
  case conn.control_stream_opened {
    True -> #(conn, outbox)
    False -> {
      let settings =
        h3.build(
          h3.Settings([
            #(h3.qpack_max_table_capacity, 0),
            #(h3.qpack_blocked_streams, 0),
          ]),
        )
      // Server-initiated unidirectional control stream: type 0x00 prefix.
      let payload = <<0x00, settings:bits>>
      let id = conn.next_server_uni
      let outbox = push(outbox, Space(2), Stream(id, 0, payload, False))
      #(
        Connection(..conn, control_stream_opened: True, next_server_uni: id + 4),
        outbox,
      )
    }
  }
}

fn handle_stream(
  conn: Connection,
  id: Int,
  offset: Int,
  data: BitArray,
  fin: Bool,
  outbox: Outbox,
) -> #(Connection, Outbox) {
  case stream.is_bidi(id) {
    // Unidirectional streams (control, QPACK encoder/decoder): consume and
    // ignore. We advertise QPACK capacity 0, so the encoder/decoder streams
    // carry nothing we must act on.
    False -> #(conn, outbox)
    True -> handle_request_stream(conn, id, offset, data, fin, outbox)
  }
}

fn handle_request_stream(
  conn: Connection,
  id: Int,
  offset: Int,
  data: BitArray,
  fin: Bool,
  outbox: Outbox,
) -> #(Connection, Outbox) {
  let stream_state =
    dict.get(conn.streams, id)
    |> result.unwrap(StreamState(stream.new_receive(), False))

  case stream.receive(stream_state.recv, offset, data, fin) {
    Error(_) -> #(conn, outbox)
    Ok(recv) -> {
      let #(recv, buffered) = stream.read(recv)
      let finished = stream.is_finished(recv)
      let stream_state =
        StreamState(recv: recv, responded: stream_state.responded)
      let conn =
        Connection(..conn, streams: dict.insert(conn.streams, id, stream_state))

      case finished && !stream_state.responded {
        False -> #(conn, outbox)
        True -> respond(conn, id, buffered, outbox)
      }
    }
  }
}

fn respond(
  conn: Connection,
  id: Int,
  request_bytes: BitArray,
  outbox: Outbox,
) -> #(Connection, Outbox) {
  case h3.parse(request_bytes) {
    Error(_) -> #(conn, outbox)
    Ok(#(frames, _)) ->
      case extract_request(frames) {
        Error(Nil) -> #(conn, outbox)
        Ok(#(header_block, body)) ->
          case message.decode_request(header_block, body) {
            Error(_) -> #(conn, outbox)
            Ok(req) -> {
              let response_bytes = message.response_frames(conn.handler(req))
              let stream_state =
                dict.get(conn.streams, id)
                |> result.unwrap(StreamState(stream.new_receive(), False))
              let conn =
                Connection(
                  ..conn,
                  streams: dict.insert(
                    conn.streams,
                    id,
                    StreamState(..stream_state, responded: True),
                  ),
                )
              #(
                conn,
                push(outbox, Space(2), Stream(id, 0, response_bytes, True)),
              )
            }
          }
      }
  }
}

// Pulls the HEADERS block and concatenated DATA payload from a request's
// HTTP/3 frames.
fn extract_request(
  frames: List(h3.Http3Frame),
) -> Result(#(BitArray, BitArray), Nil) {
  let header_block =
    list.find_map(frames, fn(f) {
      case f {
        h3.Headers(block) -> Ok(block)
        _ -> Error(Nil)
      }
    })
  case header_block {
    Error(Nil) -> Error(Nil)
    Ok(block) -> {
      let body =
        list.fold(frames, <<>>, fn(acc, f) {
          case f {
            h3.Data(d) -> <<acc:bits, d:bits>>
            _ -> acc
          }
        })
      Ok(#(block, body))
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Emitting packets
// ─────────────────────────────────────────────────────────────────────────

fn flush(
  conn: Connection,
  outbox: Outbox,
  now: Int,
) -> #(Connection, List(BitArray)) {
  // Prepend a pending ACK to each space that owes one.
  let #(conn, initial_frames) = with_ack(conn, Space(0), outbox.initial, now)
  let #(conn, handshake_frames) =
    with_ack(conn, Space(1), outbox.handshake, now)
  let #(conn, app_frames) = with_ack(conn, Space(2), outbox.application, now)

  let #(conn, long_datagram) =
    build_long_datagram(conn, initial_frames, handshake_frames)
  let #(conn, app_datagrams) = build_app_datagram(conn, app_frames)

  let datagrams =
    list.filter(list.append(long_datagram, app_datagrams), fn(d) {
      bit_array.byte_size(d) > 0
    })
  #(conn, datagrams)
}

fn with_ack(
  conn: Connection,
  space: Space,
  frames: List(Frame),
  now: Int,
) -> #(Connection, List(Frame)) {
  let state = space_state(conn, space)
  case ack_tracker.ack_needed(state.acks) {
    False -> #(conn, frames)
    True ->
      case ack_tracker.build_ack(state.acks, now, ack_delay_exponent) {
        Error(Nil) -> #(conn, frames)
        Ok(ack) -> {
          let state =
            SpaceState(..state, acks: ack_tracker.on_ack_sent(state.acks))
          #(put_space(conn, space, state), [ack, ..frames])
        }
      }
  }
}

// Coalesce Initial and Handshake packets into one datagram (padded to 1200
// when it carries an Initial, for anti-amplification headroom).
fn build_long_datagram(
  conn: Connection,
  initial_frames: List(Frame),
  handshake_frames: List(Frame),
) -> #(Connection, List(BitArray)) {
  let #(conn, initial_bytes) = case initial_frames {
    [] -> #(conn, <<>>)
    _ -> {
      let state = conn.initial
      case state.write_keys, frame_builder.build_frames(initial_frames) {
        Some(keys), Ok(payload) -> {
          let packet =
            assembly.initial_packet(
              keys,
              conn.dcid,
              conn.scid,
              <<>>,
              state.next_pn,
              send_pn_length,
              payload,
            )
          case packet {
            Ok(bytes) -> #(
              put_space(
                conn,
                Space(0),
                SpaceState(..state, next_pn: state.next_pn + 1),
              ),
              bytes,
            )
            Error(_) -> #(conn, <<>>)
          }
        }
        _, _ -> #(conn, <<>>)
      }
    }
  }

  let #(conn, handshake_bytes) = case handshake_frames {
    [] -> #(conn, <<>>)
    _ -> {
      let state = conn.handshake_space
      case state.write_keys, frame_builder.build_frames(handshake_frames) {
        Some(keys), Ok(payload) -> {
          let packet =
            assembly.handshake_packet(
              keys,
              conn.dcid,
              conn.scid,
              state.next_pn,
              send_pn_length,
              payload,
            )
          case packet {
            Ok(bytes) -> #(
              put_space(
                conn,
                Space(1),
                SpaceState(..state, next_pn: state.next_pn + 1),
              ),
              bytes,
            )
            Error(_) -> #(conn, <<>>)
          }
        }
        _, _ -> #(conn, <<>>)
      }
    }
  }

  let combined = <<initial_bytes:bits, handshake_bytes:bits>>
  case bit_array.byte_size(combined) == 0 {
    True -> #(conn, [])
    False ->
      case bit_array.byte_size(initial_bytes) > 0 {
        True -> #(conn, [assembly.pad_datagram(combined, 1200)])
        False -> #(conn, [combined])
      }
  }
}

fn build_app_datagram(
  conn: Connection,
  frames: List(Frame),
) -> #(Connection, List(BitArray)) {
  case frames {
    [] -> #(conn, [])
    _ -> {
      let state = conn.application
      case state.write_keys, frame_builder.build_frames(frames) {
        Some(keys), Ok(payload) -> {
          let packet =
            assembly.one_rtt_packet(
              keys,
              conn.dcid,
              state.next_pn,
              send_pn_length,
              payload,
            )
          case packet {
            Ok(bytes) -> #(
              put_space(
                conn,
                Space(2),
                SpaceState(..state, next_pn: state.next_pn + 1),
              ),
              [bytes],
            )
            Error(_) -> #(conn, [])
          }
        }
        _, _ -> #(conn, [])
      }
    }
  }
}

fn push(outbox: Outbox, space: Space, frame: Frame) -> Outbox {
  case space.index {
    0 -> Outbox(..outbox, initial: list.append(outbox.initial, [frame]))
    1 -> Outbox(..outbox, handshake: list.append(outbox.handshake, [frame]))
    _ -> Outbox(..outbox, application: list.append(outbox.application, [frame]))
  }
}

fn is_long_header(first_byte: Int) -> Bool {
  int.bitwise_and(first_byte, 0x80) != 0
}
