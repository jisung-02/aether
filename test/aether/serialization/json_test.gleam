// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// JSON Serialization Stage Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/core/message
import aether/pipeline/stage
import aether/serialization/json as json_stage
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/option
import gleam/result
import gleam/string
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Test Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub type TestUser {
  TestUser(name: String, age: Int)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decode Stage Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn decode_stage_parses_json_object_test() {
  let json_bytes = <<"{\"name\": \"Alice\", \"age\": 30}":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  // JSON should be in metadata
  let json_opt = json_stage.get_json(output_data)
  json_opt
  |> option.is_some()
  |> should.be_true()
}

pub fn decode_stage_parses_json_array_test() {
  let json_bytes = <<"[1, 2, 3]":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  json_stage.get_json(output_data)
  |> option.is_some()
  |> should.be_true()
}

pub fn decode_stage_parses_json_string_test() {
  let json_bytes = <<"\"hello world\"":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  json_stage.get_json(output_data)
  |> option.is_some()
  |> should.be_true()
}

pub fn decode_stage_parses_json_number_test() {
  let json_bytes = <<"42":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  json_stage.get_json(output_data)
  |> option.is_some()
  |> should.be_true()
}

pub fn decode_stage_parses_json_boolean_test() {
  let json_bytes = <<"true":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  json_stage.get_json(output_data)
  |> option.is_some()
  |> should.be_true()
}

pub fn decode_stage_parses_json_null_test() {
  let json_bytes = <<"null":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  json_stage.get_json(output_data)
  |> option.is_some()
  |> should.be_true()
}

pub fn decode_stage_preserves_original_bytes_test() {
  let json_bytes = <<"{\"key\": \"value\"}":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  // Original bytes should be preserved
  message.bytes(output_data)
  |> should.equal(json_bytes)
}

pub fn decode_stage_stores_raw_string_test() {
  let json_string = "{\"key\": \"value\"}"
  let json_bytes = bit_array.from_string(json_string)
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)
  let assert option.Some(json_data) = json_stage.get_json(output_data)

  json_data.raw_string
  |> should.equal(json_string)
}

pub fn decode_stage_error_on_invalid_json_test() {
  let invalid_bytes = <<"not valid json":utf8>>
  let input_data = message.new(invalid_bytes)
  let decoder = json_stage.decode()

  stage.execute(decoder, input_data)
  |> result.is_error()
  |> should.be_true()
}

pub fn decode_stage_error_on_incomplete_json_test() {
  let incomplete_bytes = <<"{\"key\":":utf8>>
  let input_data = message.new(incomplete_bytes)
  let decoder = json_stage.decode()

  stage.execute(decoder, input_data)
  |> result.is_error()
  |> should.be_true()
}

pub fn decode_stage_error_on_invalid_utf8_test() {
  // Invalid UTF-8 sequence
  let invalid_bytes = <<0xFF, 0xFE>>
  let input_data = message.new(invalid_bytes)
  let decoder = json_stage.decode()

  stage.execute(decoder, input_data)
  |> result.is_error()
  |> should.be_true()
}

pub fn decode_stage_handles_empty_object_test() {
  let json_bytes = <<"{}":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  json_stage.get_json(output_data)
  |> option.is_some()
  |> should.be_true()
}

