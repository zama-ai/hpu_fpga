// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : Testbench for packet loss and retries in multi-HPU DMA.
//
// Scenarios (run sequentially; see the run list in the main initial block):
//   Notify (master notify path):
//     - notify_nominal       : nominal request and ack
//     - notify_ack_timeout    : ack never returns -> timeout retry, late ack accepted
//     - notify_wrong_ack      : ack with wrong MAC ignored -> retry -> good ack
//     - notify_ack_delayed    : ack delayed with a second notify pending (in-order ack)
//   Read (master read / ciphertext path):
//     - read_nominal          : request -> full ciphertext burst -> completion IRQ
//     - read_timeout          : request unanswered -> timeout retry -> answer -> IRQ
//   Recovery (seq_num mismatch):
//     - recovery_wrong_seq_num   : wrong seq_num mid-burst -> abort -> retry -> recover
//     - recovery_dropped_packet  : dropped packet (fwd skip) -> mismatch -> retry -> recover
//     - recovery_slave_read      : mismatch recovery while a slave READ is head-of-line
//     - recovery_slave_notify    : mismatch recovery while a slave NOTIFY is head-of-line
//
// HPU_A is the DUT, HPU_B is emulated by this testbench.
//
// Beware : as we assume that if an ack is received during a retry, the ack of the retry will be
// the one that resets the notify FSM, with small timeout values we could, in this testbench send
// an ack during a notify retry. This could lead the testbench to fail if wait time are changed.
//
// ================================================================================================

