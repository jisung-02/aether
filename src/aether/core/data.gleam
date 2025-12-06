// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Data Type Definition
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import aether/core/message.{type Message}

/// Data type alias for protocol processing
///
/// This type represents the data that flows through protocol stages.
/// It is an alias to Message, which provides:
/// - `bytes`: Raw binary data (BitArray)
/// - `metadata`: Key-value metadata (Dict)
/// - `context`: Request context with timing and custom data
///
/// ## Usage
///
/// ```gleam
/// import aether/core/data.{type Data}
/// import aether/pipeline/stage.{type Stage}
///
/// // Define a protocol decoder stage
/// let decode_stage: Stage(Data, Data) = stage.new("tcp_decode", fn(data) {
///   // Process data.bytes and return updated Data
///   Ok(data)
/// })
/// ```
///
pub type Data =
  Message
