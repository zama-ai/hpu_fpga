// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// HPU top level.
// HPU is split into 3 parts.
// This module is the second part.
// Mainly used to ease P&R constraints.
// ==============================================================================================

`include "hpu_io_macro_inc.sv"

(* keep_hierarchy = "yes" *)
module hpu_3parts_2in3_core
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import top_common_param_pkg::*;
  import hpu_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import axi_if_trc_axi_pkg::*;
  import regf_common_param_pkg::*;
  import pem_common_param_pkg::*;
  import pea_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import pep_if_pkg::*;
#(
  // AXI4 ADD_W could be redefined by the simulation.
  parameter int    AXI4_TRC_ADD_W   = 64,
  parameter int    AXI4_PEM_ADD_W   = 64,
  parameter int    AXI4_GLWE_ADD_W  = 64,
  parameter int    AXI4_BSK_ADD_W   = 64,
  parameter int    AXI4_KSK_ADD_W   = 64,

  // HPU version
  parameter int    VERSION_MAJOR    = 2,
  parameter int    VERSION_MINOR    = 0
)
(
  input  logic                               prc_clk,     // process clock
  input  logic                               prc_srst_n, // synchronous reset

  input  logic                               cfg_clk,     // config clock
  input  logic                               cfg_srst_n, // synchronous reset

  // Decomposer -> NTT
  input  logic [PSI-1:0][R-1:0]              decomp_ntt_data_avail,
  input  logic [PSI-1:0][R-1:0][PBS_B_W:0]   decomp_ntt_data, // 2s complement
  input  logic                               decomp_ntt_sob,
  input  logic                               decomp_ntt_eob,
  input  logic                               decomp_ntt_sog,
  input  logic                               decomp_ntt_eog,
  input  logic                               decomp_ntt_sol,
  input  logic                               decomp_ntt_eol,
  input  logic [BPBS_ID_W-1:0]               decomp_ntt_pbs_id,
  input  logic                               decomp_ntt_last_pbs,
  input  logic                               decomp_ntt_full_throughput,
  input  logic                               decomp_ntt_ctrl_avail,

  // Mod switch output
  output logic [PSI-1:0][R-1:0]              ntt_acc_modsw_data_avail,
  output logic                               ntt_acc_modsw_ctrl_avail,
  output logic [PSI-1:0][R-1:0][MOD_Q_W-1:0] ntt_acc_modsw_data,
  output logic                               ntt_acc_modsw_sob,
  output logic                               ntt_acc_modsw_eob,
  output logic                               ntt_acc_modsw_sol,
  output logic                               ntt_acc_modsw_eol,
  output logic                               ntt_acc_modsw_sog,
  output logic                               ntt_acc_modsw_eog,
  output logic [BPBS_ID_W-1:0]               ntt_acc_modsw_pbs_id,

  //-- Data path
  output ntt_proc_data_t                     p2_p3_ntt_proc_data,
  output logic [PSI-1:0][R-1:0]              p2_p3_ntt_proc_avail,
  output logic                               p2_p3_ntt_proc_ctrl_avail,

  input  ntt_proc_data_t                     p3_p2_ntt_proc_data,
  input  logic [PSI-1:0][R-1:0]              p3_p2_ntt_proc_avail,
  input  logic                               p3_p2_ntt_proc_ctrl_avail,

  //-- Cmd path
  input ntt_proc_cmd_t                       ntt_proc_cmd,
  input logic                                ntt_proc_cmd_avail,

  //-- For regif
  output pep_rif_elt_t                       pep_rif_elt
);

// ============================================================================================== --
// localparam
// ============================================================================================== --

// ============================================================================================== --
// Signals
// ============================================================================================== --
  // -------------------------------------------------------------------------------------------- --
  // Control
  // -------------------------------------------------------------------------------------------- --
  logic [BR_BATCH_CMD_W-1:0]              br_batch_cmd;
  logic                                   br_batch_cmd_avail;

  // -------------------------------------------------------------------------------------------- --
  // NTT
  // -------------------------------------------------------------------------------------------- --
  // Output data to next ntt
  ntt_proc_data_t                         next_otw_data;
  logic [PSI-1:0][R-1:0]                  next_otw_data_avail;
  logic                                   next_otw_ctrl_avail;

  // Input from previous ntt
  ntt_proc_data_t                         prev_ret_data;
  logic [PSI-1:0][R-1:0]                  prev_ret_data_avail;
  logic                                   prev_ret_ctrl_avail;

  // NTT/INTT output
  logic [PSI-1:0][R-1:0]                  ntt_acc_data_avail;
  logic                                   ntt_acc_ctrl_avail;
  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]     ntt_acc_data;
  logic                                   ntt_acc_sob;
  logic                                   ntt_acc_eob;
  logic                                   ntt_acc_sol;
  logic                                   ntt_acc_eol;
  logic                                   ntt_acc_sog;
  logic                                   ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                   ntt_acc_pbs_id;

  // Errors and counters
  pep_error_t                             pep_error;
  pep_info_t                              pep_rif_info;
  pep_counter_inc_t                       pep_rif_counter_inc;

  pep_error_t                             pep_otw_error;
  pep_error_t                             pep_ret_error;
  pep_error_t                             pep_modsw_error;

  pep_info_t                              pep_otw_rif_info;
  pep_info_t                              pep_ret_rif_info;
  pep_info_t                              pep_modsw_rif_info;

  pep_counter_inc_t                       pep_otw_rif_counter_inc;
  pep_counter_inc_t                       pep_ret_rif_counter_inc;
  pep_counter_inc_t                       pep_modsw_rif_counter_inc;

// ============================================================================================== --
// Side
// ============================================================================================== --
  pep_error_t                             pep_errorD;
  pep_info_t                              pep_rif_infoD;
  pep_counter_inc_t                       pep_rif_counter_incD;

  assign pep_errorD           = pep_otw_error
                                | pep_ret_error
                                | pep_modsw_error;
  assign pep_rif_infoD        = pep_otw_rif_info
                                | pep_ret_rif_info
                                | pep_modsw_rif_info;
  assign pep_rif_counter_incD = pep_otw_rif_counter_inc
                                | pep_ret_rif_counter_inc
                                | pep_modsw_rif_counter_inc;

  always_ff @(posedge prc_clk)
    if (!prc_srst_n) begin
      pep_error           <= '0;
      pep_rif_info        <= '0;
      pep_rif_counter_inc <= '0;
    end
    else begin
      pep_error           <= pep_errorD          ;
      pep_rif_info        <= pep_rif_infoD       ;
      pep_rif_counter_inc <= pep_rif_counter_incD;
    end

// ============================================================================================== --
// Input
// ============================================================================================== --
  assign prev_ret_data       = p3_p2_ntt_proc_data;
  assign prev_ret_data_avail = p3_p2_ntt_proc_avail;
  assign prev_ret_ctrl_avail = p3_p2_ntt_proc_ctrl_avail;

// ============================================================================================== --
// Output
// ============================================================================================== --
  assign p2_p3_ntt_proc_data       = next_otw_data;
  assign p2_p3_ntt_proc_avail      = next_otw_data_avail;
  assign p2_p3_ntt_proc_ctrl_avail = next_otw_ctrl_avail;

  assign pep_rif_elt.error           = pep_error;
  assign pep_rif_elt.rif_info        = pep_rif_info;
  assign pep_rif_elt.rif_counter_inc = pep_rif_counter_inc;

// ============================================================================================== --
// pe_pbs_with_ntt_core_middle : outward
// contains:
// * ntt_core_middle
// ============================================================================================== --
  pe_pbs_with_ntt_core_head
  #(
    .MOD_MULT_TYPE         (MOD_MULT_TYPE),
    .REDUCT_TYPE           (REDUCT_TYPE),
    .PHI_MULT_TYPE         (PHI_MULT_TYPE),
    .PP_MOD_MULT_TYPE      (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE          (PP_MULT_TYPE),
    .MODSW_2_PRECISION_W   (MODSW_2_PRECISION_W),
    .MODSW_2_MULT_TYPE     (MODSW_2_MULT_TYPE),
    .MODSW_MULT_TYPE       (MODSW_MULT_TYPE),
    .RAM_LATENCY           (RAM_LATENCY),
    .URAM_LATENCY          (URAM_LATENCY),
    .ROM_LATENCY           (ROM_LATENCY),
    .TWD_IFNL_FILE_PREFIX  (TWD_IFNL_FILE_PREFIX),
    .TWD_PHRU_FILE_PREFIX  (TWD_PHRU_FILE_PREFIX),
    .TWD_GF64_FILE_PREFIX  (TWD_GF64_FILE_PREFIX),
    .INST_FIFO_DEPTH       (PEP_INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH),
    .S_NB                  (MID0_S_NB),
    .USE_PP                (MID0_USE_PP)
  ) pe_pbs_with_ntt_core_head (
    .clk                        (prc_clk),
    .s_rst_n                    (prc_srst_n),

    .twd_omg_ru_r_pow           ('x), /*UNUSED*/

    .br_batch_cmd               (ntt_proc_cmd.batch_cmd),
    .br_batch_cmd_avail         (ntt_proc_cmd_avail),

    .bsk                        ('x), /*UNUSED*/
    .bsk_vld                    ('x), /*UNUSED*/
    .bsk_rdy                    (),   /*UNUSED*/

    .decomp_ntt_data_avail      (decomp_ntt_data_avail),
    .decomp_ntt_data            (decomp_ntt_data),
    .decomp_ntt_sob             (decomp_ntt_sob),
    .decomp_ntt_eob             (decomp_ntt_eob),
    .decomp_ntt_sog             (decomp_ntt_sog),
    .decomp_ntt_eog             (decomp_ntt_eog),
    .decomp_ntt_sol             (decomp_ntt_sol),
    .decomp_ntt_eol             (decomp_ntt_eol),
    .decomp_ntt_pbs_id          (decomp_ntt_pbs_id),
    .decomp_ntt_last_pbs        (decomp_ntt_last_pbs),
    .decomp_ntt_full_throughput (decomp_ntt_full_throughput),
    .decomp_ntt_ctrl_avail      (decomp_ntt_ctrl_avail),
    .decomp_ntt_data_rdy        (/*UNUSED*/),
    .decomp_ntt_ctrl_rdy        (/*UNUSED*/),

    .next_data                  (next_otw_data.data),
    .next_data_avail            (next_otw_data_avail),
    .next_sob                   (next_otw_data.sob),
    .next_eob                   (next_otw_data.eob),
    .next_sol                   (next_otw_data.sol),
    .next_eol                   (next_otw_data.eol),
    .next_sos                   (next_otw_data.sos),
    .next_eos                   (next_otw_data.eos),
    .next_pbs_id                (next_otw_data.pbs_id),
    .next_ctrl_avail            (next_otw_ctrl_avail),

    .pep_error                  (pep_otw_error),
    .pep_rif_info               (pep_otw_rif_info),
    .pep_rif_counter_inc        (pep_otw_rif_counter_inc)
  );

// ============================================================================================== --
// pe_pbs_with_ntt_core_tail : return
// contains:
// * ntt_core_tail
// ============================================================================================== --
  pe_pbs_with_ntt_core_tail
  #(
    .MOD_MULT_TYPE         (MOD_MULT_TYPE),
    .REDUCT_TYPE           (REDUCT_TYPE),
    .PHI_MULT_TYPE         (PHI_MULT_TYPE),
    .PP_MOD_MULT_TYPE      (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE          (PP_MULT_TYPE),
    .MODSW_2_PRECISION_W   (MODSW_2_PRECISION_W),
    .MODSW_2_MULT_TYPE     (MODSW_2_MULT_TYPE),
    .MODSW_MULT_TYPE       (MODSW_MULT_TYPE),
    .RAM_LATENCY           (RAM_LATENCY),
    .URAM_LATENCY          (URAM_LATENCY),
    .ROM_LATENCY           (ROM_LATENCY),
    .TWD_IFNL_FILE_PREFIX  (TWD_IFNL_FILE_PREFIX),
    .TWD_PHRU_FILE_PREFIX  (TWD_PHRU_FILE_PREFIX),
    .TWD_GF64_FILE_PREFIX  (TWD_GF64_FILE_PREFIX),
    .INST_FIFO_DEPTH       (PEP_INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH),
    .S_NB                  (MID2_S_NB),
    .USE_PP                (MID2_USE_PP),
    .S_INIT                (MID2_S_INIT)
  ) pe_pbs_with_ntt_core_tail (
    .clk                   (prc_clk),
    .s_rst_n               (prc_srst_n),

    .twd_omg_ru_r_pow      ('x), /*UNUSED*/


    .br_batch_cmd          (ntt_proc_cmd.batch_cmd),
    .br_batch_cmd_avail    (ntt_proc_cmd_avail),

    .bsk                   ('x), /*UNUSED*/
    .bsk_vld               ('x), /*UNUSED*/
    .bsk_rdy               (),   /*UNUSED*/

    .prev_data             (prev_ret_data.data),
    .prev_data_avail       (prev_ret_data_avail),
    .prev_sob              (prev_ret_data.sob),
    .prev_eob              (prev_ret_data.eob),
    .prev_sol              (prev_ret_data.sol),
    .prev_eol              (prev_ret_data.eol),
    .prev_sos              (prev_ret_data.sos),
    .prev_eos              (prev_ret_data.eos),
    .prev_pbs_id           (prev_ret_data.pbs_id),
    .prev_ctrl_avail       (prev_ret_ctrl_avail),

    .ntt_acc_data          (ntt_acc_data),
    .ntt_acc_data_avail    (ntt_acc_data_avail),
    .ntt_acc_sob           (ntt_acc_sob),
    .ntt_acc_eob           (ntt_acc_eob),
    .ntt_acc_sol           (ntt_acc_sol),
    .ntt_acc_eol           (ntt_acc_eol),
    .ntt_acc_sog           (ntt_acc_sog),
    .ntt_acc_eog           (ntt_acc_eog),
    .ntt_acc_pbs_id        (ntt_acc_pbs_id),
    .ntt_acc_ctrl_avail    (ntt_acc_ctrl_avail),

    .pep_error             (pep_ret_error),
    .pep_rif_info          (pep_ret_rif_info),
    .pep_rif_counter_inc   (pep_ret_rif_counter_inc)
  );

// ---------------------------------------------------------------------------------------------- --
// pe_pbs_with_modsw
// contains:
// * mod switch
// ---------------------------------------------------------------------------------------------- --
  pe_pbs_with_modsw
  #(
    .MOD_MULT_TYPE         (MOD_MULT_TYPE),
    .REDUCT_TYPE           (REDUCT_TYPE),
    .MULT_TYPE             (MULT_TYPE),
    .PP_MOD_MULT_TYPE      (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE          (PP_MULT_TYPE),
    .MODSW_2_PRECISION_W   (MODSW_2_PRECISION_W),
    .MODSW_2_MULT_TYPE     (MODSW_2_MULT_TYPE),
    .MODSW_MULT_TYPE       (MODSW_MULT_TYPE),
    .RAM_LATENCY           (RAM_LATENCY),
    .URAM_LATENCY          (URAM_LATENCY),
    .ROM_LATENCY           (ROM_LATENCY),
    .TWD_IFNL_FILE_PREFIX  (TWD_IFNL_FILE_PREFIX),
    .TWD_PHRU_FILE_PREFIX  (TWD_PHRU_FILE_PREFIX),
    .INST_FIFO_DEPTH       (PEP_INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  ) pe_pbs_with_modsw (
    .clk                      (prc_clk),
    .s_rst_n                  (prc_srst_n),

    .ntt_acc_data_avail       (ntt_acc_data_avail),
    .ntt_acc_ctrl_avail       (ntt_acc_ctrl_avail),
    .ntt_acc_data             (ntt_acc_data),
    .ntt_acc_sob              (ntt_acc_sob),
    .ntt_acc_eob              (ntt_acc_eob),
    .ntt_acc_sol              (ntt_acc_sol),
    .ntt_acc_eol              (ntt_acc_eol),
    .ntt_acc_sog              (ntt_acc_sog),
    .ntt_acc_eog              (ntt_acc_eog),
    .ntt_acc_pbs_id           (ntt_acc_pbs_id),

    .ntt_acc_modsw_data_avail (ntt_acc_modsw_data_avail),
    .ntt_acc_modsw_ctrl_avail (ntt_acc_modsw_ctrl_avail),
    .ntt_acc_modsw_data       (ntt_acc_modsw_data),
    .ntt_acc_modsw_sob        (ntt_acc_modsw_sob),
    .ntt_acc_modsw_eob        (ntt_acc_modsw_eob),
    .ntt_acc_modsw_sol        (ntt_acc_modsw_sol),
    .ntt_acc_modsw_eol        (ntt_acc_modsw_eol),
    .ntt_acc_modsw_sog        (ntt_acc_modsw_sog),
    .ntt_acc_modsw_eog        (ntt_acc_modsw_eog),
    .ntt_acc_modsw_pbs_id     (ntt_acc_modsw_pbs_id),

    .pep_error                (pep_modsw_error),
    .pep_rif_info             (pep_modsw_rif_info),
    .pep_rif_counter_inc      (pep_modsw_rif_counter_inc)
  );

endmodule

