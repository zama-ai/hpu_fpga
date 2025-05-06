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
// ==============================================================================================

module pe_pbs
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
  parameter  arith_mult_type_e MULT_TYPE           = MULT_CORE,
  parameter  arith_mult_type_e PHI_MULT_TYPE       = set_ntt_mult_type(MOD_NTT_W,MOD_NTT_TYPE),
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
  parameter  string            TWD_GF64_FILE_PREFIX = $sformatf("memory_file/twiddle/NTT_CORE_ARCH_GF64/R%0d_PSI%0d/twd_phi",R,PSI),
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

  //== DOP instruction
  input  logic [PE_INST_W-1:0]                                         inst,
  input  logic                                                         inst_vld,
  output logic                                                         inst_rdy,

  output logic                                                         inst_ack,
  output logic [LWE_K_W-1:0]                                           inst_ack_br_loop,
  output logic                                                         inst_load_blwe_ack,

  //== pep <-> regfile
  // write
  output logic                                                         pep_regf_wr_req_vld,
  input  logic                                                         pep_regf_wr_req_rdy,
  output logic [REGF_WR_REQ_W-1:0]                                     pep_regf_wr_req,

  output logic [REGF_COEF_NB-1:0]                                      pep_regf_wr_data_vld,
  input  logic [REGF_COEF_NB-1:0]                                      pep_regf_wr_data_rdy,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                         pep_regf_wr_data,

  input  logic                                                         regf_pep_wr_ack,

  // read
  output logic                                                         pep_regf_rd_req_vld,
  input  logic                                                         pep_regf_rd_req_rdy,
  output logic [REGF_RD_REQ_W-1:0]                                     pep_regf_rd_req,

  input  logic [REGF_COEF_NB-1:0]                                      regf_pep_rd_data_avail,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                         regf_pep_rd_data,
  input  logic                                                         regf_pep_rd_last_word, // valid with avail[0]
  input  logic                                                         regf_pep_rd_is_body,
  input  logic                                                         regf_pep_rd_last_mask,

  //== Configuration
  input  logic                                                         reset_bsk_cache,
  output logic                                                         reset_bsk_cache_done, // pulse
  input  logic                                                         bsk_mem_avail,
  input  logic [BSK_PC_MAX-1:0][axi_if_bsk_axi_pkg::AXI4_ADD_W-1:0]    bsk_mem_addr,

  input  logic                                                         reset_ksk_cache,
  output logic                                                         reset_ksk_cache_done, // pulse
  input  logic                                                         ksk_mem_avail,
  input  logic [KSK_PC_MAX-1:0][axi_if_ksk_axi_pkg::AXI4_ADD_W-1:0]    ksk_mem_addr,

  input  logic                                                         reset_cache,

  input  logic [axi_if_glwe_axi_pkg::AXI4_ADD_W-1:0]                   gid_offset, // quasi static - GLWE address offset

  input  logic [1:0][R/2-1:0][MOD_NTT_W-1:0]                           twd_omg_ru_r_pow, // Not used when R=2

  input  logic                                                         use_bpip,     // quasi static
  input  logic                                                         use_bpip_opportunism,     // quasi static
  input  logic [TIMEOUT_CNT_W-1:0]                                     bpip_timeout, // quasi static

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

  //== AXI GLWE
  output logic [axi_if_glwe_axi_pkg::AXI4_ID_W-1:0]                    m_axi4_glwe_arid,
  output logic [axi_if_glwe_axi_pkg::AXI4_ADD_W-1:0]                   m_axi4_glwe_araddr,
  output logic [AXI4_LEN_W-1:0]                                        m_axi4_glwe_arlen,
  output logic [AXI4_SIZE_W-1:0]                                       m_axi4_glwe_arsize,
  output logic [AXI4_BURST_W-1:0]                                      m_axi4_glwe_arburst,
  output logic                                                         m_axi4_glwe_arvalid,
  input  logic                                                         m_axi4_glwe_arready,
  input  logic [axi_if_glwe_axi_pkg::AXI4_ID_W-1:0]                    m_axi4_glwe_rid,
  input  logic [axi_if_glwe_axi_pkg::AXI4_DATA_W-1:0]                  m_axi4_glwe_rdata,
  input  logic [AXI4_RESP_W-1:0]                                       m_axi4_glwe_rresp,
  input  logic                                                         m_axi4_glwe_rlast,
  input  logic                                                         m_axi4_glwe_rvalid,
  output logic                                                         m_axi4_glwe_rready,

  //== Error
  output logic [PEP_ERROR_W-1:0]                                       error,

  //== Info for regif
  output logic [PEP_INFO_W-1:0]                                        pep_rif_info,
  output logic [PEP_COUNTER_INC_W-1:0]                                 pep_rif_counter_inc

);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int ALMOST_DONE_BLINE_ID = 0; // TOREVIEW - adjust according to performance

