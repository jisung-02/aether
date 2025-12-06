import aether/protocol/protocol
import aether/protocol/registry
import aether/protocol/validator
import gleam/list
import gleam/result
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn create_test_registry() -> registry.Registry {
  let tcp = protocol.new("tcp") |> protocol.with_tag("transport")

  let tls =
    protocol.new("tls")
    |> protocol.with_tag("session")
    |> protocol.requires("tcp")
    |> protocol.must_come_after("tcp")

  let http = protocol.new("http") |> protocol.with_tag("application")

  let gzip =
    protocol.new("gzip")
    |> protocol.with_tag("compression")
    |> protocol.must_come_before("http")

  registry.new()
  |> registry.register(tcp)
  |> registry.register(tls)
  |> registry.register(http)
  |> registry.register(gzip)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Valid Pipeline Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn valid_simple_pipeline_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(http)

  validator.validate_pipeline(reg, ["tcp", "http"])
  |> result.is_ok()
  |> should.be_true()
}

pub fn valid_pipeline_with_ordering_constraint_test() {
  let reg = create_test_registry()

  // TLS must come after TCP - this is valid
  validator.validate_pipeline(reg, ["tcp", "tls", "http"])
  |> result.is_ok()
  |> should.be_true()
}

pub fn valid_pipeline_with_must_come_before_test() {
  let reg = create_test_registry()

  // GZIP must come before HTTP - this is valid
  validator.validate_pipeline(reg, ["tcp", "gzip", "http"])
  |> result.is_ok()
  |> should.be_true()
}

pub fn valid_complex_pipeline_test() {
  let reg = create_test_registry()

  // Complete valid stack
  validator.validate_pipeline(reg, ["tcp", "tls", "gzip", "http"])
  |> result.is_ok()
  |> should.be_true()
}

pub fn valid_single_protocol_test() {
  let tcp = protocol.new("tcp")

  let reg =
    registry.new()
    |> registry.register(tcp)

  validator.validate_pipeline(reg, ["tcp"])
  |> result.is_ok()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Ordering Violation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn invalid_ordering_must_come_after_test() {
  let reg = create_test_registry()

  // TLS before TCP is invalid (TLS must_come_after TCP)
  let result = validator.validate_pipeline(reg, ["tls", "tcp", "http"])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(errors) -> {
      // At least one error
      { list.length(errors) >= 1 }
      |> should.be_true()
    }
    Ok(_) -> should.fail()
  }
}

pub fn invalid_ordering_must_come_before_test() {
  let reg = create_test_registry()

  // GZIP after HTTP is invalid (GZIP must_come_before HTTP)
  let result = validator.validate_pipeline(reg, ["tcp", "http", "gzip"])

  result.is_error(result)
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Missing Dependency Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn missing_dependency_test() {
  let reg = create_test_registry()

  // TLS requires TCP, but TCP is not in the pipeline
  let result = validator.validate_pipeline(reg, ["tls", "http"])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(errors) -> {
      // Should have MissingDependency error
      let has_missing_dep =
        list.any(errors, fn(e) {
          case e {
            validator.MissingDependency(_, _) -> True
            _ -> False
          }
        })
      has_missing_dep
      |> should.be_true()
    }
    Ok(_) -> should.fail()
  }
}

