// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Stream Manager Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import gleeunit/should

import aether/protocol/http2/error.{Cancel}
import aether/protocol/http2/frame.{default_initial_window_size}
import aether/protocol/http2/stream.{
  Closed, HalfClosedLocal, Idle, Open, SendEndStream, SendRstStream,
}
import aether/protocol/http2/stream_manager.{Client, Server}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Manager Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_client_manager_test() {
  let manager = stream_manager.new_client()

  manager.role |> should.equal(Client)
  manager.next_stream_id |> should.equal(1)
  // Client starts with odd IDs
  manager.active_stream_count |> should.equal(0)
  manager.going_away |> should.equal(False)
}

pub fn new_server_manager_test() {
  let manager = stream_manager.new_server()

  manager.role |> should.equal(Server)
  manager.next_stream_id |> should.equal(2)
  // Server starts with even IDs
  manager.active_stream_count |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn create_stream_client_test() {
  let manager = stream_manager.new_client()

  let result = stream_manager.create_stream(manager)
  result |> should.be_ok()

  case result {
    Ok(#(updated_manager, stream)) -> {
      stream.id |> should.equal(1)
      // First client stream is 1
      stream.state |> should.equal(Open)
      // Stream is opened
      updated_manager.next_stream_id |> should.equal(3)
      // Next will be 3
      updated_manager.active_stream_count |> should.equal(1)
    }
    Error(_) -> panic
  }
}

pub fn create_stream_server_test() {
  let manager = stream_manager.new_server()

  let result = stream_manager.create_stream(manager)
  result |> should.be_ok()

  case result {
    Ok(#(updated_manager, stream)) -> {
      stream.id |> should.equal(2)
      // First server stream is 2
      updated_manager.next_stream_id |> should.equal(4)
      // Next will be 4
    }
    Error(_) -> panic
  }
}

pub fn create_multiple_streams_test() {
  let manager = stream_manager.new_client()

  // Create first stream
  let #(manager1, stream1) =
    stream_manager.create_stream(manager)
    |> should.be_ok()
  stream1.id |> should.equal(1)

  // Create second stream
  let #(manager2, stream2) =
    stream_manager.create_stream(manager1)
    |> should.be_ok()
  stream2.id |> should.equal(3)

  // Create third stream
  let #(manager3, stream3) =
    stream_manager.create_stream(manager2)
    |> should.be_ok()
  stream3.id |> should.equal(5)

  manager3.active_stream_count |> should.equal(3)
  manager3.next_stream_id |> should.equal(7)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Concurrent Stream Limit Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn max_concurrent_streams_limit_test() {
  let manager = stream_manager.new_client()

  // Set very low concurrent stream limit
  let limited_manager = stream_manager.update_max_concurrent_streams(manager, 2)

  // Create first two streams - should succeed
  let #(m1, _) = stream_manager.create_stream(limited_manager) |> should.be_ok()
  let #(m2, _) = stream_manager.create_stream(m1) |> should.be_ok()

  m2.active_stream_count |> should.equal(2)

  // Third stream should fail
  stream_manager.create_stream(m2) |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Peer Stream Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn get_or_create_peer_stream_server_test() {
  // Server receives client-initiated stream (odd ID)
  let manager = stream_manager.new_server()

  let result = stream_manager.get_or_create_peer_stream(manager, 1)
  result |> should.be_ok()

  case result {
    Ok(#(updated_manager, stream)) -> {
      stream.id |> should.equal(1)
      stream.state |> should.equal(Idle)
      // New peer stream starts Idle
      updated_manager.highest_peer_stream_id |> should.equal(1)
      updated_manager.active_stream_count |> should.equal(1)
    }
    Error(_) -> panic
  }
}

pub fn get_or_create_peer_stream_client_test() {
  // Client receives server-initiated stream (even ID, via PUSH_PROMISE)
  let manager = stream_manager.new_client()

  let result = stream_manager.get_or_create_peer_stream(manager, 2)
  result |> should.be_ok()

  case result {
    Ok(#(updated_manager, stream)) -> {
      stream.id |> should.equal(2)
      updated_manager.highest_peer_stream_id |> should.equal(2)
    }
    Error(_) -> panic
  }
}

pub fn get_or_create_peer_stream_invalid_parity_test() {
  // Server should reject even-numbered streams from peer (those are server-initiated)
  let manager = stream_manager.new_server()

  let result = stream_manager.get_or_create_peer_stream(manager, 2)
  result |> should.be_error()
}

pub fn get_existing_peer_stream_test() {
  let manager = stream_manager.new_server()

  // Create stream
  let #(m1, s1) =
    stream_manager.get_or_create_peer_stream(manager, 1)
    |> should.be_ok()

  // Get same stream again
  let #(m2, s2) =
    stream_manager.get_or_create_peer_stream(m1, 1)
    |> should.be_ok()

  s1.id |> should.equal(s2.id)
  // Active count shouldn't double
  m2.active_stream_count |> should.equal(1)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Lookup Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn get_stream_test() {
  let manager = stream_manager.new_client()
  let #(m1, s1) = stream_manager.create_stream(manager) |> should.be_ok()

  let found = stream_manager.get_stream(m1, 1)
  found |> should.be_ok()

  case found {
    Ok(s) -> s.id |> should.equal(s1.id)
    Error(_) -> panic
  }
}

pub fn get_stream_not_found_test() {
  let manager = stream_manager.new_client()

  stream_manager.get_stream(manager, 999) |> should.be_error()
}

pub fn has_stream_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()

  stream_manager.has_stream(m1, 1) |> should.equal(True)
  stream_manager.has_stream(m1, 3) |> should.equal(False)
}

pub fn get_active_streams_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()
  let #(m2, _) = stream_manager.create_stream(m1) |> should.be_ok()

  let active = stream_manager.get_active_streams(m2)
  active |> should.not_equal([])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream State Transition Tests (via Manager)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn apply_stream_event_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()

  // Stream is now Open, close it with SendEndStream
  let result = stream_manager.apply_stream_event(m1, 1, SendEndStream)
  result |> should.be_ok()

  case result {
    Ok(m2) -> {
      let s = stream_manager.get_stream(m2, 1) |> should.be_ok()
      s.state |> should.equal(HalfClosedLocal)
    }
    Error(_) -> panic
  }
}

pub fn apply_stream_event_not_found_test() {
  let manager = stream_manager.new_client()

  stream_manager.apply_stream_event(manager, 999, SendEndStream)
  |> should.be_error()
}

pub fn stream_close_decrements_active_count_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()

  m1.active_stream_count |> should.equal(1)

  // Close the stream with RST_STREAM
  let m2 =
    stream_manager.apply_stream_event(m1, 1, SendRstStream)
    |> should.be_ok()

  m2.active_stream_count |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RST_STREAM Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn reset_stream_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()

  let result = stream_manager.reset_stream(m1, 1, Cancel)
  result |> should.be_ok()

  case result {
    Ok(m2) -> {
      let s = stream_manager.get_stream(m2, 1) |> should.be_ok()
      s.state |> should.equal(Closed)
      s.reset |> should.equal(True)
      m2.active_stream_count |> should.equal(0)
    }
    Error(_) -> panic
  }
}

pub fn handle_rst_stream_test() {
  let manager = stream_manager.new_server()
  let #(m1, _) =
    stream_manager.get_or_create_peer_stream(manager, 1)
    |> should.be_ok()

  // Handle RST_STREAM from peer
  let result = stream_manager.handle_rst_stream(m1, 1, Cancel)
  result |> should.be_ok()

  case result {
    Ok(m2) -> {
      let s = stream_manager.get_stream(m2, 1) |> should.be_ok()
      s.reset |> should.equal(True)
    }
    Error(_) -> panic
  }
}

pub fn handle_rst_stream_unknown_stream_test() {
  // RST_STREAM for unknown stream should be OK (stream might have been cleaned up)
  let manager = stream_manager.new_server()

  stream_manager.handle_rst_stream(manager, 999, Cancel)
  |> should.be_ok()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Settings Update Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn update_initial_window_size_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()

  // Check initial window
  let s1 = stream_manager.get_stream(m1, 1) |> should.be_ok()
  s1.send_window |> should.equal(default_initial_window_size)

  // Update window size (increase by 10000)
  let new_size = default_initial_window_size + 10_000
  let result = stream_manager.update_initial_window_size(m1, new_size)
  result |> should.be_ok()

  case result {
    Ok(m2) -> {
      let s2 = stream_manager.get_stream(m2, 1) |> should.be_ok()
      // Window should have increased by 10000
      s2.send_window |> should.equal(default_initial_window_size + 10_000)
    }
    Error(_) -> panic
  }
}

pub fn update_initial_window_size_overflow_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()

  // Try to set window size that would overflow
  let result =
    stream_manager.update_initial_window_size(m1, 2_147_483_647 + 100)
  result |> should.be_error()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GOAWAY Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn initiate_goaway_test() {
  let manager = stream_manager.new_client()

  stream_manager.is_going_away(manager) |> should.equal(False)

  let goaway_manager = stream_manager.initiate_goaway(manager)
  stream_manager.is_going_away(goaway_manager) |> should.equal(True)
}

pub fn no_new_streams_after_goaway_test() {
  let manager =
    stream_manager.new_client()
    |> stream_manager.initiate_goaway()

  // Cannot create new streams after GOAWAY
  stream_manager.create_stream(manager) |> should.be_error()
}

pub fn handle_goaway_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()
  let #(m2, _) = stream_manager.create_stream(m1) |> should.be_ok()

  // Handle GOAWAY with last_stream_id = 1
  let m3 = stream_manager.handle_goaway(m2, 1)

  m3.going_away |> should.equal(True)
  stream_manager.get_last_stream_id(m3) |> should.equal(1)
}

