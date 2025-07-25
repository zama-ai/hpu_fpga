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
//  * pep_mono_mult_acc subsidiary
//  * pep_load_glwe subsidiary
// ==============================================================================================

module pe_pbs_with_entry_subsidiary
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
  import pep_mmacc_common_param_pkg::*;
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
  localparam int               MAIN_PSI             = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV,
  localparam int               SUBS_PSI             = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV
)
(
  input  logic                                                         clk,       // clock
  input  logic                                                         s_rst_n,    // synchronous reset

  //== Decomposer
  // Decomposer -> NTT
  output logic [PSI-1:0][R-1:0]                                        decomp_ntt_data_avail,
  output logic [PSI-1:0][R-1:0][PBS_B_W:0]                             decomp_ntt_data, // 2s complement
  output logic                                                         decomp_ntt_sob,
  output logic                                                         decomp_ntt_eob,
  output logic                                                         decomp_ntt_sog,
  output logic                                                         decomp_ntt_eog,
  output logic                                                         decomp_ntt_sol,
  output logic                                                         decomp_ntt_eol,
  output logic [BPBS_ID_W-1:0]                                         decomp_ntt_pbs_id,
  output logic                                                         decomp_ntt_last_pbs,
  output logic                                                         decomp_ntt_full_throughput,
  output logic                                                         decomp_ntt_ctrl_avail,

  //== ModSW
  // ModSW -> MMACC
  input  logic [PSI-1:0][R-1:0]                                        ntt_acc_modsw_data_avail,
  input  logic                                                         ntt_acc_modsw_ctrl_avail,
  input  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]                           ntt_acc_modsw_data,
  input  logic                                                         ntt_acc_modsw_sob,
  input  logic                                                         ntt_acc_modsw_eob,
  input  logic                                                         ntt_acc_modsw_sol,
  input  logic                                                         ntt_acc_modsw_eol,
  input  logic                                                         ntt_acc_modsw_sog,
  input  logic                                                         ntt_acc_modsw_eog,
  input  logic [BPBS_ID_W-1:0]                                         ntt_acc_modsw_pbs_id,

  //== ModSW
  // subs -> main
  output logic                                                         subs_main_ntt_acc_modsw_avail,
  output logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]                      subs_main_ntt_acc_modsw_data,
  output logic                                                         subs_main_ntt_acc_modsw_sob,
  output logic                                                         subs_main_ntt_acc_modsw_eob,
  output logic                                                         subs_main_ntt_acc_modsw_sol,
  output logic                                                         subs_main_ntt_acc_modsw_eol,
  output logic                                                         subs_main_ntt_acc_modsw_sog,
  output logic                                                         subs_main_ntt_acc_modsw_eog,
  output logic [BPBS_ID_W-1:0]                                         subs_main_ntt_acc_modsw_pbs_id,

  //== subs <-> main
  // main <-> subs : feed
  input  mainsubs_feed_cmd_t                                           main_subs_feed_cmd,
  input  logic                                                         main_subs_feed_cmd_vld,
  output logic                                                         main_subs_feed_cmd_rdy,

  input  mainsubs_feed_data_t                                          main_subs_feed_data,
  input  logic                                                         main_subs_feed_data_avail,

  input  mainsubs_feed_part_t                                          main_subs_feed_part,
  input  logic                                                         main_subs_feed_part_avail,

  // main <-> subsidiary : SXT
  input  mainsubs_sxt_cmd_t                                            main_subs_sxt_cmd,
  input  logic                                                         main_subs_sxt_cmd_vld,
  output logic                                                         main_subs_sxt_cmd_rdy,

  output subsmain_sxt_data_t                                           subs_main_sxt_data,
  output logic                                                         subs_main_sxt_data_vld,
  input  logic                                                         subs_main_sxt_data_rdy,

  output subsmain_sxt_part_t                                           subs_main_sxt_part,
  output logic                                                         subs_main_sxt_part_vld,
  input  logic                                                         subs_main_sxt_part_rdy,

  // main <-> subsidiary : LDG
  input  mainsubs_ldg_cmd_t                                            main_subs_ldg_cmd,
  input  logic                                                         main_subs_ldg_cmd_vld,
  output logic                                                         main_subs_ldg_cmd_rdy,

  input  mainsubs_ldg_data_t                                           main_subs_ldg_data,
  input  logic                                                         main_subs_ldg_data_vld,
  output logic                                                         main_subs_ldg_data_rdy,

  // main <-> subs : proc signals
  output subsmain_proc_t                                               subs_main_proc,
  input  mainsubs_proc_t                                               main_subs_proc,

  // To rif
  output pep_counter_inc_t                                             pep_rif_counter_inc,
  output pep_info_t                                                    pep_rif_info,
  output pep_error_t                                                   pep_error
);

