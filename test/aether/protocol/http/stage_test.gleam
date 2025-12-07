import aether/core/message
import aether/pipeline/stage
import aether/protocol/http/parser
import aether/protocol/http/request
import aether/protocol/http/response
import aether/protocol/http/stage as http_stage
import aether/protocol/protocol
import aether/protocol/registry
import gleam/bit_array
import gleam/http
import gleam/option
import gleam/result
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decode Stage Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn decode_stage_extracts_body_test() {
  let body = <<"Hello, World!":utf8>>
  let request_bytes = <<
    "POST /api HTTP/1.1\r\nHost: example.com\r\nContent-Length: 13\r\n\r\n":utf8,
    body:bits,
  >>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  // Body should be extracted to message bytes
  message.bytes(output_data) |> should.equal(body)
}

pub fn decode_stage_stores_request_in_metadata_test() {
  let request_bytes = <<
    "GET /api/users HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  // Request should be stored in metadata
  let req_opt = http_stage.get_request(output_data)
  req_opt |> option.is_some() |> should.be_true()

  let assert option.Some(req_data) = req_opt
  req_data.request.method |> should.equal(http.Get)
  req_data.request.uri |> should.equal("/api/users")
}

pub fn decode_stage_stores_remaining_bytes_test() {
  let request_bytes = <<
    "GET /first HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
    "GET /second HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  // Should have remaining bytes for pipelining
  http_stage.has_pipelined_requests(output_data) |> should.be_true()

  // Remaining bytes should be the second request
  let assert option.Some(remaining) =
    http_stage.get_remaining_bytes(output_data)
  { bit_array.byte_size(remaining) > 0 } |> should.be_true()
}

pub fn decode_stage_stores_http_request_test() {
  let request_bytes = <<
    "GET /api?page=1 HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()

  let assert Ok(output_data) = stage.execute(decoder, input_data)

  // gleam_http Request should be available
  let http_req_opt = http_stage.get_http_request(output_data)
  http_req_opt |> option.is_some() |> should.be_true()

  let assert option.Some(http_req) = http_req_opt
  http_req.path |> should.equal("/api")
  http_req.query |> should.equal(option.Some("page=1"))
  http_req.host |> should.equal("example.com")
}

