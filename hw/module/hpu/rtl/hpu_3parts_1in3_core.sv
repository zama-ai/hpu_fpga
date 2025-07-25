// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// HPU top level.
// HPU is split into 3 parts.
// This module is the first part.
// Mainly used to ease P&R constraints.
// ==============================================================================================

`include "hpu_io_macro_inc.sv"

(* keep_hierarchy = "yes" *)
module hpu_3parts_1in3_core
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import top_common_param_pkg::*;
  import hpu_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
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
  parameter int    AXI4_KSK_ADD_W   = 64,

  // HPU version
  parameter int    VERSION_MAJOR    = 2,
  parameter int    VERSION_MINOR    = 0

)
(
  input  logic                 prc_clk,    // process clock
  input  logic                 prc_srst_n, // synchronous reset

  input  logic                 cfg_clk,    // config clock
  input  logic                 cfg_srst_n, // synchronous reset

  output logic [1:0]           interrupt, // [0] prc_clk, [1] cfg_clk

  //== Axi4-lite slave @prc_clk and @cfg_clk
  `HPU_AXIL_IO(prc,axi_if_shell_axil_pkg)
  `HPU_AXIL_IO(cfg,axi_if_shell_axil_pkg)

  //== Axi4 trace interface
  `HPU_AXI4_IO(trc, TRC, axi_if_trc_axi_pkg,)

  //== Axi4 PEM interface
  `HPU_AXI4_IO(pem, PEM, axi_if_ct_axi_pkg, [PEM_PC-1:0])

  //== Axi4 GLWE interface
  `HPU_AXI4_IO(glwe, GLWE, axi_if_glwe_axi_pkg, [GLWE_PC-1:0])

  //== Axi4 KSK interface
  `HPU_AXI4_IO(ksk, KSK, axi_if_ksk_axi_pkg, [KSK_PC-1:0])

  //== AXI stream for ISC
  input  logic [PE_INST_W-1:0] isc_dop,
  output logic                 isc_dop_rdy,
  input  logic                 isc_dop_vld,

  output logic [PE_INST_W-1:0] isc_ack,
  input  logic                 isc_ack_rdy,
  output logic                 isc_ack_vld,

  //== HPU internal signals
  output logic [PSI-1:0][R-1:0]             decomp_ntt_data_avail,
  output logic [PSI-1:0][R-1:0][PBS_B_W:0]  decomp_ntt_data, // 2s complement
  output logic                              decomp_ntt_sob,
  output logic                              decomp_ntt_eob,
  output logic                              decomp_ntt_sog,
  output logic                              decomp_ntt_eog,
  output logic                              decomp_ntt_sol,
  output logic                              decomp_ntt_eol,
  output logic [BPBS_ID_W-1:0]              decomp_ntt_pbs_id,
  output logic                              decomp_ntt_last_pbs,
  output logic                              decomp_ntt_full_throughput,
  output logic                              decomp_ntt_ctrl_avail,

  // Mod switch output
  input logic [PSI-1:0][R-1:0]              ntt_acc_modsw_data_avail,
  input logic                               ntt_acc_modsw_ctrl_avail,
  input logic [PSI-1:0][R-1:0][MOD_Q_W-1:0] ntt_acc_modsw_data,
  input logic                               ntt_acc_modsw_sob,
  input logic                               ntt_acc_modsw_eob,
  input logic                               ntt_acc_modsw_sol,
  input logic                               ntt_acc_modsw_eol,
  input logic                               ntt_acc_modsw_sog,
  input logic                               ntt_acc_modsw_eog,
  input logic [BPBS_ID_W-1:0]               ntt_acc_modsw_pbs_id,

  //-- BSK
  output entrybsk_proc_t       entry_bsk_proc,
  input  bskentry_proc_t       bsk_entry_proc,

  //== Cmd path
  output ntt_proc_cmd_t        ntt_proc_cmd,
  output logic                 ntt_proc_cmd_avail
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Error
// ---------------------------------------------------------------------------------------------- --
  // error bus width - TODO : complete here the other modules' error.
  localparam int ERROR_NB  = PEP_ERROR_W;

// ============================================================================================== --
// Signals
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Regif
// ---------------------------------------------------------------------------------------------- --
  pep_info_t                              pep_rif_info;
  pep_counter_inc_t                       pep_rif_counter_inc;
  pem_info_t                              pem_rif_info;
  pem_counter_inc_t                       pem_rif_counter_inc;
  pea_counter_inc_t                       pea_rif_counter_inc;

  pep_info_t                              pep_entry_rif_info;
  pep_info_t                              pep_ksk_rif_info;
  pep_info_t                              pep_ks_rif_info;

  pep_info_t                              subs_pep_entry_rif_info;
  pep_info_t                              subs_pep_ksk_rif_info;
  pep_info_t                              subs_pep_ks_rif_info;

  pep_counter_inc_t                       pep_entry_rif_counter_inc;
  pep_counter_inc_t                       subs_pep_entry_rif_counter_inc;
  pep_counter_inc_t                       pep_ksk_rif_counter_inc;
  pep_counter_inc_t                       pep_ks_rif_counter_inc;

// ---------------------------------------------------------------------------------------------- --
// PEM
// ---------------------------------------------------------------------------------------------- --
  logic [PEM_PC_MAX-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0] ct_mem_addr;

  logic [PE_INST_W-1:0]                   isc_pem_insn;
  logic                                   isc_pem_vld;
  logic                                   isc_pem_rdy;
  logic                                   pem_isc_load_ack;
  logic                                   pem_isc_store_ack;

  logic                                   pem_regf_wr_req_vld;
  logic                                   pem_regf_wr_req_rdy;
  regf_wr_req_t                           pem_regf_wr_req;
  logic [REGF_COEF_NB-1:0]                pem_regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]                pem_regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   pem_regf_wr_data;
  logic                                   regf_pem_wr_ack;

  logic                                   pem_regf_rd_req_vld;
  logic                                   pem_regf_rd_req_rdy;
  regf_rd_req_t                           pem_regf_rd_req;
  logic [REGF_COEF_NB-1:0]                regf_pem_rd_data_avail;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   regf_pem_rd_data;
  logic                                   regf_pem_rd_last_word; // valid with avail[0]
  logic                                   regf_pem_rd_is_body;
  logic                                   regf_pem_rd_last_mask;

// ---------------------------------------------------------------------------------------------- --
// PEA
// ---------------------------------------------------------------------------------------------- --
  logic [PE_INST_W-1:0]                   isc_pea_insn;
  logic                                   isc_pea_vld;
  logic                                   isc_pea_rdy;
  logic                                   pea_isc_ack;

  logic                                   pea_regf_wr_req_vld;
  logic                                   pea_regf_wr_req_rdy;
  regf_wr_req_t                           pea_regf_wr_req;
  logic [REGF_COEF_NB-1:0]                pea_regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]                pea_regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   pea_regf_wr_data;
  logic                                   regf_pea_wr_ack;

  logic                                   pea_regf_rd_req_vld;
  logic                                   pea_regf_rd_req_rdy;
  regf_rd_req_t                           pea_regf_rd_req;
  logic [REGF_COEF_NB-1:0]                regf_pea_rd_data_avail;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   regf_pea_rd_data;
  logic                                   regf_pea_rd_last_word; // valid with avail[0]
  logic                                   regf_pea_rd_is_body;
  logic                                   regf_pea_rd_last_mask;

// ---------------------------------------------------------------------------------------------- --
// PEP
// ---------------------------------------------------------------------------------------------- --
// From regif
  logic                                                        reset_ksk_cache;
  logic                                                        reset_ksk_cache_done;
  logic                                                        ksk_mem_avail;
  logic [KSK_PC_MAX-1:0][axi_if_ksk_axi_pkg::AXI4_ADD_W-1:0]   ksk_mem_addr;

  logic                                                        reset_cache;
  logic                                                        reset_ks;

  logic [GLWE_PC_MAX-1:0][axi_if_glwe_axi_pkg::AXI4_ADD_W-1:0] glwe_mem_addr;
  logic                                                        use_bpip;
  logic                                                        use_bpip_opportunism;
  logic [TIMEOUT_CNT_W-1:0]                                    bpip_timeout;
  logic                                                        mod_switch_mean_comp;

  // seq <-> pe_pbs
  logic [PE_INST_W-1:0]                   isc_pep_insn;
  logic                                   isc_pep_vld;
  logic                                   isc_pep_rdy;
  logic                                   pep_isc_ack;
  logic [LWE_K_W-1:0]                     pep_isc_ack_br_loop;
  logic                                   pep_isc_load_blwe_ack;

  logic                                   pep_regf_wr_req_vld;
  logic                                   pep_regf_wr_req_rdy;
  regf_wr_req_t                           pep_regf_wr_req;

  logic [REGF_COEF_NB-1:0]                pep_regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]                pep_regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   pep_regf_wr_data;

  logic                                   regf_pep_wr_ack;


  logic                                   pep_regf_rd_req_vld;
  logic                                   pep_regf_rd_req_rdy;
  regf_rd_req_t                           pep_regf_rd_req;

  logic [REGF_COEF_NB-1:0]                regf_pep_rd_data_avail;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   regf_pep_rd_data;
  logic                                   regf_pep_rd_last_word;
  logic                                   regf_pep_rd_is_body;
  logic                                   regf_pep_rd_last_mask;

  //== seq <-> ldb
  logic [LOAD_BLWE_CMD_W-1:0]             seq_ldb_cmd;
  logic                                   seq_ldb_vld;
  logic                                   seq_ldb_rdy;
  logic                                   ldb_seq_done;

  //== seq <-> KS
  logic                                   ks_seq_cmd_enquiry;
  logic [KS_CMD_W-1:0]                    seq_ks_cmd;
  logic                                   seq_ks_cmd_avail;

  logic [KS_RESULT_W-1:0]                 ks_seq_result;
  logic                                   ks_seq_result_vld;
  logic                                   ks_seq_result_rdy;

  //== Key switch
  // KS <-> Body RAM
  logic                                   ks_boram_wr_en;
  logic [MOD_KSK_W-1:0]                   ks_boram_data;
  logic [PID_W-1:0]                       ks_boram_pid;
  logic                                   ks_boram_parity;

  logic                                   inc_ksk_wr_ptr;
  logic                                   inc_ksk_rd_ptr;

  logic                                   bsk_if_batch_start_1h;
  logic                                   ksk_if_batch_start_1h;

  logic [BR_BATCH_CMD_W-1:0]              br_batch_cmd;
  logic                                   br_batch_cmd_avail;
  logic [KS_BATCH_CMD_W-1:0]              ks_batch_cmd;
  logic                                   ks_batch_cmd_avail;

  logic [LBX-1:0][LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0] ksk;
  logic [LBX-1:0][LBY-1:0]                         ksk_vld;
  logic [LBX-1:0][LBY-1:0]                         ksk_rdy;

  logic                                   inc_bsk_wr_ptr;
  logic                                   inc_bsk_rd_ptr;

  // Acc
  subsmain_acc_data_t                     subs_main_acc_data;
  logic                                   subs_main_acc_data_avail;

  //-- MMACC
  // Feed
  mainsubs_feed_cmd_t                     main_subs_feed_cmd;
  logic                                   main_subs_feed_cmd_vld;
  logic                                   main_subs_feed_cmd_rdy;

  mainsubs_feed_data_t                    main_subs_feed_data;
  logic                                   main_subs_feed_data_avail;

  mainsubs_feed_part_t                    main_subs_feed_part;
  logic                                   main_subs_feed_part_avail;

  // Sxt
  mainsubs_sxt_cmd_t                      main_subs_sxt_cmd;
  logic                                   main_subs_sxt_cmd_vld;
  logic                                   main_subs_sxt_cmd_rdy;

  subsmain_sxt_data_t                     subs_main_sxt_data;
  logic                                   subs_main_sxt_data_vld;
  logic                                   subs_main_sxt_data_rdy;

  subsmain_sxt_part_t                     subs_main_sxt_part;
  logic                                   subs_main_sxt_part_vld;
  logic                                   subs_main_sxt_part_rdy;

  //-- LDG
  mainsubs_ldg_cmd_t                      main_subs_ldg_cmd;
  logic                                   main_subs_ldg_cmd_vld;
  logic                                   main_subs_ldg_cmd_rdy;

  mainsubs_ldg_data_t                     main_subs_ldg_data;
  logic                                   main_subs_ldg_data_vld;
  logic                                   main_subs_ldg_data_rdy;

  //-- MMACC Misc
  mainsubs_side_t                         main_subs_side;
  subsmain_side_t                         subs_main_side;

// ---------------------------------------------------------------------------------------------- --
// Errors
// ---------------------------------------------------------------------------------------------- --
  logic [ERROR_NB-1:0]                    error;

  pep_error_t                             pep_error;
  pep_error_t                             pep_ks_error;
  pep_error_t                             pep_ksk_error;
  pep_error_t                             pep_entry_error;
  pep_error_t                             subs_pep_entry_error;


// ============================================================================================== --
// To regif
// ============================================================================================== --
  pep_error_t             pep_errorD;
  pep_info_t              pep_rif_infoD;
  pep_counter_inc_t       pep_rif_counter_incD;

  assign pep_rif_infoD = pep_entry_rif_info
                        | pep_ksk_rif_info
                        | pep_ks_rif_info
                        | subs_pep_entry_rif_info
                        | subs_pep_ksk_rif_info
                        | subs_pep_ks_rif_info;

  assign pep_rif_counter_incD = pep_entry_rif_counter_inc
                        | subs_pep_entry_rif_counter_inc
                        | pep_ksk_rif_counter_inc
                        | pep_ks_rif_counter_inc;

  assign pep_errorD = pep_entry_error
                    | subs_pep_entry_error
                    | pep_ks_error
                    | pep_ksk_error;

  always_ff @(posedge prc_clk)
    if (!prc_srst_n) begin
      pep_error           <= '0;
      pep_rif_info        <= '0;
      pep_rif_counter_inc <= '0;
    end
    else begin
      pep_error           <= pep_errorD;
      pep_rif_info        <= pep_rif_infoD       ;
      pep_rif_counter_inc <= pep_rif_counter_incD;
    end

  assign error = {pep_error};  // TODO complete with the other errors

// ============================================================================================== --
// Output
// ============================================================================================== --
  always_comb begin
    entry_bsk_proc = '0;
    ntt_proc_cmd   = '0;

    entry_bsk_proc.inc_rd_ptr     = inc_bsk_rd_ptr;
    entry_bsk_proc.batch_start_1h = bsk_if_batch_start_1h;

    ntt_proc_cmd.batch_cmd        = br_batch_cmd;
  end

  assign ntt_proc_cmd_avail      = br_batch_cmd_avail;

// ============================================================================================== --
// Input
// ============================================================================================== --
  assign inc_bsk_wr_ptr       = bsk_entry_proc.inc_wr_ptr;

// ============================================================================================== --
// hpu_with_entry
// contains:
// * hpu_regif
// * instruction_scheduler
// * trace_manager
// ============================================================================================== --
  // Tie off m_axi4 unused features
  `HPU_AXI4_TIE_GL_UNUSED(trc,,1)
  `HPU_AXI4_TIE_RD_UNUSED(trc,)

  // /!\ Workaround
  // For simulation AXI4_TRC_ADD_W could be different from axi_if_trc_axi_pkg::AXI4_ADD_W
  logic [axi_if_trc_axi_pkg::AXI4_ADD_W-1:0] m_axi4_trc_awaddr_tmp;
  assign m_axi4_trc_awaddr = m_axi4_trc_awaddr_tmp[AXI4_TRC_ADD_W-1:0];
  hpu_with_entry_1in3 # (
    .ERROR_NB      (ERROR_NB),
    .VERSION_MAJOR (VERSION_MAJOR),
    .VERSION_MINOR (VERSION_MINOR)
  ) hpu_with_entry_1in3 (
    .prc_clk                   (prc_clk),
    .prc_srst_n                (prc_srst_n),

    .cfg_clk                   (cfg_clk),
    .cfg_srst_n                (cfg_srst_n),

    // Axi lite interface
    `HPU_AXIL_INSTANCE(prc,prc)
    `HPU_AXIL_INSTANCE(cfg,cfg)

    .isc_dop                   (isc_dop),
    .isc_dop_rdy               (isc_dop_rdy),
    .isc_dop_vld               (isc_dop_vld),

    .isc_ack                   (isc_ack),
    .isc_ack_rdy               (isc_ack_rdy),
    .isc_ack_vld               (isc_ack_vld),

    // Master Axi4 TM interface [Write-only]
    `HPU_AXI4_SHORT_WR_INSTANCE(trc, trc, _tmp,)

    // Registers IO
    .ct_mem_addr               (ct_mem_addr),
    .glwe_mem_addr             (glwe_mem_addr),
    .ksk_mem_addr              (ksk_mem_addr),
    .ksk_mem_avail             (ksk_mem_avail),
    .reset_ksk_cache           (reset_ksk_cache),
    .reset_ksk_cache_done      (reset_ksk_cache_done),

    .reset_cache               (reset_cache),

    .use_bpip                  (use_bpip),
    .use_bpip_opportunism      (use_bpip_opportunism),
    .bpip_timeout              (bpip_timeout),
    .mod_switch_mean_comp      (mod_switch_mean_comp),

    // To PE_MEM
    .isc_pem_insn              (isc_pem_insn),
    .isc_pem_vld               (isc_pem_vld),
    .isc_pem_rdy               (isc_pem_rdy),
    .pem_isc_load_ack          (pem_isc_load_ack),
    .pem_isc_store_ack         (pem_isc_store_ack),

    // To PE_ALU
    .isc_pea_insn              (isc_pea_insn),
    .isc_pea_vld               (isc_pea_vld),
    .isc_pea_rdy               (isc_pea_rdy),
    .pea_isc_ack               (pea_isc_ack),

    // To PE_PBS
    .isc_pep_insn              (isc_pep_insn),
    .isc_pep_vld               (isc_pep_vld),
    .isc_pep_rdy               (isc_pep_rdy),
    .pep_isc_ack               (pep_isc_ack),
    .pep_isc_ack_br_loop       (pep_isc_ack_br_loop),
    .pep_isc_load_blwe_ack     (pep_isc_load_blwe_ack),

    // Instrumentation
    .error                     (error),
    .pep_rif_info              (pep_rif_info),
    .pem_rif_info              (pem_rif_info),
    .pep_rif_counter_inc       (pep_rif_counter_inc),
    .pem_rif_counter_inc       (pem_rif_counter_inc),
    .pea_rif_counter_inc       (pea_rif_counter_inc),

    .interrupt                 (interrupt)
  );

