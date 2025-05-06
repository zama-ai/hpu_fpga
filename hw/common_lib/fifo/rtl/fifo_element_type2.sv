// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Elementary FIFO with depth = 1.
// Type 2 :means that the in_rdy paths is a register output.
//
// Parameters:
//   WIDTH : data width
//   DO_RESET_DATA : (1) reset data width RESET_DATA_VAL
//                   (0) do not reset data
//   RESET_DATA_VAL : value used to reset the data. Used when DO_RESET_DATA = 1
// ==============================================================================================

module fifo_element_type2 #(
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
  // fifo_element_type2
  // ============================================================================================== --
  logic [WIDTH-1:0] data_kept;
  logic [WIDTH-1:0] data_keptD;
  logic             vld_kept;
  logic             vld_keptD;

  logic             rdy;
  logic             rdyD;

  assign vld_keptD  = !out_rdy ? in_vld | vld_kept : 1'b0;
  assign data_keptD = (!out_rdy && vld_kept) ? data_kept : in_data;
  assign rdyD       = out_rdy | ~out_vld;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      vld_kept <= 1'b0;
      rdy      <= 1'b1;
    end else begin
      vld_kept <= vld_keptD;
      rdy      <= rdyD;
    end
  end

  generate
    if (DO_RESET_DATA) begin : reset_data_gen
      always_ff @(posedge clk)
        if (!s_rst_n) data_kept <= RESET_DATA_VAL;
        else data_kept <= data_keptD;
    end else begin : no_reset_data_gen
      always_ff @(posedge clk) data_kept <= data_keptD;
    end
  endgenerate

  assign in_rdy   = rdy;
  assign out_data = vld_kept ? data_kept : in_data;
  assign out_vld  = in_vld | vld_kept;
endmodule

