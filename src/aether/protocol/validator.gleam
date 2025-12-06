// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol Pipeline Validator Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/protocol.{type Protocol}
import aether/protocol/registry.{type Registry}
import gleam/list
import gleam/set

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Validation errors that can occur when checking protocol pipeline order
///
pub type ValidationError {
  /// A protocol appears before another protocol it should come after
  ///
  /// Example: TLS appearing before TCP when TLS.must_come_after contains "tcp"
  OrderViolation(
    /// Name of the protocol with the constraint
    protocol: String,
    /// Name of the protocol that should appear before
    expected_before: String,
    /// Actual position of the violating protocol
    actual_position: Int,
  )

  /// A required protocol is missing from the pipeline
  ///
  /// Example: TLS requires TCP but TCP is not in the pipeline
  MissingDependency(
    /// Name of the protocol that has the requirement
    protocol: String,
    /// Name of the required protocol that is missing
    required: String,
  )

  /// Two conflicting protocols are present in the same pipeline
  ///
  /// Example: HTTP/1.1 and HTTP/2 both present when they conflict
  ConflictDetected(
    /// Name of the first conflicting protocol
    protocol1: String,
    /// Name of the second conflicting protocol
    protocol2: String,
  )

  /// A protocol name in the pipeline is not registered
  UnknownProtocol(
    /// Name of the unknown protocol
    name: String,
  )

  /// A protocol that must come before another appears after it
  ///
  /// Example: GZIP appearing after HTTP when GZIP.must_come_before contains "http"
  MustComeBeforeViolation(
    /// Name of the protocol with the constraint
    protocol: String,
    /// Name of the protocol that should appear after
    expected_after: String,
    /// Actual position of the violating protocol
    actual_position: Int,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Validation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Validates a protocol pipeline order against all constraints
///
/// This function checks:
/// - All protocols exist in the registry
/// - Ordering constraints (must_come_after, must_come_before)
/// - Dependencies (requires)
/// - Conflicts (conflicts_with)
///
/// ## Parameters
///
/// - `reg`: The registry containing protocol definitions
/// - `protocol_names`: List of protocol names in pipeline order
///
/// ## Returns
///
/// Ok(Nil) if all constraints are satisfied, Error with list of violations otherwise
///
/// ## Examples
///
/// ```gleam
/// // Valid pipeline: TCP -> TLS -> HTTP
/// validate_pipeline(registry, ["tcp", "tls", "http"])
/// // => Ok(Nil)
///
/// // Invalid: HTTP before TCP when TLS must come after TCP
/// validate_pipeline(registry, ["http", "tls", "tcp"])
/// // => Error([OrderViolation(...)])
/// ```
///
pub fn validate_pipeline(
  reg: Registry,
  protocol_names: List(String),
) -> Result(Nil, List(ValidationError)) {
  // First check for unknown protocols
  let unknown_errors = check_unknown_protocols(reg, protocol_names)

  // Get all protocols that exist
  let protocols = registry.get_many(reg, protocol_names)

  // Collect all validation errors
  let errors =
    unknown_errors
    |> check_ordering_constraints(protocols, protocol_names)
    |> check_must_come_before_constraints(protocols, protocol_names)
    |> check_dependencies(protocols, protocol_names)
    |> check_conflicts(protocols)

  case errors {
    [] -> Ok(Nil)
    _ -> Error(errors)
  }
}

/// Validates a single protocol against the pipeline
///
/// Useful for checking if a protocol can be added to an existing pipeline.
///
/// ## Parameters
///
/// - `reg`: The registry containing protocol definitions
/// - `proto`: The protocol to validate
/// - `pipeline`: Current pipeline protocol names
/// - `position`: Position where the protocol would be inserted
///
/// ## Returns
///
/// Ok(Nil) if the protocol can be added, Error with violations otherwise
///
pub fn validate_addition(
  reg: Registry,
  proto: Protocol,
  pipeline: List(String),
  position: Int,
) -> Result(Nil, List(ValidationError)) {
  let proto_name = protocol.get_name(proto)
  let new_pipeline = list_insert(pipeline, proto_name, position)
  validate_pipeline(reg, new_pipeline)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Individual Check Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks for unknown protocol names
///
fn check_unknown_protocols(
  reg: Registry,
  names: List(String),
) -> List(ValidationError) {
  names
  |> list.filter(fn(name) { !registry.contains(reg, name) })
  |> list.map(fn(name) { UnknownProtocol(name: name) })
}

/// Checks must_come_after ordering constraints
///
fn check_ordering_constraints(
  errors: List(ValidationError),
  protocols: List(Protocol),
  names: List(String),
) -> List(ValidationError) {
  list.index_fold(protocols, errors, fn(acc, proto, index) {
    let proto_name = protocol.get_name(proto)
    let constraints = protocol.get_constraints(proto)

    // Check each "must come after" constraint
    let after_violations =
      set.to_list(constraints.must_come_after)
      |> list.filter_map(fn(dep) {
        case find_index_of(names, dep) {
          Ok(dep_index) if dep_index > index ->
            // The dependency appears AFTER this protocol, which is wrong
            Ok(OrderViolation(
              protocol: proto_name,
              expected_before: dep,
              actual_position: index,
            ))
          _ ->
            // Dependency is before or not found (handled by dependency check)
            Error(Nil)
        }
      })

    list.append(acc, after_violations)
  })
}

/// Checks must_come_before ordering constraints
///
fn check_must_come_before_constraints(
  errors: List(ValidationError),
  protocols: List(Protocol),
  names: List(String),
) -> List(ValidationError) {
  list.index_fold(protocols, errors, fn(acc, proto, index) {
    let proto_name = protocol.get_name(proto)
    let constraints = protocol.get_constraints(proto)

    // Check each "must come before" constraint
    let before_violations =
      set.to_list(constraints.must_come_before)
      |> list.filter_map(fn(target) {
        case find_index_of(names, target) {
          Ok(target_index) if target_index < index ->
            // The target appears BEFORE this protocol, which is wrong
            Ok(MustComeBeforeViolation(
              protocol: proto_name,
              expected_after: target,
              actual_position: index,
            ))
          _ ->
            // Target is after or not found
            Error(Nil)
        }
      })

    list.append(acc, before_violations)
  })
}

/// Checks required dependencies
///
fn check_dependencies(
  errors: List(ValidationError),
  protocols: List(Protocol),
  names: List(String),
) -> List(ValidationError) {
  list.fold(protocols, errors, fn(acc, proto) {
    let proto_name = protocol.get_name(proto)
    let constraints = protocol.get_constraints(proto)

    // Check each required protocol
    let missing =
      set.to_list(constraints.requires)
      |> list.filter(fn(req) { !list.contains(names, req) })
      |> list.map(fn(req) {
        MissingDependency(protocol: proto_name, required: req)
      })

    list.append(acc, missing)
  })
}

/// Checks for conflicting protocols
///
fn check_conflicts(
  errors: List(ValidationError),
  protocols: List(Protocol),
) -> List(ValidationError) {
  list.fold(protocols, errors, fn(acc, p1) {
    let p1_name = protocol.get_name(p1)
    let p1_constraints = protocol.get_constraints(p1)

    list.fold(protocols, acc, fn(inner_acc, p2) {
      let p2_name = protocol.get_name(p2)

      case p1_name == p2_name {
        True -> inner_acc
        False -> {
          case set.contains(p1_constraints.conflicts_with, p2_name) {
            True -> [
              ConflictDetected(protocol1: p1_name, protocol2: p2_name),
              ..inner_acc
            ]
            False -> inner_acc
          }
        }
      }
    })
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Error Formatting Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a validation error to a human-readable string
///
pub fn error_to_string(error: ValidationError) -> String {
  case error {
    OrderViolation(protocol:, expected_before:, actual_position:) ->
      "OrderViolation: '"
      <> protocol
      <> "' at position "
      <> int_to_string(actual_position)
      <> " must come after '"
      <> expected_before
      <> "'"

    MissingDependency(protocol:, required:) ->
      "MissingDependency: '" <> protocol <> "' requires '" <> required <> "'"

    ConflictDetected(protocol1:, protocol2:) ->
      "ConflictDetected: '"
      <> protocol1
      <> "' conflicts with '"
      <> protocol2
      <> "'"

    UnknownProtocol(name:) -> "UnknownProtocol: '" <> name <> "' not registered"

    MustComeBeforeViolation(protocol:, expected_after:, actual_position:) ->
      "MustComeBeforeViolation: '"
      <> protocol
      <> "' at position "
      <> int_to_string(actual_position)
      <> " must come before '"
      <> expected_after
      <> "'"
  }
}

/// Converts all validation errors to strings
///
pub fn errors_to_strings(errors: List(ValidationError)) -> List(String) {
  list.map(errors, error_to_string)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Finds the index of an item in a list
///
/// Gleam stdlib doesn't have list.index_of, so we implement it here.
///
fn find_index_of(items: List(String), target: String) -> Result(Int, Nil) {
  list.index_fold(items, Error(Nil), fn(acc, item, index) {
    case acc, item == target {
      Error(_), True -> Ok(index)
      _, _ -> acc
    }
  })
}

/// Inserts an item at the specified position in a list
///
fn list_insert(items: List(a), item: a, position: Int) -> List(a) {
  let #(before, after) = list.split(items, position)
  list.flatten([before, [item], after])
}

/// Simple int to string conversion using recursion
///
fn int_to_string(n: Int) -> String {
  case n < 0 {
    True -> "-" <> int_to_string_positive(-n)
    False -> int_to_string_positive(n)
  }
}

fn int_to_string_positive(n: Int) -> String {
  case n {
    0 -> "0"
    _ -> int_to_string_helper(n, "")
  }
}

fn int_to_string_helper(n: Int, acc: String) -> String {
  case n {
    0 -> acc
    _ -> {
      let digit = n % 10
      let char = case digit {
        0 -> "0"
        1 -> "1"
        2 -> "2"
        3 -> "3"
        4 -> "4"
        5 -> "5"
        6 -> "6"
        7 -> "7"
        8 -> "8"
        _ -> "9"
      }
      int_to_string_helper(n / 10, char <> acc)
    }
  }
}
