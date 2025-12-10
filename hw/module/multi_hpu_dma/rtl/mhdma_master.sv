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
  import mhdma_pkg::*;               // for all mhdma modules
  import axi_if_eth_axi_pkg::*;      // AXI4
  import axi_if_shell_axil_pkg::*;   // REG_DATA_W
  import axi_if_common_param_pkg::*; // HBM page
#(
  parameter                int CDC_SYNC_STAGES = 2,
  parameter                int MAX_BURST_SIZE  = PAGE_BYTES/AXI4_DATA_BYTES,
  parameter [ETH_PC-1:0][15:0] PC_CT_BYTES     = '{'h2000, 'h2020},
  parameter              [3:0] PC_STRIDE       = 'hB
) (
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
  input  logic             [  REG_DATA_W-1:0] regf_read_payload,
  // register control --------------------------------------------------------
  input  logic                                received_req,
  output logic                                request_consumed,
  // Flags -------------------------------------------------------------------
  input  logic                                read_request_allowed,
  input  logic                                notify_request_allowed,

  output logic                                new_read_request_pending,
  output logic                                new_notify_request_pending,

  input  logic                                notify_ack_received,

  output logic                                ct_emission_all_packets_received,
  // from master to packet formatter -------------------------------------------
  output header_t                             format_header,
  // ciphertext payload -------------------------------------------------------
  input  logic             [MRMAC_AXIS_W-1:0] rx_tdata,
  input  logic                                rx_tvalid,
  input  logic                                rx_tlast,
  output logic                                cerx_reception_ready,
  // Received header ----------------------------------------------------------
  input  header_t                             decoded_header,
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
  // flags for stats ----------------------------------------------------------
  // statistics ---------------------------------------------------------------
  // interrupt ---------------------------------------------------------------
  input  logic                                clear_interrupt_rr,
  output logic                                interrupt_read_request,
  // error --------------------------------------------------------------------
  output error_packet_id_mismatch
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam [AXI4_SIZE_W-1:0] MHDMA_ARSIZE = $clog2(AXI4_DATA_BYTES);
  localparam NB_MRMRAC_WORDS_PER_WRITE = AXI4_DATA_W/MRMAC_AXIS_W;

  // TOREVIEW
  // generate cannot be in packages, same snippet must be in slave & master module
  generate
    for (genvar gen_i = 0; gen_i < ETH_PC; gen_i = gen_i + 1) begin : gen_localparam
      localparam int PC_NB_WORDS = (PC_CT_BYTES[gen_i] / AXI4_DATA_BYTES);
      localparam int PC_NB_WRITES_BURST = (PC_NB_WORDS / MAX_BURST_SIZE);
      localparam int PC_REMAINS = (PC_NB_WORDS % MAX_BURST_SIZE);
      localparam int PC_NB_WRITES = (PC_REMAINS!=0) ? PC_NB_WRITES_BURST + 1 : PC_NB_WRITES_BURST;
    end
  endgenerate

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
  assign format_header.dst_addr = notify_request_allowed ?         'h0   : read_request_allowed ? rrqq_dst_addr : 'h0;
  assign format_header.src_addr = notify_request_allowed ? nrqq_src_addr : read_request_allowed ? rrqq_src_addr : 'h0;
  assign format_header.size_b   = notify_request_allowed ? nrqq_size_b   : read_request_allowed ? rrqq_size_b   : 'h0;
  assign format_header.req_id   = notify_request_allowed ? nrqq_req_id   : read_request_allowed ? rrqq_req_id   : 'h0;
  assign format_header.iop_id   = notify_request_allowed ? nrqq_iop_id   : read_request_allowed ? rrqq_iop_id   : 'h0;
  assign format_header.hpu_id   = notify_request_allowed ? nrqq_hpu_id   : read_request_allowed ? rrqq_hpu_id   : 'h0;

  // valid signal for formatting frames
  assign format_header.valid    = notify_request_allowed ? nrqq_cmd_vld : read_request_allowed ? rrqq_cmd_vld : 1'b0;

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

  logic notify_request_allowed_tmp;
  always_ff @(posedge clk_mrmac)
    notify_request_allowed_tmp <= notify_request_allowed;

  logic notify_request_sent;
  assign notify_request_sent = notify_request_allowed_tmp & ~notify_request_allowed;

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

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) rreq_state <= RR_WAIT_REQUEST;
    else rreq_state <= rreq_next_state;
  end

  logic read_request_allowed_tmp;
  always_ff @(posedge clk_mrmac)
    read_request_allowed_tmp <= read_request_allowed;

  logic read_request_sent;
  assign read_request_sent = read_request_allowed_tmp & ~read_request_allowed;

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

  // =========================================================================================== //
  // Ciphertext reception
  //
  // Assumptions:
  // We had previously garanteed to launch a Read request only and only if fifo is empty and ready
  //
  // Errors:
  // TODO
  // err_ce_rx_unexpected_ct: we should see ciphertext over rx link only read_request_allowed
  // err_ce_rx_too_much_data: we received too much data and tried to overflow the fifo
  // =========================================================================================== //
  // ce-rx input interface
  logic [CE_DATA_W-1:0] fifo_cerx_in_data;
  logic                 fifo_cerx_in_vld;
  logic                 fifo_cerx_in_rdy;
  // ce-rx output interface
  logic [CE_DATA_W-1:0] fifo_cerx_out_data;
  logic                 fifo_cerx_out_vld;
  logic                 fifo_cerx_out_rdy;
  // ce-rx counters
  logic [CERX_DATA_COUNT_W:0] fifo_cerx_cnt;    // counts the number of words used in fifo
  logic [CERX_DATA_COUNT_W:0] fifo_cerx_cnt_rx; // counts the number of words received over RX link

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      fifo_cerx_cnt <= 'h0;
    end else begin
      if (read_request_allowed & (fifo_cerx_in_vld & fifo_cerx_in_rdy)) begin
        fifo_cerx_cnt <= fifo_cerx_cnt + 1;
      end else if (read_request_allowed & fifo_cerx_out_rdy & fifo_cerx_out_vld) begin
        fifo_cerx_cnt <= fifo_cerx_cnt - 1;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      fifo_cerx_cnt_rx <= 'h0;
    end else begin
      if (read_request_allowed & fifo_cerx_in_vld & fifo_cerx_in_rdy) begin
        fifo_cerx_cnt_rx <= fifo_cerx_cnt_rx + 1;
      end if (read_request_allowed & (fifo_cerx_cnt_rx == CT_NB_COEF)) begin
        fifo_cerx_cnt_rx <= 'h0;
      end
    end
  end

  assign fifo_cerx_in_vld  = rx_tvalid;
  assign fifo_cerx_in_data = rx_tdata;

  fifo_ram_rdy_vld # (
    .WIDTH             (CERX_DATA_W     ),
    .DEPTH             (CERX_DEPTH      ),
    .RAM_LATENCY       (CERX_RAM_LATENCY)
  ) fifo_ce_rx (
    .clk        (clk_mrmac   ),
    .s_rst_n    (resetn_mrmac),

    .in_data    (fifo_cerx_in_data),
    .in_vld     (fifo_cerx_in_vld ),
    .in_rdy     (fifo_cerx_in_rdy ),

    .out_data   (fifo_cerx_out_data ),
    .out_vld    (fifo_cerx_out_vld  ),
    .out_rdy    (fifo_cerx_out_rdy)
  );
  assign cerx_reception_ready = (fifo_cerx_cnt == 0) & fifo_cerx_in_rdy;

  // TODO
  assign ct_emission_all_packets_received = 0;

 // ready signal of sending fifo according to which one we should use
  logic fifo_pc_backpressure;
  assign fifo_cerx_out_rdy = fifo_pc_backpressure;

  // =========================================================================================== //
  // Write into HBM
  // all @mrmac domain
  // TODO
  // How much time do we spend between read request and all coefficients arrived & stored ?
  // How much time between read request and first coefficient ?
  // How much time is spent bewteen receiving all words and storing theml in hbm ?
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

  // TODO: if seq_num != 0 and  received_dst_addr != previous, raise an errror

  logic [ETH_PC-1:0] axi4_write_pc;
  // word distribution to each fifo pc ------------------------------------------------------------
  logic [CERX_DATA_COUNT_W:0] fifo_cerx_cnt_tx;
  logic [ETH_PC-1:0]          target_fifo;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      fifo_cerx_cnt_tx <= 'h0;
    end else begin
      if (fifo_cerx_out_vld & fifo_cerx_out_rdy) begin
        fifo_cerx_cnt_tx <= fifo_cerx_cnt_tx +1;
      end
    end
  end

  // which fifo must be filled ?
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      target_fifo <= 2'b00;
    end else begin
      if (fifo_cerx_cnt_tx < 4*gen_localparam[0].PC_NB_WORDS) begin
        target_fifo <= 2'b01;
      end else begin
        target_fifo <= 2'b10;
      end
    end
  end

  // launch reads over the two PCs independently one at a time
  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_last_cnt
      logic [$clog2(gen_localparam[gen_i].PC_NB_WRITES):0] pc_last_cnt;
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac)begin
          pc_last_cnt <= 'h0;
        end else begin
          if(m_axi4_wlast[gen_i]) begin
            pc_last_cnt <= pc_last_cnt+1;
          end else if (pc_last_cnt == gen_localparam[gen_i].PC_NB_WRITES) begin
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
      if (first_pkt_reception | (gen_last_cnt[0].pc_last_cnt == gen_localparam[0].PC_NB_WRITES)) begin
        axi4_write_pc <= {axi4_write_pc[ETH_PC-2:0], first_pkt_reception};
      end else if (gen_last_cnt[1].pc_last_cnt == gen_localparam[1].PC_NB_WRITES) begin
        axi4_write_pc <= 'h0;
      end
    end
  end

  // deserialization of 64bits words (MRMAC) to 256b (AXI4_DATA_W)
  logic [FIFO_PC_DATA_W-1:0]                    realined_word;
  logic [$clog2(NB_MRMRAC_WORDS_PER_WRITE)-1:0] realign_cnt;
  logic                                         realined_word_vld;

  // // because in one read we have NB_MRMRAC_WORDS_PER_WRITE, we must delay the signal pc_read_finished
  // logic [NB_MRMRAC_WORDS_PER_WRITE-1:0] temp_finished_flag;
  // always_ff @(posedge clk_mrmac)
  //   temp_finished_flag[0] <= fifo_cerx_out_vld & fifo_cerx_out_rdy;

  // generate
  // for (genvar gen_i = 1; gen_i<NB_MRMRAC_WORDS_PER_WRITE; gen_i++) begin
  //   always_ff @(posedge clk_mrmac)
  //     temp_finished_flag[gen_i] <= temp_finished_flag[gen_i-1];
  // end
  // endgenerate

  always_ff @(posedge clk_mrmac) begin
    if(~resetn_mrmac) begin
      realign_cnt <= 'h0;
    end else begin
      if (fifo_cerx_out_vld & fifo_cerx_out_rdy) begin
        realign_cnt <= realign_cnt + 1;
      end else begin
        realign_cnt <= 'h0;
      end
    end
  end

  always_ff @(posedge clk_mrmac)
    if (fifo_cerx_out_vld & fifo_cerx_out_rdy)
      realined_word[realign_cnt*MRMAC_AXIS_W+:MRMAC_AXIS_W] <= fifo_cerx_out_data;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      realined_word_vld <= 1'b0;
    end else begin
      // we are valid when realign_cnt = 0 but because realign_cnt had to be init
      // we are valid one cc after realign_cnt = 3
      if (realign_cnt == 3) begin
        realined_word_vld <= 1'b1;
      end else begin
        realined_word_vld <= 1'b0;
      end
    end
  end

  generate
    for (genvar gen_wr=0; gen_wr<ETH_PC; gen_wr++) begin : gen_ce_write
      logic                      fifo_pc_wr_in_vld;
      logic                      fifo_pc_wr_in_rdy;
      // ce-rx output interface
      logic [FIFO_PC_DATA_W-1:0] fifo_pc_wr_out_data;
      logic                      fifo_pc_wr_out_vld;
      logic                      fifo_pc_wr_out_rdy;
      // control

      fifo_ram_rdy_vld # (
        .WIDTH(FIFO_PC_DATA_W),
        .DEPTH(FIFO_PC_DEPTH)
      ) fifo_pc_wr (
        .clk     (clk_mrmac         ),
        .s_rst_n (resetn_mrmac      ),

        .in_data (realined_word     ),
        .in_vld  (fifo_pc_wr_in_vld ),
        .in_rdy  (fifo_pc_wr_in_rdy ),

        .out_data(fifo_pc_wr_out_data),
        .out_vld (fifo_pc_wr_out_vld ),
        .out_rdy (fifo_pc_wr_out_rdy )
      );

      assign fifo_pc_wr_in_vld = target_fifo[gen_wr] & realined_word_vld ;

      logic [FIFO_PC_DATA_COUNT_W-1:0] fifo_pc_wr_cnt;
      logic                            cnt_fifo_pc_wr_up;
      logic                            cnt_fifo_pc_wr_down;
      logic                            enough_words;

      assign cnt_fifo_pc_wr_up = fifo_pc_wr_in_vld & fifo_pc_wr_in_rdy;
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
      logic [$clog2(gen_localparam[gen_wr].PC_NB_WRITES):0] axi_write_cnt;
      logic                                                 axi_awrite;
      logic                                                 axi_awrite_tmp;
      logic                                                 aw_valid;

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          enough_words <= 1'b0;
        end else begin
          if(m_axi4_wlast[gen_wr])begin
            enough_words <= 1'b0;
          end else if ((gen_localparam[gen_wr].PC_REMAINS != 0) & (axi_write_cnt == 1)) begin
            enough_words <= fifo_pc_wr_out_vld;
          end else if (fifo_pc_wr_cnt >= MAX_BURST_SIZE) begin
            enough_words <= 1'b1;
          end
        end
      end

      always_ff @(posedge clk_mrmac)
        axi_awrite <= (axi_write_cnt > 0) && axi4_write_pc[gen_wr] && m_axi4_awready[gen_wr] & enough_words;

      always_ff @(posedge clk_mrmac)
        axi_awrite_tmp <= axi_awrite;

      // write done is just a front edge detector with a level
      assign aw_valid = axi_awrite & ~axi_awrite_tmp;

      // Counts the number of address writes that is left to do
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          axi_write_cnt <= gen_localparam[gen_wr].PC_NB_WRITES;
        end else begin
          if (m_axi4_wlast[gen_wr] & ~(axi_write_cnt == 0)) begin
            axi_write_cnt <= axi_write_cnt - 1;
          end else if (m_axi4_wlast[gen_wr] & (axi_write_cnt == 0)) begin
            axi_write_cnt <= gen_localparam[gen_wr].PC_NB_WRITES;
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

      assign m_axi4_awid[gen_wr]    = (aw_valid & m_axi4_awready[gen_wr]) ? expected_wid     :'h0;
      assign m_axi4_awaddr[gen_wr]  = (aw_valid & m_axi4_awready[gen_wr]) ? mhdma_write_addr :'h0;
      assign m_axi4_awsize[gen_wr]  = (aw_valid & m_axi4_awready[gen_wr]) ? MHDMA_ARSIZE     :'h0;
      assign m_axi4_awburst[gen_wr] = (aw_valid & m_axi4_awready[gen_wr]) ? 2'b01            :'h0; // incr
      assign m_axi4_awvalid[gen_wr] = (aw_valid & m_axi4_awready[gen_wr]) ? 1'b1             :'h0;

      always_comb begin
        if ((gen_localparam[gen_wr].PC_REMAINS != 0) && (axi_write_cnt == 1)) begin
          m_axi4_awlen[gen_wr] = (aw_valid && m_axi4_awready[gen_wr]) ? gen_localparam[gen_wr].PC_REMAINS-1 : 'h0;
        end else begin
          m_axi4_awlen[gen_wr] = (aw_valid && m_axi4_awready[gen_wr]) ? MAX_BURST_SIZE-1 : 'h0;
        end
      end

      // Data channel -----------------------------------------------------------------------------
      logic axi_write;
      logic [$clog2(gen_localparam[gen_wr].PC_NB_WORDS):0] axi_word_cnt;

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
          if ((axi_write_cnt != 1) | (gen_localparam[gen_wr].PC_REMAINS == 0)) begin
            // when we are not in the last word or when we don't have remaining words (= only bursts)
            if (m_axi4_wlast[gen_wr]) begin
              axi_word_cnt <= MAX_BURST_SIZE;
            end else if (m_axi4_wvalid[gen_wr] & m_axi4_wready[gen_wr]) begin
              axi_word_cnt <= axi_word_cnt -1;
            end
          end else begin
            // when we don't have only bursts and have remaining words
            // we find how many are left and process them
            axi_word_cnt <= fifo_pc_wr_cnt;
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
  logic [$clog2(gen_localparam[0].PC_NB_WRITES + gen_localparam[1].PC_NB_WRITES):0] write_complete_cnt;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      write_complete_cnt <= 'h0;
    end else begin
      if (gen_ce_write[0].write_complete | gen_ce_write[1].write_complete ) begin
        write_complete_cnt <= write_complete_cnt +1;
      end else if(write_complete_cnt == (gen_localparam[0].PC_NB_WRITES + gen_localparam[1].PC_NB_WRITES)) begin
        write_complete_cnt <= 'h0;
      end
    end
  end

  assign itr_read_request = (write_complete_cnt == (gen_localparam[0].PC_NB_WRITES + gen_localparam[1].PC_NB_WRITES)) ? 1'b1 : 1'b0;

  // regf payload information ---------------------------------------------------------------------
  logic [REG_DATA_W-1:0] rr_in_data;
  logic                  rr_out_vld;

  assign rr_in_data = {received_dst_addr, 4'b0, received_hpu_id, received_iop_id};

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak theses parameters in package
    .WIDTH           (REG_DATA_W),
    .DEPTH           (XPM_MIN_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(NRX_REGF_MEMORY_TYPE)
  ) rr_resp_ram_rdy_vld_2clk (
    // Write Domain ports: MRMAC domain
    .in_clk   (clk_mrmac),
    .in_rstn  (resetn_mrmac),
    .in_data  (rr_in_data),
    .in_rdy   (/* UNUSED */),
    .in_vld   (itr_read_request),
    // Read Domain ports: CFG domain
    .out_clk  (clk_cfg),
    .out_rstn (resetn_cfg),
    .out_data (regf_read_payload),
    .out_rdy  (~interrupt_read_request),
    .out_vld  (rr_out_vld)
  );

  logic itr_rr_cfg;

  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      itr_rr_cfg <= 1'b0;
    end else begin
      if(rr_out_vld) begin
        itr_rr_cfg <= 1'b1;
      end else if (clear_interrupt_rr) begin
        itr_rr_cfg <= 1'b0;
      end
    end
  end

  assign interrupt_read_request = itr_rr_cfg;
endmodule
