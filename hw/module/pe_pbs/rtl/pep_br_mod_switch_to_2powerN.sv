// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module contains the modulo switch operation from MOD_NTT to MOD_Q.
// Note that MOD_Q is a power of 2.
// ==============================================================================================

module pep_br_mod_switch_to_2powerN
  import mod_switch_to_2powerN_pkg::*;
  import common_definition_pkg::*;
#(
  parameter int               R              = 2,
  parameter int               PSI            = 8,
  parameter int               MOD_Q_W        = 32,  // Width of Modulo q
  parameter int               MOD_NTT_W      = 32,  // Width of Modulo p
  parameter [MOD_NTT_W-1:0]   MOD_NTT        = 2 ** 32 - 2 ** 17 - 2 ** 13 + 1,
  parameter int_type_e        MOD_NTT_INV_TYPE = INT_UNKNOWN, // If the inverse is of a particular type, this could accelerate the mult
  parameter arith_mult_type_e MULT_TYPE      = MULT_KARATSUBA, // in case there is no acceleration for x MOD_P_INV
  parameter int               PRECISION_W    = 33,
  parameter bit               IN_PIPE        = 1'b1,
  parameter int               SIDE_W         = 0,// Side data size. Set to 0 if not used
  parameter [1:0]             RST_SIDE       = 0 // If side data is used,
                                             // [0] (1) reset them to 0.
                                             // [1] (1) reset them to 1.
)
(
  input  logic                                 clk,        // clock
  input  logic                                 s_rst_n,    // synchronous reset
  input  logic [PSI-1:0][R-1:0][MOD_NTT_W-1:0] a,
  output logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]   z,
  input  logic [PSI-1:0][R-1:0]                in_avail,
  output logic [PSI-1:0][R-1:0]                out_avail,
  input  logic [SIDE_W-1:0]                    in_side,
  output logic [SIDE_W-1:0]                    out_side
);

  generate
    for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin : gen_modw_p_loop
      for (genvar gen_r=0; gen_r<R; gen_r=gen_r+1) begin : gen_modw_r_loop
        if (gen_p==0 && gen_r==0) begin : gen_modsw_inst_0
          mod_switch_to_2powerN
          #(
            .MOD_Q_W        (MOD_Q_W),
            .MOD_P_W        (MOD_NTT_W),
            .MOD_P          (MOD_NTT),
            .MOD_P_INV_TYPE (MOD_NTT_INV_TYPE),
            .MULT_TYPE      (MULT_TYPE),
            .PRECISION_W    (PRECISION_W),
            .IN_PIPE        (IN_PIPE),
            .SIDE_W         (SIDE_W),
            .RST_SIDE       (RST_SIDE)
          ) mod_switch_to_2powerN (
            .clk       (clk),
            .s_rst_n   (s_rst_n),
            .a         (a[gen_p][gen_r]),
            .z         (z[gen_p][gen_r]),
            .in_avail  (in_avail[gen_p][gen_r]),
            .out_avail (out_avail[gen_p][gen_r]),
            .in_side   (in_side),
            .out_side  (out_side)
          );
        end
        else begin : gen_modsw_inst_gt_0
          mod_switch_to_2powerN
          #(
            .MOD_Q_W        (MOD_Q_W),
            .MOD_P_W        (MOD_NTT_W),
            .MOD_P          (MOD_NTT),
            .MOD_P_INV_TYPE (MOD_NTT_INV_TYPE),
            .MULT_TYPE      (MULT_TYPE),
            .PRECISION_W    (PRECISION_W),
            .IN_PIPE        (IN_PIPE),
            .SIDE_W         (0),
            .RST_SIDE       (2'b00)
          ) mod_switch_to_2powerN (
            .clk       (clk),
            .s_rst_n   (s_rst_n),
            .a         (a[gen_p][gen_r]),
            .z         (z[gen_p][gen_r]),
            .in_avail  (in_avail[gen_p][gen_r]),
            .out_avail (out_avail[gen_p][gen_r]),
            .in_side   ('x), // UNUSED
            .out_side  (/*UNUSED*/)
          );
        end
      end
    end
  endgenerate

endmodule
