// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Behavioral RAM : 2RW RAM.
// As defined by Xilinx so that the RAM is inferred correctly.
//
// Parameters :
// WIDTH             : Data width
// DEPTH             : RAM depth (number of words in RAM)
//
// ==============================================================================================

module ram_2RW_behav_core #(
  parameter int WIDTH             = 8,
  parameter int DEPTH             = 512
)
(
  input logic                      clk,

  // Port a
  input  logic                     a_en,
  input  logic                     a_wen,
  input  logic [$clog2(DEPTH)-1:0] a_add,
  input  logic [WIDTH-1:0]         a_wr_data,
  output logic [WIDTH-1:0]         a_rd_data,

  // Port b
  input  logic                     b_en,
  input  logic                     b_wen,
  input  logic [$clog2(DEPTH)-1:0] b_add,
  input  logic [WIDTH-1:0]         b_wr_data,
  output logic [WIDTH-1:0]         b_rd_data
);

// ============================================================================================== --
// ram_1R1W_behav_core
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Data array
// ---------------------------------------------------------------------------------------------- --
  // Note if write access conflict : 'X in location
  logic [WIDTH-1:0]a[DEPTH-1:0];

`ifdef DEF_INIT_RAM
  initial begin
    for (int i=0; i<DEPTH; i=i+1)
      a[i] = 'hABBAC001DEADC0DE;
  end
`endif

  always @(posedge clk) begin
    if (a_en) begin
      if (a_wen)
        a[a_add] <= a_wr_data;
      a_rd_data <= a[a_add];
    end
`ifdef QUESTA
    if (b_en) begin
      if (b_wen)
        a[b_add] <= b_wr_data;
      b_rd_data <= a[b_add];
    end
`endif
  end

`ifndef QUESTA
  always @(posedge clk) begin
    if (b_en) begin
      if (b_wen)
        a[b_add] <= b_wr_data;
      b_rd_data <= a[b_add];
    end
  end
`endif
endmodule

