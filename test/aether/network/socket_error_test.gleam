import aether/network/socket_error.{
  AddressInUse, ConnectionClosed, ConnectionRefused, ConnectionReset,
  HostUnreachable, NetworkUnreachable, NotConnected, PermissionDenied, Timeout,
  WouldBlock,
}
import test_helper.{assert_equal, assert_false, assert_true}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Classification Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn is_closed_detects_closed_errors_test() {
  assert_true(socket_error.is_closed(ConnectionClosed))
  assert_true(socket_error.is_closed(ConnectionReset))
  assert_false(socket_error.is_closed(Timeout))
  assert_false(socket_error.is_closed(ConnectionRefused))
}

pub fn is_retriable_detects_retriable_errors_test() {
  assert_true(socket_error.is_retriable(Timeout))
  assert_true(socket_error.is_retriable(WouldBlock))
  assert_false(socket_error.is_retriable(ConnectionRefused))
  assert_false(socket_error.is_retriable(PermissionDenied))
}

pub fn is_network_error_detects_network_errors_test() {
  assert_true(socket_error.is_network_error(NetworkUnreachable))
  assert_true(socket_error.is_network_error(HostUnreachable))
  assert_true(socket_error.is_network_error(ConnectionRefused))
  assert_false(socket_error.is_network_error(Timeout))
  assert_false(socket_error.is_network_error(AddressInUse))
}

pub fn is_address_error_detects_address_errors_test() {
  assert_true(socket_error.is_address_error(AddressInUse))
  assert_false(socket_error.is_address_error(ConnectionRefused))
  assert_false(socket_error.is_address_error(Timeout))
}

pub fn is_permission_error_detects_permission_errors_test() {
  assert_true(socket_error.is_permission_error(PermissionDenied))
  assert_false(socket_error.is_permission_error(ConnectionRefused))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// to_string Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn to_string_formats_connection_refused_test() {
  assert_equal("Connection refused", socket_error.to_string(ConnectionRefused))
}

pub fn to_string_formats_connection_closed_test() {
  assert_equal("Connection closed", socket_error.to_string(ConnectionClosed))
}

pub fn to_string_formats_timeout_test() {
  assert_equal("Operation timed out", socket_error.to_string(Timeout))
}

pub fn to_string_formats_not_connected_test() {
  assert_equal("Socket is not connected", socket_error.to_string(NotConnected))
}

pub fn to_string_formats_address_in_use_test() {
  assert_equal("Address already in use", socket_error.to_string(AddressInUse))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn invalid_argument_creates_error_with_message_test() {
  let err = socket_error.invalid_argument("test message")
  assert_equal(
    "Invalid argument: test message",
    socket_error.to_string(err),
  )
}

pub fn unknown_creates_error_with_reason_test() {
  let err = socket_error.unknown("custom reason")
  assert_equal("Unknown error: custom reason", socket_error.to_string(err))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Dynamic Reason Parsing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn from_dynamic_reason_parses_closed_test() {
  let err = socket_error.from_dynamic_reason("closed")
  assert_true(socket_error.is_closed(err))
}

pub fn from_dynamic_reason_parses_timeout_test() {
  let err = socket_error.from_dynamic_reason("timeout")
  assert_true(socket_error.is_retriable(err))
}

pub fn from_dynamic_reason_parses_econnrefused_test() {
  let err = socket_error.from_dynamic_reason("econnrefused")
  assert_true(socket_error.is_network_error(err))
}

pub fn from_dynamic_reason_handles_unknown_test() {
  let err = socket_error.from_dynamic_reason("some_unknown_error")
  assert_equal(
    "Unknown error: some_unknown_error",
    socket_error.to_string(err),
  )
}
