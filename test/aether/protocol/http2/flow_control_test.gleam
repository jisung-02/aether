// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Flow Control Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleeunit/should
import gleam/option.{None, Some}

import aether/protocol/http2/flow_control.{
  Blocked, CanSendAll, CanSendPartial, max_window_size,
}
import aether/protocol/http2/frame.{default_initial_window_size}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Window Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_window_test() {
  let window = flow_control.new_window()
  flow_control.window_available(window) |> should.equal(default_initial_window_size)
}

pub fn new_window_with_size_test() {
  let window = flow_control.new_window_with_size(100_000)
  flow_control.window_available(window) |> should.equal(100_000)
}

pub fn window_has_capacity_test() {
  let window = flow_control.new_window()
  flow_control.window_has_capacity(window) |> should.equal(True)
  
  let zero_window = flow_control.new_window_with_size(0)
  flow_control.window_has_capacity(zero_window) |> should.equal(False)
}

pub fn window_consume_test() {
  let window = flow_control.new_window_with_size(1000)
  
  let result = flow_control.window_consume(window, 400)
  result |> should.be_ok()
  
  case result {
    Ok(updated) -> flow_control.window_available(updated) |> should.equal(600)
    Error(_) -> panic
  }
}

pub fn window_consume_exact_test() {
  let window = flow_control.new_window_with_size(1000)
  
  let result = flow_control.window_consume(window, 1000)
  result |> should.be_ok()
  
  case result {
    Ok(updated) -> flow_control.window_available(updated) |> should.equal(0)
    Error(_) -> panic
  }
}

pub fn window_consume_insufficient_test() {
  let window = flow_control.new_window_with_size(100)
  
  let result = flow_control.window_consume(window, 200)
  result |> should.be_error()
}

pub fn window_consume_zero_test() {
  let window = flow_control.new_window()
  
  let result = flow_control.window_consume(window, 0)
  result |> should.be_error()
}

pub fn window_increment_test() {
  let window = flow_control.new_window_with_size(1000)
  
  let result = flow_control.window_increment(window, 500)
  result |> should.be_ok()
  
  case result {
    Ok(updated) -> flow_control.window_available(updated) |> should.equal(1500)
    Error(_) -> panic
  }
}

pub fn window_increment_overflow_test() {
  let window = flow_control.new_window_with_size(max_window_size - 10)
  
  // Try to increment beyond max
  let result = flow_control.window_increment(window, 100)
  result |> should.be_error()
}

pub fn window_increment_zero_test() {
  let window = flow_control.new_window()
  
  // Zero increment is a protocol error
  let result = flow_control.window_increment(window, 0)
  result |> should.be_error()
}

