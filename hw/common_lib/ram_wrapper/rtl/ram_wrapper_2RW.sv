// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// RAM wrapper.
// RAM interface for 2RW RAMs, single clock.
//
// Parameters :
// WIDTH             : Data width
// DEPTH             : RAM depth (number of words in RAM)
// RD_WR_ACCESS_TYPE : Behavior when there is a read and write access conflict.
//                     0 : output 'X'
//                     1 : Read old value - Xilinx BRAM default behaviour
//                     2 : Read new value
// KEEP_RD_DATA      : 0 : Read data is not kept at the output
//                     1 : Read data is kept at the output until next reading.
// RAM_LATENCY       : RAM read latency. Should be >= 1
// ==============================================================================================

module ram_wrapper_2RW #(
  parameter int WIDTH             = 32,
  parameter int DEPTH             = 512,
  parameter int RD_WR_ACCESS_TYPE = 1,
  parameter bit KEEP_RD_DATA      = 0,
  parameter int RAM_LATENCY       = 1
)
(
  input                            clk,        // clock
  input                            s_rst_n,    // synchronous reset

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
// ram_wrapper_2RW
// ============================================================================================== --
// TODO : Use generate to choose the RAM to be instantiated.

// ---------------------------------------------------------------------------------------------- --
// Behavioral
// ---------------------------------------------------------------------------------------------- --
  ram_2RW_behav #(
    .WIDTH             (WIDTH            ),
    .DEPTH             (DEPTH            ),
    .RD_WR_ACCESS_TYPE (RD_WR_ACCESS_TYPE),
    .KEEP_RD_DATA      (KEEP_RD_DATA     ),
    .RAM_LATENCY       (RAM_LATENCY      )
  )
  ram_2RW
  (
    .clk         (clk    ),
    .s_rst_n     (s_rst_n),

    .a_en        (a_en     ),
    .a_wen       (a_wen    ),
    .a_add       (a_add    ),
    .a_wr_data   (a_wr_data),
    .a_rd_data   (a_rd_data),

    .b_en        (b_en     ),
    .b_wen       (b_wen    ),
    .b_add       (b_add    ),
    .b_wr_data   (b_wr_data),
    .b_rd_data   (b_rd_data)
  );

endmodule
