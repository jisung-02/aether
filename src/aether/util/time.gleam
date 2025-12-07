import gleam/erlang/atom

/// Get the current system time in microseconds
///
/// This function uses Erlang's `system_time/1` to get a high-resolution
/// timestamp for performance measurement.
///
/// ## Returns
///
/// The current system time in microseconds since the Unix epoch
///
pub fn now_microseconds() -> Int {
  erlang_system_time(atom.create("microsecond"))
}

/// Get the current system time in milliseconds
///
/// ## Returns
///
/// The current system time in milliseconds since the Unix epoch
///
pub fn now_milliseconds() -> Int {
  erlang_system_time(atom.create("millisecond"))
}

/// Calculate the duration between two timestamps in microseconds
///
/// ## Parameters
///
/// - `start`: The start timestamp in microseconds
/// - `end`: The end timestamp in microseconds
///
/// ## Returns
///
/// The duration in microseconds (end - start)
///
pub fn duration_microseconds(start: Int, end: Int) -> Int {
  end - start
}

/// Calculate the duration between two timestamps in milliseconds
///
/// ## Parameters
///
/// - `start`: The start timestamp in milliseconds
/// - `end`: The end timestamp in milliseconds
///
/// ## Returns
///
/// The duration in milliseconds (end - start)
///
pub fn duration_milliseconds(start: Int, end: Int) -> Int {
  end - start
}

/// Convert microseconds to milliseconds
///
/// ## Parameters
///
/// - `microseconds`: Time in microseconds
///
/// ## Returns
///
/// Time in milliseconds (rounded down)
///
pub fn microseconds_to_milliseconds(microseconds: Int) -> Int {
  microseconds / 1000
}

/// Convert milliseconds to microseconds
///
/// ## Parameters
///
/// - `milliseconds`: Time in milliseconds
///
/// ## Returns
///
/// Time in microseconds
///
pub fn milliseconds_to_microseconds(milliseconds: Int) -> Int {
  milliseconds * 1000
}

// Erlang FFI for system time
@external(erlang, "erlang", "system_time")
fn erlang_system_time(unit: atom.Atom) -> Int
