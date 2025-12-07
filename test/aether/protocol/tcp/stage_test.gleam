// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Stage Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/core/message
import aether/pipeline/stage
import aether/protocol/protocol
import aether/protocol/registry
import aether/protocol/tcp/builder
import aether/protocol/tcp/header
import aether/protocol/tcp/stage as tcp_stage
import gleam/bit_array
import gleam/option
import gleam/result
import gleam/set
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decode Stage Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn decode_stage_extracts_payload_test() {
  // Create a TCP segment with header and payload
  let tcp_header =
    header.new(80, 12_345)
    |> header.set_sequence_number(1000)
    |> header.set_acknowledgment_number(2000)
    |> header.set_flags(header.ack_flags())

  let payload = <<"Hello, TCP!":utf8>>
  let header_bytes = builder.build_header(tcp_header)
  let full_segment = bit_array.append(header_bytes, payload)

  // Create input data with full segment
  let input_data = message.new(full_segment)

  // Run decode stage
  let decoder = tcp_stage.decode()
  let assert Ok(decoded) = stage.execute(decoder, input_data)

  // Verify payload is extracted
  message.bytes(decoded)
  |> should.equal(payload)
}

pub fn decode_stage_stores_segment_in_metadata_test() {
  // Create a TCP segment
  let tcp_header =
    header.new(8080, 80)
    |> header.set_flags(header.syn_flags())

  let payload = <<"Test payload":utf8>>
  let full_segment = builder.build_segment(tcp_header, payload)

  // Run decode stage
  let input_data = message.new(full_segment)
  let decoder = tcp_stage.decode()
  let assert Ok(decoded) = stage.execute(decoder, input_data)

  // Verify segment is in metadata
  tcp_stage.get_segment(decoded)
  |> option.is_some()
  |> should.be_true()
}

pub fn decode_stage_preserves_header_info_test() {
  // Create a TCP segment with specific header values
  let tcp_header =
    header.new(5000, 6000)
    |> header.set_sequence_number(12_345)
    |> header.set_acknowledgment_number(67_890)
    |> header.set_flags(header.psh_ack_flags())
    |> header.set_window_size(32_768)

  let payload = <<"Data":utf8>>
  let full_segment = builder.build_segment(tcp_header, payload)

  // Run decode stage
  let input_data = message.new(full_segment)
  let decoder = tcp_stage.decode()
  let assert Ok(decoded) = stage.execute(decoder, input_data)

  // Verify header info is preserved
  let assert option.Some(segment) = tcp_stage.get_segment(decoded)

  segment.header.source_port |> should.equal(5000)
  segment.header.destination_port |> should.equal(6000)
  segment.header.sequence_number |> should.equal(12_345)
  segment.header.acknowledgment_number |> should.equal(67_890)
  segment.header.flags.psh |> should.be_true()
  segment.header.flags.ack |> should.be_true()
  segment.header.window_size |> should.equal(32_768)
}

pub fn decode_stage_empty_payload_test() {
  // Create a TCP segment with no payload (just header)
  let tcp_header =
    header.new(80, 8080)
    |> header.set_flags(header.ack_flags())

  let full_segment = builder.build_segment(tcp_header, <<>>)

  // Run decode stage
  let input_data = message.new(full_segment)
  let decoder = tcp_stage.decode()
  let assert Ok(decoded) = stage.execute(decoder, input_data)

  // Verify empty payload
  message.bytes(decoded)
  |> should.equal(<<>>)
}

pub fn decode_stage_invalid_data_returns_error_test() {
  // Create data that's too short to be a valid TCP segment
  let invalid_data = message.new(<<1, 2, 3, 4, 5>>)

  let decoder = tcp_stage.decode()

  stage.execute(decoder, invalid_data)
  |> result.is_error()
  |> should.be_true()
}

