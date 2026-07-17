import aether/protocol/quic/packet_number
import gleeunit/should

// RFC 9000 Appendix A.3 worked example.

pub fn decode_rfc_worked_example_test() {
  packet_number.decode(0x9b32, 16, 0xa82f30ea)
  |> should.equal(0xa82f9b32)
}

// RFC 9000 Appendix A.2 examples.

pub fn truncate_sixteen_bits_suffice_test() {
  packet_number.truncate(0xac5c02, 0xabe8b3)
  |> should.equal(#(0x5c02, 2))
}

pub fn truncate_needs_twenty_four_bits_test() {
  packet_number.truncate(0xace8fe, 0xabe8b3)
  |> should.equal(#(0xace8fe, 3))
}

pub fn truncate_no_prior_ack_test() {
  // No acknowledgment yet: -1 mirrors the RFC pseudocode's "None" case,
  // since full_pn - -1 == full_pn + 1.
  packet_number.truncate(0, -1)
  |> should.equal(#(0, 1))
}

pub fn truncate_same_as_largest_acked_test() {
  // Degenerate case: full_pn == largest_acked. num_unacked is clamped to
  // at least 1 so the result is still well-defined.
  packet_number.truncate(100, 100)
  |> should.equal(#(100, 1))
}

pub fn truncate_byte_length_never_exceeds_four_test() {
  let #(_, len) = packet_number.truncate(1_000_000_000, -1)
  should.be_true(len <= 4)
}

pub fn truncate_decode_round_trip_test() {
  let cases = [
    #(0, -1), #(1, 0), #(300, 0), #(70_000, 1), #(16_000_000, 1),
    #(0xac5c02, 0xabe8b3), #(0xace8fe, 0xabe8b3),
  ]

  round_trip_each(cases)
}

fn round_trip_each(cases: List(#(Int, Int))) -> Nil {
  case cases {
    [] -> Nil
    [#(full_pn, largest_acked), ..rest] -> {
      let #(truncated, byte_len) =
        packet_number.truncate(full_pn, largest_acked)
      let largest_pn = case largest_acked < 0 {
        True -> -1
        False -> largest_acked
      }
      packet_number.decode(truncated, byte_len * 8, largest_pn)
      |> should.equal(full_pn)
      round_trip_each(rest)
    }
  }
}

pub fn truncate_boundary_at_byte_widths_test() {
  // Values that sit right at 1/2/3/4-byte boundaries above largest_acked.
  packet_number.truncate(127, 0) |> should.equal(#(127, 1))
  packet_number.truncate(128, 0) |> should.equal(#(128, 2))
  packet_number.truncate(32_767, 0) |> should.equal(#(32_767, 2))
  packet_number.truncate(32_768, 0) |> should.equal(#(32_768, 3))
}

pub fn decode_wraps_forward_when_candidate_too_low_test() {
  // largest_pn = 0x1fe, expected_pn = 0x1ff; masking in a small truncated
  // value yields a candidate far below expected_pn, so decode must add a
  // full window to land on the actual next packet number, 0x200.
  packet_number.decode(0x00, 8, 0x1fe)
  |> should.equal(0x200)
}

pub fn decode_wraps_backward_when_candidate_too_high_test() {
  // largest_pn = 0x300, expected_pn = 0x301; masking in a large truncated
  // value yields a candidate above the window, so decode must subtract a
  // full window to land on 0x2fe.
  packet_number.decode(0xfe, 8, 0x300)
  |> should.equal(0x2fe)
}
