//// Decodes a decrypted QUIC frame-layer payload into a list of frames
//// (RFC 9000 Section 19).
////
//// `parse_frames` assumes the payload is fully available: a QUIC packet
//// payload only reaches the frame layer after header/packet protection
//// removal, so it is never partially delivered. Because of that, any
//// truncated field encountered while walking a frame is a protocol
//// violation (`Malformed`), never `NeedMoreData` — there is nothing left
//// to wait for.

import aether/protocol/quic/error.{type WireError, Malformed}
import aether/protocol/quic/frame.{
  type Frame, Ack, ConnectionClose, Crypto, DataBlocked, HandshakeDone, MaxData,
  MaxStreamData, MaxStreams, NewConnectionId, NewToken, Padding, PathChallenge,
  PathResponse, Ping, ResetStream, RetireConnectionId, StopSending, Stream,
  StreamDataBlocked, StreamsBlocked, frame_type_ack, frame_type_ack_ecn,
  frame_type_connection_close_application, frame_type_connection_close_transport,
  frame_type_crypto, frame_type_data_blocked, frame_type_handshake_done,
  frame_type_max_data, frame_type_max_stream_data, frame_type_max_streams_bidi,
  frame_type_max_streams_uni, frame_type_new_connection_id, frame_type_new_token,
  frame_type_path_challenge, frame_type_path_response, frame_type_ping,
  frame_type_reset_stream, frame_type_retire_connection_id,
  frame_type_stop_sending, frame_type_stream_data_blocked, frame_type_stream_max,
  frame_type_stream_min, frame_type_streams_blocked_bidi,
  frame_type_streams_blocked_uni, new_connection_id_max_len,
  new_connection_id_min_len, path_data_len, stateless_reset_token_len,
  stream_flag_fin, stream_flag_len, stream_flag_off,
}
import aether/protocol/quic/varint
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result

/// Decodes every frame in a fully-available (decrypted) payload.
///
/// Returns frames in wire order. A truncated field or a protocol
/// violation (unknown frame type, an out-of-range NEW_CONNECTION_ID
/// length, an ACK range that underflows, ...) returns `Malformed`.
pub fn parse_frames(payload: BitArray) -> Result(List(Frame), WireError) {
  parse_loop(payload, [])
}

fn parse_loop(
  data: BitArray,
  acc: List(Frame),
) -> Result(List(Frame), WireError) {
  case data {
    <<>> -> Ok(list.reverse(acc))
    _ -> {
      use #(frame, rest) <- result.try(parse_one(data))
      parse_loop(rest, [frame, ..acc])
    }
  }
}

fn parse_one(data: BitArray) -> Result(#(Frame, BitArray), WireError) {
  case data {
    <<0x00, rest:bits>> -> {
      let #(count, rest) = count_padding(rest, 1)
      Ok(#(Padding(count), rest))
    }
    _ -> {
      use #(frame_type, rest) <- result.try(require_varint(data))
      dispatch(frame_type, rest)
    }
  }
}

fn count_padding(data: BitArray, count: Int) -> #(Int, BitArray) {
  case data {
    <<0x00, rest:bits>> -> count_padding(rest, count + 1)
    _ -> #(count, data)
  }
}