// ============================================================================================== --
// hpu_with_pe
// contains:
// * pe_mem
// * pe_alu
// * regfile
// ============================================================================================== --
  // Tie off m_axi4 unused features
  `HPU_AXI4_TIE_GL_UNUSED(pem, [PEM_PC-1:0], PEM_PC)

  // /!\ Workaround : simulation AXI4_PEM_ADD_W may be different from
  // the AXI4_PEM_ADD_W of the package (= the synthesized value).
  // Use intermediate variable.
  logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0] m_axi4_pem_araddr_tmp;
  logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0] m_axi4_pem_awaddr_tmp;
  always_comb
    for (int i=0; i<PEM_PC; i=i+1) begin
      m_axi4_pem_araddr[i] = m_axi4_pem_araddr_tmp[i][AXI4_PEM_ADD_W-1:0];
      m_axi4_pem_awaddr[i] = m_axi4_pem_awaddr_tmp[i][AXI4_PEM_ADD_W-1:0];
    end

  hpu_with_pe
  hpu_with_pe(
    .clk                    (prc_clk),
    .s_rst_n                (prc_srst_n),

    `HPU_AXI4_SHORT_INSTANCE(pem, pem, _tmp, [PEM_PC-1:0])

    .isc_pem_insn           (isc_pem_insn),
    .isc_pem_vld            (isc_pem_vld),
    .isc_pem_rdy            (isc_pem_rdy),
    .pem_isc_load_ack       (pem_isc_load_ack),
    .pem_isc_store_ack      (pem_isc_store_ack),

    .isc_pea_insn           (isc_pea_insn),
    .isc_pea_vld            (isc_pea_vld),
    .isc_pea_rdy            (isc_pea_rdy),
    .pea_isc_ack            (pea_isc_ack),

    .pep_regf_wr_req_vld    (pep_regf_wr_req_vld),
    .pep_regf_wr_req_rdy    (pep_regf_wr_req_rdy),
    .pep_regf_wr_req        (pep_regf_wr_req),

    .pep_regf_wr_data_vld   (pep_regf_wr_data_vld),
    .pep_regf_wr_data_rdy   (pep_regf_wr_data_rdy),
    .pep_regf_wr_data       (pep_regf_wr_data),

    .regf_pep_wr_ack        (regf_pep_wr_ack),

    .pep_regf_rd_req_vld    (pep_regf_rd_req_vld),
    .pep_regf_rd_req_rdy    (pep_regf_rd_req_rdy),
    .pep_regf_rd_req        (pep_regf_rd_req),

    .regf_pep_rd_data_avail (regf_pep_rd_data_avail),
    .regf_pep_rd_data       (regf_pep_rd_data),
    .regf_pep_rd_last_word  (regf_pep_rd_last_word),
    .regf_pep_rd_is_body    (regf_pep_rd_is_body),
    .regf_pep_rd_last_mask  (regf_pep_rd_last_mask),

    .ct_mem_addr            (ct_mem_addr),
    .pem_rif_counter_inc    (pem_rif_counter_inc),
    .pea_rif_counter_inc    (pea_rif_counter_inc),
    .pem_rif_info           (pem_rif_info)

  );

