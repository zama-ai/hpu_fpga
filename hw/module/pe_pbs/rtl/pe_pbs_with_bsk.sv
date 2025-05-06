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
//  * bsk_if
//  * bsk_manager
// ==============================================================================================

module pe_pbs_with_bsk
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import bsk_if_common_param_pkg::*;
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
  input  logic                                                         reset_bsk_cache,
  output logic                                                         reset_bsk_cache_done, // pulse
  input  logic                                                         bsk_mem_avail,
  input  logic [BSK_PC_MAX-1:0][axi_if_bsk_axi_pkg::AXI4_ADD_W-1:0]    bsk_mem_addr,

  //== AXI BSK
  output logic [BSK_PC-1:0][axi_if_bsk_axi_pkg::AXI4_ID_W-1:0]         m_axi4_bsk_arid,
  output logic [BSK_PC-1:0][axi_if_bsk_axi_pkg::AXI4_ADD_W-1:0]        m_axi4_bsk_araddr,
  output logic [BSK_PC-1:0][AXI4_LEN_W-1:0]                            m_axi4_bsk_arlen,
  output logic [BSK_PC-1:0][AXI4_SIZE_W-1:0]                           m_axi4_bsk_arsize,
  output logic [BSK_PC-1:0][AXI4_BURST_W-1:0]                          m_axi4_bsk_arburst,
  output logic [BSK_PC-1:0]                                            m_axi4_bsk_arvalid,
  input  logic [BSK_PC-1:0]                                            m_axi4_bsk_arready,
  input  logic [BSK_PC-1:0][axi_if_bsk_axi_pkg::AXI4_ID_W-1:0]         m_axi4_bsk_rid,
  input  logic [BSK_PC-1:0][axi_if_bsk_axi_pkg::AXI4_DATA_W-1:0]       m_axi4_bsk_rdata,
  input  logic [BSK_PC-1:0][AXI4_RESP_W-1:0]                           m_axi4_bsk_rresp,
  input  logic [BSK_PC-1:0]                                            m_axi4_bsk_rlast,
  input  logic [BSK_PC-1:0]                                            m_axi4_bsk_rvalid,
  output logic [BSK_PC-1:0]                                            m_axi4_bsk_rready,

  //== Control
  // Broadcast batch cmd
  input  logic [BR_BATCH_CMD_W-1:0]                                    br_batch_cmd,
  input  logic                                                         br_batch_cmd_avail,
  // BSK start
  input  logic                                                         bsk_if_batch_start_1h,
  // BSK pointer
  output logic                                                         inc_bsk_wr_ptr,
  input  logic                                                         inc_bsk_rd_ptr,

  //== BSK coefficients
  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][MOD_NTT_W-1:0]          bsk,
  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                         bsk_vld,
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                         bsk_rdy,

  //== To rif
  output pep_error_t                                                   pep_error,
  output pep_counter_inc_t                                             pep_rif_counter_inc,
  output pep_info_t                                                    pep_rif_info

);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int ALMOST_DONE_BLINE_ID = 0; // TOREVIEW - adjust according to performance

// ============================================================================================== --
// Internal signals
// ============================================================================================== --
  //== BSK

  // BSK if <-> BSK manager
  logic [BSK_CUT_NB-1:0]                                      bsk_mgr_wr_en;
  logic [BSK_CUT_NB-1:0][BSK_CUT_FCOEF_NB-1:0][MOD_NTT_W-1:0] bsk_mgr_wr_data;
  logic [BSK_CUT_NB-1:0][BSK_RAM_ADD_W-1:0]                   bsk_mgr_wr_add;
  logic [BSK_CUT_NB-1:0][GLWE_K_P1_W-1:0]                     bsk_mgr_wr_g_idx;
  logic [BSK_CUT_NB-1:0][BSK_SLOT_W-1:0]                      bsk_mgr_wr_slot;
  logic [BSK_CUT_NB-1:0][LWE_K_W-1:0]                         bsk_mgr_wr_br_loop;


