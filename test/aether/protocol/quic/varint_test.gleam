import aether/protocol/quic/error.{Malformed, NeedMoreData}
import aether/protocol/quic/varint
import gleeunit/should

// RFC 9000 Appendix A.1 vectors

pub fn decode_one_byte_rfc_vector_test() {
  varint.decode(<<0x25>>)
  |> should.equal(Ok(#(37, <<>>)))
}

pub fn decode_two_byte_rfc_vector_test() {
  varint.decode(<<0x7b, 0xbd>>)
  |> should.equal(Ok(#(15_293, <<>>)))
}

pub fn decode_four_byte_rfc_vector_test() {
  varint.decode(<<0x9d, 0x7f, 0x3e, 0x7d>>)
  |> should.equal(Ok(#(494_878_333, <<>>)))
}

pub fn decode_eight_byte_rfc_vector_test() {
  varint.decode(<<0xc2, 0x19, 0x7c, 0x5e, 0xff, 0x14, 0xe8, 0x8c>>)
  |> should.equal(Ok(#(151_288_809_941_952_652, <<>>)))
}

pub fn decode_non_minimal_encoding_test() {
  // RFC 9000 A.1: 37 may also arrive as the two-byte 0x4025.
  varint.decode(<<0x40, 0x25>>)
  |> should.equal(Ok(#(37, <<>>)))
}

pub fn decode_leaves_remaining_bytes_test() {
  varint.decode(<<0x25, 0xff, 0xff>>)
  |> should.equal(Ok(#(37, <<0xff, 0xff>>)))
}

pub fn decode_empty_input_test() {
  varint.decode(<<>>)
  |> should.equal(Error(NeedMoreData))
}

pub fn decode_truncated_input_test() {
  // First byte declares 4 bytes but only 2 are present.
  varint.decode(<<0x9d, 0x7f>>)
  |> should.equal(Error(NeedMoreData))
}

pub fn encode_uses_smallest_form_test() {
  varint.encode(37) |> should.equal(Ok(<<0x25>>))
  varint.encode(15_293) |> should.equal(Ok(<<0x7b, 0xbd>>))
  varint.encode(494_878_333) |> should.equal(Ok(<<0x9d, 0x7f, 0x3e, 0x7d>>))
  varint.encode(151_288_809_941_952_652)
  |> should.equal(Ok(<<0xc2, 0x19, 0x7c, 0x5e, 0xff, 0x14, 0xe8, 0x8c>>))
}

pub fn encode_boundaries_round_trip_test() {
  let boundaries = [
    0, 63, 64, 16_383, 16_384, 1_073_741_823, 1_073_741_824, varint.max_value,
  ]
  boundaries
  |> list_each(fn(value) {
    let assert Ok(encoded) = varint.encode(value)
    varint.decode(encoded) |> should.equal(Ok(#(value, <<>>)))
  })
}

pub fn encode_rejects_out_of_range_test() {
  varint.encode(-1)
  |> should.equal(Error(Malformed("varint value must be non-negative")))
  varint.encode(varint.max_value + 1)
  |> should.equal(Error(Malformed("varint value exceeds 2^62 - 1")))
}

pub fn encoded_size_test() {
  varint.encoded_size(63) |> should.equal(Ok(1))
  varint.encoded_size(64) |> should.equal(Ok(2))
  varint.encoded_size(16_384) |> should.equal(Ok(4))
  varint.encoded_size(1_073_741_824) |> should.equal(Ok(8))
}

fn list_each(items: List(a), run: fn(a) -> b) -> Nil {
  case items {
    [] -> Nil
    [first, ..rest] -> {
      run(first)
      list_each(rest, run)
    }
  }
}