// ============================================================================================== --
// pe_pbs
// ============================================================================================== --
  // Tie-off m_axi4 unused features
  `HPU_AXI4_TIE_GL_UNUSED(ksk, [KSK_PC-1:0], KSK_PC)
  `HPU_AXI4_TIE_WR_UNUSED(ksk, [KSK_PC-1:0])

  `HPU_AXI4_TIE_GL_UNUSED(glwe, [GLWE_PC-1:0], GLWE_PC)
  `HPU_AXI4_TIE_WR_UNUSED(glwe, [GLWE_PC-1:0])

  // /!\ Workaround : simulation AXI4_KSK/BSK_ADD_W may be different from
  // the AXI4_KSK_ADD_W of the package (= the synthesized value).
  // Use intermediate variable.
  logic [KSK_PC-1:0][axi_if_ksk_axi_pkg::AXI4_ADD_W-1:0] m_axi4_ksk_araddr_tmp;
  logic [GLWE_PC-1:0][axi_if_glwe_axi_pkg::AXI4_ADD_W-1:0] m_axi4_glwe_araddr_tmp;
  always_comb
    for (int i=0; i<KSK_PC; i=i+1)
      m_axi4_ksk_araddr[i] = m_axi4_ksk_araddr_tmp[i][AXI4_KSK_ADD_W-1:0];

  always_comb
    for (int i=0; i<GLWE_PC; i=i+1)
      m_axi4_glwe_araddr[i] = m_axi4_glwe_araddr_tmp[i][AXI4_GLWE_ADD_W-1:0];

