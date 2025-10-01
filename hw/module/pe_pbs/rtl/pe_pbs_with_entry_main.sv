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
//  * pep_mono_mult_acc main
//  * pep_load_glwe main
//  * pep_sequencer
//  * decomp
// ==============================================================================================

module pe_pbs_with_entry_main
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
  import pep_mmacc_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import pep_if_pkg::*;
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
  parameter int                PHYS_RAM_DEPTH       = 1024, // Physical RAM depth. Should be a power of 2. In Xilinx is BRAM depth for 32b words
  localparam int               MAIN_PSI             = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV
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

  //== Configuration
  input  logic [GLWE_PC_MAX-1:0][axi_if_glwe_axi_pkg::AXI4_ADD_W-1:0]  glwe_mem_addr,   // quasi static - GLWE address offset
  input  logic                                                         use_bpip,     // quasi static
  input  logic                                                         use_bpip_opportunism,     // quasi static
  input  logic [TIMEOUT_CNT_W-1:0]                                     bpip_timeout, // quasi static

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

  //== seq <-> ldb
  output logic [LOAD_BLWE_CMD_W-1:0]                                   seq_ldb_cmd,
  output logic                                                         seq_ldb_vld,
  input  logic                                                         seq_ldb_rdy,
  input  logic                                                         ldb_seq_done,

  //== seq <-> KS
  input  logic                                                         ks_seq_cmd_enquiry,
  output logic [KS_CMD_W-1:0]                                          seq_ks_cmd,
  output logic                                                         seq_ks_cmd_avail,

  input  logic [KS_RESULT_W-1:0]                                       ks_seq_result,
  input  logic                                                         ks_seq_result_vld,
  output logic                                                         ks_seq_result_rdy,

  //== Key switch
  // KS <-> Body RAM
  input  logic                                                         ks_boram_wr_en,
  input  logic [MOD_KSK_W-1:0]                                         ks_boram_data,
  input  logic [PID_W-1:0]                                             ks_boram_pid,
  input  logic                                                         ks_boram_parity,

  // ModSW -> MMACC : from subs
  input  logic                                                         subs_main_ntt_acc_modsw_avail,
  input  logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]                      subs_main_ntt_acc_modsw_data,
  input  logic                                                         subs_main_ntt_acc_modsw_sob,
  input  logic                                                         subs_main_ntt_acc_modsw_eob,
  input  logic                                                         subs_main_ntt_acc_modsw_sol,
  input  logic                                                         subs_main_ntt_acc_modsw_eol,
  input  logic                                                         subs_main_ntt_acc_modsw_sog,
  input  logic                                                         subs_main_ntt_acc_modsw_eog,
  input  logic [BPBS_ID_W-1:0]                                         subs_main_ntt_acc_modsw_pbs_id,

  //== Control
  output logic                                                         bsk_if_batch_start_1h,
  output logic                                                         ksk_if_batch_start_1h,
  input  logic                                                         inc_bsk_wr_ptr,
  output logic                                                         inc_bsk_rd_ptr,

  output logic [BR_BATCH_CMD_W-1:0]                                    br_batch_cmd,
  output logic                                                         br_batch_cmd_avail,

  // reset cache
  input  logic                                                         reset_cache,
  output logic                                                         reset_ks,

  //== main <-> subs
  // main <-> subs : feed
  output mainsubs_feed_cmd_t                                           main_subs_feed_cmd,
  output logic                                                         main_subs_feed_cmd_vld,
  input  logic                                                         main_subs_feed_cmd_rdy,

  output mainsubs_feed_data_t                                          main_subs_feed_data,
  output logic                                                         main_subs_feed_data_avail,

  output mainsubs_feed_part_t                                          main_subs_feed_part,
  output logic                                                         main_subs_feed_part_avail,

  // main <-> subsidiary : SXT
  output mainsubs_sxt_cmd_t                                            main_subs_sxt_cmd,
  output logic                                                         main_subs_sxt_cmd_vld,
  input  logic                                                         main_subs_sxt_cmd_rdy,

  input  subsmain_sxt_data_t                                           subs_main_sxt_data,
  input  logic                                                         subs_main_sxt_data_vld,
  output logic                                                         subs_main_sxt_data_rdy,

  input  subsmain_sxt_part_t                                           subs_main_sxt_part,
  input  logic                                                         subs_main_sxt_part_vld,
  output logic                                                         subs_main_sxt_part_rdy,

  // main <-> subsidiary : LDG
  output mainsubs_ldg_cmd_t                                            main_subs_ldg_cmd,
  output logic                                                         main_subs_ldg_cmd_vld,
  input  logic                                                         main_subs_ldg_cmd_rdy,

  output mainsubs_ldg_data_t                                           main_subs_ldg_data,
  output logic                                                         main_subs_ldg_data_vld,
  input  logic                                                         main_subs_ldg_data_rdy,

  // main <-> subs : proc signals
  input  subsmain_proc_t                                               subs_main_proc,
  output mainsubs_proc_t                                               main_subs_proc,

  // To rif
  output pep_counter_inc_t                                             pep_rif_counter_inc,
  output pep_info_t                                                    pep_rif_info,
  output pep_error_t                                                   pep_error
);

