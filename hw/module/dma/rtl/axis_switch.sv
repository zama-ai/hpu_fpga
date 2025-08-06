// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : two way axi4-stream switch
// ----------------------------------------------------------------------------------------------
//
// Selects one line out of LINE_NB depending on input line_sel.
//
// ==============================================================================================

module axis_switch #(
  parameter int LINE_NB       = 4,
  parameter int AXIS_TDATA_W  = 64,
  parameter int AXIS_TKEEP_W  = 11
) (
  // axi-stream - to QSFP
  input [LINE_NB-1:0][AXIS_TDATA_W-1:0]  qsfp_rx_tdata,
  input [LINE_NB-1:0][AXIS_TKEEP_W-1:0]  qsfp_rx_tkeep_user,
  input [LINE_NB-1:0]                    qsfp_rx_tlast,
  input [LINE_NB-1:0]                    qsfp_rx_tvalid,

  output [LINE_NB-1:0][AXIS_TDATA_W-1:0] qsfp_tx_tdata,
  output [LINE_NB-1:0][AXIS_TKEEP_W-1:0] qsfp_tx_tkeep_user,
  output [LINE_NB-1:0]                   qsfp_tx_tlast,
  output [LINE_NB-1:0]                   qsfp_tx_tvalid,
  input  [LINE_NB-1:0]                   qsfp_tx_tready,

  // axi4-stream - from fifo
  output [AXIS_TDATA_W-1:0] axis_rx_tdata,
  output [AXIS_TKEEP_W-1:0] axis_rx_tkeep_user,
  output                    axis_rx_tlast,
  output                    axis_rx_tvalid,

  input  [AXIS_TDATA_W-1:0] axis_tx_tdata,
  input  [AXIS_TKEEP_W-1:0] axis_tx_tkeep_user,
  input                     axis_tx_tlast,
  input                     axis_tx_tvalid,
  output                    axis_tx_tready,
  // natural number for line control
  input [$clog2(LINE_NB):0] line_sel
);

assign axis_rx_tdata      = qsfp_rx_tdata[line_sel];
assign axis_rx_tkeep_user = qsfp_rx_tkeep_user[line_sel];
assign axis_rx_tlast      = qsfp_rx_tlast[line_sel];
assign axis_rx_tvalid     = qsfp_rx_tvalid[line_sel];


assign qsfp_tx_tdata[line_sel]      = axis_tx_tdata;
assign qsfp_tx_tkeep_user[line_sel] = axis_tx_tkeep_user;
assign qsfp_tx_tlast[line_sel]      = axis_tx_tlast;
assign qsfp_tx_tvalid[line_sel]     = axis_tx_tvalid;
assign axis_tx_tready               = qsfp_tx_tready[line_sel];

endmodule
