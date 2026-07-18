//// QUIC stream-ID classification and byte reassembly (RFC 9000 Sections
//// 2-3). Pure.
////
//// Stream IDs encode their type in the two least-significant bits: bit 0
//// selects the initiator (0 client, 1 server) and bit 1 selects
//// directionality (0 bidirectional, 1 unidirectional). `ReceiveBuffer`
//// reassembles STREAM frame data (which may arrive out of order,
//// duplicated, or overlapping) into a contiguous byte stream starting at
//// offset 0; `SendBuffer` is the mirror image for outgoing data.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// The four kinds of QUIC stream, determined by the low 2 bits of the
/// stream ID.
pub type StreamKind {
  ClientBidi
  ServerBidi
  ClientUni
  ServerUni
}

/// Classifies a stream ID by its two least-significant bits
/// (RFC 9000 Section 2.1).
pub fn stream_kind(id: Int) -> StreamKind {
  case int.bitwise_and(id, 0x3) {
    0x0 -> ClientBidi
    0x1 -> ServerBidi
    0x2 -> ClientUni
    _ -> ServerUni
  }
}

/// Whether the stream is bidirectional (bit 1 of the stream ID is 0).
pub fn is_bidi(id: Int) -> Bool {
  int.bitwise_and(id, 0x2) == 0
}

/// Whether the stream was initiated by the client (bit 0 of the stream ID
/// is 0).
pub fn is_client_initiated(id: Int) -> Bool {
  int.bitwise_and(id, 0x1) == 0
}

/// Ordered reassembly of STREAM frame data by offset. Tracks the
/// contiguous `read_offset` consumed so far, any out-of-order chunks still
/// buffered (keyed by their starting offset), the final size once a FIN
/// has been seen, and the highest offset observed (for flow control).
pub opaque type ReceiveBuffer {
  ReceiveBuffer(
    read_offset: Int,
    chunks: Dict(Int, BitArray),
    final_size: Option(Int),
    highest_offset: Int,
  )
}

/// Creates an empty receive buffer.
pub fn new_receive() -> ReceiveBuffer {
  ReceiveBuffer(
    read_offset: 0,
    chunks: dict.new(),
    final_size: None,
    highest_offset: 0,
  )
}

/// Inserts a chunk of STREAM data at `offset`, optionally carrying the
/// FIN. Returns `Error(Nil)` (a final-size violation, RFC 9000 Section
/// 4.5) if the chunk lands past an already-known final size, or if `fin`
/// declares a final size below data already received, without changing
/// `b`. Overlapping or duplicate data is tolerated: bytes are deduplicated
/// so `read` yields each byte exactly once.
pub fn receive(
  b: ReceiveBuffer,
  offset: Int,
  data: BitArray,
  fin: Bool,
) -> Result(ReceiveBuffer, Nil) {
  let end = offset + bit_array.byte_size(data)

  let final_size_result = case b.final_size, fin {
    Some(fs), True ->
      case end == fs {
        True -> Ok(Some(fs))
        False -> Error(Nil)
      }
    Some(fs), False ->
      case end > fs {
        True -> Error(Nil)
        False -> Ok(Some(fs))
      }
    None, True ->
      case end < b.highest_offset {
        True -> Error(Nil)
        False -> Ok(Some(end))
      }
    None, False -> Ok(None)
  }

  case final_size_result {
    Error(Nil) -> Error(Nil)
    Ok(final_size) ->
      Ok(ReceiveBuffer(
        read_offset: b.read_offset,
        chunks: insert_chunk(b.chunks, b.read_offset, offset, data),
        final_size: final_size,
        highest_offset: int.max(b.highest_offset, end),
      ))
  }
}

/// Stores `data` (received at `offset`) in `chunks`, keeping only the
/// bytes at or beyond `read_offset` since anything earlier has already
/// been delivered by `read`.
fn insert_chunk(
  chunks: Dict(Int, BitArray),
  read_offset: Int,
  offset: Int,
  data: BitArray,
) -> Dict(Int, BitArray) {
  let len = bit_array.byte_size(data)
  let end = offset + len

  case end <= read_offset {
    True -> chunks
    False -> {
      let skip = case offset < read_offset {
        True -> read_offset - offset
        False -> 0
      }
      case bit_array.slice(data, skip, len - skip) {
        Error(Nil) -> chunks
        Ok(sliced) -> dict.insert(chunks, offset + skip, sliced)
      }
    }
  }
}

/// Pulls all bytes now contiguous from the read offset, advancing it.
/// Returns an empty `BitArray` if no new contiguous bytes are available.
pub fn read(b: ReceiveBuffer) -> #(ReceiveBuffer, BitArray) {
  read_loop(b, <<>>)
}

