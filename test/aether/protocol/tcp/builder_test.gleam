import aether/protocol/tcp/builder
import aether/protocol/tcp/header
import gleam/bit_array
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Build Header Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_header_produces_20_bytes_test() {
  let hdr = header.new(8080, 80)
  let bytes = builder.build_header(hdr)

  bit_array.byte_size(bytes) |> should.equal(20)
}

pub fn build_header_source_port_test() {
  let hdr = header.new(8080, 80)
  let bytes = builder.build_header(hdr)

  // Source port is first 2 bytes (8080 = 0x1F90)
  case bytes {
    <<source_high:8, source_low:8, _rest:bits>> -> {
      let source_port = source_high * 256 + source_low
      source_port |> should.equal(8080)
    }
    _ -> should.fail()
  }
}

pub fn build_header_dest_port_test() {
  let hdr = header.new(8080, 80)
  let bytes = builder.build_header(hdr)

  // Destination port is bytes 3-4 (80 = 0x0050)
  case bytes {
    <<_src:16, dest_high:8, dest_low:8, _rest:bits>> -> {
      let dest_port = dest_high * 256 + dest_low
      dest_port |> should.equal(80)
    }
    _ -> should.fail()
  }
}

pub fn build_header_sequence_number_test() {
  let hdr =
    header.new(8080, 80)
    |> header.set_sequence_number(1_000_000)
  let bytes = builder.build_header(hdr)

  // Sequence number is bytes 5-8
  case bytes {
    <<_ports:32, seq:32, _rest:bits>> -> {
      seq |> should.equal(1_000_000)
    }
    _ -> should.fail()
  }
}

pub fn build_header_ack_number_test() {
  let hdr =
    header.new(8080, 80)
    |> header.set_acknowledgment_number(2_000_000)
  let bytes = builder.build_header(hdr)

  // ACK number is bytes 9-12
  case bytes {
    <<_ports:32, _seq:32, ack:32, _rest:bits>> -> {
      ack |> should.equal(2_000_000)
    }
    _ -> should.fail()
  }
}

pub fn build_header_data_offset_test() {
  let hdr = header.new(8080, 80)
  let bytes = builder.build_header(hdr)

  // Data offset is upper 4 bits of byte 13
  case bytes {
    <<_first:96, offset_and_flags:8, _rest:bits>> -> {
      let data_offset = offset_and_flags / 16
      data_offset |> should.equal(5)
    }
    _ -> should.fail()
  }
}

pub fn build_header_window_size_test() {
  let hdr =
    header.new(8080, 80)
    |> header.set_window_size(32_768)
  let bytes = builder.build_header(hdr)

  // Window size is bytes 15-16
  case bytes {
    <<_first:112, window:16, _rest:bits>> -> {
      window |> should.equal(32_768)
    }
    _ -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flags Conversion Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn flags_to_int_default_test() {
  let flags = header.default_flags()
  builder.flags_to_int(flags) |> should.equal(0)
}

pub fn flags_to_int_syn_test() {
  let flags = header.syn_flags()
  // SYN is bit 1 (value 2)
  builder.flags_to_int(flags) |> should.equal(2)
}

pub fn flags_to_int_ack_test() {
  let flags = header.ack_flags()
  // ACK is bit 4 (value 16)
  builder.flags_to_int(flags) |> should.equal(16)
}

pub fn flags_to_int_syn_ack_test() {
  let flags = header.syn_ack_flags()
  // SYN (2) + ACK (16) = 18
  builder.flags_to_int(flags) |> should.equal(18)
}

pub fn flags_to_int_fin_test() {
  let flags = header.fin_flags()
  // FIN is bit 0 (value 1)
  builder.flags_to_int(flags) |> should.equal(1)
}

pub fn flags_to_int_fin_ack_test() {
  let flags = header.fin_ack_flags()
  // FIN (1) + ACK (16) = 17
  builder.flags_to_int(flags) |> should.equal(17)
}

pub fn flags_to_int_rst_test() {
  let flags = header.rst_flags()
  // RST is bit 2 (value 4)
  builder.flags_to_int(flags) |> should.equal(4)
}

pub fn flags_to_int_psh_ack_test() {
  let flags = header.psh_ack_flags()
  // PSH (8) + ACK (16) = 24
  builder.flags_to_int(flags) |> should.equal(24)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Segment Building Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_segment_with_payload_test() {
  let hdr = header.new(8080, 80)
  let payload = <<"Hello":utf8>>
  let segment = builder.build_segment(hdr, payload)

  // 20 bytes header + 5 bytes payload
  bit_array.byte_size(segment) |> should.equal(25)
}

pub fn build_segment_empty_payload_test() {
  let hdr = header.new(8080, 80)
  let segment = builder.build_segment(hdr, <<>>)

  bit_array.byte_size(segment) |> should.equal(20)
}

pub fn build_header_for_checksum_zeros_checksum_test() {
  let hdr =
    header.new(8080, 80)
    |> header.set_checksum(12_345)
  let bytes = builder.build_header_for_checksum(hdr)

  // Checksum is bytes 17-18 (should be 0)
  case bytes {
    <<_first:128, checksum:16, _rest:bits>> -> {
      checksum |> should.equal(0)
    }
    _ -> should.fail()
  }
}
