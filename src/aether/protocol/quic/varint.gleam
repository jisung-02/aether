//// QUIC variable-length integer encoding (RFC 9000 Section 16).
////
//// The two most significant bits of the first byte select the total length
//// (1, 2, 4 or 8 bytes); the remaining bits carry the value, giving a range
//// of 0 to 2^62 - 1.

import aether/protocol/quic/error.{type WireError, Malformed, NeedMoreData}

/// Largest value representable as a QUIC varint (2^62 - 1).
pub const max_value = 4_611_686_018_427_387_903

/// Decodes one varint from the front of `data`, returning the value and the
/// remaining bytes.
pub fn decode(data: BitArray) -> Result(#(Int, BitArray), WireError) {
  case data {
    <<0b00:2, value:6, rest:bits>> -> Ok(#(value, rest))
    <<0b01:2, value:14, rest:bits>> -> Ok(#(value, rest))
    <<0b10:2, value:30, rest:bits>> -> Ok(#(value, rest))
    <<0b11:2, value:62, rest:bits>> -> Ok(#(value, rest))
    _ -> Error(NeedMoreData)
  }
}

/// Encodes a value using the smallest varint form.
pub fn encode(value: Int) -> Result(BitArray, WireError) {
  case value {
    v if v < 0 -> Error(Malformed("varint value must be non-negative"))
    v if v <= 63 -> Ok(<<0b00:2, v:6>>)
    v if v <= 16_383 -> Ok(<<0b01:2, v:14>>)
    v if v <= 1_073_741_823 -> Ok(<<0b10:2, v:30>>)
    v if v <= max_value -> Ok(<<0b11:2, v:62>>)
    _ -> Error(Malformed("varint value exceeds 2^62 - 1"))
  }
}

/// Returns the number of bytes `encode` would use for `value`.
pub fn encoded_size(value: Int) -> Result(Int, WireError) {
  case value {
    v if v < 0 -> Error(Malformed("varint value must be non-negative"))
    v if v <= 63 -> Ok(1)
    v if v <= 16_383 -> Ok(2)
    v if v <= 1_073_741_823 -> Ok(4)
    v if v <= max_value -> Ok(8)
    _ -> Error(Malformed("varint value exceeds 2^62 - 1"))
  }
}