// ============================================================================================== --
// localparam
// ============================================================================================== --

// ============================================================================================== --
// Internal signals
// ============================================================================================== --
  //== Sequencer
  // seq <-> ldg
  logic [LOAD_GLWE_CMD_W-1:0]                                 seq_ldg_cmd;
  logic                                                       seq_ldg_vld;
  logic                                                       seq_ldg_rdy;
  logic                                                       ldg_seq_done;

  // seq <-> MMACC
  logic                                                       pbs_seq_cmd_enquiry;
  logic [PBS_CMD_W-1:0]                                       seq_pbs_cmd;
  logic                                                       seq_pbs_cmd_avail;

  logic                                                       sxt_seq_done;
  logic [PID_W-1:0]                                           sxt_seq_done_pid;

  //== GLWE load
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                    ldg_gram_wr_en;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]ldg_gram_wr_add;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]       ldg_gram_wr_data;

  //== GRAM arbiter
  logic [GRAM_NB-1:0]                                         garb_ldg_avail_1h;

  // main <-> subs : control
  garb_avail_1h_t                                             main_subs_garb_avail_1h;
  logic                                                       main_subs_feed_mcmd_ack_ack;

  // SEQ <-> Body correction RAM
  logic                                                       seq_boram_corr_wr_en;
  logic [KS_CORR_W-1:0]                                       seq_boram_corr_data;
  logic [PID_W-1:0]                                           seq_boram_corr_pid;

// ============================================================================================== --
// Output
// ============================================================================================== --
  always_comb begin
    main_subs_proc                   = '0;
    main_subs_proc.garb_avail_1h     = main_subs_garb_avail_1h;
    main_subs_proc.feed_mcmd_ack_ack = main_subs_feed_mcmd_ack_ack;
  end

// ============================================================================================== --
// Error / Inc
// ============================================================================================== --
  pep_error_t              pep_errorD;
  pep_counter_inc_t        pep_rif_counter_incD;
  pep_info_t               pep_rif_infoD;

  pep_seq_error_t          seq_error;
  pep_mmacc_error_t        mmacc_error;
  pep_ldg_error_t          ldg_error;

  pep_seq_counter_inc_t    seq_rif_counter_inc;
  pep_ldg_counter_inc_t    ldg_rif_counter_inc;
  pep_mmacc_counter_inc_t  mmacc_rif_counter_inc;
  pep_common_counter_inc_t common_rif_counter_inc;

  pep_seq_info_t           seq_rif_info_s;

  always_comb begin
    pep_errorD                 = '0;
    pep_rif_counter_incD       = '0;
    pep_rif_infoD              = '0;

    pep_errorD.ldg             = ldg_error;
    pep_errorD.mmacc           = mmacc_error;
    pep_errorD.seq             = seq_error;
    pep_rif_counter_incD.ld.ldg= ldg_rif_counter_inc;
    pep_rif_counter_incD.seq   = seq_rif_counter_inc;
    pep_rif_counter_incD.mmacc = mmacc_rif_counter_inc;
    pep_rif_counter_incD.common= common_rif_counter_inc;
    pep_rif_infoD.seq          = seq_rif_info_s;
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
// Common counter
// ============================================================================================== --
  pep_common_counter_inc_t common_rif_counter_incD;

  always_comb begin
    common_rif_counter_incD          = '0;
    common_rif_counter_incD.inst_inc = inst_vld & inst_rdy;
    common_rif_counter_incD.ack_inc  = inst_ack;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) common_rif_counter_inc <= '0;
    else          common_rif_counter_inc <= common_rif_counter_incD;

