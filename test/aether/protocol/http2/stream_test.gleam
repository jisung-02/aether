// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Stream State Machine Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleeunit/should

import aether/protocol/http2/stream.{
  Closed, HalfClosedLocal, HalfClosedRemote, Idle, Open, RecvEndStream,
  RecvHeaders, RecvHeadersEndStream, RecvPushPromise, RecvRstStream,
  ReservedLocal, ReservedRemote, SendEndStream, SendHeaders,
  SendHeadersEndStream, SendPushPromise, SendRstStream, StreamPriority,
}
import aether/protocol/http2/error
import aether/protocol/http2/frame.{default_initial_window_size}
import gleam/option.{None, Some}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn stream_new_test() {
  let s = stream.new(1)
  
  s.id |> should.equal(1)
  s.state |> should.equal(Idle)
  s.send_window |> should.equal(default_initial_window_size)
  s.recv_window |> should.equal(default_initial_window_size)
  s.reset |> should.equal(False)
  s.reset_code |> should.equal(None)
}

pub fn stream_new_with_windows_test() {
  let s = stream.new_with_windows(3, 100_000, 50_000)
  
  s.id |> should.equal(3)
  s.send_window |> should.equal(100_000)
  s.recv_window |> should.equal(50_000)
}

pub fn stream_new_reserved_local_test() {
  let s = stream.new_reserved_local(2)
  
  s.id |> should.equal(2)
  s.state |> should.equal(ReservedLocal)
}

pub fn stream_new_reserved_remote_test() {
  let s = stream.new_reserved_remote(4)
  
  s.id |> should.equal(4)
  s.state |> should.equal(ReservedRemote)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// State Transition Tests - Idle State
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn idle_to_open_send_headers_test() {
  let s = stream.new(1)
  let result = stream.apply_event(s, SendHeaders)
  
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(Open)
    Error(_) -> panic
  }
}

pub fn idle_to_half_closed_local_send_headers_end_stream_test() {
  let s = stream.new(1)
  let result = stream.apply_event(s, SendHeadersEndStream)
  
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(HalfClosedLocal)
    Error(_) -> panic
  }
}

pub fn idle_to_open_recv_headers_test() {
  let s = stream.new(1)
  let result = stream.apply_event(s, RecvHeaders)
  
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(Open)
    Error(_) -> panic
  }
}

pub fn idle_to_half_closed_remote_recv_headers_end_stream_test() {
  let s = stream.new(1)
  let result = stream.apply_event(s, RecvHeadersEndStream)
  
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(HalfClosedRemote)
    Error(_) -> panic
  }
}

pub fn idle_to_reserved_local_test() {
  let s = stream.new(2)
  let result = stream.apply_event(s, SendPushPromise)
  
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(ReservedLocal)
    Error(_) -> panic
  }
}

