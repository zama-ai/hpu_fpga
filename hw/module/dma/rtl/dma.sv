// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Top of DMA
// ----------------------------------------------------------------------------------------------
//
// General info on the module.
//
// Parameters : Describes the parameters.
//
// Prerequisites : Describes the conditions on the inputs.
//
// ==============================================================================================

module dma
  import axi_if_common_param_pkg::*;
  import hpu_regif_core_eth_2in3_pkg::*;
#(
  parameter int LINE_NB       = 4,  // number of QSFP lines
  parameter int AXIS_TDATA_W  = 64, // must match MAC+PCS configuration from bd
  parameter int AXIS_TKEEP_W  = 11
) (
  // Ethernet configuration interface -----------------------------------------
  input logic clk_eth_cfg,
  input logic resetn_eth_cfg,
  // Axi4-lite slave interface for regfile ------------------------------------
  input  logic [AXIL_ADD_W-1:0]  s_axil_awaddr,
  input  logic                   s_axil_awvalid,
  output logic                   s_axil_awready,
  input  logic [AXIL_DATA_W-1:0] s_axil_wdata,
  input  logic                   s_axil_wvalid,
  output logic                   s_axil_wready,
  output logic [1:0]             s_axil_bresp,
  output logic                   s_axil_bvalid,
  input  logic                   s_axil_bready,
  input  logic [AXIL_ADD_W-1:0]  s_axil_araddr,
  input  logic                   s_axil_arvalid,
  output logic                   s_axil_arready,
  output logic [AXIL_DATA_W-1:0] s_axil_rdata,
  output logic [1:0]             s_axil_rresp,
  output logic                   s_axil_rvalid,
  input  logic                   s_axil_rready,
  // QSFP system interface ----------------------------------------------------
  // == TX
  output[LINE_NB-1:0][AXIS_DATA_W-1:0  ] qsfp_tx_tdata,
  output[LINE_NB-1:0][AXIS_TKEEP_W-1:0 ] qsfp_tx_tkeep_user,
  output[LINE_NB-1:0]                    qsfp_tx_tlast,
  output[LINE_NB-1:0]                    qsfp_tx_tvalid,
  input [LINE_NB-1:0]                    qsfp_tx_tready,
  // == RX
  input [LINE_NB-1:0][AXIS_DATA_W-1:0  ] qsfp_rx_tdata,
  input [LINE_NB-1:0][AXIS_TKEEP_W-1:0 ] qsfp_rx_tkeep_user,
  input [LINE_NB-1:0]                    qsfp_rx_tlast,
  input [LINE_NB-1:0]                    qsfp_rx_tvalid,
  // axi4-stream interface to fifo --------------------------------------------
  // == RX
  output [AXIS_DATA_W-1:0]  axis_rx_tdata,
  output [AXIS_TKEEP_W-1:0] axis_rx_tkeep_user,
  output                    axis_rx_tlast,
  output                    axis_rx_tvalid,
  // == TX
  input  [AXIS_DATA_W-1:0]  axis_tx_tdata,
  input  [AXIS_TKEEP_W-1:0] axis_tx_tkeep_user,
  input                     axis_tx_tlast,
  input                     axis_tx_tvalid,
  output                    axis_tx_tready
);


  logic [$clog2(LINE_NB):0] r_line_select;

  logic [LINE_NB-1:0] gt_reset_tx_datapath_in;
  logic [LINE_NB-1:0] gt_reset_rx_datapath_in;
  logic [LINE_NB-1:0] gt_reset_all_in;

  logic [7:0] gt_line_rate;

  // loopback mode, will be applied to all channels
  //  * 000: disabled
  //  * 010: near end pma
  //  * 100: near end pcs
  logic [2:0] gt_loopback;


  // What needs to be controlled through axi4-lite
  //  = MRMAC
  //  * line selection
  //  * rx/tx datapath reset
  //  * GT PLL and datapath reset
  //  = GTM
  //  * channel line rate
  //  * loopback
  hpu_regif_core_eth_2in3  hpu_regif_core_eth_2in3 (
    // configuration interface
    .clk    (clk_eth_cfg),
    .s_rst_n(resetn_eth_cfg),
    // axi4-lite
    .s_axil_awaddr (s_axil_awaddr),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata  (s_axil_wdata),
    .s_axil_wvalid (s_axil_wvalid),
    .s_axil_wready (s_axil_wready),
    .s_axil_bresp  (s_axil_bresp),
    .s_axil_bvalid (s_axil_bvalid),
    .s_axil_bready (s_axil_bready),
    .s_axil_araddr (s_axil_araddr),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata  (s_axil_rdata),
    .s_axil_rresp  (s_axil_rresp),
    .s_axil_rvalid (s_axil_rvalid),
    .s_axil_rready (s_axil_rready),
    .r_axil_wdata  (r_axil_wdata),
    // control signals
    .r_line_select(r_line_select)
  );

  axis_switch # (
    .LINE_NB            (LINE_NB),
    .AXIS_TDATA_W       (AXIS_DATA_W),
    .AXIS_TKEEP_W       (AXIS_TKEEP_W)
  ) axis_switch (
    .qsfp_rx_tdata      (qsfp_rx_tdata),
    .qsfp_rx_tkeep_user (qsfp_rx_tkeep_user),
    .qsfp_rx_tlast      (qsfp_rx_tlast),
    .qsfp_rx_tvalid     (qsfp_rx_tvalid),

    .qsfp_tx_tdata      (qsfp_tx_tdata),
    .qsfp_tx_tkeep_user (qsfp_tx_tkeep_user),
    .qsfp_tx_tlast      (qsfp_tx_tlast),
    .qsfp_tx_tvalid     (qsfp_tx_tvalid),
    .qsfp_tx_tready     (qsfp_tx_tready),

    .axis_rx_tdata      (axis_rx_tdata),
    .axis_rx_tkeep_user (axis_rx_tkeep_user),
    .axis_rx_tlast      (axis_rx_tlast),
    .axis_rx_tvalid     (axis_rx_tvalid),

    .axis_tx_tdata      (axis_tx_tdata),
    .axis_tx_tkeep_user (axis_tx_tkeep_user),
    .axis_tx_tlast      (axis_tx_tlast),
    .axis_tx_tvalid     (axis_tx_tvalid),
    .axis_tx_tready     (axis_tx_tready),

    .line_sel(r_line_select)
  );

endmodule
