// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the Radix 2 decimation in time (Cooley-Tukey) NTT.
// The module is optimized for the prime GF64.
// Modular reductions are done partially, to save some logic.
//
// z_add = (a + (b<<SHIFT_CST) %pmr(MOD_NTT))  %pmr(MOD_NTT)
// z_sub = (a - (b<<SHIFT_CST) %pmr(MOD_NTT))  %pmr(MOD_NTT)
// ==============================================================================================

module ntt_core_gf64_bu_cooley_tukey
#(
  parameter int    SHIFT_CST  = 3,
  parameter int    MOD_NTT_W  = 64,
  parameter bit    IN_PIPE    = 1'b1, // Recommended
  parameter bit    DO_SHIFT   = 1'b1, // (0) skip the shift
  parameter int    SIDE_W     = 0, // Side data size. Set to 0 if not used
  parameter [1:0]  RST_SIDE   = 0  // If side data is used,
                                   // [0] (1) reset them to 0.
                                   // [1] (1) reset them to 1.
)
(
  input  logic                 clk,        // clock
  input  logic                 s_rst_n,    // synchronous reset

  input  logic [MOD_NTT_W+1:0] a,      // 2s compl
  input  logic [MOD_NTT_W+1:0] b,      // "
  output logic [MOD_NTT_W+1:0] z_add,  // "
  output logic [MOD_NTT_W+1:0] z_sub,   // "
  input  logic                 in_avail,
  output logic                 out_avail,
  input  logic [SIDE_W-1:0]    in_side,
  output logic [SIDE_W-1:0]    out_side
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int OP_W = MOD_NTT_W + 2;

  // since ntt_core_gf64_pmr_shift_cst outputs on register
  localparam bit INTERN_PIPE = DO_SHIFT ? 1'b0 : IN_PIPE;

// ============================================================================================== //
// Shift
// ============================================================================================== //
  logic [OP_W-1:0]   s0_a;
  logic [OP_W-1:0]   s0_b_shifted;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;

  logic [SIDE_W+OP_W-1:0] in_side_ext;
  logic [SIDE_W+OP_W-1:0] s0_side_ext;

  generate
    if (SIDE_W > 0) begin
      assign in_side_ext    = {in_side,a};
      assign {s0_side,s0_a} = s0_side_ext;
    end
    else begin
      assign in_side_ext = a;
      assign s0_a        = s0_side_ext;
    end

    if (DO_SHIFT) begin : gen_do_shift
      ntt_core_gf64_pmr_shift_cst #(
        .MOD_NTT_W (MOD_NTT_W),
        .OP_W      (OP_W),
        .CST       (SHIFT_CST),
        .CST_SIGN  (1'b0),
        .IN_PIPE   (IN_PIPE),
        .SIDE_W    (SIDE_W + OP_W),
        .RST_SIDE  (RST_SIDE)
      ) ntt_core_gf64_pmr_shift_cst (
        .clk       (clk),
        .s_rst_n   (s_rst_n),

        .a         (b),
        .z         (s0_b_shifted),

        .in_avail  (in_avail),
        .out_avail (s0_avail),
        .in_side   (in_side_ext),
        .out_side  (s0_side_ext)
      );
    end
    else begin : gen_no_do_shift
      assign s0_b_shifted = b;
      assign s0_avail     = in_avail;
      assign s0_side_ext  = in_side_ext;
    end
  endgenerate
// ============================================================================================== //
// Addition
// ============================================================================================== //
  ntt_core_gf64_pmr_add #(
    .MOD_NTT_W  (MOD_NTT_W),
    .OP_W       (OP_W),
    .IN_PIPE    (INTERN_PIPE),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) ntt_core_gf64_pmr_add (
    .clk       (clk),
    .s_rst_n   (s_rst_n),

    .a         (s0_a),
    .b         (s0_b_shifted),
    .z         (z_add),

    .in_avail  (s0_avail),
    .out_avail (out_avail),
    .in_side   (s0_side),
    .out_side  (out_side)
  );

// ============================================================================================== //
// Subtraction
// ============================================================================================== //
  ntt_core_gf64_pmr_sub #(
    .MOD_NTT_W  (MOD_NTT_W),
    .OP_W       (OP_W),
    .INVERSE    (1'b0),
    .IN_PIPE    (INTERN_PIPE),
    .SIDE_W     (0),     /*UNUSED*/
    .RST_SIDE   (2'b00) /*UNUSED*/
  ) ntt_core_gf64_pmr_sub (
    .clk       (clk),
    .s_rst_n   (s_rst_n),

    .a         (s0_a),
    .b         (s0_b_shifted),
    .z         (z_sub),

    .in_avail  ('x), /*UNUSED*/
    .out_avail (/*UNUSED*/),
    .in_side   ('x),
    .out_side  (/*UNUSED*/)
  );

endmodule
