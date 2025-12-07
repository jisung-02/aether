// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Stage Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides TCP decoder and encoder stages for pipeline integration.
// Supports both OS socket mode (production) and custom TCP mode (learning/testing).
//

import aether/core/data.{type Data}
import aether/core/message
import aether/pipeline/error.{ProcessingError}
import aether/pipeline/stage.{type Stage}
import aether/protocol/protocol.{type Protocol}
import aether/protocol/registry.{type Registry}
import aether/protocol/tcp/builder
import aether/protocol/tcp/header.{type TcpHeader}
import aether/protocol/tcp/parser
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/option

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// FFI for Type Coercion
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Coerces any value to Dynamic (safe on BEAM as types are erased at runtime)
@external(erlang, "erlang", "hd")
fn coerce_via_hd(list: List(a)) -> b

fn to_dynamic(value: a) -> Dynamic {
  coerce_via_hd([value])
}

fn from_dynamic(value: Dynamic) -> a {
  coerce_via_hd([value])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// A TCP segment containing header and payload
///
/// This type wraps a parsed TCP header along with its payload data.
/// It is stored in the Data metadata during decode/encode operations
/// to preserve TCP header information across pipeline stages.
///
/// ## Examples
///
/// ```gleam
/// let segment = TcpSegment(
///   header: header.new(8080, 80),
///   payload: <<"Hello, TCP!":utf8>>,
/// )
/// ```
///
pub type TcpSegment {
  TcpSegment(header: TcpHeader, payload: BitArray)
}

/// Metadata key for storing TcpSegment in Data
///
pub const metadata_key = "tcp:segment"

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a TCP decoder stage
///
/// This stage parses raw TCP segment bytes and extracts the payload.
/// The full TcpSegment (header + payload) is stored in the Data's
/// metadata under the key "tcp:segment", while the Data's bytes
/// are updated to contain only the payload.
///
/// ## Returns
///
/// A Stage that transforms Data containing raw TCP segment bytes
/// to Data containing only the payload.
///
/// ## Examples
///
/// ```gleam
/// let decoder = decode()
/// let raw_segment = data.new(tcp_segment_bytes)
///
/// case stage.execute(decoder, raw_segment) {
///   Ok(decoded) -> {
///     // decoded.bytes contains only the payload
///     // The full segment is in metadata["tcp:segment"]
///   }
///   Error(err) -> // handle parse error
/// }
/// ```
///
pub fn decode() -> Stage(Data, Data) {
  stage.new("tcp:decode", fn(data: Data) {
    case parser.parse_segment(message.bytes(data)) {
      Ok(#(tcp_header, payload)) -> {
        let segment = TcpSegment(header: tcp_header, payload: payload)

        data
        |> message.set_metadata(metadata_key, to_dynamic(segment))
        |> message.set_bytes(payload)
        |> Ok
      }
      Error(parse_error) -> {
        Error(ProcessingError(
          "TCP parse error: " <> parser.error_to_string(parse_error),
          option.None,
        ))
      }
    }
  })
}

/// Creates a TCP encoder stage
///
/// This stage builds a complete TCP segment from the payload and
/// header information. If a TcpSegment exists in the Data's metadata,
/// its header is used; otherwise, a default header is created.
///
/// The stage updates the Data's bytes to contain the full TCP segment
/// (header + payload), and optionally updates the payload in the
/// stored segment if the bytes have changed.
///
/// ## Returns
///
/// A Stage that transforms Data containing payload bytes to Data
/// containing a complete TCP segment.
///
/// ## Examples
///
/// ```gleam
/// let encoder = encode()
/// let payload_data = data.new(<<"Hello":utf8>>)
///   |> set_segment(segment)
///
/// case stage.execute(encoder, payload_data) {
///   Ok(encoded) -> {
///     // encoded.bytes contains the full TCP segment
///   }
///   Error(err) -> // handle error
/// }
/// ```
///
pub fn encode() -> Stage(Data, Data) {
  stage.new("tcp:encode", fn(data: Data) {
    let current_payload = message.bytes(data)

    // Try to get existing segment from metadata
    let segment = case message.get_metadata(data, metadata_key) {
      option.Some(seg_dynamic) -> {
        // Coerce the dynamic value back to TcpSegment
        let stored_segment: TcpSegment = from_dynamic(seg_dynamic)
        // Update payload if bytes have changed
        TcpSegment(..stored_segment, payload: current_payload)
      }
      option.None -> {
        // Create a default segment with the current payload
        create_default_segment(current_payload)
      }
    }

    // Build the full TCP segment
    let full_segment = builder.build_segment(segment.header, segment.payload)

    data
    |> message.set_bytes(full_segment)
    |> Ok
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates the TCP protocol definition
///
/// This function creates a Protocol instance that represents the
/// TCP transport layer protocol. It includes decoder and encoder
/// stages and is tagged for categorization.
///
/// ## Returns
///
/// A Protocol instance for TCP
///
/// ## Examples
///
/// ```gleam
/// let tcp = tcp_protocol()
///
/// // Check the protocol name
/// protocol.get_name(tcp)  // "tcp"
///
/// // Get the decoder stage
/// case protocol.get_decoder(tcp) {
///   Some(decoder) -> // use decoder
///   None -> // no decoder
/// }
/// ```
///
pub fn tcp_protocol() -> Protocol {
  protocol.new("tcp")
  |> protocol.with_tag("transport")
  |> protocol.with_tag("layer4")
  |> protocol.with_decoder(decode())
  |> protocol.with_encoder(encode())
  |> protocol.with_version("1.0.0")
  |> protocol.with_description("Transmission Control Protocol")
  |> protocol.with_author("Aether")
}

/// Registers the TCP protocol in a registry
///
/// This is a convenience function that creates the TCP protocol
/// and registers it in the provided registry.
///
/// ## Parameters
///
/// - `registry`: The registry to register the protocol in
///
/// ## Returns
///
/// The updated registry with TCP protocol registered
///
/// ## Examples
///
/// ```gleam
/// let registry = registry.new()
///   |> register_tcp()
///
/// case registry.get(registry, "tcp") {
///   Some(tcp) -> io.println("TCP registered!")
///   None -> io.println("Registration failed")
/// }
/// ```
///
pub fn register_tcp(reg: Registry) -> Registry {
  registry.register(reg, tcp_protocol())
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a default TCP segment with the given payload
///
/// This is used when encoding data that doesn't have an existing
/// TcpSegment in metadata. It creates a minimal valid TCP header
/// with default values.
///
fn create_default_segment(payload: BitArray) -> TcpSegment {
  TcpSegment(
    header: header.TcpHeader(
      source_port: 0,
      destination_port: 0,
      sequence_number: 0,
      acknowledgment_number: 0,
      data_offset: 5,
      flags: header.default_flags(),
      window_size: 65_535,
      checksum: 0,
      urgent_pointer: 0,
      options: option.None,
    ),
    payload: payload,
  )
}

/// Gets a TcpSegment from Data metadata if present
///
/// ## Parameters
///
/// - `data`: The Data to get the segment from
///
/// ## Returns
///
/// Option containing the TcpSegment if present
///
pub fn get_segment(data: Data) -> option.Option(TcpSegment) {
  case message.get_metadata(data, metadata_key) {
    option.Some(seg_dynamic) -> {
      let segment: TcpSegment = from_dynamic(seg_dynamic)
      option.Some(segment)
    }
    option.None -> option.None
  }
}

/// Sets a TcpSegment in Data metadata
///
/// ## Parameters
///
/// - `data`: The Data to set the segment in
/// - `segment`: The TcpSegment to store
///
/// ## Returns
///
/// The updated Data with the segment in metadata
///
pub fn set_segment(data: Data, segment: TcpSegment) -> Data {
  message.set_metadata(data, metadata_key, to_dynamic(segment))
}

/// Creates a TcpSegment with the given ports and payload
///
/// This is a convenience function for creating segments with
/// specific port numbers. Other header fields use defaults.
///
/// ## Parameters
///
/// - `source_port`: The source port number
/// - `destination_port`: The destination port number
/// - `payload`: The payload data
///
/// ## Returns
///
/// A new TcpSegment with the specified values
///
pub fn new_segment(
  source_port: Int,
  destination_port: Int,
  payload: BitArray,
) -> TcpSegment {
  TcpSegment(
    header: header.new(source_port, destination_port),
    payload: payload,
  )
}

/// Creates a TcpSegment with specific flags
///
/// ## Parameters
///
/// - `source_port`: The source port number
/// - `destination_port`: The destination port number
/// - `flags`: The TCP flags to set
/// - `payload`: The payload data
///
/// ## Returns
///
/// A new TcpSegment with the specified values
///
pub fn new_segment_with_flags(
  source_port: Int,
  destination_port: Int,
  flags: header.TcpFlags,
  payload: BitArray,
) -> TcpSegment {
  TcpSegment(
    header: header.with_flags(source_port, destination_port, flags),
    payload: payload,
  )
}

/// Gets the payload size from a TcpSegment
///
pub fn payload_size(segment: TcpSegment) -> Int {
  bit_array.byte_size(segment.payload)
}

/// Gets the total segment size (header + payload)
///
pub fn segment_size(segment: TcpSegment) -> Int {
  header.header_length(segment.header) + bit_array.byte_size(segment.payload)
}
