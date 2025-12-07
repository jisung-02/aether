import aether/protocol/tcp/header
import aether/protocol/tcp/state
import gleam/result
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_listener_state_test() {
  let conn = state.new_listener(8080)

  conn.state |> should.equal(state.Listen)
  conn.local_port |> should.equal(8080)
  conn.remote_port |> should.equal(0)
  conn.local_window |> should.equal(65_535)
}

pub fn new_client_state_test() {
  let conn = state.new_client(12_345, 80)

  conn.state |> should.equal(state.Closed)
  conn.local_port |> should.equal(12_345)
  conn.remote_port |> should.equal(80)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Server-side Handshake Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn handle_syn_in_listen_test() {
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)

  conn.state |> should.equal(state.SynReceived)
  conn.remote_port |> should.equal(12_345)
  conn.remote_seq |> should.equal(1001)
  // remote_seq + 1
  conn.initial_remote_seq |> should.equal(1000)
  conn.remote_window |> should.equal(65_535)
}

pub fn handle_ack_in_syn_received_test() {
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)

  // The ACK should acknowledge our SYN (initial_local_seq + 1)
  let expected_ack = conn.initial_local_seq + 1
  let assert Ok(conn) = state.handle_ack(conn, expected_ack)

  conn.state |> should.equal(state.Established)
}

pub fn complete_server_handshake_test() {
  let conn = state.new_listener(8080)

  // Step 1: Receive SYN
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  conn.state |> should.equal(state.SynReceived)

  // Step 2: Receive ACK (completing handshake)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)
  conn.state |> should.equal(state.Established)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Client-side Handshake Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn initiate_connection_from_closed_test() {
  let conn = state.new_client(12_345, 80)
  let assert Ok(conn) = state.initiate_connection(conn)

  conn.state |> should.equal(state.SynSent)
}

pub fn handle_syn_ack_in_syn_sent_test() {
  let conn = state.new_client(12_345, 80)
  let assert Ok(conn) = state.initiate_connection(conn)

  // Server responds with SYN-ACK, acknowledging our SYN
  let assert Ok(conn) =
    state.handle_syn_ack(
      conn,
      5000,
      // Server's sequence number
      conn.initial_local_seq + 1,
      // ACK of our SYN
      32_768,
      // Server's window
    )

  conn.state |> should.equal(state.Established)
  conn.remote_seq |> should.equal(5001)
  // Server's seq + 1
  conn.initial_remote_seq |> should.equal(5000)
  conn.remote_window |> should.equal(32_768)
}

pub fn complete_client_handshake_test() {
  let conn = state.new_client(12_345, 80)

  // Step 1: Send SYN
  let assert Ok(conn) = state.initiate_connection(conn)
  conn.state |> should.equal(state.SynSent)

  // Step 2: Receive SYN-ACK
  let assert Ok(conn) =
    state.handle_syn_ack(conn, 5000, conn.initial_local_seq + 1, 65_535)
  conn.state |> should.equal(state.Established)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Invalid State Transition Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn handle_syn_in_established_fails_test() {
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)

  // Cannot handle SYN in Established state
  state.handle_syn(conn, 9999, 5000, 32_768)
  |> result.is_error()
  |> should.be_true()
}

pub fn handle_syn_ack_in_listen_fails_test() {
  let conn = state.new_listener(8080)

  // Cannot handle SYN-ACK in Listen state
  state.handle_syn_ack(conn, 5000, 1000, 65_535)
  |> result.is_error()
  |> should.be_true()
}

pub fn initiate_connection_in_listen_fails_test() {
  let conn = state.new_listener(8080)

  // Cannot initiate connection from Listen state
  state.initiate_connection(conn)
  |> result.is_error()
  |> should.be_true()
}

pub fn invalid_ack_number_fails_test() {
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)

  // Wrong ACK number
  state.handle_ack(conn, 99_999)
  |> result.is_error()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Termination Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn handle_fin_in_established_test() {
  // Create established connection
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)

  // Receive FIN
  let assert Ok(conn) = state.handle_fin(conn)

  conn.state |> should.equal(state.CloseWait)
}

pub fn close_connection_from_established_test() {
  // Create established connection
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)

  // Initiate close
  let assert Ok(conn) = state.close_connection(conn)

  conn.state |> should.equal(state.FinWait1)
}

