import gleam/dynamic.{type Dynamic}
import gleeunit/should

@external(erlang, "aether_tcp_ffi", "decode_8_tuple")
fn decode_ipv6_tuple(
  tuple: Dynamic,
) -> Result(#(Int, Int, Int, Int, Int, Int, Int, Int), Nil)

@external(erlang, "aether_tcp_ffi", "sample_ipv6_tuple")
fn sample_ipv6_tuple() -> Dynamic

pub fn decode_ipv6_tuple_test() {
  sample_ipv6_tuple()
  |> decode_ipv6_tuple
  |> should.equal(Ok(#(0, 0, 0, 0, 0, 0, 0, 1)))
}
