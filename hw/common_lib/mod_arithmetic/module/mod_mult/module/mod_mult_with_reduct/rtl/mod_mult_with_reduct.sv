// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : mod_mult_with_reduct
// ----------------------------------------------------------------------------------------------
//
// Modular multiplier which architecture is
//   - a full arithmetic multiplication
//   - followed by a modular reduction on the result.
//
// Supported MOD_MULT_TYPE
//   MERSENNE
//   BARRETT
//   SOLINAS2
//   GOLDILOCKS
//
// ==============================================================================================

module mod_mult_with_reduct
  import common_definition_pkg::*;
#(
  parameter mod_mult_type_e MOD_MULT_TYPE = MOD_MULT_GOLDILOCKS,
  parameter int          MOD_W         = 64,
  parameter [MOD_W-1:0]  MOD_M         = 2**MOD_W - 2**(MOD_W/2) + 1,
  parameter arith_mult_type_e MULT_TYPE= MULT_GOLDILOCKS,
  parameter bit          IN_PIPE       = 1,
  parameter int          SIDE_W        = 0, // Side data size. Set to 0 if not used
  parameter [1:0]        RST_SIDE      = 0  // If side data is used,
                                            // [0] (1) reset them to 0.
                                            // [1] (1) reset them to 1.
)
(
  // System interface
  input               clk,
  input               s_rst_n,
  // Data interface
  input  [MOD_W-1:0]  a,
  input  [MOD_W-1:0]  b,
  output [MOD_W-1:0]  z,
  // Control interface
  input               in_avail,
  output              out_avail,
  input  [SIDE_W-1:0] in_side,
  output [SIDE_W-1:0] out_side

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam mod_reduct_type_e REDUCT_TYPE = get_mod_reduct(MOD_MULT_TYPE);

// ============================================================================================== --
// Multiplication
// ============================================================================================== --
  logic [2*MOD_W-1:0] s0_mult_result;
  logic               s0_avail;
  logic [SIDE_W-1:0]  s0_side;
  arith_mult #(
    .OP_A_W         (MOD_W),
    .OP_B_W         (MOD_W),
    .MULT_TYPE      (MULT_TYPE),
    .IN_PIPE        (IN_PIPE),
    .SIDE_W         (SIDE_W),
    .RST_SIDE       (RST_SIDE)
  ) arith_mult (
    .clk       (clk),
    .s_rst_n   (s_rst_n),
    .a         (a),
    .b         (b),
    .z         (s0_mult_result),
    .in_avail  (in_avail),
    .out_avail (s0_avail),
    .in_side   (in_side),
    .out_side  (s0_side)
  );

// ============================================================================================== --
// Reduction
// ============================================================================================== --
  mod_reduct #(
    .REDUCT_TYPE (REDUCT_TYPE),
    .MOD_W       (MOD_W),
    .MOD_M       (MOD_M),
    .OP_W        ($size(s0_mult_result)),
    .MULT_TYPE   (MULT_TYPE),
    .IN_PIPE     (1),
    .SIDE_W      (SIDE_W),
    .RST_SIDE    (RST_SIDE)
  ) mod_reduct ( 
    .clk       (clk),
    .s_rst_n   (s_rst_n),
    .a         (s0_mult_result),
    .z         (z),
    .in_avail  (s0_avail),
    .out_avail (out_avail),
    .in_side   (s0_side),
    .out_side  (out_side)
  );

endmodule
