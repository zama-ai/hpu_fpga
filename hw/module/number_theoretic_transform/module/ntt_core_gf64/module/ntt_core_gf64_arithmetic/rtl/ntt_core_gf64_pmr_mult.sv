// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs a modular multiplication in goldilocks 64 field.
// ----------------------------------------------------------------------------------------------
//
// Performs a multiplication z = a * b followed by a partial reduction in GF64.
//
// GF64 prime is a solinas2 with this form :
// 2**MOD_NTT_W - 2**(MOD_NTT_W/2) + 1
// with MOD_NTT_W an even number.
//
// The following property is used here :
// 2**MOD_NTT_W = 2**(MOD_NTT_W/2) - 1
//
// Then the reduction of all the bits above MOD_NTT_W is done using the property above.
// The result a signed number with MOD_NTT_W + 1 + 1b sign bits.
//
// Note that the inputs are 2s complement numbers.
// ==============================================================================================

module ntt_core_gf64_pmr_mult
  import common_definition_pkg::*;
#(
  parameter int            MOD_NTT_W = 64, // Should be 64 for GF64. Mainly used in verification
                                           // Should be even
  parameter int            OP_W      = MOD_NTT_W + 1 + 1, // 1 additional bit + 1bit of sign. Data are in 2s complement.
  parameter arith_mult_type_e MULT_TYPE = MULT_CORE,
  parameter bit            IN_PIPE   = 1'b1, // Recommended
  parameter int            SIDE_W    = 0, // Side data size. Set to 0 if not used
  parameter [1:0]          RST_SIDE  = 0  // If side data is used,
                                          // [0] (1) reset them to 0.
                                          // [1] (1) reset them to 1.
) (
  // System interface
  input  logic                 clk,
  input  logic                 s_rst_n,

  // Data interface
  input  logic [OP_W-1:0]      a, // 2s complement
  output logic [MOD_NTT_W+1:0] z, // 2s complement

  // multiplication factor
  input  logic [MOD_NTT_W-1:0] m, // unsigned
  input  logic                 m_vld,
  output logic                 m_rdy,

  // Control + side interface - optional
  input  logic                 in_avail,
  output logic                 out_avail,
  input  logic [SIDE_W-1:0]    in_side,
  output logic [SIDE_W-1:0]    out_side
);

// ============================================================================================== //
// Signals
// ============================================================================================== //
    logic [MOD_NTT_W:0]   s0_u_data; //unsigned
    logic                 s0_avail;
    logic [SIDE_W-1:0]    s0_side;

    logic [2*MOD_NTT_W:0] s1_u_mult_data; //unsigned
    logic                 s1_avail;
    logic [SIDE_W-1:0]    s1_side;

    logic [MOD_NTT_W+1:0] s2_result;
    logic                 s2_avail;
    logic [SIDE_W-1:0]    s2_side;

// ============================================================================================== //
// Instances
// ============================================================================================== //
    // Reduce the sign
    ntt_core_gf64_pmr_sign #(
      .MOD_NTT_W (MOD_NTT_W),
      .OP_W      (OP_W),
      .IN_PIPE   (IN_PIPE),
      .SIDE_W    (SIDE_W),
      .RST_SIDE  (RST_SIDE)
    ) ntt_core_gf64_pmr_sign (
      // System interface
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .a         (a),
      .z         (s0_u_data),

      .in_avail  (in_avail),
      .out_avail (s0_avail),
      .in_side   (in_side),
      .out_side  (s0_side)
    );

    // Multiplication
    arith_mult #(
      .OP_A_W         (MOD_NTT_W+1),
      .OP_B_W         (MOD_NTT_W),
      .MULT_TYPE      (MULT_TYPE),
      .IN_PIPE        (1'b1), // Use DSP input pipe
      .SIDE_W         (SIDE_W),
      .RST_SIDE       (RST_SIDE)
    ) arith_mult (
      .clk      (clk),
      .s_rst_n  (s_rst_n),

      .a        (s0_u_data),
      .b        (m),
      .z        (s1_u_mult_data),

      .in_avail (s0_avail),
      .out_avail(s1_avail),
      .in_side  (s0_side),
      .out_side (s1_side)
    );

    // Partial modular reduction
    ntt_core_gf64_pmr_reduction #(
      .MOD_NTT_W (MOD_NTT_W),
      .OP_W      (2*MOD_NTT_W+1),
      .IN_PIPE   (1'b1),
      .SIDE_W    (SIDE_W),
      .RST_SIDE  (RST_SIDE)
    ) ntt_core_gf64_pmr_reduction (
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .a         (s1_u_mult_data),
      .z         (z),

      .in_avail  (s1_avail),
      .out_avail (out_avail),
      .in_side   (s1_side),
      .out_side  (out_side)
    );

// ============================================================================================== //
// rdy/vld
// ============================================================================================== //
  assign m_rdy = s0_avail;

//pragma translate_off
  always_ff @(posedge clk)
    if (s0_avail)
      assert(m_vld)
      else begin
        $fatal(1,"%t > ERROR: PMR multiplication factor not available when needed!", $time);
      end
//pragma translate_on
endmodule
