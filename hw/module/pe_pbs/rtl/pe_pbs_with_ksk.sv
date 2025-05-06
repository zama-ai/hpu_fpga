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
//  * ksk_if
//  * ksk_manager
// ==============================================================================================

module pe_pbs_with_ksk
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

  //== Configuration
  input  logic                                                         reset_ksk_cache,
  output logic                                                         reset_ksk_cache_done, // pulse
  input  logic                                                         ksk_mem_avail,
  input  logic [KSK_PC_MAX-1:0][axi_if_ksk_axi_pkg::AXI4_ADD_W-1:0]    ksk_mem_addr,

  //== AXI KSK
  output logic [KSK_PC-1:0][axi_if_ksk_axi_pkg::AXI4_ID_W-1:0]         m_axi4_ksk_arid,
  output logic [KSK_PC-1:0][axi_if_ksk_axi_pkg::AXI4_ADD_W-1:0]        m_axi4_ksk_araddr,
  output logic [KSK_PC-1:0][AXI4_LEN_W-1:0]                            m_axi4_ksk_arlen,
  output logic [KSK_PC-1:0][AXI4_SIZE_W-1:0]                           m_axi4_ksk_arsize,
  output logic [KSK_PC-1:0][AXI4_BURST_W-1:0]                          m_axi4_ksk_arburst,
  output logic [KSK_PC-1:0]                                            m_axi4_ksk_arvalid,
  input  logic [KSK_PC-1:0]                                            m_axi4_ksk_arready,
  input  logic [KSK_PC-1:0][axi_if_ksk_axi_pkg::AXI4_ID_W-1:0]         m_axi4_ksk_rid,
  input  logic [KSK_PC-1:0][axi_if_ksk_axi_pkg::AXI4_DATA_W-1:0]       m_axi4_ksk_rdata,
  input  logic [KSK_PC-1:0][AXI4_RESP_W-1:0]                           m_axi4_ksk_rresp,
  input  logic [KSK_PC-1:0]                                            m_axi4_ksk_rlast,
  input  logic [KSK_PC-1:0]                                            m_axi4_ksk_rvalid,
  output logic [KSK_PC-1:0]                                            m_axi4_ksk_rready,

  //== Control
  // KSK pointer
  output logic                                                         inc_ksk_wr_ptr,
  input  logic                                                         inc_ksk_rd_ptr,
  // Broadcast batch cmd
  input  logic [KS_BATCH_CMD_W-1:0]                                    ks_batch_cmd,
  input  logic                                                         ks_batch_cmd_avail,// KSK start
  input  logic                                                         ksk_if_batch_start_1h,


  //== KSK coefficients
  output logic [LBX-1:0][LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0]              ksk,
  output logic [LBX-1:0][LBY-1:0]                                      ksk_vld,
  input  logic [LBX-1:0][LBY-1:0]                                      ksk_rdy,

  //== Error
  output pep_error_t                                                   pep_error,

  //== Info for regif
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
  //== KSK if <-> KSK manager
  logic [KSK_CUT_NB-1:0]                                      ksk_mgr_wr_en;
  logic [KSK_CUT_NB-1:0][KSK_CUT_FCOEF_NB-1:0][LBZ-1:0][MOD_KSK_W-1:0]  ksk_mgr_wr_data;
  logic [KSK_CUT_NB-1:0][KSK_RAM_ADD_W-1:0]                   ksk_mgr_wr_add;
  logic [KSK_CUT_NB-1:0][LBX_W-1:0]                           ksk_mgr_wr_x_idx;
  logic [KSK_CUT_NB-1:0][KSK_SLOT_W-1:0]                      ksk_mgr_wr_slot;
  logic [KSK_CUT_NB-1:0][KS_BLOCK_COL_W-1:0]                  ksk_mgr_wr_ks_loop;

