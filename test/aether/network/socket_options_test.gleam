import aether/network/socket_options.{
  Active, Any, Count, IpV4, IpV6, Once, Passive,
}
import gleam/option
import test_helper.{assert_equal, assert_false, assert_true}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_creates_default_options_test() {
  let opts = socket_options.new()

  assert_false(opts.reuseaddr)
  assert_false(opts.nodelay)
  assert_false(opts.keepalive)
  assert_equal(128, opts.backlog)
  assert_equal(Passive, opts.active_mode)
  assert_equal(Any, opts.interface)
  assert_false(opts.ipv6)
}

pub fn tcp_defaults_enables_optimizations_test() {
  let opts = socket_options.tcp_defaults()

  assert_true(opts.reuseaddr)
  assert_true(opts.nodelay)
  assert_true(opts.keepalive)
  assert_equal(option.Some(30_000), opts.send_timeout)
  assert_true(opts.send_timeout_close)
}

pub fn udp_defaults_disables_tcp_options_test() {
  let opts = socket_options.udp_defaults()

  assert_true(opts.reuseaddr)
  assert_false(opts.nodelay)
  assert_false(opts.keepalive)
  assert_equal(0, opts.backlog)
}

pub fn server_defaults_has_large_backlog_test() {
  let opts = socket_options.server_defaults()

  assert_true(opts.reuseaddr)
  assert_equal(1024, opts.backlog)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Builder Pattern Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn with_reuseaddr_enables_option_test() {
  let opts =
    socket_options.new()
    |> socket_options.with_reuseaddr(True)

  assert_true(opts.reuseaddr)
}

pub fn with_nodelay_enables_option_test() {
  let opts =
    socket_options.new()
    |> socket_options.with_nodelay(True)

  assert_true(opts.nodelay)
}

pub fn with_keepalive_enables_option_test() {
  let opts =
    socket_options.new()
    |> socket_options.with_keepalive(True)

  assert_true(opts.keepalive)
}

pub fn with_buffer_size_sets_all_buffers_test() {
  let opts =
    socket_options.new()
    |> socket_options.with_buffer_size(65_536)

  assert_equal(option.Some(65_536), opts.recbuf)
  assert_equal(option.Some(65_536), opts.sndbuf)
  assert_equal(option.Some(65_536), opts.buffer)
}

pub fn with_backlog_sets_queue_size_test() {
  let opts =
    socket_options.new()
    |> socket_options.with_backlog(2048)

  assert_equal(2048, opts.backlog)
}

pub fn with_active_mode_sets_mode_test() {
  let passive_opts =
    socket_options.new()
    |> socket_options.with_active_mode(Passive)
  assert_equal(Passive, passive_opts.active_mode)

  let once_opts =
    socket_options.new()
    |> socket_options.with_active_mode(Once)
  assert_equal(Once, once_opts.active_mode)

  let count_opts =
    socket_options.new()
    |> socket_options.with_active_mode(Count(10))
  assert_equal(Count(10), count_opts.active_mode)

  let active_opts =
    socket_options.new()
    |> socket_options.with_active_mode(Active)
  assert_equal(Active, active_opts.active_mode)
}

pub fn with_ipv6_enables_ipv6_test() {
  let opts =
    socket_options.new()
    |> socket_options.with_ipv6()

  assert_true(opts.ipv6)
}

pub fn builder_chaining_works_test() {
  let opts =
    socket_options.new()
    |> socket_options.with_reuseaddr(True)
    |> socket_options.with_nodelay(True)
    |> socket_options.with_keepalive(True)
    |> socket_options.with_backlog(512)
    |> socket_options.with_active_mode(Once)

  assert_true(opts.reuseaddr)
  assert_true(opts.nodelay)
  assert_true(opts.keepalive)
  assert_equal(512, opts.backlog)
  assert_equal(Once, opts.active_mode)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accessor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn get_reuseaddr_returns_value_test() {
  let opts = socket_options.tcp_defaults()
  assert_true(socket_options.get_reuseaddr(opts))
}

pub fn get_nodelay_returns_value_test() {
  let opts = socket_options.tcp_defaults()
  assert_true(socket_options.get_nodelay(opts))
}

pub fn get_backlog_returns_value_test() {
  let opts = socket_options.server_defaults()
  assert_equal(1024, socket_options.get_backlog(opts))
}

pub fn get_active_mode_returns_value_test() {
  let opts =
    socket_options.new()
    |> socket_options.with_active_mode(Once)
  assert_equal(Once, socket_options.get_active_mode(opts))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// IP Address Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn ipv4_creates_address_test() {
  let ip = socket_options.ipv4(192, 168, 1, 1)
  assert_equal(IpV4(192, 168, 1, 1), ip)
}

pub fn ipv6_creates_address_test() {
  let ip = socket_options.ipv6(0x2001, 0x0db8, 0, 0, 0, 0, 0, 1)
  assert_equal(IpV6(0x2001, 0x0db8, 0, 0, 0, 0, 0, 1), ip)
}

pub fn localhost_returns_loopback_test() {
  let ip = socket_options.localhost()
  assert_equal(IpV4(127, 0, 0, 1), ip)
}

pub fn any_address_returns_wildcard_test() {
  let ip = socket_options.any_address()
  assert_equal(IpV4(0, 0, 0, 0), ip)
}

pub fn localhost_v6_returns_loopback_test() {
  let ip = socket_options.localhost_v6()
  assert_equal(IpV6(0, 0, 0, 0, 0, 0, 0, 1), ip)
}

pub fn ip_to_string_formats_ipv4_test() {
  let ip = socket_options.ipv4(192, 168, 1, 100)
  assert_equal("192.168.1.100", socket_options.ip_to_string(ip))
}

pub fn ip_to_string_formats_localhost_test() {
  let ip = socket_options.localhost()
  assert_equal("127.0.0.1", socket_options.ip_to_string(ip))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Linger Config Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn linger_config_creates_enabled_config_test() {
  let config = socket_options.linger_config(30)
  assert_true(config.enabled)
  assert_equal(30, config.timeout_seconds)
}

pub fn linger_disabled_creates_disabled_config_test() {
  let config = socket_options.linger_disabled()
  assert_false(config.enabled)
  assert_equal(0, config.timeout_seconds)
}