// ============================================================================================== --
// Internal signals
// ============================================================================================== --
  //== BSK
  // BSK start
  logic                                                       bsk_if_batch_start_1h;

  // BSK pointer
  logic                                                       inc_bsk_wr_ptr;
  logic                                                       inc_bsk_rd_ptr;

  // Broadcast batch cmd
  logic [BR_BATCH_CMD_W-1:0]                                  br_batch_cmd;
  logic                                                       br_batch_cmd_avail;

  // BSK coefficients
  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][MOD_NTT_W-1:0]        bsk;
  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                       bsk_vld;
  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                       bsk_rdy;

  //== KSK
  // KSK start
  logic                                                       ksk_if_batch_start_1h;

    // KSK pointer
  logic                                                       inc_ksk_wr_ptr;
  logic                                                       inc_ksk_rd_ptr;

  // Broadcast batch cmd
  logic [KS_BATCH_CMD_W-1:0]                                  ks_batch_cmd;
  logic                                                       ks_batch_cmd_avail;

  // KSK coefficients
  logic [LBX-1:0][LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0]            ksk;
  logic [LBX-1:0][LBY-1:0]                                    ksk_vld;
  logic [LBX-1:0][LBY-1:0]                                    ksk_rdy;

  //== Sequencer
  // seq <-> ldb
  logic [LOAD_BLWE_CMD_W-1:0]                                 seq_ldb_cmd;
  logic                                                       seq_ldb_vld;
  logic                                                       seq_ldb_rdy;
  logic                                                       ldb_seq_done;

  // seq <-> KS
  logic                                                       ks_seq_cmd_enquiry;
  logic [KS_CMD_W-1:0]                                        seq_ks_cmd;
  logic                                                       seq_ks_cmd_avail;

  logic [KS_RESULT_W-1:0]                                     ks_seq_result;
  logic                                                       ks_seq_result_vld;
  logic                                                       ks_seq_result_rdy;

  //== Key switch
  // KS <-> Body RAM
  logic                                                       ks_boram_wr_en;
  logic [LWE_COEF_W-1:0]                                      ks_boram_data;
  logic [PID_W-1:0]                                           ks_boram_pid;
  logic                                                       ks_boram_parity;

  //== Decomposer
  // Decomposer -> NTT
  logic [PSI-1:0][R-1:0]                                      decomp_ntt_data_avail;
  logic [PSI-1:0][R-1:0][PBS_B_W:0]                           decomp_ntt_data;
  logic                                                       decomp_ntt_sob;
  logic                                                       decomp_ntt_eob;
  logic                                                       decomp_ntt_sog;
  logic                                                       decomp_ntt_eog;
  logic                                                       decomp_ntt_sol;
  logic                                                       decomp_ntt_eol;
  logic [BPBS_ID_W-1:0]                                       decomp_ntt_pbs_id;
  logic                                                       decomp_ntt_last_pbs;
  logic                                                       decomp_ntt_full_throughput;
  logic                                                       decomp_ntt_ctrl_avail;
  logic [PSI-1:0][R-1:0]                                      decomp_ntt_data_rdy;
  logic                                                       decomp_ntt_ctrl_rdy;

  //== NTT core
  // NTT core -> modSW
  logic [PSI-1:0][R-1:0]                                      ntt_acc_data_avail;
  logic                                                       ntt_acc_ctrl_avail;
  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]                         ntt_acc_data;
  logic                                                       ntt_acc_sob;
  logic                                                       ntt_acc_eob;
  logic                                                       ntt_acc_sol;
  logic                                                       ntt_acc_eol;
  logic                                                       ntt_acc_sog;
  logic                                                       ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                                       ntt_acc_pbs_id;

  //== ModSW
  // ModSW -> MMACC
  logic [PSI-1:0][R-1:0]                                      ntt_acc_modsw_data_avail;
  logic                                                       ntt_acc_modsw_ctrl_avail;
  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]                         ntt_acc_modsw_data;
  logic                                                       ntt_acc_modsw_sob;
  logic                                                       ntt_acc_modsw_eob;
  logic                                                       ntt_acc_modsw_sol;
  logic                                                       ntt_acc_modsw_eol;
  logic                                                       ntt_acc_modsw_sog;
  logic                                                       ntt_acc_modsw_eog;
  logic [BPBS_ID_W-1:0]                                       ntt_acc_modsw_pbs_id;

  //== Errors
  logic [PEP_ERROR_W-1:0]                                     pep_bsk_error;
  logic [PEP_ERROR_W-1:0]                                     pep_ksk_error;
  logic [PEP_ERROR_W-1:0]                                     pep_ks_error;
  logic [PEP_ERROR_W-1:0]                                     pep_entry_error;
  logic [PEP_ERROR_W-1:0]                                     pep_head_error;
  logic [PEP_ERROR_W-1:0]                                     pep_modsw_error;

  //== Info for regif
  pep_info_t                                                  pep_bsk_rif_info;
  pep_info_t                                                  pep_ksk_rif_info;
  pep_info_t                                                  pep_ks_rif_info;
  pep_info_t                                                  pep_entry_rif_info;
  pep_info_t                                                  pep_head_rif_info;
  pep_info_t                                                  pep_modsw_rif_info;

  pep_counter_inc_t                                           pep_bsk_rif_counter_inc;
  pep_counter_inc_t                                           pep_ksk_rif_counter_inc;
  pep_counter_inc_t                                           pep_ks_rif_counter_inc;
  pep_counter_inc_t                                           pep_entry_rif_counter_inc;
  pep_counter_inc_t                                           pep_head_rif_counter_inc;
  pep_counter_inc_t                                           pep_modsw_rif_counter_inc;

