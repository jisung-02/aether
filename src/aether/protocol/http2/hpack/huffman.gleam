// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HPACK Huffman Encoding/Decoding
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Implements Huffman coding for HPACK as per RFC 7541 Appendix B.
// Uses a static Huffman code table with variable-length codes (5-30 bits).
//
// Strategy: Lookup table approach for simplicity
// - Encoding: Direct table lookup for each byte
// - Decoding: Bit-by-bit state machine decoding
//

import gleam/bit_array
import gleam/int

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Huffman code entry (code value and bit length)
///
type HuffmanCode {
  HuffmanCode(code: Int, bits: Int)
}

/// Result of attempting to extract one symbol from the bit buffer
///
type DecodeStep {
  /// A complete symbol was matched, consuming `bits` bits
  Matched(byte: Int, bits: Int)

  /// The 30-bit EOS code was matched inside the data (this is an error)
  FoundEos

  /// No symbol matches yet - more bits are needed (or end of data)
  NeedMoreBits

  /// The buffered bits do not correspond to any valid Huffman code
  NoMatch
}

/// Errors that can occur during Huffman encoding/decoding
///
pub type HuffmanError {
  /// Invalid Huffman-encoded data
  InvalidHuffmanData(message: String)

  /// EOS symbol encountered in data
  EosInData

  /// Padding bits are invalid
  InvalidPadding(message: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// EOS (End of String) symbol code
const eos_code = 0x3FFFFFFF

/// EOS symbol bit length
const eos_bits = 30

/// Minimum Huffman code length in the RFC 7541 Appendix B table
const min_code_bits = 5

/// Maximum Huffman code length in the RFC 7541 Appendix B table
const max_code_bits = 30

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Huffman Code Table (RFC 7541 Appendix B)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the Huffman code for a given byte value (0-255)
///
/// Complete table transcribed from RFC 7541 Appendix B.
///
fn get_huffman_code(byte: Int) -> HuffmanCode {
  case byte {
    0 -> HuffmanCode(0x1FF8, 13)
    1 -> HuffmanCode(0x7FFFD8, 23)
    2 -> HuffmanCode(0xFFFFFE2, 28)
    3 -> HuffmanCode(0xFFFFFE3, 28)
    4 -> HuffmanCode(0xFFFFFE4, 28)
    5 -> HuffmanCode(0xFFFFFE5, 28)
    6 -> HuffmanCode(0xFFFFFE6, 28)
    7 -> HuffmanCode(0xFFFFFE7, 28)
    8 -> HuffmanCode(0xFFFFFE8, 28)
    9 -> HuffmanCode(0xFFFFEA, 24)
    10 -> HuffmanCode(0x3FFFFFFC, 30)
    11 -> HuffmanCode(0xFFFFFE9, 28)
    12 -> HuffmanCode(0xFFFFFEA, 28)
    13 -> HuffmanCode(0x3FFFFFFD, 30)
    14 -> HuffmanCode(0xFFFFFEB, 28)
    15 -> HuffmanCode(0xFFFFFEC, 28)
    16 -> HuffmanCode(0xFFFFFED, 28)
    17 -> HuffmanCode(0xFFFFFEE, 28)
    18 -> HuffmanCode(0xFFFFFEF, 28)
    19 -> HuffmanCode(0xFFFFFF0, 28)
    20 -> HuffmanCode(0xFFFFFF1, 28)
    21 -> HuffmanCode(0xFFFFFF2, 28)
    22 -> HuffmanCode(0x3FFFFFFE, 30)
    23 -> HuffmanCode(0xFFFFFF3, 28)
    24 -> HuffmanCode(0xFFFFFF4, 28)
    25 -> HuffmanCode(0xFFFFFF5, 28)
    26 -> HuffmanCode(0xFFFFFF6, 28)
    27 -> HuffmanCode(0xFFFFFF7, 28)
    28 -> HuffmanCode(0xFFFFFF8, 28)
    29 -> HuffmanCode(0xFFFFFF9, 28)
    30 -> HuffmanCode(0xFFFFFFA, 28)
    31 -> HuffmanCode(0xFFFFFFB, 28)
    32 -> HuffmanCode(0x14, 6)
    // ' '
    33 -> HuffmanCode(0x3F8, 10)
    // '!'
    34 -> HuffmanCode(0x3F9, 10)
    // '"'
    35 -> HuffmanCode(0xFFA, 12)
    // '#'
    36 -> HuffmanCode(0x1FF9, 13)
    // '$'
    37 -> HuffmanCode(0x15, 6)
    // '%'
    38 -> HuffmanCode(0xF8, 8)
    // '&'
    39 -> HuffmanCode(0x7FA, 11)
    // '''
    40 -> HuffmanCode(0x3FA, 10)
    // '('
    41 -> HuffmanCode(0x3FB, 10)
    // ')'
    42 -> HuffmanCode(0xF9, 8)
    // '*'
    43 -> HuffmanCode(0x7FB, 11)
    // '+'
    44 -> HuffmanCode(0xFA, 8)
    // ','
    45 -> HuffmanCode(0x16, 6)
    // '-'
    46 -> HuffmanCode(0x17, 6)
    // '.'
    47 -> HuffmanCode(0x18, 6)
    // '/'
    48 -> HuffmanCode(0x0, 5)
    // '0'
    49 -> HuffmanCode(0x1, 5)
    // '1'
    50 -> HuffmanCode(0x2, 5)
    // '2'
    51 -> HuffmanCode(0x19, 6)
    // '3'
    52 -> HuffmanCode(0x1A, 6)
    // '4'
    53 -> HuffmanCode(0x1B, 6)
    // '5'
    54 -> HuffmanCode(0x1C, 6)
    // '6'
    55 -> HuffmanCode(0x1D, 6)
    // '7'
    56 -> HuffmanCode(0x1E, 6)
    // '8'
    57 -> HuffmanCode(0x1F, 6)
    // '9'
    58 -> HuffmanCode(0x5C, 7)
    // ':'
    59 -> HuffmanCode(0xFB, 8)
    // ';'
    60 -> HuffmanCode(0x7FFC, 15)
    // '<'
    61 -> HuffmanCode(0x20, 6)
    // '='
    62 -> HuffmanCode(0xFFB, 12)
    // '>'
    63 -> HuffmanCode(0x3FC, 10)
    // '?'
    64 -> HuffmanCode(0x1FFA, 13)
    // '@'
    65 -> HuffmanCode(0x21, 6)
    // 'A'
    66 -> HuffmanCode(0x5D, 7)
    // 'B'
    67 -> HuffmanCode(0x5E, 7)
    // 'C'
    68 -> HuffmanCode(0x5F, 7)
    // 'D'
    69 -> HuffmanCode(0x60, 7)
    // 'E'
    70 -> HuffmanCode(0x61, 7)
    // 'F'
    71 -> HuffmanCode(0x62, 7)
    // 'G'
    72 -> HuffmanCode(0x63, 7)
    // 'H'
    73 -> HuffmanCode(0x64, 7)
    // 'I'
    74 -> HuffmanCode(0x65, 7)
    // 'J'
    75 -> HuffmanCode(0x66, 7)
    // 'K'
    76 -> HuffmanCode(0x67, 7)
    // 'L'
    77 -> HuffmanCode(0x68, 7)
    // 'M'
    78 -> HuffmanCode(0x69, 7)
    // 'N'
    79 -> HuffmanCode(0x6A, 7)
    // 'O'
    80 -> HuffmanCode(0x6B, 7)
    // 'P'
    81 -> HuffmanCode(0x6C, 7)
    // 'Q'
    82 -> HuffmanCode(0x6D, 7)
    // 'R'
    83 -> HuffmanCode(0x6E, 7)
    // 'S'
    84 -> HuffmanCode(0x6F, 7)
    // 'T'
    85 -> HuffmanCode(0x70, 7)
    // 'U'
    86 -> HuffmanCode(0x71, 7)
    // 'V'
    87 -> HuffmanCode(0x72, 7)
    // 'W'
    88 -> HuffmanCode(0xFC, 8)
    // 'X'
    89 -> HuffmanCode(0x73, 7)
    // 'Y'
    90 -> HuffmanCode(0xFD, 8)
    // 'Z'
    91 -> HuffmanCode(0x1FFB, 13)
    // '['
    92 -> HuffmanCode(0x7FFF0, 19)
    // '\'
    93 -> HuffmanCode(0x1FFC, 13)
    // ']'
    94 -> HuffmanCode(0x3FFC, 14)
    // '^'
    95 -> HuffmanCode(0x22, 6)
    // '_'
    96 -> HuffmanCode(0x7FFD, 15)
    // '`'
    97 -> HuffmanCode(0x3, 5)
    // 'a'
    98 -> HuffmanCode(0x23, 6)
    // 'b'
    99 -> HuffmanCode(0x4, 5)
    // 'c'
    100 -> HuffmanCode(0x24, 6)
    // 'd'
    101 -> HuffmanCode(0x5, 5)
    // 'e'
    102 -> HuffmanCode(0x25, 6)
    // 'f'
    103 -> HuffmanCode(0x26, 6)
    // 'g'
    104 -> HuffmanCode(0x27, 6)
    // 'h'
    105 -> HuffmanCode(0x6, 5)
    // 'i'
    106 -> HuffmanCode(0x74, 7)
    // 'j'
    107 -> HuffmanCode(0x75, 7)
    // 'k'
    108 -> HuffmanCode(0x28, 6)
    // 'l'
    109 -> HuffmanCode(0x29, 6)
    // 'm'
    110 -> HuffmanCode(0x2A, 6)
    // 'n'
    111 -> HuffmanCode(0x7, 5)
    // 'o'
    112 -> HuffmanCode(0x2B, 6)
    // 'p'
    113 -> HuffmanCode(0x76, 7)
    // 'q'
    114 -> HuffmanCode(0x2C, 6)
    // 'r'
    115 -> HuffmanCode(0x8, 5)
    // 's'
    116 -> HuffmanCode(0x9, 5)
    // 't'
    117 -> HuffmanCode(0x2D, 6)
    // 'u'
    118 -> HuffmanCode(0x77, 7)
    // 'v'
    119 -> HuffmanCode(0x78, 7)
    // 'w'
    120 -> HuffmanCode(0x79, 7)
    // 'x'
    121 -> HuffmanCode(0x7A, 7)
    // 'y'
    122 -> HuffmanCode(0x7B, 7)
    // 'z'
    123 -> HuffmanCode(0x7FFE, 15)
    // '{'
    124 -> HuffmanCode(0x7FC, 11)
    // '|'
    125 -> HuffmanCode(0x3FFD, 14)
    // '}'
    126 -> HuffmanCode(0x1FFD, 13)
    // '~'
    127 -> HuffmanCode(0xFFFFFFC, 28)
    128 -> HuffmanCode(0xFFFE6, 20)
    129 -> HuffmanCode(0x3FFFD2, 22)
    130 -> HuffmanCode(0xFFFE7, 20)
    131 -> HuffmanCode(0xFFFE8, 20)
    132 -> HuffmanCode(0x3FFFD3, 22)
    133 -> HuffmanCode(0x3FFFD4, 22)
    134 -> HuffmanCode(0x3FFFD5, 22)
    135 -> HuffmanCode(0x7FFFD9, 23)
    136 -> HuffmanCode(0x3FFFD6, 22)
    137 -> HuffmanCode(0x7FFFDA, 23)
    138 -> HuffmanCode(0x7FFFDB, 23)
    139 -> HuffmanCode(0x7FFFDC, 23)
    140 -> HuffmanCode(0x7FFFDD, 23)
    141 -> HuffmanCode(0x7FFFDE, 23)
    142 -> HuffmanCode(0xFFFFEB, 24)
    143 -> HuffmanCode(0x7FFFDF, 23)
    144 -> HuffmanCode(0xFFFFEC, 24)
    145 -> HuffmanCode(0xFFFFED, 24)
    146 -> HuffmanCode(0x3FFFD7, 22)
    147 -> HuffmanCode(0x7FFFE0, 23)
    148 -> HuffmanCode(0xFFFFEE, 24)
    149 -> HuffmanCode(0x7FFFE1, 23)
    150 -> HuffmanCode(0x7FFFE2, 23)
    151 -> HuffmanCode(0x7FFFE3, 23)
    152 -> HuffmanCode(0x7FFFE4, 23)
    153 -> HuffmanCode(0x1FFFDC, 21)
    154 -> HuffmanCode(0x3FFFD8, 22)
    155 -> HuffmanCode(0x7FFFE5, 23)
    156 -> HuffmanCode(0x3FFFD9, 22)
    157 -> HuffmanCode(0x7FFFE6, 23)
    158 -> HuffmanCode(0x7FFFE7, 23)
    159 -> HuffmanCode(0xFFFFEF, 24)
    160 -> HuffmanCode(0x3FFFDA, 22)
    161 -> HuffmanCode(0x1FFFDD, 21)
    162 -> HuffmanCode(0xFFFE9, 20)
    163 -> HuffmanCode(0x3FFFDB, 22)
    164 -> HuffmanCode(0x3FFFDC, 22)
    165 -> HuffmanCode(0x7FFFE8, 23)
    166 -> HuffmanCode(0x7FFFE9, 23)
    167 -> HuffmanCode(0x1FFFDE, 21)
    168 -> HuffmanCode(0x7FFFEA, 23)
    169 -> HuffmanCode(0x3FFFDD, 22)
    170 -> HuffmanCode(0x3FFFDE, 22)
    171 -> HuffmanCode(0xFFFFF0, 24)
    172 -> HuffmanCode(0x1FFFDF, 21)
    173 -> HuffmanCode(0x3FFFDF, 22)
    174 -> HuffmanCode(0x7FFFEB, 23)
    175 -> HuffmanCode(0x7FFFEC, 23)
    176 -> HuffmanCode(0x1FFFE0, 21)
    177 -> HuffmanCode(0x1FFFE1, 21)
    178 -> HuffmanCode(0x3FFFE0, 22)
    179 -> HuffmanCode(0x1FFFE2, 21)
    180 -> HuffmanCode(0x7FFFED, 23)
    181 -> HuffmanCode(0x3FFFE1, 22)
    182 -> HuffmanCode(0x7FFFEE, 23)
    183 -> HuffmanCode(0x7FFFEF, 23)
    184 -> HuffmanCode(0xFFFEA, 20)
    185 -> HuffmanCode(0x3FFFE2, 22)
    186 -> HuffmanCode(0x3FFFE3, 22)
    187 -> HuffmanCode(0x3FFFE4, 22)
    188 -> HuffmanCode(0x7FFFF0, 23)
    189 -> HuffmanCode(0x3FFFE5, 22)
    190 -> HuffmanCode(0x3FFFE6, 22)
    191 -> HuffmanCode(0x7FFFF1, 23)
    192 -> HuffmanCode(0x3FFFFE0, 26)
    193 -> HuffmanCode(0x3FFFFE1, 26)
    194 -> HuffmanCode(0xFFFEB, 20)
    195 -> HuffmanCode(0x7FFF1, 19)
    196 -> HuffmanCode(0x3FFFE7, 22)
    197 -> HuffmanCode(0x7FFFF2, 23)
    198 -> HuffmanCode(0x3FFFE8, 22)
    199 -> HuffmanCode(0x1FFFFEC, 25)
    200 -> HuffmanCode(0x3FFFFE2, 26)
    201 -> HuffmanCode(0x3FFFFE3, 26)
    202 -> HuffmanCode(0x3FFFFE4, 26)
    203 -> HuffmanCode(0x7FFFFDE, 27)
    204 -> HuffmanCode(0x7FFFFDF, 27)
    205 -> HuffmanCode(0x3FFFFE5, 26)
    206 -> HuffmanCode(0xFFFFF1, 24)
    207 -> HuffmanCode(0x1FFFFED, 25)
    208 -> HuffmanCode(0x7FFF2, 19)
    209 -> HuffmanCode(0x1FFFE3, 21)
    210 -> HuffmanCode(0x3FFFFE6, 26)
    211 -> HuffmanCode(0x7FFFFE0, 27)
    212 -> HuffmanCode(0x7FFFFE1, 27)
    213 -> HuffmanCode(0x3FFFFE7, 26)
    214 -> HuffmanCode(0x7FFFFE2, 27)
    215 -> HuffmanCode(0xFFFFF2, 24)
    216 -> HuffmanCode(0x1FFFE4, 21)
    217 -> HuffmanCode(0x1FFFE5, 21)
    218 -> HuffmanCode(0x3FFFFE8, 26)
    219 -> HuffmanCode(0x3FFFFE9, 26)
    220 -> HuffmanCode(0xFFFFFFD, 28)
    221 -> HuffmanCode(0x7FFFFE3, 27)
    222 -> HuffmanCode(0x7FFFFE4, 27)
    223 -> HuffmanCode(0x7FFFFE5, 27)
    224 -> HuffmanCode(0xFFFEC, 20)
    225 -> HuffmanCode(0xFFFFF3, 24)
    226 -> HuffmanCode(0xFFFED, 20)
    227 -> HuffmanCode(0x1FFFE6, 21)
    228 -> HuffmanCode(0x3FFFE9, 22)
    229 -> HuffmanCode(0x1FFFE7, 21)
    230 -> HuffmanCode(0x1FFFE8, 21)
    231 -> HuffmanCode(0x7FFFF3, 23)
    232 -> HuffmanCode(0x3FFFEA, 22)
    233 -> HuffmanCode(0x3FFFEB, 22)
    234 -> HuffmanCode(0x1FFFFEE, 25)
    235 -> HuffmanCode(0x1FFFFEF, 25)
    236 -> HuffmanCode(0xFFFFF4, 24)
    237 -> HuffmanCode(0xFFFFF5, 24)
    238 -> HuffmanCode(0x3FFFFEA, 26)
    239 -> HuffmanCode(0x7FFFF4, 23)
    240 -> HuffmanCode(0x3FFFFEB, 26)
    241 -> HuffmanCode(0x7FFFFE6, 27)
    242 -> HuffmanCode(0x3FFFFEC, 26)
    243 -> HuffmanCode(0x3FFFFED, 26)
    244 -> HuffmanCode(0x7FFFFE7, 27)
    245 -> HuffmanCode(0x7FFFFE8, 27)
    246 -> HuffmanCode(0x7FFFFE9, 27)
    247 -> HuffmanCode(0x7FFFFEA, 27)
    248 -> HuffmanCode(0x7FFFFEB, 27)
    249 -> HuffmanCode(0xFFFFFFE, 28)
    250 -> HuffmanCode(0x7FFFFEC, 27)
    251 -> HuffmanCode(0x7FFFFED, 27)
    252 -> HuffmanCode(0x7FFFFEE, 27)
    253 -> HuffmanCode(0x7FFFFEF, 27)
    254 -> HuffmanCode(0x7FFFFF0, 27)
    255 -> HuffmanCode(0x3FFFFEE, 26)
    // Bytes are always in range 0-255; this branch is unreachable.
    _ -> panic as "get_huffman_code: byte value out of range (0-255)"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Encodes a string using Huffman coding
///
/// Returns the Huffman-encoded BitArray.
///
pub fn encode_huffman(input: String) -> BitArray {
  encode_huffman_bytes(bit_array.from_string(input))
}

/// Encodes raw octets using Huffman coding
///
/// Unlike `encode_huffman`, this operates directly on a BitArray of
/// arbitrary octets, so it is not limited to valid UTF-8 input. This is
/// useful for exercising the full byte range (0-255) of the code table.
///
pub fn encode_huffman_bytes(bytes: BitArray) -> BitArray {
  encode_bytes(bytes, <<>>, 0, 0)
}

/// Recursively encodes bytes into Huffman codes
///
fn encode_bytes(
  input: BitArray,
  output: BitArray,
  pending_bits: Int,
  pending_value: Int,
) -> BitArray {
  case input {
    <<byte:8, rest:bits>> -> {
      let huff = get_huffman_code(byte)

      // Append this code to pending bits
      let new_pending_bits = pending_bits + huff.bits
      let new_pending_value =
        int.bitwise_or(
          int.bitwise_shift_left(pending_value, huff.bits),
          huff.code,
        )

      // Flush complete bytes to output
      flush_pending_bytes(rest, output, new_pending_bits, new_pending_value)
    }
    _ -> {
      // End of input - pad with EOS bits if needed
      case pending_bits {
        0 -> output
        _ -> {
          // Calculate padding needed to byte boundary
          let remaining_bits = 8 - pending_bits % 8
          let padding =
            int.bitwise_shift_right(eos_code, eos_bits - remaining_bits)

          let final_value =
            int.bitwise_or(
              int.bitwise_shift_left(pending_value, remaining_bits),
              padding,
            )
          let final_bits = pending_bits + remaining_bits

          // Flush final bytes
          flush_final_bytes(output, final_bits, final_value)
        }
      }
    }
  }
}

/// Flushes complete bytes from pending bits to output
///
fn flush_pending_bytes(
  input: BitArray,
  output: BitArray,
  pending_bits: Int,
  pending_value: Int,
) -> BitArray {
  case pending_bits >= 8 {
    True -> {
      // Extract top byte
      let byte =
        int.bitwise_shift_right(pending_value, pending_bits - 8)
        |> int.bitwise_and(0xFF)

      let new_output = bit_array.concat([output, <<byte:8>>])
      let new_pending_bits = pending_bits - 8
      let new_pending_value =
        int.bitwise_and(
          pending_value,
          int.bitwise_shift_left(1, new_pending_bits) - 1,
        )

      flush_pending_bytes(
        input,
        new_output,
        new_pending_bits,
        new_pending_value,
      )
    }
    False -> encode_bytes(input, output, pending_bits, pending_value)
  }
}

/// Flushes final bytes from pending bits
///
fn flush_final_bytes(output: BitArray, bits: Int, value: Int) -> BitArray {
  case bits >= 8 {
    True -> {
      let byte =
        int.bitwise_shift_right(value, bits - 8)
        |> int.bitwise_and(0xFF)
      let new_output = bit_array.concat([output, <<byte:8>>])
      let new_bits = bits - 8
      let new_value =
        int.bitwise_and(value, int.bitwise_shift_left(1, new_bits) - 1)
      flush_final_bytes(new_output, new_bits, new_value)
    }
    False -> output
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Decodes Huffman-encoded data
///
/// Decodes against the complete RFC 7541 Appendix B table, validating
/// padding (RFC 7541 Section 5.2) and rejecting an EOS symbol appearing
/// within the data (RFC 7541 Section 5.2).
///
pub fn decode_huffman(
  data: BitArray,
  _length: Int,
) -> Result(String, HuffmanError) {
  case decode_huffman_bytes(data) {
    Ok(decoded_bytes) -> {
      case bit_array.to_string(decoded_bytes) {
        Ok(str) -> Ok(str)
        Error(_) ->
          Error(InvalidHuffmanData("Decoded data is not valid UTF-8"))
      }
    }
    Error(err) -> Error(err)
  }
}

/// Decodes Huffman-encoded data into raw octets
///
/// Unlike `decode_huffman`, this returns the decoded bytes directly
/// instead of requiring them to form valid UTF-8. This is useful for
/// exercising the full byte range (0-255) of the code table.
///
pub fn decode_huffman_bytes(data: BitArray) -> Result(BitArray, HuffmanError) {
  decode_symbols(data, [], 0, 0)
}

/// Recursively decodes Huffman symbols from the input, accumulating
/// matched bytes. Pulls a new byte into the bit buffer whenever the
/// buffered bits don't yet form a complete code.
///
fn decode_symbols(
  data: BitArray,
  acc: List(Int),
  buffer: Int,
  buffer_bits: Int,
) -> Result(BitArray, HuffmanError) {
  case try_extract_symbol(buffer, buffer_bits) {
    Matched(byte, consumed) -> {
      let new_buffer_bits = buffer_bits - consumed
      let mask = int.bitwise_shift_left(1, new_buffer_bits) - 1
      let new_buffer = int.bitwise_and(buffer, mask)
      decode_symbols(data, [byte, ..acc], new_buffer, new_buffer_bits)
    }
    FoundEos -> Error(EosInData)
    NoMatch ->
      Error(InvalidHuffmanData(
        "No matching Huffman code for the buffered bits",
      ))
    NeedMoreBits ->
      case data {
        <<byte:8, rest:bits>> -> {
          let new_buffer =
            int.bitwise_or(int.bitwise_shift_left(buffer, 8), byte)
          let new_buffer_bits = buffer_bits + 8
          decode_symbols(rest, acc, new_buffer, new_buffer_bits)
        }
        _ ->
          case validate_padding(buffer, buffer_bits) {
            Ok(Nil) -> Ok(list_to_bit_array(list_reverse(acc)))
            Error(err) -> Error(err)
          }
      }
  }
}

/// Attempts to extract a single symbol from the buffered bits, trying
/// every valid Huffman code length in increasing order (5..30). Codes
/// are prefix-free, so the first exact match at the smallest length is
/// always the correct decode.
///
fn try_extract_symbol(buffer: Int, buffer_bits: Int) -> DecodeStep {
  try_at_length(buffer, buffer_bits, min_code_bits)
}

fn try_at_length(buffer: Int, buffer_bits: Int, length: Int) -> DecodeStep {
  case buffer_bits >= length {
    False -> NeedMoreBits
    True -> {
      let code = int.bitwise_shift_right(buffer, buffer_bits - length)

      case length == max_code_bits && code == eos_code {
        True -> FoundEos
        False ->
          case lookup_huffman_symbol(length, code) {
            Ok(byte) -> Matched(byte, length)
            Error(Nil) ->
              case length >= max_code_bits {
                True -> NoMatch
                False -> try_at_length(buffer, buffer_bits, length + 1)
              }
          }
      }
    }
  }
}

/// Validates trailing padding bits (RFC 7541 Section 5.2)
///
/// Leftover bits must be fewer than 8 and must all be 1s (a prefix of
/// the EOS code).
///
fn validate_padding(buffer: Int, buffer_bits: Int) -> Result(Nil, HuffmanError) {
  case buffer_bits == 0 {
    True -> Ok(Nil)
    False -> {
      case buffer_bits < 8 {
        True -> {
          let all_ones = int.bitwise_shift_left(1, buffer_bits) - 1
          case buffer == all_ones {
            True -> Ok(Nil)
            False ->
              Error(InvalidPadding(
                "Padding bits must be all 1s (a prefix of the EOS code)",
              ))
          }
        }
        False ->
          Error(InvalidPadding(
            "Leftover bits at end of input must be fewer than 8",
          ))
      }
    }
  }
}

/// Looks up the symbol for a Huffman code of the given bit length
///
fn lookup_huffman_symbol(bits: Int, code: Int) -> Result(Int, Nil) {
  case bits {
    5 -> lookup_5bit(code)
    6 -> lookup_6bit(code)
    7 -> lookup_7bit(code)
    8 -> lookup_8bit(code)
    10 -> lookup_10bit(code)
    11 -> lookup_11bit(code)
    12 -> lookup_12bit(code)
    13 -> lookup_13bit(code)
    14 -> lookup_14bit(code)
    15 -> lookup_15bit(code)
    19 -> lookup_19bit(code)
    20 -> lookup_20bit(code)
    21 -> lookup_21bit(code)
    22 -> lookup_22bit(code)
    23 -> lookup_23bit(code)
    24 -> lookup_24bit(code)
    25 -> lookup_25bit(code)
    26 -> lookup_26bit(code)
    27 -> lookup_27bit(code)
    28 -> lookup_28bit(code)
    30 -> lookup_30bit(code)
    _ -> Error(Nil)
  }
}

fn lookup_5bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x0 -> Ok(48)
    0x1 -> Ok(49)
    0x2 -> Ok(50)
    0x3 -> Ok(97)
    0x4 -> Ok(99)
    0x5 -> Ok(101)
    0x6 -> Ok(105)
    0x7 -> Ok(111)
    0x8 -> Ok(115)
    0x9 -> Ok(116)
    _ -> Error(Nil)
  }
}

fn lookup_6bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x14 -> Ok(32)
    0x15 -> Ok(37)
    0x16 -> Ok(45)
    0x17 -> Ok(46)
    0x18 -> Ok(47)
    0x19 -> Ok(51)
    0x1A -> Ok(52)
    0x1B -> Ok(53)
    0x1C -> Ok(54)
    0x1D -> Ok(55)
    0x1E -> Ok(56)
    0x1F -> Ok(57)
    0x20 -> Ok(61)
    0x21 -> Ok(65)
    0x22 -> Ok(95)
    0x23 -> Ok(98)
    0x24 -> Ok(100)
    0x25 -> Ok(102)
    0x26 -> Ok(103)
    0x27 -> Ok(104)
    0x28 -> Ok(108)
    0x29 -> Ok(109)
    0x2A -> Ok(110)
    0x2B -> Ok(112)
    0x2C -> Ok(114)
    0x2D -> Ok(117)
    _ -> Error(Nil)
  }
}

fn lookup_7bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x5C -> Ok(58)
    0x5D -> Ok(66)
    0x5E -> Ok(67)
    0x5F -> Ok(68)
    0x60 -> Ok(69)
    0x61 -> Ok(70)
    0x62 -> Ok(71)
    0x63 -> Ok(72)
    0x64 -> Ok(73)
    0x65 -> Ok(74)
    0x66 -> Ok(75)
    0x67 -> Ok(76)
    0x68 -> Ok(77)
    0x69 -> Ok(78)
    0x6A -> Ok(79)
    0x6B -> Ok(80)
    0x6C -> Ok(81)
    0x6D -> Ok(82)
    0x6E -> Ok(83)
    0x6F -> Ok(84)
    0x70 -> Ok(85)
    0x71 -> Ok(86)
    0x72 -> Ok(87)
    0x73 -> Ok(89)
    0x74 -> Ok(106)
    0x75 -> Ok(107)
    0x76 -> Ok(113)
    0x77 -> Ok(118)
    0x78 -> Ok(119)
    0x79 -> Ok(120)
    0x7A -> Ok(121)
    0x7B -> Ok(122)
    _ -> Error(Nil)
  }
}

