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
//  IS_LS  : is last stage
//  D_INIT : first value of delta index
//  D_NB   : Number of stages
//  USE_PP : Taken into account when IS_LS=1.
//           If 1, instanciate the PP and the last stage NTW
//           If 0, outputs data at the input of the PP
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

module ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd
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
  parameter  int               DELTA         = (S+1)/2, // if contains last stage, set to LS_DELTA, else set to RS_DELTA
  parameter  int               BWD_PSI_DIV   = 2, // Number of butterflies for the backward stages
  parameter  int               S_INIT        = S-1, // First stage index
  parameter  int               D_INIT        = 0, // First delta index
  parameter  int               D_NB          = DELTA, // Number of implemented stages
  parameter  bit               IS_LS         = 1'b0, // contains last stage
  parameter  bit               USE_PP        = 1'b0, // Use PP. Used when IS_LS = 1
  parameter  int               RAM_LATENCY   = 1,
  localparam int               BWD_PSI       = PSI / BWD_PSI_DIV,
  localparam int               LOCAL_DELTA   = D_INIT + D_NB,
  localparam int               THRU_MSB      = D_NB == 0 ? D_INIT + 1 : LOCAL_DELTA, // To avoid compilation warning when D_NB=0
  localparam int               ERROR_W       = 2
) (
  input  logic                                                  clk,
  input  logic                                                  s_rst_n,

  // fwd clbu input
  input  logic [PSI-1:0][R-1:0][OP_W-1:0]                       in_clbu_fwd_data,
  input  logic [PSI-1:0]                                        in_clbu_fwd_data_avail,
  input  logic                                                  in_clbu_fwd_sob,
  input  logic                                                  in_clbu_fwd_eob,
  input  logic                                                  in_clbu_fwd_sol,
  input  logic                                                  in_clbu_fwd_eol,
  input  logic                                                  in_clbu_fwd_sos,
  input  logic                                                  in_clbu_fwd_eos,
  input  logic [BPBS_ID_W-1:0]                                  in_clbu_fwd_pbs_id,
  input  logic                                                  in_clbu_fwd_ctrl_avail,

  // fwd clbu output logic - used if LOCAL_DELTA < DELTA
  output logic [PSI-1:0][R-1:0][OP_W-1:0]                       out_clbu_fwd_data,
  output logic [PSI-1:0]                                        out_clbu_fwd_data_avail,
  output logic                                                  out_clbu_fwd_sob,
  output logic                                                  out_clbu_fwd_eob,
  output logic                                                  out_clbu_fwd_sol,
  output logic                                                  out_clbu_fwd_eol,
  output logic                                                  out_clbu_fwd_sos,
  output logic                                                  out_clbu_fwd_eos,
  output logic [BPBS_ID_W-1:0]                                  out_clbu_fwd_pbs_id,
  output logic                                                  out_clbu_fwd_ctrl_avail,

  // fwd ntw output logic - used if LOCAL_DELTA = DELTA and not last stage
  output logic [PSI-1:0][R-1:0][OP_W-1:0]                       out_ntw_fwd_data,
  output logic [PSI-1:0][R-1:0]                                 out_ntw_fwd_data_avail,
  output logic                                                  out_ntw_fwd_sob,
  output logic                                                  out_ntw_fwd_eob,
  output logic                                                  out_ntw_fwd_sol,
  output logic                                                  out_ntw_fwd_eol,
  output logic                                                  out_ntw_fwd_sos,
  output logic                                                  out_ntw_fwd_eos,
  output logic [BPBS_ID_W-1:0]                                  out_ntw_fwd_pbs_id,
  output logic                                                  out_ntw_fwd_ctrl_avail,

  // bwd clbu input  logic- used if LOCAL_DELTA = DELTA and last stage
  output logic [BWD_PSI-1:0][R-1:0][OP_W-1:0]                   in_clbu_bwd_data,
  output logic [BWD_PSI-1:0]                                    in_clbu_bwd_data_avail,
  output logic                                                  in_clbu_bwd_sob,
  output logic                                                  in_clbu_bwd_eob,
  output logic                                                  in_clbu_bwd_sol,
  output logic                                                  in_clbu_bwd_eol,
  output logic                                                  in_clbu_bwd_sos,
  output logic                                                  in_clbu_bwd_eos,
  output logic [BPBS_ID_W-1:0]                                  in_clbu_bwd_pbs_id,
  output logic                                                  in_clbu_bwd_ctrl_avail,

  // Twiddles
  // quasi static signal
  input  logic [1:0][R/2-1:0][OP_W-1:0]                         twd_omg_ru_r_pow,
  // [i] = omg_ru_r ** i
  input  logic [THRU_MSB-1:D_INIT][PSI-1:0][R-1:1][OP_W-1:0]    twd_phi_ru_fwd,
  input  logic [THRU_MSB-1:D_INIT][PSI-1:0]                     twd_phi_ru_fwd_vld,
  output logic [THRU_MSB-1:D_INIT][PSI-1:0]                     twd_phi_ru_fwd_rdy,

  // Matrix factors : BSK - used if D_INIT + D_NB = DELTA
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][OP_W-1:0]        bsk,
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                  bsk_vld,
  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                  bsk_rdy,
  // Error
  output logic [ERROR_W-1:0]                                    ntt_error
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam bit BORDER_CLBU   = LOCAL_DELTA == DELTA ? 1'b1 : 1'b0;
  localparam int LPB_NB        = 1; // no loopback
  localparam bit OUT_WITH_NTW  = (BORDER_CLBU && !IS_LS) ? 1'b1 : 1'b0;
  localparam bit IN_WITH_CLBU  = D_NB > 0;

  localparam int CLBU_ERR_OFS  = 0;
  localparam int PP_ERR_OFS    = 1;

  localparam int RS_NTW_S_INIT = S_INIT - D_NB + 1;

  // =========================================================================================== //
  // ntt_core_with_matrix_multiplication_unfold_pcg
  // =========================================================================================== //
  // ------------------------------------------------------------------------------------------- --
  // Signals
  // ------------------------------------------------------------------------------------------- --
  // fwd pp -> ls
  logic [PSI-1:0][R-1:0][OP_W-1:0]  pp_lsntw_fwd_data;
  logic                             pp_lsntw_fwd_sob;
  logic                             pp_lsntw_fwd_eob;
  logic                             pp_lsntw_fwd_sol;
  logic                             pp_lsntw_fwd_eol;
  logic                             pp_lsntw_fwd_sos;
  logic                             pp_lsntw_fwd_eos;
  logic [BPBS_ID_W-1:0]             pp_lsntw_fwd_pbs_id;
  logic                             pp_lsntw_fwd_avail;
  // error
  logic                             clbu_error;
  logic                             pp_error;

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
  generate
    if (IN_WITH_CLBU) begin : gen_in_with_clbu
      ntt_core_wmm_clbu_pcg #(
        .OP_W            (OP_W),
        .MOD_NTT         (MOD_NTT),
        .R               (R),
        .PSI             (PSI),
        .S               (S),
        .D_INIT          (D_INIT),
        .RS_DELTA        (LOCAL_DELTA),
        .LS_DELTA        (LOCAL_DELTA),
        .RS_OUT_WITH_NTW (OUT_WITH_NTW),
        .LS_OUT_WITH_NTW (OUT_WITH_NTW),
        .LPB_NB          (LPB_NB),
        .MOD_MULT_TYPE   (MOD_MULT_TYPE),
        .REDUCT_TYPE     (REDUCT_TYPE),
        .MULT_TYPE       (MULT_TYPE  )
      ) ntt_core_wmm_clbu_pcg_fwd (
        // System
        .clk                 (clk),
        .s_rst_n             (s_rst_n),
        // input
        .in_a                (in_clbu_fwd_data),
        .in_avail            (in_clbu_fwd_data_avail),
        .in_sob              (in_clbu_fwd_sob),
        .in_eob              (in_clbu_fwd_eob),
        .in_sol              (in_clbu_fwd_sol),
        .in_eol              (in_clbu_fwd_eol),
        .in_sos              (in_clbu_fwd_sos),
        .in_eos              (in_clbu_fwd_eos),
        .in_pbs_id           (in_clbu_fwd_pbs_id),
        .in_ntt_bwd          ('0),
        // last stage = only one used here since LPB_NB = 1
        .ls_z                (out_clbu_fwd_data),
        .ls_avail            (out_clbu_fwd_data_avail),
        .ls_sob              (out_clbu_fwd_sob),
        .ls_eob              (out_clbu_fwd_eob),
        .ls_sol              (out_clbu_fwd_sol),
        .ls_eol              (out_clbu_fwd_eol),
        .ls_sos              (out_clbu_fwd_sos),
        .ls_eos              (out_clbu_fwd_eos),
        .ls_ntt_bwd          (/*UNUSED*/),
        .ls_pbs_id           (out_clbu_fwd_pbs_id),
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
        .twd_omg_ru_r_pow   (twd_omg_ru_r_pow),
        .twd_phi_ru         (twd_phi_ru_fwd[THRU_MSB-1:D_INIT]),
        .twd_phi_ru_vld     (twd_phi_ru_fwd_vld[THRU_MSB-1:D_INIT]),
        .twd_phi_ru_rdy     (twd_phi_ru_fwd_rdy[THRU_MSB-1:D_INIT]),
        // error
        .error_twd_phi      (clbu_error)
      );

    end // gen_in_with_clbu
    else begin : gen_no_in_with_clbu
      assign clbu_error = '0;

      assign out_clbu_fwd_data       = in_clbu_fwd_data;
      assign out_clbu_fwd_data_avail = in_clbu_fwd_data_avail;
      assign out_clbu_fwd_sob        = in_clbu_fwd_sob;
      assign out_clbu_fwd_eob        = in_clbu_fwd_eob;
      assign out_clbu_fwd_sol        = in_clbu_fwd_sol;
      assign out_clbu_fwd_eol        = in_clbu_fwd_eol;
      assign out_clbu_fwd_sos        = in_clbu_fwd_sos;
      assign out_clbu_fwd_eos        = in_clbu_fwd_eos;
      assign out_clbu_fwd_pbs_id     = in_clbu_fwd_pbs_id;


    end // gen_no_in_with_clbu

    assign out_clbu_fwd_ctrl_avail = out_clbu_fwd_data_avail[0];


    if (BORDER_CLBU) begin : gen_border_clbu

      // ===================
      // Last stage
      // ===================
      if (IS_LS) begin : gen_ls
        if (USE_PP) begin : gen_use_pp
        // -------------------------------------------------------------------------------------------- //
        // PP
        // -------------------------------------------------------------------------------------------- //
        ntt_core_wmm_post_process_wrapper #(
          .OP_W          (OP_W),
          .MOD_NTT       (MOD_NTT),
          .R             (R),
          .PSI           (PSI),
          .MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
          .MULT_TYPE     (PP_MULT_TYPE),
          .IN_PIPE       (1),
          .OUT_PIPE      (1)
        ) ntt_core_wmm_post_process_wrapper_fwd (
          // System interface
          .clk                     (clk),
          .s_rst_n                 (s_rst_n),
          // Data from CLBU
          .clbu_pp_data            (out_clbu_fwd_data),
          .clbu_pp_data_avail      (out_clbu_fwd_data_avail),
          .clbu_pp_sob             (out_clbu_fwd_sob),
          .clbu_pp_eob             (out_clbu_fwd_eob),
          .clbu_pp_sol             (out_clbu_fwd_sol),
          .clbu_pp_eol             (out_clbu_fwd_eol),
          .clbu_pp_sos             (out_clbu_fwd_sos),
          .clbu_pp_eos             (out_clbu_fwd_eos),
          .clbu_pp_ntt_bwd         (1'b0), // forward
          .clbu_pp_pbs_id          (out_clbu_fwd_pbs_id),
          .clbu_pp_ctrl_avail      (out_clbu_fwd_ctrl_avail),
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
          .pp_lsntw_fwd_data       (pp_lsntw_fwd_data   ),
          .pp_lsntw_fwd_sob        (pp_lsntw_fwd_sob    ),
          .pp_lsntw_fwd_eob        (pp_lsntw_fwd_eob    ),
          .pp_lsntw_fwd_sol        (pp_lsntw_fwd_sol    ),
          .pp_lsntw_fwd_eol        (pp_lsntw_fwd_eol    ),
          .pp_lsntw_fwd_sos        (pp_lsntw_fwd_sos    ),
          .pp_lsntw_fwd_eos        (pp_lsntw_fwd_eos    ),
          .pp_lsntw_fwd_pbs_id     (pp_lsntw_fwd_pbs_id ),
          .pp_lsntw_fwd_avail      (pp_lsntw_fwd_avail  ),
          // output data to network last stage backward
          .pp_lsntw_bwd_data       (/*UNUSED*/),
          .pp_lsntw_bwd_sob        (/*UNUSED*/),
          .pp_lsntw_bwd_eob        (/*UNUSED*/),
          .pp_lsntw_bwd_sol        (/*UNUSED*/),
          .pp_lsntw_bwd_eol        (/*UNUSED*/),
          .pp_lsntw_bwd_sos        (/*UNUSED*/),
          .pp_lsntw_bwd_eos        (/*UNUSED*/),
          .pp_lsntw_bwd_pbs_id     (/*UNUSED*/),
          .pp_lsntw_bwd_avail      (/*UNUSED*/),
          // Error trigger
          .pp_error                (pp_error),
          // Twiddles for final multiplication
          .twd_intt_final          ('x), /*UNUSED*/
          .twd_intt_final_vld      ('0), /*UNUSED*/
          .twd_intt_final_rdy      (/*UNUSED*/),
          // Matrix factors : BSK
          .bsk                     (bsk),
          .bsk_vld                 (bsk_vld),
          .bsk_rdy                 (bsk_rdy)
        );

// pragma translate_off
        always_ff @(posedge clk) begin
          if (bsk_rdy != 0)
            assert(bsk_vld != 0)
            else $error("%t > ERROR: BSK not valid!",$time);
        end
// pragma translate_on

        // -------------------------------------------------------------------------------------------- //
        // Network
        // -------------------------------------------------------------------------------------------- //
        logic [BWD_PSI-1:0][R-1:0] ntw_seq_fwd_ls_data_avail;
        always_comb
          for (int i=0; i<BWD_PSI; i=i+1)
            in_clbu_bwd_data_avail[i] = ntw_seq_fwd_ls_data_avail[i][0];

        ntt_core_wmm_network_pcg #(
          .OP_W                 (OP_W),
          .R                    (R),
          .PSI                  (PSI),
          .S                    (S),
          .OUT_PSI_DIV          (BWD_PSI_DIV),
          .RAM_LATENCY          (RAM_LATENCY),
          .IN_PIPE              (1'b1),
          .S_INIT               ('0),
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
        ) ntt_core_wmm_network_pcg_fwd_ls (
          // system
          .clk               (clk),
          .s_rst_n           (s_rst_n),
          // sequencer -> network
          .seq_ntw_rden      (1'b0), /*UNUSED*/
          // post process last stage
          .pp_lsntw_data     (pp_lsntw_fwd_data  ),
          .pp_lsntw_sob      (pp_lsntw_fwd_sob   ),
          .pp_lsntw_eob      (pp_lsntw_fwd_eob   ),
          .pp_lsntw_sol      (pp_lsntw_fwd_sol   ),
          .pp_lsntw_eol      (pp_lsntw_fwd_eol   ),
          .pp_lsntw_sos      (pp_lsntw_fwd_sos   ),
          .pp_lsntw_eos      (pp_lsntw_fwd_eos   ),
          .pp_lsntw_pbs_id   (pp_lsntw_fwd_pbs_id),
          .pp_lsntw_avail    (pp_lsntw_fwd_avail),
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
          .ntw_seq_data      (in_clbu_bwd_data),
          .ntw_seq_data_avail(ntw_seq_fwd_ls_data_avail),
          .ntw_seq_sob       (in_clbu_bwd_sob),
          .ntw_seq_eob       (in_clbu_bwd_eob),
          .ntw_seq_sol       (in_clbu_bwd_sol),
          .ntw_seq_eol       (in_clbu_bwd_eol),
          .ntw_seq_sos       (in_clbu_bwd_sos),
          .ntw_seq_eos       (in_clbu_bwd_eos),
          .ntw_seq_pbs_id    (in_clbu_bwd_pbs_id),
          .ntw_seq_ctrl_avail(in_clbu_bwd_ctrl_avail),
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

        end // gen_use_pp
        else begin : gen_no_use_pp
          // out_clbu_fwd_data already correctly connected

          assign pp_error = '0;
        end
      end // gen_ls

      // ===================
      // Regular stage
      // ===================
      else begin : gen_rs
        assign pp_error= '0;
        assign bsk_rdy = 'x; // UNUSED

        // -------------------------------------------------------------------------------------------- //
        // Network
        // -------------------------------------------------------------------------------------------- //
        ntt_core_wmm_network_pcg #(
          .OP_W                 (OP_W),
          .R                    (R),
          .PSI                  (PSI),
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
        ) ntt_core_wmm_network_pcg_fwd_rs (
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
          .pp_rsntw_data     (out_clbu_fwd_data  ),
          .pp_rsntw_sob      (out_clbu_fwd_sob   ),
          .pp_rsntw_eob      (out_clbu_fwd_eob   ),
          .pp_rsntw_sol      (out_clbu_fwd_sol   ),
          .pp_rsntw_eol      (out_clbu_fwd_eol   ),
          .pp_rsntw_sos      (out_clbu_fwd_sos   ),
          .pp_rsntw_eos      (out_clbu_fwd_eos   ),
          .pp_rsntw_pbs_id   (out_clbu_fwd_pbs_id),
          .pp_rsntw_avail    (out_clbu_fwd_data_avail[0] ),
          // network -> sequenccer
          .ntw_seq_data      (out_ntw_fwd_data),
          .ntw_seq_data_avail(out_ntw_fwd_data_avail),
          .ntw_seq_sob       (out_ntw_fwd_sob),
          .ntw_seq_eob       (out_ntw_fwd_eob),
          .ntw_seq_sol       (out_ntw_fwd_sol),
          .ntw_seq_eol       (out_ntw_fwd_eol),
          .ntw_seq_sos       (out_ntw_fwd_sos),
          .ntw_seq_eos       (out_ntw_fwd_eos),
          .ntw_seq_pbs_id    (out_ntw_fwd_pbs_id),
          .ntw_seq_ctrl_avail(out_ntw_fwd_ctrl_avail),
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
      assign out_ntw_fwd_data       = 'x;
      assign out_ntw_fwd_data_avail = 'x;
      assign out_ntw_fwd_sob        = 'x;
      assign out_ntw_fwd_eob        = 'x;
      assign out_ntw_fwd_sol        = 'x;
      assign out_ntw_fwd_eol        = 'x;
      assign out_ntw_fwd_sos        = 'x;
      assign out_ntw_fwd_eos        = 'x;
      assign out_ntw_fwd_pbs_id     = 'x;
      assign out_ntw_fwd_ctrl_avail = 'x;

      assign in_clbu_bwd_data       = 'x;
      assign in_clbu_bwd_data_avail = 'x;
      assign in_clbu_bwd_sob        = 'x;
      assign in_clbu_bwd_eob        = 'x;
      assign in_clbu_bwd_sol        = 'x;
      assign in_clbu_bwd_eol        = 'x;
      assign in_clbu_bwd_sos        = 'x;
      assign in_clbu_bwd_eos        = 'x;
      assign in_clbu_bwd_pbs_id     = 'x;
      assign in_clbu_bwd_ctrl_avail = 'x;

      assign pp_error               = '0;
    end
  endgenerate

endmodule

