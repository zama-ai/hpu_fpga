// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU-DMA Slave module
// ----------------------------------------------------------------------------------------------
// Must react to decoded commands
//
// This module handles the logic around ciphertext emission and Notify ack
// ==============================================================================================

module mhdma_slave
  import mhdma_pkg::*;               // for all mhdma modules
  import axi_if_eth_axi_pkg::*;      // AXI4
  import axi_if_shell_axil_pkg::*;   // REG_DATA_W
  import axi_if_common_param_pkg::*; // HBM page
  import pem_common_param_pkg::*;    // CT_MEM_BYTES, AXI4_WORD_PER_PC*
#(
  parameter int   CDC_SYNC_STAGES = 2
) (
  // Ethernet configuration interface -----------------------------------------
  input  logic                                clk_cfg,
  input  logic                                resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                clk_mrmac,
  input  logic                                resetn_mrmac,
  // Axi4 interface for NMU ---------------------------------------------------
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]                  m_axi4_araddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]                  m_axi4_arlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]                  m_axi4_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]                  m_axi4_arburst,
  output logic [ETH_PC-1:0]                                    m_axi4_arvalid,
  input  logic [ETH_PC-1:0]                                    m_axi4_arready,
  output logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ID_W-1:0] m_axi4_arid,

  input  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]                   m_axi4_rdata,
  input  logic [ETH_PC-1:0]                                    m_axi4_rlast,
  input  logic [ETH_PC-1:0]                                    m_axi4_rvalid,
  output logic [ETH_PC-1:0]                                    m_axi4_rready,
  // regf interface -----------------------------------------------------------
  input  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr,
  output logic             [  REG_DATA_W-1:0] regf_notify_req_id,
  output logic             [  REG_DATA_W-1:0] regf_notify_req_addr,
  // interrupt ----------------------------------------------------------------
  input  logic                                clear_interrupt_notify,
  output logic                                interrupt_notify,
  // decoder interface --------------------------------------------------------
  input  command_t                            decoded_command,
  input  logic                                decoded_command_vld,
  output logic                                decoded_command_rdy,
  // format interface ---------------------------------------------------------
  output command_t                            slave_command,
  output logic                                slave_command_vld,
  input  logic                                slave_command_rdy,

  output logic             [MRMAC_AXIS_W-1:0] ce_payload,
  output logic                                ce_vld,
  input  logic                                ce_rdy,

  input  logic                                ciphertext_sent,
  input  logic                                notify_ack_sent,
  // Error interface ----------------------------------------------------------
  output slave_error_t                        slave_error,
  input  logic                                rst_errors,
  // statistics ---------------------------------------------------------------
  output slave_stat_t                         stat,
  input  slave_stat_rst_t                     stat_rst
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int NB_MRMRAC_WORDS_PER_READ = AXI4_DATA_W/MRMAC_AXIS_W;

  // =========================================================================================== //
  // Received
  // =========================================================================================== //
  logic received_notify;
  logic received_read_request;

  assign received_notify       = (decoded_command.req_id == REQ_ID_NOTIFY);
  assign received_read_request = (decoded_command.req_id == REQ_ID_READ);

  // ==============================================================================================
  // Notify RX (NRX)
  // ==============================================================================================
  logic start_notify_ack;
  logic nrx_cmd_in_rdy;
  logic st_wait_notify;
  logic st_transmit_ack;
  logic st_nrx_got_request;

  // => must transmit to regfile IOP_ID, HPU_ID and src_addr
  // => must trigger interrupt signal when registers are ready to be read
  typedef enum logic [1:0] {
    NRX_XXX          = 'x,
    NRX_WAIT_REQUEST = 2'b00,
    NRX_GOT_REQUEST  = 2'b01,
    NRX_TRANSMIT_ACK = 2'b10
  } st_nrx;

  st_nrx nrx_state;
  st_nrx nrx_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) nrx_state <= NRX_WAIT_REQUEST;
    else nrx_state <= nrx_next_state;
  end

  assign start_notify_ack = decoded_command_vld & received_notify;

  always_comb begin
    nrx_next_state = NRX_XXX;
    case (nrx_state)
      NRX_WAIT_REQUEST:
        nrx_next_state = start_notify_ack ? NRX_GOT_REQUEST : NRX_WAIT_REQUEST;
      NRX_GOT_REQUEST:
        nrx_next_state = nrx_cmd_in_rdy ? NRX_TRANSMIT_ACK : NRX_GOT_REQUEST;
      NRX_TRANSMIT_ACK:
        nrx_next_state = notify_ack_sent ? NRX_WAIT_REQUEST : NRX_TRANSMIT_ACK;
    endcase
  end

  assign st_wait_notify     = (nrx_state == NRX_WAIT_REQUEST);
  assign st_nrx_got_request = (nrx_state == NRX_GOT_REQUEST);
  assign st_transmit_ack    = (nrx_state == NRX_TRANSMIT_ACK);

  // Notify RX command queue --------------------------------------------------
  logic     nrx_cmd_in_vld;
  logic     nrx_cmd_out_vld;
  logic     nrx_cmd_out_rdy;
  command_t nrx_cmd_fifo;

  assign nrx_cmd_in_vld = st_nrx_got_request;

  // command fifo for notify RX, received from decoder
  fifo_ram_rdy_vld # (
    .WIDTH      (DST_ADDR_W+SRC_ADDR_W+HPU_ID_W+IOP_ID_W+RSVD_W+FLAG_W+MODE_W+REQ_ID_W),
    .DEPTH      (NRX_DEPTH),
    .RAM_LATENCY(NRX_RAM_LATENCY)
  ) fifo_nrx_commands (
    .clk         (clk_mrmac),
    .s_rst_n     (resetn_mrmac),

    .in_data     ({decoded_command.dst_addr, decoded_command.src_addr, decoded_command.hpu_id, decoded_command.iop_id, decoded_command.rsvd, decoded_command.flag, decoded_command.mode, REQ_ID_NOTIFY_ACK}),
    .in_vld      (nrx_cmd_in_vld),
    .in_rdy      (nrx_cmd_in_rdy),

    .out_data    ({nrx_cmd_fifo.dst_addr, nrx_cmd_fifo.src_addr, nrx_cmd_fifo.hpu_id, nrx_cmd_fifo.iop_id, nrx_cmd_fifo.rsvd, nrx_cmd_fifo.flag, nrx_cmd_fifo.mode, nrx_cmd_fifo.req_id}),
    .out_vld     (nrx_cmd_out_vld),
    .out_rdy     (nrx_cmd_out_rdy),

    .almost_full (/* UNUSED */)
  );

  logic error_fifo_nrx_commands_ovf;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      error_fifo_nrx_commands_ovf <= 1'b0;
    end else begin
      if (rst_errors) begin
        error_fifo_nrx_commands_ovf <= 1'b0;
      end else begin
        if ( nrx_cmd_in_vld & ~nrx_cmd_in_rdy) begin
          error_fifo_nrx_commands_ovf <= 1'b1;
        end
      end
    end
  end

  // Notify RX regfile interface --------------------------------------------------------
  logic nrx_regf_in_rdy;
  logic nrx_regf_write_enable;

  assign nrx_cmd_out_rdy = st_transmit_ack & slave_command_rdy & nrx_regf_in_rdy;
  assign nrx_regf_write_enable = nrx_cmd_out_vld & nrx_cmd_out_rdy;

  // === CFG domain
  logic [2*REG_DATA_W-1:0] nrx_regf_out_data;
  logic                    nrx_regf_out_rdy;
  logic                    nrx_regf_out_vld;

  // this fifo transforms rx commands into two 32 bit readable words for regfile
  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak theses parameters in package
    .WIDTH           (2*REG_DATA_W),
    .DEPTH           (REQ_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(REQ_MEMORY_TYPE)
  ) fifo_nrx_regf (
    // Write Domain ports: MRMAC domain
    .in_clk      (clk_mrmac),
    .in_rstn     (resetn_mrmac),
    .in_data     ({nrx_cmd_fifo.iop_id, REQ_ID_NOTIFY, nrx_cmd_fifo.hpu_id, nrx_cmd_fifo.mode, nrx_cmd_fifo.flag, nrx_cmd_fifo.rsvd, nrx_cmd_fifo.dst_addr, nrx_cmd_fifo.src_addr}),
    .in_rdy      (nrx_regf_in_rdy),
    .in_vld      (nrx_regf_write_enable),
    .almost_full (/* UNUSED */),
    // Read Domain ports: CFG domain
    .out_clk     (clk_cfg),
    .out_rstn    (resetn_cfg),
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
  // FSM ------------------------------------------------------------------------------------------
  logic start_of_ct_emission;
  logic rreq_cmd_in_rdy;
  logic st_wait_rr;
  logic st_read_send;
  logic st_got_read_req;

  typedef enum logic [1:0] {
    CEM_XXX           = 'x,
    CEM_WAIT_REQUEST  = 2'b00,
    CEM_GOT_REQUEST   = 2'b01,
    CEM_READ_N_SEND   = 2'b10
  } st_cem;

  st_cem cem_state;
  st_cem cem_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) cem_state <= CEM_WAIT_REQUEST;
    else cem_state <= cem_next_state;
  end

  assign start_of_ct_emission  = decoded_command_vld & received_read_request;

  always_comb begin
    cem_next_state = CEM_XXX;
    case (cem_state)
      CEM_WAIT_REQUEST:
        cem_next_state = start_of_ct_emission ? CEM_GOT_REQUEST : CEM_WAIT_REQUEST;
      CEM_GOT_REQUEST:
        cem_next_state = rreq_cmd_in_rdy ? CEM_READ_N_SEND : CEM_GOT_REQUEST;
      CEM_READ_N_SEND:
        cem_next_state = ciphertext_sent ? CEM_WAIT_REQUEST : CEM_READ_N_SEND;
    endcase
  end

  assign st_wait_rr      = (cem_state == CEM_WAIT_REQUEST);
  assign st_got_read_req = (cem_state == CEM_GOT_REQUEST);
  assign st_read_send    = (cem_state == CEM_READ_N_SEND);

  // sending command to read request command queue ------------------------------------------------
  // when qsfp tlast is ready we are sure that all commands have been correctly received
  // we need to pass along:
  //    > HPU ID
  //    > IOP ID
  //    > DST ADDR
  //    > SRC ADDR
  //   => REQ ID must be switched from read request to ciphertext emission
  logic    rreq_cmd_in_vld;

  command_t rreq_cmd_fifo;
  logic    rreq_cmd_out_vld;
  logic    rreq_cmd_out_rdy;

  assign rreq_cmd_in_vld = st_got_read_req;

  fifo_ram_rdy_vld # (
    .WIDTH      (HPU_ID_W+IOP_ID_W+RSVD_W+FLAG_W+MODE_W+DST_ADDR_W+SRC_ADDR_W+REQ_ID_W),
    .DEPTH      (RREQ_CMD_DEPTH),
    .RAM_LATENCY(RREQ_CMD_RAM_LATENCY)
  ) rreq_command_queue (
    .clk         (clk_mrmac),
    .s_rst_n     (resetn_mrmac),

    .in_data     ({decoded_command.hpu_id, decoded_command.iop_id, decoded_command.rsvd, decoded_command.flag, decoded_command.mode, decoded_command.dst_addr, decoded_command.src_addr, REQ_ID_EMISSION}),
    .in_vld      (rreq_cmd_in_vld),
    .in_rdy      (rreq_cmd_in_rdy),

    .out_data    ({rreq_cmd_fifo.hpu_id, rreq_cmd_fifo.iop_id, rreq_cmd_fifo.rsvd, rreq_cmd_fifo.flag, rreq_cmd_fifo.mode, rreq_cmd_fifo.dst_addr, rreq_cmd_fifo.src_addr, rreq_cmd_fifo.req_id}),
    .out_vld     (rreq_cmd_out_vld),
    .out_rdy     (rreq_cmd_out_rdy),

    .almost_full (/* UNUSED */)
  );

  always_ff @(posedge clk_mrmac)
    rreq_cmd_out_rdy <= st_read_send & slave_command_rdy;

  logic [RQQ_CMD_DATA_COUNT_W-1:0] rreq_cnt;
  logic                            rreq_cnt_down;
  logic                            rreq_cnt_up;

  assign rreq_cnt_down = rreq_cmd_out_vld & rreq_cmd_out_rdy;
  assign rreq_cnt_up   = rreq_cmd_in_vld & rreq_cmd_in_rdy;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rreq_cnt <= 'h0;
    end else begin
      if (rreq_cnt_up & ~rreq_cnt_down) begin
        rreq_cnt <= rreq_cnt + 1;
      end else if (rreq_cnt_down & ~rreq_cnt_up) begin
        rreq_cnt <= rreq_cnt - 1;
      end
    end
  end

  // ==============================================================================================
  // Consuming Decoded commands
  // ==============================================================================================
  assign decoded_command_rdy = (st_nrx_got_request & ~st_read_send) | (st_got_read_req & ~st_transmit_ack);

  // =========================================================================================== //
  // Read into HBM
  // all @mrmac domain
  // =========================================================================================== //
  logic [SRC_ADDR_W-1:0] rr_ct_src_addr;
  logic [DST_ADDR_W-1:0] rr_ct_dst_addr;

  assign rr_ct_dst_addr = rreq_cmd_fifo.dst_addr;
  assign rr_ct_src_addr = rreq_cmd_fifo.src_addr;

  // phys_addr = hbm_pc_offset + ctId * CT_MEM_BYTES
  logic [ETH_PC-1:0] [AXI4_ADD_W-1:0] phy_addr;
  logic [ETH_PC-1:0]                  phy_addr_valid;
  generate
    for (genvar gen_p=0; gen_p<ETH_PC; gen_p=gen_p+1) begin : gen_phy_addr
      always_ff @(posedge clk_mrmac)
        if (rreq_cmd_out_rdy & rreq_cmd_out_vld)
          phy_addr[gen_p] <= regf_ct_mem_addr[gen_p] + (rr_ct_src_addr * CT_MEM_BYTES);

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          phy_addr_valid[gen_p] <= 'h0;
        end else begin
          phy_addr_valid[gen_p] <= rreq_cmd_out_rdy & rreq_cmd_out_vld;
        end
      end
    end
  endgenerate

  // Is read request ready ------------------------------------------------------------------------
  // flag that states that read request is ready
  logic rreq_ready;
  logic rreq_ready_tmp;
  always_ff @(posedge clk_mrmac)
    rreq_ready <= rreq_cmd_out_vld & rreq_cmd_out_rdy;
  always_ff @(posedge clk_mrmac)
    rreq_ready_tmp <= rreq_ready;

  logic rreq_ready_pulse;
  assign rreq_ready_pulse = rreq_ready & ~rreq_ready_tmp;

  // process an axi4-read on each PC --------------------------------------------------------------
  // We must read each PC one by one
  logic [ETH_PC-1:0] axi4_read_pc;        // this signal is a one hot selecting PC that we want to use
  logic [ETH_PC-1:0] pc_transfer_done;    // signal when PC transfer is complete
  logic [ETH_PC-1:0] read_fifo_ready;     // ready from receiving FIFO

  generate
    for (genvar gen_rd=0; gen_rd<ETH_PC; gen_rd++) begin : gen_ce_reads
      // Per-PC parameters
      localparam int AXI4_WORD_PER_PATH    = (gen_rd == 0) ? AXI4_WORD_PER_PC0 : AXI4_WORD_PER_PC;
      localparam int AXI4_WORD_PER_PATH_W  = $clog2(AXI4_WORD_PER_PATH) == 0 ? 1 : $clog2(AXI4_WORD_PER_PATH);
      localparam int AXI4_WORD_PER_PATH_WW = $clog2(AXI4_WORD_PER_PATH+1) == 0 ? 1 : $clog2(AXI4_WORD_PER_PATH+1);

      // AXI interface
      axi4_ar_if_t                       axi_ar;
      logic                              axi_arvalid;
      logic                              axi_arready;
      logic [AXI4_LEN_W:0]               req_axi_word_nb; // = axi_len + 1

      // Counters for dynamic burst sizing
      logic [AXI4_WORD_PER_PATH_WW-1:0]  req_axi_word_remain;
      logic [AXI4_WORD_PER_PATH_WW-1:0]  req_axi_word_remainD;
      logic                              req_last_axi_word_remain;
      logic [AXI4_WORD_PER_PATH_WW-1:0]  req_axi_word_remain_init;

      logic                              req_pbs_first_burst;
      logic                              req_pbs_first_burstD;

      logic                              req_send_axi_cmd;

      assign req_axi_word_remainD     = req_send_axi_cmd ?
                                            req_last_axi_word_remain ? req_axi_word_remain_init : req_axi_word_remain - req_axi_word_nb :
                                            req_axi_word_remain;
      assign req_last_axi_word_remain = req_axi_word_remain == req_axi_word_nb;
      assign req_axi_word_remain_init = AXI4_WORD_PER_PATH;
      assign req_pbs_first_burstD     = req_send_axi_cmd ? req_last_axi_word_remain ? 1'b1 : 1'b0 : req_pbs_first_burst;

      always_ff @(posedge clk_mrmac)
        if (~resetn_mrmac) begin
          req_axi_word_remain <= AXI4_WORD_PER_PATH;
          req_pbs_first_burst <= 1'b1;
        end
        else begin
          req_axi_word_remain <= req_axi_word_remainD;
          req_pbs_first_burst <= req_pbs_first_burstD;
        end

      // Address calculation
      logic [AXI4_ADD_W-1:0]    req_add;
      logic [AXI4_ADD_W-1:0]    req_addD;
      logic [AXI4_ADD_W-1:0]    req_add_start;
      logic [PAGE_BYTES_WW-1:0] req_page_word_remain;

      assign req_add_start = req_pbs_first_burst ? phy_addr[gen_rd] : req_add;
      assign req_addD      = req_send_axi_cmd ? req_add_start + req_axi_word_nb*AXI4_DATA_BYTES : req_add;

      always_ff @(posedge clk_mrmac)
        if (~resetn_mrmac) req_add <= '0;
        else               req_add <= req_addD;

      // Page boundary aware burst sizing
      assign req_page_word_remain = PAGE_AXI4_DATA - req_add_start[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
      assign req_axi_word_nb      = req_page_word_remain < req_axi_word_remain ? req_page_word_remain : req_axi_word_remain;

      // AXI AR channel
      assign axi_ar.arid    = MHDMA_AXI_ARID;
      assign axi_ar.arsize  = AXI4_DATA_BYTES_W;
      assign axi_ar.arburst = AXI4B_INCR;
      assign axi_ar.araddr  = req_add_start;
      assign axi_ar.arlen   = req_axi_word_nb - 1;

      assign axi_arvalid    = axi4_read_pc[gen_rd] & (req_axi_word_remain > 0);
      assign req_send_axi_cmd = axi_arvalid & axi_arready;

      // PC transfer done when last address command sent
      assign pc_transfer_done[gen_rd] = req_send_axi_cmd & req_last_axi_word_remain;

      axi4_ar_if_t m_axi4_a;

      fifo_element #(
        .WIDTH          ($bits(axi4_ar_if_t)),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) fifo_element_address_read (
        .clk     (clk_mrmac   ),
        .s_rst_n (resetn_mrmac),

        .in_data (axi_ar),
        .in_vld  (axi_arvalid),
        .in_rdy  (axi_arready),

        .out_data(m_axi4_a),
        .out_vld (m_axi4_arvalid[gen_rd]),
        .out_rdy (m_axi4_arready[gen_rd])
      );

      assign m_axi4_arid[gen_rd]    = m_axi4_a.arid;
      assign m_axi4_araddr[gen_rd]  = m_axi4_a.araddr;
      assign m_axi4_arlen[gen_rd]   = m_axi4_a.arlen;
      assign m_axi4_arsize[gen_rd]  = m_axi4_a.arsize;
      assign m_axi4_arburst[gen_rd] = m_axi4_a.arburst;

    end
  endgenerate

  // Reception FIFOs for both PC ports ------------------------------------------------------------
  // one hot value that selects which PC is selected to be read and sent to QSFP lane
  // always start with PC0
  logic [ETH_PC-1:0]                   reading_which_pc;
  logic [ETH_PC-1:0]                   fifo_ce_pc_in_rdy;
  logic [ETH_PC-1:0][MRMAC_AXIS_W-1:0] fifo_ce_pc_in_data;
  logic [ETH_PC-1:0]                   fifo_ce_pc_in_vld;

  generate
    for (genvar gen_rd=0; gen_rd<ETH_PC; gen_rd++) begin : gen_read_fifo
      // Since PEM_PC | AXI4_WORD_PER_BLWE, the body is processed by PC0
      localparam int AXI4_WORD_PER_PATH    = (gen_rd == 0) ? AXI4_WORD_PER_PC0 : AXI4_WORD_PER_PC;
      localparam int AXI4_WORD_PER_PATH_W  = (gen_rd == 0) ? AXI4_WORD_PER_PC0_W : AXI4_WORD_PER_PC_W;
      localparam int AXI4_WORD_PER_PATH_WW = (gen_rd == 0) ? AXI4_WORD_PER_PC0_WW : AXI4_WORD_PER_PC_WW;

      // input part
      logic                   read_fifo_we;
      // output part
      logic [AXI4_DATA_W-1:0] read_fifo_out_data;
      logic                   read_fifo_out_valid;
      logic                   read_fifo_out_ready;

      // we read if and only if we are in ciphertext emission mode
      assign m_axi4_rready[gen_rd] = read_fifo_ready[gen_rd] & st_read_send;

      assign read_fifo_we = m_axi4_rvalid[gen_rd] & m_axi4_rready[gen_rd];

      fifo_ram_rdy_vld # (
        .WIDTH      (AXI4_DATA_W),
        .DEPTH      (FIFO_PC_DEPTH),
        .RAM_LATENCY(FIFO_PC_RAM_LATENCY)
      ) fifo_pc_read (
        .clk         (clk_mrmac),
        .s_rst_n     (resetn_mrmac),

        .in_data     (m_axi4_rdata[gen_rd]),
        .in_vld      (read_fifo_we),
        .in_rdy      (read_fifo_ready[gen_rd]),

        .out_data    (read_fifo_out_data),
        .out_vld     (read_fifo_out_valid),
        .out_rdy     (read_fifo_out_ready),

        .almost_full (/* UNUSED */)
      );

      // we are going to read 4 times slower the fifo than we are feeding it
      logic [$clog2(NB_MRMRAC_WORDS_PER_READ)-1:0] slow_pace_count;
      logic [AXI4_WORD_PER_PATH_WW-1:0]            read_fifo_out_cnt;
      logic                                        pc_read_finished;

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          slow_pace_count <= 'h0;
        end else begin
          // If we want to read to this PC & the fifo is not empty
          if (reading_which_pc[gen_rd]) begin
            if (read_fifo_out_valid) begin
              slow_pace_count <= slow_pace_count + 1;
            end
          end else begin
            slow_pace_count <= 'h0;
          end
        end
      end

      always_ff @(posedge clk_mrmac) begin
        if(~resetn_mrmac) begin
          read_fifo_out_cnt <= 'h0;
        end else begin
          if (read_fifo_out_ready & read_fifo_out_valid) begin
            read_fifo_out_cnt <= read_fifo_out_cnt + 1;
          end else if (read_fifo_out_cnt == AXI4_WORD_PER_PATH) begin
            read_fifo_out_cnt <= 'h0;
          end
        end
      end

      // because in one read we have NB_MRMRAC_WORDS_PER_READ, we must delay the signal pc_read_finished
      logic [NB_MRMRAC_WORDS_PER_READ-1:0] temp_finished_flag;

      always_ff @(posedge clk_mrmac)
        temp_finished_flag[0] <= (read_fifo_out_cnt == AXI4_WORD_PER_PATH);

      for (genvar gen_i = 1; gen_i<NB_MRMRAC_WORDS_PER_READ; gen_i++) begin : gen_temp_finished_flag
        always_ff @(posedge clk_mrmac)
          temp_finished_flag[gen_i] <= temp_finished_flag[gen_i-1];
      end

      assign pc_read_finished = temp_finished_flag[NB_MRMRAC_WORDS_PER_READ-1];

      // read word each 4 clock cycles, we trigger at 1 as slow_pace_count default is 0
      assign read_fifo_out_ready = (slow_pace_count == 1) && reading_which_pc[gen_rd] & fifo_ce_pc_in_rdy[gen_rd];

      logic [NB_MRMRAC_WORDS_PER_READ-1:0][MRMAC_AXIS_W-1:0] ce_data_out;

      for (genvar gen_i=0; gen_i<NB_MRMRAC_WORDS_PER_READ; gen_i++) begin : gen_ce_data_out
        always_ff @(posedge clk_mrmac) begin
          if(read_fifo_out_ready & read_fifo_out_valid) begin
            ce_data_out[gen_i] <= read_fifo_out_data[(gen_i+1)*MRMAC_AXIS_W-1:gen_i*MRMAC_AXIS_W];
          end
        end
      end

      logic [NB_MRMRAC_WORDS_PER_READ-1:0] temp_rdy_vld;

      always_ff @(posedge clk_mrmac)
        temp_rdy_vld[0] <= read_fifo_out_ready & read_fifo_out_valid;

      for (genvar gen_i = 1; gen_i<NB_MRMRAC_WORDS_PER_READ; gen_i++) begin : gen_temp_rdy_vld
        always_ff @(posedge clk_mrmac)
          temp_rdy_vld[gen_i] <= temp_rdy_vld[gen_i-1];
      end

      logic [$clog2(NB_MRMRAC_WORDS_PER_READ)-1:0] realign_cnt;
      logic                                        start_deserialize;

      always_ff @(posedge clk_mrmac) begin
        if(~resetn_mrmac)begin
          start_deserialize <= 1'b0;
        end else begin
          if (reading_which_pc[gen_rd] & (read_fifo_out_valid & read_fifo_out_ready)) begin
            start_deserialize <= 1'b1;
          end else if (temp_rdy_vld[NB_MRMRAC_WORDS_PER_READ-1]) begin
            start_deserialize <= 1'b0;
          end
        end
      end

      always_ff @(posedge clk_mrmac) begin
        if(~resetn_mrmac) begin
          realign_cnt <= 'h0;
        end else begin
          if (start_deserialize) begin
            realign_cnt <= realign_cnt + 1;
            // we need to take into account that ce_data_out arrives one cc later
          end else begin
            realign_cnt <= 'h0;
          end
        end
      end

      // always_ff @(posedge clk_mrmac)
      assign fifo_ce_pc_in_data[gen_rd] = ce_data_out[realign_cnt];

      // always_ff @(posedge clk_mrmac)
      assign fifo_ce_pc_in_vld[gen_rd] = start_deserialize;

    end
  endgenerate

  // which PC must be read ------------------------------------------------------------------------
  // Track data reception per PC (count rlast signals to know when all data received)
  logic [ETH_PC-1:0] finished_reading_pc;
  generate
    for (genvar gen_rd=0; gen_rd<ETH_PC; gen_rd++) begin : gen_control_pc
      // Since PEM_PC | AXI4_WORD_PER_BLWE, the body is processed by PC0
      localparam int AXI4_WORD_PER_PATH    = (gen_rd == 0) ? AXI4_WORD_PER_PC0 : AXI4_WORD_PER_PC;
      localparam int AXI4_WORD_PER_PATH_WW = $clog2(AXI4_WORD_PER_PATH+1) == 0 ? 1 : $clog2(AXI4_WORD_PER_PATH+1);

      logic [AXI4_WORD_PER_PATH_WW-1:0] r_word_cnt;
      // Track how many words have been received
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          r_word_cnt <= 'h0;
        end else begin
          if (m_axi4_rvalid[gen_rd] & m_axi4_rready[gen_rd]) begin
            if (r_word_cnt == AXI4_WORD_PER_PATH - 1)
              r_word_cnt <= 'h0;
            else
              r_word_cnt <= r_word_cnt + 1;
          end
        end
      end

      assign finished_reading_pc[gen_rd] = m_axi4_rvalid[gen_rd] & m_axi4_rready[gen_rd] & (r_word_cnt == AXI4_WORD_PER_PATH - 1);
    end
  endgenerate

  // launch reads over PCs sequentially
  always_ff @(posedge clk_mrmac) begin : prc_read_one_at_a_time
    if (~resetn_mrmac) begin
      axi4_read_pc <= 'h0;
    end else begin
      if (rreq_ready_pulse) begin
        axi4_read_pc <= {{(ETH_PC-1){1'b0}}, 1'b1};
      end else if (pc_transfer_done[ETH_PC-1]) begin
        axi4_read_pc <= 'h0;
      end else if (|pc_transfer_done) begin
        axi4_read_pc <= axi4_read_pc << 1;
      end
    end
  end

  // we only have one QSFP lane interface, we will read each PC FIFO independently, one at a time
  logic [ETH_PC-1:0] pc_read_finished;
  logic              any_pc_read_finished;

  generate
    for (genvar gen_i = 0; gen_i < ETH_PC; gen_i++) begin : gen_pc_rd_fin
      assign pc_read_finished[gen_i] = gen_read_fifo[gen_i].pc_read_finished;
    end
  endgenerate

  assign any_pc_read_finished = |pc_read_finished;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      reading_which_pc <= 'h0;
    end else begin
      if (rreq_ready_pulse) begin
        reading_which_pc <= {{(ETH_PC-1){1'b0}}, 1'b1};
      end else if (any_pc_read_finished) begin
        reading_which_pc <= reading_which_pc << 1;
      end
    end
  end

  // Fifo Ciphertext Emission ---------------------------------------------------------------------
  logic [MRMAC_AXIS_W-1:0]  fifo_ce_in_data;
  logic                     fifo_ce_in_vld;
  logic                     fifo_ce_in_rdy;

  // data in input are already in the correct form for sending directly to the lane
  always_comb begin
    fifo_ce_in_vld  = 1'b0;
    fifo_ce_in_data = 'h0;
    for (int i = 0; i < ETH_PC; i++) begin
      if (reading_which_pc[i]) begin
        fifo_ce_in_vld  = fifo_ce_pc_in_vld[i];
        fifo_ce_in_data = fifo_ce_pc_in_data[i];
      end
    end
  end

  // backpressure over ready for each fifo
  generate
    for (genvar gen_i = 0; gen_i < ETH_PC; gen_i++) begin : gen_ce_pc_rdy
      assign fifo_ce_pc_in_rdy[gen_i] = reading_which_pc[gen_i] ? fifo_ce_in_rdy : 1'b0;
    end
  endgenerate

  // Gate fifo_ce output: don't let formatter consume until all data is loaded.
  // This prevents MRMAC TX underrun (tvalid gap mid-frame) when HBM reads are slow.
  // If ever MRMAC drops the valid the current frame is dropped
  logic ce_fifo_vld;

  logic [$clog2(CT_NB_COEF+1)-1:0] ce_load_cnt;
  logic                            ce_data_loaded;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_load_cnt <= '0;
    end else begin
      if (ciphertext_sent) begin
        ce_load_cnt <= '0;
      end else if (fifo_ce_in_vld & fifo_ce_in_rdy) begin
        ce_load_cnt <= ce_load_cnt + 1;
      end
    end
  end

  // we receive more than CT_NB_WORDS_MRMAC because CT_NB_COEF is not a power of two
  assign ce_data_loaded = (ce_load_cnt >= CT_NB_WORDS_MRMAC);

  fifo_ram_rdy_vld # (
    .WIDTH      (MRMAC_AXIS_W   ),
    .DEPTH      (CT_NB_COEF     ),
    .RAM_LATENCY(CE_RAM_LATENCY ),
    .ALMOST_FULL_REMAIN (0)
  ) fifo_ce (
    .clk         (clk_mrmac),
    .s_rst_n     (resetn_mrmac),

    .in_data     (fifo_ce_in_data),
    .in_vld      (fifo_ce_in_vld),
    .in_rdy      (fifo_ce_in_rdy),

    .out_data    (ce_payload),
    .out_vld     (ce_fifo_vld),
    .out_rdy     (ce_rdy & ce_data_loaded),
    .almost_full (/* UNUSED */)
  );

  assign ce_vld = ce_fifo_vld & ce_data_loaded;

  // =========================================================================================== //
  // Interface to formatter
  // =========================================================================================== //
  // acks takes precedence in from of read request
  always_ff @(posedge clk_mrmac) begin
    if (nrx_cmd_out_vld)  begin
      slave_command_vld       <= nrx_cmd_out_vld;
      slave_command           <= nrx_cmd_fifo;
      slave_command.rsvd      <= 'h0;
      slave_command.flag      <= 'h0;
      slave_command.mode      <= 'h0;
      slave_command.dst_addr  <= 'h0;
    end else if (rreq_cmd_out_vld) begin
      slave_command_vld     <= rreq_cmd_out_vld;
      slave_command         <= rreq_cmd_fifo;
    end else begin
      slave_command_vld     <= 'h0;
      slave_command         <= 'h0;
    end
  end

  // =========================================================================================== //
  // Errors
  // =========================================================================================== //
  assign slave_error = {error_fifo_nrx_commands_ovf};

  // =========================================================================================== //
  // Statistics
  // =========================================================================================== //
  assign stat.fsm_notify_rx  = nrx_state;
  assign stat.fsm_cem        = cem_state;

  logic [REG_DATA_W-1:0] nb_read_to_hbm;
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
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
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          nb_words_received_pc[gen_i] <= 'h0;
        end else begin
          if (stat_rst.nb_words_received_pc[gen_i]) begin
            nb_words_received_pc[gen_i] <= 'h0;
          end else begin
            if (m_axi4_rready[gen_i] & m_axi4_rvalid[gen_i]) begin
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
      always_ff @(posedge clk_mrmac) begin
        if(~resetn_mrmac) begin
          t_wait_words_en[gen_i] <= 1'b0;
        end else begin
          if (m_axi4_arvalid[gen_i]) begin
            t_wait_words_en[gen_i] <= 1'b1;
          end else if (m_axi4_rvalid[gen_i]) begin
            t_wait_words_en[gen_i] <= 1'b0;
          end
        end
      end


      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          t_rr_wait_words_pc[gen_i] <= 'h0;
        end else begin
          if(t_wait_words_en[gen_i]) begin
            t_rr_wait_words_pc[gen_i] <= t_rr_wait_words_pc[gen_i] +1;
          end
        end
      end
    end
  endgenerate

  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] rr_phy_addr;
  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_i_phy_addr
      assign rr_phy_addr[gen_i] = phy_addr[gen_i];
    end
  endgenerate

  assign stat.rr_phy_addr           = rr_phy_addr;
  assign stat.nb_read_to_hbm        = nb_read_to_hbm;
  assign stat.nb_words_received_pc  = nb_words_received_pc;
  assign stat.t_rr_wait_words_pc    = t_rr_wait_words_pc;

endmodule
