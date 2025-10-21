// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This testbench only tests debug mode
// Debug mode corresponds to the control of one lane through register file
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_multi_hpu_dma;
  import axi_if_shell_axil_pkg::*;        // axi4-lite
  import hpu_regif_core_eth_2in3_pkg::*;  // ethernet regif
  import mhdma_pkg::*;                    // multi-hpu-dma

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 4;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int HPU_NB = 2; // in this test we will try to connect two mhdma (or HPUs)

  localparam int FIFO_DEPTH = 512;

  // ciphertext memories -------------------------------------------------------------------------
  parameter int MEM_WR_CMD_BUF_DEPTH = 4; // Should be >= 1
  parameter int MEM_RD_CMD_BUF_DEPTH = 1; // Should be >= 1
  // Data latency
  parameter int MEM_WR_DATA_LATENCY = 42; // Should be >= 1
  parameter int MEM_RD_DATA_LATENCY = 1;  // Should be >= 1
  // Set random on ready valid, on write path
  parameter bit MEM_USE_WR_RANDOM = 1;
  // Set random on ready valid, on read path
  parameter bit MEM_USE_RD_RANDOM = 0; // check path, no need random

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk_control;
  bit clk_mrmac;

  initial begin
    clk_control = 1'b0;
    clk_mrmac = 1'b0;
  end

  always begin
    #CLK_HALF_PERIOD_A clk_control = ~clk_control;
  end
  always begin
    #CLK_HALF_PERIOD_B clk_mrmac = ~clk_mrmac;
  end

  bit a_rst_n; // asynchronous reset
  bit s_rstn_control; // synchronous reset
  bit s_rstn_mrmac; // synchronous reset

  initial begin
    a_rst_n = 1'b0;                  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always_ff @(posedge clk_control) begin
    s_rstn_control <= a_rst_n;
  end
  always_ff @(posedge clk_mrmac) begin
    s_rstn_mrmac <= a_rst_n;
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

  assign error = error_tb_notify | error_register_read;

  always_ff @(posedge clk_control)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [AXIL_ADD_W-1:0]      s_axil_dma_awaddr_hpu_a;
  logic                       s_axil_dma_awvalid_hpu_a;
  logic                       s_axil_dma_awready_hpu_a;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_wdata_hpu_a;
  logic [AXIL_DATA_BYTES-1:0] s_axil_dma_wstrb_hpu_a; /* UNUSED */
  logic                       s_axil_dma_wvalid_hpu_a;
  logic                       s_axil_dma_wready_hpu_a;
  logic [1:0]                 s_axil_dma_bresp_hpu_a;
  logic                       s_axil_dma_bvalid_hpu_a;
  logic                       s_axil_dma_bready_hpu_a;
  logic [AXIL_ADD_W-1:0]      s_axil_dma_araddr_hpu_a;
  logic                       s_axil_dma_arvalid_hpu_a;
  logic                       s_axil_dma_arready_hpu_a;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_rdata_hpu_a;
  logic [1:0]                 s_axil_dma_rresp_hpu_a;
  logic                       s_axil_dma_rvalid_hpu_a;
  logic                       s_axil_dma_rready_hpu_a;

  logic [AXIL_ADD_W-1:0]      s_axil_dma_awaddr_hpu_b;
  logic                       s_axil_dma_awvalid_hpu_b;
  logic                       s_axil_dma_awready_hpu_b;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_wdata_hpu_b;
  logic [AXIL_DATA_BYTES-1:0] s_axil_dma_wstrb_hpu_b; /* UNUSED */
  logic                       s_axil_dma_wvalid_hpu_b;
  logic                       s_axil_dma_wready_hpu_b;
  logic [1:0]                 s_axil_dma_bresp_hpu_b;
  logic                       s_axil_dma_bvalid_hpu_b;
  logic                       s_axil_dma_bready_hpu_b;
  logic [AXIL_ADD_W-1:0]      s_axil_dma_araddr_hpu_b;
  logic                       s_axil_dma_arvalid_hpu_b;
  logic                       s_axil_dma_arready_hpu_b;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_rdata_hpu_b;
  logic [1:0]                 s_axil_dma_rresp_hpu_b;
  logic                       s_axil_dma_rvalid_hpu_b;
  logic                       s_axil_dma_rready_hpu_b;
  // QSFP system interface ----------------------------------------------------
  // == TX
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_tx_tdata;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_tx_tlast;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_tx_tvalid;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_tx_tready;
  // == RX
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_rx_tdata;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_rx_tlast;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid;

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
  logic [31:0] line_parameter;
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
  logic [31:0] line_debug;
  logic        reset_registers;
  logic        tx_loop;
  logic        rx_to_tx;

  assign line_debug[28:0] = 'h0;
  assign line_debug[29]   = rx_to_tx;
  assign line_debug[30]   = tx_loop;
  assign line_debug[31]   = reset_registers;

  // [section] reset ----------------------------------------------------------
  logic [31:0] reset_parameter;
  logic [QSFP_LANE_NB-1:0] rst_rx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_tx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_all;

  assign reset_parameter = {20'h0, rst_rx_datapath, rst_tx_datapath, rst_all};

  // monitoring of reset done
  logic [HPU_NB-1:0][31:0] reset_monitor;

  // HPU A ----------------------------------------------------------------------------------------
  multi_hpu_dma #(
    .FIFO_DEPTH(FIFO_DEPTH)
  ) hpu_a (
    .clk_eth_cfg   (clk_control    ),
    .resetn_eth_cfg(s_rstn_control ),

    .clk_eth_mrmac   (clk_mrmac    ),
    .resetn_eth_mrmac(s_rstn_mrmac ),

    .s_axil_dma_awaddr (s_axil_dma_awaddr_hpu_a ),
    .s_axil_dma_awvalid(s_axil_dma_awvalid_hpu_a),
    .s_axil_dma_awready(s_axil_dma_awready_hpu_a),
    .s_axil_dma_wdata  (s_axil_dma_wdata_hpu_a  ),
    .s_axil_dma_wstrb  (s_axil_dma_wstrb_hpu_a  ),
    .s_axil_dma_wvalid (s_axil_dma_wvalid_hpu_a ),
    .s_axil_dma_wready (s_axil_dma_wready_hpu_a ),
    .s_axil_dma_bresp  (s_axil_dma_bresp_hpu_a  ),
    .s_axil_dma_bvalid (s_axil_dma_bvalid_hpu_a ),
    .s_axil_dma_bready (s_axil_dma_bready_hpu_a ),
    .s_axil_dma_araddr (s_axil_dma_araddr_hpu_a ),
    .s_axil_dma_arvalid(s_axil_dma_arvalid_hpu_a),
    .s_axil_dma_arready(s_axil_dma_arready_hpu_a),
    .s_axil_dma_rdata  (s_axil_dma_rdata_hpu_a  ),
    .s_axil_dma_rresp  (s_axil_dma_rresp_hpu_a  ),
    .s_axil_dma_rvalid (s_axil_dma_rvalid_hpu_a ),
    .s_axil_dma_rready (s_axil_dma_rready_hpu_a ),

    .qsfp_tx_tdata     (qsfp_tx_tdata[0]     ),
    .qsfp_tx_tkeep_user(qsfp_tx_tkeep_user[0]),
    .qsfp_tx_tlast     (qsfp_tx_tlast[0]     ),
    .qsfp_tx_tvalid    (qsfp_tx_tvalid[0]    ),
    .qsfp_tx_tready    (qsfp_tx_tready[0]    ),

    .qsfp_rx_tdata     (qsfp_rx_tdata[0]     ),
    .qsfp_rx_tkeep_user(qsfp_rx_tkeep_user[0]),
    .qsfp_rx_tlast     (qsfp_rx_tlast[0]     ),
    .qsfp_rx_tvalid    (qsfp_rx_tvalid[0]    ),

    .gt_line_rate        (gt_line_rate[0]        ),
    .gt_loopback         (gt_loopback[0]         ),
    .gt_reset_rx_datapath(gt_reset_rx_datapath[0]),
    .gt_reset_tx_datapath(gt_reset_tx_datapath[0]),
    .gt_reset_all        (gt_reset_all[0]        ),
    .gt_rx_reset_done    (gt_rx_reset_done[0]    ),
    .gt_tx_reset_done    (gt_tx_reset_done[0]    )
);

  // HPU B ----------------------------------------------------------------------------------------
  multi_hpu_dma #(
    .FIFO_DEPTH(FIFO_DEPTH)
  ) hpu_b (
    .clk_eth_cfg   (clk_control    ),
    .resetn_eth_cfg(s_rstn_control ),

    .clk_eth_mrmac   (clk_mrmac    ),
    .resetn_eth_mrmac(s_rstn_mrmac ),

    .s_axil_dma_awaddr (s_axil_dma_awaddr_hpu_b ),
    .s_axil_dma_awvalid(s_axil_dma_awvalid_hpu_b),
    .s_axil_dma_awready(s_axil_dma_awready_hpu_b),
    .s_axil_dma_wdata  (s_axil_dma_wdata_hpu_b  ),
    .s_axil_dma_wstrb  (s_axil_dma_wstrb_hpu_b  ),
    .s_axil_dma_wvalid (s_axil_dma_wvalid_hpu_b ),
    .s_axil_dma_wready (s_axil_dma_wready_hpu_b ),
    .s_axil_dma_bresp  (s_axil_dma_bresp_hpu_b  ),
    .s_axil_dma_bvalid (s_axil_dma_bvalid_hpu_b ),
    .s_axil_dma_bready (s_axil_dma_bready_hpu_b ),
    .s_axil_dma_araddr (s_axil_dma_araddr_hpu_b ),
    .s_axil_dma_arvalid(s_axil_dma_arvalid_hpu_b),
    .s_axil_dma_arready(s_axil_dma_arready_hpu_b),
    .s_axil_dma_rdata  (s_axil_dma_rdata_hpu_b  ),
    .s_axil_dma_rresp  (s_axil_dma_rresp_hpu_b  ),
    .s_axil_dma_rvalid (s_axil_dma_rvalid_hpu_b ),
    .s_axil_dma_rready (s_axil_dma_rready_hpu_b ),

    .qsfp_tx_tdata     (qsfp_tx_tdata[1]     ),
    .qsfp_tx_tkeep_user(qsfp_tx_tkeep_user[1]),
    .qsfp_tx_tlast     (qsfp_tx_tlast[1]     ),
    .qsfp_tx_tvalid    (qsfp_tx_tvalid[1]    ),
    .qsfp_tx_tready    (qsfp_tx_tready[1]    ),

    .qsfp_rx_tdata     (qsfp_rx_tdata[1]     ),
    .qsfp_rx_tkeep_user(qsfp_rx_tkeep_user[1]),
    .qsfp_rx_tlast     (qsfp_rx_tlast[1]     ),
    .qsfp_rx_tvalid    (qsfp_rx_tvalid[1]    ),

    .gt_line_rate        (gt_line_rate[1]        ),
    .gt_loopback         (gt_loopback[1]         ),
    .gt_reset_rx_datapath(gt_reset_rx_datapath[1]),
    .gt_reset_tx_datapath(gt_reset_tx_datapath[1]),
    .gt_reset_all        (gt_reset_all[1]        ),
    .gt_rx_reset_done    (gt_rx_reset_done[1]    ),
    .gt_tx_reset_done    (gt_tx_reset_done[1]    )
);

