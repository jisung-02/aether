// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// URL Encoding/Decoding Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides percent-encoding/decoding for URLs as defined in RFC 3986.
//

import gleam/bit_array
import gleam/list
import gleam/string
import gleam/string_tree

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Errors that can occur during URL encoding/decoding
///
pub type UrlError {
  /// Invalid percent-encoding sequence
  InvalidPercentEncoding(message: String)
  /// Invalid hex digit in percent-encoding
  InvalidHexDigit(char: String)
  /// Incomplete percent-encoding (missing digits)
  IncompletePercentEncoding
  /// Invalid UTF-8 sequence in decoded bytes
  InvalidUtf8
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Percent Decoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Decodes a percent-encoded string
///
/// Decodes %XX sequences to their character values and converts + to space.
///
/// ## Parameters
///
/// - `encoded`: The percent-encoded string
///
/// ## Returns
///
/// The decoded string or an error
///
/// ## Examples
///
/// ```gleam
/// percent_decode("hello%20world")  // Ok("hello world")
/// percent_decode("hello+world")    // Ok("hello world")
/// percent_decode("%E4%B8%AD%E6%96%87")  // Ok("中文")
/// ```
///
pub fn percent_decode(encoded: String) -> Result(String, UrlError) {
  case percent_decode_bytes(<<encoded:utf8>>) {
    Ok(bytes) -> {
      case bit_array.to_string(bytes) {
        Ok(s) -> Ok(s)
        Error(_) -> Error(InvalidUtf8)
      }
    }
    Error(e) -> Error(e)
  }
}

/// Decodes percent-encoded bytes
///
/// Lower-level function that operates on BitArray.
///
pub fn percent_decode_bytes(bytes: BitArray) -> Result(BitArray, UrlError) {
  do_percent_decode(bytes, <<>>)
}

fn do_percent_decode(
  input: BitArray,
  acc: BitArray,
) -> Result(BitArray, UrlError) {
  case input {
    // Empty input - done
    <<>> -> Ok(acc)

    // Percent-encoded sequence
    <<37, rest:bits>> -> {
      // 37 = '%'
      case rest {
        <<h1, h2, remaining:bits>> -> {
          case hex_to_int(h1), hex_to_int(h2) {
            Ok(high), Ok(low) -> {
              let byte = high * 16 + low
              do_percent_decode(remaining, <<acc:bits, byte>>)
            }
            Error(_), _ ->
              Error(InvalidHexDigit(char: string_from_codepoint(h1)))
            _, Error(_) ->
              Error(InvalidHexDigit(char: string_from_codepoint(h2)))
          }
        }
        _ -> Error(IncompletePercentEncoding)
      }
    }

    // Plus sign -> space (in query strings)
    <<43, rest:bits>> -> {
      // 43 = '+'
      do_percent_decode(rest, <<acc:bits, 32>>)
      // 32 = ' '
    }

    // Regular character
    <<byte, rest:bits>> -> {
      do_percent_decode(rest, <<acc:bits, byte>>)
    }

    // Non-byte-aligned (shouldn't happen with valid input)
    _ -> Error(InvalidPercentEncoding(message: "Invalid byte sequence"))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Percent Encoding Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Encodes a string using percent-encoding
///
/// Encodes all characters except unreserved characters (A-Z, a-z, 0-9, -, _, ., ~).
///
/// ## Parameters
///
/// - `decoded`: The string to encode
///
/// ## Returns
///
/// The percent-encoded string
///
/// ## Examples
///
/// ```gleam
/// percent_encode("hello world")  // "hello%20world"
/// percent_encode("foo=bar")      // "foo%3Dbar"
/// ```
///
pub fn percent_encode(decoded: String) -> String {
  percent_encode_bytes(<<decoded:utf8>>)
}

/// Encodes bytes using percent-encoding
///
pub fn percent_encode_bytes(bytes: BitArray) -> String {
  do_percent_encode(bytes, string_tree.new())
  |> string_tree.to_string()
}

fn do_percent_encode(
  input: BitArray,
  acc: string_tree.StringTree,
) -> string_tree.StringTree {
  case input {
    <<>> -> acc
    <<byte, rest:bits>> -> {
      let new_acc = case is_unreserved(byte) {
        True -> string_tree.append(acc, string_from_codepoint(byte))
        False -> {
          let hex = int_to_hex_string(byte)
          string_tree.append(acc, "%" <> hex)
        }
      }
      do_percent_encode(rest, new_acc)
    }
    _ -> acc
  }
}

/// Checks if a byte is an unreserved character per RFC 3986
///
fn is_unreserved(byte: Int) -> Bool {
  // A-Z
  { byte >= 65 && byte <= 90 }
  // a-z
  || { byte >= 97 && byte <= 122 }
  // 0-9
  || { byte >= 48 && byte <= 57 }
  // - _ . ~
  || byte == 45
  || byte == 95
  || byte == 46
  || byte == 126
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Query String Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Parses a query string into key-value pairs
///
/// Handles the standard "key=value&key2=value2" format.
/// Keys and values are percent-decoded.
///
/// ## Parameters
///
/// - `query`: The query string (without leading ?)
///
/// ## Returns
///
/// A list of key-value tuples or an error
///
/// ## Examples
///
/// ```gleam
/// parse_query_string("foo=bar&baz=qux")
/// // Ok([#("foo", "bar"), #("baz", "qux")])
///
/// parse_query_string("name=John%20Doe")
/// // Ok([#("name", "John Doe")])
/// ```
///
pub fn parse_query_string(
  query: String,
) -> Result(List(#(String, String)), UrlError) {
  case query {
    "" -> Ok([])
    _ -> {
      query
      |> string.split("&")
      |> list.try_map(parse_query_pair)
    }
  }
}

fn parse_query_pair(pair: String) -> Result(#(String, String), UrlError) {
  case string.split_once(pair, "=") {
    Ok(#(key, value)) -> {
      case percent_decode(key), percent_decode(value) {
        Ok(decoded_key), Ok(decoded_value) -> Ok(#(decoded_key, decoded_value))
        Error(e), _ -> Error(e)
        _, Error(e) -> Error(e)
      }
    }
    Error(_) -> {
      // Key without value
      case percent_decode(pair) {
        Ok(decoded_key) -> Ok(#(decoded_key, ""))
        Error(e) -> Error(e)
      }
    }
  }
}

/// Builds a query string from key-value pairs
///
/// Keys and values are percent-encoded.
///
/// ## Parameters
///
/// - `params`: List of key-value tuples
///
/// ## Returns
///
/// The encoded query string (without leading ?)
///
/// ## Examples
///
/// ```gleam
/// build_query_string([#("foo", "bar"), #("baz", "qux")])
/// // "foo=bar&baz=qux"
/// ```
///
pub fn build_query_string(params: List(#(String, String))) -> String {
  params
  |> list.map(fn(pair) {
    percent_encode(pair.0) <> "=" <> percent_encode(pair.1)
  })
  |> string.join("&")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a UrlError to a human-readable string
///
pub fn error_to_string(error: UrlError) -> String {
  case error {
    InvalidPercentEncoding(message) -> "Invalid percent encoding: " <> message
    InvalidHexDigit(char) -> "Invalid hex digit: " <> char
    IncompletePercentEncoding -> "Incomplete percent encoding sequence"
    InvalidUtf8 -> "Invalid UTF-8 sequence in decoded data"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a hex digit (as byte) to its integer value
///
fn hex_to_int(byte: Int) -> Result(Int, Nil) {
  case byte {
    // 0-9
    b if b >= 48 && b <= 57 -> Ok(b - 48)
    // A-F
    b if b >= 65 && b <= 70 -> Ok(b - 55)
    // a-f
    b if b >= 97 && b <= 102 -> Ok(b - 87)
    _ -> Error(Nil)
  }
}

/// Converts an integer (0-255) to a two-character uppercase hex string
///
fn int_to_hex_string(n: Int) -> String {
  let high = n / 16
  let low = n % 16
  int_to_hex_char(high) <> int_to_hex_char(low)
}

fn int_to_hex_char(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    10 -> "A"
    11 -> "B"
    12 -> "C"
    13 -> "D"
    14 -> "E"
    15 -> "F"
    _ -> "0"
  }
}

fn string_from_codepoint(codepoint: Int) -> String {
  case bit_array.to_string(<<codepoint>>) {
    Ok(s) -> s
    Error(_) -> "?"
  }
}
