// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA Master module
// ----------------------------------------------------------------------------------------------
// Receives requests from RPU and address them
//
// This module must be able to send Notify and Read Request to formatter
//
//
// Read request retry can happen when
// 1) a timeout occurs
// 2) an incorrect seq num happens: we fill the memory with zeros and ask for a new read request
// ==============================================================================================

module mhdma_master
  import mhdma_pkg::*;               // for all mhdma modules
  import axi_if_eth_axi_pkg::*;      // AXI4
  import axi_if_shell_axil_pkg::*;   // REG_DATA_W
  import axi_if_common_param_pkg::*; // HBM page
  import pem_common_param_pkg::*;    // CT_MEM_BYTES, AXI4_WORD_PER_PC_L*
#(
  parameter int CDC_SYNC_STAGES = 2
) (
  // Ethernet configuration interface -----------------------------------------
  input  logic                                clk_cfg,
  input  logic                                resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                clk_mrmac,
  input  logic                                resetn_mrmac,
  // Axi4 interface for NMU ---------------------------------------------------
  output logic [ETH_PC-1:0][AXI4_ID_W-1:0]    m_axi4_awid,
  output logic [ETH_PC-1:0][AXI4_ADD_W-1:0]   m_axi4_awaddr,
  output logic [ETH_PC-1:0][AXI4_LEN_W-1:0]   m_axi4_awlen,
  output logic [ETH_PC-1:0][AXI4_SIZE_W-1:0]  m_axi4_awsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0] m_axi4_awburst,
  output logic [ETH_PC-1:0]                   m_axi4_awvalid,
  input  logic [ETH_PC-1:0]                   m_axi4_awready,

  output logic [ETH_PC-1:0][AXI4_DATA_W-1:0]  m_axi4_wdata,
  output logic [ETH_PC-1:0][AXI4_STRB_W-1:0]  m_axi4_wstrb,
  output logic [ETH_PC-1:0]                   m_axi4_wlast,
  output logic [ETH_PC-1:0]                   m_axi4_wvalid,
  input  logic [ETH_PC-1:0]                   m_axi4_wready,

  input  logic [ETH_PC-1:0][AXI4_ID_W-1:0]    m_axi4_bid,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]  m_axi4_bresp,
  input  logic [ETH_PC-1:0]                   m_axi4_bvalid,
  output logic [ETH_PC-1:0]                   m_axi4_bready,
  // regf interface -----------------------------------------------------------
  input  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr,
  input  logic               [REG_DATA_W-1:0] regf_req_id,
  input  logic               [REG_DATA_W-1:0] regf_req_addr,
  output logic               [REG_DATA_W-1:0] regf_read_payload,
  input  logic               [REG_DATA_W-1:0] regf_timeout_duration_notify,
  input  logic               [REG_DATA_W-1:0] regf_timeout_duration_read_req,
  // register control
  input  logic                                received_req,
  output logic                                request_consumed,
  // interrupt ---------------------------------------------------------------
  input  logic                                clear_interrupt_rr,
  output logic                                interrupt_read_request,
  // decoder interface --------------------------------------------------------
  input  command_t                            decoded_command,
  input  logic                                decoded_command_vld,
  output logic                                decoded_command_rdy,

  input  logic             [MRMAC_AXIS_W-1:0] decoder_rx_tdata,
  input  logic                                decoder_rx_tvalid,

  input  logic                                notify_ack_received,
  // formatter interface ------------------------------------------------------
  output command_t                            master_command,
  output logic                                master_command_vld,
  input  logic                                master_command_rdy,

  input  logic                                read_request_sent,
  input  logic                                notify_sent,

  output logic                                ce_reception_ready,
  // Error interface ----------------------------------------------------------
  output master_error_t                       master_error,
  input  logic                                rst_errors,
  // statistics ---------------------------------------------------------------
  output master_stat_t                        stat,
  input  master_stat_rst_t                    stat_rst
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int NB_WORDS_TOTAL  = AXI4_WORD_PER_PC0 + (ETH_PC-1) * AXI4_WORD_PER_PC;
  localparam int NB_WORDS_TO_HBM = (NB_WORDS_TOTAL*AXI4_DATA_W)/MRMAC_AXIS_W;

  // Max burst count per PC for page boundary crossings
  localparam int AXI_BURST_NB_MAX    = ((AXI4_WORD_PER_PC0 + PAGE_AXI4_DATA-1) / PAGE_AXI4_DATA) + 1; // +1 in case of address non alignment
  localparam int AXI_BURST_NB_MAX_W  = $clog2(AXI_BURST_NB_MAX) == 0 ? 1 : $clog2(AXI_BURST_NB_MAX);
  localparam int AXI_BURST_NB_MAX_WW = $clog2(AXI_BURST_NB_MAX+1) == 0 ? 1 : $clog2(AXI_BURST_NB_MAX+1);

  // ==============================================================================================
  // FSM
  // ==============================================================================================
  logic timeout_reached_notify;

  // Notify TX (NTX) ------------------------------------------------------------------------------
  typedef enum logic [1:0] {
    NTX_XXX          = 'x,
    NTX_WAIT_REQUEST = 2'b00,
    NTX_WAIT_ACK     = 2'b01,
    NTX_SEND_NOTIFY  = 2'b10
  } st_ntx;

  st_ntx ntx_state;
  st_ntx ntx_next_state;

  logic start_notify_request;
  logic st_ntx_wait_request;
  logic ntx_retry;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) ntx_state <= NTX_WAIT_REQUEST;
    else ntx_state <= ntx_next_state;
  end

  always_comb begin
    ntx_next_state = NTX_XXX;
    case (ntx_state)
      NTX_WAIT_REQUEST:
        ntx_next_state = start_notify_request ? NTX_SEND_NOTIFY : NTX_WAIT_REQUEST;
      NTX_SEND_NOTIFY:
        ntx_next_state = notify_sent ? NTX_WAIT_ACK : NTX_SEND_NOTIFY;
      NTX_WAIT_ACK:
        // (Assumption) transmission is not instantaneous, notify_ack_received cannot arrive before axis tlast
        ntx_next_state = notify_ack_received ? NTX_WAIT_REQUEST : timeout_reached_notify ? NTX_SEND_NOTIFY : NTX_WAIT_ACK;
    endcase
  end

  assign st_ntx_wait_request = (ntx_state==NTX_WAIT_REQUEST);

  // Read request ---------------------------------------------------------------------------------
  logic start_read_request;
  logic ciphertext_received;
  logic valid_ciphertext_received;
  logic rr_retry;

  typedef enum logic [1:0] {
    RR_XXX          = 'x,
    RR_WAIT_REQUEST = 2'b00,
    RR_SEND_REQUEST = 2'b01,
    RR_WAIT_PACKETS = 2'b10
  } st_read_req;

  st_read_req rreq_state;
  st_read_req rreq_next_state;

  logic st_wait_packets;
  logic st_rr_wait_request;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) rreq_state <= RR_WAIT_REQUEST;
    else rreq_state <= rreq_next_state;
  end

  always_comb begin
    rreq_next_state = RR_XXX;
    case (rreq_state)
      RR_WAIT_REQUEST:
        rreq_next_state = start_read_request ? RR_SEND_REQUEST : RR_WAIT_REQUEST;
      RR_SEND_REQUEST:
        rreq_next_state =  read_request_sent ? RR_WAIT_PACKETS : RR_SEND_REQUEST;
      RR_WAIT_PACKETS:
        rreq_next_state = rr_retry ? RR_SEND_REQUEST : valid_ciphertext_received ? RR_WAIT_REQUEST : RR_WAIT_PACKETS;
    endcase
  end

  assign st_wait_packets    = (rreq_state == RR_WAIT_PACKETS);
  assign st_rr_wait_request = (rreq_state == RR_WAIT_REQUEST);

  // =========================================================================================== //
  // Consuming decoded commands
  // =========================================================================================== //
  logic nack_rdy;
  logic rr_packets_rdy;

  always_ff @(posedge clk_mrmac)
    nack_rdy <= decoded_command_vld & (decoded_command.req_id == REQ_ID_NOTIFY_ACK) & st_ntx_wait_request;

  always_ff @(posedge clk_mrmac)
    rr_packets_rdy <= decoded_command_vld & (decoded_command.req_id == REQ_ID_EMISSION) & st_wait_packets;

  assign decoded_command_rdy = nack_rdy | rr_packets_rdy;

  // =========================================================================================== //
  // Retry
  // =========================================================================================== //

  // notify ---------------------------------------------------------------------------------------
  always_ff @(posedge clk_mrmac) begin
      if (~resetn_mrmac) begin
        ntx_retry <= 1'b0;
      end else begin
        if (timeout_reached_notify) begin
          ntx_retry <= 1'b1;
        end else if (master_command_rdy & (master_command.req_id == REQ_ID_NOTIFY)) begin
          ntx_retry <= 1'b0;
        end
      end
  end

  // read requets ---------------------------------------------------------------------------------
  logic mismatch_retry_pending;
  logic timeout_reached_read_request;
  logic retry_seq_num;
  logic seq_num_mismatch;
  logic wait_for_seq0;

  assign valid_ciphertext_received = ciphertext_received & ~mismatch_retry_pending;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rr_retry <= 1'b0;
    end else begin
      if (timeout_reached_read_request | retry_seq_num) begin
        rr_retry <= 1'b1;
      end else if (master_command_rdy & (master_command.req_id == REQ_ID_READ)) begin
        rr_retry <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      mismatch_retry_pending <= 1'b0;
    end else begin
      if (seq_num_mismatch) begin
        mismatch_retry_pending <= 1'b1;
      end else if (ciphertext_received) begin
        mismatch_retry_pending <= 1'b0;
      end
    end
  end

  assign retry_seq_num = mismatch_retry_pending & ciphertext_received;

  // Seq num mismatch decoding
  logic [SEQ_NUM_W-1:0] expected_seq_num;
  logic                 seq_num_valid;
  logic                 rr_packets_rdyQ;
  logic                 seq0_detected;

  assign seq0_detected = rr_packets_rdy & (decoded_command.seq_num == 0);

  always_ff @(posedge clk_mrmac)
    rr_packets_rdyQ <= rr_packets_rdy;

  // seq num valid over frontedge of rr_packets_rdy & there is no seq num errors
  assign seq_num_valid = (rr_packets_rdy & ~rr_packets_rdyQ) & (~wait_for_seq0 | seq0_detected);

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      expected_seq_num <= 'h0;
    end else begin
      if (start_read_request)
        expected_seq_num <= 'h0;
      else if (seq_num_valid) begin
        expected_seq_num <= expected_seq_num + 1;
      end
    end
  end

  // After mismatch retry, ignore all CE emissions until one arrives with seq_num == 0
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      wait_for_seq0 <= 1'b0;
    end else begin
      if (retry_seq_num) begin
        wait_for_seq0 <= 1'b1;
      end else if (seq0_detected) begin
        wait_for_seq0 <= 1'b0;
      end
    end
  end

  // Any seq_num != expected is a mismatch: drop remaining packets, zero-pad, retry
  assign seq_num_mismatch = seq_num_valid & (decoded_command.seq_num != expected_seq_num);

  // =========================================================================================== //
  // Timeouts
  // =========================================================================================== //
  logic [REG_DATA_W-1:0] to_dur_read_req;
  logic [REG_DATA_W-1:0] to_dur_notify;

  always_ff @(posedge clk_mrmac)
    to_dur_read_req <= regf_timeout_duration_read_req;

  always_ff @(posedge clk_mrmac)
    to_dur_notify <= regf_timeout_duration_notify;

  // timeout --------------------------------------------------------------------------------------
  logic [REG_DATA_W-1:0] to_notify_cnt;

  always_ff @(posedge clk_mrmac) begin : timeout_counter
    if (~resetn_mrmac) begin
      to_notify_cnt <= 'h0;
    end else begin
      if ((ntx_state == NTX_WAIT_ACK)) begin
        to_notify_cnt <= to_notify_cnt + 1;
      end else begin
        to_notify_cnt <= 'h0;
      end
    end
  end

  assign timeout_reached_notify = (to_notify_cnt == to_dur_notify);

  // timeout read request -------------------------------------------------------------------------
  logic [REG_DATA_W-1:0] to_read_request_cnt;

  always_ff @(posedge clk_mrmac) begin : timeout_counter_rr
    if (~resetn_mrmac) begin
      to_read_request_cnt <= 'h0;
    end else begin
      if ((rreq_state == RR_WAIT_PACKETS)) begin
        if (mismatch_retry_pending) begin
          to_read_request_cnt <= 'h0;
        end else begin
          to_read_request_cnt <= to_read_request_cnt + 1;
        end
      end else begin
        to_read_request_cnt <= 'h0;
      end
    end
  end

  assign timeout_reached_read_request = (to_read_request_cnt == to_dur_read_req);

  // =========================================================================================== //
  // CDC from regf to mrmac clock
  // =========================================================================================== //
  // Read ReQuest Queue (RRQQ) --------------------------------------------------------------------
  // === CFG domain
  logic                    rrqq_in_rdy;
  logic                    rrqq_in_vld;
  logic [2*REG_DATA_W-1:0] rrqq_in_data;
  // tmp
  logic [2*REG_DATA_W-1:0] rrqq_data_kept;
  logic                    rrqq_data_kept_avail;
  logic                    rrqq_data_vld;

  // === MRMAC domain
  command_t rrqq_cmd;
  logic     rrqq_cmd_rdy;
  logic     rrqq_cmd_vld;

  assign rrqq_in_vld = received_req & (regf_req_id[23:20] == REQ_ID_READ);
  // backpressure
  always_ff @(posedge clk_cfg)
    if (~rrqq_in_rdy & rrqq_in_vld)
      rrqq_data_kept <= {regf_req_id, regf_req_addr};

  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      rrqq_data_kept_avail <= 1'b0;
    end else begin
      if (rrqq_in_vld & ~rrqq_in_rdy) begin
        rrqq_data_kept_avail <= 1'b1;
      end else if (rrqq_data_vld & rrqq_in_rdy) begin
        rrqq_data_kept_avail <= 1'b0;
      end
    end
  end

  assign rrqq_data_vld = rrqq_in_vld | rrqq_data_kept_avail;
  assign rrqq_in_data = (rrqq_in_rdy & rrqq_in_vld) ? {regf_req_id, regf_req_addr} : rrqq_data_kept;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak theses parameters in package
    .WIDTH           (2*REG_DATA_W),
    .DEPTH           (REQ_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(REQ_MEMORY_TYPE)
  ) rrqq_fifo_ram_rdy_vld_2clk (
    // CFG domain
    .in_clk      (clk_cfg),
    .in_rstn     (resetn_cfg),
    .in_data     (rrqq_in_data),
    .in_rdy      (rrqq_in_rdy),
    .in_vld      (rrqq_data_vld),
    .almost_full (/* UNUSED */),
    // MRMAC domain
    .out_clk     (clk_mrmac),
    .out_rstn    (resetn_mrmac),
    .out_data    ({rrqq_cmd.iop_id, rrqq_cmd.req_id, rrqq_cmd.hpu_id, rrqq_cmd.size_b, rrqq_cmd.dst_addr, rrqq_cmd.src_addr}),
    .out_rdy     (rrqq_cmd_rdy),
    .out_vld     (rrqq_cmd_vld)
  );

  assign start_read_request = master_command_rdy & (master_command.req_id == REQ_ID_READ);
  assign rrqq_cmd_rdy = start_read_request & st_rr_wait_request;

  // Notify ReQuest Queue (NRQQ) ------------------------------------------------------------------
  // === CFG domain
  logic                    nrqq_in_rdy;
  logic                    nrqq_in_vld;
  logic [2*REG_DATA_W-1:0] nrqq_in_data;
  // tmp
  logic [2*REG_DATA_W-1:0] nrqq_data_kept;
  logic                    nrqq_data_kept_avail;
  logic                    nrqq_data_vld;
  // === MRMAC domain
  command_t nrqq_cmd_data;
  logic     nrqq_cmd_rdy;
  logic     nrqq_cmd_vld;

  // @cfg clock ---------------------------------
  assign nrqq_in_vld = received_req & (regf_req_id[23:20] == REQ_ID_NOTIFY);

  // backpressure
  always_ff @(posedge clk_cfg)
    if (nrqq_in_vld & ~nrqq_in_rdy)
      nrqq_data_kept <= {regf_req_id, regf_req_addr};

  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      nrqq_data_kept_avail <= 1'b0;
    end else begin
      if (nrqq_in_vld & ~nrqq_in_rdy) begin
        nrqq_data_kept_avail <= 1'b1;
      end else if (nrqq_data_vld & nrqq_in_rdy) begin
        nrqq_data_kept_avail <= 1'b0;
      end
    end
  end

  assign nrqq_data_vld = nrqq_in_vld | nrqq_data_kept_avail;
  assign nrqq_in_data = (nrqq_in_rdy & nrqq_in_vld) ?  {regf_req_id, regf_req_addr} : nrqq_data_kept;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak theses parameters in package
    .WIDTH           (2*REG_DATA_W),
    .DEPTH           (REQ_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(REQ_MEMORY_TYPE)
  ) nrqq_fifo_ram_rdy_vld_2clk (
    // CFG domain
    .in_clk      (clk_cfg),
    .in_rstn     (resetn_cfg),
    .in_data     (nrqq_in_data),
    .in_rdy      (nrqq_in_rdy),
    .in_vld      (nrqq_data_vld),
    .almost_full (/* UNUSED */),
    //  MRMAC domain
    .out_clk     (clk_mrmac),
    .out_rstn    (resetn_mrmac),
    .out_data    ({nrqq_cmd_data.iop_id, nrqq_cmd_data.req_id, nrqq_cmd_data.hpu_id, nrqq_cmd_data.size_b, nrqq_cmd_data.dst_addr, nrqq_cmd_data.src_addr}),
    .out_rdy     (nrqq_cmd_rdy),
    .out_vld     (nrqq_cmd_vld)
  );

  logic     nrqq_retry_in_rdy;
  command_t nrqq_retry_data;
  logic     nrqq_retry_rdy;
  logic     nrqq_retry_vld;

  assign nrqq_cmd_rdy = (master_command_rdy & (master_command.req_id == REQ_ID_NOTIFY)) & ~ntx_retry & nrqq_retry_in_rdy;
  assign start_notify_request = nrqq_cmd_rdy;

  fifo_ram_rdy_vld # (
    .WIDTH             (IOP_ID_W + HPU_ID_W + SIZE_B_W +DST_ADDR_W + SRC_ADDR_W),
    .DEPTH             (REQ_FIFO_DEPTH),
    .RAM_LATENCY       (CE_RAM_LATENCY)
  ) nrqq_fifo_retries (
    .clk         (clk_mrmac   ),
    .s_rst_n     (resetn_mrmac),

    .in_data     ({nrqq_cmd_data.iop_id, nrqq_cmd_data.hpu_id, nrqq_cmd_data.size_b, nrqq_cmd_data.dst_addr, nrqq_cmd_data.src_addr}),
    .in_vld      (start_notify_request),
    .in_rdy      (nrqq_retry_in_rdy   ),

    .out_data    ({nrqq_retry_data.iop_id, nrqq_retry_data.hpu_id, nrqq_retry_data.size_b, nrqq_retry_data.dst_addr, nrqq_retry_data.src_addr}),
    .out_vld     (nrqq_retry_vld),
    .out_rdy     (nrqq_retry_rdy),

    .almost_full (/* UNUSED */)
  );

  assign nrqq_retry_rdy = notify_ack_received & (ntx_state == NTX_WAIT_ACK);

  // ----------------------------------------------------------------------------------------------
  // when we have the data of both request identifier and addresses, we consume the information
  // > this signal is in configuration clock
  assign request_consumed = (rrqq_data_vld | nrqq_data_vld);

  // =========================================================================================== //
  // Master command allocation
  // =========================================================================================== //
  always_ff @(posedge clk_mrmac) begin
    if (nrqq_cmd_vld | ntx_retry) begin
      master_command.hpu_id   <= ntx_retry ? nrqq_retry_data.hpu_id : nrqq_cmd_data.hpu_id;
      master_command.size_b   <= ntx_retry ? nrqq_retry_data.size_b : nrqq_cmd_data.size_b;
      master_command.iop_id   <= ntx_retry ? nrqq_retry_data.iop_id : nrqq_cmd_data.iop_id;
      master_command.src_addr <= ntx_retry ? nrqq_retry_data.src_addr : nrqq_cmd_data.src_addr;
      master_command.dst_addr <= 'h0;
      master_command.req_id   <= REQ_ID_NOTIFY;

      master_command_vld      <= (st_ntx_wait_request & nrqq_cmd_vld) | (nrqq_retry_vld & ntx_retry);

    end else if (rrqq_cmd_vld | rr_retry) begin
      master_command.hpu_id   <= rrqq_cmd.hpu_id;
      master_command.size_b   <= rrqq_cmd.size_b;
      master_command.iop_id   <= rrqq_cmd.iop_id;
      master_command.src_addr <= rrqq_cmd.src_addr;
      master_command.dst_addr <= rrqq_cmd.dst_addr;
      master_command.req_id   <= REQ_ID_READ;

      master_command_vld      <= (st_rr_wait_request & rrqq_cmd_vld) | rr_retry;

    end else begin
      master_command_vld <= 1'b0;
    end
  end

  // =========================================================================================== //
  // Ciphertext reception
  //
  // Assumptions:
  // We had previously guaranteed to launch a Read request only and only if fifo is empty and ready
  // =========================================================================================== //
  // ce-rx input interface
  logic [MRMAC_AXIS_W-1:0]    fifo_cerx_in_data;
  logic                       fifo_cerx_in_vld;
  logic                       fifo_cerx_in_rdy;
  // ce-rx output interface
  logic [MRMAC_AXIS_W-1:0]    fifo_cerx_out_data;
  logic                       fifo_cerx_out_vld;
  logic                       fifo_cerx_out_rdy;
  // ce-rx counters
  logic [CE_DATA_COUNT_W:0] fifo_cerx_cnt;    // counts the number of words used in fifo
  logic                     cnt_cerx_up;
  logic                     cnt_cerx_down;
  logic                     fifo_pc_backpressure;

  // First thig to do is to be sure that the current values are valid.
  // If we receive more data than what we expect we must invalidate it and not propagate it.
  logic [COUNTER_W-1:0] ce_valid_cnt;
  logic                 ce_valid;

  // Count words entering fifo_ce_rx (valid only while waiting for packets)
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_valid_cnt <= 'h0;
    end else begin
      if (start_read_request | ciphertext_received) begin
        ce_valid_cnt <= 'h0;
      end else if (st_wait_packets & fifo_cerx_in_vld & fifo_cerx_in_rdy) begin
        ce_valid_cnt <= ce_valid_cnt + 1;
      end
    end
  end

  // hard cap to avoid accepting too much words
  // Valid when no mismatch and having tolerated number of words and when error : valid is cleared
  assign ce_valid = (ce_valid_cnt < NB_WORDS_TO_HBM) & ~mismatch_retry_pending
                  & (~wait_for_seq0 | seq0_detected) & ~seq_num_mismatch;

  assign cnt_cerx_up   = fifo_cerx_in_vld & fifo_cerx_in_rdy;
  assign cnt_cerx_down = fifo_cerx_out_rdy & fifo_cerx_out_vld;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      fifo_cerx_cnt <= 'h0;
    end else begin
      if (cnt_cerx_up & ~cnt_cerx_down) begin
        fifo_cerx_cnt <= fifo_cerx_cnt + 1;
      end else if (~cnt_cerx_up & cnt_cerx_down) begin
        fifo_cerx_cnt <= fifo_cerx_cnt - 1;
      end
    end
  end

  assign fifo_cerx_in_vld  = decoder_rx_tvalid & ce_valid;
  assign fifo_cerx_in_data = decoder_rx_tdata;

  fifo_ram_rdy_vld # (
    .WIDTH             (MRMAC_AXIS_W    ),
    .DEPTH             (CT_NB_COEF      ),
    .RAM_LATENCY       (CE_RAM_LATENCY)
  ) fifo_ce_rx (
    .clk         (clk_mrmac   ),
    .s_rst_n     (resetn_mrmac),

    .in_data     (fifo_cerx_in_data),
    .in_vld      (fifo_cerx_in_vld ),
    .in_rdy      (fifo_cerx_in_rdy ),

    .out_data    (fifo_cerx_out_data ),
    .out_vld     (fifo_cerx_out_vld  ),
    .out_rdy     (fifo_cerx_out_rdy),

    .almost_full (/* UNUSED */)
  );

  // if fifo is empty and in_rdy then we can move the formatter FSM state to ST_READ_REQ
  assign ce_reception_ready = (fifo_cerx_cnt == 0) & fifo_cerx_in_rdy;

  // =========================================================================================== //
  // Zero injection in case of a wrong seq num
  // =========================================================================================== //
  // Ciphertext emission RX mux
  logic [$clog2(NB_WORDS_TO_HBM)-1:0] cerx_mux_word_cnt;
  logic [MRMAC_AXIS_W-1:0]            cerx_mux_data;
  logic                               cerx_mux_handshake;

  // Zero-padding at FIFO output
  logic [$clog2(NB_WORDS_TO_HBM)-1:0] zpad_gap_start;
  logic                               zpad_gap_pending;
  logic                               zpad_injecting;

  // Output word counter (tracks total words through the effective output path)
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      cerx_mux_word_cnt <= '0;
    end else begin
      if (ciphertext_received) begin
        cerx_mux_word_cnt <= '0;
      end else if (cerx_mux_handshake) begin
        cerx_mux_word_cnt <= cerx_mux_word_cnt + 1;
      end
    end
  end

  // Zero-injection: pad from the gap start to NB_WORDS_TO_HBM
  // End condition uses cerx_mux_word_cnt directly since gap always extends to end
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      zpad_injecting <= 1'b0;
    end else begin
      if (ciphertext_received) begin
        zpad_injecting <= 1'b0;
      end else if (~zpad_injecting & zpad_gap_pending & (cerx_mux_word_cnt == zpad_gap_start)) begin
        zpad_injecting <= 1'b1;
      end else if (zpad_injecting & fifo_pc_backpressure & (cerx_mux_word_cnt == NB_WORDS_TO_HBM - 1)) begin
        zpad_injecting <= 1'b0;
      end
    end
  end

  // Effective output signals: mux between FIFO data and zero injection
  assign cerx_mux_data      = zpad_injecting ? {MRMAC_AXIS_W{1'b0}} : fifo_cerx_out_data;
  assign cerx_mux_handshake = zpad_injecting ? fifo_pc_backpressure : (fifo_cerx_out_rdy & fifo_cerx_out_vld);

  // FIFO ready: hold off when injecting zeros or about to (prevents one real word leaking before zpad_injecting rises)
  assign fifo_cerx_out_rdy = ~zpad_injecting
                           & ~(zpad_gap_pending & (cerx_mux_word_cnt == zpad_gap_start))
                           & fifo_pc_backpressure;

  // Record gap start for FIFO-output zero injection
  // On any seq_num mismatch: pad from current input position to NB_WORDS_TO_HBM
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      zpad_gap_pending <= 1'b0;
      zpad_gap_start   <= '0;
    end else begin
      if (ciphertext_received) begin
        zpad_gap_pending <= 1'b0;
        zpad_gap_start   <= '0;
      end else if (seq_num_mismatch & ~zpad_injecting) begin
        zpad_gap_pending <= 1'b1;
        zpad_gap_start   <= ce_valid_cnt;
      end
    end
  end

  // =========================================================================================== //
  // Write into HBM
  // all @mrmac domain
  // =========================================================================================== //
  // Exactly as for RX we write into each PC one at a time
  //  - we have two fifos, one for each PC
  //  - between fifo_ce_rx and fifo_wr_pc we will avoid stalling as much as possible
  //  - we must transmit to regif relevant info and raise interrupt when all words ready in hbm
  logic [DST_ADDR_W-1:0] received_dst_addr;
  logic [  IOP_ID_W-1:0] received_iop_id;
  logic [  HPU_ID_W-1:0] received_hpu_id;

  always_ff @(posedge clk_mrmac) begin
    if (decoded_command_rdy & decoded_command_vld) begin
      received_dst_addr <= decoded_command.dst_addr;
      received_iop_id   <= decoded_command.iop_id;
      received_hpu_id   <= decoded_command.hpu_id;
    end
  end

  // phys_addr = hbm_pc_offset + ctId * CT_MEM_BYTES
  logic [ETH_PC-1:0][AXI4_ADD_W-1:0] phy_addr;
  logic                              dst_addr_valid;
  logic                              phy_addr_valid;

  always_ff @(posedge clk_mrmac)
    dst_addr_valid <= (decoded_command_rdy & decoded_command_vld) & (decoded_command.req_id == REQ_ID_EMISSION) & (decoded_command.seq_num == 0);

  always_ff @(posedge clk_mrmac)
    phy_addr_valid <= dst_addr_valid;

  generate
    for (genvar gen_p=0; gen_p<ETH_PC; gen_p=gen_p+1)
      always_ff @(posedge clk_mrmac)
        if (dst_addr_valid)
          phy_addr[gen_p] <= regf_ct_mem_addr[gen_p] + received_dst_addr * CT_MEM_BYTES;
  endgenerate

  // word distribution to each fifo pc ------------------------------------------------------------
  logic [ETH_PC-1:0]        pc_transfer_done;
  logic [ETH_PC-1:0]        axi4_write_pc;
  logic [ETH_PC-1:0]        target_fifo;
  logic [ETH_PC-1:0]        write_error;
  logic [CE_DATA_COUNT_W:0] fifo_cerx_cnt_tx;  // Counter for 64-bit words (only for debugging)

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      fifo_cerx_cnt_tx <= 'h0;
    end else begin
      if (fifo_cerx_out_vld & fifo_cerx_out_rdy) begin
        fifo_cerx_cnt_tx <= fifo_cerx_cnt_tx +1;
      end else if (ciphertext_received) begin
        fifo_cerx_cnt_tx <= 'h0;
      end
    end
  end

  // when phy_addr is computed from data received by decoder and valid or when we have done all
  // neeed writes on the first PC we can shift to the next
  // when all writes on the second pc is done we can reset the signal
  always_ff @(posedge clk_mrmac) begin : prc_write_pc_one_at_a_time
    if (~resetn_mrmac) begin
      axi4_write_pc <= 'h0;
    end else begin
      if (phy_addr_valid) begin
        axi4_write_pc <= {{(ETH_PC-1){1'b0}}, 1'b1};
      end else if (pc_transfer_done[ETH_PC-1]) begin
        axi4_write_pc <= 'h0;
      end else if (|pc_transfer_done) begin
        axi4_write_pc <= axi4_write_pc << 1;
      end
    end
  end

  // Deserialization of 64bits words (MRMAC) to 256b (AXI4_DATA_W)
  logic [AXI4_DATA_W-1:0]                       realined_word;
  logic [$clog2(NB_MRMRAC_WORDS_PER_WRITE)-1:0] realign_cnt;
  logic                                         realined_word_vld;
  logic                                         fifo_cerx_out_rdy_vld_reg;

  // Per-target-PC word counter and one-hot target_fifo selection
  logic [AXI4_WORD_PER_PC0_WW-1:0] target_pc_word_cnt;
  logic                            target_pc_last_word;

  assign target_pc_last_word = target_fifo[0] ? (target_pc_word_cnt == AXI4_WORD_PER_PC0 - 1) : (target_pc_word_cnt == AXI4_WORD_PER_PC - 1);

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      target_pc_word_cnt <= 'h0;
    end else begin
      if (realined_word_vld) begin
        if (ciphertext_received | target_pc_last_word) begin
          target_pc_word_cnt <= 'h0;
        end else begin
          target_pc_word_cnt <= target_pc_word_cnt + 1;
        end
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      target_fifo <= {{(ETH_PC-1){1'b0}}, 1'b1};
    end else begin
      if (ciphertext_received) begin
        target_fifo <= {{(ETH_PC-1){1'b0}}, 1'b1};
      end else if (realined_word_vld) begin
        if (target_pc_last_word) begin
          target_fifo <= target_fifo << 1;
        end
      end
    end
  end

  always_ff @(posedge clk_mrmac)
    fifo_cerx_out_rdy_vld_reg <= cerx_mux_handshake;

  always_ff @(posedge clk_mrmac) begin
    if(~resetn_mrmac) begin
      realign_cnt <= 'h0;
    end else begin
       if (cerx_mux_handshake & (realign_cnt == NB_MRMRAC_WORDS_PER_WRITE-1)) begin
        realign_cnt <= 'h0;
       end else if (cerx_mux_handshake) begin
        realign_cnt <= realign_cnt + 1;
      end
    end
  end

  always_ff @(posedge clk_mrmac)
    if (cerx_mux_handshake)
      realined_word[realign_cnt*MRMAC_AXIS_W+:MRMAC_AXIS_W] <= cerx_mux_data;

  assign realined_word_vld = (realign_cnt == 0) & fifo_cerx_out_rdy_vld_reg;

  generate
    for (genvar gen_wr=0; gen_wr<ETH_PC; gen_wr++) begin : gen_ce_write
      logic                   fifo_pc_wr_in_vld;
      logic                   fifo_pc_wr_in_rdy;
      // ce-rx output interface
      logic [AXI4_DATA_W-1:0] fifo_pc_wr_out_data;
      logic                   fifo_pc_wr_out_vld;
      logic                   fifo_pc_wr_out_rdy;

      fifo_ram_rdy_vld # (
        .WIDTH(AXI4_DATA_W),
        .DEPTH(FIFO_PC_DEPTH)
      ) fifo_pc_wr (
        .clk         (clk_mrmac         ),
        .s_rst_n     (resetn_mrmac      ),

        .in_data     (realined_word     ),
        .in_vld      (fifo_pc_wr_in_vld ),
        .in_rdy      (fifo_pc_wr_in_rdy ),

        .out_data    (fifo_pc_wr_out_data),
        .out_vld     (fifo_pc_wr_out_vld ),
        .out_rdy     (fifo_pc_wr_out_rdy ),

        .almost_full (/* UNUSED */)
      );

      assign fifo_pc_wr_in_vld = target_fifo[gen_wr] & realined_word_vld ;

      logic [FIFO_PC_DATA_COUNT_W:0] fifo_pc_wr_cnt;
      logic                          cnt_fifo_pc_wr_up;
      logic                          cnt_fifo_pc_wr_down;

      assign cnt_fifo_pc_wr_up   = fifo_pc_wr_in_vld & fifo_pc_wr_in_rdy;
      assign cnt_fifo_pc_wr_down = fifo_pc_wr_out_rdy & fifo_pc_wr_out_vld;

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          fifo_pc_wr_cnt <= 'h0;
        end else begin
          if (cnt_fifo_pc_wr_up & ~cnt_fifo_pc_wr_down) begin
            fifo_pc_wr_cnt <= fifo_pc_wr_cnt + 1;
          end else if (~cnt_fifo_pc_wr_up & cnt_fifo_pc_wr_down) begin
            fifo_pc_wr_cnt <= fifo_pc_wr_cnt - 1;
          end
        end
      end

      // ======================================================================================= //
      // Address channel
      // ======================================================================================= //
      // PC-specific word count
      localparam int AXI4_WORD_PER_PC_L    = (gen_wr == 0) ? AXI4_WORD_PER_PC0 : AXI4_WORD_PER_PC;
      localparam int AXI4_WORD_PER_PC_W_L  = (gen_wr == 0) ? AXI4_WORD_PER_PC0_W : AXI4_WORD_PER_PC_W;
      localparam int AXI4_WORD_PER_PC_WW_L = (gen_wr == 0) ? AXI4_WORD_PER_PC0_WW : AXI4_WORD_PER_PC_WW;

      // axi structs
      axi4_aw_if_t                      axi_a;
      logic                             axi_a_awvalid;
      logic                             axi_a_awready;
      axi4_aw_if_t                      m_axi4_aw;

      // Remaining words counter
      logic [AXI4_WORD_PER_PC_WW_L-1:0] req_axi_word_remain;
      logic [AXI4_WORD_PER_PC_WW_L-1:0] req_axi_word_remainD;
      logic                             req_last_axi_word_remain;
      logic                             req_pbs_first_burst;
      logic                             req_pbs_first_burstD;
      logic                             req_send_axi_cmd;

      // Burst counter for brsp_fifo
      logic [AXI_BURST_NB_MAX_W-1:0]    req_burst_cnt_m1;
      logic [AXI_BURST_NB_MAX_W-1:0]    req_burst_cnt_m1D;

      // Page boundary and burst length calculation
      logic [AXI4_ADD_W-1:0]            req_add;
      logic [AXI4_ADD_W-1:0]            req_addD;
      logic [AXI4_ADD_W-1:0]            req_add_start;
      logic [PAGE_BYTES_WW-1:0]         req_page_word_remain;
      logic [AXI4_LEN_W:0]              req_axi_word_nb;

      // FIFO ready signals
      logic rcp_fifo_in_rdy;
      logic brsp_fifo_in_rdy;

      assign req_send_axi_cmd = axi_a_awvalid & axi_a_awready;

      assign req_axi_word_remainD     = req_send_axi_cmd ? req_last_axi_word_remain ? AXI4_WORD_PER_PC_L : req_axi_word_remain - req_axi_word_nb : req_axi_word_remain;
      assign req_last_axi_word_remain = req_axi_word_remain == req_axi_word_nb;
      assign req_pbs_first_burstD     = req_send_axi_cmd ? req_last_axi_word_remain ? 1'b1 : 1'b0 : req_pbs_first_burst;
      assign req_burst_cnt_m1D        = req_send_axi_cmd ? req_last_axi_word_remain ? '0 : req_burst_cnt_m1 + 1 : req_burst_cnt_m1;

      always_ff @(posedge clk_mrmac)
        if (~resetn_mrmac) begin
          req_axi_word_remain <= AXI4_WORD_PER_PC_L;
          req_pbs_first_burst <= 1'b1;
          req_burst_cnt_m1    <= '0;
        end
        else begin
          req_axi_word_remain <= req_axi_word_remainD;
          req_pbs_first_burst <= req_pbs_first_burstD;
          req_burst_cnt_m1    <= req_burst_cnt_m1D;
        end

      // Address computation
      assign req_add_start        = req_pbs_first_burst ? phy_addr[gen_wr] : req_add;
      assign req_addD             = req_send_axi_cmd ? req_add_start + req_axi_word_nb * AXI4_DATA_BYTES : req_add;
      assign req_page_word_remain = PAGE_AXI4_DATA - req_add_start[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
      assign req_axi_word_nb      = req_page_word_remain < req_axi_word_remain ? req_page_word_remain : req_axi_word_remain;

      always_ff @(posedge clk_mrmac)
        if (~resetn_mrmac) req_add <= '0;
        else               req_add <= req_addD;

      // Track when all address commands for this PC have been sent
      logic addr_cmds_done;

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          addr_cmds_done <= 1'b0;
        end else if (req_send_axi_cmd & req_last_axi_word_remain) begin
          addr_cmds_done <= 1'b1;
        end else if (~axi4_write_pc[gen_wr]) begin
          addr_cmds_done <= 1'b0;
        end
      end

      // Address valid
      assign axi_a_awvalid  = axi4_write_pc[gen_wr] & ~addr_cmds_done &
                              (~req_pbs_first_burst | rcp_fifo_in_rdy) & (~req_last_axi_word_remain | brsp_fifo_in_rdy);
      assign axi_a.awid     = MHDMA_AXI_ARID;
      assign axi_a.awaddr   = req_add_start;
      assign axi_a.awsize   = MHDMA_ARSIZE;
      assign axi_a.awburst  = AXI4B_INCR;
      assign axi_a.awlen    = req_axi_word_nb - 1;

      assign m_axi4_awid[gen_wr]    = m_axi4_aw.awid;
      assign m_axi4_awaddr[gen_wr]  = m_axi4_aw.awaddr;
      assign m_axi4_awlen[gen_wr]   = m_axi4_aw.awlen;
      assign m_axi4_awsize[gen_wr]  = m_axi4_aw.awsize;
      assign m_axi4_awburst[gen_wr] = m_axi4_aw.awburst;

      fifo_element #(
        .WIDTH          ($bits(axi4_aw_if_t)),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) fifo_element_awrite_temp (
        .clk     (clk_mrmac),
        .s_rst_n (resetn_mrmac),

        .in_data (axi_a),
        .in_vld  (axi_a_awvalid),
        .in_rdy  (axi_a_awready),

        .out_data(m_axi4_aw),
        .out_vld (m_axi4_awvalid[gen_wr]),
        .out_rdy (m_axi4_awready[gen_wr])
      );

      // ======================================================================================= //
      // rcp_fifo: Store FIRST burst length only
      // ======================================================================================= //
      logic                 rcp_fifo_in_vld;
      logic [AXI4_LEN_W:0]  rcp_fifo_out_len;
      logic                 rcp_fifo_out_vld;
      logic                 rcp_fifo_out_rdy;

      // Push only on first burst
      assign rcp_fifo_in_vld = req_send_axi_cmd & req_pbs_first_burst;

      fifo_reg #(
        .WIDTH       (AXI4_LEN_W+1),
        .DEPTH       (2),
        .LAT_PIPE_MH ({1'b1, 1'b1})
      ) rcp_fifo (
        .clk      (clk_mrmac),
        .s_rst_n  (resetn_mrmac),

        .in_data  (req_axi_word_nb),
        .in_vld   (rcp_fifo_in_vld),
        .in_rdy   (rcp_fifo_in_rdy),

        .out_data (rcp_fifo_out_len),
        .out_vld  (rcp_fifo_out_vld),
        .out_rdy  (rcp_fifo_out_rdy)
      );

      // ======================================================================================= //
      // brsp_fifo: Store burst count for B response tracking
      // ======================================================================================= //
      logic                          brsp_fifo_in_vld;
      logic [AXI_BURST_NB_MAX_W-1:0] brsp_fifo_out_burst_cnt_m1;
      logic                          brsp_fifo_out_vld;
      logic                          brsp_fifo_out_rdy;

      // Push only on last burst
      assign brsp_fifo_in_vld = req_send_axi_cmd & req_last_axi_word_remain;

      fifo_reg #(
        .WIDTH       (AXI_BURST_NB_MAX_W),
        .DEPTH       (2),
        .LAT_PIPE_MH ({1'b1, 1'b1})
      ) brsp_fifo (
        .clk      (clk_mrmac),
        .s_rst_n  (resetn_mrmac),

        .in_data  (req_burst_cnt_m1),
        .in_vld   (brsp_fifo_in_vld),
        .in_rdy   (brsp_fifo_in_rdy),

        .out_data (brsp_fifo_out_burst_cnt_m1),
        .out_vld  (brsp_fifo_out_vld),
        .out_rdy  (brsp_fifo_out_rdy)
      );

      // ======================================================================================= //
      // Data channel
      // ======================================================================================= //
      axi4_w_if_t  axi_w;
      logic        axi_wvalid;
      logic        axi_wready;
      axi4_w_if_t  m_axi4_w;

      // Word counters
      logic [AXI4_WORD_PER_PC_W_L-1:0] w_word_cnt;       // Total words sent
      logic [AXI4_LEN_W-1:0]           w_burst_word_cnt; // Words within current burst
      logic                            w_first_burst;
      logic [AXI4_LEN_W-1:0]           w_burst_word_max;
      logic                            w_last_word;
      logic                            w_last_burst_word;
      logic                            w_send_data;

      assign w_send_data       = axi_wvalid & axi_wready;
      assign w_last_word       = (w_word_cnt == AXI4_WORD_PER_PC_L - 1);
      assign w_burst_word_max  = w_first_burst ? rcp_fifo_out_len - 1 : AXI4_LEN_MAX;
      assign w_last_burst_word = w_last_word | (w_burst_word_cnt == w_burst_word_max);

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          w_word_cnt       <= '0;
          w_burst_word_cnt <= '0;
          w_first_burst    <= 1'b1;
        end
        else if (w_send_data) begin
          w_word_cnt       <= w_last_word ? '0 : w_word_cnt + 1;
          w_burst_word_cnt <= w_last_burst_word ? '0 : w_burst_word_cnt + 1;
          w_first_burst    <= w_last_burst_word ? w_last_word : 1'b0;
        end
      end

      // Pop rcp_fifo only when last word of entire transfer is sent
      assign rcp_fifo_out_rdy = w_send_data & w_last_word;

      // pc_transfer_done when all data words sent
      assign pc_transfer_done[gen_wr] = w_send_data & w_last_word;

      assign fifo_pc_wr_out_rdy = axi_wready & rcp_fifo_out_vld;
      assign axi_wvalid         = fifo_pc_wr_out_vld & axi4_write_pc[gen_wr] & rcp_fifo_out_vld;

      assign axi_w.wlast = w_last_burst_word;
      assign axi_w.wstrb = {AXI4_STRB_W{1'b1}};
      assign axi_w.wdata = fifo_pc_wr_out_data;

      assign m_axi4_wdata[gen_wr] = m_axi4_w.wdata;
      assign m_axi4_wstrb[gen_wr] = m_axi4_w.wstrb;
      assign m_axi4_wlast[gen_wr] = m_axi4_w.wlast;

      fifo_element #(
        .WIDTH          (AXI4_W_IF_W),
        .DEPTH          (2),
        .TYPE_ARRAY     ({4'h1,4'h2}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) fifo_element_write_temp (
        .clk     (clk_mrmac   ),
        .s_rst_n (resetn_mrmac),

        .in_data (axi_w),
        .in_vld  (axi_wvalid),
        .in_rdy  (axi_wready),

        .out_data(m_axi4_w),
        .out_vld (m_axi4_wvalid[gen_wr]),
        .out_rdy (m_axi4_wready[gen_wr])
      );

      // ======================================================================================= //
      // Write response channel
      // ======================================================================================= //
      localparam int BRSP_CNT_W = AXI_BURST_NB_MAX_WW + 2;

      axi4_b_if_t  axi_b;
      logic        axi_bvalid;
      logic        axi_bready;
      axi4_b_if_t  m_axi4_b;

      logic [BRSP_CNT_W-1:0]          brsp_bresp_cnt;
      logic [BRSP_CNT_W-1:0]          brsp_bresp_cntD;
      logic                           brsp_bresp_cnt_inc;
      logic                           brsp_bresp_cnt_dec;
      logic [AXI_BURST_NB_MAX_WW-1:0] brsp_bresp_cnt_dec_val;
      logic [AXI_BURST_NB_MAX_WW-1:0] brsp_bresp_cnt_dec_val_m1;
      logic                           brsp_bresp_cnt_full;
      logic                           brsp_all_bresp_received;
      logic                           brsp_ack;

      assign brsp_bresp_cnt_full  = brsp_bresp_cnt == {BRSP_CNT_W{1'b1}};
      assign axi_bready           = ~brsp_bresp_cnt_full;
      assign brsp_bresp_cnt_inc   = axi_bready & axi_bvalid;
      assign brsp_bresp_cntD      = brsp_bresp_cnt_inc  && !brsp_bresp_cnt_dec ? brsp_bresp_cnt + 1 :
                                    !brsp_bresp_cnt_inc && brsp_bresp_cnt_dec  ? brsp_bresp_cnt - brsp_bresp_cnt_dec_val :
                                    brsp_bresp_cnt_inc  && brsp_bresp_cnt_dec  ? brsp_bresp_cnt - brsp_bresp_cnt_dec_val_m1 :
                                    brsp_bresp_cnt;

      always_ff @(posedge clk_mrmac)
        if (~resetn_mrmac) brsp_bresp_cnt <= '0;
        else               brsp_bresp_cnt <= brsp_bresp_cntD;

      assign brsp_all_bresp_received   = (brsp_bresp_cnt > brsp_fifo_out_burst_cnt_m1);
      assign brsp_bresp_cnt_dec        = brsp_fifo_out_vld & brsp_all_bresp_received;
      assign brsp_bresp_cnt_dec_val_m1 = brsp_fifo_out_burst_cnt_m1;
      assign brsp_bresp_cnt_dec_val    = brsp_fifo_out_burst_cnt_m1 + 1;

      assign brsp_ack          = brsp_fifo_out_vld & brsp_all_bresp_received;
      assign brsp_fifo_out_rdy = brsp_all_bresp_received;

      // Handle write errors
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          write_error[gen_wr] <= 1'b0;
        end else begin
          if (rst_errors) begin
            write_error[gen_wr] <= 1'b0;
          end else if (axi_bready & axi_bvalid) begin
            case (axi_b.bresp)
              AXI4_OKAY:   write_error[gen_wr] <= 1'b0;
              AXI4_EXOKAY: write_error[gen_wr] <= 1'b0;
              AXI4_SLVERR: write_error[gen_wr] <= 1'b1;
              AXI4_DECERR: write_error[gen_wr] <= 1'b1;
            endcase
          end
        end
      end

      assign m_axi4_b.bid   = m_axi4_bid[gen_wr];
      assign m_axi4_b.bresp = m_axi4_bresp[gen_wr];

      fifo_element #(
        .WIDTH          ($bits(axi4_b_if_t)),
        .DEPTH          (2),
        .TYPE_ARRAY     ({4'h1,4'h2}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) fifo_element_bresp_temp (
        .clk     (clk_mrmac),
        .s_rst_n (resetn_mrmac),

        .in_data (m_axi4_b),
        .in_vld  (m_axi4_bvalid[gen_wr]),
        .in_rdy  (m_axi4_bready[gen_wr]),

        .out_data(axi_b),
        .out_vld (axi_bvalid),
        .out_rdy (axi_bready)
      );
    end
  endgenerate

  logic [ETH_PC-1:0] fifo_pc_wr_rdy;

  generate
    for (genvar gen_i = 0; gen_i < ETH_PC; gen_i++) begin : gen_pc_wr_rdy
      assign fifo_pc_wr_rdy[gen_i] = gen_ce_write[gen_i].fifo_pc_wr_in_rdy;
    end
  endgenerate

  assign fifo_pc_backpressure = |(target_fifo & fifo_pc_wr_rdy);

  // Interrupt generation -------------------------------------------------------------------------
  // Ciphertext received when both PCs have completed their transfers (= all B responses received)
  // Use brsp_ack from each PC which fires when all B responses are received
  logic [ETH_PC-1:0] pc_brsp_ack;
  logic [ETH_PC-1:0] pc_brsp_ack_seen;

  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_brsp_ack
      assign pc_brsp_ack[gen_i] = gen_ce_write[gen_i].brsp_ack;

      // Track if brsp_ack was seen (sticky until ciphertext_received)
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          pc_brsp_ack_seen[gen_i] <= 1'b0;
        end else begin
          if (ciphertext_received) begin
            pc_brsp_ack_seen[gen_i] <= 1'b0;
          end else if (pc_brsp_ack[gen_i]) begin
            pc_brsp_ack_seen[gen_i] <= 1'b1;
          end
        end
      end
    end
  endgenerate

  // ciphertext_received is a pulse when both PCs have received all B responses
  assign ciphertext_received = &(pc_brsp_ack | pc_brsp_ack_seen);

  // regf payload information ---------------------------------------------------------------------
  logic [REG_DATA_W-1:0] rr_regf_in_data;
  logic                  rr_regf_in_rdy;
  logic                  rr_regf_in_vld;

  logic [REG_DATA_W-1:0] rr_regf_out_data;
  logic                  rr_regf_out_vld;
  logic                  rr_regf_out_rdy;

  // rr_regf_in_rdy there is no back pressurew
  assign rr_regf_in_data = {received_dst_addr, 4'b0, received_hpu_id, received_iop_id};

  // Interrput must be triggered only when ciphertext is valid
  assign rr_regf_in_vld = valid_ciphertext_received;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak theses parameters in package
    .WIDTH           (REG_DATA_W),
    .DEPTH           (REQ_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(REQ_MEMORY_TYPE)
  ) rr_resp_ram_rdy_vld_2clk (
    // Write Domain ports: MRMAC domain
    .in_clk      (clk_mrmac),
    .in_rstn     (resetn_mrmac),
    .in_data     (rr_regf_in_data),
    .in_rdy      (rr_regf_in_rdy),
    .in_vld      (rr_regf_in_vld),
    .almost_full (/* UNUSED */),
    // Read Domain ports: CFG domain
    .out_clk     (clk_cfg),
    .out_rstn    (resetn_cfg),
    .out_data    (rr_regf_out_data),
    .out_rdy     (rr_regf_out_rdy),
    .out_vld     (rr_regf_out_vld)
  );

  assign rr_regf_out_rdy = clear_interrupt_rr;

  assign regf_read_payload = rr_regf_out_data;
  assign interrupt_read_request = rr_regf_out_vld;

  // =========================================================================================== //
  // Errors
  // =========================================================================================== //
  logic seq_num_error;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      seq_num_error <= 1'b0;
    end else begin
      if (rst_errors) begin
        seq_num_error <= 1'b0;
      end else if (seq_num_mismatch) begin
        seq_num_error <= 1'b1;
      end
    end
  end

  assign master_error = {seq_num_error, write_error};

  // =========================================================================================== //
  // Statistics
  // =========================================================================================== //
  logic [REG_DATA_W-1:0] retry_notify_cnt;
  logic [REG_DATA_W-1:0] retry_read_req_cnt;
  logic [REG_DATA_W-1:0] notify_cnt;
  logic [REG_DATA_W-1:0] notify_ack_cnt;
  logic [REG_DATA_W-1:0] t_notify_to_ack;
  logic [REG_DATA_W-1:0] t_rr_to_ce_received;
  logic [REG_DATA_W-1:0] nb_write_complete_cnt;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      notify_cnt <= 'h0;
    end else begin
      if (stat_rst.cnt_notify) begin
        notify_cnt <= 'h0;
      end else begin
        if (notify_sent) begin
          notify_cnt <= notify_cnt + 1;
        end
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      notify_ack_cnt <= 'h0;
    end else begin
      if (stat_rst.cnt_notify_ack) begin
        notify_ack_cnt <= 'h0;
      end else begin
        if (notify_ack_received) begin
          notify_ack_cnt <= notify_ack_cnt + 1;
        end
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if(~resetn_mrmac) begin
      retry_notify_cnt <= 'h0;
    end else begin
      if (stat_rst.cnt_notify_retry) begin
        retry_notify_cnt <= 'h0;
      end else begin
        if (timeout_reached_notify) begin
          retry_notify_cnt <= retry_notify_cnt + 1;
        end
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if(~resetn_mrmac) begin
      retry_read_req_cnt <= 'h0;
    end else begin
      if (stat_rst.cnt_read_req_retry) begin
        retry_read_req_cnt <= 'h0;
      end else begin
        if (timeout_reached_read_request | retry_seq_num) begin
          retry_read_req_cnt <= retry_read_req_cnt + 1;
        end
      end
    end
  end

  // timing counter : counter between notify sent from this HPU (on tlast) and ack reception (2nd frame of the header)
  logic count_notify_ack;
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      count_notify_ack <= 1'b0;
    end else begin
      if (notify_sent) begin
        count_notify_ack <= 1'b1;
      end else if (notify_ack_received) begin
        count_notify_ack <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      t_notify_to_ack <= 'h0;
    end else begin
      if (count_notify_ack) begin
        t_notify_to_ack <= t_notify_to_ack + 1;
      end else begin
        t_notify_to_ack <= 'h0;
      end
    end
  end

  // timing counter : counter between start and end of read request
  logic count_rreq_receive;
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      count_rreq_receive <= 1'b0;
    end else begin
      if (start_read_request) begin
        count_rreq_receive <= 1'b1;
      end else if (ciphertext_received) begin
        count_rreq_receive <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      t_rr_to_ce_received <= 'h0;
    end else begin
       if(count_rreq_receive) begin
        t_rr_to_ce_received <= t_rr_to_ce_received + 1;
       end else begin
        t_rr_to_ce_received <= 'h0;
       end
    end
  end

  // value assignation for timing registers -------------------------------------------------------
  logic [REG_DATA_W-1:0] stat_t_notify_to_ack_r;
  logic [REG_DATA_W-1:0] stat_t_rr_to_ce_received_r;
  logic [REG_DATA_W-1:0] stat_nb_ce_words_received_r;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      stat_t_notify_to_ack_r <= 'h0;
    end else begin
      if (notify_ack_received) begin
        stat_t_notify_to_ack_r <= t_notify_to_ack;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      stat_t_rr_to_ce_received_r <= 'h0;
    end else begin
      if (ciphertext_received) begin
        stat_t_rr_to_ce_received_r <= t_rr_to_ce_received;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      stat_nb_ce_words_received_r <= 'h0;
    end else begin
      if (stat_rst.nb_ce_words_received) begin
        stat_nb_ce_words_received_r <= 'h0;
      end else begin
        if (ciphertext_received) begin
          stat_nb_ce_words_received_r <= { {(REG_DATA_W-CE_DATA_COUNT_W){1'b0}}, fifo_cerx_cnt_tx};
        end
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac)begin
      nb_write_complete_cnt <= 'h0;
    end else begin
      // Count completed transfers (all B responses received)
      if (|pc_brsp_ack) begin
        nb_write_complete_cnt <= nb_write_complete_cnt +1;
      end
    end
  end

  assign stat.fsm_notify            = ntx_state;
  assign stat.fsm_read_req          = rreq_state;
  assign stat.cnt_notify_retries    = retry_notify_cnt;
  assign stat.cnt_read_req_retries  = retry_read_req_cnt;
  assign stat.cnt_notify            = notify_cnt;
  assign stat.cnt_notify_ack        = notify_ack_cnt;
  assign stat.cnt_notify_timeout    = to_notify_cnt;
  assign stat.nb_write_complete_cnt = nb_write_complete_cnt;
  assign stat.t_notify_to_ack       = stat_t_notify_to_ack_r;
  assign stat.t_rr_to_ce_received   = stat_t_rr_to_ce_received_r;
  assign stat.nb_ce_words_received  = stat_nb_ce_words_received_r;

endmodule
