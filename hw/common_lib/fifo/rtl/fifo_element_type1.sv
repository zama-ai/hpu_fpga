// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Elementary FIFO with depth = 1.
// Type 1 :means that the out_data and out_vld paths are register outputs.
//
// Parameters:
//   WIDTH : data width
//   DO_RESET_DATA : (1) reset data width RESET_DATA_VAL
//                   (0) do not reset data
//   RESET_DATA_VAL : value used to reset the data. Used when DO_RESET_DATA = 1
// ==============================================================================================

module fifo_element_type1 #(
  parameter int             WIDTH          = 1,
  parameter bit             DO_RESET_DATA  = 0,
  parameter     [WIDTH-1:0] RESET_DATA_VAL = 0
) (
  input              clk,     // clock
  input              s_rst_n, // synchronous reset

  input  [WIDTH-1:0] in_data,
  input              in_vld,
  output             in_rdy,

  output [WIDTH-1:0] out_data,
  output             out_vld,
  input              out_rdy
);

  // ============================================================================================== --
  // fifo_element_type1
  // ============================================================================================== --
  logic [WIDTH-1:0] data;
  logic [WIDTH-1:0] dataD;
  logic             vld;
  logic             vldD;

  assign vldD  = out_rdy ? in_vld : vld | in_vld;
  assign dataD = (in_vld && in_rdy) ? in_data : data;

  always_ff @(posedge clk)
    if (!s_rst_n) vld <= 1'b0;
    else vld <= vldD;

  generate
    if (DO_RESET_DATA) begin : reset_data_gen
      always_ff @(posedge clk)
        if (!s_rst_n) data <= RESET_DATA_VAL;
        else data <= dataD;
    end else begin : no_reset_data_gen
      always_ff @(posedge clk) data <= dataD;
    end
  endgenerate

  assign out_data = data;
  assign out_vld  = vld;
  assign in_rdy   = out_rdy | ~vld;
endmodule

