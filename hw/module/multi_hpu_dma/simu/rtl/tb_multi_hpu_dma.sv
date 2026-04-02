// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This testbench only tests debug mode
// Debug mode corresponds to the control of one lane through register file
//
// Note: fifo starvation on QSFP TX is not tested here but on formatter testbench.
// run with "run_edalize -m tb_multi_hpu_dma -t vcs -F TOP_PC TOP_PC_pem2_glwe1_bsk8_ksk8 -F TOP_PCMAX TOP_PCMAX_pem2_glwe1_bsk8_ksk8 -F AXI_DATA_W AXI_DATA_W_256"
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_multi_hpu_dma;
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

  localparam int HPU_NB = 2; // in this test we will try to connect two mhdma (or HPUs)

  localparam int LOOP_NOTIFY = 10;
  localparam int BREAK_RDY_VLD = 1;

  // ciphertext memories -------------------------------------------------------------------------
  // We do more than 1 read/write at a time but I want to simulate waits in HBM
  localparam int MEM_WR_CMD_BUF_DEPTH = 1;
  localparam int MEM_RD_CMD_BUF_DEPTH = 1;
  // Data latency, values are arbitrary
  localparam int MEM_WR_DATA_LATENCY = 142;
  localparam int MEM_RD_DATA_LATENCY = 100;
  // Set random on ready valid, on write and read path
  localparam bit MEM_USE_WR_RANDOM = 1;
  localparam bit MEM_USE_RD_RANDOM = 1;

  // simulation sizes to reduce runtime
  localparam int MEM_SIM_SIZE = 18; // must be < 22 in order to not slow down sim too much!
  localparam int RFM_SIM      = 'h0;

  // Max ciphertext ID based on memory simulation size
  localparam int MEM_MAX_VALUE = (1 << MEM_SIM_SIZE) / CT_MEM_BYTES;

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
  bit error_tb_notify;
  bit error_register_read;
  bit error_notify_payload;
  bit error_rr_payload;
  bit error_write_mismatch;
  bit error_interrupt_notify;
  bit error_assert;
  bit error_register;

  assign error = error_register | error_tb_notify | error_register_read | error_notify_payload | error_rr_payload | error_write_mismatch | error_interrupt_notify | error_assert;

  always_ff @(posedge clk_control)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // =========================================================================================== --
  // input / output signals
  // =========================================================================================== --
  // AXI4-Lite slave interface
  logic [HPU_NB-1:0][AXIL_ADD_W-1:0]      s_axil_mhdma_awaddr;
  logic [HPU_NB-1:0]                      s_axil_mhdma_awvalid;
  logic [HPU_NB-1:0]                      s_axil_mhdma_awready;
  logic [HPU_NB-1:0][AXIL_DATA_W-1:0]     s_axil_mhdma_wdata;
  logic [HPU_NB-1:0][AXIL_DATA_BYTES-1:0] s_axil_mhdma_wstrb; /* UNUSED */
  logic [HPU_NB-1:0]                      s_axil_mhdma_wvalid;
  logic [HPU_NB-1:0]                      s_axil_mhdma_wready;
  logic [HPU_NB-1:0][1:0]                 s_axil_mhdma_bresp;
  logic [HPU_NB-1:0]                      s_axil_mhdma_bvalid;
  logic [HPU_NB-1:0]                      s_axil_mhdma_bready;
  logic [HPU_NB-1:0][AXIL_ADD_W-1:0]      s_axil_mhdma_araddr;
  logic [HPU_NB-1:0]                      s_axil_mhdma_arvalid;
  logic [HPU_NB-1:0]                      s_axil_mhdma_arready;
  logic [HPU_NB-1:0][AXIL_DATA_W-1:0]     s_axil_mhdma_rdata;
  logic [HPU_NB-1:0][1:0]                 s_axil_mhdma_rresp;
  logic [HPU_NB-1:0]                      s_axil_mhdma_rvalid;
  logic [HPU_NB-1:0]                      s_axil_mhdma_rready;
  // QSFP system interface
  // == TX
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_tx_tdata;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_tx_tlast;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_tx_tvalid;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_tx_tready;

  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_rx_tdata_delayed;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user_delayed;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_rx_tlast_delayed;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid_delayed;

  // Interrupt interface
  logic [HPU_NB-1:0]                                      interrupt_notify;
  logic [HPU_NB-1:0]                                      interrupt_read_request;

  // cnx to memory models - vectorized [HPU_NB][ETH_PC]
  logic [HPU_NB-1:0][ETH_PC-1:0][AXI4_ID_W-1:0]           axi4_ct_awid;
  logic [HPU_NB-1:0][ETH_PC-1:0][AXI4_ADD_W-1:0]          axi4_ct_awaddr;
  logic [HPU_NB-1:0][ETH_PC-1:0][7:0]                     axi4_ct_awlen;
  logic [HPU_NB-1:0][ETH_PC-1:0][2:0]                     axi4_ct_awsize;
  logic [HPU_NB-1:0][ETH_PC-1:0][1:0]                     axi4_ct_awburst;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_awvalid;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_awready;
  logic [HPU_NB-1:0][ETH_PC-1:0][AXI4_DATA_W-1:0]         axi4_ct_wdata;
  logic [HPU_NB-1:0][ETH_PC-1:0][(AXI4_DATA_W/8)-1:0]     axi4_ct_wstrb;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_wlast;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_wvalid;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_wready;
  logic [HPU_NB-1:0][ETH_PC-1:0][AXI4_ID_W-1:0]           axi4_ct_bid;
  logic [HPU_NB-1:0][ETH_PC-1:0][1:0]                     axi4_ct_bresp;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_bvalid;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_bready;

  logic [HPU_NB-1:0][ETH_PC-1:0][AXI4_ID_W-1:0]           axi4_ct_arid;
  logic [HPU_NB-1:0][ETH_PC-1:0][AXI4_ADD_W-1:0]          axi4_ct_araddr;
  logic [HPU_NB-1:0][ETH_PC-1:0][7:0]                     axi4_ct_arlen;
  logic [HPU_NB-1:0][ETH_PC-1:0][2:0]                     axi4_ct_arsize;
  logic [HPU_NB-1:0][ETH_PC-1:0][1:0]                     axi4_ct_arburst;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_arvalid;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_arready;
  logic [HPU_NB-1:0][ETH_PC-1:0][AXI4_ID_W-1:0]           axi4_ct_rid;
  logic [HPU_NB-1:0][ETH_PC-1:0][AXI4_DATA_W-1:0]         axi4_ct_rdata;
  logic [HPU_NB-1:0][ETH_PC-1:0][1:0]                     axi4_ct_rresp;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_rlast;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_rvalid;
  logic [HPU_NB-1:0][ETH_PC-1:0]                          axi4_ct_rready;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  // gt configuration signals
  logic [HPU_NB-1:0][7:0]              gt_line_rate;
  logic [HPU_NB-1:0][2:0]              gt_loopback;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_reset_rx_datapath;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_reset_tx_datapath;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_reset_all;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_rx_reset_done;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_tx_reset_done;

  // [section] line parameter -------------------------------------------------
  logic [REG_DATA_W-1:0] line_parameter;
  logic        debug_flag;
  logic [2:0]  line_loopback;
  logic [7:0]  line_rate;
  logic [1:0]  line_select;

  assign line_parameter[1:0]   = line_select;
  assign line_parameter[4:2]   = line_loopback;
  assign line_parameter[12:5]  = line_rate;
  assign line_parameter[27:13] = 'h0;
  assign line_parameter[31]    = debug_flag;

  // [section] line debug -----------------------------------------------------
  logic [REG_DATA_W-1:0] line_debug;
  logic        reset_registers;
  logic        tx_loop;
  logic        rx_to_tx;

  assign line_debug[28:0] = 'h0;
  assign line_debug[29]   = rx_to_tx;
  assign line_debug[30]   = tx_loop;
  assign line_debug[31]   = reset_registers;

  // [section] reset ----------------------------------------------------------
  logic [REG_DATA_W-1:00] reset_parameter;
  logic [QSFP_LANE_NB-1:0] rst_rx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_tx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_all;

  assign reset_parameter = {20'h0, rst_rx_datapath, rst_tx_datapath, rst_all};

  // monitoring of reset done
  logic [HPU_NB-1:0][REG_DATA_W-1:00] reset_monitor;

  // ============================================================================================== --
  // Multi-HPU DMA instances
  // ============================================================================================== --
  generate
    for (genvar gen_hpu = 0; gen_hpu < HPU_NB; gen_hpu++) begin : gen_multi_hpu_dma
      multi_hpu_dma multi_hpu_dma (
        .clk_mhdma_cfg            (clk_control                        ),
        .resetn_mhdma_cfg         (s_rstn_control                     ),

        .clk_mhdma          (clk_mhdma                          ),
        .resetn_mhdma       (s_rstn_mhdma                       ),

        .s_axil_mhdma_awaddr      (s_axil_mhdma_awaddr         [gen_hpu]),
        .s_axil_mhdma_awvalid     (s_axil_mhdma_awvalid        [gen_hpu]),
        .s_axil_mhdma_awready     (s_axil_mhdma_awready        [gen_hpu]),
        .s_axil_mhdma_wdata       (s_axil_mhdma_wdata          [gen_hpu]),
        .s_axil_mhdma_wstrb       (s_axil_mhdma_wstrb          [gen_hpu]),
        .s_axil_mhdma_wvalid      (s_axil_mhdma_wvalid         [gen_hpu]),
        .s_axil_mhdma_wready      (s_axil_mhdma_wready         [gen_hpu]),
        .s_axil_mhdma_bresp       (s_axil_mhdma_bresp          [gen_hpu]),
        .s_axil_mhdma_bvalid      (s_axil_mhdma_bvalid         [gen_hpu]),
        .s_axil_mhdma_bready      (s_axil_mhdma_bready         [gen_hpu]),
        .s_axil_mhdma_araddr      (s_axil_mhdma_araddr         [gen_hpu]),
        .s_axil_mhdma_arvalid     (s_axil_mhdma_arvalid        [gen_hpu]),
        .s_axil_mhdma_arready     (s_axil_mhdma_arready        [gen_hpu]),
        .s_axil_mhdma_rdata       (s_axil_mhdma_rdata          [gen_hpu]),
        .s_axil_mhdma_rresp       (s_axil_mhdma_rresp          [gen_hpu]),
        .s_axil_mhdma_rvalid      (s_axil_mhdma_rvalid         [gen_hpu]),
        .s_axil_mhdma_rready      (s_axil_mhdma_rready         [gen_hpu]),

        .m_axi4_mhdma_hbm_arid    (axi4_ct_arid              [gen_hpu]),
        .m_axi4_mhdma_hbm_araddr  (axi4_ct_araddr            [gen_hpu]),
        .m_axi4_mhdma_hbm_arlen   (axi4_ct_arlen             [gen_hpu]),
        .m_axi4_mhdma_hbm_arsize  (axi4_ct_arsize            [gen_hpu]),
        .m_axi4_mhdma_hbm_arburst (axi4_ct_arburst           [gen_hpu]),
        .m_axi4_mhdma_hbm_arvalid (axi4_ct_arvalid           [gen_hpu]),
        .m_axi4_mhdma_hbm_arready (axi4_ct_arready           [gen_hpu]),
        .m_axi4_mhdma_hbm_rid     (axi4_ct_rid               [gen_hpu]),
        .m_axi4_mhdma_hbm_rdata   (axi4_ct_rdata             [gen_hpu]),
        .m_axi4_mhdma_hbm_rresp   (axi4_ct_rresp             [gen_hpu]),
        .m_axi4_mhdma_hbm_rlast   (axi4_ct_rlast             [gen_hpu]),
        .m_axi4_mhdma_hbm_rvalid  (axi4_ct_rvalid            [gen_hpu]),
        .m_axi4_mhdma_hbm_rready  (axi4_ct_rready            [gen_hpu]),
        .m_axi4_mhdma_hbm_awid    (axi4_ct_awid              [gen_hpu]),
        .m_axi4_mhdma_hbm_awaddr  (axi4_ct_awaddr            [gen_hpu]),
        .m_axi4_mhdma_hbm_awlen   (axi4_ct_awlen             [gen_hpu]),
        .m_axi4_mhdma_hbm_awsize  (axi4_ct_awsize            [gen_hpu]),
        .m_axi4_mhdma_hbm_awburst (axi4_ct_awburst           [gen_hpu]),
        .m_axi4_mhdma_hbm_awvalid (axi4_ct_awvalid           [gen_hpu]),
        .m_axi4_mhdma_hbm_awready (axi4_ct_awready           [gen_hpu]),
        .m_axi4_mhdma_hbm_wdata   (axi4_ct_wdata             [gen_hpu]),
        .m_axi4_mhdma_hbm_wstrb   (axi4_ct_wstrb             [gen_hpu]),
        .m_axi4_mhdma_hbm_wlast   (axi4_ct_wlast             [gen_hpu]),
        .m_axi4_mhdma_hbm_wvalid  (axi4_ct_wvalid            [gen_hpu]),
        .m_axi4_mhdma_hbm_wready  (axi4_ct_wready            [gen_hpu]),
        .m_axi4_mhdma_hbm_bid     (axi4_ct_bid               [gen_hpu]),
        .m_axi4_mhdma_hbm_bresp   (axi4_ct_bresp             [gen_hpu]),
        .m_axi4_mhdma_hbm_bvalid  (axi4_ct_bvalid            [gen_hpu]),
        .m_axi4_mhdma_hbm_bready  (axi4_ct_bready            [gen_hpu]),

        .qsfp_tx_tdata          (qsfp_tx_tdata             [gen_hpu]),
        .qsfp_tx_tkeep_user     (qsfp_tx_tkeep_user        [gen_hpu]),
        .qsfp_tx_tlast          (qsfp_tx_tlast             [gen_hpu]),
        .qsfp_tx_tvalid         (qsfp_tx_tvalid            [gen_hpu]),
        .qsfp_tx_tready         (qsfp_tx_tready            [gen_hpu]),

        .qsfp_rx_tdata          (qsfp_rx_tdata_delayed     [gen_hpu]),
        .qsfp_rx_tkeep_user     (qsfp_rx_tkeep_user_delayed[gen_hpu]),
        .qsfp_rx_tlast          (qsfp_rx_tlast_delayed     [gen_hpu]),
        .qsfp_rx_tvalid         (qsfp_rx_tvalid_delayed    [gen_hpu]),

        .interrupt_notify       (interrupt_notify          [gen_hpu]),
        .interrupt_read_request (interrupt_read_request    [gen_hpu]),

        .gt_line_rate           (gt_line_rate              [gen_hpu]),
        .gt_loopback            (gt_loopback               [gen_hpu]),
        .gt_reset_rx_datapath   (gt_reset_rx_datapath      [gen_hpu]),
        .gt_reset_tx_datapath   (gt_reset_tx_datapath      [gen_hpu]),
        .gt_reset_all           (gt_reset_all              [gen_hpu]),
        .gt_rx_reset_done       (gt_rx_reset_done          [gen_hpu]),
        .gt_tx_reset_done       (gt_tx_reset_done          [gen_hpu])
      );
    end
  endgenerate

  // ============================================================================================== --
  // Ready/valid control logic
  // ============================================================================================== --
  generate
    for (genvar gen_hpu = 0; gen_hpu < HPU_NB; gen_hpu++) begin : gen_rdyvld_ctrl
      for (genvar gen_i = 0; gen_i < QSFP_LANE_NB; gen_i++) begin : gen_lane
        tb_model_backpressure #(.ENABLE(BREAK_RDY_VLD)) bp_tx (
          .clk         (clk_mhdma),
          .rstn        (s_rstn_mhdma),

          .s_tdata     (qsfp_tx_tdata            [gen_hpu][gen_i]),
          .s_tkeep_user(qsfp_tx_tkeep_user       [gen_hpu][gen_i]),
          .s_tlast     (qsfp_tx_tlast            [gen_hpu][gen_i]),
          .s_tvalid    (qsfp_tx_tvalid           [gen_hpu][gen_i]),
          .s_tready    (qsfp_tx_tready           [gen_hpu][gen_i]),

          .m_tdata     (qsfp_rx_tdata_delayed     [1-gen_hpu][gen_i]),
          .m_tkeep_user(qsfp_rx_tkeep_user_delayed[1-gen_hpu][gen_i]),
          .m_tlast     (qsfp_rx_tlast_delayed     [1-gen_hpu][gen_i]),
          .m_tvalid    (qsfp_rx_tvalid_delayed    [1-gen_hpu][gen_i])
        );
      end
    end
  endgenerate

