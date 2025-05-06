// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the post-processing:
//   - At the end of the FWD NTT : matrix multiplication
//   - At the end of the BWD NTT : final point-wise multiplication.
// ==============================================================================================

module ntt_core_wmm_post_process_wrapper
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;
#(
  parameter  int        OP_W            = 32,
  parameter  [OP_W-1:0] MOD_NTT         = 2**32-2**17-2**13+1,
  parameter int         R               = 8, // Butterfly Radix
  parameter int         PSI             = 8, // Number of butterflies
  parameter mod_mult_type_e        MOD_MULT_TYPE   = MOD_MULT_SOLINAS3,
  parameter arith_mult_type_e      MULT_TYPE       = MULT_KARATSUBA,
  parameter bit         IN_PIPE         = 1'b1, // Recommended
  parameter bit         OUT_PIPE        = 1'b1  // Recommended

) (
  // System interface -------------------------------------------------------------------
  input                                                         clk,
  input                                                         s_rst_n,
  // Data from CLBU ---------------------------------------------------------------------
  input                 [PSI-1:0][        R-1:0][     OP_W-1:0] clbu_pp_data,
  input                                         [      PSI-1:0] clbu_pp_data_avail,
  input                                                         clbu_pp_sob,
  input                                                         clbu_pp_eob,
  input                                                         clbu_pp_sol,
  input                                                         clbu_pp_eol,
  input                                                         clbu_pp_sos,
  input                                                         clbu_pp_eos,
  input                                                         clbu_pp_ntt_bwd,
  input                                         [ BPBS_ID_W-1:0] clbu_pp_pbs_id,
  input                                                         clbu_pp_ctrl_avail, // TODO : Cleanup because UNUSED
  input                                                         clbu_pp_last_stg,
  // output data to network regular stage ----------------------------------------------
  output                [PSI-1:0][        R-1:0][     OP_W-1:0] pp_rsntw_data,
  output                                                        pp_rsntw_sob,
  output                                                        pp_rsntw_eob,
  output                                                        pp_rsntw_sol,
  output                                                        pp_rsntw_eol,
  output                                                        pp_rsntw_sos,
  output                                                        pp_rsntw_eos,
  output                                        [ BPBS_ID_W-1:0] pp_rsntw_pbs_id,
  output                                                        pp_rsntw_avail,
  // output data to network last stage -------------------------------------------------
  output                [PSI-1:0][        R-1:0][     OP_W-1:0] pp_lsntw_data,
  output                                                        pp_lsntw_sob,
  output                                                        pp_lsntw_eob,
  output                                                        pp_lsntw_sol,
  output                                                        pp_lsntw_eol,
  output                                                        pp_lsntw_sos,
  output                                                        pp_lsntw_eos,
  output                                        [ BPBS_ID_W-1:0] pp_lsntw_pbs_id,
  output                                                        pp_lsntw_avail,
  // output data to network last stage -------------------------------------------------
  output                [PSI-1:0][        R-1:0][     OP_W-1:0] pp_lsntw_fwd_data,
  output                                                        pp_lsntw_fwd_sob,
  output                                                        pp_lsntw_fwd_eob,
  output                                                        pp_lsntw_fwd_sol,
  output                                                        pp_lsntw_fwd_eol,
  output                                                        pp_lsntw_fwd_sos,
  output                                                        pp_lsntw_fwd_eos,
  output                                        [ BPBS_ID_W-1:0] pp_lsntw_fwd_pbs_id,
  output                                                        pp_lsntw_fwd_avail,
  // output data to network last stage -------------------------------------------------
  output                [PSI-1:0][        R-1:0][     OP_W-1:0] pp_lsntw_bwd_data,
  output                                                        pp_lsntw_bwd_sob,
  output                                                        pp_lsntw_bwd_eob,
  output                                                        pp_lsntw_bwd_sol,
  output                                                        pp_lsntw_bwd_eol,
  output                                                        pp_lsntw_bwd_sos,
  output                                                        pp_lsntw_bwd_eos,
  output                                        [ BPBS_ID_W-1:0] pp_lsntw_bwd_pbs_id,
  output                                                        pp_lsntw_bwd_avail,
  // Error trigger ----------------------------------------------------------------------
  output logic                                                  pp_error,
  // Twiddles for final multiplication
  input                 [PSI-1:0][        R-1:0][     OP_W-1:0] twd_intt_final,
  input                          [      PSI-1:0][        R-1:0] twd_intt_final_vld,
  output                         [      PSI-1:0][        R-1:0] twd_intt_final_rdy,
  // Matrix factors : BSK ---------------------------------------------------------------
  input        [PSI-1:0][  R-1:0][GLWE_K_P1-1:0][     OP_W-1:0] bsk,
  input                 [PSI-1:0][        R-1:0][GLWE_K_P1-1:0] bsk_vld,
  output                [PSI-1:0][        R-1:0][GLWE_K_P1-1:0] bsk_rdy
);

  logic [PSI-1:0][R-1:0]               pp_rsntw_sob_a;
  logic [PSI-1:0][R-1:0]               pp_rsntw_eob_a;
  logic [PSI-1:0][R-1:0]               pp_rsntw_sol_a;
  logic [PSI-1:0][R-1:0]               pp_rsntw_eol_a;
  logic [PSI-1:0][R-1:0]               pp_rsntw_sos_a;
  logic [PSI-1:0][R-1:0]               pp_rsntw_eos_a;
  logic [PSI-1:0][R-1:0][BPBS_ID_W-1:0] pp_rsntw_pbs_id_a;
  logic [PSI-1:0][R-1:0]               pp_rsntw_avail_a;

  logic [PSI-1:0][R-1:0]               pp_lsntw_sob_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_eob_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_sol_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_eol_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_sos_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_eos_a;
  logic [PSI-1:0][R-1:0][BPBS_ID_W-1:0] pp_lsntw_pbs_id_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_avail_a;

  logic [PSI-1:0][R-1:0]               pp_lsntw_fwd_sob_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_fwd_eob_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_fwd_sol_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_fwd_eol_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_fwd_sos_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_fwd_eos_a;
  logic [PSI-1:0][R-1:0][BPBS_ID_W-1:0] pp_lsntw_fwd_pbs_id_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_fwd_avail_a;

  logic [PSI-1:0][R-1:0]               pp_lsntw_bwd_sob_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_bwd_eob_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_bwd_sol_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_bwd_eol_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_bwd_sos_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_bwd_eos_a;
  logic [PSI-1:0][R-1:0][BPBS_ID_W-1:0] pp_lsntw_bwd_pbs_id_a;
  logic [PSI-1:0][R-1:0]               pp_lsntw_bwd_avail_a;

  logic [PSI-1:0][R-1:0]               pp_error_a;

  generate
    for (genvar psi_gen = 0; psi_gen < PSI; psi_gen++) begin : psi_loop_gen
      for (genvar r_gen = 0; r_gen < R; r_gen++) begin : r_loop_gen
        ntt_core_wmm_post_process #(
          .OP_W           (OP_W),
          .MOD_NTT        (MOD_NTT),
          .MOD_MULT_TYPE  (MOD_MULT_TYPE),
          .MULT_TYPE      (MULT_TYPE),
          .IN_PIPE        (IN_PIPE),
          .OUT_PIPE       (OUT_PIPE)
        ) ntt_core_wmm_post_process (
          // system
          .clk                 (clk),
          .s_rst_n             (s_rst_n),
          // input
          .clbu_pp_data        (clbu_pp_data[psi_gen][r_gen]),
          .clbu_pp_data_avail  (clbu_pp_data_avail[psi_gen]),
          .clbu_pp_sob         (clbu_pp_sob),
          .clbu_pp_eob         (clbu_pp_eob),
          .clbu_pp_sol         (clbu_pp_sol),
          .clbu_pp_eol         (clbu_pp_eol),
          .clbu_pp_sos         (clbu_pp_sos),
          .clbu_pp_eos         (clbu_pp_eos),
          .clbu_pp_ntt_bwd     (clbu_pp_ntt_bwd),
          .clbu_pp_pbs_id      (clbu_pp_pbs_id),
          .clbu_pp_ctrl_avail  (clbu_pp_ctrl_avail),
          .clbu_pp_last_stg    (clbu_pp_last_stg),
          // merged last stage
          .pp_lsntw_data       (pp_lsntw_data[psi_gen][r_gen]),
          .pp_lsntw_sob        (pp_lsntw_sob_a[psi_gen][r_gen]),
          .pp_lsntw_eob        (pp_lsntw_eob_a[psi_gen][r_gen]),
          .pp_lsntw_sol        (pp_lsntw_sol_a[psi_gen][r_gen]),
          .pp_lsntw_eol        (pp_lsntw_eol_a[psi_gen][r_gen]),
          .pp_lsntw_sos        (pp_lsntw_sos_a[psi_gen][r_gen]),
          .pp_lsntw_eos        (pp_lsntw_eos_a[psi_gen][r_gen]),
          .pp_lsntw_pbs_id     (pp_lsntw_pbs_id_a[psi_gen][r_gen]),
          .pp_lsntw_avail      (pp_lsntw_avail_a[psi_gen][r_gen]),
          // forward last stage
          .pp_lsntw_fwd_data   (pp_lsntw_fwd_data[psi_gen][r_gen]),
          .pp_lsntw_fwd_sob    (pp_lsntw_fwd_sob_a[psi_gen][r_gen]),
          .pp_lsntw_fwd_eob    (pp_lsntw_fwd_eob_a[psi_gen][r_gen]),
          .pp_lsntw_fwd_sol    (pp_lsntw_fwd_sol_a[psi_gen][r_gen]),
          .pp_lsntw_fwd_eol    (pp_lsntw_fwd_eol_a[psi_gen][r_gen]),
          .pp_lsntw_fwd_sos    (pp_lsntw_fwd_sos_a[psi_gen][r_gen]),
          .pp_lsntw_fwd_eos    (pp_lsntw_fwd_eos_a[psi_gen][r_gen]),
          .pp_lsntw_fwd_pbs_id (pp_lsntw_fwd_pbs_id_a[psi_gen][r_gen]),
          .pp_lsntw_fwd_avail  (pp_lsntw_fwd_avail_a[psi_gen][r_gen]),
          // backward last stage
          .pp_lsntw_bwd_data   (pp_lsntw_bwd_data[psi_gen][r_gen]),
          .pp_lsntw_bwd_sob    (pp_lsntw_bwd_sob_a[psi_gen][r_gen]),
          .pp_lsntw_bwd_eob    (pp_lsntw_bwd_eob_a[psi_gen][r_gen]),
          .pp_lsntw_bwd_sol    (pp_lsntw_bwd_sol_a[psi_gen][r_gen]),
          .pp_lsntw_bwd_eol    (pp_lsntw_bwd_eol_a[psi_gen][r_gen]),
          .pp_lsntw_bwd_sos    (pp_lsntw_bwd_sos_a[psi_gen][r_gen]),
          .pp_lsntw_bwd_eos    (pp_lsntw_bwd_eos_a[psi_gen][r_gen]),
          .pp_lsntw_bwd_pbs_id (pp_lsntw_bwd_pbs_id_a[psi_gen][r_gen]),
          .pp_lsntw_bwd_avail  (pp_lsntw_bwd_avail_a[psi_gen][r_gen]),
          // regular stage
          .pp_rsntw_data       (pp_rsntw_data[psi_gen][r_gen]),
          .pp_rsntw_sob        (pp_rsntw_sob_a[psi_gen][r_gen]),
          .pp_rsntw_eob        (pp_rsntw_eob_a[psi_gen][r_gen]),
          .pp_rsntw_sol        (pp_rsntw_sol_a[psi_gen][r_gen]),
          .pp_rsntw_eol        (pp_rsntw_eol_a[psi_gen][r_gen]),
          .pp_rsntw_sos        (pp_rsntw_sos_a[psi_gen][r_gen]),
          .pp_rsntw_eos        (pp_rsntw_eos_a[psi_gen][r_gen]),
          .pp_rsntw_pbs_id     (pp_rsntw_pbs_id_a[psi_gen][r_gen]),
          .pp_rsntw_avail      (pp_rsntw_avail_a[psi_gen][r_gen]),
          // error trigger
          .pp_error            (pp_error_a[psi_gen][r_gen]),
          .twd_intt_final      (twd_intt_final[psi_gen][r_gen]),
          .twd_intt_final_vld  (twd_intt_final_vld[psi_gen][r_gen]),
          .twd_intt_final_rdy  (twd_intt_final_rdy[psi_gen][r_gen]),
          .bsk                 (bsk[psi_gen][r_gen]),
          .bsk_vld             (bsk_vld[psi_gen][r_gen]),
          .bsk_rdy             (bsk_rdy[psi_gen][r_gen])
        );

      end
    end
  endgenerate

  assign pp_rsntw_sob         = pp_rsntw_sob_a[0][0];
  assign pp_rsntw_eob         = pp_rsntw_eob_a[0][0];
  assign pp_rsntw_sol         = pp_rsntw_sol_a[0][0];
  assign pp_rsntw_eol         = pp_rsntw_eol_a[0][0];
  assign pp_rsntw_sos         = pp_rsntw_sos_a[0][0];
  assign pp_rsntw_eos         = pp_rsntw_eos_a[0][0];
  assign pp_rsntw_pbs_id      = pp_rsntw_pbs_id_a[0][0];
  assign pp_rsntw_avail       = pp_rsntw_avail_a[0][0];

  assign pp_lsntw_sob         = pp_lsntw_sob_a[0][0];
  assign pp_lsntw_eob         = pp_lsntw_eob_a[0][0];
  assign pp_lsntw_sol         = pp_lsntw_sol_a[0][0];
  assign pp_lsntw_eol         = pp_lsntw_eol_a[0][0];
  assign pp_lsntw_sos         = pp_lsntw_sos_a[0][0];
  assign pp_lsntw_eos         = pp_lsntw_eos_a[0][0];
  assign pp_lsntw_pbs_id      = pp_lsntw_pbs_id_a[0][0];
  assign pp_lsntw_avail       = pp_lsntw_avail_a[0][0];

  assign pp_lsntw_fwd_sob     = pp_lsntw_fwd_sob_a[0][0];
  assign pp_lsntw_fwd_eob     = pp_lsntw_fwd_eob_a[0][0];
  assign pp_lsntw_fwd_sol     = pp_lsntw_fwd_sol_a[0][0];
  assign pp_lsntw_fwd_eol     = pp_lsntw_fwd_eol_a[0][0];
  assign pp_lsntw_fwd_sos     = pp_lsntw_fwd_sos_a[0][0];
  assign pp_lsntw_fwd_eos     = pp_lsntw_fwd_eos_a[0][0];
  assign pp_lsntw_fwd_pbs_id  = pp_lsntw_fwd_pbs_id_a[0][0];
  assign pp_lsntw_fwd_avail   = pp_lsntw_fwd_avail_a[0][0];

  assign pp_lsntw_bwd_sob     = pp_lsntw_bwd_sob_a[0][0];
  assign pp_lsntw_bwd_eob     = pp_lsntw_bwd_eob_a[0][0];
  assign pp_lsntw_bwd_sol     = pp_lsntw_bwd_sol_a[0][0];
  assign pp_lsntw_bwd_eol     = pp_lsntw_bwd_eol_a[0][0];
  assign pp_lsntw_bwd_sos     = pp_lsntw_bwd_sos_a[0][0];
  assign pp_lsntw_bwd_eos     = pp_lsntw_bwd_eos_a[0][0];
  assign pp_lsntw_bwd_pbs_id  = pp_lsntw_bwd_pbs_id_a[0][0];
  assign pp_lsntw_bwd_avail   = pp_lsntw_bwd_avail_a[0][0];

  assign pp_error             = |pp_error_a;

endmodule
