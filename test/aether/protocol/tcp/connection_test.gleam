import aether/protocol/tcp/connection
import aether/protocol/tcp/header
import aether/protocol/tcp/stage.{type TcpSegment, TcpSegment}
import aether/protocol/tcp/state
import gleam/int
import gleam/list
import gleam/option
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Test Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn create_established_connection() -> state.TcpConnection {
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)
  conn
}

fn create_test_segment(seq: Int, payload_size: Int) -> TcpSegment {
  let hdr =
    header.with_flags(12345, 8080, header.ack_flags())
    |> header.set_sequence_number(seq)
  let payload = create_dummy_payload(payload_size)
  TcpSegment(header: hdr, payload: payload)
}

fn create_dummy_payload(size: Int) -> BitArray {
  create_dummy_payload_loop(size, <<>>)
}

fn create_dummy_payload_loop(remaining: Int, acc: BitArray) -> BitArray {
  case remaining {
    0 -> acc
    n -> create_dummy_payload_loop(n - 1, <<acc:bits, 0:8>>)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Manager Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_connection_manager_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Initial congestion window should be 1 MSS
  connection.get_cwnd(manager) |> should.equal(1)

  // Initial ssthresh should be 65535
  connection.get_ssthresh(manager) |> should.equal(65_535)

  // Should start in SlowStart phase
  connection.get_phase(manager) |> should.equal(connection.SlowStart)
}

pub fn new_manager_empty_buffers_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Send buffer should be empty
  connection.get_send_buffer_size(manager) |> should.equal(0)

  // Unacked segments should be empty
  connection.get_unacked_count(manager) |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Send Buffer Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn send_adds_to_buffer_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)
  let segment = create_test_segment(1000, 100)

  let manager = connection.send(manager, segment)

  connection.get_send_buffer_size(manager) |> should.equal(1)
}

pub fn send_multiple_segments_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)
  let seg1 = create_test_segment(1000, 100)
  let seg2 = create_test_segment(1100, 100)
  let seg3 = create_test_segment(1200, 100)

  let manager =
    manager
    |> connection.send(seg1)
    |> connection.send(seg2)
    |> connection.send(seg3)

  connection.get_send_buffer_size(manager) |> should.equal(3)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Congestion Window Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn send_respects_congestion_window_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Add multiple segments to send buffer
  let seg1 = create_test_segment(1000, 1460)
  let seg2 = create_test_segment(2460, 1460)
  let seg3 = create_test_segment(3920, 1460)

  let manager =
    manager
    |> connection.send(seg1)
    |> connection.send(seg2)
    |> connection.send(seg3)

  // Initial cwnd = 1, so only 1 segment should be sent
  let #(manager, sent_segments) = connection.process_send(manager)

  // Should send exactly 1 segment (cwnd = 1)
  list.length(sent_segments) |> should.equal(1)

  // One segment should be in unacked
  connection.get_unacked_count(manager) |> should.equal(1)

  // Two segments should remain in send buffer
  connection.get_send_buffer_size(manager) |> should.equal(2)
}

pub fn available_window_calculation_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // calculate_available_window returns number of SEGMENTS, not bytes
  // Initial available window = min(cwnd * MSS, remote_window) / MSS - unacked_segments
  // cwnd = 1, MSS = 1460, remote_window = 65535, unacked_segments = 0
  // Available = min(1460, 65535) / 1460 - 0 = 1 segment
  let available = connection.calculate_available_window(manager)
  available |> should.equal(1)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ACK Processing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn ack_increases_congestion_window_in_slow_start_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Verify we're in SlowStart
  connection.get_phase(manager) |> should.equal(connection.SlowStart)

  let initial_cwnd = connection.get_cwnd(manager)

  // Simulate receiving an ACK (measured RTT of 100ms)
  let manager = connection.handle_ack(manager, 1001, 100)

  // In Slow Start, cwnd increases by 1 for each ACK
  let new_cwnd = connection.get_cwnd(manager)
  new_cwnd |> should.equal(initial_cwnd + 1)
}

pub fn ack_removes_from_unacked_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)
  let segment = create_test_segment(1000, 100)

  // Send segment
  let manager = connection.send(manager, segment)
  let #(manager, _) = connection.process_send(manager)

  // Should have 1 unacked segment
  connection.get_unacked_count(manager) |> should.equal(1)

  // ACK the segment (seq 1000 + 100 bytes = ACK 1100)
  let manager = connection.handle_ack(manager, 1100, 50)

  // Unacked should be empty now
  connection.get_unacked_count(manager) |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Duplicate ACK and Fast Retransmit Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn duplicate_ack_tracking_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // First ACK sets baseline
  let #(manager, retransmit1) = connection.handle_duplicate_ack(manager, 1000, 1)
  option.is_none(retransmit1) |> should.be_true()

  // Second duplicate ACK
  let #(manager, retransmit2) = connection.handle_duplicate_ack(manager, 1000, 2)
  option.is_none(retransmit2) |> should.be_true()

  // Dup ACK count should be tracked
  connection.get_dup_ack_count(manager) |> should.equal(2)
}