// ============================================================================================== --
// Sequencer
// ============================================================================================== --
  pep_sequencer
  #(
    .INST_FIFO_DEPTH   (INST_FIFO_DEPTH)
  ) pep_sequencer (
    .clk                   (clk),
    .s_rst_n               (s_rst_n),

    .use_bpip              (use_bpip),
    .use_bpip_opportunism  (use_bpip_opportunism),
    .bpip_timeout          (bpip_timeout),

    .inst                  (inst),
    .inst_vld              (inst_vld),
    .inst_rdy              (inst_rdy),

    .inst_ack              (inst_ack),
    .inst_ack_br_loop      (inst_ack_br_loop),
    .inst_load_blwe_ack    (inst_load_blwe_ack),

    .seq_ldg_cmd           (seq_ldg_cmd),
    .seq_ldg_vld           (seq_ldg_vld),
    .seq_ldg_rdy           (seq_ldg_rdy),

    .seq_ldb_cmd           (seq_ldb_cmd),
    .seq_ldb_vld           (seq_ldb_vld),
    .seq_ldb_rdy           (seq_ldb_rdy),

    .ldg_seq_done          (ldg_seq_done),
    .ldb_seq_done          (ldb_seq_done),

    .ks_seq_cmd_enquiry    (ks_seq_cmd_enquiry),
    .seq_ks_cmd            (seq_ks_cmd),
    .seq_ks_cmd_avail      (seq_ks_cmd_avail),

    .ks_seq_result         (ks_seq_result),
    .ks_seq_result_vld     (ks_seq_result_vld),
    .ks_seq_result_rdy     (ks_seq_result_rdy),

    .pbs_seq_cmd_enquiry   (pbs_seq_cmd_enquiry),
    .seq_pbs_cmd           (seq_pbs_cmd),
    .seq_pbs_cmd_avail     (seq_pbs_cmd_avail),

    .sxt_seq_done          (sxt_seq_done),
    .sxt_seq_done_pid      (sxt_seq_done_pid),

    .bsk_if_batch_start_1h (bsk_if_batch_start_1h),
    .ksk_if_batch_start_1h (ksk_if_batch_start_1h),

    .seq_boram_corr_wr_en  (seq_boram_corr_wr_en),
    .seq_boram_corr_data   (seq_boram_corr_data),
    .seq_boram_corr_pid    (seq_boram_corr_pid),

    .reset_cache           (reset_cache),
    .reset_ks              (reset_ks),

    .seq_error             (seq_error),
    .seq_rif_info          (seq_rif_info_s),
    .seq_rif_counter_inc   (seq_rif_counter_inc)
  );

