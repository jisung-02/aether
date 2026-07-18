//// QUIC connection ID tracking (RFC 9000 Section 5.1).
////
//// Each endpoint issues connection IDs with sequence numbers (0 is the one
//// exchanged during the handshake). NEW_CONNECTION_ID frames add remote
//// CIDs the peer has offered; RETIRE_CONNECTION_ID frames retire them. One
//// remote CID is active at a time and used as the destination for
//// outgoing packets. Locally issued CIDs are matched against the
//// destination CID of incoming packets to route them to this connection.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list

/// A single connection ID: its sequence number, the id bytes, and the
/// stateless reset token that accompanies it (`<<>>` for the CID exchanged
/// during the handshake, which has no reset token).
pub type ConnectionId {
  ConnectionId(sequence: Int, id: BitArray, reset_token: BitArray)
}

/// Tracks the connection IDs in use for one connection: the CIDs this
/// endpoint has issued to the peer, the CIDs the peer has issued to us, and
/// which of the peer's CIDs is currently active.
pub opaque type CidManager {
  CidManager(
    local: Dict(Int, ConnectionId),
    remote: Dict(Int, ConnectionId),
    active_remote_sequence: Int,
  )
}

/// Creates a manager from the locally issued CIDs and the remote CID
/// exchanged during the handshake. The remote CID starts as sequence 0
/// with no reset token, and is the active remote CID.
pub fn new(local: List(ConnectionId), remote_initial: BitArray) -> CidManager {
  let local_dict =
    list.fold(local, dict.new(), fn(acc, cid) {
      dict.insert(acc, cid.sequence, cid)
    })
  let remote_dict =
    dict.new()
    |> dict.insert(
      0,
      ConnectionId(sequence: 0, id: remote_initial, reset_token: <<>>),
    )
  CidManager(local: local_dict, remote: remote_dict, active_remote_sequence: 0)
}

/// Adds a remote CID from a NEW_CONNECTION_ID frame. Errors if a CID with
/// the same sequence number already exists with a different id (a protocol
/// violation); re-adding the same sequence with the same id is a no-op.
pub fn add_remote(m: CidManager, cid: ConnectionId) -> Result(CidManager, Nil) {
  case dict.get(m.remote, cid.sequence) {
    Ok(existing) if existing.id == cid.id -> Ok(m)
    Ok(_existing) -> Error(Nil)
    Error(Nil) ->
      Ok(CidManager(..m, remote: dict.insert(m.remote, cid.sequence, cid)))
  }
}

/// Retires a remote CID by sequence number. If it was the active CID, the
/// lowest remaining remote sequence number becomes active (there may be
/// none left).
pub fn retire_remote(m: CidManager, sequence: Int) -> CidManager {
  let remote = dict.delete(m.remote, sequence)
  case sequence == m.active_remote_sequence {
    True ->
      CidManager(
        ..m,
        remote: remote,
        active_remote_sequence: lowest_sequence(remote),
      )
    False -> CidManager(..m, remote: remote)
  }
}

/// The id of the currently active remote CID, or `<<>>` if none remain.
pub fn active_remote(m: CidManager) -> BitArray {
  case dict.get(m.remote, m.active_remote_sequence) {
    Ok(cid) -> cid.id
    Error(Nil) -> <<>>
  }
}

/// Adds a locally issued CID (to be announced to the peer via
/// NEW_CONNECTION_ID).
pub fn issue_local(
  m: CidManager,
  sequence: Int,
  id: BitArray,
  token: BitArray,
) -> CidManager {
  let cid = ConnectionId(sequence: sequence, id: id, reset_token: token)
  CidManager(..m, local: dict.insert(m.local, sequence, cid))
}

/// Removes a locally issued CID by sequence number. Errors if that
/// sequence isn't present.
pub fn retire_local(m: CidManager, sequence: Int) -> Result(CidManager, Nil) {
  case dict.has_key(m.local, sequence) {
    True -> Ok(CidManager(..m, local: dict.delete(m.local, sequence)))
    False -> Error(Nil)
  }
}

/// Finds the locally issued CID whose id matches `id`, for routing an
/// incoming packet's destination connection ID to this connection.
pub fn local_by_id(m: CidManager, id: BitArray) -> Result(ConnectionId, Nil) {
  m.local
  |> dict.values()
  |> list.find(fn(cid) { cid.id == id })
}

/// The lowest sequence number among the remaining remote CIDs, or -1 if
/// none remain.
fn lowest_sequence(remote: Dict(Int, ConnectionId)) -> Int {
  case dict.keys(remote) |> list.sort(int.compare) {
    [] -> -1
    [lowest, ..] -> lowest
  }
}
