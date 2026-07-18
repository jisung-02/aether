import aether/protocol/quic/error.{Malformed, NeedMoreData}
import aether/protocol/quic/packet
import gleam/bit_array
import gleam/list
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RFC 9001 Appendix A.2: client Initial packet header
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_long_rfc9001_client_initial_test() {
  let dcid = <<0x83, 0x94, 0xc8, 0xf0, 0x3e, 0x51, 0x57, 0x08>>
  let protected_payload = zeros(1182)

  // first byte 0xc3: form=1 fixed=1 type=Initial(00) reserved=00 pn_len=4(11)
  // version 0x00000001, dcid len 8 + dcid, scid len 0, token len varint 0,
  // length varint 1182 (0x449e), then the (still protected) pn + payload.
  let datagram =
    bit_array.concat([
      <<0xc3:8>>,
      <<0x00000001:32>>,
      <<8:8>>,
      dcid,
      <<0:8>>,
      <<0:8>>,
      <<0x44, 0x9e>>,
      protected_payload,
    ])

  case packet.parse_long(datagram) {
    Error(_) -> should.fail()
    Ok(#(parsed, remaining)) -> {
      remaining |> should.equal(<<>>)
      case parsed {
        packet.Initial(
          version,
          got_dcid,
          got_scid,
          token,
          length,
          first_byte,
          protected,
        ) -> {
          version |> should.equal(0x00000001)
          got_dcid |> should.equal(dcid)
          got_scid |> should.equal(<<>>)
          token |> should.equal(<<>>)
          length |> should.equal(1182)
          first_byte |> should.equal(0xc3)
          protected |> should.equal(protected_payload)
        }
        _ -> should.fail()
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Version Negotiation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn version_negotiation_round_trip_test() {
  let dcid = <<1, 2, 3, 4>>
  let scid = <<5, 6, 7, 8, 9>>
  let versions = [0x00000001, 0xff00001d]

  let assert Ok(bytes) = packet.build_version_negotiation(dcid, scid, versions)

  case packet.parse_long(bytes) {
    Error(_) -> should.fail()
    Ok(#(parsed, remaining)) -> {
      remaining |> should.equal(<<>>)
      parsed
      |> should.equal(packet.VersionNegotiation(dcid, scid, versions))
    }
  }
}

pub fn version_negotiation_empty_versions_test() {
  let dcid = <<1, 2, 3, 4>>
  let scid = <<>>

  let assert Ok(bytes) = packet.build_version_negotiation(dcid, scid, [])

  case packet.parse_long(bytes) {
    Error(_) -> should.fail()
    Ok(#(parsed, _remaining)) ->
      parsed |> should.equal(packet.VersionNegotiation(dcid, scid, []))
  }
}

pub fn version_negotiation_bad_version_list_length_test() {
  // 3 trailing bytes after DCID/SCID: not a multiple of 4.
  let datagram =
    bit_array.concat([
      <<0x80:8>>,
      <<0:32>>,
      <<0:8>>,
      <<0:8>>,
      <<1, 2, 3>>,
    ])

  packet.parse_long(datagram)
  |> should.equal(
    Error(Malformed("version list length must be a multiple of 4")),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Retry
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn retry_round_trip_test() {
  let dcid = <<1, 2, 3, 4, 5, 6, 7, 8>>
  let scid = <<9, 10, 11, 12>>
  let retry_token = <<"a retry token":utf8>>
  let integrity_tag = zeros(16)

  let assert Ok(bytes) =
    packet.build_retry(packet.quic_v1, dcid, scid, retry_token, integrity_tag)

  case packet.parse_long(bytes) {
    Error(_) -> should.fail()
    Ok(#(parsed, remaining)) -> {
      remaining |> should.equal(<<>>)
      parsed
      |> should.equal(packet.Retry(
        packet.quic_v1,
        dcid,
        scid,
        retry_token,
        integrity_tag,
      ))
    }
  }
}

pub fn retry_empty_token_test() {
  let dcid = <<1, 2>>
  let scid = <<>>
  let integrity_tag = zeros(16)

  let assert Ok(bytes) =
    packet.build_retry(packet.quic_v1, dcid, scid, <<>>, integrity_tag)

  case packet.parse_long(bytes) {
    Error(_) -> should.fail()
    Ok(#(parsed, _)) ->
      parsed
      |> should.equal(packet.Retry(
        packet.quic_v1,
        dcid,
        scid,
        <<>>,
        integrity_tag,
      ))
  }
}

pub fn retry_build_rejects_short_tag_test() {
  packet.build_retry(packet.quic_v1, <<1>>, <<>>, <<"token":utf8>>, <<0, 0, 0>>)
  |> should.equal(Error(Malformed("retry integrity tag must be 16 bytes")))
}

pub fn retry_parse_needs_more_data_when_shorter_than_tag_test() {
  // Only 10 bytes after DCID/SCID, but a retry needs at least 16 (the tag).
  let datagram =
    bit_array.concat([
      <<0xf0:8>>,
      <<0x00000001:32>>,
      <<0:8>>,
      <<0:8>>,
      zeros(10),
    ])

  packet.parse_long(datagram) |> should.equal(Error(NeedMoreData))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Initial / 0-RTT / Handshake round trips (build -> parse)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn initial_round_trip_test() {
  let dcid = <<1, 2, 3, 4, 5, 6, 7, 8>>
  let scid = <<9, 10, 11, 12>>
  let token = <<"token bytes":utf8>>
  let payload = <<"crypto frame payload":utf8>>

  let assert Ok(bytes) =
    packet.build_initial(packet.quic_v1, dcid, scid, token, 0xabcd, 2, payload)

  case packet.parse_long(bytes) {
    Error(_) -> should.fail()
    Ok(#(parsed, remaining)) -> {
      remaining |> should.equal(<<>>)
      case parsed {
        packet.Initial(
          version,
          got_dcid,
          got_scid,
          got_token,
          length,
          first_byte,
          protected,
        ) -> {
          version |> should.equal(packet.quic_v1)
          got_dcid |> should.equal(dcid)
          got_scid |> should.equal(scid)
          got_token |> should.equal(token)
          length |> should.equal(2 + bit_array.byte_size(payload))
          packet.packet_number_length(first_byte) |> should.equal(2)

          let assert Ok(pn_bytes) = bit_array.slice(protected, 0, 2)
          let assert Ok(rest) =
            bit_array.slice(protected, 2, bit_array.byte_size(protected) - 2)
          rest |> should.equal(payload)

          case packet.finish_header(first_byte, pn_bytes) {
            Error(_) -> should.fail()
            Ok(info) -> {
              info.pn_length |> should.equal(2)
              info.packet_number |> should.equal(0xabcd)
              info.key_phase |> should.equal(False)
            }
          }
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn zero_rtt_round_trip_test() {
  let dcid = <<1, 2, 3>>
  let scid = <<4, 5>>
  let payload = <<"early data":utf8>>

  let assert Ok(bytes) =
    packet.build_zero_rtt(packet.quic_v1, dcid, scid, 42, 1, payload)

  case packet.parse_long(bytes) {
    Error(_) -> should.fail()
    Ok(#(parsed, remaining)) -> {
      remaining |> should.equal(<<>>)
      case parsed {
        packet.ZeroRtt(
          version,
          got_dcid,
          got_scid,
          length,
          first_byte,
          protected,
        ) -> {
          version |> should.equal(packet.quic_v1)
          got_dcid |> should.equal(dcid)
          got_scid |> should.equal(scid)
          length |> should.equal(1 + bit_array.byte_size(payload))
          packet.packet_number_length(first_byte) |> should.equal(1)
          protected |> should.equal(bit_array.concat([<<42:8>>, payload]))
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn handshake_round_trip_test() {
  let dcid = <<1, 2, 3>>
  let scid = <<>>
  let payload = <<"handshake crypto data":utf8>>

  let assert Ok(bytes) =
    packet.build_handshake(packet.quic_v1, dcid, scid, 0x030201, 3, payload)

  case packet.parse_long(bytes) {
    Error(_) -> should.fail()
    Ok(#(parsed, remaining)) -> {
      remaining |> should.equal(<<>>)
      case parsed {
        packet.Handshake(
          version,
          got_dcid,
          got_scid,
          length,
          first_byte,
          protected,
        ) -> {
          version |> should.equal(packet.quic_v1)
          got_dcid |> should.equal(dcid)
          got_scid |> should.equal(scid)
          length |> should.equal(3 + bit_array.byte_size(payload))

          let assert Ok(pn_bytes) = bit_array.slice(protected, 0, 3)
          case packet.finish_header(first_byte, pn_bytes) {
            Error(_) -> should.fail()
            Ok(info) -> info.packet_number |> should.equal(0x030201)
          }
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn coalesced_initial_then_handshake_test() {
  let dcid = <<1, 2, 3, 4>>
  let scid = <<>>

  let assert Ok(initial_bytes) =
    packet.build_initial(packet.quic_v1, dcid, scid, <<>>, 1, 1, <<
      "first":utf8,
    >>)
  let assert Ok(handshake_bytes) =
    packet.build_handshake(packet.quic_v1, dcid, scid, 2, 1, <<"second":utf8>>)

  let datagram = bit_array.concat([initial_bytes, handshake_bytes])

  case packet.parse_long(datagram) {
    Error(_) -> should.fail()
    Ok(#(_first_packet, remaining)) ->
      remaining |> should.equal(handshake_bytes)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Short header (1-RTT)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn one_rtt_round_trip_test() {
  let dcid = <<1, 2, 3, 4>>
  let payload = <<"application data":utf8>>

  let assert Ok(bytes) = packet.build_one_rtt(dcid, True, True, 7, 1, payload)

  case packet.parse_short(bytes, 4) {
    Error(_) -> should.fail()
    Ok(#(parsed, remaining)) -> {
      remaining |> should.equal(<<>>)
      case parsed {
        packet.OneRtt(got_dcid, spin_bit, first_byte, protected) -> {
          got_dcid |> should.equal(dcid)
          spin_bit |> should.equal(True)
          packet.packet_number_length(first_byte) |> should.equal(1)

          let assert Ok(pn_bytes) = bit_array.slice(protected, 0, 1)
          case packet.finish_header(first_byte, pn_bytes) {
            Error(_) -> should.fail()
            Ok(info) -> {
              info.packet_number |> should.equal(7)
              info.key_phase |> should.equal(True)
            }
          }
        }
        _ -> should.fail()
      }
    }
  }
}

pub fn one_rtt_no_spin_no_key_phase_test() {
  let dcid = <<9, 9>>
  let payload = <<"x":utf8>>

  let assert Ok(bytes) = packet.build_one_rtt(dcid, False, False, 1, 1, payload)

  case packet.parse_short(bytes, 2) {
    Error(_) -> should.fail()
    Ok(#(packet.OneRtt(_, spin_bit, first_byte, _), _)) -> {
      spin_bit |> should.equal(False)
      packet.key_phase(first_byte) |> should.equal(False)
    }
    _ -> should.fail()
  }
}

pub fn one_rtt_rejects_long_header_test() {
  packet.parse_short(<<0xc0, 1, 2, 3>>, 2)
  |> should.equal(Error(Malformed("not a short header packet")))
}

pub fn one_rtt_rejects_fixed_bit_zero_test() {
  packet.parse_short(<<0x00, 1, 2, 3>>, 2)
  |> should.equal(Error(Malformed("fixed bit must be 1")))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// finish_header / packet_number_length / key_phase
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn packet_number_length_all_widths_test() {
  packet.packet_number_length(0xc0) |> should.equal(1)
  packet.packet_number_length(0xc1) |> should.equal(2)
  packet.packet_number_length(0xc2) |> should.equal(3)
  packet.packet_number_length(0xc3) |> should.equal(4)
}

pub fn key_phase_bit_test() {
  packet.key_phase(0x44) |> should.equal(True)
  packet.key_phase(0x40) |> should.equal(False)
}

pub fn finish_header_four_byte_packet_number_test() {
  case packet.finish_header(0xc3, <<0x00, 0x00, 0x00, 0x02>>) {
    Error(_) -> should.fail()
    Ok(info) -> {
      info.pn_length |> should.equal(4)
      info.packet_number |> should.equal(2)
      info.key_phase |> should.equal(False)
    }
  }
}

pub fn finish_header_needs_more_data_when_short_test() {
  packet.finish_header(0xc1, <<0x01>>) |> should.equal(Error(NeedMoreData))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Malformed / truncated input
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_long_empty_input_test() {
  packet.parse_long(<<>>) |> should.equal(Error(NeedMoreData))
}

pub fn parse_long_truncated_before_version_test() {
  packet.parse_long(<<0xc3, 0x00, 0x00>>)
  |> should.equal(Error(NeedMoreData))
}

pub fn parse_long_rejects_short_header_test() {
  packet.parse_long(<<0x40, 0x00, 0x00, 0x00, 0x01>>)
  |> should.equal(Error(Malformed("not a long header packet")))
}

pub fn parse_long_rejects_fixed_bit_zero_test() {
  // form=1, fixed=0, version != 0.
  packet.parse_long(<<0x80, 0x00, 0x00, 0x00, 0x01>>)
  |> should.equal(Error(Malformed("fixed bit must be 1")))
}

pub fn parse_long_truncated_at_dcid_length_test() {
  let datagram = bit_array.concat([<<0xc3:8>>, <<0x00000001:32>>])
  packet.parse_long(datagram) |> should.equal(Error(NeedMoreData))
}

pub fn parse_long_truncated_at_dcid_bytes_test() {
  // Declares an 8-byte DCID but only supplies 3.
  let datagram =
    bit_array.concat([<<0xc3:8>>, <<0x00000001:32>>, <<8:8>>, <<1, 2, 3>>])
  packet.parse_long(datagram) |> should.equal(Error(NeedMoreData))
}

pub fn parse_long_dcid_length_21_is_malformed_test() {
  let datagram =
    bit_array.concat([<<0xc3:8>>, <<0x00000001:32>>, <<21:8>>, zeros(21)])
  packet.parse_long(datagram)
  |> should.equal(Error(Malformed("connection id length exceeds 20 bytes")))
}

pub fn parse_long_truncated_at_scid_length_test() {
  let datagram = bit_array.concat([<<0xc3:8>>, <<0x00000001:32>>, <<0:8>>])
  packet.parse_long(datagram) |> should.equal(Error(NeedMoreData))
}

pub fn parse_long_truncated_at_scid_bytes_test() {
  let datagram =
    bit_array.concat([
      <<0xc3:8>>,
      <<0x00000001:32>>,
      <<0:8>>,
      <<4:8>>,
      <<1, 2>>,
    ])
  packet.parse_long(datagram) |> should.equal(Error(NeedMoreData))
}

pub fn parse_long_truncated_at_token_length_test() {
  let datagram =
    bit_array.concat([<<0xc3:8>>, <<0x00000001:32>>, <<0:8>>, <<0:8>>])
  packet.parse_long(datagram) |> should.equal(Error(NeedMoreData))
}

pub fn parse_long_truncated_at_token_bytes_test() {
  // Token varint claims 10 bytes, none present.
  let datagram =
    bit_array.concat([
      <<0xc3:8>>,
      <<0x00000001:32>>,
      <<0:8>>,
      <<0:8>>,
      <<0b01:2, 10:14>>,
    ])
  packet.parse_long(datagram) |> should.equal(Error(NeedMoreData))
}

pub fn parse_long_truncated_at_length_field_test() {
  // dcid_len=0, scid_len=0, token_len varint=0, then nothing for Length.
  let datagram =
    bit_array.concat([
      <<0xc3:8>>,
      <<0x00000001:32>>,
      <<0:8>>,
      <<0:8>>,
      <<0:8>>,
    ])
  packet.parse_long(datagram) |> should.equal(Error(NeedMoreData))
}

pub fn parse_long_truncated_at_protected_bytes_test() {
  // Length says 100 bytes of protected data, but none follow.
  let datagram =
    bit_array.concat([
      <<0xc3:8>>,
      <<0x00000001:32>>,
      <<0:8>>,
      <<0:8>>,
      <<0:8>>,
      <<0b01:2, 100:14>>,
    ])
  packet.parse_long(datagram) |> should.equal(Error(NeedMoreData))
}

pub fn build_initial_rejects_dcid_over_20_bytes_test() {
  packet.build_initial(packet.quic_v1, zeros(21), <<>>, <<>>, 1, 1, <<>>)
  |> should.equal(Error(Malformed("dcid exceeds 20 bytes")))
}

pub fn build_initial_rejects_scid_over_20_bytes_test() {
  packet.build_initial(packet.quic_v1, <<>>, zeros(21), <<>>, 1, 1, <<>>)
  |> should.equal(Error(Malformed("scid exceeds 20 bytes")))
}

pub fn build_one_rtt_rejects_dcid_over_20_bytes_test() {
  packet.build_one_rtt(zeros(21), False, False, 1, 1, <<>>)
  |> should.equal(Error(Malformed("dcid exceeds 20 bytes")))
}

pub fn parse_short_rejects_dcid_length_over_20_test() {
  packet.parse_short(<<0x40, 1, 2>>, 21)
  |> should.equal(Error(Malformed("dcid length exceeds 20 bytes")))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn zeros(count: Int) -> BitArray {
  list.repeat(<<0>>, count)
  |> bit_array.concat()
}