// ============================================================================================== --
// Internal signals
// ============================================================================================== --
  //== GLWE load
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                    ldg_gram_wr_en;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]ldg_gram_wr_add;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]       ldg_gram_wr_data;

  //== Mono mult acc
  // MMACC -> Decomposer
  logic [ACC_DECOMP_COEF_NB-1:0]                              acc_decomp_data_avail;
  logic                                                       acc_decomp_ctrl_avail;
  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0]                 acc_decomp_data;
  logic                                                       acc_decomp_sob;
  logic                                                       acc_decomp_eob;
  logic                                                       acc_decomp_sog;
  logic                                                       acc_decomp_eog;
  logic                                                       acc_decomp_sol;
  logic                                                       acc_decomp_eol;
  logic                                                       acc_decomp_soc;
  logic                                                       acc_decomp_eoc;
  logic [BPBS_ID_W-1:0]                                       acc_decomp_pbs_id;
  logic                                                       acc_decomp_last_pbs;
  logic                                                       acc_decomp_full_throughput;

// ============================================================================================== --
// Error / Inc
// ============================================================================================== --
  pep_error_t           pep_errorD;
  pep_counter_inc_t     pep_rif_counter_incD;

  pep_ldg_error_t       ldg_error;
  pep_mmacc_error_t     mmacc_error;
  pep_ldg_counter_inc_t ldg_rif_counter_inc;
  logic                 decomp_error;

  always_comb begin
    pep_rif_counter_incD        = '0;
    pep_errorD                  = '0;

    pep_rif_counter_incD.ld.ldg = ldg_rif_counter_inc;
    pep_errorD.ldg              = ldg_error;
    pep_errorD.mmacc            = mmacc_error;
    pep_errorD.ntt.in_ovf       = decomp_error;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pep_error           <= '0;
      pep_rif_counter_inc <= '0;
    end
    else begin
      pep_error           <= pep_errorD          ;
      pep_rif_counter_inc <= pep_rif_counter_incD;
    end

  assign pep_rif_info = '0;

// ============================================================================================== --
// Output
// ============================================================================================== --
  logic subs_main_ldg_cmd_done;
  logic subs_main_feed_mcmd_ack;
  logic subs_main_sxt_cmd_ack;
  always_comb begin
    subs_main_proc               = '0;
    subs_main_proc.ldg_cmd_done  = subs_main_ldg_cmd_done;
    subs_main_proc.feed_mcmd_ack = subs_main_feed_mcmd_ack;
    subs_main_proc.sxt_cmd_ack   = subs_main_sxt_cmd_ack;
  end

