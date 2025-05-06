// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Assembly version of pe_pbs_with_entry. Used for debug.
// ==============================================================================================

module pe_pbs_with_entry_assembly
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
  parameter  int               SLR_LATENCY         = 2*6, // Set to 0 if not used.
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
  input  logic [axi_if_glwe_axi_pkg::AXI4_ADD_W-1:0]                   gid_offset,   // quasi static - GLWE address offset
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
  input  logic [LWE_COEF_W-1:0]                                        ks_boram_data,
  input  logic [PID_W-1:0]                                             ks_boram_pid,
  input  logic                                                         ks_boram_parity,

  //== Decomposer
  // Decomposer -> NTT
  output logic [PSI-1:0][R-1:0]                                        decomp_ntt_data_avail,
  output logic [PSI-1:0][R-1:0][PBS_B_W:0]                             decomp_ntt_data,
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
  input  logic [PSI-1:0][R-1:0]                                        decomp_ntt_data_rdy,
  input  logic                                                         decomp_ntt_ctrl_rdy,

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

  //== Control
  output logic                                                         bsk_if_batch_start_1h,
  output logic                                                         ksk_if_batch_start_1h,
  output logic [BR_BATCH_CMD_W-1:0]                                    br_batch_cmd,
  output logic                                                         br_batch_cmd_avail,
  input  logic                                                         inc_bsk_wr_ptr,
  output logic                                                         inc_bsk_rd_ptr,

  //== reset cache
  input  logic                                                         reset_cache,
  output logic                                                         reset_ks,

  //== To rif
  output pep_counter_inc_t                                             pep_rif_counter_inc,
  output pep_info_t                                                    pep_rif_info,
  output pep_error_t                                                   pep_error
);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int OUTWARD_SLR_LATENCY = SLR_LATENCY/2;
  localparam int RETURN_SLR_LATENCY  = SLR_LATENCY - OUTWARD_SLR_LATENCY;

  localparam int MAIN_PSI            = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV;
  localparam int SUBS_PSI            = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV;

// ============================================================================================== --
// Signals
// ============================================================================================== --
  //== main <-> subs
  // ModSW -> MMACC : from subs
  subsmain_acc_data_t                              in_subs_main_ntt_acc_modsw;
  logic                                            in_subs_main_ntt_acc_modsw_avail;

  subsmain_acc_data_t                              out_subs_main_ntt_acc_modsw;
  logic                                            out_subs_main_ntt_acc_modsw_avail;

  // main <-> subs : feed
  mainsubs_feed_cmd_t                              in_main_subs_feed_cmd;
  logic                                            in_main_subs_feed_cmd_vld;
  logic                                            in_main_subs_feed_cmd_rdy;

  mainsubs_feed_data_t                             in_main_subs_feed_data;
  logic                                            in_main_subs_feed_data_avail;

  mainsubs_feed_part_t                             in_main_subs_feed_part;
  logic                                            in_main_subs_feed_part_avail;

  mainsubs_feed_cmd_t                              out_main_subs_feed_cmd;
  logic                                            out_main_subs_feed_cmd_vld;
  logic                                            out_main_subs_feed_cmd_rdy;

  mainsubs_feed_data_t                             out_main_subs_feed_data;
  logic                                            out_main_subs_feed_data_avail;

  mainsubs_feed_part_t                             out_main_subs_feed_part;
  logic                                            out_main_subs_feed_part_avail;

  // main <-> subsidiary : SXT
  mainsubs_sxt_cmd_t                               in_main_subs_sxt_cmd;
  logic                                            in_main_subs_sxt_cmd_vld;
  logic                                            in_main_subs_sxt_cmd_rdy;

  subsmain_sxt_data_t                              in_subs_main_sxt_data;
  logic                                            in_subs_main_sxt_data_vld;
  logic                                            in_subs_main_sxt_data_rdy;

  subsmain_sxt_part_t                              in_subs_main_sxt_part;
  logic                                            in_subs_main_sxt_part_vld;
  logic                                            in_subs_main_sxt_part_rdy;

  mainsubs_sxt_cmd_t                               out_main_subs_sxt_cmd;
  logic                                            out_main_subs_sxt_cmd_vld;
  logic                                            out_main_subs_sxt_cmd_rdy;

  subsmain_sxt_data_t                              out_subs_main_sxt_data;
  logic                                            out_subs_main_sxt_data_vld;
  logic                                            out_subs_main_sxt_data_rdy;

  subsmain_sxt_part_t                              out_subs_main_sxt_part;
  logic                                            out_subs_main_sxt_part_vld;
  logic                                            out_subs_main_sxt_part_rdy;

  // main <-> subsidiary : LDG
  mainsubs_ldg_cmd_t                               in_main_subs_ldg_cmd;
  logic                                            in_main_subs_ldg_cmd_vld;
  logic                                            in_main_subs_ldg_cmd_rdy;

  mainsubs_ldg_data_t                              in_main_subs_ldg_data;
  logic                                            in_main_subs_ldg_data_vld;
  logic                                            in_main_subs_ldg_data_rdy;

  mainsubs_ldg_cmd_t                               out_main_subs_ldg_cmd;
  logic                                            out_main_subs_ldg_cmd_vld;
  logic                                            out_main_subs_ldg_cmd_rdy;

  mainsubs_ldg_data_t                              out_main_subs_ldg_data;
  logic                                            out_main_subs_ldg_data_vld;
  logic                                            out_main_subs_ldg_data_rdy;

  // main <-> subs : proc signals
  subsmain_proc_t                                  in_subs_main_proc;
  mainsubs_proc_t                                  in_main_subs_proc;

  subsmain_proc_t                                  out_subs_main_proc;
  mainsubs_proc_t                                  out_main_subs_proc;

