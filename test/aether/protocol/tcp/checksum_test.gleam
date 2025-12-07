import aether/protocol/tcp/builder
import aether/protocol/tcp/checksum
import aether/protocol/tcp/header
import gleam/bit_array
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pseudo Header Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn ipv4_pseudo_header_size_test() {
  let src = <<192, 168, 1, 1>>
  let dst = <<192, 168, 1, 2>>
  let pseudo = checksum.ipv4_pseudo_header(src, dst, 20)

  bit_array.byte_size(pseudo) |> should.equal(12)
}

pub fn ipv4_pseudo_header_content_test() {
  let src = <<192, 168, 1, 1>>
  let dst = <<192, 168, 1, 2>>
  let pseudo = checksum.ipv4_pseudo_header(src, dst, 40)

  case pseudo {
    <<
      192,
      168,
      1,
      1,
      // Source IP
      192,
      168,
      1,
      2,
      // Dest IP
      0,
      // Reserved
      6,
      // Protocol (TCP)
      length_high:8,
      length_low:8,
      // TCP Length
    >> -> {
      let length = length_high * 256 + length_low
      length |> should.equal(40)
    }
    _ -> should.fail()
  }
}

pub fn ipv6_pseudo_header_size_test() {
  let src = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1>>
  let dst = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2>>
  let pseudo = checksum.ipv6_pseudo_header(src, dst, 20)

  bit_array.byte_size(pseudo) |> should.equal(40)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Checksum Calculation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn checksum_not_zero_test() {
  let src = <<192, 168, 1, 1>>
  let dst = <<192, 168, 1, 2>>
  let pseudo = checksum.ipv4_pseudo_header(src, dst, 20)

  let hdr = header.new(8080, 80)
  let segment = builder.build_header_for_checksum(hdr)

  let result = checksum.calculate_checksum(pseudo, segment)

  // Checksum should not be zero for non-trivial data
  { result != 0 } |> should.be_true()
}

pub fn checksum_is_16_bit_test() {
  let src = <<192, 168, 1, 1>>
  let dst = <<192, 168, 1, 2>>
  let pseudo = checksum.ipv4_pseudo_header(src, dst, 20)

  let hdr = header.new(8080, 80)
  let segment = builder.build_header_for_checksum(hdr)

  let result = checksum.calculate_checksum(pseudo, segment)

  // Checksum should be in 16-bit range
  { result >= 0 } |> should.be_true()
  { result <= 65_535 } |> should.be_true()
}

pub fn checksum_deterministic_test() {
  let src = <<192, 168, 1, 1>>
  let dst = <<192, 168, 1, 2>>
  let pseudo = checksum.ipv4_pseudo_header(src, dst, 20)

  let hdr = header.new(8080, 80)
  let segment = builder.build_header_for_checksum(hdr)

  let result1 = checksum.calculate_checksum(pseudo, segment)
  let result2 = checksum.calculate_checksum(pseudo, segment)

  result1 |> should.equal(result2)
}

pub fn checksum_different_for_different_data_test() {
  let src = <<192, 168, 1, 1>>
  let dst = <<192, 168, 1, 2>>
  let pseudo = checksum.ipv4_pseudo_header(src, dst, 20)

  let hdr1 = header.new(8080, 80)
  let hdr2 = header.new(8081, 81)

  let segment1 = builder.build_header_for_checksum(hdr1)
  let segment2 = builder.build_header_for_checksum(hdr2)

  let result1 = checksum.calculate_checksum(pseudo, segment1)
  let result2 = checksum.calculate_checksum(pseudo, segment2)

  { result1 != result2 } |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Checksum Verification Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn verify_checksum_value_test() {
  let src = <<192, 168, 1, 1>>
  let dst = <<192, 168, 1, 2>>
  let pseudo = checksum.ipv4_pseudo_header(src, dst, 20)

  let hdr = header.new(8080, 80)
  let segment = builder.build_header_for_checksum(hdr)

  // Calculate the checksum
  let calculated = checksum.calculate_checksum(pseudo, segment)

  // Verify it matches
  checksum.verify_checksum_value(pseudo, segment, calculated)
  |> should.be_true()
}

pub fn verify_checksum_value_wrong_test() {
  let src = <<192, 168, 1, 1>>
  let dst = <<192, 168, 1, 2>>
  let pseudo = checksum.ipv4_pseudo_header(src, dst, 20)

  let hdr = header.new(8080, 80)
  let segment = builder.build_header_for_checksum(hdr)

  // Verify with wrong checksum
  checksum.verify_checksum_value(pseudo, segment, 12_345)
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// IP Address Helper Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn ipv4_address_test() {
  let ip = checksum.ipv4_address(192, 168, 1, 1)

  ip |> should.equal(<<192, 168, 1, 1>>)
}

pub fn ipv4_address_localhost_test() {
  let ip = checksum.ipv4_address(127, 0, 0, 1)

  ip |> should.equal(<<127, 0, 0, 1>>)
}

pub fn parse_ipv4_address_test() {
  let ip = <<192, 168, 1, 100>>
  let assert Ok(#(a, b, c, d)) = checksum.parse_ipv4_address(ip)

  a |> should.equal(192)
  b |> should.equal(168)
  c |> should.equal(1)
  d |> should.equal(100)
}

pub fn parse_ipv4_address_invalid_test() {
  let invalid = <<192, 168, 1>>
  // Too short

  checksum.parse_ipv4_address(invalid)
  |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Integration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn complete_checksum_workflow_test() {
  // Build addresses
  let src_ip = checksum.ipv4_address(192, 168, 1, 100)
  let dst_ip = checksum.ipv4_address(192, 168, 1, 200)

  // Build TCP header
  let hdr =
    header.with_flags(12_345, 80, header.syn_flags())
    |> header.set_sequence_number(1_000_000)
    |> header.set_window_size(65_535)

  // Build segment without checksum
  let segment = builder.build_header_for_checksum(hdr)
  let segment_len = bit_array.byte_size(segment)

  // Create pseudo header
  let pseudo = checksum.ipv4_pseudo_header(src_ip, dst_ip, segment_len)

  // Calculate checksum
  let calc_checksum = checksum.calculate_checksum(pseudo, segment)

  // Verify the checksum is valid
  checksum.verify_checksum_value(pseudo, segment, calc_checksum)
  |> should.be_true()

  // Verify wrong checksum fails
  checksum.verify_checksum_value(pseudo, segment, calc_checksum + 1)
  |> should.be_false()
}

pub fn checksum_with_payload_test() {
  let src_ip = checksum.ipv4_address(10, 0, 0, 1)
  let dst_ip = checksum.ipv4_address(10, 0, 0, 2)

  let hdr =
    header.with_flags(8080, 80, header.psh_ack_flags())
    |> header.set_sequence_number(5000)
    |> header.set_acknowledgment_number(6000)

  let payload = <<"GET / HTTP/1.1":utf8>>
  let segment = builder.build_segment_for_checksum(hdr, payload)
  let segment_len = bit_array.byte_size(segment)

  let pseudo = checksum.ipv4_pseudo_header(src_ip, dst_ip, segment_len)
  let calc_checksum = checksum.calculate_checksum(pseudo, segment)

  // Checksum should be valid
  { calc_checksum >= 0 && calc_checksum <= 65_535 } |> should.be_true()

  // Verify it matches
  checksum.verify_checksum_value(pseudo, segment, calc_checksum)
  |> should.be_true()
}