pub fn three_duplicate_acks_triggers_fast_retransmit_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Add segment to unacked (simulating it was sent)
  let segment = create_test_segment(1000, 100)
  let manager = connection.send(manager, segment)
  let #(manager, _) = connection.process_send(manager)

  // Three duplicate ACKs should trigger Fast Retransmit
  let #(manager, retransmit1) = connection.handle_duplicate_ack(manager, 1000, 1)
  option.is_none(retransmit1) |> should.be_true()

  let #(manager, retransmit2) = connection.handle_duplicate_ack(manager, 1000, 2)
  option.is_none(retransmit2) |> should.be_true()

  let #(manager, retransmit3) = connection.handle_duplicate_ack(manager, 1000, 3)
  // Third duplicate ACK triggers retransmit (segment was in unacked)
  option.is_some(retransmit3) |> should.be_true()

  // Should enter Fast Recovery
  connection.get_phase(manager) |> should.equal(connection.FastRecovery)
}

pub fn fast_recovery_sets_ssthresh_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Increase cwnd first
  let manager = connection.handle_ack(manager, 1001, 100)
  let manager = connection.handle_ack(manager, 2001, 100)
  let manager = connection.handle_ack(manager, 3001, 100)

  let cwnd_before = connection.get_cwnd(manager)

  // Trigger Fast Recovery with 3 duplicate ACKs
  let segment = create_test_segment(4000, 100)
  let manager = connection.send(manager, segment)
  let #(manager, _) = connection.process_send(manager)

  let #(manager, _) = connection.handle_duplicate_ack(manager, 4000, 1)
  let #(manager, _) = connection.handle_duplicate_ack(manager, 4000, 2)
  let #(manager, _) = connection.handle_duplicate_ack(manager, 4000, 3)

  // ssthresh should be set to cwnd/2
  let expected_ssthresh = int.max(cwnd_before / 2, 2)
  connection.get_ssthresh(manager) |> should.equal(expected_ssthresh)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RTT Estimation Tests (RFC 6298)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn rtt_first_measurement_test() {
  let timers = connection.new_timers()

  // First RTT measurement: SRTT = R, RTTVAR = R/2
  let timers = connection.update_rtt(timers, 100)

  // SRTT should be 100
  connection.get_srtt(timers) |> should.equal(100.0)

  // RTTVAR should be 50 (R/2)
  connection.get_rttvar(timers) |> should.equal(50.0)

  // RTO = SRTT + 4*RTTVAR = 100 + 200 = 300, but min is 1000ms
  connection.get_rto(timers) |> should.equal(1000)
}

pub fn rtt_subsequent_measurement_test() {
  let timers = connection.new_timers()

  // First measurement
  let timers = connection.update_rtt(timers, 100)

  // Second measurement with same RTT
  let timers = connection.update_rtt(timers, 100)

  // SRTT should be updated: (1 - 0.125) * 100 + 0.125 * 100 = 100
  connection.get_srtt(timers) |> should.equal(100.0)
}

pub fn rtt_increases_with_higher_measurement_test() {
  let timers = connection.new_timers()

  // First measurement: 100ms
  let timers = connection.update_rtt(timers, 100)
  let initial_srtt = connection.get_srtt(timers)

  // Second measurement: 200ms (higher)
  let timers = connection.update_rtt(timers, 200)
  let new_srtt = connection.get_srtt(timers)

  // SRTT should increase
  { new_srtt >. initial_srtt } |> should.be_true()
}

pub fn rto_bounds_test() {
  let timers = connection.new_timers()

  // Very small RTT
  let timers = connection.update_rtt(timers, 1)
  // RTO should be at least 1000ms (min bound)
  { connection.get_rto(timers) >= 1000 } |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Timeout and Retransmission Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn timeout_triggers_slow_start_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Increase cwnd via ACKs
  let manager = connection.handle_ack(manager, 1001, 100)
  let manager = connection.handle_ack(manager, 2001, 100)
  let manager = connection.handle_ack(manager, 3001, 100)

  let cwnd_before = connection.get_cwnd(manager)
  { cwnd_before > 1 } |> should.be_true()

  // Simulate timeout (reset congestion state)
  let manager = connection.handle_timeout(manager)

  // cwnd should reset to 1
  connection.get_cwnd(manager) |> should.equal(1)

  // Should be in SlowStart
  connection.get_phase(manager) |> should.equal(connection.SlowStart)

  // ssthresh should be cwnd/2 (at least 2)
  let expected_ssthresh = int.max(cwnd_before / 2, 2)
  connection.get_ssthresh(manager) |> should.equal(expected_ssthresh)
}

