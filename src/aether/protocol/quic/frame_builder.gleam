//// Encodes QUIC frames to their RFC 9000 Section 19 wire format.
////
//// Every varint field uses the smallest encoding (`varint.encode`
//// already enforces that). STREAM frames always set the LEN bit and only
//// set the OFF bit when the offset is non-zero, per RFC 9000 Section
//// 19.8's recommendation to omit fields that would otherwise be zero.

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
  frame_type_stop_sending, frame_type_stream_data_blocked, frame_type_stream_min,
  frame_type_streams_blocked_bidi, frame_type_streams_blocked_uni,
  new_connection_id_max_len, new_connection_id_min_len, path_data_len,
  stateless_reset_token_len, stream_flag_fin, stream_flag_len, stream_flag_off,
}
import aether/protocol/quic/varint
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Encodes a single frame to wire format.
pub fn build_frame(frame: Frame) -> Result(BitArray, WireError) {
  case frame {
    Padding(count) -> Ok(build_padding(count))
    Ping -> encode_type(frame_type_ping)
    Ack(largest_acked, ack_delay, first_range, ranges, ecn) ->
      build_ack(largest_acked, ack_delay, first_range, ranges, ecn)
    ResetStream(stream_id, app_error_code, final_size) ->
      build_varints(frame_type_reset_stream, [
        stream_id,
        app_error_code,
        final_size,
      ])
    StopSending(stream_id, app_error_code) ->
      build_varints(frame_type_stop_sending, [stream_id, app_error_code])
    Crypto(offset, data) -> build_crypto(offset, data)
    NewToken(token) -> build_new_token(token)
    Stream(stream_id, offset, data, fin) ->
      build_stream(stream_id, offset, data, fin)
    MaxData(max) -> build_varints(frame_type_max_data, [max])
    MaxStreamData(stream_id, max) ->
      build_varints(frame_type_max_stream_data, [stream_id, max])
    MaxStreams(bidirectional, max) ->
      build_varints(max_streams_type(bidirectional), [max])
    DataBlocked(limit) -> build_varints(frame_type_data_blocked, [limit])
    StreamDataBlocked(stream_id, limit) ->
      build_varints(frame_type_stream_data_blocked, [stream_id, limit])
    StreamsBlocked(bidirectional, limit) ->
      build_varints(streams_blocked_type(bidirectional), [limit])
    NewConnectionId(seq, retire_prior_to, cid, stateless_reset_token) ->
      build_new_connection_id(seq, retire_prior_to, cid, stateless_reset_token)
    RetireConnectionId(seq) ->
      build_varints(frame_type_retire_connection_id, [seq])
    PathChallenge(data) -> build_fixed(frame_type_path_challenge, data)
    PathResponse(data) -> build_fixed(frame_type_path_response, data)
    ConnectionClose(error_code, frame_type, reason) ->
      build_connection_close(error_code, frame_type, reason)
    HandshakeDone -> encode_type(frame_type_handshake_done)
  }
}

/// Encodes multiple frames, concatenating their wire forms in order.
pub fn build_frames(frames: List(Frame)) -> Result(BitArray, WireError) {
  build_frames_loop(frames, [])
}

