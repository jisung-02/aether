// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Content Negotiation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/core/message
import aether/serialization/negotiation
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accept Header Parser Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn parse_simple_accept_test() {
  let accept = "application/json"
  let parsed = negotiation.parse_accept(accept)

  list.length(parsed)
  |> should.equal(1)

  let assert [media_type] = parsed

  media_type.type_
  |> should.equal("application")

  media_type.subtype
  |> should.equal("json")

  media_type.quality
  |> should.equal(1.0)
}

pub fn parse_multiple_accept_test() {
  let accept = "application/json, text/html, text/plain"
  let parsed = negotiation.parse_accept(accept)

  list.length(parsed)
  |> should.equal(3)
}

pub fn parse_accept_with_quality_test() {
  let accept = "text/plain; q=0.5, application/json; q=1.0"
  let parsed = negotiation.parse_accept(accept)

  // Should be sorted by quality (highest first)
  let assert [first, second] = parsed

  first.subtype
  |> should.equal("json")

  first.quality
  |> should.equal(1.0)

  second.subtype
  |> should.equal("plain")

  second.quality
  |> should.equal(0.5)
}

pub fn parse_accept_with_multiple_quality_values_test() {
  let accept =
    "text/plain; q=0.5, application/json; q=1.0, text/html; q=0.9, application/xml; q=0.8"
  let parsed = negotiation.parse_accept(accept)

  list.length(parsed)
  |> should.equal(4)

  // Should be sorted: json (1.0), html (0.9), xml (0.8), plain (0.5)
  let assert [first, second, third, fourth] = parsed

  first.subtype
  |> should.equal("json")

  second.subtype
  |> should.equal("html")

  third.subtype
  |> should.equal("xml")

  fourth.subtype
  |> should.equal("plain")
}

pub fn parse_accept_with_wildcard_test() {
  let accept = "*/*"
  let parsed = negotiation.parse_accept(accept)

  let assert [media_type] = parsed

  media_type.type_
  |> should.equal("*")

  media_type.subtype
  |> should.equal("*")
}

pub fn parse_accept_with_subtype_wildcard_test() {
  let accept = "application/*"
  let parsed = negotiation.parse_accept(accept)

  let assert [media_type] = parsed

  media_type.type_
  |> should.equal("application")

  media_type.subtype
  |> should.equal("*")
}

pub fn parse_accept_default_quality_test() {
  let accept = "application/json"
  let parsed = negotiation.parse_accept(accept)

  let assert [media_type] = parsed

  // Default quality should be 1.0
  media_type.quality
  |> should.equal(1.0)
}

pub fn parse_accept_with_charset_test() {
  let accept = "text/html; charset=utf-8; q=0.9"
  let parsed = negotiation.parse_accept(accept)

  let assert [media_type] = parsed

  media_type.type_
  |> should.equal("text")

  media_type.subtype
  |> should.equal("html")

  media_type.quality
  |> should.equal(0.9)

  // Charset should be in parameters (q is extracted separately)
  dict.get(media_type.parameters, "charset")
  |> should.equal(Ok("utf-8"))
}

pub fn parse_empty_accept_test() {
  let accept = ""
  let parsed = negotiation.parse_accept(accept)

  list.is_empty(parsed)
  |> should.be_true()
}

pub fn parse_accept_with_spaces_test() {
  let accept = "  application/json  ,  text/html  "
  let parsed = negotiation.parse_accept(accept)

  list.length(parsed)
  |> should.equal(2)

  let assert [first, second] = parsed

  first.type_
  |> should.equal("application")

  second.type_
  |> should.equal("text")
}

pub fn parse_invalid_quality_defaults_to_one_test() {
  let accept = "application/json; q=invalid"
  let parsed = negotiation.parse_accept(accept)

  let assert [media_type] = parsed

  // Invalid quality should default to 1.0
  media_type.quality
  |> should.equal(1.0)
}

