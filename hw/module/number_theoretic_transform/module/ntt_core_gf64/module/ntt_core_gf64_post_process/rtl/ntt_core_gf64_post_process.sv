// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the post-process computation in GF64 domain.
// Modular reductions are partial.
// To ease the P&R the GLWE_K_P1 coef of the BSK for 1 data are sent each delayed by 1 cycle.
// ==============================================================================================

module ntt_core_gf64_post_process
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
#(
  parameter arith_mult_type_e MULT_TYPE = MULT_CORE,
  parameter bit               IN_PIPE   = 1'b1
)
(
  input  logic                                                clk,        // clock
  input  logic                                                s_rst_n,    // synchronous reset

  input  logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0]                in_data,
  input  logic [PSI-1:0][R-1:0]                               in_avail,
  input  logic                                                in_sob,
  input  logic                                                in_eob,
  input  logic                                                in_sol,
  input  logic                                                in_eol,
  input  logic                                                in_sos,
  input  logic                                                in_eos,
  input  logic [BPBS_ID_W-1:0]                                in_pbs_id,

  output logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0]                out_data,
  output logic [PSI-1:0][R-1:0]                               out_avail,
  output logic                                                out_sob,
  output logic                                                out_eob,
  output logic                                                out_sol,
  output logic                                                out_eol,
  output logic                                                out_sos,
  output logic                                                out_eos,
  output logic [BPBS_ID_W-1:0]                                out_pbs_id,

  // Matrix factors : BSK
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][MOD_NTT_W-1:0] bsk,
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                bsk_vld,
  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                bsk_rdy,

  output logic                                                error
);

// ============================================================================================== --
// Instance
// ============================================================================================== --
  logic [PSI-1:0][R-1:0]                 error_a;
  logic [PSI-1:0][R-1:0]                 out_sob_a;
  logic [PSI-1:0][R-1:0]                 out_eob_a;
  logic [PSI-1:0][R-1:0]                 out_sol_a;
  logic [PSI-1:0][R-1:0]                 out_eol_a;
  logic [PSI-1:0][R-1:0]                 out_sos_a;
  logic [PSI-1:0][R-1:0]                 out_eos_a;
  logic [PSI-1:0][R-1:0][BPBS_ID_W-1:0]  out_pbs_id_a;
  generate
    for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin : gen_psi_loop
      for (genvar gen_r=0; gen_r<R; gen_r=gen_r+1) begin : gen_r_loop
        if (gen_p==0 && gen_r==0) begin : gen_0
          ntt_core_gf64_pp_core
          #(
            .MOD_NTT_W (MOD_NTT_W),
            .MULT_TYPE (MULT_TYPE),
            .IN_PIPE   (IN_PIPE)
          ) ntt_core_gf64_pp_core (
            .clk        (clk),
            .s_rst_n    (s_rst_n),

            .in_data    (in_data[gen_p][gen_r]),
            .in_avail   (in_avail[gen_p][gen_r]),
            .in_sob     (in_sob),
            .in_eob     (in_eob),
            .in_sol     (in_sol),
            .in_eol     (in_eol),
            .in_sos     (in_sos),
            .in_eos     (in_eos),
            .in_pbs_id  (in_pbs_id),

            .out_data   (out_data[gen_p][gen_r]),
            .out_avail  (out_avail[gen_p][gen_r]),
            .out_sob    (out_sob),
            .out_eob    (out_eob),
            .out_sol    (out_sol),
            .out_eol    (out_eol),
            .out_sos    (out_sos),
            .out_eos    (out_eos),
            .out_pbs_id (out_pbs_id),

            .bsk        (bsk[gen_p][gen_r]),
            .bsk_vld    (bsk_vld[gen_p][gen_r]),
            .bsk_rdy    (bsk_rdy[gen_p][gen_r]),

            .error      (error_a[gen_p][gen_r])
          );
        end
        else begin : gen_no_0
          ntt_core_gf64_pp_core
          #(
            .MOD_NTT_W (MOD_NTT_W),
            .MULT_TYPE (MULT_TYPE),
            .IN_PIPE   (IN_PIPE)
          ) ntt_core_gf64_pp_core (
            .clk        (clk),
            .s_rst_n    (s_rst_n),

            .in_data    (in_data[gen_p][gen_r]),
            .in_avail   (in_avail[gen_p][gen_r]),
            .in_sob     ('x), /*UNUSED*/
            .in_eob     ('x), /*UNUSED*/
            .in_sol     (in_sol),
            .in_eol     (in_eol),
            .in_sos     ('x), /*UNUSED*/
            .in_eos     ('x), /*UNUSED*/
            .in_pbs_id  ('x), /*UNUSED*/

            .out_data   (out_data[gen_p][gen_r]),
            .out_avail  (out_avail[gen_p][gen_r]),
            .out_sob    (/*UNUSED*/),
            .out_eob    (/*UNUSED*/),
            .out_sol    (/*UNUSED*/),
            .out_eol    (/*UNUSED*/),
            .out_sos    (/*UNUSED*/),
            .out_eos    (/*UNUSED*/),
            .out_pbs_id (/*UNUSED*/),

            .bsk        (bsk[gen_p][gen_r]),
            .bsk_vld    (bsk_vld[gen_p][gen_r]),
            .bsk_rdy    (bsk_rdy[gen_p][gen_r]),

            .error      (error_a[gen_p][gen_r])
          );
        end
      end
    end // gen_psi_loop
  endgenerate

// ============================================================================================== --
// Error
// ============================================================================================== --
  logic errorD;

  assign errorD = |error_a;

  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= errorD;

endmodule
