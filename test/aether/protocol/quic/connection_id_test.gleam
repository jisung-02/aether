import aether/protocol/quic/connection_id.{ConnectionId}
import gleeunit/should

pub fn new_active_remote_is_initial_test() {
  let local = [ConnectionId(sequence: 0, id: <<1, 2, 3>>, reset_token: <<>>)]
  let m = connection_id.new(local, <<9, 9, 9>>)

  connection_id.active_remote(m) |> should.equal(<<9, 9, 9>>)
}

pub fn new_local_by_id_finds_local_cid_test() {
  let local = [ConnectionId(sequence: 0, id: <<1, 2, 3>>, reset_token: <<>>)]
  let m = connection_id.new(local, <<9, 9, 9>>)

  connection_id.local_by_id(m, <<1, 2, 3>>)
  |> should.equal(
    Ok(ConnectionId(sequence: 0, id: <<1, 2, 3>>, reset_token: <<>>)),
  )
}

pub fn new_local_by_id_unknown_is_error_test() {
  let local = [ConnectionId(sequence: 0, id: <<1, 2, 3>>, reset_token: <<>>)]
  let m = connection_id.new(local, <<9, 9, 9>>)

  connection_id.local_by_id(m, <<0xff>>) |> should.equal(Error(Nil))
}

pub fn add_remote_does_not_change_active_test() {
  let m = connection_id.new([], <<0>>)
  let assert Ok(m) =
    connection_id.add_remote(
      m,
      ConnectionId(sequence: 1, id: <<1>>, reset_token: <<1, 1, 1>>),
    )

  // Adding a remote CID must not move the active sequence off 0.
  connection_id.active_remote(m) |> should.equal(<<0>>)
}

pub fn retire_active_remote_switches_to_next_test() {
  let m = connection_id.new([], <<0>>)
  let assert Ok(m) =
    connection_id.add_remote(
      m,
      ConnectionId(sequence: 1, id: <<1>>, reset_token: <<1, 1, 1>>),
    )
  let m = connection_id.retire_remote(m, 0)

  connection_id.active_remote(m) |> should.equal(<<1>>)
}

pub fn add_remote_duplicate_sequence_different_id_is_error_test() {
  let m = connection_id.new([], <<0>>)
  let assert Ok(m) =
    connection_id.add_remote(
      m,
      ConnectionId(sequence: 1, id: <<1>>, reset_token: <<1, 1, 1>>),
    )

  connection_id.add_remote(
    m,
    ConnectionId(sequence: 1, id: <<2>>, reset_token: <<2, 2, 2>>),
  )
  |> should.equal(Error(Nil))
}

pub fn add_remote_duplicate_sequence_same_id_is_noop_ok_test() {
  let m = connection_id.new([], <<0>>)
  let assert Ok(m) =
    connection_id.add_remote(
      m,
      ConnectionId(sequence: 1, id: <<1>>, reset_token: <<1, 1, 1>>),
    )

  let result =
    connection_id.add_remote(
      m,
      ConnectionId(sequence: 1, id: <<1>>, reset_token: <<1, 1, 1>>),
    )

  should.be_ok(result)
  connection_id.active_remote(m) |> should.equal(<<0>>)
}

pub fn retire_only_remaining_remote_clears_active_test() {
  let m = connection_id.new([], <<0>>)
  let m = connection_id.retire_remote(m, 0)

  connection_id.active_remote(m) |> should.equal(<<>>)
}

pub fn issue_local_then_local_by_id_finds_it_test() {
  let m = connection_id.new([], <<0>>)
  let m = connection_id.issue_local(m, 1, <<7, 7>>, <<1, 2, 3, 4>>)

  connection_id.local_by_id(m, <<7, 7>>)
  |> should.equal(
    Ok(ConnectionId(sequence: 1, id: <<7, 7>>, reset_token: <<1, 2, 3, 4>>)),
  )
}

pub fn retire_local_removes_it_test() {
  let m = connection_id.new([], <<0>>)
  let m = connection_id.issue_local(m, 1, <<7, 7>>, <<1, 2, 3, 4>>)
  let assert Ok(m) = connection_id.retire_local(m, 1)

  connection_id.local_by_id(m, <<7, 7>>) |> should.equal(Error(Nil))
}

pub fn retire_local_unknown_sequence_is_error_test() {
  let m = connection_id.new([], <<0>>)

  connection_id.retire_local(m, 42) |> should.equal(Error(Nil))
}

pub fn retire_active_remote_picks_lowest_remaining_sequence_test() {
  let m = connection_id.new([], <<0>>)
  let assert Ok(m) =
    connection_id.add_remote(
      m,
      ConnectionId(sequence: 2, id: <<2>>, reset_token: <<>>),
    )
  let assert Ok(m) =
    connection_id.add_remote(
      m,
      ConnectionId(sequence: 1, id: <<1>>, reset_token: <<>>),
    )
  let assert Ok(m) =
    connection_id.add_remote(
      m,
      ConnectionId(sequence: 3, id: <<3>>, reset_token: <<>>),
    )

  // Active is still 0; retiring it should pick 1, the lowest of {1, 2, 3}.
  let m = connection_id.retire_remote(m, 0)

  connection_id.active_remote(m) |> should.equal(<<1>>)
}
