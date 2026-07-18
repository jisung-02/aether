//// Maps between HTTP/3 request/response and `gleam/http` values
//// (RFC 9114 Section 4). Request header blocks are QPACK-decoded and
//// split into pseudo-headers and regular headers; responses are
//// QPACK-encoded and framed as HEADERS + DATA.

import aether/protocol/http3/frame.{Data, Headers}
import aether/protocol/http3/qpack
import aether/protocol/quic/error.{type WireError, Malformed}
import gleam/http.{type Scheme, Http, Https}
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// Decodes an HTTP/3 request from its QPACK header block and body bytes
/// into a `gleam/http` request (RFC 9114 Section 4.3.1). Fails on a
/// malformed field section, a missing or duplicated pseudo-header, an
/// unknown pseudo-header, or a pseudo-header following a regular header.
pub fn decode_request(
  header_block: BitArray,
  body: BitArray,
) -> Result(Request(BitArray), WireError) {
  use fields <- result.try(qpack.decode(header_block))
  use #(pseudo, regular) <- result.try(split_pseudo_headers(fields))

  use method_string <- result.try(required(pseudo, ":method"))
  use path <- result.try(required(pseudo, ":path"))
  use scheme <- result.try(scheme_from(pseudo))
  let method = http.parse_method(method_string) |> result.unwrap(http.Get)
  let authority = find_pseudo(pseudo, ":authority")

  Ok(Request(
    method: method,
    headers: regular,
    body: body,
    scheme: scheme,
    host: authority |> result.unwrap(""),
    port: None,
    path: path,
    query: query_of(path),
  ))
}

/// Encodes a response's headers and body: returns the QPACK-encoded field
/// section (with `:status` first) and the body bytes, for the caller to
/// frame as HEADERS + DATA.
pub fn encode_response(response: Response(BitArray)) -> #(BitArray, BitArray) {
  let fields = [
    #(":status", int.to_string(response.status)),
    ..response.headers
  ]
  #(qpack.encode(fields), response.body)
}

/// Frames a response as the HEADERS and DATA bytes to write on the
/// request stream.
pub fn response_frames(response: Response(BitArray)) -> BitArray {
  let #(header_block, body) = encode_response(response)
  <<frame.build(Headers(header_block)):bits, frame.build(Data(body)):bits>>
}

/// Runs `handler` on `request` and returns the framed HTTP/3 response
/// bytes (HEADERS + DATA) to write on the request stream.
pub fn handle(
  request: Request(BitArray),
  handler: fn(Request(BitArray)) -> Response(BitArray),
) -> BitArray {
  response_frames(handler(request))
}

// ─────────────────────────────────────────────────────────────────────────

fn split_pseudo_headers(
  fields: List(#(String, String)),
) -> Result(#(List(#(String, String)), List(#(String, String))), WireError) {
  // Pseudo-headers must all precede regular headers (RFC 9114 4.3).
  do_split(fields, [], [], False)
}

fn do_split(
  fields: List(#(String, String)),
  pseudo: List(#(String, String)),
  regular: List(#(String, String)),
  seen_regular: Bool,
) -> Result(#(List(#(String, String)), List(#(String, String))), WireError) {
  case fields {
    [] -> Ok(#(list.reverse(pseudo), list.reverse(regular)))
    [#(name, value), ..rest] ->
      case is_pseudo(name) {
        True ->
          case seen_regular {
            True -> Error(Malformed("pseudo-header after regular header"))
            False ->
              case list.key_find(pseudo, name) {
                Ok(_) -> Error(Malformed("duplicate pseudo-header"))
                Error(Nil) ->
                  do_split(rest, [#(name, value), ..pseudo], regular, False)
              }
          }
        False -> do_split(rest, pseudo, [#(name, value), ..regular], True)
      }
  }
}

fn is_pseudo(name: String) -> Bool {
  case name {
    ":" <> _ -> True
    _ -> False
  }
}

fn required(
  pseudo: List(#(String, String)),
  name: String,
) -> Result(String, WireError) {
  find_pseudo(pseudo, name)
  |> result.replace_error(Malformed("missing pseudo-header " <> name))
}

fn find_pseudo(
  pseudo: List(#(String, String)),
  name: String,
) -> Result(String, Nil) {
  list.key_find(pseudo, name)
}

fn scheme_from(pseudo: List(#(String, String))) -> Result(Scheme, WireError) {
  case find_pseudo(pseudo, ":scheme") {
    Ok("https") -> Ok(Https)
    Ok("http") -> Ok(Http)
    // Default to https; QUIC transport is always TLS-protected.
    Error(Nil) -> Ok(Https)
    Ok(_) -> Error(Malformed("unsupported :scheme"))
  }
}

fn query_of(path: String) -> option.Option(String) {
  case string.split_once(path, "?") {
    Ok(#(_, query)) -> Some(query)
    Error(Nil) -> None
  }
}
