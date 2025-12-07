import aether/protocol/tcp/header
import gleam/option
import gleeunit/should

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flag Constructor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn default_flags_all_false_test() {
  let flags = header.default_flags()

  flags.ns |> should.be_false()
  flags.cwr |> should.be_false()
  flags.ece |> should.be_false()
  flags.urg |> should.be_false()
  flags.ack |> should.be_false()
  flags.psh |> should.be_false()
  flags.rst |> should.be_false()
  flags.syn |> should.be_false()
  flags.fin |> should.be_false()
}

pub fn syn_flags_only_syn_true_test() {
  let flags = header.syn_flags()

  flags.syn |> should.be_true()
  flags.ack |> should.be_false()
  flags.fin |> should.be_false()
  flags.rst |> should.be_false()
}

pub fn syn_ack_flags_test() {
  let flags = header.syn_ack_flags()

  flags.syn |> should.be_true()
  flags.ack |> should.be_true()
  flags.fin |> should.be_false()
}

pub fn ack_flags_only_ack_true_test() {
  let flags = header.ack_flags()

  flags.ack |> should.be_true()
  flags.syn |> should.be_false()
  flags.fin |> should.be_false()
}

pub fn fin_ack_flags_test() {
  let flags = header.fin_ack_flags()

  flags.fin |> should.be_true()
  flags.ack |> should.be_true()
  flags.syn |> should.be_false()
}

pub fn fin_flags_test() {
  let flags = header.fin_flags()

  flags.fin |> should.be_true()
  flags.ack |> should.be_false()
}

pub fn rst_flags_test() {
  let flags = header.rst_flags()

  flags.rst |> should.be_true()
  flags.syn |> should.be_false()
  flags.ack |> should.be_false()
}

pub fn psh_ack_flags_test() {
  let flags = header.psh_ack_flags()

  flags.psh |> should.be_true()
  flags.ack |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Constructor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn new_header_defaults_test() {
  let hdr = header.new(8080, 80)

  hdr.source_port |> should.equal(8080)
  hdr.destination_port |> should.equal(80)
  hdr.sequence_number |> should.equal(0)
  hdr.acknowledgment_number |> should.equal(0)
  hdr.data_offset |> should.equal(5)
  hdr.window_size |> should.equal(65_535)
  hdr.checksum |> should.equal(0)
  hdr.urgent_pointer |> should.equal(0)
  hdr.options |> should.equal(option.None)
}

pub fn with_flags_test() {
  let hdr = header.with_flags(8080, 80, header.syn_flags())

  hdr.source_port |> should.equal(8080)
  hdr.flags.syn |> should.be_true()
  hdr.flags.ack |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Header Modifier Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn set_sequence_number_test() {
  let hdr =
    header.new(8080, 80)
    |> header.set_sequence_number(1000)

  hdr.sequence_number |> should.equal(1000)
}

pub fn set_acknowledgment_number_test() {
  let hdr =
    header.new(8080, 80)
    |> header.set_acknowledgment_number(2000)

  hdr.acknowledgment_number |> should.equal(2000)
}

pub fn set_window_size_test() {
  let hdr =
    header.new(8080, 80)
    |> header.set_window_size(32_768)

  hdr.window_size |> should.equal(32_768)
}

pub fn set_checksum_test() {
  let hdr =
    header.new(8080, 80)
    |> header.set_checksum(12_345)

  hdr.checksum |> should.equal(12_345)
}

pub fn set_flags_test() {
  let hdr =
    header.new(8080, 80)
    |> header.set_flags(header.fin_ack_flags())

  hdr.flags.fin |> should.be_true()
  hdr.flags.ack |> should.be_true()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Flag Accessor Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn is_syn_test() {
  let syn_hdr = header.with_flags(8080, 80, header.syn_flags())
  let ack_hdr = header.with_flags(8080, 80, header.ack_flags())

  header.is_syn(syn_hdr) |> should.be_true()
  header.is_syn(ack_hdr) |> should.be_false()
}

pub fn is_syn_ack_test() {
  let syn_ack_hdr = header.with_flags(8080, 80, header.syn_ack_flags())
  let syn_hdr = header.with_flags(8080, 80, header.syn_flags())

  header.is_syn_ack(syn_ack_hdr) |> should.be_true()
  header.is_syn_ack(syn_hdr) |> should.be_false()
}

pub fn is_fin_ack_test() {
  let fin_ack_hdr = header.with_flags(8080, 80, header.fin_ack_flags())
  let fin_hdr = header.with_flags(8080, 80, header.fin_flags())

  header.is_fin_ack(fin_ack_hdr) |> should.be_true()
  header.is_fin_ack(fin_hdr) |> should.be_false()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Function Tests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pub fn header_length_no_options_test() {
  let hdr = header.new(8080, 80)

  header.header_length(hdr) |> should.equal(20)
}

pub fn min_header_size_test() {
  header.min_header_size() |> should.equal(20)
}

pub fn max_header_size_test() {
  header.max_header_size() |> should.equal(60)
}