// ============================================================================================== --
// Output
// ============================================================================================== --
  pep_counter_inc_t pep_rif_counter_incD;
  pep_info_t        pep_rif_infoD;
  pep_error_t       pep_errorD;

  pep_counter_inc_t main_pep_rif_counter_inc;
  pep_info_t        main_pep_rif_info;
  pep_error_t       main_pep_error;

  pep_counter_inc_t subs_pep_rif_counter_inc;
  pep_info_t        subs_pep_rif_info;
  pep_error_t       subs_pep_error;

  assign pep_rif_counter_incD = main_pep_rif_counter_inc | subs_pep_rif_counter_inc;
  assign pep_rif_infoD        = main_pep_rif_info        | subs_pep_rif_info;
  assign pep_errorD           = main_pep_error           | subs_pep_error;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pep_rif_counter_inc <= '0;
      pep_rif_info        <= '0;
      pep_error           <= '0;
    end
    else begin
      pep_rif_counter_inc <= pep_rif_counter_incD;
      pep_rif_info        <= pep_rif_infoD       ;
      pep_error           <= pep_errorD          ;
    end

// ============================================================================================== --
// SLR
// ============================================================================================== --
  generate
    if (SLR_LATENCY == 0) begin : gen_no_slr_latency
      assign out_subs_main_ntt_acc_modsw_avail      = in_subs_main_ntt_acc_modsw_avail;
      assign out_subs_main_ntt_acc_modsw            = in_subs_main_ntt_acc_modsw;

      assign out_main_subs_feed_cmd                 = in_main_subs_feed_cmd;
      assign out_main_subs_feed_cmd_vld             = in_main_subs_feed_cmd_vld;
      assign in_main_subs_feed_cmd_rdy              = out_main_subs_feed_cmd_rdy;

      assign out_main_subs_feed_data                = in_main_subs_feed_data;
      assign out_main_subs_feed_data_avail          = in_main_subs_feed_data_avail;

      assign out_main_subs_feed_part                = in_main_subs_feed_part;
      assign out_main_subs_feed_part_avail          = in_main_subs_feed_part_avail;

      assign out_main_subs_sxt_cmd                  = in_main_subs_sxt_cmd;
      assign out_main_subs_sxt_cmd_vld              = in_main_subs_sxt_cmd_vld;
      assign in_main_subs_sxt_cmd_rdy               = out_main_subs_sxt_cmd_rdy;

      assign out_subs_main_sxt_data                 = in_subs_main_sxt_data;
      assign out_subs_main_sxt_data_vld             = in_subs_main_sxt_data_vld;
      assign in_subs_main_sxt_data_rdy              = out_subs_main_sxt_data_rdy;

      assign out_subs_main_sxt_part                 = in_subs_main_sxt_part;
      assign out_subs_main_sxt_part_vld             = in_subs_main_sxt_part_vld;
      assign in_subs_main_sxt_part_rdy              = out_subs_main_sxt_part_rdy;

      assign out_main_subs_ldg_cmd                  = in_main_subs_ldg_cmd;
      assign out_main_subs_ldg_cmd_vld              = in_main_subs_ldg_cmd_vld;
      assign in_main_subs_ldg_cmd_rdy               = out_main_subs_ldg_cmd_rdy;

      assign out_main_subs_ldg_data                 = in_main_subs_ldg_data;
      assign out_main_subs_ldg_data_vld             = in_main_subs_ldg_data_vld;
      assign in_main_subs_ldg_data_rdy              = out_main_subs_ldg_data_rdy;

      assign out_subs_main_proc                     = in_subs_main_proc;
      assign out_main_subs_proc                     = in_main_subs_proc;
    end
    else begin : gen_slr_latency
      // main -> subs
      fifo_element #(
        .WIDTH          (MAINSUBS_FEED_CMD_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_fifo_element_0 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_main_subs_feed_cmd),
        .in_vld  (in_main_subs_feed_cmd_vld),
        .in_rdy  (in_main_subs_feed_cmd_rdy),

        .out_data(out_main_subs_feed_cmd),
        .out_vld (out_main_subs_feed_cmd_vld),
        .out_rdy (out_main_subs_feed_cmd_rdy)
      );

      fifo_element #(
        .WIDTH          (MAINSUBS_SXT_CMD_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_fifo_element_2 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_main_subs_sxt_cmd),
        .in_vld  (in_main_subs_sxt_cmd_vld),
        .in_rdy  (in_main_subs_sxt_cmd_rdy),

        .out_data(out_main_subs_sxt_cmd),
        .out_vld (out_main_subs_sxt_cmd_vld),
        .out_rdy (out_main_subs_sxt_cmd_rdy)
      );

      fifo_element #(
        .WIDTH          (MAINSUBS_LDG_CMD_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_fifo_element_3 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_main_subs_ldg_cmd),
        .in_vld  (in_main_subs_ldg_cmd_vld),
        .in_rdy  (in_main_subs_ldg_cmd_rdy),

        .out_data(out_main_subs_ldg_cmd),
        .out_vld (out_main_subs_ldg_cmd_vld),
        .out_rdy (out_main_subs_ldg_cmd_rdy)
      );

      fifo_element #(
        .WIDTH          (MAINSUBS_LDG_DATA_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_fifo_element_4 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_main_subs_ldg_data),
        .in_vld  (in_main_subs_ldg_data_vld),
        .in_rdy  (in_main_subs_ldg_data_rdy),

        .out_data(out_main_subs_ldg_data),
        .out_vld (out_main_subs_ldg_data_vld),
        .out_rdy (out_main_subs_ldg_data_rdy)
      );

      fifo_element #(
      .WIDTH          (MAINSUBS_PROC_W),
      .DEPTH          (OUTWARD_SLR_LATENCY),
      .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
      .DO_RESET_DATA  (1),
      .RESET_DATA_VAL (0)
      ) main_subs_fifo_element_1 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data ({in_main_subs_proc}),
        .in_vld  (1'b1),
        .in_rdy  (/*UNUSED*/),

        .out_data({out_main_subs_proc}),
        .out_vld (/*UNUSED*/),
        .out_rdy (1'b1)
      );

      fifo_element #(
        .WIDTH          (MAINSUBS_FEED_DATA_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({RETURN_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_fifo_element_5 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_main_subs_feed_data),
        .in_vld  (in_main_subs_feed_data_avail),
        .in_rdy  (/*UNUSED*/),

        .out_data(out_main_subs_feed_data),
        .out_vld (out_main_subs_feed_data_avail),
        .out_rdy (1'b1)
      );

      fifo_element #(
        .WIDTH          (MAINSUBS_FEED_PART_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({RETURN_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_fifo_element_6 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_main_subs_feed_part),
        .in_vld  (in_main_subs_feed_part_avail),
        .in_rdy  (/*UNUSED*/),

        .out_data(out_main_subs_feed_part),
        .out_vld (out_main_subs_feed_part_avail),
        .out_rdy (1'b1)
      );

      // subs -> main
      fifo_element #(
        .WIDTH          (SUBSMAIN_ACC_DATA_W),
        .DEPTH          (RETURN_SLR_LATENCY),
        .TYPE_ARRAY     ({RETURN_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) subs_main_fifo_element_0 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_subs_main_ntt_acc_modsw),
        .in_vld  (in_subs_main_ntt_acc_modsw_avail),
        .in_rdy  (/*UNUSED*/),

        .out_data(out_subs_main_ntt_acc_modsw),
        .out_vld (out_subs_main_ntt_acc_modsw_avail),
        .out_rdy (1'b1)
      );

      fifo_element #(
      .WIDTH          (SUBSMAIN_PROC_W),
      .DEPTH          (RETURN_SLR_LATENCY),
      .TYPE_ARRAY     ({RETURN_SLR_LATENCY{4'h1}}),
      .DO_RESET_DATA  (1),
      .RESET_DATA_VAL (0)
      ) subs_main_fifo_element_1 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data ({in_subs_main_proc}),
        .in_vld  (1'b1),
        .in_rdy  (/*UNUSED*/),

        .out_data({out_subs_main_proc}),
        .out_vld (/*UNUSED*/),
        .out_rdy (1'b1)
      );

      fifo_element #(
        .WIDTH          (SUBSMAIN_SXT_DATA_W),
        .DEPTH          (RETURN_SLR_LATENCY),
        .TYPE_ARRAY     ({RETURN_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) subs_main_fifo_element_3 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_subs_main_sxt_data),
        .in_vld  (in_subs_main_sxt_data_vld),
        .in_rdy  (in_subs_main_sxt_data_rdy),

        .out_data(out_subs_main_sxt_data),
        .out_vld (out_subs_main_sxt_data_vld),
        .out_rdy (out_subs_main_sxt_data_rdy)
      );

      fifo_element #(
        .WIDTH          (SUBSMAIN_SXT_PART_W),
        .DEPTH          (RETURN_SLR_LATENCY),
        .TYPE_ARRAY     ({RETURN_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) subs_main_fifo_element_4 (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_subs_main_sxt_part),
        .in_vld  (in_subs_main_sxt_part_vld),
        .in_rdy  (in_subs_main_sxt_part_rdy),

        .out_data(out_subs_main_sxt_part),
        .out_vld (out_subs_main_sxt_part_vld),
        .out_rdy (out_subs_main_sxt_part_rdy)
      );

    end
  endgenerate

// ============================================================================================== --
// main
// ============================================================================================== --
  pe_pbs_with_entry_main
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

    .TWD_IFNL_FILE_PREFIX  (TWD_IFNL_FILE_PREFIX),
    .TWD_PHRU_FILE_PREFIX  (TWD_PHRU_FILE_PREFIX),

    .INST_FIFO_DEPTH       (INST_FIFO_DEPTH),

    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),

    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  ) pe_pbs_with_entry_main (
    .clk                                   (clk),
    .s_rst_n                               (s_rst_n),

    .inst                                  (inst),
    .inst_vld                              (inst_vld),
    .inst_rdy                              (inst_rdy),

    .inst_ack                              (inst_ack),
    .inst_ack_br_loop                      (inst_ack_br_loop),
    .inst_load_blwe_ack                    (inst_load_blwe_ack),

    .pep_regf_wr_req_vld                   (pep_regf_wr_req_vld),
    .pep_regf_wr_req_rdy                   (pep_regf_wr_req_rdy),
    .pep_regf_wr_req                       (pep_regf_wr_req),

    .pep_regf_wr_data_vld                  (pep_regf_wr_data_vld),
    .pep_regf_wr_data_rdy                  (pep_regf_wr_data_rdy),
    .pep_regf_wr_data                      (pep_regf_wr_data),

    .regf_pep_wr_ack                       (regf_pep_wr_ack),

    .gid_offset                            (gid_offset),
    .use_bpip                              (use_bpip),
    .use_bpip_opportunism                  (use_bpip_opportunism),
    .bpip_timeout                          (bpip_timeout),

    .m_axi4_glwe_arid                      (m_axi4_glwe_arid),
    .m_axi4_glwe_araddr                    (m_axi4_glwe_araddr),
    .m_axi4_glwe_arlen                     (m_axi4_glwe_arlen),
    .m_axi4_glwe_arsize                    (m_axi4_glwe_arsize),
    .m_axi4_glwe_arburst                   (m_axi4_glwe_arburst),
    .m_axi4_glwe_arvalid                   (m_axi4_glwe_arvalid),
    .m_axi4_glwe_arready                   (m_axi4_glwe_arready),
    .m_axi4_glwe_rid                       (m_axi4_glwe_rid),
    .m_axi4_glwe_rdata                     (m_axi4_glwe_rdata),
    .m_axi4_glwe_rresp                     (m_axi4_glwe_rresp),
    .m_axi4_glwe_rlast                     (m_axi4_glwe_rlast),
    .m_axi4_glwe_rvalid                    (m_axi4_glwe_rvalid),
    .m_axi4_glwe_rready                    (m_axi4_glwe_rready),

    .seq_ldb_cmd                           (seq_ldb_cmd),
    .seq_ldb_vld                           (seq_ldb_vld),
    .seq_ldb_rdy                           (seq_ldb_rdy),
    .ldb_seq_done                          (ldb_seq_done),

    .ks_seq_cmd_enquiry                    (ks_seq_cmd_enquiry),
    .seq_ks_cmd                            (seq_ks_cmd),
    .seq_ks_cmd_avail                      (seq_ks_cmd_avail),

    .ks_seq_result                         (ks_seq_result),
    .ks_seq_result_vld                     (ks_seq_result_vld),
    .ks_seq_result_rdy                     (ks_seq_result_rdy),

    .ks_boram_wr_en                        (ks_boram_wr_en),
    .ks_boram_data                         (ks_boram_data),
    .ks_boram_pid                          (ks_boram_pid),
    .ks_boram_parity                       (ks_boram_parity),

    .subs_main_ntt_acc_modsw_avail         (out_subs_main_ntt_acc_modsw_avail),
    .subs_main_ntt_acc_modsw_data          (out_subs_main_ntt_acc_modsw.data),
    .subs_main_ntt_acc_modsw_sob           (out_subs_main_ntt_acc_modsw.sob),
    .subs_main_ntt_acc_modsw_eob           (out_subs_main_ntt_acc_modsw.eob),
    .subs_main_ntt_acc_modsw_sol           (out_subs_main_ntt_acc_modsw.sol),
    .subs_main_ntt_acc_modsw_eol           (out_subs_main_ntt_acc_modsw.eol),
    .subs_main_ntt_acc_modsw_sog           (out_subs_main_ntt_acc_modsw.sog),
    .subs_main_ntt_acc_modsw_eog           (out_subs_main_ntt_acc_modsw.eog),
    .subs_main_ntt_acc_modsw_pbs_id        (out_subs_main_ntt_acc_modsw.pbs_id),

    .bsk_if_batch_start_1h                 (bsk_if_batch_start_1h),
    .ksk_if_batch_start_1h                 (ksk_if_batch_start_1h),
    .inc_bsk_wr_ptr                        (inc_bsk_wr_ptr),
    .inc_bsk_rd_ptr                        (inc_bsk_rd_ptr),

    .br_batch_cmd                          (br_batch_cmd      ),
    .br_batch_cmd_avail                    (br_batch_cmd_avail),

    .reset_cache                           (reset_cache),
    .reset_ks                              (reset_ks),

    .main_subs_feed_cmd                    (in_main_subs_feed_cmd),
    .main_subs_feed_cmd_vld                (in_main_subs_feed_cmd_vld),
    .main_subs_feed_cmd_rdy                (in_main_subs_feed_cmd_rdy),

    .main_subs_feed_data                   (in_main_subs_feed_data),
    .main_subs_feed_data_avail             (in_main_subs_feed_data_avail),

    .main_subs_feed_part                   (in_main_subs_feed_part),
    .main_subs_feed_part_avail             (in_main_subs_feed_part_avail),

    .main_subs_sxt_cmd                     (in_main_subs_sxt_cmd),
    .main_subs_sxt_cmd_vld                 (in_main_subs_sxt_cmd_vld),
    .main_subs_sxt_cmd_rdy                 (in_main_subs_sxt_cmd_rdy),

    .subs_main_sxt_data                    (out_subs_main_sxt_data),
    .subs_main_sxt_data_vld                (out_subs_main_sxt_data_vld),
    .subs_main_sxt_data_rdy                (out_subs_main_sxt_data_rdy),

    .subs_main_sxt_part                    (out_subs_main_sxt_part),
    .subs_main_sxt_part_vld                (out_subs_main_sxt_part_vld),
    .subs_main_sxt_part_rdy                (out_subs_main_sxt_part_rdy),

    .main_subs_ldg_cmd                     (in_main_subs_ldg_cmd),
    .main_subs_ldg_cmd_vld                 (in_main_subs_ldg_cmd_vld),
    .main_subs_ldg_cmd_rdy                 (in_main_subs_ldg_cmd_rdy),

    .main_subs_ldg_data                    (in_main_subs_ldg_data),
    .main_subs_ldg_data_vld                (in_main_subs_ldg_data_vld),
    .main_subs_ldg_data_rdy                (in_main_subs_ldg_data_rdy),

    .subs_main_proc                        (out_subs_main_proc),
    .main_subs_proc                        (in_main_subs_proc),

    .pep_rif_info                          (main_pep_rif_info),
    .pep_rif_counter_inc                   (main_pep_rif_counter_inc),
    .pep_error                             (main_pep_error)
  );

// ============================================================================================== --
// subsidiary
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

    .TWD_IFNL_FILE_PREFIX  (TWD_IFNL_FILE_PREFIX),
    .TWD_PHRU_FILE_PREFIX  (TWD_PHRU_FILE_PREFIX),

    .INST_FIFO_DEPTH       (INST_FIFO_DEPTH),

    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),

    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  ) pe_pbs_with_entry_subsidiary (
    .clk                                   (clk),
    .s_rst_n                               (s_rst_n),

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
    .decomp_ntt_data_rdy                   (decomp_ntt_data_rdy),
    .decomp_ntt_ctrl_rdy                   (decomp_ntt_ctrl_rdy),

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

    .subs_main_ntt_acc_modsw_avail         (in_subs_main_ntt_acc_modsw_avail),
    .subs_main_ntt_acc_modsw_data          (in_subs_main_ntt_acc_modsw.data),
    .subs_main_ntt_acc_modsw_sob           (in_subs_main_ntt_acc_modsw.sob),
    .subs_main_ntt_acc_modsw_eob           (in_subs_main_ntt_acc_modsw.eob),
    .subs_main_ntt_acc_modsw_sol           (in_subs_main_ntt_acc_modsw.sol),
    .subs_main_ntt_acc_modsw_eol           (in_subs_main_ntt_acc_modsw.eol),
    .subs_main_ntt_acc_modsw_sog           (in_subs_main_ntt_acc_modsw.sog),
    .subs_main_ntt_acc_modsw_eog           (in_subs_main_ntt_acc_modsw.eog),
    .subs_main_ntt_acc_modsw_pbs_id        (in_subs_main_ntt_acc_modsw.pbs_id),

    .main_subs_feed_cmd                    (out_main_subs_feed_cmd),
    .main_subs_feed_cmd_vld                (out_main_subs_feed_cmd_vld),
    .main_subs_feed_cmd_rdy                (out_main_subs_feed_cmd_rdy),

    .main_subs_feed_data                   (out_main_subs_feed_data),
    .main_subs_feed_data_avail             (out_main_subs_feed_data_avail),

    .main_subs_feed_part                   (out_main_subs_feed_part),
    .main_subs_feed_part_avail             (out_main_subs_feed_part_avail),

    .main_subs_sxt_cmd                     (out_main_subs_sxt_cmd),
    .main_subs_sxt_cmd_vld                 (out_main_subs_sxt_cmd_vld),
    .main_subs_sxt_cmd_rdy                 (out_main_subs_sxt_cmd_rdy),

    .subs_main_sxt_data                    (in_subs_main_sxt_data),
    .subs_main_sxt_data_vld                (in_subs_main_sxt_data_vld),
    .subs_main_sxt_data_rdy                (in_subs_main_sxt_data_rdy),

    .subs_main_sxt_part                    (in_subs_main_sxt_part),
    .subs_main_sxt_part_vld                (in_subs_main_sxt_part_vld),
    .subs_main_sxt_part_rdy                (in_subs_main_sxt_part_rdy),

    .main_subs_ldg_cmd                     (out_main_subs_ldg_cmd),
    .main_subs_ldg_cmd_vld                 (out_main_subs_ldg_cmd_vld),
    .main_subs_ldg_cmd_rdy                 (out_main_subs_ldg_cmd_rdy),

    .main_subs_ldg_data                    (out_main_subs_ldg_data),
    .main_subs_ldg_data_vld                (out_main_subs_ldg_data_vld),
    .main_subs_ldg_data_rdy                (out_main_subs_ldg_data_rdy),

    .subs_main_proc                        (in_subs_main_proc),
    .main_subs_proc                        (out_main_subs_proc),

    .pep_rif_counter_inc                   (subs_pep_rif_counter_inc),
    .pep_error                             (subs_pep_error)
  );

endmodule