fn lookup_8bit(code: Int) -> Result(Int, Nil) {
  case code {
    0xF8 -> Ok(38)
    0xF9 -> Ok(42)
    0xFA -> Ok(44)
    0xFB -> Ok(59)
    0xFC -> Ok(88)
    0xFD -> Ok(90)
    _ -> Error(Nil)
  }
}

fn lookup_10bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x3F8 -> Ok(33)
    0x3F9 -> Ok(34)
    0x3FA -> Ok(40)
    0x3FB -> Ok(41)
    0x3FC -> Ok(63)
    _ -> Error(Nil)
  }
}

fn lookup_11bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x7FA -> Ok(39)
    0x7FB -> Ok(43)
    0x7FC -> Ok(124)
    _ -> Error(Nil)
  }
}

fn lookup_12bit(code: Int) -> Result(Int, Nil) {
  case code {
    0xFFA -> Ok(35)
    0xFFB -> Ok(62)
    _ -> Error(Nil)
  }
}

fn lookup_13bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x1FF8 -> Ok(0)
    0x1FF9 -> Ok(36)
    0x1FFA -> Ok(64)
    0x1FFB -> Ok(91)
    0x1FFC -> Ok(93)
    0x1FFD -> Ok(126)
    _ -> Error(Nil)
  }
}