// ============================================================================================== --
// Error / Inc
// ============================================================================================== --
  pep_error_t        pep_errorD;
  pep_counter_inc_t  pep_rif_counter_incD;

  pep_ksk_error_t    ksk_mgr_error;
  logic [KSK_PC-1:0] load_ksk_pc_recp_dur;

  always_comb begin
    pep_errorD                                        = '0;
    pep_rif_counter_incD                              = '0;
    pep_errorD.ksk_mgr                                = ksk_mgr_error;
    pep_rif_counter_incD.key.load_ksk_dur[KSK_PC-1:0] = load_ksk_pc_recp_dur;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pep_error <= '0;
      pep_rif_counter_inc <= '0;
    end
    else begin
      pep_error <= pep_errorD;
      pep_rif_counter_inc <= pep_rif_counter_incD;
    end

  assign pep_rif_info = '0;

// ============================================================================================== --
// KSK
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// ksk_if
// ---------------------------------------------------------------------------------------------- --
  ksk_if ksk_if
  (
    .clk                  (clk),
    .s_rst_n              (s_rst_n),

    .reset_cache          (reset_ksk_cache),
    .reset_cache_done     (reset_ksk_cache_done),

    .m_axi4_arid          (m_axi4_ksk_arid),
    .m_axi4_araddr        (m_axi4_ksk_araddr),
    .m_axi4_arlen         (m_axi4_ksk_arlen),
    .m_axi4_arsize        (m_axi4_ksk_arsize),
    .m_axi4_arburst       (m_axi4_ksk_arburst),
    .m_axi4_arvalid       (m_axi4_ksk_arvalid),
    .m_axi4_arready       (m_axi4_ksk_arready),
    .m_axi4_rid           (m_axi4_ksk_rid),
    .m_axi4_rdata         (m_axi4_ksk_rdata),
    .m_axi4_rresp         (m_axi4_ksk_rresp),
    .m_axi4_rlast         (m_axi4_ksk_rlast),
    .m_axi4_rvalid        (m_axi4_ksk_rvalid),
    .m_axi4_rready        (m_axi4_ksk_rready),

    .ksk_mem_avail        (ksk_mem_avail),
    .ksk_mem_addr         (ksk_mem_addr),

    .batch_start_1h       (ksk_if_batch_start_1h),

    .inc_ksk_wr_ptr       (inc_ksk_wr_ptr),
    .inc_ksk_rd_ptr       (inc_ksk_rd_ptr),

    .ksk_mgr_wr_en        (ksk_mgr_wr_en),
    .ksk_mgr_wr_data      (ksk_mgr_wr_data),
    .ksk_mgr_wr_add       (ksk_mgr_wr_add),
    .ksk_mgr_wr_x_idx     (ksk_mgr_wr_x_idx),
    .ksk_mgr_wr_slot      (ksk_mgr_wr_slot),
    .ksk_mgr_wr_ks_loop   (ksk_mgr_wr_ks_loop),

    .load_ksk_pc_recp_dur (load_ksk_pc_recp_dur)
  );

// ---------------------------------------------------------------------------------------------- --
// ksk_manager
// ---------------------------------------------------------------------------------------------- --
  ksk_manager
  #(
    .RAM_LATENCY (URAM_LATENCY)
  ) ksk_manager (
    .clk             (clk),
    .s_rst_n         (s_rst_n),

    .reset_cache     (reset_ksk_cache),

    .ksk             (ksk),
    .ksk_vld         (ksk_vld),
    .ksk_rdy         (ksk_rdy),

    .batch_cmd       (ks_batch_cmd),
    .batch_cmd_avail (ks_batch_cmd_avail),

    .wr_en           (ksk_mgr_wr_en),
    .wr_data         (ksk_mgr_wr_data),
    .wr_add          (ksk_mgr_wr_add),
    .wr_x_idx        (ksk_mgr_wr_x_idx),
    .wr_slot         (ksk_mgr_wr_slot),
    .wr_ks_loop      (ksk_mgr_wr_ks_loop),

    .error           (ksk_mgr_error)
  );

endmodule
