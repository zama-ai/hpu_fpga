// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with 1 processing stage column of the INTT.
// The module is optimized for the prime GF64.
// Modular reductions are done partially, to save some logic.
//
// 1 column consists in:
// * a column of Radix-2 butterfly units
// * a network at the input and output, to order coef as in a regular butterfly Rev->Nat
//   for stage NTT_STG_ID.
//
// ==============================================================================================

module ntt_core_gf64_bu_stage_column_bwd
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
#(
  parameter int    NTT_STG_ID = 0,    // decreasing numbering
  parameter bit    IN_PIPE    = 1'b1, // Recommended
  parameter int    SIDE_W     = 0, // Side data size. Set to 0 if not used
  parameter [1:0]  RST_SIDE   = 0  // If side data is used,
                                  // [0] (1) reset them to 0.
                                  // [1] (1) reset them to 1.

)
(
  input  logic                            clk,        // clock
  input  logic                            s_rst_n,    // synchronous reset

  input  logic [PSI*R-1:0][MOD_NTT_W+1:0] in_data,
  output logic [PSI*R-1:0][MOD_NTT_W+1:0] out_data,
  input  logic [PSI*R-1:0]                in_avail,
  output logic [PSI*R-1:0]                out_avail,
  input  logic [SIDE_W-1:0]               in_side,
  output logic [SIDE_W-1:0]               out_side
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int OP_W = MOD_NTT_W + 2;
  localparam int C    = PSI*R;

  localparam int RDX_LOG = NTT_STG_RDX_ID[NTT_STG_ID];
  localparam int RDX     = 2**RDX_LOG;

  localparam int RDX_NB  = C / RDX;
  localparam int BU_NB   = C / 2;

  localparam bit               IS_NGC   = NTT_STG_IS_NGC[NTT_STG_ID];
  localparam [32-1:0][31:0] OMG_2POW_TMP = IS_NGC ? {2{INTT_GF64_NGC_OMG_2POW[RDX_LOG]}} : // NGC max size is 32
                                                    INTT_GF64_CYC_OMG_2POW[RDX_LOG]; // CYC max size is 64
  localparam [BU_NB-1:0][31:0] OMG_2POW = get_omg_2pow(OMG_2POW_TMP);

  localparam bit DO_SHIFT = IS_NGC || (RDX_LOG > 1);


// pragma translate_off
  generate
    if (RDX > C) begin : __UNSUPPORTED_NTT_PARTITION
      $fatal(1,"> ERROR: Unsupported NTT partition. radix block size (%0d) used should be less or equal to R*PSI (%0d)",RDX,C);
    end
  endgenerate
// pragma translate_on

// ============================================================================================== //
// functions
// ============================================================================================== //
  function [BU_NB-1:0][31:0] get_omg_2pow (input [32-1:0][31:0] omg_2pow_tmp);
    for (int i=0; i<BU_NB; i=i+1)
      get_omg_2pow[i] = omg_2pow_tmp[i%32];
  endfunction

// ============================================================================================== //
// s0
// ============================================================================================== //
// Order data for processing
  logic [RDX_NB-1:0][RDX/2-1:0][1:0][OP_W-1:0] s0_data_a;
  logic [RDX_NB-1:0][RDX/2-1:0][1:0]           s0_avail_a;
  logic [RDX_NB-1:0][1:0][RDX/2-1:0][OP_W-1:0] in_data_a;
  logic [RDX_NB-1:0][1:0][RDX/2-1:0]           in_avail_a;

  assign in_data_a  = in_data;
  assign in_avail_a = in_avail;

  always_comb
    for (int r=0; r<RDX_NB; r=r+1)
      for (int c=0; c<RDX/2; c=c+1)
        for (int i=0; i<2; i=i+1) begin
          s0_data_a[r][c][i]  = in_data_a[r][i][c];
          s0_avail_a[r][c][i] = in_avail_a[r][i][c];
        end

  // rename
  logic [SIDE_W-1:0]  s0_side;

  assign s0_side  = in_side;

// ============================================================================================== //
// Butterfly units
// ============================================================================================== //
// Use Gentleman-Sande, since the order is Nat->Rev
// Note that here the omegas are negative values. Therefore, if there is a multiplication to be done,
// the subtraction that preceeds is inversed.
  logic [BU_NB-1:0][1:0][OP_W-1:0] s0_data;
  logic [BU_NB-1:0][1:0]           s0_avail;
  logic [BU_NB-1:0][1:0][OP_W-1:0] s1_data;
  logic [BU_NB-1:0][1:0]           s1_avail;
  logic [SIDE_W-1:0]               s1_side;

  assign s0_data  = s0_data_a;
  assign s0_avail = s0_avail_a;

  generate
    for (genvar gen_b=0; gen_b<BU_NB; gen_b=gen_b+1) begin : gen_bu_loop
      assign s1_avail[gen_b][1] = s1_avail[gen_b][0];
      if (gen_b == 0) begin : gen_0
        ntt_core_gf64_bu_gentleman_sande
        #(
            .SHIFT_CST (OMG_2POW[gen_b]),
            .SHIFT_CST_SIGN (OMG_2POW[gen_b] > 0),
            .MOD_NTT_W (MOD_NTT_W),
            .DO_SHIFT  (DO_SHIFT),
            .IN_PIPE   (IN_PIPE),
            .SIDE_W    (SIDE_W),
            .RST_SIDE  (RST_SIDE)
        ) ntt_core_gf64_bu_gentleman_sande  (
            .clk       (clk),
            .s_rst_n   (s_rst_n),

            .a         (s0_data[gen_b][0]),
            .b         (s0_data[gen_b][1]),
            .z_add     (s1_data[gen_b][0]),
            .z_sub     (s1_data[gen_b][1]),
            .in_avail  (s0_avail[gen_b][0]),
            .out_avail (s1_avail[gen_b][0]),
            .in_side   (s0_side),
            .out_side  (s1_side)
        );
      end
      else begin : gen_not_0
        ntt_core_gf64_bu_gentleman_sande
        #(
            .SHIFT_CST (OMG_2POW[gen_b]),
            .SHIFT_CST_SIGN (OMG_2POW[gen_b] > 0),
            .MOD_NTT_W (MOD_NTT_W),
            .DO_SHIFT  (DO_SHIFT),
            .IN_PIPE   (IN_PIPE),
            .SIDE_W    (0),
            .RST_SIDE  (2'b00)
        ) ntt_core_gf64_bu_gentleman_sande  (
            .clk       (clk),
            .s_rst_n   (s_rst_n),

            .a         (s0_data[gen_b][0]),
            .b         (s0_data[gen_b][1]),
            .z_add     (s1_data[gen_b][0]),
            .z_sub     (s1_data[gen_b][1]),
            .in_avail  (s0_avail[gen_b][0]),
            .out_avail (s1_avail[gen_b][0]),
            .in_side   ('x), /*UNUSED*/
            .out_side  (/*UNUSED*/)
        );
      end
    end // gen_bu_loop
  endgenerate

// ============================================================================================== //
// Output
// ============================================================================================== //
// Order data for output
  logic [RDX_NB-1:0][RDX/2-1:0][1:0][OP_W-1:0] s1_data_a;
  logic [RDX_NB-1:0][RDX/2-1:0][1:0]           s1_avail_a;
  logic [RDX_NB-1:0][1:0][RDX/2-1:0][OP_W-1:0] out_data_a;
  logic [RDX_NB-1:0][1:0][RDX/2-1:0]           out_avail_a;

  assign s1_data_a  = s1_data;
  assign s1_avail_a = s1_avail;

  always_comb
    for (int r=0; r<RDX_NB; r=r+1)
      for (int c=0; c<RDX/2; c=c+1)
        for (int i=0; i<2; i=i+1) begin
          out_data_a[r][i][c]  = s1_data_a[r][c][i];
          out_avail_a[r][i][c] = s1_avail_a[r][c][i];
        end

  // rename
  assign out_data  = out_data_a;
  assign out_avail = out_avail_a;
  assign out_side  = s1_side;

endmodule