// ============================================================================================== --
// ERROR
// ============================================================================================== --
  logic [PEP_ERROR_W-1:0] errorD;
  pep_info_t          pep_rif_infoD;
  pep_counter_inc_t   pep_rif_counter_incD;
  assign errorD = pep_bsk_error
                  | pep_ksk_error
                  | pep_ks_error
                  | pep_entry_error
                  | pep_head_error
                  | pep_modsw_error;

  assign pep_rif_infoD = pep_bsk_rif_info
                         | pep_ksk_rif_info
                         | pep_ks_rif_info
                         | pep_entry_rif_info
                         | pep_head_rif_info
                         | pep_modsw_rif_info;

  assign pep_rif_counter_incD = pep_bsk_rif_counter_inc
                         | pep_ksk_rif_counter_inc
                         | pep_ks_rif_counter_inc
                         | pep_entry_rif_counter_inc
                         | pep_head_rif_counter_inc
                         | pep_modsw_rif_counter_inc;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error               <= '0;
      pep_rif_info        <= '0;
      pep_rif_counter_inc <= '0;
    end
    else begin
      error               <= errorD;
      pep_rif_info        <= pep_rif_infoD       ;
      pep_rif_counter_inc <= pep_rif_counter_incD;
    end

// ============================================================================================== --
// pe_pbs_with_bsk
// contains:
// * bsk_if
// * bsk_manager
// ============================================================================================== --
  pe_pbs_with_bsk
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
    .INST_FIFO_DEPTH       (INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  ) pe_pbs_with_bsk  (
    .clk                  (clk),
    .s_rst_n              (s_rst_n),

    .reset_bsk_cache      (reset_bsk_cache),
    .reset_bsk_cache_done (reset_bsk_cache_done),
    .bsk_mem_avail        (bsk_mem_avail),
    .bsk_mem_addr         (bsk_mem_addr),

    .m_axi4_bsk_arid      (m_axi4_bsk_arid),
    .m_axi4_bsk_araddr    (m_axi4_bsk_araddr),
    .m_axi4_bsk_arlen     (m_axi4_bsk_arlen),
    .m_axi4_bsk_arsize    (m_axi4_bsk_arsize),
    .m_axi4_bsk_arburst   (m_axi4_bsk_arburst),
    .m_axi4_bsk_arvalid   (m_axi4_bsk_arvalid),
    .m_axi4_bsk_arready   (m_axi4_bsk_arready),
    .m_axi4_bsk_rid       (m_axi4_bsk_rid),
    .m_axi4_bsk_rdata     (m_axi4_bsk_rdata),
    .m_axi4_bsk_rresp     (m_axi4_bsk_rresp),
    .m_axi4_bsk_rlast     (m_axi4_bsk_rlast),
    .m_axi4_bsk_rvalid    (m_axi4_bsk_rvalid),
    .m_axi4_bsk_rready    (m_axi4_bsk_rready),

    .br_batch_cmd         (br_batch_cmd      ),
    .br_batch_cmd_avail   (br_batch_cmd_avail),
    .bsk_if_batch_start_1h(bsk_if_batch_start_1h),

    .inc_bsk_wr_ptr       (inc_bsk_wr_ptr),
    .inc_bsk_rd_ptr       (inc_bsk_rd_ptr),

    .bsk                  (bsk),
    .bsk_vld              (bsk_vld),
    .bsk_rdy              (bsk_rdy),

    .error                (pep_bsk_error),

    .pep_rif_info         (pep_bsk_rif_info       ),
    .pep_rif_counter_inc  (pep_bsk_rif_counter_inc)
  );

