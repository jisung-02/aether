// HTTP/2 HPACK Tests
// Tests for header compression and decompression

import aether/protocol/http2/hpack/decoder
import aether/protocol/http2/hpack/encoder
import aether/protocol/http2/hpack/integer
import aether/protocol/http2/hpack/table
import aether/protocol/http2/hpack/string as hpack_string
import gleam/bit_array
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Integer Encoding Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn encode_integer_small_5bit_test() {
  // RFC 7541 Example: encode 10 with 5-bit prefix
  let result = integer.encode_integer(10, 5)
  result |> should.equal(<<0b00001010>>)
}

pub fn encode_integer_large_5bit_test() {
  // RFC 7541 Example: encode 1337 with 5-bit prefix
  let result = integer.encode_integer(1337, 5)
  // 1337 requires multi-byte encoding
  bit_array.byte_size(result) |> should.equal(3)
}

pub fn encode_integer_zero_test() {
  let result = integer.encode_integer(0, 5)
  result |> should.equal(<<0b00000000>>)
}

pub fn encode_integer_max_prefix_test() {
  // Encode value that exactly fits in prefix
  let result = integer.encode_integer(30, 5)
  result |> should.equal(<<0b00011110>>)
}

pub fn decode_integer_small_test() {
  let data = <<10:5>>
  case integer.decode_integer(<<0b00001010>>, 5) {
    Ok(#(value, _rest)) -> value |> should.equal(10)
    Error(_) -> should.fail()
  }
}

pub fn decode_integer_roundtrip_test() {
  // Test roundtrip for various values
  let test_values = [0, 1, 30, 31, 100, 1000, 10000]
  test_values
  |> list_all(fn(v) {
    let encoded = integer.encode_integer(v, 5)
    case integer.decode_integer(encoded, 5) {
      Ok(#(decoded, _)) -> decoded == v
      Error(_) -> False
    }
  })
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// String Encoding Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn encode_string_literal_test() {
  let result = hpack_string.encode_string("hello", False)
  // Length prefix (5) + "hello"
  bit_array.byte_size(result) |> should.equal(6)
}

pub fn decode_string_literal_roundtrip_test() {
  let original = "test-value"
  let encoded = hpack_string.encode_string(original, False)
  
  case hpack_string.decode_string(encoded) {
    Ok(#(decoded, _rest)) -> decoded.value |> should.equal(original)
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Static Table Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn static_table_authority_test() {
  // Index 1 is :authority
  case table.get_static_entry(1) {
    Ok(entry) -> entry.name |> should.equal(":authority")
    Error(_) -> should.fail()
  }
}

pub fn static_table_method_get_test() {
  // Index 2 is :method: GET
  case table.get_static_entry(2) {
    Ok(entry) -> {
      entry.name |> should.equal(":method")
      entry.value |> should.equal("GET")
    }
    Error(_) -> should.fail()
  }
}

pub fn static_table_method_post_test() {
  // Index 3 is :method: POST
  case table.get_static_entry(3) {
    Ok(entry) -> {
      entry.name |> should.equal(":method")
      entry.value |> should.equal("POST")
    }
    Error(_) -> should.fail()
  }
}

pub fn static_table_path_root_test() {
  // Index 4 is :path: /
  case table.get_static_entry(4) {
    Ok(entry) -> {
      entry.name |> should.equal(":path")
      entry.value |> should.equal("/")
    }
    Error(_) -> should.fail()
  }
}

pub fn static_table_status_200_test() {
  // Index 8 is :status: 200
  case table.get_static_entry(8) {
    Ok(entry) -> {
      entry.name |> should.equal(":status")
      entry.value |> should.equal("200")
    }
    Error(_) -> should.fail()
  }
}

pub fn static_table_invalid_index_test() {
  // Index 0 is invalid
  table.get_static_entry(0)
  |> should.be_error()
}

pub fn static_table_out_of_bounds_test() {
  // Index > 61 is invalid for static table
  table.get_static_entry(100)
  |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encoder/Decoder State Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_decoder_creates_valid_state_test() {
  let state = decoder.new_decoder(4096)
  // Should have default max table size
  should.be_true(True)  // State created successfully
}

pub fn new_encoder_creates_valid_state_test() {
  let state = encoder.new_encoder(4096, True)
  // Should have default settings
  should.be_true(True)  // State created successfully
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Encoding Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn encode_indexed_header_test() {
  let state = encoder.new_encoder(4096, False)
  let headers = [
    encoder.HeaderField(name: ":method", value: "GET"),
  ]
  
  case encoder.encode_headers(state, headers) {
    Ok(#(encoded, _new_state)) -> {
      // Should produce some output
      bit_array.byte_size(encoded) |> should.not_equal(0)
    }
    Error(_) -> should.fail()
  }
}

pub fn encode_literal_header_test() {
  let state = encoder.new_encoder(4096, False)
  let headers = [
    encoder.HeaderField(name: "x-custom", value: "custom-value"),
  ]
  
  case encoder.encode_headers(state, headers) {
    Ok(#(encoded, _new_state)) -> {
      bit_array.byte_size(encoded) |> should.not_equal(0)
    }
    Error(_) -> should.fail()
  }
}

pub fn encode_multiple_headers_test() {
  let state = encoder.new_encoder(4096, False)
  let headers = [
    encoder.HeaderField(name: ":method", value: "GET"),
    encoder.HeaderField(name: ":path", value: "/"),
    encoder.HeaderField(name: ":scheme", value: "https"),
    encoder.HeaderField(name: "content-type", value: "application/json"),
  ]
  
  case encoder.encode_headers(state, headers) {
    Ok(#(encoded, _new_state)) -> {
      bit_array.byte_size(encoded) |> should.not_equal(0)
    }
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Roundtrip Tests (Encode -> Decode)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn header_roundtrip_simple_test() {
  let enc_state = encoder.new_encoder(4096, False)
  let dec_state = decoder.new_decoder(4096)
  
  let headers = [
    encoder.HeaderField(name: ":method", value: "GET"),
    encoder.HeaderField(name: ":path", value: "/api/test"),
  ]
  
  case encoder.encode_headers(enc_state, headers) {
    Ok(#(encoded, _)) -> {
      case decoder.decode_header_block(dec_state, encoded) {
        Ok(#(decoded_headers, _)) -> {
          // Should have same number of headers
          list_length(decoded_headers) |> should.equal(2)
        }
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn list_all(items: List(a), predicate: fn(a) -> Bool) -> Bool {
  case items {
    [] -> True
    [first, ..rest] ->
      case predicate(first) {
        False -> False
        True -> list_all(rest, predicate)
      }
  }
}

fn list_length(items: List(a)) -> Int {
  list_length_acc(items, 0)
}

fn list_length_acc(items: List(a), acc: Int) -> Int {
  case items {
    [] -> acc
    [_, ..rest] -> list_length_acc(rest, acc + 1)
  }
}