fn read_loop(b: ReceiveBuffer, acc: BitArray) -> #(ReceiveBuffer, BitArray) {
  case find_covering(b.chunks, b.read_offset) {
    None -> #(b, acc)
    Some(#(chunk_offset, chunk_data)) -> {
      let chunk_len = bit_array.byte_size(chunk_data)
      let skip = b.read_offset - chunk_offset
      case bit_array.slice(chunk_data, skip, chunk_len - skip) {
        Error(Nil) -> #(b, acc)
        Ok(new_bytes) -> {
          let new_read_offset = chunk_offset + chunk_len
          let new_chunks =
            b.chunks
            |> dict.delete(chunk_offset)
            |> drop_stale(new_read_offset)
          let new_b =
            ReceiveBuffer(..b, read_offset: new_read_offset, chunks: new_chunks)
          read_loop(new_b, bit_array.append(acc, new_bytes))
        }
      }
    }
  }
}

/// Finds the buffered chunk that starts at or before `read_offset` and
/// extends past it, preferring the one that reaches furthest so
/// overlapping duplicates make maximal progress in one step.
fn find_covering(
  chunks: Dict(Int, BitArray),
  read_offset: Int,
) -> Option(#(Int, BitArray)) {
  chunks
  |> dict.to_list
  |> list.fold(None, fn(best, entry) {
    let #(chunk_offset, chunk_data) = entry
    let end = chunk_offset + bit_array.byte_size(chunk_data)
    case chunk_offset <= read_offset && end > read_offset {
      False -> best
      True ->
        case best {
          None -> Some(entry)
          Some(#(best_offset, best_data)) -> {
            let best_end = best_offset + bit_array.byte_size(best_data)
            case end > best_end {
              True -> Some(entry)
              False -> best
            }
          }
        }
    }
  })
}

/// Drops chunks that are now entirely behind `read_offset` and can never
/// be read again.
fn drop_stale(
  chunks: Dict(Int, BitArray),
  read_offset: Int,
) -> Dict(Int, BitArray) {
  dict.filter(chunks, fn(chunk_offset, chunk_data) {
    chunk_offset + bit_array.byte_size(chunk_data) > read_offset
  })
}

/// Whether the FIN has been seen and every byte up to it has been read.
pub fn is_finished(b: ReceiveBuffer) -> Bool {
  case b.final_size {
    None -> False
    Some(final_size) -> b.read_offset == final_size
  }
}

/// The highest offset (past-the-end) observed so far, for flow control
/// accounting.
pub fn highest_offset(b: ReceiveBuffer) -> Int {
  b.highest_offset
}

/// Outgoing byte queue for a stream: pending bytes not yet handed out by
/// `next_chunk`, the absolute send offset already handed out, and whether
/// the caller has closed the stream (no more writes, FIN once drained).
pub opaque type SendBuffer {
  SendBuffer(sent_offset: Int, pending: BitArray, closed: Bool)
}

/// Creates an empty send buffer.
pub fn new_send() -> SendBuffer {
  SendBuffer(sent_offset: 0, pending: <<>>, closed: False)
}

/// Appends `data` to the end of the outgoing queue.
pub fn write(b: SendBuffer, data: BitArray) -> SendBuffer {
  SendBuffer(..b, pending: bit_array.append(b.pending, data))
}

/// Marks the stream as closed: once the pending queue is drained,
/// `next_chunk` will carry the FIN.
pub fn close(b: SendBuffer) -> SendBuffer {
  SendBuffer(..b, closed: True)
}

/// Returns the next chunk to send: the updated buffer, the absolute send
/// offset of the chunk, up to `max_len` bytes from the pending queue, and
/// whether this chunk carries the FIN (only when it drains the queue and
/// `close` was called). Advances the send offset by the number of bytes
/// returned.
pub fn next_chunk(
  b: SendBuffer,
  max_len: Int,
) -> #(SendBuffer, Int, BitArray, Bool) {
  let available = bit_array.byte_size(b.pending)
  let take_len = case max_len < available {
    True -> max_len
    False -> available
  }

  case bit_array.slice(b.pending, 0, take_len) {
    Error(Nil) -> #(b, b.sent_offset, <<>>, False)
    Ok(chunk) -> {
      let rest_len = available - take_len
      case bit_array.slice(b.pending, take_len, rest_len) {
        Error(Nil) -> #(b, b.sent_offset, <<>>, False)
        Ok(rest) -> {
          let offset = b.sent_offset
          let fin = b.closed && take_len == available
          let new_b =
            SendBuffer(
              sent_offset: offset + take_len,
              pending: rest,
              closed: b.closed,
            )
          #(new_b, offset, chunk, fin)
        }
      }
    }
  }
}
