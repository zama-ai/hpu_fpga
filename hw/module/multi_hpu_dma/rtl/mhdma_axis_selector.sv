// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : two way axi4-stream switch
// ----------------------------------------------------------------------------------------------
//
// Selects one line out of QSFP_LANE_NB depending on input line_sel.
//
// ==============================================================================================

module mhdma_axis_selector
  import mhdma_pkg::*;
  #() (
  // axi-stream - to QSFP
  input [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0]  qsfp_rx_tdata,
  input [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0]  qsfp_rx_tkeep_user,
  input [QSFP_LANE_NB-1:0]                    qsfp_rx_tlast,
  input [QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid,

  output [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0] qsfp_tx_tdata,
  output [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user,
  output [QSFP_LANE_NB-1:0]                   qsfp_tx_tlast,
  output [QSFP_LANE_NB-1:0]                   qsfp_tx_tvalid,
  input  [QSFP_LANE_NB-1:0]                   qsfp_tx_tready,

  // axi4-stream - from fifo
  output [MRMAC_AXIS_W-1:0] axis_rx_tdata,
  output [MRMAC_TKEEP_W-1:0] axis_rx_tkeep_user,
  output                    axis_rx_tlast,
  output                    axis_rx_tvalid,

  input  [MRMAC_AXIS_W-1:0] axis_tx_tdata,
  input  [MRMAC_TKEEP_W-1:0] axis_tx_tkeep_user,
  input                     axis_tx_tlast,
  input                     axis_tx_tvalid,
  output                    axis_tx_tready,
  // natural number for line control
  input [$clog2(QSFP_LANE_NB)-1:0] line_sel
);

  // Rx
  assign axis_rx_tdata      = qsfp_rx_tdata[line_sel];
  assign axis_rx_tkeep_user = qsfp_rx_tkeep_user[line_sel];
  assign axis_rx_tlast      = qsfp_rx_tlast[line_sel];
  assign axis_rx_tvalid     = qsfp_rx_tvalid[line_sel];

  // TX link
  assign axis_tx_tready = qsfp_tx_tready[line_sel];

  generate
    for (genvar i = 0; i < LANE_NB; i++) begin
      assign qsfp_tx_tdata[i]       = (line_sel == i) ? axis_tx_tdata      : 'h0;
      assign qsfp_tx_tkeep_user[i]  = (line_sel == i) ? axis_tx_tkeep_user : 'h0;
      assign qsfp_tx_tlast[i]       = (line_sel == i) ? axis_tx_tlast      : 'h0;
      assign qsfp_tx_tvalid[i]      = (line_sel == i) ? axis_tx_tvalid     : 'h0;
    end
  endgenerate


endmodule
