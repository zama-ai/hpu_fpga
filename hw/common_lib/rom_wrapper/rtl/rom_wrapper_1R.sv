// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Wrapper for one path read only memory
// ----------------------------------------------------------------------------------------------
//
// Wrapper for one path read only memory.
//
// Parameters :
// FILENAME          : File for initialization of the memory, values are in bits
// WIDTH             : Data width
// DEPTH             : ROM depth (number of words in ROM)
// KEEP_RD_DATA      : 0 : Read data is not kept at the output
//                     1 : Read data is kept at the output until next reading.
// ROM_LATENCY       : ROM read latency. Should be >= 1
// ==============================================================================================

module rom_wrapper_1R #(
  parameter     FILENAME     = "",
  parameter int WIDTH        = 8,
  parameter int DEPTH        = 512,
  parameter     KEEP_RD_DATA = 0,
  parameter int ROM_LATENCY  = 1
) (
  // system interface
  input                            clk,
  input                            s_rst_n,
  // data interface
  input                            rd_en,
  input  logic [$clog2(DEPTH)-1:0] rd_add,
  output logic [        WIDTH-1:0] rd_data

);

  // ============================================================================================ //
  // rom_wrapper_1R
  // ============================================================================================ //
  // TODO : Use generate to choose the RAM to be instantiated.

  // -------------------------------------------------------------------------------------------- //
  // Behavioral ROM : target Xilinx RAMB
  // -------------------------------------------------------------------------------------------- //
  rom_1R_behav #(
    .FILENAME    (FILENAME),
    .WIDTH       (WIDTH),
    .DEPTH       (DEPTH),
    .KEEP_RD_DATA(KEEP_RD_DATA),
    .ROM_LATENCY (ROM_LATENCY)
  ) rom_1R_behav (
    .clk    (clk),
    .s_rst_n(s_rst_n),
    .rd_en  (rd_en),
    .rd_add (rd_add),
    .rd_data(rd_data)
  );

endmodule
