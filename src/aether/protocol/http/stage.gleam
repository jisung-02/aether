// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HTTP Stage Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides HTTP decoder and encoder stages for pipeline integration.
// Supports HTTP/1.1 request parsing with pipelining support.
//

import aether/core/data.{type Data}
import aether/core/message
import aether/pipeline/error.{ProcessingError}
import aether/pipeline/stage.{type Stage}
import aether/protocol/http/builder
import aether/protocol/http/parser
import aether/protocol/http/request.{
  type HttpVersion, type ParsedRequest, ParsedRequest,
}
import aether/protocol/protocol.{type Protocol}
import aether/protocol/registry.{type Registry}
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/http/request as http_request
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

/// HTTP request data container for pipeline stages
///
/// This type wraps a parsed HTTP request along with its gleam_http
/// representation and any remaining bytes for HTTP pipelining.
///
/// ## Fields
///
/// - `request`: The raw ParsedRequest from parsing
/// - `http_request`: The converted gleam_http Request type
/// - `remaining_bytes`: Bytes remaining after this request (for pipelining)
///
/// ## Examples
///
/// ```gleam
/// let data = HttpRequestData(
///   request: parsed,
///   http_request: parser.to_http_request(parsed),
///   remaining_bytes: <<>>,
/// )
/// ```
///
pub type HttpRequestData {
  HttpRequestData(
    request: ParsedRequest,
    http_request: http_request.Request(BitArray),
    remaining_bytes: BitArray,
  )
}

/// Metadata key for storing HttpRequestData in Data
///
pub const metadata_key = "http:request"

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Stage Creation Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates an HTTP decoder stage
///
/// This stage parses raw HTTP request bytes and extracts the body.
/// The full HttpRequestData (request + http_request + remaining_bytes)
/// is stored in the Data's metadata under the key "http:request",
/// while the Data's bytes are updated to contain only the body.
///
/// Supports HTTP pipelining by storing remaining bytes for subsequent
/// request parsing.
///
/// ## Returns
///
/// A Stage that transforms Data containing raw HTTP request bytes
/// to Data containing only the request body.
///
/// ## Examples
///
/// ```gleam
/// let decoder = decode()
/// let raw_request = data.new(http_request_bytes)
///
/// case stage.execute(decoder, raw_request) {
///   Ok(decoded) -> {
///     // decoded.bytes contains only the body
///     // The full request is in metadata["http:request"]
///   }
///   Error(err) -> // handle parse error
/// }
/// ```
///
pub fn decode() -> Stage(Data, Data) {
  stage.new("http:decode", fn(data: Data) {
    case parser.parse_request(message.bytes(data)) {
      Ok(#(parsed, remaining)) -> {
        let http_req = parser.to_http_request(parsed)
        let req_data =
          HttpRequestData(
            request: parsed,
            http_request: http_req,
            remaining_bytes: remaining,
          )

        data
        |> message.set_metadata(metadata_key, to_dynamic(req_data))
        |> message.set_bytes(parsed.body)
        |> Ok
      }
      Error(parse_error) -> {
        Error(ProcessingError(
          "HTTP parse error: " <> parser.error_to_string(parse_error),
          option.None,
        ))
      }
    }
  })
}