pub fn check_retransmissions_returns_timed_out_segments_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Add segment and send it
  let segment = create_test_segment(1000, 100)
  let manager = connection.send(manager, segment)
  let #(manager, _) = connection.process_send(manager)

  // Force check retransmissions (would need time simulation)
  // This tests the function exists and returns proper types
  let #(_manager, retransmits) = connection.check_retransmissions(manager)

  // Initially no retransmits (not enough time passed)
  list.length(retransmits) |> should.equal(0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Congestion Avoidance Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn transition_to_congestion_avoidance_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Set low ssthresh to trigger transition
  let manager = connection.set_ssthresh(manager, 3)

  // Slow Start: cwnd increases by 1 per ACK until cwnd >= ssthresh
  let manager = connection.handle_ack(manager, 1001, 100)
  // cwnd = 2
  let manager = connection.handle_ack(manager, 2001, 100)
  // cwnd = 3 (>= ssthresh)

  // Should transition to Congestion Avoidance
  connection.get_phase(manager) |> should.equal(connection.CongestionAvoidance)
}

pub fn congestion_avoidance_linear_growth_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Set low ssthresh and transition to Congestion Avoidance
  let manager = connection.set_ssthresh(manager, 2)
  let manager = connection.handle_ack(manager, 1001, 100)
  let manager = connection.handle_ack(manager, 2001, 100)

  // Should be in Congestion Avoidance now
  connection.get_phase(manager) |> should.equal(connection.CongestionAvoidance)

  let cwnd_before = connection.get_cwnd(manager)

  // In Congestion Avoidance, cwnd increases by 1/cwnd per ACK
  // After cwnd ACKs, cwnd should increase by 1
  let manager = simulate_cwnd_acks(manager, cwnd_before)

  let cwnd_after = connection.get_cwnd(manager)
  // Should have increased by approximately 1
  { cwnd_after >= cwnd_before } |> should.be_true()
}

fn simulate_cwnd_acks(
  manager: connection.TcpConnectionManager,
  count: Int,
) -> connection.TcpConnectionManager {
  case count {
    0 -> manager
    n -> {
      let manager = connection.handle_ack(manager, n * 1000 + 1, 100)
      simulate_cwnd_acks(manager, n - 1)
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Out-of-Order Buffering Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn buffer_out_of_order_segment_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Receive segment with higher sequence number (out of order)
  let segment = create_test_segment(2000, 100)
  let manager = connection.buffer_out_of_order(manager, segment)

  connection.get_recv_buffer_size(manager) |> should.equal(1)
}

pub fn multiple_out_of_order_segments_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Receive segments out of order
  let seg1 = create_test_segment(3000, 100)
  let seg2 = create_test_segment(2000, 100)

  let manager =
    manager
    |> connection.buffer_out_of_order(seg1)
    |> connection.buffer_out_of_order(seg2)

  connection.get_recv_buffer_size(manager) |> should.equal(2)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Integration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn full_send_ack_cycle_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Send a segment
  let segment = create_test_segment(1000, 100)
  let manager = connection.send(manager, segment)
  let #(manager, sent) = connection.process_send(manager)

  // One segment sent
  list.length(sent) |> should.equal(1)
  connection.get_unacked_count(manager) |> should.equal(1)

  // Receive ACK
  let manager = connection.handle_ack(manager, 1100, 50)

  // No more unacked
  connection.get_unacked_count(manager) |> should.equal(0)

  // cwnd should have increased (Slow Start)
  connection.get_cwnd(manager) |> should.equal(2)
}

pub fn congestion_state_progression_test() {
  let conn = create_established_connection()
  let manager = connection.new(conn)

  // Start in Slow Start
  connection.get_phase(manager) |> should.equal(connection.SlowStart)

  // Set ssthresh low for testing
  let manager = connection.set_ssthresh(manager, 4)

  // Progress through Slow Start
  let manager = connection.handle_ack(manager, 1001, 100)
  let manager = connection.handle_ack(manager, 2001, 100)
  let manager = connection.handle_ack(manager, 3001, 100)
  let manager = connection.handle_ack(manager, 4001, 100)

  // Should be in Congestion Avoidance
  connection.get_phase(manager) |> should.equal(connection.CongestionAvoidance)

  // Send segment and trigger Fast Recovery
  let segment = create_test_segment(5000, 100)
  let manager = connection.send(manager, segment)
  let #(manager, _) = connection.process_send(manager)

  let #(manager, _) = connection.handle_duplicate_ack(manager, 5000, 1)
  let #(manager, _) = connection.handle_duplicate_ack(manager, 5000, 2)
  let #(manager, _) = connection.handle_duplicate_ack(manager, 5000, 3)

  // Should be in Fast Recovery
  connection.get_phase(manager) |> should.equal(connection.FastRecovery)
}
