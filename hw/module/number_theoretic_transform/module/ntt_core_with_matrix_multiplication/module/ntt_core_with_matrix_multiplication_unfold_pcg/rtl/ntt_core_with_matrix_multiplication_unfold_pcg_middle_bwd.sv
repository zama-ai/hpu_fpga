// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core tackles the NTT and INTT computations by using the same DIT butterfly-units.
// It also computes a matrix multiplication.
//
// Prerequisites :
// Input data are interleaved in time, to avoid an output accumulator.
// Input order is the "incremental stride" order, with R**(S-1) as the stride.
// Output data are also interleaved in time.
// Output order is also the "incremental stride" order.
//
// The unfold_pcg architecture:
//   NTT and INTT are sequential.
//   Use pseudo constant geometry architecture (PCG)
//
// The content of the 'core' module depends on the following parameters:
//  IS_LS : is last stage
//  D_INIT : first value of delta index
//  D_NB : Number of stages
//
//  if D_INIT + D_NB = DELTA
//    if IS_LS = 0
//       the module contains :
//          * D_NB stages of CLBU
//          * regular stage network
//    else
//       the module contains :
//          * D_NB stages of CLBU
//          * post process
//          * last stage network
//  else
//    the module contains D_NB stages of CLBU
//
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;
  import ntt_core_wmm_pkg::*;
  import ntt_core_wmm_network_pcg_pkg::*;