fn build_frames_loop(
  frames: List(Frame),
  acc: List(BitArray),
) -> Result(BitArray, WireError) {
  case frames {
    [] -> Ok(bit_array.concat(list.reverse(acc)))
    [frame, ..rest] -> {
      use bytes <- result.try(build_frame(frame))
      build_frames_loop(rest, [bytes, ..acc])
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Shared helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn max_streams_type(bidirectional: Bool) -> Int {
  case bidirectional {
    True -> frame_type_max_streams_bidi
    False -> frame_type_max_streams_uni
  }
}

fn streams_blocked_type(bidirectional: Bool) -> Int {
  case bidirectional {
    True -> frame_type_streams_blocked_bidi
    False -> frame_type_streams_blocked_uni
  }
}

fn encode_type(type_code: Int) -> Result(BitArray, WireError) {
  varint.encode(type_code)
}

/// Encodes a frame type followed by a fixed sequence of varint fields.
fn build_varints(
  type_code: Int,
  values: List(Int),
) -> Result(BitArray, WireError) {
  use type_bytes <- result.try(varint.encode(type_code))
  use field_bytes <- result.try(encode_varints(values))
  Ok(bit_array.concat([type_bytes, field_bytes]))
}

fn encode_varints(values: List(Int)) -> Result(BitArray, WireError) {
  case values {
    [] -> Ok(<<>>)
    [value, ..rest] -> {
      use value_bytes <- result.try(varint.encode(value))
      use rest_bytes <- result.try(encode_varints(rest))
      Ok(bit_array.concat([value_bytes, rest_bytes]))
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PADDING
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_padding(count: Int) -> BitArray {
  build_padding_loop(count, <<>>)
}

fn build_padding_loop(remaining: Int, acc: BitArray) -> BitArray {
  case remaining <= 0 {
    True -> acc
    False -> build_padding_loop(remaining - 1, <<acc:bits, 0:8>>)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CRYPTO / NEW_TOKEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_crypto(offset: Int, data: BitArray) -> Result(BitArray, WireError) {
  use type_bytes <- result.try(varint.encode(frame_type_crypto))
  use offset_bytes <- result.try(varint.encode(offset))
  use length_bytes <- result.try(varint.encode(bit_array.byte_size(data)))
  Ok(bit_array.concat([type_bytes, offset_bytes, length_bytes, data]))
}

fn build_new_token(token: BitArray) -> Result(BitArray, WireError) {
  use type_bytes <- result.try(varint.encode(frame_type_new_token))
  use length_bytes <- result.try(varint.encode(bit_array.byte_size(token)))
  Ok(bit_array.concat([type_bytes, length_bytes, token]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// STREAM
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_stream(
  stream_id: Int,
  offset: Int,
  data: BitArray,
  fin: Bool,
) -> Result(BitArray, WireError) {
  let has_off = offset > 0
  let type_code =
    frame_type_stream_min
    |> int.bitwise_or(stream_flag_len)
    |> set_flag_if(has_off, stream_flag_off)
    |> set_flag_if(fin, stream_flag_fin)

  use type_bytes <- result.try(varint.encode(type_code))
  use stream_id_bytes <- result.try(varint.encode(stream_id))
  use offset_bytes <- result.try(case has_off {
    True -> varint.encode(offset)
    False -> Ok(<<>>)
  })
  use length_bytes <- result.try(varint.encode(bit_array.byte_size(data)))
  Ok(
    bit_array.concat([
      type_bytes,
      stream_id_bytes,
      offset_bytes,
      length_bytes,
      data,
    ]),
  )
}

fn set_flag_if(bits: Int, condition: Bool, flag: Int) -> Int {
  case condition {
    True -> int.bitwise_or(bits, flag)
    False -> bits
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// NEW_CONNECTION_ID
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_new_connection_id(
  seq: Int,
  retire_prior_to: Int,
  cid: BitArray,
  stateless_reset_token: BitArray,
) -> Result(BitArray, WireError) {
  let cid_len = bit_array.byte_size(cid)
  use <- bool.guard(
    cid_len < new_connection_id_min_len || cid_len > new_connection_id_max_len,
    Error(Malformed(
      "NEW_CONNECTION_ID cid length must be 1-20 bytes, got "
      <> int.to_string(cid_len),
    )),
  )
  use <- bool.guard(
    bit_array.byte_size(stateless_reset_token) != stateless_reset_token_len,
    Error(Malformed("NEW_CONNECTION_ID stateless reset token must be 16 bytes")),
  )
  use type_bytes <- result.try(varint.encode(frame_type_new_connection_id))
  use seq_bytes <- result.try(varint.encode(seq))
  use retire_bytes <- result.try(varint.encode(retire_prior_to))
  Ok(
    bit_array.concat([
      type_bytes,
      seq_bytes,
      retire_bytes,
      <<cid_len:8>>,
      cid,
      stateless_reset_token,
    ]),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PATH_CHALLENGE / PATH_RESPONSE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_fixed(type_code: Int, data: BitArray) -> Result(BitArray, WireError) {
  use <- bool.guard(
    bit_array.byte_size(data) != path_data_len,
    Error(Malformed(
      "expected exactly " <> int.to_string(path_data_len) <> " bytes",
    )),
  )
  build_fixed_unchecked(type_code, data)
}

fn build_fixed_unchecked(
  type_code: Int,
  data: BitArray,
) -> Result(BitArray, WireError) {
  use type_bytes <- result.try(varint.encode(type_code))
  Ok(bit_array.concat([type_bytes, data]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CONNECTION_CLOSE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_connection_close(
  error_code: Int,
  frame_type: Option(Int),
  reason: String,
) -> Result(BitArray, WireError) {
  let type_code = case frame_type {
    Some(_) -> frame_type_connection_close_transport
    None -> frame_type_connection_close_application
  }
  use type_bytes <- result.try(varint.encode(type_code))
  use error_bytes <- result.try(varint.encode(error_code))
  use frame_type_bytes <- result.try(case frame_type {
    Some(ft) -> varint.encode(ft)
    None -> Ok(<<>>)
  })
  let reason_bytes = bit_array.from_string(reason)
  use length_bytes <- result.try(
    varint.encode(bit_array.byte_size(reason_bytes)),
  )
  Ok(
    bit_array.concat([
      type_bytes,
      error_bytes,
      frame_type_bytes,
      length_bytes,
      reason_bytes,
    ]),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ACK
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn build_ack(
  largest_acked: Int,
  ack_delay: Int,
  first_range: Int,
  ranges: List(#(Int, Int)),
  ecn: Option(#(Int, Int, Int)),
) -> Result(BitArray, WireError) {
  let type_code = case ecn {
    Some(_) -> frame_type_ack_ecn
    None -> frame_type_ack
  }
  use type_bytes <- result.try(varint.encode(type_code))
  use largest_bytes <- result.try(varint.encode(largest_acked))
  use delay_bytes <- result.try(varint.encode(ack_delay))
  use count_bytes <- result.try(varint.encode(list.length(ranges)))
  use first_bytes <- result.try(varint.encode(first_range))
  use ranges_bytes <- result.try(build_ack_ranges(ranges))
  use ecn_bytes <- result.try(case ecn {
    Some(#(ect0, ect1, ce)) -> encode_varints([ect0, ect1, ce])
    None -> Ok(<<>>)
  })
  Ok(
    bit_array.concat([
      type_bytes,
      largest_bytes,
      delay_bytes,
      count_bytes,
      first_bytes,
      ranges_bytes,
      ecn_bytes,
    ]),
  )
}

fn build_ack_ranges(ranges: List(#(Int, Int))) -> Result(BitArray, WireError) {
  case ranges {
    [] -> Ok(<<>>)
    [#(gap, len), ..rest] -> {
      use gap_bytes <- result.try(varint.encode(gap))
      use len_bytes <- result.try(varint.encode(len))
      use rest_bytes <- result.try(build_ack_ranges(rest))
      Ok(bit_array.concat([gap_bytes, len_bytes, rest_bytes]))
    }
  }
}