pub fn get_last_stream_id_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()
  let #(m2, _) = stream_manager.create_stream(m1) |> should.be_ok()

  // Last stream created was ID 3
  stream_manager.get_last_stream_id(m2) |> should.equal(3)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Cleanup Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn cleanup_closed_streams_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()
  let #(m2, _) = stream_manager.create_stream(m1) |> should.be_ok()

  // Close first stream
  let m3 = stream_manager.reset_stream(m2, 1, Cancel) |> should.be_ok()

  stream_manager.total_count(m3) |> should.equal(2)
  // Both streams still in map

  // Cleanup, keep 0 closed streams
  let m4 = stream_manager.cleanup_closed_streams(m3, 0)

  stream_manager.total_count(m4) |> should.equal(1)
  // Only active stream remains
  stream_manager.has_stream(m4, 1) |> should.equal(False)
  // Closed stream removed
  stream_manager.has_stream(m4, 3) |> should.equal(True)
  // Active stream remains
}

pub fn purge_closed_streams_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()

  // Close the stream
  let m2 = stream_manager.reset_stream(m1, 1, Cancel) |> should.be_ok()

  stream_manager.total_count(m2) |> should.equal(1)

  let m3 = stream_manager.purge_closed_streams(m2)
  stream_manager.total_count(m3) |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flow Control Tests (via Manager)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn consume_stream_window_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()

  let result = stream_manager.consume_stream_window(m1, 1, 1000)
  result |> should.be_ok()

  case result {
    Ok(m2) -> {
      let s = stream_manager.get_stream(m2, 1) |> should.be_ok()
      s.send_window |> should.equal(default_initial_window_size - 1000)
    }
    Error(_) -> panic
  }
}

