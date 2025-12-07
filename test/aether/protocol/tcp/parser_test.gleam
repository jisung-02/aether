import aether/protocol/tcp/builder
import aether/protocol/tcp/header
import aether/protocol/tcp/parser
import gleam/result
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Parse Header Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_valid_header_test() {
  let original = header.new(8080, 80)
    |> header.set_sequence_number(1000)
    |> header.set_acknowledgment_number(2000)
    |> header.set_flags(header.syn_flags())

  let bytes = builder.build_header(original)
  let assert Ok(parsed) = parser.parse_header(bytes)

  parsed.source_port |> should.equal(8080)
  parsed.destination_port |> should.equal(80)
  parsed.sequence_number |> should.equal(1000)
  parsed.acknowledgment_number |> should.equal(2000)
  parsed.flags.syn |> should.be_true()
}

pub fn parse_header_preserves_flags_test() {
  let original = header.with_flags(8080, 80, header.syn_ack_flags())
  let bytes = builder.build_header(original)
  let assert Ok(parsed) = parser.parse_header(bytes)

  parsed.flags.syn |> should.be_true()
  parsed.flags.ack |> should.be_true()
  parsed.flags.fin |> should.be_false()
}

pub fn parse_header_preserves_window_test() {
  let original = header.new(8080, 80)
    |> header.set_window_size(32_768)
  let bytes = builder.build_header(original)
  let assert Ok(parsed) = parser.parse_header(bytes)

  parsed.window_size |> should.equal(32_768)
}

pub fn parse_header_preserves_checksum_test() {
  let original = header.new(8080, 80)
    |> header.set_checksum(12345)
  let bytes = builder.build_header(original)
  let assert Ok(parsed) = parser.parse_header(bytes)

  parsed.checksum |> should.equal(12345)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Parse Error Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_invalid_length_short_test() {
  let short_bytes = <<1, 2, 3>>

  parser.parse_header(short_bytes)
  |> result.is_error()
  |> should.be_true()
}

pub fn parse_invalid_length_19_bytes_test() {
  let bytes = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>

  parser.parse_header(bytes)
  |> result.is_error()
  |> should.be_true()
}

pub fn parse_empty_input_test() {
  parser.parse_header(<<>>)
  |> result.is_error()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Roundtrip Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn roundtrip_syn_header_test() {
  let original = header.with_flags(12345, 8080, header.syn_flags())
    |> header.set_sequence_number(100_000)
    |> header.set_window_size(65_535)

  let bytes = builder.build_header(original)
  let assert Ok(parsed) = parser.parse_header(bytes)

  parsed.source_port |> should.equal(12345)
  parsed.destination_port |> should.equal(8080)
  parsed.sequence_number |> should.equal(100_000)
  parsed.window_size |> should.equal(65_535)
  parsed.flags.syn |> should.be_true()
  parsed.flags.ack |> should.be_false()
}

pub fn roundtrip_syn_ack_header_test() {
  let original = header.with_flags(80, 12345, header.syn_ack_flags())
    |> header.set_sequence_number(200_000)
    |> header.set_acknowledgment_number(100_001)
    |> header.set_window_size(32_768)

  let bytes = builder.build_header(original)
  let assert Ok(parsed) = parser.parse_header(bytes)

  parsed.source_port |> should.equal(80)
  parsed.destination_port |> should.equal(12345)
  parsed.sequence_number |> should.equal(200_000)
  parsed.acknowledgment_number |> should.equal(100_001)
  parsed.window_size |> should.equal(32_768)
  parsed.flags.syn |> should.be_true()
  parsed.flags.ack |> should.be_true()
}

pub fn roundtrip_ack_header_test() {
  let original = header.with_flags(12345, 80, header.ack_flags())
    |> header.set_sequence_number(100_001)
    |> header.set_acknowledgment_number(200_001)

  let bytes = builder.build_header(original)
  let assert Ok(parsed) = parser.parse_header(bytes)

  parsed.flags.syn |> should.be_false()
  parsed.flags.ack |> should.be_true()
  parsed.sequence_number |> should.equal(100_001)
  parsed.acknowledgment_number |> should.equal(200_001)
}

pub fn roundtrip_fin_ack_header_test() {
  let original = header.with_flags(8080, 80, header.fin_ack_flags())
    |> header.set_sequence_number(500_000)

  let bytes = builder.build_header(original)
  let assert Ok(parsed) = parser.parse_header(bytes)

  parsed.flags.fin |> should.be_true()
  parsed.flags.ack |> should.be_true()
  parsed.flags.syn |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Segment Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_segment_with_payload_test() {
  let hdr = header.with_flags(8080, 80, header.psh_ack_flags())
  let payload = <<"Hello":utf8>>
  let segment = builder.build_segment(hdr, payload)

  let assert Ok(#(parsed_hdr, parsed_payload)) = parser.parse_segment(segment)

  parsed_hdr.source_port |> should.equal(8080)
  parsed_hdr.flags.psh |> should.be_true()
  parsed_hdr.flags.ack |> should.be_true()
  parsed_payload |> should.equal(<<"Hello":utf8>>)
}

pub fn parse_segment_empty_payload_test() {
  let hdr = header.with_flags(8080, 80, header.ack_flags())
  let segment = builder.build_segment(hdr, <<>>)

  let assert Ok(#(parsed_hdr, parsed_payload)) = parser.parse_segment(segment)

  parsed_hdr.flags.ack |> should.be_true()
  parsed_payload |> should.equal(<<>>)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Int to Flags Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn int_to_flags_zero_test() {
  let flags = parser.int_to_flags(0)

  flags.ns |> should.be_false()
  flags.syn |> should.be_false()
  flags.ack |> should.be_false()
  flags.fin |> should.be_false()
}

pub fn int_to_flags_syn_test() {
  let flags = parser.int_to_flags(2)

  flags.syn |> should.be_true()
  flags.ack |> should.be_false()
}

pub fn int_to_flags_ack_test() {
  let flags = parser.int_to_flags(16)

  flags.ack |> should.be_true()
  flags.syn |> should.be_false()
}

pub fn int_to_flags_syn_ack_test() {
  let flags = parser.int_to_flags(18)

  flags.syn |> should.be_true()
  flags.ack |> should.be_true()
}

pub fn int_to_flags_fin_test() {
  let flags = parser.int_to_flags(1)

  flags.fin |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Message Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_to_string_invalid_length_test() {
  let err = parser.InvalidLength(expected: 20, actual: 10)
  let msg = parser.error_to_string(err)

  // Just verify it returns a non-empty string
  { msg != "" } |> should.be_true()
}

pub fn error_to_string_malformed_test() {
  let err = parser.MalformedHeader(message: "test error")
  let msg = parser.error_to_string(err)

  { msg != "" } |> should.be_true()
}