// ============================================================================================== --
// Load GLWE from MEM
// ============================================================================================== --
  pep_load_glwe_splitc_subs
  pep_load_glwe_splitc_subs (
    .clk                (clk),
    .s_rst_n            (s_rst_n),

    .garb_ldg_avail_1h  (main_subs_proc.garb_avail_1h.ldg),

    .subs_cmd           (main_subs_ldg_cmd.cmd),
    .subs_cmd_vld       (main_subs_ldg_cmd_vld),
    .subs_cmd_rdy       (main_subs_ldg_cmd_rdy),
    .subs_cmd_done      (subs_main_ldg_cmd_done),

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
        main_subs_feed_data_l[p][r]     = main_subs_feed_data.elt[p][r].data;
        main_subs_feed_rot_data_l[p][r] = main_subs_feed_data.elt[p][r].rot_data;
      end
    end

  always_comb
    for (int p=0; p<PSI/MSPLIT_DIV; p=p+1) begin
      for (int r=0; r<R; r=r+1) begin
        main_subs_feed_part_l[p][r]     = main_subs_feed_part.elt[p][r].data;
        main_subs_feed_rot_part_l[p][r] = main_subs_feed_part.elt[p][r].rot_data;
      end
    end

  pep_mmacc_splitc_subsidiary
  #(
    .RAM_LATENCY              (RAM_LATENCY),
    .URAM_LATENCY             (URAM_LATENCY),
    .PHYS_RAM_DEPTH           (PHYS_RAM_DEPTH)
  ) pep_mmacc_splitc_subsidiary (
    .clk                             (clk),
    .s_rst_n                         (s_rst_n),

    .acc_decomp_data_avail           (acc_decomp_data_avail),
    .acc_decomp_ctrl_avail           (acc_decomp_ctrl_avail),
    .acc_decomp_data                 (acc_decomp_data),
    .acc_decomp_sob                  (acc_decomp_sob),
    .acc_decomp_eob                  (acc_decomp_eob),
    .acc_decomp_sog                  (acc_decomp_sog),
    .acc_decomp_eog                  (acc_decomp_eog),
    .acc_decomp_sol                  (acc_decomp_sol),
    .acc_decomp_eol                  (acc_decomp_eol),
    .acc_decomp_soc                  (acc_decomp_soc),
    .acc_decomp_eoc                  (acc_decomp_eoc),
    .acc_decomp_pbs_id               (acc_decomp_pbs_id),
    .acc_decomp_last_pbs             (acc_decomp_last_pbs),
    .acc_decomp_full_throughput      (acc_decomp_full_throughput),

    .ntt_acc_data_avail              (ntt_acc_modsw_data_avail),
    .ntt_acc_ctrl_avail              (ntt_acc_modsw_ctrl_avail),
    .ntt_acc_data                    (ntt_acc_modsw_data),
    .ntt_acc_sob                     (ntt_acc_modsw_sob),
    .ntt_acc_eob                     (ntt_acc_modsw_eob),
    .ntt_acc_sol                     (ntt_acc_modsw_sol),
    .ntt_acc_eol                     (ntt_acc_modsw_eol),
    .ntt_acc_sog                     (ntt_acc_modsw_sog),
    .ntt_acc_eog                     (ntt_acc_modsw_eog),
    .ntt_acc_pbs_id                  (ntt_acc_modsw_pbs_id),

    .ldg_gram_wr_en                  (ldg_gram_wr_en),
    .ldg_gram_wr_add                 (ldg_gram_wr_add),
    .ldg_gram_wr_data                (ldg_gram_wr_data),

    .garb_feed_rot_avail_1h          (main_subs_proc.garb_avail_1h.feed_rot),
    .garb_feed_dat_avail_1h          (main_subs_proc.garb_avail_1h.feed_dat),
    .garb_acc_rd_avail_1h            (main_subs_proc.garb_avail_1h.acc_rd),
    .garb_acc_wr_avail_1h            (main_subs_proc.garb_avail_1h.acc_wr),
    .garb_sxt_avail_1h               (main_subs_proc.garb_avail_1h.sxt),

    .main_subs_feed_mcmd             (main_subs_feed_cmd.mcmd),
    .main_subs_feed_mcmd_vld         (main_subs_feed_cmd_vld),
    .main_subs_feed_mcmd_rdy         (main_subs_feed_cmd_rdy),
    .subs_main_feed_mcmd_ack         (subs_main_feed_mcmd_ack),
    .main_subs_feed_mcmd_ack_ack     (main_subs_proc.feed_mcmd_ack_ack),

    .main_subs_feed_data             (main_subs_feed_data_l),
    .main_subs_feed_rot_data         (main_subs_feed_rot_data_l),
    .main_subs_feed_data_avail       (main_subs_feed_data_avail),

    .main_subs_feed_part             (main_subs_feed_part_l),
    .main_subs_feed_rot_part         (main_subs_feed_rot_part_l),
    .main_subs_feed_part_avail       (main_subs_feed_part_avail),

    .subs_main_ntt_acc_avail         (subs_main_ntt_acc_modsw_avail),
    .subs_main_ntt_acc_data          (subs_main_ntt_acc_modsw_data),
    .subs_main_ntt_acc_sob           (subs_main_ntt_acc_modsw_sob),
    .subs_main_ntt_acc_eob           (subs_main_ntt_acc_modsw_eob),
    .subs_main_ntt_acc_sol           (subs_main_ntt_acc_modsw_sol),
    .subs_main_ntt_acc_eol           (subs_main_ntt_acc_modsw_eol),
    .subs_main_ntt_acc_sog           (subs_main_ntt_acc_modsw_sog),
    .subs_main_ntt_acc_eog           (subs_main_ntt_acc_modsw_eog),
    .subs_main_ntt_acc_pbs_id        (subs_main_ntt_acc_modsw_pbs_id),

    .main_subs_sxt_cmd_vld           (main_subs_sxt_cmd_vld),
    .main_subs_sxt_cmd_rdy           (main_subs_sxt_cmd_rdy),
    .main_subs_sxt_cmd_body          (main_subs_sxt_cmd.body),
    .main_subs_sxt_cmd_icmd          (main_subs_sxt_cmd.icmd),
    .subs_main_sxt_cmd_ack           (subs_main_sxt_cmd_ack),

    .subs_main_sxt_data_data         (subs_main_sxt_data.data),
    .subs_main_sxt_data_vld          (subs_main_sxt_data_vld),
    .subs_main_sxt_data_rdy          (subs_main_sxt_data_rdy),

    .subs_main_sxt_part_data         (subs_main_sxt_part.data),
    .subs_main_sxt_part_vld          (subs_main_sxt_part_vld),
    .subs_main_sxt_part_rdy          (subs_main_sxt_part_rdy),

    .mmacc_error                     (mmacc_error)

  );