// ============================================================================================== --
// Error / Inc / Info
// ============================================================================================== --
  pep_error_t        pep_errorD;
  pep_counter_inc_t  pep_rif_counter_incD;
  pep_info_t         pep_rif_infoD;

  pep_bsk_error_t    bsk_mgr_error;
  logic [BSK_PC-1:0] load_bsk_pc_recp_dur;
  bskif_info_t       bskif_rif_info;

  always_comb begin
    pep_errorD                                         = '0;
    pep_rif_counter_incD                               = '0;
    pep_rif_infoD                                      = '0;

    pep_errorD.bsk_mgr                                = bsk_mgr_error;
    pep_rif_counter_incD.key.load_bsk_dur[BSK_PC-1:0] = load_bsk_pc_recp_dur;
    pep_rif_infoD.bskif                               = bskif_rif_info;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pep_error           <= '0;
      pep_rif_counter_inc <= '0;
      pep_rif_info        <= '0;
    end
    else begin
      pep_error           <= pep_errorD;
      pep_rif_counter_inc <= pep_rif_counter_incD;
      pep_rif_info        <= pep_rif_infoD;
    end

// ============================================================================================== --
// BSK
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// bsk_if
// ---------------------------------------------------------------------------------------------- --
  bsk_if bsk_if
  (
    .clk                  (clk),
    .s_rst_n              (s_rst_n),

    .reset_cache          (reset_bsk_cache),
    .reset_cache_done     (reset_bsk_cache_done),

    .m_axi4_arid          (m_axi4_bsk_arid),
    .m_axi4_araddr        (m_axi4_bsk_araddr),
    .m_axi4_arlen         (m_axi4_bsk_arlen),
    .m_axi4_arsize        (m_axi4_bsk_arsize),
    .m_axi4_arburst       (m_axi4_bsk_arburst),
    .m_axi4_arvalid       (m_axi4_bsk_arvalid),
    .m_axi4_arready       (m_axi4_bsk_arready),
    .m_axi4_rid           (m_axi4_bsk_rid),
    .m_axi4_rdata         (m_axi4_bsk_rdata),
    .m_axi4_rresp         (m_axi4_bsk_rresp),
    .m_axi4_rlast         (m_axi4_bsk_rlast),
    .m_axi4_rvalid        (m_axi4_bsk_rvalid),
    .m_axi4_rready        (m_axi4_bsk_rready),

    .bsk_mem_avail        (bsk_mem_avail),
    .bsk_mem_addr         (bsk_mem_addr),

    .batch_start_1h       (bsk_if_batch_start_1h),

    .inc_bsk_wr_ptr       (inc_bsk_wr_ptr),
    .inc_bsk_rd_ptr       (inc_bsk_rd_ptr),

    .bsk_mgr_wr_en        (bsk_mgr_wr_en),
    .bsk_mgr_wr_data      (bsk_mgr_wr_data),
    .bsk_mgr_wr_add       (bsk_mgr_wr_add),
    .bsk_mgr_wr_g_idx     (bsk_mgr_wr_g_idx),
    .bsk_mgr_wr_slot      (bsk_mgr_wr_slot),
    .bsk_mgr_wr_br_loop   (bsk_mgr_wr_br_loop),

    .load_bsk_pc_recp_dur (load_bsk_pc_recp_dur),
    .bskif_rif_info       (bskif_rif_info)
  );

// ---------------------------------------------------------------------------------------------- --
// bsk_manager
// ---------------------------------------------------------------------------------------------- --
  bsk_manager
  #(
    .OP_W          (MOD_Q_W),
    .RAM_LATENCY   (URAM_LATENCY)
  ) bsk_manager (
    .clk             (clk),
    .s_rst_n         (s_rst_n),
    .reset_cache     (reset_bsk_cache),

    .bsk             (bsk),
    .bsk_vld         (bsk_vld),
    .bsk_rdy         (bsk_rdy),


    .batch_cmd       (br_batch_cmd),
    .batch_cmd_avail (br_batch_cmd_avail),

    .wr_en           (bsk_mgr_wr_en),
    .wr_data         (bsk_mgr_wr_data),
    .wr_add          (bsk_mgr_wr_add),
    .wr_g_idx        (bsk_mgr_wr_g_idx),
    .wr_slot         (bsk_mgr_wr_slot),
    .wr_br_loop      (bsk_mgr_wr_br_loop),

    .bsk_mgr_error   (bsk_mgr_error)
  );

endmodule
