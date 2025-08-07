// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This is the explicit title of the testbench module
// ----------------------------------------------------------------------------------------------
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_dma;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int LINE_NB = 4;
  localparam int AXIS_TDATA_W  = 64;
  localparam int AXIS_TKEEP_W  = 11;

// ============================================================================================== --
// functions
// ============================================================================================== --
//** functions **//

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit a_rst_n; // asynchronous reset
  bit s_rst_n; // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;                   // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
  end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [AXIL_ADD_W-1:0]      s_axil_dma_awaddr;
  logic                       s_axil_dma_awvalid;
  logic                       s_axil_dma_awready;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_wdata;
  logic [AXIL_DATA_BYTES-1:0] s_axil_dma_wstrb; /* UNUSED */
  logic                       s_axil_dma_wvalid;
  logic                       s_axil_dma_wready;
  logic [1:0]                 s_axil_dma_bresp;
  logic                       s_axil_dma_bvalid;
  logic                       s_axil_dma_bready;
  logic [AXIL_ADD_W-1:0]      s_axil_dma_araddr;
  logic                       s_axil_dma_arvalid;
  logic                       s_axil_dma_arready;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_rdata;
  logic [1:0]                 s_axil_dma_rresp;
  logic                       s_axil_dma_rvalid;
  logic                       s_axil_dma_rready;
  // QSFP system interface ----------------------------------------------------
  // == TX
  logic [LINE_NB-1:0][AXIS_TDATA_W-1:0  ] qsfp_tx_tdata;
  logic [LINE_NB-1:0][AXIS_TKEEP_W-1:0 ] qsfp_tx_tkeep_user;
  logic [LINE_NB-1:0]                    qsfp_tx_tlast;
  logic [LINE_NB-1:0]                    qsfp_tx_tvalid;
  logic [LINE_NB-1:0]                    qsfp_tx_tready;
  // == RX
  logic [LINE_NB-1:0][AXIS_TDATA_W-1:0  ] qsfp_rx_tdata;
  logic [LINE_NB-1:0][AXIS_TKEEP_W-1:0 ] qsfp_rx_tkeep_user;
  logic [LINE_NB-1:0]                    qsfp_rx_tlast;
  logic [LINE_NB-1:0]                    qsfp_rx_tvalid;
  // axi4-stream interface to fifo --------------------------------------------
  // == RX
  logic [AXIS_TDATA_W-1:0]  axis_rx_tdata;
  logic [AXIS_TKEEP_W-1:0] axis_rx_tkeep_user;
  logic                    axis_rx_tlast;
  logic                    axis_rx_tvalid;
  // == TX
  logic [AXIS_TDATA_W-1:0]  axis_tx_tdata;
  logic [AXIS_TKEEP_W-1:0] axis_tx_tkeep_user;
  logic                    axis_tx_tlast;
  logic                    axis_tx_tvalid;
  logic                    axis_tx_tready;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  dma #(
  //** parameters **//
  ) dut (
    .clk_eth_cfg   (clk    ),
    .resetn_eth_cfg(a_rst_n),

    .s_axil_dma_awaddr(s_axil_dma_awaddr),
    .s_axil_dma_awvalid(s_axil_dma_awvalid),
    .s_axil_dma_awready(s_axil_dma_awready),
    .s_axil_dma_wdata(s_axil_dma_wdata),
    .s_axil_dma_wstrb(s_axil_dma_wstrb),
    .s_axil_dma_wvalid(s_axil_dma_wvalid),
    .s_axil_dma_wready(s_axil_dma_wready),
    .s_axil_dma_bresp(s_axil_dma_bresp),
    .s_axil_dma_bvalid(s_axil_dma_bvalid),
    .s_axil_dma_bready(s_axil_dma_bready),
    .s_axil_dma_araddr(s_axil_dma_araddr),
    .s_axil_dma_arvalid(s_axil_dma_arvalid),
    .s_axil_dma_arready(s_axil_dma_arready),
    .s_axil_dma_rdata(s_axil_dma_rdata),
    .s_axil_dma_rresp(s_axil_dma_rresp),
    .s_axil_dma_rvalid(s_axil_dma_rvalid),
    .s_axil_dma_rready(s_axil_dma_rready),

    .qsfp_tx_tdata(qsfp_tx_tdata),
    .qsfp_tx_tkeep_user(qsfp_tx_tkeep_user),
    .qsfp_tx_tlast(qsfp_tx_tlast),
    .qsfp_tx_tvalid(qsfp_tx_tvalid),
    .qsfp_tx_tready(qsfp_tx_tready),

    .qsfp_rx_tdata(qsfp_rx_tdata),
    .qsfp_rx_tkeep_user(qsfp_rx_tkeep_user),
    .qsfp_rx_tlast(qsfp_rx_tlast),
    .qsfp_rx_tvalid(qsfp_rx_tvalid),

    .axis_rx_tdata(axis_rx_tdata),
    .axis_rx_tkeep_user(axis_rx_tkeep_user),
    .axis_rx_tlast(axis_rx_tlast),
    .axis_rx_tvalid(axis_rx_tvalid),

    .axis_tx_tdata(axis_tx_tdata),
    .axis_tx_tkeep_user(axis_tx_tkeep_user),
    .axis_tx_tlast(axis_tx_tlast),
    .axis_tx_tvalid(axis_tx_tvalid),
    .axis_tx_tready(axis_tx_tready)
);

// ============================================================================================== --
// Scenario
// ============================================================================================== --


  maxil_if #(
  .AXIL_DATA_W(AXIL_DATA_W),
  .AXIL_ADD_W  (AXIL_ADD_W)
  ) maxil_drv_if ( .clk(clk), .rst_n(s_rst_n));

  // Connect interface on testbench signals
  assign s_axil_dma_awaddr  = maxil_drv_if.awaddr;
  assign s_axil_dma_awvalid = maxil_drv_if.awvalid;
  assign s_axil_dma_wdata   = maxil_drv_if.wdata;
  assign s_axil_dma_wstrb   = maxil_drv_if.wstrb;
  assign s_axil_dma_wvalid  = maxil_drv_if.wvalid;
  assign s_axil_dma_bready  = maxil_drv_if.bready;
  assign s_axil_dma_araddr  = maxil_drv_if.araddr;
  assign s_axil_dma_arvalid = maxil_drv_if.arvalid;
  assign s_axil_dma_rready  = maxil_drv_if.rready;

  assign maxil_drv_if.awready = s_axil_dma_awready;
  assign maxil_drv_if.wready  = s_axil_dma_wready;
  assign maxil_drv_if.bresp   = s_axil_dma_bresp;
  assign maxil_drv_if.bvalid  = s_axil_dma_bvalid;
  assign maxil_drv_if.arready = s_axil_dma_arready;
  assign maxil_drv_if.rdata   = s_axil_dma_rdata;
  assign maxil_drv_if.rresp   = s_axil_dma_rresp;
  assign maxil_drv_if.rvalid  = s_axil_dma_rvalid;

endmodule