pub fn increment_stream_window_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()

  // Consume some window first
  let m2 = stream_manager.consume_stream_window(m1, 1, 10_000) |> should.be_ok()

  // Then receive WINDOW_UPDATE
  let result = stream_manager.increment_stream_window(m2, 1, 5000)
  result |> should.be_ok()

  case result {
    Ok(m3) -> {
      let s = stream_manager.get_stream(m3, 1) |> should.be_ok()
      s.send_window |> should.equal(default_initial_window_size - 10_000 + 5000)
    }
    Error(_) -> panic
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Statistics Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn active_count_test() {
  let manager = stream_manager.new_client()
  stream_manager.active_count(manager) |> should.equal(0)

  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()
  stream_manager.active_count(m1) |> should.equal(1)

  let #(m2, _) = stream_manager.create_stream(m1) |> should.be_ok()
  stream_manager.active_count(m2) |> should.equal(2)

  let m3 = stream_manager.reset_stream(m2, 1, Cancel) |> should.be_ok()
  stream_manager.active_count(m3) |> should.equal(1)
}

pub fn total_count_test() {
  let manager = stream_manager.new_client()
  stream_manager.total_count(manager) |> should.equal(0)

  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()
  stream_manager.total_count(m1) |> should.equal(1)

  let m2 = stream_manager.reset_stream(m1, 1, Cancel) |> should.be_ok()
  // Closed streams still count until cleaned up
  stream_manager.total_count(m2) |> should.equal(1)
}

pub fn get_streams_by_state_test() {
  let manager = stream_manager.new_client()
  let #(m1, _) = stream_manager.create_stream(manager) |> should.be_ok()
  let #(m2, _) = stream_manager.create_stream(m1) |> should.be_ok()

  // Close one stream
  let m3 = stream_manager.reset_stream(m2, 1, Cancel) |> should.be_ok()

  let open_streams = stream_manager.get_streams_by_state(m3, Open)
  let closed_streams = stream_manager.get_streams_by_state(m3, Closed)

  // Should have 1 open, 1 closed
  open_streams |> should.not_equal([])
  closed_streams |> should.not_equal([])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// String Conversion Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn role_to_string_test() {
  stream_manager.role_to_string(Client) |> should.equal("client")
  stream_manager.role_to_string(Server) |> should.equal("server")
}

pub fn to_string_test() {
  let manager = stream_manager.new_client()
  let s = stream_manager.to_string(manager)

  // Should contain key information
  s |> should.not_equal("")
}