// ============================================================================================== --
// Scenario
// ============================================================================================== --

  // AXI4-LITE drivers ----------------------------------------------------------------------------
  maxil_if #(
  .AXIL_DATA_W(AXIL_DATA_W),
  .AXIL_ADD_W  (AXIL_ADD_W)
  ) maxil_drv_if_hpu_a ( .clk(clk_control), .rst_n(s_rstn_control));

  // Connect interface on testbench signals
  assign s_axil_dma_awaddr_hpu_a  = maxil_drv_if_hpu_a.awaddr;
  assign s_axil_dma_awvalid_hpu_a = maxil_drv_if_hpu_a.awvalid;
  assign s_axil_dma_wdata_hpu_a   = maxil_drv_if_hpu_a.wdata;
  assign s_axil_dma_wstrb_hpu_a   = maxil_drv_if_hpu_a.wstrb;
  assign s_axil_dma_wvalid_hpu_a  = maxil_drv_if_hpu_a.wvalid;
  assign s_axil_dma_bready_hpu_a  = maxil_drv_if_hpu_a.bready;
  assign s_axil_dma_araddr_hpu_a  = maxil_drv_if_hpu_a.araddr;
  assign s_axil_dma_arvalid_hpu_a = maxil_drv_if_hpu_a.arvalid;
  assign s_axil_dma_rready_hpu_a  = maxil_drv_if_hpu_a.rready;

  assign maxil_drv_if_hpu_a.awready = s_axil_dma_awready_hpu_a;
  assign maxil_drv_if_hpu_a.wready  = s_axil_dma_wready_hpu_a;
  assign maxil_drv_if_hpu_a.bresp   = s_axil_dma_bresp_hpu_a;
  assign maxil_drv_if_hpu_a.bvalid  = s_axil_dma_bvalid_hpu_a;
  assign maxil_drv_if_hpu_a.arready = s_axil_dma_arready_hpu_a;
  assign maxil_drv_if_hpu_a.rdata   = s_axil_dma_rdata_hpu_a;
  assign maxil_drv_if_hpu_a.rresp   = s_axil_dma_rresp_hpu_a;
  assign maxil_drv_if_hpu_a.rvalid  = s_axil_dma_rvalid_hpu_a;

  maxil_if #(
  .AXIL_DATA_W(AXIL_DATA_W),
  .AXIL_ADD_W  (AXIL_ADD_W)
  ) maxil_drv_if_hpu_b ( .clk(clk_control), .rst_n(s_rstn_control));

  // Connect interface on testbench signals
  assign s_axil_dma_awaddr_hpu_b  = maxil_drv_if_hpu_b.awaddr;
  assign s_axil_dma_awvalid_hpu_b = maxil_drv_if_hpu_b.awvalid;
  assign s_axil_dma_wdata_hpu_b   = maxil_drv_if_hpu_b.wdata;
  assign s_axil_dma_wstrb_hpu_b   = maxil_drv_if_hpu_b.wstrb;
  assign s_axil_dma_wvalid_hpu_b  = maxil_drv_if_hpu_b.wvalid;
  assign s_axil_dma_bready_hpu_b  = maxil_drv_if_hpu_b.bready;
  assign s_axil_dma_araddr_hpu_b  = maxil_drv_if_hpu_b.araddr;
  assign s_axil_dma_arvalid_hpu_b = maxil_drv_if_hpu_b.arvalid;
  assign s_axil_dma_rready_hpu_b  = maxil_drv_if_hpu_b.rready;

  assign maxil_drv_if_hpu_b.awready = s_axil_dma_awready_hpu_b;
  assign maxil_drv_if_hpu_b.wready  = s_axil_dma_wready_hpu_b;
  assign maxil_drv_if_hpu_b.bresp   = s_axil_dma_bresp_hpu_b;
  assign maxil_drv_if_hpu_b.bvalid  = s_axil_dma_bvalid_hpu_b;
  assign maxil_drv_if_hpu_b.arready = s_axil_dma_arready_hpu_b;
  assign maxil_drv_if_hpu_b.rdata   = s_axil_dma_rdata_hpu_b;
  assign maxil_drv_if_hpu_b.rresp   = s_axil_dma_rresp_hpu_b;
  assign maxil_drv_if_hpu_b.rvalid  = s_axil_dma_rvalid_hpu_b;

  // memory models --------------------------------------------------------------------------------
  logic [HPU_NB-1:0][AXI4_ID_W-1:0]       axi4_ct_awid;
  logic [HPU_NB-1:0][AXI4_ADD_W-1:0]      axi4_ct_awaddr;
  logic [HPU_NB-1:0][7:0]                 axi4_ct_awlen;
  logic [HPU_NB-1:0][2:0]                 axi4_ct_awsize;
  logic [HPU_NB-1:0][1:0]                 axi4_ct_awburst;
  logic [HPU_NB-1:0]                      axi4_ct_awvalid;
  logic [HPU_NB-1:0]                      axi4_ct_awready;
  logic [HPU_NB-1:0][AXI4_DATA_W-1:0]     axi4_ct_wdata;
  logic [HPU_NB-1:0][(AXI4_DATA_W/8)-1:0] axi4_ct_wstrb;
  logic [HPU_NB-1:0]                      axi4_ct_wlast;
  logic [HPU_NB-1:0]                      axi4_ct_wvalid;
  logic [HPU_NB-1:0]                      axi4_ct_wready;
  logic [HPU_NB-1:0][AXI4_ID_W-1:0]       axi4_ct_bid;
  logic [HPU_NB-1:0][1:0]                 axi4_ct_bresp;
  logic [HPU_NB-1:0]                      axi4_ct_bvalid;
  logic [HPU_NB-1:0]                      axi4_ct_bready;

  logic [HPU_NB-1:0][AXI4_ID_W-1:0]       axi4_ct_arid;
  logic [HPU_NB-1:0][AXI4_ADD_W-1:0]      axi4_ct_araddr;
  logic [HPU_NB-1:0][7:0]                 axi4_ct_arlen;
  logic [HPU_NB-1:0][2:0]                 axi4_ct_arsize;
  logic [HPU_NB-1:0][1:0]                 axi4_ct_arburst;
  logic [HPU_NB-1:0]                      axi4_ct_arvalid;
  logic [HPU_NB-1:0]                      axi4_ct_arready;
  logic [HPU_NB-1:0][AXI4_ID_W-1:0]       axi4_ct_rid;
  logic [HPU_NB-1:0][AXI4_DATA_W-1:0]     axi4_ct_rdata;
  logic [HPU_NB-1:0][1:0]                 axi4_ct_rresp;
  logic [HPU_NB-1:0]                      axi4_ct_rlast;
  logic [HPU_NB-1:0]                      axi4_ct_rvalid;
  logic [HPU_NB-1:0]                      axi4_ct_rready;

  generate
    for (genvar gen_p=0; gen_p<HPU_NB; gen_p=gen_p+1) begin : gen_mem_loop
      axi4_mem #(
        .DATA_WIDTH      (AXI4_DATA_W                    ),
        .ADDR_WIDTH      (8                     ), //64?!
        .ID_WIDTH        (AXI4_ID_W                      ),
        .WR_CMD_BUF_DEPTH(MEM_WR_CMD_BUF_DEPTH           ),
        .RD_CMD_BUF_DEPTH(MEM_RD_CMD_BUF_DEPTH           ),
        .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY+ gen_p * 50),
        .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY            ),
        .USE_WR_RANDOM   (MEM_USE_WR_RANDOM              ),
        .USE_RD_RANDOM   (MEM_USE_RD_RANDOM              )
      ) axi4_mem_ct (
        .clk           (clk                   ),
        .rst           (~s_rst_n              ),
        .s_axi4_awid   (axi4_ct_awid[gen_p]   ),
        .s_axi4_awaddr (axi4_ct_awaddr[gen_p] ),
        .s_axi4_awlen  (axi4_ct_awlen[gen_p]  ),
        .s_axi4_awsize (axi4_ct_awsize[gen_p] ),
        .s_axi4_awburst(axi4_ct_awburst[gen_p]),
        .s_axi4_awlock ('0), // disable
        .s_axi4_awcache('0), // disable
        .s_axi4_awprot ('0), // disable
        .s_axi4_awvalid(axi4_ct_awvalid[gen_p]),
        .s_axi4_awready(axi4_ct_awready[gen_p]),
        .s_axi4_wdata  (axi4_ct_wdata[gen_p]  ),
        .s_axi4_wstrb  (axi4_ct_wstrb[gen_p]  ),
        .s_axi4_wlast  (axi4_ct_wlast[gen_p]  ),
        .s_axi4_wvalid (axi4_ct_wvalid[gen_p] ),
        .s_axi4_wready (axi4_ct_wready[gen_p] ),
        .s_axi4_bid    (axi4_ct_bid[gen_p]    ),
        .s_axi4_bresp  (axi4_ct_bresp[gen_p]  ),
        .s_axi4_bvalid (axi4_ct_bvalid[gen_p] ),
        .s_axi4_bready (axi4_ct_bready[gen_p] ),
        .s_axi4_arid   (axi4_ct_arid[gen_p]   ),
        .s_axi4_araddr (axi4_ct_araddr[gen_p] ),
        .s_axi4_arlen  (axi4_ct_arlen[gen_p]  ),
        .s_axi4_arsize (axi4_ct_arsize[gen_p] ),
        .s_axi4_arburst(axi4_ct_arburst[gen_p]),
        .s_axi4_arlock ('0), // disable
        .s_axi4_arcache('0), // disable
        .s_axi4_arprot ('0), // disable
        .s_axi4_arvalid(axi4_ct_arvalid[gen_p]),
        .s_axi4_arready(axi4_ct_arready[gen_p]),
        .s_axi4_rid    (axi4_ct_rid[gen_p]    ),
        .s_axi4_rdata  (axi4_ct_rdata[gen_p]  ),
        .s_axi4_rresp  (axi4_ct_rresp[gen_p]  ),
        .s_axi4_rlast  (axi4_ct_rlast[gen_p]  ),
        .s_axi4_rvalid (axi4_ct_rvalid[gen_p] ),
        .s_axi4_rready (axi4_ct_rready[gen_p] )
      );
    end
  endgenerate

  // Signals --------------------------------------------------------------------------------------
  // must not bee too short, not too long
  logic [31:0] timeout_size;

  // HPU-A and HPU-B node id will be set randomly and mandatorily different
  logic [3:0] random_hpu_a;
  logic [3:0] random_hpu_b;

  // IOP related signals
  logic [ 3:0] iop_id;
  logic [15:0] iop_src_addr;
  logic [15:0] iop_dst_addr;

  // Fixed for now, might evolve later
  logic [15:0] req_size_b;
  assign req_size_b = 'h4000;

  // scenario -------------------------------------------------------------------------------------
  initial begin
    maxil_drv_if_hpu_a.init();
    maxil_drv_if_hpu_b.init();

    reset_registers = 'h0;
    tx_loop         = 'h0;
    rx_to_tx        = 'h0;
    repeat(20) @(posedge clk_control);

    /* In this scenario we must define theses test-cases :
     ==============================================================================================
     * - classical use:
     *                > X Notifies to Y that a ciphertext is ready
     *                > Y then reads this ciphertext
     *  -------------------------------------------------------------------------------------------
     * > we must see that the ciphertext moved from memory X to Y
     *  ===========================================================================================
     * - Piling requests:
     *                > X Notifies to Y that several ciphertexts are ready
     *                > Y then reads alls ciphertexts
     *  -------------------------------------------------------------------------------------------
     * > all ciphertexts must have moved from memory X to Y
     *  ===========================================================================================
     * - Notfiy timeout
     *                > X Notifies to Y that a ciphertexts is ready
     *                > X doesn't receive the ack
     *  -------------------------------------------------------------------------------------------
     * > Does the timeout is triggered correctly and the Notify request resent properly ?
     *  ===========================================================================================
     * - Read request timeout #1
     *                > X does a read request to Y
     *                > no packets is then received
     *  -------------------------------------------------------------------------------------------
     * > Does the timeout is triggered correctly and the Read request resent properly ?
     *  ===========================================================================================
     * - Read request timeout #2
     *                > X does a read request to Y
     *                > a packet is lost
     *  -------------------------------------------------------------------------------------------
     * > Does the timeout is triggered correctly and the Read request resent properly ?
     */

    // Initialization =============================================================================
    $display("A - Initial register check and definition");
    init_registers();

    // Defining MAC addresses for both instances of HPU -------------------------------------------
    write_mac_addresses();

    // TODO: add checker

    // Classical use-case =========================================================================
    // or how this should be used most of the time
    // for now size_b is fixed, all our ciphertext are 16.384kB size_b=0x40004
    iop_id       = $urandom();
    iop_src_addr = $urandom();
    iop_dst_addr = $urandom();

    // Sending a NOTIFY from HPU-B to HPU-A -------------------------------------------------------
    notify_reqest(random_hpu_b, random_hpu_a, iop_id, iop_src_addr);

    // TODO: add checker

    // Sending a read request from HPU-A to HPU-B -------------------------------------------------
    read_request(random_hpu_b, iop_id, iop_src_addr, iop_dst_addr);

    // TODO: add checker

    $display("%t > INFO: End simulation",$time);
    repeat(20) @(posedge clk_control);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Initialize memory
// ============================================================================================== --
  initial begin
    for (int i = 0; i < 10000; i++) begin
        gen_mem_loop[0].axi4_mem_ct.axi4_ram_ct_wr.mem[i] = i;
    end
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --
  logic [31:0] rdata;

  task automatic init_registers;
    begin
    // Reading system REGISTERS -------------------------------------------------------------------
      maxil_drv_if_hpu_a.read_trans(SYSTEM_LINE_OFS, rdata);
      assert (rdata == 'h0) else begin
        $display("%t > ERROR:register SYSTEM_LINE_OFS not correctly read %h",$time, rdata);
        error_register_read = 1'b1;
      end

    // ASSIGN REGISTERS & CHECK -------------------------------------------------------------------
    line_rate     = 8'hAB;  // random, no idea what it should be
    line_loopback = 3'b100; // 3 near end pcs loopback
    line_select   = 2'b10;  // 2nd line selected
    debug_flag    = 1'b0;
    @(posedge clk_control);

    maxil_drv_if_hpu_a.write_trans(SYSTEM_LINE_OFS, line_parameter);
    maxil_drv_if_hpu_b.write_trans(SYSTEM_LINE_OFS, line_parameter);

    rst_rx_datapath = 4'b0100;
    rst_tx_datapath = 4'b1011;
    rst_all         = 4'b0101;
    @(posedge clk_control);

    maxil_drv_if_hpu_a.write_trans(RESET_DATAPATH_OFS, reset_parameter);
    maxil_drv_if_hpu_b.write_trans(RESET_DATAPATH_OFS, reset_parameter);

    assert ((gt_line_rate[0] == line_rate) && (gt_line_rate[1] == line_rate)) else begin
      $display("[ERROR] line_rate has unexpected value %x %x %x",gt_line_rate[0], gt_line_rate[1], line_rate);
      error_register_read = 1;
    end
    assert ((gt_loopback[0] ==line_loopback) && (gt_loopback[1] == line_loopback)) else begin
      $display("[ERROR] gt_loopback has unexpected value");
      error_register_read = 1;
    end
    assert ((hpu_a.line_sel == line_select) &&  (hpu_b.line_sel == line_select)) else begin
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

    maxil_drv_if_hpu_a.read_trans(RESET_MONITOR_OFS, reset_monitor[0]);
    maxil_drv_if_hpu_b.read_trans(RESET_MONITOR_OFS, reset_monitor[1]);

    assert ((reset_monitor[3:0] == gt_tx_reset_done) && (reset_monitor[7:4] == gt_rx_reset_done)) begin
      $display("%t >    ERROR: reset monitor has not been read correctly",$time);
      error_register_read = 1'b1;
    end

    // Setting timeout size to both HPUs ----------------------------------------------------------
    maxil_drv_if_hpu_a.write_trans(SYSTEM_TIMEOUT_OFS, timeout_size);
    maxil_drv_if_hpu_b.write_trans(SYSTEM_TIMEOUT_OFS, timeout_size);

    // Setting up credible values -------------------------------------------------------------
    // no loopback, no reset, not in debug lane0 selected
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
    logic [23:0] mac_addr;
    logic [ 3:0] hpu_id;
    logic        hpu_current;
    logic [31:0] register_mac_addr_a;
    logic [31:0] register_mac_addr_b;
    begin
      random_hpu_a = $urandom_range(7, 0);

      // let's avoid saying that we are the same HPU
      do begin
        random_hpu_b = $urandom_range(7, 0);
      end while (random_hpu_b == random_hpu_a);

      $display("\n[INFO] Writing MAC addresses");
      $display("[INFO] For this run....");
      $display("[INFO]  > HPU_A:id=%0d", random_hpu_a);
      $display("[INFO]  > HPU_B:id=%0d \n", random_hpu_b);

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

        $display("[INFO] HPU_ID=%0d :: MAC=%0x", i, mac_addr);
        maxil_drv_if_hpu_a.write_trans(HPU_ID_ZERO_OFS+(4*i), register_mac_addr_a);
        maxil_drv_if_hpu_b.write_trans(HPU_ID_ZERO_OFS+(4*i), register_mac_addr_b);
      end

    end
  endtask

  /* Performs a Read request from HPU A to HPU B
    - Since HPU A and HPU B are the same no need to be able to be able to send from both
    - There is two registers to write to send a read request */
  task automatic read_request(
    input logic [ 3:0] node_id,
    input logic [ 3:0] iop_id,
    input logic [15:0] src_addr,
    input logic [15:0] dest_addr
  );
    logic [31:0] read_req_id;
    logic [31:0] read_req_addr;
    begin
      $display("\n[INFO] Sending a read request from HPU-%0x to HPU-%0x",random_hpu_a ,node_id);

      // see package
      read_req_addr = {dest_addr, src_addr};
      read_req_id = {4'b0000, iop_id, 4'b0000, node_id, req_size_b};

      maxil_drv_if_hpu_a.write_trans(REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv_if_hpu_a.write_trans(REQUEST_REQ_ID_OFS, read_req_id);
    end
  endtask


  /* Performs a Notify request from an HPU to another
   * - HPU-A and HPU-B can be both side here
   * - if you chose a wrong HPU-id you will get an error
   */
  task automatic notify_reqest(
    input logic [ 3:0] src_node_id,
    input logic [ 3:0] dst_node_id,
    input logic [ 3:0] iop_id,
    input logic [15:0] src_addr
  );
    logic [31:0] read_req_id;
    logic [31:0] read_req_addr;
    begin
      $display("\n[INFO] Sending a Notify request from HPU-%0x to HPU-%0x", src_node_id, dst_node_id);

      read_req_addr = {16'b0, src_addr};
      read_req_id = {4'b0000, iop_id, 4'b0000, dst_node_id, req_size_b};

      if (src_node_id == random_hpu_a) begin
        maxil_drv_if_hpu_a.write_trans(REQUEST_REQ_ADDR_OFS, read_req_addr);
        maxil_drv_if_hpu_a.write_trans(REQUEST_REQ_ID_OFS, read_req_id);
      end else if (src_node_id == random_hpu_b) begin
        maxil_drv_if_hpu_b.write_trans(REQUEST_REQ_ADDR_OFS, read_req_addr);
        maxil_drv_if_hpu_b.write_trans(REQUEST_REQ_ID_OFS, read_req_id);
      end else begin
        $display("[ERROR] you are trying to send a Notify request from an HPU non instantiated");
        error_tb_notify = 1'b1;
      end

    end
  endtask

endmodule