// ============================================================================================== --
// Load GLWE from MEM
// ============================================================================================== --
  pep_load_glwe_splitc_main
  pep_load_glwe_splitc_main (
    .clk                (clk),
    .s_rst_n            (s_rst_n),

    .gid_offset         (glwe_mem_addr[GLWE_PC-1:0]),

    .garb_ldg_avail_1h  (garb_ldg_avail_1h),

    .seq_ldg_cmd        (seq_ldg_cmd),
    .seq_ldg_vld        (seq_ldg_vld),
    .seq_ldg_rdy        (seq_ldg_rdy),
    .ldg_seq_done       (ldg_seq_done),

    .m_axi4_arid        (m_axi4_glwe_arid),
    .m_axi4_araddr      (m_axi4_glwe_araddr),
    .m_axi4_arlen       (m_axi4_glwe_arlen),
    .m_axi4_arsize      (m_axi4_glwe_arsize),
    .m_axi4_arburst     (m_axi4_glwe_arburst),
    .m_axi4_arvalid     (m_axi4_glwe_arvalid),
    .m_axi4_arready     (m_axi4_glwe_arready),
    .m_axi4_rid         (m_axi4_glwe_rid),
    .m_axi4_rdata       (m_axi4_glwe_rdata),
    .m_axi4_rresp       (m_axi4_glwe_rresp),
    .m_axi4_rlast       (m_axi4_glwe_rlast),
    .m_axi4_rvalid      (m_axi4_glwe_rvalid),
    .m_axi4_rready      (m_axi4_glwe_rready),

    .subs_cmd           (main_subs_ldg_cmd.cmd),
    .subs_cmd_vld       (main_subs_ldg_cmd_vld),
    .subs_cmd_rdy       (main_subs_ldg_cmd_rdy),
    .subs_cmd_done      (subs_main_proc.ldg_cmd_done),

    .subs_data          (main_subs_ldg_data.data),
    .subs_data_vld      (main_subs_ldg_data_vld),
    .subs_data_rdy      (main_subs_ldg_data_rdy),

    .glwe_ram_wr_en     (ldg_gram_wr_en),
    .glwe_ram_wr_add    (ldg_gram_wr_add),
    .glwe_ram_wr_data   (ldg_gram_wr_data),

    .pep_ldg_counter_inc(ldg_rif_counter_inc),
    .ldg_error          (ldg_error)
  );

