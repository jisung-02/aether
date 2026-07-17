//// QUIC v1 frame types (RFC 9000 Section 19).
////
//// One ADT covers every frame type the wire format defines. STREAM
//// (0x08-0x0f) collapses its OFF/LEN/FIN type bits into `offset` and
//// `fin` fields. ACK (0x02/0x03) is split by the presence of ECN counts
//// through the `ecn` field. MAX_STREAMS/STREAMS_BLOCKED (which each have
//// a bidirectional and a unidirectional type code) carry a
//// `bidirectional` flag instead of two separate constructors.
//// CONNECTION_CLOSE (0x1c/0x1d) carries an optional `frame_type`, present
//// only for the transport-level (0x1c) form.

import gleam/option.{type Option}

/// PADDING (RFC 9000 Section 19.1).
pub const frame_type_padding = 0x00

/// PING (RFC 9000 Section 19.2).
pub const frame_type_ping = 0x01

/// ACK without ECN counts (RFC 9000 Section 19.3).
pub const frame_type_ack = 0x02

/// ACK with ECN counts (RFC 9000 Section 19.3.2).
pub const frame_type_ack_ecn = 0x03

/// RESET_STREAM (RFC 9000 Section 19.4).
pub const frame_type_reset_stream = 0x04

/// STOP_SENDING (RFC 9000 Section 19.5).
pub const frame_type_stop_sending = 0x05

/// CRYPTO (RFC 9000 Section 19.6).
pub const frame_type_crypto = 0x06

/// NEW_TOKEN (RFC 9000 Section 19.7).
pub const frame_type_new_token = 0x07

/// Lowest STREAM type code (RFC 9000 Section 19.8).
pub const frame_type_stream_min = 0x08

/// Highest STREAM type code (RFC 9000 Section 19.8).
pub const frame_type_stream_max = 0x0f

/// STREAM OFF bit: an explicit `Offset` field is present.
pub const stream_flag_off = 0x04

/// STREAM LEN bit: an explicit `Length` field is present.
pub const stream_flag_len = 0x02

/// STREAM FIN bit: this is the final frame for the stream.
pub const stream_flag_fin = 0x01

/// MAX_DATA (RFC 9000 Section 19.9).
pub const frame_type_max_data = 0x10

/// MAX_STREAM_DATA (RFC 9000 Section 19.10).
pub const frame_type_max_stream_data = 0x11

/// MAX_STREAMS, bidirectional streams (RFC 9000 Section 19.11).
pub const frame_type_max_streams_bidi = 0x12

/// MAX_STREAMS, unidirectional streams (RFC 9000 Section 19.11).
pub const frame_type_max_streams_uni = 0x13

/// DATA_BLOCKED (RFC 9000 Section 19.12).
pub const frame_type_data_blocked = 0x14

/// STREAM_DATA_BLOCKED (RFC 9000 Section 19.13).
pub const frame_type_stream_data_blocked = 0x15

/// STREAMS_BLOCKED, bidirectional streams (RFC 9000 Section 19.14).
pub const frame_type_streams_blocked_bidi = 0x16

/// STREAMS_BLOCKED, unidirectional streams (RFC 9000 Section 19.14).
pub const frame_type_streams_blocked_uni = 0x17

/// NEW_CONNECTION_ID (RFC 9000 Section 19.15).
pub const frame_type_new_connection_id = 0x18

/// RETIRE_CONNECTION_ID (RFC 9000 Section 19.16).
pub const frame_type_retire_connection_id = 0x19

/// PATH_CHALLENGE (RFC 9000 Section 19.17).
pub const frame_type_path_challenge = 0x1a

/// PATH_RESPONSE (RFC 9000 Section 19.18).
pub const frame_type_path_response = 0x1b

/// CONNECTION_CLOSE, transport-level (RFC 9000 Section 19.19).
pub const frame_type_connection_close_transport = 0x1c

/// CONNECTION_CLOSE, application-level (RFC 9000 Section 19.19).
pub const frame_type_connection_close_application = 0x1d

/// HANDSHAKE_DONE (RFC 9000 Section 19.20).
pub const frame_type_handshake_done = 0x1e

/// Smallest valid NEW_CONNECTION_ID `cid` length in bytes.
pub const new_connection_id_min_len = 1

/// Largest valid NEW_CONNECTION_ID `cid` length in bytes.
pub const new_connection_id_max_len = 20

/// Fixed length, in bytes, of a NEW_CONNECTION_ID stateless reset token.
pub const stateless_reset_token_len = 16

/// Fixed length, in bytes, of PATH_CHALLENGE/PATH_RESPONSE data.
pub const path_data_len = 8

/// One decoded QUIC frame. See RFC 9000 Section 19 for the wire encodings.
pub type Frame {
  /// One or more consecutive PADDING (0x00) bytes, coalesced into a count.
  Padding(count: Int)

  /// PING (0x01): elicits an acknowledgement, carries no data.
  Ping

  /// ACK (0x02) / ACK with ECN counts (0x03).
  ///
  /// `ranges` holds the additional `#(gap, length)` pairs beyond
  /// `first_range`, in the order they appear on the wire. `ecn` is `Some`
  /// only for the ECN-carrying frame type (0x03).
  Ack(
    largest_acked: Int,
    ack_delay: Int,
    first_range: Int,
    ranges: List(#(Int, Int)),
    ecn: Option(#(Int, Int, Int)),
  )

  /// RESET_STREAM (0x04).
  ResetStream(stream_id: Int, app_error_code: Int, final_size: Int)

  /// STOP_SENDING (0x05).
  StopSending(stream_id: Int, app_error_code: Int)

  /// CRYPTO (0x06).
  Crypto(offset: Int, data: BitArray)

  /// NEW_TOKEN (0x07).
  NewToken(token: BitArray)

  /// STREAM (0x08-0x0f).
  Stream(stream_id: Int, offset: Int, data: BitArray, fin: Bool)

  /// MAX_DATA (0x10).
  MaxData(max: Int)

  /// MAX_STREAM_DATA (0x11).
  MaxStreamData(stream_id: Int, max: Int)

  /// MAX_STREAMS (0x12 bidirectional / 0x13 unidirectional).
  MaxStreams(bidirectional: Bool, max: Int)

  /// DATA_BLOCKED (0x14).
  DataBlocked(limit: Int)

  /// STREAM_DATA_BLOCKED (0x15).
  StreamDataBlocked(stream_id: Int, limit: Int)

  /// STREAMS_BLOCKED (0x16 bidirectional / 0x17 unidirectional).
  StreamsBlocked(bidirectional: Bool, limit: Int)

  /// NEW_CONNECTION_ID (0x18). `cid` must be 1-20 bytes;
  /// `stateless_reset_token` is always 16 bytes.
  NewConnectionId(
    seq: Int,
    retire_prior_to: Int,
    cid: BitArray,
    stateless_reset_token: BitArray,
  )

  /// RETIRE_CONNECTION_ID (0x19).
  RetireConnectionId(seq: Int)

  /// PATH_CHALLENGE (0x1a). `data` is always 8 bytes.
  PathChallenge(data: BitArray)

  /// PATH_RESPONSE (0x1b). `data` is always 8 bytes.
  PathResponse(data: BitArray)

  /// CONNECTION_CLOSE (0x1c transport / 0x1d application). `frame_type`
  /// is `Some` only for the transport-level (0x1c) form.
  ConnectionClose(error_code: Int, frame_type: Option(Int), reason: String)

  /// HANDSHAKE_DONE (0x1e).
  HandshakeDone
}
