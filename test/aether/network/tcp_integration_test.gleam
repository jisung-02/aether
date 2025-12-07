// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Integration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// These tests verify actual TCP socket operations using localhost.
// They create real server/client connections to test the full stack.
//

import aether/network/socket_options
import aether/network/tcp
import gleam/erlang/process
import test_helper.{assert_equal, assert_ok}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Listen and Accept Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn tcp_listen_on_random_port_test() {
  let opts = socket_options.server_defaults()

  // Listen on port 0 to get a random available port
  let listen_socket = assert_ok(tcp.listen(0, opts))

  // Get the assigned port
  let port = assert_ok(tcp.get_port(listen_socket))

  // Port should be non-zero
  case port > 0 {
    True -> Nil
    False -> panic as "Expected non-zero port"
  }

  // Clean up
  let _ = tcp.close_listen(listen_socket)
  Nil
}

pub fn tcp_listen_on_specific_port_test() {
  let opts = socket_options.server_defaults()

  // Find an available port by listening on 0 first
  let temp_socket = assert_ok(tcp.listen(0, opts))
  let port = assert_ok(tcp.get_port(temp_socket))
  let _ = tcp.close_listen(temp_socket)

  // Small delay to ensure port is released
  process.sleep(50)

  // Now listen on that specific port
  let listen_socket = assert_ok(tcp.listen(port, opts))
  let actual_port = assert_ok(tcp.get_port(listen_socket))
  assert_equal(port, actual_port)

  // Clean up
  let _ = tcp.close_listen(listen_socket)
  Nil
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Connect and Send/Recv Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn tcp_echo_test() {
  let opts = socket_options.server_defaults()

  // Create server
  let listen_socket = assert_ok(tcp.listen(0, opts))
  let port = assert_ok(tcp.get_port(listen_socket))

  // Connect client
  let client_opts = socket_options.tcp_defaults()
  let client = assert_ok(tcp.connect("127.0.0.1", port, client_opts))

  // Accept connection on server side
  let server_conn = assert_ok(tcp.accept_timeout(listen_socket, 5000))

  // Send data from client
  let message = <<"Hello, TCP!">>
  let _ = assert_ok(tcp.send(client, message))

  // Receive on server
  let received = assert_ok(tcp.recv_timeout(server_conn, 0, 5000))
  assert_equal(message, received)

  // Echo back
  let _ = assert_ok(tcp.send(server_conn, received))

  // Receive echo on client
  let echoed = assert_ok(tcp.recv_timeout(client, 0, 5000))
  assert_equal(message, echoed)

  // Clean up
  let _ = tcp.close(client)
  let _ = tcp.close(server_conn)
  let _ = tcp.close_listen(listen_socket)
  Nil
}

pub fn tcp_multiple_messages_test() {
  let opts = socket_options.server_defaults()

  // Create server
  let listen_socket = assert_ok(tcp.listen(0, opts))
  let port = assert_ok(tcp.get_port(listen_socket))

  // Connect client
  let client_opts = socket_options.tcp_defaults()
  let client = assert_ok(tcp.connect("127.0.0.1", port, client_opts))

  // Accept connection
  let server_conn = assert_ok(tcp.accept_timeout(listen_socket, 5000))

  // Send multiple messages
  let msg1 = <<"Message 1">>
  let msg2 = <<"Message 2">>
  let msg3 = <<"Message 3">>

  let _ = assert_ok(tcp.send(client, msg1))
  let _ = assert_ok(tcp.send(client, msg2))
  let _ = assert_ok(tcp.send(client, msg3))

  // Receive all data (TCP is stream-based, messages may be combined)
  let received = assert_ok(tcp.recv_timeout(server_conn, 0, 5000))

  // Verify we received at least the first message
  // TCP is stream-based so messages may be combined or fragmented
  case bit_array_length(received) >= 9 {
    True -> Nil
    False -> panic as "Expected at least 9 bytes"
  }

  // Clean up
  let _ = tcp.close(client)
  let _ = tcp.close(server_conn)
  let _ = tcp.close_listen(listen_socket)
  Nil
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Error Handling Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn tcp_connect_timeout_test() {
  let opts = socket_options.tcp_defaults()

  // Try to connect to a non-routable IP with short timeout
  // Using 10.255.255.1 which should timeout
  case tcp.connect_timeout("10.255.255.1", 12_345, opts, 100) {
    Error(_err) -> Nil
    // Expected timeout or connection refused
    Ok(_) -> panic as "Expected connection to fail"
  }
}

pub fn tcp_recv_timeout_test() {
  let opts = socket_options.server_defaults()

  // Create server
  let listen_socket = assert_ok(tcp.listen(0, opts))
  let port = assert_ok(tcp.get_port(listen_socket))

  // Connect client
  let client_opts = socket_options.tcp_defaults()
  let client = assert_ok(tcp.connect("127.0.0.1", port, client_opts))

  // Accept connection
  let server_conn = assert_ok(tcp.accept_timeout(listen_socket, 5000))

  // Try to receive with short timeout (no data sent)
  case tcp.recv_timeout(server_conn, 0, 100) {
    Error(_) -> Nil
    // Expected timeout
    Ok(_) -> panic as "Expected timeout"
  }

  // Clean up
  let _ = tcp.close(client)
  let _ = tcp.close(server_conn)
  let _ = tcp.close_listen(listen_socket)
  Nil
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@external(erlang, "erlang", "byte_size")
fn bit_array_length(data: BitArray) -> Int
