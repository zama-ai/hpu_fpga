// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : two way axi4-stream switch
// ----------------------------------------------------------------------------------------------
//
// Selects one line out of LANE_NB depending on input line_sel.
//
// ==============================================================================================

module axis_switch_lane_to_1 #(
  parameter int LANE_NB       = 4,
  parameter int AXIS_TDATA_W  = 64,
  parameter int AXIS_TKEEP_W  = 11
) (
  // axi-stream - to QSFP
  input [LANE_NB-1:0][AXIS_TDATA_W-1:0]  qsfp_rx_tdata,
  input [LANE_NB-1:0][AXIS_TKEEP_W-1:0]  qsfp_rx_tkeep_user,
  input [LANE_NB-1:0]                    qsfp_rx_tlast,
  input [LANE_NB-1:0]                    qsfp_rx_tvalid,

  output [LANE_NB-1:0][AXIS_TDATA_W-1:0] qsfp_tx_tdata,
  output [LANE_NB-1:0][AXIS_TKEEP_W-1:0] qsfp_tx_tkeep_user,
  output [LANE_NB-1:0]                   qsfp_tx_tlast,
  output [LANE_NB-1:0]                   qsfp_tx_tvalid,
  input  [LANE_NB-1:0]                   qsfp_tx_tready,

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
  input [$clog2(LANE_NB)-1:0] line_sel
);

  // Rx
  logic [AXIS_TDATA_W-1:0] temp_rx_tdata;
  logic [AXIS_TKEEP_W-1:0] temp_rx_tkeep_user;
  logic                    temp_rx_tlast;
  logic                    temp_rx_tvalid;

  always_comb begin : gen_rx
    temp_rx_tdata      = '0;
    temp_rx_tkeep_user = '0;
    temp_rx_tlast      = 1'b0;
    temp_rx_tvalid     = 1'b0;

    for (int i = 0; i < LANE_NB; i++) begin
      if (line_sel == i) begin
        temp_rx_tdata      = qsfp_rx_tdata[i];
        temp_rx_tkeep_user = qsfp_rx_tkeep_user[i];
        temp_rx_tlast      = qsfp_rx_tlast[i];
        temp_rx_tvalid     = qsfp_rx_tvalid[i];
      end
    end
  end
  assign axis_rx_tdata      = temp_rx_tdata;
  assign axis_rx_tkeep_user = temp_rx_tkeep_user;
  assign axis_rx_tlast      = temp_rx_tlast;
  assign axis_rx_tvalid     = temp_rx_tvalid;


  // TX link
  logic [LANE_NB-1:0][AXIS_TDATA_W-1:0] temp_tx_tdata;
  logic [LANE_NB-1:0][AXIS_TKEEP_W-1:0] temp_tx_tkeep_user;
  logic [LANE_NB-1:0]                   temp_tx_tlast;
  logic [LANE_NB-1:0]                   temp_tx_tvalid;
  logic                                 temp_tx_tready;

  always_comb begin : gen_tx
    temp_tx_tdata = 'h0;
    temp_tx_tkeep_user = 'h0;
    temp_tx_tlast = 'h0;
    temp_tx_tvalid = 'h0;
    temp_tx_tready = 'h0;

    for (int i = 0; i < LANE_NB; i++) begin
      if (line_sel == i) begin
        temp_tx_tdata[i]      = axis_tx_tdata;
        temp_tx_tkeep_user[i] = axis_tx_tkeep_user;
        temp_tx_tlast[i]      = axis_tx_tlast;
        temp_tx_tvalid[i]     = axis_tx_tvalid;
        temp_tx_tready        = qsfp_tx_tready[i];
      end else begin
        temp_tx_tdata[i]      = 'h0;
        temp_tx_tkeep_user[i] = 'h0;
        temp_tx_tlast[i]      = 1'b0;
        temp_tx_tvalid[i]     = 1'b0;
      end
    end
  end

  assign qsfp_tx_tdata = temp_tx_tdata;
  assign qsfp_tx_tkeep_user = temp_tx_tkeep_user;
  assign qsfp_tx_tlast = temp_tx_tlast;
  assign qsfp_tx_tvalid = temp_tx_tvalid;
  assign axis_tx_tready = temp_tx_tready;

endmodule
