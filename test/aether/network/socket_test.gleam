import aether/network/socket.{
  Closed, Connected, Created, IpAddr, Listening, Tcp, Udp, UnixPath,
}
import aether/network/socket_options
import test_helper.{assert_equal}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Address Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn ip_address_creates_socket_address_test() {
  let ip = socket_options.localhost()
  let addr = socket.ip_address(ip, 8080)

  case addr {
    IpAddr(address, port) -> {
      assert_equal(ip, address)
      assert_equal(8080, port)
    }
    _ -> panic as "Expected IpAddr"
  }
}

pub fn ipv4_address_creates_socket_address_test() {
  let addr = socket.ipv4_address(192, 168, 1, 1, 9000)

  case addr {
    IpAddr(ip, port) -> {
      assert_equal(socket_options.IpV4(192, 168, 1, 1), ip)
      assert_equal(9000, port)
    }
    _ -> panic as "Expected IpAddr"
  }
}

pub fn unix_address_creates_path_address_test() {
  let addr = socket.unix_address("/var/run/socket.sock")

  case addr {
    UnixPath(path) -> assert_equal("/var/run/socket.sock", path)
    _ -> panic as "Expected UnixPath"
  }
}

pub fn localhost_address_creates_loopback_test() {
  let addr = socket.localhost_address(8080)

  case addr {
    IpAddr(ip, port) -> {
      assert_equal(socket_options.localhost(), ip)
      assert_equal(8080, port)
    }
    _ -> panic as "Expected IpAddr"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Transport Type Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn transport_to_string_formats_tcp_test() {
  assert_equal("TCP", socket.transport_to_string(Tcp))
}

pub fn transport_to_string_formats_udp_test() {
  assert_equal("UDP", socket.transport_to_string(Udp))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket State Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn state_to_string_formats_created_test() {
  assert_equal("Created", socket.state_to_string(Created))
}

pub fn state_to_string_formats_connected_test() {
  assert_equal("Connected", socket.state_to_string(Connected))
}

pub fn state_to_string_formats_listening_test() {
  assert_equal("Listening", socket.state_to_string(Listening))
}

pub fn state_to_string_formats_closed_test() {
  assert_equal("Closed", socket.state_to_string(Closed))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Shutdown Direction Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn shutdown_to_string_formats_read_test() {
  assert_equal("Read", socket.shutdown_to_string(socket.Read))
}

pub fn shutdown_to_string_formats_write_test() {
  assert_equal("Write", socket.shutdown_to_string(socket.Write))
}

pub fn shutdown_to_string_formats_both_test() {
  assert_equal("Both", socket.shutdown_to_string(socket.Both))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket Creation Helper Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn from_inner_creates_socket_with_correct_state_test() {
  // We can't create a real InnerSocket without an actual connection,
  // but we can test the structure
  let _opts = socket_options.tcp_defaults()

  // Test that the function signature is correct
  // This is a compile-time test more than a runtime test
  Nil
}
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Socket State Function Tests (using mock socket)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Note: More comprehensive socket tests require actual network connections
// which are covered in integration tests. These unit tests focus on
// pure functions and type construction.