pub fn decode_stage_empty_input_returns_error_test() {
  let empty_data = message.new(<<>>)

  let decoder = tcp_stage.decode()

  stage.execute(decoder, empty_data)
  |> result.is_error()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encode Stage Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn encode_stage_builds_segment_from_metadata_test() {
  // Create a segment and store in metadata
  let segment =
    tcp_stage.new_segment(12_345, 80, <<"Response data":utf8>>)

  let input_data =
    message.new(<<"Response data":utf8>>)
    |> tcp_stage.set_segment(segment)

  // Run encode stage
  let encoder = tcp_stage.encode()
  let assert Ok(encoded) = stage.execute(encoder, input_data)

  // Verify output is a valid TCP segment (header + payload)
  let bytes = message.bytes(encoded)

  // Should be at least 20 bytes (header) + payload
  bit_array.byte_size(bytes)
  |> should.equal(20 + 13)
  // 20 byte header + "Response data" (13 bytes)
}

pub fn encode_stage_uses_updated_payload_test() {
  // Create segment with original payload
  let original_payload = <<"Original":utf8>>
  let segment = tcp_stage.new_segment(8080, 80, original_payload)

  // Create data with updated payload
  let new_payload = <<"Updated payload":utf8>>
  let input_data =
    message.new(new_payload)
    |> tcp_stage.set_segment(segment)

  // Run encode stage
  let encoder = tcp_stage.encode()
  let assert Ok(encoded) = stage.execute(encoder, input_data)

  // Verify the new payload is used (output size should reflect new payload)
  let bytes = message.bytes(encoded)

  // Header (20) + "Updated payload" (15 bytes)
  bit_array.byte_size(bytes)
  |> should.equal(20 + 15)
}

pub fn encode_stage_without_metadata_creates_default_test() {
  // Create data without segment in metadata
  let payload = <<"No header data":utf8>>
  let input_data = message.new(payload)

  // Run encode stage
  let encoder = tcp_stage.encode()
  let assert Ok(encoded) = stage.execute(encoder, input_data)

  // Should still produce valid output (default header + payload)
  let bytes = message.bytes(encoded)

  bit_array.byte_size(bytes)
  |> should.equal(20 + 14)
  // 20 byte header + "No header data" (14 bytes)
}

pub fn encode_stage_preserves_flags_test() {
  // Create segment with specific flags
  let segment =
    tcp_stage.new_segment_with_flags(
      8080,
      80,
      header.syn_ack_flags(),
      <<>>,
    )

  let input_data =
    message.new(<<>>)
    |> tcp_stage.set_segment(segment)

  // Run encode stage
  let encoder = tcp_stage.encode()
  let assert Ok(encoded) = stage.execute(encoder, input_data)

  // The output should be decodable and preserve flags
  let decoder = tcp_stage.decode()
  let assert Ok(decoded) = stage.execute(decoder, encoded)

  let assert option.Some(result_segment) = tcp_stage.get_segment(decoded)

  result_segment.header.flags.syn |> should.be_true()
  result_segment.header.flags.ack |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Roundtrip Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn roundtrip_decode_encode_test() {
  // Create original segment
  let original_payload = <<"Roundtrip test data":utf8>>
  let tcp_header =
    header.new(5000, 6000)
    |> header.set_sequence_number(12_345)
    |> header.set_acknowledgment_number(67_890)
    |> header.set_flags(header.ack_flags())
    |> header.set_window_size(32_768)

  let original_segment = builder.build_segment(tcp_header, original_payload)

  // Decode then encode
  let decoder = tcp_stage.decode()
  let encoder = tcp_stage.encode()

  let input_data = message.new(original_segment)

  let assert Ok(decoded) = stage.execute(decoder, input_data)
  let assert Ok(encoded) = stage.execute(encoder, decoded)

  // Output should match original
  message.bytes(encoded)
  |> should.equal(original_segment)
}

pub fn roundtrip_preserves_header_values_test() {
  // Create segment with all header fields set
  let tcp_header =
    header.new(443, 52_000)
    |> header.set_sequence_number(1_000_000)
    |> header.set_acknowledgment_number(2_000_000)
    |> header.set_flags(header.psh_ack_flags())
    |> header.set_window_size(65_535)
    |> header.set_checksum(12_345)

  let payload = <<"HTTPS data":utf8>>
  let original = builder.build_segment(tcp_header, payload)

  // Roundtrip
  let decoder = tcp_stage.decode()
  let encoder = tcp_stage.encode()

  let assert Ok(decoded) = stage.execute(decoder, message.new(original))
  let assert Ok(encoded) = stage.execute(encoder, decoded)

  // Verify the result
  message.bytes(encoded)
  |> should.equal(original)
}

pub fn roundtrip_empty_payload_test() {
  // Create segment with no payload (e.g., ACK-only)
  let tcp_header =
    header.new(80, 12_345)
    |> header.set_flags(header.ack_flags())

  let original = builder.build_segment(tcp_header, <<>>)

  // Roundtrip
  let decoder = tcp_stage.decode()
  let encoder = tcp_stage.encode()

  let assert Ok(decoded) = stage.execute(decoder, message.new(original))
  let assert Ok(encoded) = stage.execute(encoder, decoded)

  message.bytes(encoded)
  |> should.equal(original)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol and Registry Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn tcp_protocol_has_correct_name_test() {
  let proto = tcp_stage.tcp_protocol()

  protocol.get_name(proto)
  |> should.equal("tcp")
}

pub fn tcp_protocol_has_transport_tag_test() {
  let proto = tcp_stage.tcp_protocol()
  let tags = protocol.get_tags(proto)

  set.contains(tags, "transport")
  |> should.be_true()
}

pub fn tcp_protocol_has_layer4_tag_test() {
  let proto = tcp_stage.tcp_protocol()
  let tags = protocol.get_tags(proto)

  set.contains(tags, "layer4")
  |> should.be_true()
}

pub fn tcp_protocol_has_decoder_test() {
  let proto = tcp_stage.tcp_protocol()

  protocol.get_decoder(proto)
  |> option.is_some()
  |> should.be_true()
}

pub fn tcp_protocol_has_encoder_test() {
  let proto = tcp_stage.tcp_protocol()

  protocol.get_encoder(proto)
  |> option.is_some()
  |> should.be_true()
}

pub fn register_tcp_adds_to_registry_test() {
  let reg =
    registry.new()
    |> tcp_stage.register_tcp()

  registry.contains(reg, "tcp")
  |> should.be_true()
}

pub fn registered_tcp_can_be_retrieved_test() {
  let reg =
    registry.new()
    |> tcp_stage.register_tcp()

  let assert option.Some(proto) = registry.get(reg, "tcp")

  protocol.get_name(proto)
  |> should.equal("tcp")
}

pub fn registered_tcp_found_by_transport_tag_test() {
  let reg =
    registry.new()
    |> tcp_stage.register_tcp()

  let transport_protocols = registry.get_by_tag(reg, "transport")

  // Should find at least one (our TCP)
  { transport_protocols != [] }
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Function Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_segment_creates_valid_segment_test() {
  let segment = tcp_stage.new_segment(8080, 80, <<"Test":utf8>>)

  segment.header.source_port |> should.equal(8080)
  segment.header.destination_port |> should.equal(80)
  segment.payload |> should.equal(<<"Test":utf8>>)
}

pub fn new_segment_with_flags_creates_correct_flags_test() {
  let segment =
    tcp_stage.new_segment_with_flags(
      8080,
      80,
      header.syn_flags(),
      <<>>,
    )

  segment.header.flags.syn |> should.be_true()
  segment.header.flags.ack |> should.be_false()
}

pub fn payload_size_returns_correct_size_test() {
  let segment = tcp_stage.new_segment(80, 8080, <<"12345":utf8>>)

  tcp_stage.payload_size(segment)
  |> should.equal(5)
}

pub fn segment_size_includes_header_test() {
  let segment = tcp_stage.new_segment(80, 8080, <<"12345":utf8>>)

  // 20 byte header + 5 byte payload
  tcp_stage.segment_size(segment)
  |> should.equal(25)
}

pub fn get_segment_returns_none_when_not_present_test() {
  let data = message.new(<<>>)

  tcp_stage.get_segment(data)
  |> option.is_none()
  |> should.be_true()
}

pub fn set_segment_and_get_segment_roundtrip_test() {
  let segment = tcp_stage.new_segment(1234, 5678, <<"Data":utf8>>)

  let data =
    message.new(<<>>)
    |> tcp_stage.set_segment(segment)

  let assert option.Some(retrieved) = tcp_stage.get_segment(data)

  retrieved.header.source_port |> should.equal(1234)
  retrieved.header.destination_port |> should.equal(5678)
  retrieved.payload |> should.equal(<<"Data":utf8>>)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Metadata Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn decode_stage_has_correct_name_test() {
  let decoder = tcp_stage.decode()

  stage.get_name(decoder)
  |> should.equal("tcp:decode")
}

pub fn encode_stage_has_correct_name_test() {
  let encoder = tcp_stage.encode()

  stage.get_name(encoder)
  |> should.equal("tcp:encode")
}
