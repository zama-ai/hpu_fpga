// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Modular multiplier wrapper
// ----------------------------------------------------------------------------------------------
//
// This module implements a modular multiplication.
// According to MOD_MULT_TYPE, an architecture is chosen.
// Supported MOD_MULT_TYPE:
//   - "MERSENNE" : Mersenne modulo
//                  MOD_M should have this format : 2**XX - 1
//                  where XX id MOD_W
//   - "BARRETT"
//   - "SOLINAS2" : Solinas modulo with 2 exponents.
//                  MOD_M should have this format : 2**XX - 2**YY + 1
//                  XX is the highest exponent of the solinas modulo. Should be MOD_W.
//                  YY is the second exponent.
//   - "SOLINAS3" : Solinas modulo with 3 exponents.
//                  MOD_M should have this format : 2**XX - 2**YY - 2**ZZ + 1
//                  XX is the highest exponent of the solinas modulo. Should be MOD_W.
//                  YY is the second exponent.
//                  ZZ is the third exponent.
//   - "GOLDILOCKS" : Goldilocks prime 2**64 - 2**32 + 1
//                    Modular reduction uses Goldilocks prime specific optimisations.
//
// For 64x64-bit multiplication, set MULT_TYPE to:
//   - "MULT_GOLDILOCKS" : Multiplier that outputs 98-bit instead of 128-bit values.
//
// ==============================================================================================

module mod_mult
  import common_definition_pkg::*;
#(
  parameter mod_mult_type_e MOD_MULT_TYPE = MOD_MULT_GOLDILOCKS,
  parameter int          MOD_W         = 64,
  parameter [MOD_W-1:0]  MOD_M         = 2**MOD_W - 2**(MOD_W/2) + 1,
  parameter arith_mult_type_e       MULT_TYPE     = MULT_GOLDILOCKS,
  parameter bit          IN_PIPE       = 1,
  parameter int          SIDE_W        = 0, // Side data size. Set to 0 if not used
  parameter [1:0]        RST_SIDE      = 0  // If side data is used,
                                            // [0] (1) reset them to 0.
                                            // [1] (1) reset them to 1.

) (
  // System interface
  input                clk,
  input                s_rst_n,
  // Data interface
  input  [MOD_W-1:0]   a,
  input  [MOD_W-1:0]   b,
  output [MOD_W-1:0]   z,
  // Control + side interface - optional
  input                in_avail,
  output               out_avail,
  input  [SIDE_W-1:0]  in_side,
  output [SIDE_W-1:0]  out_side
);

  generate
    if (MOD_MULT_TYPE == MOD_MULT_MERSENNE
       || MOD_MULT_TYPE == MOD_MULT_BARRETT
       || MOD_MULT_TYPE == MOD_MULT_SOLINAS2
       || MOD_MULT_TYPE == MOD_MULT_SOLINAS3
       || MOD_MULT_TYPE == MOD_MULT_GOLDILOCKS ) begin : gen_mod_mult_with_reduct
      mod_mult_with_reduct #(
        .MOD_MULT_TYPE (MOD_MULT_TYPE),
        .MOD_W         (MOD_W),
        .MOD_M         (MOD_M),
        .MULT_TYPE     (MULT_TYPE),
        .IN_PIPE       (IN_PIPE),
        .SIDE_W        (SIDE_W),
        .RST_SIDE      (RST_SIDE)
      ) mod_mult (
        .clk      (clk),
        .s_rst_n  (s_rst_n),
        .a        (a),
        .b        (b),
        .z        (z),
        .in_avail (in_avail),
        .out_avail(out_avail),
        .in_side  (in_side),
        .out_side (out_side)
      );
    end
    else begin : __UNKNOWN_MOD_MULT_TYPE__
      $fatal(1, "> ERROR: Unknown MOD_MULT_TYPE %s", MOD_MULT_TYPE);
    end
  endgenerate
endmodule