fn lookup_14bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x3FFC -> Ok(94)
    0x3FFD -> Ok(125)
    _ -> Error(Nil)
  }
}

fn lookup_15bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x7FFC -> Ok(60)
    0x7FFD -> Ok(96)
    0x7FFE -> Ok(123)
    _ -> Error(Nil)
  }
}

fn lookup_19bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x7FFF0 -> Ok(92)
    0x7FFF1 -> Ok(195)
    0x7FFF2 -> Ok(208)
    _ -> Error(Nil)
  }
}

fn lookup_20bit(code: Int) -> Result(Int, Nil) {
  case code {
    0xFFFE6 -> Ok(128)
    0xFFFE7 -> Ok(130)
    0xFFFE8 -> Ok(131)
    0xFFFE9 -> Ok(162)
    0xFFFEA -> Ok(184)
    0xFFFEB -> Ok(194)
    0xFFFEC -> Ok(224)
    0xFFFED -> Ok(226)
    _ -> Error(Nil)
  }
}

fn lookup_21bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x1FFFDC -> Ok(153)
    0x1FFFDD -> Ok(161)
    0x1FFFDE -> Ok(167)
    0x1FFFDF -> Ok(172)
    0x1FFFE0 -> Ok(176)
    0x1FFFE1 -> Ok(177)
    0x1FFFE2 -> Ok(179)
    0x1FFFE3 -> Ok(209)
    0x1FFFE4 -> Ok(216)
    0x1FFFE5 -> Ok(217)
    0x1FFFE6 -> Ok(227)
    0x1FFFE7 -> Ok(229)
    0x1FFFE8 -> Ok(230)
    _ -> Error(Nil)
  }
}

