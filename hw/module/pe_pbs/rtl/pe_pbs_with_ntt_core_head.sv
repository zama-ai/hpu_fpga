// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Programmable bootstrap processing element (PE).
// This module deals with processing the bootstrap on BLWE. It reads the BLWE stored in the regfile,
// operates the key_switch and the bootstrap, then writes it back in the regfile.
//
// This is a subpart of the pe_pbs. This split is necessary to ease the P&R.
// This subpart contains, according to NTT_CORE_ARCH :
//  * ntt_core_with_matrix_multiplication_head
//  * ntt_core_gf64_head
// ==============================================================================================

module pe_pbs_with_ntt_core_head
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import bsk_mgr_common_param_pkg::*;
  import ksk_mgr_common_param_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import regf_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
#(
  // Operator type
  parameter  mod_mult_type_e   MOD_MULT_TYPE       = set_mod_mult_type(MOD_NTT_TYPE),
  parameter  mod_reduct_type_e REDUCT_TYPE         = set_mod_reduct_type(MOD_NTT_TYPE),
  parameter  arith_mult_type_e PHI_MULT_TYPE       = set_ntt_mult_type(MOD_NTT_W,MOD_NTT_TYPE),
  parameter  mod_mult_type_e   PP_MOD_MULT_TYPE    = MOD_MULT_TYPE,
  parameter  arith_mult_type_e PP_MULT_TYPE        = PHI_MULT_TYPE,
  parameter  int               MODSW_2_PRECISION_W = MOD_NTT_W + 32,
  parameter  arith_mult_type_e MODSW_2_MULT_TYPE   = set_mult_type(MODSW_2_PRECISION_W),
  parameter  arith_mult_type_e MODSW_MULT_TYPE     = set_mult_type(MOD_NTT_W),
  // RAM latency
  parameter  int               RAM_LATENCY         = 2,
  parameter  int               URAM_LATENCY        = RAM_LATENCY + 1,
  parameter  int               ROM_LATENCY         = 2,
  // Twiddle files
  parameter  string            TWD_IFNL_FILE_PREFIX = NTT_CORE_ARCH == NTT_CORE_ARCH_WMM_UNFOLD ?
                                                          "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_ifnl_bwd"    :
                                                          "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_ifnl",
  parameter  string            TWD_PHRU_FILE_PREFIX = "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_phru",
  parameter  string            TWD_GF64_FILE_PREFIX = $sformatf("memory_file/twiddle/NTT_CORE_ARCH_G64/R%0d_PSI%0d/twd_phi",R,PSI),
  // Instruction FIFO depth
  parameter  int               INST_FIFO_DEPTH      = 8, // Should be >= 2
  // Regfile info
  parameter  int               REGF_RD_LATENCY      = URAM_LATENCY + 4, // minimum latency to get the data
  parameter  int               KS_IF_COEF_NB        = (LBY < REGF_COEF_NB) ? LBY : REGF_SEQ_COEF_NB,
  parameter  int               KS_IF_SUBW_NB        = (LBY < REGF_COEF_NB) ? 1 : REGF_SEQ,
  //
  parameter  int               PHYS_RAM_DEPTH       = 1024, // Physical RAM depth. Should be a power of 2. In Xilinx is BRAM depth for 32b words
  parameter  int               S_NB                 = 6, // Total number of stages implemented in this part.
  parameter  bit               USE_PP               = 1
)
(
  input  logic                                                         clk,       // clock
  input  logic                                                         s_rst_n,    // synchronous reset

  //== Configuration
  input  logic [1:0][R/2-1:0][MOD_NTT_W-1:0]                           twd_omg_ru_r_pow, // Not used when R=2

  // Broadcast batch cmd
  input  logic [BR_BATCH_CMD_W-1:0]                                    br_batch_cmd,
  input  logic                                                         br_batch_cmd_avail,

  // BSK coefficients
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][MOD_NTT_W-1:0]          bsk,
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                         bsk_vld,
  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                         bsk_rdy,

  //== Decomposer
  // Decomposer -> NTT
  input  logic [PSI-1:0][R-1:0]                                        decomp_ntt_data_avail,
  input  logic [PSI-1:0][R-1:0][PBS_B_W:0]                             decomp_ntt_data, // 2s complement
  input  logic                                                         decomp_ntt_sob,
  input  logic                                                         decomp_ntt_eob,
  input  logic                                                         decomp_ntt_sog,
  input  logic                                                         decomp_ntt_eog,
  input  logic                                                         decomp_ntt_sol,
  input  logic                                                         decomp_ntt_eol,
  input  logic [BPBS_ID_W-1:0]                                         decomp_ntt_pbs_id,
  input  logic                                                         decomp_ntt_last_pbs,
  input  logic                                                         decomp_ntt_full_throughput,
  input  logic                                                         decomp_ntt_ctrl_avail,
  output logic [PSI-1:0][R-1:0]                                        decomp_ntt_data_rdy,
  output logic                                                         decomp_ntt_ctrl_rdy,

  // Output data to next
  output logic [PSI-1:0][R-1:0][NTT_OP_W-1:0]                          next_data,
  output logic [PSI-1:0][R-1:0]                                        next_data_avail,
  output logic                                                         next_sob,
  output logic                                                         next_eob,
  output logic                                                         next_sol,
  output logic                                                         next_eol,
  output logic                                                         next_sos,
  output logic                                                         next_eos,
  output logic [BPBS_ID_W-1:0]                                         next_pbs_id,
  output logic                                                         next_ctrl_avail,

  //== To rif
  output pep_error_t                                                   pep_error,
  output pep_info_t                                                    pep_rif_info,
  output pep_counter_inc_t                                             pep_rif_counter_inc
);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int ALMOST_DONE_BLINE_ID = 0; // TOREVIEW - adjust according to performance

