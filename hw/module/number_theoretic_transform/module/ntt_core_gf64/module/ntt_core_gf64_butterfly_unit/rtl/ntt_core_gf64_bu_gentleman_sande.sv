// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the Radix 2 decimation in frequency (Gentleman-Sande) NTT.
// The module is optimized for the prime GF64.
// Modular reductions are done partially, to save some logic.
//
// z_add = (a + b)               %pmr(MOD_NTT)
// z_sub = ((a - b) <<SHIFT_CST) %pmr(MOD_NTT)
//
// INVERSE
// z_sub = ((b - a) <<SHIFT_CST) %pmr(MOD_NTT)
// ==============================================================================================

module ntt_core_gf64_bu_gentleman_sande
#(
  parameter int    SHIFT_CST  = 3,
  parameter bit    SHIFT_CST_SIGN = 1'b0,
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

// ============================================================================================== //
// Input Pipe
// ============================================================================================== //
  logic [MOD_NTT_W+1:0] s0_a;
  logic [MOD_NTT_W+1:0] s0_b;
  logic                 s0_avail;
  logic [SIDE_W-1:0]    s0_side;

  generate
    if (IN_PIPE) begin: gen_in_pipe
      always_ff @(posedge clk) begin
        s0_a    <= a;
        s0_b    <= b;
      end

    end
    else begin : gen_no_in_pipe
      assign s0_a     = a;
      assign s0_b     = b;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE ),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail ),
    .out_avail(s0_avail),

    .in_side  (in_side  ),
    .out_side (s0_side  )
  );

// ============================================================================================== //
// Addition
// ============================================================================================== //
  logic [OP_W-1:0]   s1_add;
  logic              s1_avail;
  logic [SIDE_W-1:0] s1_side;

  ntt_core_gf64_pmr_add #(
    .MOD_NTT_W  (MOD_NTT_W),
    .OP_W       (OP_W),
    .IN_PIPE    (1'b0),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) ntt_core_gf64_pmr_add (
    .clk       (clk),
    .s_rst_n   (s_rst_n),

    .a         (s0_a),
    .b         (s0_b),
    .z         (s1_add),

    .in_avail  (s0_avail),
    .out_avail (s1_avail),
    .in_side   (s0_side),
    .out_side  (s1_side)
  );

// ============================================================================================== //
// Subtraction
// ============================================================================================== //
  logic [OP_W-1:0]   s1_sub;
  ntt_core_gf64_pmr_sub #(
    .MOD_NTT_W  (MOD_NTT_W),
    .OP_W       (OP_W),
    .INVERSE    (1'b0),
    .IN_PIPE    (1'b0),
    .SIDE_W     (0),     /*UNUSED*/
    .RST_SIDE   (2'b00) /*UNUSED*/
  ) ntt_core_gf64_pmr_sub (
    .clk       (clk),
    .s_rst_n   (s_rst_n),

    .a         (s0_a),
    .b         (s0_b),
    .z         (s1_sub),

    .in_avail  ('x), /*UNUSED*/
    .out_avail (/*UNUSED*/),
    .in_side   ('x),
    .out_side  (/*UNUSED*/)
  );

// ============================================================================================== //
// Shift
// ============================================================================================== //
  logic [OP_W-1:0]   s2_add;
  logic [OP_W-1:0]   s2_sub_shifted;
  logic              s2_avail;
  logic [SIDE_W-1:0] s2_side;

  logic [SIDE_W+OP_W-1:0] s1_side_ext;
  logic [SIDE_W+OP_W-1:0] s2_side_ext;

  generate
    if (SIDE_W > 0) begin
      assign s1_side_ext      = {s1_side,s1_add};
      assign {s2_side,s2_add} = s2_side_ext;
    end
    else begin
      assign s1_side_ext = s1_add;
      assign s2_add      = s2_side_ext;
    end

    if (DO_SHIFT) begin : gen_do_shift
      ntt_core_gf64_pmr_shift_cst #(
        .MOD_NTT_W (MOD_NTT_W),
        .OP_W      (OP_W),
        .CST       (SHIFT_CST),
        .CST_SIGN  (SHIFT_CST_SIGN),
        .IN_PIPE   (1'b0),
        .SIDE_W    (SIDE_W + OP_W),
        .RST_SIDE  (RST_SIDE)
      ) ntt_core_gf64_pmr_shift_cst (
        .clk       (clk),
        .s_rst_n   (s_rst_n),

        .a         (s1_sub),
        .z         (s2_sub_shifted),

        .in_avail  (s1_avail),
        .out_avail (s2_avail),
        .in_side   (s1_side_ext),
        .out_side  (s2_side_ext)
      );
    end
    else begin : gen_no_do_shift
      assign s2_sub_shifted = s1_sub;
      assign s2_avail       = s1_avail;
      assign s2_side_ext    = s1_side_ext;
    end
  endgenerate

// ============================================================================================== //
// Output
// ============================================================================================== //
  assign z_add     = s2_add;
  assign z_sub     = s2_sub_shifted;
  assign out_avail = s2_avail;
  assign out_side  = s2_side;

endmodule