fn lookup_22bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x3FFFD2 -> Ok(129)
    0x3FFFD3 -> Ok(132)
    0x3FFFD4 -> Ok(133)
    0x3FFFD5 -> Ok(134)
    0x3FFFD6 -> Ok(136)
    0x3FFFD7 -> Ok(146)
    0x3FFFD8 -> Ok(154)
    0x3FFFD9 -> Ok(156)
    0x3FFFDA -> Ok(160)
    0x3FFFDB -> Ok(163)
    0x3FFFDC -> Ok(164)
    0x3FFFDD -> Ok(169)
    0x3FFFDE -> Ok(170)
    0x3FFFDF -> Ok(173)
    0x3FFFE0 -> Ok(178)
    0x3FFFE1 -> Ok(181)
    0x3FFFE2 -> Ok(185)
    0x3FFFE3 -> Ok(186)
    0x3FFFE4 -> Ok(187)
    0x3FFFE5 -> Ok(189)
    0x3FFFE6 -> Ok(190)
    0x3FFFE7 -> Ok(196)
    0x3FFFE8 -> Ok(198)
    0x3FFFE9 -> Ok(228)
    0x3FFFEA -> Ok(232)
    0x3FFFEB -> Ok(233)
    _ -> Error(Nil)
  }
}

fn lookup_23bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x7FFFD8 -> Ok(1)
    0x7FFFD9 -> Ok(135)
    0x7FFFDA -> Ok(137)
    0x7FFFDB -> Ok(138)
    0x7FFFDC -> Ok(139)
    0x7FFFDD -> Ok(140)
    0x7FFFDE -> Ok(141)
    0x7FFFDF -> Ok(143)
    0x7FFFE0 -> Ok(147)
    0x7FFFE1 -> Ok(149)
    0x7FFFE2 -> Ok(150)
    0x7FFFE3 -> Ok(151)
    0x7FFFE4 -> Ok(152)
    0x7FFFE5 -> Ok(155)
    0x7FFFE6 -> Ok(157)
    0x7FFFE7 -> Ok(158)
    0x7FFFE8 -> Ok(165)
    0x7FFFE9 -> Ok(166)
    0x7FFFEA -> Ok(168)
    0x7FFFEB -> Ok(174)
    0x7FFFEC -> Ok(175)
    0x7FFFED -> Ok(180)
    0x7FFFEE -> Ok(182)
    0x7FFFEF -> Ok(183)
    0x7FFFF0 -> Ok(188)
    0x7FFFF1 -> Ok(191)
    0x7FFFF2 -> Ok(197)
    0x7FFFF3 -> Ok(231)
    0x7FFFF4 -> Ok(239)
    _ -> Error(Nil)
  }
}