// ============================================================================================== --
// PBS
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// mono_mult_acc
// ---------------------------------------------------------------------------------------------- --
  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0] main_subs_feed_data_l;
  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0] main_subs_feed_rot_data_l;

  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0] main_subs_feed_part_l;
  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0] main_subs_feed_rot_part_l;

  always_comb
    for (int p=0; p<PSI/2; p=p+1) begin
      for (int r=0; r<R; r=r+1) begin
        main_subs_feed_data.elt[p][r].data     = main_subs_feed_data_l[p][r];
        main_subs_feed_data.elt[p][r].rot_data = main_subs_feed_rot_data_l[p][r];
      end
    end

  always_comb
    for (int p=0; p<PSI/MSPLIT_DIV; p=p+1) begin
      for (int r=0; r<R; r=r+1) begin
        main_subs_feed_part.elt[p][r].data     = main_subs_feed_part_l[p][r];
        main_subs_feed_part.elt[p][r].rot_data = main_subs_feed_rot_part_l[p][r];
      end
    end

  pep_mmacc_splitc_main
  #(
    .RAM_LATENCY              (RAM_LATENCY),
    .URAM_LATENCY             (URAM_LATENCY),
    .PHYS_RAM_DEPTH           (PHYS_RAM_DEPTH)
  ) pep_mmacc_splitc_main (
    .clk                          (clk),
    .s_rst_n                      (s_rst_n),

    .reset_cache                  (reset_cache),

    .ldg_gram_wr_en               (ldg_gram_wr_en),
    .ldg_gram_wr_add              (ldg_gram_wr_add),
    .ldg_gram_wr_data             (ldg_gram_wr_data),

    .sxt_regf_wr_req_vld          (pep_regf_wr_req_vld),
    .sxt_regf_wr_req_rdy          (pep_regf_wr_req_rdy),
    .sxt_regf_wr_req              (pep_regf_wr_req),

    .sxt_regf_wr_data_vld         (pep_regf_wr_data_vld),
    .sxt_regf_wr_data_rdy         (pep_regf_wr_data_rdy),
    .sxt_regf_wr_data             (pep_regf_wr_data),

    .regf_sxt_wr_ack              (regf_pep_wr_ack),

    .pbs_seq_cmd_enquiry          (pbs_seq_cmd_enquiry),
    .seq_pbs_cmd                  (seq_pbs_cmd),
    .seq_pbs_cmd_avail            (seq_pbs_cmd_avail),

    .sxt_seq_done                 (sxt_seq_done),
    .sxt_seq_done_pid             (sxt_seq_done_pid),

    .ks_boram_wr_en               (ks_boram_wr_en),
    .ks_boram_data                (ks_boram_data),
    .ks_boram_pid                 (ks_boram_pid),
    .ks_boram_parity              (ks_boram_parity),

    .seq_boram_corr_wr_en         (seq_boram_corr_wr_en),
    .seq_boram_corr_data          (seq_boram_corr_data),
    .seq_boram_corr_pid           (seq_boram_corr_pid),

    .inc_bsk_wr_ptr               (inc_bsk_wr_ptr),
    .inc_bsk_rd_ptr               (inc_bsk_rd_ptr),

    .main_subs_garb_feed_rot_avail_1h (main_subs_garb_avail_1h.feed_rot),
    .main_subs_garb_feed_dat_avail_1h (main_subs_garb_avail_1h.feed_dat),
    .main_subs_garb_acc_rd_avail_1h   (main_subs_garb_avail_1h.acc_rd),
    .main_subs_garb_acc_wr_avail_1h   (main_subs_garb_avail_1h.acc_wr),
    .main_subs_garb_sxt_avail_1h      (main_subs_garb_avail_1h.sxt),
    .main_subs_garb_ldg_avail_1h      (main_subs_garb_avail_1h.ldg),

    .garb_ldg_avail_1h            (garb_ldg_avail_1h),

    .main_subs_feed_mcmd          (main_subs_feed_cmd.mcmd),
    .main_subs_feed_mcmd_vld      (main_subs_feed_cmd_vld),
    .main_subs_feed_mcmd_rdy      (main_subs_feed_cmd_rdy),
    .subs_main_feed_mcmd_ack      (subs_main_proc.feed_mcmd_ack),
    .main_subs_feed_mcmd_ack_ack  (main_subs_feed_mcmd_ack_ack),

    .main_subs_feed_data          (main_subs_feed_data_l),
    .main_subs_feed_rot_data      (main_subs_feed_rot_data_l),
    .main_subs_feed_data_avail    (main_subs_feed_data_avail),

    .main_subs_feed_part          (main_subs_feed_part_l),
    .main_subs_feed_rot_part      (main_subs_feed_rot_part_l),
    .main_subs_feed_part_avail    (main_subs_feed_part_avail),

    .subs_main_ntt_acc_avail      (subs_main_ntt_acc_modsw_avail),
    .subs_main_ntt_acc_data       (subs_main_ntt_acc_modsw_data),
    .subs_main_ntt_acc_sob        (subs_main_ntt_acc_modsw_sob),
    .subs_main_ntt_acc_eob        (subs_main_ntt_acc_modsw_eob),
    .subs_main_ntt_acc_sol        (subs_main_ntt_acc_modsw_sol),
    .subs_main_ntt_acc_eol        (subs_main_ntt_acc_modsw_eol),
    .subs_main_ntt_acc_sog        (subs_main_ntt_acc_modsw_sog),
    .subs_main_ntt_acc_eog        (subs_main_ntt_acc_modsw_eog),
    .subs_main_ntt_acc_pbs_id     (subs_main_ntt_acc_modsw_pbs_id),

    .main_subs_sxt_cmd_vld        (main_subs_sxt_cmd_vld),
    .main_subs_sxt_cmd_rdy        (main_subs_sxt_cmd_rdy),
    .main_subs_sxt_cmd_body       (main_subs_sxt_cmd.body),
    .main_subs_sxt_cmd_icmd       (main_subs_sxt_cmd.icmd),
    .subs_main_sxt_cmd_ack        (subs_main_proc.sxt_cmd_ack),

    .subs_main_sxt_data_data      (subs_main_sxt_data.data),
    .subs_main_sxt_data_vld       (subs_main_sxt_data_vld),
    .subs_main_sxt_data_rdy       (subs_main_sxt_data_rdy),

    .subs_main_sxt_part_data      (subs_main_sxt_part.data),
    .subs_main_sxt_part_vld       (subs_main_sxt_part_vld ),
    .subs_main_sxt_part_rdy       (subs_main_sxt_part_rdy ),

    .mmacc_error                  (mmacc_error),
    .mmacc_rif_counter_inc        (mmacc_rif_counter_inc),

    .batch_cmd                    (br_batch_cmd),
    .batch_cmd_avail              (br_batch_cmd_avail)

  );

endmodule

