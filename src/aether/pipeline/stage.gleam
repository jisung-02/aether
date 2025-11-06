import gleam/option.{type Option}

import aether/pipeline/error.{type StageError}

/// Metadata associated with a stage for documentation and debugging
///
/// This type provides additional information about a stage that can be
/// useful for understanding its purpose, configuration, and behavior.
///
pub type StageMetadata {
  /// Creates new stage metadata
  ///
  /// ## Parameters
  /// - `description`: Human-readable description of what the stage does
  /// - `version`: Optional version identifier for the stage implementation
  /// - `tags`: List of tags for categorization and searching
  /// - `config`: Optional configuration data as a string
  ///
  StageMetadata(
    description: String,
    version: Option(String),
    tags: List(String),
    config: Option(String),
  )
}

/// A processing stage that transforms input data to output data
///
/// ## Type Parameters
/// - `input`: The type of data this stage accepts as input
/// - `output`: The type of data this stage produces as output
///
/// ## Fields
/// - `name`: Unique identifier for this stage instance
/// - `process`: Function that performs the actual data transformation
/// - `metadata`: Optional metadata about the stage
///
pub type Stage(input, output) {
  /// Creates a new stage with name, processing function, and optional metadata
  ///
  /// ## Parameters
  /// - `name`: Unique name/identifier for this stage
  /// - `process`: Function that transforms input to Result(output, StageError)
  /// - `metadata`: Optional metadata about the stage
  ///
  Stage(
    name: String,
    process: fn(input) -> Result(output, StageError),
    metadata: Option(StageMetadata),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new stage with the given name and processing function
///
/// ## Parameters
///
/// - `name`: The name of the stage
/// - `process`: The processing function that transforms input to output
///
/// ## Returns
///
/// A new Stage instance with no metadata
///
pub fn new(
  name: String,
  process: fn(input) -> Result(output, StageError),
) -> Stage(input, output) {
  Stage(name, process, option.None)
}

/// Creates a new stage with the given name, processing function, and metadata
///
/// ## Parameters
///
/// - `name`: The name of the stage
/// - `process`: The processing function that transforms input to output
/// - `metadata`: The metadata for the stage
///
/// ## Returns
///
/// A new Stage instance with the specified metadata
///
pub fn new_with_metadata(
  name: String,
  process: fn(input) -> Result(output, StageError),
  metadata: StageMetadata,
) -> Stage(input, output) {
  Stage(name, process, option.Some(metadata))
}

/// Adds metadata to an existing stage
///
/// ## Parameters
///
/// - `stage`: The stage to add metadata to
/// - `metadata`: The metadata to add
///
/// ## Returns
///
/// A new Stage instance with the specified metadata
///
pub fn with_metadata(
  stage: Stage(input, output),
  metadata: StageMetadata,
) -> Stage(input, output) {
  Stage(stage.name, stage.process, option.Some(metadata))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Metadata Access Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the name of a stage
///
/// ## Parameters
///
/// - `stage`: The stage to get the name from
///
/// ## Returns
///
/// The name of the stage
///
pub fn get_name(stage: Stage(input, output)) -> String {
  stage.name
}

/// Gets the metadata of a stage
///
/// ## Parameters
///
/// - `stage`: The stage to get metadata from
///
/// ## Returns
///
/// An Option containing the metadata if present, or None if no metadata
///
pub fn get_metadata(stage: Stage(input, output)) -> Option(StageMetadata) {
  stage.metadata
}

/// Gets the description from a stage's metadata
///
/// ## Parameters
///
/// - `stage`: The stage to get the description from
///
/// ## Returns
///
/// An Option containing the description if metadata exists, or None
///
pub fn get_description(stage: Stage(input, output)) -> Option(String) {
  case stage.metadata {
    option.Some(metadata) -> option.Some(metadata.description)
    option.None -> option.None
  }
}

/// Gets the version from a stage's metadata
///
/// ## Parameters
///
/// - `stage`: The stage to get the version from
///
/// ## Returns
///
/// An Option containing the version if metadata exists and has a version, or None
///
pub fn get_version(stage: Stage(input, output)) -> Option(String) {
  case stage.metadata {
    option.Some(metadata) -> metadata.version
    option.None -> option.None
  }
}

/// Gets the tags from a stage's metadata
///
/// ## Parameters
///
/// - `stage`: The stage to get the tags from
///
/// ## Returns
///
/// A List containing the tags if metadata exists, or an empty list
///
pub fn get_tags(stage: Stage(input, output)) -> List(String) {
  case stage.metadata {
    option.Some(metadata) -> metadata.tags
    option.None -> []
  }
}

/// Gets the config from a stage's metadata
///
/// ## Parameters
///
/// - `stage`: The stage to get the config from
///
/// ## Returns
///
/// An Option containing the config if metadata exists, or None
///
pub fn get_config(stage: Stage(input, output)) -> Option(String) {
  case stage.metadata {
    option.Some(metadata) -> metadata.config
    option.None -> option.None
  }
}