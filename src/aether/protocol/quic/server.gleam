//// The UDP runtime for the QUIC server: binds a socket, receives
//// datagrams in a loop, and routes each one to the
//// `aether/protocol/quic/connection.Connection` it belongs to.
////
//// Connections are keyed by the destination connection id (DCID) the
//// client addresses on the wire — the `scid` this server issued when the
//// connection was created. A datagram whose DCID is not in the table and
//// whose first packet is a long-header Initial starts a new connection
//// with a freshly generated 8-byte scid; anything else with an unknown
//// DCID is dropped (localhost delivers in order, so a non-Initial packet
//// arriving for an unknown connection is not expected in the happy path
//// this phase covers).
////
//// ponytail: one receive-loop process serves every connection — no
//// per-connection process, no idle-connection eviction/LRU, and a failed
//// `recv_from` is retried rather than escalated. That is enough for a dev
//// server; add eviction if this needs to run unattended for a long time.

import aether/network/socket
import aether/network/socket_error
import aether/network/socket_options
import aether/network/udp.{type UdpDatagram}
import aether/protocol/quic/connection.{type Connection}
import aether/protocol/tls/handshake
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list

/// Every connection id this server issues is this many bytes.
const scid_length = 8

/// Large enough for any datagram a UDP socket can deliver (UDP's own
/// payload limit is 65527 bytes).
const max_datagram_size = 65_535

/// A running QUIC/UDP server: the bound socket, the port it landed on,
/// and the pid of its receive-loop process.
pub opaque type Server {
  Server(socket: socket.Socket, port: Int, loop_pid: Pid)
}

/// Binds a UDP socket on `port` (0 for an OS-assigned ephemeral port) and
/// spawns the receive loop that drives every `Connection` this server
/// accepts. Returns an error if the socket cannot be bound.
pub fn start(
  port: Int,
  tls_config: handshake.Config,
  handler: connection.Handler,
) -> Result(Server, String) {
  let options = socket_options.udp_defaults()
  case udp.bind(port, options) {
    Error(err) -> Error(socket_error.to_string(err))
    Ok(sock) ->
      case udp.get_port(sock) {
        Error(err) -> Error(socket_error.to_string(err))
        Ok(bound_port) -> {
          let loop_pid =
            process.spawn_unlinked(fn() {
              receive_loop(sock, tls_config, handler, dict.new())
            })
          Ok(Server(socket: sock, port: bound_port, loop_pid: loop_pid))
        }
      }
  }
}

/// The UDP port the server is bound to.
pub fn port(server: Server) -> Int {
  server.port
}

/// Stops the receive loop and closes the socket. In-memory connection
/// state is dropped with it (ponytail: no graceful drain).
pub fn stop(server: Server) -> Nil {
  process.kill(server.loop_pid)
  let _ = udp.close(server.socket)
  Nil
}

// ─────────────────────────────────────────────────────────────────────────
// Receive loop
// ─────────────────────────────────────────────────────────────────────────

fn receive_loop(
  sock: socket.Socket,
  tls_config: handshake.Config,
  handler: connection.Handler,
  conns: Dict(BitArray, Connection),
) -> Nil {
  case udp.recv_from(sock, max_datagram_size) {
    Ok(datagram) -> {
      let conns = handle_datagram(sock, tls_config, handler, conns, datagram)
      receive_loop(sock, tls_config, handler, conns)
    }
    // ponytail: a transient recv error (or the socket being closed by
    // `stop`, which kills this process directly) just retries; there is
    // no separate error channel to report it on for a dev server.
    Error(_) -> receive_loop(sock, tls_config, handler, conns)
  }
}

fn handle_datagram(
  sock: socket.Socket,
  tls_config: handshake.Config,
  handler: connection.Handler,
  conns: Dict(BitArray, Connection),
  datagram: UdpDatagram,
) -> Dict(BitArray, Connection) {
  case route_key(datagram.data) {
    Error(Nil) -> conns
    Ok(key) ->
      case dict.get(conns, key) {
        Ok(conn) -> feed(sock, conns, key, conn, datagram)
        Error(Nil) ->
          case is_initial(datagram.data) {
            True -> {
              let scid = crypto.strong_random_bytes(scid_length)
              let conn = connection.new(tls_config, scid, handler)
              feed(sock, conns, scid, conn, datagram)
            }
            // Non-Initial packet for a connection we don't know: drop.
            False -> conns
          }
      }
  }
}

/// Feeds one datagram to `conn`, sends every reply datagram back to the
/// sender, and returns the dict with `conn`'s post-receive state stored
/// under `key` — or removed, if the connection is now closed.
fn feed(
  sock: socket.Socket,
  conns: Dict(BitArray, Connection),
  key: BitArray,
  conn: Connection,
  datagram: UdpDatagram,
) -> Dict(BitArray, Connection) {
  let #(conn, outgoing) =
    connection.receive(conn, datagram.data, monotonic_time_us())
  let address = socket.ip_address(datagram.from_ip, datagram.from_port)
  list.each(outgoing, fn(bytes) {
    let _ = udp.send_to_address(sock, address, bytes)
    Nil
  })
  case connection.is_closed(conn) {
    True -> dict.delete(conns, key)
    False -> dict.insert(conns, key, conn)
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Routing
// ─────────────────────────────────────────────────────────────────────────

/// Extracts the destination connection id used to route `datagram`,
/// without fully parsing the packet.
///
/// For a long header, the DCID length is the byte right after the 1-byte
/// first byte and 4-byte version (i.e. byte 5), followed by that many
/// DCID bytes. For a short header the DCID isn't self-describing on the
/// wire, but every scid this server issues is `scid_length` bytes, so it
/// is the first `scid_length` bytes after the first byte.
pub fn route_key(datagram: BitArray) -> Result(BitArray, Nil) {
  case datagram {
    <<first_byte:8, _:bits>> ->
      case is_long_header(first_byte) {
        True -> long_header_dcid(datagram)
        False -> short_header_dcid(datagram)
      }
    _ -> Error(Nil)
  }
}

fn long_header_dcid(datagram: BitArray) -> Result(BitArray, Nil) {
  case datagram {
    <<_first_byte:8, _version:32, dcid_len:8, rest:bits>> ->
      case rest {
        <<dcid:bytes-size(dcid_len), _:bits>> -> Ok(dcid)
        _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn short_header_dcid(datagram: BitArray) -> Result(BitArray, Nil) {
  case datagram {
    <<_first_byte:8, dcid:bytes-size(scid_length), _:bits>> -> Ok(dcid)
    _ -> Error(Nil)
  }
}

/// True for a long-header Initial packet — the only packet type allowed
/// to start a new connection for an unrecognised DCID.
fn is_initial(datagram: BitArray) -> Bool {
  case datagram {
    <<first_byte:8, _:bits>> ->
      is_long_header(first_byte) && is_initial_type(first_byte)
    _ -> False
  }
}

fn is_long_header(first_byte: Int) -> Bool {
  int.bitwise_and(first_byte, 0x80) != 0
}

// The long-header packet type occupies bits 5-4 (mask 0x30); Initial is
// type 0.
fn is_initial_type(first_byte: Int) -> Bool {
  int.bitwise_and(first_byte, 0x30) == 0
}

// ─────────────────────────────────────────────────────────────────────────
// Time
// ─────────────────────────────────────────────────────────────────────────

type TimeUnit {
  Microsecond
}

@external(erlang, "erlang", "monotonic_time")
fn erlang_monotonic_time(unit: TimeUnit) -> Int

fn monotonic_time_us() -> Int {
  erlang_monotonic_time(Microsecond)
}
