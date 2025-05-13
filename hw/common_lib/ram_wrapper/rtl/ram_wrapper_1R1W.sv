// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// RAM wrapper.
// RAM interface for 1R1W RAMs.
//
// Parameters :
// WIDTH             : Data width
// DEPTH             : RAM depth (number of words in RAM)
// RD_WR_ACCESS_TYPE : Behavior when there is a read and write access conflict.
//                     0 : output 'X'
//                     1 : Read old value - not recommended by Xilinx
//                     2 : Read new value
// KEEP_RD_DATA      : 0 : Read data is not kept at the output
//                     1 : Read data is kept at the output until next reading.
// RAM_LATENCY       : RAM read latency. Should be >= 1
// ==============================================================================================

module ram_wrapper_1R1W #(
  parameter int WIDTH             = 32,
  parameter int DEPTH             = 512,
  parameter int RD_WR_ACCESS_TYPE = 1,
  parameter bit KEEP_RD_DATA      = 0,
  parameter int RAM_LATENCY       = 1
)
(
  input                     clk,        // clock
  input                     s_rst_n,    // synchronous reset

  // Read port
  input                     rd_en,
  input [$clog2(DEPTH)-1:0] rd_add,
  output [WIDTH-1:0]        rd_data, // available RAM_LATENCY cycles after rd_en

  // Write port
  input                     wr_en,
  input [$clog2(DEPTH)-1:0] wr_add,
  input [WIDTH-1:0]         wr_data
);

  import ram_wrapper_pkg::*;

// ============================================================================================== --
// Check parameter
// ============================================================================================== --
// pragma translate_off
  initial begin
    assert (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_CONFLICT
        || RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_OLD
        || RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_NEW)
    else $error("> ERROR: Unsupported RAM access type : %d", RD_WR_ACCESS_TYPE);
  end
// pragma translate_on

// ============================================================================================== --
// ram_wrapper_1R1W
// ============================================================================================== --
// TODO : Use generate to choose the RAM to be instantiated.

// ---------------------------------------------------------------------------------------------- --
// Behavioral
// ---------------------------------------------------------------------------------------------- --
  ram_1R1W_behav #(
    .WIDTH             (WIDTH            ),
    .DEPTH             (DEPTH            ),
    .RD_WR_ACCESS_TYPE (RD_WR_ACCESS_TYPE),
    .KEEP_RD_DATA      (KEEP_RD_DATA     ),
    .RAM_LATENCY       (RAM_LATENCY      )
  )
  ram_1R1W
  (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .rd_en   (rd_en  ),
    .rd_add  (rd_add ),
    .rd_data (rd_data),

    .wr_en   (wr_en  ),
    .wr_add  (wr_add ),
    .wr_data (wr_data)
  );
endmodule
