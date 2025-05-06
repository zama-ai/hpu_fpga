// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core tackles the NTT and INTT computations by reusing the same DIT butterfly-units.
// It also computes a matrix multiplication.
// This module includes the twiddle phi run and twiddle intt final, since their instance is
// architecture dependent.
//
// Prerequisites :
// Input data are interleaved in time, to avoid an output accumulator.
// Input order is the "incremental stride" order, with R**(S-1) as the stride.
// Output data are also interleaved in time.
// Output order is also the "incremental stride" order.
//
// 5 flavors are available (NTT_CORE_ARCH):
// NTT_CORE_ARCH_WMM_COMPACT  : The compact architecture uses the same logic to implement all the stages.
// NTT_CORE_ARCH_WMM_PIPELINE : The pipeline architecture: the forward process is done entirely before the loopback.
// NTT_CORE_ARCH_WMM_UNFOLD   : The unfold architecture: NTT and INTT are executed sequentially.
// NTT_CORE_ARCH_WMM_COMPACT_PCG  : The compact pcg architecture uses the same logic to implement all the stages.
// NTT_CORE_ARCH_WMM_UNFOLD_PCG   : The unfold pcg architecture: NTT and INTT are executed sequentially.
//
// This is defined in the ntt_core_wmm_pkg.
//
// The "dimension" of the NTT (R, PSI, DELTA) is given by ntt_core_common_param_pkg
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_with_matrix_multiplication
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;
  import ntt_core_wmm_pkg::*;
