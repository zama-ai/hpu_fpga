// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA reception module
// ----------------------------------------------------------------------------------------------
// Receives request from RPU and address them
// - Notify TX
// - Read Request
// ==============================================================================================

module mhdma_master
  import mhdma_pkg::*;              // for all mhdma modules
  import axi_if_shell_axil_pkg::*;  // REG_DATA_W
#() (
  // Ethernet configuration interface -----------------------------------------
  input  logic                                clk_cfg,
  input  logic                                resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                clk_mrmac,
  input  logic                                resetn_mrmac,
  // regf interface -----------------------------------------------------------
  input  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr,
  input  logic             [  REG_DATA_W-1:0] regf_req_id,
  input  logic             [  REG_DATA_W-1:0] regf_req_addr,
  input  logic             [REG_DATA_W/2-1:0] regf_timeout_dur,
  // register control --------------------------------------------------------
  input  logic                                received_req,
  output logic                                request_consumed,
  // Flags -------------------------------------------------------------------
  input  logic                                read_request_allowed,
  input  logic                                notify_request_allowed,

  output logic                                new_read_request_pending,
  output logic                                new_notify_request_pending,

  input  logic                                notify_ack_received,
  input  logic                                ciphertext_received,
  // from master to packet formatter -------------------------------------------
  output logic             [  DST_ADDR_W-1:0] master_dst_addr,
  output logic             [  SRC_ADDR_W-1:0] master_src_addr,
  output logic             [    SIZE_B_W-1:0] master_size_b,
  output logic             [    REQ_ID_W-1:0] master_req_id,
  output logic             [    IOP_ID_W-1:0] master_iop_id,
  output logic             [    HPU_ID_W-1:0] master_hpu_id,
  output logic                                master_header_valid,
  // ciphertext payload -------------------------------------------------------
  input  logic             [MRMAC_AXIS_W-1:0] rx_tdata,
  input  logic                                rx_tsop,
  input  logic                                rx_tlast,
  input  logic                                rx_tvalid
  // flags for stats ----------------------------------------------------------
  // statistics ---------------------------------------------------------------
  // error --------------------------------------------------------------------
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int CDC_SYNC_STAGES = 2;

  // =========================================================================================== //
  // CDC from regf to mrmac clock
  // =========================================================================================== //
  logic rrqq_wr_en; // read request queue write enable
  logic nrqq_wr_en; // notify request queue write enable

  // when we have the data of both request identifier and addresses, we consume the information
  // this signal is in configuration clock
  assign request_consumed = (rrqq_wr_en | nrqq_wr_en) ? 1'b1 : 1'b0;

  // Read ReQuest Queue (RRQQ) --------------------------------------------------------------------
  // config clock
  logic                        rrqq_wr_rst_busy;
  logic                        rrqq_full;
  // mrmac clock
  logic                        rrqq_rd_rst_busy;
  logic                        rrqq_data_valid;
  logic                        rrqq_rd_en;
  logic [       RQQ_WIDTH-1:0] rrqq_rd_data;
  logic                        rrqq_empty;
  logic [RQQ_DATA_COUNT_W-1:0] rrqq_rd_data_count;

  // cfg
  assign rrqq_wr_en = received_req & ~rrqq_wr_rst_busy & ~rrqq_full & (regf_req_id[23:20] == REQ_ID_READ);
  // mrmac
  assign new_read_request_pending = ((rrqq_rd_data_count == 0) & ~read_request_allowed) ? 1'b0 : 1'b1;
  assign rrqq_rd_en =  new_read_request_pending & ~rrqq_rd_rst_busy & ~rrqq_empty;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    .WIDTH           (RQQ_WIDTH),
    // tweak theses parameters in package
    .DEPTH           (XPM_MIN_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(RQQ_MEMORY_TYPE)
  ) rrqq_fifo_ram_rdy_vld_2clk (
    // Write Domain ports: CFG domain
    .wr_rstn      (resetn_cfg),
    .wr_clk       (clk_cfg),
    .wr_en        (rrqq_wr_en),
    .wr_data      ({regf_req_id, regf_req_addr}),
    .full         (rrqq_full),
    .wr_rst_busy  (rrqq_wr_rst_busy),
    // Read Domain ports: MRMAC domain
    .rd_clk       (clk_mrmac),
    .rd_en        (rrqq_rd_en),
    .rd_data      (rrqq_rd_data),
    .rd_data_count(rrqq_rd_data_count),
    .empty        (rrqq_empty),
    .rd_rst_busy  (rrqq_rd_rst_busy),
    .data_valid   (rrqq_data_valid)
  );

  // current read request, sampled when valid is toggled
  logic [DST_ADDR_W-1:0] rrqq_dst_addr;
  logic [SRC_ADDR_W-1:0] rrqq_src_addr;
  logic [  SIZE_B_W-1:0] rrqq_size_b;
  logic [  REQ_ID_W-1:0] rrqq_req_id;
  logic [  IOP_ID_W-1:0] rrqq_iop_id;
  logic [  HPU_ID_W-1:0] rrqq_hpu_id;

  always_ff @(posedge clk_mrmac) begin : read_request_sampling
    if (~resetn_mrmac) begin
      rrqq_dst_addr <= 'h0;
      rrqq_src_addr <= 'h0;
      rrqq_size_b   <= 'h0;
      rrqq_iop_id   <= 'h0;
      rrqq_req_id   <= 'h0;
      rrqq_hpu_id   <= 'h0;
    end else begin
      if (rrqq_data_valid) begin
        rrqq_src_addr <= rrqq_rd_data[CMD_SRC_ADDR_OFS-1:0];
        rrqq_dst_addr <= rrqq_rd_data[CMD_DST_ADDR_OFS-1:CMD_SRC_ADDR_OFS];
        rrqq_size_b   <= rrqq_rd_data[CMD_SIZE_B_OFS-1:CMD_DST_ADDR_OFS];
        rrqq_hpu_id   <= rrqq_rd_data[CMD_HPU_ID_OFS-1:CMD_SIZE_B_OFS];
        rrqq_req_id   <= rrqq_rd_data[CMD_REQ_ID_OFS-1:CMD_HPU_ID_OFS];
        rrqq_iop_id   <= rrqq_rd_data[CMD_IOP_ID_OFS-1:CMD_REQ_ID_OFS];
      end
    end
  end

  logic rrqq_data_validD;
  always_ff @(posedge clk_mrmac)
    rrqq_data_validD <= rrqq_data_valid;

  // Notify ReQuest Queue (NRQQ) ------------------------------------------------------------------
  // config clock
  logic                         nrqq_wr_rst_busy;
  logic                         nrqq_full;
  // mrmac clock
  logic                         nrqq_rd_rst_busy;
  logic                         nrqq_data_valid;
  logic                         nrqq_rd_en;
  logic [      NRQQ_WIDTH-1:0]  nrqq_rd_data;
  logic                         nrqq_empty;
  logic [NRQQ_DATA_COUNT_W-1:0] nrqq_rd_data_count;

  // cfg
  assign nrqq_wr_en = (received_req) & ~nrqq_wr_rst_busy & ~nrqq_full & (regf_req_id[23:20] == REQ_ID_NOTIFY_TX);
  // mrmac
  assign new_notify_request_pending = (nrqq_rd_data_count == 0) ? 1'b0 : 1'b1;
  assign nrqq_rd_en =  new_notify_request_pending & notify_request_allowed & ~nrqq_rd_rst_busy & ~nrqq_empty;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak theses parameters in package
    .WIDTH           (NRQQ_WIDTH),
    .DEPTH           (XPM_MIN_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(NRQQ_MEMORY_TYPE)
  ) nrqq_fifo_ram_rdy_vld_2clk (
    // Write Domain ports: CFG domain
    .wr_rstn      (resetn_cfg),
    .wr_clk       (clk_cfg),
    .wr_en        (nrqq_wr_en),
    .wr_data      ({regf_req_id, regf_req_addr}),
    .full         (nrqq_full),
    .wr_rst_busy  (nrqq_wr_rst_busy),
    // Read Domain ports: MRMAC domain
    .rd_clk       (clk_mrmac),
    .rd_en        (nrqq_rd_en),
    .rd_data      (nrqq_rd_data),
    .rd_data_count(nrqq_rd_data_count),
    .empty        (nrqq_empty),
    .rd_rst_busy  (nrqq_rd_rst_busy),
    .data_valid   (nrqq_data_valid)
  );

  // current notify request, sampled when valid is toggled
  logic [SRC_ADDR_W-1:0] nrqq_src_addr;
  logic [IOP_ID_W-1:0]   nrqq_iop_id;
  logic [SIZE_B_W-1:0]   nrqq_size_b;
  logic [REQ_ID_W-1:0]   nrqq_req_id;
  logic [HPU_ID_W-1:0]   nrqq_hpu_id;

  // none of theses information are in the first word:
  //  => sampled on the same clock cycle as sending first frame
  always_ff @(posedge clk_mrmac) begin : notify_request_sampling
    if (~resetn_mrmac) begin
      nrqq_src_addr  <= 'h0;
      nrqq_size_b    <= 'h0;
      nrqq_iop_id    <= 'h0;
      nrqq_req_id    <= 'h0;
      nrqq_hpu_id    <= 'h0;
    end else begin
      if (nrqq_data_valid) begin
        nrqq_iop_id    <= nrqq_rd_data[CMD_IOP_ID_OFS-1:CMD_REQ_ID_OFS];
        nrqq_req_id    <= nrqq_rd_data[CMD_REQ_ID_OFS-1:CMD_HPU_ID_OFS];
        nrqq_hpu_id    <= nrqq_rd_data[CMD_HPU_ID_OFS-1:CMD_SIZE_B_OFS];
        nrqq_size_b    <= nrqq_rd_data[CMD_SIZE_B_OFS-1:CMD_DST_ADDR_OFS];
        nrqq_src_addr  <= nrqq_rd_data[CMD_SRC_ADDR_OFS-1:0];
      end
    end
  end
  logic nrqq_data_validD;
  always_ff @(posedge clk_mrmac)
    nrqq_data_validD <= nrqq_data_valid;


  // Header information ---------------------------------------------------------------------------
  assign master_dst_addr = notify_request_allowed ?         'h0   : read_request_allowed ? rrqq_dst_addr : 'h0;
  assign master_src_addr = notify_request_allowed ? nrqq_src_addr : read_request_allowed ? rrqq_src_addr : 'h0;
  assign master_size_b   = notify_request_allowed ? nrqq_size_b   : read_request_allowed ? rrqq_size_b   : 'h0;
  assign master_req_id   = notify_request_allowed ? nrqq_req_id   : read_request_allowed ? rrqq_req_id   : 'h0;
  assign master_iop_id   = notify_request_allowed ? nrqq_iop_id   : read_request_allowed ? rrqq_iop_id   : 'h0;
  assign master_hpu_id   = notify_request_allowed ? nrqq_hpu_id   : read_request_allowed ? rrqq_hpu_id   : 'h0;

  // valid signal for formatting frames
  assign master_header_valid = notify_request_allowed ? nrqq_data_validD : read_request_allowed ? rrqq_data_validD : 1'b0;

  // ==============================================================================================
  // FSM
  // ==============================================================================================
  // Notify TX (NTX) ------------------------------------------------------------------------------
  logic        ntx_timeout;
  logic [15:0] cnt_notify_ack;

  typedef enum {
    ST_WAIT_REQUEST,
    ST_WAIT_ACK,
    ST_SEND_NOTIFY
  } st_ntx;

  st_ntx ntx_state;
  st_ntx ntx_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) ntx_state <= ST_WAIT_REQUEST;
    else ntx_state <= ntx_next_state;
  end

  logic notify_request_allowedD;
  always_ff @(posedge clk_mrmac)
    notify_request_allowedD <= notify_request_allowed;

  logic notify_request_sent;
  assign notify_request_sent = notify_request_allowedD & ~notify_request_allowed;

  always_comb begin
    case (ntx_state)
      ST_WAIT_REQUEST:
        ntx_next_state = (new_notify_request_pending & notify_request_allowed) ? ST_SEND_NOTIFY : ST_WAIT_REQUEST;
      ST_SEND_NOTIFY:
        ntx_next_state = notify_request_sent ? ST_WAIT_ACK : ST_SEND_NOTIFY;
      ST_WAIT_ACK:
        ntx_next_state = notify_ack_received ? ST_WAIT_REQUEST : (ntx_timeout ? ST_SEND_NOTIFY : ntx_next_state);
    endcase
  end

  // TODO: in cfg mode?
  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      ntx_timeout <= 1'b0;
    end else begin
      // TODO:regf_timeout_dur
      if (cnt_notify_ack >= regf_timeout_dur) begin
        ntx_timeout <= 1'b1;
      end else begin
        ntx_timeout <= 1'b0;
      end
    end
  end

  // Read request ---------------------------------------------------------------------------------
  logic rreq_timeout;
  logic rreq_timeout_cdc;
  logic rreq_ct_transmitted;
  logic rreq_send_request;
  logic error_packet_id_mismatch;

  typedef enum {
    ST_WAIT_READ_REQUEST,
    ST_SEND_READ_REQUEST,
    ST_WAIT_PACKETS
  } st_read_req;

  st_read_req rreq_state;
  st_read_req rreq_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) rreq_state <= ST_WAIT_READ_REQUEST;
    else rreq_state <= rreq_next_state;
  end

  logic read_request_allowedD;
  always_ff @(posedge clk_mrmac)
    read_request_allowedD <= read_request_allowed;

  logic read_request_sent;
  assign read_request_sent = read_request_allowedD & ~read_request_allowed;

  always_comb begin
    case (rreq_state)
      ST_WAIT_READ_REQUEST:
        rreq_next_state = new_read_request_pending ? ST_SEND_READ_REQUEST : ST_WAIT_READ_REQUEST;
      ST_SEND_READ_REQUEST:
        rreq_next_state =  read_request_sent ? ST_WAIT_PACKETS : ST_SEND_READ_REQUEST;
      ST_WAIT_PACKETS:
        // if error_packet_id_mismatch or timeout => ST_SEND_READ_REQUEST
        // if write into hbm is finished => ST_WAIT_READ_REQUEST
        rreq_next_state = (error_packet_id_mismatch | rreq_timeout_cdc) ? ST_SEND_READ_REQUEST : (rreq_ct_transmitted? ST_WAIT_READ_REQUEST: ST_WAIT_PACKETS);
    endcase
  end

  // TODO:
  assign error_packet_id_mismatch = 1'b0;
  assign rreq_timeout_cdc = 1'b0;
  assign rreq_ct_transmitted = 1'b0;

  assign rreq_send_request = (rreq_state == ST_SEND_READ_REQUEST) ? 1'b1: 1'b0;

endmodule
