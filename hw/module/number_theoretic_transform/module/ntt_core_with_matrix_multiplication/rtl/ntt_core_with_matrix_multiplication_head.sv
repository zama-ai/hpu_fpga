// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core tackles the NTT and INTT computations by using the same DIT butterfly-units.
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
//
// To fit the SLRs, the current version proposes a partition into at least 2 parts.
// Note : Only NTT_CORE_ARCH_WMM_UNFOLD_PCG flavor is used.
//
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_with_matrix_multiplication_head
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
  parameter  int           BWD_PSI_DIV           = 1,
  parameter  int           DELTA                 = 4,
  parameter  int           RAM_LATENCY           = 1,
  parameter  int           ROM_LATENCY           = 1,
  parameter  int           S_NB                  = 2, // Number of NTT stages.
  parameter  bit           USE_PP                = 1, // If this partition contains the entire FWD NTT,
                                                      // this parameter indicates if the PP is instantiated.
  parameter  string        TWD_IFNL_FILE_PREFIX  = NTT_CORE_ARCH == NTT_CORE_ARCH_WMM_UNFOLD ?
                                                        "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_ifnl_bwd"    :
                                                        "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_ifnl",
  parameter  string        TWD_PHRU_FILE_PREFIX  = "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_phru",
  localparam int           ERROR_W               = 2    // [1:0] ntt
                                                   + 2  // [3:2] twd phru
) (
  input                                            clk,
  input                                            s_rst_n,
  // Data from decomposition
  input  [PSI-1:0][R-1:0][OP_W-1:0]                decomp_ntt_data,
  input  [PSI-1:0][R-1:0]                          decomp_ntt_data_vld,
  output [PSI-1:0][R-1:0]                          decomp_ntt_data_rdy,
  input                                            decomp_ntt_sob,
  input                                            decomp_ntt_eob,
  input                                            decomp_ntt_sol,
  input                                            decomp_ntt_eol,
  input                                            decomp_ntt_sog,
  input                                            decomp_ntt_eog,
  input [BPBS_ID_W-1:0]                            decomp_ntt_pbs_id,
  input                                            decomp_ntt_last_pbs,
  input                                            decomp_ntt_full_throughput,
  input                                            decomp_ntt_ctrl_vld,
  output                                           decomp_ntt_ctrl_rdy,

  // To next ntt_core or output
  output [PSI-1:0][R-1:0][OP_W-1:0]                next_data,
  output [PSI-1:0][R-1:0]                          next_data_avail,
  output                                           next_sob,
  output                                           next_eob,
  output                                           next_sol,
  output                                           next_eol,
  output                                           next_sos,
  output                                           next_eos,
  output [BPBS_ID_W-1:0]                           next_pbs_id,
  output                                           next_ctrl_avail,

  // Twiddles
  // Powers of omega : [i] = omg_ru_r ** i
  // quasi static signal
  input  [1:0][R/2-1:0][OP_W-1:0]                  twd_omg_ru_r_pow, // Not used when R=2

  // Matrix factors : BSK
  // Only used if the PP is in this part.
  input  [PSI-1:0][R-1:0][GLWE_K_P1-1:0][OP_W-1:0] bsk,
  input  [PSI-1:0][R-1:0][GLWE_K_P1-1:0]           bsk_vld,
  output [PSI-1:0][R-1:0][GLWE_K_P1-1:0]           bsk_rdy,

  // batch command from accumulator
  input  [BR_BATCH_CMD_W-1:0]                      batch_cmd,
  input                                            batch_cmd_avail,
  // Error
  output [ERROR_W-1:0]                             ntt_error
);

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  // ============================================================================================ //
  // Signals
  // ============================================================================================ //
  // seq -> clbu
  logic [PSI-1:0][R-1:0][OP_W-1:0]                       seq_clbu_data;
  logic [PSI-1:0]                                        seq_clbu_data_avail;
  logic [PSI-1:0][R-1:0]                                 seq_clbu_data_avail_ext;
  logic                                                  seq_clbu_sob;
  logic                                                  seq_clbu_eob;
  logic                                                  seq_clbu_sol;
  logic                                                  seq_clbu_eol;
  logic                                                  seq_clbu_sos;
  logic                                                  seq_clbu_eos;
  logic [BPBS_ID_W-1:0]                                  seq_clbu_pbs_id;
  logic                                                  seq_clbu_ntt_bwd;
  logic                                                  seq_clbu_ctrl_avail;

  // ============================================================================================ //
  // Format signal
  // ============================================================================================ //
    always_comb
      for (int p=0; p<PSI; p=p+1)
        seq_clbu_data_avail_ext[p] = {R{seq_clbu_data_avail[p]}};


  // ============================================================================================ //
  // Instances
  // ============================================================================================ //
  // ------------------------------------------------------------------------------------------- --
  // Head
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
  // Middle
  // ------------------------------------------------------------------------------------------- --
  generate
    if (S_NB > 0) begin : gen_middle
      ntt_core_with_matrix_multiplication_middle
      #(
        .OP_W                  (OP_W),
        .MOD_NTT               (MOD_NTT),
        .MOD_NTT_TYPE          (MOD_NTT_TYPE),
        .MOD_MULT_TYPE         (MOD_MULT_TYPE),
        .REDUCT_TYPE           (REDUCT_TYPE),
        .MULT_TYPE             (MULT_TYPE),
        .PP_MOD_MULT_TYPE      (PP_MOD_MULT_TYPE),
        .PP_MULT_TYPE          (PP_MULT_TYPE),
        .R                     (R),
        .PSI                   (PSI),
        .S                     (S),
        .DELTA                 (DELTA),
        .BWD_PSI_DIV           (BWD_PSI_DIV),
        .RAM_LATENCY           (RAM_LATENCY),
        .ROM_LATENCY           (ROM_LATENCY),
        .S_INIT                (S-1),
        .S_NB                  (S_NB),
        .USE_PP                (USE_PP),
        .TWD_PHRU_FILE_PREFIX  (TWD_PHRU_FILE_PREFIX),
        .TWD_IFNL_FILE_PREFIX  (TWD_IFNL_FILE_PREFIX)
      ) ntt_core_with_matrix_multiplication_middle (
        .clk                     (clk),
        .s_rst_n                 (s_rst_n),

        .prev_data               (seq_clbu_data),
        .prev_data_avail         (seq_clbu_data_avail_ext),
        .prev_sob                (seq_clbu_sob),
        .prev_eob                (seq_clbu_eob),
        .prev_sol                (seq_clbu_sol),
        .prev_eol                (seq_clbu_eol),
        .prev_sos                (seq_clbu_sos),
        .prev_eos                (seq_clbu_eos),
        .prev_pbs_id             (seq_clbu_pbs_id),
        .prev_ctrl_avail         (seq_clbu_ctrl_avail),

        .next_data               (next_data),
        .next_data_avail         (next_data_avail),
        .next_sob                (next_sob),
        .next_eob                (next_eob),
        .next_sol                (next_sol),
        .next_eol                (next_eol),
        .next_sos                (next_sos),
        .next_eos                (next_eos),
        .next_pbs_id             (next_pbs_id),
        .next_ctrl_avail         (next_ctrl_avail),

        .twd_omg_ru_r_pow        (twd_omg_ru_r_pow),

        .bsk                     (bsk    ),
        .bsk_vld                 (bsk_vld),
        .bsk_rdy                 (bsk_rdy),

        .batch_cmd               (batch_cmd      ),
        .batch_cmd_avail         (batch_cmd_avail),

        .ntt_error               (ntt_error)
      );
    end
    else begin : gen_no_middle
      assign next_data       = seq_clbu_data;
      assign next_data_avail = seq_clbu_data_avail_ext;
      assign next_sob        = seq_clbu_sob;
      assign next_eob        = seq_clbu_eob;
      assign next_sol        = seq_clbu_sol;
      assign next_eol        = seq_clbu_eol;
      assign next_sos        = seq_clbu_sos;
      assign next_eos        = seq_clbu_eos;
      assign next_pbs_id     = seq_clbu_pbs_id;
      assign next_ctrl_avail = seq_clbu_ctrl_avail;

      assign ntt_error       = '0;
    end
  endgenerate

endmodule