pub fn decode_stage_error_on_invalid_request_test() {
  let invalid_bytes = <<"INVALID REQUEST":utf8>>

  let input_data = message.new(invalid_bytes)
  let decoder = http_stage.decode()

  stage.execute(decoder, input_data)
  |> result.is_error()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encode Stage Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn encode_stage_builds_request_test() {
  let body = <<"new body":utf8>>
  let parsed =
    request.post("/api")
    |> request.set_header("host", "example.com")
    |> request.set_body(<<"original":utf8>>)

  let req_data = http_stage.new_request_data(parsed, <<>>)

  // Create data with the request in metadata and new body
  let input_data =
    message.new(body)
    |> http_stage.set_request(req_data)

  let encoder = http_stage.encode()
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  // Output should be complete HTTP request with new body
  let output_bytes = message.bytes(output_data)
  let assert Ok(str) = bit_array.to_string(output_bytes)

  str |> should_contain("POST /api HTTP/1.1\r\n")
  str |> should_contain("host: example.com\r\n")
  str |> should_contain("new body")
}

pub fn encode_stage_error_without_metadata_test() {
  let input_data = message.new(<<"body":utf8>>)
  let encoder = http_stage.encode()

  stage.execute(encoder, input_data)
  |> result.is_error()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Roundtrip Tests (decode -> modify -> encode)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn roundtrip_decode_encode_test() {
  let original_bytes = <<"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8>>

  let input_data = message.new(original_bytes)

  // Decode
  let decoder = http_stage.decode()
  let assert Ok(decoded_data) = stage.execute(decoder, input_data)

  // Encode
  let encoder = http_stage.encode()
  let assert Ok(encoded_data) = stage.execute(encoder, decoded_data)

  // Should be able to parse the encoded output
  let output_bytes = message.bytes(encoded_data)
  let assert Ok(#(parsed, _)) = parser.parse_request(output_bytes)

  parsed.method |> should.equal(http.Get)
  parsed.uri |> should.equal("/")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn http_protocol_has_correct_name_test() {
  let proto = http_stage.http_protocol()

  protocol.get_name(proto) |> should.equal("http")
}

pub fn http_protocol_has_correct_tags_test() {
  let proto = http_stage.http_protocol()

  protocol.has_tag(proto, "application") |> should.be_true()
  protocol.has_tag(proto, "layer7") |> should.be_true()
  protocol.has_tag(proto, "text-based") |> should.be_true()
}

pub fn http_protocol_has_decoder_test() {
  let proto = http_stage.http_protocol()

  protocol.get_decoder(proto)
  |> option.is_some()
  |> should.be_true()
}

pub fn http_protocol_has_encoder_test() {
  let proto = http_stage.http_protocol()

  protocol.get_encoder(proto)
  |> option.is_some()
  |> should.be_true()
}

pub fn http_protocol_has_version_test() {
  let proto = http_stage.http_protocol()
  let metadata = protocol.get_metadata(proto)

  metadata.version |> should.equal("1.1")
}

pub fn http_protocol_has_description_test() {
  let proto = http_stage.http_protocol()
  let metadata = protocol.get_metadata(proto)

  metadata.description |> should.equal("Hypertext Transfer Protocol")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Registry Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn register_http_test() {
  let reg =
    registry.new()
    |> http_stage.register_http()

  registry.get(reg, "http")
  |> option.is_some()
  |> should.be_true()
}

pub fn registered_http_protocol_works_test() {
  let reg =
    registry.new()
    |> http_stage.register_http()

  let assert option.Some(proto) = registry.get(reg, "http")
  let assert option.Some(decoder) = protocol.get_decoder(proto)

  let request_bytes = <<"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8>>

  let input_data = message.new(request_bytes)
  let result = stage.execute(decoder, input_data)

  result |> result.is_ok() |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Function Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn get_method_test() {
  let request_bytes = <<"POST /api HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8>>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  http_stage.get_method(output_data) |> should.equal(option.Some("POST"))
}

pub fn get_uri_test() {
  let request_bytes = <<
    "GET /api/users HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  http_stage.get_uri(output_data) |> should.equal(option.Some("/api/users"))
}

pub fn get_version_test() {
  let request_bytes = <<"GET / HTTP/1.0\r\nHost: example.com\r\n\r\n":utf8>>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  http_stage.get_version(output_data)
  |> should.equal(option.Some(request.Http10))
}

pub fn get_header_test() {
  let request_bytes = <<
    "GET / HTTP/1.1\r\nHost: example.com\r\nAccept: application/json\r\n\r\n":utf8,
  >>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  http_stage.get_header(output_data, "accept")
  |> should.equal(option.Some("application/json"))
}

pub fn get_content_type_test() {
  let body = <<"data":utf8>>
  let request_bytes = <<
    "POST /api HTTP/1.1\r\nHost: example.com\r\nContent-Type: application/json\r\nContent-Length: 4\r\n\r\n":utf8,
    body:bits,
  >>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  http_stage.get_content_type(output_data)
  |> should.equal(option.Some("application/json"))
}

pub fn get_host_test() {
  let request_bytes = <<
    "GET / HTTP/1.1\r\nHost: example.com:8080\r\n\r\n":utf8,
  >>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  http_stage.get_host(output_data)
  |> should.equal(option.Some("example.com:8080"))
}

pub fn get_body_size_test() {
  let body = <<"Hello":utf8>>
  let request_bytes = <<
    "POST /api HTTP/1.1\r\nHost: example.com\r\nContent-Length: 5\r\n\r\n":utf8,
    body:bits,
  >>

  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()
  let assert Ok(output_data) = stage.execute(decoder, input_data)

  http_stage.get_body_size(output_data) |> should.equal(5)
}

pub fn get_body_size_no_request_test() {
  let input_data = message.new(<<>>)

  http_stage.get_body_size(input_data) |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleam/string

fn should_contain(haystack: String, needle: String) {
  string.contains(haystack, needle) |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Response Data Type Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_response_data_test() {
  let resp = response.ok()
  let resp_data = http_stage.new_response_data(resp, option.None)

  resp_data.response.status |> should.equal(200)
  resp_data.original_request |> should.equal(option.None)
}

pub fn new_response_data_with_request_test() {
  // First decode a request
  let request_bytes = <<"GET /api HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8>>
  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()
  let assert Ok(decoded_data) = stage.execute(decoder, input_data)

  // Get the request data
  let assert option.Some(req_data) = http_stage.get_request(decoded_data)

  // Create response data with original request
  let resp = response.ok()
  let resp_data = http_stage.new_response_data(resp, option.Some(req_data))

  resp_data.response.status |> should.equal(200)
  resp_data.original_request |> option.is_some() |> should.be_true()

  let assert option.Some(orig_req) = resp_data.original_request
  orig_req.request.uri |> should.equal("/api")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Response Metadata Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn set_and_get_response_test() {
  let resp =
    response.ok()
    |> response.text()
    |> response.with_string_body("Hello")

  let resp_data = http_stage.new_response_data(resp, option.None)

  let data =
    message.new(<<>>)
    |> http_stage.set_response(resp_data)

  let retrieved = http_stage.get_response(data)
  retrieved |> option.is_some() |> should.be_true()

  let assert option.Some(retrieved_data) = retrieved
  retrieved_data.response.status |> should.equal(200)
}

pub fn get_http_response_test() {
  let resp =
    response.not_found()
    |> response.with_string_body("Not found")

  let resp_data = http_stage.new_response_data(resp, option.None)
  let data =
    message.new(<<>>)
    |> http_stage.set_response(resp_data)

  let http_resp = http_stage.get_http_response(data)
  http_resp |> option.is_some() |> should.be_true()

  let assert option.Some(r) = http_resp
  r.status |> should.equal(404)
  r.reason |> should.equal("Not Found")
}

pub fn get_response_status_test() {
  let resp = response.internal_server_error()
  let resp_data = http_stage.new_response_data(resp, option.None)
  let data =
    message.new(<<>>)
    |> http_stage.set_response(resp_data)

  http_stage.get_response_status(data) |> should.equal(option.Some(500))
}

pub fn get_response_status_no_response_test() {
  let data = message.new(<<>>)

  http_stage.get_response_status(data) |> should.equal(option.None)
}

pub fn get_response_body_size_test() {
  let resp =
    response.ok()
    |> response.with_string_body("12345")

  let resp_data = http_stage.new_response_data(resp, option.None)
  let data =
    message.new(<<>>)
    |> http_stage.set_response(resp_data)

  http_stage.get_response_body_size(data) |> should.equal(5)
}

pub fn get_response_body_size_no_response_test() {
  let data = message.new(<<>>)

  http_stage.get_response_body_size(data) |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Create Response for Request Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn create_response_for_request_test() {
  // First decode a request
  let request_bytes = <<"GET /api HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8>>
  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()
  let assert Ok(decoded_data) = stage.execute(decoder, input_data)

  // Create response for the request
  let resp =
    response.ok()
    |> response.json()
    |> response.with_string_body("{\"status\": \"ok\"}")

  let data_with_response =
    http_stage.create_response_for_request(decoded_data, resp)

  // Response should be set
  let resp_opt = http_stage.get_response(data_with_response)
  resp_opt |> option.is_some() |> should.be_true()

  let assert option.Some(resp_data) = resp_opt

  // Response should have the original request linked
  resp_data.original_request |> option.is_some() |> should.be_true()

  let assert option.Some(orig_req) = resp_data.original_request
  orig_req.request.uri |> should.equal("/api")
}

pub fn create_response_for_request_no_request_test() {
  // Data without request
  let data = message.new(<<>>)

  let resp = response.ok()
  let data_with_response = http_stage.create_response_for_request(data, resp)

  // Response should be set but without original request
  let resp_opt = http_stage.get_response(data_with_response)
  resp_opt |> option.is_some() |> should.be_true()

  let assert option.Some(resp_data) = resp_opt
  resp_data.original_request |> should.equal(option.None)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Encode Response Stage Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn encode_response_stage_builds_response_test() {
  let resp =
    response.ok()
    |> response.text()
    |> response.with_string_body("Hello, World!")

  let resp_data = http_stage.new_response_data(resp, option.None)
  let input_data =
    message.new(<<>>)
    |> http_stage.set_response(resp_data)

  let encoder = http_stage.encode_response()
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  let output_bytes = message.bytes(output_data)
  let assert Ok(str) = bit_array.to_string(output_bytes)

  str |> should_contain("HTTP/1.1 200 OK\r\n")
  str |> should_contain("content-type: text/plain; charset=utf-8\r\n")
  str |> should_contain("content-length: 13\r\n")
  str |> should_contain("\r\n\r\nHello, World!")
}

pub fn encode_response_stage_error_response_test() {
  let resp = response.error_response(404, "Resource not found")
  let resp_data = http_stage.new_response_data(resp, option.None)
  let input_data =
    message.new(<<>>)
    |> http_stage.set_response(resp_data)

  let encoder = http_stage.encode_response()
  let assert Ok(output_data) = stage.execute(encoder, input_data)

  let output_bytes = message.bytes(output_data)
  let assert Ok(str) = bit_array.to_string(output_bytes)

  str |> should_contain("HTTP/1.1 404 Not Found\r\n")
  str |> should_contain("application/json")
  str |> should_contain("Resource not found")
}

pub fn encode_response_stage_error_without_metadata_test() {
  let input_data = message.new(<<>>)
  let encoder = http_stage.encode_response()

  stage.execute(encoder, input_data)
  |> result.is_error()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Request-Response Roundtrip Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn request_response_roundtrip_test() {
  // 1. Decode incoming request
  let request_bytes = <<
    "GET /api/status HTTP/1.1\r\nHost: example.com\r\n\r\n":utf8,
  >>
  let input_data = message.new(request_bytes)
  let decoder = http_stage.decode()
  let assert Ok(decoded_data) = stage.execute(decoder, input_data)

  // 2. Create response for the request
  let resp =
    response.ok()
    |> response.json()
    |> response.with_string_body("{\"healthy\": true}")

  let data_with_response =
    http_stage.create_response_for_request(decoded_data, resp)

  // 3. Encode the response
  let encoder = http_stage.encode_response()
  let assert Ok(output_data) = stage.execute(encoder, data_with_response)

  // 4. Verify output
  let output_bytes = message.bytes(output_data)
  let assert Ok(str) = bit_array.to_string(output_bytes)

  str |> should_contain("HTTP/1.1 200 OK\r\n")
  str |> should_contain("application/json; charset=utf-8")
  str |> should_contain("{\"healthy\": true}")

  // Original request should still be linked
  let resp_data = http_stage.get_response(output_data)
  resp_data |> option.is_some() |> should.be_true()

  let assert option.Some(rd) = resp_data
  rd.original_request |> option.is_some() |> should.be_true()
}
