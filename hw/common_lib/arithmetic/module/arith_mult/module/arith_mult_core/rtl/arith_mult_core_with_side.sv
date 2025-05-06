// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : arith_mult_core_with_side
// ----------------------------------------------------------------------------------------------
//
// arith_mult_core_with_side : z = a * b.
//
// Parameters :
//  LATENCY       : Number of cycles used for the multiplication.
//                  These cycles will be used by the synthesizer for inferring the
//                  best implementation of this operation.
//                  In Xilinx architecture, the DSP 27x18 needs 2 cycles,
//                  or 3, according to the frequency.
//  OP_A_W,
//  OP_B_W        : Operand width
//
// ==============================================================================================

module arith_mult_core_with_side #(
  parameter bit   IN_PIPE  = 0,
  parameter int   OP_A_W   = 16,
  parameter int   OP_B_W   = 16,

  parameter int   SIDE_W   = 0, // Side data size. Set to 0 if not used
  parameter [1:0] RST_SIDE = 0  // If side data is used,
                                // [0] (1) reset them to 0.
                                // [1] (1) reset them to 1.

  
)
(
    input  logic                       clk,        // clock
    input  logic                       s_rst_n,    // synchronous reset
    input  logic [OP_A_W-1:0]          a,          // operand a
    input  logic [OP_B_W-1:0]          b,          // operand b
    output logic [OP_A_W + OP_B_W-1:0] z,          // result

    input  logic                       in_avail,   // Control signal
    output logic                       out_avail,

    input  logic [SIDE_W-1:0]          in_side,
    output logic [SIDE_W-1:0]          out_side
);

  import arith_mult_core_pkg::*;

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int LAT = get_latency() + IN_PIPE;

// ============================================================================================== //
// arith_mult_core
// ============================================================================================== //
  arith_mult_core #(
    .IN_PIPE  (IN_PIPE),
    .OP_A_W   (OP_A_W ),
    .OP_B_W   (OP_B_W )
  ) arith_mult_core (
    .clk     (clk    ),
    .a       (a      ),
    .b       (b      ),
    .z       (z      )
  );

// ============================================================================================== //
// Delay line
// ============================================================================================== //
  common_lib_delay_side #(
    .LATENCY    (LAT     ),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
                        
    .in_avail (in_avail ),
    .out_avail(out_avail),
                        
    .in_side  (in_side  ),
    .out_side (out_side )
  );

endmodule