// ============================================================================================== --
// pe_pbs_with_ksk
// contains:
// * ksk_if
// * ksk_manager
// ============================================================================================== --
  pe_pbs_with_ksk
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
    .INST_FIFO_DEPTH       (INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  )
  pe_pbs_with_ksk
  (
    .clk                  (clk),
    .s_rst_n              (s_rst_n),

    .reset_ksk_cache      (reset_ksk_cache),
    .reset_ksk_cache_done (reset_ksk_cache_done),
    .ksk_mem_avail        (ksk_mem_avail),
    .ksk_mem_addr         (ksk_mem_addr),

    .m_axi4_ksk_arid      (m_axi4_ksk_arid),
    .m_axi4_ksk_araddr    (m_axi4_ksk_araddr),
    .m_axi4_ksk_arlen     (m_axi4_ksk_arlen),
    .m_axi4_ksk_arsize    (m_axi4_ksk_arsize),
    .m_axi4_ksk_arburst   (m_axi4_ksk_arburst),
    .m_axi4_ksk_arvalid   (m_axi4_ksk_arvalid),
    .m_axi4_ksk_arready   (m_axi4_ksk_arready),
    .m_axi4_ksk_rid       (m_axi4_ksk_rid),
    .m_axi4_ksk_rdata     (m_axi4_ksk_rdata),
    .m_axi4_ksk_rresp     (m_axi4_ksk_rresp),
    .m_axi4_ksk_rlast     (m_axi4_ksk_rlast),
    .m_axi4_ksk_rvalid    (m_axi4_ksk_rvalid),
    .m_axi4_ksk_rready    (m_axi4_ksk_rready),

    .inc_ksk_wr_ptr       (inc_ksk_wr_ptr),
    .inc_ksk_rd_ptr       (inc_ksk_rd_ptr),

    .ks_batch_cmd         (ks_batch_cmd),
    .ks_batch_cmd_avail   (ks_batch_cmd_avail),
    .ksk_if_batch_start_1h(ksk_if_batch_start_1h),

    .ksk                  (ksk),
    .ksk_vld              (ksk_vld),
    .ksk_rdy              (ksk_rdy),

    .error                (pep_ksk_error),
    .pep_rif_info         (pep_ksk_rif_info       ),
    .pep_rif_counter_inc(pep_ksk_rif_counter_inc)
  );

