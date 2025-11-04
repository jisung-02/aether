import gleam/int
import gleam/float
import gleam/string
import gleam/bit_array
import gleam/option.{type Option}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub type Message {
  Message(
    bytes: BitArray, // Request body before serialization
    metadata: Dict(String, Dynamic), // Metadata for the request (e.g., HTTP request headers)
    context: Context, //Information attached at the framework level
  )
}

pub type Context {
  Context(
    request_id: String,
    started_at: Int,  // microseconds
    custom: Dict(String, Dynamic),
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Message Operations
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates new Message with given bytes
pub fn new(bytes: BitArray) -> Message {
  Message(
    bytes: bytes,
    metadata: dict.new(),
    context: new_context(),
  )
}

/// Creates new Message with empty bytes
pub fn empty() -> Message {
  new(<<>>)
}

/// Creates new Message from a string
pub fn from_string(str: String) -> Message {
  new(<<str:utf8>>)
}

/// Gets the bytes from data
pub fn bytes(message: Message) -> BitArray {
  message.bytes
}

/// Updates bytes (immutable)
pub fn set_bytes(message: Message, bytes: BitArray) -> Message {
  Message(..message, bytes: bytes)
}

/// Appends bytes to existing data
pub fn append_bytes(message: Message, additional: BitArray) -> Message {
  let new_bytes = <<message.bytes:bits, additional:bits>>
  Message(..message, bytes: new_bytes)
}

/// Gets the size of bytes in the data
pub fn byte_size(message: Message) -> Int {
  bit_array.byte_size(message.bytes)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Metadata Operations
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets metadata value (immutable update)
///
/// ## Examples
///
/// ```gleam
/// let message = new(<<>>)
/// let updated = set_metadata(message, "content-type", dynamic.from("application/json"))
/// ```
pub fn set_metadata(message: Message, key: String, value: Dynamic) -> Message {
  Message(..message, metadata: dict.insert(message.metadata, key, value))
}

/// Gets metadata value
///
/// Returns None if key doesn't exist
pub fn get_metadata(message: Message, key: String) -> Option(Dynamic) {
  dict.get(message.metadata, key)
  |> option.from_result()
}

/// Deletes metadata key (immutable)
pub fn delete_metadata(message: Message, key: String) -> Message {
  Message(..message, metadata: dict.delete(message.metadata, key))
}

/// Checks if metadata key exists
pub fn has_metadata(message: Message, key: String) -> Bool {
  dict.has_key(message.metadata, key)
}

/// Gets all metadata keys
pub fn metadata_keys(message: Message) -> List(String) {
  dict.keys(message.metadata)
}

/// Merges metadata from another dict (immutable)
///
/// Values from the new metadata will override existing keys
pub fn merge_metadata(message: Message, new_metadata: Dict(String, Dynamic)) -> Message {
  let merged = dict.merge(message.metadata, new_metadata)
  Message(..message, metadata: merged)
}

/// Clears all metadata (immutable)
pub fn clear_metadata(message: Message) -> Message {
  Message(..message, metadata: dict.new())
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Context Operations
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates new Context with unique ID
///
/// Automatically generates a unique request ID and captures the current time
pub fn new_context() -> Context {
  let request_id = generate_request_id()
  let now = system_time_microseconds()

  Context(
    request_id: request_id,
    started_at: now,
    custom: dict.new(),
  )
}

/// Creates Context with a specific request ID
///
/// Useful for testing or when continuing an existing request context
pub fn new_context_with_id(request_id: String) -> Context {
  Context(
    request_id: request_id,
    started_at: system_time_microseconds(),
    custom: dict.new(),
  )
}

/// Gets the request ID from data
pub fn request_id(message: Message) -> String {
  message.context.request_id
}

/// Gets the started_at timestamp from data (in microseconds)
pub fn started_at(message: Message) -> Int {
  message.context.started_at
}

/// Calculates elapsed time in microseconds since request started
pub fn elapsed_microseconds(message: Message) -> Int {
  system_time_microseconds() - message.context.started_at
}

/// Calculates elapsed time in milliseconds since request started
pub fn elapsed_milliseconds(message: Message) -> Int {
  elapsed_microseconds(message) / 1000
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Custom Context Data Operations
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Sets custom context data (immutable)
///
/// Useful for passing data between middlewares
///
/// ## Examples
///
/// ```gleam
/// // In auth middleware
/// let message = set_context_data(message, "user_id", dynamic.from("alice"))
///
/// // In handler
/// case get_context_data(message, "user_id") {
///   Some(user_id) -> // use user_id
///   None -> // handle unauthenticated
/// }
/// ```
pub fn set_context_data(message: Message, key: String, value: Dynamic) -> Message {
  let new_custom = dict.insert(message.context.custom, key, value)
  let new_context = Context(..message.context, custom: new_custom)
  Message(..message, context: new_context)
}

/// Gets custom context data
///
/// Returns None if key doesn't exist
pub fn get_context_data(message: Message, key: String) -> Option(Dynamic) {
  dict.get(message.context.custom, key)
  |> option.from_result()
}

/// Deletes custom context data (immutable)
pub fn delete_context_data(message: Message, key: String) -> Message {
  let new_custom = dict.delete(message.context.custom, key)
  let new_context = Context(..message.context, custom: new_custom)
  Message(..message, context: new_context)
}

/// Checks if custom context data key exists
pub fn has_context_data(message: Message, key: String) -> Bool {
  dict.has_key(message.context.custom, key)
}

/// Gets all custom context data keys
pub fn context_data_keys(message: Message) -> List(String) {
  dict.keys(message.context.custom)
}

/// Merges custom context data from another dict (immutable)
pub fn merge_context_data(message: Message, new_custom: Dict(String, Dynamic)) -> Message {
  let merged = dict.merge(message.context.custom, new_custom)
  let new_context = Context(..message.context, custom: merged)
  Message(..message, context: new_context)
}

/// Clears all custom context data (immutable)
pub fn clear_context_data(message: Message) -> Message {
  let new_context = Context(..message.context, custom: dict.new())
  Message(..message, context: new_context)
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Utility Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Generates a unique request ID
/// 
/// Format: "req_{timestamp}_{random}"
fn generate_request_id() -> String {
  let timestamp = system_time_microseconds()
  let random = erlang_random_integer()
  
  string.concat([
    "req_",
    int.to_string(timestamp),
    "_",
    int.to_string(random),
  ])
}

/// Gets current system time in microseconds
@external(erlang, "erlang", "system_time")
fn system_time_microseconds() -> Int

/// Generates a random integer
/// 
/// Uses Erlang's rand:uniform/0 which returns a float between 0.0 and 1.0,
/// then converts to integer
@external(erlang, "rand", "uniform")
fn erlang_random_float() -> Float

fn erlang_random_integer() -> Int {
  let random_float = erlang_random_float()
  let scaled = random_float *. 1000000.0
  float.round(scaled)
}