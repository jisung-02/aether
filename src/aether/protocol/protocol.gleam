// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol Abstraction Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/core/data.{type Data}
import aether/pipeline/stage.{type Stage}
import gleam/option.{type Option}
import gleam/set.{type Set}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Protocol abstraction with decoder and encoder stages
///
/// A Protocol represents a network protocol layer that can encode and decode
/// data. Protocols can be composed together with ordering constraints to
/// build complete protocol stacks.
///
/// ## Examples
///
/// ```gleam
/// let tcp = protocol.new("tcp")
///   |> protocol.with_tag("transport")
///   |> protocol.with_decoder(tcp_decode_stage)
///   |> protocol.with_encoder(tcp_encode_stage)
///
/// let tls = protocol.new("tls")
///   |> protocol.with_tag("session")
///   |> protocol.with_tag("security")
///   |> protocol.requires("tcp")
///   |> protocol.must_come_after("tcp")
/// ```
///
pub type Protocol {
  Protocol(
    name: String,
    tags: Set(String),
    decoder: Option(Stage(Data, Data)),
    encoder: Option(Stage(Data, Data)),
    constraints: ProtocolConstraints,
    metadata: ProtocolMetadata,
  )
}

/// Optional ordering and dependency constraints for protocols
///
/// These constraints define relationships between protocols to ensure
/// valid protocol stack composition.
///
pub type ProtocolConstraints {
  ProtocolConstraints(
    /// Protocols that must appear before this one in the pipeline
    must_come_after: Set(String),
    /// Protocols that must appear after this one in the pipeline
    must_come_before: Set(String),
    /// Protocols that cannot coexist in the same pipeline
    conflicts_with: Set(String),
    /// Protocols that are required to be present in the pipeline
    requires: Set(String),
  )
}

