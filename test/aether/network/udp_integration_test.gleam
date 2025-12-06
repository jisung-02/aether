// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// UDP Integration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// These tests verify actual UDP socket operations using localhost.
// They create real sockets to test the full stack.
//

import aether/network/socket_options
import aether/network/udp
import gleam/erlang/process
import test_helper.{assert_equal, assert_ok}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// UDP Bind Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn udp_bind_on_random_port_test() {
  let opts = socket_options.udp_defaults()

  // Bind on port 0 to get a random available port
  let sock = assert_ok(udp.bind(0, opts))

  // Get the assigned port
  let port = assert_ok(udp.get_port(sock))

  // Port should be non-zero
  case port > 0 {
    True -> Nil
    False -> panic as "Expected non-zero port"
  }

  // Clean up
  let _ = udp.close(sock)
  Nil
}

pub fn udp_bind_on_specific_port_test() {
  let opts = socket_options.udp_defaults()

  // Find an available port by binding on 0 first
  let temp_socket = assert_ok(udp.bind(0, opts))
  let port = assert_ok(udp.get_port(temp_socket))
  let _ = udp.close(temp_socket)

  // Small delay to ensure port is released
  process.sleep(50)

  // Now bind on that specific port
  let sock = assert_ok(udp.bind(port, opts))
  let actual_port = assert_ok(udp.get_port(sock))
  assert_equal(port, actual_port)

  // Clean up
  let _ = udp.close(sock)
  Nil
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// UDP Send and Recv Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn udp_echo_test() {
  let opts = socket_options.udp_defaults()

  // Create server socket
  let server = assert_ok(udp.bind(0, opts))
  let server_port = assert_ok(udp.get_port(server))

  // Create client socket
  let client = assert_ok(udp.bind(0, opts))

  // Send data from client to server
  let message = <<"Hello, UDP!">>
  let _ = assert_ok(udp.send_to(client, "127.0.0.1", server_port, message))

  // Receive on server
  let datagram = assert_ok(udp.recv_from_timeout(server, 0, 5000))
  assert_equal(message, datagram.data)

  // Verify source is from client's localhost
  assert_equal(socket_options.localhost(), datagram.from_ip)

  // Echo back to client using the IP address
  let from_ip_str = socket_options.ip_to_string(datagram.from_ip)
  let _ = assert_ok(udp.send_to(server, from_ip_str, datagram.from_port, datagram.data))

  // Receive echo on client
  let echo_datagram = assert_ok(udp.recv_from_timeout(client, 0, 5000))
  assert_equal(message, echo_datagram.data)

  // Clean up
  let _ = udp.close(client)
  let _ = udp.close(server)
  Nil
}

pub fn udp_multiple_datagrams_test() {
  let opts = socket_options.udp_defaults()

  // Create server socket
  let server = assert_ok(udp.bind(0, opts))
  let server_port = assert_ok(udp.get_port(server))

  // Create client socket
  let client = assert_ok(udp.bind(0, opts))

  // Send multiple datagrams
  let msg1 = <<"Datagram 1">>
  let msg2 = <<"Datagram 2">>
  let msg3 = <<"Datagram 3">>

  let _ = assert_ok(udp.send_to(client, "127.0.0.1", server_port, msg1))
  let _ = assert_ok(udp.send_to(client, "127.0.0.1", server_port, msg2))
  let _ = assert_ok(udp.send_to(client, "127.0.0.1", server_port, msg3))

  // Receive all datagrams (UDP preserves message boundaries)
  let recv1 = assert_ok(udp.recv_from_timeout(server, 0, 5000))
  let recv2 = assert_ok(udp.recv_from_timeout(server, 0, 5000))
  let recv3 = assert_ok(udp.recv_from_timeout(server, 0, 5000))

  // Verify each datagram was received intact
  assert_equal(msg1, recv1.data)
  assert_equal(msg2, recv2.data)
  assert_equal(msg3, recv3.data)

  // Clean up
  let _ = udp.close(client)
  let _ = udp.close(server)
  Nil
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// UDP Error Handling Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn udp_recv_timeout_test() {
  let opts = socket_options.udp_defaults()

  // Create socket
  let sock = assert_ok(udp.bind(0, opts))

  // Try to receive with short timeout (no data sent)
  case udp.recv_from_timeout(sock, 0, 100) {
    Error(_) -> Nil
    // Expected timeout
    Ok(_) -> panic as "Expected timeout"
  }

  // Clean up
  let _ = udp.close(sock)
  Nil
}

pub fn udp_large_datagram_test() {
  let opts = socket_options.udp_defaults()

  // Create server socket
  let server = assert_ok(udp.bind(0, opts))
  let server_port = assert_ok(udp.get_port(server))

  // Create client socket
  let client = assert_ok(udp.bind(0, opts))

  // Create a larger message (but under UDP max size)
  let large_message = create_large_message(1024)

  // Send large datagram
  let _ = assert_ok(udp.send_to(client, "127.0.0.1", server_port, large_message))

  // Receive on server
  let datagram = assert_ok(udp.recv_from_timeout(server, 0, 5000))
  assert_equal(large_message, datagram.data)

  // Clean up
  let _ = udp.close(client)
  let _ = udp.close(server)
  Nil
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn create_large_message(size: Int) -> BitArray {
  create_large_message_loop(<<>>, size)
}

fn create_large_message_loop(acc: BitArray, remaining: Int) -> BitArray {
  case remaining <= 0 {
    True -> acc
    False -> create_large_message_loop(<<acc:bits, "A":utf8>>, remaining - 1)
  }
}