#(
  parameter  int               OP_W          = 32,
  parameter  [OP_W-1:0]        MOD_NTT       = 2**32-2**17-2**13+1,
  parameter  int_type_e        MOD_NTT_TYPE  = SOLINAS3,
  parameter  mod_mult_type_e   MOD_MULT_TYPE = set_mod_mult_type(MOD_NTT_TYPE),
  parameter  mod_reduct_type_e REDUCT_TYPE   = set_mod_reduct_type(MOD_NTT_TYPE),
  parameter  arith_mult_type_e MULT_TYPE     = set_ntt_mult_type(OP_W,MOD_NTT_TYPE),
  parameter  mod_mult_type_e   PP_MOD_MULT_TYPE = MOD_MULT_TYPE,
  parameter  arith_mult_type_e PP_MULT_TYPE     = MULT_TYPE,
  parameter  int               R             = 2, // Butterfly Radix
  parameter  int               PSI           = 4, // Number of butterflies
  parameter  int               S             = $clog2(N)/$clog2(R), // Total number of stages
  parameter  int               DELTA         = (S+1)/2, // if IS_LS, set to LS_DELTA, else set to RS_DELTA
  parameter  int               BWD_PSI_DIV   = 2, // Number of butterflies for the backward stages
  parameter  int               S_INIT        = S-1, // First stage index
  parameter  int               D_INIT        = 0, // First delta index
  parameter  int               D_NB          = DELTA, // Number of implemented stages
  parameter  bit               IS_LS         = 1'b0, // contains last stage
  parameter  int               RAM_LATENCY   = 1,
  localparam int               BWD_PSI       = PSI / BWD_PSI_DIV,
  localparam int               LOCAL_DELTA   = D_INIT + D_NB,
  localparam int               ERROR_W       = 2
) (
  input  logic                                                      clk,
  input  logic                                                      s_rst_n,

  // bwd clbu input
  input  logic [BWD_PSI-1:0][R-1:0][OP_W-1:0]                       in_clbu_bwd_data,
  input  logic [BWD_PSI-1:0]                                        in_clbu_bwd_data_avail,
  input  logic                                                      in_clbu_bwd_sob,
  input  logic                                                      in_clbu_bwd_eob,
  input  logic                                                      in_clbu_bwd_sol,
  input  logic                                                      in_clbu_bwd_eol,
  input  logic                                                      in_clbu_bwd_sos,
  input  logic                                                      in_clbu_bwd_eos,
  input  logic [BPBS_ID_W-1:0]                                      in_clbu_bwd_pbs_id,
  input  logic                                                      in_clbu_bwd_ctrl_avail,

  // bwd clbu output - used if LOCAL_DELTA < DELTA
  output logic [BWD_PSI-1:0][R-1:0][OP_W-1:0]                       out_clbu_bwd_data,
  output logic [BWD_PSI-1:0]                                        out_clbu_bwd_data_avail,
  output logic                                                      out_clbu_bwd_sob,
  output logic                                                      out_clbu_bwd_eob,
  output logic                                                      out_clbu_bwd_sol,
  output logic                                                      out_clbu_bwd_eol,
  output logic                                                      out_clbu_bwd_sos,
  output logic                                                      out_clbu_bwd_eos,
  output logic [BPBS_ID_W-1:0]                                      out_clbu_bwd_pbs_id,
  output logic                                                      out_clbu_bwd_ctrl_avail,

  // bwd ntw output - used if LOCAL_DELTA = DELTA and not last stage
  output logic [BWD_PSI-1:0][R-1:0][OP_W-1:0]                       out_ntw_bwd_data,
  output logic [BWD_PSI-1:0][R-1:0]                                 out_ntw_bwd_data_avail,
  output logic                                                      out_ntw_bwd_sob,
  output logic                                                      out_ntw_bwd_eob,
  output logic                                                      out_ntw_bwd_sol,
  output logic                                                      out_ntw_bwd_eol,
  output logic                                                      out_ntw_bwd_sos,
  output logic                                                      out_ntw_bwd_eos,
  output logic [BPBS_ID_W-1:0]                                      out_ntw_bwd_pbs_id,
  output logic                                                      out_ntw_bwd_ctrl_avail,
  // Output to acc - used if LOCAL_DELTA = DELTA and last stage
  // Output data to acc
  output logic [PSI-1:0][R-1:0][OP_W-1:0]                           ntt_acc_data,
  output logic [PSI-1:0][R-1:0]                                     ntt_acc_data_avail,
  output logic                                                      ntt_acc_sob,
  output logic                                                      ntt_acc_eob,
  output logic                                                      ntt_acc_sol,
  output logic                                                      ntt_acc_eol,
  output logic                                                      ntt_acc_sog,
  output logic                                                      ntt_acc_eog,
  output logic [BPBS_ID_W-1:0]                                      ntt_acc_pbs_id,
  output logic                                                      ntt_acc_ctrl_avail,

  // Twiddles
  // quasi static signal
  input  logic [1:0][R/2-1:0][OP_W-1:0]                             twd_omg_ru_r_pow,
  // [i] = omg_ru_r ** i
  input  logic [LOCAL_DELTA-1:D_INIT][BWD_PSI-1:0][R-1:1][OP_W-1:0] twd_phi_ru_bwd,
  input  logic [LOCAL_DELTA-1:D_INIT][BWD_PSI-1:0]                  twd_phi_ru_bwd_vld,
  output logic [LOCAL_DELTA-1:D_INIT][BWD_PSI-1:0]                  twd_phi_ru_bwd_rdy,
  // final multiplication factors
  input  logic [BWD_PSI-1:0][R-1:0][OP_W-1:0]                       twd_intt_final,
  input  logic [BWD_PSI-1:0][R-1:0]                                 twd_intt_final_vld,
  output logic [BWD_PSI-1:0][R-1:0]                                 twd_intt_final_rdy,

  // Error
  output logic [ERROR_W-1:0]                                        ntt_error

);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam bit BORDER_CLBU   = LOCAL_DELTA == DELTA ? 1'b1 : 1'b0;
  localparam int LPB_NB        = 1; // no loopback
  localparam bit OUT_WITH_NTW  = (BORDER_CLBU && !IS_LS) ? 1'b1 : 1'b0;

  localparam int CLBU_ERR_OFS  = 0;
  localparam int PP_ERR_OFS    = 1;

  localparam int RS_NTW_S_INIT = S_INIT - D_NB + 1;

  localparam int BWD_PSI_DIV_W = BWD_PSI_DIV == 1 ? 1 : $clog2(BWD_PSI_DIV);

  // =========================================================================================== //
  // ntt_core_with_matrix_multiplication_unfold_pcg
  // =========================================================================================== //
  // ------------------------------------------------------------------------------------------- --
  // Signals
  // ------------------------------------------------------------------------------------------- --
  // bwd pp -> ls
  logic [BWD_PSI-1:0][R-1:0][OP_W-1:0] pp_lsntw_bwd_data;
  logic                                pp_lsntw_bwd_sob;
  logic                                pp_lsntw_bwd_eob;
  logic                                pp_lsntw_bwd_sol;
  logic                                pp_lsntw_bwd_eol;
  logic                                pp_lsntw_bwd_sos;
  logic                                pp_lsntw_bwd_eos;
  logic [BPBS_ID_W-1:0 ]                pp_lsntw_bwd_pbs_id;
  logic                                pp_lsntw_bwd_avail;

  // bwd ntw output to acc
  logic [BWD_PSI-1:0][R-1:0][OP_W-1:0] out_ntw_acc_data;
  logic [BWD_PSI-1:0][R-1:0]           out_ntw_acc_data_avail;
  logic                                out_ntw_acc_sob;
  logic                                out_ntw_acc_eob;
  logic                                out_ntw_acc_sol;
  logic                                out_ntw_acc_eol;
  logic                                out_ntw_acc_sog;
  logic                                out_ntw_acc_eog;
  logic [BPBS_ID_W-1:0]                 out_ntw_acc_pbs_id;
  logic                                out_ntw_acc_ctrl_avail;

  // error
  logic                                clbu_error;
  logic                                pp_error;

  // ============================================================================================ //
  // Errors
  // ============================================================================================ //
  assign ntt_error[CLBU_ERR_OFS] = clbu_error;
  assign ntt_error[PP_ERR_OFS]   = pp_error;


  // ============================================================================================ //
  // unfold_pcg
  // ============================================================================================ //
  // ---------------------------------------------------------------------------------------- //
  // Cluster Butterfly Unit
  // ---------------------------------------------------------------------------------------- //
  ntt_core_wmm_clbu_pcg #(
    .OP_W            (OP_W),
    .MOD_NTT         (MOD_NTT),
    .R               (R),
    .PSI             (BWD_PSI),
    .S               (S),
    .D_INIT          (D_INIT),
    .RS_DELTA        (LOCAL_DELTA),
    .LS_DELTA        (LOCAL_DELTA),
    .RS_OUT_WITH_NTW (OUT_WITH_NTW),
    .LS_OUT_WITH_NTW (OUT_WITH_NTW), // Since LPB_NB = 1 : output on LS only
    .LPB_NB          (LPB_NB),
    .MOD_MULT_TYPE   (MOD_MULT_TYPE),
    .REDUCT_TYPE     (REDUCT_TYPE),
    .MULT_TYPE       (MULT_TYPE  )
  ) ntt_core_wmm_clbu_pcg_bwd (
    // System
    .clk                 (clk),
    .s_rst_n             (s_rst_n),
    // input
    .in_a                (in_clbu_bwd_data),
    .in_avail            (in_clbu_bwd_data_avail),
    .in_sob              (in_clbu_bwd_sob),
    .in_eob              (in_clbu_bwd_eob),
    .in_sol              (in_clbu_bwd_sol),
    .in_eol              (in_clbu_bwd_eol),
    .in_sos              (in_clbu_bwd_sos),
    .in_eos              (in_clbu_bwd_eos),
    .in_pbs_id           (in_clbu_bwd_pbs_id),
    .in_ntt_bwd          ('1),
    // last stage = only one used here since LPB_NB = 1
    .ls_z                (out_clbu_bwd_data),
    .ls_avail            (out_clbu_bwd_data_avail),
    .ls_sob              (out_clbu_bwd_sob),
    .ls_eob              (out_clbu_bwd_eob),
    .ls_sol              (out_clbu_bwd_sol),
    .ls_eol              (out_clbu_bwd_eol),
    .ls_sos              (out_clbu_bwd_sos),
    .ls_eos              (out_clbu_bwd_eos),
    .ls_ntt_bwd          (/*UNUSED*/),
    .ls_pbs_id           (out_clbu_bwd_pbs_id),
    // regular stage
    .rs_z                (/*UNUSED*/),
    .rs_avail            (/*UNUSED*/),
    .rs_sob              (/*UNUSED*/),
    .rs_eob              (/*UNUSED*/),
    .rs_sol              (/*UNUSED*/),
    .rs_eol              (/*UNUSED*/),
    .rs_sos              (/*UNUSED*/),
    .rs_eos              (/*UNUSED*/),
    .rs_ntt_bwd          (/*UNUSED*/),
    .rs_pbs_id           (/*UNUSED*/),
    // twiddles
    .twd_omg_ru_r_pow    (twd_omg_ru_r_pow),
    .twd_phi_ru          (twd_phi_ru_bwd[LOCAL_DELTA-1:D_INIT]),
    .twd_phi_ru_vld      (twd_phi_ru_bwd_vld[LOCAL_DELTA-1:D_INIT]),
    .twd_phi_ru_rdy      (twd_phi_ru_bwd_rdy[LOCAL_DELTA-1:D_INIT]),
    // error
    .error_twd_phi       (clbu_error)
  );

  assign out_clbu_bwd_ctrl_avail = out_clbu_bwd_data_avail[0];

  generate
    if (BORDER_CLBU) begin : gen_border_clbu

      // ===================
      // Last stage
      // ===================
      if (IS_LS) begin : gen_ls
        // -------------------------------------------------------------------------------------------- //
        // PP
        // -------------------------------------------------------------------------------------------- //
        ntt_core_wmm_post_process_wrapper #(
          .OP_W          (OP_W),
          .MOD_NTT       (MOD_NTT),
          .R             (R),
          .PSI           (BWD_PSI),
          .MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
          .MULT_TYPE     (PP_MULT_TYPE),
          .IN_PIPE       (1),
          .OUT_PIPE      (1)
        ) ntt_core_wmm_post_process_wrapper_bwd (
          // System interface
          .clk                     (clk),
          .s_rst_n                 (s_rst_n),
          // Data from CLBU
          .clbu_pp_data            (out_clbu_bwd_data),
          .clbu_pp_data_avail      (out_clbu_bwd_data_avail),
          .clbu_pp_sob             (out_clbu_bwd_sob),
          .clbu_pp_eob             (out_clbu_bwd_eob),
          .clbu_pp_sol             (out_clbu_bwd_sol),
          .clbu_pp_eol             (out_clbu_bwd_eol),
          .clbu_pp_sos             (out_clbu_bwd_sos),
          .clbu_pp_eos             (out_clbu_bwd_eos),
          .clbu_pp_ntt_bwd         (1'b1), // backward
          .clbu_pp_pbs_id          (out_clbu_bwd_pbs_id),
          .clbu_pp_ctrl_avail      (out_clbu_bwd_ctrl_avail),
          .clbu_pp_last_stg        (1'b1), // is last stage
          // output data to network regular stage
          .pp_rsntw_data           (/*UNUSED*/),
          .pp_rsntw_sob            (/*UNUSED*/),
          .pp_rsntw_eob            (/*UNUSED*/),
          .pp_rsntw_sol            (/*UNUSED*/),
          .pp_rsntw_eol            (/*UNUSED*/),
          .pp_rsntw_sos            (/*UNUSED*/),
          .pp_rsntw_eos            (/*UNUSED*/),
          .pp_rsntw_pbs_id         (/*UNUSED*/),
          .pp_rsntw_avail          (/*UNUSED*/),
          // output data to network last stage
          .pp_lsntw_data           (/*UNUSED*/),
          .pp_lsntw_sob            (/*UNUSED*/),
          .pp_lsntw_eob            (/*UNUSED*/),
          .pp_lsntw_sol            (/*UNUSED*/),
          .pp_lsntw_eol            (/*UNUSED*/),
          .pp_lsntw_sos            (/*UNUSED*/),
          .pp_lsntw_eos            (/*UNUSED*/),
          .pp_lsntw_pbs_id         (/*UNUSED*/),
          .pp_lsntw_avail          (/*UNUSED*/),
          // output data to network last stage forward
          .pp_lsntw_fwd_data       (/*UNUSED*/),
          .pp_lsntw_fwd_sob        (/*UNUSED*/),
          .pp_lsntw_fwd_eob        (/*UNUSED*/),
          .pp_lsntw_fwd_sol        (/*UNUSED*/),
          .pp_lsntw_fwd_eol        (/*UNUSED*/),
          .pp_lsntw_fwd_sos        (/*UNUSED*/),
          .pp_lsntw_fwd_eos        (/*UNUSED*/),
          .pp_lsntw_fwd_pbs_id     (/*UNUSED*/),
          .pp_lsntw_fwd_avail      (/*UNUSED*/),
          // output data to network last stage backward
          .pp_lsntw_bwd_data       (pp_lsntw_bwd_data   ),
          .pp_lsntw_bwd_sob        (pp_lsntw_bwd_sob    ),
          .pp_lsntw_bwd_eob        (pp_lsntw_bwd_eob    ),
          .pp_lsntw_bwd_sol        (pp_lsntw_bwd_sol    ),
          .pp_lsntw_bwd_eol        (pp_lsntw_bwd_eol    ),
          .pp_lsntw_bwd_sos        (pp_lsntw_bwd_sos    ),
          .pp_lsntw_bwd_eos        (pp_lsntw_bwd_eos    ),
          .pp_lsntw_bwd_pbs_id     (pp_lsntw_bwd_pbs_id ),
          .pp_lsntw_bwd_avail      (pp_lsntw_bwd_avail  ),
          // Error trigger
          .pp_error                (pp_error),
          // Twiddles for final multiplication
          .twd_intt_final          (twd_intt_final    ),
          .twd_intt_final_vld      (twd_intt_final_vld),
          .twd_intt_final_rdy      (twd_intt_final_rdy),
          // Matrix factors : BSK
          .bsk                     ('x),/*UNUSED*/
          .bsk_vld                 ('x),/*UNUSED*/
          .bsk_rdy                 (/*UNUSED*/)
        );

        // -------------------------------------------------------------------------------------------- //
        // Network
        // -------------------------------------------------------------------------------------------- //
        ntt_core_wmm_network_pcg #(
          .OP_W                 (OP_W),
          .R                    (R),
          .PSI                  (BWD_PSI),
          .S                    (S),
          .OUT_PSI_DIV          (1),
          .RAM_LATENCY          (RAM_LATENCY),
          .IN_PIPE              (1'b1),
          .S_INIT               (S),
          .S_DEC                ('0),
          .SEND_TO_SEQ          (1'b0),
          .TOKEN_W              (BATCH_TOKEN_W),
          .RS_DELTA             (LOCAL_DELTA),
          .LS_DELTA             (LOCAL_DELTA),
          .LPB_NB               (LPB_NB),
          .RS_OUT_WITH_NTW      (1'b1),
          .LS_OUT_WITH_NTW      (1'b0),
          .USE_RS               (1'b0),
          .USE_LS               (1'b1)
        ) ntt_core_wmm_network_pcg_bwd_ls (
          // system
          .clk               (clk),
          .s_rst_n           (s_rst_n),
          // sequencer -> network
          .seq_ntw_rden      (1'b0), /*UNUSED*/
          // post process last stage
          .pp_lsntw_data     (pp_lsntw_bwd_data  ),
          .pp_lsntw_sob      (pp_lsntw_bwd_sob   ),
          .pp_lsntw_eob      (pp_lsntw_bwd_eob   ),
          .pp_lsntw_sol      (pp_lsntw_bwd_sol   ),
          .pp_lsntw_eol      (pp_lsntw_bwd_eol   ),
          .pp_lsntw_sos      (pp_lsntw_bwd_sos   ),
          .pp_lsntw_eos      (pp_lsntw_bwd_eos   ),
          .pp_lsntw_pbs_id   (pp_lsntw_bwd_pbs_id),
          .pp_lsntw_avail    (pp_lsntw_bwd_avail),
          // regular stage
          .pp_rsntw_data     ('x),/*UNUSED*/
          .pp_rsntw_sob      ('x),/*UNUSED*/
          .pp_rsntw_eob      ('x),/*UNUSED*/
          .pp_rsntw_sol      ('x),/*UNUSED*/
          .pp_rsntw_eol      ('x),/*UNUSED*/
          .pp_rsntw_sos      ('x),/*UNUSED*/
          .pp_rsntw_eos      ('x),/*UNUSED*/
          .pp_rsntw_pbs_id   ('x),/*UNUSED*/
          .pp_rsntw_avail    ('0),/*UNUSED*/
          // network -> sequenccer
          .ntw_seq_data      (/*UNUSED*/),
          .ntw_seq_data_avail(/*UNUSED*/),
          .ntw_seq_sob       (/*UNUSED*/),
          .ntw_seq_eob       (/*UNUSED*/),
          .ntw_seq_sol       (/*UNUSED*/),
          .ntw_seq_eol       (/*UNUSED*/),
          .ntw_seq_sos       (/*UNUSED*/),
          .ntw_seq_eos       (/*UNUSED*/),
          .ntw_seq_pbs_id    (/*UNUSED*/),
          .ntw_seq_ctrl_avail(/*UNUSED*/),
          // network -> accumulator
          .ntw_acc_data      (out_ntw_acc_data),
          .ntw_acc_data_avail(out_ntw_acc_data_avail),
          .ntw_acc_sob       (out_ntw_acc_sob),
          .ntw_acc_eob       (out_ntw_acc_eob),
          .ntw_acc_sol       (out_ntw_acc_sol),
          .ntw_acc_eol       (out_ntw_acc_eol),
          .ntw_acc_sog       (out_ntw_acc_sog),
          .ntw_acc_eog       (out_ntw_acc_eog),
          .ntw_acc_pbs_id    (out_ntw_acc_pbs_id),
          .ntw_acc_ctrl_avail(out_ntw_acc_ctrl_avail)
        );

        // -------------------------------------------------------------------------------------------- //
        // Reformat output
        // -------------------------------------------------------------------------------------------- //
        if (BWD_PSI_DIV == 1) begin : gen_bwd_psi_div_eq_1
          assign ntt_acc_data       = out_ntw_acc_data;
          assign ntt_acc_data_avail = out_ntw_acc_data_avail;
          assign ntt_acc_sob        = out_ntw_acc_sob;
          assign ntt_acc_eob        = out_ntw_acc_eob;
          assign ntt_acc_sol        = out_ntw_acc_sol;
          assign ntt_acc_eol        = out_ntw_acc_eol;
          assign ntt_acc_sog        = out_ntw_acc_sog;
          assign ntt_acc_eog        = out_ntw_acc_eog;
          assign ntt_acc_pbs_id     = out_ntw_acc_pbs_id;
          assign ntt_acc_ctrl_avail = out_ntw_acc_ctrl_avail;
        end
        else begin: gen_bwd_psi_div_gt_1
          logic [BWD_PSI_DIV_W-1:0]  out_cnt;
          logic [GLWE_K_P1_W-1:0]    out_lvl_cnt;
          logic [BWD_PSI_DIV_W-1:0]  out_cntD;
          logic [GLWE_K_P1_W-1:0]    out_lvl_cntD;

          logic                      last_out_cnt;
          logic                      first_out_cnt;
          logic                      last_out_lvl_cnt;
          logic                      first_out_lvl_cnt;
          logic [BWD_PSI-1:0][R-1:0] last_out_cnt_v;
          logic [BWD_PSI-1:0][R-1:0] last_out_cnt_vD;
          logic                      last_out_cnt_vD_tmp;

          assign last_out_lvl_cnt = out_lvl_cnt == (GLWE_K_P1-1);
          assign first_out_lvl_cnt= out_lvl_cnt == 0;
          assign last_out_cnt     = out_cnt == (BWD_PSI_DIV-1);
          assign first_out_cnt    = out_cnt == 0;
          assign out_lvl_cntD     = out_ntw_acc_ctrl_avail ? last_out_lvl_cnt ? 0 : out_lvl_cnt + 1 : out_lvl_cnt;
          assign out_cntD         = (out_ntw_acc_ctrl_avail && last_out_lvl_cnt) ? last_out_cnt ? 0 : out_cnt + 1 : out_cnt;
          assign last_out_cnt_vD_tmp = out_cntD == (BWD_PSI_DIV-1);
          assign last_out_cnt_vD     = {BWD_PSI*R{last_out_cnt_vD_tmp}};

          always_ff @(posedge clk)
            if (!s_rst_n) begin
              out_cnt        <= '0;
              out_lvl_cnt    <= '0;
              last_out_cnt_v <= '0;
            end
            else begin
              out_cnt        <= out_cntD;
              out_lvl_cnt    <= out_lvl_cntD;
              last_out_cnt_v <= last_out_cnt_vD;
            end

          logic [BWD_PSI-1:0][R-1:0][GLWE_K_P1*(BWD_PSI_DIV-1)-1:0][OP_W-1:0] buf_ntw_acc_data;
          logic                                                               buf_ntw_acc_sob;
          logic                                                               buf_ntw_acc_sog;
          logic [BWD_PSI-1:0][R-1:0][GLWE_K_P1*(BWD_PSI_DIV-1)-1:0][OP_W-1:0] buf_ntw_acc_dataD;
          logic                                                               buf_ntw_acc_sobD;
          logic                                                               buf_ntw_acc_sogD;
          logic [BWD_PSI_DIV-2:0][BWD_PSI-1:0][R-1:0][OP_W-1:0]               buf_ntw_acc_out_data;

          for (genvar gen_p=0; gen_p<BWD_PSI; gen_p=gen_p+1) begin
            for (genvar gen_r=0; gen_r<R; gen_r=gen_r+1) begin
              assign buf_ntw_acc_dataD[gen_p][gen_r][GLWE_K_P1*(BWD_PSI_DIV-1)-1] =
                  out_ntw_acc_data_avail[gen_p][gen_r] ? out_ntw_acc_data[gen_p][gen_r]: // Bufferize the results
                                                         buf_ntw_acc_data[gen_p][gen_r][GLWE_K_P1*(BWD_PSI_DIV-1)-1];
              assign buf_ntw_acc_dataD[gen_p][gen_r][GLWE_K_P1*(BWD_PSI_DIV-1)-2:0] =
                  out_ntw_acc_data_avail[gen_p][gen_r] ? buf_ntw_acc_data[gen_p][gen_r][GLWE_K_P1*(BWD_PSI_DIV-1)-1:1] :
                                                         buf_ntw_acc_data[gen_p][gen_r][GLWE_K_P1*(BWD_PSI_DIV-1)-2:0];

              for (genvar gen_i=0; gen_i<BWD_PSI_DIV-1; gen_i=gen_i+1) begin
                assign buf_ntw_acc_out_data[gen_i][gen_p][gen_r] = buf_ntw_acc_data[gen_p][gen_r][gen_i*GLWE_K_P1];
              end
            end
          end

          // start-of buffer
          assign buf_ntw_acc_sobD = (first_out_cnt && first_out_lvl_cnt && out_ntw_acc_ctrl_avail) ? out_ntw_acc_sob : buf_ntw_acc_sob;
          assign buf_ntw_acc_sogD = (first_out_cnt && first_out_lvl_cnt && out_ntw_acc_ctrl_avail) ? out_ntw_acc_sog : buf_ntw_acc_sog;

          always_ff @(posedge clk) begin
            buf_ntw_acc_data <= buf_ntw_acc_dataD;
            buf_ntw_acc_sob  <= buf_ntw_acc_sobD;
            buf_ntw_acc_sog  <= buf_ntw_acc_sogD;
          end

          assign ntt_acc_data       = {out_ntw_acc_data, buf_ntw_acc_out_data};
          assign ntt_acc_data_avail = {BWD_PSI_DIV{out_ntw_acc_data_avail & last_out_cnt_v}};
          assign ntt_acc_sob        = buf_ntw_acc_sob && first_out_lvl_cnt;
          assign ntt_acc_eob        = out_ntw_acc_eob;
          assign ntt_acc_sol        = first_out_lvl_cnt;
          assign ntt_acc_eol        = last_out_lvl_cnt;
          assign ntt_acc_sog        = buf_ntw_acc_sog && first_out_lvl_cnt;
          assign ntt_acc_eog        = out_ntw_acc_eog;
          assign ntt_acc_pbs_id     = out_ntw_acc_pbs_id;
          assign ntt_acc_ctrl_avail = out_ntw_acc_ctrl_avail & last_out_cnt;

        end // gen_bwd_psi_div_gt_1

      end // gen_ls

      // ===================
      // Regular stage
      // ===================
      else begin : gen_rs
        assign twd_intt_final_rdy = 'x; // UNUSED
        assign pp_error = '0;

        // -------------------------------------------------------------------------------------------- //
        // Network
        // -------------------------------------------------------------------------------------------- //
        ntt_core_wmm_network_pcg #(
          .OP_W                 (OP_W),
          .R                    (R),
          .PSI                  (BWD_PSI),
          .S                    (S),
          .OUT_PSI_DIV          (1),
          .RAM_LATENCY          (RAM_LATENCY),
          .IN_PIPE              (1'b1),
          .S_INIT               (RS_NTW_S_INIT),
          .S_DEC                ('0),
          .SEND_TO_SEQ          (1'b0),
          .TOKEN_W              (BATCH_TOKEN_W),
          .RS_DELTA             (LOCAL_DELTA),
          .LS_DELTA             (LOCAL_DELTA),
          .LPB_NB               (LPB_NB),
          .RS_OUT_WITH_NTW      (1'b1),
          .LS_OUT_WITH_NTW      (1'b0),
          .USE_RS               (1'b1),
          .USE_LS               (1'b0)
        ) ntt_core_wmm_network_pcg_bwd_rs (
          // system
          .clk               (clk),
          .s_rst_n           (s_rst_n),
          // sequencer -> network
          .seq_ntw_rden      (1'b0), /*UNUSED*/
          // post process last stage
          .pp_lsntw_data     ('x),/*UNUSED*/
          .pp_lsntw_sob      ('x),/*UNUSED*/
          .pp_lsntw_eob      ('x),/*UNUSED*/
          .pp_lsntw_sol      ('x),/*UNUSED*/
          .pp_lsntw_eol      ('x),/*UNUSED*/
          .pp_lsntw_sos      ('x),/*UNUSED*/
          .pp_lsntw_eos      ('x),/*UNUSED*/
          .pp_lsntw_pbs_id   ('x),/*UNUSED*/
          .pp_lsntw_avail    (1'b0),
          // regular stage
          .pp_rsntw_data     (out_clbu_bwd_data  ),
          .pp_rsntw_sob      (out_clbu_bwd_sob   ),
          .pp_rsntw_eob      (out_clbu_bwd_eob   ),
          .pp_rsntw_sol      (out_clbu_bwd_sol   ),
          .pp_rsntw_eol      (out_clbu_bwd_eol   ),
          .pp_rsntw_sos      (out_clbu_bwd_sos   ),
          .pp_rsntw_eos      (out_clbu_bwd_eos   ),
          .pp_rsntw_pbs_id   (out_clbu_bwd_pbs_id),
          .pp_rsntw_avail    (out_clbu_bwd_data_avail[0]),
          // network -> sequenccer
          .ntw_seq_data      (out_ntw_bwd_data),
          .ntw_seq_data_avail(out_ntw_bwd_data_avail),
          .ntw_seq_sob       (out_ntw_bwd_sob),
          .ntw_seq_eob       (out_ntw_bwd_eob),
          .ntw_seq_sol       (out_ntw_bwd_sol),
          .ntw_seq_eol       (out_ntw_bwd_eol),
          .ntw_seq_sos       (out_ntw_bwd_sos),
          .ntw_seq_eos       (out_ntw_bwd_eos),
          .ntw_seq_pbs_id    (out_ntw_bwd_pbs_id),
          .ntw_seq_ctrl_avail(out_ntw_bwd_ctrl_avail),
          // network -> accumulator
          .ntw_acc_data      (/*UNUSED*/),
          .ntw_acc_data_avail(/*UNUSED*/),
          .ntw_acc_sob       (/*UNUSED*/),
          .ntw_acc_eob       (/*UNUSED*/),
          .ntw_acc_sol       (/*UNUSED*/),
          .ntw_acc_eol       (/*UNUSED*/),
          .ntw_acc_sog       (/*UNUSED*/),
          .ntw_acc_eog       (/*UNUSED*/),
          .ntw_acc_pbs_id    (/*UNUSED*/),
          .ntw_acc_ctrl_avail(/*UNUSED*/)
        );

      end
    end // gen_border_clbu
    else begin : gen_no_border_clbu
      // The following signals are not used
      assign out_ntw_bwd_data       = 'x;
      assign out_ntw_bwd_data_avail = 'x;
      assign out_ntw_bwd_sob        = 'x;
      assign out_ntw_bwd_eob        = 'x;
      assign out_ntw_bwd_sol        = 'x;
      assign out_ntw_bwd_eol        = 'x;
      assign out_ntw_bwd_sos        = 'x;
      assign out_ntw_bwd_eos        = 'x;
      assign out_ntw_bwd_pbs_id     = 'x;
      assign out_ntw_bwd_ctrl_avail = 'x;

      assign ntt_acc_data           = 'x;
      assign ntt_acc_data_avail     = 'x;
      assign ntt_acc_sob            = 'x;
      assign ntt_acc_eob            = 'x;
      assign ntt_acc_sol            = 'x;
      assign ntt_acc_eol            = 'x;
      assign ntt_acc_sog            = 'x;
      assign ntt_acc_eog            = 'x;
      assign ntt_acc_pbs_id         = 'x;
      assign ntt_acc_ctrl_avail     = 'x;

      assign pp_error               = '0;
    end
  endgenerate

endmodule