// ============================================================================================== --
// Error / Inc / Info
// ============================================================================================== --
  pep_error_t pep_errorD;

  pep_ntt_error_t ntt_error;
  logic           infifo_ovf_error;

  assign ntt_error.in_ovf = infifo_ovf_error;

  always_comb begin
    pep_errorD     = '0;
    pep_errorD.ntt = ntt_error;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) pep_error <= '0;
    else          pep_error <= pep_errorD;

  assign pep_rif_info        = '0;
  assign pep_rif_counter_inc = '0;

// ============================================================================================== --
// NTT input overflow
// ============================================================================================== --
  logic infifo_ovf_errorD;

  assign infifo_ovf_errorD = decomp_ntt_ctrl_avail & ~decomp_ntt_ctrl_rdy;

  always_ff @(posedge clk)
    if (!s_rst_n) infifo_ovf_error <= 1'b0;
    else          infifo_ovf_error <= infifo_ovf_errorD;

// ============================================================================================== --
// batch_cmd
// ============================================================================================== --
  // register to ease P&R
  logic [BR_BATCH_CMD_W-1:0] br_batch_cmd_dly;
  logic                      br_batch_cmd_avail_dly;

  always_ff @(posedge clk)
    if (!s_rst_n) br_batch_cmd_avail_dly <= 1'b0;
    else          br_batch_cmd_avail_dly <= br_batch_cmd_avail;

  always_ff @(posedge clk)
    br_batch_cmd_dly <= br_batch_cmd;

