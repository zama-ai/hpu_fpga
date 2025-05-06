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
// This subpart contains :
//  * pep_br_mod_switch_to_2powerN
// ==============================================================================================

module pe_pbs_with_modsw
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
  parameter  arith_mult_type_e MULT_TYPE           = set_ntt_mult_type(MOD_NTT_W,MOD_NTT_TYPE),
  parameter  mod_mult_type_e   PP_MOD_MULT_TYPE    = MOD_MULT_TYPE,
  parameter  arith_mult_type_e PP_MULT_TYPE        = MULT_TYPE,
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
  // Instruction FIFO depth
  parameter  int               INST_FIFO_DEPTH      = 8, // Should be >= 2
  // Regfile info
  parameter int                REGF_RD_LATENCY      = URAM_LATENCY + 4, // minimum latency to get the data
  parameter int                KS_IF_COEF_NB        = (LBY < REGF_COEF_NB) ? LBY : REGF_SEQ_COEF_NB,
  parameter int                KS_IF_SUBW_NB        = (LBY < REGF_COEF_NB) ? 1 : REGF_SEQ,
  //
  parameter int                PHYS_RAM_DEPTH       = 1024 // Physical RAM depth. Should be a power of 2. In Xilinx is BRAM depth for 32b words
)
(
  input  logic                                                         clk,       // clock
  input  logic                                                         s_rst_n,    // synchronous reset

  //== NTT core
  // NTT core -> modSW
  input  logic [PSI-1:0][R-1:0]                                        ntt_acc_data_avail,
  input  logic                                                         ntt_acc_ctrl_avail,
  input  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]                           ntt_acc_data,
  input  logic                                                         ntt_acc_sob,
  input  logic                                                         ntt_acc_eob,
  input  logic                                                         ntt_acc_sol,
  input  logic                                                         ntt_acc_eol,
  input  logic                                                         ntt_acc_sog,
  input  logic                                                         ntt_acc_eog,
  input  logic [BPBS_ID_W-1:0]                                         ntt_acc_pbs_id,

  //== ModSW
  // ModSW -> MMACC
  output logic [PSI-1:0][R-1:0]                                        ntt_acc_modsw_data_avail,
  output logic                                                         ntt_acc_modsw_ctrl_avail,
  output logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]                           ntt_acc_modsw_data,
  output logic                                                         ntt_acc_modsw_sob,
  output logic                                                         ntt_acc_modsw_eob,
  output logic                                                         ntt_acc_modsw_sol,
  output logic                                                         ntt_acc_modsw_eol,
  output logic                                                         ntt_acc_modsw_sog,
  output logic                                                         ntt_acc_modsw_eog,
  output logic [BPBS_ID_W-1:0]                                         ntt_acc_modsw_pbs_id,

  //== Info for regif
  output pep_error_t                                                   pep_error,
  output pep_info_t                                                    pep_rif_info,
  output pep_counter_inc_t                                             pep_rif_counter_inc
);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int ALMOST_DONE_BLINE_ID = 0; // TOREVIEW - adjust according to performance

// ============================================================================================== --
// Internal signals
// ============================================================================================== --

// ============================================================================================== --
// Error, Inc, Info
// ============================================================================================== --
  pep_error_t pep_errorD;

  assign pep_errorD = '0;

  always_ff @(posedge clk)
    if (!s_rst_n) pep_error <= '0;
    else          pep_error <= pep_errorD;

  assign pep_rif_info        = '0;
  assign pep_rif_counter_inc = '0;

// ============================================================================================== --
// PBS
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// mod_switch_to_2powerN
// ---------------------------------------------------------------------------------------------- --
  assign ntt_acc_modsw_ctrl_avail = ntt_acc_modsw_data_avail[0][0];

  pep_br_mod_switch_to_2powerN
  #(
    .R                (R),
    .PSI              (PSI),
    .MOD_Q_W          (MOD_Q_W),
    .MOD_NTT_W        (MOD_NTT_W),
    .MOD_NTT          (MOD_NTT),
    .MOD_NTT_INV_TYPE (MOD_NTT_INV_TYPE),
    .MULT_TYPE        (MODSW_2_MULT_TYPE),
    .PRECISION_W      (MODSW_2_PRECISION_W),
    .IN_PIPE          (1'b1),
    .SIDE_W           (6+BPBS_ID_W),
    .RST_SIDE         (2'b00)
  ) pep_br_mod_switch_to_2powerN (
    .clk      (clk),
    .s_rst_n  (s_rst_n),
    .a        (ntt_acc_data),
    .z        (ntt_acc_modsw_data),
    .in_avail (ntt_acc_data_avail),
    .out_avail(ntt_acc_modsw_data_avail),
    .in_side  ({ntt_acc_sob,
                ntt_acc_eob,
                ntt_acc_sol,
                ntt_acc_eol,
                ntt_acc_sog,
                ntt_acc_eog,
                ntt_acc_pbs_id}),
    .out_side ({ntt_acc_modsw_sob,
                ntt_acc_modsw_eob,
                ntt_acc_modsw_sol,
                ntt_acc_modsw_eol,
                ntt_acc_modsw_sog,
                ntt_acc_modsw_eog,
                ntt_acc_modsw_pbs_id})
  );

endmodule
