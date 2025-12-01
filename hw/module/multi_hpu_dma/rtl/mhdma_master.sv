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
  // Read ReQuest Queue (RRQQ) --------------------------------------------------------------------
  // === CFG domain
  logic                 rrqq_in_rdy;
  logic                 rrqq_in_vld;
  logic [RQQ_WIDTH-1:0] rrqq_in_data;
  // tmp
  logic [RQQ_WIDTH-1:0] rrqq_data_kept;
  logic                 rrqq_data_kept_avail;
  logic                 rrqq_data_vld;

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
  logic [RQQ_WIDTH-1:0] rrqq_out_data;
  logic                 rrqq_out_rdy;
  logic                 rrqq_out_vld;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak theses parameters in package
    .WIDTH           (RQQ_WIDTH),
    .DEPTH           (XPM_MIN_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(RQQ_MEMORY_TYPE)
  ) rrqq_fifo_ram_rdy_vld_2clk (
    // CFG domain
    .in_clk   (clk_cfg),
    .in_rstn  (resetn_cfg),
    .in_data  (rrqq_in_data),
    .in_rdy   (rrqq_in_rdy),
    .in_vld   (rrqq_in_vld),
    // MRMAC domain
    .out_clk  (clk_mrmac),
    .out_rstn (resetn_mrmac),
    .out_data (rrqq_out_data),
    .out_rdy  (rrqq_out_rdy),
    .out_vld  (rrqq_out_vld)
  );

  assign new_read_request_pending = rrqq_out_vld;
  assign rrqq_out_rdy = read_request_allowed;

  // current read request, sampled when valid is toggled
  logic [DST_ADDR_W-1:0] rrqq_dst_addr;
  logic [SRC_ADDR_W-1:0] rrqq_src_addr;
  logic [  SIZE_B_W-1:0] rrqq_size_b;
  logic [  REQ_ID_W-1:0] rrqq_req_id;
  logic [  IOP_ID_W-1:0] rrqq_iop_id;
  logic [  HPU_ID_W-1:0] rrqq_hpu_id;

  always_ff @(posedge clk_mrmac) begin : read_request_sampling
    if (rrqq_out_vld) begin
      rrqq_src_addr <= rrqq_out_data[CMD_SRC_ADDR_OFS-1:0];
      rrqq_dst_addr <= rrqq_out_data[CMD_DST_ADDR_OFS-1:CMD_SRC_ADDR_OFS];
      rrqq_size_b   <= rrqq_out_data[CMD_SIZE_B_OFS-1:CMD_DST_ADDR_OFS];
      rrqq_hpu_id   <= rrqq_out_data[CMD_HPU_ID_OFS-1:CMD_SIZE_B_OFS];
      rrqq_req_id   <= rrqq_out_data[CMD_REQ_ID_OFS-1:CMD_HPU_ID_OFS];
      rrqq_iop_id   <= rrqq_out_data[CMD_IOP_ID_OFS-1:CMD_REQ_ID_OFS];
    end
  end

  logic rrqq_cmd_vld;
  always_ff @(posedge clk_mrmac)
    rrqq_cmd_vld <= rrqq_out_vld;

  // Notify ReQuest Queue (NRQQ) ------------------------------------------------------------------
  // === CFG domain
  logic                  nrqq_in_rdy;
  logic                  nrqq_in_vld;
  logic [NRQQ_WIDTH-1:0] nrqq_in_data;
  // tmp
  logic [NRQQ_WIDTH-1:0] nrqq_data_kept;
  logic                  nrqq_data_kept_avail;
  logic                  nrqq_data_vld;
  // === MRMAC domain
  logic [NRQQ_WIDTH-1:0] nrqq_out_data;
  logic                  nrqq_out_rdy;
  logic                  nrqq_out_vld;

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
    .WIDTH           (NRQQ_WIDTH),
    .DEPTH           (XPM_MIN_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(NRQQ_MEMORY_TYPE)
  ) nrqq_fifo_ram_rdy_vld_2clk (
    // CFG domain
    .in_clk   (clk_cfg),
    .in_rstn  (resetn_cfg),
    .in_data  (nrqq_in_data),
    .in_rdy   (nrqq_in_rdy),
    .in_vld   (nrqq_data_vld),
    //  MRMAC domain
    .out_clk  (clk_mrmac),
    .out_rstn (resetn_mrmac),
    .out_data (nrqq_out_data),
    .out_rdy  (nrqq_out_rdy),
    .out_vld  (nrqq_out_vld)
  );

  assign new_notify_request_pending = nrqq_out_vld;
  assign nrqq_out_rdy = notify_request_allowed;

  // current notify request, sampled when valid is toggled
  logic [SRC_ADDR_W-1:0] nrqq_src_addr;
  logic [IOP_ID_W-1:0]   nrqq_iop_id;
  logic [SIZE_B_W-1:0]   nrqq_size_b;
  logic [REQ_ID_W-1:0]   nrqq_req_id;
  logic [HPU_ID_W-1:0]   nrqq_hpu_id;

  // none of theses information are in the first word:
  //  => sampled on the same clock cycle as sending first frame
  always_ff @(posedge clk_mrmac) begin : notify_request_sampling
    if (nrqq_out_vld) begin
      nrqq_iop_id    <= nrqq_out_data[CMD_IOP_ID_OFS-1:CMD_REQ_ID_OFS];
      nrqq_req_id    <= nrqq_out_data[CMD_REQ_ID_OFS-1:CMD_HPU_ID_OFS];
      nrqq_hpu_id    <= nrqq_out_data[CMD_HPU_ID_OFS-1:CMD_SIZE_B_OFS];
      nrqq_size_b    <= nrqq_out_data[CMD_SIZE_B_OFS-1:CMD_DST_ADDR_OFS];
      nrqq_src_addr  <= nrqq_out_data[CMD_SRC_ADDR_OFS-1:0];
    end
  end

  logic nrqq_cmd_vld;
  always_ff @(posedge clk_mrmac)
    nrqq_cmd_vld <= nrqq_out_vld;

  // Header information ---------------------------------------------------------------------------
  assign master_dst_addr = notify_request_allowed ?         'h0   : read_request_allowed ? rrqq_dst_addr : 'h0;
  assign master_src_addr = notify_request_allowed ? nrqq_src_addr : read_request_allowed ? rrqq_src_addr : 'h0;
  assign master_size_b   = notify_request_allowed ? nrqq_size_b   : read_request_allowed ? rrqq_size_b   : 'h0;
  assign master_req_id   = notify_request_allowed ? nrqq_req_id   : read_request_allowed ? rrqq_req_id   : 'h0;
  assign master_iop_id   = notify_request_allowed ? nrqq_iop_id   : read_request_allowed ? rrqq_iop_id   : 'h0;
  assign master_hpu_id   = notify_request_allowed ? nrqq_hpu_id   : read_request_allowed ? rrqq_hpu_id   : 'h0;

  // valid signal for formatting frames
  assign master_header_valid = notify_request_allowed ? nrqq_cmd_vld : read_request_allowed ? rrqq_cmd_vld : 1'b0;

  // ----------------------------------------------------------------------------------------------
  // when we have the data of both request identifier and addresses, we consume the information
  // > this signal is in configuration clock
  assign request_consumed = (rrqq_data_vld | nrqq_data_vld) ? 1'b1 : 1'b0;

  // ==============================================================================================
  // FSM
  // ==============================================================================================
  // Notify TX (NTX) ------------------------------------------------------------------------------
  typedef enum logic [1:0] {
    NTX_XXX          = 'x,
    NTX_WAIT_REQUEST = 2'b00,
    NTX_WAIT_ACK     = 2'b01,
    NTX_SEND_NOTIFY  = 2'b10
  } st_ntx;

  st_ntx ntx_state;
  st_ntx ntx_next_state;
  logic  ntx_timeout;
  logic  ntx_timeout_cdc;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) ntx_state <= NTX_WAIT_REQUEST;
    else ntx_state <= ntx_next_state;
  end

  logic notify_request_allowedD;
  always_ff @(posedge clk_mrmac)
    notify_request_allowedD <= notify_request_allowed;

  logic notify_request_sent;
  assign notify_request_sent = notify_request_allowedD & ~notify_request_allowed;

  always_comb begin
    ntx_next_state = NTX_XXX;
    case (ntx_state)
      NTX_WAIT_REQUEST:
        ntx_next_state = (new_notify_request_pending & notify_request_allowed) ? NTX_SEND_NOTIFY : NTX_WAIT_REQUEST;
      NTX_SEND_NOTIFY:
        ntx_next_state = notify_request_sent ? NTX_WAIT_ACK : NTX_SEND_NOTIFY;
      NTX_WAIT_ACK:
        ntx_next_state = notify_ack_received ? NTX_WAIT_REQUEST : (ntx_timeout_cdc ? NTX_SEND_NOTIFY : ntx_next_state);
    endcase
  end

  logic [15:0] cnt_notify_ack;
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

  xpm_cdc_single_wrapper # (
    .CDC_SYNC_STAGES(CDC_SYNC_STAGES),
    .SRC_INPUT_REG  (0)
  ) cdc_single_ntx_timeout (
    .src_clk(clk_cfg),
    .src_in (ntx_timeout),

    .dest_clk(clk_mrmac),
    .dest_out(ntx_timeout_cdc)
  );

  // Read request ---------------------------------------------------------------------------------
  typedef enum logic [1:0] {
    RR_XXX          = 'x,
    RR_WAIT_REQUEST = 2'b00,
    RR_SEND_REQUEST = 2'b01,
    RR_WAIT_PACKETS = 2'b10
  } st_read_req;

  st_read_req rreq_state;
  st_read_req rreq_next_state;
  logic       rreq_timeout;
  logic       rreq_timeout_cdc;
  logic       rreq_ct_transmitted;
  logic       rreq_send_request;
  logic       error_packet_id_mismatch;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) rreq_state <= RR_WAIT_REQUEST;
    else rreq_state <= rreq_next_state;
  end

  logic read_request_allowedD;
  always_ff @(posedge clk_mrmac)
    read_request_allowedD <= read_request_allowed;

  logic read_request_sent;
  assign read_request_sent = read_request_allowedD & ~read_request_allowed;

  always_comb begin
    rreq_next_state = RR_XXX;
    case (rreq_state)
      RR_WAIT_REQUEST:
        rreq_next_state = new_read_request_pending ? RR_SEND_REQUEST : RR_WAIT_REQUEST;
      RR_SEND_REQUEST:
        rreq_next_state =  read_request_sent ? RR_WAIT_PACKETS : RR_SEND_REQUEST;
      RR_WAIT_PACKETS:
        // if error_packet_id_mismatch or timeout => RR_SEND_REQUEST
        // if write into hbm is finished => RR_WAIT_REQUEST
        rreq_next_state = (error_packet_id_mismatch | rreq_timeout_cdc) ? RR_SEND_REQUEST : (rreq_ct_transmitted? RR_WAIT_REQUEST: RR_WAIT_PACKETS);
    endcase
  end

  // TODO:
  assign error_packet_id_mismatch = 1'b0;
  assign rreq_timeout_cdc = 1'b0;
  assign rreq_ct_transmitted = 1'b0;

  assign rreq_send_request = (rreq_state == RR_SEND_REQUEST) ? 1'b1: 1'b0;

endmodule
