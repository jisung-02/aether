import aether/protocol/quic/error.{Malformed}
import aether/protocol/tls/extensions.{
  Extension, encode_alpn, encode_key_share, encode_list,
  encode_supported_versions_selected, find, key_share_ext, parse_alpn,
  parse_key_shares, parse_list, parse_server_name, parse_signature_algorithms,
  parse_supported_groups, parse_supported_versions,
  quic_transport_parameters_ext, server_name_ext, tls13_version, x25519_group,
}
import gleam/bit_array
import gleeunit/should

pub fn encode_list_parse_list_round_trip_test() {
  let exts = [
    Extension(server_name_ext, <<1, 2, 3>>),
    Extension(key_share_ext, <<0x00, 0x1d, 0x00, 0x02, 0xaa, 0xbb>>),
    Extension(quic_transport_parameters_ext, <<>>),
  ]
  parse_list(encode_list(exts)) |> should.equal(Ok(exts))
}

pub fn encode_list_of_empty_list_is_zero_length_test() {
  encode_list([]) |> should.equal(<<0:16>>)
  parse_list(<<0:16>>) |> should.equal(Ok([]))
}

pub fn find_hit_test() {
  let exts = [Extension(1, <<9, 9>>), Extension(2, <<8, 8>>)]
  find(exts, 2) |> should.equal(Ok(<<8, 8>>))
}

pub fn find_returns_the_first_match_test() {
  let exts = [Extension(1, <<1>>), Extension(1, <<2>>)]
  find(exts, 1) |> should.equal(Ok(<<1>>))
}

pub fn find_miss_test() {
  let exts = [Extension(1, <<9, 9>>)]
  find(exts, 99) |> should.equal(Error(Nil))
}

pub fn encode_alpn_parse_alpn_round_trip_test() {
  parse_alpn(encode_alpn("h3")) |> should.equal(Ok(["h3"]))
}

pub fn parse_alpn_multiple_protocols_test() {
  // 2-byte list length, then 1-byte length-prefixed names: "h3", "http/1.1".
  let data = <<0x00, 0x0c, 0x02, "h3":utf8, 0x08, "http/1.1":utf8>>
  parse_alpn(data) |> should.equal(Ok(["h3", "http/1.1"]))
}

pub fn parse_alpn_rejects_empty_name_test() {
  // list length 1, one entry declaring a 0-length name.
  let data = <<0x00, 0x01, 0x00>>
  parse_alpn(data)
  |> should.equal(Error(Malformed("ALPN protocol name must not be empty")))
}

pub fn parse_alpn_rejects_invalid_utf8_test() {
  let data = <<0x00, 0x02, 0x01, 0xff>>
  case parse_alpn(data) {
    Error(Malformed(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn encode_key_share_format_test() {
  let key = <<0xaa, 0xbb, 0xcc, 0xdd>>
  encode_key_share(x25519_group, key)
  |> should.equal(<<x25519_group:16, 4:16, 0xaa, 0xbb, 0xcc, 0xdd>>)
}

pub fn encode_key_share_as_extension_round_trips_through_parse_key_shares_test() {
  let key = <<1, 2, 3, 4, 5>>
  let single_entry = encode_key_share(x25519_group, key)
  // Wrap the single server-shape entry as a one-element client-shape list
  // to confirm parse_key_shares reads the same (group, length, key) layout.
  let list_wrapped =
    bit_array.concat([<<bit_array.byte_size(single_entry):16>>, single_entry])
  parse_key_shares(list_wrapped) |> should.equal(Ok([#(x25519_group, key)]))
}

pub fn encode_supported_versions_selected_is_tls13_test() {
  encode_supported_versions_selected() |> should.equal(<<tls13_version:16>>)
}

pub fn parse_supported_versions_client_shape_test() {
  // 1-byte list length, then 2-byte version entries.
  let data = <<0x04, 0x03, 0x04, 0x03, 0x03>>
  parse_supported_versions(data) |> should.equal(Ok([0x0304, 0x0303]))
}

pub fn parse_supported_groups_test() {
  let data = <<0x00, 0x04, 0x00, 0x1d, 0x00, 0x17>>
  parse_supported_groups(data) |> should.equal(Ok([0x001d, 0x0017]))
}

pub fn parse_signature_algorithms_test() {
  let data = <<0x00, 0x04, 0x04, 0x03, 0x08, 0x04>>
  parse_signature_algorithms(data) |> should.equal(Ok([0x0403, 0x0804]))
}

pub fn parse_server_name_returns_first_host_name_test() {
  let name = "example.com"
  let name_bytes = bit_array.from_string(name)
  let entry =
    bit_array.concat([<<0:8, bit_array.byte_size(name_bytes):16>>, name_bytes])
  let data = bit_array.concat([<<bit_array.byte_size(entry):16>>, entry])
  parse_server_name(data) |> should.equal(Ok(name))
}

pub fn parse_server_name_skips_non_host_name_entries_test() {
  let name = "example.com"
  let name_bytes = bit_array.from_string(name)
  let other_entry = <<1:8, 2:16, 0xaa, 0xbb>>
  let host_entry =
    bit_array.concat([<<0:8, bit_array.byte_size(name_bytes):16>>, name_bytes])
  let entries = bit_array.concat([other_entry, host_entry])
  let data = bit_array.concat([<<bit_array.byte_size(entries):16>>, entries])
  parse_server_name(data) |> should.equal(Ok(name))
}

pub fn parse_server_name_requires_a_host_name_entry_test() {
  let other_entry = <<1:8, 2:16, 0xaa, 0xbb>>
  let data =
    bit_array.concat([<<bit_array.byte_size(other_entry):16>>, other_entry])
  parse_server_name(data)
  |> should.equal(Error(Malformed("server_name list has no host_name entry")))
}

pub fn parse_list_rejects_truncated_list_test() {
  // Declares a 10-byte list but only 2 bytes are present.
  let data = <<0x00, 0x0a, 0x01, 0x02>>
  case parse_list(data) {
    Error(Malformed(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_list_rejects_trailing_garbage_test() {
  // Declares a 0-byte list but trailing bytes remain.
  let data = <<0x00, 0x00, 0xff, 0xff>>
  case parse_list(data) {
    Error(Malformed(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_list_rejects_truncated_extension_header_test() {
  let data = <<0x00, 0x02, 0x00, 0x01>>
  case parse_list(data) {
    Error(Malformed(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_list_rejects_truncated_extension_data_test() {
  // Declares extension data of length 5 but only supplies 2 bytes.
  let data = <<0x00, 0x06, 0x00, 0x01, 0x00, 0x05, 0xaa, 0xbb>>
  case parse_list(data) {
    Error(Malformed(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_list_of_empty_input_test() {
  case parse_list(<<>>) {
    Error(Malformed(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn no_crash_on_arbitrary_bytes_test() {
  let inputs = [
    <<>>,
    <<0xff>>,
    <<0xff, 0xff, 0xff, 0xff, 0xff>>,
    <<0x00, 0x01>>,
    <<0x00, 0x00, 0x00>>,
  ]
  check_no_crash(inputs)
}

fn check_no_crash(inputs: List(BitArray)) -> Nil {
  case inputs {
    [] -> Nil
    [input, ..rest] -> {
      let _ = parse_list(input)
      let _ = parse_key_shares(input)
      let _ = parse_supported_versions(input)
      let _ = parse_supported_groups(input)
      let _ = parse_signature_algorithms(input)
      let _ = parse_alpn(input)
      let _ = parse_server_name(input)
      check_no_crash(rest)
    }
  }
}
