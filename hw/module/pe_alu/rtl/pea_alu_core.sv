// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Arithmmmetic logic unit processing element (PE).
// This module deals with reading in the regfile, et doing the ALU operation on the BLWE, before
// writing it back into the regfile.
//
//
//
// ==============================================================================================

module pea_alu_core
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import hpu_common_instruction_pkg::*;
#(
  parameter arith_mult_type_e MULT_TYPE = MULT_CORE,
  parameter int SIDE_W = 1
)
(
  input  logic                                   clk,        // clock
  input  logic                                   s_rst_n,    // synchronous reset

  input  logic [MOD_Q_W-1:0]                     in_a0,
  input  logic [MOD_Q_W-1:0]                     in_a1,
  input  logic [DOP_W-1:0]                       in_dop,
  input  logic [MSG_CST_W-1:0]                   in_msg_cst,
  input  logic [MUL_FACTOR_W-1:0]                in_mul_factor,
  input  logic [SIDE_W-1:0]                      in_side,
  input  logic                                   in_avail,

  output logic [MOD_Q_W-1:0]                     out_z,
  output logic [SIDE_W-1:0]                      out_side,
  output logic                                   out_avail
);

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
// Take advantage of this cycle to do the select of the arithmetic bloc inputs.
  logic [MOD_Q_W-1:0]      s0_mul_op0;
  logic [MUL_FACTOR_W-1:0] s0_mul_op1;
  logic [MOD_Q_W-1:0]      s0_add_op1;
  logic [DOP_W-1:0]        s0_dop;
  logic [SIDE_W-1:0]       s0_side;
  logic                    s0_avail;

  logic [MOD_Q_W-1:0]      in_msg_cst_ext;
  logic [MOD_Q_W-1:0]      in_mul_op0;
  logic [MOD_Q_W-1:0]      in_add_op1;
  logic [MUL_FACTOR_W-1:0] in_mul_op1;

  // Set the msg at the correct place in the body coefficient.
  // Note that if the coefficient is not the body, in_msg_cst should be null. 
  assign in_msg_cst_ext = in_msg_cst[USEFUL_BIT-1:0] << (MOD_Q_W-USEFUL_BIT);
  assign in_mul_op0 = (in_dop == DOP_SSUB) ? in_msg_cst_ext : in_a0;
  assign in_mul_op1 = (in_dop == DOP_MAC || in_dop == DOP_MULS) ? in_mul_factor : 1;
  always_comb
    case (in_dop)
      DOP_SSUB:
        in_add_op1 = in_a0;
      DOP_ADD, DOP_SUB, DOP_MAC:
        in_add_op1 = in_a1;
      DOP_ADDS, DOP_SUBS:
        in_add_op1 = in_msg_cst_ext;
      DOP_MULS:
        in_add_op1 = '0;
      default:
        in_add_op1 = 'x;
    endcase

  always_ff @(posedge clk) begin
    s0_mul_op0    <= in_mul_op0;
    s0_mul_op1    <= in_mul_op1;
    s0_add_op1    <= in_add_op1;
    s0_dop        <= in_dop;
    s0_side       <= in_side;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s0_avail <= 1'b0;
    else          s0_avail <= in_avail;

// ============================================================================================== --
// ALU
// ============================================================================================== --
  // The number of processing cycles is the same for all the operations.
  // This is done to avoid any race, between the operations.
  //-------------------------------
  // Multiplication with a scalar
  //-------------------------------
  logic [MOD_Q_W+MUL_FACTOR_W-1:0] s1_mul_res;
  logic [MOD_Q_W-1:0]   s1_mul_res_reduct;
  logic [MOD_Q_W-1:0]   s1_add_op1;
  logic [DOP_W-1:0]     s1_dop;
  logic [SIDE_W-1:0]    s1_side;
  logic                 s1_avail;

  arith_mult
  #(
    .OP_A_W         (MOD_Q_W),
    .OP_B_W         (MUL_FACTOR_W),
    .MULT_TYPE      (MULT_TYPE),
    .IN_PIPE        (1'b1), // TOREVIEW
    .SIDE_W         (SIDE_W + MOD_Q_W + DOP_W),
    .RST_SIDE       (2'b00)
  ) arith_mult (
    .clk      (clk),
    .s_rst_n  (s_rst_n),
    .a        (s0_mul_op0),
    .b        (s0_mul_op1),
    .z        (s1_mul_res),
    .in_avail (s0_avail),
    .out_avail(s1_avail),
    .in_side  ({s0_dop,s0_add_op1,s0_side}),
    .out_side ({s1_dop,s1_add_op1,s1_side})
  );

  // Since MOD_Q is a power of 2, the modular reduction is straight forward.
  assign s1_mul_res_reduct = s1_mul_res[MOD_Q_W-1:0];

  //-------------------------------
  // Addition / Subtraction
  //-------------------------------
  logic [MOD_Q_W:0]   s1_add_res;
  logic [MOD_Q_W:0]   s1_sub_res;

  assign s1_add_res = s1_mul_res_reduct + s1_add_op1;
  assign s1_sub_res = s1_mul_res_reduct - s1_add_op1;

  //-------------------------------
  // Mux
  //-------------------------------
  logic [MOD_Q_W:0]   s2_add_res;
  logic [MOD_Q_W:0]   s2_sub_res;
  logic               s2_avail;
  logic [SIDE_W-1:0]  s2_side;
  logic [DOP_W-1:0]   s2_dop;

  always_ff @(posedge clk) begin
    s2_add_res <= s1_add_res;
    s2_sub_res <= s1_sub_res;
    s2_side    <= s1_side;
    s2_dop     <= s1_dop;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s2_avail <= 1'b0;
    else          s2_avail <= s1_avail;

  logic [MOD_Q_W:0] s2_result;
  logic [MOD_Q_W-1:0] s2_result_reduct;

  assign s2_result = (s2_dop == DOP_SUBS || s2_dop == DOP_SSUB || s2_dop == DOP_SUB) ? s2_sub_res : s2_add_res;
  
  // Since MOD_Q is a power of 2, the modular reduction is straight forward
  assign s2_result_reduct = s2_result[MOD_Q_W-1:0];

// ============================================================================================== --
// Output
// ============================================================================================== --
  always_ff @(posedge clk) begin
    out_z    <= s2_result_reduct;
    out_side <= s2_side;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) out_avail <= 1'b0;
    else          out_avail <= s2_avail;

endmodule