#(
  parameter  int           OP_W                  = 32,
  parameter  [OP_W-1:0]    MOD_NTT               = 2**32-2**17-2**13+1,
  parameter  int_type_e    MOD_NTT_TYPE          = SOLINAS3,
  parameter  mod_mult_type_e   MOD_MULT_TYPE     = MOD_MULT_SOLINAS3,
  parameter  mod_reduct_type_e REDUCT_TYPE       = MOD_REDUCT_SOLINAS3,
  parameter  arith_mult_type_e MULT_TYPE         = MULT_KARATSUBA,
  parameter  mod_mult_type_e   PP_MOD_MULT_TYPE  = MOD_MULT_SOLINAS3,
  parameter  arith_mult_type_e PP_MULT_TYPE      = MULT_KARATSUBA,
  parameter  ntt_core_arch_e   NTT_CORE_ARCH     = NTT_CORE_ARCH_WMM_UNFOLD_PCG,
  parameter  int           R                     = 8, // Butterfly Radix
  parameter  int           PSI                   = 8, // Number of butterflies
  parameter  int           S                     = $clog2(N)/$clog2(R), // Number of stages
  parameter  int           DELTA                 = 4,
  parameter  int           BWD_PSI_DIV           = 1,
  parameter  int           RAM_LATENCY           = 1,
  parameter  int           ROM_LATENCY           = 1,
  parameter  string        TWD_IFNL_FILE_PREFIX  = NTT_CORE_ARCH == NTT_CORE_ARCH_WMM_UNFOLD ?
                                                        "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_ifnl_bwd"    :
                                                        "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_ifnl",
  parameter  string        TWD_PHRU_FILE_PREFIX  = "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_phru",
  localparam int           ERROR_W               = 2    // [1:0] ntt
                                                   + 2  // [3:2] twd phru
) (
  input  logic                                           clk,
  input  logic                                           s_rst_n,
  // Data from decomposition
  input  logic [PSI-1:0][R-1:0][OP_W-1:0]                decomp_ntt_data,
  input  logic [PSI-1:0][R-1:0]                          decomp_ntt_data_vld,
  output logic [PSI-1:0][R-1:0]                          decomp_ntt_data_rdy,
  input  logic                                           decomp_ntt_sob,
  input  logic                                           decomp_ntt_eob,
  input  logic                                           decomp_ntt_sol,
  input  logic                                           decomp_ntt_eol,
  input  logic                                           decomp_ntt_sog,
  input  logic                                           decomp_ntt_eog,
  input  logic [BPBS_ID_W-1:0]                           decomp_ntt_pbs_id,
  input  logic                                           decomp_ntt_last_pbs,
  input  logic                                           decomp_ntt_full_throughput,
  input  logic                                           decomp_ntt_ctrl_vld,
  output logic                                           decomp_ntt_ctrl_rdy,
  // output logic data to acc
  output logic [PSI-1:0][R-1:0][OP_W-1:0]                ntt_acc_data,
  output logic [PSI-1:0][R-1:0]                          ntt_acc_data_avail,
  output logic                                           ntt_acc_sob,
  output logic                                           ntt_acc_eob,
  output logic                                           ntt_acc_sol,
  output logic                                           ntt_acc_eol,
  output logic                                           ntt_acc_sog,
  output logic                                           ntt_acc_eog,
  output logic [BPBS_ID_W-1:0]                           ntt_acc_pbs_id,
  output logic                                           ntt_acc_ctrl_avail,
  // Twiddles
  // Powers of omega : [i] = omg_ru_r ** i
  // quasi static signal
  input  logic [1:0][R/2-1:0][OP_W-1:0]                  twd_omg_ru_r_pow, // Not used when R=2
  // Matrix factors : BSK
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][OP_W-1:0] bsk,
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]           bsk_vld,
  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]           bsk_rdy,

  // batch command from accumulator
  input  logic [BR_BATCH_CMD_W-1:0]                      batch_cmd,
  input  logic                                           batch_cmd_avail,
  // Error
  output logic [ERROR_W-1:0]                             ntt_error
);

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  // ============================================================================================ //
  // ntt_core_wmm + twiddle_phru
  // ============================================================================================ //
  generate
    if (NTT_CORE_ARCH == NTT_CORE_ARCH_WMM_UNFOLD_PCG) begin : gen_unfold_pcg
    // --------------------------------------------------------------------------------------------
    // ntt_core_with_matrix_multiplication_unfold_pcg
    // --------------------------------------------------------------------------------------------
      //== ntt_core_wmm
      ntt_core_with_matrix_multiplication_head #(
        .OP_W          (OP_W),
        .MOD_NTT       (MOD_NTT),
        .MOD_NTT_TYPE  (MOD_NTT_TYPE),
        .MOD_MULT_TYPE (MOD_MULT_TYPE),
        .MULT_TYPE     (MULT_TYPE    ),
        .REDUCT_TYPE   (REDUCT_TYPE  ),
        .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
        .PP_MULT_TYPE     (PP_MULT_TYPE),
        .R             (R),
        .PSI           (PSI),
        .S             (S),
        .DELTA         (DELTA),
        .BWD_PSI_DIV   (BWD_PSI_DIV),
        .RAM_LATENCY   (RAM_LATENCY),
        .ROM_LATENCY   (ROM_LATENCY),
        .S_NB          (2*S),
        .USE_PP        (1),
        .TWD_IFNL_FILE_PREFIX (TWD_IFNL_FILE_PREFIX),
        .TWD_PHRU_FILE_PREFIX (TWD_PHRU_FILE_PREFIX)
      ) ntt_core_wmm (
        // System
        .clk                       (clk),
        .s_rst_n                   (s_rst_n),
        // decomp -> ntt
        .decomp_ntt_data           (decomp_ntt_data),
        .decomp_ntt_data_vld       (decomp_ntt_data_vld),
        .decomp_ntt_sob            (decomp_ntt_sob),
        .decomp_ntt_eob            (decomp_ntt_eob),
        .decomp_ntt_sol            (decomp_ntt_sol),
        .decomp_ntt_eol            (decomp_ntt_eol),
        .decomp_ntt_sog            (decomp_ntt_sog),
        .decomp_ntt_eog            (decomp_ntt_eog),
        .decomp_ntt_pbs_id         (decomp_ntt_pbs_id),
        .decomp_ntt_last_pbs       (decomp_ntt_last_pbs),
        .decomp_ntt_full_throughput(decomp_ntt_full_throughput),
        .decomp_ntt_ctrl_vld       (decomp_ntt_ctrl_vld),
        .decomp_ntt_ctrl_rdy       (decomp_ntt_ctrl_rdy),
        .decomp_ntt_data_rdy       (decomp_ntt_data_rdy),
        // data -> acc
        .next_data                 (ntt_acc_data),
        .next_data_avail           (ntt_acc_data_avail),
        .next_sob                  (ntt_acc_sob),
        .next_eob                  (ntt_acc_eob),
        .next_sol                  (ntt_acc_sol),
        .next_eol                  (ntt_acc_eol),
        .next_sos                  (ntt_acc_sog),
        .next_eos                  (ntt_acc_eog),
        .next_pbs_id               (ntt_acc_pbs_id),
        .next_ctrl_avail           (ntt_acc_ctrl_avail),
        // Twiddles
        .twd_omg_ru_r_pow          (twd_omg_ru_r_pow),
        // bootstrapping key
        .bsk                       (bsk),
        .bsk_vld                   (bsk_vld),
        .bsk_rdy                   (bsk_rdy),
        // Batch cmd
        .batch_cmd                 (batch_cmd),
        .batch_cmd_avail           (batch_cmd_avail),
        // Error flags
        .ntt_error                 (ntt_error)
      );

    end // gen_unfold_pcg
    else begin : gen_unknown
      $fatal(1,"> ERROR: Unsupported NTT_CORE_ARCH %0d", NTT_CORE_ARCH);
    end
  endgenerate

endmodule