pub fn multiple_missing_dependencies_test() {
  let proto_a =
    protocol.new("a")
    |> protocol.requires("x")
    |> protocol.requires("y")

  let reg =
    registry.new()
    |> registry.register(proto_a)

  let result = validator.validate_pipeline(reg, ["a"])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(errors) -> {
      // Should have 2 MissingDependency errors
      let missing_deps =
        list.filter(errors, fn(e) {
          case e {
            validator.MissingDependency(_, _) -> True
            _ -> False
          }
        })
      list.length(missing_deps)
      |> should.equal(2)
    }
    Ok(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Conflict Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn conflict_detected_test() {
  let http1 =
    protocol.new("http1")
    |> protocol.conflicts_with("http2")

  let http2 = protocol.new("http2")

  let reg =
    registry.new()
    |> registry.register(http1)
    |> registry.register(http2)

  let result = validator.validate_pipeline(reg, ["http1", "http2"])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(errors) -> {
      let has_conflict =
        list.any(errors, fn(e) {
          case e {
            validator.ConflictDetected(_, _) -> True
            _ -> False
          }
        })
      has_conflict
      |> should.be_true()
    }
    Ok(_) -> should.fail()
  }
}

pub fn no_conflict_when_only_one_present_test() {
  let http1 =
    protocol.new("http1")
    |> protocol.conflicts_with("http2")

  let tcp = protocol.new("tcp")

  let reg =
    registry.new()
    |> registry.register(http1)
    |> registry.register(tcp)

  validator.validate_pipeline(reg, ["tcp", "http1"])
  |> result.is_ok()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Unknown Protocol Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn unknown_protocol_test() {
  let tcp = protocol.new("tcp")

  let reg =
    registry.new()
    |> registry.register(tcp)

  let result = validator.validate_pipeline(reg, ["tcp", "unknown"])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(errors) -> {
      let has_unknown =
        list.any(errors, fn(e) {
          case e {
            validator.UnknownProtocol("unknown") -> True
            _ -> False
          }
        })
      has_unknown
      |> should.be_true()
    }
    Ok(_) -> should.fail()
  }
}

pub fn multiple_unknown_protocols_test() {
  let reg = registry.new()

  let result = validator.validate_pipeline(reg, ["foo", "bar", "baz"])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(errors) -> {
      let unknown_count =
        list.filter(errors, fn(e) {
          case e {
            validator.UnknownProtocol(_) -> True
            _ -> False
          }
        })
        |> list.length()

      unknown_count
      |> should.equal(3)
    }
    Ok(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Empty Pipeline Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn empty_pipeline_is_valid_test() {
  let reg = registry.new()

  // Empty list of protocols is valid (no constraints to violate)
  validator.validate_pipeline(reg, [])
  |> result.is_ok()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Multiple Error Types Test
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn collects_all_errors_test() {
  let tls =
    protocol.new("tls")
    |> protocol.requires("tcp")
    |> protocol.must_come_after("tcp")
    |> protocol.conflicts_with("plain")

  let plain = protocol.new("plain")

  let reg =
    registry.new()
    |> registry.register(tls)
    |> registry.register(plain)

  // Missing tcp (dependency), tls before tcp would be wrong, and conflict with plain
  let result = validator.validate_pipeline(reg, ["tls", "plain"])

  result.is_error(result)
  |> should.be_true()

  case result {
    Error(errors) -> {
      // Should have multiple errors
      list.length(errors)
      |> fn(len) { len >= 2 }
      |> should.be_true()
    }
    Ok(_) -> should.fail()
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn error_to_string_order_violation_test() {
  let error = validator.OrderViolation("tls", "tcp", 0)
  let str = validator.error_to_string(error)

  // Should contain relevant information
  str
  |> fn(s) { s != "" }
  |> should.be_true()
}

pub fn error_to_string_missing_dependency_test() {
  let error = validator.MissingDependency("tls", "tcp")
  let str = validator.error_to_string(error)

  str
  |> fn(s) { s != "" }
  |> should.be_true()
}

pub fn error_to_string_conflict_test() {
  let error = validator.ConflictDetected("http1", "http2")
  let str = validator.error_to_string(error)

  str
  |> fn(s) { s != "" }
  |> should.be_true()
}

pub fn error_to_string_unknown_test() {
  let error = validator.UnknownProtocol("foo")
  let str = validator.error_to_string(error)

  str
  |> fn(s) { s != "" }
  |> should.be_true()
}

pub fn errors_to_strings_test() {
  let errors = [
    validator.OrderViolation("a", "b", 0),
    validator.MissingDependency("c", "d"),
  ]

  let strings = validator.errors_to_strings(errors)

  list.length(strings)
  |> should.equal(2)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Validate Addition Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn validate_addition_valid_test() {
  let tcp = protocol.new("tcp")
  let http = protocol.new("http")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(http)

  // Adding http after tcp should be valid
  validator.validate_addition(reg, http, ["tcp"], 1)
  |> result.is_ok()
  |> should.be_true()
}

pub fn validate_addition_invalid_test() {
  let tcp = protocol.new("tcp")
  let tls =
    protocol.new("tls")
    |> protocol.must_come_after("tcp")

  let reg =
    registry.new()
    |> registry.register(tcp)
    |> registry.register(tls)

  // Adding tls before tcp should be invalid
  validator.validate_addition(reg, tls, ["tcp"], 0)
  |> result.is_error()
  |> should.be_true()
}