pub fn parse_quality_out_of_range_test() {
  let accept = "application/json; q=1.5"
  let parsed = negotiation.parse_accept(accept)

  let assert [media_type] = parsed

  // Quality > 1.0 should default to 1.0
  media_type.quality
  |> should.equal(1.0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Content-Type Matching Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn negotiate_exact_match_test() {
  let accept = "application/json"
  let available = ["application/json", "text/plain"]

  negotiation.negotiate(accept, available)
  |> should.equal(option.Some("application/json"))
}

pub fn negotiate_wildcard_test() {
  let accept = "*/*"
  let available = ["application/json", "text/plain"]

  negotiation.negotiate(accept, available)
  |> option.is_some()
  |> should.be_true()
}

pub fn negotiate_subtype_wildcard_test() {
  let accept = "application/*"
  let available = ["application/json", "text/plain"]

  negotiation.negotiate(accept, available)
  |> should.equal(option.Some("application/json"))
}

pub fn negotiate_no_match_test() {
  let accept = "application/xml"
  let available = ["application/json", "text/plain"]

  negotiation.negotiate(accept, available)
  |> should.equal(option.None)
}

pub fn negotiate_quality_preference_test() {
  let accept = "text/plain; q=0.8, application/json; q=1.0, text/html; q=0.9"
  let available = ["application/json", "text/plain", "text/html"]

  // Should prefer application/json (q=1.0)
  negotiation.negotiate(accept, available)
  |> should.equal(option.Some("application/json"))
}

pub fn negotiate_first_available_for_equal_quality_test() {
  let accept = "application/json, text/plain"
  let available = ["text/plain", "application/json"]

  // Both have q=1.0, should match application/json first (order in accept header)
  negotiation.negotiate(accept, available)
  |> should.equal(option.Some("application/json"))
}

pub fn negotiate_fallback_to_lower_quality_test() {
  let accept = "application/xml; q=1.0, text/plain; q=0.5"
  let available = ["text/plain"]

  // application/xml not available, should fall back to text/plain
  negotiation.negotiate(accept, available)
  |> should.equal(option.Some("text/plain"))
}

pub fn negotiate_empty_available_test() {
  let accept = "application/json"
  let available: List(String) = []

  negotiation.negotiate(accept, available)
  |> should.equal(option.None)
}

pub fn matches_media_type_exact_test() {
  let media_type = negotiation.new_media_type("application", "json")

  negotiation.matches_media_type(media_type, "application/json")
  |> should.be_true()
}

pub fn matches_media_type_wildcard_test() {
  let media_type = negotiation.new_media_type("*", "*")

  negotiation.matches_media_type(media_type, "application/json")
  |> should.be_true()

  negotiation.matches_media_type(media_type, "text/plain")
  |> should.be_true()
}

pub fn matches_media_type_subtype_wildcard_test() {
  let media_type = negotiation.new_media_type("application", "*")

  negotiation.matches_media_type(media_type, "application/json")
  |> should.be_true()

  negotiation.matches_media_type(media_type, "application/xml")
  |> should.be_true()

  negotiation.matches_media_type(media_type, "text/plain")
  |> should.be_false()
}

pub fn matches_media_type_no_match_test() {
  let media_type = negotiation.new_media_type("application", "xml")

  negotiation.matches_media_type(media_type, "application/json")
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Serializer Registry Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_registry_is_empty_test() {
  let registry = negotiation.new_registry()

  negotiation.get_available_types(registry)
  |> list.is_empty()
  |> should.be_true()
}

pub fn register_serializer_test() {
  let serializer =
    negotiation.Serializer(content_type: "application/json", serialize: fn(_) {
      Ok("{}")
    })

  let registry =
    negotiation.new_registry()
    |> negotiation.register("application/json", serializer)

  negotiation.get_available_types(registry)
  |> list.length()
  |> should.equal(1)

  negotiation.get_available_types(registry)
  |> list.contains("application/json")
  |> should.be_true()
}

pub fn register_multiple_serializers_test() {
  let json_serializer =
    negotiation.Serializer(content_type: "application/json", serialize: fn(_) {
      Ok("{}")
    })

  let text_serializer =
    negotiation.Serializer(content_type: "text/plain", serialize: fn(_) {
      Ok("text")
    })

  let registry =
    negotiation.new_registry()
    |> negotiation.register("application/json", json_serializer)
    |> negotiation.register("text/plain", text_serializer)

  negotiation.get_available_types(registry)
  |> list.length()
  |> should.equal(2)
}

pub fn select_serializer_success_test() {
  let json_serializer =
    negotiation.Serializer(content_type: "application/json", serialize: fn(_) {
      Ok("{}")
    })

  let registry =
    negotiation.new_registry()
    |> negotiation.register("application/json", json_serializer)

  let accept = "application/json"

  negotiation.select_serializer(registry, accept)
  |> result.is_ok()
  |> should.be_true()

  let assert Ok(#(content_type, _serializer)) =
    negotiation.select_serializer(registry, accept)

  content_type
  |> should.equal("application/json")
}

pub fn select_serializer_no_match_test() {
  let json_serializer =
    negotiation.Serializer(content_type: "application/json", serialize: fn(_) {
      Ok("{}")
    })

  let registry =
    negotiation.new_registry()
    |> negotiation.register("application/json", json_serializer)

  let accept = "application/xml"

  negotiation.select_serializer(registry, accept)
  |> result.is_error()
  |> should.be_true()
}

pub fn select_serializer_empty_registry_test() {
  let registry = negotiation.new_registry()
  let accept = "application/json"

  case negotiation.select_serializer(registry, accept) {
    Error(negotiation.NoSerializerFound) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn select_serializer_with_default_test() {
  let json_serializer =
    negotiation.Serializer(content_type: "application/json", serialize: fn(_) {
      Ok("{}")
    })

  let registry =
    negotiation.new_registry()
    |> negotiation.register("application/json", json_serializer)
    |> negotiation.with_default("application/json")

  // Wildcard should use default
  let accept = "*/*"

  let assert Ok(#(content_type, _)) =
    negotiation.select_serializer(registry, accept)

  content_type
  |> should.equal("application/json")
}

pub fn select_serializer_empty_accept_uses_default_test() {
  let json_serializer =
    negotiation.Serializer(content_type: "application/json", serialize: fn(_) {
      Ok("{}")
    })

  let registry =
    negotiation.new_registry()
    |> negotiation.register("application/json", json_serializer)
    |> negotiation.with_default("application/json")

  // Empty accept should use default
  let accept = ""

  let assert Ok(#(content_type, _)) =
    negotiation.select_serializer(registry, accept)

  content_type
  |> should.equal("application/json")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Built-in Serializer Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn json_serializer_content_type_test() {
  let serializer = negotiation.json_serializer()

  serializer.content_type
  |> should.equal("application/json")
}

pub fn text_serializer_content_type_test() {
  let serializer = negotiation.text_serializer()

  serializer.content_type
  |> should.equal("text/plain")
}

pub fn register_json_serializer_test() {
  let registry =
    negotiation.new_registry()
    |> negotiation.register_json_serializer()

  negotiation.get_available_types(registry)
  |> list.contains("application/json")
  |> should.be_true()
}

pub fn register_text_serializer_test() {
  let registry =
    negotiation.new_registry()
    |> negotiation.register_text_serializer()

  negotiation.get_available_types(registry)
  |> list.contains("text/plain")
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Function Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn set_and_get_response_data_test() {
  let data = message.new(<<>>)
  let response_str = "Hello, World!"

  let updated_data = negotiation.set_string_response(data, response_str)

  negotiation.get_response_data(updated_data)
  |> option.is_some()
  |> should.be_true()
}

pub fn has_negotiation_false_initially_test() {
  let data = message.new(<<>>)

  negotiation.has_negotiation(data)
  |> should.be_false()
}

pub fn media_type_to_string_test() {
  let media_type = negotiation.new_media_type("application", "json")

  negotiation.media_type_to_string(media_type)
  |> should.equal("application/json")
}

pub fn new_media_type_with_quality_test() {
  let media_type = negotiation.new_media_type_with_quality("text", "html", 0.8)

  media_type.type_
  |> should.equal("text")

  media_type.subtype
  |> should.equal("html")

  media_type.quality
  |> should.equal(0.8)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_to_string_not_acceptable_test() {
  let error = negotiation.NotAcceptable(["application/json", "text/plain"])

  negotiation.error_to_string(error)
  |> should_contain("Not Acceptable")

  negotiation.error_to_string(error)
  |> should_contain("application/json")
}

pub fn error_to_string_no_serializer_test() {
  let error = negotiation.NoSerializerFound

  negotiation.error_to_string(error)
  |> should_contain("No serializers")
}

pub fn error_to_string_serialization_failed_test() {
  let error = negotiation.SerializationFailed("encoding error")

  negotiation.error_to_string(error)
  |> should_contain("Serialization failed")

  negotiation.error_to_string(error)
  |> should_contain("encoding error")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Response Helper Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn not_acceptable_response_test() {
  let resp = negotiation.not_acceptable_response(["application/json"])

  resp.status
  |> should.equal(406)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn serializer_key_constant_test() {
  negotiation.serializer_key
  |> should.equal("negotiation:serializer")
}

pub fn content_type_key_constant_test() {
  negotiation.content_type_key
  |> should.equal("negotiation:content_type")
}

pub fn response_data_key_constant_test() {
  negotiation.response_data_key
  |> should.equal("negotiation:response_data")
}

pub fn default_content_type_constant_test() {
  negotiation.default_content_type
  |> should.equal("application/json")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/string

fn should_contain(haystack: String, needle: String) {
  string.contains(haystack, needle)
  |> should.be_true()
}
