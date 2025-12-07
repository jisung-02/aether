// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Frame Parser Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/http2/frame.{
  ContinuationF, DataF, GoawayF, HeadersF, PingF, PriorityF, PushPromiseF,
  RstStreamF, SettingsF, WindowUpdateF,
}
import aether/protocol/http2/frame_builder
import aether/protocol/http2/frame_parser
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_header_insufficient_data_test() {
  let data = <<0, 0, 10>>
  // Only 3 bytes, need 9

  case frame_parser.parse_header(data) {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

pub fn parse_header_valid_test() {
  // Length: 10, Type: DATA(0), Flags: 0x01, Stream ID: 1
  let data = <<0, 0, 10, 0, 1, 0, 0, 0, 1>>

  case frame_parser.parse_header(data) {
    Error(_) -> should.fail()
    Ok(#(header, _remaining)) -> {
      header.length |> should.equal(10)
      header.frame_type |> should.equal(frame.Data)
      header.flags |> should.equal(1)
      header.stream_id |> should.equal(1)
    }
  }
}

pub fn has_complete_header_test() {
  frame_parser.has_complete_header(<<0, 0, 0, 0, 0, 0, 0, 0, 0>>)
  |> should.be_true()

  frame_parser.has_complete_header(<<0, 0, 0, 0, 0, 0, 0, 0>>)
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// DATA Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_data_frame_simple_test() {
  let data_payload = <<"Hello":utf8>>
  let data_frame = frame_builder.create_data_frame(1, data_payload, False)
  let bytes = frame_builder.build_frame(data_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        DataF(header, payload) -> {
          header.stream_id |> should.equal(1)
          header.frame_type |> should.equal(frame.Data)
          payload.data |> should.equal(data_payload)
          payload.pad_length |> should.equal(0)
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn parse_data_frame_with_end_stream_test() {
  let data_payload = <<"Test":utf8>>
  let data_frame = frame_builder.create_data_frame(3, data_payload, True)
  let bytes = frame_builder.build_frame(data_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        DataF(header, payload) -> {
          header.stream_id |> should.equal(3)
          frame.is_end_stream(header.flags) |> should.be_true()
          payload.data |> should.equal(data_payload)
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn parse_data_frame_stream_zero_error_test() {
  // DATA frame with stream ID 0 should error
  let bytes = <<0, 0, 5, 0, 0, 0, 0, 0, 0, "hello":utf8>>

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HEADERS Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_headers_frame_simple_test() {
  let header_block = <<0x82, 0x86, 0x84>>
  // HPACK encoded headers
  let headers_frame =
    frame_builder.create_headers_frame(1, header_block, False, True)
  let bytes = frame_builder.build_frame(headers_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        HeadersF(header, payload) -> {
          header.stream_id |> should.equal(1)
          header.frame_type |> should.equal(frame.Headers)
          frame.is_end_headers(header.flags) |> should.be_true()
          payload.header_block |> should.equal(header_block)
          payload.has_priority |> should.be_false()
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn parse_headers_frame_with_priority_test() {
  let header_block = <<0x82>>
  let headers_frame =
    frame_builder.create_headers_frame_with_priority(
      3,
      header_block,
      1,
      True,
      16,
      False,
      True,
    )
  let bytes = frame_builder.build_frame(headers_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        HeadersF(header, payload) -> {
          header.stream_id |> should.equal(3)
          frame.is_priority(header.flags) |> should.be_true()
          payload.has_priority |> should.be_true()
          payload.stream_dependency |> should.equal(1)
          payload.exclusive |> should.be_true()
          payload.weight |> should.equal(16)
        }
        _ -> should.fail()
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PRIORITY Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_priority_frame_test() {
  let priority_frame = frame_builder.create_priority_frame(5, 3, False, 32)
  let bytes = frame_builder.build_frame(priority_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        PriorityF(header, payload) -> {
          header.stream_id |> should.equal(5)
          header.frame_type |> should.equal(frame.Priority)
          payload.stream_dependency |> should.equal(3)
          payload.exclusive |> should.be_false()
          payload.weight |> should.equal(32)
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn parse_priority_frame_exclusive_test() {
  let priority_frame = frame_builder.create_priority_frame(7, 5, True, 128)
  let bytes = frame_builder.build_frame(priority_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        PriorityF(_header, payload) -> {
          payload.exclusive |> should.be_true()
          payload.stream_dependency |> should.equal(5)
          payload.weight |> should.equal(128)
        }
        _ -> should.fail()
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RST_STREAM Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_rst_stream_frame_test() {
  let rst_frame = frame_builder.create_rst_stream_frame(1, 8)
  // CANCEL error
  let bytes = frame_builder.build_frame(rst_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        RstStreamF(header, payload) -> {
          header.stream_id |> should.equal(1)
          header.frame_type |> should.equal(frame.RstStream)
          payload.error_code |> should.equal(8)
        }
        _ -> should.fail()
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SETTINGS Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_settings_frame_empty_test() {
  let settings_frame = frame_builder.create_settings_frame([])
  let bytes = frame_builder.build_frame(settings_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        SettingsF(header, payload) -> {
          header.stream_id |> should.equal(0)
          header.frame_type |> should.equal(frame.Settings)
          payload.ack |> should.be_false()
          list_length(payload.parameters) |> should.equal(0)
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn parse_settings_frame_with_params_test() {
  let params = [
    frame.SettingsParameter(identifier: frame.MaxConcurrentStreams, value: 100),
    frame.SettingsParameter(identifier: frame.InitialWindowSize, value: 65_535),
  ]
  let settings_frame = frame_builder.create_settings_frame(params)
  let bytes = frame_builder.build_frame(settings_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        SettingsF(_header, payload) -> {
          payload.ack |> should.be_false()
          list_length(payload.parameters) |> should.equal(2)
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn parse_settings_ack_frame_test() {
  let ack_frame = frame_builder.create_settings_ack_frame()
  let bytes = frame_builder.build_frame(ack_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        SettingsF(_header, payload) -> {
          payload.ack |> should.be_true()
          list_length(payload.parameters) |> should.equal(0)
        }
        _ -> should.fail()
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PUSH_PROMISE Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_push_promise_frame_test() {
  let header_block = <<0x82, 0x84>>
  let pp_frame =
    frame_builder.create_push_promise_frame(1, 2, header_block, True)
  let bytes = frame_builder.build_frame(pp_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        PushPromiseF(header, payload) -> {
          header.stream_id |> should.equal(1)
          header.frame_type |> should.equal(frame.PushPromise)
          frame.is_end_headers(header.flags) |> should.be_true()
          payload.promised_stream_id |> should.equal(2)
          payload.header_block |> should.equal(header_block)
        }
        _ -> should.fail()
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PING Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_ping_frame_test() {
  let opaque_data = <<1, 2, 3, 4, 5, 6, 7, 8>>
  let ping_frame = frame_builder.create_ping_frame(opaque_data)
  let bytes = frame_builder.build_frame(ping_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        PingF(header, payload) -> {
          header.stream_id |> should.equal(0)
          header.frame_type |> should.equal(frame.Ping)
          payload.ack |> should.be_false()
          payload.opaque_data |> should.equal(opaque_data)
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn parse_ping_ack_frame_test() {
  let opaque_data = <<8, 7, 6, 5, 4, 3, 2, 1>>
  let ping_ack_frame = frame_builder.create_ping_ack_frame(opaque_data)
  let bytes = frame_builder.build_frame(ping_ack_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        PingF(_header, payload) -> {
          payload.ack |> should.be_true()
          payload.opaque_data |> should.equal(opaque_data)
        }
        _ -> should.fail()
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GOAWAY Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_goaway_frame_test() {
  let debug_data = <<"shutdown":utf8>>
  let goaway_frame = frame_builder.create_goaway_frame(100, 0, debug_data)
  let bytes = frame_builder.build_frame(goaway_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        GoawayF(header, payload) -> {
          header.stream_id |> should.equal(0)
          header.frame_type |> should.equal(frame.Goaway)
          payload.last_stream_id |> should.equal(100)
          payload.error_code |> should.equal(0)
          payload.debug_data |> should.equal(debug_data)
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn parse_goaway_frame_with_error_test() {
  let goaway_frame = frame_builder.create_goaway_frame(50, 1, <<>>)
  // PROTOCOL_ERROR
  let bytes = frame_builder.build_frame(goaway_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        GoawayF(_header, payload) -> {
          payload.last_stream_id |> should.equal(50)
          payload.error_code |> should.equal(1)
        }
        _ -> should.fail()
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// WINDOW_UPDATE Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_window_update_frame_stream_test() {
  let wu_frame = frame_builder.create_window_update_frame(1, 32_768)
  let bytes = frame_builder.build_frame(wu_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        WindowUpdateF(header, payload) -> {
          header.stream_id |> should.equal(1)
          header.frame_type |> should.equal(frame.WindowUpdate)
          payload.window_size_increment |> should.equal(32_768)
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn parse_window_update_frame_connection_test() {
  let wu_frame = frame_builder.create_connection_window_update_frame(65_535)
  let bytes = frame_builder.build_frame(wu_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        WindowUpdateF(header, payload) -> {
          header.stream_id |> should.equal(0)
          payload.window_size_increment |> should.equal(65_535)
        }
        _ -> should.fail()
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CONTINUATION Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_continuation_frame_test() {
  let header_block = <<0x82, 0x86>>
  let cont_frame =
    frame_builder.create_continuation_frame(1, header_block, True)
  let bytes = frame_builder.build_frame(cont_frame)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      case result.frame {
        ContinuationF(header, payload) -> {
          header.stream_id |> should.equal(1)
          header.frame_type |> should.equal(frame.Continuation)
          frame.is_end_headers(header.flags) |> should.be_true()
          payload.header_block |> should.equal(header_block)
        }
        _ -> should.fail()
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Multi-Frame Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_all_frames_test() {
  let frame1 = frame_builder.create_settings_frame([])
  let frame2 = frame_builder.create_ping_frame(<<1, 2, 3, 4, 5, 6, 7, 8>>)

  let bytes = frame_builder.build_frames([frame1, frame2])

  case frame_parser.parse_all_frames(bytes) {
    Error(_) -> should.fail()
    Ok(#(frames, remaining)) -> {
      list_length(frames) |> should.equal(2)
      bit_array_size(remaining) |> should.equal(0)
    }
  }
}

pub fn parse_all_frames_with_remaining_test() {
  let frame1 = frame_builder.create_settings_ack_frame()
  let bytes = frame_builder.build_frame(frame1)

  // Add incomplete frame data
  let incomplete = <<bytes:bits, 0, 0, 10>>

  case frame_parser.parse_all_frames(incomplete) {
    Error(_) -> should.fail()
    Ok(#(frames, remaining)) -> {
      list_length(frames) |> should.equal(1)
      bit_array_size(remaining) |> should.equal(3)
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Round-Trip Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn roundtrip_data_frame_test() {
  let original = frame_builder.create_data_frame(1, <<"test":utf8>>, True)
  let bytes = frame_builder.build_frame(original)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      // Rebuild and compare
      let rebuilt = frame_builder.build_frame(result.frame)
      rebuilt |> should.equal(bytes)
    }
  }
}

pub fn roundtrip_settings_frame_test() {
  let params = [
    frame.SettingsParameter(identifier: frame.MaxFrameSize, value: 32_768),
  ]
  let original = frame_builder.create_settings_frame(params)
  let bytes = frame_builder.build_frame(original)

  case frame_parser.parse_frame(bytes) {
    Error(_) -> should.fail()
    Ok(result) -> {
      let rebuilt = frame_builder.build_frame(result.frame)
      rebuilt |> should.equal(bytes)
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn list_length(items: List(a)) -> Int {
  list_length_helper(items, 0)
}

fn list_length_helper(items: List(a), acc: Int) -> Int {
  case items {
    [] -> acc
    [_, ..rest] -> list_length_helper(rest, acc + 1)
  }
}

fn bit_array_size(data: BitArray) -> Int {
  case data {
    <<>> -> 0
    <<_:8, rest:bits>> -> 1 + bit_array_size(rest)
    _ -> 0
  }
}
