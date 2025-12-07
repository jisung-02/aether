// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HPACK Static and Dynamic Table
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Implements HPACK header tables as per RFC 7541 Sections 2.3 and 4.
//
// The static table contains 61 predefined header field entries.
// The dynamic table is a FIFO structure for connection-specific headers.
//
// Indexing:
// - Index 0: Not used (reserved)
// - Index 1-61: Static table
// - Index 62+: Dynamic table (most recent entry = 62)
//

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Static table entry (RFC 7541 Appendix A)
///
pub type StaticEntry {
  StaticEntry(index: Int, name: String, value: String)
}

/// Dynamic table entry
///
pub type DynamicEntry {
  DynamicEntry(name: String, value: String, size: Int)
}

/// Dynamic table state
///
pub type DynamicTable {
  DynamicTable(
    /// Entries in insertion order (newest first)
    entries: List(DynamicEntry),
    /// Current total size in bytes
    size: Int,
    /// Maximum allowed size (from SETTINGS_HEADER_TABLE_SIZE)
    max_size: Int,
  )
}

/// Errors that can occur during table operations
///
pub type TableError {
  /// Index is out of valid range
  InvalidIndex(index: Int)

  /// Dynamic table size would exceed maximum
  TableSizeExceeded(current: Int, max: Int)

  /// Entry not found
  EntryNotFound(message: String)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Number of static table entries
pub const static_table_size = 61

/// Default maximum dynamic table size (4KB)
pub const default_max_dynamic_table_size = 4096

/// Overhead per dynamic table entry (RFC 7541 Section 4.1)
pub const entry_overhead = 32

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Static Table (RFC 7541 Appendix A)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// The static table defined in RFC 7541 Appendix A
///
const static_table: List(StaticEntry) = [
  StaticEntry(1, ":authority", ""),
  StaticEntry(2, ":method", "GET"),
  StaticEntry(3, ":method", "POST"),
  StaticEntry(4, ":path", "/"),
  StaticEntry(5, ":path", "/index.html"),
  StaticEntry(6, ":scheme", "http"),
  StaticEntry(7, ":scheme", "https"),
  StaticEntry(8, ":status", "200"),
  StaticEntry(9, ":status", "204"),
  StaticEntry(10, ":status", "206"),
  StaticEntry(11, ":status", "304"),
  StaticEntry(12, ":status", "400"),
  StaticEntry(13, ":status", "404"),
  StaticEntry(14, ":status", "500"),
  StaticEntry(15, "accept-charset", ""),
  StaticEntry(16, "accept-encoding", "gzip, deflate"),
  StaticEntry(17, "accept-language", ""),
  StaticEntry(18, "accept-ranges", ""),
  StaticEntry(19, "accept", ""),
  StaticEntry(20, "access-control-allow-origin", ""),
  StaticEntry(21, "age", ""),
  StaticEntry(22, "allow", ""),
  StaticEntry(23, "authorization", ""),
  StaticEntry(24, "cache-control", ""),
  StaticEntry(25, "content-disposition", ""),
  StaticEntry(26, "content-encoding", ""),
  StaticEntry(27, "content-language", ""),
  StaticEntry(28, "content-length", ""),
  StaticEntry(29, "content-location", ""),
  StaticEntry(30, "content-range", ""),
  StaticEntry(31, "content-type", ""),
  StaticEntry(32, "cookie", ""),
  StaticEntry(33, "date", ""),
  StaticEntry(34, "etag", ""),
  StaticEntry(35, "expect", ""),
  StaticEntry(36, "expires", ""),
  StaticEntry(37, "from", ""),
  StaticEntry(38, "host", ""),
  StaticEntry(39, "if-match", ""),
  StaticEntry(40, "if-modified-since", ""),
  StaticEntry(41, "if-none-match", ""),
  StaticEntry(42, "if-range", ""),
  StaticEntry(43, "if-unmodified-since", ""),
  StaticEntry(44, "last-modified", ""),
  StaticEntry(45, "link", ""),
  StaticEntry(46, "location", ""),
  StaticEntry(47, "max-forwards", ""),
  StaticEntry(48, "proxy-authenticate", ""),
  StaticEntry(49, "proxy-authorization", ""),
  StaticEntry(50, "range", ""),
  StaticEntry(51, "referer", ""),
  StaticEntry(52, "refresh", ""),
  StaticEntry(53, "retry-after", ""),
  StaticEntry(54, "server", ""),
  StaticEntry(55, "set-cookie", ""),
  StaticEntry(56, "strict-transport-security", ""),
  StaticEntry(57, "transfer-encoding", ""),
  StaticEntry(58, "user-agent", ""),
  StaticEntry(59, "vary", ""),
  StaticEntry(60, "via", ""),
  StaticEntry(61, "www-authenticate", ""),
]

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Static Table Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets a static table entry by index (1-61)
///
pub fn get_static_entry(index: Int) -> Result(StaticEntry, TableError) {
  case index >= 1 && index <= static_table_size {
    True -> {
      static_table
      |> list.find(fn(entry) { entry.index == index })
      |> result.replace_error(InvalidIndex(index))
    }
    False -> Error(InvalidIndex(index))
  }
}

/// Finds all static entries with the given name
///
pub fn find_static_by_name(name: String) -> List(StaticEntry) {
  static_table
  |> list.filter(fn(entry) { entry.name == name })
}

/// Finds static entry with exact name and value match
///
/// Returns the index if found, None otherwise.
///
pub fn find_static_by_name_value(name: String, value: String) -> Option(Int) {
  static_table
  |> list.find(fn(entry) { entry.name == name && entry.value == value })
  |> result.map(fn(entry) { entry.index })
  |> option.from_result
}

/// Finds static entry with matching name (value can differ)
///
/// Returns the index of the first match, None otherwise.
///
pub fn find_static_by_name_only(name: String) -> Option(Int) {
  static_table
  |> list.find(fn(entry) { entry.name == name })
  |> result.map(fn(entry) { entry.index })
  |> option.from_result
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Dynamic Table Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new empty dynamic table
///
pub fn new_dynamic_table(max_size: Int) -> DynamicTable {
  DynamicTable(entries: [], size: 0, max_size: max_size)
}

/// Calculates the size of a table entry (RFC 7541 Section 4.1)
///
/// Size = name_length + value_length + 32
///
pub fn calculate_entry_size(name: String, value: String) -> Int {
  string.byte_size(name) + string.byte_size(value) + entry_overhead
}

/// Creates a dynamic entry from name and value
///
fn make_dynamic_entry(name: String, value: String) -> DynamicEntry {
  let size = calculate_entry_size(name, value)
  DynamicEntry(name: name, value: value, size: size)
}

/// Inserts a new entry into the dynamic table
///
/// New entries are prepended (index 62 is always the newest).
/// Evicts old entries if necessary to maintain max_size.
///
pub fn insert_entry(
  table: DynamicTable,
  name: String,
  value: String,
) -> DynamicTable {
  let entry = make_dynamic_entry(name, value)

  // Check if entry itself exceeds max size
  case entry.size > table.max_size {
    True -> {
      // Entry is larger than max size - clear table and don't insert
      DynamicTable(..table, entries: [], size: 0)
    }
    False -> {
      // Prepend new entry
      let new_entries = [entry, ..table.entries]
      let new_size = table.size + entry.size

      // Evict entries from the end until size is within limit
      let evicted_table =
        DynamicTable(..table, entries: new_entries, size: new_size)
      evict_entries_if_needed(evicted_table)
    }
  }
}

/// Evicts entries from the end of the table until size <= max_size
///
fn evict_entries_if_needed(table: DynamicTable) -> DynamicTable {
  case table.size > table.max_size {
    False -> table
    True -> {
      // Remove entries from the end until size is acceptable
      evict_entries_recursive(table)
    }
  }
}

fn evict_entries_recursive(table: DynamicTable) -> DynamicTable {
  case table.size > table.max_size, table.entries {
    False, _ -> table
    True, [] -> table
    True, _ -> {
      // Remove last entry
      let new_entries = list.take(table.entries, list.length(table.entries) - 1)
      let new_size =
        new_entries
        |> list.fold(0, fn(acc, entry) { acc + entry.size })

      let new_table =
        DynamicTable(..table, entries: new_entries, size: new_size)
      evict_entries_recursive(new_table)
    }
  }
}

/// Gets a dynamic table entry by index (62+)
///
/// Index 62 is the most recently inserted entry.
///
pub fn get_dynamic_entry(
  table: DynamicTable,
  index: Int,
) -> Result(DynamicEntry, TableError) {
  let dynamic_index = index - static_table_size - 1

  case dynamic_index >= 0 && dynamic_index < list.length(table.entries) {
    True -> {
      table.entries
      |> list.drop(dynamic_index)
      |> list.first
      |> result.replace_error(InvalidIndex(index))
    }
    False -> Error(InvalidIndex(index))
  }
}

/// Finds dynamic entry with exact name and value match
///
/// Returns the absolute index if found (62+), None otherwise.
///
pub fn find_dynamic_by_name_value(
  table: DynamicTable,
  name: String,
  value: String,
) -> Option(Int) {
  table.entries
  |> list.index_fold(None, fn(acc, entry, idx) {
    case acc {
      Some(_) -> acc
      None ->
        case entry.name == name && entry.value == value {
          True -> Some(static_table_size + idx + 1)
          False -> None
        }
    }
  })
}

/// Finds dynamic entry with matching name (value can differ)
///
/// Returns the absolute index of the first match (62+), None otherwise.
///
pub fn find_dynamic_by_name_only(
  table: DynamicTable,
  name: String,
) -> Option(Int) {
  table.entries
  |> list.index_fold(None, fn(acc, entry, idx) {
    case acc {
      Some(_) -> acc
      None ->
        case entry.name == name {
          True -> Some(static_table_size + idx + 1)
          False -> None
        }
    }
  })
}

/// Updates the maximum size of the dynamic table
///
/// If the new size is smaller, entries are evicted from the end.
///
pub fn update_max_size(table: DynamicTable, new_max_size: Int) -> DynamicTable {
  let updated_table = DynamicTable(..table, max_size: new_max_size)

  case new_max_size == 0 {
    True -> DynamicTable(..updated_table, entries: [], size: 0)
    False -> evict_entries_if_needed(updated_table)
  }
}

/// Clears all entries from the dynamic table
///
pub fn clear_dynamic_table(table: DynamicTable) -> DynamicTable {
  DynamicTable(..table, entries: [], size: 0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Combined Table Functions (Static + Dynamic)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets an entry from either static or dynamic table
///
/// - Index 1-61: Static table
/// - Index 62+: Dynamic table
///
pub fn get_entry(
  table: DynamicTable,
  index: Int,
) -> Result(#(String, String), TableError) {
  case index {
    0 -> Error(InvalidIndex(0))
    _ if index <= static_table_size -> {
      get_static_entry(index)
      |> result.map(fn(entry) { #(entry.name, entry.value) })
    }
    _ -> {
      get_dynamic_entry(table, index)
      |> result.map(fn(entry) { #(entry.name, entry.value) })
    }
  }
}

/// Finds entry with exact name and value match in both tables
///
/// Searches static table first, then dynamic table.
/// Returns the index if found, None otherwise.
///
pub fn find_by_name_value(
  table: DynamicTable,
  name: String,
  value: String,
) -> Option(Int) {
  // Check static table first
  case find_static_by_name_value(name, value) {
    Some(idx) -> Some(idx)
    None -> find_dynamic_by_name_value(table, name, value)
  }
}

/// Finds entry with matching name in both tables
///
/// Searches static table first, then dynamic table.
/// Returns the index of the first match, None otherwise.
///
pub fn find_by_name_only(table: DynamicTable, name: String) -> Option(Int) {
  // Check static table first
  case find_static_by_name_only(name) {
    Some(idx) -> Some(idx)
    None -> find_dynamic_by_name_only(table, name)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts a TableError to a human-readable string
///
pub fn table_error_to_string(error: TableError) -> String {
  case error {
    InvalidIndex(index) -> "Invalid table index: " <> int.to_string(index)
    TableSizeExceeded(current, max) ->
      "Table size exceeded: "
      <> int.to_string(current)
      <> " > "
      <> int.to_string(max)
    EntryNotFound(message) -> "Entry not found: " <> message
  }
}

/// Gets the number of entries in the dynamic table
///
pub fn get_dynamic_table_length(table: DynamicTable) -> Int {
  list.length(table.entries)
}

/// Gets the current size of the dynamic table in bytes
///
pub fn get_dynamic_table_size(table: DynamicTable) -> Int {
  table.size
}