// ============================================================================================== --
// pe_pbs_with_ks
// contains:
// * pep_key_switch
// * pep_load_blwe
// ============================================================================================== --
  pe_pbs_with_ks
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
    .INST_FIFO_DEPTH       (INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  ) pe_pbs_with_ks (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .pep_regf_rd_req_vld    (pep_regf_rd_req_vld),
    .pep_regf_rd_req_rdy    (pep_regf_rd_req_rdy),
    .pep_regf_rd_req        (pep_regf_rd_req),

    .regf_pep_rd_data_avail (regf_pep_rd_data_avail),
    .regf_pep_rd_data       (regf_pep_rd_data),
    .regf_pep_rd_last_word  (regf_pep_rd_last_word),
    .regf_pep_rd_is_body    (regf_pep_rd_is_body),
    .regf_pep_rd_last_mask  (regf_pep_rd_last_mask),

    .ksk                    (ksk),
    .ksk_vld                (ksk_vld),
    .ksk_rdy                (ksk_rdy),

    .seq_ldb_cmd            (seq_ldb_cmd),
    .seq_ldb_vld            (seq_ldb_vld),
    .seq_ldb_rdy            (seq_ldb_rdy),
    .ldb_seq_done           (ldb_seq_done),

    .ks_seq_cmd_enquiry     (ks_seq_cmd_enquiry),
    .seq_ks_cmd             (seq_ks_cmd),
    .seq_ks_cmd_avail       (seq_ks_cmd_avail),

    .ks_seq_result          (ks_seq_result),
    .ks_seq_result_vld      (ks_seq_result_vld),
    .ks_seq_result_rdy      (ks_seq_result_rdy),

    .ks_boram_wr_en         (ks_boram_wr_en),
    .ks_boram_data          (ks_boram_data),
    .ks_boram_pid           (ks_boram_pid),
    .ks_boram_parity        (ks_boram_parity),

    .inc_ksk_wr_ptr         (inc_ksk_wr_ptr),
    .inc_ksk_rd_ptr         (inc_ksk_rd_ptr),

    .ks_batch_cmd           (ks_batch_cmd),
    .ks_batch_cmd_avail     (ks_batch_cmd_avail),

    .reset_cache            (reset_cache),

    .error                  (pep_ks_error),
    .pep_rif_info           (pep_ks_rif_info       ),
    .pep_rif_counter_inc    (pep_ks_rif_counter_inc)
  );

