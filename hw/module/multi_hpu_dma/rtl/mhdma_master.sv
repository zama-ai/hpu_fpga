// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA Master module
// ------------------------------------------------------------------------------------------------
// Sends Notify & Read-Request to the formatter, receives ciphertext packets from decoder, check
// they are valid with seq_num and writes the payload into memory with AXI4 bus (One PC at a time).
//
// Retry logic:
//  - Notify: retried on timeout only (NTX_WAIT_ACK -> NTX_SEND_NOTIFY).
//  - Read request: retried on timeout OR seq_num mismatch. On mismatch or timeout
//    (while writing), the in-flight AXI burst completes (AXI protocol), then transfer
//    stops; retry overwrites from offset 0.
//
// Write path: stream-through with reactive page-aligned bursts.
//  - Dataflow: decoder > fifo_ce_rx > deserialization > fifo > burst FSM > AXI4 > fifo
//  - One burst state machine per PC (BURST_IDLE > BURST_AW > BURST_W_DATA > BURST_DONE)
//
// Assumptions:
//  - regf_timeout_duration_notify & regf_timeout_duration_read_req are quasi static signals.
//  - rr_resp_ram_rdy_vld_2clk must not go full : REQ_FIFO_DEPTH must be enough
//    otherwise the interrupt push is silently lost.
//  - Decoder must hold decoded_command and decoded_command_vld stable until
//    decoded_command_rdy is asserted (1-cycle latency: rdy is registered).
//
// Note:
//  - master_command_vld drops only one clock cycle after ready :
//      acceptable because handshakes are only FSM-to-FSM
//  - If FIFO read request -> regif is full. We block FSM and cannot go to RR_SEND_REQUEST
//
// ================================================================================================

module mhdma_master
  import mhdma_pkg::*;               // for all mhdma modules
  import axi_if_mhdma_axi_pkg::*;    // AXI4
  import axi_if_shell_axil_pkg::*;   // REG_DATA_W
  import axi_if_common_param_pkg::*; // HBM page
  import pem_common_param_pkg::*;    // CT_MEM_BYTES, AXI4_WORD_PER_PC_L*
