import aether/core/data.{type Data}
import aether/pipeline/stage
import aether/protocol/protocol
import gleam/option
import gleam/set
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol Creation Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_creates_protocol_with_name_test() {
  let proto = protocol.new("tcp")

  protocol.get_name(proto)
  |> should.equal("tcp")
}

pub fn new_creates_protocol_with_empty_tags_test() {
  let proto = protocol.new("http")

  protocol.get_tags(proto)
  |> set.is_empty()
  |> should.be_true()
}

pub fn new_creates_protocol_with_no_decoder_test() {
  let proto = protocol.new("tcp")

  protocol.get_decoder(proto)
  |> should.equal(option.None)
}

pub fn new_creates_protocol_with_no_encoder_test() {
  let proto = protocol.new("tcp")

  protocol.get_encoder(proto)
  |> should.equal(option.None)
}

pub fn new_creates_protocol_with_default_metadata_test() {
  let proto = protocol.new("tcp")
  let metadata = protocol.get_metadata(proto)

  metadata.version
  |> should.equal("1.0.0")

  metadata.description
  |> should.equal("")

  metadata.author
  |> should.equal(option.None)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Tag Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn with_tag_adds_single_tag_test() {
  let proto =
    protocol.new("tcp")
    |> protocol.with_tag("transport")

  protocol.get_tags(proto)
  |> set.contains("transport")
  |> should.be_true()
}

pub fn with_tag_adds_multiple_tags_test() {
  let proto =
    protocol.new("tls")
    |> protocol.with_tag("session")
    |> protocol.with_tag("security")

  let tags = protocol.get_tags(proto)

  set.contains(tags, "session")
  |> should.be_true()

  set.contains(tags, "security")
  |> should.be_true()
}

pub fn with_tag_is_idempotent_test() {
  let proto =
    protocol.new("tcp")
    |> protocol.with_tag("transport")
    |> protocol.with_tag("transport")

  protocol.get_tags(proto)
  |> set.size()
  |> should.equal(1)
}

pub fn with_tags_adds_multiple_at_once_test() {
  let proto =
    protocol.new("tls")
    |> protocol.with_tags(["session", "security", "encryption"])

  let tags = protocol.get_tags(proto)

  set.size(tags)
  |> should.equal(3)
}

pub fn has_tag_returns_true_for_existing_tag_test() {
  let proto =
    protocol.new("tcp")
    |> protocol.with_tag("transport")

  protocol.has_tag(proto, "transport")
  |> should.be_true()
}

pub fn has_tag_returns_false_for_missing_tag_test() {
  let proto =
    protocol.new("tcp")
    |> protocol.with_tag("transport")

  protocol.has_tag(proto, "session")
  |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Decoder/Encoder Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn with_decoder_sets_decoder_stage_test() {
  let decode_stage: stage.Stage(Data, Data) =
    stage.new("tcp_decode", fn(data) { Ok(data) })

  let proto =
    protocol.new("tcp")
    |> protocol.with_decoder(decode_stage)

  protocol.get_decoder(proto)
  |> option.is_some()
  |> should.be_true()
}

pub fn with_encoder_sets_encoder_stage_test() {
  let encode_stage: stage.Stage(Data, Data) =
    stage.new("tcp_encode", fn(data) { Ok(data) })

  let proto =
    protocol.new("tcp")
    |> protocol.with_encoder(encode_stage)

  protocol.get_encoder(proto)
  |> option.is_some()
  |> should.be_true()
}

pub fn protocol_can_have_both_decoder_and_encoder_test() {
  let decode_stage: stage.Stage(Data, Data) =
    stage.new("tcp_decode", fn(data) { Ok(data) })
  let encode_stage: stage.Stage(Data, Data) =
    stage.new("tcp_encode", fn(data) { Ok(data) })

  let proto =
    protocol.new("tcp")
    |> protocol.with_decoder(decode_stage)
    |> protocol.with_encoder(encode_stage)

  protocol.get_decoder(proto)
  |> option.is_some()
  |> should.be_true()

  protocol.get_encoder(proto)
  |> option.is_some()
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constraint Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn must_come_after_adds_constraint_test() {
  let proto =
    protocol.new("tls")
    |> protocol.must_come_after("tcp")

  let constraints = protocol.get_constraints(proto)

  set.contains(constraints.must_come_after, "tcp")
  |> should.be_true()
}

pub fn must_come_before_adds_constraint_test() {
  let proto =
    protocol.new("gzip")
    |> protocol.must_come_before("http")

  let constraints = protocol.get_constraints(proto)

  set.contains(constraints.must_come_before, "http")
  |> should.be_true()
}

pub fn requires_adds_dependency_test() {
  let proto =
    protocol.new("tls")
    |> protocol.requires("tcp")

  let constraints = protocol.get_constraints(proto)

  set.contains(constraints.requires, "tcp")
  |> should.be_true()
}

pub fn conflicts_with_adds_conflict_test() {
  let proto =
    protocol.new("http1")
    |> protocol.conflicts_with("http2")

  let constraints = protocol.get_constraints(proto)

  set.contains(constraints.conflicts_with, "http2")
  |> should.be_true()
}

pub fn multiple_constraints_can_be_combined_test() {
  let proto =
    protocol.new("tls")
    |> protocol.requires("tcp")
    |> protocol.must_come_after("tcp")
    |> protocol.conflicts_with("plain")

  let constraints = protocol.get_constraints(proto)

  set.contains(constraints.requires, "tcp")
  |> should.be_true()

  set.contains(constraints.must_come_after, "tcp")
  |> should.be_true()

  set.contains(constraints.conflicts_with, "plain")
  |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Metadata Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn with_version_sets_version_test() {
  let proto =
    protocol.new("tcp")
    |> protocol.with_version("2.0.0")

  let metadata = protocol.get_metadata(proto)

  metadata.version
  |> should.equal("2.0.0")
}

pub fn with_description_sets_description_test() {
  let proto =
    protocol.new("tcp")
    |> protocol.with_description("Transmission Control Protocol")

  let metadata = protocol.get_metadata(proto)

  metadata.description
  |> should.equal("Transmission Control Protocol")
}

pub fn with_author_sets_author_test() {
  let proto =
    protocol.new("tcp")
    |> protocol.with_author("IETF")

  let metadata = protocol.get_metadata(proto)

  metadata.author
  |> should.equal(option.Some("IETF"))
}

pub fn with_metadata_replaces_all_metadata_test() {
  let custom_metadata =
    protocol.new_metadata("3.0.0", "Custom Protocol", option.Some("Author"))

  let proto =
    protocol.new("custom")
    |> protocol.with_metadata(custom_metadata)

  let metadata = protocol.get_metadata(proto)

  metadata.version
  |> should.equal("3.0.0")

  metadata.description
  |> should.equal("Custom Protocol")

  metadata.author
  |> should.equal(option.Some("Author"))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Builder Pattern Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn builder_pattern_chains_correctly_test() {
  let decode_stage: stage.Stage(Data, Data) =
    stage.new("tcp_decode", fn(data) { Ok(data) })
  let encode_stage: stage.Stage(Data, Data) =
    stage.new("tcp_encode", fn(data) { Ok(data) })

  let proto =
    protocol.new("tcp")
    |> protocol.with_tag("transport")
    |> protocol.with_tag("reliable")
    |> protocol.with_decoder(decode_stage)
    |> protocol.with_encoder(encode_stage)
    |> protocol.with_version("1.1.0")
    |> protocol.with_description("TCP Protocol")
    |> protocol.with_author("IETF")

  // Verify all properties
  protocol.get_name(proto)
  |> should.equal("tcp")

  let tags = protocol.get_tags(proto)
  set.size(tags)
  |> should.equal(2)

  protocol.get_decoder(proto)
  |> option.is_some()
  |> should.be_true()

  protocol.get_encoder(proto)
  |> option.is_some()
  |> should.be_true()

  let metadata = protocol.get_metadata(proto)
  metadata.version
  |> should.equal("1.1.0")
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Immutability Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn operations_are_immutable_test() {
  let original = protocol.new("tcp")
  let modified = protocol.with_tag(original, "transport")

  // Original should still have no tags
  protocol.get_tags(original)
  |> set.is_empty()
  |> should.be_true()

  // Modified should have the tag
  protocol.get_tags(modified)
  |> set.contains("transport")
  |> should.be_true()
}
