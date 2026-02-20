// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA formatter or TX module for QSFP lane
// ==============================================================================================

module mhdma_formatter
  import mhdma_pkg::*;          // multi-hpu-dma
  import axi_if_eth_axi_pkg::*; // AXI4
(
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                      clk_mrmac,
  input  logic                                      resetn_mrmac,
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

  input  logic                                      ce_reception_ready,

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
  output formatter_stat_t                           stat
);

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

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      hpu_mac_table_tmp <= 'h0;
    end else begin
      hpu_mac_table_tmp <= hpu_mac_table;
    end
  end

  // =========================================================================================== //
  // Ciphertext Emission FIFO
  // =========================================================================================== //
  logic                    ce_fifo_rdy;
  logic                    ce_fifo_vld;
  logic                    ce_frame_ready;

  logic [MRMAC_AXIS_W-1:0] ce_fifo_out_data;
  logic                    ce_fifo_out_vld;
  logic                    ce_fifo_out_rdy;

  // Frame-level buffering: accumulate enough payload words before allowing
  // consumption, to guarantee no tvalid gap mid-frame (MRMAC drops frames on gap)
  fifo_ram_rdy_vld # (
    .WIDTH       (MRMAC_AXIS_W    ),
    .DEPTH       (NB_WORDS_PAYLOAD),
    .RAM_LATENCY (CE_RAM_LATENCY  ),
    .ALMOST_FULL_REMAIN (0)
  ) fifo_ce (
    .clk         (clk_mrmac   ),
    .s_rst_n     (resetn_mrmac),

    .in_data     (ce_payload),
    .in_vld      (ce_vld),
    .in_rdy      (ce_rdy),

    .out_data    (ce_fifo_out_data),
    .out_vld     (ce_fifo_out_vld),
    .out_rdy     (ce_fifo_out_rdy),

    .almost_full (/* UNUSED */)
  );

  assign ce_fifo_out_rdy = ce_fifo_rdy & ce_frame_ready;

  // Gate FIFO output: downstream only sees valid data when a full frame is buffered
  assign ce_fifo_vld = ce_fifo_out_vld & ce_frame_ready;

  // counting if there is enough words into fifo to continue
  logic [CE_FRAME_CNT_W-1:0] ce_frame_cnt;
  logic                       ce_fifo_up;
  logic                       ce_fifo_down;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
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
    ST_NOTIFY_ACK        = 3'b010,
    ST_READ_REQ    = 3'b011,
    ST_NOTIFY      = 3'b100
  } st_tx;

  st_tx tx_state;
  st_tx tx_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) tx_state <= ST_IDLE;
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
  assign read_request_pending   = master_command_vld & (master_command.req_id == REQ_ID_READ) & ce_reception_ready;
  assign notify_request_pending = master_command_vld & (master_command.req_id == REQ_ID_NOTIFY);

  // ----------------------------------------------------------------------------------------------
  // Building ready sink from FSM : consume one and only data when we are in a specific state
  logic st_ct_emissionQ;
  logic st_notify_ackQ;
  logic st_read_requestQ;
  logic st_notify_requestQ;

  always_ff @(posedge clk_mrmac) begin
    st_ct_emissionQ    <= st_ct_emission;
    st_notify_ackQ     <= st_notify_ack;
    st_read_requestQ   <= st_read_request;
    st_notify_requestQ <= st_notify_request;
  end

  assign consume_ct_emission  = st_ct_emission & ~st_ct_emissionQ;
  assign consume_notify_ack   = st_notify_ack & ~st_notify_ackQ;
  assign consume_read_request = st_read_request & ~st_read_requestQ;
  assign consume_notify       = st_notify_request & ~st_notify_requestQ;

  assign slave_command_rdy = consume_ct_emission | consume_notify_ack;
  assign master_command_rdy = consume_notify | consume_read_request;

  // =========================================================================================== //
  // Building headers
  // =========================================================================================== //
  // control --------------------------------------------------------------------------------------
  // we are sending a request on qsfp lane when we have a pulse on header start-of-packet
  // deasserting this request when we hit enough words on the counter
  logic header_sop;                    // pulse
  // to simplify notations we define each cases as :
  logic stop_sending_small_packet;     // notify / notify-ack / read-request
  logic stop_sending_ce_full_frame;    // ciphertext-emission: when we send ETH_NB_BYTES_PAYLOAD
  logic stop_sending_ce_partial_frame; // ciphertext-emission: when we send LAST_PACKET_BYTE_SIZE
  logic end_of_packet;                 // pulse of all stop signals
  logic okay_to_send_request;          // level between start of / end of packet
  logic small_packet;                  // level of a small packet (notify & ack + read request)

  logic tx_header_last; // last header word
  logic tx_small_last;  // last word of a small packet
  logic tx_last_word;   // pulse on last word

  // input of axi4stream temp register
  logic                      tx_tlast_D;
  logic [  MRMAC_AXIS_W-1:0] tx_tdata_D;
  logic [ MRMAC_TKEEP_W-1:0] tx_tkeep_user_D;
  logic                      tx_tvalid_D;

  logic [$clog2(NB_WORDS_MAX)+1:0] tx_cnt;
  logic [        MRMAC_AXIS_W-1:0] tx_header;
  logic                            ce_header_valid;
  // ce -------------------------------------------------------------------------------------------
  // During CE we need to increment seq_num for each packet sent
  // For the arbiter we need the information to release the fsm that all have been sent
  logic [SEQ_NUM_W-1:0] ce_seq_num;
  // we need to build header and stall ciphertext arrival until we are ready
  logic                 ce_first_header;      // level: up for first packet header (used for tx & backpressure)
  logic                 ce_first_header_sent; // level: up when first packet header has been sent
  logic                 ce_last_packet;       // level: up when last packet is transmitting
  logic                 ce_end_of_packet;     // pulse: last word of last packet
  logic                 ce_start_of_header;   // pulse: header transmission for all packets
  logic                 ce_start_emission;    // pulse: start of first header transmission
  logic                 ce_sop_header;        // pulse: start-of headers between packets

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      small_packet <= 1'b0;
    end else begin
      small_packet <= st_read_request | st_notify_request | st_notify_ack;
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      tx_cnt <= 'h0;
    end else begin
      if (okay_to_send_request & ~end_of_packet & qsfp_tx_tready) begin
        if (st_ct_emission) begin
          if (ce_header_valid | (ce_fifo_out_rdy & ce_fifo_vld)) begin
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

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      okay_to_send_request <= 1'b0;
    end else begin
      if (header_sop) begin
        okay_to_send_request <= 1'b1;
      end else if (end_of_packet) begin
        okay_to_send_request <= 1'b0;
      end
    end
  end

  // we have to trigger signal one cycle earlier to have okay_to_send_request on time
  assign stop_sending_small_packet     = qsfp_tx_tready & (tx_cnt == NB_WORDS_MIN)     & small_packet;
  assign stop_sending_ce_full_frame    = qsfp_tx_tready & (tx_cnt == NB_WORDS_FULL)    & st_ct_emission;
  assign stop_sending_ce_partial_frame = qsfp_tx_tready & (tx_cnt == NB_WORDS_PARTIAL) & ce_last_packet;

  assign end_of_packet = stop_sending_small_packet | stop_sending_ce_full_frame | stop_sending_ce_partial_frame;

  assign tx_small_last  = qsfp_tx_tready & (tx_cnt == NB_WORDS_MIN);
  assign tx_header_last = qsfp_tx_tready & (tx_cnt == NB_WORDS_CUST_HEADER_SIZE);
  assign tx_last_word   = qsfp_tx_tready & st_ct_emission & (ce_last_packet ? (tx_cnt == NB_WORDS_PARTIAL) : (tx_cnt == NB_WORDS_FULL));

  assign header_sop = (master_command_rdy & master_command_vld) | (slave_command_rdy & slave_command_vld) | ce_start_of_header;

  // =========================================================================================== //
  // Ciphertext Emission (CE)
  // =========================================================================================== //
  assign ce_start_of_header = ce_start_emission | ce_sop_header;

  // this signal must be reset, it is linked to FSM changing state
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_last_packet <= 1'b0;
    end else begin
      if (qsfp_tx_tready & st_ct_emission & (ce_seq_num == NB_PACKETS_FULL) & ~tx_tlast_D) begin
        ce_last_packet <= 1'b1;
      end else if (tx_tlast_D) begin
        ce_last_packet <= 1'b0;
      end
    end
  end
  assign ce_end_of_packet = ce_last_packet & tx_tlast_D;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_first_header <= 1'b0;
    end else begin
      if (tx_header_last) begin
        ce_first_header <= 1'b0;
      end else if (ce_start_emission) begin
        ce_first_header <= 1'b1;
      end
    end
  end

  // decoding header payload --------------------------------------------------
  // header is propagated well before we receive any data on fifo tx
  command_t              ce_header_payload_tmp;
  logic [DST_ADDR_W-1:0] ce_dst_addr;
  logic [SRC_ADDR_W-1:0] ce_src_addr;
  logic [    RSVD_W-1:0] ce_rsvd;
  logic [    FLAG_W-1:0] ce_flag;
  logic [    MODE_W-1:0] ce_mode;
  logic [  HPU_ID_W-1:0] ce_hpu_id;
  logic [  IOP_ID_W-1:0] ce_iop_id;

  always_ff @(posedge clk_mrmac)
    if (slave_command_rdy & slave_command_vld)
      ce_header_payload_tmp <= slave_command;

  assign ce_iop_id       = ce_header_payload_tmp.iop_id;
  assign ce_hpu_id       = ce_header_payload_tmp.hpu_id;
  assign ce_rsvd         = ce_header_payload_tmp.rsvd;
  assign ce_flag         = ce_header_payload_tmp.flag;
  assign ce_mode         = ce_header_payload_tmp.mode;
  assign ce_dst_addr     = ce_header_payload_tmp.dst_addr;
  assign ce_src_addr     = ce_header_payload_tmp.src_addr;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_seq_num <= 'h0;
    end else begin
      if (ce_sop_header) begin
        ce_seq_num <= ce_seq_num+1;
      end else if (ce_end_of_packet) begin
        ce_seq_num <= 'h0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_first_header_sent <= 1'b0;
    end else begin
      if (ce_first_header & tx_header_last) begin
        ce_first_header_sent <= 1'b1;
      end else if (ce_end_of_packet) begin
        ce_first_header_sent <= 1'b0;
      end
    end
  end

  assign ce_start_emission = qsfp_tx_tready & st_ct_emission & (ce_seq_num == 0) & ce_fifo_vld & ~ce_first_header_sent;

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
  always_ff @(posedge clk_mrmac) begin : prc_header_gen
    if (~resetn_mrmac) begin
      header_target_hpu_mac_addr <= 'h0;
      header_req_id              <= 'h0;
      header_src_addr            <= 'h0;
      header_dst_addr            <= 'h0;
      header_iop_id              <= 'h0;
      header_rsvd                <= 'h0;
      header_flag                <= 'h0;
      header_mode                <= 'h0;
    end else begin
      if (master_command_rdy & master_command_vld) begin
        header_target_hpu_mac_addr <= hpu_mac_table_tmp[master_command.hpu_id];
        header_req_id              <= master_command.req_id;
        header_src_addr            <= master_command.src_addr;
        header_dst_addr            <= master_command.dst_addr;
        header_iop_id              <= master_command.iop_id;
        header_rsvd                <= master_command.rsvd;
        header_flag                <= master_command.flag;
        header_mode                <= master_command.mode;
      end else if (slave_command_rdy & slave_command_vld) begin
        header_target_hpu_mac_addr <= hpu_mac_table_tmp[slave_command.hpu_id];
        header_req_id              <= slave_command.req_id;
        header_src_addr            <= slave_command.src_addr;
        header_dst_addr            <= slave_command.dst_addr;
        header_iop_id              <= slave_command.iop_id;
        header_rsvd                <= slave_command.rsvd;
        header_flag                <= slave_command.flag;
        header_mode                <= slave_command.mode;
      end else if (ce_fifo_vld & st_ct_emission) begin
        header_target_hpu_mac_addr <= hpu_mac_table_tmp[ce_hpu_id];
        header_req_id              <= REQ_ID_EMISSION;
        header_src_addr            <= ce_src_addr;
        header_dst_addr            <= ce_dst_addr;
        header_iop_id              <= ce_iop_id;
        header_rsvd                <= ce_rsvd;
        header_flag                <= ce_flag;
        header_mode                <= ce_mode;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin : prc_header_ethernet_len
    if (small_packet) begin
      header_eth_len <= ETH_LEN_MIN;
    end else if (ce_last_packet) begin
      header_eth_len <= ETH_LEN_LAST_PKT;
    end else begin
      header_eth_len <= ETH_LEN_MAX;
    end
  end

  always_ff @(posedge clk_mrmac) begin : prc_header_ce
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
  logic [$clog2(MRMAC_AXIS_W/8)-1:0] last_word_bytes;
  logic [      MRMAC_AXIS_W/8-1:0]   tx_byte_enable;
  logic [      MRMAC_AXIS_W/8-1:0]   tx_byte_enable_d;

  assign tx_byte_enable_d = (last_word_bytes == 0) ? 8'hFF : (1 << last_word_bytes) - 1;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      tx_byte_enable <= 8'h00;
    end else begin
      if (okay_to_send_request & qsfp_tx_tready) begin
        if ((tx_cnt == 0) | ~small_packet)
          tx_byte_enable <= 8'hFF;
        else if (small_packet && (tx_cnt == (NB_WORDS_MIN-1)) )
          tx_byte_enable <= tx_byte_enable_d;
        else if (tx_tlast_D)
          tx_byte_enable <= 8'h00;
      end
    end
  end

  assign last_word_bytes = (ETH_NB_BYTES_HEADER + header_eth_len) & {$clog2(MRMAC_AXIS_W/8){1'b1}};

  // =========================================================================================== //
  // Building packets
  // =========================================================================================== //
  // Ciphertext emission --------------------------------------------------------------------------
  // While receiving data, we must stall the coefficients arrival after NB_WORDS_PAYLOAD words
  // We know that we want to send ETH_NB_BYTES_PAYLOAD bytes per payload
  // We should send NB_PACKETS_FULL packets and last one is of size LAST_PACKET_BYTE_SIZE
  // LAST_PACKET_BYTE_SIZE must be greater than minimum (ETH_NB_BYTES_MIN=64)

  // we need to stall words coming from ciphertext emission to build headers
  logic ce_stalling; // level: up when we need to send header between packets

  // we should stall the emission of coefficients after we have to correct number of words
  // we should un-stall when header has left
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_stalling <= 1'b0;
    end else begin
      if (qsfp_tx_tready & (tx_cnt == NB_WORDS_FULL)) begin
        ce_stalling <= 1'b1;
      end else if (tx_header_last) begin
        ce_stalling <= 1'b0;
      end
    end
  end

  // edge detection on ce_stalling (used to set pending flag)
  logic ce_stalling_tmp;
  always_ff @(posedge clk_mrmac)
    ce_stalling_tmp <= ce_stalling;

  // inter-frame header pending flag: converts edge into level that waits for CE FIFO ready
  logic ce_header_pending;
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
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

  // backpressure over ciphertext coefficients
  // active
  //    - when we are in the correct state &
  //    - when the first header is not starting to be propagated &
  //    - qsfp tx is ready &
  //    - we don't need to stall between packets for sending headers
  assign ce_fifo_rdy = qsfp_tx_tready & st_ct_emission & ce_first_header_sent & ~ce_stalling;

  // =========================================================================================== //
  // Frame-level gating :
  // =========================================================================================== //
  // Track FIFO fill level to know when enough payload data is available for a frame.
  // This prevents starting a frame before the FIFO can sustain continuous tvalid.
  logic [CE_FRAME_CNT_W-1:0] ce_frame_threshold;

  // When header is pending, look ahead one frame (+1) to pick the correct threshold
  assign ce_frame_threshold = ((ce_seq_num + ce_header_pending) >= NB_PACKETS_FULL)
      ? CE_FRAME_CNT_W'(NB_WORDS_LAST_PACKET)
      : CE_FRAME_CNT_W'(NB_WORDS_PAYLOAD);

  // During stalling, tracks threshold combinationally so ce_frame_ready
  // is already correct when stalling clears (no reassertion latency).
  // Outside stalling, latches high to prevent mid-frame tvalid drop.
  // Clears only on ciphertext_sent.
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_frame_ready <= 1'b0;
    end else begin
      if (ciphertext_sent) begin
        ce_frame_ready <= 1'b0;
      end else if (ce_stalling) begin
        ce_frame_ready <= (ce_frame_cnt >= ce_frame_threshold);
      end else if (~ce_frame_ready & (ce_frame_cnt >= ce_frame_threshold)) begin
        ce_frame_ready <= 1'b1;
      end
    end
  end

  // =========================================================================================== //
  // AXI4-stream
  // =========================================================================================== //
  // before sending anything to MRMAC we register it
  logic [  MRMAC_AXIS_W-1:0] tx_tdata_reg;
  logic [ MRMAC_TKEEP_W-1:0] tx_tkeep_user_reg;
  logic                      tx_tlast_reg;
  logic                      tx_tvalid_reg;

  assign tx_tdata_D      = small_packet | ce_header_valid ? tx_header : ce_fifo_vld ? ce_fifo_out_data : 'h0;
  assign tx_tvalid_D     = small_packet ? |tx_cnt : |tx_cnt & (ce_header_valid | ce_fifo_vld);
  assign tx_tkeep_user_D = {3'b000, tx_byte_enable};
  assign tx_tlast_D      = small_packet ? tx_small_last : st_ct_emission ? tx_last_word : 1'b0;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      tx_tdata_reg <= 'h0;
      tx_tvalid_reg <= 'h0;
      tx_tkeep_user_reg <= 'h0;
      tx_tlast_reg <= 'h0;
    end else if (qsfp_tx_tready) begin
      tx_tdata_reg      <= mhdma_pkg::byte_swap(tx_tdata_D);
      tx_tvalid_reg     <= tx_tvalid_D;
      tx_tkeep_user_reg <= tx_tkeep_user_D;
      tx_tlast_reg      <= tx_tlast_D;
    end
  end

  assign qsfp_tx_tdata      = tx_tdata_reg;
  assign qsfp_tx_tvalid     = tx_tvalid_reg;
  assign qsfp_tx_tkeep_user = tx_tkeep_user_reg;
  assign qsfp_tx_tlast      = tx_tlast_reg;

  // =========================================================================================== //
  // FSM backpressure : confirming that a specific packet has been sent
  // =========================================================================================== //
  assign notify_ack_sent   = st_notify_ack     & tx_tlast_D;
  assign notify_sent       = st_notify_request & tx_tlast_D;
  assign read_request_sent = st_read_request   & tx_tlast_D;
  assign ciphertext_sent   = st_ct_emission    & tx_tlast_D & (ce_seq_num == NB_PACKETS_FULL);

  // =========================================================================================== //
  // Errors
  // =========================================================================================== //
  // Detect tvalid gap during payload transmission (MRMAC TX underrun)
  logic payload_active;
  assign payload_active = st_ct_emission & ce_first_header_sent & ~ce_stalling & |tx_cnt;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac ) begin
      format_error.formatter_error <= 1'b0;
    end else begin
      if (rst_errors) begin
        format_error.formatter_error <= 1'b0;
      end else if (payload_active & ~ce_fifo_vld & qsfp_tx_tready) begin
        format_error.formatter_error <= 1'b1;
      end
    end
  end

  // =========================================================================================== //
  // Statistics
  // =========================================================================================== //
  assign stat.fsm_formatter = tx_state;

endmodule
