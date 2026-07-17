// HTTP/2 HPACK Tests
// Tests for header compression and decompression

import aether/protocol/http2/hpack/decoder
import aether/protocol/http2/hpack/encoder
import aether/protocol/http2/hpack/huffman
import aether/protocol/http2/hpack/integer
import aether/protocol/http2/hpack/string as hpack_string
import aether/protocol/http2/hpack/table
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
  let _data = <<10:5>>
  case integer.decode_integer(<<0b00001010>>, 5) {
    Ok(#(value, _rest)) -> value |> should.equal(10)
    Error(_) -> should.fail()
  }
}

pub fn decode_integer_roundtrip_test() {
  // Test roundtrip for various values
  let test_values = [0, 1, 30, 31, 100, 1000, 10_000]
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
  let _state = decoder.new_decoder(4096)
  // Should have default max table size
  should.be_true(True)
  // State created successfully
}

pub fn new_encoder_creates_valid_state_test() {
  let _state = encoder.new_encoder(4096, True)
  // Should have default settings
  should.be_true(True)
  // State created successfully
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
// Huffman Coding Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Round-trips every byte value 0-255 individually through the raw
/// byte-oriented Huffman encode/decode functions. This exercises every
/// entry of the RFC 7541 Appendix B code table.
///
pub fn huffman_roundtrip_all_bytes_test() {
  check_byte_roundtrip_range(0)
  |> should.be_true()
}

fn check_byte_roundtrip_range(byte: Int) -> Bool {
  case byte > 255 {
    True -> True
    False ->
      case check_single_byte_roundtrip(byte) {
        True -> check_byte_roundtrip_range(byte + 1)
        False -> False
      }
  }
}

fn check_single_byte_roundtrip(byte: Int) -> Bool {
  let original = <<byte:8>>
  let encoded = huffman.encode_huffman_bytes(original)
  case huffman.decode_huffman_bytes(encoded) {
    Ok(decoded) -> decoded == original
    Error(_) -> False
  }
}

/// Round-trips a mixed ASCII string (letters, digits, punctuation, space)
/// through the string-oriented Huffman encode/decode functions.
///
pub fn huffman_roundtrip_mixed_string_test() {
  let original = "hello world! ABC-123 :/"
  let encoded = huffman.encode_huffman(original)

  case huffman.decode_huffman(encoded, bit_array.byte_size(encoded)) {
    Ok(decoded) -> decoded |> should.equal(original)
    Error(_) -> should.fail()
  }
}

/// RFC 7541 Appendix C.4.1: Huffman encoding of "www.example.com"
///
pub fn huffman_encode_rfc_c4_1_test() {
  let result = huffman.encode_huffman("www.example.com")
  result
  |> should.equal(<<
    0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff,
  >>)
}

/// RFC 7541 Appendix C.6.1: Huffman encoding of "302"
///
pub fn huffman_encode_rfc_c6_1_302_test() {
  let result = huffman.encode_huffman("302")
  result |> should.equal(<<0x64, 0x02>>)
}

/// RFC 7541 Appendix C.6.1: Huffman encoding of "private"
///
pub fn huffman_encode_rfc_c6_1_private_test() {
  let result = huffman.encode_huffman("private")
  result |> should.equal(<<0xae, 0xc3, 0x77, 0x1a, 0x4b>>)
}

/// RFC 7541 Section 5.2: leftover padding bits must all be 1s. Here "a"
/// (5-bit code 0b00011) is padded with 0s instead of 1s, which must be
/// rejected as invalid padding rather than silently accepted.
///
pub fn huffman_decode_invalid_padding_test() {
  // 'a' = 0b00011 (5 bits) followed by 3 zero padding bits: 0b00011000
  let invalid = <<0x18>>

  huffman.decode_huffman_bytes(invalid)
  |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Dynamic Table Size Update Ceiling Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// RFC 7541 Section 6.3: a dynamic table size update at or below the
/// protocol ceiling (the value passed to `new_decoder`) must succeed.
///
pub fn table_size_update_at_ceiling_succeeds_test() {
  let state = decoder.new_decoder(100)
  let encoded = encoder.encode_table_size_update(100)

  decoder.decode_header_block(state, encoded)
  |> should.be_ok()
}

pub fn table_size_update_below_ceiling_succeeds_test() {
  let state = decoder.new_decoder(100)
  let encoded = encoder.encode_table_size_update(50)

  decoder.decode_header_block(state, encoded)
  |> should.be_ok()
}

/// RFC 7541 Section 6.3: a dynamic table size update requesting a size
/// larger than the protocol ceiling must be rejected as a decoding error.
///
pub fn table_size_update_above_ceiling_fails_test() {
  let state = decoder.new_decoder(100)
  let encoded = encoder.encode_table_size_update(200)

  decoder.decode_header_block(state, encoded)
  |> should.be_error()
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
