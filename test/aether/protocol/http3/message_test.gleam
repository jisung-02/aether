import aether/protocol/http3/frame
import aether/protocol/http3/message
import aether/protocol/http3/qpack
import gleam/http.{Get, Https}
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

/// A QPACK-encoded request header block for a typical GET.
fn get_request_block() -> BitArray {
  qpack.encode([
    #(":method", "GET"),
    #(":scheme", "https"),
    #(":authority", "example.com"),
    #(":path", "/hello"),
    #("user-agent", "curl/8"),
  ])
}

pub fn decode_request_test() {
  let assert Ok(request) = message.decode_request(get_request_block(), <<>>)

  request.method |> should.equal(Get)
  request.scheme |> should.equal(Https)
  request.host |> should.equal("example.com")
  request.path |> should.equal("/hello")
  request.body |> should.equal(<<>>)
  // Pseudo-headers are stripped; the regular header survives.
  request.headers |> should.equal([#("user-agent", "curl/8")])
}

pub fn decode_request_with_query_test() {
  let block =
    qpack.encode([
      #(":method", "GET"),
      #(":scheme", "https"),
      #(":authority", "h"),
      #(":path", "/search?q=quic"),
    ])
  let assert Ok(request) = message.decode_request(block, <<>>)
  request.path |> should.equal("/search?q=quic")
  request.query |> should.equal(Some("q=quic"))
}

pub fn decode_request_with_body_test() {
  let block =
    qpack.encode([
      #(":method", "POST"),
      #(":scheme", "https"),
      #(":authority", "h"),
      #(":path", "/submit"),
    ])
  let assert Ok(request) = message.decode_request(block, <<"payload":utf8>>)
  request.method |> should.equal(http.Post)
  request.body |> should.equal(<<"payload":utf8>>)
  request.query |> should.equal(None)
}

pub fn decode_request_missing_method_test() {
  let block =
    qpack.encode([#(":scheme", "https"), #(":authority", "h"), #(":path", "/")])
  message.decode_request(block, <<>>) |> should.be_error
}

pub fn decode_request_missing_path_test() {
  let block =
    qpack.encode([
      #(":method", "GET"),
      #(":scheme", "https"),
      #(":authority", "h"),
    ])
  message.decode_request(block, <<>>) |> should.be_error
}

pub fn encode_response_round_trips_test() {
  let resp =
    response.new(200)
    |> response.set_header("content-type", "text/plain")
    |> response.set_body(<<"hi":utf8>>)

  let #(header_block, body) = message.encode_response(resp)
  body |> should.equal(<<"hi":utf8>>)

  let assert Ok(fields) = qpack.decode(header_block)
  // :status is emitted first.
  list.first(fields) |> should.equal(Ok(#(":status", "200")))
  list.key_find(fields, "content-type") |> should.equal(Ok("text/plain"))
}

pub fn response_frames_are_headers_then_data_test() {
  let resp =
    response.new(404)
    |> response.set_body(<<"nope":utf8>>)

  let bytes = message.response_frames(resp)
  let assert Ok(#(frames, <<>>)) = frame.parse(bytes)

  case frames {
    [frame.Headers(header_block), frame.Data(body)] -> {
      body |> should.equal(<<"nope":utf8>>)
      let assert Ok(fields) = qpack.decode(header_block)
      list.key_find(fields, ":status") |> should.equal(Ok("404"))
    }
    _ -> should.fail()
  }
}

pub fn handle_echoes_through_a_handler_test() {
  let assert Ok(request) = message.decode_request(get_request_block(), <<>>)

  let bytes =
    message.handle(request, fn(req) {
      response.new(200)
      |> response.set_body(<<"path=":utf8, req.path:utf8>>)
    })

  let assert Ok(#([frame.Headers(hb), frame.Data(body)], <<>>)) =
    frame.parse(bytes)
  body |> should.equal(<<"path=/hello":utf8>>)
  let assert Ok(fields) = qpack.decode(hb)
  list.key_find(fields, ":status") |> should.equal(Ok("200"))
}
