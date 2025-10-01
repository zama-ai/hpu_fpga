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
//  * pep_key_switch
//  * pep_load_blwe
// ==============================================================================================

module pe_pbs_with_ks
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

  //== pep <-> regfile
  // read
  output logic                                                         pep_regf_rd_req_vld,
  input  logic                                                         pep_regf_rd_req_rdy,
  output logic [REGF_RD_REQ_W-1:0]                                     pep_regf_rd_req,

  input  logic [REGF_COEF_NB-1:0]                                      regf_pep_rd_data_avail,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                         regf_pep_rd_data,
  input  logic                                                         regf_pep_rd_last_word, // valid with avail[0]
  input  logic                                                         regf_pep_rd_is_body,
  input  logic                                                         regf_pep_rd_last_mask,

  //== KSK coefficients
  input  logic [LBX-1:0][LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0]              ksk,
  input  logic [LBX-1:0][LBY-1:0]                                      ksk_vld,
  output logic [LBX-1:0][LBY-1:0]                                      ksk_rdy,

  //== seq <-> ldb
  input  logic [LOAD_BLWE_CMD_W-1:0]                                   seq_ldb_cmd,
  input  logic                                                         seq_ldb_vld,
  output logic                                                         seq_ldb_rdy,
  output logic                                                         ldb_seq_done,

  //== seq <-> KS
  output logic                                                         ks_seq_cmd_enquiry,
  input  logic [KS_CMD_W-1:0]                                          seq_ks_cmd,
  input  logic                                                         seq_ks_cmd_avail,

  output logic [KS_RESULT_W-1:0]                                       ks_seq_result,
  output logic                                                         ks_seq_result_vld,
  input  logic                                                         ks_seq_result_rdy,

  //== KS <-> Body RAM
  output logic                                                         ks_boram_wr_en,
  output logic [MOD_KSK_W-1:0]                                         ks_boram_data,
  output logic [PID_W-1:0]                                             ks_boram_pid,
  output logic                                                         ks_boram_parity,

  //== Control
  // KSK pointer
  input  logic                                                         inc_ksk_wr_ptr,
  output logic                                                         inc_ksk_rd_ptr,
  // Broadcast batch cmd
  output logic [KS_BATCH_CMD_W-1:0]                                    ks_batch_cmd,
  output logic                                                         ks_batch_cmd_avail,

  //== reset cache
  input  logic                                                         reset_cache,

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
// Internal signals
// ============================================================================================== --
  //== BLWE load
  // ldb <-> ks
  logic [KS_IF_SUBW_NB-1:0]                                   ldb_blram_wr_en;
  logic [KS_IF_SUBW_NB-1:0][PID_W-1:0]                        ldb_blram_wr_pid;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0]   ldb_blram_wr_data;
  logic [KS_IF_SUBW_NB-1:0]                                   ldb_blram_wr_pbs_last;

// ============================================================================================== --
// ERROR
// ============================================================================================== --
  pep_error_t       pep_errorD;
  pep_counter_inc_t pep_rif_counter_incD;

  pep_ks_error_t      ks_error;
  logic               ldb_rcp_dur;
  always_comb begin
    pep_errorD           = '0;
    pep_rif_counter_incD = '0;

    pep_errorD.ks                       = ks_error;
    pep_rif_counter_incD.ld.ldb.rcp_dur = ldb_rcp_dur;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pep_error           <= '0;
      pep_rif_counter_inc <= '0;
    end
    else begin
      pep_error           <= pep_errorD;
      pep_rif_counter_inc <= pep_rif_counter_incD;
    end

  assign pep_rif_info = '0;

// ============================================================================================== --
// Load BLWE from regfile
// ============================================================================================== --
  pep_load_blwe
  #(
    .REGF_RD_LATENCY (REGF_RD_LATENCY),
    .KS_IF_COEF_NB   (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB   (KS_IF_SUBW_NB)
  ) pep_load_blwe (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .seq_ldb_cmd            (seq_ldb_cmd),
    .seq_ldb_vld            (seq_ldb_vld),
    .seq_ldb_rdy            (seq_ldb_rdy),
    .ldb_seq_done           (ldb_seq_done),

    .pep_regf_rd_req_vld    (pep_regf_rd_req_vld),
    .pep_regf_rd_req_rdy    (pep_regf_rd_req_rdy),
    .pep_regf_rd_req        (pep_regf_rd_req),

    .regf_pep_rd_data_avail (regf_pep_rd_data_avail),
    .regf_pep_rd_data       (regf_pep_rd_data),
    .regf_pep_rd_last_word  (regf_pep_rd_last_word),
    .regf_pep_rd_is_body    (regf_pep_rd_is_body),
    .regf_pep_rd_last_mask  (regf_pep_rd_last_mask),

    .pep_blram_wr_en        (ldb_blram_wr_en),
    .pep_blram_wr_pid       (ldb_blram_wr_pid),
    .pep_blram_wr_data      (ldb_blram_wr_data),
    .pep_blram_wr_pbs_last  (ldb_blram_wr_pbs_last),

    .ldb_rif_rcp_dur        (ldb_rcp_dur)
  );

// ============================================================================================== --
// Key switch
// ============================================================================================== --
  pep_key_switch
  #(
    .RAM_LATENCY          (RAM_LATENCY),
    .ALMOST_DONE_BLINE_ID (ALMOST_DONE_BLINE_ID),
    .KS_IF_SUBW_NB        (KS_IF_SUBW_NB),
    .KS_IF_COEF_NB        (KS_IF_COEF_NB)
  ) pep_key_switch (
    .clk                   (clk),
    .s_rst_n               (s_rst_n),

    .ks_seq_cmd_enquiry    (ks_seq_cmd_enquiry),
    .seq_ks_cmd            (seq_ks_cmd),
    .seq_ks_cmd_avail      (seq_ks_cmd_avail),

    .inc_ksk_wr_ptr        (inc_ksk_wr_ptr),
    .inc_ksk_rd_ptr        (inc_ksk_rd_ptr),

    .batch_cmd             (ks_batch_cmd),
    .batch_cmd_avail       (ks_batch_cmd_avail),

    .ldb_blram_wr_en       (ldb_blram_wr_en),
    .ldb_blram_wr_pid      (ldb_blram_wr_pid),
    .ldb_blram_wr_data     (ldb_blram_wr_data),
    .ldb_blram_wr_pbs_last (ldb_blram_wr_pbs_last),

    .ksk                   (ksk),
    .ksk_vld               (ksk_vld),
    .ksk_rdy               (ksk_rdy),

    .ks_seq_result         (ks_seq_result),
    .ks_seq_result_vld     (ks_seq_result_vld),
    .ks_seq_result_rdy     (ks_seq_result_rdy),

    .boram_wr_en           (ks_boram_wr_en),
    .boram_data            (ks_boram_data),
    .boram_pid             (ks_boram_pid),
    .boram_parity          (ks_boram_parity),

    .reset_cache           (reset_cache),

    .ks_error              (ks_error)
  );

endmodule