fn lookup_24bit(code: Int) -> Result(Int, Nil) {
  case code {
    0xFFFFEA -> Ok(9)
    0xFFFFEB -> Ok(142)
    0xFFFFEC -> Ok(144)
    0xFFFFED -> Ok(145)
    0xFFFFEE -> Ok(148)
    0xFFFFEF -> Ok(159)
    0xFFFFF0 -> Ok(171)
    0xFFFFF1 -> Ok(206)
    0xFFFFF2 -> Ok(215)
    0xFFFFF3 -> Ok(225)
    0xFFFFF4 -> Ok(236)
    0xFFFFF5 -> Ok(237)
    _ -> Error(Nil)
  }
}

fn lookup_25bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x1FFFFEC -> Ok(199)
    0x1FFFFED -> Ok(207)
    0x1FFFFEE -> Ok(234)
    0x1FFFFEF -> Ok(235)
    _ -> Error(Nil)
  }
}

fn lookup_26bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x3FFFFE0 -> Ok(192)
    0x3FFFFE1 -> Ok(193)
    0x3FFFFE2 -> Ok(200)
    0x3FFFFE3 -> Ok(201)
    0x3FFFFE4 -> Ok(202)
    0x3FFFFE5 -> Ok(205)
    0x3FFFFE6 -> Ok(210)
    0x3FFFFE7 -> Ok(213)
    0x3FFFFE8 -> Ok(218)
    0x3FFFFE9 -> Ok(219)
    0x3FFFFEA -> Ok(238)
    0x3FFFFEB -> Ok(240)
    0x3FFFFEC -> Ok(242)
    0x3FFFFED -> Ok(243)
    0x3FFFFEE -> Ok(255)
    _ -> Error(Nil)
  }
}

