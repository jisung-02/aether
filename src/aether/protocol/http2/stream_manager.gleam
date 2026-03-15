// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP/2 Stream Manager
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Coordinates multiple concurrent HTTP/2 streams within a connection.
// Handles stream creation, lookup, lifecycle management, and enforces
// connection-level limits.
//
// Key Responsibilities:
// - Stream ID allocation (odd for client, even for server)
// - Concurrent stream limits (MAX_CONCURRENT_STREAMS)
// - Stream lookup by ID
// - Stream state transitions
// - Stream cleanup on close
//

import gleam/dict.{type Dict}
import gleam/int
import gleam/list

import aether/protocol/http2/error.{
  type ConnectionError, type ErrorCode, type StreamError, Protocol,
  ProtocolError, RefusedStream, StreamClosed, StreamProtocol,
}
import aether/protocol/http2/frame.{
  default_initial_window_size, default_max_concurrent_streams,
}
import aether/protocol/http2/stream.{
  type Stream, type StreamEvent, type StreamState, Idle, Stream,
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Connection Role
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// The role of this endpoint in the HTTP/2 connection
///
pub type Role {
  /// Client role - initiates streams with odd IDs
  Client
  /// Server role - initiates streams with even IDs (via PUSH_PROMISE)
  Server
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Manager Configuration
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Configuration settings for stream management
///
pub type StreamSettings {
  StreamSettings(
    /// Maximum number of concurrent streams allowed
    /// Default: 0x7FFFFFFF (unlimited)
    max_concurrent_streams: Int,
    /// Initial window size for new streams
    /// Default: 65535
    initial_window_size: Int,
    /// Whether server push is enabled
    /// Default: true
    enable_push: Bool,
  )
}

/// Default stream settings
///
pub fn default_settings() -> StreamSettings {
  StreamSettings(
    max_concurrent_streams: default_max_concurrent_streams,
    initial_window_size: default_initial_window_size,
    enable_push: True,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Manager Type
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Manages all streams within an HTTP/2 connection
///
pub type StreamManager {
  StreamManager(
    /// Role of this endpoint (Client or Server)
    role: Role,
    /// Map of stream ID to Stream
    streams: Dict(Int, Stream),
    /// Next stream ID to use when creating a new stream
    /// Client: starts at 1, increments by 2 (odd)
    /// Server: starts at 2, increments by 2 (even)
    next_stream_id: Int,
    /// Highest stream ID received from the peer
    highest_peer_stream_id: Int,
    /// Local settings (what we have sent)
    local_settings: StreamSettings,
    /// Remote settings (what peer has sent)
    remote_settings: StreamSettings,
    /// Number of currently active streams
    active_stream_count: Int,
    /// Last stream ID that was or might be processed (for GOAWAY)
    last_stream_id: Int,
    /// Whether the connection is in GOAWAY state
    going_away: Bool,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Manager Creation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new stream manager for the given role
///
pub fn new(role: Role) -> StreamManager {
  let next_id = case role {
    Client -> 1
    // Odd IDs
    Server -> 2
    // Even IDs
  }

  StreamManager(
    role: role,
    streams: dict.new(),
    next_stream_id: next_id,
    highest_peer_stream_id: 0,
    local_settings: default_settings(),
    remote_settings: default_settings(),
    active_stream_count: 0,
    last_stream_id: 0,
    going_away: False,
  )
}

/// Creates a client stream manager
///
pub fn new_client() -> StreamManager {
  new(Client)
}

/// Creates a server stream manager
///
pub fn new_server() -> StreamManager {
  new(Server)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Creation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new locally-initiated stream
///
/// Returns the updated manager and the new stream, or an error if
/// the concurrent stream limit is exceeded.
///
pub fn create_stream(
  manager: StreamManager,
) -> Result(#(StreamManager, Stream), ConnectionError) {
  // Check if we're accepting new streams
  case manager.going_away {
    True -> Error(Protocol(ProtocolError, "Connection is going away"))
    False -> {
      // Check concurrent stream limit
      case
        manager.active_stream_count
        >= manager.remote_settings.max_concurrent_streams
      {
        True ->
          Error(Protocol(
            RefusedStream,
            "Maximum concurrent streams exceeded: "
              <> int.to_string(manager.active_stream_count)
              <> " >= "
              <> int.to_string(manager.remote_settings.max_concurrent_streams),
          ))
        False -> {
          let stream_id = manager.next_stream_id
          let new_stream =
            stream.new_with_windows(
              stream_id,
              manager.remote_settings.initial_window_size,
              manager.local_settings.initial_window_size,
            )

          // Apply initial state transition to Open
          case stream.apply_event(new_stream, stream.SendHeaders) {
            Ok(opened_stream) -> {
              let updated_manager =
                StreamManager(
                  ..manager,
                  streams: dict.insert(
                    manager.streams,
                    stream_id,
                    opened_stream,
                  ),
                  next_stream_id: manager.next_stream_id + 2,
                  active_stream_count: manager.active_stream_count + 1,
                  last_stream_id: stream_id,
                )
              Ok(#(updated_manager, opened_stream))
            }
            Error(_) -> Error(Protocol(ProtocolError, "Failed to open stream"))
          }
        }
      }
    }
  }
}

/// Creates or retrieves a stream for receiving peer-initiated traffic
///
/// This is called when we receive a HEADERS frame on a new stream ID.
///
pub fn get_or_create_peer_stream(
  manager: StreamManager,
  stream_id: Int,
) -> Result(#(StreamManager, Stream), ConnectionError) {
  // Validate stream ID
  case validate_peer_stream_id(manager, stream_id) {
    Error(err) -> Error(err)
    Ok(Nil) -> {
      case dict.get(manager.streams, stream_id) {
        // Stream exists
        Ok(existing_stream) -> Ok(#(manager, existing_stream))
        // New stream from peer
        Error(Nil) -> {
          // Check concurrent stream limit
          case
            manager.active_stream_count
            >= manager.local_settings.max_concurrent_streams
          {
            True ->
              Error(Protocol(
                RefusedStream,
                "Peer exceeded maximum concurrent streams",
              ))
            False -> {
              // Create new stream in Idle state
              let new_stream =
                stream.new_with_windows(
                  stream_id,
                  manager.remote_settings.initial_window_size,
                  manager.local_settings.initial_window_size,
                )

              let updated_manager =
                StreamManager(
                  ..manager,
                  streams: dict.insert(manager.streams, stream_id, new_stream),
                  highest_peer_stream_id: int.max(
                    manager.highest_peer_stream_id,
                    stream_id,
                  ),
                  active_stream_count: manager.active_stream_count + 1,
                  last_stream_id: int.max(manager.last_stream_id, stream_id),
                )

              Ok(#(updated_manager, new_stream))
            }
          }
        }
      }
    }
  }
}

/// Validates that a stream ID from the peer is valid
///
fn validate_peer_stream_id(
  manager: StreamManager,
  stream_id: Int,
) -> Result(Nil, ConnectionError) {
  // Stream ID must be positive
  case stream_id <= 0 {
    True ->
      Error(Protocol(ProtocolError, "Invalid stream ID: must be positive"))
    False -> {
      // Check if stream ID has correct parity for peer
      let is_peer_initiated = case manager.role {
        Client -> stream.is_server_initiated(stream_id)
        Server -> stream.is_client_initiated(stream_id)
      }

      case is_peer_initiated {
        False ->
          Error(Protocol(
            ProtocolError,
            "Stream ID has wrong parity for peer-initiated stream",
          ))
        True -> {
          // Stream ID must not be less than highest seen
          case stream_id <= manager.highest_peer_stream_id {
            True -> {
              // Could be a valid existing stream or an error
              case dict.has_key(manager.streams, stream_id) {
                True -> Ok(Nil)
                False ->
                  Error(Protocol(
                    ProtocolError,
                    "Stream ID less than highest seen but stream doesn't exist",
                  ))
              }
            }
            False -> Ok(Nil)
          }
        }
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Lookup
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets a stream by ID
///
pub fn get_stream(manager: StreamManager, stream_id: Int) -> Result(Stream, Nil) {
  dict.get(manager.streams, stream_id)
}

/// Checks if a stream exists
///
pub fn has_stream(manager: StreamManager, stream_id: Int) -> Bool {
  dict.has_key(manager.streams, stream_id)
}

/// Gets all active (non-idle, non-closed) streams
///
pub fn get_active_streams(manager: StreamManager) -> List(Stream) {
  manager.streams
  |> dict.values()
  |> list.filter(stream.is_active)
}

/// Gets all stream IDs
///
pub fn get_stream_ids(manager: StreamManager) -> List(Int) {
  dict.keys(manager.streams)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream State Transitions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Applies an event to a stream and updates the manager
///
pub fn apply_stream_event(
  manager: StreamManager,
  stream_id: Int,
  event: StreamEvent,
) -> Result(StreamManager, StreamError) {
  case dict.get(manager.streams, stream_id) {
    Error(Nil) ->
      Error(StreamProtocol(stream_id, StreamClosed, "Stream not found"))
    Ok(s) -> {
      case stream.apply_event(s, event) {
        Ok(updated_stream) -> {
          // Check if stream transitioned to closed
          let active_count = case stream.is_closed(updated_stream) {
            True -> int.max(0, manager.active_stream_count - 1)
            False -> manager.active_stream_count
          }

          Ok(
            StreamManager(
              ..manager,
              streams: dict.insert(manager.streams, stream_id, updated_stream),
              active_stream_count: active_count,
            ),
          )
        }
        Error(err) -> Error(err)
      }
    }
  }
}

/// Updates a stream in the manager
///
pub fn update_stream(manager: StreamManager, s: Stream) -> StreamManager {
  StreamManager(..manager, streams: dict.insert(manager.streams, s.id, s))
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RST_STREAM Handling
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Resets a stream with the given error code
///
pub fn reset_stream(
  manager: StreamManager,
  stream_id: Int,
  code: ErrorCode,
) -> Result(StreamManager, StreamError) {
  case dict.get(manager.streams, stream_id) {
    Error(Nil) ->
      Error(StreamProtocol(stream_id, StreamClosed, "Stream not found"))
    Ok(s) -> {
      let reset_s = stream.reset_stream(s, code)
      let active_count = case stream.is_active(s) {
        True -> int.max(0, manager.active_stream_count - 1)
        False -> manager.active_stream_count
      }

      Ok(
        StreamManager(
          ..manager,
          streams: dict.insert(manager.streams, stream_id, reset_s),
          active_stream_count: active_count,
        ),
      )
    }
  }
}

/// Handles a received RST_STREAM frame
///
pub fn handle_rst_stream(
  manager: StreamManager,
  stream_id: Int,
  code: ErrorCode,
) -> Result(StreamManager, StreamError) {
  case dict.get(manager.streams, stream_id) {
    Error(Nil) -> {
      // Stream doesn't exist - this could be a closed stream
      // which is allowed per RFC 9113
      Ok(manager)
    }
    Ok(s) -> {
      // Mark stream as reset
      let reset_s = stream.reset_stream(s, code)
      let active_count = case stream.is_active(s) {
        True -> int.max(0, manager.active_stream_count - 1)
        False -> manager.active_stream_count
      }

      Ok(
        StreamManager(
          ..manager,
          streams: dict.insert(manager.streams, stream_id, reset_s),
          active_stream_count: active_count,
        ),
      )
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Settings Updates
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Updates local settings (settings we've sent to peer)
///
pub fn update_local_settings(
  manager: StreamManager,
  settings: StreamSettings,
) -> StreamManager {
  StreamManager(..manager, local_settings: settings)
}

/// Updates remote settings (settings received from peer)
///
pub fn update_remote_settings(
  manager: StreamManager,
  settings: StreamSettings,
) -> StreamManager {
  StreamManager(..manager, remote_settings: settings)
}

/// Updates the initial window size for all open streams
/// Called when SETTINGS_INITIAL_WINDOW_SIZE is received
///
pub fn update_initial_window_size(
  manager: StreamManager,
  new_size: Int,
) -> Result(StreamManager, ConnectionError) {
  let old_size = manager.remote_settings.initial_window_size
  let delta = new_size - old_size

  // Update all non-idle streams
  let update_result =
    dict.fold(manager.streams, Ok(dict.new()), fn(acc, id, s) {
      case acc {
        Error(err) -> Error(err)
        Ok(streams) -> {
          case s.state {
            Idle -> Ok(dict.insert(streams, id, s))
            _ -> {
              let new_window = s.send_window + delta
              // Check for overflow
              case new_window > 2_147_483_647 || new_window < 0 {
                True ->
                  Error(Protocol(
                    error.FlowControlError,
                    "Window size overflow after SETTINGS update",
                  ))
                False ->
                  Ok(dict.insert(
                    streams,
                    id,
                    Stream(..s, send_window: new_window),
                  ))
              }
            }
          }
        }
      }
    })

  case update_result {
    Error(err) -> Error(err)
    Ok(updated_streams) -> {
      let updated_settings =
        StreamSettings(..manager.remote_settings, initial_window_size: new_size)
      Ok(
        StreamManager(
          ..manager,
          streams: updated_streams,
          remote_settings: updated_settings,
        ),
      )
    }
  }
}

/// Updates max concurrent streams setting
///
pub fn update_max_concurrent_streams(
  manager: StreamManager,
  max_streams: Int,
) -> StreamManager {
  let updated_settings =
    StreamSettings(
      ..manager.remote_settings,
      max_concurrent_streams: max_streams,
    )
  StreamManager(..manager, remote_settings: updated_settings)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GOAWAY Handling
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Initiates graceful shutdown - no new streams will be accepted
///
pub fn initiate_goaway(manager: StreamManager) -> StreamManager {
  StreamManager(..manager, going_away: True)
}

/// Handles a received GOAWAY frame
///
pub fn handle_goaway(
  manager: StreamManager,
  last_stream_id: Int,
) -> StreamManager {
  // Mark connection as going away
  // Streams with ID > last_stream_id were not processed
  StreamManager(..manager, going_away: True, last_stream_id: last_stream_id)
}

/// Gets the last stream ID (for GOAWAY)
///
pub fn get_last_stream_id(manager: StreamManager) -> Int {
  manager.last_stream_id
}

/// Checks if the connection is going away
///
pub fn is_going_away(manager: StreamManager) -> Bool {
  manager.going_away
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stream Cleanup
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Removes closed streams to free memory
///
/// Keeps a specified number of recently closed streams for reference.
///
pub fn cleanup_closed_streams(
  manager: StreamManager,
  keep_count: Int,
) -> StreamManager {
  let closed_streams =
    manager.streams
    |> dict.to_list()
    |> list.filter(fn(pair) {
      let #(_, s) = pair
      stream.is_closed(s)
    })
    |> list.sort(fn(a, b) {
      let #(id_a, _) = a
      let #(id_b, _) = b
      int.compare(id_b, id_a)
    })

  // Keep only the most recent closed streams
  let to_remove =
    closed_streams
    |> list.drop(keep_count)
    |> list.map(fn(pair) {
      let #(id, _) = pair
      id
    })

  let cleaned_streams =
    list.fold(to_remove, manager.streams, fn(streams, id) {
      dict.delete(streams, id)
    })

  StreamManager(..manager, streams: cleaned_streams)
}

/// Forces removal of all closed streams
///
pub fn purge_closed_streams(manager: StreamManager) -> StreamManager {
  cleanup_closed_streams(manager, 0)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flow Control at Manager Level
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Consumes flow control window for a stream
///
pub fn consume_stream_window(
  manager: StreamManager,
  stream_id: Int,
  bytes: Int,
) -> Result(StreamManager, StreamError) {
  case dict.get(manager.streams, stream_id) {
    Error(Nil) ->
      Error(StreamProtocol(stream_id, StreamClosed, "Stream not found"))
    Ok(s) -> {
      case stream.consume_send_window(s, bytes) {
        Ok(updated) ->
          Ok(
            StreamManager(
              ..manager,
              streams: dict.insert(manager.streams, stream_id, updated),
            ),
          )
        Error(err) -> Error(err)
      }
    }
  }
}

/// Increments flow control window for a stream (WINDOW_UPDATE received)
///
pub fn increment_stream_window(
  manager: StreamManager,
  stream_id: Int,
  increment: Int,
) -> Result(StreamManager, StreamError) {
  case dict.get(manager.streams, stream_id) {
    Error(Nil) -> {
      // Stream might be closed - just ignore
      Ok(manager)
    }
    Ok(s) -> {
      case stream.increment_send_window(s, increment) {
        Ok(updated) ->
          Ok(
            StreamManager(
              ..manager,
              streams: dict.insert(manager.streams, stream_id, updated),
            ),
          )
        Error(err) -> Error(err)
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Statistics
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the count of active streams
///
pub fn active_count(manager: StreamManager) -> Int {
  manager.active_stream_count
}

/// Gets the total stream count (including closed)
///
pub fn total_count(manager: StreamManager) -> Int {
  dict.size(manager.streams)
}

/// Gets streams by state
///
pub fn get_streams_by_state(
  manager: StreamManager,
  state: StreamState,
) -> List(Stream) {
  manager.streams
  |> dict.values()
  |> list.filter(fn(s) { s.state == state })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Debug/String Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Converts Role to string
///
pub fn role_to_string(role: Role) -> String {
  case role {
    Client -> "client"
    Server -> "server"
  }
}

/// Formats the stream manager for debugging
///
pub fn to_string(manager: StreamManager) -> String {
  "StreamManager("
  <> "role="
  <> role_to_string(manager.role)
  <> ", active="
  <> int.to_string(manager.active_stream_count)
  <> ", total="
  <> int.to_string(dict.size(manager.streams))
  <> ", next_id="
  <> int.to_string(manager.next_stream_id)
  <> ", going_away="
  <> case manager.going_away {
    True -> "true"
    False -> "false"
  }
  <> ")"
}
