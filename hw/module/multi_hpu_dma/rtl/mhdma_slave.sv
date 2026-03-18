// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : Multi-HPU-DMA Slave module
// ------------------------------------------------------------------------------------------------
// Reacts to decoded commands from the decoder and drives:
//   1) Notify-ACK path: acknowledges incoming notify requests via the formatter
//   2) Ciphertext Emission path: reads ciphertext data from HBM and streams it to the formatter
//
// Architecture overview:
//   - There are two FSMs : NRX (Notify RX) & CEM (Ciphertext EMission)
//   - A CDC FIFO (fifo_nrx_regf) bridges notify information from clk_mhdma to clk_mhdma_cfg.
//   - If fifo_nrx_regf is full we don't consume words from decoder FIFO
//   - PCs are processed sequentially (ar_pc_onehot / rd_pc_onehot), so a single
//     shared burst FSM, fifo_element, fifo_ram_rdy_vld and serialization pipeline is used.
//     Per-PC AXI4 IO is muxed/demuxed based on the active PC index.
//   - AXI4 read data (AXI4_DATA_W wide) is serialized into MRMAC_AXIS_W words before
//     being pushed into the CE FIFO for the formatter.
//
// Assumptions:
//   - CT_MEM_BYTES is page-aligned (used in phy_addr = base + ctId * CT_MEM_BYTES)
//   - AXI4_DATA_W is an integer multiple of MRMAC_AXIS_W
//   - The upstream decoder holds decoded_command stable while decoded_command_vld is high
//   - ciphertext_sent and notify_ack_sent are single-cycle pulses
//   - regf_ct_mem_addr is stable for the entire duration of a read operation
//   - ETH_PC >= 1
//
// ================================================================================================

module mhdma_slave
  import mhdma_pkg::*;                                         // for all mhdma modules
  import axi_if_mhdma_axi_pkg::*;                              // AXI4
  import axi_if_shell_axil_pkg::*;                             // REG_DATA_W
  import axi_if_common_param_pkg::*;                           // HBM page
  import pem_common_param_pkg::*;                              // CT_MEM_BYTES, AXI4_WORD_PER_PC*