fn lookup_27bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x7FFFFDE -> Ok(203)
    0x7FFFFDF -> Ok(204)
    0x7FFFFE0 -> Ok(211)
    0x7FFFFE1 -> Ok(212)
    0x7FFFFE2 -> Ok(214)
    0x7FFFFE3 -> Ok(221)
    0x7FFFFE4 -> Ok(222)
    0x7FFFFE5 -> Ok(223)
    0x7FFFFE6 -> Ok(241)
    0x7FFFFE7 -> Ok(244)
    0x7FFFFE8 -> Ok(245)
    0x7FFFFE9 -> Ok(246)
    0x7FFFFEA -> Ok(247)
    0x7FFFFEB -> Ok(248)
    0x7FFFFEC -> Ok(250)
    0x7FFFFED -> Ok(251)
    0x7FFFFEE -> Ok(252)
    0x7FFFFEF -> Ok(253)
    0x7FFFFF0 -> Ok(254)
    _ -> Error(Nil)
  }
}

fn lookup_28bit(code: Int) -> Result(Int, Nil) {
  case code {
    0xFFFFFE2 -> Ok(2)
    0xFFFFFE3 -> Ok(3)
    0xFFFFFE4 -> Ok(4)
    0xFFFFFE5 -> Ok(5)
    0xFFFFFE6 -> Ok(6)
    0xFFFFFE7 -> Ok(7)
    0xFFFFFE8 -> Ok(8)
    0xFFFFFE9 -> Ok(11)
    0xFFFFFEA -> Ok(12)
    0xFFFFFEB -> Ok(14)
    0xFFFFFEC -> Ok(15)
    0xFFFFFED -> Ok(16)
    0xFFFFFEE -> Ok(17)
    0xFFFFFEF -> Ok(18)
    0xFFFFFF0 -> Ok(19)
    0xFFFFFF1 -> Ok(20)
    0xFFFFFF2 -> Ok(21)
    0xFFFFFF3 -> Ok(23)
    0xFFFFFF4 -> Ok(24)
    0xFFFFFF5 -> Ok(25)
    0xFFFFFF6 -> Ok(26)
    0xFFFFFF7 -> Ok(27)
    0xFFFFFF8 -> Ok(28)
    0xFFFFFF9 -> Ok(29)
    0xFFFFFFA -> Ok(30)
    0xFFFFFFB -> Ok(31)
    0xFFFFFFC -> Ok(127)
    0xFFFFFFD -> Ok(220)
    0xFFFFFFE -> Ok(249)
    _ -> Error(Nil)
  }
}