pub fn idle_to_reserved_remote_test() {
  let s = stream.new(2)
  let result = stream.apply_event(s, RecvPushPromise)
  
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(ReservedRemote)
    Error(_) -> panic
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// State Transition Tests - Open State
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn open_to_half_closed_local_test() {
  let s = stream.new(1)
  let result = stream.apply_event(s, SendHeaders)
    |> should.be_ok()
  
  let result2 = stream.apply_event(result, SendEndStream)
  result2 |> should.be_ok()
  case result2 {
    Ok(updated) -> updated.state |> should.equal(HalfClosedLocal)
    Error(_) -> panic
  }
}

pub fn open_to_half_closed_remote_test() {
  let s = stream.new(1)
  let result = stream.apply_event(s, SendHeaders)
    |> should.be_ok()
  
  let result2 = stream.apply_event(result, RecvEndStream)
  result2 |> should.be_ok()
  case result2 {
    Ok(updated) -> updated.state |> should.equal(HalfClosedRemote)
    Error(_) -> panic
  }
}

pub fn open_to_closed_send_rst_test() {
  let s = stream.new(1)
  let open_stream = stream.apply_event(s, SendHeaders)
    |> should.be_ok()
  
  let result = stream.apply_event(open_stream, SendRstStream)
  result |> should.be_ok()
  case result {
    Ok(updated) -> {
      updated.state |> should.equal(Closed)
      updated.reset |> should.equal(True)
    }
    Error(_) -> panic
  }
}

pub fn open_to_closed_recv_rst_test() {
  let s = stream.new(1)
  let open_stream = stream.apply_event(s, SendHeaders)
    |> should.be_ok()
  
  let result = stream.apply_event(open_stream, RecvRstStream)
  result |> should.be_ok()
  case result {
    Ok(updated) -> {
      updated.state |> should.equal(Closed)
      updated.reset |> should.equal(True)
    }
    Error(_) -> panic
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// State Transition Tests - Half-Closed States
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn half_closed_local_to_closed_test() {
  let s = stream.new(1)
  let half_closed = s
    |> stream.apply_event(SendHeaders)
    |> should.be_ok()
    |> stream.apply_event(SendEndStream)
    |> should.be_ok()
  
  half_closed.state |> should.equal(HalfClosedLocal)
  
  let result = stream.apply_event(half_closed, RecvEndStream)
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(Closed)
    Error(_) -> panic
  }
}

pub fn half_closed_remote_to_closed_test() {
  let s = stream.new(1)
  let half_closed = s
    |> stream.apply_event(SendHeaders)
    |> should.be_ok()
    |> stream.apply_event(RecvEndStream)
    |> should.be_ok()
  
  half_closed.state |> should.equal(HalfClosedRemote)
  
  let result = stream.apply_event(half_closed, SendEndStream)
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(Closed)
    Error(_) -> panic
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// State Transition Tests - Reserved States
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn reserved_local_to_half_closed_remote_test() {
  let s = stream.new_reserved_local(2)
  let result = stream.apply_event(s, SendHeaders)
  
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(HalfClosedRemote)
    Error(_) -> panic
  }
}

pub fn reserved_remote_to_half_closed_local_test() {
  let s = stream.new_reserved_remote(2)
  let result = stream.apply_event(s, RecvHeaders)
  
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(HalfClosedLocal)
    Error(_) -> panic
  }
}

pub fn reserved_local_to_closed_rst_test() {
  let s = stream.new_reserved_local(2)
  let result = stream.apply_event(s, SendRstStream)
  
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.state |> should.equal(Closed)
    Error(_) -> panic
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Invalid Transition Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn closed_state_no_transitions_test() {
  let s = stream.new(1)
  let closed_stream = s
    |> stream.apply_event(SendHeaders)
    |> should.be_ok()
    |> stream.apply_event(SendRstStream)
    |> should.be_ok()
  
  closed_stream.state |> should.equal(Closed)
  
  // Try various transitions - all should fail
  stream.apply_event(closed_stream, SendHeaders) |> should.be_error()
  stream.apply_event(closed_stream, RecvHeaders) |> should.be_error()
  stream.apply_event(closed_stream, SendEndStream) |> should.be_error()
}

pub fn invalid_transition_from_idle_test() {
  let s = stream.new(1)
  
  // Cannot send/recv END_STREAM directly from idle
  stream.apply_event(s, SendEndStream) |> should.be_error()
  stream.apply_event(s, RecvEndStream) |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// State Helper Function Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn can_send_test() {
  let idle = stream.new(1)
  let open = stream.apply_event(idle, SendHeaders) |> should.be_ok()
  let half_closed_local = stream.apply_event(open, SendEndStream) |> should.be_ok()
  let half_closed_remote = stream.apply_event(stream.new(1) |> stream.apply_event(SendHeaders) |> should.be_ok(), RecvEndStream) |> should.be_ok()
  
  stream.can_send(idle) |> should.equal(False)
  stream.can_send(open) |> should.equal(True)
  stream.can_send(half_closed_local) |> should.equal(False)
  stream.can_send(half_closed_remote) |> should.equal(True)
}

pub fn can_receive_test() {
  let idle = stream.new(1)
  let open = stream.apply_event(idle, SendHeaders) |> should.be_ok()
  let half_closed_local = stream.apply_event(open, SendEndStream) |> should.be_ok()
  
  stream.can_receive(idle) |> should.equal(False)
  stream.can_receive(open) |> should.equal(True)
  stream.can_receive(half_closed_local) |> should.equal(True)
}

pub fn is_active_test() {
  let idle = stream.new(1)
  let open = stream.apply_event(idle, SendHeaders) |> should.be_ok()
  let closed = stream.apply_event(open, SendRstStream) |> should.be_ok()
  
  stream.is_active(idle) |> should.equal(False)
  stream.is_active(open) |> should.equal(True)
  stream.is_active(closed) |> should.equal(False)
}

pub fn is_client_initiated_test() {
  stream.is_client_initiated(1) |> should.equal(True)
  stream.is_client_initiated(3) |> should.equal(True)
  stream.is_client_initiated(2) |> should.equal(False)
  stream.is_client_initiated(4) |> should.equal(False)
  stream.is_client_initiated(0) |> should.equal(False)
}

pub fn is_server_initiated_test() {
  stream.is_server_initiated(2) |> should.equal(True)
  stream.is_server_initiated(4) |> should.equal(True)
  stream.is_server_initiated(1) |> should.equal(False)
  stream.is_server_initiated(3) |> should.equal(False)
  stream.is_server_initiated(0) |> should.equal(False)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flow Control Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn consume_send_window_test() {
  let s = stream.new_with_windows(1, 1000, 1000)
  
  let result = stream.consume_send_window(s, 500)
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.send_window |> should.equal(500)
    Error(_) -> panic
  }
}

pub fn consume_send_window_insufficient_test() {
  let s = stream.new_with_windows(1, 100, 100)
  
  let result = stream.consume_send_window(s, 200)
  result |> should.be_error()
}

pub fn consume_recv_window_test() {
  let s = stream.new_with_windows(1, 1000, 1000)
  
  let result = stream.consume_recv_window(s, 300)
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.recv_window |> should.equal(700)
    Error(_) -> panic
  }
}

pub fn increment_send_window_test() {
  let s = stream.new_with_windows(1, 1000, 1000)
  
  let result = stream.increment_send_window(s, 500)
  result |> should.be_ok()
  case result {
    Ok(updated) -> updated.send_window |> should.equal(1500)
    Error(_) -> panic
  }
}

pub fn increment_send_window_overflow_test() {
  let s = stream.new_with_windows(1, 2_147_483_600, 1000)
  
  // This should overflow past 2^31-1
  let result = stream.increment_send_window(s, 100)
  result |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Priority Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn set_priority_test() {
  let s = stream.new(1)
  let priority = StreamPriority(dependency: 3, exclusive: True, weight: 32)
  
  let updated = stream.set_priority(s, priority)
  updated.priority.dependency |> should.equal(3)
  updated.priority.exclusive |> should.equal(True)
  updated.priority.weight |> should.equal(32)
}

pub fn set_weight_clamp_test() {
  let s = stream.new(1)
  
  // Weight should be clamped to 1-256
  let updated1 = stream.set_weight(s, 0)
  updated1.priority.weight |> should.equal(1)
  
  let updated2 = stream.set_weight(s, 300)
  updated2.priority.weight |> should.equal(256)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Reset Stream Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn reset_stream_test() {
  let s = stream.new(1)
    |> stream.apply_event(SendHeaders)
    |> should.be_ok()
  
  let reset = stream.reset_stream(s, error.Cancel)
  
  reset.state |> should.equal(Closed)
  reset.reset |> should.equal(True)
  reset.reset_code |> should.equal(Some(error.Cancel))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// String Conversion Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn state_to_string_test() {
  stream.state_to_string(Idle) |> should.equal("idle")
  stream.state_to_string(Open) |> should.equal("open")
  stream.state_to_string(Closed) |> should.equal("closed")
  stream.state_to_string(HalfClosedLocal) |> should.equal("half-closed (local)")
  stream.state_to_string(HalfClosedRemote) |> should.equal("half-closed (remote)")
  stream.state_to_string(ReservedLocal) |> should.equal("reserved (local)")
  stream.state_to_string(ReservedRemote) |> should.equal("reserved (remote)")
}

pub fn event_to_string_test() {
  stream.event_to_string(SendHeaders) |> should.equal("send HEADERS")
  stream.event_to_string(RecvEndStream) |> should.equal("recv END_STREAM")
  stream.event_to_string(SendRstStream) |> should.equal("send RST_STREAM")
}
