import aether/protocol/tls/key_schedule
import aether/protocol/tls/rfc8448_vectors as vectors
import gleam/bit_array
import gleeunit/should

fn hex(string: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(string)
  bytes
}

// Extracts the trailing verify_data from an encoded Finished message
// (1-byte type + 3-byte length header, then 32 bytes of verify_data).
fn finished_verify_data_bytes(message: String) -> BitArray {
  let assert Ok(verify_data) = bit_array.slice(hex(message), 4, 32)
  verify_data
}

// RFC 8448 Section 3 runs the full key schedule for one example handshake
// trace; every secret below is checked against that trace verbatim.

pub fn early_secret_test() {
  key_schedule.early_secret()
  |> should.equal(hex(vectors.early_secret))
}

pub fn handshake_secret_test() {
  key_schedule.handshake_secret(
    hex(vectors.early_secret),
    hex(vectors.ecdhe_shared_secret),
  )
  |> should.equal(hex(vectors.handshake_secret))
}

pub fn master_secret_test() {
  key_schedule.master_secret(hex(vectors.handshake_secret))
  |> should.equal(hex(vectors.master_secret))
}

pub fn client_and_server_hs_traffic_test() {
  let transcript_hash =
    key_schedule.new_transcript()
    |> key_schedule.add(hex(vectors.client_hello))
    |> key_schedule.add(hex(vectors.server_hello))
    |> key_schedule.hash

  key_schedule.client_hs_traffic(hex(vectors.handshake_secret), transcript_hash)
  |> should.equal(hex(vectors.client_hs_traffic_secret))

  key_schedule.server_hs_traffic(hex(vectors.handshake_secret), transcript_hash)
  |> should.equal(hex(vectors.server_hs_traffic_secret))
}

pub fn client_and_server_ap_traffic_test() {
  let transcript_hash =
    key_schedule.new_transcript()
    |> key_schedule.add(hex(vectors.client_hello))
    |> key_schedule.add(hex(vectors.server_hello))
    |> key_schedule.add(hex(vectors.encrypted_extensions))
    |> key_schedule.add(hex(vectors.certificate))
    |> key_schedule.add(hex(vectors.certificate_verify))
    |> key_schedule.add(hex(vectors.server_finished))
    |> key_schedule.hash

  key_schedule.client_ap_traffic(hex(vectors.master_secret), transcript_hash)
  |> should.equal(hex(vectors.client_ap_traffic_secret))

  key_schedule.server_ap_traffic(hex(vectors.master_secret), transcript_hash)
  |> should.equal(hex(vectors.server_ap_traffic_secret))
}

pub fn server_finished_verify_data_test() {
  let transcript_hash =
    key_schedule.new_transcript()
    |> key_schedule.add(hex(vectors.client_hello))
    |> key_schedule.add(hex(vectors.server_hello))
    |> key_schedule.add(hex(vectors.encrypted_extensions))
    |> key_schedule.add(hex(vectors.certificate))
    |> key_schedule.add(hex(vectors.certificate_verify))
    |> key_schedule.hash

  key_schedule.finished_verify_data(
    hex(vectors.server_hs_traffic_secret),
    transcript_hash,
  )
  |> should.equal(finished_verify_data_bytes(vectors.server_finished))
}

pub fn client_finished_verify_data_test() {
  let transcript_hash =
    key_schedule.new_transcript()
    |> key_schedule.add(hex(vectors.client_hello))
    |> key_schedule.add(hex(vectors.server_hello))
    |> key_schedule.add(hex(vectors.encrypted_extensions))
    |> key_schedule.add(hex(vectors.certificate))
    |> key_schedule.add(hex(vectors.certificate_verify))
    |> key_schedule.add(hex(vectors.server_finished))
    |> key_schedule.hash

  key_schedule.finished_verify_data(
    hex(vectors.client_hs_traffic_secret),
    transcript_hash,
  )
  |> should.equal(finished_verify_data_bytes(vectors.client_finished))
}

pub fn transcript_incremental_matches_one_shot_test() {
  let one_shot =
    key_schedule.new_transcript()
    |> key_schedule.add(<<
      hex(vectors.client_hello):bits,
      hex(vectors.server_hello):bits,
      hex(vectors.encrypted_extensions):bits,
    >>)
    |> key_schedule.hash

  let incremental =
    key_schedule.new_transcript()
    |> key_schedule.add(hex(vectors.client_hello))
    |> key_schedule.add(hex(vectors.server_hello))
    |> key_schedule.add(hex(vectors.encrypted_extensions))
    |> key_schedule.hash

  incremental
  |> should.equal(one_shot)
}
