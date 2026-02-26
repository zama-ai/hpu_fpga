// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This testbench tests parallel Read Requests between two HPUs
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_mhdma_parallel_read;
  import mhdma_pkg::*;                    // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;        // axi4-lite + REG_DATA_W
  import axi_if_common_param_pkg::*;      // general axi4
  import hpu_regif_core_mhdma_2in3_pkg::*;  // ethernet regif
  import axi_if_mhdma_axi_pkg::*;           // AXI ethernet
  import pem_common_param_pkg::*;         // CT_MEM_BYTES, AXI4_WORD_PER_PC*

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 4;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int HPU_NB = 2; // in this test we will try to connect two mhdma (or HPUs)

  localparam int LOOP_READ = 5;
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
  localparam int MEM_SIM_SIZE = 18; // must be < 22

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
  bit error_rr_payload;
  bit error_register_read;
  bit error_tb_read;
  bit error_write_mismatch;
  bit error_assert;

  assign error = error_assert | error_rr_payload | error_register_read | error_write_mismatch | error_tb_read;

  always_ff @(posedge clk_control)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
// AXI4-Lite slave interface
logic [HPU_NB-1:0][AXIL_ADD_W-1:0]                      s_axil_mhdma_awaddr;
logic [HPU_NB-1:0]                                      s_axil_mhdma_awvalid;
logic [HPU_NB-1:0]                                      s_axil_mhdma_awready;
logic [HPU_NB-1:0][AXIL_DATA_W-1:0]                     s_axil_mhdma_wdata;
logic [HPU_NB-1:0][AXIL_DATA_BYTES-1:0]                 s_axil_mhdma_wstrb; /* UNUSED */
logic [HPU_NB-1:0]                                      s_axil_mhdma_wvalid;
logic [HPU_NB-1:0]                                      s_axil_mhdma_wready;
logic [HPU_NB-1:0][1:0]                                 s_axil_mhdma_bresp;
logic [HPU_NB-1:0]                                      s_axil_mhdma_bvalid;
logic [HPU_NB-1:0]                                      s_axil_mhdma_bready;
logic [HPU_NB-1:0][AXIL_ADD_W-1:0]                      s_axil_mhdma_araddr;
logic [HPU_NB-1:0]                                      s_axil_mhdma_arvalid;
logic [HPU_NB-1:0]                                      s_axil_mhdma_arready;
logic [HPU_NB-1:0][AXIL_DATA_W-1:0]                     s_axil_mhdma_rdata;
logic [HPU_NB-1:0][1:0]                                 s_axil_mhdma_rresp;
logic [HPU_NB-1:0]                                      s_axil_mhdma_rvalid;
logic [HPU_NB-1:0]                                      s_axil_mhdma_rready;
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
  logic [2:0] line_loopback;
  logic [7:0] line_rate;
  logic [1:0] line_select;
  logic debug_flag;

  assign line_parameter[1:0]   = line_select;
  assign line_parameter[4:2]   = line_loopback;
  assign line_parameter[12:5]  = line_rate;
  assign line_parameter[27:13] = 'h0;
  assign line_parameter[31]    = debug_flag;

  // [section] line debug -----------------------------------------------------
  logic [REG_DATA_W-1:0] line_debug;
  logic reset_registers;
  logic tx_loop;
  logic rx_to_tx;

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

  // Signals --------------------------------------------------------------------------------------
  logic [REG_DATA_W-1:0] read_data;
  logic [REG_DATA_W-1:0] regf_start_addr_ofs;

  // HPU-A and HPU-B node id will be set randomly and mandatorily different
  logic [HPU_ID_W-1:0] random_hpu_a;
  logic [HPU_ID_W-1:0] random_hpu_b;

  // IOP related signals
  logic [HPU_NB-1:0][  IOP_ID_W-1:0] iop_id;
  logic [HPU_NB-1:0][SRC_ADDR_W-1:0] iop_src_addr;
  logic [HPU_NB-1:0][DST_ADDR_W-1:0] iop_dst_addr;

  logic [RSVD_W+FLAG_W+MODE_W-1:0] req_rfm; // reserved / flag / mode is not tested here
  assign req_rfm = 'h0;

  // for checking read request completions
  logic [HPU_NB-1:0][REG_DATA_W-1:0] rr_req_id_rd;
  logic [HPU_NB-1:0][REG_DATA_W-1:0] rr_req_addr_rd;
  logic [HPU_NB-1:0][REG_DATA_W-1:0] rr_req_id_expected;
  logic [HPU_NB-1:0][REG_DATA_W-1:0] rr_req_addr_expected;

  // Statistics
  logic [HPU_NB-1:0][REG_DATA_W-1:0] stat_rr_received;
  logic [HPU_NB-1:0][REG_DATA_W-1:0] stat_ce_received;
  logic [HPU_NB-1:0][REG_DATA_W-1:0] stat_errors;

  int random_iter;

  // scenario -------------------------------------------------------------------------------------
  initial begin
    gen_maxil_if[0].maxil_if.init();
    gen_maxil_if[1].maxil_if.init();

    reset_registers = 'h0;
    tx_loop = 'h0;
    rx_to_tx = 'h0;
    regf_start_addr_ofs = 'h0;
    repeat(20) @(posedge clk_control);

    random_iter = $urandom_range(REQ_FIFO_DEPTH, 2);

    $display("\n\n"); // separating from xpm fifo information

    $display("\n==================================================================================================");
    $display("  Initial register check and definition");
    $display("==================================================================================================");
    init_config();

    $display("\n==================================================================================================");
    $display("  SCENARIO : trying concurrent Read Requests %0d * %0d times", LOOP_READ, random_iter);
    $display("==================================================================================================");

    for(int i = 0; i < LOOP_READ; i++) begin
      fork
        begin
          for (int j = 0; j < random_iter; j++) begin
            // sending Read Request from A to B
            // Use lower half of address space to avoid overlap with B->A direction
            iop_id[0]       = $urandom();
            iop_src_addr[0] = $urandom_range(0, MEM_MAX_VALUE/2-1);
            iop_dst_addr[0] = $urandom_range(0, MEM_MAX_VALUE/2-1);

            read_request(random_hpu_a, random_hpu_b, iop_id[0], iop_src_addr[0], iop_dst_addr[0]);

            // wait for completion, then check immediately
            wait (interrupt_read_request[0] == 1'b1);
            gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_READ_REQUEST_OFS, rr_req_addr_rd[0]);
            gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, rr_req_id_rd[0]);

            rr_req_id_expected[0]   = {iop_id[0], REQ_ID_EMISSION, random_hpu_b, req_rfm};
            rr_req_addr_expected[0] = {iop_dst_addr[0], iop_src_addr[0]};

            assert (rr_req_id_rd[0] == rr_req_id_expected[0]) else begin
              $display("%t > [ERROR::%0d]: Read REQ_ID incorrect HPU A (received %x) != (exp %x)", $time, j, rr_req_id_rd[0], rr_req_id_expected[0]);
              gen_maxil_if[0].maxil_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors[0]);
              $display("%t > [ERROR]: HPU A error register: 0x%08h", $time, stat_errors[0]);
              error_rr_payload = 1'b1;
            end
            assert (rr_req_addr_rd[0] == rr_req_addr_expected[0]) else begin
              $display("%t > [ERROR::%0d]: Read REQ_ADDR incorrect HPU A (received %x) != (exp %x)", $time, j, rr_req_addr_rd[0], rr_req_addr_expected[0]);
              gen_maxil_if[0].maxil_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors[0]);
              $display("%t > [ERROR]: HPU A error register: 0x%08h", $time, stat_errors[0]);
              error_rr_payload = 1'b1;
            end

            check_memories(0, iop_src_addr[0], iop_dst_addr[0]);
          end
        end

        begin
          for (int j = 0; j < random_iter; j++) begin
            // sending Read Request from B to A
            // Use upper half of address space to avoid overlap with A->B direction
            iop_id[1]       = $urandom();
            iop_src_addr[1] = $urandom_range(MEM_MAX_VALUE/2, MEM_MAX_VALUE-1);
            iop_dst_addr[1] = $urandom_range(MEM_MAX_VALUE/2, MEM_MAX_VALUE-1);

            read_request(random_hpu_b, random_hpu_a, iop_id[1], iop_src_addr[1], iop_dst_addr[1]);

            // wait for completion, then check immediately
            wait (interrupt_read_request[1] == 1'b1);
            gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_READ_REQUEST_OFS, rr_req_addr_rd[1]);
            gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, rr_req_id_rd[1]);

            rr_req_id_expected[1]   = {iop_id[1], REQ_ID_EMISSION, random_hpu_a, req_rfm};
            rr_req_addr_expected[1] = {iop_dst_addr[1], iop_src_addr[1]};

            assert (rr_req_id_rd[1] == rr_req_id_expected[1]) else begin
              $display("%t > [ERROR::%0d]: Read REQ_ID incorrect HPU B (received %x) != (exp %x)", $time, j, rr_req_id_rd[1], rr_req_id_expected[1]);
              gen_maxil_if[1].maxil_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors[1]);
              $display("%t > [ERROR]: HPU B error register: 0x%08h", $time, stat_errors[1]);
              error_rr_payload = 1'b1;
            end
            assert (rr_req_addr_rd[1] == rr_req_addr_expected[1]) else begin
              $display("%t > [ERROR::%0d]: Read REQ_ADDR incorrect HPU B (received %x) != (exp %x)", $time, j, rr_req_addr_rd[1], rr_req_addr_expected[1]);
              gen_maxil_if[1].maxil_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors[1]);
              $display("%t > [ERROR]: HPU B error register: 0x%08h", $time, stat_errors[1]);
              error_rr_payload = 1'b1;
            end

            check_memories(1, iop_src_addr[1], iop_dst_addr[1]);
          end
        end
      join
    end

    // Final statistics ---------------------------------------------------------------------------
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS,                     stat_errors[0]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_SYSTEM_ERRORS_OFS,                     stat_errors[1]);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS, stat_rr_received[0]);
    gen_maxil_if[0].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_CE_RECEIVED_OFS,       stat_ce_received[0]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS, stat_rr_received[1]);
    gen_maxil_if[1].maxil_if.read_trans(MHDMA_REQUEST_STAT_NB_CE_RECEIVED_OFS,       stat_ce_received[1]);

    $display("\n ----------------- HPU_A -------------------------------------");
    $display(" stat_errors      : 0x%08h", stat_errors[0]);
    $display(" stat_rr_received : %0d", stat_rr_received[0]);
    $display(" stat_ce_received : %0d", stat_ce_received[0]);
    $display(" ----------------- HPU_B -------------------------------------");
    $display(" stat_errors      : 0x%08h", stat_errors[1]);
    $display(" stat_rr_received : %0d", stat_rr_received[1]);
    $display(" stat_ce_received : %0d", stat_ce_received[1]);

    assert (stat_errors[0] == 0 && stat_errors[1] == 0) else begin
      $display("%t > [ERROR]: Error register is not null!", $time);
      error_register_read = 1'b1;
    end

    assert (stat_ce_received[0] == (NB_PACKETS_FULL+1)*LOOP_READ*random_iter && stat_ce_received[1] == (NB_PACKETS_FULL+1)*LOOP_READ*random_iter) else begin
      $display("%t > [ERROR]: CE received count mismatch with expected value %0d", $time, LOOP_READ*random_iter);
      error_register_read = 1'b1;
    end

    $display("%t > INFO: End simulation",$time);
    $display(" =============================================================\n");
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
    assert ((gen_multi_hpu_dma[0].multi_hpu_dma.line_sel == line_select) &&  (gen_multi_hpu_dma[1].multi_hpu_dma.line_sel == line_select)) else begin
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

    write_mac_addresses();
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

  /* Performs a Read request from an HPU to another
   * - Bidirectional: can send from either HPU based on src_node_id
   */
  task automatic read_request(
    input logic [  HPU_ID_W-1:0] src_node_id,
    input logic [  HPU_ID_W-1:0] dst_node_id,
    input logic [  IOP_ID_W-1:0] iop_id,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dest_addr
  );
    logic [REG_DATA_W-1:0] read_req_id;
    logic [REG_DATA_W-1:0] read_req_addr;
    begin
      // see package
      read_req_addr = {dest_addr, src_addr};
      read_req_id = {iop_id, REQ_ID_READ, dst_node_id, req_rfm};

      if (src_node_id == random_hpu_a) begin
        gen_maxil_if[0].maxil_if.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
        gen_maxil_if[0].maxil_if.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
      end else if (src_node_id == random_hpu_b) begin
        gen_maxil_if[1].maxil_if.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
        gen_maxil_if[1].maxil_if.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
      end else begin
        $display("[ERROR] you are trying to send a read request from an HPU non instantiated");
        error_tb_read = 1'b1;
      end
    end
  endtask