pub fn decode_stage_handles_empty_array_test() {
  let json_bytes = <<"[]":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  json_stage.get_json(output_data)
  |> option.is_some()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encode Stage Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn encode_stage_encodes_json_object_test() {
  let json_value =
    json.object([#("name", json.string("Bob")), #("age", json.int(25))])

  let input_data =
    message.new(<<>>)
    |> json_stage.set_json_for_encode(json_value)

  let encoder = json_stage.encode()
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  let output_bytes = message.bytes(output_data)
  let assert Ok(output_string) = bit_array.to_string(output_bytes)

  output_string
  |> should_contain("\"name\"")
  output_string
  |> should_contain("\"Bob\"")
  output_string
  |> should_contain("\"age\"")
  output_string
  |> should_contain("25")
}

pub fn encode_stage_encodes_json_array_test() {
  let json_value = json.array([1, 2, 3], of: json.int)

  let input_data =
    message.new(<<>>)
    |> json_stage.set_json_for_encode(json_value)

  let encoder = json_stage.encode()
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  let output_bytes = message.bytes(output_data)
  let assert Ok(output_string) = bit_array.to_string(output_bytes)

  output_string
  |> should.equal("[1,2,3]")
}

pub fn encode_stage_encodes_json_string_test() {
  let json_value = json.string("hello world")

  let input_data =
    message.new(<<>>)
    |> json_stage.set_json_for_encode(json_value)

  let encoder = json_stage.encode()
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  let output_bytes = message.bytes(output_data)
  let assert Ok(output_string) = bit_array.to_string(output_bytes)

  output_string
  |> should.equal("\"hello world\"")
}

pub fn encode_stage_encodes_json_number_test() {
  let json_value = json.int(42)

  let input_data =
    message.new(<<>>)
    |> json_stage.set_json_for_encode(json_value)

  let encoder = json_stage.encode()
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  let output_bytes = message.bytes(output_data)
  let assert Ok(output_string) = bit_array.to_string(output_bytes)

  output_string
  |> should.equal("42")
}

pub fn encode_stage_encodes_json_boolean_test() {
  let json_value = json.bool(True)

  let input_data =
    message.new(<<>>)
    |> json_stage.set_json_for_encode(json_value)

  let encoder = json_stage.encode()
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  let output_bytes = message.bytes(output_data)
  let assert Ok(output_string) = bit_array.to_string(output_bytes)

  output_string
  |> should.equal("true")
}

pub fn encode_stage_encodes_json_null_test() {
  let json_value = json.null()

  let input_data =
    message.new(<<>>)
    |> json_stage.set_json_for_encode(json_value)

  let encoder = json_stage.encode()
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  let output_bytes = message.bytes(output_data)
  let assert Ok(output_string) = bit_array.to_string(output_bytes)

  output_string
  |> should.equal("null")
}

pub fn encode_stage_error_without_json_test() {
  let input_data = message.new(<<>>)
  let encoder = json_stage.encode()

  stage.execute(encoder, input_data)
  |> result.is_error()
  |> should.be_true()
}

pub fn encode_stage_sets_content_type_metadata_test() {
  let json_value = json.object([#("status", json.string("ok"))])

  let input_data =
    message.new(<<>>)
    |> json_stage.set_json_for_encode(json_value)

  let encoder = json_stage.encode()
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  // Content-Type should be set in metadata
  json_stage.is_json_content_type(output_data)
  |> should.be_true()
}

pub fn encode_stage_with_no_content_type_config_test() {
  let json_value = json.object([#("status", json.string("ok"))])
  let config = json_stage.config_no_content_type()

  let input_data =
    message.new(<<>>)
    |> json_stage.set_json_for_encode(json_value)

  let encoder = json_stage.encode_with_config(config)
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  // Content-Type should NOT be set
  json_stage.is_json_content_type(output_data)
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Type-Safe Decoding Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn decode_as_type_test() {
  let json_bytes = <<"{\"name\": \"Charlie\", \"age\": 35}":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  let user_decoder = {
    use name <- decode.field("name", decode.string)
    use age <- decode.field("age", decode.int)
    decode.success(TestUser(name:, age:))
  }

  let assert Ok(user) = json_stage.decode_as(output_data, user_decoder)

  user.name
  |> should.equal("Charlie")
  user.age
  |> should.equal(35)
}

pub fn decode_as_error_on_missing_field_test() {
  let json_bytes = <<"{\"name\": \"Charlie\"}":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  let user_decoder = {
    use name <- decode.field("name", decode.string)
    use age <- decode.field("age", decode.int)
    decode.success(TestUser(name:, age:))
  }

  json_stage.decode_as(output_data, user_decoder)
  |> result.is_error()
  |> should.be_true()
}

pub fn decode_as_error_on_wrong_type_test() {
  let json_bytes = <<"{\"name\": \"Charlie\", \"age\": \"not a number\"}":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  let user_decoder = {
    use name <- decode.field("name", decode.string)
    use age <- decode.field("age", decode.int)
    decode.success(TestUser(name:, age:))
  }

  json_stage.decode_as(output_data, user_decoder)
  |> result.is_error()
  |> should.be_true()
}

pub fn decode_as_error_without_json_data_test() {
  let input_data = message.new(<<>>)

  let user_decoder = {
    use name <- decode.field("name", decode.string)
    use age <- decode.field("age", decode.int)
    decode.success(TestUser(name:, age:))
  }

  json_stage.decode_as(input_data, user_decoder)
  |> result.is_error()
  |> should.be_true()
}

pub fn decode_string_as_success_test() {
  let json_string = "{\"name\": \"Diana\", \"age\": 28}"

  let user_decoder = {
    use name <- decode.field("name", decode.string)
    use age <- decode.field("age", decode.int)
    decode.success(TestUser(name:, age:))
  }

  let assert Ok(user) = json_stage.decode_string_as(json_string, user_decoder)

  user.name
  |> should.equal("Diana")
  user.age
  |> should.equal(28)
}

pub fn decode_string_as_error_test() {
  let invalid_json = "not valid json"

  let user_decoder = {
    use name <- decode.field("name", decode.string)
    use age <- decode.field("age", decode.int)
    decode.success(TestUser(name:, age:))
  }

  json_stage.decode_string_as(invalid_json, user_decoder)
  |> result.is_error()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Roundtrip Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn roundtrip_decode_encode_test() {
  // 1. Start with JSON
  let original_json =
    json.object([#("status", json.string("ok")), #("count", json.int(42))])
  let original_string = json.to_string(original_json)
  let original_bytes = bit_array.from_string(original_string)

  // 2. Decode
  let input_data = message.new(original_bytes)
  let decode_stage = json_stage.decode()
  let assert Ok(decoded_data) = stage.execute(decode_stage, input_data)

  // 3. Set new JSON for encoding
  let new_json =
    json.object([#("status", json.string("ok")), #("count", json.int(42))])
  let data_with_json = json_stage.set_json_for_encode(decoded_data, new_json)

  // 4. Encode
  let encode_stage = json_stage.encode()
  let assert Ok(encoded_data) = stage.execute(encode_stage, data_with_json)

  // 5. Verify
  let output_bytes = message.bytes(encoded_data)
  let assert Ok(output_string) = bit_array.to_string(output_bytes)

  output_string
  |> should_contain("status")
  output_string
  |> should_contain("ok")
  output_string
  |> should_contain("count")
  output_string
  |> should_contain("42")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Configuration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn default_config_test() {
  let config = json_stage.default_config()

  config.set_content_type
  |> should.be_true()
  config.content_type
  |> should.equal("application/json; charset=utf-8")
}

pub fn config_no_content_type_test() {
  let config = json_stage.config_no_content_type()

  config.set_content_type
  |> should.be_false()
}

pub fn config_custom_content_type_test() {
  let config = json_stage.config_with_content_type("application/vnd.api+json")

  config.set_content_type
  |> should.be_true()
  config.content_type
  |> should.equal("application/vnd.api+json")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Function Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn has_json_false_when_no_json_test() {
  let data = message.new(<<>>)

  json_stage.has_json(data)
  |> should.be_false()
}

pub fn has_json_true_after_decode_test() {
  let json_bytes = <<"{\"key\": \"value\"}":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  json_stage.has_json(output_data)
  |> should.be_true()
}

pub fn has_json_for_encode_false_when_no_json_test() {
  let data = message.new(<<>>)

  json_stage.has_json_for_encode(data)
  |> should.be_false()
}

pub fn has_json_for_encode_true_after_set_test() {
  let data =
    message.new(<<>>)
    |> json_stage.set_json_for_encode(json.string("test"))

  json_stage.has_json_for_encode(data)
  |> should.be_true()
}

pub fn get_json_value_test() {
  let json_bytes = <<"{\"key\": \"value\"}":utf8>>
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  json_stage.get_json_value(output_data)
  |> option.is_some()
  |> should.be_true()
}

pub fn get_raw_json_string_test() {
  let json_string = "{\"key\": \"value\"}"
  let json_bytes = bit_array.from_string(json_string)
  let input_data = message.new(json_bytes)
  let decoder = json_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  let assert option.Some(raw) = json_stage.get_raw_json_string(output_data)
  raw
  |> should.equal(json_string)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Message Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_to_string_parse_error_test() {
  let error = json_stage.ParseError("unexpected token")
  json_stage.error_to_string(error)
  |> should_contain("Parse Error")
}

pub fn error_to_string_decode_error_test() {
  let error = json_stage.DecodeError("missing field 'name'")
  json_stage.error_to_string(error)
  |> should_contain("Decode Error")
}

pub fn error_to_string_encode_error_test() {
  let error = json_stage.EncodeError("failed to encode")
  json_stage.error_to_string(error)
  |> should_contain("Encode Error")
}

pub fn error_to_string_invalid_content_type_test() {
  let error =
    json_stage.InvalidContentType(
      expected: "application/json",
      actual: "text/html",
    )
  json_stage.error_to_string(error)
  |> should_contain("Content-Type")
  json_stage.error_to_string(error)
  |> should_contain("application/json")
  json_stage.error_to_string(error)
  |> should_contain("text/html")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Content-Type Validation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn require_json_content_type_success_test() {
  let json_value = json.string("test")
  let data =
    message.new(<<>>)
    |> json_stage.set_json_for_encode(json_value)

  let encoder = json_stage.encode()
  let assert Ok(output_data) = stage.execute(encoder, data)

  json_stage.require_json_content_type(output_data)
  |> result.is_ok()
  |> should.be_true()
}

pub fn require_json_content_type_error_when_not_set_test() {
  let data = message.new(<<>>)

  json_stage.require_json_content_type(data)
  |> result.is_error()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn metadata_key_constant_test() {
  json_stage.metadata_key
  |> should.equal("json:parsed")
}

pub fn encode_metadata_key_constant_test() {
  json_stage.encode_metadata_key
  |> should.equal("json:encode")
}

pub fn default_content_type_constant_test() {
  json_stage.default_content_type
  |> should.equal("application/json; charset=utf-8")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn should_contain(haystack: String, needle: String) {
  string.contains(haystack, needle)
  |> should.be_true()
}
