// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol Registry Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/protocol/protocol.{type Protocol}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/set

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// A registry for storing and retrieving protocols by name
///
/// The Registry provides a central location for managing protocols
/// and enables lookup by name or tag.
///
/// ## Examples
///
/// ```gleam
/// let registry = registry.new()
///   |> registry.register(tcp_protocol)
///   |> registry.register(tls_protocol)
///   |> registry.register(http_protocol)
///
/// // Get by name
/// case registry.get(registry, "tcp") {
///   Some(protocol) -> // use protocol
///   None -> // not found
/// }
///
/// // Get all transport protocols
/// let transports = registry.get_by_tag(registry, "transport")
/// ```
///
pub opaque type Registry {
  Registry(protocols: Dict(String, Protocol))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Registry Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new empty registry
///
/// ## Returns
///
/// An empty Registry instance
///
/// ## Examples
///
/// ```gleam
/// let registry = registry.new()
/// ```
///
pub fn new() -> Registry {
  Registry(protocols: dict.new())
}

/// Creates a registry from a list of protocols
///
/// ## Parameters
///
/// - `protocols`: List of protocols to register
///
/// ## Returns
///
/// A Registry containing all provided protocols
///
pub fn from_list(protocols: List(Protocol)) -> Registry {
  protocols
  |> list.fold(new(), fn(reg, proto) { register(reg, proto) })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Registration Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Registers a protocol in the registry
///
/// If a protocol with the same name already exists, it will be replaced.
///
/// ## Parameters
///
/// - `registry`: The registry to add the protocol to
/// - `proto`: The protocol to register
///
/// ## Returns
///
/// A new Registry with the protocol added
///
/// ## Examples
///
/// ```gleam
/// let registry = registry.new()
///   |> registry.register(tcp_protocol)
/// ```
///
pub fn register(registry: Registry, proto: Protocol) -> Registry {
  let name = protocol.get_name(proto)
  Registry(protocols: dict.insert(registry.protocols, name, proto))
}

/// Unregisters a protocol from the registry by name
///
/// ## Parameters
///
/// - `registry`: The registry to remove the protocol from
/// - `name`: The name of the protocol to remove
///
/// ## Returns
///
/// A new Registry with the protocol removed
///
pub fn unregister(registry: Registry, name: String) -> Registry {
  Registry(protocols: dict.delete(registry.protocols, name))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Lookup Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets a protocol by name
///
/// ## Parameters
///
/// - `registry`: The registry to search
/// - `name`: The name of the protocol to find
///
/// ## Returns
///
/// Option containing the protocol if found, None otherwise
///
/// ## Examples
///
/// ```gleam
/// case registry.get(registry, "tcp") {
///   Some(tcp) -> // found
///   None -> // not found
/// }
/// ```
///
pub fn get(registry: Registry, name: String) -> Option(Protocol) {
  dict.get(registry.protocols, name)
  |> option.from_result()
}

/// Gets all protocols that have a specific tag
///
/// ## Parameters
///
/// - `registry`: The registry to search
/// - `tag`: The tag to filter by
///
/// ## Returns
///
/// List of protocols that have the specified tag
///
/// ## Examples
///
/// ```gleam
/// let transports = registry.get_by_tag(registry, "transport")
/// // Returns [tcp, udp, ...]
/// ```
///
pub fn get_by_tag(registry: Registry, tag: String) -> List(Protocol) {
  dict.values(registry.protocols)
  |> list.filter(fn(proto) { set.contains(protocol.get_tags(proto), tag) })
}

/// Gets multiple protocols by their names
///
/// Returns only the protocols that were found. Missing protocols are
/// silently ignored.
///
/// ## Parameters
///
/// - `registry`: The registry to search
/// - `names`: List of protocol names to find
///
/// ## Returns
///
/// List of protocols that were found (in the order of the input names)
///
pub fn get_many(registry: Registry, names: List(String)) -> List(Protocol) {
  names
  |> list.filter_map(fn(name) {
    get(registry, name)
    |> option.to_result(Nil)
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Query Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks if the registry contains a protocol with the given name
///
/// ## Parameters
///
/// - `registry`: The registry to check
/// - `name`: The name to look for
///
/// ## Returns
///
/// True if the protocol exists, False otherwise
///
pub fn contains(registry: Registry, name: String) -> Bool {
  dict.has_key(registry.protocols, name)
}

/// Checks if the registry is empty
///
/// ## Parameters
///
/// - `registry`: The registry to check
///
/// ## Returns
///
/// True if the registry has no protocols, False otherwise
///
pub fn is_empty(registry: Registry) -> Bool {
  dict.is_empty(registry.protocols)
}

/// Gets the number of protocols in the registry
///
/// ## Parameters
///
/// - `registry`: The registry to count
///
/// ## Returns
///
/// The number of registered protocols
///
pub fn size(registry: Registry) -> Int {
  dict.size(registry.protocols)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Listing Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Lists all protocol names in the registry
///
/// ## Parameters
///
/// - `registry`: The registry to list
///
/// ## Returns
///
/// List of all registered protocol names
///
pub fn list_names(registry: Registry) -> List(String) {
  dict.keys(registry.protocols)
}

/// Lists all protocols in the registry
///
/// ## Parameters
///
/// - `registry`: The registry to list
///
/// ## Returns
///
/// List of all registered protocols
///
pub fn list_all(registry: Registry) -> List(Protocol) {
  dict.values(registry.protocols)
}

/// Lists all unique tags used by protocols in the registry
///
/// ## Parameters
///
/// - `registry`: The registry to scan
///
/// ## Returns
///
/// List of all unique tags
///
pub fn list_tags(registry: Registry) -> List(String) {
  dict.values(registry.protocols)
  |> list.flat_map(fn(proto) { set.to_list(protocol.get_tags(proto)) })
  |> list.unique()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Merges two registries
///
/// If both registries contain a protocol with the same name, the protocol
/// from the second registry takes precedence.
///
/// ## Parameters
///
/// - `first`: The first registry
/// - `second`: The second registry (takes precedence on conflicts)
///
/// ## Returns
///
/// A new Registry containing all protocols from both registries
///
pub fn merge(first: Registry, second: Registry) -> Registry {
  Registry(protocols: dict.merge(first.protocols, second.protocols))
}

/// Filters protocols based on a predicate function
///
/// ## Parameters
///
/// - `registry`: The registry to filter
/// - `predicate`: Function that returns True for protocols to keep
///
/// ## Returns
///
/// A new Registry containing only matching protocols
///
pub fn filter(
  registry: Registry,
  predicate: fn(Protocol) -> Bool,
) -> Registry {
  let filtered =
    dict.filter(registry.protocols, fn(_name, proto) { predicate(proto) })
  Registry(protocols: filtered)
}

/// Maps over all protocols in the registry
///
/// ## Parameters
///
/// - `registry`: The registry to map over
/// - `mapper`: Function to apply to each protocol
///
/// ## Returns
///
/// A new Registry with transformed protocols
///
pub fn map(registry: Registry, mapper: fn(Protocol) -> Protocol) -> Registry {
  let mapped = dict.map_values(registry.protocols, fn(_name, proto) { mapper(proto) })
  Registry(protocols: mapped)
}