/// Metadata about a protocol for documentation and versioning
///
pub type ProtocolMetadata {
  ProtocolMetadata(version: String, description: String, author: Option(String))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new Protocol with the given name
///
/// ## Parameters
///
/// - `name`: Unique identifier for this protocol
///
/// ## Returns
///
/// A new Protocol instance with default settings
///
/// ## Examples
///
/// ```gleam
/// let http = protocol.new("http")
/// ```
///
pub fn new(name: String) -> Protocol {
  Protocol(
    name: name,
    tags: set.new(),
    decoder: option.None,
    encoder: option.None,
    constraints: empty_constraints(),
    metadata: default_metadata(),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Tag Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Adds a tag to the protocol for categorization
///
/// Tags can be used to categorize protocols by layer, function, or other
/// criteria. Common tags include: "transport", "session", "application",
/// "security", "compression".
///
/// ## Parameters
///
/// - `protocol`: The protocol to add the tag to
/// - `tag`: The tag string to add
///
/// ## Returns
///
/// A new Protocol with the tag added
///
/// ## Examples
///
/// ```gleam
/// let tls = protocol.new("tls")
///   |> protocol.with_tag("session")
///   |> protocol.with_tag("security")
/// ```
///
pub fn with_tag(protocol: Protocol, tag: String) -> Protocol {
  Protocol(..protocol, tags: set.insert(protocol.tags, tag))
}

/// Adds multiple tags to the protocol at once
///
/// ## Parameters
///
/// - `protocol`: The protocol to add tags to
/// - `tags`: List of tag strings to add
///
/// ## Returns
///
/// A new Protocol with all tags added
///
pub fn with_tags(protocol: Protocol, tags: List(String)) -> Protocol {
  let new_tags =
    tags
    |> set.from_list()
    |> set.union(protocol.tags)
  Protocol(..protocol, tags: new_tags)
}

/// Checks if the protocol has a specific tag
///
/// ## Parameters
///
/// - `protocol`: The protocol to check
/// - `tag`: The tag to look for
///
/// ## Returns
///
/// True if the protocol has the tag, False otherwise
///
pub fn has_tag(protocol: Protocol, tag: String) -> Bool {
  set.contains(protocol.tags, tag)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decoder/Encoder Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the decoder stage for the protocol
///
/// The decoder stage transforms incoming data according to the protocol's
/// decoding rules (e.g., parsing TCP segments, decrypting TLS data).
///
/// ## Parameters
///
/// - `protocol`: The protocol to set the decoder for
/// - `decoder`: The stage that performs decoding
///
/// ## Returns
///
/// A new Protocol with the decoder set
///
pub fn with_decoder(protocol: Protocol, decoder: Stage(Data, Data)) -> Protocol {
  Protocol(..protocol, decoder: option.Some(decoder))
}

/// Sets the encoder stage for the protocol
///
/// The encoder stage transforms outgoing data according to the protocol's
/// encoding rules (e.g., creating TCP segments, encrypting with TLS).
///
/// ## Parameters
///
/// - `protocol`: The protocol to set the encoder for
/// - `encoder`: The stage that performs encoding
///
/// ## Returns
///
/// A new Protocol with the encoder set
///
pub fn with_encoder(protocol: Protocol, encoder: Stage(Data, Data)) -> Protocol {
  Protocol(..protocol, encoder: option.Some(encoder))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constraint Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Adds a "must come after" constraint
///
/// This constraint ensures that the specified protocol appears before
/// this protocol in any pipeline.
///
/// ## Parameters
///
/// - `protocol`: The protocol to add the constraint to
/// - `other`: The name of the protocol that must come before
///
/// ## Returns
///
/// A new Protocol with the constraint added
///
/// ## Examples
///
/// ```gleam
/// let tls = protocol.new("tls")
///   |> protocol.must_come_after("tcp")  // TLS must come after TCP
/// ```
///
pub fn must_come_after(protocol: Protocol, other: String) -> Protocol {
  let new_constraints =
    ProtocolConstraints(
      ..protocol.constraints,
      must_come_after: set.insert(protocol.constraints.must_come_after, other),
    )
  Protocol(..protocol, constraints: new_constraints)
}

/// Adds a "must come before" constraint
///
/// This constraint ensures that the specified protocol appears after
/// this protocol in any pipeline.
///
/// ## Parameters
///
/// - `protocol`: The protocol to add the constraint to
/// - `other`: The name of the protocol that must come after
///
/// ## Returns
///
/// A new Protocol with the constraint added
///
/// ## Examples
///
/// ```gleam
/// let gzip = protocol.new("gzip")
///   |> protocol.must_come_before("http")  // GZIP before HTTP
/// ```
///
pub fn must_come_before(protocol: Protocol, other: String) -> Protocol {
  let new_constraints =
    ProtocolConstraints(
      ..protocol.constraints,
      must_come_before: set.insert(protocol.constraints.must_come_before, other),
    )
  Protocol(..protocol, constraints: new_constraints)
}

/// Adds a required dependency constraint
///
/// This constraint ensures that the specified protocol is present
/// somewhere in the pipeline when this protocol is used.
///
/// ## Parameters
///
/// - `protocol`: The protocol to add the constraint to
/// - `other`: The name of the required protocol
///
/// ## Returns
///
/// A new Protocol with the constraint added
///
/// ## Examples
///
/// ```gleam
/// let tls = protocol.new("tls")
///   |> protocol.requires("tcp")  // TLS requires TCP to be present
/// ```
///
pub fn requires(protocol: Protocol, other: String) -> Protocol {
  let new_constraints =
    ProtocolConstraints(
      ..protocol.constraints,
      requires: set.insert(protocol.constraints.requires, other),
    )
  Protocol(..protocol, constraints: new_constraints)
}

/// Adds a conflict constraint
///
/// This constraint ensures that the specified protocol cannot be used
/// together with this protocol in the same pipeline.
///
/// ## Parameters
///
/// - `protocol`: The protocol to add the constraint to
/// - `other`: The name of the conflicting protocol
///
/// ## Returns
///
/// A new Protocol with the constraint added
///
/// ## Examples
///
/// ```gleam
/// let http1 = protocol.new("http1")
///   |> protocol.conflicts_with("http2")  // Cannot use both HTTP versions
/// ```
///
pub fn conflicts_with(protocol: Protocol, other: String) -> Protocol {
  let new_constraints =
    ProtocolConstraints(
      ..protocol.constraints,
      conflicts_with: set.insert(protocol.constraints.conflicts_with, other),
    )
  Protocol(..protocol, constraints: new_constraints)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Metadata Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets the complete metadata for the protocol
///
/// ## Parameters
///
/// - `protocol`: The protocol to set metadata for
/// - `metadata`: The metadata to set
///
/// ## Returns
///
/// A new Protocol with the metadata set
///
pub fn with_metadata(protocol: Protocol, metadata: ProtocolMetadata) -> Protocol {
  Protocol(..protocol, metadata: metadata)
}

/// Sets the version for the protocol
///
/// ## Parameters
///
/// - `protocol`: The protocol to set the version for
/// - `version`: The version string (e.g., "1.0.0")
///
/// ## Returns
///
/// A new Protocol with the version set
///
pub fn with_version(protocol: Protocol, version: String) -> Protocol {
  let new_metadata = ProtocolMetadata(..protocol.metadata, version: version)
  Protocol(..protocol, metadata: new_metadata)
}

/// Sets the description for the protocol
///
/// ## Parameters
///
/// - `protocol`: The protocol to set the description for
/// - `description`: Human-readable description
///
/// ## Returns
///
/// A new Protocol with the description set
///
pub fn with_description(protocol: Protocol, description: String) -> Protocol {
  let new_metadata =
    ProtocolMetadata(..protocol.metadata, description: description)
  Protocol(..protocol, metadata: new_metadata)
}

/// Sets the author for the protocol
///
/// ## Parameters
///
/// - `protocol`: The protocol to set the author for
/// - `author`: The author name
///
/// ## Returns
///
/// A new Protocol with the author set
///
pub fn with_author(protocol: Protocol, author: String) -> Protocol {
  let new_metadata =
    ProtocolMetadata(..protocol.metadata, author: option.Some(author))
  Protocol(..protocol, metadata: new_metadata)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accessor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the name of the protocol
///
pub fn get_name(protocol: Protocol) -> String {
  protocol.name
}

/// Gets the tags of the protocol
///
pub fn get_tags(protocol: Protocol) -> Set(String) {
  protocol.tags
}

/// Gets the decoder stage of the protocol
///
pub fn get_decoder(protocol: Protocol) -> Option(Stage(Data, Data)) {
  protocol.decoder
}

/// Gets the encoder stage of the protocol
///
pub fn get_encoder(protocol: Protocol) -> Option(Stage(Data, Data)) {
  protocol.encoder
}

/// Gets the constraints of the protocol
///
pub fn get_constraints(protocol: Protocol) -> ProtocolConstraints {
  protocol.constraints
}

/// Gets the metadata of the protocol
///
pub fn get_metadata(protocol: Protocol) -> ProtocolMetadata {
  protocol.metadata
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates empty constraints
///
fn empty_constraints() -> ProtocolConstraints {
  ProtocolConstraints(
    must_come_after: set.new(),
    must_come_before: set.new(),
    conflicts_with: set.new(),
    requires: set.new(),
  )
}

/// Creates default metadata
///
fn default_metadata() -> ProtocolMetadata {
  ProtocolMetadata(version: "1.0.0", description: "", author: option.None)
}

/// Creates a new ProtocolMetadata with all fields
///
pub fn new_metadata(
  version: String,
  description: String,
  author: Option(String),
) -> ProtocolMetadata {
  ProtocolMetadata(version: version, description: description, author: author)
}

/// Creates a new ProtocolConstraints with all fields
///
pub fn new_constraints(
  must_come_after: Set(String),
  must_come_before: Set(String),
  conflicts_with: Set(String),
  requires: Set(String),
) -> ProtocolConstraints {
  ProtocolConstraints(
    must_come_after: must_come_after,
    must_come_before: must_come_before,
    conflicts_with: conflicts_with,
    requires: requires,
  )
}