// ============================================================================================== --
// Scenario
// ============================================================================================== --

  // AXI4-LITE drivers ----------------------------------------------------------------------------
  generate
    for (genvar gen_hpu = 0; gen_hpu < HPU_NB; gen_hpu++) begin : gen_maxil_if
      maxil_if #(
        .AXIL_DATA_W(AXIL_DATA_W),
        .AXIL_ADD_W (AXIL_ADD_W)
      ) maxil_if ( .clk(clk_control), .rst_n(s_rstn_control));

      assign s_axil_mhdma_awaddr [gen_hpu] = maxil_if.awaddr;
      assign s_axil_mhdma_awvalid[gen_hpu] = maxil_if.awvalid;
      assign s_axil_mhdma_wdata  [gen_hpu] = maxil_if.wdata;
      assign s_axil_mhdma_wstrb  [gen_hpu] = maxil_if.wstrb;
      assign s_axil_mhdma_wvalid [gen_hpu] = maxil_if.wvalid;
      assign s_axil_mhdma_bready [gen_hpu] = maxil_if.bready;
      assign s_axil_mhdma_araddr [gen_hpu] = maxil_if.araddr;
      assign s_axil_mhdma_arvalid[gen_hpu] = maxil_if.arvalid;
      assign s_axil_mhdma_rready [gen_hpu] = maxil_if.rready;

      assign maxil_if.awready = s_axil_mhdma_awready[gen_hpu];
      assign maxil_if.wready  = s_axil_mhdma_wready [gen_hpu];
      assign maxil_if.bresp   = s_axil_mhdma_bresp  [gen_hpu];
      assign maxil_if.bvalid  = s_axil_mhdma_bvalid [gen_hpu];
      assign maxil_if.arready = s_axil_mhdma_arready[gen_hpu];
      assign maxil_if.rdata   = s_axil_mhdma_rdata  [gen_hpu];
      assign maxil_if.rresp   = s_axil_mhdma_rresp  [gen_hpu];
      assign maxil_if.rvalid  = s_axil_mhdma_rvalid [gen_hpu];
    end
  endgenerate

  generate
    for (genvar gen_hpu=0; gen_hpu<HPU_NB; gen_hpu=gen_hpu+1) begin : gen_mem_hpu
      for (genvar gen_pc=0; gen_pc<ETH_PC; gen_pc=gen_pc+1) begin : gen_mem_pc
        axi4_mem #(
          .DATA_WIDTH      (AXI4_DATA_W                     ),
          .ADDR_WIDTH      (MEM_SIM_SIZE                    ),
          .ID_WIDTH        (AXI4_ID_W                       ),
          .WR_CMD_BUF_DEPTH(MEM_WR_CMD_BUF_DEPTH            ),
          .RD_CMD_BUF_DEPTH(MEM_RD_CMD_BUF_DEPTH            ),
          .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY+ gen_pc * 50),
          .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY             ),
          .USE_WR_RANDOM   (MEM_USE_WR_RANDOM               ),
          .USE_RD_RANDOM   (MEM_USE_RD_RANDOM               )
        ) axi4_mem_ct (
          .clk           (clk_mhdma                         ),
          .rst           (~s_rstn_mhdma                     ),
          .s_axi4_awid   (axi4_ct_awid[gen_hpu][gen_pc]     ),
          .s_axi4_awaddr (axi4_ct_awaddr[gen_hpu][gen_pc][MEM_SIM_SIZE-1:0]),
          .s_axi4_awlen  (axi4_ct_awlen[gen_hpu][gen_pc]    ),
          .s_axi4_awsize (axi4_ct_awsize[gen_hpu][gen_pc]   ),
          .s_axi4_awburst(axi4_ct_awburst[gen_hpu][gen_pc]  ),
          .s_axi4_awlock  (/* UNUSED */),
          .s_axi4_awcache (/* UNUSED */),
          .s_axi4_awprot  (/* UNUSED */),
          .s_axi4_awqos   (/* UNUSED */),
          .s_axi4_awregion(/* UNUSED */),
          .s_axi4_awvalid(axi4_ct_awvalid[gen_hpu][gen_pc]  ),
          .s_axi4_awready(axi4_ct_awready[gen_hpu][gen_pc]  ),
          .s_axi4_wdata  (axi4_ct_wdata[gen_hpu][gen_pc]    ),
          .s_axi4_wstrb  (axi4_ct_wstrb[gen_hpu][gen_pc]    ),
          .s_axi4_wlast  (axi4_ct_wlast[gen_hpu][gen_pc]    ),
          .s_axi4_wvalid (axi4_ct_wvalid[gen_hpu][gen_pc]   ),
          .s_axi4_wready (axi4_ct_wready[gen_hpu][gen_pc]   ),
          .s_axi4_bid    (axi4_ct_bid[gen_hpu][gen_pc]      ),
          .s_axi4_bresp  (axi4_ct_bresp[gen_hpu][gen_pc]    ),
          .s_axi4_bvalid (axi4_ct_bvalid[gen_hpu][gen_pc]   ),
          .s_axi4_bready (axi4_ct_bready[gen_hpu][gen_pc]   ),
          .s_axi4_arid   (axi4_ct_arid[gen_hpu][gen_pc]     ),
          .s_axi4_araddr (axi4_ct_araddr[gen_hpu][gen_pc][MEM_SIM_SIZE-1:0]),
          .s_axi4_arlen  (axi4_ct_arlen[gen_hpu][gen_pc]    ),
          .s_axi4_arsize (axi4_ct_arsize[gen_hpu][gen_pc]   ),
          .s_axi4_arburst(axi4_ct_arburst[gen_hpu][gen_pc]  ),
          .s_axi4_arlock  (/* UNUSED */),
          .s_axi4_arcache (/* UNUSED */),
          .s_axi4_arprot  (/* UNUSED */),
          .s_axi4_arqos   (/* UNUSED */),
          .s_axi4_arregion(/* UNUSED */),
          .s_axi4_arvalid(axi4_ct_arvalid[gen_hpu][gen_pc]  ),
          .s_axi4_arready(axi4_ct_arready[gen_hpu][gen_pc]  ),
          .s_axi4_rid    (axi4_ct_rid[gen_hpu][gen_pc]      ),
          .s_axi4_rdata  (axi4_ct_rdata[gen_hpu][gen_pc]    ),
          .s_axi4_rresp  (axi4_ct_rresp[gen_hpu][gen_pc]    ),
          .s_axi4_rlast  (axi4_ct_rlast[gen_hpu][gen_pc]    ),
          .s_axi4_rvalid (axi4_ct_rvalid[gen_hpu][gen_pc]   ),
          .s_axi4_rready (axi4_ct_rready[gen_hpu][gen_pc]   )
        );

        // Each generated instance initializes its own memory
        initial begin
          for (int k = 0; k < 2**MEM_SIM_SIZE; k++) begin
            logic [255:0] value;
            value = '0;
            for (int j = 0; j < 4; j++) begin
              logic [63:0] w;
              w[63:32] = $urandom();
              w[31:0]  = $urandom();
              value |= (w << (j*64));
            end
            axi4_mem_ct.axi4_ram_ct_wr.mem[k] = value;
          end
        end

      end
    end
  endgenerate

  int random_iter;
  // Signals --------------------------------------------------------------------------------------
  logic [REG_DATA_W-1:0] read_data;

  // HPU-A and HPU-B node id will be set randomly and mandatorily different
  logic [HPU_ID_W-1:0] random_hpu_a;
  logic [HPU_ID_W-1:0] random_hpu_b;

  // IOP related signals
  logic [  IOP_ID_W-1:0] iop_id;
  logic [SRC_ADDR_W-1:0] iop_src_addr;
  logic [DST_ADDR_W-1:0] iop_dst_addr;

  // for checking memories from several read requests at once
  logic [SRC_ADDR_W-1:0] rr_src_addr_ref_q[$];
  logic [DST_ADDR_W-1:0] rr_dst_addr_ref_q[$];
  logic [SRC_ADDR_W-1:0] exp_src_addr;
  logic [DST_ADDR_W-1:0] exp_dst_addr;

  // for checking
  logic [  REG_DATA_W-1:0] notify_req_id_exp;
  logic [  REG_DATA_W-1:0] notify_req_addr_exp;
  logic [2*REG_DATA_W-1:0] notify_payload_ref_q[$];

  logic [  REG_DATA_W-1:0] rr_req_id_exp;
  logic [  REG_DATA_W-1:0] rr_addr_exp;
  logic [2*REG_DATA_W-1:0] rr_payload_ref_q[$];

  // Randomized flag and mode, checked at each iteration
  logic [FLAG_W-1:0] req_flag;
  logic [MODE_W-1:0] req_mode;

  logic [REG_DATA_W-1:0] stat_errors;

  logic [REG_DATA_W-1:0] regf_start_addr_ofs;

  logic [REG_DATA_W-1:0] stat_notify;
  logic [REG_DATA_W-1:0] stat_notify_ack;
  logic [REG_DATA_W-1:0] stat_notify_retry;
  logic [REG_DATA_W-1:0] stat_read_req_retry;
  logic [REG_DATA_W-1:0] stat_notify_timeout;
  logic [REG_DATA_W-1:0] stat_fsm_value;
  logic [REG_DATA_W-1:0] stat_t_notify_to_ack;
  logic [REG_DATA_W-1:0] stat_t_rr_to_ce_received;
  logic [REG_DATA_W-1:0] stat_t_ce_first_to_last_pkt;
  logic [REG_DATA_W-1:0] stat_cnt_nack_received;
  logic [REG_DATA_W-1:0] stat_cnt_notify_received;
  logic [REG_DATA_W-1:0] stat_cnt_read_req_received;
  logic [REG_DATA_W-1:0] stat_cnt_ce_received;

  logic             [REG_DATA_W-1:0]   stat_nb_read_to_hbm;
  logic [ETH_PC-1:0][REG_DATA_W-1:0]   stat_nb_words_received_pc;
  logic [ETH_PC-1:0][REG_DATA_W-1:0]   stat_t_rr_wait_words_pc;
  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] stat_rr_phy_addr;
  logic             [REG_DATA_W-1:0]   stat_nb_ce_words_received;
  logic             [REG_DATA_W-1:0]   stat_nb_write_complete;
  // new stats
  logic             [REG_DATA_W-1:0]   stat_nb_notify_sent;
  logic             [REG_DATA_W-1:0]   stat_nb_ce_sent;
  logic             [REG_DATA_W-1:0]   stat_nb_notify_ack_sent;
  logic             [REG_DATA_W-1:0]   stat_nb_read_req_sent;
  logic             [REG_DATA_W-1:0]   stat_t_notify_to_ack_max;
  logic             [REG_DATA_W-1:0]   stat_t_rr_to_ce_received_max;
  logic             [REG_DATA_W-1:0]   stat_t_hbm_write_latency;
  logic             [REG_DATA_W-1:0]   stat_t_hbm_write_latency_max;
  logic             [REG_DATA_W-1:0]   stat_t_hbm_write_latency_min;
  logic             [REG_DATA_W-1:0]   stat_t_notify_to_ack_min;
  logic             [REG_DATA_W-1:0]   stat_t_rr_to_ce_received_min;
  logic             [REG_DATA_W-1:0]   stat_nb_decoder_dropped;

  int arbitrary_notify_nb;
  int arbitrary_read_req_nb;

  // scenario -------------------------------------------------------------------------------------
  int scenario_id;
  initial begin
    gen_maxil_if[0].maxil_if.init();
    gen_maxil_if[1].maxil_if.init();

    reset_registers = 'h0;
    tx_loop         = 'h0;
    rx_to_tx        = 'h0;
    regf_start_addr_ofs = 'h0;
    repeat(20) @(posedge clk_control);

    random_iter           = $urandom_range(32, 2);
    arbitrary_notify_nb   = XPM_MIN_FIFO_DEPTH; // if we have a full fifo on fifo_nrx_regf, we will lose notifies
    arbitrary_read_req_nb = XPM_MIN_FIFO_DEPTH;

    $display("\n\n"); // separating from xpm fifo information

    $display("\n==================================================================================================");
    $display("  Initial register check and definition");
    $display("==================================================================================================");
    init_config();

    // Defining MAC addresses for both instances of HPU -------------------------------------------
    write_mac_addresses();

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Default behavior, repeated for %0d times", scenario_id, random_iter);
    $display("  > B Notifies to A that a ciphertext is ready");
    $display("  > A then reads this ciphertext and send it to B");
    $display("==================================================================================================");

    for (int i = 0; i < random_iter; i++) begin
      iop_id       = $urandom();
      iop_src_addr = $urandom_range(0, MEM_MAX_VALUE-1);
      iop_dst_addr = $urandom_range(0, MEM_MAX_VALUE-1);
      req_flag     = $urandom();
      req_mode     = $urandom();

      repeat(2) @(posedge clk_control);
      notify_request(random_hpu_b, random_hpu_a, iop_id, iop_src_addr, req_flag, req_mode);

      // if a Notify is received by HPU A we should be able to confirm it by reading in the regf
      notify_req_id_exp   = {iop_id, REQ_ID_NOTIFY, random_hpu_b, req_mode, req_flag, 8'h0};
      notify_req_addr_exp = {16'b0, iop_src_addr};

      wait (interrupt_notify[0] == 1'b1);

      gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_NOTIFY_REQ_ADDR_OFS, read_data);
      assert (read_data == notify_req_addr_exp) else begin
        $display("%t > [ERROR]: Notify REQ_ADDR incorrect %x != exp %x", $time, read_data, notify_req_addr_exp);
        error_notify_payload = 1'b1;
      end

      gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_NOTIFY_REQ_ID_OFS, read_data);
      assert (read_data == notify_req_id_exp) else begin
        $display("%t > [ERROR]: Notify REQ_ID incorrect %x != exp %x", $time, read_data, notify_req_id_exp);
        $display("%t > [ERROR]: iop_id     %x != %x ", $time, iop_id,       read_data[31:24]);
        $display("%t > [ERROR]: hpu_id     %x != %x ", $time, random_hpu_b, read_data[19:16]);
        $display("%t > [ERROR]: mode       %x != %x ", $time, req_mode,     read_data[15:14]);
        $display("%t > [ERROR]: flag       %x != %x ", $time, req_flag,     read_data[13:8]);
        error_notify_payload = 1'b1;
      end

      repeat(2) @(posedge clk_control);

      // Sending a read request from HPU-A to HPU-B -------------------------------------------------
      read_request(random_hpu_b, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

      wait (interrupt_read_request[0] == 1'b1);

      rr_addr_exp   = {iop_dst_addr, iop_src_addr};
      rr_req_id_exp = {iop_id, REQ_ID_EMISSION, random_hpu_b, req_mode, req_flag, 8'h0};

      gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_READ_REQUEST_OFS, read_data);
      assert (read_data == rr_addr_exp) else begin
        $display("%t > [ERROR]: RR REQ_ADDR incorrect %x != exp %x", $time, read_data, rr_addr_exp);
        error_rr_payload = 1'b1;
      end

      gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, read_data);
      assert (read_data == rr_req_id_exp) else begin
        $display("%t > [ERROR]: RR REQ_ID incorrect %x != exp %x", $time, read_data, rr_req_id_exp);
        $display("%t > [ERROR]: iop_id     %x != %x ", $time, iop_id,       read_data[31:24]);
        $display("%t > [ERROR]: hpu_id     %x != %x ", $time, random_hpu_b, read_data[19:16]);
        $display("%t > [ERROR]: mode       %x != %x ", $time, req_mode,     read_data[15:14]);
        $display("%t > [ERROR]: flag       %x != %x ", $time, req_flag,     read_data[13:8]);
        error_rr_payload = 1'b1;
      end

      gen_check_mem.check_memories(iop_src_addr, iop_dst_addr);
    end

    scenario_id = scenario_id + 1;

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Sending a Pile of %0d Notifies, done %0d times from A to B and inversely", scenario_id, arbitrary_notify_nb, LOOP_NOTIFY);
    $display("==================================================================================================");
    for (int k = 0; k < LOOP_NOTIFY; k++) begin
      for (int i = 0; i < arbitrary_notify_nb; i++) begin
        iop_id       = $urandom();
        iop_src_addr = $urandom_range(0, MEM_MAX_VALUE-1);
        iop_dst_addr = $urandom_range(0, MEM_MAX_VALUE-1);
        req_flag     = $urandom();
        req_mode     = $urandom();

        repeat(10) @(posedge clk_control);
        // Sending a NOTIFY from HPU-B to HPU-A -------------------------------------------------------
        notify_request(random_hpu_b, random_hpu_a, iop_id, iop_src_addr, req_flag, req_mode);

        // if a Notify is received by HPU A we should be able to confirm it by reading in the regf
        notify_payload_ref_q.push_front({iop_id, REQ_ID_NOTIFY, random_hpu_b, req_mode, req_flag, 8'h0, 16'b0, iop_src_addr});
      end

      $display("%t > INFO : All %0d Notify have been sent from B to A", $time, arbitrary_notify_nb);

      for (int i = 0; i < arbitrary_notify_nb; i++) begin

        // we must wait for interrupt to be raised before reading
        wait (interrupt_notify[0] == 1'b1);
        // Read ADDR first (no pop), then ID (pops the FIFO)
        gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_NOTIFY_REQ_ADDR_OFS, read_data);
        {notify_req_id_exp, notify_req_addr_exp} = notify_payload_ref_q.pop_back();

        assert (read_data == notify_req_addr_exp) else begin
          $display("%t > [ERROR]: Notify REQ_ADDR incorrect (received %x) =! (exp %x)", $time, read_data, notify_req_addr_exp);
          error_notify_payload = 1'b1;
        end

        gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_NOTIFY_REQ_ID_OFS, read_data);
        assert (read_data == notify_req_id_exp) else begin
          $display("%t > [ERROR]: Notify REQ_ID incorrect (received %x) =! (exp %x)", $time, read_data, notify_req_id_exp);
          error_notify_payload = 1'b1;
        end
      end

      @(posedge clk_control);
      if (interrupt_notify[0] == 1'b1) begin
        $display("%t > [ERROR]: Interrupt on HPU_A has not been lowered\n",$time);
        error_interrupt_notify = 1'b1;
      end

      for (int i = 0; i < arbitrary_notify_nb; i++) begin
        iop_id       = $urandom();
        iop_src_addr = $urandom_range(0, MEM_MAX_VALUE-1);
        iop_dst_addr = $urandom_range(0, MEM_MAX_VALUE-1);
        req_flag     = $urandom();
        req_mode     = $urandom();

        repeat(10) @(posedge clk_control);
        // Sending a NOTIFY from HPU-A to HPU-B -------------------------------------------------------
        notify_request(random_hpu_a, random_hpu_b, iop_id, iop_src_addr, req_flag, req_mode);

        // if a Notify is received by HPU B we should be able to confirm it by reading in the regf
        notify_payload_ref_q.push_front({iop_id, REQ_ID_NOTIFY, random_hpu_a, req_mode, req_flag, 8'h0});
      end

      $display("%t > INFO : All %0d Notify have been sent from A to B", $time, arbitrary_notify_nb);

      for (int i = 0; i < arbitrary_notify_nb; i++) begin

        // we must wait for interrupt to be raised before reading
        wait (interrupt_notify[1] == 1'b1);

        gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_NOTIFY_REQ_ID_OFS, read_data);
        notify_req_id_exp = notify_payload_ref_q.pop_back();
        assert (read_data == notify_req_id_exp) else begin
          $display("%t > [ERROR]: Notify REQ_ID incorrect %x != exp %x", $time, read_data, notify_req_id_exp);
          $display("%t > [ERROR]: iop_id     %x != %x ", $time, iop_id,       read_data[31:24]);
          $display("%t > [ERROR]: hpu_id     %x != %x ", $time, random_hpu_b, read_data[19:16]);
          $display("%t > [ERROR]: mode       %x != %x ", $time, req_mode,     read_data[15:14]);
          $display("%t > [ERROR]: flag       %x != %x ", $time, req_flag,     read_data[13:8]);
          error_notify_payload = 1'b1;
        end
      end
    end

    @(posedge clk_control);
    if (interrupt_notify[0] == 1'b1) begin
      $display("%t > [ERROR]: Interrupt on HPU_A has not been lowered\n",$time);
      error_interrupt_notify = 1'b1;
    end

    scenario_id = scenario_id + 1;

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Sending a Pile of %0d read requests, done %0d times from A to B", scenario_id, arbitrary_read_req_nb, LOOP_NOTIFY);
    $display("==================================================================================================");

    for (int i = 0; i < arbitrary_read_req_nb; i ++) begin
      iop_id       = $urandom();
      iop_src_addr = $urandom_range(0, MEM_MAX_VALUE-1);
      iop_dst_addr = $urandom_range(0, MEM_MAX_VALUE-1);
      req_flag     = $urandom();
      req_mode     = $urandom();
      read_request(random_hpu_b, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

      rr_payload_ref_q.push_front({iop_id, REQ_ID_EMISSION, random_hpu_b, req_mode, req_flag, 8'h0});
      rr_src_addr_ref_q.push_front(iop_src_addr);
      rr_dst_addr_ref_q.push_front(iop_dst_addr);

    end

    for (int i = 0; i < arbitrary_read_req_nb; i++) begin
      iop_id       = $urandom();
      iop_src_addr = $urandom_range(0, MEM_MAX_VALUE-1);
      iop_dst_addr = $urandom_range(0, MEM_MAX_VALUE-1);
      // we must wait for interrupt to be raised before reading
      wait (interrupt_read_request[0] == 1'b1);

      gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, read_data);
      rr_req_id_exp = rr_payload_ref_q.pop_back();
      assert (read_data == rr_req_id_exp) else begin
        $display("%t > [ERROR]: Read request REQ_ID incorrect %x != exp %x", $time, read_data, rr_req_id_exp);
        $display("%t > [ERROR]: iop_id     %x != %x ", $time, rr_req_id_exp[31:24], read_data[31:24]);
        $display("%t > [ERROR]: hpu_id     %x != %x ", $time, rr_req_id_exp[19:16], read_data[19:16]);
        $display("%t > [ERROR]: mode       %x != %x ", $time, rr_req_id_exp[15:14], read_data[15:14]);
        $display("%t > [ERROR]: flag       %x != %x ", $time, rr_req_id_exp[13:8], read_data[13:8]);
        error_notify_payload = 1'b1;
      end

      exp_src_addr = rr_src_addr_ref_q.pop_back();
      exp_dst_addr = rr_dst_addr_ref_q.pop_back();

      gen_check_mem.check_memories(exp_src_addr, exp_dst_addr);
    end

    $display("%t > INFO : All %0d read request have been sent  and memory models checked\n",$time, arbitrary_read_req_nb);

    $display("\n==================================================================================================");
    $display("  Reading registers");
    $display("==================================================================================================");

    gen_maxil_if[0].maxil_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors);

    display_errors(stat_errors);

    if (stat_errors!=0) begin
      $display("[ERROR]: Error register is not null! %b", stat_errors);
      error_register = 1'b1;
    end

    gen_maxil_if[0].maxil_if.read_trans(MHDMA_SYSTEM_FSM_VALUE_OFS, stat_fsm_value);
    $display(" stat_fsm_value                : 0x%08h", stat_fsm_value);

    $display("\n ----------------- HPU_A -------------------------------------");
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, stat_notify);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS, stat_notify_ack);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, stat_notify_retry);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_retry);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS, stat_notify_timeout);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_OFS, stat_t_notify_to_ack);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_OFS, stat_t_rr_to_ce_received);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_CE_FIRST_TO_LAST_PKT_OFS, stat_t_ce_first_to_last_pkt);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS, stat_cnt_nack_received);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_NOTIFY_RECEIVED_OFS, stat_cnt_notify_received);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS, stat_cnt_read_req_received);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_CE_RECEIVED_OFS, stat_cnt_ce_received);
    $display(" stat_notify                   : %0d", stat_notify);
    $display(" stat_notify_ack               : %0d", stat_notify_ack);
    $display(" stat_notify_retry             : %0d", stat_notify_retry);
    $display(" stat_read_req_retry           : %0d", stat_read_req_retry);
    $display(" stat_notify_timeout           : %0d", stat_notify_timeout);
    $display(" stat_t_notify_to_ack          : %0d", stat_t_notify_to_ack);
    $display(" stat_t_rr_to_ce_received      : %0d", stat_t_rr_to_ce_received);
    $display(" stat_t_ce_first_to_last_pkt   : %0d", stat_t_ce_first_to_last_pkt);
    $display(" stat_cnt_nack_received        : %0d", stat_cnt_nack_received);
    $display(" stat_cnt_notify_received      : %0d", stat_cnt_notify_received);
    $display(" stat_cnt_read_req_received    : %0d", stat_cnt_read_req_received);
    $display(" stat_cnt_ce_received          : %0d", stat_cnt_ce_received);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_TO_HBM_OFS, stat_nb_read_to_hbm);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC0_OFS, stat_nb_words_received_pc[0]);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC1_OFS, stat_nb_words_received_pc[1]);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_RR_WAIT_WORDS_PC_PC0_OFS, stat_t_rr_wait_words_pc[0]);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_RR_WAIT_WORDS_PC_PC1_OFS, stat_t_rr_wait_words_pc[1]);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC0_LSB_OFS, stat_rr_phy_addr[0][REG_DATA_W-1:0]);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC0_MSB_OFS, stat_rr_phy_addr[0][2*REG_DATA_W-1:REG_DATA_W]);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC1_LSB_OFS, stat_rr_phy_addr[1][REG_DATA_W-1:0]);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC1_MSB_OFS, stat_rr_phy_addr[1][2*REG_DATA_W-1:REG_DATA_W]);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_CE_WORDS_RECEIVED_OFS, stat_nb_ce_words_received);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_CNT_NB_WRITE_COMPLETE_OFS, stat_nb_write_complete);
    $display(" stat_nb_read_to_hbm           : %0d", stat_nb_read_to_hbm);
    $display(" stat_nb_words_received_pc [0] : %0d", stat_nb_words_received_pc[0]);
    $display(" stat_nb_words_received_pc [1] : %0d", stat_nb_words_received_pc[1]);
    $display(" stat_t_rr_wait_words_pc   [0] : %0d", stat_t_rr_wait_words_pc[0]);
    $display(" stat_t_rr_wait_words_pc   [1] : %0d", stat_t_rr_wait_words_pc[1]);
    $display(" stat_rr_phy_addr          [0] : %0d", stat_rr_phy_addr[0]);
    $display(" stat_rr_phy_addr          [1] : %0d", stat_rr_phy_addr[1]);
    $display(" stat_nb_ce_words_received     : %0d", stat_nb_ce_words_received);
    $display(" stat_nb_write_complete        : %0d", stat_nb_write_complete);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_NOTIFY_SENT_OFS, stat_nb_notify_sent);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_CE_SENT_OFS, stat_nb_ce_sent);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_NOTIFY_ACK_SENT_OFS, stat_nb_notify_ack_sent);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_REQ_SENT_OFS, stat_nb_read_req_sent);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_HBM_WRITE_LATENCY_OFS, stat_t_hbm_write_latency);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_HBM_WRITE_LATENCY_MAX_OFS, stat_t_hbm_write_latency_max);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_HBM_WRITE_LATENCY_MIN_OFS, stat_t_hbm_write_latency_min);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_MIN_OFS, stat_t_notify_to_ack_min);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_MAX_OFS, stat_t_notify_to_ack_max);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_MIN_OFS, stat_t_rr_to_ce_received_min);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_MAX_OFS, stat_t_rr_to_ce_received_max);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_DECODER_DROPPED_OFS, stat_nb_decoder_dropped);
    $display(" stat_nb_notify_sent           : %0d", stat_nb_notify_sent);
    $display(" stat_nb_ce_sent              : %0d", stat_nb_ce_sent);
    $display(" stat_nb_notify_ack_sent      : %0d", stat_nb_notify_ack_sent);
    $display(" stat_nb_read_req_sent        : %0d", stat_nb_read_req_sent);
    $display(" stat_t_hbm_write_latency     : %0d", stat_t_hbm_write_latency);
    $display(" stat_t_hbm_write_latency_max : %0d", stat_t_hbm_write_latency_max);
    $display(" stat_t_hbm_write_latency_min : %0d", stat_t_hbm_write_latency_min);
    $display(" stat_t_notify_to_ack_min     : %0d", stat_t_notify_to_ack_min);
    $display(" stat_t_notify_to_ack_max     : %0d", stat_t_notify_to_ack_max);
    $display(" stat_t_rr_to_ce_received_min : %0d", stat_t_rr_to_ce_received_min);
    $display(" stat_t_rr_to_ce_received_max : %0d", stat_t_rr_to_ce_received_max);
    $display(" stat_nb_decoder_dropped      : %0d", stat_nb_decoder_dropped);

    // checking that some stats registers are not zeors & correctly accessed
    assert (stat_t_notify_to_ack_min != 0 && stat_t_notify_to_ack_min != {REG_DATA_W{1'b1}}) else begin
      $display("%t > [ERROR] HPU_A: stat_t_notify_to_ack_min is uninitialized (%0d)", $time, stat_t_notify_to_ack_min);
      error_register = 1'b1;
    end
    assert (stat_t_notify_to_ack_max != 0) else begin
      $display("%t > [ERROR] HPU_A: stat_t_notify_to_ack_max is zero", $time);
      error_register = 1'b1;
    end
    assert (stat_t_notify_to_ack_min <= stat_t_notify_to_ack_max) else begin
      $display("%t > [ERROR] HPU_A: stat_t_notify_to_ack_min (%0d) > max (%0d)", $time, stat_t_notify_to_ack_min, stat_t_notify_to_ack_max);
      error_register = 1'b1;
    end
    assert (stat_t_rr_to_ce_received_min != 0 && stat_t_rr_to_ce_received_min != {REG_DATA_W{1'b1}}) else begin
      $display("%t > [ERROR] HPU_A: stat_t_rr_to_ce_received_min is uninitialized (%0d)", $time, stat_t_rr_to_ce_received_min);
      error_register = 1'b1;
    end
    assert (stat_t_rr_to_ce_received_max != 0) else begin
      $display("%t > [ERROR] HPU_A: stat_t_rr_to_ce_received_max is zero", $time);
      error_register = 1'b1;
    end
    assert (stat_t_rr_to_ce_received_min <= stat_t_rr_to_ce_received_max) else begin
      $display("%t > [ERROR] HPU_A: stat_t_rr_to_ce_received_min (%0d) > max (%0d)", $time, stat_t_rr_to_ce_received_min, stat_t_rr_to_ce_received_max);
      error_register = 1'b1;
    end
    assert (stat_t_hbm_write_latency != 0) else begin
      $display("%t > [ERROR] HPU_A: stat_t_hbm_write_latency is zero", $time);
      error_register = 1'b1;
    end
    assert (stat_t_hbm_write_latency_max != 0) else begin
      $display("%t > [ERROR] HPU_A: stat_t_hbm_write_latency_max is zero", $time);
      error_register = 1'b1;
    end
    assert (stat_t_hbm_write_latency_min != 0 && stat_t_hbm_write_latency_min != {REG_DATA_W{1'b1}}) else begin
      $display("%t > [ERROR] HPU_A: stat_t_hbm_write_latency_min is uninitialized (%0d)", $time, stat_t_hbm_write_latency_min);
      error_register = 1'b1;
    end
    assert (stat_t_hbm_write_latency_min <= stat_t_hbm_write_latency_max) else begin
      $display("%t > [ERROR] HPU_A: stat_t_hbm_write_latency_min (%0d) > max (%0d)", $time, stat_t_hbm_write_latency_min, stat_t_hbm_write_latency_max);
      error_register = 1'b1;
    end
    assert (stat_nb_decoder_dropped == 0) else begin
      $display("%t > [ERROR] HPU_A: stat_nb_decoder_dropped is non-zero (%0d) - no bad packets expected", $time, stat_nb_decoder_dropped);
      error_register = 1'b1;
    end

    $display(" ----------------- HPU_B -------------------------------------");
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, stat_notify);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS, stat_notify_ack);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, stat_notify_retry);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_retry);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS, stat_notify_timeout);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_OFS, stat_t_notify_to_ack);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_OFS, stat_t_rr_to_ce_received);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_CE_FIRST_TO_LAST_PKT_OFS, stat_t_ce_first_to_last_pkt);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS, stat_cnt_nack_received);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_NOTIFY_RECEIVED_OFS, stat_cnt_notify_received);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS, stat_cnt_read_req_received);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_CE_RECEIVED_OFS, stat_cnt_ce_received);
    $display(" stat_notify                   : %0d", stat_notify);
    $display(" stat_notify_ack               : %0d", stat_notify_ack);
    $display(" stat_notify_retry             : %0d", stat_notify_retry);
    $display(" stat_read_req_retry           : %0d", stat_read_req_retry);
    $display(" stat_notify_timeout           : %0d", stat_notify_timeout);
    $display(" stat_t_notify_to_ack          : %0d", stat_t_notify_to_ack);
    $display(" stat_t_rr_to_ce_received      : %0d", stat_t_rr_to_ce_received);
    $display(" stat_t_ce_first_to_last_pkt   : %0d", stat_t_ce_first_to_last_pkt);
    $display(" stat_cnt_nack_received        : %0d", stat_cnt_nack_received);
    $display(" stat_cnt_notify_received      : %0d", stat_cnt_notify_received);
    $display(" stat_cnt_read_req_received    : %0d", stat_cnt_read_req_received);
    $display(" stat_cnt_ce_received          : %0d", stat_cnt_ce_received);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_TO_HBM_OFS, stat_nb_read_to_hbm);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC0_OFS, stat_nb_words_received_pc[0]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC1_OFS, stat_nb_words_received_pc[1]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_RR_WAIT_WORDS_PC_PC0_OFS, stat_t_rr_wait_words_pc[0]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_RR_WAIT_WORDS_PC_PC1_OFS, stat_t_rr_wait_words_pc[1]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC0_LSB_OFS, stat_rr_phy_addr[0][REG_DATA_W-1:0]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC0_MSB_OFS, stat_rr_phy_addr[0][2*REG_DATA_W-1:REG_DATA_W]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC1_LSB_OFS, stat_rr_phy_addr[1][REG_DATA_W-1:0]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC1_MSB_OFS, stat_rr_phy_addr[1][2*REG_DATA_W-1:REG_DATA_W]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_CE_WORDS_RECEIVED_OFS, stat_nb_ce_words_received);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_CNT_NB_WRITE_COMPLETE_OFS, stat_nb_write_complete);
    $display(" stat_nb_read_to_hbm           : %0d", stat_nb_read_to_hbm);
    $display(" stat_nb_words_received_pc [0] : %0d", stat_nb_words_received_pc[0]);
    $display(" stat_nb_words_received_pc [1] : %0d", stat_nb_words_received_pc[1]);
    $display(" stat_t_rr_wait_words_pc   [0] : %0d", stat_t_rr_wait_words_pc[0]);
    $display(" stat_t_rr_wait_words_pc   [1] : %0d", stat_t_rr_wait_words_pc[1]);
    $display(" stat_rr_phy_addr          [0] : %0d", stat_rr_phy_addr[0]);
    $display(" stat_rr_phy_addr          [1] : %0d", stat_rr_phy_addr[1]);
    $display(" stat_nb_ce_words_received     : %0d", stat_nb_ce_words_received);
    $display(" stat_nb_write_complete        : %0d", stat_nb_write_complete);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_NOTIFY_SENT_OFS, stat_nb_notify_sent);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_CE_SENT_OFS, stat_nb_ce_sent);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_NOTIFY_ACK_SENT_OFS, stat_nb_notify_ack_sent);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_REQ_SENT_OFS, stat_nb_read_req_sent);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_HBM_WRITE_LATENCY_OFS, stat_t_hbm_write_latency);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_HBM_WRITE_LATENCY_MAX_OFS, stat_t_hbm_write_latency_max);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_HBM_WRITE_LATENCY_MIN_OFS, stat_t_hbm_write_latency_min);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_MIN_OFS, stat_t_notify_to_ack_min);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_MAX_OFS, stat_t_notify_to_ack_max);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_MIN_OFS, stat_t_rr_to_ce_received_min);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_MAX_OFS, stat_t_rr_to_ce_received_max);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_DECODER_DROPPED_OFS, stat_nb_decoder_dropped);
    $display(" stat_nb_notify_sent           : %0d", stat_nb_notify_sent);
    $display(" stat_nb_ce_sent              : %0d", stat_nb_ce_sent);
    $display(" stat_nb_notify_ack_sent      : %0d", stat_nb_notify_ack_sent);
    $display(" stat_nb_read_req_sent        : %0d", stat_nb_read_req_sent);
    $display(" stat_t_hbm_write_latency     : %0d", stat_t_hbm_write_latency);
    $display(" stat_t_hbm_write_latency_max : %0d", stat_t_hbm_write_latency_max);
    $display(" stat_t_hbm_write_latency_min : %0d", stat_t_hbm_write_latency_min);
    $display(" stat_t_notify_to_ack_min     : %0d", stat_t_notify_to_ack_min);
    $display(" stat_t_notify_to_ack_max     : %0d", stat_t_notify_to_ack_max);
    $display(" stat_t_rr_to_ce_received_min : %0d", stat_t_rr_to_ce_received_min);
    $display(" stat_t_rr_to_ce_received_max : %0d", stat_t_rr_to_ce_received_max);
    $display(" stat_nb_decoder_dropped      : %0d", stat_nb_decoder_dropped);

    // checking that some stats registers are not zeors & correctly accessed
    assert (stat_t_notify_to_ack_min != 0 && stat_t_notify_to_ack_min != {REG_DATA_W{1'b1}}) else begin
      $display("%t > [ERROR] HPU_B: stat_t_notify_to_ack_min is uninitialized (%0d)", $time, stat_t_notify_to_ack_min);
      error_register = 1'b1;
    end
    assert (stat_t_notify_to_ack_max != 0) else begin
      $display("%t > [ERROR] HPU_B: stat_t_notify_to_ack_max is zero", $time);
      error_register = 1'b1;
    end
    assert (stat_t_notify_to_ack_min <= stat_t_notify_to_ack_max) else begin
      $display("%t > [ERROR] HPU_B: stat_t_notify_to_ack_min (%0d) > max (%0d)", $time, stat_t_notify_to_ack_min, stat_t_notify_to_ack_max);
      error_register = 1'b1;
    end
    assert (stat_nb_decoder_dropped == 0) else begin
      $display("%t > [ERROR] HPU_B: stat_nb_decoder_dropped is non-zero (%0d)", $time, stat_nb_decoder_dropped);
      error_register = 1'b1;
    end
    $display(" ------------------------------------------------------------- \n");

    $display("%t > INFO: End simulation",$time);
    repeat(20) @(posedge clk_control);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --
  logic [REG_DATA_W-1:00] rdata;

  task automatic init_config;
    begin
    // Reading system REGISTERS -------------------------------------------------------------------
      gen_maxil_if[0].maxil_if.read_trans(MHDMA_SYSTEM_LANE_OFS, rdata);
      assert (rdata == 'h0) else begin
        $display("%t > ERROR:register SYSTEM_LINE_OFS not correctly read %h",$time, rdata);
        error_register_read = 1'b1;
      end

    // ASSIGN REGISTERS & CHECK -------------------------------------------------------------------
    line_rate     = 8'hAB;  // arbitrary: in reality should be 0
    line_loopback = 3'b100; // 3 near end pcs loopback
    line_select   = 2'b10;  // 2nd line selected
    debug_flag    = 1'b0;
    @(posedge clk_control);

    gen_maxil_if[0].maxil_if.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);
    gen_maxil_if[1].maxil_if.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);

    rst_rx_datapath = 4'b0100;
    rst_tx_datapath = 4'b1011;
    rst_all         = 4'b0101;
    @(posedge clk_control);

    gen_maxil_if[0].maxil_if.write_trans(MHDMA_RESET_DATAPATH_OFS, reset_parameter);
    gen_maxil_if[1].maxil_if.write_trans(MHDMA_RESET_DATAPATH_OFS, reset_parameter);

    assert ((gt_line_rate[0] == line_rate) && (gt_line_rate[1] == line_rate)) else begin
      $display("[ERROR] line_rate has unexpected value %x %x %x",gt_line_rate[0], gt_line_rate[1], line_rate);
      error_register_read = 1;
    end
    assert ((gt_loopback[0] ==line_loopback) && (gt_loopback[1] == line_loopback)) else begin
      $display("[ERROR] gt_loopback has unexpected value");
      error_register_read = 1;
    end
    assert ((gen_multi_hpu_dma[0].multi_hpu_dma.line_sel == line_select) && (gen_multi_hpu_dma[1].multi_hpu_dma.line_sel == line_select)) else begin
      $display("[ERROR] line_sel has unexpected value");
      error_register_read = 1;
    end

    for (int i = 0; i<2; i++) begin
      assert ((gt_reset_rx_datapath[i] == rst_rx_datapath) && (gt_reset_tx_datapath[i] == rst_tx_datapath) && (gt_reset_all[i] == rst_all)) else begin
        $display("%t >    ERROR: reset configuration has not been applied correctly",$time);
        error_register_read = 1'b1;
      end
    end

    // read reset register ------------------------------------------------------------------------
    // fake stimulation
    for (int i = 0; i<2; i++) begin
      gt_rx_reset_done[i]= 4'b1111;
      gt_tx_reset_done[i]= 4'b1111;
    end
    @(posedge clk_control);

    gen_maxil_if[0].maxil_if.read_trans(MHDMA_RESET_MONITOR_OFS, reset_monitor[0]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_RESET_MONITOR_OFS, reset_monitor[1]);

    assert ((reset_monitor[0][3:0] != gt_tx_reset_done) | (reset_monitor[0][7:4] != gt_rx_reset_done)) else begin
      $display("[ERROR] reset monitor has not been read correctly in HPU A");
      error_register_read = 1'b1;
    end
    assert ((reset_monitor[1][3:0] != gt_tx_reset_done) | (reset_monitor[1][7:4] != gt_rx_reset_done)) else begin
      $display("[ERROR] reset monitor has not been read correctly in HPU B");
      error_register_read = 1'b1;
    end

    // Setting timeout size to both HPUs ----------------------------------------------------------
    // keeping default value
    gen_maxil_if[0].maxil_if.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_LSB_OFS, 'hF);
    gen_maxil_if[0].maxil_if.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_MSB_OFS, 'h0);
    gen_maxil_if[0].maxil_if.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_LSB_OFS, 'hA);
    gen_maxil_if[0].maxil_if.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_MSB_OFS, 'h0);

    gen_maxil_if[1].maxil_if.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_LSB_OFS, 'hF);
    gen_maxil_if[1].maxil_if.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_MSB_OFS, 'h0);
    gen_maxil_if[1].maxil_if.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_LSB_OFS, 'hA);
    gen_maxil_if[1].maxil_if.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_MSB_OFS, 'h0);

    // Setting up credible values -------------------------------------------------------------
    // no loopback, no reset, not in debug & lane0 selected
    line_rate     = 8'h0;
    line_loopback = 3'b000;
    line_select   = 2'b00;
    debug_flag    = 1'b0;
    rst_rx_datapath = 4'b0000;
    rst_tx_datapath = 4'b0000;
    rst_all         = 4'b0000;
    @(posedge clk_control);

    $display("%t > INFO: Configuration successful\n",$time);
    end
  endtask

  /* Performs writes to according registers to define all possible MAC addresses
   *  - HPU-A and HPU-B are random and different at each runs
   *  - We have at most 8 HPUs: we will write them all
   */
  task automatic write_mac_addresses();
    logic [ MAC_ADDR_W-1:0] mac_addr;
    logic [   HPU_ID_W-1:0] hpu_id;
    logic                   hpu_current;
    logic [REG_DATA_W-1:00] register_mac_addr_a;
    logic [REG_DATA_W-1:00] register_mac_addr_b;
    begin
      random_hpu_a = $urandom_range(7, 0);

      // let's avoid saying that we are the same HPU
      do begin
        random_hpu_b = $urandom_range(7, 0);
      end while (random_hpu_b == random_hpu_a);

      $display("┌------------------------┐");
      $display("| For this run....       |");
      $display("| ---------------------- |");
      $display("| HPU_A:id=%d            |", random_hpu_a);
      $display("| HPU_B:id=%d            |", random_hpu_b);
      $display("| ---------------------- |");
      for (int i = 0 ; i < 8 ; i++ ) begin
        mac_addr = $urandom();
        hpu_id = i;

        if(i == random_hpu_a) begin
          register_mac_addr_a = {1'b1, 3'b000, hpu_id, mac_addr};
        end else begin
          register_mac_addr_a = {1'b0, 3'b000, hpu_id, mac_addr};
        end

        if(i == random_hpu_b) begin
          register_mac_addr_b = {1'b1, 3'b000, hpu_id, mac_addr};
        end else begin
          register_mac_addr_b = {1'b0, 3'b000, hpu_id, mac_addr};
        end

        $display("| HPU_ID=%0d :: MAC=%6x |", i, mac_addr);
        gen_maxil_if[0].maxil_if.write_trans(MHDMA_SYSTEM_HPU_ID_0_OFS+(4*i), register_mac_addr_a);
        gen_maxil_if[1].maxil_if.write_trans(MHDMA_SYSTEM_HPU_ID_0_OFS+(4*i), register_mac_addr_b);
      end
      $display("└------------------------┘");

    end
  endtask

  /* Performs a Read request from HPU A to HPU B
    - Since HPU A and HPU B are the same no need to be able to be able to send from both
    - There is two registers to write to send a read request */
  task automatic read_request(
    input logic [  HPU_ID_W-1:0] node_id,
    input logic [  IOP_ID_W-1:0] iop_id,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dest_addr,
    input logic [    FLAG_W-1:0] req_flag,
    input logic [    MODE_W-1:0] req_mode
  );
    logic [REG_DATA_W-1:0] read_req_id;
    logic [REG_DATA_W-1:0] read_req_addr;
    begin
      // see package
      read_req_addr = {dest_addr, src_addr};
      read_req_id = {iop_id, REQ_ID_READ, node_id, req_mode, req_flag, 8'h0};

      gen_maxil_if[0].maxil_if.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      gen_maxil_if[0].maxil_if.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
      // there is as well the hbm pc offsets to write from RPU pov but in simulation we let it set to 0
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
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [    FLAG_W-1:0] req_flag,
    input logic [    MODE_W-1:0] req_mode
  );
    logic [REG_DATA_W-1:0] read_req_id;
    logic [REG_DATA_W-1:0] read_req_addr;
    begin

      read_req_addr = {16'b0, src_addr};
      read_req_id = {iop_id, REQ_ID_NOTIFY, dst_node_id, req_mode, req_flag, 8'h0};

      if (src_node_id == random_hpu_a) begin
        gen_maxil_if[0].maxil_if.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
        gen_maxil_if[0].maxil_if.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
      end else if (src_node_id == random_hpu_b) begin
        gen_maxil_if[1].maxil_if.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
        gen_maxil_if[1].maxil_if.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
      end else begin
        $display("[ERROR] you are trying to send a Notify request from an HPU non instantiated");
        error_tb_notify = 1'b1;
      end

    end
  endtask

// ============================================================================================== --
// Checker
// ============================================================================================== --
// NOTE: VCS cannot dynamically index generate arrays in cross-module references.
// This does not work for ETH_PC != 2

  /* Checker
  * memory content should be the same between HPU_A and HPU_B for PC_0 and PC_1
  * assumption: we chose in this test to do read request from HPU A to B
  * anything can be in HPU B memory. on HPU A we have only the copied values of hpu B
  */
  // check_memories must live inside a generate so that PC1 hierarchical refs
  // are only elaborated when gen_mem_pc[1] actually exists.
  generate if (ETH_PC > 1) begin : gen_check_mem
    task automatic check_memories(
      input logic [SRC_ADDR_W-1:0] src_addr,
      input logic [DST_ADDR_W-1:0] dst_addr
    );
      int addr_hpu_0, addr_hpu_1;
      logic mismatch_found;
      logic [AXI4_DATA_W-1:0] val_hpu0, val_hpu1;
      int nb_words;

      mismatch_found = 1'b0;
      addr_hpu_0 = (regf_start_addr_ofs + (dst_addr * CT_MEM_BYTES)) / AXI4_DATA_BYTES;
      addr_hpu_1 = (regf_start_addr_ofs + (src_addr * CT_MEM_BYTES)) / AXI4_DATA_BYTES;
      $display("addr_hpu_0 = %x, addr_hpu_1 = %x", addr_hpu_0, addr_hpu_1);

      for (int pc = 0; pc < ETH_PC; pc++) begin
        nb_words = (pc == 0) ? AXI4_WORD_PER_PC0 : AXI4_WORD_PER_PC;
        for (int k = 0; k < nb_words; k++) begin
          if (pc == 0) begin
            val_hpu0 = gen_mem_hpu[0].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_0 + k];
            val_hpu1 = gen_mem_hpu[1].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_1 + k];
          end else begin
            val_hpu0 = gen_mem_hpu[0].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_0 + k];
            val_hpu1 = gen_mem_hpu[1].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_1 + k];
          end

          if ($isunknown(val_hpu0)) begin
            $display("ERROR: X/Z in HPU_0 at PC=%0d, offset=%0d, addr=%0d, val=%h", pc, k, addr_hpu_0 + k, val_hpu0);
            mismatch_found = 1;
            error_write_mismatch = 1'b1;
          end else if ($isunknown(val_hpu1)) begin
            $display("ERROR: X/Z in HPU_1 at PC=%0d, offset=%0d, addr=%0d, val=%h", pc, k, addr_hpu_1 + k, val_hpu1);
            mismatch_found = 1;
            error_write_mismatch = 1'b1;
          end else if (val_hpu0 !== val_hpu1) begin
            $display("ERROR: Mismatch at PC=%0d, offset=%0d: HPU_0[%0d]=%h != HPU_1[%0d]=%h",
                     pc, k, addr_hpu_0 + k, val_hpu0, addr_hpu_1 + k, val_hpu1);
            mismatch_found = 1;
            error_write_mismatch = 1'b1;
          end
        end
      end

      if (~mismatch_found)
        $display("[INFO]: Memory check PASSED: HPU_A and HPU_B contents match");
    endtask
  end else begin : gen_check_mem
    task automatic check_memories(
      input logic [SRC_ADDR_W-1:0] src_addr,
      input logic [DST_ADDR_W-1:0] dst_addr
    );
      int addr_hpu_0, addr_hpu_1;
      logic mismatch_found;
      logic [AXI4_DATA_W-1:0] val_hpu0, val_hpu1;

      mismatch_found = 1'b0;
      addr_hpu_0 = (regf_start_addr_ofs + (dst_addr * CT_MEM_BYTES)) / AXI4_DATA_BYTES;
      addr_hpu_1 = (regf_start_addr_ofs + (src_addr * CT_MEM_BYTES)) / AXI4_DATA_BYTES;
      $display("addr_hpu_0 = %x, addr_hpu_1 = %x", addr_hpu_0, addr_hpu_1);

      // Only PC0 exists when ETH_PC==1
      for (int k = 0; k < AXI4_WORD_PER_PC0; k++) begin
        val_hpu0 = gen_mem_hpu[0].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_0 + k];
        val_hpu1 = gen_mem_hpu[1].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_1 + k];

        if ($isunknown(val_hpu0)) begin
          $display("ERROR: X/Z in HPU_0 at PC=0, offset=%0d, addr=%0d, val=%h", k, addr_hpu_0 + k, val_hpu0);
          mismatch_found = 1;
          error_write_mismatch = 1'b1;
        end else if ($isunknown(val_hpu1)) begin
          $display("ERROR: X/Z in HPU_1 at PC=0, offset=%0d, addr=%0d, val=%h", k, addr_hpu_1 + k, val_hpu1);
          mismatch_found = 1;
          error_write_mismatch = 1'b1;
        end else if (val_hpu0 !== val_hpu1) begin
          $display("ERROR: Mismatch at PC=0, offset=%0d: HPU_0[%0d]=%h != HPU_1[%0d]=%h",
                   k, addr_hpu_0 + k, val_hpu0, addr_hpu_1 + k, val_hpu1);
          mismatch_found = 1;
          error_write_mismatch = 1'b1;
        end
      end

      if (~mismatch_found)
        $display("[INFO]: Memory check PASSED: HPU_A and HPU_B contents match");
    endtask
  end endgenerate


  // ============================================================================================== --
  // SVA
  // ============================================================================================== --
  // Assumption: if TX is correct, so is RX, if HPU 0 is correct, so is HPU 1

  // XSIM is less flexible than other tools, let's ignore it for quick debug
  `ifndef XSIM
    // After TLAST, not TVALID
    property no_valid_after_last(int lane);
      @(posedge clk_mhdma) disable iff (~s_rstn_mhdma)
      (qsfp_tx_tvalid[0][lane] && qsfp_tx_tready[0][lane] && qsfp_tx_tlast[0][lane]) |=> ~qsfp_tx_tvalid[0][lane];
    endproperty

    // TLAST requires TVALID
    property mrmac_tlast_valid(int lane);
      @(posedge clk_mhdma) disable iff (~s_rstn_mhdma)
      qsfp_tx_tlast[0][lane] |-> qsfp_tx_tvalid[0][lane];
    endproperty

    // TX/RX AXIS valid must stay stable until ready
    property axis_stable(int lane);
      @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
      (qsfp_tx_tvalid[0][lane] && ~qsfp_tx_tready[0][lane]) |=> $stable(qsfp_tx_tvalid[0][lane]) && $stable(qsfp_tx_tdata[0][lane]) && $stable(qsfp_tx_tkeep_user[0][lane]);
    endproperty

    // Once tvalid is asserted, it must be held until tlast handshake
    property tvalid_held_until_tlast(int lane);
      @(posedge clk_mhdma) disable iff (~s_rstn_mhdma)
      (qsfp_tx_tvalid[0][lane] && !(qsfp_tx_tlast[0][lane] && qsfp_tx_tready[0][lane])) |=> qsfp_tx_tvalid[0][lane];
    endproperty

    // Minimum Ethernet frame size (64 bytes) on valid frames - MRMAC inserts 4 bytes so we check for 60
    property mrmac_min_frame_size(int lane);
      int byte_count;
      @(posedge clk_mhdma) disable iff (~s_rstn_mhdma)
      (!$past(qsfp_tx_tvalid[0][lane]) && qsfp_tx_tvalid[0][lane], byte_count=0) |->
        first_match(
          (qsfp_tx_tvalid[0][lane], byte_count += (qsfp_tx_tready[0][lane] ? $countones(qsfp_tx_tkeep_user[0][lane]) : 0))[*1:$] ##0
          (qsfp_tx_tlast[0][lane] && qsfp_tx_tready[0][lane])
        ) ##0 (byte_count >= 60);
    endproperty

    generate
      for (genvar i = 0; i < 4; i++) begin
        assert_no_valid_after_last: assert property(no_valid_after_last(i))
          else begin
            $error("[ERROR-SVA]: tx_valid still asserted after tx_last");
            error_assert = 1'b1;
          end

        assert_tlast_requires_tvalid: assert property(mrmac_tlast_valid(i))
          else begin
            $error("[ERROR-SVA]: saw t_last when not valid");
            error_assert = 1'b1;
          end

        axis_is_stable_when_unconsumed: assert property(axis_stable(i))
          else begin
            $error("[ERROR]: Value changed when ready fell");
            error_assert = 1'b1;
          end

        correct_min_size: assert property(mrmac_min_frame_size(i))
          else begin
            $error("[ERROR-SVA]: incorrect minimum size");
            error_assert = 1'b1;
          end

        assert_tvalid_held_until_tlast: assert property(tvalid_held_until_tlast(i))
          else begin
            $error("[ERROR-SVA]: tvalid dropped before tlast");
            error_assert = 1'b1;
          end

      end
    endgenerate
  `endif
endmodule
