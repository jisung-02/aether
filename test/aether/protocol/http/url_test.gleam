import aether/protocol/http/url
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Percent Decode Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn percent_decode_simple_test() {
  url.percent_decode("hello%20world")
  |> should.equal(Ok("hello world"))
}

pub fn percent_decode_plus_sign_test() {
  url.percent_decode("hello+world")
  |> should.equal(Ok("hello world"))
}

pub fn percent_decode_no_encoding_test() {
  url.percent_decode("hello")
  |> should.equal(Ok("hello"))
}

pub fn percent_decode_special_chars_test() {
  url.percent_decode("foo%3Dbar")
  |> should.equal(Ok("foo=bar"))
}

pub fn percent_decode_ampersand_test() {
  url.percent_decode("a%26b")
  |> should.equal(Ok("a&b"))
}

pub fn percent_decode_unicode_test() {
  // 中 = E4 B8 AD, 文 = E6 96 87
  url.percent_decode("%E4%B8%AD%E6%96%87")
  |> should.equal(Ok("中文"))
}

pub fn percent_decode_korean_test() {
  // 한 = ED 95 9C, 글 = EA B8 80
  url.percent_decode("%ED%95%9C%EA%B8%80")
  |> should.equal(Ok("한글"))
}

pub fn percent_decode_mixed_test() {
  url.percent_decode("hello%20%E4%B8%96%E7%95%8C")
  |> should.equal(Ok("hello 世界"))
}

pub fn percent_decode_lowercase_hex_test() {
  url.percent_decode("hello%2fworld")
  |> should.equal(Ok("hello/world"))
}

pub fn percent_decode_uppercase_hex_test() {
  url.percent_decode("hello%2Fworld")
  |> should.equal(Ok("hello/world"))
}

pub fn percent_decode_incomplete_error_test() {
  url.percent_decode("hello%2")
  |> should.be_error()
}

pub fn percent_decode_invalid_hex_error_test() {
  url.percent_decode("hello%GG")
  |> should.be_error()
}

pub fn percent_decode_empty_test() {
  url.percent_decode("")
  |> should.equal(Ok(""))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Percent Encode Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn percent_encode_simple_test() {
  url.percent_encode("hello world")
  |> should.equal("hello%20world")
}

pub fn percent_encode_no_encoding_needed_test() {
  url.percent_encode("hello")
  |> should.equal("hello")
}

pub fn percent_encode_special_chars_test() {
  url.percent_encode("foo=bar")
  |> should.equal("foo%3Dbar")
}

pub fn percent_encode_ampersand_test() {
  url.percent_encode("a&b")
  |> should.equal("a%26b")
}

pub fn percent_encode_unreserved_chars_test() {
  // Unreserved chars should not be encoded
  url.percent_encode("ABCxyz012-_.~")
  |> should.equal("ABCxyz012-_.~")
}

pub fn percent_encode_unicode_test() {
  url.percent_encode("中文")
  |> should.equal("%E4%B8%AD%E6%96%87")
}

pub fn percent_encode_empty_test() {
  url.percent_encode("")
  |> should.equal("")
}

pub fn percent_encode_slash_test() {
  url.percent_encode("/path/to/file")
  |> should.equal("%2Fpath%2Fto%2Ffile")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Roundtrip Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn encode_decode_roundtrip_test() {
  let original = "hello world"
  let encoded = url.percent_encode(original)
  let assert Ok(decoded) = url.percent_decode(encoded)
  decoded |> should.equal(original)
}

pub fn encode_decode_unicode_roundtrip_test() {
  let original = "안녕하세요 世界"
  let encoded = url.percent_encode(original)
  let assert Ok(decoded) = url.percent_decode(encoded)
  decoded |> should.equal(original)
}

pub fn encode_decode_special_chars_roundtrip_test() {
  let original = "key=value&other=data"
  let encoded = url.percent_encode(original)
  let assert Ok(decoded) = url.percent_decode(encoded)
  decoded |> should.equal(original)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Query String Parse Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_query_string_simple_test() {
  url.parse_query_string("foo=bar")
  |> should.equal(Ok([#("foo", "bar")]))
}

pub fn parse_query_string_multiple_test() {
  url.parse_query_string("foo=bar&baz=qux")
  |> should.equal(Ok([#("foo", "bar"), #("baz", "qux")]))
}

pub fn parse_query_string_encoded_test() {
  url.parse_query_string("name=John%20Doe")
  |> should.equal(Ok([#("name", "John Doe")]))
}

pub fn parse_query_string_plus_test() {
  url.parse_query_string("name=John+Doe")
  |> should.equal(Ok([#("name", "John Doe")]))
}

pub fn parse_query_string_empty_value_test() {
  url.parse_query_string("foo=")
  |> should.equal(Ok([#("foo", "")]))
}

pub fn parse_query_string_no_value_test() {
  url.parse_query_string("foo")
  |> should.equal(Ok([#("foo", "")]))
}

pub fn parse_query_string_empty_test() {
  url.parse_query_string("")
  |> should.equal(Ok([]))
}

pub fn parse_query_string_complex_test() {
  url.parse_query_string("page=1&limit=10&sort=name%20asc")
  |> should.equal(Ok([#("page", "1"), #("limit", "10"), #("sort", "name asc")]))
}

pub fn parse_query_string_encoded_key_test() {
  url.parse_query_string("my%20key=value")
  |> should.equal(Ok([#("my key", "value")]))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Query String Build Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn build_query_string_simple_test() {
  url.build_query_string([#("foo", "bar")])
  |> should.equal("foo=bar")
}

pub fn build_query_string_multiple_test() {
  url.build_query_string([#("foo", "bar"), #("baz", "qux")])
  |> should.equal("foo=bar&baz=qux")
}

pub fn build_query_string_encoded_test() {
  url.build_query_string([#("name", "John Doe")])
  |> should.equal("name=John%20Doe")
}

pub fn build_query_string_empty_test() {
  url.build_query_string([])
  |> should.equal("")
}

pub fn build_query_string_special_chars_test() {
  url.build_query_string([#("key", "value=with&special")])
  |> should.equal("key=value%3Dwith%26special")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Query String Roundtrip Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn query_string_roundtrip_test() {
  let original = [#("foo", "bar"), #("baz", "qux")]
  let built = url.build_query_string(original)
  let assert Ok(parsed) = url.parse_query_string(built)
  parsed |> should.equal(original)
}

pub fn query_string_roundtrip_special_test() {
  let original = [#("name", "John Doe"), #("city", "New York")]
  let built = url.build_query_string(original)
  let assert Ok(parsed) = url.parse_query_string(built)
  parsed |> should.equal(original)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_to_string_invalid_hex_test() {
  url.error_to_string(url.InvalidHexDigit("G"))
  |> should.equal("Invalid hex digit: G")
}

pub fn error_to_string_incomplete_test() {
  url.error_to_string(url.IncompletePercentEncoding)
  |> should.equal("Incomplete percent encoding sequence")
}

pub fn error_to_string_invalid_utf8_test() {
  url.error_to_string(url.InvalidUtf8)
  |> should.equal("Invalid UTF-8 sequence in decoded data")
}