// ============================================================================================== --
// PBS
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// NTT core with matrix multiplication
// ---------------------------------------------------------------------------------------------- --
generate
  if (S_NB == 2*S) begin : gen_entire_ntt
    if (NTT_CORE_ARCH == NTT_CORE_ARCH_GF64) begin : gen_ntt_core_gf64
      assign ntt_error.twd_phru = '0;
      assign ntt_error.ntt[1]   = '0;

      logic [PSI-1:0][R-1:0][MOD_NTT_W-1:0] next_data_tmp;

      always_comb
        for (int p=0; p<PSI; p=p+1)
          for (int r=0; r<R; r=r+1)
            next_data[p][r] = {2'b00,next_data_tmp[p][r]}; // extend with 0s
      ntt_core_gf64
      #(
        .PHI_MULT_TYPE    (PHI_MULT_TYPE),
        .PP_MULT_TYPE     (PP_MULT_TYPE),
        .RAM_LATENCY      (RAM_LATENCY),
        .ROM_LATENCY      (ROM_LATENCY),
        .TWD_GF64_FILE_PREFIX (TWD_GF64_FILE_PREFIX)
      ) ntt_core_gf64 (
        .clk                 (clk),
        .s_rst_n             (s_rst_n),

        .decomp_ntt_data     (decomp_ntt_data),
        .decomp_ntt_data_vld (decomp_ntt_data_avail),
        .decomp_ntt_data_rdy (decomp_ntt_data_rdy),
        .decomp_ntt_sob      (decomp_ntt_sob),
        .decomp_ntt_eob      (decomp_ntt_eob),
        .decomp_ntt_sol      (decomp_ntt_sol),
        .decomp_ntt_eol      (decomp_ntt_eol),
        .decomp_ntt_sog      (decomp_ntt_sog),
        .decomp_ntt_eog      (decomp_ntt_eog),
        .decomp_ntt_pbs_id   (decomp_ntt_pbs_id),
        .decomp_ntt_ctrl_vld (decomp_ntt_ctrl_avail),
        .decomp_ntt_ctrl_rdy (decomp_ntt_ctrl_rdy),

        .ntt_acc_data        (next_data_tmp),
        .ntt_acc_data_avail  (next_data_avail),
        .ntt_acc_sob         (next_sob),
        .ntt_acc_eob         (next_eob),
        .ntt_acc_sol         (next_sol),
        .ntt_acc_eol         (next_eol),
        .ntt_acc_sog         (next_sos),
        .ntt_acc_eog         (next_eos),
        .ntt_acc_pbs_id      (next_pbs_id),
        .ntt_acc_ctrl_avail  (next_ctrl_avail),

        .bsk                 (bsk),
        .bsk_vld             (bsk_vld),
        .bsk_rdy             (bsk_rdy),

        .error               (ntt_error.ntt[0])
      );
    end
    else begin : gen_ntt_core_wmm
      logic [PSI-1:0][R-1:0][MOD_NTT_W-1:0] next_data_tmp;
      logic [PSI-1:0][R-1:0][MOD_NTT_W-1:0] decomp_ntt_data_tmp;

      always_comb
        for (int p=0; p<PSI; p=p+1)
          for (int r=0; r<R; r=r+1) begin
            next_data[p][r] = {2'b00,next_data_tmp[p][r]}; // extend with 0s
            // Apply modulo on negative value
            decomp_ntt_data_tmp[p][r] = decomp_ntt_data[p][r][PBS_B_W] ?
                                          MOD_NTT + {{MOD_NTT_W-PBS_B_W{1'b1}},decomp_ntt_data[p][r][PBS_B_W-1:0]}:
                                          MOD_NTT_W'(decomp_ntt_data[p][r]); // extend with 0s
          end

      ntt_core_with_matrix_multiplication
      #(
        .OP_W                   (MOD_NTT_W),
        .MOD_NTT                (MOD_NTT),
        .MOD_NTT_TYPE           (MOD_NTT_TYPE),
        .MOD_MULT_TYPE          (MOD_MULT_TYPE),
        .REDUCT_TYPE            (REDUCT_TYPE),
        .MULT_TYPE              (PHI_MULT_TYPE),
        .PP_MOD_MULT_TYPE       (PP_MOD_MULT_TYPE),
        .PP_MULT_TYPE           (PP_MULT_TYPE),
        .NTT_CORE_ARCH          (NTT_CORE_ARCH),
        .R                      (R),
        .PSI                    (PSI),
        .S                      (S),
        .DELTA                  (DELTA),
        .BWD_PSI_DIV            (BWD_PSI_DIV),
        .RAM_LATENCY            (RAM_LATENCY),
        .ROM_LATENCY            (ROM_LATENCY),
        .TWD_IFNL_FILE_PREFIX   (TWD_IFNL_FILE_PREFIX),
        .TWD_PHRU_FILE_PREFIX   (TWD_PHRU_FILE_PREFIX)
      ) ntt_core_with_matrix_multiplication (
        .clk                        (clk),
        .s_rst_n                    (s_rst_n),

        .decomp_ntt_data            (decomp_ntt_data_tmp),
        .decomp_ntt_data_vld        (decomp_ntt_data_avail),
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
        .decomp_ntt_ctrl_vld        (decomp_ntt_ctrl_avail),
        .decomp_ntt_ctrl_rdy        (decomp_ntt_ctrl_rdy),

        .ntt_acc_data               (next_data),
        .ntt_acc_data_avail         (next_data_avail),
        .ntt_acc_sob                (next_sob),
        .ntt_acc_eob                (next_eob),
        .ntt_acc_sol                (next_sol),
        .ntt_acc_eol                (next_eol),
        .ntt_acc_sog                (next_sos),
        .ntt_acc_eog                (next_eos),
        .ntt_acc_pbs_id             (next_pbs_id),
        .ntt_acc_ctrl_avail         (next_ctrl_avail),

        .twd_omg_ru_r_pow           (twd_omg_ru_r_pow),

        .bsk                        (bsk),
        .bsk_vld                    (bsk_vld),
        .bsk_rdy                    (bsk_rdy),

        .batch_cmd                  (br_batch_cmd_dly),
        .batch_cmd_avail            (br_batch_cmd_avail_dly),

        .ntt_error                  ({ntt_error.twd_phru,ntt_error.ntt})
      );
    end
  end
  else begin : gen_head_ntt
    if (NTT_CORE_ARCH == NTT_CORE_ARCH_GF64) begin : gen_ntt_core_gf64
      assign ntt_error.twd_phru = '0;
      assign ntt_error.ntt[1]   = '0; // TOREVIEW
      assign next_ctrl_avail = next_data_avail[0][0];

      ntt_core_gf64_head
      #(
        .S_NB             (S_NB),
        .USE_PP           (USE_PP),
        .PHI_MULT_TYPE    (PHI_MULT_TYPE),
        .PP_MULT_TYPE     (PP_MULT_TYPE),
        .RAM_LATENCY      (RAM_LATENCY),
        .ROM_LATENCY      (ROM_LATENCY),
        .TWD_GF64_FILE_PREFIX (TWD_GF64_FILE_PREFIX)
      ) ntt_core_gf64_head (
        .clk                 (clk),
        .s_rst_n             (s_rst_n),

        .decomp_ntt_data     (decomp_ntt_data),
        .decomp_ntt_data_vld (decomp_ntt_data_avail),
        .decomp_ntt_data_rdy (decomp_ntt_data_rdy),
        .decomp_ntt_sob      (decomp_ntt_sob),
        .decomp_ntt_eob      (decomp_ntt_eob),
        .decomp_ntt_sol      (decomp_ntt_sol),
        .decomp_ntt_eol      (decomp_ntt_eol),
        .decomp_ntt_sog      (decomp_ntt_sog),
        .decomp_ntt_eog      (decomp_ntt_eog),
        .decomp_ntt_pbs_id   (decomp_ntt_pbs_id),
        .decomp_ntt_ctrl_vld (decomp_ntt_ctrl_avail),
        .decomp_ntt_ctrl_rdy (decomp_ntt_ctrl_rdy),

        .next_data           (next_data),
        .next_avail          (next_data_avail),
        .next_sob            (next_sob),
        .next_eob            (next_eob),
        .next_sol            (next_sol),
        .next_eol            (next_eol),
        .next_sos            (next_sos),
        .next_eos            (next_eos),
        .next_pbs_id         (next_pbs_id),

        .bsk                 (bsk),
        .bsk_vld             (bsk_vld),
        .bsk_rdy             (bsk_rdy),

        .error               (ntt_error.ntt[0])

      );
    end
    else begin : gen_ntt_core_wmm
      logic [PSI-1:0][R-1:0][MOD_NTT_W-1:0] next_data_tmp;
      logic [PSI-1:0][R-1:0][MOD_NTT_W-1:0] decomp_ntt_data_tmp;

      always_comb
        for (int p=0; p<PSI; p=p+1)
          for (int r=0; r<R; r=r+1) begin
            next_data[p][r] = {2'b00,next_data_tmp[p][r]}; // extend with 0s
            // Apply modulo on negative value
            decomp_ntt_data_tmp[p][r] = decomp_ntt_data[p][r][PBS_B_W] ?
                                          MOD_NTT + {{MOD_NTT_W-PBS_B_W{1'b1}},decomp_ntt_data[p][r][PBS_B_W-1:0]}:
                                          MOD_NTT_W'(decomp_ntt_data[p][r]); // extend with 0s
          end

      ntt_core_with_matrix_multiplication_head
      #(
        .OP_W                   (MOD_NTT_W),
        .MOD_NTT                (MOD_NTT),
        .MOD_NTT_TYPE           (MOD_NTT_TYPE),
        .MOD_MULT_TYPE          (MOD_MULT_TYPE),
        .REDUCT_TYPE            (REDUCT_TYPE),
        .MULT_TYPE              (PHI_MULT_TYPE),
        .PP_MOD_MULT_TYPE       (PP_MOD_MULT_TYPE),
        .PP_MULT_TYPE           (PP_MULT_TYPE),
        .NTT_CORE_ARCH          (NTT_CORE_ARCH),
        .R                      (R),
        .PSI                    (PSI),
        .S                      (S),
        .DELTA                  (DELTA),
        .BWD_PSI_DIV            (BWD_PSI_DIV),
        .RAM_LATENCY            (RAM_LATENCY),
        .ROM_LATENCY            (ROM_LATENCY),
        .S_NB                   (S_NB),
        .USE_PP                 (USE_PP),
        .TWD_IFNL_FILE_PREFIX   (TWD_IFNL_FILE_PREFIX),
        .TWD_PHRU_FILE_PREFIX   (TWD_PHRU_FILE_PREFIX)
      ) ntt_core_with_matrix_multiplication_head (
        .clk                        (clk),
        .s_rst_n                    (s_rst_n),

        .decomp_ntt_data            (decomp_ntt_data_tmp),
        .decomp_ntt_data_vld        (decomp_ntt_data_avail),
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
        .decomp_ntt_ctrl_vld        (decomp_ntt_ctrl_avail),
        .decomp_ntt_ctrl_rdy        (decomp_ntt_ctrl_rdy),

        .next_data                  (next_data_tmp),
        .next_data_avail            (next_data_avail),
        .next_sob                   (next_sob),
        .next_eob                   (next_eob),
        .next_sol                   (next_sol),
        .next_eol                   (next_eol),
        .next_sos                   (next_sos),
        .next_eos                   (next_eos),
        .next_pbs_id                (next_pbs_id),
        .next_ctrl_avail            (next_ctrl_avail),

        .twd_omg_ru_r_pow           (twd_omg_ru_r_pow),

        .bsk                        (bsk),
        .bsk_vld                    (bsk_vld),
        .bsk_rdy                    (bsk_rdy),

        .batch_cmd                  (br_batch_cmd_dly),
        .batch_cmd_avail            (br_batch_cmd_avail_dly),

        .ntt_error                  ({ntt_error.twd_phru,ntt_error.ntt})
      );
    end
  end
endgenerate

endmodule