// ============================================================================================== --
// pe_pbs_with_entry
// contains:
// * pep_mono_mult_acc
// * pep_sequencer
// * pep_load_glwe
// * decomposer
// ============================================================================================== --
  pe_pbs_with_entry_assembly
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
    .SLR_LATENCY           (0),
    .TWD_IFNL_FILE_PREFIX  (TWD_IFNL_FILE_PREFIX),
    .TWD_PHRU_FILE_PREFIX  (TWD_PHRU_FILE_PREFIX),
    .INST_FIFO_DEPTH       (INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  ) pe_pbs_with_entry_assembly (
    .clk                        (clk),
    .s_rst_n                    (s_rst_n),

    .use_bpip                   (use_bpip),
    .use_bpip_opportunism       (use_bpip_opportunism),
    .bpip_timeout               (bpip_timeout),

    .inst                       (inst),
    .inst_vld                   (inst_vld),
    .inst_rdy                   (inst_rdy),

    .inst_ack                   (inst_ack),
    .inst_ack_br_loop           (inst_ack_br_loop),
    .inst_load_blwe_ack         (inst_load_blwe_ack),

    .pep_regf_wr_req_vld        (pep_regf_wr_req_vld),
    .pep_regf_wr_req_rdy        (pep_regf_wr_req_rdy),
    .pep_regf_wr_req            (pep_regf_wr_req),

    .pep_regf_wr_data_vld       (pep_regf_wr_data_vld),
    .pep_regf_wr_data_rdy       (pep_regf_wr_data_rdy),
    .pep_regf_wr_data           (pep_regf_wr_data),

    .regf_pep_wr_ack            (regf_pep_wr_ack),

    .gid_offset                 (gid_offset),

    .m_axi4_glwe_arid           (m_axi4_glwe_arid),
    .m_axi4_glwe_araddr         (m_axi4_glwe_araddr),
    .m_axi4_glwe_arlen          (m_axi4_glwe_arlen),
    .m_axi4_glwe_arsize         (m_axi4_glwe_arsize),
    .m_axi4_glwe_arburst        (m_axi4_glwe_arburst),
    .m_axi4_glwe_arvalid        (m_axi4_glwe_arvalid),
    .m_axi4_glwe_arready        (m_axi4_glwe_arready),
    .m_axi4_glwe_rid            (m_axi4_glwe_rid),
    .m_axi4_glwe_rdata          (m_axi4_glwe_rdata),
    .m_axi4_glwe_rresp          (m_axi4_glwe_rresp),
    .m_axi4_glwe_rlast          (m_axi4_glwe_rlast),
    .m_axi4_glwe_rvalid         (m_axi4_glwe_rvalid),
    .m_axi4_glwe_rready         (m_axi4_glwe_rready),

    .seq_ldb_cmd                (seq_ldb_cmd),
    .seq_ldb_vld                (seq_ldb_vld),
    .seq_ldb_rdy                (seq_ldb_rdy),
    .ldb_seq_done               (ldb_seq_done),

    .ks_seq_cmd_enquiry         (ks_seq_cmd_enquiry),
    .seq_ks_cmd                 (seq_ks_cmd),
    .seq_ks_cmd_avail           (seq_ks_cmd_avail),

    .ks_seq_result              (ks_seq_result),
    .ks_seq_result_vld          (ks_seq_result_vld),
    .ks_seq_result_rdy          (ks_seq_result_rdy),

    .ks_boram_wr_en             (ks_boram_wr_en),
    .ks_boram_data              (ks_boram_data),
    .ks_boram_pid               (ks_boram_pid),
    .ks_boram_parity            (ks_boram_parity),

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
    .decomp_ntt_data_rdy        (decomp_ntt_data_rdy),
    .decomp_ntt_ctrl_rdy        (decomp_ntt_ctrl_rdy),

    .ntt_acc_modsw_data_avail   (ntt_acc_modsw_data_avail),
    .ntt_acc_modsw_ctrl_avail   (ntt_acc_modsw_ctrl_avail),
    .ntt_acc_modsw_data         (ntt_acc_modsw_data),
    .ntt_acc_modsw_sob          (ntt_acc_modsw_sob),
    .ntt_acc_modsw_eob          (ntt_acc_modsw_eob),
    .ntt_acc_modsw_sol          (ntt_acc_modsw_sol),
    .ntt_acc_modsw_eol          (ntt_acc_modsw_eol),
    .ntt_acc_modsw_sog          (ntt_acc_modsw_sog),
    .ntt_acc_modsw_eog          (ntt_acc_modsw_eog),
    .ntt_acc_modsw_pbs_id       (ntt_acc_modsw_pbs_id),

    .bsk_if_batch_start_1h      (bsk_if_batch_start_1h),
    .ksk_if_batch_start_1h      (ksk_if_batch_start_1h),
    .br_batch_cmd               (br_batch_cmd),
    .br_batch_cmd_avail         (br_batch_cmd_avail),
    .inc_bsk_wr_ptr             (inc_bsk_wr_ptr),
    .inc_bsk_rd_ptr             (inc_bsk_rd_ptr),

    .reset_cache                (reset_cache),

    .error                      (pep_entry_error),
    .pep_rif_info               (pep_entry_rif_info),
    .pep_rif_counter_inc        (pep_entry_rif_counter_inc)
  );


