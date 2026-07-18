// QPACK field compression tests (RFC 9204), static-table-only.

import aether/protocol/http2/hpack/huffman
import aether/protocol/http3/qpack
import aether/protocol/http3/qpack_static
import aether/protocol/quic/error.{type WireError, Malformed}
import gleam/bit_array
import gleam/int
import gleam/string
import gleeunit/should

fn hex(string: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(string)
  bytes
}

fn assert_malformed(result: Result(a, WireError)) -> Nil {
  case result {
    Error(Malformed(_)) -> Nil
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// qpack_static
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn static_entry_authority_test() {
  qpack_static.entry(0) |> should.equal(Ok(#(":authority", "")))
}

pub fn static_entry_path_test() {
  qpack_static.entry(1) |> should.equal(Ok(#(":path", "/")))
}

pub fn static_entry_method_get_test() {
  qpack_static.entry(17) |> should.equal(Ok(#(":method", "GET")))
}

pub fn static_entry_status_200_test() {
  qpack_static.entry(25) |> should.equal(Ok(#(":status", "200")))
}

pub fn static_entry_out_of_range_test() {
  qpack_static.entry(99) |> should.equal(Error(Nil))
}

pub fn static_entry_negative_test() {
  qpack_static.entry(-1) |> should.equal(Error(Nil))
}

pub fn static_find_full_match_test() {
  qpack_static.find(":method", "GET")
  |> should.equal(qpack_static.FullMatch(17))
}

pub fn static_find_name_match_test() {
  // :authority only appears with value "" in the static table, so any
  // other value is a name-only match on index 0.
  qpack_static.find(":authority", "example.com")
  |> should.equal(qpack_static.NameMatch(0))
}

pub fn static_find_name_match_first_occurrence_test() {
  // The first row whose *name* is "content-type" is index 44; a value
  // not present anywhere in the table should match that first index.
  qpack_static.find("content-type", "application/x-custom")
  |> should.equal(qpack_static.NameMatch(44))
}

pub fn static_find_no_match_test() {
  qpack_static.find("x-custom-header", "some-value")
  |> should.equal(qpack_static.NoMatch)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// qpack.decode: RFC 9204 vectors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn decode_appendix_b1_vector_test() {
  // RFC 9204 Appendix B.1: Literal Field Line with Name Reference,
  // static index 1 (:path), raw (non-Huffman) value "/index.html".
  qpack.decode(hex("0000510b2f696e6465782e68746d6c"))
  |> should.equal(Ok([#(":path", "/index.html")]))
}

pub fn decode_indexed_static_path_test() {
  // 0xc1 = 0b1100_0001: Indexed Field Line, T=1 (static), index=1.
  qpack.decode(hex("0000c1"))
  |> should.equal(Ok([#(":path", "/")]))
}

pub fn decode_indexed_static_method_get_test() {
  // 0xd1 = 0b1101_0001: Indexed Field Line, T=1 (static), index=17.
  qpack.decode(hex("0000d1"))
  |> should.equal(Ok([#(":method", "GET")]))
}

pub fn decode_multiple_field_lines_test() {
  // c1 (:path=/) followed by d1 (:method=GET).
  qpack.decode(hex("0000c1d1"))
  |> should.equal(Ok([#(":path", "/"), #(":method", "GET")]))
}

pub fn decode_empty_field_section_test() {
  qpack.decode(hex("0000")) |> should.equal(Ok([]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// qpack.decode: malformed input
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn decode_nonzero_required_insert_count_test() {
  qpack.decode(hex("0200c1")) |> assert_malformed
}

pub fn decode_dynamic_indexed_field_line_test() {
  // 0x80 = 0b1000_0000: Indexed Field Line, T=0 (dynamic) -- rejected,
  // since no dynamic table capacity was ever granted.
  qpack.decode(hex("000080")) |> assert_malformed
}

pub fn decode_dynamic_name_reference_test() {
  // 0x40 = 0b0100_0000: Literal Field Line with Name Reference, T=0
  // (dynamic) -- rejected.
  qpack.decode(hex("00004000")) |> assert_malformed
}

pub fn decode_post_base_indexed_test() {
  // 0x10 = 0b0001_0000: Indexed Field Line With Post-Base Index, always
  // rejected (no dynamic table).
  qpack.decode(hex("000010")) |> assert_malformed
}

pub fn decode_post_base_literal_name_test() {
  // 0x00 = 0b0000_0000: Literal Field Line With Post-Base Name
  // Reference, always rejected (no dynamic table).
  qpack.decode(hex("000000")) |> assert_malformed
}

pub fn decode_truncated_prefix_test() {
  qpack.decode(hex("")) |> assert_malformed
}

pub fn decode_truncated_field_line_test() {
  // 0x51 starts a literal field line with a static name reference
  // (index 1, :path), then a string-literal length byte (0xff) that
  // claims more length than the (zero) remaining bytes provide.
  qpack.decode(hex("000051ff")) |> assert_malformed
}

pub fn decode_invalid_static_index_test() {
  // 0xff = 0b1111_1111: Indexed Field Line, T=1, and a 6-bit prefix
  // value of 63 that overflows into a continuation byte (0x64 = 100),
  // yielding index 63 + 100 = 163 -- out of the static table's 0-98
  // range.
  qpack.decode(hex("0000ff64")) |> assert_malformed
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// qpack.encode / qpack.decode round trips
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn round_trip_get_request_test() {
  let fields = [
    #(":method", "GET"),
    #(":path", "/"),
    #(":scheme", "https"),
    #(":authority", "example.com"),
  ]

  qpack.encode(fields) |> qpack.decode |> should.equal(Ok(fields))
}

pub fn round_trip_response_test() {
  let fields = [#(":status", "200"), #("content-type", "text/plain")]

  qpack.encode(fields) |> qpack.decode |> should.equal(Ok(fields))
}

pub fn round_trip_literal_name_test() {
  let fields = [#("x-custom", "hello world")]

  qpack.encode(fields) |> qpack.decode |> should.equal(Ok(fields))
}

pub fn round_trip_mixed_fields_test() {
  let fields = [
    #(":status", "404"),
    #("x-request-id", "abc-123-def-456"),
    #("cache-control", "no-store"),
    #("x-another-custom-header", "some raw value here"),
  ]

  qpack.encode(fields) |> qpack.decode |> should.equal(Ok(fields))
}

pub fn round_trip_empty_fields_test() {
  qpack.encode([]) |> qpack.decode |> should.equal(Ok([]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Huffman path
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn encode_uses_huffman_when_shorter_test() {
  // A long, lowercase-ascii value Huffman-compresses well (each 'a' is a
  // 5-bit code), so it is strictly shorter Huffman-encoded than raw.
  let name = "x-abc"
  let value = string.repeat("a", 30)
  let fields = [#(name, value)]

  // Sanity: confirm this value really does benefit from Huffman coding.
  let raw = bit_array.from_string(value)
  let huffman_encoded = huffman.encode_huffman_bytes(raw)
  { bit_array.byte_size(huffman_encoded) < bit_array.byte_size(raw) }
  |> should.be_true()

  let encoded = qpack.encode(fields)

  // Layout: 2-byte prefix, then the literal-literal-name header byte,
  // then `name` (5 raw bytes, since "x-abc" is under the 10-byte
  // Huffman threshold), then the value's string-literal header byte,
  // whose top bit (H) must be set.
  let name_len = bit_array.byte_size(bit_array.from_string(name))
  let value_header_offset = 2 + 1 + name_len

  case bit_array.slice(encoded, value_header_offset, 1) {
    Ok(<<header_byte:8>>) ->
      int.bitwise_and(header_byte, 0x80) |> should.equal(0x80)
    _ -> should.fail()
  }

  // And it still decodes back to the original field.
  encoded |> qpack.decode |> should.equal(Ok(fields))
}

pub fn encode_uses_raw_for_short_values_test() {
  // Short values (<10 bytes) never use Huffman per
  // `should_huffman_encode`; round-trip regardless.
  let fields = [#("x-y", "hi")]

  qpack.encode(fields) |> qpack.decode |> should.equal(Ok(fields))
}
