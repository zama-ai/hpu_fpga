// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core tackles the NTT and INTT computations by reusing the same DIT butterfly-units.
// It also computes a matrix multiplication.
//
// Prerequisites :
// Input data are interleaved in time, to avoid an output accumulator.
// Input order is the "incremental stride" order, with R**(S-1) as the stride.
// Output data are also interleaved in time.
// Output order is also the "incremental stride" order.
//
// The unfold_pcg architecture: NTT and INTT are sequential.
//
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_with_matrix_multiplication_unfold_pcg
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;
  import ntt_core_wmm_pkg::*;
  import ntt_core_wmm_network_pcg_pkg::*;
#(
  parameter  int           OP_W          = 32,
  parameter  [OP_W-1:0]    MOD_NTT       = 2**32-2**17-2**13+1,
  parameter  int_type_e        MOD_NTT_TYPE  = SOLINAS3,
  parameter  mod_mult_type_e   MOD_MULT_TYPE = set_mod_mult_type(MOD_NTT_TYPE),
  parameter  mod_reduct_type_e REDUCT_TYPE   = set_mod_reduct_type(MOD_NTT_TYPE),
  parameter  arith_mult_type_e MULT_TYPE     = set_ntt_mult_type(OP_W,MOD_NTT_TYPE),
  parameter  mod_mult_type_e   PP_MOD_MULT_TYPE = MOD_MULT_TYPE,
  parameter  arith_mult_type_e PP_MULT_TYPE     = MULT_TYPE,
  parameter  int           R             = 2, // Butterfly Radix
  parameter  int           PSI           = 4, // Number of butterflies
  parameter  int           S             = $clog2(N)/$clog2(R), // Number of stages
  parameter  int           FWD_DELTA     = (S+1)/2,
  parameter  int           BWD_DELTA     = (S+1)/2,
  parameter  int           BWD_PSI_DIV   = 2, // Number of butterflies for the backward stages
  parameter  int           RAM_LATENCY   = 1,
  localparam int           ERROR_W       = 2,
  localparam int           BWD_PSI       = PSI / BWD_PSI_DIV,
  localparam int           FWD_CLBU_NB   = (S + FWD_DELTA-1) / FWD_DELTA,
  localparam int           BWD_CLBU_NB   = (S + BWD_DELTA-1) / BWD_DELTA
) (
  input                                                   clk,
  input                                                   s_rst_n,
  // Data from decomposition
  input           [PSI-1:0][        R-1:0][     OP_W-1:0] decomp_ntt_data,
  input                    [      PSI-1:0][        R-1:0] decomp_ntt_data_vld,
  output                   [      PSI-1:0][        R-1:0] decomp_ntt_data_rdy,
  input                                                   decomp_ntt_sob,
  input                                                   decomp_ntt_eob,
  input                                                   decomp_ntt_sol,
  input                                                   decomp_ntt_eol,
  input                                                   decomp_ntt_sog,
  input                                                   decomp_ntt_eog,
  input                                   [ BPBS_ID_W-1:0] decomp_ntt_pbs_id,
  input                                                   decomp_ntt_last_pbs,
  input                                                   decomp_ntt_full_throughput,
  input                                                   decomp_ntt_ctrl_vld,
  output                                                  decomp_ntt_ctrl_rdy,
  // Output data to acc
  output          [PSI-1:0][        R-1:0][     OP_W-1:0] ntt_acc_data,
  output                   [      PSI-1:0][        R-1:0] ntt_acc_data_avail,
  output                                                  ntt_acc_sob,
  output                                                  ntt_acc_eob,
  output                                                  ntt_acc_sol,
  output                                                  ntt_acc_eol,
  output                                                  ntt_acc_sog,
  output                                                  ntt_acc_eog,
  output                                  [ BPBS_ID_W-1:0] ntt_acc_pbs_id,
  output                                                  ntt_acc_ctrl_avail,
  // Twiddles
  // quasi static signal
  input               [1:0][      R/2-1:0][     OP_W-1:0] twd_omg_ru_r_pow,
  // [i] = omg_ru_r ** i
  input  [FWD_CLBU_NB-1:0][FWD_DELTA-1:0][PSI-1:0][    R-1:1][     OP_W-1:0] twd_phi_ru_fwd,
  input  [FWD_CLBU_NB-1:0][FWD_DELTA-1:0][PSI-1:0]                           twd_phi_ru_fwd_vld,
  output [FWD_CLBU_NB-1:0][FWD_DELTA-1:0][PSI-1:0]                           twd_phi_ru_fwd_rdy,
  input  [BWD_CLBU_NB-1:0][BWD_DELTA-1:0][BWD_PSI-1:0][R-1:1][     OP_W-1:0] twd_phi_ru_bwd,
  input  [BWD_CLBU_NB-1:0][BWD_DELTA-1:0][BWD_PSI-1:0]                       twd_phi_ru_bwd_vld,
  output [BWD_CLBU_NB-1:0][BWD_DELTA-1:0][BWD_PSI-1:0]                       twd_phi_ru_bwd_rdy,
  input           [BWD_PSI-1:0][    R-1:0][     OP_W-1:0] twd_intt_final,
  input           [BWD_PSI-1:0][    R-1:0]                twd_intt_final_vld,
  output          [BWD_PSI-1:0][    R-1:0]                twd_intt_final_rdy,
  // Matrix factors : BSK
  input  [PSI-1:0][  R-1:0][GLWE_K_P1-1:0][     OP_W-1:0] bsk,
  input  [PSI-1:0][  R-1:0][GLWE_K_P1-1:0]                bsk_vld,
  output [PSI-1:0][  R-1:0][GLWE_K_P1-1:0]                bsk_rdy,
  // Error
  output                                  [  ERROR_W-1:0] ntt_error
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam int FWD_LS_DELTA = S % FWD_DELTA == 0 ? FWD_DELTA : S % FWD_DELTA;
  localparam int FWD_RS_DELTA = FWD_DELTA;

  localparam int BWD_LS_DELTA = S % BWD_DELTA == 0 ? BWD_DELTA : S % BWD_DELTA;
  localparam int BWD_RS_DELTA = BWD_DELTA;

  localparam int LPB_NB   = 1;

  localparam int CLBU_ERR_OFS = 0;
  localparam int PP_ERR_OFS   = 1;

  localparam int INFIFO_DEPTH = BATCH_PBS_NB * STG_ITER_NB * INTL_L;

  //====== Latency
  localparam int NTW_RD_LATENCY_TMP = ntt_core_wmm_network_pcg_pkg::get_read_latency(RAM_LATENCY);

  // NTW_RD_LATENCY is used to launch the rden signal to ramrd.
  // It should not be less than the number of cycles necessary for the input process of a stage.
  localparam int NTW_RD_LATENCY = NTW_RD_LATENCY_TMP > STG_ITER_NB * GLWE_K_P1 ?
      STG_ITER_NB * GLWE_K_P1 : NTW_RD_LATENCY_TMP;

  localparam int BWD_PSI_DIV_W = BWD_PSI_DIV == 1 ? 1 : $clog2(BWD_PSI_DIV);

  // =========================================================================================== //
  // ntt_core_with_matrix_multiplication_unfold_pcg
  // =========================================================================================== //
  // ------------------------------------------------------------------------------------------- --
  // Signals
  // ------------------------------------------------------------------------------------------- --
  // infifo -> seq
  logic [     PSI-1:0][       R-1:0][OP_W-1:0]           infifo_seq_data;
  logic [     PSI-1:0][       R-1:0]                     infifo_seq_data_vld;
  logic [     PSI-1:0][       R-1:0]                     infifo_seq_data_rdy;
  logic                                                  infifo_seq_sob;
  logic                                                  infifo_seq_eob;
  logic                                                  infifo_seq_sol;
  logic                                                  infifo_seq_eol;
  logic                                                  infifo_seq_sog;
  logic                                                  infifo_seq_eog;
  logic [BPBS_ID_W-1:0]                                   infifo_seq_pbs_id;
  logic                                                  infifo_seq_last_pbs;
  logic                                                  infifo_seq_full_throughput;
  logic                                                  infifo_seq_ctrl_vld;
  logic                                                  infifo_seq_ctrl_rdy;
  // seq -> clbu
  logic [     PSI-1:0][       R-1:0][OP_W-1:0]           seq_clbu_data;
  logic [     PSI-1:0]                                   seq_clbu_data_avail;
  logic                                                  seq_clbu_sob;
  logic                                                  seq_clbu_eob;
  logic                                                  seq_clbu_sol;
  logic                                                  seq_clbu_eol;
  logic                                                  seq_clbu_sos;
  logic                                                  seq_clbu_eos;
  logic [BPBS_ID_W-1:0]                                   seq_clbu_pbs_id;
  logic                                                  seq_clbu_ntt_bwd;
  logic                                                  seq_clbu_ctrl_avail; 
  //== pipeline signals
  // CLBU
  logic [FWD_CLBU_NB-1:0][     PSI-1:0][   R-1:0][OP_W-1:0]  out_clbu_fwd_data;
  logic [FWD_CLBU_NB-1:0][     PSI-1:0]                      out_clbu_fwd_data_avail;
  logic [FWD_CLBU_NB-1:0]                                    out_clbu_fwd_sob;
  logic [FWD_CLBU_NB-1:0]                                    out_clbu_fwd_eob;
  logic [FWD_CLBU_NB-1:0]                                    out_clbu_fwd_sol;
  logic [FWD_CLBU_NB-1:0]                                    out_clbu_fwd_eol;
  logic [FWD_CLBU_NB-1:0]                                    out_clbu_fwd_sos;
  logic [FWD_CLBU_NB-1:0]                                    out_clbu_fwd_eos;
  logic [FWD_CLBU_NB-1:0][BPBS_ID_W-1:0]                      out_clbu_fwd_pbs_id;
  logic [FWD_CLBU_NB-1:0]                                    out_clbu_fwd_ctrl_avail;
  // bwd clbu -> pp
  logic [BWD_CLBU_NB-1:0][ BWD_PSI-1:0][   R-1:0][OP_W-1:0]  out_clbu_bwd_data;
  logic [BWD_CLBU_NB-1:0][ BWD_PSI-1:0]                      out_clbu_bwd_data_avail;
  logic [BWD_CLBU_NB-1:0]                                    out_clbu_bwd_sob;
  logic [BWD_CLBU_NB-1:0]                                    out_clbu_bwd_eob;
  logic [BWD_CLBU_NB-1:0]                                    out_clbu_bwd_sol;
  logic [BWD_CLBU_NB-1:0]                                    out_clbu_bwd_eol;
  logic [BWD_CLBU_NB-1:0]                                    out_clbu_bwd_sos;
  logic [BWD_CLBU_NB-1:0]                                    out_clbu_bwd_eos;
  logic [BWD_CLBU_NB-1:0][BPBS_ID_W-1:0]                      out_clbu_bwd_pbs_id;
  logic [BWD_CLBU_NB-1:0]                                    out_clbu_bwd_ctrl_avail;
  // fwd pp -> rs
//  logic [  S-1:0][     PSI-1:0][   R-1:0][OP_W-1:0]      pp_rsntw_fwd_data;
//  logic [  S-1:0]                                        pp_rsntw_fwd_sob;
//  logic [  S-1:0]                                        pp_rsntw_fwd_eob;
//  logic [  S-1:0]                                        pp_rsntw_fwd_sol;
//  logic [  S-1:0]                                        pp_rsntw_fwd_eol;
//  logic [  S-1:0]                                        pp_rsntw_fwd_sos;
//  logic [  S-1:0]                                        pp_rsntw_fwd_eos;
//  logic [  S-1:0][BPBS_ID_W-1:0]                          pp_rsntw_fwd_pbs_id;
//  logic [  S-1:0]                                        pp_rsntw_fwd_avail;
//  // bwd pp -> rs
//  logic [  S-1:0][ BWD_PSI-1:0][   R-1:0][OP_W-1:0]      pp_rsntw_bwd_data;
//  logic [  S-1:0]                                        pp_rsntw_bwd_sob;
//  logic [  S-1:0]                                        pp_rsntw_bwd_eob;
//  logic [  S-1:0]                                        pp_rsntw_bwd_sol;
//  logic [  S-1:0]                                        pp_rsntw_bwd_eol;
//  logic [  S-1:0]                                        pp_rsntw_bwd_sos;
//  logic [  S-1:0]                                        pp_rsntw_bwd_eos;
//  logic [  S-1:0][BPBS_ID_W-1:0]                          pp_rsntw_bwd_pbs_id;
//  logic [  S-1:0]                                        pp_rsntw_bwd_avail;
  // fwd pp -> ls
  logic [PSI-1:0][   R-1:0][OP_W-1:0]                    pp_lsntw_fwd_data;
  logic                                                  pp_lsntw_fwd_sob;
  logic                                                  pp_lsntw_fwd_eob;
  logic                                                  pp_lsntw_fwd_sol;
  logic                                                  pp_lsntw_fwd_eol;
  logic                                                  pp_lsntw_fwd_sos;
  logic                                                  pp_lsntw_fwd_eos;
  logic [BPBS_ID_W-1:0]                                   pp_lsntw_fwd_pbs_id;
  logic                                                  pp_lsntw_fwd_avail;
  // bwd pp -> ls
  logic [BWD_PSI-1:0 ][   R-1:0][OP_W-1:0]               pp_lsntw_bwd_data;
  logic                                                  pp_lsntw_bwd_sob;
  logic                                                  pp_lsntw_bwd_eob;
  logic                                                  pp_lsntw_bwd_sol;
  logic                                                  pp_lsntw_bwd_eol;
  logic                                                  pp_lsntw_bwd_sos;
  logic                                                  pp_lsntw_bwd_eos;
  logic [BPBS_ID_W-1:0 ]                                  pp_lsntw_bwd_pbs_id;
  logic                                                  pp_lsntw_bwd_avail;
  // fwd clbu input
  logic [FWD_CLBU_NB-1:0][     PSI-1:0][   R-1:0][OP_W-1:0]  in_clbu_fwd_data;
  logic [FWD_CLBU_NB-1:0][     PSI-1:0]                      in_clbu_fwd_data_avail;
  logic [FWD_CLBU_NB-1:0]                                    in_clbu_fwd_sob;
  logic [FWD_CLBU_NB-1:0]                                    in_clbu_fwd_eob;
  logic [FWD_CLBU_NB-1:0]                                    in_clbu_fwd_sol;
  logic [FWD_CLBU_NB-1:0]                                    in_clbu_fwd_eol;
  logic [FWD_CLBU_NB-1:0]                                    in_clbu_fwd_sos;
  logic [FWD_CLBU_NB-1:0]                                    in_clbu_fwd_eos;
  logic [FWD_CLBU_NB-1:0][BPBS_ID_W-1:0]                      in_clbu_fwd_pbs_id;
  logic [FWD_CLBU_NB-1:0][     PSI-1:0]                      in_clbu_fwd_ntt_bwd;
  logic [FWD_CLBU_NB-1:0]                                    in_clbu_fwd_ctrl_avail;
  // bwd clbu input
  logic [BWD_CLBU_NB-1:0][ BWD_PSI-1:0][   R-1:0][OP_W-1:0]  in_clbu_bwd_data;
  logic [BWD_CLBU_NB-1:0][ BWD_PSI-1:0]                      in_clbu_bwd_data_avail;
  logic [BWD_CLBU_NB-1:0]                                    in_clbu_bwd_sob;
  logic [BWD_CLBU_NB-1:0]                                    in_clbu_bwd_eob;
  logic [BWD_CLBU_NB-1:0]                                    in_clbu_bwd_sol;
  logic [BWD_CLBU_NB-1:0]                                    in_clbu_bwd_eol;
  logic [BWD_CLBU_NB-1:0]                                    in_clbu_bwd_sos;
  logic [BWD_CLBU_NB-1:0]                                    in_clbu_bwd_eos;
  logic [BWD_CLBU_NB-1:0][BPBS_ID_W-1:0]                      in_clbu_bwd_pbs_id;
  logic [BWD_CLBU_NB-1:0]                                    in_clbu_bwd_ctrl_avail;
  // fwd ntw output
  logic [FWD_CLBU_NB-1:0][     PSI-1:0][   R-1:0][OP_W-1:0]  out_ntw_fwd_data;
  logic [FWD_CLBU_NB-1:0][     PSI-1:0][   R-1:0]            out_ntw_fwd_data_avail;
  logic [FWD_CLBU_NB-1:0]                                    out_ntw_fwd_sob;
  logic [FWD_CLBU_NB-1:0]                                    out_ntw_fwd_eob;
  logic [FWD_CLBU_NB-1:0]                                    out_ntw_fwd_sol;
  logic [FWD_CLBU_NB-1:0]                                    out_ntw_fwd_eol;
  logic [FWD_CLBU_NB-1:0]                                    out_ntw_fwd_sos;
  logic [FWD_CLBU_NB-1:0]                                    out_ntw_fwd_eos;
  logic [FWD_CLBU_NB-1:0][BPBS_ID_W-1:0]                      out_ntw_fwd_pbs_id;
  logic [FWD_CLBU_NB-1:0]                                    out_ntw_fwd_ctrl_avail;
  // bwd ntw output
  logic [BWD_CLBU_NB-1:0][ BWD_PSI-1:0][   R-1:0][OP_W-1:0]  out_ntw_bwd_data;
  logic [BWD_CLBU_NB-1:0][ BWD_PSI-1:0][   R-1:0]            out_ntw_bwd_data_avail;
  logic [BWD_CLBU_NB-1:0]                                    out_ntw_bwd_sob;
  logic [BWD_CLBU_NB-1:0]                                    out_ntw_bwd_eob;
  logic [BWD_CLBU_NB-1:0]                                    out_ntw_bwd_sol;
  logic [BWD_CLBU_NB-1:0]                                    out_ntw_bwd_eol;
  logic [BWD_CLBU_NB-1:0]                                    out_ntw_bwd_sos;
  logic [BWD_CLBU_NB-1:0]                                    out_ntw_bwd_eos;
  logic [BWD_CLBU_NB-1:0][BPBS_ID_W-1:0]                      out_ntw_bwd_pbs_id;
  logic [BWD_CLBU_NB-1:0]                                    out_ntw_bwd_ctrl_avail;
  // Output to acc
  logic [ BWD_PSI-1:0][       R-1:0][OP_W-1:0]           out_ntw_acc_data;
  logic [ BWD_PSI-1:0][       R-1:0]                     out_ntw_acc_data_avail;
  logic                                                  out_ntw_acc_sob;
  logic                                                  out_ntw_acc_eob;
  logic                                                  out_ntw_acc_sol;
  logic                                                  out_ntw_acc_eol;
  logic                                                  out_ntw_acc_sog;
  logic                                                  out_ntw_acc_eog;
  logic [BPBS_ID_W-1:0]                                   out_ntw_acc_pbs_id;
  logic                                                  out_ntw_acc_ctrl_avail;
  // seq -> ntw loopback
  logic [FWD_CLBU_NB-1:0]                                fwd_clbu_error;
  logic [BWD_CLBU_NB-1:0]                                bwd_clbu_error;
  logic [1:0]                                            pp_error;

  // ============================================================================================ //
  // Infifo
  // ============================================================================================ //
  ntt_core_wmm_infifo #(
    .OP_W       (OP_W),
    .R          (R),
    .PSI        (PSI),
    .RAM_LATENCY(RAM_LATENCY),
    .DEPTH      (INFIFO_DEPTH),
    .BYPASS     (1'b1) // Unfold architecture does not need infifo to bufferize input data.
  ) ntt_core_wmm_infifo (
    // system
    .clk                          (clk),
    .s_rst_n                      (s_rst_n),
    // decomp -> infifo
    .decomp_infifo_data           (decomp_ntt_data),
    .decomp_infifo_data_vld       (decomp_ntt_data_vld),
    .decomp_infifo_data_rdy       (decomp_ntt_data_rdy),
    .decomp_infifo_sob            (decomp_ntt_sob),
    .decomp_infifo_eob            (decomp_ntt_eob),
    .decomp_infifo_sol            (decomp_ntt_sol),
    .decomp_infifo_eol            (decomp_ntt_eol),
    .decomp_infifo_sog            (decomp_ntt_sog),
    .decomp_infifo_eog            (decomp_ntt_eog),
    .decomp_infifo_pbs_id         (decomp_ntt_pbs_id),
    .decomp_infifo_last_pbs       (decomp_ntt_last_pbs),
    .decomp_infifo_full_throughput(decomp_ntt_full_throughput),
    .decomp_infifo_ctrl_vld       (decomp_ntt_ctrl_vld),
    .decomp_infifo_ctrl_rdy       (decomp_ntt_ctrl_rdy),
    // infifo -> sequencer
    .infifo_seq_data              (infifo_seq_data),
    .infifo_seq_data_vld          (infifo_seq_data_vld),
    .infifo_seq_data_rdy          (infifo_seq_data_rdy),
    .infifo_seq_sob               (infifo_seq_sob),
    .infifo_seq_eob               (infifo_seq_eob),
    .infifo_seq_sol               (infifo_seq_sol),
    .infifo_seq_eol               (infifo_seq_eol),
    .infifo_seq_sog               (infifo_seq_sog),
    .infifo_seq_eog               (infifo_seq_eog),
    .infifo_seq_pbs_id            (infifo_seq_pbs_id),
    .infifo_seq_last_pbs          (infifo_seq_last_pbs),
    .infifo_seq_full_throughput   (infifo_seq_full_throughput),
    .infifo_seq_ctrl_vld          (infifo_seq_ctrl_vld),
    .infifo_seq_ctrl_rdy          (infifo_seq_ctrl_rdy)
  );

  // ============================================================================================ //
  // Sequencer
  // ============================================================================================ //
  ntt_core_wmm_sequencer #(
    .OP_W          (OP_W),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .NTW_RD_LATENCY(NTW_RD_LATENCY),
    .S_DEC         (0),
    .LPB_NB        (LPB_NB)
  ) ntt_core_wmm_sequencer (
    // system
    .clk                       (clk),
    .s_rst_n                   (s_rst_n),
    // infifo -> sequencer
    .infifo_seq_data           (infifo_seq_data),
    .infifo_seq_data_vld       (infifo_seq_data_vld),
    .infifo_seq_data_rdy       (infifo_seq_data_rdy),
    .infifo_seq_sob            (infifo_seq_sob),
    .infifo_seq_eob            (infifo_seq_eob),
    .infifo_seq_sol            (infifo_seq_sol),
    .infifo_seq_eol            (infifo_seq_eol),
    .infifo_seq_sog            (infifo_seq_sog),
    .infifo_seq_eog            (infifo_seq_eog),
    .infifo_seq_pbs_id         (infifo_seq_pbs_id),
    .infifo_seq_last_pbs       (infifo_seq_last_pbs),
    .infifo_seq_full_throughput(infifo_seq_full_throughput),
    .infifo_seq_ctrl_vld       (infifo_seq_ctrl_vld),
    .infifo_seq_ctrl_rdy       (infifo_seq_ctrl_rdy),
    // network -> sequencer
    .ntw_seq_data              (/*UNUSED*/),
    .ntw_seq_data_avail        ('0),
    .ntw_seq_sob               (/*UNUSED*/),
    .ntw_seq_eob               (/*UNUSED*/),
    .ntw_seq_sol               (/*UNUSED*/),
    .ntw_seq_eol               (/*UNUSED*/),
    .ntw_seq_sos               (/*UNUSED*/),
    .ntw_seq_eos               (/*UNUSED*/),
    .ntw_seq_pbs_id            (/*UNUSED*/),
    .ntw_seq_ctrl_avail        (1'b0),
    // sequencer -> CLBU
    .seq_clbu_data             (seq_clbu_data),
    .seq_clbu_data_avail       (seq_clbu_data_avail),
    .seq_clbu_sob              (seq_clbu_sob),
    .seq_clbu_eob              (seq_clbu_eob),
    .seq_clbu_sol              (seq_clbu_sol),
    .seq_clbu_eol              (seq_clbu_eol),
    .seq_clbu_sos              (seq_clbu_sos),
    .seq_clbu_eos              (seq_clbu_eos),
    .seq_clbu_pbs_id           (seq_clbu_pbs_id),
    .seq_clbu_ntt_bwd          (seq_clbu_ntt_bwd),
    .seq_clbu_ctrl_avail       (seq_clbu_ctrl_avail),
    // sequencer -> ntw read enable
    .seq_ntw_fwd_rden          (/*UNUSED*/),
    .seq_ntw_bwd_rden          (/*UNUSED*/)
  );

  // ============================================================================================ //
  // unfold_pcg
  // ============================================================================================ //
  // ============================================================================================ //
  // Forward
  // ============================================================================================ //
  assign in_clbu_fwd_data[0]       = seq_clbu_data;
  assign in_clbu_fwd_data_avail[0] = seq_clbu_data_avail;
  assign in_clbu_fwd_sob[0]        = seq_clbu_sob;
  assign in_clbu_fwd_eob[0]        = seq_clbu_eob;
  assign in_clbu_fwd_sol[0]        = seq_clbu_sol;
  assign in_clbu_fwd_eol[0]        = seq_clbu_eol;
  assign in_clbu_fwd_sos[0]        = seq_clbu_sos;
  assign in_clbu_fwd_eos[0]        = seq_clbu_eos;
  assign in_clbu_fwd_pbs_id[0]     = seq_clbu_pbs_id;
  assign in_clbu_fwd_ctrl_avail[0] = seq_clbu_ctrl_avail;

  //== RS
  generate
    for (genvar gen_c = 0; gen_c < FWD_CLBU_NB-1; gen_c = gen_c + 1) begin : gen_fwd_rs_stage
      // ---------------------------------------------------------------------------------------- //
      // Cluster Butterfly Unit
      // ---------------------------------------------------------------------------------------- //
      ntt_core_wmm_clbu_pcg #(
        .OP_W            (OP_W),
        .MOD_NTT         (MOD_NTT),
        .R               (R),
        .PSI             (PSI),
        .S               (S),
        .RS_DELTA        (FWD_RS_DELTA),
        .LS_DELTA        (FWD_RS_DELTA),
        .RS_OUT_WITH_NTW (1'b1),
        .LS_OUT_WITH_NTW (1'b1), // Since LPB_NB = 1 : output on LS only
        .LPB_NB          (LPB_NB),
        .MOD_MULT_TYPE   (MOD_MULT_TYPE),
        .REDUCT_TYPE     (REDUCT_TYPE),
        .MULT_TYPE       (MULT_TYPE  )
      ) ntt_core_wmm_clbu_pcg_fwd_rs (
        // System
        .clk                 (clk),
        .s_rst_n             (s_rst_n),
        // input
        .in_a                (in_clbu_fwd_data[gen_c]),
        .in_avail            (in_clbu_fwd_data_avail[gen_c]),
        .in_sob              (in_clbu_fwd_sob[gen_c]),
        .in_eob              (in_clbu_fwd_eob[gen_c]),
        .in_sol              (in_clbu_fwd_sol[gen_c]),
        .in_eol              (in_clbu_fwd_eol[gen_c]),
        .in_sos              (in_clbu_fwd_sos[gen_c]),
        .in_eos              (in_clbu_fwd_eos[gen_c]),
        .in_pbs_id           (in_clbu_fwd_pbs_id[gen_c]),
        .in_ntt_bwd          ('0),
        // last stage = only one used here since LPB_NB = 1
        .ls_z                (out_clbu_fwd_data[gen_c]),
        .ls_avail            (out_clbu_fwd_data_avail[gen_c]),
        .ls_sob              (out_clbu_fwd_sob[gen_c]),
        .ls_eob              (out_clbu_fwd_eob[gen_c]),
        .ls_sol              (out_clbu_fwd_sol[gen_c]),
        .ls_eol              (out_clbu_fwd_eol[gen_c]),
        .ls_sos              (out_clbu_fwd_sos[gen_c]),
        .ls_eos              (out_clbu_fwd_eos[gen_c]),
        .ls_ntt_bwd          (/*UNUSED*/),
        .ls_pbs_id           (out_clbu_fwd_pbs_id[gen_c]),
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
        .twd_phi_ru         (twd_phi_ru_fwd[gen_c][FWD_RS_DELTA-1:0]),
        .twd_phi_ru_vld     (twd_phi_ru_fwd_vld[gen_c][FWD_RS_DELTA-1:0]),
        .twd_phi_ru_rdy     (twd_phi_ru_fwd_rdy[gen_c][FWD_RS_DELTA-1:0]),
        // error
        .error_twd_phi      (fwd_clbu_error[gen_c])
      );

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
        .S_INIT               (S-1 - gen_c*FWD_RS_DELTA),
        .S_DEC                ('0),
        .SEND_TO_SEQ          (1'b0),
        .TOKEN_W              (BATCH_TOKEN_W),
        .RS_DELTA             (FWD_RS_DELTA),
        .LS_DELTA             (FWD_LS_DELTA),
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
        .pp_rsntw_data     (out_clbu_fwd_data[gen_c]  ),
        .pp_rsntw_sob      (out_clbu_fwd_sob[gen_c]   ),
        .pp_rsntw_eob      (out_clbu_fwd_eob[gen_c]   ),
        .pp_rsntw_sol      (out_clbu_fwd_sol[gen_c]   ),
        .pp_rsntw_eol      (out_clbu_fwd_eol[gen_c]   ),
        .pp_rsntw_sos      (out_clbu_fwd_sos[gen_c]   ),
        .pp_rsntw_eos      (out_clbu_fwd_eos[gen_c]   ),
        .pp_rsntw_pbs_id   (out_clbu_fwd_pbs_id[gen_c]),
        .pp_rsntw_avail    (out_clbu_fwd_data_avail[gen_c][0] ),
        // network -> sequenccer
        .ntw_seq_data      (out_ntw_fwd_data[gen_c]),
        .ntw_seq_data_avail(out_ntw_fwd_data_avail[gen_c]),
        .ntw_seq_sob       (out_ntw_fwd_sob[gen_c]),
        .ntw_seq_eob       (out_ntw_fwd_eob[gen_c]),
        .ntw_seq_sol       (out_ntw_fwd_sol[gen_c]),
        .ntw_seq_eol       (out_ntw_fwd_eol[gen_c]),
        .ntw_seq_sos       (out_ntw_fwd_sos[gen_c]),
        .ntw_seq_eos       (out_ntw_fwd_eos[gen_c]),
        .ntw_seq_pbs_id    (out_ntw_fwd_pbs_id[gen_c]),
        .ntw_seq_ctrl_avail(out_ntw_fwd_ctrl_avail[gen_c]),
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

      assign in_clbu_fwd_data[gen_c+1]       = out_ntw_fwd_data[gen_c];
      assign in_clbu_fwd_data_avail[gen_c+1] = out_ntw_fwd_data_avail[gen_c];
      assign in_clbu_fwd_sob[gen_c+1]        = out_ntw_fwd_sob[gen_c];
      assign in_clbu_fwd_eob[gen_c+1]        = out_ntw_fwd_eob[gen_c];
      assign in_clbu_fwd_sol[gen_c+1]        = out_ntw_fwd_sol[gen_c];
      assign in_clbu_fwd_eol[gen_c+1]        = out_ntw_fwd_eol[gen_c];
      assign in_clbu_fwd_sos[gen_c+1]        = out_ntw_fwd_sos[gen_c];
      assign in_clbu_fwd_eos[gen_c+1]        = out_ntw_fwd_eos[gen_c];
      assign in_clbu_fwd_pbs_id[gen_c+1]     = out_ntw_fwd_pbs_id[gen_c];
      assign in_clbu_fwd_ctrl_avail[gen_c+1] = out_ntw_fwd_ctrl_avail[gen_c];
    end
  endgenerate
  
  //== LS
  // ---------------------------------------------------------------------------------------- //
  // Cluster Butterfly Unit
  // ---------------------------------------------------------------------------------------- //
  ntt_core_wmm_clbu_pcg #(
    .OP_W            (OP_W),
    .MOD_NTT         (MOD_NTT),
    .R               (R),
    .PSI             (PSI),
    .S               (S),
    .RS_DELTA        (FWD_LS_DELTA),
    .LS_DELTA        (FWD_LS_DELTA),
    .RS_OUT_WITH_NTW (1'b0),
    .LS_OUT_WITH_NTW (1'b0),
    .LPB_NB          (LPB_NB),
    .MOD_MULT_TYPE   (MOD_MULT_TYPE),
    .REDUCT_TYPE     (REDUCT_TYPE),
    .MULT_TYPE       (MULT_TYPE  )
  ) ntt_core_wmm_clbu_pcg_fwd_ls (
    // System
    .clk                 (clk),
    .s_rst_n             (s_rst_n),
    // input
    .in_a                (in_clbu_fwd_data[FWD_CLBU_NB-1]),
    .in_avail            (in_clbu_fwd_data_avail[FWD_CLBU_NB-1]),
    .in_sob              (in_clbu_fwd_sob[FWD_CLBU_NB-1]),
    .in_eob              (in_clbu_fwd_eob[FWD_CLBU_NB-1]),
    .in_sol              (in_clbu_fwd_sol[FWD_CLBU_NB-1]),
    .in_eol              (in_clbu_fwd_eol[FWD_CLBU_NB-1]),
    .in_sos              (in_clbu_fwd_sos[FWD_CLBU_NB-1]),
    .in_eos              (in_clbu_fwd_eos[FWD_CLBU_NB-1]),
    .in_pbs_id           (in_clbu_fwd_pbs_id[FWD_CLBU_NB-1]),
    .in_ntt_bwd          ('0),
    // last stage = only one used here since LPB_NB = 1
    .ls_z                (out_clbu_fwd_data[FWD_CLBU_NB-1]),
    .ls_avail            (out_clbu_fwd_data_avail[FWD_CLBU_NB-1]),
    .ls_sob              (out_clbu_fwd_sob[FWD_CLBU_NB-1]),
    .ls_eob              (out_clbu_fwd_eob[FWD_CLBU_NB-1]),
    .ls_sol              (out_clbu_fwd_sol[FWD_CLBU_NB-1]),
    .ls_eol              (out_clbu_fwd_eol[FWD_CLBU_NB-1]),
    .ls_sos              (out_clbu_fwd_sos[FWD_CLBU_NB-1]),
    .ls_eos              (out_clbu_fwd_eos[FWD_CLBU_NB-1]),
    .ls_ntt_bwd          (/*UNUSED*/),
    .ls_pbs_id           (out_clbu_fwd_pbs_id[FWD_CLBU_NB-1]),
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
    .twd_phi_ru         (twd_phi_ru_fwd[FWD_CLBU_NB-1][FWD_LS_DELTA-1:0]),
    .twd_phi_ru_vld     (twd_phi_ru_fwd_vld[FWD_CLBU_NB-1][FWD_LS_DELTA-1:0]),
    .twd_phi_ru_rdy     (twd_phi_ru_fwd_rdy[FWD_CLBU_NB-1][FWD_LS_DELTA-1:0]),
    // error
    .error_twd_phi      (fwd_clbu_error[FWD_CLBU_NB-1])
  );

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
    .clbu_pp_data            (out_clbu_fwd_data[FWD_CLBU_NB-1]),
    .clbu_pp_data_avail      (out_clbu_fwd_data_avail[FWD_CLBU_NB-1]),
    .clbu_pp_sob             (out_clbu_fwd_sob[FWD_CLBU_NB-1]),
    .clbu_pp_eob             (out_clbu_fwd_eob[FWD_CLBU_NB-1]),
    .clbu_pp_sol             (out_clbu_fwd_sol[FWD_CLBU_NB-1]),
    .clbu_pp_eol             (out_clbu_fwd_eol[FWD_CLBU_NB-1]),
    .clbu_pp_sos             (out_clbu_fwd_sos[FWD_CLBU_NB-1]),
    .clbu_pp_eos             (out_clbu_fwd_eos[FWD_CLBU_NB-1]),
    .clbu_pp_ntt_bwd         (1'b0), // forward
    .clbu_pp_pbs_id          (out_clbu_fwd_pbs_id[FWD_CLBU_NB-1]),
    .clbu_pp_ctrl_avail      (out_clbu_fwd_ctrl_avail[FWD_CLBU_NB-1]),
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
    .pp_error                (pp_error[0]),
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
      in_clbu_bwd_data_avail[0][i] = ntw_seq_fwd_ls_data_avail[i][0];

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
    .RS_DELTA             (FWD_RS_DELTA),
    .LS_DELTA             (FWD_LS_DELTA),
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
    .ntw_seq_data      (in_clbu_bwd_data[0]),
    .ntw_seq_data_avail(ntw_seq_fwd_ls_data_avail),
    .ntw_seq_sob       (in_clbu_bwd_sob[0]),
    .ntw_seq_eob       (in_clbu_bwd_eob[0]),
    .ntw_seq_sol       (in_clbu_bwd_sol[0]),
    .ntw_seq_eol       (in_clbu_bwd_eol[0]),
    .ntw_seq_sos       (in_clbu_bwd_sos[0]),
    .ntw_seq_eos       (in_clbu_bwd_eos[0]),
    .ntw_seq_pbs_id    (in_clbu_bwd_pbs_id[0]),
    .ntw_seq_ctrl_avail(in_clbu_bwd_ctrl_avail[0]),
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

  // ============================================================================================ //
  // Backward
  // ============================================================================================ //
  //== RS
  generate
    for (genvar gen_c = 0; gen_c < BWD_CLBU_NB-1; gen_c = gen_c + 1) begin : gen_bwd_rs_stage
      // ---------------------------------------------------------------------------------------- //
      // Cluster Butterfly Unit
      // ---------------------------------------------------------------------------------------- //
      ntt_core_wmm_clbu_pcg #(
        .OP_W            (OP_W),
        .MOD_NTT         (MOD_NTT),
        .R               (R),
        .PSI             (BWD_PSI),
        .S               (S),
        .RS_DELTA        (BWD_RS_DELTA),
        .LS_DELTA        (BWD_RS_DELTA),
        .RS_OUT_WITH_NTW (1'b1),
        .LS_OUT_WITH_NTW (1'b1), // Since LPB_NB = 1 : output on LS only
        .LPB_NB          (LPB_NB),
        .MOD_MULT_TYPE   (MOD_MULT_TYPE),
        .REDUCT_TYPE     (REDUCT_TYPE),
        .MULT_TYPE       (MULT_TYPE  )
      ) ntt_core_wmm_clbu_pcg_bwd_rs (
        // System
        .clk                (clk),
        .s_rst_n            (s_rst_n),
        // input
        .in_a         (in_clbu_bwd_data[gen_c]),
        .in_avail     (in_clbu_bwd_data_avail[gen_c]),
        .in_sob       (in_clbu_bwd_sob[gen_c]),
        .in_eob       (in_clbu_bwd_eob[gen_c]),
        .in_sol       (in_clbu_bwd_sol[gen_c]),
        .in_eol       (in_clbu_bwd_eol[gen_c]),
        .in_sos       (in_clbu_bwd_sos[gen_c]),
        .in_eos       (in_clbu_bwd_eos[gen_c]),
        .in_pbs_id    (in_clbu_bwd_pbs_id[gen_c]),
        .in_ntt_bwd   ('1),
        // last stage = only one used here since LPB_NB = 1
        .ls_z                (out_clbu_bwd_data[gen_c]),
        .ls_avail            (out_clbu_bwd_data_avail[gen_c]),
        .ls_sob              (out_clbu_bwd_sob[gen_c]),
        .ls_eob              (out_clbu_bwd_eob[gen_c]),
        .ls_sol              (out_clbu_bwd_sol[gen_c]),
        .ls_eol              (out_clbu_bwd_eol[gen_c]),
        .ls_sos              (out_clbu_bwd_sos[gen_c]),
        .ls_eos              (out_clbu_bwd_eos[gen_c]),
        .ls_ntt_bwd          (/*UNUSED*/),
        .ls_pbs_id           (out_clbu_bwd_pbs_id[gen_c]),
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
        .twd_phi_ru         (twd_phi_ru_bwd[gen_c][BWD_RS_DELTA-1:0]),
        .twd_phi_ru_vld     (twd_phi_ru_bwd_vld[gen_c][BWD_RS_DELTA-1:0]),
        .twd_phi_ru_rdy     (twd_phi_ru_bwd_rdy[gen_c][BWD_RS_DELTA-1:0]),
        // error
        .error_twd_phi      (bwd_clbu_error[gen_c])
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
        .S_INIT               (2*S-1 - gen_c*BWD_RS_DELTA),
        .S_DEC                ('0),
        .SEND_TO_SEQ          (1'b0),
        .TOKEN_W              (BATCH_TOKEN_W),
        .RS_DELTA             (BWD_RS_DELTA),
        .LS_DELTA             (BWD_LS_DELTA),
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
        .pp_rsntw_data     (out_clbu_bwd_data[gen_c]  ),
        .pp_rsntw_sob      (out_clbu_bwd_sob[gen_c]   ),
        .pp_rsntw_eob      (out_clbu_bwd_eob[gen_c]   ),
        .pp_rsntw_sol      (out_clbu_bwd_sol[gen_c]   ),
        .pp_rsntw_eol      (out_clbu_bwd_eol[gen_c]   ),
        .pp_rsntw_sos      (out_clbu_bwd_sos[gen_c]   ),
        .pp_rsntw_eos      (out_clbu_bwd_eos[gen_c]   ),
        .pp_rsntw_pbs_id   (out_clbu_bwd_pbs_id[gen_c]),
        .pp_rsntw_avail    (out_clbu_bwd_data_avail[gen_c][0] ),
        // network -> sequenccer
        .ntw_seq_data      (out_ntw_bwd_data[gen_c]),
        .ntw_seq_data_avail(out_ntw_bwd_data_avail[gen_c]),
        .ntw_seq_sob       (out_ntw_bwd_sob[gen_c]),
        .ntw_seq_eob       (out_ntw_bwd_eob[gen_c]),
        .ntw_seq_sol       (out_ntw_bwd_sol[gen_c]),
        .ntw_seq_eol       (out_ntw_bwd_eol[gen_c]),
        .ntw_seq_sos       (out_ntw_bwd_sos[gen_c]),
        .ntw_seq_eos       (out_ntw_bwd_eos[gen_c]),
        .ntw_seq_pbs_id    (out_ntw_bwd_pbs_id[gen_c]),
        .ntw_seq_ctrl_avail(out_ntw_bwd_ctrl_avail[gen_c]),
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

      assign in_clbu_bwd_data[gen_c+1]       = out_ntw_bwd_data[gen_c];
      assign in_clbu_bwd_data_avail[gen_c+1] = out_ntw_bwd_data_avail[gen_c];
      assign in_clbu_bwd_sob[gen_c+1]        = out_ntw_bwd_sob[gen_c];
      assign in_clbu_bwd_eob[gen_c+1]        = out_ntw_bwd_eob[gen_c];
      assign in_clbu_bwd_sol[gen_c+1]        = out_ntw_bwd_sol[gen_c];
      assign in_clbu_bwd_eol[gen_c+1]        = out_ntw_bwd_eol[gen_c];
      assign in_clbu_bwd_sos[gen_c+1]        = out_ntw_bwd_sos[gen_c];
      assign in_clbu_bwd_eos[gen_c+1]        = out_ntw_bwd_eos[gen_c];
      assign in_clbu_bwd_pbs_id[gen_c+1]     = out_ntw_bwd_pbs_id[gen_c];
      assign in_clbu_bwd_ctrl_avail[gen_c+1] = out_ntw_bwd_ctrl_avail[gen_c];
    end
  endgenerate
  
  //== LS
  // ---------------------------------------------------------------------------------------- //
  // Cluster Butterfly Unit
  // ---------------------------------------------------------------------------------------- //
  ntt_core_wmm_clbu_pcg #(
    .OP_W            (OP_W),
    .MOD_NTT         (MOD_NTT),
    .R               (R),
    .PSI             (BWD_PSI),
    .S               (S),
    .RS_DELTA        (BWD_LS_DELTA),
    .LS_DELTA        (BWD_LS_DELTA),
    .RS_OUT_WITH_NTW (1'b0),
    .LS_OUT_WITH_NTW (1'b0),
    .LPB_NB          (LPB_NB),
    .MOD_MULT_TYPE   (MOD_MULT_TYPE),
    .REDUCT_TYPE     (REDUCT_TYPE),
    .MULT_TYPE       (MULT_TYPE  )
  ) ntt_core_wmm_clbu_pcg_bwd_ls (
    // System
    .clk                (clk),
    .s_rst_n            (s_rst_n),
    // input
    .in_a               (in_clbu_bwd_data[BWD_CLBU_NB-1]),
    .in_avail           (in_clbu_bwd_data_avail[BWD_CLBU_NB-1]),
    .in_sob             (in_clbu_bwd_sob[BWD_CLBU_NB-1]),
    .in_eob             (in_clbu_bwd_eob[BWD_CLBU_NB-1]),
    .in_sol             (in_clbu_bwd_sol[BWD_CLBU_NB-1]),
    .in_eol             (in_clbu_bwd_eol[BWD_CLBU_NB-1]),
    .in_sos             (in_clbu_bwd_sos[BWD_CLBU_NB-1]),
    .in_eos             (in_clbu_bwd_eos[BWD_CLBU_NB-1]),
    .in_pbs_id          (in_clbu_bwd_pbs_id[BWD_CLBU_NB-1]),
    .in_ntt_bwd         ('1),
    // last stage = only one used here since LPB_NB = 1
    .ls_z               (out_clbu_bwd_data[BWD_CLBU_NB-1]),
    .ls_avail           (out_clbu_bwd_data_avail[BWD_CLBU_NB-1]),
    .ls_sob             (out_clbu_bwd_sob[BWD_CLBU_NB-1]),
    .ls_eob             (out_clbu_bwd_eob[BWD_CLBU_NB-1]),
    .ls_sol             (out_clbu_bwd_sol[BWD_CLBU_NB-1]),
    .ls_eol             (out_clbu_bwd_eol[BWD_CLBU_NB-1]),
    .ls_sos             (out_clbu_bwd_sos[BWD_CLBU_NB-1]),
    .ls_eos             (out_clbu_bwd_eos[BWD_CLBU_NB-1]),
    .ls_ntt_bwd         (/*UNUSED*/),
    .ls_pbs_id          (out_clbu_bwd_pbs_id[BWD_CLBU_NB-1]),
    // regular stage
    .rs_z               (/*UNUSED*/),
    .rs_avail           (/*UNUSED*/),
    .rs_sob             (/*UNUSED*/),
    .rs_eob             (/*UNUSED*/),
    .rs_sol             (/*UNUSED*/),
    .rs_eol             (/*UNUSED*/),
    .rs_sos             (/*UNUSED*/),
    .rs_eos             (/*UNUSED*/),
    .rs_ntt_bwd         (/*UNUSED*/),
    .rs_pbs_id          (/*UNUSED*/),
    // twiddles
    .twd_omg_ru_r_pow   (twd_omg_ru_r_pow),
    .twd_phi_ru         (twd_phi_ru_bwd[BWD_CLBU_NB-1][BWD_LS_DELTA-1:0]),
    .twd_phi_ru_vld     (twd_phi_ru_bwd_vld[BWD_CLBU_NB-1][BWD_LS_DELTA-1:0]),
    .twd_phi_ru_rdy     (twd_phi_ru_bwd_rdy[BWD_CLBU_NB-1][BWD_LS_DELTA-1:0]),
    // error
    .error_twd_phi      (bwd_clbu_error[BWD_CLBU_NB-1])
  );

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
    .clbu_pp_data            (out_clbu_bwd_data[BWD_CLBU_NB-1]),
    .clbu_pp_data_avail      (out_clbu_bwd_data_avail[BWD_CLBU_NB-1]),
    .clbu_pp_sob             (out_clbu_bwd_sob[BWD_CLBU_NB-1]),
    .clbu_pp_eob             (out_clbu_bwd_eob[BWD_CLBU_NB-1]),
    .clbu_pp_sol             (out_clbu_bwd_sol[BWD_CLBU_NB-1]),
    .clbu_pp_eol             (out_clbu_bwd_eol[BWD_CLBU_NB-1]),
    .clbu_pp_sos             (out_clbu_bwd_sos[BWD_CLBU_NB-1]),
    .clbu_pp_eos             (out_clbu_bwd_eos[BWD_CLBU_NB-1]),
    .clbu_pp_ntt_bwd         (1'b1), // backward
    .clbu_pp_pbs_id          (out_clbu_bwd_pbs_id[BWD_CLBU_NB-1]),
    .clbu_pp_ctrl_avail      (out_clbu_bwd_ctrl_avail[BWD_CLBU_NB-1]),
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
    .pp_error                (pp_error[1]),
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
    .RS_DELTA             (BWD_RS_DELTA),
    .LS_DELTA             (BWD_LS_DELTA),
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

  
  assign ntt_error[CLBU_ERR_OFS] = (|fwd_clbu_error) | (|bwd_clbu_error);
  assign ntt_error[PP_ERR_OFS]   = |pp_error;


  // ============================================================================================== --
  // Reformat output
  // ============================================================================================== --
  generate
    if (BWD_PSI_DIV == 1) begin : gen_bwd_psi_div_eq_1
      assign ntt_acc_data            = out_ntw_acc_data;
      assign ntt_acc_data_avail      = out_ntw_acc_data_avail;
      assign ntt_acc_sob             = out_ntw_acc_sob;
      assign ntt_acc_eob             = out_ntw_acc_eob;
      assign ntt_acc_sol             = out_ntw_acc_sol;
      assign ntt_acc_eol             = out_ntw_acc_eol;
      assign ntt_acc_sog             = out_ntw_acc_sog;
      assign ntt_acc_eog             = out_ntw_acc_eog;
      assign ntt_acc_pbs_id          = out_ntw_acc_pbs_id;
      assign ntt_acc_ctrl_avail      = out_ntw_acc_ctrl_avail;
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

      assign ntt_acc_data            = {out_ntw_acc_data, buf_ntw_acc_out_data};
      assign ntt_acc_data_avail      = {BWD_PSI_DIV{out_ntw_acc_data_avail & last_out_cnt_v}};
      assign ntt_acc_sob             = buf_ntw_acc_sob && first_out_lvl_cnt;
      assign ntt_acc_eob             = out_ntw_acc_eob;
      assign ntt_acc_sol             = first_out_lvl_cnt;
      assign ntt_acc_eol             = last_out_lvl_cnt;
      assign ntt_acc_sog             = buf_ntw_acc_sog && first_out_lvl_cnt;
      assign ntt_acc_eog             = out_ntw_acc_eog;
      assign ntt_acc_pbs_id          = out_ntw_acc_pbs_id;
      assign ntt_acc_ctrl_avail      = out_ntw_acc_ctrl_avail & last_out_cnt;
      
    end // gen_bwd_psi_div_gt_1
  endgenerate

endmodule
