// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA formatter (TX module for QSFP lane)
//
// Builds custom Ethernet frames from slave/master commands and CE payload data.
// Output Data (qsfp_tx_tdata) is byte swapped
//
// Packet types (FSM priority, highest first):
//   CT_EMISSION  (slave)  - multi-frame: NB_PACKETS_FULL (full) + 1 (partial), payload from CE FIFO
//   NOTIFY_ACK   (slave)  - single small packet (NB_WORDS_MIN words)
//   READ_REQ     (master) - single small packet
//   NOTIFY       (master) - single small packet
//
// Completion signals (*_sent) are a registered pulse.
//
// Notes :
//  > slave_command_rdy & master_command_rdy are single-cycle pulses (from consume_* edge detectors),
// not levels. The upstream slave/master hold command_vld high until these pulse arrives.
//  > Ciphertext is put into a store & forward FIFO:
// This guarantees continuous tvalid mid-frame depending on packet size (MRMAC drops frames on gap).
//
// Assumptions :
// - The upstream slave/master hold command_vld high until these pulse arrives.
// - command.hpu_id must be < NB_MAX_HPU. No bounds check on MAC table index;
// - NB_PACKETS_FULL >= 1. The stalling / threshold logic assumes at least one full frame.
// - LAST_PACKET_BYTE_SIZE >= ETH_NB_BYTES_MIN (64).
// - Commands with unrecognized req_id are silently discarded
// - Formatter_error (sticky, cleared by rst_errors) detects tvalid gap during CE payload
//   transmission. fifo_ce gating should prevent this under normal operation.
//
// ================================================================================================

module mhdma_formatter
  import mhdma_pkg::*;                              // multi-hpu-dma
  import axi_if_mhdma_axi_pkg::*;                   // AXI4
  import axi_if_shell_axil_pkg::*;                  // REG_DATA_W