// pragma translate_off
  always_ff @(posedge prc_clk)
    if (!prc_srst_n) begin
      // Do nothing
    end
    else begin
      for (int i=0; i<KSK_PC; i=i+1) begin
        if (m_axi4_ksk_arvalid[i]) begin
          assert(m_axi4_ksk_araddr_tmp[i] >> AXI4_KSK_ADD_W == '0)
          else begin
            $fatal(1,"%t > ERROR: KSK AXI [%d] address overflows. Simulation supports only %d bits: 0x%0x.",$time, i, AXI4_KSK_ADD_W,m_axi4_ksk_araddr_tmp[i]);
          end
        end
      end
    end
// pragma translate_on

// ---------------------------------------------------------------------------------------------- --
// pe_pbs_with_entry
// contains:
// * pep_mono_mult_acc : main
// * pep_sequencer
// * pep_load_glwe : main
// * decomposer
// ---------------------------------------------------------------------------------------------- --
  pe_pbs_with_entry_main
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
  ) pe_pbs_with_entry_main (
    .clk                        (prc_clk),
    .s_rst_n                    (prc_srst_n),

    .inst                       (isc_pep_insn),
    .inst_vld                   (isc_pep_vld),
    .inst_rdy                   (isc_pep_rdy),
    .inst_ack                   (pep_isc_ack),
    .inst_ack_br_loop           (pep_isc_ack_br_loop),
    .inst_load_blwe_ack         (pep_isc_load_blwe_ack),

    .pep_regf_wr_req_vld        (pep_regf_wr_req_vld),
    .pep_regf_wr_req_rdy        (pep_regf_wr_req_rdy),
    .pep_regf_wr_req            (pep_regf_wr_req),

    .pep_regf_wr_data_vld       (pep_regf_wr_data_vld),
    .pep_regf_wr_data_rdy       (pep_regf_wr_data_rdy),
    .pep_regf_wr_data           (pep_regf_wr_data),

    .regf_pep_wr_ack            (regf_pep_wr_ack),

    .glwe_mem_addr              (glwe_mem_addr),

    .use_bpip                   (use_bpip),
    .use_bpip_opportunism       (use_bpip_opportunism),
    .bpip_timeout               (bpip_timeout),

    `HPU_AXI4_SHORT_RD_INSTANCE(glwe, glwe, _tmp, [GLWE_PC-1:0])

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

    .subs_main_ntt_acc_modsw_avail   (subs_main_acc_data_avail),
    .subs_main_ntt_acc_modsw_data    (subs_main_acc_data.data),
    .subs_main_ntt_acc_modsw_sob     (subs_main_acc_data.sob),
    .subs_main_ntt_acc_modsw_eob     (subs_main_acc_data.eob),
    .subs_main_ntt_acc_modsw_sol     (subs_main_acc_data.sol),
    .subs_main_ntt_acc_modsw_eol     (subs_main_acc_data.eol),
    .subs_main_ntt_acc_modsw_sog     (subs_main_acc_data.sog),
    .subs_main_ntt_acc_modsw_eog     (subs_main_acc_data.eog),
    .subs_main_ntt_acc_modsw_pbs_id  (subs_main_acc_data.pbs_id),

    .bsk_if_batch_start_1h      (bsk_if_batch_start_1h),
    .ksk_if_batch_start_1h      (ksk_if_batch_start_1h),
    .inc_bsk_wr_ptr             (inc_bsk_wr_ptr),
    .inc_bsk_rd_ptr             (inc_bsk_rd_ptr),

    .reset_cache                (reset_cache),
    .reset_ks                   (reset_ks),

    .br_batch_cmd               (br_batch_cmd),
    .br_batch_cmd_avail         (br_batch_cmd_avail),

    .pep_error                  (pep_entry_error),
    .pep_rif_info               (pep_entry_rif_info),
    .pep_rif_counter_inc        (pep_entry_rif_counter_inc),

    .main_subs_feed_cmd         (main_subs_feed_cmd),
    .main_subs_feed_cmd_vld     (main_subs_feed_cmd_vld),
    .main_subs_feed_cmd_rdy     (main_subs_feed_cmd_rdy),

    .main_subs_feed_data        (main_subs_feed_data),
    .main_subs_feed_data_avail  (main_subs_feed_data_avail),

    .main_subs_feed_part        (main_subs_feed_part),
    .main_subs_feed_part_avail  (main_subs_feed_part_avail),

    .main_subs_sxt_cmd          (main_subs_sxt_cmd),
    .main_subs_sxt_cmd_vld      (main_subs_sxt_cmd_vld),
    .main_subs_sxt_cmd_rdy      (main_subs_sxt_cmd_rdy),

    .subs_main_sxt_data         (subs_main_sxt_data),
    .subs_main_sxt_data_vld     (subs_main_sxt_data_vld),
    .subs_main_sxt_data_rdy     (subs_main_sxt_data_rdy),

    .subs_main_sxt_part         (subs_main_sxt_part),
    .subs_main_sxt_part_vld     (subs_main_sxt_part_vld),
    .subs_main_sxt_part_rdy     (subs_main_sxt_part_rdy),

    .main_subs_ldg_cmd          (main_subs_ldg_cmd),
    .main_subs_ldg_cmd_vld      (main_subs_ldg_cmd_vld),
    .main_subs_ldg_cmd_rdy      (main_subs_ldg_cmd_rdy),

    .main_subs_ldg_data         (main_subs_ldg_data),
    .main_subs_ldg_data_vld     (main_subs_ldg_data_vld),
    .main_subs_ldg_data_rdy     (main_subs_ldg_data_rdy),

    .subs_main_proc             (subs_main_side.proc),
    .main_subs_proc             (main_subs_side.proc)
  );

// ============================================================================================== --
// pe_pbs_with_entry_subsidiary
// contains:
// * pep_mon_mult_acc
// * pep_load_glwe
// ============================================================================================== --
  pe_pbs_with_entry_subsidiary
  #(
    .MOD_MULT_TYPE        (MOD_MULT_TYPE),
    .REDUCT_TYPE          (REDUCT_TYPE),
    .MULT_TYPE            (MULT_TYPE),
    .PP_MOD_MULT_TYPE     (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE         (PP_MULT_TYPE),
    .MODSW_2_PRECISION_W  (MODSW_2_PRECISION_W),
    .MODSW_2_MULT_TYPE    (MODSW_2_MULT_TYPE),
    .MODSW_MULT_TYPE      (MODSW_MULT_TYPE),

    .RAM_LATENCY          (RAM_LATENCY),
    .URAM_LATENCY         (URAM_LATENCY),
    .ROM_LATENCY          (ROM_LATENCY),

    .TWD_IFNL_FILE_PREFIX (TWD_IFNL_FILE_PREFIX),
    .TWD_PHRU_FILE_PREFIX (TWD_PHRU_FILE_PREFIX),

    .INST_FIFO_DEPTH      (PEP_INST_FIFO_DEPTH),

    .REGF_RD_LATENCY      (REGF_RD_LATENCY),
    .KS_IF_COEF_NB        (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB        (KS_IF_SUBW_NB),

    .PHYS_RAM_DEPTH       (PHYS_RAM_DEPTH)
  ) pe_pbs_with_entry_subsidiary (
    .clk                                   (prc_clk),
    .s_rst_n                               (prc_srst_n),

    .decomp_ntt_data_avail                 (decomp_ntt_data_avail),
    .decomp_ntt_data                       (decomp_ntt_data),
    .decomp_ntt_sob                        (decomp_ntt_sob),
    .decomp_ntt_eob                        (decomp_ntt_eob),
    .decomp_ntt_sog                        (decomp_ntt_sog),
    .decomp_ntt_eog                        (decomp_ntt_eog),
    .decomp_ntt_sol                        (decomp_ntt_sol),
    .decomp_ntt_eol                        (decomp_ntt_eol),
    .decomp_ntt_pbs_id                     (decomp_ntt_pbs_id),
    .decomp_ntt_last_pbs                   (decomp_ntt_last_pbs),
    .decomp_ntt_full_throughput            (decomp_ntt_full_throughput),
    .decomp_ntt_ctrl_avail                 (decomp_ntt_ctrl_avail),

    .ntt_acc_modsw_data_avail              (ntt_acc_modsw_data_avail),
    .ntt_acc_modsw_ctrl_avail              (ntt_acc_modsw_ctrl_avail),
    .ntt_acc_modsw_data                    (ntt_acc_modsw_data),
    .ntt_acc_modsw_sob                     (ntt_acc_modsw_sob),
    .ntt_acc_modsw_eob                     (ntt_acc_modsw_eob),
    .ntt_acc_modsw_sol                     (ntt_acc_modsw_sol),
    .ntt_acc_modsw_eol                     (ntt_acc_modsw_eol),
    .ntt_acc_modsw_sog                     (ntt_acc_modsw_sog),
    .ntt_acc_modsw_eog                     (ntt_acc_modsw_eog),
    .ntt_acc_modsw_pbs_id                  (ntt_acc_modsw_pbs_id),

    .subs_main_ntt_acc_modsw_avail         (subs_main_acc_data_avail),
    .subs_main_ntt_acc_modsw_data          (subs_main_acc_data.data),
    .subs_main_ntt_acc_modsw_sob           (subs_main_acc_data.sob),
    .subs_main_ntt_acc_modsw_eob           (subs_main_acc_data.eob),
    .subs_main_ntt_acc_modsw_sol           (subs_main_acc_data.sol),
    .subs_main_ntt_acc_modsw_eol           (subs_main_acc_data.eol),
    .subs_main_ntt_acc_modsw_sog           (subs_main_acc_data.sog),
    .subs_main_ntt_acc_modsw_eog           (subs_main_acc_data.eog),
    .subs_main_ntt_acc_modsw_pbs_id        (subs_main_acc_data.pbs_id),

    .main_subs_feed_cmd                    (main_subs_feed_cmd),
    .main_subs_feed_cmd_vld                (main_subs_feed_cmd_vld),
    .main_subs_feed_cmd_rdy                (main_subs_feed_cmd_rdy),

    .main_subs_feed_data                   (main_subs_feed_data),
    .main_subs_feed_data_avail             (main_subs_feed_data_avail),

    .main_subs_feed_part                   (main_subs_feed_part),
    .main_subs_feed_part_avail             (main_subs_feed_part_avail),

    .main_subs_sxt_cmd                     (main_subs_sxt_cmd),
    .main_subs_sxt_cmd_vld                 (main_subs_sxt_cmd_vld),
    .main_subs_sxt_cmd_rdy                 (main_subs_sxt_cmd_rdy),

    .subs_main_sxt_data                    (subs_main_sxt_data),
    .subs_main_sxt_data_vld                (subs_main_sxt_data_vld),
    .subs_main_sxt_data_rdy                (subs_main_sxt_data_rdy),

    .subs_main_sxt_part                    (subs_main_sxt_part),
    .subs_main_sxt_part_vld                (subs_main_sxt_part_vld),
    .subs_main_sxt_part_rdy                (subs_main_sxt_part_rdy),

    .main_subs_ldg_cmd                     (main_subs_ldg_cmd),
    .main_subs_ldg_cmd_vld                 (main_subs_ldg_cmd_vld),
    .main_subs_ldg_cmd_rdy                 (main_subs_ldg_cmd_rdy),

    .main_subs_ldg_data                    (main_subs_ldg_data),
    .main_subs_ldg_data_vld                (main_subs_ldg_data_vld),
    .main_subs_ldg_data_rdy                (main_subs_ldg_data_rdy),

    .subs_main_proc                        (subs_main_side.proc),
    .main_subs_proc                        (main_subs_side.proc),

    .pep_error                             (subs_pep_entry_error),
    .pep_rif_info                          (subs_pep_entry_rif_info),
    .pep_rif_counter_inc                   (subs_pep_entry_rif_counter_inc)
  );

// ---------------------------------------------------------------------------------------------- --
// pe_pbs_with_ksk
// contains:
// * ksk_if
// * ksk_manager
// ---------------------------------------------------------------------------------------------- --
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
    .INST_FIFO_DEPTH       (PEP_INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  ) pe_pbs_with_ksk (
    .clk                    (prc_clk),
    .s_rst_n                (prc_srst_n),

    .reset_ksk_cache        (reset_ks),
    .reset_ksk_cache_done   (reset_ksk_cache_done),
    .ksk_mem_avail          (ksk_mem_avail),
    .ksk_mem_addr           (ksk_mem_addr),

    `HPU_AXI4_SHORT_RD_INSTANCE(ksk, ksk, _tmp, [KSK_PC-1:0])

    .inc_ksk_wr_ptr         (inc_ksk_wr_ptr),
    .inc_ksk_rd_ptr         (inc_ksk_rd_ptr),

    .ks_batch_cmd           (ks_batch_cmd),
    .ks_batch_cmd_avail     (ks_batch_cmd_avail),
    .ksk_if_batch_start_1h  (ksk_if_batch_start_1h),

    .ksk                    (ksk),
    .ksk_vld                (ksk_vld),
    .ksk_rdy                (ksk_rdy),

    .pep_error              (pep_ksk_error),
    .pep_rif_info           (pep_ksk_rif_info),
    .pep_rif_counter_inc    (pep_ksk_rif_counter_inc)
  );

