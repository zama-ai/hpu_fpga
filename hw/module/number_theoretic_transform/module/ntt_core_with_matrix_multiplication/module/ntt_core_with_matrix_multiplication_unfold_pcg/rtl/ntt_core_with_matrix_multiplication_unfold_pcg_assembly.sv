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
// This module is used to test the ntt_core_with_matrix_multiplication_unfold_pcg partition.
// It supports only FWD_DELTA and BWD_DELTA > 1
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_with_matrix_multiplication_unfold_pcg_assembly
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;
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
  localparam int           BWD_PSI       = PSI / BWD_PSI_DIV
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
  input  [S-1:0][PSI-1:0][    R-1:1][     OP_W-1:0] twd_phi_ru_fwd, // [0] is for the 1rst stage
  input  [S-1:0][PSI-1:0]                           twd_phi_ru_fwd_vld,
  output [S-1:0][PSI-1:0]                           twd_phi_ru_fwd_rdy,
  input  [S-1:0][BWD_PSI-1:0][R-1:1][     OP_W-1:0] twd_phi_ru_bwd,
  input  [S-1:0][BWD_PSI-1:0]                       twd_phi_ru_bwd_vld,
  output [S-1:0][BWD_PSI-1:0]                       twd_phi_ru_bwd_rdy,
  input           [BWD_PSI-1:0][    R-1:0][     OP_W-1:0] twd_intt_final,
  input           [BWD_PSI-1:0][    R-1:0]                twd_intt_final_vld,
  output          [BWD_PSI-1:0][    R-1:0]                twd_intt_final_rdy,
  // Matrix factors : BSK
  input  [PSI-1:0][  R-1:0][GLWE_K_P1-1:0][     OP_W-1:0] bsk,
  input  [PSI-1:0][  R-1:0][GLWE_K_P1-1:0]                bsk_vld,
  output [PSI-1:0][  R-1:0][GLWE_K_P1-1:0]                bsk_rdy,
  // Error
  output logic                                 [  ERROR_W-1:0] ntt_error
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam int FWD_LS_DELTA = S % FWD_DELTA == 0 ? FWD_DELTA : S % FWD_DELTA;
  localparam int FWD_RS_DELTA = FWD_DELTA;

  localparam int FWD_D_NB_0   = FWD_RS_DELTA / 2;
  localparam int FWD_D_NB_1   = FWD_RS_DELTA - FWD_D_NB_0;
  localparam int FWD_D_NB_2   = FWD_LS_DELTA / 2;
  localparam int FWD_D_NB_3   = FWD_LS_DELTA - FWD_D_NB_2;

  localparam int FWD_D_INIT_0 = 0;
  localparam int FWD_D_INIT_1 = FWD_D_INIT_0 + FWD_D_NB_0;
  localparam int FWD_D_INIT_2 = 0;
  localparam int FWD_D_INIT_3 = FWD_D_INIT_2 + FWD_D_NB_2;

  localparam int FWD_S_INIT_0 = S-1;
  localparam int FWD_S_INIT_1 = FWD_S_INIT_0 - FWD_D_NB_0;
  localparam int FWD_S_INIT_2 = FWD_S_INIT_1 - FWD_D_NB_1;
  localparam int FWD_S_INIT_3 = FWD_S_INIT_2 - FWD_D_NB_2;

  localparam int FWD_TWD_OFS_0 = 0;
  localparam int FWD_TWD_OFS_1 = FWD_TWD_OFS_0 + FWD_D_NB_0;
  localparam int FWD_TWD_OFS_2 = FWD_TWD_OFS_1 + FWD_D_NB_1;
  localparam int FWD_TWD_OFS_3 = FWD_TWD_OFS_2 + FWD_D_NB_2;

  localparam int BWD_LS_DELTA = S % BWD_DELTA == 0 ? BWD_DELTA : S % BWD_DELTA;
  localparam int BWD_RS_DELTA = BWD_DELTA;

  localparam int BWD_D_NB_0   = BWD_RS_DELTA > 3 ? BWD_RS_DELTA/3 : 1;
  localparam int BWD_D_NB_1   = BWD_RS_DELTA > 3 ? BWD_RS_DELTA/3 : 1;
  localparam int BWD_D_NB_2   = BWD_RS_DELTA - BWD_D_NB_0 - BWD_D_NB_1;
  localparam int BWD_D_NB_3   = BWD_LS_DELTA/2;
  localparam int BWD_D_NB_4   = BWD_LS_DELTA - BWD_D_NB_3;

  localparam int BWD_D_INIT_0 = 0;
  localparam int BWD_D_INIT_1 = BWD_D_INIT_0 + BWD_D_NB_0;
  localparam int BWD_D_INIT_2 = BWD_D_INIT_1 + BWD_D_NB_1;
  localparam int BWD_D_INIT_3 = 0;
  localparam int BWD_D_INIT_4 = BWD_D_INIT_3 + BWD_D_NB_3;

  localparam int BWD_S_INIT_0 = 2*S-1;
  localparam int BWD_S_INIT_1 = BWD_S_INIT_0 - BWD_D_NB_0;
  localparam int BWD_S_INIT_2 = BWD_S_INIT_1 - BWD_D_NB_1;
  localparam int BWD_S_INIT_3 = BWD_S_INIT_2 - BWD_D_NB_2;
  localparam int BWD_S_INIT_4 = BWD_S_INIT_3 - BWD_D_NB_3;

  localparam int BWD_TWD_OFS_0 = 0;
  localparam int BWD_TWD_OFS_1 = BWD_TWD_OFS_0 + BWD_D_NB_0;
  localparam int BWD_TWD_OFS_2 = BWD_TWD_OFS_1 + BWD_D_NB_1;
  localparam int BWD_TWD_OFS_3 = BWD_TWD_OFS_2 + BWD_D_NB_2;
  localparam int BWD_TWD_OFS_4 = BWD_TWD_OFS_3 + BWD_D_NB_3;


  // Check parameters
  generate
    if (S < 5) begin : __UNSUPPORTED_S_
      $fatal(1,"> ERROR: Unsupported S. For this test assembly, we need S >= 5 ");
    end
    if (FWD_DELTA < 2) begin : __UNSUPPORTED_FWD_DELTA_
      $fatal(1, "> ERROR: Unsupported FWD_DELTA values. For this test assembly, we need FWD_DELTA >= 2");
    end
    if (BWD_DELTA < 3) begin : __UNSUPPORTED_BWD_DELTA_
      $fatal(1, "> ERROR: Unsupported BWD_DELTA values. For this test assembly, we need BWD_DELTA >= 3");
    end
  endgenerate

  // =========================================================================================== //
  // ntt_core_with_matrix_multiplication_unfold_pcg
  // =========================================================================================== //
  // ------------------------------------------------------------------------------------------- --
  // Signals
  // ------------------------------------------------------------------------------------------- --
  // seq -> clbu
  logic [PSI-1:0][R-1:0][OP_W-1:0]                       seq_clbu_data;
  logic [PSI-1:0]                                        seq_clbu_data_avail;
  logic                                                  seq_clbu_sob;
  logic                                                  seq_clbu_eob;
  logic                                                  seq_clbu_sol;
  logic                                                  seq_clbu_eol;
  logic                                                  seq_clbu_sos;
  logic                                                  seq_clbu_eos;
  logic [BPBS_ID_W-1:0]                                   seq_clbu_pbs_id;
  logic                                                  seq_clbu_ntt_bwd;
  logic                                                  seq_clbu_ctrl_avail;


  // fwd clbu output logic - used if LOCAL_DELTA < DELTA
  logic [3:0][PSI-1:0][R-1:0][OP_W-1:0]                  out_clbu_fwd_data;
  logic [3:0][PSI-1:0]                                   out_clbu_fwd_data_avail;
  logic [3:0]                                            out_clbu_fwd_sob;
  logic [2:0]                                            out_clbu_fwd_eob;
  logic [2:0]                                            out_clbu_fwd_sol;
  logic [2:0]                                            out_clbu_fwd_eol;
  logic [2:0]                                            out_clbu_fwd_sos;
  logic [2:0]                                            out_clbu_fwd_eos;
  logic [2:0][BPBS_ID_W-1:0]                              out_clbu_fwd_pbs_id;
  logic [2:0]                                            out_clbu_fwd_ctrl_avail;

  // fwd ntw output logic - used if LOCAL_DELTA = DELTA and not last stage
  logic [2:0][PSI-1:0][R-1:0][OP_W-1:0]                  out_ntw_fwd_data;
  logic [2:0][PSI-1:0][R-1:0]                            out_ntw_fwd_data_avail;
  logic [2:0][PSI-1:0]                                   out_ntw_fwd_data_avail_tmp;
  logic [2:0]                                            out_ntw_fwd_sob;
  logic [2:0]                                            out_ntw_fwd_eob;
  logic [2:0]                                            out_ntw_fwd_sol;
  logic [2:0]                                            out_ntw_fwd_eol;
  logic [2:0]                                            out_ntw_fwd_sos;
  logic [2:0]                                            out_ntw_fwd_eos;
  logic [2:0][BPBS_ID_W-1:0]                              out_ntw_fwd_pbs_id;
  logic [2:0]                                            out_ntw_fwd_ctrl_avail;

  // bwd clbu input  logic- used if LOCAL_DELTA = DELTA and last stage
  logic [BWD_PSI-1:0][R-1:0][OP_W-1:0]                   in_clbu_bwd_data;
  logic [BWD_PSI-1:0]                                    in_clbu_bwd_data_avail;
  logic                                                  in_clbu_bwd_sob;
  logic                                                  in_clbu_bwd_eob;
  logic                                                  in_clbu_bwd_sol;
  logic                                                  in_clbu_bwd_eol;
  logic                                                  in_clbu_bwd_sos;
  logic                                                  in_clbu_bwd_eos;
  logic [BPBS_ID_W-1:0]                                   in_clbu_bwd_pbs_id;
  logic                                                  in_clbu_bwd_ctrl_avail;

  // bwd clbu output - used if LOCAL_DELTA < DELTA
  logic [3:0][BWD_PSI-1:0][R-1:0][OP_W-1:0]              out_clbu_bwd_data;
  logic [3:0][BWD_PSI-1:0]                               out_clbu_bwd_data_avail;
  logic [3:0]                                            out_clbu_bwd_sob;
  logic [3:0]                                            out_clbu_bwd_eob;
  logic [3:0]                                            out_clbu_bwd_sol;
  logic [3:0]                                            out_clbu_bwd_eol;
  logic [3:0]                                            out_clbu_bwd_sos;
  logic [3:0]                                            out_clbu_bwd_eos;
  logic [3:0][BPBS_ID_W-1:0]                              out_clbu_bwd_pbs_id;
  logic [3:0]                                            out_clbu_bwd_ctrl_avail;

  // bwd ntw output - used if LOCAL_DELTA = DELTA and not last stage
  logic [3:0][BWD_PSI-1:0][R-1:0][OP_W-1:0]              out_ntw_bwd_data;
  logic [3:0][BWD_PSI-1:0][R-1:0]                        out_ntw_bwd_data_avail;
  logic [3:0][BWD_PSI-1:0]                               out_ntw_bwd_data_avail_tmp;
  logic [3:0]                                            out_ntw_bwd_sob;
  logic [3:0]                                            out_ntw_bwd_eob;
  logic [3:0]                                            out_ntw_bwd_sol;
  logic [3:0]                                            out_ntw_bwd_eol;
  logic [3:0]                                            out_ntw_bwd_sos;
  logic [3:0]                                            out_ntw_bwd_eos;
  logic [3:0][BPBS_ID_W-1:0]                              out_ntw_bwd_pbs_id;
  logic [3:0]                                            out_ntw_bwd_ctrl_avail;

  logic [3:0][ERROR_W-1:0]                               ntt_error_fwd;
  logic [4:0][ERROR_W-1:0]                               ntt_error_bwd;

  // ------------------------------------------------------------------------------------------- --
  // error
  // ------------------------------------------------------------------------------------------- --
  always_comb begin
    var [ERROR_W-1:0] tmp;
    tmp = '0;
    for (int i=0; i<4; i=i+1)
      tmp = tmp | ntt_error_fwd[i];
    for (int i=0; i<5; i=i+1)
      tmp = tmp | ntt_error_bwd[i];
    ntt_error = tmp;
  end

  // ------------------------------------------------------------------------------------------- --
  // Intermediate values
  // ------------------------------------------------------------------------------------------- --
  always_comb begin
    for (int p=0; p<PSI; p=p+1) begin
      for (int i=0; i<3; i=i+1)
        out_ntw_fwd_data_avail_tmp[i][p] = out_ntw_fwd_data_avail[i][p][0];
      for (int i=0; i<4; i=i+1)
        out_ntw_bwd_data_avail_tmp[i][p] = out_ntw_bwd_data_avail[i][p][0];
    end
  end

  // ------------------------------------------------------------------------------------------- --
  // Start
  // ------------------------------------------------------------------------------------------- --
  ntt_core_with_matrix_multiplication_unfold_pcg_head
  #(
    .OP_W        (OP_W       ),
    .R           (R          ),
    .PSI         (PSI        ),
    .S           (S          ),
    .RAM_LATENCY (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg_head (
    .clk                        (clk),
    .s_rst_n                    (s_rst_n),

    .decomp_ntt_data            (decomp_ntt_data),
    .decomp_ntt_data_vld        (decomp_ntt_data_vld),
    .decomp_ntt_data_rdy        (decomp_ntt_data_rdy),
    .decomp_ntt_sob             (decomp_ntt_sob),
    .decomp_ntt_eob             (decomp_ntt_eob),
    .decomp_ntt_sol             (decomp_ntt_sol),
    .decomp_ntt_eol             (decomp_ntt_eol),
    .decomp_ntt_sog             (decomp_ntt_sog),
    .decomp_ntt_eog             (decomp_ntt_eog),
    .decomp_ntt_pbs_id          (decomp_ntt_pbs_id),
    .decomp_ntt_last_pbs        (decomp_ntt_last_pbs),
    .decomp_ntt_full_throughput (decomp_ntt_full_throughput),
    .decomp_ntt_ctrl_vld        (decomp_ntt_ctrl_vld),
    .decomp_ntt_ctrl_rdy        (decomp_ntt_ctrl_rdy),

    .seq_clbu_data              (seq_clbu_data),
    .seq_clbu_data_avail        (seq_clbu_data_avail),
    .seq_clbu_sob               (seq_clbu_sob),
    .seq_clbu_eob               (seq_clbu_eob),
    .seq_clbu_sol               (seq_clbu_sol),
    .seq_clbu_eol               (seq_clbu_eol),
    .seq_clbu_sos               (seq_clbu_sos),
    .seq_clbu_eos               (seq_clbu_eos),
    .seq_clbu_pbs_id            (seq_clbu_pbs_id),
    .seq_clbu_ntt_bwd           (seq_clbu_ntt_bwd),
    .seq_clbu_ctrl_avail        (seq_clbu_ctrl_avail)
  );

  // ------------------------------------------------------------------------------------------- --
  // Forward
  // ------------------------------------------------------------------------------------------- --
  ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .MOD_NTT_TYPE  (MOD_NTT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .DELTA         (FWD_RS_DELTA),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .S_INIT        (FWD_S_INIT_0),
    .D_INIT        (FWD_D_INIT_0),
    .D_NB          (FWD_D_NB_0),
    .IS_LS         (0),
    .RAM_LATENCY   (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd_0 (
    .clk                     (clk),
    .s_rst_n                 (s_rst_n),

    .in_clbu_fwd_data        (seq_clbu_data),
    .in_clbu_fwd_data_avail  (seq_clbu_data_avail),
    .in_clbu_fwd_sob         (seq_clbu_sob),
    .in_clbu_fwd_eob         (seq_clbu_eob),
    .in_clbu_fwd_sol         (seq_clbu_sol),
    .in_clbu_fwd_eol         (seq_clbu_eol),
    .in_clbu_fwd_sos         (seq_clbu_sos),
    .in_clbu_fwd_eos         (seq_clbu_eos),
    .in_clbu_fwd_pbs_id      (seq_clbu_pbs_id),
    .in_clbu_fwd_ctrl_avail  (seq_clbu_ctrl_avail),


    .out_clbu_fwd_data       (out_clbu_fwd_data[0]),
    .out_clbu_fwd_data_avail (out_clbu_fwd_data_avail[0]),
    .out_clbu_fwd_sob        (out_clbu_fwd_sob[0]),
    .out_clbu_fwd_eob        (out_clbu_fwd_eob[0]),
    .out_clbu_fwd_sol        (out_clbu_fwd_sol[0]),
    .out_clbu_fwd_eol        (out_clbu_fwd_eol[0]),
    .out_clbu_fwd_sos        (out_clbu_fwd_sos[0]),
    .out_clbu_fwd_eos        (out_clbu_fwd_eos[0]),
    .out_clbu_fwd_pbs_id     (out_clbu_fwd_pbs_id[0]),
    .out_clbu_fwd_ctrl_avail (out_clbu_fwd_ctrl_avail[0]),

    .out_ntw_fwd_data        (/*UNUSED*/),
    .out_ntw_fwd_data_avail  (/*UNUSED*/),
    .out_ntw_fwd_sob         (/*UNUSED*/),
    .out_ntw_fwd_eob         (/*UNUSED*/),
    .out_ntw_fwd_sol         (/*UNUSED*/),
    .out_ntw_fwd_eol         (/*UNUSED*/),
    .out_ntw_fwd_sos         (/*UNUSED*/),
    .out_ntw_fwd_eos         (/*UNUSED*/),
    .out_ntw_fwd_pbs_id      (/*UNUSED*/),
    .out_ntw_fwd_ctrl_avail  (/*UNUSED*/),

    .in_clbu_bwd_data        (/*UNUSED*/),
    .in_clbu_bwd_data_avail  (/*UNUSED*/),
    .in_clbu_bwd_sob         (/*UNUSED*/),
    .in_clbu_bwd_eob         (/*UNUSED*/),
    .in_clbu_bwd_sol         (/*UNUSED*/),
    .in_clbu_bwd_eol         (/*UNUSED*/),
    .in_clbu_bwd_sos         (/*UNUSED*/),
    .in_clbu_bwd_eos         (/*UNUSED*/),
    .in_clbu_bwd_pbs_id      (/*UNUSED*/),
    .in_clbu_bwd_ctrl_avail  (/*UNUSED*/),

    .twd_omg_ru_r_pow        (twd_omg_ru_r_pow),

    .twd_phi_ru_fwd          (twd_phi_ru_fwd[FWD_TWD_OFS_0+:FWD_D_NB_0]),
    .twd_phi_ru_fwd_vld      (twd_phi_ru_fwd_vld[FWD_TWD_OFS_0+:FWD_D_NB_0]),
    .twd_phi_ru_fwd_rdy      (twd_phi_ru_fwd_rdy[FWD_TWD_OFS_0+:FWD_D_NB_0]),

    .bsk                     (/*UNUSED*/),
    .bsk_vld                 (/*UNUSED*/),
    .bsk_rdy                 (/*UNUSED*/),

    .ntt_error               (ntt_error_fwd[0])
  );

  ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .MOD_NTT_TYPE  (MOD_NTT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .DELTA         (FWD_RS_DELTA),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .S_INIT        (FWD_S_INIT_1),
    .D_INIT        (FWD_D_INIT_1),
    .D_NB          (FWD_D_NB_1),
    .IS_LS         (0),
    .RAM_LATENCY   (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd_1 (
    .clk                     (clk),
    .s_rst_n                 (s_rst_n),

    .in_clbu_fwd_data        (out_clbu_fwd_data[0]),
    .in_clbu_fwd_data_avail  (out_clbu_fwd_data_avail[0]),
    .in_clbu_fwd_sob         (out_clbu_fwd_sob[0]),
    .in_clbu_fwd_eob         (out_clbu_fwd_eob[0]),
    .in_clbu_fwd_sol         (out_clbu_fwd_sol[0]),
    .in_clbu_fwd_eol         (out_clbu_fwd_eol[0]),
    .in_clbu_fwd_sos         (out_clbu_fwd_sos[0]),
    .in_clbu_fwd_eos         (out_clbu_fwd_eos[0]),
    .in_clbu_fwd_pbs_id      (out_clbu_fwd_pbs_id[0]),
    .in_clbu_fwd_ctrl_avail  (out_clbu_fwd_ctrl_avail[0]),


    .out_clbu_fwd_data       (/*UNUSED*/),
    .out_clbu_fwd_data_avail (/*UNUSED*/),
    .out_clbu_fwd_sob        (/*UNUSED*/),
    .out_clbu_fwd_eob        (/*UNUSED*/),
    .out_clbu_fwd_sol        (/*UNUSED*/),
    .out_clbu_fwd_eol        (/*UNUSED*/),
    .out_clbu_fwd_sos        (/*UNUSED*/),
    .out_clbu_fwd_eos        (/*UNUSED*/),
    .out_clbu_fwd_pbs_id     (/*UNUSED*/),
    .out_clbu_fwd_ctrl_avail (/*UNUSED*/),

    .out_ntw_fwd_data        (out_ntw_fwd_data[1]),
    .out_ntw_fwd_data_avail  (out_ntw_fwd_data_avail[1]),
    .out_ntw_fwd_sob         (out_ntw_fwd_sob[1]),
    .out_ntw_fwd_eob         (out_ntw_fwd_eob[1]),
    .out_ntw_fwd_sol         (out_ntw_fwd_sol[1]),
    .out_ntw_fwd_eol         (out_ntw_fwd_eol[1]),
    .out_ntw_fwd_sos         (out_ntw_fwd_sos[1]),
    .out_ntw_fwd_eos         (out_ntw_fwd_eos[1]),
    .out_ntw_fwd_pbs_id      (out_ntw_fwd_pbs_id[1]),
    .out_ntw_fwd_ctrl_avail  (out_ntw_fwd_ctrl_avail[1]),

    .in_clbu_bwd_data        (/*UNUSED*/),
    .in_clbu_bwd_data_avail  (/*UNUSED*/),
    .in_clbu_bwd_sob         (/*UNUSED*/),
    .in_clbu_bwd_eob         (/*UNUSED*/),
    .in_clbu_bwd_sol         (/*UNUSED*/),
    .in_clbu_bwd_eol         (/*UNUSED*/),
    .in_clbu_bwd_sos         (/*UNUSED*/),
    .in_clbu_bwd_eos         (/*UNUSED*/),
    .in_clbu_bwd_pbs_id      (/*UNUSED*/),
    .in_clbu_bwd_ctrl_avail  (/*UNUSED*/),

    .twd_omg_ru_r_pow        (twd_omg_ru_r_pow),

    .twd_phi_ru_fwd          (twd_phi_ru_fwd[FWD_TWD_OFS_1+:FWD_D_NB_1]),
    .twd_phi_ru_fwd_vld      (twd_phi_ru_fwd_vld[FWD_TWD_OFS_1+:FWD_D_NB_1]),
    .twd_phi_ru_fwd_rdy      (twd_phi_ru_fwd_rdy[FWD_TWD_OFS_1+:FWD_D_NB_1]),

    .bsk                     (/*UNUSED*/),
    .bsk_vld                 (/*UNUSED*/),
    .bsk_rdy                 (/*UNUSED*/),

    .ntt_error               (ntt_error_fwd[1])
  );

  ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .MOD_NTT_TYPE  (MOD_NTT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .DELTA         (FWD_LS_DELTA),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .S_INIT        (FWD_S_INIT_2),
    .D_INIT        (FWD_D_INIT_2),
    .D_NB          (FWD_D_NB_2),
    .IS_LS         (1),
    .USE_PP        (1),
    .RAM_LATENCY   (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd_2 (
    .clk                     (clk),
    .s_rst_n                 (s_rst_n),

    .in_clbu_fwd_data        (out_ntw_fwd_data[1]),
    .in_clbu_fwd_data_avail  (out_ntw_fwd_data_avail_tmp[1]),
    .in_clbu_fwd_sob         (out_ntw_fwd_sob[1]),
    .in_clbu_fwd_eob         (out_ntw_fwd_eob[1]),
    .in_clbu_fwd_sol         (out_ntw_fwd_sol[1]),
    .in_clbu_fwd_eol         (out_ntw_fwd_eol[1]),
    .in_clbu_fwd_sos         (out_ntw_fwd_sos[1]),
    .in_clbu_fwd_eos         (out_ntw_fwd_eos[1]),
    .in_clbu_fwd_pbs_id      (out_ntw_fwd_pbs_id[1]),
    .in_clbu_fwd_ctrl_avail  (out_ntw_fwd_ctrl_avail[1]),


    .out_clbu_fwd_data       (out_clbu_fwd_data[2]),
    .out_clbu_fwd_data_avail (out_clbu_fwd_data_avail[2]),
    .out_clbu_fwd_sob        (out_clbu_fwd_sob[2]),
    .out_clbu_fwd_eob        (out_clbu_fwd_eob[2]),
    .out_clbu_fwd_sol        (out_clbu_fwd_sol[2]),
    .out_clbu_fwd_eol        (out_clbu_fwd_eol[2]),
    .out_clbu_fwd_sos        (out_clbu_fwd_sos[2]),
    .out_clbu_fwd_eos        (out_clbu_fwd_eos[2]),
    .out_clbu_fwd_pbs_id     (out_clbu_fwd_pbs_id[2]),
    .out_clbu_fwd_ctrl_avail (out_clbu_fwd_ctrl_avail[2]),

    .out_ntw_fwd_data        (/*UNUSED*/),
    .out_ntw_fwd_data_avail  (/*UNUSED*/),
    .out_ntw_fwd_sob         (/*UNUSED*/),
    .out_ntw_fwd_eob         (/*UNUSED*/),
    .out_ntw_fwd_sol         (/*UNUSED*/),
    .out_ntw_fwd_eol         (/*UNUSED*/),
    .out_ntw_fwd_sos         (/*UNUSED*/),
    .out_ntw_fwd_eos         (/*UNUSED*/),
    .out_ntw_fwd_pbs_id      (/*UNUSED*/),
    .out_ntw_fwd_ctrl_avail  (/*UNUSED*/),

    .in_clbu_bwd_data        (/*UNUSED*/),
    .in_clbu_bwd_data_avail  (/*UNUSED*/),
    .in_clbu_bwd_sob         (/*UNUSED*/),
    .in_clbu_bwd_eob         (/*UNUSED*/),
    .in_clbu_bwd_sol         (/*UNUSED*/),
    .in_clbu_bwd_eol         (/*UNUSED*/),
    .in_clbu_bwd_sos         (/*UNUSED*/),
    .in_clbu_bwd_eos         (/*UNUSED*/),
    .in_clbu_bwd_pbs_id      (/*UNUSED*/),
    .in_clbu_bwd_ctrl_avail  (/*UNUSED*/),

    .twd_omg_ru_r_pow        (twd_omg_ru_r_pow),

    .twd_phi_ru_fwd          (twd_phi_ru_fwd[FWD_TWD_OFS_2+:FWD_D_NB_2]),
    .twd_phi_ru_fwd_vld      (twd_phi_ru_fwd_vld[FWD_TWD_OFS_2+:FWD_D_NB_2]),
    .twd_phi_ru_fwd_rdy      (twd_phi_ru_fwd_rdy[FWD_TWD_OFS_2+:FWD_D_NB_2]),

    .bsk                     (/*UNUSED*/),
    .bsk_vld                 (/*UNUSED*/),
    .bsk_rdy                 (/*UNUSED*/),

    .ntt_error               (ntt_error_fwd[2])
  );

  ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .MOD_NTT_TYPE  (MOD_NTT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .DELTA         (FWD_LS_DELTA),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .S_INIT        (FWD_S_INIT_3),
    .D_INIT        (FWD_D_INIT_3),
    .D_NB          (FWD_D_NB_3),
    .IS_LS         (1),
    .USE_PP        (1),
    .RAM_LATENCY   (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd_3 (
    .clk                     (clk),
    .s_rst_n                 (s_rst_n),

    .in_clbu_fwd_data        (out_clbu_fwd_data[2]),
    .in_clbu_fwd_data_avail  (out_clbu_fwd_data_avail[2]),
    .in_clbu_fwd_sob         (out_clbu_fwd_sob[2]),
    .in_clbu_fwd_eob         (out_clbu_fwd_eob[2]),
    .in_clbu_fwd_sol         (out_clbu_fwd_sol[2]),
    .in_clbu_fwd_eol         (out_clbu_fwd_eol[2]),
    .in_clbu_fwd_sos         (out_clbu_fwd_sos[2]),
    .in_clbu_fwd_eos         (out_clbu_fwd_eos[2]),
    .in_clbu_fwd_pbs_id      (out_clbu_fwd_pbs_id[2]),
    .in_clbu_fwd_ctrl_avail  (out_clbu_fwd_ctrl_avail[2]),

    .out_clbu_fwd_data       (/*UNUSED*/),
    .out_clbu_fwd_data_avail (/*UNUSED*/),
    .out_clbu_fwd_sob        (/*UNUSED*/),
    .out_clbu_fwd_eob        (/*UNUSED*/),
    .out_clbu_fwd_sol        (/*UNUSED*/),
    .out_clbu_fwd_eol        (/*UNUSED*/),
    .out_clbu_fwd_sos        (/*UNUSED*/),
    .out_clbu_fwd_eos        (/*UNUSED*/),
    .out_clbu_fwd_pbs_id     (/*UNUSED*/),
    .out_clbu_fwd_ctrl_avail (/*UNUSED*/),

    .out_ntw_fwd_data        (/*UNUSED*/),
    .out_ntw_fwd_data_avail  (/*UNUSED*/),
    .out_ntw_fwd_sob         (/*UNUSED*/),
    .out_ntw_fwd_eob         (/*UNUSED*/),
    .out_ntw_fwd_sol         (/*UNUSED*/),
    .out_ntw_fwd_eol         (/*UNUSED*/),
    .out_ntw_fwd_sos         (/*UNUSED*/),
    .out_ntw_fwd_eos         (/*UNUSED*/),
    .out_ntw_fwd_pbs_id      (/*UNUSED*/),
    .out_ntw_fwd_ctrl_avail  (/*UNUSED*/),

    .in_clbu_bwd_data        (in_clbu_bwd_data),
    .in_clbu_bwd_data_avail  (in_clbu_bwd_data_avail),
    .in_clbu_bwd_sob         (in_clbu_bwd_sob),
    .in_clbu_bwd_eob         (in_clbu_bwd_eob),
    .in_clbu_bwd_sol         (in_clbu_bwd_sol),
    .in_clbu_bwd_eol         (in_clbu_bwd_eol),
    .in_clbu_bwd_sos         (in_clbu_bwd_sos),
    .in_clbu_bwd_eos         (in_clbu_bwd_eos),
    .in_clbu_bwd_pbs_id      (in_clbu_bwd_pbs_id),
    .in_clbu_bwd_ctrl_avail  (in_clbu_bwd_ctrl_avail),

    .twd_omg_ru_r_pow        (twd_omg_ru_r_pow),

    .twd_phi_ru_fwd          (twd_phi_ru_fwd[FWD_TWD_OFS_3+:FWD_D_NB_3]),
    .twd_phi_ru_fwd_vld      (twd_phi_ru_fwd_vld[FWD_TWD_OFS_3+:FWD_D_NB_3]),
    .twd_phi_ru_fwd_rdy      (twd_phi_ru_fwd_rdy[FWD_TWD_OFS_3+:FWD_D_NB_3]),

    .bsk                     (bsk),
    .bsk_vld                 (bsk_vld),
    .bsk_rdy                 (bsk_rdy),

    .ntt_error               (ntt_error_fwd[3])
  );

  // ------------------------------------------------------------------------------------------- --
  // Backward
  // ------------------------------------------------------------------------------------------- --
 ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .MOD_NTT_TYPE  (MOD_NTT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .DELTA         (BWD_RS_DELTA),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .S_INIT        (BWD_S_INIT_0),
    .D_INIT        (BWD_D_INIT_0),
    .D_NB          (BWD_D_NB_0),
    .IS_LS         (0),
    .RAM_LATENCY   (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd_0 (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .in_clbu_bwd_data       (in_clbu_bwd_data),
    .in_clbu_bwd_data_avail (in_clbu_bwd_data_avail),
    .in_clbu_bwd_sob        (in_clbu_bwd_sob),
    .in_clbu_bwd_eob        (in_clbu_bwd_eob),
    .in_clbu_bwd_sol        (in_clbu_bwd_sol),
    .in_clbu_bwd_eol        (in_clbu_bwd_eol),
    .in_clbu_bwd_sos        (in_clbu_bwd_sos),
    .in_clbu_bwd_eos        (in_clbu_bwd_eos),
    .in_clbu_bwd_pbs_id     (in_clbu_bwd_pbs_id),
    .in_clbu_bwd_ctrl_avail (in_clbu_bwd_ctrl_avail),


    .out_clbu_bwd_data      (out_clbu_bwd_data[0]),
    .out_clbu_bwd_data_avail(out_clbu_bwd_data_avail[0]),
    .out_clbu_bwd_sob       (out_clbu_bwd_sob[0]),
    .out_clbu_bwd_eob       (out_clbu_bwd_eob[0]),
    .out_clbu_bwd_sol       (out_clbu_bwd_sol[0]),
    .out_clbu_bwd_eol       (out_clbu_bwd_eol[0]),
    .out_clbu_bwd_sos       (out_clbu_bwd_sos[0]),
    .out_clbu_bwd_eos       (out_clbu_bwd_eos[0]),
    .out_clbu_bwd_pbs_id    (out_clbu_bwd_pbs_id[0]),
    .out_clbu_bwd_ctrl_avail(out_clbu_bwd_ctrl_avail[0]),

    .out_ntw_bwd_data       (/*UNUSED*/),
    .out_ntw_bwd_data_avail (/*UNUSED*/),
    .out_ntw_bwd_sob        (/*UNUSED*/),
    .out_ntw_bwd_eob        (/*UNUSED*/),
    .out_ntw_bwd_sol        (/*UNUSED*/),
    .out_ntw_bwd_eol        (/*UNUSED*/),
    .out_ntw_bwd_sos        (/*UNUSED*/),
    .out_ntw_bwd_eos        (/*UNUSED*/),
    .out_ntw_bwd_pbs_id     (/*UNUSED*/),
    .out_ntw_bwd_ctrl_avail (/*UNUSED*/),

    .ntt_acc_data           (/*UNUSED*/),
    .ntt_acc_data_avail     (/*UNUSED*/),
    .ntt_acc_sob            (/*UNUSED*/),
    .ntt_acc_eob            (/*UNUSED*/),
    .ntt_acc_sol            (/*UNUSED*/),
    .ntt_acc_eol            (/*UNUSED*/),
    .ntt_acc_sog            (/*UNUSED*/),
    .ntt_acc_eog            (/*UNUSED*/),
    .ntt_acc_pbs_id         (/*UNUSED*/),
    .ntt_acc_ctrl_avail     (/*UNUSED*/),

    .twd_omg_ru_r_pow       (twd_omg_ru_r_pow),

    .twd_phi_ru_bwd         (twd_phi_ru_bwd[BWD_TWD_OFS_0+:BWD_D_NB_0]),
    .twd_phi_ru_bwd_vld     (twd_phi_ru_bwd_vld[BWD_TWD_OFS_0+:BWD_D_NB_0]),
    .twd_phi_ru_bwd_rdy     (twd_phi_ru_bwd_rdy[BWD_TWD_OFS_0+:BWD_D_NB_0]),

    .twd_intt_final         (/*UNUSED*/),
    .twd_intt_final_vld     (/*UNUSED*/),
    .twd_intt_final_rdy     (/*UNUSED*/),

    .ntt_error              (ntt_error_bwd[0])

  );

 ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .MOD_NTT_TYPE  (MOD_NTT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .DELTA         (BWD_RS_DELTA),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .S_INIT        (BWD_S_INIT_1),
    .D_INIT        (BWD_D_INIT_1),
    .D_NB          (BWD_D_NB_1),
    .IS_LS         (0),
    .RAM_LATENCY   (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd_1 (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .in_clbu_bwd_data       (out_clbu_bwd_data[0]),
    .in_clbu_bwd_data_avail (out_clbu_bwd_data_avail[0]),
    .in_clbu_bwd_sob        (out_clbu_bwd_sob[0]),
    .in_clbu_bwd_eob        (out_clbu_bwd_eob[0]),
    .in_clbu_bwd_sol        (out_clbu_bwd_sol[0]),
    .in_clbu_bwd_eol        (out_clbu_bwd_eol[0]),
    .in_clbu_bwd_sos        (out_clbu_bwd_sos[0]),
    .in_clbu_bwd_eos        (out_clbu_bwd_eos[0]),
    .in_clbu_bwd_pbs_id     (out_clbu_bwd_pbs_id[0]),
    .in_clbu_bwd_ctrl_avail (out_clbu_bwd_ctrl_avail[0]),

    .out_clbu_bwd_data      (out_clbu_bwd_data[1]),
    .out_clbu_bwd_data_avail(out_clbu_bwd_data_avail[1]),
    .out_clbu_bwd_sob       (out_clbu_bwd_sob[1]),
    .out_clbu_bwd_eob       (out_clbu_bwd_eob[1]),
    .out_clbu_bwd_sol       (out_clbu_bwd_sol[1]),
    .out_clbu_bwd_eol       (out_clbu_bwd_eol[1]),
    .out_clbu_bwd_sos       (out_clbu_bwd_sos[1]),
    .out_clbu_bwd_eos       (out_clbu_bwd_eos[1]),
    .out_clbu_bwd_pbs_id    (out_clbu_bwd_pbs_id[1]),
    .out_clbu_bwd_ctrl_avail(out_clbu_bwd_ctrl_avail[1]),

    .out_ntw_bwd_data       (/*UNUSED*/),
    .out_ntw_bwd_data_avail (/*UNUSED*/),
    .out_ntw_bwd_sob        (/*UNUSED*/),
    .out_ntw_bwd_eob        (/*UNUSED*/),
    .out_ntw_bwd_sol        (/*UNUSED*/),
    .out_ntw_bwd_eol        (/*UNUSED*/),
    .out_ntw_bwd_sos        (/*UNUSED*/),
    .out_ntw_bwd_eos        (/*UNUSED*/),
    .out_ntw_bwd_pbs_id     (/*UNUSED*/),
    .out_ntw_bwd_ctrl_avail (/*UNUSED*/),

    .ntt_acc_data           (/*UNUSED*/),
    .ntt_acc_data_avail     (/*UNUSED*/),
    .ntt_acc_sob            (/*UNUSED*/),
    .ntt_acc_eob            (/*UNUSED*/),
    .ntt_acc_sol            (/*UNUSED*/),
    .ntt_acc_eol            (/*UNUSED*/),
    .ntt_acc_sog            (/*UNUSED*/),
    .ntt_acc_eog            (/*UNUSED*/),
    .ntt_acc_pbs_id         (/*UNUSED*/),
    .ntt_acc_ctrl_avail     (/*UNUSED*/),

    .twd_omg_ru_r_pow       (twd_omg_ru_r_pow),

    .twd_phi_ru_bwd         (twd_phi_ru_bwd[BWD_TWD_OFS_1+:BWD_D_NB_1]),
    .twd_phi_ru_bwd_vld     (twd_phi_ru_bwd_vld[BWD_TWD_OFS_1+:BWD_D_NB_1]),
    .twd_phi_ru_bwd_rdy     (twd_phi_ru_bwd_rdy[BWD_TWD_OFS_1+:BWD_D_NB_1]),

    .twd_intt_final         (/*UNUSED*/),
    .twd_intt_final_vld     (/*UNUSED*/),
    .twd_intt_final_rdy     (/*UNUSED*/),

    .ntt_error              (ntt_error_bwd[1])

  );

 ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .MOD_NTT_TYPE  (MOD_NTT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .DELTA         (BWD_RS_DELTA),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .S_INIT        (BWD_S_INIT_2),
    .D_INIT        (BWD_D_INIT_2),
    .D_NB          (BWD_D_NB_2),
    .IS_LS         (0),
    .RAM_LATENCY   (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd_2 (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .in_clbu_bwd_data       (out_clbu_bwd_data[1]),
    .in_clbu_bwd_data_avail (out_clbu_bwd_data_avail[1]),
    .in_clbu_bwd_sob        (out_clbu_bwd_sob[1]),
    .in_clbu_bwd_eob        (out_clbu_bwd_eob[1]),
    .in_clbu_bwd_sol        (out_clbu_bwd_sol[1]),
    .in_clbu_bwd_eol        (out_clbu_bwd_eol[1]),
    .in_clbu_bwd_sos        (out_clbu_bwd_sos[1]),
    .in_clbu_bwd_eos        (out_clbu_bwd_eos[1]),
    .in_clbu_bwd_pbs_id     (out_clbu_bwd_pbs_id[1]),
    .in_clbu_bwd_ctrl_avail (out_clbu_bwd_ctrl_avail[1]),

    .out_clbu_bwd_data      (/*UNUSED*/),
    .out_clbu_bwd_data_avail(/*UNUSED*/),
    .out_clbu_bwd_sob       (/*UNUSED*/),
    .out_clbu_bwd_eob       (/*UNUSED*/),
    .out_clbu_bwd_sol       (/*UNUSED*/),
    .out_clbu_bwd_eol       (/*UNUSED*/),
    .out_clbu_bwd_sos       (/*UNUSED*/),
    .out_clbu_bwd_eos       (/*UNUSED*/),
    .out_clbu_bwd_pbs_id    (/*UNUSED*/),
    .out_clbu_bwd_ctrl_avail(/*UNUSED*/),

    .out_ntw_bwd_data       (out_ntw_bwd_data[2]),
    .out_ntw_bwd_data_avail (out_ntw_bwd_data_avail[2]),
    .out_ntw_bwd_sob        (out_ntw_bwd_sob[2]),
    .out_ntw_bwd_eob        (out_ntw_bwd_eob[2]),
    .out_ntw_bwd_sol        (out_ntw_bwd_sol[2]),
    .out_ntw_bwd_eol        (out_ntw_bwd_eol[2]),
    .out_ntw_bwd_sos        (out_ntw_bwd_sos[2]),
    .out_ntw_bwd_eos        (out_ntw_bwd_eos[2]),
    .out_ntw_bwd_pbs_id     (out_ntw_bwd_pbs_id[2]),
    .out_ntw_bwd_ctrl_avail (out_ntw_bwd_ctrl_avail[2]),

    .ntt_acc_data           (/*UNUSED*/),
    .ntt_acc_data_avail     (/*UNUSED*/),
    .ntt_acc_sob            (/*UNUSED*/),
    .ntt_acc_eob            (/*UNUSED*/),
    .ntt_acc_sol            (/*UNUSED*/),
    .ntt_acc_eol            (/*UNUSED*/),
    .ntt_acc_sog            (/*UNUSED*/),
    .ntt_acc_eog            (/*UNUSED*/),
    .ntt_acc_pbs_id         (/*UNUSED*/),
    .ntt_acc_ctrl_avail     (/*UNUSED*/),

    .twd_omg_ru_r_pow       (twd_omg_ru_r_pow),

    .twd_phi_ru_bwd         (twd_phi_ru_bwd[BWD_TWD_OFS_2+:BWD_D_NB_2]),
    .twd_phi_ru_bwd_vld     (twd_phi_ru_bwd_vld[BWD_TWD_OFS_2+:BWD_D_NB_2]),
    .twd_phi_ru_bwd_rdy     (twd_phi_ru_bwd_rdy[BWD_TWD_OFS_2+:BWD_D_NB_2]),

    .twd_intt_final         (/*UNUSED*/),
    .twd_intt_final_vld     (/*UNUSED*/),
    .twd_intt_final_rdy     (/*UNUSED*/),


    .ntt_error              (ntt_error_bwd[2])
  );

 ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .MOD_NTT_TYPE  (MOD_NTT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .DELTA         (BWD_LS_DELTA),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .S_INIT        (BWD_S_INIT_3),
    .D_INIT        (BWD_D_INIT_3),
    .D_NB          (BWD_D_NB_3),
    .IS_LS         (1),
    .RAM_LATENCY   (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd_3 (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .in_clbu_bwd_data       (out_ntw_bwd_data[2]),
    .in_clbu_bwd_data_avail (out_ntw_bwd_data_avail_tmp[2]),
    .in_clbu_bwd_sob        (out_ntw_bwd_sob[2]),
    .in_clbu_bwd_eob        (out_ntw_bwd_eob[2]),
    .in_clbu_bwd_sol        (out_ntw_bwd_sol[2]),
    .in_clbu_bwd_eol        (out_ntw_bwd_eol[2]),
    .in_clbu_bwd_sos        (out_ntw_bwd_sos[2]),
    .in_clbu_bwd_eos        (out_ntw_bwd_eos[2]),
    .in_clbu_bwd_pbs_id     (out_ntw_bwd_pbs_id[2]),
    .in_clbu_bwd_ctrl_avail (out_ntw_bwd_ctrl_avail[2]),

    .out_clbu_bwd_data      (out_clbu_bwd_data[3]),
    .out_clbu_bwd_data_avail(out_clbu_bwd_data_avail[3]),
    .out_clbu_bwd_sob       (out_clbu_bwd_sob[3]),
    .out_clbu_bwd_eob       (out_clbu_bwd_eob[3]),
    .out_clbu_bwd_sol       (out_clbu_bwd_sol[3]),
    .out_clbu_bwd_eol       (out_clbu_bwd_eol[3]),
    .out_clbu_bwd_sos       (out_clbu_bwd_sos[3]),
    .out_clbu_bwd_eos       (out_clbu_bwd_eos[3]),
    .out_clbu_bwd_pbs_id    (out_clbu_bwd_pbs_id[3]),
    .out_clbu_bwd_ctrl_avail(out_clbu_bwd_ctrl_avail[3]),

    .out_ntw_bwd_data       (/*UNUSED*/),
    .out_ntw_bwd_data_avail (/*UNUSED*/),
    .out_ntw_bwd_sob        (/*UNUSED*/),
    .out_ntw_bwd_eob        (/*UNUSED*/),
    .out_ntw_bwd_sol        (/*UNUSED*/),
    .out_ntw_bwd_eol        (/*UNUSED*/),
    .out_ntw_bwd_sos        (/*UNUSED*/),
    .out_ntw_bwd_eos        (/*UNUSED*/),
    .out_ntw_bwd_pbs_id     (/*UNUSED*/),
    .out_ntw_bwd_ctrl_avail (/*UNUSED*/),

    .ntt_acc_data           (/*UNUSED*/),
    .ntt_acc_data_avail     (/*UNUSED*/),
    .ntt_acc_sob            (/*UNUSED*/),
    .ntt_acc_eob            (/*UNUSED*/),
    .ntt_acc_sol            (/*UNUSED*/),
    .ntt_acc_eol            (/*UNUSED*/),
    .ntt_acc_sog            (/*UNUSED*/),
    .ntt_acc_eog            (/*UNUSED*/),
    .ntt_acc_pbs_id         (/*UNUSED*/),
    .ntt_acc_ctrl_avail     (/*UNUSED*/),



    .twd_omg_ru_r_pow       (twd_omg_ru_r_pow),

    .twd_phi_ru_bwd         (twd_phi_ru_bwd[BWD_TWD_OFS_3+:BWD_D_NB_3]),
    .twd_phi_ru_bwd_vld     (twd_phi_ru_bwd_vld[BWD_TWD_OFS_3+:BWD_D_NB_3]),
    .twd_phi_ru_bwd_rdy     (twd_phi_ru_bwd_rdy[BWD_TWD_OFS_3+:BWD_D_NB_3]),

    .twd_intt_final         (/*UNUSED*/),
    .twd_intt_final_vld     (/*UNUSED*/),
    .twd_intt_final_rdy     (/*UNUSED*/),


    .ntt_error              (ntt_error_bwd[3])

  );

 ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .MOD_NTT_TYPE  (MOD_NTT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .DELTA         (BWD_LS_DELTA),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .S_INIT        (BWD_S_INIT_4),
    .D_INIT        (BWD_D_INIT_4),
    .D_NB          (BWD_D_NB_4),
    .IS_LS         (1),
    .RAM_LATENCY   (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd_4 (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .in_clbu_bwd_data       (out_clbu_bwd_data[3]),
    .in_clbu_bwd_data_avail (out_clbu_bwd_data_avail[3]),
    .in_clbu_bwd_sob        (out_clbu_bwd_sob[3]),
    .in_clbu_bwd_eob        (out_clbu_bwd_eob[3]),
    .in_clbu_bwd_sol        (out_clbu_bwd_sol[3]),
    .in_clbu_bwd_eol        (out_clbu_bwd_eol[3]),
    .in_clbu_bwd_sos        (out_clbu_bwd_sos[3]),
    .in_clbu_bwd_eos        (out_clbu_bwd_eos[3]),
    .in_clbu_bwd_pbs_id     (out_clbu_bwd_pbs_id[3]),
    .in_clbu_bwd_ctrl_avail (out_clbu_bwd_ctrl_avail[3]),


    .out_clbu_bwd_data      (/*UNUSED*/),
    .out_clbu_bwd_data_avail(/*UNUSED*/),
    .out_clbu_bwd_sob       (/*UNUSED*/),
    .out_clbu_bwd_eob       (/*UNUSED*/),
    .out_clbu_bwd_sol       (/*UNUSED*/),
    .out_clbu_bwd_eol       (/*UNUSED*/),
    .out_clbu_bwd_sos       (/*UNUSED*/),
    .out_clbu_bwd_eos       (/*UNUSED*/),
    .out_clbu_bwd_pbs_id    (/*UNUSED*/),
    .out_clbu_bwd_ctrl_avail(/*UNUSED*/),


    .out_ntw_bwd_data       (/*UNUSED*/),
    .out_ntw_bwd_data_avail (/*UNUSED*/),
    .out_ntw_bwd_sob        (/*UNUSED*/),
    .out_ntw_bwd_eob        (/*UNUSED*/),
    .out_ntw_bwd_sol        (/*UNUSED*/),
    .out_ntw_bwd_eol        (/*UNUSED*/),
    .out_ntw_bwd_sos        (/*UNUSED*/),
    .out_ntw_bwd_eos        (/*UNUSED*/),
    .out_ntw_bwd_pbs_id     (/*UNUSED*/),
    .out_ntw_bwd_ctrl_avail (/*UNUSED*/),


    .ntt_acc_data           (ntt_acc_data      ),
    .ntt_acc_data_avail     (ntt_acc_data_avail),
    .ntt_acc_sob            (ntt_acc_sob       ),
    .ntt_acc_eob            (ntt_acc_eob       ),
    .ntt_acc_sol            (ntt_acc_sol       ),
    .ntt_acc_eol            (ntt_acc_eol       ),
    .ntt_acc_sog            (ntt_acc_sog       ),
    .ntt_acc_eog            (ntt_acc_eog       ),
    .ntt_acc_pbs_id         (ntt_acc_pbs_id    ),
    .ntt_acc_ctrl_avail     (ntt_acc_ctrl_avail),



    .twd_omg_ru_r_pow       (twd_omg_ru_r_pow),

    .twd_phi_ru_bwd         (twd_phi_ru_bwd[BWD_TWD_OFS_4+:BWD_D_NB_4]),
    .twd_phi_ru_bwd_vld     (twd_phi_ru_bwd_vld[BWD_TWD_OFS_4+:BWD_D_NB_4]),
    .twd_phi_ru_bwd_rdy     (twd_phi_ru_bwd_rdy[BWD_TWD_OFS_4+:BWD_D_NB_4]),

    .twd_intt_final         (twd_intt_final    ),
    .twd_intt_final_vld     (twd_intt_final_vld),
    .twd_intt_final_rdy     (twd_intt_final_rdy),


    .ntt_error              (ntt_error_bwd[4])

  );


endmodule