pub fn close_connection_from_close_wait_test() {
  // Create established connection
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)

  // Receive FIN (goes to CloseWait)
  let assert Ok(conn) = state.handle_fin(conn)

  // Send our FIN (goes to LastAck)
  let assert Ok(conn) = state.close_connection(conn)

  conn.state |> should.equal(state.LastAck)
}

pub fn handle_rst_closes_connection_test() {
  // Create established connection
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)

  // Receive RST
  let assert Ok(conn) = state.handle_rst(conn)

  conn.state |> should.equal(state.Closed)
}

pub fn time_wait_expired_test() {
  // Simulate getting to TimeWait state
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)
  let assert Ok(conn) = state.close_connection(conn)
  // -> FinWait1
  let assert Ok(conn) = state.handle_fin(conn)
  // -> Closing

  // Simulate ACK of our FIN
  let conn = state.TcpConnection(..conn, state: state.TimeWait)

  // TimeWait expires
  let assert Ok(conn) = state.time_wait_expired(conn)

  conn.state |> should.equal(state.Closed)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Data Transfer Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn data_sent_updates_sequence_test() {
  // Create established connection
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)

  let original_seq = conn.local_seq

  // Send 100 bytes
  let assert Ok(conn) = state.data_sent(conn, 100)

  conn.local_seq |> should.equal(original_seq + 100)
}

pub fn data_received_updates_ack_test() {
  // Create established connection
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)

  let original_remote_seq = conn.remote_seq

  // Receive 50 bytes
  let assert Ok(conn) = state.data_received(conn, 50)

  conn.remote_seq |> should.equal(original_remote_seq + 50)
}

pub fn data_sent_in_closed_fails_test() {
  let conn = state.new_client(12_345, 80)

  state.data_sent(conn, 100)
  |> result.is_error()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Window Management Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn update_remote_window_test() {
  let conn = state.new_listener(8080)
  let conn = state.update_remote_window(conn, 32_768)

  conn.remote_window |> should.equal(32_768)
}

pub fn update_local_window_test() {
  let conn = state.new_listener(8080)
  let conn = state.update_local_window(conn, 16_384)

  conn.local_window |> should.equal(16_384)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Processing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn process_syn_header_test() {
  let conn = state.new_listener(8080)

  let syn_hdr =
    header.with_flags(12_345, 8080, header.syn_flags())
    |> header.set_sequence_number(1000)
    |> header.set_window_size(65_535)

  let assert Ok(conn) = state.process_header(conn, syn_hdr)

  conn.state |> should.equal(state.SynReceived)
}

pub fn process_rst_header_test() {
  // Create established connection
  let conn = state.new_listener(8080)
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)

  let rst_hdr = header.with_flags(12_345, 8080, header.rst_flags())

  let assert Ok(conn) = state.process_header(conn, rst_hdr)

  conn.state |> should.equal(state.Closed)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Function Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn state_name_test() {
  state.state_name(state.Closed) |> should.equal("Closed")
  state.state_name(state.Listen) |> should.equal("Listen")
  state.state_name(state.SynSent) |> should.equal("SynSent")
  state.state_name(state.SynReceived) |> should.equal("SynReceived")
  state.state_name(state.Established) |> should.equal("Established")
  state.state_name(state.FinWait1) |> should.equal("FinWait1")
  state.state_name(state.FinWait2) |> should.equal("FinWait2")
  state.state_name(state.CloseWait) |> should.equal("CloseWait")
  state.state_name(state.Closing) |> should.equal("Closing")
  state.state_name(state.LastAck) |> should.equal("LastAck")
  state.state_name(state.TimeWait) |> should.equal("TimeWait")
}

pub fn can_send_data_test() {
  let conn = state.new_listener(8080)
  state.can_send_data(conn) |> should.be_false()

  // Create established connection
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  state.can_send_data(conn) |> should.be_false()

  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)
  state.can_send_data(conn) |> should.be_true()
}

pub fn can_receive_data_test() {
  let conn = state.new_listener(8080)
  state.can_receive_data(conn) |> should.be_false()

  // Create established connection
  let assert Ok(conn) = state.handle_syn(conn, 12_345, 1000, 65_535)
  let assert Ok(conn) = state.handle_ack(conn, conn.initial_local_seq + 1)
  state.can_receive_data(conn) |> should.be_true()
}

pub fn error_to_string_test() {
  let err =
    state.InvalidStateTransition(
      current_state: state.Listen,
      message: "test error",
    )
  let msg = state.error_to_string(err)

  { msg != "" } |> should.be_true()
}