/// Creates an HTTP encoder stage
///
/// This stage builds a complete HTTP request from the body and
/// request information. If an HttpRequestData exists in the Data's
/// metadata, its request is used; otherwise, an error is returned.
///
/// The stage updates the Data's bytes to contain the full HTTP request
/// (request line + headers + body).
///
/// ## Returns
///
/// A Stage that transforms Data containing body bytes to Data
/// containing a complete HTTP request.
///
/// ## Examples
///
/// ```gleam
/// let encoder = encode()
/// let body_data = data.new(<<"body":utf8>>)
///   |> set_request(req_data)
///
/// case stage.execute(encoder, body_data) {
///   Ok(encoded) -> {
///     // encoded.bytes contains the full HTTP request
///   }
///   Error(err) -> // handle error
/// }
/// ```
///
pub fn encode() -> Stage(Data, Data) {
  stage.new("http:encode", fn(data: Data) {
    case get_request(data) {
      option.Some(req_data) -> {
        // Update request body with current bytes
        let current_body = message.bytes(data)
        let updated =
          ParsedRequest(..req_data.request, body: current_body)
        let bytes = builder.build_request(updated)

        data
        |> message.set_bytes(bytes)
        |> Ok
      }
      option.None -> {
        Error(ProcessingError("No HTTP request in metadata", option.None))
      }
    }
  })
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Protocol Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates the HTTP protocol definition
///
/// This function creates a Protocol instance that represents the
/// HTTP/1.1 application layer protocol. It includes decoder and
/// encoder stages and is tagged for categorization.
///
/// ## Returns
///
/// A Protocol instance for HTTP
///
/// ## Examples
///
/// ```gleam
/// let http = http_protocol()
///
/// // Check the protocol name
/// protocol.get_name(http)  // "http"
///
/// // Get the decoder stage
/// case protocol.get_decoder(http) {
///   Some(decoder) -> // use decoder
///   None -> // no decoder
/// }
/// ```
///
pub fn http_protocol() -> Protocol {
  protocol.new("http")
  |> protocol.with_tag("application")
  |> protocol.with_tag("layer7")
  |> protocol.with_tag("text-based")
  |> protocol.with_decoder(decode())
  |> protocol.with_encoder(encode())
  |> protocol.with_version("1.1")
  |> protocol.with_description("Hypertext Transfer Protocol")
  |> protocol.with_author("Aether")
}

/// Registers the HTTP protocol in a registry
///
/// This is a convenience function that creates the HTTP protocol
/// and registers it in the provided registry.
///
/// ## Parameters
///
/// - `registry`: The registry to register the protocol in
///
/// ## Returns
///
/// The updated registry with HTTP protocol registered
///
/// ## Examples
///
/// ```gleam
/// let registry = registry.new()
///   |> register_http()
///
/// case registry.get(registry, "http") {
///   Some(http) -> io.println("HTTP registered!")
///   None -> io.println("Registration failed")
/// }
/// ```
///
pub fn register_http(reg: Registry) -> Registry {
  registry.register(reg, http_protocol())
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets an HttpRequestData from Data metadata if present
///
/// ## Parameters
///
/// - `data`: The Data to get the request from
///
/// ## Returns
///
/// Option containing the HttpRequestData if present
///
pub fn get_request(data: Data) -> option.Option(HttpRequestData) {
  case message.get_metadata(data, metadata_key) {
    option.Some(req_dynamic) -> {
      let req_data: HttpRequestData = from_dynamic(req_dynamic)
      option.Some(req_data)
    }
    option.None -> option.None
  }
}

/// Sets an HttpRequestData in Data metadata
///
/// ## Parameters
///
/// - `data`: The Data to set the request in
/// - `request_data`: The HttpRequestData to store
///
/// ## Returns
///
/// The updated Data with the request in metadata
///
pub fn set_request(data: Data, request_data: HttpRequestData) -> Data {
  message.set_metadata(data, metadata_key, to_dynamic(request_data))
}

/// Gets the remaining bytes for HTTP pipelining
///
/// ## Parameters
///
/// - `data`: The Data to get remaining bytes from
///
/// ## Returns
///
/// Option containing the remaining bytes if present
///
pub fn get_remaining_bytes(data: Data) -> option.Option(BitArray) {
  case get_request(data) {
    option.Some(req_data) -> option.Some(req_data.remaining_bytes)
    option.None -> option.None
  }
}

/// Checks if there are pipelined requests remaining
///
/// ## Parameters
///
/// - `data`: The Data to check
///
/// ## Returns
///
/// True if there are remaining bytes to parse
///
pub fn has_pipelined_requests(data: Data) -> Bool {
  case get_remaining_bytes(data) {
    option.Some(remaining) -> bit_array.byte_size(remaining) > 0
    option.None -> False
  }
}

/// Gets the gleam_http Request from Data
///
/// ## Parameters
///
/// - `data`: The Data to get the request from
///
/// ## Returns
///
/// Option containing the gleam_http Request if present
///
pub fn get_http_request(data: Data) -> option.Option(http_request.Request(BitArray)) {
  case get_request(data) {
    option.Some(req_data) -> option.Some(req_data.http_request)
    option.None -> option.None
  }
}

/// Gets the ParsedRequest from Data
///
/// ## Parameters
///
/// - `data`: The Data to get the request from
///
/// ## Returns
///
/// Option containing the ParsedRequest if present
///
pub fn get_parsed_request(data: Data) -> option.Option(ParsedRequest) {
  case get_request(data) {
    option.Some(req_data) -> option.Some(req_data.request)
    option.None -> option.None
  }
}

/// Creates new HttpRequestData from a ParsedRequest
///
/// ## Parameters
///
/// - `parsed`: The ParsedRequest
/// - `remaining`: The remaining bytes
///
/// ## Returns
///
/// A new HttpRequestData
///
pub fn new_request_data(
  parsed: ParsedRequest,
  remaining: BitArray,
) -> HttpRequestData {
  HttpRequestData(
    request: parsed,
    http_request: parser.to_http_request(parsed),
    remaining_bytes: remaining,
  )
}

/// Gets the HTTP method from Data as a string
///
/// ## Parameters
///
/// - `data`: The Data to get the method from
///
/// ## Returns
///
/// Option containing the method string if present
///
pub fn get_method(data: Data) -> option.Option(String) {
  case get_parsed_request(data) {
    option.Some(req) -> option.Some(request.method_to_string(req.method))
    option.None -> option.None
  }
}

/// Gets the request URI from Data
///
/// ## Parameters
///
/// - `data`: The Data to get the URI from
///
/// ## Returns
///
/// Option containing the URI if present
///
pub fn get_uri(data: Data) -> option.Option(String) {
  case get_parsed_request(data) {
    option.Some(req) -> option.Some(req.uri)
    option.None -> option.None
  }
}

/// Gets the HTTP version from Data
///
/// ## Parameters
///
/// - `data`: The Data to get the version from
///
/// ## Returns
///
/// Option containing the HttpVersion if present
///
pub fn get_version(data: Data) -> option.Option(HttpVersion) {
  case get_parsed_request(data) {
    option.Some(req) -> option.Some(req.version)
    option.None -> option.None
  }
}

/// Gets a specific header value from Data
///
/// ## Parameters
///
/// - `data`: The Data to get the header from
/// - `name`: The header name (case-insensitive)
///
/// ## Returns
///
/// Option containing the header value if present
///
pub fn get_header(data: Data, name: String) -> option.Option(String) {
  case get_parsed_request(data) {
    option.Some(req) -> request.get_header(req, name)
    option.None -> option.None
  }
}

/// Gets the Content-Type header from Data
///
/// ## Parameters
///
/// - `data`: The Data to get the Content-Type from
///
/// ## Returns
///
/// Option containing the Content-Type if present
///
pub fn get_content_type(data: Data) -> option.Option(String) {
  get_header(data, "content-type")
}

/// Gets the Host header from Data
///
/// ## Parameters
///
/// - `data`: The Data to get the Host from
///
/// ## Returns
///
/// Option containing the Host if present
///
pub fn get_host(data: Data) -> option.Option(String) {
  get_header(data, "host")
}

/// Gets the request body size from Data
///
/// ## Parameters
///
/// - `data`: The Data to get the body size from
///
/// ## Returns
///
/// The body size in bytes
///
pub fn get_body_size(data: Data) -> Int {
  case get_parsed_request(data) {
    option.Some(req) -> bit_array.byte_size(req.body)
    option.None -> 0
  }
}
