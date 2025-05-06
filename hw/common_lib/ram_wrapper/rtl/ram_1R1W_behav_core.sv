// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Behavioral RAM : 1R1W RAM.
// As defined by Xilinx so that the RAM is inferred correctly.
//
// Parameters :
// WIDTH             : Data width
// DEPTH             : RAM depth (number of words in RAM)
//
// ==============================================================================================

module ram_1R1W_behav_core #(
  parameter int WIDTH             = 8,
  parameter int DEPTH             = 512
)
(
  input logic                      clk,        // clock

  // Read port
  input  logic                     rd_en,
  input  logic [$clog2(DEPTH)-1:0] rd_add,
  output logic [WIDTH-1:0]         rd_data, // available RAM_LATENCY cycles after rd_en

  // Write port
  input logic                      wr_en,
  input logic [$clog2(DEPTH)-1:0]  wr_add,
  input logic [WIDTH-1:0]          wr_data
);

// ============================================================================================== --
// ram_1R1W_behav_core
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Data array
// ---------------------------------------------------------------------------------------------- --
  logic [WIDTH-1:0]a[DEPTH-1:0];

`ifdef DEF_INIT_RAM
  initial begin
    for (int i=0; i<DEPTH; i=i+1)
      a[i] = 'hABBAC001DEADC0DE;
  end
`endif
  // Use always instead of always_ff to enable the initial above
  always @(posedge clk) begin
    if (wr_en) begin
      a[wr_add] <= wr_data;
    end
  end

  always_ff @(posedge clk) begin
    if (rd_en) begin
      rd_data <= a[rd_add];
    end
  end

endmodule