fn dispatch(
  frame_type: Int,
  rest: BitArray,
) -> Result(#(Frame, BitArray), WireError) {
  case frame_type {
    t if t == frame_type_ping -> Ok(#(Ping, rest))
    t if t == frame_type_ack -> parse_ack(rest, False)
    t if t == frame_type_ack_ecn -> parse_ack(rest, True)
    t if t == frame_type_reset_stream -> parse_reset_stream(rest)
    t if t == frame_type_stop_sending -> parse_stop_sending(rest)
    t if t == frame_type_crypto -> parse_crypto(rest)
    t if t == frame_type_new_token -> parse_new_token(rest)
    t if t >= frame_type_stream_min && t <= frame_type_stream_max ->
      parse_stream(rest, t)
    t if t == frame_type_max_data -> parse_max_data(rest)
    t if t == frame_type_max_stream_data -> parse_max_stream_data(rest)
    t if t == frame_type_max_streams_bidi -> parse_max_streams(rest, True)
    t if t == frame_type_max_streams_uni -> parse_max_streams(rest, False)
    t if t == frame_type_data_blocked -> parse_data_blocked(rest)
    t if t == frame_type_stream_data_blocked -> parse_stream_data_blocked(rest)
    t if t == frame_type_streams_blocked_bidi ->
      parse_streams_blocked(rest, True)
    t if t == frame_type_streams_blocked_uni ->
      parse_streams_blocked(rest, False)
    t if t == frame_type_new_connection_id -> parse_new_connection_id(rest)
    t if t == frame_type_retire_connection_id ->
      parse_retire_connection_id(rest)
    t if t == frame_type_path_challenge ->
      parse_fixed(rest, path_data_len, PathChallenge)
    t if t == frame_type_path_response ->
      parse_fixed(rest, path_data_len, PathResponse)
    t if t == frame_type_connection_close_transport ->
      parse_connection_close(rest, True)
    t if t == frame_type_connection_close_application ->
      parse_connection_close(rest, False)
    t if t == frame_type_handshake_done -> Ok(#(HandshakeDone, rest))
    _ -> Error(Malformed("unknown frame type " <> int.to_string(frame_type)))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Shared helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Decodes a varint, converting the truncation case (`NeedMoreData`) to
/// `Malformed`: the payload is fully available at this layer.
fn require_varint(data: BitArray) -> Result(#(Int, BitArray), WireError) {
  case varint.decode(data) {
    Ok(decoded) -> Ok(decoded)
    Error(_) -> Error(Malformed("truncated varint"))
  }
}

/// Takes exactly `count` bytes from the front of `data`.
fn take_bytes(
  data: BitArray,
  count: Int,
) -> Result(#(BitArray, BitArray), WireError) {
  case bit_array.byte_size(data) < count {
    True ->
      Error(Malformed(
        "truncated frame: expected " <> int.to_string(count) <> " bytes",
      ))
    False ->
      case
        bit_array.slice(data, 0, count),
        bit_array.slice(data, count, bit_array.byte_size(data) - count)
      {
        Ok(taken), Ok(remaining) -> Ok(#(taken, remaining))
        _, _ -> Error(Malformed("failed to slice frame data"))
      }
  }
}

fn parse_fixed(
  data: BitArray,
  len: Int,
  build: fn(BitArray) -> Frame,
) -> Result(#(Frame, BitArray), WireError) {
  use #(fixed, rest) <- result.try(take_bytes(data, len))
  Ok(#(build(fixed), rest))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Per-frame parsers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_reset_stream(data: BitArray) -> Result(#(Frame, BitArray), WireError) {
  use #(stream_id, rest) <- result.try(require_varint(data))
  use #(app_error_code, rest) <- result.try(require_varint(rest))
  use #(final_size, rest) <- result.try(require_varint(rest))
  Ok(#(ResetStream(stream_id, app_error_code, final_size), rest))
}

fn parse_stop_sending(data: BitArray) -> Result(#(Frame, BitArray), WireError) {
  use #(stream_id, rest) <- result.try(require_varint(data))
  use #(app_error_code, rest) <- result.try(require_varint(rest))
  Ok(#(StopSending(stream_id, app_error_code), rest))
}

fn parse_crypto(data: BitArray) -> Result(#(Frame, BitArray), WireError) {
  use #(offset, rest) <- result.try(require_varint(data))
  use #(length, rest) <- result.try(require_varint(rest))
  use #(crypto_data, rest) <- result.try(take_bytes(rest, length))
  Ok(#(Crypto(offset, crypto_data), rest))
}

fn parse_new_token(data: BitArray) -> Result(#(Frame, BitArray), WireError) {
  use #(length, rest) <- result.try(require_varint(data))
  use <- bool.guard(
    length == 0,
    Error(Malformed("NEW_TOKEN token must not be empty")),
  )
  use #(token, rest) <- result.try(take_bytes(rest, length))
  Ok(#(NewToken(token), rest))
}

fn parse_stream(
  data: BitArray,
  frame_type: Int,
) -> Result(#(Frame, BitArray), WireError) {
  let has_off = int.bitwise_and(frame_type, stream_flag_off) != 0
  let has_len = int.bitwise_and(frame_type, stream_flag_len) != 0
  let fin = int.bitwise_and(frame_type, stream_flag_fin) != 0

  use #(stream_id, rest) <- result.try(require_varint(data))
  use #(offset, rest) <- result.try(case has_off {
    True -> require_varint(rest)
    False -> Ok(#(0, rest))
  })
  case has_len {
    True -> {
      use #(length, rest) <- result.try(require_varint(rest))
      use #(stream_data, rest) <- result.try(take_bytes(rest, length))
      Ok(#(Stream(stream_id, offset, stream_data, fin), rest))
    }
    False ->
      // No LEN bit: stream data runs to the end of the payload, and this
      // frame must be the last one (nothing remains to parse after it).
      Ok(#(Stream(stream_id, offset, rest, fin), <<>>))
  }
}

fn parse_max_data(data: BitArray) -> Result(#(Frame, BitArray), WireError) {
  use #(max, rest) <- result.try(require_varint(data))
  Ok(#(MaxData(max), rest))
}

fn parse_max_stream_data(
  data: BitArray,
) -> Result(#(Frame, BitArray), WireError) {
  use #(stream_id, rest) <- result.try(require_varint(data))
  use #(max, rest) <- result.try(require_varint(rest))
  Ok(#(MaxStreamData(stream_id, max), rest))
}

fn parse_max_streams(
  data: BitArray,
  bidirectional: Bool,
) -> Result(#(Frame, BitArray), WireError) {
  use #(max, rest) <- result.try(require_varint(data))
  Ok(#(MaxStreams(bidirectional, max), rest))
}

fn parse_data_blocked(data: BitArray) -> Result(#(Frame, BitArray), WireError) {
  use #(limit, rest) <- result.try(require_varint(data))
  Ok(#(DataBlocked(limit), rest))
}

fn parse_stream_data_blocked(
  data: BitArray,
) -> Result(#(Frame, BitArray), WireError) {
  use #(stream_id, rest) <- result.try(require_varint(data))
  use #(limit, rest) <- result.try(require_varint(rest))
  Ok(#(StreamDataBlocked(stream_id, limit), rest))
}

fn parse_streams_blocked(
  data: BitArray,
  bidirectional: Bool,
) -> Result(#(Frame, BitArray), WireError) {
  use #(limit, rest) <- result.try(require_varint(data))
  Ok(#(StreamsBlocked(bidirectional, limit), rest))
}

fn parse_new_connection_id(
  data: BitArray,
) -> Result(#(Frame, BitArray), WireError) {
  use #(seq, rest) <- result.try(require_varint(data))
  use #(retire_prior_to, rest) <- result.try(require_varint(rest))
  case rest {
    <<cid_len:8, rest:bits>> -> {
      use <- bool.guard(
        cid_len < new_connection_id_min_len
          || cid_len > new_connection_id_max_len,
        Error(Malformed(
          "NEW_CONNECTION_ID cid length must be 1-20 bytes, got "
          <> int.to_string(cid_len),
        )),
      )
      use #(cid, rest) <- result.try(take_bytes(rest, cid_len))
      use #(token, rest) <- result.try(take_bytes(
        rest,
        stateless_reset_token_len,
      ))
      Ok(#(NewConnectionId(seq, retire_prior_to, cid, token), rest))
    }
    _ -> Error(Malformed("truncated NEW_CONNECTION_ID length"))
  }
}

fn parse_retire_connection_id(
  data: BitArray,
) -> Result(#(Frame, BitArray), WireError) {
  use #(seq, rest) <- result.try(require_varint(data))
  Ok(#(RetireConnectionId(seq), rest))
}

fn parse_connection_close(
  data: BitArray,
  is_transport: Bool,
) -> Result(#(Frame, BitArray), WireError) {
  use #(error_code, rest) <- result.try(require_varint(data))
  use #(frame_type, rest) <- result.try(case is_transport {
    True -> {
      use #(ft, rest) <- result.try(require_varint(rest))
      Ok(#(Some(ft), rest))
    }
    False -> Ok(#(None, rest))
  })
  use #(reason_len, rest) <- result.try(require_varint(rest))
  use #(reason_bytes, rest) <- result.try(take_bytes(rest, reason_len))
  case bit_array.to_string(reason_bytes) {
    Ok(reason) -> Ok(#(ConnectionClose(error_code, frame_type, reason), rest))
    Error(_) -> Error(Malformed("CONNECTION_CLOSE reason is not valid UTF-8"))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ACK parsing (RFC 9000 Section 19.3): ranges are decoded on the wire as
// gap/length pairs relative to the previous range's smallest acknowledged
// packet number. Each step must not underflow below packet number 0.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_ack(
  data: BitArray,
  has_ecn: Bool,
) -> Result(#(Frame, BitArray), WireError) {
  use #(largest_acked, rest) <- result.try(require_varint(data))
  use #(ack_delay, rest) <- result.try(require_varint(rest))
  use #(range_count, rest) <- result.try(require_varint(rest))
  use #(first_range, rest) <- result.try(require_varint(rest))
  use smallest <- result.try(case largest_acked - first_range {
    v if v < 0 -> Error(Malformed("ACK first range underflows below 0"))
    v -> Ok(v)
  })
  use #(ranges, _smallest, rest) <- result.try(
    parse_ack_ranges(rest, range_count, smallest, []),
  )
  use #(ecn, rest) <- result.try(case has_ecn {
    True -> {
      use #(ect0, rest) <- result.try(require_varint(rest))
      use #(ect1, rest) <- result.try(require_varint(rest))
      use #(ce, rest) <- result.try(require_varint(rest))
      Ok(#(Some(#(ect0, ect1, ce)), rest))
    }
    False -> Ok(#(None, rest))
  })
  Ok(#(Ack(largest_acked, ack_delay, first_range, ranges, ecn), rest))
}

fn parse_ack_ranges(
  data: BitArray,
  remaining: Int,
  smallest: Int,
  acc: List(#(Int, Int)),
) -> Result(#(List(#(Int, Int)), Int, BitArray), WireError) {
  case remaining {
    0 -> Ok(#(list.reverse(acc), smallest, data))
    _ -> {
      use #(gap, rest) <- result.try(require_varint(data))
      use #(len, rest) <- result.try(require_varint(rest))
      use next_largest <- result.try(case smallest - gap - 2 {
        v if v < 0 -> Error(Malformed("ACK range gap underflows below 0"))
        v -> Ok(v)
      })
      use next_smallest <- result.try(case next_largest - len {
        v if v < 0 -> Error(Malformed("ACK range length underflows below 0"))
        v -> Ok(v)
      })
      parse_ack_ranges(rest, remaining - 1, next_smallest, [#(gap, len), ..acc])
    }
  }
}