fn lookup_30bit(code: Int) -> Result(Int, Nil) {
  case code {
    0x3FFFFFFC -> Ok(10)
    0x3FFFFFFD -> Ok(13)
    0x3FFFFFFE -> Ok(22)
    _ -> Error(Nil)
  }
}

/// Convert list of bytes to BitArray
fn list_to_bit_array(bytes: List(Int)) -> BitArray {
  list_to_bit_array_acc(bytes, <<>>)
}

fn list_to_bit_array_acc(bytes: List(Int), acc: BitArray) -> BitArray {
  case bytes {
    [] -> acc
    [b, ..rest] -> list_to_bit_array_acc(rest, <<acc:bits, b:8>>)
  }
}

/// Reverse a list
fn list_reverse(items: List(a)) -> List(a) {
  list_reverse_acc(items, [])
}

fn list_reverse_acc(items: List(a), acc: List(a)) -> List(a) {
  case items {
    [] -> acc
    [x, ..rest] -> list_reverse_acc(rest, [x, ..acc])
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts HuffmanError to string
///
pub fn huffman_error_to_string(error: HuffmanError) -> String {
  case error {
    InvalidHuffmanData(message) -> "Invalid Huffman data: " <> message
    EosInData -> "EOS symbol found in data"
    InvalidPadding(message) -> "Invalid padding: " <> message
  }
}

/// Estimates if Huffman encoding would reduce size
///
/// Simple heuristic: Huffman is beneficial if input is mostly ASCII text.
///
pub fn should_huffman_encode(input: String) -> Bool {
  let bytes = bit_array.from_string(input)
  let length = bit_array.byte_size(bytes)

  // Very short strings: don't use Huffman
  case length < 10 {
    True -> False
    False -> {
      // For now, use Huffman for strings longer than 10 bytes
      // TODO: Implement smarter heuristic based on character distribution
      True
    }
  }
}