// ============================================================================================== --
// Checker
// ============================================================================================== --
  /* Checker
  * memory content should be the same between receiver and source HPU for PC_0 and PC_1
  * recv_hpu: 0 means HPU_A received data from HPU_B, 1 means HPU_B received data from HPU_A
  * src_addr: ciphertext ID at the source HPU (where data was read from)
  * dst_addr: ciphertext ID at the receiver HPU (where data was written to)
  */
  task automatic check_memories(
    input int recv_hpu,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dst_addr
  );
    int addr_recv, addr_src;
    logic mismatch_found;
    logic [AXI4_DATA_W-1:0] val_recv, val_src;
    int nb_words;

    mismatch_found = 1'b0;

    // Use CT_MEM_BYTES for address calculation (cid * CT_MEM_BYTES), divide by 32 for word address
    addr_recv = (regf_start_addr_ofs + (dst_addr * CT_MEM_BYTES)) / 32;
    addr_src  = (regf_start_addr_ofs + (src_addr * CT_MEM_BYTES)) / 32;

    // Check both PCs
    for (int pc = 0; pc < ETH_PC; pc++) begin
      nb_words = (pc == 0) ? AXI4_WORD_PER_PC0 : AXI4_WORD_PER_PC;

      for (int k = 0; k < nb_words; k++) begin
        // VCS cannot dynamically index generate blocks, use explicit if/else
        if (recv_hpu == 0) begin
          if (pc == 0) begin
            val_recv = gen_mem_hpu[0].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_recv + k];
            val_src  = gen_mem_hpu[1].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_src  + k];
          end else begin
            val_recv = gen_mem_hpu[0].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_recv + k];
            val_src  = gen_mem_hpu[1].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_src  + k];
          end
        end else begin
          if (pc == 0) begin
            val_recv = gen_mem_hpu[1].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_recv + k];
            val_src  = gen_mem_hpu[0].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_src  + k];
          end else begin
            val_recv = gen_mem_hpu[1].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_recv + k];
            val_src  = gen_mem_hpu[0].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_src  + k];
          end
        end

        // Check for X/Z
        if ($isunknown(val_recv)) begin
          $display("ERROR: X/Z in HPU_%0d at PC=%0d, offset=%0d, addr=%0d, val=%h", recv_hpu, pc, k, addr_recv + k, val_recv);
          mismatch_found = 1;
          error_write_mismatch = 1'b1;
        end
        else if ($isunknown(val_src)) begin
          $display("ERROR: X/Z in HPU_%0d at PC=%0d, offset=%0d, addr=%0d, val=%h", 1-recv_hpu, pc, k, addr_src + k, val_src);
          mismatch_found = 1;
          error_write_mismatch = 1'b1;
        end
        // Check for mismatch
        else if (val_recv !== val_src) begin
          $display("ERROR: Mismatch at PC=%0d, offset=%0d: HPU_%0d[%0d]=%h != HPU_%0d[%0d]=%h",
                   pc, k, recv_hpu, addr_recv + k, val_recv, 1-recv_hpu, addr_src + k, val_src);
          mismatch_found = 1;
          error_write_mismatch = 1'b1;
        end
      end
    end

    if (~mismatch_found)
      $display("[INFO]: Memory check PASSED: HPU_%0d received correct data from HPU_%0d", recv_hpu, 1-recv_hpu);
  endtask

endmodule