`resetall
`timescale 1ns/10ps
module tb_mhdma_pkt_loss;
  import mhdma_pkg::*;                      // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;          // axi4-lite + REG_DATA_W
  import axi_if_common_param_pkg::*;        // general axi4
  import hpu_regif_core_mhdma_2in3_pkg::*;  // ethernet regif
  import axi_if_mhdma_axi_pkg::*;           // AXI ethernet
  import pem_common_param_pkg::*;           // CT_MEM_BYTES, AXI4_WORD_PER_PC*

  `include "tb_mhdma_tasks.sv"

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 4;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int FIFO_DEPTH = 512;

  localparam int HPU_NB = 1; // in this test we will try to connect two mhdma (or HPUs)

  localparam int NB_HPU = 8;
  localparam [31:0] TIMEOUT_DUR_NOTIFY = 'd180;
  localparam [31:0] TIMEOUT_DUR_READ_REQ = 'd4000;

  // ciphertext memories -------------------------------------------------------------------------
  localparam int MEM_WR_CMD_BUF_DEPTH = 4;  // Should be >= 1
  localparam int MEM_RD_CMD_BUF_DEPTH = 1;  // Should be >= 1
  // Data latency
  localparam int MEM_WR_DATA_LATENCY = 42;  // Should be >= 1
  localparam int MEM_RD_DATA_LATENCY = 1;   // Should be >= 1
  // Set random on ready valid, on write path
  localparam bit MEM_USE_WR_RANDOM = 1;
  // Set random on ready valid, on read path
  localparam bit MEM_USE_RD_RANDOM = 0;     // check path, no need random

  // simulation sizes to reduce runtime
  localparam int MEM_SIM_SIZE = 18;         // must be < 22
  localparam int RFM_SIM      = 'h0;

  localparam int MAX_BURST_SIZE  = PAGE_BYTES/AXI4_DATA_BYTES;

  localparam int TOTAL_NB_PACKETS = $ceil(CT_NB_COEF / NB_WORDS_PAYLOAD) + 1;

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk_control;
  bit clk_mhdma;

  initial begin
    clk_control = 1'b0;
    clk_mhdma = 1'b0;
  end

  always begin
    #CLK_HALF_PERIOD_A clk_control = ~clk_control;
  end
  always begin
    #CLK_HALF_PERIOD_B clk_mhdma = ~clk_mhdma;
  end

  bit a_rst_n; // asynchronous reset
  bit s_rstn_control; // synchronous reset
  bit s_rstn_mhdma; // synchronous reset

  initial begin
    a_rst_n = 1'b0;                  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always_ff @(posedge clk_control) begin
    s_rstn_control <= a_rst_n;
  end
  always_ff @(posedge clk_mhdma) begin
    s_rstn_mhdma <= a_rst_n;
  end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk_control) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit error_ack;
  bit error_retry;
  bit error_tb_notify;
  bit error_register_read;
  bit error_fsm;
  bit error_interrupt;
  bit error_timeout_watchdog;

  assign error = error_ack | error_retry | error_tb_notify | error_register_read | error_fsm | error_interrupt | error_timeout_watchdog;

  always_ff @(posedge clk_control)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // Global watchdog: prevent simulation from hanging, some tests here are waiting on failure
  initial begin
    logic [REG_DATA_W-1:0] wd_errors;
    #5_000_000;
    $display("%t > FAILURE: Global watchdog timeout!", $time);
    maxil_drv_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, wd_errors);
    dump_mhdma_state("global watchdog timeout", wd_errors);
    error_timeout_watchdog = 1'b1;
  end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [MRMAC_AXIS_W-1:0]    unused_payload [$];

  logic [AXIL_ADD_W-1:0]      s_axil_mhdma_awaddr;
  logic                       s_axil_mhdma_awvalid;
  logic                       s_axil_mhdma_awready;
  logic [AXIL_DATA_W-1:0]     s_axil_mhdma_wdata;
  logic [AXIL_DATA_BYTES-1:0] s_axil_mhdma_wstrb; /* UNUSED */
  logic                       s_axil_mhdma_wvalid;
  logic                       s_axil_mhdma_wready;
  logic [1:0]                 s_axil_mhdma_bresp;
  logic                       s_axil_mhdma_bvalid;
  logic                       s_axil_mhdma_bready;
  logic [AXIL_ADD_W-1:0]      s_axil_mhdma_araddr;
  logic                       s_axil_mhdma_arvalid;
  logic                       s_axil_mhdma_arready;
  logic [AXIL_DATA_W-1:0]     s_axil_mhdma_rdata;
  logic [1:0]                 s_axil_mhdma_rresp;
  logic                       s_axil_mhdma_rvalid;
  logic                       s_axil_mhdma_rready;

  // Interrupt interface
  logic                       interrupt_notify;
  logic                       interrupt_read_request;
  // HPUs
  logic [NB_HPU-1:0][MAC_ADDR_W-1:0] mac_addr_l;

  // AXI4 to HBM: HPUA (single NMU) ----------------------------------------------------------------
  logic [AXI4_ID_W-1:0]       axi4_ct_awid;
  logic [AXI4_ADD_W-1:0]      axi4_ct_awaddr;
  logic [7:0]                 axi4_ct_awlen;
  logic [2:0]                 axi4_ct_awsize;
  logic [1:0]                 axi4_ct_awburst;
  logic                       axi4_ct_awvalid;
  logic                       axi4_ct_awready;
  logic [AXI4_DATA_W-1:0]     axi4_ct_wdata;
  logic [(AXI4_DATA_W/8)-1:0] axi4_ct_wstrb;
  logic                       axi4_ct_wlast;
  logic                       axi4_ct_wvalid;
  logic                       axi4_ct_wready;
  logic [AXI4_ID_W-1:0]       axi4_ct_bid;
  logic [1:0]                 axi4_ct_bresp;
  logic                       axi4_ct_bvalid;
  logic                       axi4_ct_bready;

  logic [AXI4_ID_W-1:0]       axi4_ct_arid;
  logic [AXI4_ADD_W-1:0]      axi4_ct_araddr;
  logic [7:0]                 axi4_ct_arlen;
  logic [2:0]                 axi4_ct_arsize;
  logic [1:0]                 axi4_ct_arburst;
  logic                       axi4_ct_arvalid;
  logic                       axi4_ct_arready;
  logic [AXI4_ID_W-1:0]       axi4_ct_rid;
  logic [AXI4_DATA_W-1:0]     axi4_ct_rdata;
  logic [1:0]                 axi4_ct_rresp;
  logic                       axi4_ct_rlast;
  logic                       axi4_ct_rvalid;
  logic                       axi4_ct_rready;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  // gt configuration signals -------------------------------------------------
  logic [7:0]              gt_line_rate;
  logic [2:0]              gt_loopback;
  logic [QSFP_LANE_NB-1:0] gt_reset_rx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_tx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_all;
  logic [QSFP_LANE_NB-1:0] gt_rx_reset_done;
  logic [QSFP_LANE_NB-1:0] gt_tx_reset_done;

  // lane parameters ----------------------------------------------------------
  logic [REG_DATA_W-1:0] line_parameter;
  logic        debug_flag;
  logic [2:0]  line_loopback;
  logic [7:0]  line_rate;
  logic [1:0]  lane;

  assign line_parameter[1:0]   = lane;
  assign line_parameter[4:2]   = line_loopback;
  assign line_parameter[12:5]  = line_rate;
  assign line_parameter[27:13] = 'h0;
  assign line_parameter[31]    = debug_flag;

  // lane debug ---------------------------------------------------------------
  logic [REG_DATA_W-1:0] line_debug;
  logic        reset_registers;
  logic        tx_loop;
  logic        rx_to_tx;

  assign line_debug[28:0] = 'h0;
  assign line_debug[29]   = rx_to_tx;
  assign line_debug[30]   = tx_loop;
  assign line_debug[31]   = reset_registers;

  // [section] reset ----------------------------------------------------------
  logic [  REG_DATA_W-1:0] reset_parameter;
  logic [QSFP_LANE_NB-1:0] rst_rx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_tx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_all;

  assign reset_parameter = {20'h0, rst_rx_datapath, rst_tx_datapath, rst_all};

  // monitoring of reset done
  logic [REG_DATA_W-1:00] reset_monitor;

  // HPU ----------------------------------------------------------------------
  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_rx_tdata_delayed;
  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user_delayed;
  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tlast_delayed;
  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid_delayed;

  // ============================================================================================== --
  // QSFP interface
  // ============================================================================================== --
    qsfp_if qsfp_rx_vif[QSFP_LANE_NB] (clk_mhdma);

    // == TX
    logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_tx_tdata;
    logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user;
    logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tlast;
    logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tvalid;
    logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tready;
    //
    // == RX
    logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_rx_tdata;
    logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user;
    logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tlast;
    logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid;

    generate
      for (genvar gen_i=0; gen_i<QSFP_LANE_NB; gen_i=gen_i+1) begin
        always @(*) begin
          qsfp_rx_tdata_delayed[gen_i]      <= #100ns qsfp_rx_vif[gen_i].tdata;
          qsfp_rx_tkeep_user_delayed[gen_i] <= #100ns qsfp_rx_vif[gen_i].tkeep_user;
          qsfp_rx_tlast_delayed[gen_i]      <= #100ns qsfp_rx_vif[gen_i].tlast;
          qsfp_rx_tvalid_delayed[gen_i]     <= #100ns qsfp_rx_vif[gen_i].tvalid;
        end

        initial begin
          qsfp_rx_vif[gen_i].tdata      = 'h0;
          qsfp_rx_vif[gen_i].tkeep_user = 'h0;
          qsfp_rx_vif[gen_i].tlast      = 1'b0;
          qsfp_rx_vif[gen_i].tvalid     = 1'b0;
          qsfp_rx_vif[gen_i].tready     = 1'b1; // Always ready (no backpressure in this tb)
          qsfp_tx_tready[gen_i]         = 1'b1;
        end
      end
    endgenerate

  // ============================================================================================== --
  // DUT
  // ============================================================================================== --
  multi_hpu_dma hpu_a (
    .clk_mhdma_cfg            (clk_control    ),
    .resetn_mhdma_cfg         (s_rstn_control ),

    .clk_mhdma          (clk_mhdma    ),
    .resetn_mhdma       (s_rstn_mhdma ),

    .s_axil_mhdma_awaddr      (s_axil_mhdma_awaddr ),
    .s_axil_mhdma_awvalid     (s_axil_mhdma_awvalid),
    .s_axil_mhdma_awready     (s_axil_mhdma_awready),
    .s_axil_mhdma_wdata       (s_axil_mhdma_wdata  ),
    .s_axil_mhdma_wstrb       (s_axil_mhdma_wstrb  ),
    .s_axil_mhdma_wvalid      (s_axil_mhdma_wvalid ),
    .s_axil_mhdma_wready      (s_axil_mhdma_wready ),
    .s_axil_mhdma_bresp       (s_axil_mhdma_bresp  ),
    .s_axil_mhdma_bvalid      (s_axil_mhdma_bvalid ),
    .s_axil_mhdma_bready      (s_axil_mhdma_bready ),
    .s_axil_mhdma_araddr      (s_axil_mhdma_araddr ),
    .s_axil_mhdma_arvalid     (s_axil_mhdma_arvalid),
    .s_axil_mhdma_arready     (s_axil_mhdma_arready),
    .s_axil_mhdma_rdata       (s_axil_mhdma_rdata  ),
    .s_axil_mhdma_rresp       (s_axil_mhdma_rresp  ),
    .s_axil_mhdma_rvalid      (s_axil_mhdma_rvalid ),
    .s_axil_mhdma_rready      (s_axil_mhdma_rready ),

    .m_axi4_mhdma_hbm_arid    (axi4_ct_arid         ),
    .m_axi4_mhdma_hbm_araddr  (axi4_ct_araddr       ),
    .m_axi4_mhdma_hbm_arlen   (axi4_ct_arlen        ),
    .m_axi4_mhdma_hbm_arsize  (axi4_ct_arsize       ),
    .m_axi4_mhdma_hbm_arburst (axi4_ct_arburst      ),
    .m_axi4_mhdma_hbm_arvalid (axi4_ct_arvalid      ),
    .m_axi4_mhdma_hbm_arready (axi4_ct_arready      ),
    .m_axi4_mhdma_hbm_rid     (axi4_ct_rid          ),
    .m_axi4_mhdma_hbm_rdata   (axi4_ct_rdata        ),
    .m_axi4_mhdma_hbm_rresp   (axi4_ct_rresp        ),
    .m_axi4_mhdma_hbm_rlast   (axi4_ct_rlast        ),
    .m_axi4_mhdma_hbm_rvalid  (axi4_ct_rvalid       ),
    .m_axi4_mhdma_hbm_rready  (axi4_ct_rready       ),
    .m_axi4_mhdma_hbm_awid    (axi4_ct_awid         ),
    .m_axi4_mhdma_hbm_awaddr  (axi4_ct_awaddr       ),
    .m_axi4_mhdma_hbm_awlen   (axi4_ct_awlen        ),
    .m_axi4_mhdma_hbm_awsize  (axi4_ct_awsize       ),
    .m_axi4_mhdma_hbm_awburst (axi4_ct_awburst      ),
    .m_axi4_mhdma_hbm_awvalid (axi4_ct_awvalid      ),
    .m_axi4_mhdma_hbm_awready (axi4_ct_awready      ),
    .m_axi4_mhdma_hbm_wdata   (axi4_ct_wdata        ),
    .m_axi4_mhdma_hbm_wstrb   (axi4_ct_wstrb        ),
    .m_axi4_mhdma_hbm_wlast   (axi4_ct_wlast        ),
    .m_axi4_mhdma_hbm_wvalid  (axi4_ct_wvalid       ),
    .m_axi4_mhdma_hbm_wready  (axi4_ct_wready       ),
    .m_axi4_mhdma_hbm_bid     (axi4_ct_bid          ),
    .m_axi4_mhdma_hbm_bresp   (axi4_ct_bresp        ),
    .m_axi4_mhdma_hbm_bvalid  (axi4_ct_bvalid       ),
    .m_axi4_mhdma_hbm_bready  (axi4_ct_bready       ),

    .qsfp_tx_tdata          (qsfp_tx_tdata           ),
    .qsfp_tx_tkeep_user     (qsfp_tx_tkeep_user      ),
    .qsfp_tx_tlast          (qsfp_tx_tlast           ),
    .qsfp_tx_tvalid         (qsfp_tx_tvalid          ),
    .qsfp_tx_tready         (qsfp_tx_tready          ),

    .qsfp_rx_tdata          (qsfp_rx_tdata_delayed      ),
    .qsfp_rx_tkeep_user     (qsfp_rx_tkeep_user_delayed ),
    .qsfp_rx_tlast          (qsfp_rx_tlast_delayed      ),
    .qsfp_rx_tvalid         (qsfp_rx_tvalid_delayed     ),

    .interrupt_notify       (interrupt_notify       ),
    .interrupt_read_request (interrupt_read_request ),

    .gt_line_rate           (gt_line_rate            ),
    .gt_loopback            (gt_loopback            ),
    .gt_reset_rx_datapath   (gt_reset_rx_datapath    ),
    .gt_reset_tx_datapath   (gt_reset_tx_datapath    ),
    .gt_reset_all           (gt_reset_all            ),
    .gt_rx_reset_done       (gt_rx_reset_done        ),
    .gt_tx_reset_done       (gt_tx_reset_done        )
);

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// Signals --------------------------------------------------------------------------------------
logic [REG_DATA_W-1:0] read_data;
logic [REG_DATA_W-1:0] timeout_size;

logic [REG_DATA_W-1:0] regf_start_addr_ofs;

logic [REG_DATA_W-1:0] stat_notify;
logic [REG_DATA_W-1:0] stat_notify_ack;
logic [REG_DATA_W-1:0] stat_notify_retry;
logic [REG_DATA_W-1:0] stat_read_req_retry;
logic [REG_DATA_W-1:0] stat_notify_timeout;
logic [REG_DATA_W-1:0] stat_t_notify_to_ack;
logic [REG_DATA_W-1:0] stat_t_rr_to_ce_received;
logic [REG_DATA_W-1:0] stat_t_ce_first_to_last_pkt;
logic [REG_DATA_W-1:0] stat_cnt_nack_received;
logic [REG_DATA_W-1:0] stat_cnt_notify_received;
logic [REG_DATA_W-1:0] stat_cnt_read_req_received;
logic [REG_DATA_W-1:0] stat_cnt_ce_received;
logic [REG_DATA_W-1:0] stat_read_req_timeout_retry;
logic [REG_DATA_W-1:0] stat_errors;
logic [REG_DATA_W-1:0] rr_recv_base;
logic [REG_DATA_W-1:0] nr_recv_base;

logic [SRC_ADDR_W-1:0] iop_src_addr;
logic [DST_ADDR_W-1:0] iop_dst_addr;
logic [RSVD_W+FLAG_W+MODE_W-1:0] req_rfm;
logic [MAC_ADDR_W-1:0] dst_mac_addr;
logic [MAC_ADDR_W-1:0] src_mac_addr;
logic [HPU_ID_W-1:0]   dst_hpu_id;
logic [HPU_ID_W-1:0]   src_hpu_id;
logic [IOP_ID_W-1:0]   iop_id;
logic [SRC_ADDR_W-1:0] src_addr;
logic [DST_ADDR_W-1:0] dst_addr;

  // AXI4-LITE drivers ----------------------------------------------------------------------------
  maxil_if #(
  .AXIL_DATA_W(AXIL_DATA_W),
  .AXIL_ADD_W  (AXIL_ADD_W)
  ) maxil_drv_if ( .clk(clk_control), .rst_n(s_rstn_control));

  // Connect interface on testbench signals
  assign s_axil_mhdma_awaddr  = maxil_drv_if.awaddr;
  assign s_axil_mhdma_awvalid = maxil_drv_if.awvalid;
  assign s_axil_mhdma_wdata   = maxil_drv_if.wdata;
  assign s_axil_mhdma_wstrb   = maxil_drv_if.wstrb;
  assign s_axil_mhdma_wvalid  = maxil_drv_if.wvalid;
  assign s_axil_mhdma_bready  = maxil_drv_if.bready;
  assign s_axil_mhdma_araddr  = maxil_drv_if.araddr;
  assign s_axil_mhdma_arvalid = maxil_drv_if.arvalid;
  assign s_axil_mhdma_rready  = maxil_drv_if.rready;

  assign maxil_drv_if.awready = s_axil_mhdma_awready;
  assign maxil_drv_if.wready  = s_axil_mhdma_wready;
  assign maxil_drv_if.bresp   = s_axil_mhdma_bresp;
  assign maxil_drv_if.bvalid  = s_axil_mhdma_bvalid;
  assign maxil_drv_if.arready = s_axil_mhdma_arready;
  assign maxil_drv_if.rdata   = s_axil_mhdma_rdata;
  assign maxil_drv_if.rresp   = s_axil_mhdma_rresp;
  assign maxil_drv_if.rvalid  = s_axil_mhdma_rvalid;

  axi4_mem #(
    .DATA_WIDTH      (AXI4_DATA_W          ),
    .ADDR_WIDTH      (MEM_SIM_SIZE         ),
    .ID_WIDTH        (AXI4_ID_W            ),
    .WR_CMD_BUF_DEPTH(MEM_WR_CMD_BUF_DEPTH ),
    .RD_CMD_BUF_DEPTH(MEM_RD_CMD_BUF_DEPTH ),
    .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY  ),
    .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY  ),
    .USE_WR_RANDOM   (MEM_USE_WR_RANDOM    ),
    .USE_RD_RANDOM   (MEM_USE_RD_RANDOM    )
  ) axi4_mem_ct (
    .clk              (clk_mhdma                       ),
    .rst              (~s_rstn_mhdma                   ),
    .s_axi4_awid      (axi4_ct_awid                    ),
    .s_axi4_awaddr    (axi4_ct_awaddr[MEM_SIM_SIZE-1:0]),
    .s_axi4_awlen     (axi4_ct_awlen                   ),
    .s_axi4_awsize    (axi4_ct_awsize                  ),
    .s_axi4_awburst   (axi4_ct_awburst                 ),
    .s_axi4_awlock    (/* UNUSED */                    ),
    .s_axi4_awcache   (/* UNUSED */                    ),
    .s_axi4_awprot    (/* UNUSED */                    ),
    .s_axi4_awqos     (/* UNUSED */                    ),
    .s_axi4_awregion  (/* UNUSED */                    ),
    .s_axi4_awvalid   (axi4_ct_awvalid                 ),
    .s_axi4_awready   (axi4_ct_awready                 ),
    .s_axi4_wdata     (axi4_ct_wdata                   ),
    .s_axi4_wstrb     (axi4_ct_wstrb                   ),
    .s_axi4_wlast     (axi4_ct_wlast                   ),
    .s_axi4_wvalid    (axi4_ct_wvalid                  ),
    .s_axi4_wready    (axi4_ct_wready                  ),
    .s_axi4_bid       (axi4_ct_bid                     ),
    .s_axi4_bresp     (axi4_ct_bresp                   ),
    .s_axi4_bvalid    (axi4_ct_bvalid                  ),
    .s_axi4_bready    (axi4_ct_bready                  ),
    .s_axi4_arid      (axi4_ct_arid                    ),
    .s_axi4_araddr    (axi4_ct_araddr[MEM_SIM_SIZE-1:0]),
    .s_axi4_arlen     (axi4_ct_arlen                   ),
    .s_axi4_arsize    (axi4_ct_arsize                  ),
    .s_axi4_arburst   (axi4_ct_arburst                 ),
    .s_axi4_arlock    (/* UNUSED */                    ),
    .s_axi4_arcache   (/* UNUSED */                    ),
    .s_axi4_arprot    (/* UNUSED */                    ),
    .s_axi4_arqos     (/* UNUSED */                    ),
    .s_axi4_arregion  (/* UNUSED */                    ),
    .s_axi4_arvalid   (axi4_ct_arvalid                 ),
    .s_axi4_arready   (axi4_ct_arready                 ),
    .s_axi4_rid       (axi4_ct_rid                     ),
    .s_axi4_rdata     (axi4_ct_rdata                   ),
    .s_axi4_rresp     (axi4_ct_rresp                   ),
    .s_axi4_rlast     (axi4_ct_rlast                   ),
    .s_axi4_rvalid    (axi4_ct_rvalid                  ),
    .s_axi4_rready    (axi4_ct_rready                  )
  );

  // Initialize memory
  initial begin
    for (int k = 0; k < 2**MEM_SIM_SIZE; k++) begin
      logic [AXI4_DATA_W-1:0] value;
      value = '0;
      for (int j = 0; j < AXI4_DATA_W/64; j++) begin
        logic [63:0] w;
        w[63:32] = $urandom();
        w[31:0]  = $urandom();
        value |= (w << (j*64));
      end
      axi4_mem_ct.axi4_ram_ct_wr.mem[k] = value;
    end
  end

  // Decoder --------------------------------------------------------------------------------------
  // The decoder now exposes two role-split command streams. The scenario logic only inspects
  // READ/NOTIFY and uses !rx_header_vld for idle, so merge both streams back into a single
  // rx_header view and drain both queues (slave-role shown first; READ/NOTIFY live there).
  command_t rx_header_master;
  logic     rx_header_master_vld;
  logic     rx_header_master_rdy;

  command_t rx_header_slave;
  logic     rx_header_slave_vld;
  logic     rx_header_slave_rdy;

  command_t rx_header;
  logic     rx_header_vld;
  logic     rx_header_rdy;

  assign rx_header          = rx_header_slave_vld ? rx_header_slave : rx_header_master;
  assign rx_header_vld      = rx_header_slave_vld | rx_header_master_vld;
  assign rx_header_slave_rdy  = rx_header_rdy &  rx_header_slave_vld;
  assign rx_header_master_rdy = rx_header_rdy & ~rx_header_slave_vld;

  // this is supposed to be HPU_B decoder
  mhdma_decoder mhdma_decoder (
    .clk_mhdma           (clk_mhdma               ),
    .resetn_mhdma        (s_rstn_mhdma            ),

    .notify_ack_received (/*    unused          */),
    .current_hpu_mac     (src_mac_addr            ),

    .decoded_command_master     (rx_header_master    ),
    .decoded_command_master_vld (rx_header_master_vld),
    .decoded_command_master_rdy (rx_header_master_rdy),

    .decoded_command_slave      (rx_header_slave     ),
    .decoded_command_slave_vld  (rx_header_slave_vld ),
    .decoded_command_slave_rdy  (rx_header_slave_rdy ),

    .rx_tdata_out        (/*    unused          */),
    .rx_tvalid_out       (/*    unused          */),

    // stats are completely ignored here
    .stat                (/*    unused          */),
    .stat_rst            (/*    unused          */),

    .decoder_error       (/*    unused          */),
    .rst_errors          (/*    unused          */),

    // only one lane is used in this tb
    .qsfp_rx_tdata       (qsfp_tx_tdata[lane]     ),
    .qsfp_rx_tkeep_user  (qsfp_tx_tkeep_user[lane]),
    .qsfp_rx_tlast       (qsfp_tx_tlast[lane]     ),
    .qsfp_rx_tvalid      (qsfp_tx_tvalid[lane]    )
  );

  always_ff @(posedge clk_mhdma)
   rx_header_rdy <= ($urandom() % 100 < 50);

  assign req_rfm = 'h0;

  // scenario -------------------------------------------------------------------------------------
  int scenario_id;
  int drop_idx;

  initial begin
    maxil_drv_if.init();

    reset_registers = 'h0;
    tx_loop         = 'h0;
    rx_to_tx        = 'h0;
    regf_start_addr_ofs = 'h0;
    repeat(20) @(posedge clk_control);

    $display("\n==================================================================================================");
    $display("  Initial register check and definition");
    $display("==================================================================================================");
    init_config();

    run_scenario_notify_nominal();
    run_scenario_notify_ack_timeout();
    run_scenario_notify_wrong_ack();
    run_scenario_notify_ack_delayed();
    run_scenario_read_nominal();
    run_scenario_read_timeout();
    run_scenario_recovery_wrong_seq_num();
    run_scenario_recovery_dropped_packet();
    run_scenario_recovery_slave_read();
    run_scenario_recovery_slave_notify();

    print_final_summary();

    $display("%t > INFO: End simulation",$time);
    repeat(20) @(posedge clk_control);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --
  logic [REG_DATA_W-1:0] rdata;

  // ============================================================================================ --
  // Scenarios
  // Each scenario is a self-contained task: scenario_start() prints the banner, scenario_end()
  // prints PASSED and increments scenario_id.
  // They run sequentially from the main initial block.
  // ============================================================================================ --

  // --------------------------------------------------------------------------------------------- --
  // Notify - default behavior: send a notify, peer acks it, check the ack was counted.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_notify_nominal();
    begin
      scenario_start(scenario_id, "Notify: nominal request and ack");
      iop_id       = scenario_id;
      iop_src_addr = $urandom_range(0, (1<<SRC_ADDR_W)-1);

      notify_request(src_hpu_id, dst_hpu_id, iop_id, iop_src_addr);

      repeat(2) @(posedge clk_mhdma);

      send_notify_ack_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, 16'h0);

      repeat (50) @(posedge clk_control);

      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS, stat_cnt_nack_received);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, stat_notify);

      assert (stat_cnt_nack_received == 1) begin
        $display("%t > [INFO]: Received %0d ack after Notify", $time, stat_cnt_nack_received);
      end else begin
        $display("%t > [ERROR]: HPU didn't receive the ack from testbench", $time);
        error_ack = 1'b1;
      end

      check_fsm_initialized();
      scenario_end(scenario_id, clk_control, error);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Notify - no ack: peer stays silent past the timeout, DUT must retry the notify.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_notify_ack_timeout();
    begin
      scenario_start(scenario_id, "Notify: ack never returns -> timeout retry");
      iop_id       = scenario_id;
      iop_src_addr = $urandom_range(0, (1<<SRC_ADDR_W)-1);
      notify_request(src_hpu_id, dst_hpu_id, iop_id, iop_src_addr);

      repeat(2*TIMEOUT_DUR_NOTIFY+5) @(posedge clk_mhdma);

      send_notify_ack_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, 16'h0);

      repeat (50) @(posedge clk_control);

      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS, stat_cnt_nack_received);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, stat_notify_retry);

      assert (stat_notify_retry != 0) begin
        $display("%t > [INFO]: Did %0d retries", $time, stat_notify_retry);
        $display("%t > [INFO]: Received %0d ack after Notify", $time, stat_cnt_nack_received);
      end else begin
        $display("%t > [ERROR]: HPU didn't retry sending other Notifies", $time);
        error_retry = 1'b1;
      end

      check_fsm_initialized();
      scenario_end(scenario_id, clk_control, error);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Notify - wrong ack: an ack with a bad MAC is ignored, DUT retries until a valid ack arrives.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_notify_wrong_ack();
    begin
      scenario_start(scenario_id, "Notify: wrong ack -> ignored, retry");
      iop_id       = scenario_id;
      iop_src_addr = $urandom_range(0, (1<<SRC_ADDR_W)-1);
      notify_request(src_hpu_id, dst_hpu_id, iop_id, iop_src_addr);

      repeat(2*TIMEOUT_DUR_NOTIFY + 5) @(posedge clk_mhdma);
      send_notify_ack_packet(qsfp_rx_vif[0], 24'b0, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, 16'h0);

      repeat(2*TIMEOUT_DUR_NOTIFY + 5 ) @(posedge clk_mhdma);
      send_notify_ack_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, 16'h0);

      repeat (50) @(posedge clk_control);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS, stat_cnt_nack_received);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, stat_notify_retry);

      assert (stat_notify_retry != 0) begin
        $display("%t > [INFO]: Did %0d retries", $time, stat_notify_retry);
        $display("%t > [INFO]: Received %0d ack after Notify", $time, stat_cnt_nack_received);
      end else begin
        $display("%t > [ERROR]: HPU didn't retry sending other Notifies", $time);
        error_retry = 1'b1;
      end

      check_fsm_initialized();
      scenario_end(scenario_id, clk_control, error);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Notify - pending: two notifies in flight, each acked in order by the peer.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_notify_ack_delayed();
    logic [IOP_ID_W-1:0] id_a, id_b;
    begin
      scenario_start(scenario_id, "Notify: ack delayed with a second notify pending");
      // Two distinct random iop_ids (instead of fixed 58/98): confirms two-outstanding tracking
      // and in-order ack matching are not value-specific.
      id_a = $urandom_range(1, (1<<IOP_ID_W)-1);
      id_b = $urandom_range(1, (1<<IOP_ID_W)-1);
      if (id_b == id_a) id_b = (id_a == (1<<IOP_ID_W)-1) ? id_a - 1 : id_a + 1;
      iop_src_addr = $urandom_range(0, (1<<SRC_ADDR_W)-1);

      iop_id = id_a;
      notify_request(src_hpu_id, dst_hpu_id, iop_id, iop_src_addr);

      iop_id = id_b;
      notify_request(src_hpu_id, dst_hpu_id, iop_id, iop_src_addr);

      // Wait for decoder to receive first notify (with possible retries)
      wait(rx_header_vld && rx_header.req_id == REQ_ID_NOTIFY && rx_header.iop_id == id_a);
      $display("%t > [TB] Decoder saw notify iop_id=%0d", $time, id_a);
      send_notify_ack_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, id_a, iop_src_addr, 16'h0);

      // Wait for decoder to receive second notify
      wait(rx_header_vld && rx_header.req_id == REQ_ID_NOTIFY && rx_header.iop_id == id_b);
      $display("%t > [TB] Decoder saw notify iop_id=%0d", $time, id_b);
      send_notify_ack_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, id_b, iop_src_addr, 16'h0);

      // Verify we received the expected notifies
      repeat(50) @(posedge clk_control);

      check_fsm_initialized();
      scenario_end(scenario_id, clk_control, error);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Ciphertext emission - default: DUT issues a read request, peer answers with the full burst.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_read_nominal();
    begin
      scenario_start(scenario_id, "Read: nominal request and ciphertext reception");
      iop_id       = scenario_id;
      iop_src_addr = $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1);
      iop_dst_addr = $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1);

      fork
        begin
          read_request(dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr);
        end
        begin
          wait(rx_header_vld & (rx_header.req_id == REQ_ID_READ));
        end
      join

      // Send ciphertext emission packets as if we're the remote HPU responding
      for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
        send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr, pkt[7:0], unused_payload);
        repeat(10) @(posedge clk_mhdma);
      end

      repeat(50) @(posedge clk_control);

      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS, stat_cnt_read_req_received);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_CE_RECEIVED_OFS, stat_cnt_ce_received);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_timeout_retry);

      assert (stat_cnt_ce_received == NB_PACKETS_FULL+1) begin
        $display("%t > [INFO]: stat_cnt_ce_received : %0d", $time, stat_cnt_ce_received);
      end else begin
        $display("%t > [ERROR]: HPU didn't receive correct amount of CE packets (%0d) expected %0d", $time, stat_cnt_ce_received, NB_PACKETS_FULL+1);
        error_retry = 1'b1;
      end

      assert (stat_read_req_timeout_retry == 0) begin
        $display("%t > [INFO]: HPU didn't retry sending other Read requests", $time);
      end else begin
        $display("%t > [ERROR]: Did %0d retries", $time, stat_read_req_timeout_retry);
        error_retry = 1'b1;
      end

      wait(interrupt_read_request);
      maxil_drv_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, read_data); // don't care about answer just need to lower itr

      repeat(100) @(posedge clk_control);

      check_fsm_initialized();

      if (~interrupt_read_request)
        $display("%t > [INFO]: interrupt_read_request correctly lowered", $time);

      scenario_end(scenario_id, clk_control, error);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Read request not answered in time: peer answers only after the timeout, DUT must retry.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_read_timeout();
    begin
      scenario_start(scenario_id, "Read: request unanswered -> timeout retry");
      iop_id       = scenario_id;
      iop_src_addr = $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1);
      iop_dst_addr = $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1);
      read_request(dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr);

      repeat(2*TIMEOUT_DUR_READ_REQ + 10 ) @(posedge clk_mhdma);

      $display("%t > [INFO]: answering only after %0d clock cycles", $time, 2*TIMEOUT_DUR_READ_REQ + 10);

      // Send ciphertext emission packets as if we're the remote HPU responding
      for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
        send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr, pkt[7:0], unused_payload);
        repeat(10) @(posedge clk_mhdma);
      end

      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_timeout_retry);

      assert (stat_read_req_timeout_retry != 0) begin
        $display("%t > [INFO]: Did %0d retries", $time, stat_read_req_timeout_retry);
      end else begin
        $display("%t > [ERROR]: HPU didn't retry sending other Notifies", $time);
        error_retry = 1'b1;
      end

      repeat(100) @(posedge clk_control);

      wait(interrupt_read_request);
      maxil_drv_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, read_data); // don't care about answer just need to lower itr

      repeat(100) @(posedge clk_control);

      check_fsm_initialized();

      if (~interrupt_read_request)
        $display("%t > [INFO]: interrupt_read_request correctly lowered", $time);

      scenario_end(scenario_id, clk_control, error);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Wrong seq num: peer sends a bad seq_num mid-burst, DUT aborts (seq_num_error) and retries.
  // Timeout is maxed out so the retry is provably mismatch-driven, not timeout-driven.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_recovery_wrong_seq_num();
    int                   corrupt_pos;
    logic [SEQ_NUM_W-1:0] corrupt_val;
    begin
      scenario_start(scenario_id, "Recovery: wrong seq_num -> immediate abort and retry");
      // Clear stale stat counter
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_timeout_retry);
      // Set timeout to max to prove retry happens via mismatch, NOT timeout
      maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS, 32'hFFFFFFFF);

      iop_id       = scenario_id;
      iop_src_addr = $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1);
      iop_dst_addr = $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1);

      fork
        read_request(dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr);
        wait(rx_header_vld & (rx_header.req_id == REQ_ID_READ));
      join

      // Wait for initial request to be consumed by decoder (avoid race on retry wait)
      wait(!rx_header_vld);

      // Pick a random packet (>=1, after the seq0 that sets up the address) and a wrong seq_num
      // for it, so the mismatch position/value varies run-to-run (exercises different partial-write
      // states on the abort path).
      corrupt_pos = $urandom_range(1, NB_PACKETS_FULL);
      corrupt_val = $urandom_range(0, NB_PACKETS_FULL);
      if (corrupt_val == corrupt_pos) corrupt_val = SEQ_NUM_W'(corrupt_pos + 1); // force a real mismatch
      $display("%t > [INFO]: injecting wrong seq_num=%0d at packet %0d", $time, corrupt_val, corrupt_pos);

      // Send CE packets while monitoring for the retry read request in parallel.
      // The abort + retry can complete while stale packets are still being sent,
      // so the retry monitor must run concurrently to avoid missing it.
      fork
        begin
          for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
            if (pkt == corrupt_pos) begin
              send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr, corrupt_val, unused_payload);
            end else begin
              send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr, pkt[7:0], unused_payload);
            end
            repeat(10) @(posedge clk_mhdma);
          end
        end
        begin
          // Wait for retry read request on QSFP TX (DUT completes abort then re-sends)
          wait(rx_header_vld & (rx_header.req_id == REQ_ID_READ));
          $display("%t > [INFO]: Retry read request detected on QSFP TX", $time);
        end
      join

      // Wait for retry read request to be fully consumed on QSFP TX
      wait(!rx_header_vld);

      if (interrupt_read_request) begin
        $display("%t > [ERROR]: interrupt_read_request should not have been raised during abort", $time);
        error_interrupt = 1'b1;
      end

      // Allow CDC propagation of stat counters (mhdma -> cfg clock domain)
      repeat(10) @(posedge clk_control);

      // Verify retry stat was incremented (mismatch-triggered, not timeout)
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_timeout_retry);
      assert (stat_read_req_timeout_retry != 0) begin
        $display("%t > [INFO]: Did %0d retries after wrong seq num", $time, stat_read_req_timeout_retry);
      end else begin
        $display("%t > [ERROR]: HPU didn't retry after seq_num mismatch", $time);
        error_retry = 1'b1;
      end

      // Only seq_num_error is expected; dumps the Errors block only if any other bit is set.
      // Single read of the read-to-clear errors register.
      maxil_drv_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors);
      check_only_seq_num_error(stat_errors);

      // Respond to retry with correct ciphertext (all packets from seq_num 0)
      for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
        send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr, pkt[7:0], unused_payload);
        repeat(10) @(posedge clk_mhdma);
      end

      repeat(200) @(posedge clk_control);

      if (interrupt_read_request) begin
        maxil_drv_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, read_data);
      end else begin
        $display("%t > [ERROR]: interrupt_read_request has not been raised after retry", $time);
        error_interrupt = 1'b1;
      end

      repeat(100) @(posedge clk_control);
      check_fsm_initialized();

      if (~interrupt_read_request)
        $display("%t > [INFO]: interrupt_read_request correctly lowered", $time);

      // Restore timeout for next scenario
      maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS, TIMEOUT_DUR_READ_REQ);

      scenario_end(scenario_id, clk_control, error);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Real packet drop: a middle packet never arrives, causing a forward-skip seq_num mismatch.
  // Forward-skip mismatch requires at least 3 packets (drop one in the middle).
  // NB_PACKETS_FULL < 2 means only 2 packets exist (seq_num 0..1), not enough -> SKIPPED.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_recovery_dropped_packet();
    begin
      if (NB_PACKETS_FULL < 2) begin
        scenario_start(scenario_id, $sformatf("Recovery: dropped packet -> abort and retry [SKIPPED NB_PACKETS_FULL=%0d < 2]", NB_PACKETS_FULL));
      end else begin
        scenario_start(scenario_id, "Recovery: dropped packet -> abort and retry");
        // Clear stale stat counter
        maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_timeout_retry);
        // Set timeout to max: we expect mismatch-triggered retry, not timeout
        maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS, 32'hFFFFFFFF);

        iop_id       = scenario_id;
        iop_src_addr = $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1);
        iop_dst_addr = $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1);

        // Drop a random middle packet: >= 1 (pkt 0 sets up the address) and <= NB_PACKETS_FULL-1
        // (a later packet must still arrive to trigger the forward-skip mismatch).
        drop_idx = $urandom_range(1, NB_PACKETS_FULL-1);

        fork
          read_request(dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr);
          wait(rx_header_vld & (rx_header.req_id == REQ_ID_READ));
        join

        // Wait for initial request to be consumed by decoder (avoid race on retry wait)
        wait(!rx_header_vld);

        // Send CE packets while monitoring for the retry read request in parallel.
        // The abort + retry can complete while stale packets are still being sent,
        // so the retry monitor must run concurrently to avoid missing it.
        fork
          begin
            // Send CE packets: drop one packet entirely (forward skip: DUT expects drop_idx, gets drop_idx+1)
            for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
              if (pkt == drop_idx) begin
                $display("%t > [INFO]: Dropping packet %0d (simulating network loss)", $time, drop_idx);
              end else begin
                send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr, pkt[7:0], unused_payload);
              end
              repeat(10) @(posedge clk_mhdma);
            end
          end
          begin
            // Wait for retry read request on QSFP TX
            wait(rx_header_vld & (rx_header.req_id == REQ_ID_READ));
            $display("%t > [INFO]: Retry read request detected on QSFP TX (mismatch on dropped pkt)", $time);
          end
        join

        // Wait for retry read request to be fully consumed on QSFP TX
        wait(!rx_header_vld);

        if (interrupt_read_request) begin
          $display("%t > [ERROR]: interrupt_read_request should not have been raised during abort", $time);
          error_interrupt = 1'b1;
        end

        // Allow CDC propagation of stat counters (mhdma -> cfg clock domain)
        repeat(10) @(posedge clk_control);

        // Verify retry stat was incremented
        maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_timeout_retry);
        assert (stat_read_req_timeout_retry != 0) begin
          $display("%t > [INFO]: Did %0d retries after packet loss", $time, stat_read_req_timeout_retry);
        end else begin
          $display("%t > [ERROR]: HPU didn't retry after packet loss", $time);
          error_retry = 1'b1;
        end

        // Only seq_num_error is expected; dumps the Errors block only if any other bit is set.
        // Single read of the read-to-clear errors register.
        maxil_drv_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors);
        check_only_seq_num_error(stat_errors);

        // Respond to retry with complete correct ciphertext
        for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
          send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr, pkt[7:0], unused_payload);
          repeat(10) @(posedge clk_mhdma);
        end

        repeat(200) @(posedge clk_control);

        if (interrupt_read_request) begin
          maxil_drv_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, read_data);
        end else begin
          $display("%t > [ERROR]: interrupt_read_request has not been raised after retry", $time);
          error_interrupt = 1'b1;
        end

        repeat(100) @(posedge clk_control);
        check_fsm_initialized();

        if (~interrupt_read_request)
          $display("%t > [INFO]: interrupt_read_request correctly lowered", $time);

        // Restore timeout for subsequent scenarios
        maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS, TIMEOUT_DUR_READ_REQ);
      end // if NB_PACKETS_FULL >= 2

      scenario_end(scenario_id, clk_control, error);
    end
  endtask

  // Force a mismatch-driven (not timeout-driven) retry on a fresh master read, leaving the DUT
  // master FSM parked in wait_for_seq0. On return the retry read request has drained off the TX.
  task automatic arm_wait_for_seq0();
    logic [REG_DATA_W-1:0] retry_base, retry_now;
    begin
      // Baseline the retry counter so we can positively confirm the corrupted burst actually drove
      // a mismatch retry (otherwise the scenario could silently pass without exercising recovery).
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, retry_base);
      maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS, 32'hFFFFFFFF); // disable timeout retry

      iop_id       = scenario_id;
      iop_src_addr = $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1);
      iop_dst_addr = $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1);

      // DUT (master) issues a read request; wait until it appears on the QSFP TX.
      fork
        read_request(dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr);
        wait(rx_header_vld & (rx_header.req_id == REQ_ID_READ));
      join
      wait(!rx_header_vld);

      // Answer with a corrupted burst (forward-skip mismatch) and wait for the DUT to abort and
      // re-send its read request (the retry) - that re-send marks entry into wait_for_seq0.
      fork
        send_ce_emission(.corrupt_seq1(1'b1));
        begin
          wait(rx_header_vld & (rx_header.req_id == REQ_ID_READ));
          $display("%t > [INFO]: Retry read request detected on QSFP TX (DUT now in wait_for_seq0)", $time);
        end
      join
      wait(!rx_header_vld);

      // Confirm the mismatch actually triggered a retry (CDC settle first for the cfg-domain stat).
      repeat(10) @(posedge clk_control);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, retry_now);
      assert (retry_now != retry_base) begin
        $display("%t > [INFO]: mismatch-driven retry confirmed (arm_wait_for_seq0)", $time);
      end else begin
        $display("%t > [ERROR]: arm_wait_for_seq0: no mismatch-driven retry observed", $time);
        error_retry = 1'b1;
      end
    end
  endtask

  // Send a full seq0..N ciphertext emission for the current iop. If corrupt_seq1, packet index 1
  // carries seq_num=3 (instead of 1) to trigger a forward-skip mismatch.
  task automatic send_ce_emission(input bit corrupt_seq1);
    begin
      send_full_ciphertext_burst(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id,
                                 iop_id, iop_src_addr, iop_dst_addr, unused_payload,
                                 .corrupt_idx(corrupt_seq1 ? 1 : -1));
    end
  endtask

  // Block until the master read completes. A true head-of-line wedge never completes and is caught
  // by the global watchdog (-> error_timeout_watchdog). No fixed wait: slave CE responses scale
  // with ciphertext size (GLWE_K / -g), so a fixed timeout would false-"wedge" larger configs.
  task automatic wait_master_read_done();
    begin
      $display("%t > [INFO]: waiting for master read to complete (global watchdog arbitrates a true wedge)", $time);
      wait(interrupt_read_request);
      $display("%t > [INFO]: master read completed during concurrent slave activity", $time);
      maxil_drv_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, read_data);
    end
  endtask

  // Confirm both injected slave-role commands were received (not silently dropped behind recovery).
  // errors_val is the (already-read) error register, passed through to the on-error dump so we do
  // not re-read (and thus clear) the read-to-clear errors register.
  task automatic check_two_slave_cmds_received(input string kind, input logic [REG_DATA_W-1:0] delta,
                                               input logic [REG_DATA_W-1:0] errors_val);
    begin
      assert (delta == 2) begin
        $display("%t > [INFO]: both slave-role %s received during recovery", $time, kind);
      end else begin
        $display("%t > [ERROR]: slave-role %s not all received (delta=%0d, expected 2) - dropped while master recovering", $time, kind, delta);
        dump_mhdma_state($sformatf("slave-role %s dropped during recovery", kind), errors_val);
        error_register_read = 1'b1;
      end
    end
  endtask

  // READ variant: slave-role READs sit at the stream head ahead of the recovery emission.
  task automatic run_scenario_recovery_slave_read();
    begin
      if (NB_PACKETS_FULL < 2) begin
        scenario_start(scenario_id, $sformatf("Recovery: concurrent slave READ (head-of-line) [SKIPPED NB_PACKETS_FULL=%0d < 2]", NB_PACKETS_FULL));
      end else begin
        scenario_start(scenario_id, "Recovery: concurrent slave READ (head-of-line)");

        arm_wait_for_seq0();

        // Inject slave-role READs at the head of the shared stream, ahead of the recovery emission.
        $display("%t > [INFO]: Injecting slave-role read requests during recovery window", $time);
        maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS, rr_recv_base);
        for (int sl = 0; sl < 2; sl++) begin
          send_read_request_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, 8'hC0 + sl[7:0],
                                   $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1),
                                   $urandom_range(0, (1 << MEM_SIM_SIZE) / CT_MEM_BYTES - 1));
          repeat(5) @(posedge clk_mhdma);
        end

        // Recovery emission sits BEHIND the slave reads - the master read must still complete.
        send_ce_emission(.corrupt_seq1(1'b0));
        wait_master_read_done();

        maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS, stat_cnt_read_req_received);
        // Single read of the read-to-clear errors register, shared by both checks below.
        maxil_drv_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors);
        check_two_slave_cmds_received("read requests", stat_cnt_read_req_received - rr_recv_base, stat_errors);
        check_only_seq_num_error(stat_errors);

        // Slave CE/notify-ack responses to the injected commands may still be draining; wait for
        // the FSMs to settle (watchdog backstops a true wedge) instead of a fixed, too-short delay.
        wait_fsm_idle();
        check_fsm_initialized();
        maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS, TIMEOUT_DUR_READ_REQ);
      end
      scenario_end(scenario_id, clk_control, error);
    end
  endtask

  // NOTIFY variant: slave-role NOTIFYs sit at the stream head ahead of the recovery emission.
  task automatic run_scenario_recovery_slave_notify();
    begin
      if (NB_PACKETS_FULL < 2) begin
        scenario_start(scenario_id, $sformatf("Recovery: concurrent slave NOTIFY (head-of-line) [SKIPPED NB_PACKETS_FULL=%0d < 2]", NB_PACKETS_FULL));
      end else begin
        scenario_start(scenario_id, "Recovery: concurrent slave NOTIFY (head-of-line)");

        arm_wait_for_seq0();

        // Inject slave-role NOTIFYs at the head of the shared stream, ahead of the recovery emission.
        $display("%t > [INFO]: Injecting slave-role notify requests during recovery window", $time);
        maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_NOTIFY_RECEIVED_OFS, nr_recv_base);
        for (int sl = 0; sl < 2; sl++) begin
          send_notify_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, 8'hD0 + sl[7:0],
                             $urandom_range(0, (1<<SRC_ADDR_W)-1));
          repeat(5) @(posedge clk_mhdma);
        end

        // Recovery emission sits BEHIND the slave notifies - the master read must still complete.
        send_ce_emission(.corrupt_seq1(1'b0));
        wait_master_read_done();

        // Service the two notify interrupts so the nrx regf path drains and its FSM returns to idle.
        for (int n = 0; n < 2; n++) begin
          wait(interrupt_notify);
          maxil_drv_if.read_trans(MHDMA_REQUEST_NOTIFY_REQ_ID_OFS, read_data);
          repeat(5) @(posedge clk_control);
        end

        maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_NOTIFY_RECEIVED_OFS, stat_cnt_notify_received);
        // Single read of the read-to-clear errors register, shared by both checks below.
        maxil_drv_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors);
        check_two_slave_cmds_received("notifies", stat_cnt_notify_received - nr_recv_base, stat_errors);
        check_only_seq_num_error(stat_errors);

        // Slave CE/notify-ack responses to the injected commands may still be draining; wait for
        // the FSMs to settle (watchdog backstops a true wedge) instead of a fixed, too-short delay.
        wait_fsm_idle();
        check_fsm_initialized();
        maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS, TIMEOUT_DUR_READ_REQ);
      end
      scenario_end(scenario_id, clk_control, error);
    end
  endtask

  task automatic print_final_summary();
    begin
      $display("\n========================================= HPU_A Final Summary  ======================================");
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, stat_notify);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS, stat_notify_ack);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, stat_notify_retry);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_retry);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS, stat_notify_timeout);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_OFS, stat_t_notify_to_ack);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_OFS, stat_t_rr_to_ce_received);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_T_CE_FIRST_TO_LAST_PKT_OFS, stat_t_ce_first_to_last_pkt);
      maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS, stat_cnt_nack_received);
      $display(" stat_notify                 : %0d", stat_notify);
      $display(" stat_notify_ack             : %0d", stat_notify_ack);
      $display(" stat_nack_received          : %0d", stat_cnt_nack_received);
      $display(" stat_notify_retry           : %0d", stat_notify_retry);
      $display(" stat_read_req_retry         : %0d", stat_read_req_retry);
      $display(" stat_notify_timeout         : %0d", stat_notify_timeout);
      $display(" stat_t_notify_to_ack        : %0d", stat_t_notify_to_ack);
      $display(" stat_t_rr_to_ce_received    : %0d", stat_t_rr_to_ce_received);
      $display(" stat_t_ce_first_to_last_pkt : %0d", stat_t_ce_first_to_last_pkt);
      $display("==================================================================================================\n");
    end
  endtask

  task automatic init_config;
    begin
      // Reading system REGISTERS -----------------------------------------------------------------
      maxil_drv_if.read_trans(MHDMA_SYSTEM_LANE_OFS, rdata);
      assert (rdata == 'h0) else begin
        $display("%t > ERROR:register MHDMA_SYSTEM_LANE_OFS not correctly read %h",$time, rdata);
        error_register_read = 1'b1;
      end

      qsfp_rx_tdata = 'h0;
      qsfp_rx_tkeep_user = 'h0;
      qsfp_rx_tlast = 'h0;
      qsfp_rx_tvalid = 'h0;

      // Setting timeout size ---------------------------------------------------------------------
      maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_NOTIFY_OFS, TIMEOUT_DUR_NOTIFY);
      maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS, TIMEOUT_DUR_READ_REQ);

      // Setting up credible values -------------------------------------------------------------
      // no loopback, no reset, not in debug lane0 selected
      line_rate     = 8'h0;
      line_loopback = 3'b000;
      lane   = 2'b00;
      debug_flag    = 1'b0;
      rst_rx_datapath = 4'b0000;
      rst_tx_datapath = 4'b0000;
      rst_all         = 4'b0000;
      maxil_drv_if.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);
      @(posedge clk_control);

      src_hpu_id = 0;
      dst_hpu_id = 1;

      src_mac_addr = $urandom();
      dst_mac_addr = $urandom();

      write_mac_addresses(dst_mac_addr, src_mac_addr);

      $display("%t > INFO: Configuration successful\n",$time);
    end
  endtask

  task automatic write_mac_addresses(
    input logic [MAC_ADDR_W-1:0] src_mac_addr,
    input logic [MAC_ADDR_W-1:0] dst_mac_addr
  );
    begin
      maxil_drv_if.write_trans(MHDMA_SYSTEM_HPU_ID_0_OFS, {1'b1, 7'b0, src_mac_addr});
      maxil_drv_if.write_trans(MHDMA_SYSTEM_HPU_ID_1_OFS, {1'b0, 7'b0, dst_mac_addr});

      repeat(50) @(posedge clk_mhdma);

    end
  endtask

  /* Performs a Notify request from an HPU to another
   * - HPU-A and HPU-B can be both side here
   * - if you chose a wrong HPU-id you will get an error
   */
  task automatic notify_request(
    input logic [  HPU_ID_W-1:0] src_node_id,
    input logic [  HPU_ID_W-1:0] dst_node_id,
    input logic [  IOP_ID_W-1:0] iop_id,
    input logic [SRC_ADDR_W-1:0] src_addr
  );
    logic [REG_DATA_W-1:00] read_req_id;
    logic [REG_DATA_W-1:00] read_req_addr;
    begin

      read_req_addr = {16'b0, src_addr};
      read_req_id = {iop_id, REQ_ID_NOTIFY, dst_node_id, req_rfm};

      maxil_drv_if.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv_if.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);

      repeat(50) @(posedge clk_mhdma);

    end
  endtask

  /* Performs a Read request from HPU A to HPU B
    - Since HPU A and HPU B are the same no need to be able to be able to send from both
    - There is two registers to write to send a read request */
  task automatic read_request(
    input logic [  HPU_ID_W-1:0] node_id,
    input logic [  IOP_ID_W-1:0] iop_id,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dest_addr
  );
    logic [REG_DATA_W-1:0] read_req_id;
    logic [REG_DATA_W-1:0] read_req_addr;
    begin
      // see package
      read_req_addr = {dest_addr, src_addr};
      read_req_id = {iop_id, REQ_ID_READ, node_id, req_rfm};

      maxil_drv_if.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv_if.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);

      repeat(50) @(posedge clk_mhdma);

    end
  endtask

  // Wait for the DUT FSMs to drain before check_fsm_initialized(). The DUT's slave-role CE /
  // notify-ack responses scale with ciphertext size, so a fixed settle is unsafe; poll the FSMs.
  // Require all FSMs to stay idle for FSM_IDLE_STABLE consecutive cycles before returning, so we do
  // not stop in the brief CEM_WAIT gap *between* two back-to-back slave responses (which would make
  // check_fsm_initialized pass while a second response is still pending). A true wedge never reaches
  // the stable window and is caught by the global watchdog.
  localparam int FSM_IDLE_STABLE = 16;
  task automatic wait_fsm_idle();
    int idle_cnt;
    begin
      idle_cnt = 0;
      while (idle_cnt < FSM_IDLE_STABLE) begin
        if (hpu_a.mhdma_bridge.mhdma_master.rreq_state  != 0
         || hpu_a.mhdma_bridge.mhdma_master.ntx_retry   != 0
         || hpu_a.mhdma_bridge.mhdma_slave.cem_state    != 0
         || hpu_a.mhdma_bridge.mhdma_slave.nrx_state    != 0
         || hpu_a.mhdma_bridge.mhdma_formatter.tx_state != 0)
          idle_cnt = 0;
        else
          idle_cnt = idle_cnt + 1;
        @(posedge clk_mhdma);
      end
    end
  endtask

  task automatic check_fsm_initialized();
    bit fsm_err;
    begin
      fsm_err = 1'b0;
      if (hpu_a.mhdma_bridge.mhdma_master.ntx_retry != 0) begin
        $display("%t > [ERROR] : FSM mhdma_master.ntx_retry has not been back to IDLE", $time);
        fsm_err = 1'b1;
      end
      if (hpu_a.mhdma_bridge.mhdma_master.rreq_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_master.rreq_state has not been back to IDLE", $time);
        fsm_err = 1'b1;
      end
      if (hpu_a.mhdma_bridge.mhdma_slave.nrx_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_slave.nrx_state has not been back to IDLE", $time);
        fsm_err = 1'b1;
      end
      if (hpu_a.mhdma_bridge.mhdma_slave.cem_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_slave.cem_state has not been back to IDLE", $time);
        fsm_err = 1'b1;
      end
      if (hpu_a.mhdma_bridge.mhdma_formatter.tx_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_slave.tx_state has not been back to IDLE", $time);
        fsm_err = 1'b1;
      end

      if (fsm_err) begin
        // Single read of the read-to-clear errors register, handed to the dump.
        maxil_drv_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors);
        dump_mhdma_state("FSM not back to IDLE", stat_errors);
        error_fsm = 1'b1;
      end else begin
        repeat(50) @(posedge clk_mhdma);
        $display("%t > [INFO]: all FSMs are back to IDLE", $time);
      end
    end
  endtask


  task automatic check_only_seq_num_error(input logic [REG_DATA_W-1:0] errors_val);
    begin
      assert ((errors_val & ~(REG_DATA_W'('h8))) == '0) begin
        $display("%t > [INFO]: only seq_num_error set, as expected (0x%08h)", $time, errors_val);
      end else begin
        $display("%t > [ERROR]: unexpected error bits during concurrent slave activity: 0x%08h", $time, errors_val);
        dump_mhdma_state("unexpected error bits", errors_val);
        error_register_read = 1'b1;
      end
    end
  endtask

  task automatic dump_mhdma_state(input string ctx, input logic [REG_DATA_W-1:0] errors_val);
    logic [REG_DATA_W-1:0] dbg_fsm_value;
    begin
      $display("\n%t > [DEBUG] ===== MHDMA state dump (%s) =====", $time, ctx);
      display_errors(errors_val);
      maxil_drv_if.read_trans(MHDMA_SYSTEM_FSM_VALUE_OFS, dbg_fsm_value);
      $display(" fsm_value register            : 0x%08h", dbg_fsm_value);
      $display("   master.notify   (ntx_state) : 0x%0h", hpu_a.mhdma_bridge.mhdma_master.ntx_state);
      $display("   master.read_req (rreq_state): 0x%0h  (0 = RR_WAIT_REQUEST / idle)", hpu_a.mhdma_bridge.mhdma_master.rreq_state);
      $display("   master.ntx_retry            : %0b", hpu_a.mhdma_bridge.mhdma_master.ntx_retry);
      $display("   slave.notify_rx (nrx_state) : 0x%0h", hpu_a.mhdma_bridge.mhdma_slave.nrx_state);
      $display("   slave.cem       (cem_state) : 0x%0h", hpu_a.mhdma_bridge.mhdma_slave.cem_state);
      $display("   formatter.tx    (tx_state)  : 0x%0h", hpu_a.mhdma_bridge.mhdma_formatter.tx_state);
      $display(" %t > [DEBUG] ===== end MHDMA state dump =====\n", $time);
    end
  endtask

endmodule
