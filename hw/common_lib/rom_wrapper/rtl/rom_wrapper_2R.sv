// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// ROM wrapper.
// ROM interface for RR ROMs.
//
// Parameters :
// FILENAME      : File containing the initialization values of the memory, values are in bits
// WIDTH             : Data width
// DEPTH             : ROM depth (number of words in ROM)
// KEEP_RD_DATA      : 0 : Read data is not kept at the output
//                     1 : Read data is kept at the output until next reading.
// ROM_LATENCY       : ROM read latency. Should be >= 1
// ==============================================================================================

module rom_wrapper_2R #(
  parameter     FILENAME     = "",
  parameter int WIDTH        = 8,
  parameter int DEPTH        = 512,
  parameter     KEEP_RD_DATA = 0,
  parameter int ROM_LATENCY  = 1
) (
  // system interface
  input                            clk,
  input                            s_rst_n,
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
  // rom_wrapper_2R
  // ============================================================================================ //
  // TODO : Use generate to choose the RAM to be instantiated.

  // -------------------------------------------------------------------------------------------- //
  // Behavioral ROM : target Xilinx RAMB
  // -------------------------------------------------------------------------------------------- //
  rom_2R_behav #(
    .FILENAME    (FILENAME),
    .WIDTH       (WIDTH),
    .DEPTH       (DEPTH),
    .KEEP_RD_DATA(KEEP_RD_DATA),
    .ROM_LATENCY (ROM_LATENCY)
  ) rom_2R_behav (
    .clk      (clk),
    .s_rst_n  (s_rst_n),
    .a_rd_en  (a_rd_en),
    .a_rd_add (a_rd_add),
    .a_rd_data(a_rd_data),
    .b_rd_en  (b_rd_en),
    .b_rd_add (b_rd_add),
    .b_rd_data(b_rd_data)
  );

endmodule