(
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                      clk_mhdma,
  input  logic                                      resetn_mhdma,
  // bridge interface ---------------------------------------------------------
  input  logic [NB_MAX_HPU-1:0][    MAC_ADDR_W-1:0] hpu_mac_table,
  input  logic                 [      HPU_ID_W-1:0] current_hpu_id,
  input  logic                 [    MAC_ADDR_W-1:0] current_hpu_mac,
  // slave interface ---------------------------------------------------------
  input  command_t                                  slave_command,
  input  logic                                      slave_command_vld,
  output logic                                      slave_command_rdy,

  input  logic                 [  MRMAC_AXIS_W-1:0] ce_payload,
  output logic                                      ce_rdy,
  input  logic                                      ce_vld,

  output logic                                      notify_ack_sent,
  output logic                                      ciphertext_sent,
  // master interface ---------------------------------------------------------
  input  command_t                                  master_command,
  input  logic                                      master_command_vld,
  output logic                                      master_command_rdy,

  output logic                                      notify_sent,
  output logic                                      read_request_sent,
  // Error interface ----------------------------------------------------------
  output format_error_t                             format_error,
  input  logic                                      rst_errors,
  // QSFP TX interface --------------------------------------------------------
  output logic                 [  MRMAC_AXIS_W-1:0] qsfp_tx_tdata,
  output logic                 [ MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user,
  output logic                                      qsfp_tx_tlast,
  output logic                                      qsfp_tx_tvalid,
  input  logic                                      qsfp_tx_tready,
  // statistics ---------------------------------------------------------------
  output formatter_stat_t                           stat,
  input  formatter_stat_rst_t                       stat_rst
);

// pragma translate_off
  initial begin
    assert (LAST_PACKET_BYTE_SIZE >= ETH_NB_BYTES_MIN)
    else $error("> ERROR: LAST_PACKET_BYTE_SIZE must be >= ETH_NB_BYTES_MIN");
  end
// pragma translate_on

  // =========================================================================================== //
  // Localparam
  // =========================================================================================== //
  localparam int NB_WORDS_FULL    = NB_WORDS_CUST_HEADER_SIZE+NB_WORDS_PAYLOAD;
  localparam int NB_WORDS_PARTIAL = NB_WORDS_LAST_PACKET+NB_WORDS_CUST_HEADER_SIZE;

  localparam int CE_FRAME_CNT_W  = $clog2(NB_WORDS_PAYLOAD+1);

  // =========================================================================================== //
  // MAC table pipeline
  // =========================================================================================== //
  // this register is needed to ease timing
  logic [NB_MAX_HPU-1:0][MAC_ADDR_W-1:0] hpu_mac_table_tmp;

  always_ff @(posedge clk_mhdma)
    hpu_mac_table_tmp <= hpu_mac_table;

  // =========================================================================================== //
  // Ciphertext Emission FIFO
  // =========================================================================================== //
  logic                    ce_fifo_rdy;
  logic                    ce_frame_ready;

  logic [MRMAC_AXIS_W-1:0] ce_fifo_out_data;
  logic                    ce_fifo_out_vld;
  logic                    ce_fifo_out_rdy;

  // Frame-level buffering: accumulate enough payload words before allowing consumption.
  // This is needed to guarantee no tvalid gap mid-frame, otherwise MRMAC drops the packet
  fifo_ram_rdy_vld # (
    .WIDTH       (MRMAC_AXIS_W    ),
    .DEPTH       (NB_WORDS_PAYLOAD),
    .RAM_LATENCY (CE_RAM_LATENCY  ),
    .ALMOST_FULL_REMAIN (0)
  ) fifo_ce (
    .clk         (clk_mhdma   ),
    .s_rst_n     (resetn_mhdma),

    .in_data     (ce_payload),
    .in_vld      (ce_vld),
    .in_rdy      (ce_rdy),

    .out_data    (ce_fifo_out_data),
    .out_vld     (ce_fifo_out_vld),
    .out_rdy     (ce_fifo_out_rdy),

    .almost_full (/* UNUSED */)
  );

  assign ce_fifo_out_rdy = ce_fifo_rdy & ce_frame_ready;

  // Fill-level counter for fifo_ce for store & forward by frame-size
  logic [CE_FRAME_CNT_W-1:0] ce_frame_cnt;
  logic                      ce_fifo_up;
  logic                      ce_fifo_down;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ce_frame_cnt <= 'h0;
    end else begin
      if (ciphertext_sent) begin
        ce_frame_cnt <= 'h0;
      end else begin
        if (ce_fifo_up & ~ce_fifo_down) begin
          ce_frame_cnt <= ce_frame_cnt + 1;
        end else if (ce_fifo_down & ~ce_fifo_up) begin
          ce_frame_cnt <= ce_frame_cnt - 1;
        end
      end
    end
  end

  assign ce_fifo_up   = ce_vld & ce_rdy;
  assign ce_fifo_down = ce_fifo_out_rdy & ce_fifo_out_vld;

  // =========================================================================================== //
  // FSM
  // =========================================================================================== //
  logic ct_emission_pending;
  logic notify_ack_pending;
  logic read_request_pending;
  logic notify_request_pending;

  logic consume_ct_emission;
  logic consume_notify;
  logic consume_notify_ack;
  logic consume_read_request;

  // TX FSM ---------------------------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_XXX         = 'x,
    ST_IDLE        = 3'b000,
    ST_CT_EMISSION = 3'b001,
    ST_NOTIFY_ACK  = 3'b010,
    ST_READ_REQ    = 3'b011,
    ST_NOTIFY      = 3'b100
  } st_tx;

  st_tx tx_state;
  st_tx tx_next_state;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) tx_state <= ST_IDLE;
    else tx_state <= tx_next_state;
  end

  always_comb begin
    tx_next_state = ST_XXX;
    case (tx_state)
      ST_IDLE:
        begin
          if (ct_emission_pending) begin
            tx_next_state = ST_CT_EMISSION;
          end else if (notify_ack_pending) begin
            tx_next_state = ST_NOTIFY_ACK;
          end else if (read_request_pending) begin
            tx_next_state = ST_READ_REQ;
          end else if (notify_request_pending) begin
            tx_next_state = ST_NOTIFY;
          end else begin
            tx_next_state = ST_IDLE;
          end
        end
      ST_CT_EMISSION:
        tx_next_state = ciphertext_sent ? ST_IDLE : ST_CT_EMISSION;
      ST_NOTIFY_ACK:
        tx_next_state = notify_ack_sent ? ST_IDLE : ST_NOTIFY_ACK;
      ST_READ_REQ:
        tx_next_state = read_request_sent ? ST_IDLE : ST_READ_REQ;
      ST_NOTIFY:
        tx_next_state = notify_sent ? ST_IDLE : ST_NOTIFY;
      default:
        tx_next_state = ST_IDLE;
    endcase
  end

  logic st_ct_emission;
  logic st_notify_ack;
  logic st_read_request;
  logic st_notify_request;

  assign st_ct_emission    = tx_state == ST_CT_EMISSION;
  assign st_notify_ack     = tx_state == ST_NOTIFY_ACK;
  assign st_read_request   = tx_state == ST_READ_REQ;
  assign st_notify_request = tx_state == ST_NOTIFY;

  // ----------------------------------------------------------------------------------------------
  assign ct_emission_pending    = slave_command_vld  & (slave_command.req_id  == REQ_ID_EMISSION);
  assign notify_ack_pending     = slave_command_vld  & (slave_command.req_id  == REQ_ID_NOTIFY_ACK);
  assign read_request_pending   = master_command_vld & (master_command.req_id == REQ_ID_READ);
  assign notify_request_pending = master_command_vld & (master_command.req_id == REQ_ID_NOTIFY);

  // ----------------------------------------------------------------------------------------------
  // Building ready sink from FSM : consume one and only data when we are in a specific state
  logic st_ct_emissionQ;
  logic st_notify_ackQ;
  logic st_read_requestQ;
  logic st_notify_requestQ;

  always_ff @(posedge clk_mhdma) begin
    st_ct_emissionQ    <= st_ct_emission;
    st_notify_ackQ     <= st_notify_ack;
    st_read_requestQ   <= st_read_request;
    st_notify_requestQ <= st_notify_request;
  end

  assign consume_ct_emission  = st_ct_emission & ~st_ct_emissionQ;
  assign consume_notify_ack   = st_notify_ack & ~st_notify_ackQ;
  assign consume_read_request = st_read_request & ~st_read_requestQ;
  assign consume_notify       = st_notify_request & ~st_notify_requestQ;


  // =========================================================================================== //
  // Consuming commands over slave & master
  // =========================================================================================== //

  // Guardrail : Discarding falses commands -------------------------------------------------------
  // Discard commands w/ unrecognized req_id to prevent upstream blocking (and having to reset
  // after wrong manipulation)
  logic slave_discard;
  logic master_discard;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      slave_discard  <= 1'b0;
      master_discard <= 1'b0;
    end else begin
      slave_discard  <= (tx_state == ST_IDLE) & slave_command_vld
                      & (slave_command.req_id  != REQ_ID_EMISSION) & (slave_command.req_id  != REQ_ID_NOTIFY_ACK)
                      & ~slave_discard;
      master_discard <= (tx_state == ST_IDLE) & master_command_vld
                      & (master_command.req_id != REQ_ID_READ) & (master_command.req_id != REQ_ID_NOTIFY)
                      & ~master_discard;
    end
  end

  assign slave_command_rdy  = consume_ct_emission | consume_notify_ack | slave_discard;
  assign master_command_rdy = consume_notify | consume_read_request | master_discard;

  // =========================================================================================== //
  // Building headers
  // =========================================================================================== //
  // control --------------------------------------------------------------------------------------
  // We are sending a request on qsfp lane when we have a pulse on header start-of-packet.
  // Deasserting this request when we hit enough words on the counter
  logic header_sop;                    // pulse
  // to simplify notations we define each cases as :
  logic stop_sending_small_packet;     // notify / notify-ack / read-request
  logic stop_sending_ce_full_frame;    // ciphertext-emission: when we send ETH_NB_BYTES_PAYLOAD
  logic stop_sending_ce_partial_frame; // ciphertext-emission: when we send LAST_PACKET_BYTE_SIZE
  logic end_of_packet;                 // pulse of all stop signals
  logic okay_to_send_request;          // level between start of / end of packet
  logic small_packet;                  // level of a small packet (notify & ack + read request)

  logic tx_header_last; // pulse when tx_cnt == NB_WORDS_CUST_HEADER_SIZE (4): end of the 4-word custom header
  logic tx_small_last;  // pulse when tx_cnt == NB_WORDS_MIN (8): end of a small packet (notify/ack/read-req: header + zero-padding)
  logic tx_last_word;   // pulse at end of a CE frame: tx_cnt == NB_WORDS_FULL (or NB_WORDS_PARTIAL on last packet)

  // Signals feeding the output AXI-Stream buffer (fifo_element_qsfp)
  logic                     tx_tlast_D;
  logic [ MRMAC_AXIS_W-1:0] tx_tdata_D;
  logic [MRMAC_TKEEP_W-1:0] tx_tkeep_user_D;
  logic                     tx_tvalid_D;
  logic                     tx_tready;

  logic [$clog2(NB_WORDS_MAX)+1:0] tx_cnt;
  logic [        MRMAC_AXIS_W-1:0] tx_header;
  logic                            ce_header_valid;

  // Ciphertext Emission control ------------------------------------------------------------------
  // During CE we increment seq_num for each frame sent.
  // Used to detect the last frame (ce_seq_num == NB_PACKETS_FULL) and to populate the header.
  logic [SEQ_NUM_W-1:0] ce_seq_num;
  // we need to build header and stall ciphertext arrival until we are ready
  logic ce_first_header;      // level: up for first packet header (used for tx & backpressure)
  logic ce_first_header_sent; // level: up when first packet header has been sent
  logic ce_last_packet;       // level: up when last packet is transmitting
  logic ce_end_of_packet;     // pulse: asserted on any stop condition (OR of all stop signals)
  logic ce_start_of_header;   // pulse: header transmission for all packets
  logic ce_start_emission;    // pulse: start of first header transmission
  logic ce_sop_header;        // pulse: start-of headers between packets

  always_ff @(posedge clk_mhdma)
    small_packet <= st_read_request | st_notify_request | st_notify_ack;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      tx_cnt <= 'h0;
    end else begin
      if (okay_to_send_request & ~end_of_packet & tx_tready) begin
        if (st_ct_emission) begin
          if (ce_header_valid | (ce_fifo_out_rdy & ce_fifo_out_vld)) begin
            tx_cnt <= tx_cnt+1;
          end
        end else begin
          tx_cnt <= tx_cnt+1;
        end
      end else if (end_of_packet) begin
        tx_cnt <= 'h0;
      end
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      okay_to_send_request <= 1'b0;
    end else begin
      if (header_sop) begin
        okay_to_send_request <= 1'b1;
      end else if (end_of_packet) begin
        okay_to_send_request <= 1'b0;
      end
    end
  end

  assign stop_sending_small_packet     = tx_tready & (tx_cnt == NB_WORDS_MIN)     & small_packet;
  assign stop_sending_ce_full_frame    = tx_tready & (tx_cnt == NB_WORDS_FULL)    & st_ct_emission & ~ce_last_packet;
  assign stop_sending_ce_partial_frame = tx_tready & (tx_cnt == NB_WORDS_PARTIAL) & ce_last_packet;

  assign end_of_packet = stop_sending_small_packet | stop_sending_ce_full_frame | stop_sending_ce_partial_frame;

  assign tx_small_last  = tx_tready & (tx_cnt == NB_WORDS_MIN);
  assign tx_header_last = tx_tready & (tx_cnt == NB_WORDS_CUST_HEADER_SIZE);
  assign tx_last_word   = tx_tready & st_ct_emission & (ce_last_packet ? (tx_cnt == NB_WORDS_PARTIAL) : (tx_cnt == NB_WORDS_FULL));

  assign header_sop = consume_ct_emission | consume_notify_ack | consume_notify | consume_read_request | ce_start_of_header;

  // =========================================================================================== //
  // Ciphertext Emission (CE)
  // =========================================================================================== //
  assign ce_start_of_header = ce_start_emission | ce_sop_header;

  // this signal must be reset, it is linked to FSM changing state
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ce_last_packet <= 1'b0;
    end else begin
      if (tx_tready & st_ct_emission & (ce_seq_num == NB_PACKETS_FULL) & ~tx_tlast_D) begin
        ce_last_packet <= 1'b1;
      end else if (tx_tlast_D) begin
        ce_last_packet <= 1'b0;
      end
    end
  end

  assign ce_end_of_packet = ce_last_packet & tx_tlast_D;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ce_first_header <= 1'b0;
    end else begin
      if (tx_header_last) begin
        ce_first_header <= 1'b0;
      end else if (ce_start_emission) begin
        ce_first_header <= 1'b1;
      end
    end
  end

  // Registration of slave command
  command_t ce_header_payload_tmp;

  always_ff @(posedge clk_mhdma)
    if (consume_ct_emission)
      ce_header_payload_tmp <= slave_command;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ce_seq_num <= 'h0;
    end else begin
      if (ce_sop_header) begin
        ce_seq_num <= ce_seq_num+1;
      end else if (ce_end_of_packet) begin
        ce_seq_num <= 'h0;
      end
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ce_first_header_sent <= 1'b0;
    end else begin
      if (ce_first_header & tx_header_last) begin
        ce_first_header_sent <= 1'b1;
      end else if (ce_end_of_packet) begin
        ce_first_header_sent <= 1'b0;
      end
    end
  end

  assign ce_start_emission = ce_frame_ready & ce_fifo_out_vld & st_ct_emission & (ce_seq_num == 0) & ~ce_first_header_sent;

  // =========================================================================================== //
  // Cycle by cycle construction
  // =========================================================================================== //
  logic [  MAC_ADDR_W-1:0] header_target_hpu_mac_addr;
  logic [ETHERNET_LEN-1:0] header_eth_len;
  logic [   SEQ_NUM_W-1:0] header_seq_num;
  logic [  DST_ADDR_W-1:0] header_dst_addr;
  logic [  SRC_ADDR_W-1:0] header_src_addr;
  logic [      RSVD_W-1:0] header_rsvd;
  logic [      FLAG_W-1:0] header_flag;
  logic [      MODE_W-1:0] header_mode;
  logic [    REQ_ID_W-1:0] header_req_id;
  logic [    IOP_ID_W-1:0] header_iop_id;

  // header assignation depending on request
  always_ff @(posedge clk_mhdma) begin : prc_header_gen
    if (consume_notify | consume_read_request) begin
      header_target_hpu_mac_addr <= hpu_mac_table_tmp[master_command.hpu_id];
      header_req_id              <= master_command.req_id;
      header_src_addr            <= master_command.src_addr;
      header_dst_addr            <= master_command.dst_addr;
      header_iop_id              <= master_command.iop_id;
      header_rsvd                <= master_command.rsvd;
      header_flag                <= master_command.flag;
      header_mode                <= master_command.mode;
    end else if (consume_ct_emission | consume_notify_ack) begin
      header_target_hpu_mac_addr <= hpu_mac_table_tmp[slave_command.hpu_id];
      header_req_id              <= slave_command.req_id;
      header_src_addr            <= slave_command.src_addr;
      header_dst_addr            <= slave_command.dst_addr;
      header_iop_id              <= slave_command.iop_id;
      header_rsvd                <= slave_command.rsvd;
      header_flag                <= slave_command.flag;
      header_mode                <= slave_command.mode;
    end else if (ce_fifo_out_vld & st_ct_emission) begin
      header_target_hpu_mac_addr <= hpu_mac_table_tmp[ce_header_payload_tmp.hpu_id];
      header_req_id              <= REQ_ID_EMISSION;
      header_src_addr            <= ce_header_payload_tmp.src_addr;
      header_dst_addr            <= ce_header_payload_tmp.dst_addr;
      header_iop_id              <= ce_header_payload_tmp.iop_id;
      header_rsvd                <= ce_header_payload_tmp.rsvd;
      header_flag                <= ce_header_payload_tmp.flag;
      header_mode                <= ce_header_payload_tmp.mode;
    end
  end

  always_ff @(posedge clk_mhdma) begin : prc_header_ethernet_len
    if (small_packet) begin
      header_eth_len <= ETH_LEN_MIN;
    end else if (ce_last_packet) begin
      header_eth_len <= ETH_LEN_LAST_PKT;
    end else begin
      header_eth_len <= ETH_LEN_MAX;
    end
  end

  always_ff @(posedge clk_mhdma) begin : prc_header_ce
    if (st_ct_emission) begin
      header_seq_num <= ce_seq_num;
    end else begin
      header_seq_num <= 'h0;
    end
  end

  always_comb begin
    case (tx_cnt)
      'h1 :
        tx_header = {MAC_OUI, header_target_hpu_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
      'h2 :
        tx_header = {MAC_OUI[7:0], current_hpu_mac, header_eth_len, LLC_DSAP, LLC_SSAP};
      'h3 :
        tx_header = {LLC_CTRL, header_req_id, current_hpu_id, header_seq_num, header_src_addr, header_dst_addr, header_iop_id};
      'h4 :
        tx_header = {header_rsvd, header_flag, header_mode, 48'h0};
      default:
        tx_header = 'h0;
    endcase
  end

  // tkeep ----------------------------------------------------------------------------------------
  logic [$clog2(MRMAC_AXIS_BYTES)-1:0] last_word_bytes;
  logic [        MRMAC_AXIS_BYTES-1:0] tx_byte_enable;
  logic [        MRMAC_AXIS_BYTES-1:0] tx_byte_enable_d;

  assign tx_byte_enable_d = (last_word_bytes == 0) ? {MRMAC_AXIS_BYTES{1'b1}} : MRMAC_AXIS_BYTES'(1 << last_word_bytes) - 1;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      tx_byte_enable <= 'h0;
    end else begin
      if (okay_to_send_request & tx_tready) begin
        if ((tx_cnt == 0) | ~small_packet) begin
          tx_byte_enable <= {(MRMAC_AXIS_W/8){1'b1}};
        end else if (small_packet & (tx_cnt == (NB_WORDS_MIN-1))) begin
          tx_byte_enable <= tx_byte_enable_d;
        end else if (ce_last_packet & (tx_cnt == (NB_WORDS_PARTIAL-1))) begin
           tx_byte_enable <= tx_byte_enable_d;
        end
      end
    end
  end

  assign last_word_bytes = (ETH_NB_BYTES_HEADER + header_eth_len) & {$clog2(MRMAC_AXIS_BYTES){1'b1}};

  // =========================================================================================== //
  // Building packets
  // =========================================================================================== //
  // Ciphertext emission --------------------------------------------------------------------------
  // MRMAC drops frames on tvalid gaps mid-frame: between two CE frames, stall CE FIFO reads
  // while the next inter-frame header is emitted so the payload stream stays gap-free.
  // (The very first header is sent at start of CT emission, before any payload — see ce_first_header.)
  logic ce_stalling; // level: high during inter-frame header window
  logic ce_stalling_tmp;
  logic ce_header_pending;

  // we should stall the emission of coefficients after we have the correct number of words
  // we should stop stalling when header has left module
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ce_stalling <= 1'b0;
    end else begin
      if (tx_tready & (tx_cnt == NB_WORDS_FULL)) begin
        ce_stalling <= 1'b1;
      end else if (tx_header_last) begin
        ce_stalling <= 1'b0;
      end
    end
  end

  // edge detection on ce_stalling (used to set pending flag)
  always_ff @(posedge clk_mhdma)
    ce_stalling_tmp <= ce_stalling;

  // inter-frame header pending flag: converts edge into level that waits for CE FIFO ready
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ce_header_pending <= 1'b0;
    end else begin
      if (ce_sop_header) begin
        ce_header_pending <= 1'b0;
      end else if (ce_stalling & ~ce_stalling_tmp) begin
        ce_header_pending <= 1'b1;
      end
    end
  end

  // header starts only when FIFO has enough data for the next frame
  assign ce_sop_header = ce_header_pending & ce_frame_ready;

  // level active when we have headers on ciphertext emission
  assign ce_header_valid = (ce_first_header | ce_stalling);

  // CE FIFO read-enable (gating, not true backpressure): pop a coefficient only when MRMAC
  // is ready, FSM is in CT emission, first header is sent, and not in inter-frame header window.
  assign ce_fifo_rdy = tx_tready & st_ct_emission & ce_first_header_sent & ~ce_stalling;

  // =========================================================================================== //
  // Frame-level gating :
  // =========================================================================================== //
  // Track FIFO fill level to know when enough payload data is available for a frame.
  // This prevents starting a frame before the FIFO can sustain continuous tvalid.
  logic [CE_FRAME_CNT_W-1:0] ce_frame_threshold;
  logic                      ce_frame_comparator;

  // When header is pending, look ahead one frame (+1) to pick the correct threshold
  assign ce_frame_threshold = ((ce_seq_num + ce_header_pending) >= NB_PACKETS_FULL) ? CE_FRAME_CNT_W'(NB_WORDS_LAST_PACKET) : CE_FRAME_CNT_W'(NB_WORDS_PAYLOAD);
  assign ce_frame_comparator = (ce_frame_cnt >= ce_frame_threshold);

  // During stalling, tracks threshold combinationally so ce_frame_ready is already correct when stalling clears (no reassertion latency).
  // Outside stalling, toggles high only if ce_frame_ready was 0 and comparison valid.
  // Clears only on ciphertext_sent.
  // Note that when ce_fifo_out_rdy drops for any reason, tx stalls
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ce_frame_ready <= 1'b0;
    end else begin
      if (ciphertext_sent) begin
        ce_frame_ready <= 1'b0;
      end else if (ce_stalling) begin
        ce_frame_ready <= ce_frame_comparator;
      end else if (~ce_frame_ready & ce_frame_comparator) begin
        ce_frame_ready <= 1'b1;
      end
    end
  end

  // =========================================================================================== //
  // AXI4-stream
  // =========================================================================================== //
  assign tx_tdata_D      = (small_packet | ce_header_valid) ? tx_header : ce_fifo_out_data;
  assign tx_tvalid_D     = small_packet ? (|tx_cnt) : ((|tx_cnt) & (ce_header_valid | ce_fifo_out_vld));
  assign tx_tkeep_user_D = {3'b000, tx_byte_enable};
  assign tx_tlast_D      = small_packet ? tx_small_last : (st_ct_emission ? tx_last_word : 1'b0);

  logic fifo_qsfp_tlast;

  fifo_element #(
    .WIDTH          (MRMAC_AXIS_W+MRMAC_TKEEP_W+1),
    .DEPTH          (2),
    .TYPE_ARRAY     ({4'h1,4'h2}),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) fifo_element_qsfp (
    .clk     (clk_mhdma   ),
    .s_rst_n (resetn_mhdma),

    .in_data ({mhdma_pkg::byte_swap(tx_tdata_D), tx_tkeep_user_D, tx_tlast_D}),
    .in_vld  (tx_tvalid_D),
    .in_rdy  (tx_tready),

    .out_data({qsfp_tx_tdata, qsfp_tx_tkeep_user, fifo_qsfp_tlast}),
    .out_vld (qsfp_tx_tvalid),
    .out_rdy (qsfp_tx_tready)
  );

  // Gate stale tlast: fifo_element retains out_data when empty, so tlast
  // can remain high after the last word has been consumed.
  assign qsfp_tx_tlast = fifo_qsfp_tlast & qsfp_tx_tvalid;

  // =========================================================================================== //
  // Completion signals : pulse when the last word of a specific packet type is sent
  // =========================================================================================== //
  always_ff @(posedge clk_mhdma) begin
    notify_ack_sent   <= st_notify_ack     & tx_tlast_D;
    notify_sent       <= st_notify_request & tx_tlast_D;
    read_request_sent <= st_read_request   & tx_tlast_D;
    ciphertext_sent   <= st_ct_emission    & tx_tlast_D & (ce_seq_num == NB_PACKETS_FULL);
  end

  // =========================================================================================== //
  // Errors
  // =========================================================================================== //
  // Detect tvalid gap during payload transmission (MRMAC TX underrun)
  logic payload_active;

  assign payload_active = st_ct_emission & ce_first_header_sent & ~ce_stalling & |tx_cnt;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      format_error.formatter_error <= 1'b0;
    end else begin
      if (rst_errors) begin
        format_error.formatter_error <= 1'b0;
      end else if (payload_active & ~ce_fifo_out_vld & tx_tready) begin
        format_error.formatter_error <= 1'b1;
      end
    end
  end

  // =========================================================================================== //
  // Statistics
  // =========================================================================================== //
  assign stat.fsm_formatter = tx_state;

  // TX packet counters
  localparam int NUM_FMT_STAT_CNTS = 4;
  logic [NUM_FMT_STAT_CNTS-1:0][REG_DATA_W-1:0] fmt_stat_cnt;
  logic [NUM_FMT_STAT_CNTS-1:0]                 fmt_stat_cnt_inc;
  logic [NUM_FMT_STAT_CNTS-1:0]                 fmt_stat_cnt_rst;

  assign fmt_stat_cnt_inc = {read_request_sent, notify_sent, notify_ack_sent, ciphertext_sent};
  assign fmt_stat_cnt_rst = {stat_rst.cnt_read_req_sent, stat_rst.cnt_notify_sent, stat_rst.cnt_notify_ack_sent, stat_rst.cnt_ce_sent};

  for (genvar gen_i = 0; gen_i < NUM_FMT_STAT_CNTS; gen_i++) begin : gen_fmt_stat_cnt
    always_ff @(posedge clk_mhdma) begin
      if (~resetn_mhdma)                  fmt_stat_cnt[gen_i] <= 'h0;
      else if (fmt_stat_cnt_rst[gen_i])   fmt_stat_cnt[gen_i] <= 'h0;
      else if (fmt_stat_cnt_inc[gen_i])   fmt_stat_cnt[gen_i] <= fmt_stat_cnt[gen_i] + 1;
    end
  end

  assign stat.cnt_ce_sent         = fmt_stat_cnt[0];
  assign stat.cnt_notify_ack_sent = fmt_stat_cnt[1];
  assign stat.cnt_notify_sent     = fmt_stat_cnt[2];
  assign stat.cnt_read_req_sent   = fmt_stat_cnt[3];

endmodule