// ============================================================================================== --
// pe_pbs_with_ntt_core_head
// contains:
// * ntt_core_head
// ============================================================================================== --
  logic [PSI-1:0][R-1:0][MOD_Q_W+1:0] ntt_acc_data_tmp;

  always_comb
    for (int p=0; p<PSI; p=p+1)
      for (int r=0; r<R; r=r+1)
        ntt_acc_data[p][r] = ntt_acc_data_tmp[p][r][MOD_NTT_W-1:0]; // Truncate

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
    .INST_FIFO_DEPTH       (INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH),
    .S_NB                  (2*S),
    .USE_PP                (1)
  ) pe_pbs_with_ntt_core_head (
    .clk                        (clk),
    .s_rst_n                    (s_rst_n),

    .twd_omg_ru_r_pow           (twd_omg_ru_r_pow),

    .br_batch_cmd               (br_batch_cmd),
    .br_batch_cmd_avail         (br_batch_cmd_avail),

    .bsk                        (bsk),
    .bsk_vld                    (bsk_vld),
    .bsk_rdy                    (bsk_rdy),

    .decomp_ntt_data_avail      (decomp_ntt_data_avail),
    .decomp_ntt_data            (decomp_ntt_data),
    .decomp_ntt_sob             (decomp_ntt_sob),
    .decomp_ntt_eob             (decomp_ntt_eob),
    .decomp_ntt_sol             (decomp_ntt_sol),
    .decomp_ntt_eol             (decomp_ntt_eol),
    .decomp_ntt_sog             (decomp_ntt_sog),
    .decomp_ntt_eog             (decomp_ntt_eog),
    .decomp_ntt_pbs_id          (decomp_ntt_pbs_id),
    .decomp_ntt_last_pbs        (decomp_ntt_last_pbs),
    .decomp_ntt_full_throughput (decomp_ntt_full_throughput),
    .decomp_ntt_ctrl_avail      (decomp_ntt_ctrl_avail),
    .decomp_ntt_data_rdy        (decomp_ntt_data_rdy),
    .decomp_ntt_ctrl_rdy        (decomp_ntt_ctrl_rdy),

    .next_data                  (ntt_acc_data_tmp),
    .next_data_avail            (ntt_acc_data_avail),
    .next_sob                   (ntt_acc_sob),
    .next_eob                   (ntt_acc_eob),
    .next_sol                   (ntt_acc_sol),
    .next_eol                   (ntt_acc_eol),
    .next_sos                   (ntt_acc_sog),
    .next_eos                   (ntt_acc_eog),
    .next_pbs_id                (ntt_acc_pbs_id),
    .next_ctrl_avail            (ntt_acc_ctrl_avail),

    .error                      (pep_head_error),
    .pep_rif_info               (pep_head_rif_info),
    .pep_rif_counter_inc        (pep_head_rif_counter_inc)
  );

// ============================================================================================== --
// pe_pbs_with_modsw
// contains:
// * mod_switch_to_2powerN
// ============================================================================================== --
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
    .INST_FIFO_DEPTH       (INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  ) pe_pbs_with_modsw (
    .clk                           (clk),
    .s_rst_n                       (s_rst_n),

    .ntt_acc_data                  (ntt_acc_data),
    .ntt_acc_data_avail            (ntt_acc_data_avail),
    .ntt_acc_sob                   (ntt_acc_sob),
    .ntt_acc_eob                   (ntt_acc_eob),
    .ntt_acc_sol                   (ntt_acc_sol),
    .ntt_acc_eol                   (ntt_acc_eol),
    .ntt_acc_sog                   (ntt_acc_sog),
    .ntt_acc_eog                   (ntt_acc_eog),
    .ntt_acc_pbs_id                (ntt_acc_pbs_id),
    .ntt_acc_ctrl_avail            (ntt_acc_ctrl_avail),

    .ntt_acc_modsw_data            (ntt_acc_modsw_data),
    .ntt_acc_modsw_data_avail      (ntt_acc_modsw_data_avail),
    .ntt_acc_modsw_sob             (ntt_acc_modsw_sob),
    .ntt_acc_modsw_eob             (ntt_acc_modsw_eob),
    .ntt_acc_modsw_sol             (ntt_acc_modsw_sol),
    .ntt_acc_modsw_eol             (ntt_acc_modsw_eol),
    .ntt_acc_modsw_sog             (ntt_acc_modsw_sog),
    .ntt_acc_modsw_eog             (ntt_acc_modsw_eog),
    .ntt_acc_modsw_pbs_id          (ntt_acc_modsw_pbs_id),
    .ntt_acc_modsw_ctrl_avail      (ntt_acc_modsw_ctrl_avail),

    .error                         (pep_modsw_error),
    .pep_rif_info                  (pep_modsw_rif_info),
    .pep_rif_counter_inc           (pep_modsw_rif_counter_inc)
  );

endmodule
