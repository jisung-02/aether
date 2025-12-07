// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Header Parser Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/tcp/header.{
  type TcpFlags, type TcpHeader, TcpFlags, TcpHeader,
}
import gleam/bit_array
import gleam/option

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Errors that can occur during TCP header parsing
///
pub type ParseError {
  /// The input data is too short to contain a valid TCP header
  InvalidLength(expected: Int, actual: Int)
  /// The checksum verification failed
  InvalidChecksum(expected: Int, actual: Int)
  /// The header data is malformed
  MalformedHeader(message: String)
  /// The data offset field is invalid
  InvalidDataOffset(offset: Int)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Parsing Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses a TCP header from a BitArray
///
/// The input must be at least 20 bytes (minimum TCP header size).
/// If the data_offset field indicates options are present, they will
/// be parsed as well.
///
/// ## Parameters
///
/// - `bytes`: The raw bytes to parse
///
/// ## Returns
///
/// A Result containing either the parsed TcpHeader or a ParseError
///
/// ## Examples
///
/// ```gleam
/// let bytes = <<0, 80, 0, 80, 0, 0, 0, 1, 0, 0, 0, 0, 80, 2, 255, 255, 0, 0, 0, 0>>
/// case parse_header(bytes) {
///   Ok(header) -> // use header
///   Error(err) -> // handle error
/// }
/// ```
///
pub fn parse_header(bytes: BitArray) -> Result(TcpHeader, ParseError) {
  let size = bit_array.byte_size(bytes)
  case size < 20 {
    True -> Error(InvalidLength(expected: 20, actual: size))
    False -> do_parse_header(bytes)
  }
}

/// Parses a TCP header and extracts the payload
///
/// ## Parameters
///
/// - `bytes`: The raw segment bytes (header + payload)
///
/// ## Returns
///
/// A Result containing a tuple of (TcpHeader, payload BitArray) or a ParseError
///
pub fn parse_segment(
  bytes: BitArray,
) -> Result(#(TcpHeader, BitArray), ParseError) {
  case parse_header(bytes) {
    Ok(hdr) -> {
      let header_len = hdr.data_offset * 4
      case extract_payload(bytes, header_len) {
        Ok(payload) -> Ok(#(hdr, payload))
        Error(err) -> Error(err)
      }
    }
    Error(err) -> Error(err)
  }
}

/// Internal function to parse header after length validation
///
fn do_parse_header(bytes: BitArray) -> Result(TcpHeader, ParseError) {
  case bytes {
    <<
      source_port:size(16),
      dest_port:size(16),
      seq_num:size(32),
      ack_num:size(32),
      data_offset:size(4),
      _reserved:size(3),
      ns:size(1),
      cwr:size(1),
      ece:size(1),
      urg:size(1),
      ack:size(1),
      psh:size(1),
      rst:size(1),
      syn:size(1),
      fin:size(1),
      window:size(16),
      checksum:size(16),
      urgent:size(16),
      rest:bits,
    >> -> {
      // Validate data offset (must be >= 5)
      case data_offset < 5 {
        True -> Error(InvalidDataOffset(offset: data_offset))
        False -> {
          let flags =
            TcpFlags(
              ns: int_to_bool(ns),
              cwr: int_to_bool(cwr),
              ece: int_to_bool(ece),
              urg: int_to_bool(urg),
              ack: int_to_bool(ack),
              psh: int_to_bool(psh),
              rst: int_to_bool(rst),
              syn: int_to_bool(syn),
              fin: int_to_bool(fin),
            )

          // Parse options if present
          let options_length = { data_offset - 5 } * 4
          let options = parse_options(rest, options_length)

          Ok(TcpHeader(
            source_port: source_port,
            destination_port: dest_port,
            sequence_number: seq_num,
            acknowledgment_number: ack_num,
            data_offset: data_offset,
            flags: flags,
            window_size: window,
            checksum: checksum,
            urgent_pointer: urgent,
            options: options,
          ))
        }
      }
    }
    _ -> Error(MalformedHeader(message: "Unable to parse TCP header structure"))
  }
}

/// Parses TCP options from the remaining bytes
///
fn parse_options(rest: BitArray, options_length: Int) -> option.Option(BitArray) {
  case options_length > 0 {
    True -> {
      case extract_bytes(rest, options_length) {
        Ok(opts) -> option.Some(opts)
        Error(_) -> option.None
      }
    }
    False -> option.None
  }
}

/// Extracts a specific number of bytes from a BitArray
///
fn extract_bytes(data: BitArray, length: Int) -> Result(BitArray, ParseError) {
  let available = bit_array.byte_size(data)
  case available >= length {
    True -> {
      case data {
        <<extracted:bytes-size(length), _rest:bits>> -> Ok(extracted)
        _ -> Error(MalformedHeader(message: "Failed to extract bytes"))
      }
    }
    False -> Error(InvalidLength(expected: length, actual: available))
  }
}

/// Extracts payload from segment bytes
///
fn extract_payload(
  data: BitArray,
  header_len: Int,
) -> Result(BitArray, ParseError) {
  let total_len = bit_array.byte_size(data)
  case total_len >= header_len {
    True -> {
      case data {
        <<_header:bytes-size(header_len), payload:bits>> -> Ok(payload)
        _ -> Error(MalformedHeader(message: "Failed to extract payload"))
      }
    }
    False -> Error(InvalidLength(expected: header_len, actual: total_len))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flag Parsing Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses TCP flags from a 9-bit integer
///
/// ## Parameters
///
/// - `flags_int`: The 9-bit integer containing packed flags
///
/// ## Returns
///
/// A TcpFlags structure
///
pub fn int_to_flags(flags_int: Int) -> TcpFlags {
  TcpFlags(
    ns: int_to_bool(flags_int / 256 % 2),
    cwr: int_to_bool(flags_int / 128 % 2),
    ece: int_to_bool(flags_int / 64 % 2),
    urg: int_to_bool(flags_int / 32 % 2),
    ack: int_to_bool(flags_int / 16 % 2),
    psh: int_to_bool(flags_int / 8 % 2),
    rst: int_to_bool(flags_int / 4 % 2),
    syn: int_to_bool(flags_int / 2 % 2),
    fin: int_to_bool(flags_int % 2),
  )
}

/// Converts an integer to a boolean (0 = False, non-zero = True)
///
fn int_to_bool(i: Int) -> Bool {
  i != 0
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a ParseError to a human-readable string
///
pub fn error_to_string(error: ParseError) -> String {
  case error {
    InvalidLength(expected, actual) ->
      "Invalid length: expected at least "
      <> int_to_string(expected)
      <> " bytes, got "
      <> int_to_string(actual)
    InvalidChecksum(expected, actual) ->
      "Invalid checksum: expected "
      <> int_to_string(expected)
      <> ", got "
      <> int_to_string(actual)
    MalformedHeader(message) -> "Malformed header: " <> message
    InvalidDataOffset(offset) ->
      "Invalid data offset: " <> int_to_string(offset) <> " (must be >= 5)"
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(i: Int) -> String