#(
  parameter int CDC_SYNC_STAGES = 2
) (
  // Ethernet configuration interface -------------------------------------------------------------
  input  logic                                                   clk_mhdma_cfg,
  input  logic                                                   resetn_mhdma_cfg,
  // Ethernet fast clock interface ----------------------------------------------------------------
  input  logic                                                   clk_mhdma,
  input  logic                                                   resetn_mhdma,
  // Axi4 interface for NMU -----------------------------------------------------------------------
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]                    m_axi4_araddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]                    m_axi4_arlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]                    m_axi4_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]                    m_axi4_arburst,
  output logic [ETH_PC-1:0]                                      m_axi4_arvalid,
  input  logic [ETH_PC-1:0]                                      m_axi4_arready,
  output logic [ETH_PC-1:0][axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0] m_axi4_arid,

  input  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]                     m_axi4_rdata,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]                     m_axi4_rresp,
  input  logic [ETH_PC-1:0][axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0] m_axi4_rid,
  input  logic [ETH_PC-1:0]                                      m_axi4_rlast,
  input  logic [ETH_PC-1:0]                                      m_axi4_rvalid,
  output logic [ETH_PC-1:0]                                      m_axi4_rready,
  // regf interface -------------------------------------------------------------------------------
  input  logic [ETH_PC-1:0][2*REG_DATA_W-1:0]                    regf_ct_mem_addr,
  output logic             [  REG_DATA_W-1:0]                    regf_notify_req_id,
  output logic             [  REG_DATA_W-1:0]                    regf_notify_req_addr,
  // interrupt ------------------------------------------------------------------------------------
  input  logic                                                   clear_interrupt_notify,
  output logic                                                   interrupt_notify,
  // decoder interface ----------------------------------------------------------------------------
  input  command_t                                               decoded_command,
  input  logic                                                   decoded_command_vld,
  output logic                                                   decoded_command_rdy,
  // format interface -----------------------------------------------------------------------------
  output command_t                                               slave_command,
  output logic                                                   slave_command_vld,
  input  logic                                                   slave_command_rdy,

  output logic             [MRMAC_AXIS_W-1:0]                    ce_payload,
  output logic                                                   ce_vld,
  input  logic                                                   ce_rdy,

  input  logic                                                   ciphertext_sent,
  input  logic                                                   notify_ack_sent,
  // Error interface ------------------------------------------------------------------------------
  output slave_error_t                                           slave_error,
  input  logic                                                   rst_errors,
  // statistics -----------------------------------------------------------------------------------
  output slave_stat_t                                            stat,
  input  slave_stat_rst_t                                        stat_rst
);

  // =========================================================================================== //
  // Received
  // =========================================================================================== //
  logic received_notify;
  logic received_read_request;
  logic slave_rdy_notify;
  logic slave_rdy_read;

  assign received_notify       = (decoded_command.req_id == REQ_ID_NOTIFY);
  assign received_read_request = (decoded_command.req_id == REQ_ID_READ);

  // ==============================================================================================
  // Notify RX (NRX)
  // ==============================================================================================
  logic start_notify_ack;
  logic nrx_cmd_in_rdy;

  typedef enum logic [1:0] {
    NRX_XXX          = 'x,
    NRX_WAIT_REQUEST = 2'b00,
    NRX_TRANSMIT_ACK = 2'b10
  } st_nrx;

  st_nrx nrx_state;
  st_nrx nrx_next_state;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      nrx_state <= NRX_WAIT_REQUEST;
    end else begin
      nrx_state <= nrx_next_state;
    end
  end

  assign start_notify_ack = decoded_command_vld & slave_rdy_notify;

  always_comb begin
    nrx_next_state = NRX_XXX;
    case (nrx_state)
      NRX_WAIT_REQUEST:
        nrx_next_state = start_notify_ack ? NRX_TRANSMIT_ACK : NRX_WAIT_REQUEST;
      NRX_TRANSMIT_ACK:
        nrx_next_state = notify_ack_sent ? NRX_WAIT_REQUEST : NRX_TRANSMIT_ACK;
      default: nrx_next_state = NRX_WAIT_REQUEST;
    endcase
  end

  logic st_wait_notify;
  logic st_transmit_ack;

  assign st_wait_notify  = (nrx_state == NRX_WAIT_REQUEST);
  assign st_transmit_ack = (nrx_state == NRX_TRANSMIT_ACK);

  // Notify RX command queue --------------------------------------------------
  command_t nrx_cmd_fifo;
  logic     nrx_cmd_out_vld;
  logic     nrx_cmd_out_rdy;

  command_t nrx_cmd_in;
  logic     nrx_cmd_in_vld;

  assign nrx_cmd_in_vld = start_notify_ack;

  // command fifo for notify RX, received from decoder
  // Note: avoiding having multiple concurrent drivers by override req_id in combinational block
  always_comb begin
    nrx_cmd_in        = decoded_command;
    nrx_cmd_in.req_id = REQ_ID_NOTIFY_ACK;
  end

  fifo_ram_rdy_vld # (
    .WIDTH      ($bits(command_t)),
    .DEPTH      (NRX_DEPTH),
    .RAM_LATENCY(NRX_RAM_LATENCY)
  ) fifo_nrx_commands (
    .clk         (clk_mhdma),
    .s_rst_n     (resetn_mhdma),

    .in_data     (nrx_cmd_in),
    .in_vld      (nrx_cmd_in_vld),
    .in_rdy      (nrx_cmd_in_rdy),

    .out_data    (nrx_cmd_fifo),
    .out_vld     (nrx_cmd_out_vld),
    .out_rdy     (nrx_cmd_out_rdy),

    .almost_full (/* UNUSED */)
  );

  // Notify RX regfile interface --------------------------------------------------------
  logic nrx_regf_in_rdy;
  logic nrx_regf_write_enable;

  assign nrx_cmd_out_rdy = st_transmit_ack & slave_command_rdy & nrx_regf_in_rdy & (slave_command.req_id == REQ_ID_NOTIFY_ACK);
  assign nrx_regf_write_enable = nrx_cmd_out_vld & nrx_cmd_out_rdy;

  // CFG domain ----------------------------------------------------------------------------------
  logic [2*REG_DATA_W-1:0] nrx_regf_out_data;
  logic                    nrx_regf_out_rdy;
  logic                    nrx_regf_out_vld;

  // this fifo transforms rx commands into two 32 bit readable words for regfile
  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    .WIDTH           (2*REG_DATA_W),
    .DEPTH           (REQ_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(REQ_MEMORY_TYPE)
  ) fifo_nrx_regf (
    // Write Domain ports: MRMAC domain
    .in_clk      (clk_mhdma),
    .in_rstn     (resetn_mhdma),
    .in_data     ({nrx_cmd_fifo.iop_id, REQ_ID_NOTIFY, nrx_cmd_fifo.hpu_id, nrx_cmd_fifo.mode, nrx_cmd_fifo.flag, nrx_cmd_fifo.rsvd, nrx_cmd_fifo.dst_addr, nrx_cmd_fifo.src_addr}),
    .in_rdy      (nrx_regf_in_rdy),
    .in_vld      (nrx_regf_write_enable),
    .almost_full (/* UNUSED */),
    // Read Domain ports: CFG domain
    .out_clk     (clk_mhdma_cfg),
    .out_rstn    (resetn_mhdma_cfg),
    .out_data    (nrx_regf_out_data),
    .out_rdy     (nrx_regf_out_rdy),
    .out_vld     (nrx_regf_out_vld)
  );

  assign nrx_regf_out_rdy = clear_interrupt_notify;

  // directly to regif interface: upper word = req_id register, lower word = req_addr register
  assign regf_notify_req_id = nrx_regf_out_data[2*REG_DATA_W-1:REG_DATA_W];
  assign regf_notify_req_addr = nrx_regf_out_data[REG_DATA_W-1:0];
  assign interrupt_notify = nrx_regf_out_vld;

  // ==============================================================================================
  // Ciphertext EMission (CEM)
  // ==============================================================================================
  logic start_of_ct_emission;
  logic rreq_cmd_in_rdy;

  typedef enum logic [1:0] {
    CEM_XXX           = 'x,
    CEM_WAIT_REQUEST  = 2'b00,
    CEM_READ_N_SEND   = 2'b10
  } st_cem;

  st_cem cem_state;
  st_cem cem_next_state;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma)  begin
      cem_state <= CEM_WAIT_REQUEST;
    end else begin
      cem_state <= cem_next_state;
    end
  end

  assign start_of_ct_emission  = decoded_command_vld & slave_rdy_read;

  always_comb begin
    cem_next_state = CEM_XXX;
    case (cem_state)
      CEM_WAIT_REQUEST:
        cem_next_state = start_of_ct_emission ? CEM_READ_N_SEND : CEM_WAIT_REQUEST;
      CEM_READ_N_SEND:
        cem_next_state = ciphertext_sent ? CEM_WAIT_REQUEST : CEM_READ_N_SEND;
      default: cem_next_state = CEM_WAIT_REQUEST;
    endcase
  end

  logic st_wait_rr;
  logic st_read_send;

  assign st_wait_rr   = (cem_state == CEM_WAIT_REQUEST);
  assign st_read_send = (cem_state == CEM_READ_N_SEND);

  // sending command to read request command queue ------------------------------------------------
  command_t rreq_cmd_fifo;
  logic    rreq_cmd_out_vld;
  logic    rreq_cmd_out_rdy;

  command_t rreq_cmd_in;
  logic     rreq_cmd_in_vld;

  assign rreq_cmd_in_vld = start_of_ct_emission;

  always_comb begin
    rreq_cmd_in        = decoded_command;
    rreq_cmd_in.req_id = REQ_ID_EMISSION;
  end

  fifo_ram_rdy_vld # (
    .WIDTH      ($bits(command_t)),
    .DEPTH      (RREQ_CMD_DEPTH),
    .RAM_LATENCY(RREQ_CMD_RAM_LATENCY)
  ) rreq_command_queue (
    .clk         (clk_mhdma),
    .s_rst_n     (resetn_mhdma),

    .in_data     (rreq_cmd_in),
    .in_vld      (rreq_cmd_in_vld),
    .in_rdy      (rreq_cmd_in_rdy),

    .out_data    (rreq_cmd_fifo),
    .out_vld     (rreq_cmd_out_vld),
    .out_rdy     (rreq_cmd_out_rdy),

    .almost_full (/* UNUSED */)
  );

  assign rreq_cmd_out_rdy = st_read_send & slave_command_rdy & (slave_command.req_id == REQ_ID_EMISSION);

  // ==============================================================================================
  // Consuming Decoded commands
  // ==============================================================================================
  // We are ready when receiving a command while waiting for it, as long as fifo in_rdy is ready as well.
  // Added a self clearing condition to have a pulse
  // slave_rdy_notify : notify_accepted
  // slave_rdy_read   : read_accepted

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      slave_rdy_notify <= 1'b0;
    end else begin
      slave_rdy_notify <= decoded_command_vld & st_wait_notify & received_notify & nrx_cmd_in_rdy & ~slave_rdy_notify;
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      slave_rdy_read <= 1'b0;
    end else begin
      slave_rdy_read <= decoded_command_vld & st_wait_rr & received_read_request & rreq_cmd_in_rdy & ~slave_rdy_read;
    end
  end

  assign decoded_command_rdy = slave_rdy_notify | slave_rdy_read;

  // =========================================================================================== //
  // Read from HBM
  // =========================================================================================== //
  logic [SRC_ADDR_W-1:0] rr_ct_src_addr;
  logic                  rreq_cmd_consumed;

  // Adding pipeline stage to ease timing
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      rreq_cmd_consumed <= 1'b0;
    end else begin
      rreq_cmd_consumed <= rreq_cmd_out_rdy & rreq_cmd_out_vld;
    end
  end

  always_ff @(posedge clk_mhdma)
   rr_ct_src_addr <= rreq_cmd_fifo.src_addr;

  // - Computing physical address
  // phys_addr = hbm_pc_offset + ctId * CT_MEM_BYTES
  logic [ETH_PC-1:0] [AXI4_ADD_W-1:0] phy_addr;
  generate
    for (genvar gen_p=0; gen_p<ETH_PC; gen_p=gen_p+1) begin : gen_phy_addr
      always_ff @(posedge clk_mhdma)
        if (rreq_cmd_consumed)
          phy_addr[gen_p] <= regf_ct_mem_addr[gen_p] + (rr_ct_src_addr * CT_MEM_BYTES);
    end
  endgenerate

  // - Is read request ready
  logic rreq_ready;
  logic rreq_ready_tmp;
  logic rreq_ready_pulse;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      rreq_ready <= 1'b0;
    end else begin
      rreq_ready <= rreq_cmd_consumed;
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      rreq_ready_tmp <= 1'b0;
    end else begin
      rreq_ready_tmp <= rreq_ready;
    end
  end

  assign rreq_ready_pulse = rreq_ready & ~rreq_ready_tmp;

  // - How much words are there per PC to read
  logic [AXI4_WORD_PER_PC0_WW-1:0] axi4_word_per_path;
  logic                pc_transfer_done;
  logic                read_fifo_ready;
  logic [ETH_PC-1:0]   ar_pc_onehot;
  logic [ETH_PC-1:0]   rd_pc_onehot;
  logic [ETH_PC_W-1:0] ar_pc_idx;
  logic [ETH_PC_W-1:0] rd_pc_idx;

  always_comb begin
    ar_pc_idx = '0;
    for (int i = 0; i < ETH_PC; i++)
      if (ar_pc_onehot[i])
        ar_pc_idx = ETH_PC_W'(i);
  end

  always_comb begin
    rd_pc_idx = '0;
    for (int i = 0; i < ETH_PC; i++)
      if (rd_pc_onehot[i])
        rd_pc_idx = ETH_PC_W'(i);
  end

  assign axi4_word_per_path = (ar_pc_idx == 0) ? AXI4_WORD_PER_PC0_WW'(AXI4_WORD_PER_PC0) : AXI4_WORD_PER_PC0_WW'(AXI4_WORD_PER_PC);

  // Single shared burst FSM (AR channel) --------------------------------------------------------
  // Very similar to module pem_load burst generation.
  axi4_ar_if_t                     s0_axi;
  logic                            s0_axi_arvalid;
  logic                            s0_axi_arready;
  logic [AXI4_LEN_W:0]             req_axi_word_nb;

  logic [AXI4_WORD_PER_PC0_WW-1:0] req_axi_word_remain;
  logic [AXI4_WORD_PER_PC0_WW-1:0] req_axi_word_remainD;
  logic                            req_last_axi_word_remain;
  logic [AXI4_WORD_PER_PC0_WW-1:0] req_axi_word_remain_init;

  logic                            req_first_burst;
  logic                            req_first_burstD;

  logic                            req_send_axi_cmd;

  logic                            req_pc_ar_done;

  assign req_axi_word_remain_init = axi4_word_per_path;

  // req_axi_word_remainD is the same than pem_load but req_first_burst condition has been added
  assign req_axi_word_remainD = req_send_axi_cmd ?
                                req_last_axi_word_remain ? req_axi_word_remain_init : req_axi_word_remain - req_axi_word_nb :
                                req_first_burst ? req_axi_word_remain_init :
                                req_axi_word_remain;

  assign req_last_axi_word_remain = req_axi_word_remain == req_axi_word_nb;
  assign req_first_burstD     = req_send_axi_cmd ? req_last_axi_word_remain ? 1'b1 : 1'b0 : req_first_burst;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      req_axi_word_remain <= AXI4_WORD_PER_PC0_WW'(AXI4_WORD_PER_PC0);
      req_first_burst <= 1'b1;
    end else begin
      req_axi_word_remain <= req_axi_word_remainD;
      req_first_burst <= req_first_burstD;
    end
  end

  // Address calculation
  logic [AXI4_ADD_W-1:0]    req_add;
  logic [AXI4_ADD_W-1:0]    req_addD;
  logic [AXI4_ADD_W-1:0]    req_add_start;
  logic [PAGE_BYTES_WW-1:0] req_page_word_remain;

  assign req_add_start = req_first_burst ? phy_addr[ar_pc_idx] : req_add;
  assign req_addD      = req_send_axi_cmd ? req_add_start + req_axi_word_nb*AXI4_DATA_BYTES : req_add;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      req_add <= '0;
    end else begin
      req_add <= req_addD;
    end
  end

  // Page boundary aware burst sizing
  assign req_page_word_remain = PAGE_AXI4_DATA - req_add_start[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
  assign req_axi_word_nb      = req_page_word_remain < req_axi_word_remain ? req_page_word_remain : req_axi_word_remain;

  // AXI AR channel
  assign s0_axi.arid    = MHDMA_AXI_ARID;
  assign s0_axi.arsize  = AXI4_DATA_BYTES_W;
  assign s0_axi.arburst = AXI4B_INCR;
  assign s0_axi.araddr  = req_add_start;
  assign s0_axi.arlen   = req_axi_word_nb - 1;

  // Gate AR when ar_pc_onehot has advanced ahead of rd_pc_onehot: prevents issuing
  // AR to a HBM port whose rready is blocked (rready is demuxed by rd_pc_onehot).
  assign s0_axi_arvalid  = |ar_pc_onehot & (ar_pc_onehot == rd_pc_onehot);
  assign req_send_axi_cmd = s0_axi_arvalid & s0_axi_arready;

  assign req_pc_ar_done    = req_send_axi_cmd & req_last_axi_word_remain;
  assign pc_transfer_done = req_pc_ar_done;

  // Single fifo_element for AR pipeline register
  axi4_ar_if_t m_axi4_a;
  logic        fifo_ar_out_vld;
  logic        fifo_ar_out_rdy;

  fifo_element #(
    .WIDTH          ($bits(axi4_ar_if_t)),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) fifo_element_ar (
    .clk     (clk_mhdma),
    .s_rst_n (resetn_mhdma),

    .in_data (s0_axi),
    .in_vld  (s0_axi_arvalid),
    .in_rdy  (s0_axi_arready),

    .out_data(m_axi4_a),
    .out_vld (fifo_ar_out_vld),
    .out_rdy (fifo_ar_out_rdy)
  );

  // Demux AR outputs to per-PC AXI4 ports: drive active PC, tie others to 0/inactive
  // We register ar_pc_idx through the fifo_element latency using a shadow register
  logic [ETH_PC_W-1:0] ar_pc_idx_pipe;
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ar_pc_idx_pipe <= '0;
    end else if (s0_axi_arvalid & s0_axi_arready) begin
      ar_pc_idx_pipe <= ar_pc_idx;
    end
  end

  assign fifo_ar_out_rdy = m_axi4_arready[ar_pc_idx_pipe];

  generate
    for (genvar gen_rd = 0; gen_rd < ETH_PC; gen_rd++) begin : gen_ar_demux
      assign m_axi4_arvalid[gen_rd] = fifo_ar_out_vld & (ar_pc_idx_pipe == ETH_PC_W'(gen_rd));
      assign m_axi4_arid[gen_rd]    = m_axi4_a.arid;
      assign m_axi4_araddr[gen_rd]  = m_axi4_a.araddr;
      assign m_axi4_arlen[gen_rd]   = m_axi4_a.arlen;
      assign m_axi4_arsize[gen_rd]  = m_axi4_a.arsize;
      assign m_axi4_arburst[gen_rd] = m_axi4_a.arburst;
    end
  endgenerate

  // Single shared read data path (R channel) ----------------------------------------------------
  logic [AXI4_DATA_W-1:0] rdata_muxed;
  logic [AXI4_RESP_W-1:0] rresp_muxed;
  logic                   rvalid_muxed;

  assign rdata_muxed  = m_axi4_rdata[rd_pc_idx];
  assign rresp_muxed  = m_axi4_rresp[rd_pc_idx];
  assign rvalid_muxed = m_axi4_rvalid[rd_pc_idx];

  // Demux rready: only assert for the active PC
  logic rready_shared;

  generate
    for (genvar gen_rd = 0; gen_rd < ETH_PC; gen_rd++) begin : gen_rready_demux
      assign m_axi4_rready[gen_rd] = rd_pc_onehot[gen_rd] ? rready_shared : 1'b0;
    end
  endgenerate

  // rready: we read if and only if we are in ciphertext emission mode
  assign rready_shared = read_fifo_ready & st_read_send;

  logic read_fifo_we;
  assign read_fifo_we = rvalid_muxed & rready_shared;

  // Single fifo_ram_rdy_vld for read data
  logic [AXI4_DATA_W-1:0] read_fifo_out_data;
  logic                   read_fifo_out_valid;
  logic                   read_fifo_out_ready;

  fifo_ram_rdy_vld # (
    .WIDTH      (AXI4_DATA_W),
    .DEPTH      (FIFO_PC_DEPTH),
    .RAM_LATENCY(FIFO_PC_RAM_LATENCY)
  ) fifo_pc_read (
    .clk        (clk_mhdma),
    .s_rst_n    (resetn_mhdma),

    .in_data    (rdata_muxed),
    .in_vld     (read_fifo_we),
    .in_rdy     (read_fifo_ready),

    .out_data   (read_fifo_out_data),
    .out_vld    (read_fifo_out_valid),
    .out_rdy    (read_fifo_out_ready),

    .almost_full(/* UNUSED */)
  );

  // Single serialization pipeline (AXI4_DATA_W -> MRMAC_AXIS_W) -------------------------------
  // Dynamic word count for current read PC
  logic [AXI4_WORD_PER_PC0_WW-1:0] rd_word_per_path;

  assign rd_word_per_path = (rd_pc_idx == 0) ? AXI4_WORD_PER_PC0_WW'(AXI4_WORD_PER_PC0) : AXI4_WORD_PER_PC0_WW'(AXI4_WORD_PER_PC);

  // --- Serialization: AXI4_DATA_W -> MRMAC_AXIS_W, one narrow word per cycle with backpressure ---
  // Mirrors master deserialization pattern (deser_*) but in reverse direction (ser_*).
  logic [$clog2(NB_MRMAC_WORDS_PER_READ)-1:0] ser_cnt;            // emitted narrow-word index
  logic [AXI4_DATA_W-1:0]                       ser_word;         // registered wide word being serialized
  logic                                         ser_vld;          // wide word loaded, emission in progress
  logic                                         ser_last_beat;    // last narrow word being consumed
  logic                                         ser_handshake;    // narrow-word accepted by fifo_ce
  logic [AXI4_WORD_PER_PC0_WW-1:0]              ser_word_cnt;     // counts fully-serialized wide words per PC
  logic                                         pc_read_finished; // current PC fully serialized

  // Fifo CE input ready
  logic fifo_ce_in_rdy;

  // Handshake & last-beat (mirrors master's cerx_handshake / deser_last_beat)
  assign ser_handshake = ser_vld & fifo_ce_in_rdy;
  assign ser_last_beat = ser_handshake & (ser_cnt == NB_MRMAC_WORDS_PER_READ - 1);

  // ser_cnt: narrow word index 0..N-1 (mirrors deser_cnt)
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ser_cnt <= '0;
    end else begin
      if (ser_last_beat) begin
        ser_cnt <= '0;
      end else if (ser_handshake) begin
        ser_cnt <= ser_cnt + 1;
      end
    end
  end

  // ser_word: capture wide word from read FIFO (mirrors deser_word, but loads whole word at once)
  always_ff @(posedge clk_mhdma)
    if (read_fifo_out_ready & read_fifo_out_valid)
      ser_word <= read_fifo_out_data;

  // ser_vld: asserted when wide word loaded, cleared after last narrow beat (mirrors deser_vld)
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ser_vld <= 1'b0;
    end else if (ser_last_beat) begin
      ser_vld <= read_fifo_out_ready & read_fifo_out_valid;
    end else if (~ser_vld & read_fifo_out_ready & read_fifo_out_valid) begin
      ser_vld <= 1'b1;
    end
  end

  // Backpressure to upstream read FIFO (mirrors master's fifo_cerx_out_rdy)
  // Accept new wide word when serializer is idle or finishing last beat with downstream ready
  assign read_fifo_out_ready = (~ser_vld | (ser_last_beat & fifo_ce_in_rdy)) & (|rd_pc_onehot);

  // ser_word_cnt: counts fully-serialized wide words per PC (replaces read_fifo_out_cnt)
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      ser_word_cnt <= '0;
    end else begin
      if (pc_read_finished | rreq_ready_pulse) begin
        ser_word_cnt <= '0;
      end else if (ser_last_beat) begin
        ser_word_cnt <= ser_word_cnt + 1;
      end
    end
  end

  // pc_read_finished: last narrow word of last wide word consumed (replaces temp_finished_flag chain)
  assign pc_read_finished = ser_last_beat & (ser_word_cnt == rd_word_per_path - 1);

  // PC sequencing logic -------------------------------------------------------------------------
  // launch AR reads over PCs sequentially
  always_ff @(posedge clk_mhdma) begin : prc_read_one_at_a_time
    if (~resetn_mhdma) begin
      ar_pc_onehot <= 'h0;
    end else begin
      if (rreq_ready_pulse) begin
        ar_pc_onehot <= {{(ETH_PC-1){1'b0}}, 1'b1};
      end else if (ar_pc_onehot[ETH_PC-1] & pc_transfer_done) begin
        ar_pc_onehot <= 'h0;
      end else if (pc_transfer_done) begin
        ar_pc_onehot <= ar_pc_onehot << 1;
      end
    end
  end

  // we only have one QSFP lane interface, we will read each PC independently, one at a time
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      rd_pc_onehot <= 'h0;
    end else begin
      if (rreq_ready_pulse) begin
        rd_pc_onehot <= {{(ETH_PC-1){1'b0}}, 1'b1};
      end else if (rd_pc_onehot[ETH_PC-1] & pc_read_finished) begin
        rd_pc_onehot <= 'h0;
      end else if (pc_read_finished) begin
        rd_pc_onehot <= rd_pc_onehot << 1;
      end
    end
  end

  // Fifo Ciphertext Emission --------------------------------------------------------------------
  logic [MRMAC_AXIS_W-1:0] fifo_ce_in_data;
  logic                    fifo_ce_in_vld;

  assign fifo_ce_in_data = ser_word[ser_cnt * MRMAC_AXIS_W +: MRMAC_AXIS_W];
  assign fifo_ce_in_vld  = ser_vld;

  fifo_ram_rdy_vld # (
    .WIDTH      (MRMAC_AXIS_W   ),
    .DEPTH      (CT_NB_COEF     ),
    .RAM_LATENCY(CE_RAM_LATENCY ),
    .ALMOST_FULL_REMAIN (0)
  ) fifo_ce (
    .clk         (clk_mhdma),
    .s_rst_n     (resetn_mhdma),

    .in_data     (fifo_ce_in_data),
    .in_vld      (fifo_ce_in_vld),
    .in_rdy      (fifo_ce_in_rdy),

    .out_data    (ce_payload),
    .out_vld     (ce_vld),
    .out_rdy     (ce_rdy),
    .almost_full (/* UNUSED */)
  );

  // =========================================================================================== //
  // Interface to formatter
  // =========================================================================================== //
  // ACKs take precedence over read requests
  // we don't need dst_addr, flag & mode for ack
  always_ff @(posedge clk_mhdma) begin
    if (nrx_cmd_out_vld)  begin
      slave_command          <= nrx_cmd_fifo;
      slave_command.rsvd     <= 'h0;
      slave_command.flag     <= 'h0;
      slave_command.mode     <= 'h0;
      slave_command.dst_addr <= 'h0;
    end else if (rreq_cmd_out_vld) begin
      slave_command          <= rreq_cmd_fifo;
    end else begin
      slave_command          <= 'h0;
    end
  end

  // Slave_command_vld: set when either FIFO has data
  // These fifos have their data consumed when slave_command_rdy and correct fsm state is current
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      slave_command_vld <= 1'b0;
    end else begin
      slave_command_vld <= nrx_cmd_out_vld | rreq_cmd_out_vld;
    end
  end

  // =========================================================================================== //
  // Error detection
  // =========================================================================================== //
  // rreq_cmd_ovf_error: sticky flag, set when rreq_command_queue overflows
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      slave_error.rreq_cmd_ovf_error <= 1'b0;
    end else begin
      if (rst_errors) begin
        slave_error.rreq_cmd_ovf_error <= 1'b0;
      end else if (rreq_cmd_in_vld & ~rreq_cmd_in_rdy) begin
        slave_error.rreq_cmd_ovf_error <= 1'b1;
      end
    end
  end

  // read_rresp_error: sticky flag, set when rresp != OKAY during valid read transfer
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      slave_error.read_rresp_error <= 1'b0;
    end else begin
      if (rst_errors) begin
        slave_error.read_rresp_error <= 1'b0;
      end else if (rvalid_muxed & rready_shared & (rresp_muxed != AXI4_OKAY)) begin
        slave_error.read_rresp_error <= 1'b1;
      end
    end
  end

  // =========================================================================================== //
  // Statistics
  // =========================================================================================== //
  assign stat.fsm_notify_rx  = nrx_state;
  assign stat.fsm_cem        = cem_state;

  logic [REG_DATA_W-1:0] nb_read_to_hbm;
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      nb_read_to_hbm <= 'h0;
    end else begin
      if (stat_rst.nb_read_to_hbm) begin
        nb_read_to_hbm <= 'h0;
      end else begin
        if (|(m_axi4_arready & m_axi4_arvalid)) begin
          nb_read_to_hbm <= nb_read_to_hbm + 1;
        end
      end
    end
  end

  logic [ETH_PC-1:0][REG_DATA_W-1:0] nb_words_received_pc;
  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_i_nb_words_received
      always_ff @(posedge clk_mhdma) begin
        if (~resetn_mhdma) begin
          nb_words_received_pc[gen_i] <= 'h0;
        end else begin
          if (stat_rst.nb_words_received_pc[gen_i]) begin
            nb_words_received_pc[gen_i] <= 'h0;
          end else begin
            if (rd_pc_onehot[gen_i] & rvalid_muxed & rready_shared) begin
              nb_words_received_pc[gen_i] <= nb_words_received_pc[gen_i] + 1;
            end
          end
        end
      end
    end
  endgenerate

  // time waiting for words per pc
  logic [ETH_PC-1:0]                 t_wait_words_en;
  logic [ETH_PC-1:0][REG_DATA_W-1:0] t_rr_wait_words_pc;
  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_i_t_wait_for_words_pc

      // note that if we read several times we will include it in the counter
      always_ff @(posedge clk_mhdma) begin
        if (~resetn_mhdma) begin
          t_wait_words_en[gen_i] <= 1'b0;
        end else begin
          if (m_axi4_arvalid[gen_i]) begin
            t_wait_words_en[gen_i] <= 1'b1;
          end else if (rd_pc_onehot[gen_i] & rvalid_muxed) begin
            t_wait_words_en[gen_i] <= 1'b0;
          end
        end
      end

      always_ff @(posedge clk_mhdma) begin
        if (~resetn_mhdma) begin
          t_rr_wait_words_pc[gen_i] <= 'h0;
        end else begin
          if(t_wait_words_en[gen_i]) begin
            t_rr_wait_words_pc[gen_i] <= t_rr_wait_words_pc[gen_i] +1;
          end
        end
      end
    end
  endgenerate

  assign stat.rr_phy_addr           = phy_addr;
  assign stat.nb_read_to_hbm        = nb_read_to_hbm;
  assign stat.nb_words_received_pc  = nb_words_received_pc;
  assign stat.t_rr_wait_words_pc    = t_rr_wait_words_pc;

endmodule