pub fn window_increment_negative_test() {
  let window = flow_control.new_window()
  
  let result = flow_control.window_increment(window, -100)
  result |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flow Controller Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_controller_test() {
  let controller = flow_control.new()
  
  flow_control.connection_send_capacity(controller)
    |> should.equal(default_initial_window_size)
  flow_control.connection_recv_capacity(controller)
    |> should.equal(default_initial_window_size)
  flow_control.initial_stream_window_size(controller)
    |> should.equal(default_initial_window_size)
}

pub fn new_controller_with_window_size_test() {
  let controller = flow_control.new_with_window_size(100_000)
  
  flow_control.connection_send_capacity(controller) |> should.equal(100_000)
  flow_control.connection_recv_capacity(controller) |> should.equal(100_000)
  flow_control.initial_stream_window_size(controller) |> should.equal(100_000)
}

pub fn can_send_data_test() {
  let controller = flow_control.new()
  flow_control.can_send_data(controller) |> should.equal(True)
  
  let empty_controller = flow_control.new_with_window_size(0)
  flow_control.can_send_data(empty_controller) |> should.equal(False)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection-Level Flow Control Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn consume_send_window_test() {
  let controller = flow_control.new()
  
  let result = flow_control.consume_send_window(controller, 1000)
  result |> should.be_ok()
  
  case result {
    Ok(updated) -> 
      flow_control.connection_send_capacity(updated)
        |> should.equal(default_initial_window_size - 1000)
    Error(_) -> panic
  }
}

pub fn consume_send_window_insufficient_test() {
  let controller = flow_control.new_with_window_size(100)
  
  let result = flow_control.consume_send_window(controller, 200)
  result |> should.be_error()
}

pub fn consume_recv_window_test() {
  let controller = flow_control.new()
  
  let result = flow_control.consume_recv_window(controller, 1000)
  result |> should.be_ok()
  
  case result {
    Ok(updated) ->
      flow_control.connection_recv_capacity(updated)
        |> should.equal(default_initial_window_size - 1000)
    Error(_) -> panic
  }
}

pub fn handle_connection_window_update_test() {
  let controller = flow_control.new()
  
  // Consume some window first
  let consumed = flow_control.consume_send_window(controller, 10_000)
    |> should.be_ok()
  
  flow_control.connection_send_capacity(consumed)
    |> should.equal(default_initial_window_size - 10_000)
  
  // Receive WINDOW_UPDATE
  let result = flow_control.handle_connection_window_update(consumed, 5000)
  result |> should.be_ok()
  
  case result {
    Ok(updated) ->
      flow_control.connection_send_capacity(updated)
        |> should.equal(default_initial_window_size - 10_000 + 5000)
    Error(_) -> panic
  }
}

pub fn handle_connection_window_update_zero_test() {
  let controller = flow_control.new()
  
  // Zero increment is a protocol error
  let result = flow_control.handle_connection_window_update(controller, 0)
  result |> should.be_error()
}

pub fn handle_connection_window_update_overflow_test() {
  let controller = flow_control.new_with_window_size(max_window_size - 10)
  
  // Would overflow
  let result = flow_control.handle_connection_window_update(controller, 100)
  result |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream-Level Integration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn max_sendable_bytes_conn_limited_test() {
  let controller = flow_control.new_with_window_size(1000)
  let stream_window = 5000
  
  // Connection window is limiting
  flow_control.max_sendable_bytes(controller, stream_window)
    |> should.equal(1000)
}

pub fn max_sendable_bytes_stream_limited_test() {
  let controller = flow_control.new()  // 65535
  let stream_window = 1000
  
  // Stream window is limiting
  flow_control.max_sendable_bytes(controller, stream_window)
    |> should.equal(1000)
}

pub fn max_sendable_bytes_equal_test() {
  let controller = flow_control.new_with_window_size(2000)
  let stream_window = 2000
  
  flow_control.max_sendable_bytes(controller, stream_window)
    |> should.equal(2000)
}

pub fn can_send_bytes_test() {
  let controller = flow_control.new_with_window_size(1000)
  
  flow_control.can_send_bytes(controller, 500, 100) |> should.equal(True)
  flow_control.can_send_bytes(controller, 500, 500) |> should.equal(True)
  flow_control.can_send_bytes(controller, 500, 600) |> should.equal(False)
  flow_control.can_send_bytes(controller, 2000, 1500) |> should.equal(False)
}

pub fn validate_stream_window_update_test() {
  let result = flow_control.validate_stream_window_update(1000, 1)
  result |> should.be_ok()
  
  case result {
    Ok(increment) -> increment |> should.equal(1000)
    Error(_) -> panic
  }
}

pub fn validate_stream_window_update_zero_test() {
  let result = flow_control.validate_stream_window_update(0, 1)
  result |> should.be_error()
}

pub fn validate_stream_window_update_negative_test() {
  let result = flow_control.validate_stream_window_update(-100, 1)
  result |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Settings Update Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn update_initial_window_size_test() {
  let controller = flow_control.new()
  
  let result = flow_control.update_initial_window_size(controller, 100_000)
  result |> should.be_ok()
  
  case result {
    Ok(updated) ->
      flow_control.initial_stream_window_size(updated) |> should.equal(100_000)
    Error(_) -> panic
  }
}

pub fn update_initial_window_size_overflow_test() {
  let controller = flow_control.new()
  
  let result = flow_control.update_initial_window_size(controller, max_window_size + 1)
  result |> should.be_error()
}

pub fn update_initial_window_size_negative_test() {
  let controller = flow_control.new()
  
  let result = flow_control.update_initial_window_size(controller, -100)
  result |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Send Result Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn prepare_send_can_send_all_test() {
  let controller = flow_control.new()
  
  let result = flow_control.prepare_send(controller, 10_000, 5000)
  result |> should.equal(CanSendAll)
}

pub fn prepare_send_partial_test() {
  let controller = flow_control.new_with_window_size(1000)
  
  // Want to send 5000 but only 1000 available
  let result = flow_control.prepare_send(controller, 10_000, 5000)
  result |> should.equal(CanSendPartial(1000))
}

pub fn prepare_send_stream_limited_partial_test() {
  let controller = flow_control.new()  // 65535
  let stream_window = 500
  
  // Stream window limits to 500
  let result = flow_control.prepare_send(controller, stream_window, 1000)
  result |> should.equal(CanSendPartial(500))
}

pub fn prepare_send_blocked_test() {
  let controller = flow_control.new_with_window_size(0)
  
  let result = flow_control.prepare_send(controller, 10_000, 1000)
  result |> should.equal(Blocked)
}

pub fn prepare_send_blocked_by_stream_test() {
  let controller = flow_control.new()
  let stream_window = 0
  
  let result = flow_control.prepare_send(controller, stream_window, 1000)
  result |> should.equal(Blocked)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Pending Window Update Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn flush_pending_window_update_none_test() {
  let controller = flow_control.new()
  
  let result = flow_control.flush_pending_window_update(controller)
  result |> should.be_ok()
  
  case result {
    Ok(#(_, pending)) -> {
      case pending {
        None -> Nil  // Expected
        Some(_) -> panic  // Should not have pending update
      }
    }
    Error(_) -> panic
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// String Conversion Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn to_string_test() {
  let controller = flow_control.new()
  let s = flow_control.to_string(controller)
  
  // Should contain key information
  s |> should.not_equal("")
}
