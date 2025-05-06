// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : mod_reduct_solinas2
// ----------------------------------------------------------------------------------------------
//
// Modular reduction with specific modulo value:
//  MOD_M = 2**MOD_W - 2**INT_POW + 1
//
// Some simplifications are made in the RTL that makes the support for all values
// with the form described above not possible.
// Indeed the wrap done to get e and f is only done once in the code.
// For some value of INT_POW, repetition of this wrapping is necessary. Particularly when
// (MOD_W-INT_POW) is small.
//
// Can deal with input up to 2*MOD_W+1 bits.
// This is the size of the sum of the 2 results of multiplication of 2
// values % MOD_M.
//
// LATENCY = IN_PIPE + $countone(LAT_PIPE_MH)
// ==============================================================================================

module mod_reduct_solinas2 #(
  parameter int          MOD_W      = 64,
  parameter [MOD_W-1:0]  MOD_M      = 2**MOD_W - 2**(MOD_W/2) + 1,
  parameter int          OP_W       = 2*MOD_W+1, // Should be in [MOD_W:2*MOD_W+1]
  parameter bit          IN_PIPE    = 1,
  parameter int          SIDE_W     = 0, // Side data size. Set to 0 if not used
  parameter [1:0]        RST_SIDE   = 0  // If side data is used,
                                         // [0] (1) reset them to 0.
                                         // [1] (1) reset them to 1.
)
(
  // System interface
  input  logic               clk,
  input  logic               s_rst_n,
  // Data interface
  input  logic [OP_W-1:0]    a,
  output logic [MOD_W-1:0]   z,
  // Control + side interface - optional
  input  logic               in_avail,
  output logic               out_avail,

  input  logic [SIDE_W-1:0]  in_side,
  output logic [SIDE_W-1:0]  out_side

);
  // ============================================================================================ //
  // Localparam
  // ============================================================================================ //
  // Since MOD_M has the following form: 
  // MOD_M = 2**MOD_W - 2**INT_POW + 1
  // We can retreive INT_POW

  localparam int INT_POW   = $clog2(2**MOD_W+1 - MOD_M);
  localparam bit USE_HALF  = 1'b0; // (INT_POW <= MOD_W/2) && (OP_W <= 2*MOD_W);

  // ============================================================================================ //
  // Instances
  // ============================================================================================ //
  generate
    if (USE_HALF) begin : gen_half
      mod_reduct_solinas2_half #(
        .MOD_W        (MOD_W),
        .MOD_M        (MOD_M),
        .OP_W         (OP_W),
        .IN_PIPE      (IN_PIPE),
        .SIDE_W       (SIDE_W),
        .RST_SIDE     (RST_SIDE)
      ) mod_reduct_solinas2_half (
        .clk      (clk      ),
        .s_rst_n  (s_rst_n  ),
        .a        (a        ),
        .z        (z        ),
        .in_avail (in_avail ),
        .out_avail(out_avail),
        .in_side  (in_side  ),
        .out_side (out_side )
      );
    end
    else begin : gen_general // for the solinas2 general case
      mod_reduct_solinas2_general #(
        .MOD_W        (MOD_W),
        .MOD_M        (MOD_M),
        .OP_W         (OP_W),
        .IN_PIPE      (IN_PIPE),
        .SIDE_W       (SIDE_W),
        .RST_SIDE     (RST_SIDE)
      ) mod_reduct_solinas2_general (
        .clk      (clk      ),
        .s_rst_n  (s_rst_n  ),
        .a        (a        ),
        .z        (z        ),
        .in_avail (in_avail ),
        .out_avail(out_avail),
        .in_side  (in_side  ),
        .out_side (out_side )
      );
    end
  endgenerate


endmodule
