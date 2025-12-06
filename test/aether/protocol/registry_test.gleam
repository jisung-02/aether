import aether/protocol/protocol
import aether/protocol/registry
import gleam/list
import gleam/option
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Registry Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_creates_empty_registry_test() {
  let reg = registry.new()

  registry.is_empty(reg)
  |> should.be_true()

  registry.size(reg)
  |> should.equal(0)
}

pub fn from_list_creates_registry_with_protocols_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")

  let reg = registry.from_list([tcp, http])

  registry.size(reg)
  |> should.equal(2)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Registration Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn register_adds_protocol_test() {
  let tcp = protocol.new("tcp")

  let reg =
    registry.new()
    |> registry.register(tcp)

  registry.contains(reg, "tcp")
  |> should.be_true()
}

pub fn register_multiple_protocols_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")
  let tls = protocol.new("tls")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(http)
    |> registry.register(tls)

  registry.size(reg)
  |> should.equal(3)
}

pub fn register_replaces_existing_protocol_test() {
  let tcp_v1 =
    protocol.new("tcp")
    |> protocol.with_version("1.0.0")

  let tcp_v2 =
    protocol.new("tcp")
    |> protocol.with_version("2.0.0")

  let reg =
    registry.new()
    |> registry.register(tcp_v1)
    |> registry.register(tcp_v2)

  registry.size(reg)
  |> should.equal(1)

  case registry.get(reg, "tcp") {
    option.Some(proto) -> {
      let metadata = protocol.get_metadata(proto)
      metadata.version
      |> should.equal("2.0.0")
    }
    option.None -> should.fail()
  }
}

pub fn unregister_removes_protocol_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(http)
    |> registry.unregister("tcp")

  registry.contains(reg, "tcp")
  |> should.be_false()

  registry.contains(reg, "http")
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Lookup Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn get_returns_some_for_existing_protocol_test() {
  let tcp = protocol.new("tcp")

  let reg =
    registry.new()
    |> registry.register(tcp)

  case registry.get(reg, "tcp") {
    option.Some(proto) -> {
      protocol.get_name(proto)
      |> should.equal("tcp")
    }
    option.None -> should.fail()
  }
}

pub fn get_returns_none_for_missing_protocol_test() {
  let reg = registry.new()

  registry.get(reg, "tcp")
  |> should.equal(option.None)
}

pub fn get_by_tag_returns_matching_protocols_test() {
  let tcp =
    protocol.new("tcp")
    |> protocol.with_tag("transport")

  let udp =
    protocol.new("udp")
    |> protocol.with_tag("transport")

  let http =
    protocol.new("http")
    |> protocol.with_tag("application")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(udp)
    |> registry.register(http)

  let transports = registry.get_by_tag(reg, "transport")

  list.length(transports)
  |> should.equal(2)
}

pub fn get_by_tag_returns_empty_for_no_matches_test() {
  let tcp =
    protocol.new("tcp")
    |> protocol.with_tag("transport")

  let reg =
    registry.new()
    |> registry.register(tcp)

  registry.get_by_tag(reg, "session")
  |> list.length()
  |> should.equal(0)
}

pub fn get_many_returns_found_protocols_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")
  let tls = protocol.new("tls")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(http)
    |> registry.register(tls)

  let found = registry.get_many(reg, ["tcp", "http"])

  list.length(found)
  |> should.equal(2)
}

pub fn get_many_ignores_missing_protocols_test() {
  let tcp = protocol.new("tcp")

  let reg =
    registry.new()
    |> registry.register(tcp)

  let found = registry.get_many(reg, ["tcp", "missing", "also_missing"])

  list.length(found)
  |> should.equal(1)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Query Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn contains_returns_true_for_registered_test() {
  let tcp = protocol.new("tcp")

  let reg =
    registry.new()
    |> registry.register(tcp)

  registry.contains(reg, "tcp")
  |> should.be_true()
}

pub fn contains_returns_false_for_unregistered_test() {
  let reg = registry.new()

  registry.contains(reg, "tcp")
  |> should.be_false()
}

pub fn is_empty_returns_true_for_empty_registry_test() {
  registry.new()
  |> registry.is_empty()
  |> should.be_true()
}

pub fn is_empty_returns_false_for_non_empty_registry_test() {
  let tcp = protocol.new("tcp")

  registry.new()
  |> registry.register(tcp)
  |> registry.is_empty()
  |> should.be_false()
}

pub fn size_returns_correct_count_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")
  let tls = protocol.new("tls")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(http)
    |> registry.register(tls)

  registry.size(reg)
  |> should.equal(3)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Listing Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn list_names_returns_all_names_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(http)

  let names = registry.list_names(reg)

  list.length(names)
  |> should.equal(2)

  list.contains(names, "tcp")
  |> should.be_true()

  list.contains(names, "http")
  |> should.be_true()
}

pub fn list_all_returns_all_protocols_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(http)

  let protocols = registry.list_all(reg)

  list.length(protocols)
  |> should.equal(2)
}

pub fn list_tags_returns_unique_tags_test() {
  let tcp =
    protocol.new("tcp")
    |> protocol.with_tag("transport")

  let udp =
    protocol.new("udp")
    |> protocol.with_tag("transport")

  let http =
    protocol.new("http")
    |> protocol.with_tag("application")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(udp)
    |> registry.register(http)

  let tags = registry.list_tags(reg)

  // Should have "transport" and "application" (unique)
  list.length(tags)
  |> should.equal(2)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Utility Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn merge_combines_registries_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")

  let reg1 =
    registry.new()
    |> registry.register(tcp)

  let reg2 =
    registry.new()
    |> registry.register(http)

  let merged = registry.merge(reg1, reg2)

  registry.size(merged)
  |> should.equal(2)
}

pub fn merge_second_takes_precedence_test() {
  let tcp_v1 =
    protocol.new("tcp")
    |> protocol.with_version("1.0.0")

  let tcp_v2 =
    protocol.new("tcp")
    |> protocol.with_version("2.0.0")

  let reg1 =
    registry.new()
    |> registry.register(tcp_v1)

  let reg2 =
    registry.new()
    |> registry.register(tcp_v2)

  let merged = registry.merge(reg1, reg2)

  case registry.get(merged, "tcp") {
    option.Some(proto) -> {
      let metadata = protocol.get_metadata(proto)
      metadata.version
      |> should.equal("2.0.0")
    }
    option.None -> should.fail()
  }
}

pub fn filter_keeps_matching_protocols_test() {
  let tcp =
    protocol.new("tcp")
    |> protocol.with_tag("transport")

  let http =
    protocol.new("http")
    |> protocol.with_tag("application")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(http)

  let filtered = registry.filter(reg, fn(p) { protocol.has_tag(p, "transport") })

  registry.size(filtered)
  |> should.equal(1)

  registry.contains(filtered, "tcp")
  |> should.be_true()
}

pub fn map_transforms_all_protocols_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(http)

  let mapped = registry.map(reg, fn(p) { protocol.with_tag(p, "mapped") })

  case registry.get(mapped, "tcp") {
    option.Some(proto) -> {
      protocol.has_tag(proto, "mapped")
      |> should.be_true()
    }
    option.None -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Immutability Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn register_is_immutable_test() {
  let tcp = protocol.new("tcp")

  let original = registry.new()
  let modified = registry.register(original, tcp)

  // Original should still be empty
  registry.is_empty(original)
  |> should.be_true()

  // Modified should have the protocol
  registry.contains(modified, "tcp")
  |> should.be_true()
}