// ---------------------------------------------------------------------------------------------- --
// pe_pbs_with_ksk
// contains:
// * pep_key_switch
// * pep_load_blwe
// ---------------------------------------------------------------------------------------------- --
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
    .INST_FIFO_DEPTH       (PEP_INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  ) pe_pbs_with_ks (
    .clk                      (prc_clk),
    .s_rst_n                  (prc_srst_n),

    .pep_regf_rd_req_vld      (pep_regf_rd_req_vld),
    .pep_regf_rd_req_rdy      (pep_regf_rd_req_rdy),
    .pep_regf_rd_req          (pep_regf_rd_req),

    .regf_pep_rd_data_avail   (regf_pep_rd_data_avail),
    .regf_pep_rd_data         (regf_pep_rd_data),
    .regf_pep_rd_last_word    (regf_pep_rd_last_word),
    .regf_pep_rd_is_body      (regf_pep_rd_is_body),
    .regf_pep_rd_last_mask    (regf_pep_rd_last_mask),

    .ksk                      (ksk),
    .ksk_vld                  (ksk_vld),
    .ksk_rdy                  (ksk_rdy),

    .seq_ldb_cmd              (seq_ldb_cmd),
    .seq_ldb_vld              (seq_ldb_vld),
    .seq_ldb_rdy              (seq_ldb_rdy),
    .ldb_seq_done             (ldb_seq_done),

    .ks_seq_cmd_enquiry       (ks_seq_cmd_enquiry),
    .seq_ks_cmd               (seq_ks_cmd),
    .seq_ks_cmd_avail         (seq_ks_cmd_avail),

    .ks_seq_result            (ks_seq_result),
    .ks_seq_result_vld        (ks_seq_result_vld),
    .ks_seq_result_rdy        (ks_seq_result_rdy),

    .ks_boram_wr_en           (ks_boram_wr_en),
    .ks_boram_data            (ks_boram_data),
    .ks_boram_pid             (ks_boram_pid),
    .ks_boram_parity          (ks_boram_parity),

    .inc_ksk_wr_ptr           (inc_ksk_wr_ptr),
    .inc_ksk_rd_ptr           (inc_ksk_rd_ptr),

    .ks_batch_cmd             (ks_batch_cmd),
    .ks_batch_cmd_avail       (ks_batch_cmd_avail),

    .reset_cache              (reset_ks),
    .mod_switch_mean_comp     (mod_switch_mean_comp),

    .pep_error                (pep_ks_error),
    .pep_rif_info             (pep_ks_rif_info),
    .pep_rif_counter_inc      (pep_ks_rif_counter_inc)
  );

endmodule
