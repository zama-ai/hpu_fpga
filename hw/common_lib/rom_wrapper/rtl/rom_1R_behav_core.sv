// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Behavioral single port ROM.
//
// Parameters :
// WIDTH             : Data width
// DEPTH             : RAM depth (number of words in RAM)
//
// ==============================================================================================

module rom_1R_behav_core #(
  parameter     FILENAME = "",
  parameter int WIDTH    = 8,
  parameter int DEPTH    = 512
) (
  // system interface
  input                            clk,
  // data interface
  input                            rd_en,
  input  logic [$clog2(DEPTH)-1:0] rd_add,
  output logic [        WIDTH-1:0] rd_data
);

  // ============================================================================================ //
  // rom_1R_core
  // ============================================================================================ //
  // Configuration of the array as a blockram of WIDTHxDEPTH size
  // Xilinx specific constraint for ROM inference
  (* rom_style = "block" *) logic [WIDTH-1:0] a[DEPTH-1:0];

  // reading the memory file
  initial begin
    $readmemh(FILENAME, a, 0, DEPTH-1);
  end

  // Read process
  always_ff @(posedge clk) begin
    if (rd_en) begin
      rd_data <= a[rd_add];
    end
  end

endmodule
