// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TCP Connection Manager Module
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// Provides TCP connection management with:
// - Congestion control (Slow Start, Congestion Avoidance, Fast Recovery)
// - Retransmission mechanisms
// - RTT estimation (RFC 6298)
// - Send/receive buffer management
//

import aether/protocol/tcp/header
import aether/protocol/tcp/stage.{type TcpSegment, TcpSegment}
import aether/protocol/tcp/state.{type TcpConnection}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Maximum Segment Size (default for Ethernet)
const mss: Int = 1460

/// Initial retransmission timeout (1 second)
const initial_rto: Int = 1000

/// Minimum RTO (1 second per RFC 6298)
const min_rto: Int = 1000

/// Maximum RTO (60 seconds)
const max_rto: Int = 60_000

/// Initial slow start threshold
const initial_ssthresh: Int = 65_535

/// Number of duplicate ACKs to trigger Fast Retransmit
const dup_ack_threshold: Int = 3

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// TCP Connection Manager
///
/// Provides reliable data transfer over TCP by managing:
/// - Send and receive buffers
/// - Unacknowledged segment tracking
/// - Congestion control state
/// - RTT estimation and retransmission timers
///
pub type TcpConnectionManager {
  TcpConnectionManager(
    /// The underlying TCP connection state
    connection: TcpConnection,
    /// List of segments waiting to be sent (FIFO - head is next to send)
    send_buffer: List(TcpSegment),
    /// List of received out-of-order segments
    recv_buffer: List(TcpSegment),
    /// Segments that have been sent but not yet acknowledged
    unacked_segments: Dict(Int, UnackedSegment),
    /// Congestion control state
    congestion: CongestionControl,
    /// Timer state for RTT estimation and RTO
    timers: ConnectionTimers,
    /// Counter for duplicate ACKs
    dup_ack_count: Int,
    /// Last acknowledged sequence number
    last_ack: Int,
  )
}

/// Unacknowledged segment tracking
///
/// Tracks segments that have been sent but not yet acknowledged,
/// along with timing information for retransmission decisions.
///
pub type UnackedSegment {
  UnackedSegment(
    /// The segment that was sent
    segment: TcpSegment,
    /// Timestamp when the segment was sent (milliseconds)
    sent_at: Int,
    /// Number of times this segment has been retransmitted
    retransmit_count: Int,
  )
}

/// Congestion control state
///
/// Implements the TCP congestion control algorithms:
/// - Slow Start: Exponential growth
/// - Congestion Avoidance: Linear growth
/// - Fast Recovery: Rapid recovery after packet loss
///
pub type CongestionControl {
  CongestionControl(
    /// Congestion window size (in MSS units)
    cwnd: Int,
    /// Slow start threshold (in MSS units)
    ssthresh: Int,
    /// Current congestion control phase
    phase: CongestionPhase,
  )
}

/// Congestion control phases
///
pub type CongestionPhase {
  /// Exponential growth phase (cwnd doubles per RTT)
  SlowStart
  /// Linear growth phase (cwnd increases by 1 MSS per RTT)
  CongestionAvoidance
  /// Recovery phase after detecting packet loss via duplicate ACKs
  FastRecovery
}