#(
  parameter int CDC_SYNC_STAGES = 2
) (
  // Ethernet configuration interface -------------------------------------------------------------
  input  logic                                clk_mhdma_cfg,
  input  logic                                resetn_mhdma_cfg,
  // Ethernet fast clock interface ----------------------------------------------------------------
  input  logic                                clk_mhdma,
  input  logic                                resetn_mhdma,
  // Axi4 interface for NMU -----------------------------------------------------------------------
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
  // regf interface -------------------------------------------------------------------------------
  input  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr,
  input  logic               [REG_DATA_W-1:0] regf_req_id,
  input  logic               [REG_DATA_W-1:0] regf_req_addr,
  output logic               [REG_DATA_W-1:0] regf_read_req_id,
  output logic               [REG_DATA_W-1:0] regf_read_addr,
  input  logic               [REG_DATA_W-1:0] regf_timeout_duration_notify,
  input  logic               [REG_DATA_W-1:0] regf_timeout_duration_read_req,
  // register control
  input  logic                                received_req,
  output logic                                request_consumed,
  // interrupt ------------------------------------------------------------------------------------
  input  logic                                clear_interrupt_rr,
  output logic                                interrupt_read_request,
  // decoder interface ----------------------------------------------------------------------------
  input  command_t                            decoded_command,
  input  logic                                decoded_command_vld,
  output logic                                decoded_command_rdy,

  input  logic             [MRMAC_AXIS_W-1:0] decoder_rx_tdata,
  input  logic                                decoder_rx_tvalid,

  input  logic                                notify_ack_received,
  // formatter interface --------------------------------------------------------------------------
  output command_t                            master_command,
  output logic                                master_command_vld,
  input  logic                                master_command_rdy,

  input  logic                                read_request_sent,
  input  logic                                notify_sent,

  // Error interface ------------------------------------------------------------------------------
  output master_error_t                       master_error,
  input  logic                                rst_errors,
  // statistics -----------------------------------------------------------------------------------
  output master_stat_t                        stat,
  input  master_stat_rst_t                    stat_rst
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int NB_WORDS_TOTAL  = AXI4_WORD_PER_PC0 + (ETH_PC-1) * AXI4_WORD_PER_PC;
  localparam int NB_WORDS_TOTAL_WW = $clog2(NB_WORDS_TOTAL+1) == 0 ? 1 : $clog2(NB_WORDS_TOTAL+1);
  localparam int NB_WORDS_TO_HBM = (NB_WORDS_TOTAL*AXI4_DATA_W)/MRMAC_AXIS_W;

  // Max burst count per PC for page boundary crossings
  localparam int AXI_BURST_NB_MAX    = 2 * (NB_PACKETS_FULL + 2);
  localparam int AXI_BURST_NB_MAX_W  = $clog2(AXI_BURST_NB_MAX) == 0 ? 1 : $clog2(AXI_BURST_NB_MAX);
  localparam int AXI_BURST_NB_MAX_WW = $clog2(AXI_BURST_NB_MAX+1) == 0 ? 1 : $clog2(AXI_BURST_NB_MAX+1);

  localparam int NUM_STAT_CNTS = 4;

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
  logic st_ntx_wait_ack;
  logic ntx_retry;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ntx_state <= NTX_WAIT_REQUEST;
    end else begin
      ntx_state <= ntx_next_state;
    end
  end

  always_comb begin
    ntx_next_state = NTX_XXX;
    case (ntx_state)
      NTX_WAIT_REQUEST:
        ntx_next_state = start_notify_request ? NTX_SEND_NOTIFY : NTX_WAIT_REQUEST;
      NTX_SEND_NOTIFY:
        ntx_next_state = notify_sent ? NTX_WAIT_ACK : NTX_SEND_NOTIFY;
      NTX_WAIT_ACK:
        // Transmission is not instantaneous, notify_ack_received cannot arrive before axis tlast
        ntx_next_state = notify_ack_received ? NTX_WAIT_REQUEST : timeout_reached_notify ? NTX_SEND_NOTIFY : NTX_WAIT_ACK;
      default: ntx_next_state = NTX_WAIT_REQUEST;
    endcase
  end

  assign st_ntx_wait_request = (ntx_state == NTX_WAIT_REQUEST);
  assign st_ntx_wait_ack     = (ntx_state == NTX_WAIT_ACK);

  // Read request ---------------------------------------------------------------------------------
  logic start_read_request;
  logic ciphertext_received;
  logic valid_ciphertext_received;
  logic rr_retry;
  logic rr_regf_in_rdy; // fifo that creates interrupts (@mhdma_clk)

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

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      rreq_state <= RR_WAIT_REQUEST;
    end else begin
      rreq_state <= rreq_next_state;
    end
  end

  always_comb begin
    rreq_next_state = RR_XXX;
    case (rreq_state)
      RR_WAIT_REQUEST:
        rreq_next_state = start_read_request & rr_regf_in_rdy ? RR_SEND_REQUEST : RR_WAIT_REQUEST;
      RR_SEND_REQUEST:
        rreq_next_state =  read_request_sent ? RR_WAIT_PACKETS : RR_SEND_REQUEST;
      RR_WAIT_PACKETS:
        rreq_next_state = rr_retry ? RR_SEND_REQUEST : valid_ciphertext_received ? RR_WAIT_REQUEST : RR_WAIT_PACKETS;
      default: rreq_next_state = RR_WAIT_REQUEST;
    endcase
  end

  assign st_wait_packets    = (rreq_state == RR_WAIT_PACKETS);
  assign st_rr_wait_request = (rreq_state == RR_WAIT_REQUEST);

  // =========================================================================================== //
  // Consuming decoded commands
  // =========================================================================================== //
  logic nack_rdy;
  logic rr_packets_rdy;

  // NOTE: The decoder holds decoded_command_vld and decoded_command stable until decoded_command_rdy is 1
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      nack_rdy       <= 1'b0;
      rr_packets_rdy <= 1'b0;
    end else begin
      nack_rdy       <= decoded_command_vld & (decoded_command.req_id == REQ_ID_NOTIFY_ACK);
      rr_packets_rdy <= decoded_command_vld & (decoded_command.req_id == REQ_ID_EMISSION);
    end
  end

  assign decoded_command_rdy = nack_rdy | rr_packets_rdy;

  // =========================================================================================== //
  // Retry
  // =========================================================================================== //

  // notify ---------------------------------------------------------------------------------------
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ntx_retry <= 1'b0;
    end else begin
      if (timeout_reached_notify) begin
        ntx_retry <= 1'b1;
      end else if (master_command_rdy & (master_command.req_id == REQ_ID_NOTIFY)) begin
        ntx_retry <= 1'b0;
      end
    end
  end

  // retry signal ---------------------------------------------------------------------------------
  logic mismatch_retry_pending;
  logic timeout_reached_read_request;
  logic retry_seq_num;
  logic seq_num_mismatch;
  logic wait_for_seq0;
  logic timeout_retry_pending;

  assign valid_ciphertext_received = ciphertext_received & ~mismatch_retry_pending & ~timeout_retry_pending;

  // building read request retry signal
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      rr_retry <= 1'b0;
    end else begin
      if (timeout_reached_read_request | retry_seq_num) begin
        rr_retry <= 1'b1;
      end else if (master_command_rdy & (master_command.req_id == REQ_ID_READ)) begin
        rr_retry <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      mismatch_retry_pending <= 1'b0;
    end else if (ciphertext_received) begin
      mismatch_retry_pending <= 1'b0;
    end else if (seq_num_mismatch) begin
      mismatch_retry_pending <= 1'b1;
    end
  end

  // NOTE that mismatch_retry_pending has one cycle delay with ciphertext_received
  assign retry_seq_num = mismatch_retry_pending & ciphertext_received;

  // Seq num mismatch decoding --------------------------------------------------------------------
  logic [SEQ_NUM_W-1:0] expected_seq_num;
  logic [SEQ_NUM_W-1:0] received_seq_num; // registered copy of decoded_command.seq_num for mismatch check
  logic                 seq_num_valid;
  logic                 rr_packets_rdy_r;
  logic                 seq0_detected;
  logic                 frontedge_rr_packets_rdy;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      rr_packets_rdy_r <= 1'b0;
    end else begin
      rr_packets_rdy_r <= rr_packets_rdy;
    end
  end

  assign frontedge_rr_packets_rdy = (rr_packets_rdy & ~rr_packets_rdy_r);

  // Register seq0 detection alongside rr_packets_rdy so we only compare decoded_command.seq_num while decoded_command_vld guaranteed valid data.
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      seq0_detected <= 1'b0;
    end else begin
      seq0_detected <= decoded_command_vld & (decoded_command.req_id == REQ_ID_EMISSION) & (decoded_command.seq_num == 0);
    end
  end

  // Register decoded seq_num (aligned with seq0_detected / frontedge_rr_packets_rdy timing).
  always_ff @(posedge clk_mhdma)
    received_seq_num <= decoded_command.seq_num;

  assign seq_num_valid = st_wait_packets & frontedge_rr_packets_rdy & (~wait_for_seq0 | seq0_detected);

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
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
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      wait_for_seq0 <= 1'b0;
    end else begin
      if (retry_seq_num) begin
        wait_for_seq0 <= 1'b1;
      end else if (seq0_detected) begin
        wait_for_seq0 <= 1'b0;
      end
    end
  end

  // Any seq_num != expected is a mismatch: drop remaining packets, zero-pad (if needed) then retry
  // Uses registered received_seq_num to be aligned with frontedge_rr_packets_rdy/seq_num_valid timing
  assign seq_num_mismatch = seq_num_valid & (received_seq_num != expected_seq_num);

  // =========================================================================================== //
  // Timeouts
  // =========================================================================================== //
  logic [REG_DATA_W-1:0] to_dur_read_req;
  logic [REG_DATA_W-1:0] to_dur_notify;

  always_ff @(posedge clk_mhdma)
    to_dur_read_req <= regf_timeout_duration_read_req;

  always_ff @(posedge clk_mhdma)
    to_dur_notify <= regf_timeout_duration_notify;

  // timeout --------------------------------------------------------------------------------------
  logic [REG_DATA_W-1:0] to_notify_cnt;

  always_ff @(posedge clk_mhdma) begin : timeout_counter
    if (~resetn_mhdma) begin
      to_notify_cnt <= 'h0;
    end else begin
      if (ntx_state == NTX_WAIT_ACK) begin
        to_notify_cnt <= to_notify_cnt + 1;
      end else begin
        to_notify_cnt <= 'h0;
      end
    end
  end

  assign timeout_reached_notify = (to_notify_cnt == to_dur_notify);

  // timeout read request -------------------------------------------------------------------------
  logic [REG_DATA_W-1:0] to_read_request_cnt;

  always_ff @(posedge clk_mhdma) begin : timeout_counter_rr
    if (~resetn_mhdma) begin
      to_read_request_cnt <= 'h0;
    end else begin
      if (rreq_state == RR_WAIT_PACKETS) begin
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

  always_ff @(posedge clk_mhdma_cfg)
    if (~rrqq_in_rdy & rrqq_in_vld)
      rrqq_data_kept <= {regf_req_id, regf_req_addr};

  always_ff @(posedge clk_mhdma_cfg) begin
    if (~resetn_mhdma_cfg) begin
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
    .in_clk      (clk_mhdma_cfg),
    .in_rstn     (resetn_mhdma_cfg),
    .in_data     (rrqq_in_data),
    .in_rdy      (rrqq_in_rdy),
    .in_vld      (rrqq_data_vld),
    .almost_full (/* UNUSED */),
    // MRMAC domain
    .out_clk     (clk_mhdma),
    .out_rstn    (resetn_mhdma),
    .out_data    ({rrqq_cmd.iop_id, rrqq_cmd.req_id, rrqq_cmd.hpu_id, rrqq_cmd.mode, rrqq_cmd.flag, rrqq_cmd.rsvd, rrqq_cmd.dst_addr, rrqq_cmd.src_addr}),
    .out_rdy     (rrqq_cmd_rdy),
    .out_vld     (rrqq_cmd_vld)
  );

  assign rrqq_cmd_rdy = start_read_request & st_rr_wait_request;
  assign start_read_request = master_command_rdy & (master_command.req_id == REQ_ID_READ);

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
  command_t                nrqq_cmd;
  logic                    nrqq_cmd_rdy;
  logic                    nrqq_cmd_vld;

  // @cfg clock ---------------------------------
  assign nrqq_in_vld = received_req & (regf_req_id[23:20] == REQ_ID_NOTIFY);

  // backpressure
  always_ff @(posedge clk_mhdma_cfg)
    if (nrqq_in_vld & ~nrqq_in_rdy)
      nrqq_data_kept <= {regf_req_id, regf_req_addr};

  always_ff @(posedge clk_mhdma_cfg) begin
    if (~resetn_mhdma_cfg) begin
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
    .in_clk      (clk_mhdma_cfg),
    .in_rstn     (resetn_mhdma_cfg),
    .in_data     (nrqq_in_data),
    .in_rdy      (nrqq_in_rdy),
    .in_vld      (nrqq_data_vld),
    .almost_full (/* UNUSED */),
    //  MRMAC domain
    .out_clk     (clk_mhdma),
    .out_rstn    (resetn_mhdma),
    .out_data    ({nrqq_cmd.iop_id, nrqq_cmd.req_id, nrqq_cmd.hpu_id, nrqq_cmd.mode, nrqq_cmd.flag, nrqq_cmd.rsvd, nrqq_cmd.dst_addr, nrqq_cmd.src_addr}),
    .out_rdy     (nrqq_cmd_rdy),
    .out_vld     (nrqq_cmd_vld)
  );

  logic     nrqq_retry_in_rdy;
  command_t nrqq_retry;
  logic     nrqq_retry_rdy;
  logic     nrqq_retry_vld;

  assign nrqq_cmd_rdy = (master_command_rdy & (master_command.req_id == REQ_ID_NOTIFY)) & ~ntx_retry & nrqq_retry_in_rdy;
  assign start_notify_request = nrqq_cmd_rdy;

  fifo_ram_rdy_vld # (
    .WIDTH       (IOP_ID_W + HPU_ID_W + RSVD_W + FLAG_W + MODE_W + DST_ADDR_W + SRC_ADDR_W),
    .DEPTH       (REQ_FIFO_DEPTH),
    .RAM_LATENCY (CE_RAM_LATENCY)
  ) nrqq_fifo_retries (
    .clk         (clk_mhdma   ),
    .s_rst_n     (resetn_mhdma),

    .in_data     ({nrqq_cmd.iop_id, nrqq_cmd.hpu_id, nrqq_cmd.mode, nrqq_cmd.flag, nrqq_cmd.rsvd, nrqq_cmd.dst_addr, nrqq_cmd.src_addr}),
    .in_vld      (start_notify_request),
    .in_rdy      (nrqq_retry_in_rdy   ),

    .out_data    ({nrqq_retry.iop_id, nrqq_retry.hpu_id, nrqq_retry.mode, nrqq_retry.flag, nrqq_retry.rsvd, nrqq_retry.dst_addr, nrqq_retry.src_addr}),
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
  logic ce_reception_ready; // gating when fifo is not empty

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      master_command.req_id <= 'h0;   // prevents X upon start of FSM
      master_command_vld    <= 1'b0;
    end else begin
    if (nrqq_cmd_vld | ntx_retry) begin
      master_command.hpu_id   <= ntx_retry ? nrqq_retry.hpu_id   : nrqq_cmd.hpu_id;
      master_command.rsvd     <= ntx_retry ? nrqq_retry.rsvd     : nrqq_cmd.rsvd;
      master_command.flag     <= ntx_retry ? nrqq_retry.flag     : nrqq_cmd.flag;
      master_command.mode     <= ntx_retry ? nrqq_retry.mode     : nrqq_cmd.mode;
      master_command.iop_id   <= ntx_retry ? nrqq_retry.iop_id   : nrqq_cmd.iop_id;
      master_command.src_addr <= ntx_retry ? nrqq_retry.src_addr : nrqq_cmd.src_addr;
      master_command.dst_addr <= ntx_retry ? nrqq_retry.dst_addr : nrqq_cmd.dst_addr;
      master_command.req_id   <= REQ_ID_NOTIFY;

      master_command_vld      <= ((st_ntx_wait_request & nrqq_cmd_vld) | (nrqq_retry_vld & ntx_retry));

    end else if (rrqq_cmd_vld | rr_retry) begin
      master_command.hpu_id   <= rrqq_cmd.hpu_id;
      master_command.rsvd     <= rrqq_cmd.rsvd;
      master_command.flag     <= rrqq_cmd.flag;
      master_command.mode     <= rrqq_cmd.mode;
      master_command.iop_id   <= rrqq_cmd.iop_id;
      master_command.src_addr <= rrqq_cmd.src_addr;
      master_command.dst_addr <= rrqq_cmd.dst_addr;
      master_command.req_id   <= REQ_ID_READ;

      master_command_vld      <= ((st_rr_wait_request & rrqq_cmd_vld & ce_reception_ready & rr_regf_in_rdy) | rr_retry);

    end else begin
      master_command_vld <= 1'b0;
    end
    end
  end

  // =========================================================================================== //
  // Abort transfer on seq_num mismatch
  // =========================================================================================== //
  logic abort_transfer;
  logic [ETH_PC-1:0]        axi4_write_pc;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      abort_transfer <= 1'b0;
    end else if (seq_num_mismatch | (timeout_reached_read_request & |axi4_write_pc)) begin
      abort_transfer <= 1'b1;
    end else if (ciphertext_received) begin
      abort_transfer <= 1'b0;
    end
  end

  // Track timeout-driven aborts to suppress spurious interrupt on abort completion
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      timeout_retry_pending <= 1'b0;
    end else if (ciphertext_received) begin
      timeout_retry_pending <= 1'b0;
    end else if (timeout_reached_read_request & |axi4_write_pc) begin
      timeout_retry_pending <= 1'b1;
    end
  end

  // =========================================================================================== //
  // Ciphertext reception
  //
  // Assumptions:
  // We had previously guaranteed to launch a Read request only and only if fifo is empty and ready
  // =========================================================================================== //
  // ce-rx input interface
  logic [MRMAC_AXIS_W-1:0]  fifo_cerx_in_data;
  logic                     fifo_cerx_in_vld;
  logic                     fifo_cerx_in_rdy;
  // ce-rx output interface
  logic [MRMAC_AXIS_W-1:0]  fifo_cerx_out_data;
  logic                     fifo_cerx_out_vld;
  logic                     fifo_cerx_out_rdy;
  logic                     fifo_cerx_out_rdy_flush;
  // ce-rx FIFO & control
  logic [CE_DATA_COUNT_W:0] fifo_cerx_cnt;  // counts the number of words used in fifo
  logic                     cnt_cerx_up;
  logic                     cnt_cerx_down;
  logic                     cerx_handshake; // Handshake at output (useful for deserialization)
  logic [COUNTER_W-1:0]     ce_valid_cnt;
  logic                     ce_valid;

  // First thing to do is to be sure that the current values are valid.
  // If we receive more data than what we expect we must invalidate it and not propagate it.

  // Count words entering fifo_ce_rx (valid only while waiting for packets)
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
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
  assign cnt_cerx_down = (fifo_cerx_out_rdy | fifo_cerx_out_rdy_flush) & fifo_cerx_out_vld;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      fifo_cerx_cnt <= 'h0;
    end else begin
      if (cnt_cerx_up & ~cnt_cerx_down) begin
        fifo_cerx_cnt <= fifo_cerx_cnt + 1;
      end else if (~cnt_cerx_up & cnt_cerx_down) begin
        fifo_cerx_cnt <= fifo_cerx_cnt - 1;
      end
    end
  end

  // Register decoder payload to align with rr_packets_rdy / seq_num_mismatch timing.
  // Without this, payload data arrives one cycle before the seq_num check can gate ce_valid.
  logic                    decoder_rx_tvalid_r;
  logic [MRMAC_AXIS_W-1:0] decoder_rx_tdata_r;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      decoder_rx_tvalid_r <= 1'b0;
    end else begin
      decoder_rx_tvalid_r <= decoder_rx_tvalid;
    end
  end

  always_ff @(posedge clk_mhdma)
    decoder_rx_tdata_r <= decoder_rx_tdata;

  assign fifo_cerx_in_vld  = decoder_rx_tvalid_r & ce_valid;
  assign fifo_cerx_in_data = decoder_rx_tdata_r;

  fifo_ram_rdy_vld # (
    .WIDTH      (MRMAC_AXIS_W      ),
    .DEPTH      (CT_NB_COEF        ),
    .RAM_LATENCY(CE_RAM_LATENCY    )
  ) fifo_ce_rx (
    .clk        (clk_mhdma         ),
    .s_rst_n    (resetn_mhdma      ),

    .in_data    (fifo_cerx_in_data ),
    .in_vld     (fifo_cerx_in_vld  ),
    .in_rdy     (fifo_cerx_in_rdy  ),

    .out_data   (fifo_cerx_out_data),
    .out_vld    (fifo_cerx_out_vld ),
    .out_rdy    (fifo_cerx_out_rdy | fifo_cerx_out_rdy_flush),

    .almost_full(/*    UNUSED    */)
  );

  // It is mandatory to flush out data that has not been consumed yet by AXI write on Abort.
  assign fifo_cerx_out_rdy_flush = abort_transfer & (fifo_cerx_cnt != 0);

  // if fifo is empty and in_rdy and no in-flight AXI then we can accept new ciphertext
  // We are not consuming master_command from master as long as ~ce_reception_ready
  assign ce_reception_ready = (fifo_cerx_cnt == 0) & fifo_cerx_in_rdy & ~|axi4_write_pc;

  assign cerx_handshake = fifo_cerx_out_vld & fifo_cerx_out_rdy & ~abort_transfer;

  // =========================================================================================== //
  // Write into HBM
  // all @mrmac domain
  // * must write into each PC one at a time (-> must use little resource as possible)
  // * takes into account the HBM page so we are always aligned
  // * we must assert a write at each received valid (through seq_num) packets
  //
  // Once full ciphertext is written into memory, we forward relevant info to regif & raise itr
  // =========================================================================================== //
  // Pre-Processing -------------------------------------------------------------------------------
  command_t received_cmd;

  always_ff @(posedge clk_mhdma)
    if (decoded_command_rdy & decoded_command_vld)
      received_cmd <= decoded_command;

  // Computing physical address =>  hbm_pc_offset + ctId * CT_MEM_BYTES
  logic [ETH_PC-1:0][AXI4_ADD_W-1:0] phy_addr;
  logic                              dst_addr_valid;
  logic                              phy_addr_valid;

  always_ff @(posedge clk_mhdma)
    dst_addr_valid <= (decoded_command_rdy & decoded_command_vld) & (decoded_command.req_id == REQ_ID_EMISSION) & (decoded_command.seq_num == 0);

  always_ff @(posedge clk_mhdma)
    phy_addr_valid <= dst_addr_valid;

  generate
    for (genvar gen_p=0; gen_p<ETH_PC; gen_p=gen_p+1)
      always_ff @(posedge clk_mhdma)
        if (dst_addr_valid)
          phy_addr[gen_p] <= regf_ct_mem_addr[gen_p] + received_cmd.dst_addr * CT_MEM_BYTES;
  endgenerate

  // word distribution per PC ---------------------------------------------------------------------
  logic [ETH_PC-1:0] pc_transfer_done;  // level: per-PC B responses all received
  logic              pc_w_complete;     // pulse: single FSM W-data done for current PC
  logic [ETH_PC-1:0] write_error;

  // Shift to next PC when all W-data sent. B responses are tracked per-port independently.
  // axi4_write_pc is basically a one hot that initialises when address is valid and shifts when pc is write complete
  always_ff @(posedge clk_mhdma) begin : prc_write_pc_one_at_a_time
    if (~resetn_mhdma) begin
      axi4_write_pc <= 'h0;
    end else begin
      if (phy_addr_valid) begin
        axi4_write_pc <= {{(ETH_PC-1){1'b0}}, 1'b1};
      end else if (pc_w_complete & axi4_write_pc[ETH_PC-1]) begin
        axi4_write_pc <= 'h0;
      end else if (pc_w_complete) begin
        axi4_write_pc <= axi4_write_pc << 1;
      end
    end
  end

  // =========================================================================================== //
  // Deserialization of MRMAC_AXIS_W words to AXI4_DATA_W with backpressure
  // =========================================================================================== //
  logic [$clog2(NB_MRMAC_WORDS_PER_WRITE)-1:0] deser_cnt;
  logic [AXI4_DATA_W-1:0]                       deser_word;
  logic                                         deser_vld;
  logic [AXI4_DATA_W-1:0]                       deser_data;
  logic                                         deser_rdy;   // from elastic buffer

  // Combinational assembly: splice live FIFO data into last slice position,
  // bypassing the deser_word register to eliminate the 1-cycle settling delay.
  logic                   deser_last_beat;
  logic [AXI4_DATA_W-1:0] deser_word_next;

  assign deser_last_beat = cerx_handshake & (deser_cnt == NB_MRMAC_WORDS_PER_WRITE - 1);

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      deser_cnt <= 'h0;
    end else begin
      if (abort_transfer) begin
        deser_cnt <= 'h0;
      end else if (cerx_handshake & (deser_cnt == NB_MRMAC_WORDS_PER_WRITE - 1)) begin
        deser_cnt <= 'h0;
      end else if (cerx_handshake) begin
        deser_cnt <= deser_cnt + 1;
      end
    end
  end

  always_ff @(posedge clk_mhdma)
    if (cerx_handshake)
      deser_word[deser_cnt*MRMAC_AXIS_W+:MRMAC_AXIS_W] <= fifo_cerx_out_data;

  // deser_word_next is only here to avoid one clock cycle bubble :
  // It takes combinationally the register "deser_word" but updates previous word space (deser_cnt*MRMAC_AXIS_W +: MRMAC_AXIS_W).
  // When deser_last_beat we skip the register and instead we take deser_word_next wit all AXI4_DATA_W/MRMAC_AXIS_W words
  always_comb begin
    deser_word_next = deser_word;
    deser_word_next[deser_cnt*MRMAC_AXIS_W +: MRMAC_AXIS_W] = fifo_cerx_out_data;
  end

  always_ff @(posedge clk_mhdma) begin
    if (deser_last_beat) begin
      deser_data <= deser_word_next;
    end
  end

  // Holding assembled word until elastic buffer accepts it
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      deser_vld <= 1'b0;
    end else if (deser_vld & deser_rdy) begin
      deser_vld <= deser_last_beat;
    end else if (deser_last_beat) begin
      deser_vld <= 1'b1;
    end
  end

  assign fifo_cerx_out_rdy = ~abort_transfer & (~deser_vld | deser_rdy) & |axi4_write_pc;

  // =========================================================================================== //
  // Elastic buffer (shared across PCs, depth=2)
  // Absorbs inter-burst gaps during BURST_AW transitions
  // =========================================================================================== //
  logic [AXI4_DATA_W-1:0] w_buf_data;
  logic                   w_buf_vld;
  logic                   w_buf_rdy;
  // w_buf_rdy assigned after burst FSM declarations (see Data channel section)

  fifo_element #(
    .WIDTH         (AXI4_DATA_W ),
    .DEPTH         (2           ),
    .TYPE_ARRAY    ({4'h1, 4'h2}),
    .DO_RESET_DATA (0           ),
    .RESET_DATA_VAL(0           )
  ) deser_elastic_buf (
    .clk           (clk_mhdma   ),
    .s_rst_n       (resetn_mhdma),

    .in_data       (deser_data  ),
    .in_vld        (deser_vld & ~abort_transfer),
    .in_rdy        (deser_rdy   ),

    .out_data      (w_buf_data  ),
    .out_vld       (w_buf_vld   ),
    .out_rdy       (w_buf_rdy   )
  );

  // =========================================================================================== //
  // Burst state machine (single instance, PCs processed sequentially)
  // =========================================================================================== //
  // Active PC index: one-hot to binary (generate-based OR reduction)
  logic [ETH_PC_W-1:0] active_pc_idx;

  generate
    for (genvar gen_b = 0; gen_b < ETH_PC_W; gen_b++) begin : gen_oh2bin
      logic [ETH_PC-1:0] oh_sel;
      for (genvar gen_j = 0; gen_j < ETH_PC; gen_j++) begin : gen_oh_sel
        assign oh_sel[gen_j] = axi4_write_pc[gen_j] & gen_j[gen_b];
      end
      assign active_pc_idx[gen_b] = |oh_sel;
    end
  endgenerate

  // PC-specific word count (PC0 has +1 header word)
  logic [AXI4_WORD_PER_PC0_WW-1:0] active_words_per_pc;
  assign active_words_per_pc = (active_pc_idx == 0) ? AXI4_WORD_PER_PC0_WW'(AXI4_WORD_PER_PC0) : AXI4_WORD_PER_PC0_WW'(AXI4_WORD_PER_PC);

  // PC base offset for credit computation
  logic [NB_WORDS_TOTAL_WW-1:0] active_pc_base_offset;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      active_pc_base_offset <= '0;
    end else if (phy_addr_valid) begin
      active_pc_base_offset <= '0;
    end else if (pc_w_complete) begin
      active_pc_base_offset <= active_pc_base_offset + NB_WORDS_TOTAL_WW'(active_words_per_pc);
    end
  end

  // ======================================================================================= //
  // Credit-based burst length computation
  // ======================================================================================= //
  // Burst FSM state (next section)
  logic [AXI4_ADD_W-1:0]           burst_addr;
  logic [AXI4_WORD_PER_PC0_WW-1:0] words_remain;
  // Burst FSM must not issue AXI writes for data that has not yet been received from the
  // network. To enforce this, a credit counter tracks how many AXI words are "authorized" to
  // be written, based on validated packet arrivals:

  // Credit accumulator ---------------------------------------------------------------------------
  //  authorized_axi4_words: running total AXI words we are allowed to write (across all PCs).
  //    Incremented each time a packet's sequence number is validated.
  logic [NB_WORDS_TOTAL_WW-1:0]    authorized_axi4_words;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      authorized_axi4_words <= '0;
    end else begin
      if (start_read_request) begin
        authorized_axi4_words <= '0;
      end else if (seq_num_valid & ~seq_num_mismatch) begin
        if (expected_seq_num < NB_PACKETS_FULL) begin
          authorized_axi4_words <= authorized_axi4_words + NB_WORDS_TOTAL_WW'(AXI4_WORDS_PER_FULL_PKT);
        end else begin
          authorized_axi4_words <= authorized_axi4_words + NB_WORDS_TOTAL_WW'(AXI4_WORDS_PER_LAST_PKT);
        end
      end
    end
  end

  // Credit computation ---------------------------------------------------------------------------
  //  pc_consumed_total: how many of those authorized words, burst FSM has already consumed
  logic [NB_WORDS_TOTAL_WW-1:0] pc_consumed_total;
  logic [NB_WORDS_TOTAL_WW-1:0] words_committed;

  assign words_committed   = NB_WORDS_TOTAL_WW'(active_words_per_pc) - NB_WORDS_TOTAL_WW'(words_remain);

  // active_pc_base_offset (words for all completed PCs) + words_committed (words issued so far within the active PC)
  assign pc_consumed_total = active_pc_base_offset + words_committed;

  //  pc_credits : The number of additional words the FSM is allowed to burst right now.
  logic [NB_WORDS_TOTAL_WW-1:0] pc_credits;

  assign pc_credits = (authorized_axi4_words > pc_consumed_total) ? (authorized_axi4_words - pc_consumed_total) : '0;

  // Page-aligned burst length --------------------------------------------------------------------
  //  computed_burst_len: the burst length limited to the current 4 KB page boundary.
  logic [AXI4_LEN_W:0]      computed_burst_len;
  logic [PAGE_BYTES_WW-1:0] page_word_remain;

  assign page_word_remain   = PAGE_AXI4_DATA - burst_addr[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
  assign computed_burst_len = (page_word_remain < words_remain) ? page_word_remain : words_remain;

  // Credit-clamped burst length ------------------------------------------------------------------
  //  Final burst length = min(computed_burst_len, pc_credits).
  //  Ensures we never issue a burst larger than the data currently received from the network.
  //  If pc_credits == 0 (no data available yet), effective_burst_len_r == 0, which deasserts
  //  awvalid and stalls the burst FSM in BURST_AW until more packets arrive.
  logic [AXI4_LEN_W:0] effective_burst_len;
  logic [AXI4_LEN_W:0] effective_burst_len_r;

  assign effective_burst_len = (NB_WORDS_TOTAL_WW'(computed_burst_len) <= pc_credits) ? computed_burst_len : (AXI4_LEN_W+1)'(pc_credits);

  // Pipeline register: breaks the combinational chain before FSM
  //   burst_addr -> page_word_remain -> computed_burst_len -> effective_burst_len
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      effective_burst_len_r <= 'h0;
    end else begin
      effective_burst_len_r <= effective_burst_len;
    end
  end

  // ======================================================================================= //
  // Burst FSM
  // ======================================================================================= //
  logic [AXI4_LEN_W:0]            burst_word_cnt; // number of words in current burst
  logic [AXI4_LEN_W:0]            burst_beat_cnt;
  logic [AXI_BURST_NB_MAX_WW-1:0] bursts_issued;
  logic                           abort_draining;

  typedef enum logic [1:0] {
    BURST_XXX    = 'x,
    BURST_IDLE   = 2'b00,
    BURST_AW     = 2'b01,
    BURST_W_DATA = 2'b10,
    BURST_DONE   = 2'b11
  } st_burst;

  st_burst burst_state;
  st_burst burst_next_state;

  // AXI channel signals
  axi4_aw_if_t axi_a;
  logic        axi_a_awvalid;
  logic        axi_a_awready;

  axi4_w_if_t  axi_w;
  logic        axi_wvalid;
  logic        axi_wready;

  logic        w_send_data;
  logic        wlast;

  assign w_send_data = axi_wvalid & axi_wready;
  assign wlast       = (burst_word_cnt != 0) & (burst_beat_cnt == burst_word_cnt - 1);

  // pc_w_complete: when we are leaving BURST_DONE state (W FIFO is guaranteed to be drained)
  logic in_burst_done;
  logic in_burst_done_r;

  assign in_burst_done = (burst_state == BURST_DONE);

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      in_burst_done_r <= 1'b0;
    end else begin
      in_burst_done_r <= in_burst_done;
    end
  end

  assign pc_w_complete = ~in_burst_done & in_burst_done_r;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      burst_state <= BURST_IDLE;
    end else begin
      burst_state <= burst_next_state;
    end
  end

  logic m_axi4_wvalid_single;
  logic m_axi4_awvalid_single;

  always_comb begin
    burst_next_state = BURST_XXX;
    case (burst_state)
      BURST_IDLE:
        // Gate with ~pc_w_complete: on the cycle pc_w_complete fires, axi4_write_pc is shifting.
        // Wait one cycle for the new PC index to settle before capturing parameters.
        burst_next_state = (|axi4_write_pc & ~pc_w_complete) ? (abort_transfer ? BURST_DONE : BURST_AW) : BURST_IDLE;
      BURST_AW:
        burst_next_state = (axi_a_awvalid & axi_a_awready) ? BURST_W_DATA : abort_transfer ? BURST_DONE : BURST_AW;
      BURST_W_DATA:
        burst_next_state = (w_send_data & wlast) ? ((abort_draining | words_remain == 0) ? BURST_DONE : BURST_AW) : BURST_W_DATA;
      BURST_DONE:
        // Wait for both AW and W FIFOs to drain before shifting PC (prevents stale AW on next port)
        burst_next_state = (~m_axi4_wvalid_single & ~m_axi4_awvalid_single) ? BURST_IDLE : BURST_DONE;
      default : burst_next_state = BURST_IDLE;
    endcase
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      burst_addr     <= 'h0;
      burst_word_cnt <= 'h0;
      words_remain   <= 'h0;
      burst_beat_cnt <= 'h0;
      bursts_issued  <= 'h0;
      abort_draining <= 1'b0;
    end else begin
      case (burst_state)
        BURST_IDLE: begin
          abort_draining <= 1'b0;
          if (|axi4_write_pc & ~pc_w_complete) begin
            burst_addr    <= phy_addr[active_pc_idx];
            words_remain  <= AXI4_WORD_PER_PC0_WW'(active_words_per_pc);
            bursts_issued <= 'h0;
          end
        end

        BURST_AW: begin
          if (axi_a_awvalid & axi_a_awready) begin
            burst_word_cnt <= effective_burst_len_r;
            burst_beat_cnt <= 'h0;
            bursts_issued  <= bursts_issued + 1;
            words_remain   <= words_remain - effective_burst_len_r;
          end
        end

        BURST_W_DATA: begin
          if (abort_transfer & ~abort_draining) begin
            abort_draining <= 1'b1;
          end

          if (w_send_data) begin
            burst_beat_cnt <= burst_beat_cnt + 1;
            if (wlast & ~abort_draining & words_remain > 0) begin
              burst_addr <= burst_addr + (AXI4_ADD_W'(burst_word_cnt) << AXI4_DATA_BYTES_W);
            end
          end
        end

        BURST_DONE: begin
          // nothing: single-cycle, transitions to BURST_IDLE next
        end
      endcase
    end
  end

  // ======================================================================================= //
  // Save bursts_issued per PC on W-data completion (for per-port B-response tracking)
  // ======================================================================================= //
  logic [ETH_PC-1:0][AXI_BURST_NB_MAX_WW-1:0] saved_bursts_issued;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      saved_bursts_issued <= '0;
    end else if (start_read_request) begin
      saved_bursts_issued <= '0;
    end else if (pc_w_complete) begin
      saved_bursts_issued[active_pc_idx] <= bursts_issued;
    end
  end

  // ======================================================================================= //
  // Address channel (single instance, demuxed to active port)
  // ======================================================================================= //
  axi4_aw_if_t m_axi4_aw_single;

  // Suppress awvalid on the first cycle of BURST_AW: effective_burst_len_r is registered and lags by one cycle.
  logic burst_aw_entry;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      burst_aw_entry <= 1'b0;
    end else begin
      burst_aw_entry <= (burst_state != BURST_AW) & (burst_next_state == BURST_AW);
    end
  end

  assign axi_a_awvalid = (burst_state == BURST_AW) & (effective_burst_len_r > 0) & ~abort_transfer & ~burst_aw_entry;
  assign axi_a.awid    = MHDMA_AXI_ARID;
  assign axi_a.awaddr  = burst_addr;
  assign axi_a.awsize  = MHDMA_ARSIZE;
  assign axi_a.awburst = AXI4B_INCR;
  assign axi_a.awlen   = effective_burst_len_r - 1;

  fifo_element #(
    .WIDTH          ($bits(axi4_aw_if_t)),
    .DEPTH          (1                  ),
    .TYPE_ARRAY     (4'h3               ),
    .DO_RESET_DATA  (1'b0               ),
    .RESET_DATA_VAL (0                  )
  ) fifo_element_awrite (
    .clk     (clk_mhdma                        ),
    .s_rst_n (resetn_mhdma                     ),

    .in_data (axi_a                            ),
    .in_vld  (axi_a_awvalid                    ),
    .in_rdy  (axi_a_awready                    ),

    .out_data(m_axi4_aw_single                 ),
    .out_vld (m_axi4_awvalid_single            ),
    .out_rdy (|(m_axi4_awready & axi4_write_pc))
  );

  // Demux AW to active port
  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_aw_demux
      assign m_axi4_awid[gen_i]    = m_axi4_aw_single.awid;
      assign m_axi4_awaddr[gen_i]  = m_axi4_aw_single.awaddr;
      assign m_axi4_awlen[gen_i]   = m_axi4_aw_single.awlen;
      assign m_axi4_awsize[gen_i]  = m_axi4_aw_single.awsize;
      assign m_axi4_awburst[gen_i] = m_axi4_aw_single.awburst;
      assign m_axi4_awvalid[gen_i] = m_axi4_awvalid_single & axi4_write_pc[gen_i];
    end
  endgenerate

  // ======================================================================================= //
  // Data channel (single instance, demuxed to active port)
  // ======================================================================================= //
  // Elastic buffer consumption: driven by single burst FSM
  assign w_buf_rdy   = (axi_wready & (burst_state == BURST_W_DATA) & |axi4_write_pc & ~abort_draining) | abort_transfer;
  assign axi_wvalid  = (burst_state == BURST_W_DATA) & (abort_draining | (w_buf_vld & |axi4_write_pc));
  assign axi_w.wdata = abort_draining ? 'h0 : w_buf_data;
  assign axi_w.wlast = wlast;
  assign axi_w.wstrb = abort_draining ? 'h0 : {AXI4_STRB_W{1'b1}};

  axi4_w_if_t m_axi4_w_single;

  fifo_element #(
    .WIDTH         (AXI4_W_IF_W ),
    .DEPTH         (2            ),
    .TYPE_ARRAY    ({4'h1, 4'h2} ),
    .DO_RESET_DATA (0            ),
    .RESET_DATA_VAL(0            )
  ) fifo_element_write (
    .clk     (clk_mhdma                       ),
    .s_rst_n (resetn_mhdma                    ),

    .in_data (axi_w                           ),
    .in_vld  (axi_wvalid                      ),
    .in_rdy  (axi_wready                      ),

    .out_data(m_axi4_w_single                 ),
    .out_vld (m_axi4_wvalid_single            ),
    .out_rdy (|(m_axi4_wready & axi4_write_pc))
  );

  // Demux W to active port
  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_w_demux
      assign m_axi4_wdata[gen_i]  = m_axi4_w_single.wdata;
      assign m_axi4_wstrb[gen_i]  = m_axi4_w_single.wstrb;
      assign m_axi4_wlast[gen_i]  = m_axi4_w_single.wlast;
      assign m_axi4_wvalid[gen_i] = m_axi4_wvalid_single & axi4_write_pc[gen_i];
    end
  endgenerate

  // ======================================================================================= //
  // Per-port B-response tracking (no FIFO, always accept)
  // * we do this in order to not wait for each B response before sending next write
  // ======================================================================================= //
  logic [ETH_PC-1:0]                           pc_w_done;
  logic [ETH_PC-1:0][AXI_BURST_NB_MAX_WW-1:0]  brsp_cnt;

  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_b_track
      // Always accept B responses (no backpressure)
      assign m_axi4_bready[gen_i] = 1'b1;

      // Per-port B-response counter
      always_ff @(posedge clk_mhdma) begin
        if (~resetn_mhdma) begin
          brsp_cnt[gen_i] <= '0;
        end else if (start_read_request) begin
          brsp_cnt[gen_i] <= '0;
        end else if (m_axi4_bvalid[gen_i]) begin
          brsp_cnt[gen_i] <= brsp_cnt[gen_i] + 1;
        end
      end

      // Sticky flag: W-data sent for this PC
      always_ff @(posedge clk_mhdma) begin
        if (~resetn_mhdma) begin
          pc_w_done[gen_i] <= 1'b0;
        end else if (start_read_request) begin
          pc_w_done[gen_i] <= 1'b0;
        end else if (pc_w_complete & axi4_write_pc[gen_i]) begin
          pc_w_done[gen_i] <= 1'b1;
        end
      end

      // Per-PC transfer done: all W beats sent AND all B responses received
      assign pc_transfer_done[gen_i] = pc_w_done[gen_i] & (saved_bursts_issued[gen_i] == brsp_cnt[gen_i]);

      // Write error tracking (sticky per-PC, clearable by rst_errors)
      always_ff @(posedge clk_mhdma) begin
        if (~resetn_mhdma) begin
          write_error[gen_i] <= 1'b0;
        end else begin
          if (rst_errors) begin
            write_error[gen_i] <= 1'b0;
          end else if (m_axi4_bvalid[gen_i]) begin
            case (m_axi4_bresp[gen_i])
              AXI4_SLVERR: write_error[gen_i] <= 1'b1;
              AXI4_DECERR: write_error[gen_i] <= 1'b1;
              default:; // two others are ignored : we want sticky errors
            endcase
          end
        end
      end
    end
  endgenerate

  // Interrupt generation -------------------------------------------------------------------------
  // pc_transfer_done[i] is a level (stays high once B responses match).
  // Rising-edge detect to produce a single-cycle pulse for ciphertext_received.
  logic all_pc_done;
  logic all_pc_done_r;

  assign all_pc_done = &pc_transfer_done & (~abort_transfer | fifo_cerx_cnt == 0);

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      all_pc_done_r <= 1'b0;
    end else begin
      all_pc_done_r <= all_pc_done;
    end
  end

  assign ciphertext_received = all_pc_done & ~all_pc_done_r;

  // regf payload information ---------------------------------------------------------------------
  logic [2*REG_DATA_W-1:0] rr_regf_in_data;
  logic                    rr_regf_in_vld;

  logic [2*REG_DATA_W-1:0] rr_regf_out_data;
  logic                    rr_regf_out_vld;
  logic                    rr_regf_out_rdy;

  assign rr_regf_in_data = {received_cmd.iop_id, received_cmd.req_id, received_cmd.hpu_id, received_cmd.mode, received_cmd.flag, received_cmd.rsvd, received_cmd.dst_addr, received_cmd.src_addr};

  // Interrupt must be triggered only when ciphertext is valid
  assign rr_regf_in_vld = valid_ciphertext_received;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak these parameters in package
    .WIDTH           (2*REG_DATA_W),
    .DEPTH           (REQ_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(REQ_MEMORY_TYPE)
  ) rr_resp_ram_rdy_vld_2clk (
    // Write Domain ports: MRMAC domain
    .in_clk      (clk_mhdma),
    .in_rstn     (resetn_mhdma),
    .in_data     (rr_regf_in_data),
    .in_rdy      (rr_regf_in_rdy),
    .in_vld      (rr_regf_in_vld),
    .almost_full (/* UNUSED */),
    // Read Domain ports: CFG domain
    .out_clk     (clk_mhdma_cfg),
    .out_rstn    (resetn_mhdma_cfg),
    .out_data    (rr_regf_out_data),
    .out_rdy     (rr_regf_out_rdy),
    .out_vld     (rr_regf_out_vld)
  );

  assign rr_regf_out_rdy = clear_interrupt_rr;

  // upper word = req_id register, lower word = addr register
  assign regf_read_req_id = rr_regf_out_data[2*REG_DATA_W-1:REG_DATA_W];
  assign regf_read_addr = rr_regf_out_data[REG_DATA_W-1:0];
  assign interrupt_read_request = rr_regf_out_vld;

  // =========================================================================================== //
  // Errors
  // =========================================================================================== //
  logic seq_num_error;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
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

  // Counters -------------------------------------------------------------------------------------
  logic [NUM_STAT_CNTS-1:0][REG_DATA_W-1:0] stat_cnt;
  logic [NUM_STAT_CNTS-1:0]                 stat_cnt_inc;
  logic [NUM_STAT_CNTS-1:0]                 stat_cnt_rst;

  logic [REG_DATA_W-1:0] t_notify_to_ack;
  logic [REG_DATA_W-1:0] t_rr_to_ce_received;
  logic [REG_DATA_W-1:0] nb_write_complete_cnt;

  assign stat_cnt_inc = {
    timeout_reached_read_request | retry_seq_num,
    timeout_reached_notify,
    notify_ack_received,
    notify_sent
  };

  assign stat_cnt_rst = {
    stat_rst.cnt_read_req_retry,
    stat_rst.cnt_notify_retry,
    stat_rst.cnt_notify_ack,
    stat_rst.cnt_notify
  };

  generate
    for (genvar gen_i = 0; gen_i < NUM_STAT_CNTS; gen_i++) begin : gen_stat_cnt
      always_ff @(posedge clk_mhdma) begin
        if (~resetn_mhdma) begin
          stat_cnt[gen_i] <= 'h0;
        end else if (stat_cnt_rst[gen_i]) begin
          stat_cnt[gen_i] <= 'h0;
        end else if (stat_cnt_inc[gen_i]) begin
          stat_cnt[gen_i] <= stat_cnt[gen_i] + 1;
        end
      end
    end
  endgenerate

  // Timing measurements --------------------------------------------------------------------------
  // timing counter : counter between notify sent from this HPU (on tlast) and ack reception (2nd frame of the header)
  logic count_notify_ack;
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      count_notify_ack <= 1'b0;
    end else begin
      if (notify_sent) begin
        count_notify_ack <= 1'b1;
      end else if (notify_ack_received) begin
        count_notify_ack <= 1'b0;
      end
    end
  end

  // timing counter : counter between start and end of read request
  logic count_rreq_receive;
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      count_rreq_receive <= 1'b0;
    end else begin
      if (start_read_request) begin
        count_rreq_receive <= 1'b1;
      end else if (ciphertext_received) begin
        count_rreq_receive <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      t_notify_to_ack <= 'h0;
    end else begin
      if (count_notify_ack) begin
        t_notify_to_ack <= t_notify_to_ack + 1;
      end else begin
        t_notify_to_ack <= 'h0;
      end
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      t_rr_to_ce_received <= 'h0;
    end else begin
       if(count_rreq_receive) begin
        t_rr_to_ce_received <= t_rr_to_ce_received + 1;
       end else begin
        t_rr_to_ce_received <= 'h0;
       end
    end
  end

  logic [REG_DATA_W-1:0] stat_t_notify_to_ack_r;
  logic [REG_DATA_W-1:0] stat_t_rr_to_ce_received_r;
  logic [REG_DATA_W-1:0] stat_nb_ce_words_received_r;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      stat_t_notify_to_ack_r <= 'h0;
    end else begin
      if (notify_ack_received) begin
        stat_t_notify_to_ack_r <= t_notify_to_ack;
      end
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      stat_t_rr_to_ce_received_r <= 'h0;
    end else begin
      if (ciphertext_received) begin
        stat_t_rr_to_ce_received_r <= t_rr_to_ce_received;
      end
    end
  end

  logic [REG_DATA_W-1:0] t_notify_to_ack_max;
  logic [REG_DATA_W-1:0] t_rr_to_ce_received_max;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      t_notify_to_ack_max <= 'h0;
    end else begin
      if (notify_ack_received) begin
        t_notify_to_ack_max <= (t_notify_to_ack_max<t_notify_to_ack) ? t_notify_to_ack : t_notify_to_ack_max;
      end
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      t_rr_to_ce_received_max <= 'h0;
    end else begin
      if (ciphertext_received) begin
        t_rr_to_ce_received_max <= (t_rr_to_ce_received_max<t_rr_to_ce_received) ? t_rr_to_ce_received : t_rr_to_ce_received_max;
      end
    end
  end

  // Debug registers ------------------------------------------------------------------------------
  logic [CE_DATA_COUNT_W:0] fifo_cerx_cnt_tx;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      fifo_cerx_cnt_tx <= 'h0;
    end else begin
      if (fifo_cerx_out_vld & fifo_cerx_out_rdy) begin
        fifo_cerx_cnt_tx <= fifo_cerx_cnt_tx +1;
      end else if (ciphertext_received) begin
        fifo_cerx_cnt_tx <= 'h0;
      end
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
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

  // Rising-edge detect: pc_transfer_done is a level, count only once per transfer
  logic [ETH_PC-1:0] pc_transfer_done_r;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      pc_transfer_done_r <= '0;
    end else begin
      pc_transfer_done_r <= pc_transfer_done;
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      nb_write_complete_cnt <= 'h0;
    end else begin
      if (|(pc_transfer_done & ~pc_transfer_done_r)) begin
        nb_write_complete_cnt <= nb_write_complete_cnt + 1;
      end
    end
  end

  assign stat.fsm_notify            = ntx_state;
  assign stat.fsm_read_req          = rreq_state;
  assign stat.fsm_burst             = burst_state;
  assign stat.cnt_notify            = stat_cnt[0];
  assign stat.cnt_notify_ack        = stat_cnt[1];
  assign stat.cnt_notify_retries    = stat_cnt[2];
  assign stat.cnt_read_req_retries  = stat_cnt[3];
  assign stat.cnt_notify_timeout    = to_notify_cnt;
  assign stat.nb_write_complete_cnt = nb_write_complete_cnt;
  assign stat.t_notify_to_ack           = stat_t_notify_to_ack_r;
  assign stat.t_notify_to_ack_max       = t_notify_to_ack_max;
  assign stat.t_rr_to_ce_received       = stat_t_rr_to_ce_received_r;
  assign stat.t_rr_to_ce_received_max   = t_rr_to_ce_received_max;
  assign stat.nb_ce_words_received  = stat_nb_ce_words_received_r;

endmodule
