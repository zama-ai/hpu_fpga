// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Two path Read-only memory core
// ----------------------------------------------------------------------------------------------
//
// Behavioral double port ROM.
//
// Parameters :
// FILENAME          : File containing the initialization of the memory, values are in bits
// WIDTH             : Data width
// DEPTH             : ROM depth (number of words in ROM)
//
// ==============================================================================================

module rom_2R_behav_core #(
  parameter     FILENAME = "",
  parameter int WIDTH    = 8,
  parameter int DEPTH    = 512
) (
  // system interface
  input                            clk,
  // data interface a
  input                            a_rd_en,
  input  logic [$clog2(DEPTH)-1:0] a_rd_add,
  output logic [        WIDTH-1:0] a_rd_data,
  // data interface b
  input                            b_rd_en,
  input  logic [$clog2(DEPTH)-1:0] b_rd_add,
  output logic [        WIDTH-1:0] b_rd_data
);

  // ============================================================================================ //
  // rom_2R_core
  // ============================================================================================ //
  // Configuration of the array as a blockram of WIDTHxDEPTH size
  // Xilinx specific constraint for ROM inference
  (* rom_style = "block" *) logic [WIDTH-1:0] a[DEPTH-1:0];

  // reading the memory file
  initial begin
    $readmemh(FILENAME, a, 0, DEPTH - 1);
  end

  // memory path a ----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (a_rd_en) begin
      a_rd_data <= a[a_rd_add];
    end
  end

  // memory path b ----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (b_rd_en) begin
      b_rd_data <= a[b_rd_add];
    end
  end

endmodule