/// Connection timer state
///
/// Maintains RTT estimates and calculates retransmission timeout
/// according to RFC 6298.
///
pub type ConnectionTimers {
  ConnectionTimers(
    /// Retransmission timeout in milliseconds
    retransmit_timeout: Int,
    /// Smoothed RTT estimate
    srtt: Float,
    /// RTT variance estimate
    rttvar: Float,
    /// Whether we have an RTT measurement yet
    has_measurement: Bool,
  )
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Constructor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a new connection manager
///
/// ## Parameters
///
/// - `connection`: The underlying TCP connection state
///
/// ## Returns
///
/// A new TcpConnectionManager with default congestion control and timer settings
///
/// ## Examples
///
/// ```gleam
/// let conn = state.new_listener(8080)
/// let manager = connection.new(conn)
/// ```
///
pub fn new(connection: TcpConnection) -> TcpConnectionManager {
  TcpConnectionManager(
    connection: connection,
    send_buffer: [],
    recv_buffer: [],
    unacked_segments: dict.new(),
    congestion: new_congestion_control(),
    timers: new_connection_timers(),
    dup_ack_count: 0,
    last_ack: connection.unacked_seq,
  )
}

/// Creates default congestion control state
///
fn new_congestion_control() -> CongestionControl {
  CongestionControl(cwnd: 1, ssthresh: initial_ssthresh, phase: SlowStart)
}

/// Creates default timer state
///
pub fn new_timers() -> ConnectionTimers {
  ConnectionTimers(
    retransmit_timeout: initial_rto,
    srtt: 0.0,
    rttvar: 0.0,
    has_measurement: False,
  )
}

fn new_connection_timers() -> ConnectionTimers {
  new_timers()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Send Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Queues data for sending
///
/// Adds a new segment to the send buffer. The segment will be sent
/// when process_send is called, respecting the congestion window.
///
/// ## Parameters
///
/// - `manager`: The connection manager
/// - `data`: The payload data to send
///
/// ## Returns
///
/// Updated connection manager with the data queued
///
pub fn send(
  manager: TcpConnectionManager,
  segment: TcpSegment,
) -> TcpConnectionManager {
  // Append to end of list (FIFO queue behavior)
  let new_buffer = list.append(manager.send_buffer, [segment])

  TcpConnectionManager(..manager, send_buffer: new_buffer)
}

/// Queues raw data for sending
///
/// Creates a segment from raw data and queues it for sending.
///
pub fn send_data(
  manager: TcpConnectionManager,
  data: BitArray,
) -> TcpConnectionManager {
  let segment = create_data_segment(manager.connection, data)
  send(manager, segment)
}

/// Processes the send buffer and returns segments to transmit
///
/// Respects the congestion window and only sends as many segments
/// as the window allows.
///
/// ## Parameters
///
/// - `manager`: The connection manager
///
/// ## Returns
///
/// A tuple of (updated manager, list of segments to send)
///
pub fn process_send(
  manager: TcpConnectionManager,
) -> #(TcpConnectionManager, List(TcpSegment)) {
  let available_window = calculate_available_window(manager)

  case available_window > 0 {
    True -> {
      // Send as many segments as window allows
      let #(to_send, remaining) =
        take_from_list(manager.send_buffer, available_window)

      // Mark segments as unacked
      let now = system_time_milliseconds()
      let new_unacked =
        list.fold(to_send, manager.unacked_segments, fn(acc, seg) {
          dict.insert(
            acc,
            seg.header.sequence_number,
            UnackedSegment(segment: seg, sent_at: now, retransmit_count: 0),
          )
        })

      let new_manager =
        TcpConnectionManager(
          ..manager,
          send_buffer: remaining,
          unacked_segments: new_unacked,
        )

      #(new_manager, to_send)
    }
    False -> #(manager, [])
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ACK Handling Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Handles incoming ACK
///
/// Updates the connection state, removes acknowledged segments,
/// and adjusts the congestion window.
///
/// ## Parameters
///
/// - `manager`: The connection manager
/// - `ack_number`: The acknowledgment number from the ACK
/// - `rtt`: Measured round-trip time in milliseconds (if available)
///
/// ## Returns
///
/// Updated connection manager
///
pub fn handle_ack(
  manager: TcpConnectionManager,
  ack_number: Int,
  rtt: Int,
) -> TcpConnectionManager {
  // Check for duplicate ACK
  case ack_number == manager.last_ack {
    True -> {
      // This is a duplicate ACK
      TcpConnectionManager(..manager, dup_ack_count: manager.dup_ack_count + 1)
    }
    False -> {
      // New ACK - remove acknowledged segments
      let new_unacked =
        dict.filter(manager.unacked_segments, fn(seq, _) { seq >= ack_number })

      // Update RTT estimates
      let new_timers = update_rtt(manager.timers, rtt)

      // Update congestion window
      let new_congestion = update_congestion_window_on_ack(manager.congestion)

      // Exit Fast Recovery if we were in it
      let final_congestion = case new_congestion.phase {
        FastRecovery ->
          CongestionControl(
            ..new_congestion,
            cwnd: new_congestion.ssthresh,
            phase: CongestionAvoidance,
          )
        _ -> new_congestion
      }

      TcpConnectionManager(
        ..manager,
        unacked_segments: new_unacked,
        timers: new_timers,
        congestion: final_congestion,
        dup_ack_count: 0,
        last_ack: ack_number,
      )
    }
  }
}

/// Handles duplicate ACKs for Fast Retransmit
///
/// When 3 duplicate ACKs are received, triggers Fast Retransmit
/// and enters Fast Recovery.
///
/// ## Parameters
///
/// - `manager`: The connection manager
/// - `ack_number`: The acknowledgment number from the duplicate ACK
/// - `dup_count`: Number of duplicate ACKs received
///
/// ## Returns
///
/// A tuple of (updated manager, optional segment to retransmit)
///
pub fn handle_duplicate_ack(
  manager: TcpConnectionManager,
  ack_number: Int,
  dup_count: Int,
) -> #(TcpConnectionManager, Option(TcpSegment)) {
  // Update dup_ack_count
  let manager = TcpConnectionManager(..manager, dup_ack_count: dup_count)

  case dup_count >= dup_ack_threshold {
    True -> {
      // Fast retransmit
      case dict.get(manager.unacked_segments, ack_number) {
        Ok(unacked) -> {
          // Enter fast recovery
          let new_ssthresh = int.max(manager.congestion.cwnd / 2, 2)
          let new_congestion =
            CongestionControl(
              cwnd: new_ssthresh + dup_ack_threshold,
              ssthresh: new_ssthresh,
              phase: FastRecovery,
            )

          let new_manager =
            TcpConnectionManager(..manager, congestion: new_congestion)

          #(new_manager, option.Some(unacked.segment))
        }
        Error(_) -> {
          // Segment not found, just enter fast recovery without retransmit
          let new_ssthresh = int.max(manager.congestion.cwnd / 2, 2)
          let new_congestion =
            CongestionControl(
              cwnd: new_ssthresh + dup_ack_threshold,
              ssthresh: new_ssthresh,
              phase: FastRecovery,
            )
          let new_manager =
            TcpConnectionManager(..manager, congestion: new_congestion)
          #(new_manager, option.None)
        }
      }
    }
    False -> #(manager, option.None)
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Retransmission Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Checks for segments that need retransmission
///
/// Scans all unacknowledged segments and returns those that have
/// exceeded the retransmission timeout.
///
/// ## Parameters
///
/// - `manager`: The connection manager
///
/// ## Returns
///
/// A tuple of (updated manager, list of segments to retransmit)
///
pub fn check_retransmissions(
  manager: TcpConnectionManager,
) -> #(TcpConnectionManager, List(TcpSegment)) {
  let now = system_time_milliseconds()
  let rto = manager.timers.retransmit_timeout

  let #(to_retransmit, new_unacked) =
    dict.fold(
      manager.unacked_segments,
      #([], manager.unacked_segments),
      fn(acc, seq, unacked) {
        let #(retrans, dict_acc) = acc
        let time_since_sent = now - unacked.sent_at

        case time_since_sent > rto {
          True -> {
            // Timeout occurred, retransmit
            let updated_unacked =
              UnackedSegment(
                ..unacked,
                sent_at: now,
                retransmit_count: unacked.retransmit_count + 1,
              )

            #(
              [unacked.segment, ..retrans],
              dict.insert(dict_acc, seq, updated_unacked),
            )
          }
          False -> acc
        }
      },
    )

  // On timeout, enter slow start
  let new_congestion = case list.length(to_retransmit) > 0 {
    True ->
      CongestionControl(
        cwnd: 1,
        ssthresh: int.max(manager.congestion.cwnd / 2, 2),
        phase: SlowStart,
      )
    False -> manager.congestion
  }

  let new_manager =
    TcpConnectionManager(
      ..manager,
      unacked_segments: new_unacked,
      congestion: new_congestion,
    )

  #(new_manager, to_retransmit)
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Congestion Control Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Calculates the available window for sending
///
/// The available window is the minimum of the congestion window and
/// the receiver's advertised window, minus any unacknowledged data.
///
/// ## Parameters
///
/// - `manager`: The connection manager
///
/// ## Returns
///
/// Number of segments that can be sent
///
pub fn calculate_available_window(manager: TcpConnectionManager) -> Int {
  let cwnd_bytes = manager.congestion.cwnd * mss
  let unacked_bytes = dict.size(manager.unacked_segments) * mss
  let remote_window = manager.connection.remote_window

  // Available = min(cwnd, remote_window) - unacked
  let max_window = int.min(cwnd_bytes, remote_window)
  int.max(0, { max_window - unacked_bytes } / mss)
}

/// Updates the congestion window on receiving an ACK
///
/// Implements the congestion control algorithm:
/// - Slow Start: cwnd += 1 per ACK (exponential growth)
/// - Congestion Avoidance: cwnd += 1/cwnd per ACK (linear growth)
/// - Fast Recovery: cwnd += 1 per duplicate ACK
///
/// ## Parameters
///
/// - `congestion`: Current congestion control state
///
/// ## Returns
///
/// Updated congestion control state
///
pub fn update_congestion_window_on_ack(
  congestion: CongestionControl,
) -> CongestionControl {
  case congestion.phase {
    SlowStart -> {
      // Exponential growth: cwnd += 1 per ACK
      let new_cwnd = congestion.cwnd + 1

      case new_cwnd >= congestion.ssthresh {
        True ->
          CongestionControl(
            cwnd: new_cwnd,
            ssthresh: congestion.ssthresh,
            phase: CongestionAvoidance,
          )
        False -> CongestionControl(..congestion, cwnd: new_cwnd)
      }
    }

    CongestionAvoidance -> {
      // Linear growth: cwnd += 1/cwnd per ACK
      // For integer math, increment by 1 (conservative approximation)
      CongestionControl(..congestion, cwnd: congestion.cwnd + 1)
    }

    FastRecovery -> {
      // Inflate window for each duplicate ACK
      CongestionControl(..congestion, cwnd: congestion.cwnd + 1)
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RTT Estimation Functions (RFC 6298)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Updates RTT estimates and recalculates RTO
///
/// Implements the RFC 6298 algorithm for RTT estimation:
/// - First measurement: SRTT = R, RTTVAR = R/2
/// - Subsequent: RTTVAR = (1-β)*RTTVAR + β*|SRTT-R|, SRTT = (1-α)*SRTT + α*R
/// - RTO = SRTT + 4*RTTVAR
///
/// ## Parameters
///
/// - `timers`: Current timer state
/// - `measured_rtt`: New RTT measurement in milliseconds
///
/// ## Returns
///
/// Updated timer state with new RTO
///
pub fn update_rtt(timers: ConnectionTimers, measured_rtt: Int) -> ConnectionTimers {
  let m = int.to_float(measured_rtt)

  case timers.has_measurement {
    False -> {
      // First RTT measurement
      ConnectionTimers(
        retransmit_timeout: int.max(min_rto, measured_rtt * 2),
        srtt: m,
        rttvar: m /. 2.0,
        has_measurement: True,
      )
    }
    True -> {
      // RFC 6298 algorithm
      let alpha = 0.125
      let beta = 0.25

      let rttvar =
        { 1.0 -. beta }
        *. timers.rttvar
        +. beta
        *. float_abs(timers.srtt -. m)
      let srtt = { 1.0 -. alpha } *. timers.srtt +. alpha *. m

      let rto = float.round(srtt +. 4.0 *. rttvar)
      let rto = int.max(min_rto, rto)
      let rto = int.min(max_rto, rto)

      ConnectionTimers(
        retransmit_timeout: rto,
        srtt: srtt,
        rttvar: rttvar,
        has_measurement: True,
      )
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Out-of-Order Packet Handling
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Buffers an out-of-order segment for later processing
///
/// ## Parameters
///
/// - `manager`: The connection manager
/// - `segment`: The out-of-order segment to buffer
///
/// ## Returns
///
/// Updated connection manager with the segment buffered
///
pub fn buffer_out_of_order(
  manager: TcpConnectionManager,
  segment: TcpSegment,
) -> TcpConnectionManager {
  let new_buffer = list.append(manager.recv_buffer, [segment])
  TcpConnectionManager(..manager, recv_buffer: new_buffer)
}

/// Processes buffered segments and returns in-order data
///
/// ## Parameters
///
/// - `manager`: The connection manager
/// - `expected_seq`: The expected sequence number
///
/// ## Returns
///
/// A tuple of (updated manager, list of in-order segments)
///
pub fn process_recv_buffer(
  manager: TcpConnectionManager,
  expected_seq: Int,
) -> #(TcpConnectionManager, List(TcpSegment)) {
  do_process_recv_buffer(manager, expected_seq, [])
}

fn do_process_recv_buffer(
  manager: TcpConnectionManager,
  expected_seq: Int,
  acc: List(TcpSegment),
) -> #(TcpConnectionManager, List(TcpSegment)) {
  case manager.recv_buffer {
    [segment, ..remaining] -> {
      case segment.header.sequence_number == expected_seq {
        True -> {
          // This segment is in order
          let new_manager =
            TcpConnectionManager(..manager, recv_buffer: remaining)
          let payload_len = bit_array_byte_size(segment.payload)
          do_process_recv_buffer(
            new_manager,
            expected_seq + payload_len,
            [segment, ..acc],
          )
        }
        False -> {
          // Not in order - stop processing
          #(manager, list.reverse(acc))
        }
      }
    }
    [] -> #(manager, list.reverse(acc))
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Helper Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Creates a data segment from the connection state
///
fn create_data_segment(conn: TcpConnection, data: BitArray) -> TcpSegment {
  TcpSegment(
    header: header.TcpHeader(
      source_port: conn.local_port,
      destination_port: conn.remote_port,
      sequence_number: conn.local_seq,
      acknowledgment_number: conn.remote_seq,
      data_offset: 5,
      flags: header.ack_flags(),
      window_size: conn.local_window,
      checksum: 0,
      urgent_pointer: 0,
      options: option.None,
    ),
    payload: data,
  )
}

/// Takes elements from the front of a list
///
fn take_from_list(
  items: List(TcpSegment),
  count: Int,
) -> #(List(TcpSegment), List(TcpSegment)) {
  do_take_from_list(items, count, [])
}

fn do_take_from_list(
  items: List(TcpSegment),
  remaining: Int,
  acc: List(TcpSegment),
) -> #(List(TcpSegment), List(TcpSegment)) {
  case remaining <= 0 {
    True -> #(list.reverse(acc), items)
    False -> {
      case items {
        [first, ..rest] ->
          do_take_from_list(rest, remaining - 1, [first, ..acc])
        [] -> #(list.reverse(acc), [])
      }
    }
  }
}

/// Absolute value for floats
///
fn float_abs(x: Float) -> Float {
  case x <. 0.0 {
    True -> 0.0 -. x
    False -> x
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Accessor Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Gets the current congestion window size
///
pub fn get_cwnd(manager: TcpConnectionManager) -> Int {
  manager.congestion.cwnd
}

/// Gets the current slow start threshold
///
pub fn get_ssthresh(manager: TcpConnectionManager) -> Int {
  manager.congestion.ssthresh
}

/// Gets the current congestion phase
///
pub fn get_phase(manager: TcpConnectionManager) -> CongestionPhase {
  manager.congestion.phase
}

/// Gets the current RTO in milliseconds (from manager)
///
pub fn get_rto_from_manager(manager: TcpConnectionManager) -> Int {
  manager.timers.retransmit_timeout
}

/// Gets the RTO from timer state
///
pub fn get_rto(timers: ConnectionTimers) -> Int {
  timers.retransmit_timeout
}

/// Gets the SRTT from timer state
///
pub fn get_srtt(timers: ConnectionTimers) -> Float {
  timers.srtt
}

/// Gets the RTTVAR from timer state
///
pub fn get_rttvar(timers: ConnectionTimers) -> Float {
  timers.rttvar
}

/// Gets the underlying connection
///
pub fn get_connection(manager: TcpConnectionManager) -> TcpConnection {
  manager.connection
}

/// Updates the underlying connection
///
pub fn set_connection(
  manager: TcpConnectionManager,
  connection: TcpConnection,
) -> TcpConnectionManager {
  TcpConnectionManager(..manager, connection: connection)
}

/// Gets the number of unacknowledged segments
///
pub fn unacked_count(manager: TcpConnectionManager) -> Int {
  dict.size(manager.unacked_segments)
}

/// Gets the number of unacknowledged segments (alias)
///
pub fn get_unacked_count(manager: TcpConnectionManager) -> Int {
  unacked_count(manager)
}

/// Gets the number of segments in the send buffer
///
pub fn send_buffer_size(manager: TcpConnectionManager) -> Int {
  list.length(manager.send_buffer)
}

/// Gets the number of segments in the send buffer (alias)
///
pub fn get_send_buffer_size(manager: TcpConnectionManager) -> Int {
  send_buffer_size(manager)
}

/// Gets the number of segments in the receive buffer
///
pub fn recv_buffer_size(manager: TcpConnectionManager) -> Int {
  list.length(manager.recv_buffer)
}

/// Gets the number of segments in the receive buffer (alias)
///
pub fn get_recv_buffer_size(manager: TcpConnectionManager) -> Int {
  recv_buffer_size(manager)
}

/// Gets the duplicate ACK count
///
pub fn get_dup_ack_count(manager: TcpConnectionManager) -> Int {
  manager.dup_ack_count
}

/// Sets the slow start threshold
///
pub fn set_ssthresh(manager: TcpConnectionManager, ssthresh: Int) -> TcpConnectionManager {
  let new_congestion = CongestionControl(..manager.congestion, ssthresh: ssthresh)
  TcpConnectionManager(..manager, congestion: new_congestion)
}

/// Handles timeout event
///
/// Resets congestion state to Slow Start with cwnd = 1 and
/// ssthresh = cwnd/2 (at least 2)
///
pub fn handle_timeout(manager: TcpConnectionManager) -> TcpConnectionManager {
  let new_ssthresh = int.max(manager.congestion.cwnd / 2, 2)
  let new_congestion = CongestionControl(
    cwnd: 1,
    ssthresh: new_ssthresh,
    phase: SlowStart,
  )
  TcpConnectionManager(..manager, congestion: new_congestion)
}

/// Converts congestion phase to string
///
pub fn phase_to_string(phase: CongestionPhase) -> String {
  case phase {
    SlowStart -> "SlowStart"
    CongestionAvoidance -> "CongestionAvoidance"
    FastRecovery -> "FastRecovery"
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// FFI - External Functions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@external(erlang, "os", "system_time")
fn system_time_milliseconds() -> Int

@external(erlang, "erlang", "byte_size")
fn bit_array_byte_size(data: BitArray) -> Int
