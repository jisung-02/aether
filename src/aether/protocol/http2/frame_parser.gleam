// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Parses binary HTTP/2 frames from wire format as per RFC 9113.
// Handles the 9-byte frame header and all frame payload types.
//

import aether/protocol/http2/error.{
  type ParseError, FrameTooLarge, HpackError, IncompletePayload,
  InsufficientData, InvalidFlags, InvalidFrame, InvalidPadding, InvalidSettings,
  InvalidStreamId,
}
import aether/protocol/http2/frame.{
  type ContinuationFrame, type DataFrame, type Frame, type FrameHeader,
  type FrameType, type GoawayFrame, type HeadersFrame, type PingFrame,
  type PriorityFrame, type PushPromiseFrame, type RstStreamFrame,
  type SettingsFrame, type SettingsParameter, type WindowUpdateFrame,
  Continuation, ContinuationF, ContinuationFrame, Data, DataF, DataFrame,
  FrameHeader, Goaway, GoawayF, GoawayFrame, Headers, HeadersF, HeadersFrame,
  Ping, PingF, PingFrame, Priority, PriorityF, PriorityFrame, PushPromise,
  PushPromiseF, PushPromiseFrame, RstStream, RstStreamF, RstStreamFrame,
  Settings, SettingsF, SettingsFrame, SettingsParameter, Unknown, UnknownF,
  WindowUpdate, WindowUpdateF, WindowUpdateFrame, default_max_frame_size,
  flag_ack, flag_end_headers, flag_end_stream, flag_padded, flag_priority,
  frame_header_size, frame_type_from_int, has_flag, settings_id_from_int,
}
import gleam/bit_array
import gleam/int
import gleam/list

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Parse Result Type
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Result of parsing a frame, containing the frame and remaining bytes
///
pub type ParseResult {
  ParseResult(frame: Frame, remaining: BitArray)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Main Parser Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses a complete HTTP/2 frame from binary data
///
/// Returns the parsed frame and any remaining bytes, or a parse error.
///
pub fn parse_frame(data: BitArray) -> Result(ParseResult, ParseError) {
  parse_frame_with_max_size(data, default_max_frame_size)
}

/// Parses a frame with a custom maximum frame size
///
pub fn parse_frame_with_max_size(
  data: BitArray,
  max_frame_size: Int,
) -> Result(ParseResult, ParseError) {
  case parse_header(data) {
    Error(e) -> Error(e)
    Ok(#(header, rest)) -> {
      // Validate frame size
      case header.length > max_frame_size {
        True -> Error(FrameTooLarge(header.length, max_frame_size))
        False -> parse_payload(header, rest)
      }
    }
  }
}

/// Checks if there's enough data to parse at least the frame header
///
pub fn has_complete_header(data: BitArray) -> Bool {
  bit_array.byte_size(data) >= frame_header_size
}

/// Checks if there's enough data to parse a complete frame
///
pub fn has_complete_frame(data: BitArray) -> Bool {
  case bit_array.byte_size(data) >= frame_header_size {
    False -> False
    True -> {
      case parse_header(data) {
        Error(_) -> False
        Ok(#(header, rest)) -> bit_array.byte_size(rest) >= header.length
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses the 9-byte frame header
///
pub fn parse_header(
  data: BitArray,
) -> Result(#(FrameHeader, BitArray), ParseError) {
  let available = bit_array.byte_size(data)
  case available < frame_header_size {
    True -> Error(InsufficientData(frame_header_size, available))
    False -> {
      // Frame header format:
      // - Length: 24 bits (3 bytes)
      // - Type: 8 bits (1 byte)
      // - Flags: 8 bits (1 byte)
      // - Reserved: 1 bit
      // - Stream ID: 31 bits (4 bytes total with reserved bit)
      case data {
        <<
          length_high:8,
          length_mid:8,
          length_low:8,
          frame_type:8,
          flags:8,
          _reserved:1,
          stream_id:31,
          rest:bits,
        >> -> {
          let length =
            int.bitwise_or(
              int.bitwise_or(
                int.bitwise_shift_left(length_high, 16),
                int.bitwise_shift_left(length_mid, 8),
              ),
              length_low,
            )

          let header =
            FrameHeader(
              length: length,
              frame_type: frame_type_from_int(frame_type),
              flags: flags,
              stream_id: stream_id,
            )

          Ok(#(header, rest))
        }
        _ -> Error(InvalidFrame("Failed to parse frame header"))
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Payload Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses the frame payload based on frame type
///
fn parse_payload(
  header: FrameHeader,
  data: BitArray,
) -> Result(ParseResult, ParseError) {
  let available = bit_array.byte_size(data)
  case available < header.length {
    True -> Error(IncompletePayload(header.length, available))
    False -> {
      // Extract payload and remaining bytes
      case extract_bytes(data, header.length) {
        Error(_) -> Error(InvalidFrame("Failed to extract payload"))
        Ok(#(payload, remaining)) -> {
          // Parse based on frame type
          case parse_typed_payload(header, payload) {
            Error(e) -> Error(e)
            Ok(frame) -> Ok(ParseResult(frame, remaining))
          }
        }
      }
    }
  }
}

/// Parses payload based on frame type
///
fn parse_typed_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  case header.frame_type {
    Data -> parse_data_payload(header, payload)
    Headers -> parse_headers_payload(header, payload)
    Priority -> parse_priority_payload(header, payload)
    RstStream -> parse_rst_stream_payload(header, payload)
    Settings -> parse_settings_payload(header, payload)
    PushPromise -> parse_push_promise_payload(header, payload)
    Ping -> parse_ping_payload(header, payload)
    Goaway -> parse_goaway_payload(header, payload)
    WindowUpdate -> parse_window_update_payload(header, payload)
    Continuation -> parse_continuation_payload(header, payload)
    Unknown(_) -> Ok(UnknownF(header, payload))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// DATA Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_data_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  // Validate stream ID (must be non-zero)
  case header.stream_id == 0 {
    True -> Error(InvalidStreamId(0, "DATA"))
    False -> {
      case has_flag(header.flags, flag_padded) {
        False -> {
          // No padding
          Ok(DataF(header, DataFrame(pad_length: 0, data: payload)))
        }
        True -> {
          // Has padding - first byte is pad length
          case payload {
            <<pad_length:8, rest:bits>> -> {
              let data_length = bit_array.byte_size(rest) - pad_length
              case data_length < 0 {
                True -> Error(InvalidPadding("Pad length exceeds payload"))
                False -> {
                  case extract_bytes(rest, data_length) {
                    Error(_) -> Error(InvalidPadding("Failed to extract data"))
                    Ok(#(data, _padding)) ->
                      Ok(DataF(
                        header,
                        DataFrame(pad_length: pad_length, data: data),
                      ))
                  }
                }
              }
            }
            _ -> Error(InvalidPadding("Missing pad length byte"))
          }
        }
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HEADERS Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_headers_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  // Validate stream ID
  case header.stream_id == 0 {
    True -> Error(InvalidStreamId(0, "HEADERS"))
    False -> {
      let padded = has_flag(header.flags, flag_padded)
      let priority = has_flag(header.flags, flag_priority)

      parse_headers_with_options(header, payload, padded, priority)
    }
  }
}

fn parse_headers_with_options(
  header: FrameHeader,
  payload: BitArray,
  padded: Bool,
  has_priority: Bool,
) -> Result(Frame, ParseError) {
  // Step 1: Handle padding
  case padded {
    False -> parse_headers_priority(header, payload, 0, has_priority)
    True -> {
      case payload {
        <<pad_length:8, rest:bits>> ->
          parse_headers_priority(header, rest, pad_length, has_priority)
        _ -> Error(InvalidPadding("Missing pad length byte"))
      }
    }
  }
}

fn parse_headers_priority(
  header: FrameHeader,
  payload: BitArray,
  pad_length: Int,
  has_priority: Bool,
) -> Result(Frame, ParseError) {
  case has_priority {
    False -> {
      // No priority - extract header block minus padding
      let block_length = bit_array.byte_size(payload) - pad_length
      case block_length < 0 {
        True -> Error(InvalidPadding("Pad length exceeds payload"))
        False -> {
          case extract_bytes(payload, block_length) {
            Error(_) -> Error(InvalidFrame("Failed to extract header block"))
            Ok(#(header_block, _)) -> {
              Ok(HeadersF(
                header,
                HeadersFrame(
                  pad_length: pad_length,
                  has_priority: False,
                  stream_dependency: 0,
                  exclusive: False,
                  weight: 16,
                  header_block: header_block,
                ),
              ))
            }
          }
        }
      }
    }
    True -> {
      // Has priority - parse 5 bytes of priority info
      case payload {
        <<exclusive:1, stream_dependency:31, weight:8, rest:bits>> -> {
          let block_length = bit_array.byte_size(rest) - pad_length
          case block_length < 0 {
            True -> Error(InvalidPadding("Pad length exceeds payload"))
            False -> {
              case extract_bytes(rest, block_length) {
                Error(_) ->
                  Error(InvalidFrame("Failed to extract header block"))
                Ok(#(header_block, _)) -> {
                  Ok(HeadersF(
                    header,
                    HeadersFrame(
                      pad_length: pad_length,
                      has_priority: True,
                      stream_dependency: stream_dependency,
                      exclusive: exclusive == 1,
                      weight: weight + 1,
                      header_block: header_block,
                    ),
                  ))
                }
              }
            }
          }
        }
        _ -> Error(InvalidFrame("Invalid HEADERS priority data"))
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PRIORITY Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_priority_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  // Validate stream ID
  case header.stream_id == 0 {
    True -> Error(InvalidStreamId(0, "PRIORITY"))
    False -> {
      // PRIORITY frame is exactly 5 bytes
      case payload {
        <<exclusive:1, stream_dependency:31, weight:8>> -> {
          Ok(PriorityF(
            header,
            PriorityFrame(
              stream_dependency: stream_dependency,
              exclusive: exclusive == 1,
              weight: weight + 1,
            ),
          ))
        }
        _ -> Error(InvalidFrame("PRIORITY frame must be 5 bytes"))
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RST_STREAM Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_rst_stream_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  // Validate stream ID
  case header.stream_id == 0 {
    True -> Error(InvalidStreamId(0, "RST_STREAM"))
    False -> {
      // RST_STREAM frame is exactly 4 bytes
      case payload {
        <<error_code:32>> -> {
          Ok(RstStreamF(header, RstStreamFrame(error_code: error_code)))
        }
        _ -> Error(InvalidFrame("RST_STREAM frame must be 4 bytes"))
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SETTINGS Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_settings_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  // SETTINGS must be on stream 0
  case header.stream_id != 0 {
    True -> Error(InvalidStreamId(header.stream_id, "SETTINGS"))
    False -> {
      let is_ack = has_flag(header.flags, flag_ack)
      case is_ack {
        True -> {
          // ACK must have empty payload
          case header.length == 0 {
            True ->
              Ok(SettingsF(header, SettingsFrame(ack: True, parameters: [])))
            False -> Error(InvalidSettings("ACK SETTINGS must be empty"))
          }
        }
        False -> {
          // Non-ACK: parse settings parameters
          case header.length % 6 == 0 {
            False ->
              Error(InvalidSettings("SETTINGS length must be multiple of 6"))
            True -> {
              case parse_settings_parameters(payload, []) {
                Error(e) -> Error(e)
                Ok(parameters) ->
                  Ok(SettingsF(
                    header,
                    SettingsFrame(ack: False, parameters: parameters),
                  ))
              }
            }
          }
        }
      }
    }
  }
}

fn parse_settings_parameters(
  data: BitArray,
  acc: List(SettingsParameter),
) -> Result(List(SettingsParameter), ParseError) {
  case data {
    <<>> -> Ok(list.reverse(acc))
    <<identifier:16, value:32, rest:bits>> -> {
      let param =
        SettingsParameter(
          identifier: settings_id_from_int(identifier),
          value: value,
        )
      parse_settings_parameters(rest, [param, ..acc])
    }
    _ -> Error(InvalidSettings("Malformed settings parameter"))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PUSH_PROMISE Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_push_promise_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  // Validate stream ID
  case header.stream_id == 0 {
    True -> Error(InvalidStreamId(0, "PUSH_PROMISE"))
    False -> {
      let padded = has_flag(header.flags, flag_padded)
      parse_push_promise_with_options(header, payload, padded)
    }
  }
}

fn parse_push_promise_with_options(
  header: FrameHeader,
  payload: BitArray,
  padded: Bool,
) -> Result(Frame, ParseError) {
  case padded {
    False -> {
      case payload {
        <<_reserved:1, promised_stream_id:31, header_block:bits>> -> {
          Ok(PushPromiseF(
            header,
            PushPromiseFrame(
              pad_length: 0,
              promised_stream_id: promised_stream_id,
              header_block: header_block,
            ),
          ))
        }
        _ -> Error(InvalidFrame("Invalid PUSH_PROMISE frame"))
      }
    }
    True -> {
      case payload {
        <<pad_length:8, _reserved:1, promised_stream_id:31, rest:bits>> -> {
          let block_length = bit_array.byte_size(rest) - pad_length
          case block_length < 0 {
            True -> Error(InvalidPadding("Pad length exceeds payload"))
            False -> {
              case extract_bytes(rest, block_length) {
                Error(_) ->
                  Error(InvalidFrame("Failed to extract header block"))
                Ok(#(header_block, _)) -> {
                  Ok(PushPromiseF(
                    header,
                    PushPromiseFrame(
                      pad_length: pad_length,
                      promised_stream_id: promised_stream_id,
                      header_block: header_block,
                    ),
                  ))
                }
              }
            }
          }
        }
        _ -> Error(InvalidPadding("Missing pad length byte"))
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PING Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_ping_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  // PING must be on stream 0
  case header.stream_id != 0 {
    True -> Error(InvalidStreamId(header.stream_id, "PING"))
    False -> {
      // PING frame must be exactly 8 bytes
      case header.length == 8 {
        False -> Error(InvalidFrame("PING frame must be 8 bytes"))
        True -> {
          let is_ack = has_flag(header.flags, flag_ack)
          Ok(PingF(header, PingFrame(ack: is_ack, opaque_data: payload)))
        }
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GOAWAY Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_goaway_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  // GOAWAY must be on stream 0
  case header.stream_id != 0 {
    True -> Error(InvalidStreamId(header.stream_id, "GOAWAY"))
    False -> {
      // Minimum 8 bytes (last_stream_id + error_code)
      case payload {
        <<_reserved:1, last_stream_id:31, error_code:32, debug_data:bits>> -> {
          Ok(GoawayF(
            header,
            GoawayFrame(
              last_stream_id: last_stream_id,
              error_code: error_code,
              debug_data: debug_data,
            ),
          ))
        }
        _ -> Error(InvalidFrame("GOAWAY frame must be at least 8 bytes"))
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// WINDOW_UPDATE Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_window_update_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  // WINDOW_UPDATE is exactly 4 bytes
  case payload {
    <<_reserved:1, window_size_increment:31>> -> {
      // Increment must be non-zero
      case window_size_increment == 0 {
        True -> Error(InvalidFrame("WINDOW_UPDATE increment must be non-zero"))
        False -> {
          Ok(WindowUpdateF(
            header,
            WindowUpdateFrame(window_size_increment: window_size_increment),
          ))
        }
      }
    }
    _ -> Error(InvalidFrame("WINDOW_UPDATE frame must be 4 bytes"))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CONTINUATION Frame Parser
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn parse_continuation_payload(
  header: FrameHeader,
  payload: BitArray,
) -> Result(Frame, ParseError) {
  // Validate stream ID
  case header.stream_id == 0 {
    True -> Error(InvalidStreamId(0, "CONTINUATION"))
    False -> {
      Ok(ContinuationF(header, ContinuationFrame(header_block: payload)))
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Extracts a specified number of bytes from a BitArray
///
fn extract_bytes(
  data: BitArray,
  count: Int,
) -> Result(#(BitArray, BitArray), Nil) {
  case count <= 0 {
    True -> Ok(#(<<>>, data))
    False -> {
      case bit_array.byte_size(data) < count {
        True -> Error(Nil)
        False -> {
          // Use slice to extract bytes
          case bit_array.slice(data, 0, count) {
            Error(_) -> Error(Nil)
            Ok(extracted) -> {
              case
                bit_array.slice(data, count, bit_array.byte_size(data) - count)
              {
                Error(_) -> Ok(#(extracted, <<>>))
                Ok(remaining) -> Ok(#(extracted, remaining))
              }
            }
          }
        }
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Multi-Frame Parsing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses all complete frames from a buffer
///
pub fn parse_all_frames(
  data: BitArray,
) -> Result(#(List(Frame), BitArray), ParseError) {
  parse_all_frames_with_max_size(data, default_max_frame_size)
}

/// Parses all complete frames with a custom max frame size
///
pub fn parse_all_frames_with_max_size(
  data: BitArray,
  max_frame_size: Int,
) -> Result(#(List(Frame), BitArray), ParseError) {
  parse_frames_loop(data, max_frame_size, [])
}

fn parse_frames_loop(
  data: BitArray,
  max_frame_size: Int,
  acc: List(Frame),
) -> Result(#(List(Frame), BitArray), ParseError) {
  case has_complete_frame(data) {
    False -> Ok(#(list.reverse(acc), data))
    True -> {
      case parse_frame_with_max_size(data, max_frame_size) {
        Error(e) -> Error(e)
        Ok(ParseResult(frame, remaining)) ->
          parse_frames_loop(remaining, max_frame_size, [frame, ..acc])
      }
    }
  }
}
