// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA Master module
// ----------------------------------------------------------------------------------------------
// Receives requests from RPU and address them
//
// This module must be able to send Notify and Read Request to formatter
// ==============================================================================================

module mhdma_master
  import mhdma_pkg::*;               // for all mhdma modules
  import axi_if_eth_axi_pkg::*;      // AXI4
  import axi_if_shell_axil_pkg::*;   // REG_DATA_W
  import axi_if_common_param_pkg::*; // HBM page
#(
  parameter int   CDC_SYNC_STAGES = 2,
  parameter int   MAX_BURST_SIZE  = PAGE_BYTES/AXI4_DATA_BYTES,
  parameter [3:0] PC_STRIDE       = 'hB,
  // must not add default values to theses parameters, coming from bridge module
  parameter int   PC_NB_WORDS  [ETH_PC],
  parameter int   PC_REMAINS   [ETH_PC],
  parameter int   PC_NB_WRITES [ETH_PC]
) (
  // Ethernet configuration interface -----------------------------------------
  input  logic                                clk_cfg,
  input  logic                                resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                clk_mrmac,
  input  logic                                resetn_mrmac,
  // regf interface -----------------------------------------------------------
  input  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr,
  input  logic               [REG_DATA_W-1:0] regf_req_id,
  input  logic               [REG_DATA_W-1:0] regf_req_addr,
  output logic               [REG_DATA_W-1:0] regf_read_payload,
  input  logic               [REG_DATA_W-1:0] regf_timeout_duration_notify,
  input  logic               [REG_DATA_W-1:0] regf_timeout_duration_read_req,
  // register control --------------------------------------------------------
  input  logic                                received_req,
  output logic                                request_consumed,
  // Flags -------------------------------------------------------------------
  input  logic                                read_request_allowed,
  input  logic                                notify_request_allowed,

  output logic                                new_read_request_pending,
  output logic                                new_notify_request_pending,

  input  logic                                notify_ack_received,

  output logic                                packets_received,
  // formatter interface ------------------------------------------------------
  output header_t                             format_header,
  output logic                                format_retry_notify,
  output logic                                format_retry_read_request,
  input  logic                                format_notify_sent,
  input  logic                                format_rreq_sent,
  // ciphertext payload -------------------------------------------------------
  input  logic             [MRMAC_AXIS_W-1:0] rx_tdata,
  input  logic                                rx_tvalid,
  input  logic                                rx_tlast,
  output logic                                cerx_reception_ready,
  // Received header ----------------------------------------------------------
  input  header_t                             decoded_header,
  // statistics ---------------------------------------------------------------
  // counters
  output logic [REG_DATA_W-1:0]               stat_cnt_notify,
  output logic [REG_DATA_W-1:0]               stat_cnt_notify_ack,
  output logic [REG_DATA_W-1:0]               stat_cnt_notify_retries,
  output logic [REG_DATA_W-1:0]               stat_cnt_notify_timeout,
  output logic [REG_DATA_W-1:0]               stat_nb_ce_words_received,
  // timing
  output logic [REG_DATA_W-1:0]               stat_t_notify_to_ack,
  output logic [REG_DATA_W-1:0]               stat_t_rr_to_ce_received,
  // resets
  input  logic                                rst_cnt_notify,
  input  logic                                rst_cnt_notify_ack,
  input  logic                                rst_cnt_timeout, //unused
  input  logic                                rst_cnt_notify_retry,
  input  logic                                rst_nb_ce_words_received,
  // register
  output logic [1:0]                          stat_fsm_notify,
  output logic [1:0]                          stat_fsm_read_req,
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
  // interrupt ---------------------------------------------------------------
  input  logic                                clear_interrupt_rr,
  output logic                                interrupt_read_request,
  // error --------------------------------------------------------------------
  output error_packet_id_mismatch
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam NB_MRMRAC_WORDS_PER_WRITE = AXI4_DATA_W/MRMAC_AXIS_W;

  // TODO only two PC toreview
  localparam NB_WORDS_TOTAL = PC_NB_WORDS[0] + PC_NB_WORDS[1];
  localparam NB_WORDS_TO_HBM = (NB_WORDS_TOTAL*AXI4_DATA_W)/MRMAC_AXIS_W;

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
  assign rrqq_in_data = (rrqq_in_vld & rrqq_in_rdy) ? {regf_req_id, regf_req_addr} : rrqq_data_kept;

  // === MRMAC domain
  logic [2*REG_DATA_W-1:0] rrqq_out_data;
  logic                    rrqq_out_rdy;
  logic                    rrqq_out_vld;

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
    .in_vld      (rrqq_in_vld),
    .almost_full (/* UNUSED */),
    // MRMAC domain
    .out_clk     (clk_mrmac),
    .out_rstn    (resetn_mrmac),
    .out_data    (rrqq_out_data),
    .out_rdy     (rrqq_out_rdy),
    .out_vld     (rrqq_out_vld)
  );

  assign new_read_request_pending = rrqq_out_vld;

  logic read_request_allowed_reg;

  always_ff @(posedge clk_mrmac)
    read_request_allowed_reg <= read_request_allowed;

  // ready is valid only when we see a rising edge on an allowed read request.
  assign rrqq_out_rdy = read_request_allowed & ~read_request_allowed_reg;

  // current read request, sampled when valid is toggled
  logic [DST_ADDR_W-1:0] rrqq_dst_addr;
  logic [SRC_ADDR_W-1:0] rrqq_src_addr;
  logic [  SIZE_B_W-1:0] rrqq_size_b;
  logic [  REQ_ID_W-1:0] rrqq_req_id;
  logic [  IOP_ID_W-1:0] rrqq_iop_id;
  logic [  HPU_ID_W-1:0] rrqq_hpu_id;
  logic                  rrqq_vld;

  always_ff @(posedge clk_mrmac) begin : read_request_sampling
    if (rrqq_out_rdy & rrqq_out_vld) begin
      rrqq_src_addr <= rrqq_out_data[CMD_SRC_ADDR_OFS-1:0];
      rrqq_dst_addr <= rrqq_out_data[CMD_DST_ADDR_OFS-1:CMD_SRC_ADDR_OFS];
      rrqq_size_b   <= rrqq_out_data[CMD_SIZE_B_OFS-1:CMD_DST_ADDR_OFS];
      rrqq_hpu_id   <= rrqq_out_data[CMD_HPU_ID_OFS-1:CMD_SIZE_B_OFS];
      rrqq_req_id   <= rrqq_out_data[CMD_REQ_ID_OFS-1:CMD_HPU_ID_OFS];
      rrqq_iop_id   <= rrqq_out_data[CMD_IOP_ID_OFS-1:CMD_REQ_ID_OFS];
    end
  end

  always_ff @(posedge clk_mrmac)
    rrqq_vld <= rrqq_out_rdy & rrqq_out_vld;

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
  logic [2*REG_DATA_W-1:0] nrqq_out_data;
  logic                    nrqq_out_rdy;
  logic                    nrqq_out_vld;

  // @cfg clock ---------------------------------
  assign nrqq_in_vld = received_req & (regf_req_id[23:20] == REQ_ID_NOTIFY_TX);
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
    .out_data    (nrqq_out_data),
    .out_rdy     (nrqq_out_rdy),
    .out_vld     (nrqq_out_vld)
  );

  assign new_notify_request_pending = nrqq_out_vld;

  // we must consume only one request at a time
  logic notify_request_allowed_reg;
  always_ff @(posedge clk_mrmac)
    notify_request_allowed_reg <= notify_request_allowed;

  assign nrqq_out_rdy = notify_request_allowed & ~notify_request_allowed_reg;

  // current notify request, sampled when valid is toggled
  logic [SRC_ADDR_W-1:0] nrqq_src_addr;
  logic [IOP_ID_W-1:0]   nrqq_iop_id;
  logic [SIZE_B_W-1:0]   nrqq_size_b;
  logic [REQ_ID_W-1:0]   nrqq_req_id;
  logic [HPU_ID_W-1:0]   nrqq_hpu_id;

  // none of theses information are in the first word:
  //  => sampled on the same clock cycle as sending first frame
  always_ff @(posedge clk_mrmac) begin : notify_request_sampling
    if (nrqq_out_rdy & nrqq_out_vld) begin
      nrqq_iop_id    <= nrqq_out_data[CMD_IOP_ID_OFS-1:CMD_REQ_ID_OFS];
      nrqq_req_id    <= nrqq_out_data[CMD_REQ_ID_OFS-1:CMD_HPU_ID_OFS];
      nrqq_hpu_id    <= nrqq_out_data[CMD_HPU_ID_OFS-1:CMD_SIZE_B_OFS];
      nrqq_size_b    <= nrqq_out_data[CMD_SIZE_B_OFS-1:CMD_DST_ADDR_OFS];
      nrqq_src_addr  <= nrqq_out_data[CMD_SRC_ADDR_OFS-1:0];
    end
  end

  logic nrqq_cmd_vld;
  always_ff @(posedge clk_mrmac)
    nrqq_cmd_vld <= nrqq_out_rdy & nrqq_out_vld;

  // Header information ---------------------------------------------------------------------------
  assign format_header.dst_addr = notify_request_allowed ?         'h0   : read_request_allowed ? rrqq_dst_addr : 'h0;
  assign format_header.src_addr = notify_request_allowed ? nrqq_src_addr : read_request_allowed ? rrqq_src_addr : 'h0;
  assign format_header.size_b   = notify_request_allowed ? nrqq_size_b   : read_request_allowed ? rrqq_size_b   : 'h0;
  assign format_header.req_id   = notify_request_allowed ? nrqq_req_id   : read_request_allowed ? rrqq_req_id   : 'h0;
  assign format_header.iop_id   = notify_request_allowed ? nrqq_iop_id   : read_request_allowed ? rrqq_iop_id   : 'h0;
  assign format_header.hpu_id   = notify_request_allowed ? nrqq_hpu_id   : read_request_allowed ? rrqq_hpu_id   : 'h0;

  // valid signal for formatting frames
  assign format_header.valid    = notify_request_allowed ? nrqq_cmd_vld : read_request_allowed ? rrqq_vld : 1'b0;

  // ----------------------------------------------------------------------------------------------
  // when we have the data of both request identifier and addresses, we consume the information
  // > this signal is in configuration clock
  assign request_consumed = (rrqq_data_vld | nrqq_data_vld) ? 1'b1 : 1'b0;

  // ==============================================================================================
  // FSM
  // ==============================================================================================
  logic timeout_reached_notify;
  logic timeout_reached_read_request;

  // Notify TX (NTX) ------------------------------------------------------------------------------
  typedef enum logic [1:0] {
    NTX_XXX          = 'x,
    NTX_WAIT_REQUEST = 2'b01,
    NTX_WAIT_ACK     = 2'b10,
    NTX_SEND_NOTIFY  = 2'b11
  } st_ntx;

  st_ntx ntx_state;
  st_ntx ntx_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) ntx_state <= NTX_WAIT_REQUEST;
    else ntx_state <= ntx_next_state;
  end

  always_comb begin
    ntx_next_state = NTX_XXX;
    case (ntx_state)
      NTX_WAIT_REQUEST:
        ntx_next_state = (new_notify_request_pending & notify_request_allowed) ? NTX_SEND_NOTIFY : NTX_WAIT_REQUEST;
      NTX_SEND_NOTIFY:
        ntx_next_state = format_notify_sent ? NTX_WAIT_ACK : NTX_SEND_NOTIFY;
      NTX_WAIT_ACK:
        // (Assumption) transmission is not instantaneous, notify_ack_received cannot arrive before axis tlast
        ntx_next_state = notify_ack_received ? NTX_WAIT_REQUEST : timeout_reached_notify ? NTX_SEND_NOTIFY : NTX_WAIT_ACK;
    endcase
  end

  // Read request ---------------------------------------------------------------------------------
  typedef enum logic [1:0] {
    RR_XXX          = 'x,
    RR_WAIT_REQUEST = 2'b01,
    RR_SEND_REQUEST = 2'b10,
    RR_WAIT_PACKETS = 2'b11
  } st_read_req;

  st_read_req rreq_state;
  st_read_req rreq_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) rreq_state <= RR_WAIT_REQUEST;
    else rreq_state <= rreq_next_state;
  end

  always_comb begin
    rreq_next_state = RR_XXX;
    case (rreq_state)
      RR_WAIT_REQUEST:
        rreq_next_state = new_read_request_pending ? RR_SEND_REQUEST : RR_WAIT_REQUEST;
      RR_SEND_REQUEST:
        rreq_next_state =  format_rreq_sent ? RR_WAIT_PACKETS : RR_SEND_REQUEST;
      RR_WAIT_PACKETS:
        // if error_packet_id_mismatch or timeout => RR_SEND_REQUEST
        // if write into hbm is finished => RR_WAIT_REQUEST
        rreq_next_state = (error_packet_id_mismatch | timeout_reached_read_request) ? RR_SEND_REQUEST : packets_received? RR_WAIT_REQUEST: RR_WAIT_PACKETS;
    endcase
  end

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

  always_ff @(posedge clk_mrmac)
    format_retry_notify <= timeout_reached_notify;

  // timeout read request -------------------------------------------------------------------------
  logic [REG_DATA_W-1:0] to_read_request_cnt;

  always_ff @(posedge clk_mrmac) begin : timeout_counter_rr
    if (~resetn_mrmac) begin
      to_read_request_cnt <= 'h0;
    end else begin
      if ((rreq_state == RR_WAIT_PACKETS)) begin
        to_read_request_cnt <= to_read_request_cnt + 1;
      end else begin
        to_read_request_cnt <= 'h0;
      end
    end
  end

  assign timeout_reached_read_request = (to_read_request_cnt == to_dur_read_req);

  always_ff @(posedge clk_mrmac)
    format_retry_read_request <= timeout_reached_read_request;

  // TODO:
  assign error_packet_id_mismatch = 1'b0;

  // =========================================================================================== //
  // Ciphertext reception
  //
  // Assumptions:
  // We had previously guaranteed to launch a Read request only and only if fifo is empty and ready
  //
  // Errors:
  // TODO
  // err_ce_rx_unexpected_ct: we should see ciphertext over rx link only read_request_allowed
  // err_ce_rx_too_much_data: we received too much data and tried to overflow the fifo
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
  logic                       cnt_cerx_up;
  logic                       cnt_cerx_down;
  logic                       fifo_pc_backpressure;

  // First thig to do is to be sure that the current values are valid.
  // If we receive more data than what we expect we must invalidate it and not propagate it.
  logic [31:0] ce_valid_cnt; // size is arbitrary toreview
  logic ce_valid;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_valid_cnt <= 'h0;
    end else begin
      if (read_request_allowed & rx_tvalid) begin
        ce_valid_cnt <= ce_valid_cnt + 1;
      end else if (~read_request_allowed | format_retry_read_request) begin
        ce_valid_cnt <= 'h0;
      end
    end
  end

  assign ce_valid = (ce_valid_cnt<NB_WORDS_TO_HBM);

  assign cnt_cerx_up   = read_request_allowed & (fifo_cerx_in_vld & fifo_cerx_in_rdy);
  assign cnt_cerx_down = read_request_allowed & (fifo_cerx_out_rdy & fifo_cerx_out_vld);

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

  assign fifo_cerx_in_vld  = rx_tvalid & ce_valid;
  assign fifo_cerx_in_data = rx_tdata;

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
  assign cerx_reception_ready = (fifo_cerx_cnt == 0) & fifo_cerx_in_rdy;

 // ready signal of sending fifo according to which one we should use
  assign fifo_cerx_out_rdy = fifo_pc_backpressure;

  // =========================================================================================== //
  // Write into HBM
  // all @mrmac domain
  // TODO
  // How much time do we spend between read request and all coefficients arrived & stored ?
  // How much time between read request and first coefficient ?
  // How much time is spent between receiving all words and storing theml in hbm ?
  // =========================================================================================== //

  // Exactly as for RX we write into each PC one at a time
  //  - we have two fifos, one for each PC
  //  - between fifo_ce_rx and fifo_wr_pc we will avoid stalling as much as possible
  //  - we must transmit to regif relevant info and raise interrupt when all words ready in hbm

  // TODO:check use
  // packet pulses
  logic new_pkt_reception;
  logic first_pkt_reception;
  logic last_pkt_reception;

  assign new_pkt_reception = read_request_allowed & decoded_header.valid & (decoded_header.req_id==REQ_ID_EMISSION);

  // because we count seq_num=0 as first packet, last is NB_PACKETS_FULL
  assign first_pkt_reception = new_pkt_reception & (decoded_header.seq_num == 0);
  assign last_pkt_reception  = new_pkt_reception & (decoded_header.seq_num == NB_PACKETS_FULL);

  logic [DST_ADDR_W-1:0] received_dst_addr;
  logic [  IOP_ID_W-1:0] received_iop_id;
  logic [  HPU_ID_W-1:0] received_hpu_id;
  logic                  received_valid;

  always_ff @(posedge clk_mrmac) begin
    if (decoded_header.valid) begin
      received_dst_addr <= decoded_header.dst_addr;
      received_iop_id   <= decoded_header.iop_id;
      received_hpu_id   <= decoded_header.hpu_id;
    end
  end
  always_ff @(posedge clk_mrmac)
    received_valid<=decoded_header.valid;

  // phys_addr = hbm_pc_offset + ctId * ciphertext_size
  logic [ETH_PC-1:0] [AXI4_ADD_W-1:0] phy_addr;
  logic dst_addr_valid;
  logic phy_addr_valid;

  assign dst_addr_valid = received_valid & (decoded_header.req_id == REQ_ID_EMISSION) & (decoded_header.seq_num ==0);

  generate
    for (genvar gen_p=0; gen_p<ETH_PC; gen_p=gen_p+1)
      always_ff @(posedge clk_mrmac)
          if (dst_addr_valid)
            phy_addr[gen_p] <= regf_ct_mem_addr[gen_p] + (received_dst_addr << PC_STRIDE);
  endgenerate

  always_ff @(posedge clk_mrmac)
    phy_addr_valid <= dst_addr_valid;

  // TODO: if seq_num != 0 and  received_dst_addr != previous, raise an error

  logic [ETH_PC-1:0] axi4_write_pc;
  // word distribution to each fifo pc ------------------------------------------------------------
  logic [CE_DATA_COUNT_W:0] fifo_cerx_cnt_tx;
  logic [ETH_PC-1:0]        target_fifo;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      fifo_cerx_cnt_tx <= 'h0;
    end else begin
      if (fifo_cerx_out_vld & fifo_cerx_out_rdy) begin
        fifo_cerx_cnt_tx <= fifo_cerx_cnt_tx +1;
      end else if (packets_received) begin
        fifo_cerx_cnt_tx <= 'h0;
      end
    end
  end

  // which fifo must be filled ?
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      target_fifo <= 2'b00;
    end else begin
      // we target first fifo when we have less than PC_NB_WORDS*NB_MRMRAC_WORDS_PER_WRITE
      // we reset (to fifo 0) when we have the double, note that we could receive more words but they could be invalid
      // this is in case axi data width in not divisible by mrmac data size
      if (fifo_cerx_cnt_tx < NB_MRMRAC_WORDS_PER_WRITE*PC_NB_WORDS[0]) begin
        target_fifo <= 2'b01;
      end else if (fifo_cerx_cnt_tx == NB_MRMRAC_WORDS_PER_WRITE*PC_NB_WORDS[0]) begin
        target_fifo <= 2'b10;
      end
    end
  end

  // launch reads over the two PCs independently one at a time
  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_last_cnt
      logic [$clog2(PC_NB_WRITES[gen_i]):0] pc_last_cnt;
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac)begin
          pc_last_cnt <= 'h0;
        end else begin
          if(m_axi4_wlast[gen_i]) begin
            pc_last_cnt <= pc_last_cnt+1;
          end else if (pc_last_cnt == PC_NB_WRITES[gen_i]) begin
            pc_last_cnt <= 'h0;
          end
        end
      end
    end
  endgenerate

  // when read request registers are ready we can initialize the shift register
  // when we have done all writes on the first PC (the number of lasts matches to expected) we can shift
  // when all writes on the second pc is done we can reset the signal
  always_ff @(posedge clk_mrmac) begin : prc_write_pc_one_at_a_time
    if (~resetn_mrmac) begin
      axi4_write_pc <= 'h0;
    end else begin
      if (first_pkt_reception | (gen_last_cnt[0].pc_last_cnt == PC_NB_WRITES[0])) begin
        axi4_write_pc <= {axi4_write_pc[ETH_PC-2:0], first_pkt_reception};
      end else if (gen_last_cnt[1].pc_last_cnt == PC_NB_WRITES[1]) begin
        axi4_write_pc <= 'h0;
      end
    end
  end

  // deserialization of 64bits words (MRMAC) to 256b (AXI4_DATA_W)
  logic [AXI4_DATA_W-1:0]                       realined_word;
  logic [$clog2(NB_MRMRAC_WORDS_PER_WRITE)-1:0] realign_cnt;
  logic                                         realined_word_vld;
  logic                                         fifo_cerx_out_rdy_vld;
  logic                                         fifo_cerx_out_rdy_vld_reg;

  assign fifo_cerx_out_rdy_vld = fifo_cerx_out_rdy & fifo_cerx_out_vld;
  always_ff @(posedge clk_mrmac)
    fifo_cerx_out_rdy_vld_reg <= fifo_cerx_out_rdy_vld;

  always_ff @(posedge clk_mrmac) begin
    if(~resetn_mrmac) begin
      realign_cnt <= 'h0;
    end else begin
       if (fifo_cerx_out_rdy_vld & (realign_cnt == NB_MRMRAC_WORDS_PER_WRITE-1)) begin
        realign_cnt <= 'h0;
       end else if (fifo_cerx_out_rdy_vld) begin
        realign_cnt <= realign_cnt + 1;
      end
    end
  end

  always_ff @(posedge clk_mrmac)
    if (fifo_cerx_out_rdy_vld)
      realined_word[realign_cnt*MRMAC_AXIS_W+:MRMAC_AXIS_W] <= fifo_cerx_out_data;

  assign realined_word_vld = (realign_cnt == 0) & fifo_cerx_out_rdy_vld_reg;

  generate
    for (genvar gen_wr=0; gen_wr<ETH_PC; gen_wr++) begin : gen_ce_write
      logic                   fifo_pc_wr_in_vld;
      logic                   fifo_pc_wr_in_rdy;
      // ce-rx output interface
      logic [AXI4_DATA_W-1:0] fifo_pc_wr_out_data;
      logic                   fifo_pc_wr_out_vld;
      logic                   fifo_pc_wr_out_rdy;
      // control

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
      logic                            cnt_fifo_pc_wr_up;
      logic                            cnt_fifo_pc_wr_down;
      logic                            enough_words;

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
      // Address
      // ======================================================================================= //
      // We must write PC_NB_WRITES + PC_REMAINS addresses
      logic [$clog2(PC_NB_WRITES[gen_wr]):0] axi_write_cnt;
      logic                                                 axi_awrite;
      logic                                                 axi_awrite_tmp;
      logic                                                 aw_valid;

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          enough_words <= 1'b0;
        end else begin
          if(m_axi4_wlast[gen_wr])begin
            enough_words <= 1'b0;
          end else if ((PC_REMAINS[gen_wr] != 0) & (axi_write_cnt == 1)) begin
            enough_words <= fifo_pc_wr_out_vld;
          end else if (fifo_pc_wr_cnt >= MAX_BURST_SIZE) begin
            enough_words <= 1'b1;
          end
        end
      end

      always_ff @(posedge clk_mrmac)
        axi_awrite <= (axi_write_cnt > 0) && axi4_write_pc[gen_wr] & enough_words;

      always_ff @(posedge clk_mrmac)
        axi_awrite_tmp <= axi_awrite;

      // write done is just a front edge detector with a level
      assign aw_valid = axi_awrite & ~axi_awrite_tmp;

      // Counts the number of address writes that is left to do
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          axi_write_cnt <= PC_NB_WRITES[gen_wr];
        end else begin
          if (m_axi4_wlast[gen_wr] & ~(axi_write_cnt == 1)) begin
            axi_write_cnt <= axi_write_cnt - 1;
          end else if (m_axi4_wlast[gen_wr] & (axi_write_cnt == 1)) begin
            axi_write_cnt <= PC_NB_WRITES[gen_wr];
          end
        end
      end

      // Address channel --------------------------------------------------------------------------
      logic [AXI4_ADD_W-1:0] mhdma_write_addr;
      // read address takes the physical address computed earlier as soon as the value is ready
      // when starting the reading process we compute the offset accounting burst sequence
      always_ff @(posedge clk_mrmac) begin
        if (phy_addr_valid) begin
          mhdma_write_addr <= phy_addr[gen_wr];
        end else if (m_axi4_wlast[gen_wr]) begin
          mhdma_write_addr <= mhdma_write_addr + (AXI4_DATA_BYTES*MAX_BURST_SIZE);
        end
      end

      // we use axi4_write_pc front edge detection for computing expected wid
      logic [AXI4_ID_W-1:0] expected_wid;
      logic                 axi4_write_pc_tmp;
      logic                 wid_valid;

      always_ff @(posedge clk_mrmac)
        axi4_write_pc_tmp <= axi4_write_pc[gen_wr];

      assign wid_valid = axi4_write_pc[gen_wr] & ~axi4_write_pc_tmp;

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          expected_wid <= 'h0;
        end else begin
          if (wid_valid) begin
            expected_wid <= expected_wid + 1;
          end
        end
      end

      assign m_axi4_awid[gen_wr]    = aw_valid ? expected_wid     :'h0;
      assign m_axi4_awaddr[gen_wr]  = aw_valid ? mhdma_write_addr :'h0;
      assign m_axi4_awsize[gen_wr]  = aw_valid ? MHDMA_ARSIZE     :'h0;
      assign m_axi4_awburst[gen_wr] = aw_valid ? 2'b01            :'h0; // incr
      assign m_axi4_awvalid[gen_wr] = aw_valid ? 1'b1             :'h0;

      always_comb begin
        if ((PC_REMAINS[gen_wr] != 0) && (axi_write_cnt == 1)) begin
          m_axi4_awlen[gen_wr] = aw_valid ? PC_REMAINS[gen_wr]-1 : 'h0;
        end else begin
          m_axi4_awlen[gen_wr] = aw_valid ? MAX_BURST_SIZE-1 : 'h0;
        end
      end

      // Data channel -----------------------------------------------------------------------------
      logic axi_write;
      logic [$clog2(PC_NB_WORDS[gen_wr]):0] axi_word_cnt;

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          axi_write <= 1'b0;
        end else begin
          if (aw_valid) begin
            axi_write <= 1'b1;
          end else if (m_axi4_wlast[gen_wr]) begin
            axi_write <= 1'b0;
          end
        end
      end

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          axi_word_cnt <= MAX_BURST_SIZE;
        end else begin
          if (packets_received) begin                                            // all transactions done, reset the counter
              axi_word_cnt <= MAX_BURST_SIZE;
          end else begin
            if ((axi_write_cnt != 1) | (PC_REMAINS[gen_wr] == 0)) begin           // (not last trans) or (full bursts trans)
              if (m_axi4_wlast[gen_wr]) begin
                axi_word_cnt <= MAX_BURST_SIZE;
              end else if (m_axi4_wvalid[gen_wr] & m_axi4_wready[gen_wr]) begin
                axi_word_cnt <= axi_word_cnt -1;
              end
            end else begin                                                        // last trans & remain param not zero
              axi_word_cnt <= fifo_pc_wr_cnt;
            end
          end
        end
      end

      // we can start to write to HBM when we have enough words in FIFO and HBM is ready to receive words
      assign fifo_pc_wr_out_rdy = m_axi4_wready[gen_wr] & (enough_words | (axi_write_cnt == 1));

      assign m_axi4_wlast[gen_wr]  = ((axi_write & m_axi4_wready[gen_wr]) & (axi_word_cnt == 1)) ? 1'b1 : 1'b0;
      assign m_axi4_wstrb[gen_wr]  = (axi_write & m_axi4_wready[gen_wr]) ? 32'hFFFFFFFF : 'h0;
      assign m_axi4_wvalid[gen_wr] = axi_write & fifo_pc_wr_out_vld & fifo_pc_wr_out_rdy;

      assign m_axi4_wdata[gen_wr]  = m_axi4_wvalid[gen_wr] ? fifo_pc_wr_out_data : 'h0;

      // Write response channel -------------------------------------------------------------------
      // let's do simple and be ready for response at all time

      // Assert BREADY when ready to accept responses
      // Can be always high for simple designs, or controlled based on internal state
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          m_axi4_bready[gen_wr] <= 1'b0;
        end else begin
          // Assert ready when expecting a response
          m_axi4_bready[gen_wr] <= 1'b1;
        end
      end

      logic write_complete;
      logic write_error;

      // Handle write response
      always_ff @(clk_mrmac) begin
        if (~resetn_mrmac) begin
          write_error <= 1'b0;
        end else begin
          if (m_axi4_bvalid[gen_wr] && m_axi4_bready[gen_wr]) begin
            if (m_axi4_bid[gen_wr] == expected_wid) begin
              // Check response status
              case (m_axi4_bresp)
                AXI4_OKAY:   write_error <= 1'b0;  // Success
                AXI4_EXOKAY: write_error <= 1'b0;  // Exclusive access success
                AXI4_SLVERR: write_error <= 1'b1;  // Slave error
                AXI4_DECERR: write_error <= 1'b1;  // Decode error
              endcase
            end
          end
        end
      end

      always_ff @(clk_mrmac) begin
        if (~resetn_mrmac) begin
          write_complete <= 1'b0;
        end else begin
          write_complete <= 1'b0;
          if (m_axi4_bvalid[gen_wr] && m_axi4_bready[gen_wr])
            if (m_axi4_bid[gen_wr] == expected_wid)
              write_complete <= 1'b1;
        end
      end

    end
  endgenerate

  assign fifo_pc_backpressure = target_fifo ? gen_ce_write[1].fifo_pc_wr_in_rdy :  gen_ce_write[0].fifo_pc_wr_in_rdy;

  // Interrupt generation -------------------------------------------------------------------------
  // interrupt must be raised when we have both write_complete.
  // We already check that we send the correct number of workds into HBM with axi_word_cnt on both PC.
  // by design we cannot have several writes in HBM with different read request
  logic itr_read_request;
  logic [$clog2(PC_NB_WRITES[0] + PC_NB_WRITES[1]):0] write_complete_cnt;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      write_complete_cnt <= 'h0;
    end else begin
      if (gen_ce_write[0].write_complete | gen_ce_write[1].write_complete ) begin
        write_complete_cnt <= write_complete_cnt +1;
      end else if(write_complete_cnt == (PC_NB_WRITES[0] + PC_NB_WRITES[1])) begin
        write_complete_cnt <= 'h0;
      end
    end
  end

  assign itr_read_request = (write_complete_cnt == (PC_NB_WRITES[0] + PC_NB_WRITES[1])) ? 1'b1 : 1'b0;

  // itr_read_request is a pulse and can be used as a way to determine when to quit ST_READ_REQ
  // TODO: check that we don't need seq_num check or errors here and it's enough
  assign packets_received = itr_read_request;

  // regf payload information ---------------------------------------------------------------------
  logic [REG_DATA_W-1:0] rr_regf_in_data;
  logic                  rr_regf_in_rdy;
  logic                  rr_regf_in_vld;

  logic [REG_DATA_W-1:0] rr_regf_out_data;
  logic                  rr_regf_out_vld;
  logic                  rr_regf_out_rdy;

  // rr_regf_in_rdy there is no back pressurew
  assign rr_regf_in_data = {received_dst_addr, 4'b0, received_hpu_id, received_iop_id};

  assign rr_regf_in_vld =itr_read_request;

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

  assign rr_regf_out_rdy = interrupt_read_request & clear_interrupt_rr;

  assign regf_read_payload = rr_regf_out_data;
  assign interrupt_read_request = rr_regf_out_vld;

  // =========================================================================================== //
  // Statistics
  // =========================================================================================== //
  logic [REG_DATA_W-1:0] retry_notify_cnt;
  logic [REG_DATA_W-1:0] notify_cnt;
  logic [REG_DATA_W-1:0] notify_ack_cnt;
  logic [REG_DATA_W-1:0] t_notify_to_ack;
  logic [REG_DATA_W-1:0] t_rr_to_ce_received;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      notify_cnt <= 'h0;
    end else begin
      if (rst_cnt_notify) begin
        notify_cnt <= 'h0;
      end else begin
        if (format_notify_sent) begin
          notify_cnt <= notify_cnt + 1;
        end
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      notify_ack_cnt <= 'h0;
    end else begin
      if (rst_cnt_notify_ack) begin
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
      if (rst_cnt_notify_retry) begin
        retry_notify_cnt <= 'h0;
      end else begin
        if (timeout_reached_notify) begin
          retry_notify_cnt <= retry_notify_cnt + 1;
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
      if (format_notify_sent) begin
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

  // timing counter : counter between read request sent from this HPU and all frames have been received
  logic count_rreq_receive;
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      count_rreq_receive <= 1'b0;
    end else begin
      if (format_rreq_sent) begin
        count_rreq_receive <= 1'b1;
      end else if (packets_received) begin
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
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      stat_t_notify_to_ack <= 'h0;
    end else begin
      if (notify_ack_received) begin
        stat_t_notify_to_ack <= t_notify_to_ack;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      stat_t_rr_to_ce_received <= 'h0;
    end else begin
      if (packets_received) begin
        stat_t_rr_to_ce_received <= t_rr_to_ce_received;
      end
    end
  end

  //
  assign stat_cnt_notify_retries = retry_notify_cnt;
  assign stat_cnt_notify         = notify_cnt;
  assign stat_cnt_notify_ack     = notify_ack_cnt;

  assign stat_cnt_notify_timeout = to_notify_cnt;    // maybe not useful

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      stat_nb_ce_words_received <= 'h0;
    end else begin
      if (rst_nb_ce_words_received) begin
        stat_nb_ce_words_received <= 'h0;
      end else begin
        if (packets_received) begin
          stat_nb_ce_words_received <= { {(REG_DATA_W-CE_DATA_COUNT_W){1'b0}}, fifo_cerx_cnt_tx};
        end
      end
    end
  end

  assign stat_fsm_notify   = ntx_state;
  assign stat_fsm_read_req = rreq_state;

endmodule