// ---------------------------------------------------------------------------------------------- --
// decomposer
// ---------------------------------------------------------------------------------------------- --
  decomp_balanced_sequential
  #(
    .CHUNK_NB   (CHUNK_NB)
  ) decomp_balanced_sequential (
    .clk                        (clk),
    .s_rst_n                    (s_rst_n),

    .acc_decomp_ctrl_avail      (acc_decomp_ctrl_avail),
    .acc_decomp_data_avail      (acc_decomp_data_avail),
    .acc_decomp_data            (acc_decomp_data),
    .acc_decomp_sob             (acc_decomp_sob),
    .acc_decomp_eob             (acc_decomp_eob),
    .acc_decomp_sog             (acc_decomp_sog),
    .acc_decomp_eog             (acc_decomp_eog),
    .acc_decomp_sol             (acc_decomp_sol),
    .acc_decomp_eol             (acc_decomp_eol),
    .acc_decomp_soc             (acc_decomp_soc),
    .acc_decomp_eoc             (acc_decomp_eoc),
    .acc_decomp_pbs_id          (acc_decomp_pbs_id),
    .acc_decomp_last_pbs        (acc_decomp_last_pbs),
    .acc_decomp_full_throughput (acc_decomp_full_throughput),

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

    .error                      (decomp_error)
  );


endmodule
