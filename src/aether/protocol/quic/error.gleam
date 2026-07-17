//// QUIC transport error codes (RFC 9000 Section 20) and the shared
//// wire-level parse error type used by the quic parsers.

/// Errors produced while parsing QUIC wire data.
///
/// `NeedMoreData` means the input was truncated and the caller should wait
/// for more bytes; `Malformed` means the peer violated the protocol and the
/// connection should be closed.
pub type WireError {
  NeedMoreData
  Malformed(reason: String)
}

/// Transport error codes from RFC 9000 Section 20.1.
pub type TransportError {
  NoError
  InternalError
  ConnectionRefused
  FlowControlError
  StreamLimitError
  StreamStateError
  FinalSizeError
  FrameEncodingError
  TransportParameterError
  ConnectionIdLimitError
  ProtocolViolation
  InvalidToken
  ApplicationError
  CryptoBufferExceeded
  KeyUpdateError
  AeadLimitReached
  NoViablePath
  /// TLS alert carried in a CRYPTO_ERROR code (0x0100-0x01ff).
  CryptoError(alert: Int)
  /// Codes not defined by RFC 9000 (greased or from extensions).
  UnknownError(code: Int)
}

/// Converts a transport error to its wire code.
pub fn to_code(error: TransportError) -> Int {
  case error {
    NoError -> 0x00
    InternalError -> 0x01
    ConnectionRefused -> 0x02
    FlowControlError -> 0x03
    StreamLimitError -> 0x04
    StreamStateError -> 0x05
    FinalSizeError -> 0x06
    FrameEncodingError -> 0x07
    TransportParameterError -> 0x08
    ConnectionIdLimitError -> 0x09
    ProtocolViolation -> 0x0a
    InvalidToken -> 0x0b
    ApplicationError -> 0x0c
    CryptoBufferExceeded -> 0x0d
    KeyUpdateError -> 0x0e
    AeadLimitReached -> 0x0f
    NoViablePath -> 0x10
    CryptoError(alert) -> 0x100 + alert
    UnknownError(code) -> code
  }
}

/// Converts a wire code to a transport error.
pub fn from_code(code: Int) -> TransportError {
  case code {
    0x00 -> NoError
    0x01 -> InternalError
    0x02 -> ConnectionRefused
    0x03 -> FlowControlError
    0x04 -> StreamLimitError
    0x05 -> StreamStateError
    0x06 -> FinalSizeError
    0x07 -> FrameEncodingError
    0x08 -> TransportParameterError
    0x09 -> ConnectionIdLimitError
    0x0a -> ProtocolViolation
    0x0b -> InvalidToken
    0x0c -> ApplicationError
    0x0d -> CryptoBufferExceeded
    0x0e -> KeyUpdateError
    0x0f -> AeadLimitReached
    0x10 -> NoViablePath
    _ ->
      case code >= 0x100 && code <= 0x1ff {
        True -> CryptoError(code - 0x100)
        False -> UnknownError(code)
      }
  }
}
