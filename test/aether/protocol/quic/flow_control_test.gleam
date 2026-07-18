import aether/protocol/quic/flow_control
import gleam/option.{None, Some}
import gleeunit/should

pub fn send_available_starts_at_initial_max_test() {
  flow_control.new_send(100)
  |> flow_control.send_available
  |> should.equal(100)
}

pub fn record_sent_within_limit_reduces_available_test() {
  let assert Ok(s) = flow_control.new_send(100) |> flow_control.record_sent(60)
  flow_control.send_available(s) |> should.equal(40)
}

pub fn record_sent_exceeding_limit_errors_test() {
  let assert Ok(s) = flow_control.new_send(100) |> flow_control.record_sent(60)
  flow_control.record_sent(s, 50) |> should.equal(Error(Nil))
}

pub fn record_sent_up_to_boundary_leaves_zero_available_test() {
  let assert Ok(s) = flow_control.new_send(100) |> flow_control.record_sent(60)
  let assert Ok(s) = flow_control.record_sent(s, 40)
  flow_control.send_available(s) |> should.equal(0)
}

pub fn on_max_data_raises_limit_and_unblocks_test() {
  let assert Ok(s) = flow_control.new_send(100) |> flow_control.record_sent(100)
  flow_control.send_available(s) |> should.equal(0)

  let s = flow_control.on_max_data(s, 150)
  flow_control.send_available(s) |> should.equal(50)
}

pub fn on_max_data_ignores_lower_value_test() {
  let assert Ok(s) = flow_control.new_send(100) |> flow_control.record_sent(100)
  let s = flow_control.on_max_data(s, 150)
  let s = flow_control.on_max_data(s, 120)
  flow_control.send_available(s) |> should.equal(50)
}

pub fn record_received_within_limit_test() {
  flow_control.new_recv(100)
  |> flow_control.record_received(80)
  |> should.be_ok
}

pub fn record_received_beyond_limit_errors_test() {
  flow_control.new_recv(100)
  |> flow_control.record_received(101)
  |> should.equal(Error(Nil))
}

pub fn record_received_at_boundary_allowed_test() {
  flow_control.new_recv(100)
  |> flow_control.record_received(100)
  |> should.be_ok
}

pub fn maybe_extend_does_not_fire_before_half_window_test() {
  let r = flow_control.new_recv(100) |> flow_control.consume(40)
  let #(r, extension) = flow_control.maybe_extend(r)
  extension |> should.equal(None)
  flow_control.recv_max_data(r) |> should.equal(100)
}

pub fn maybe_extend_fires_past_half_window_test() {
  let r = flow_control.new_recv(100) |> flow_control.consume(60)
  let #(r, extension) = flow_control.maybe_extend(r)
  extension |> should.equal(Some(160))
  flow_control.recv_max_data(r) |> should.equal(160)
}

pub fn maybe_extend_allows_higher_offsets_after_extending_test() {
  let r = flow_control.new_recv(100) |> flow_control.consume(60)
  let #(r, _extension) = flow_control.maybe_extend(r)
  flow_control.record_received(r, 160) |> should.be_ok
  flow_control.record_received(r, 161) |> should.equal(Error(Nil))
}
