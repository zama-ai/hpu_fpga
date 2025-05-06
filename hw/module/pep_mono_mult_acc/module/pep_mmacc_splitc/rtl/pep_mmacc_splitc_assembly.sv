// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module assembles pep_mmacc_splitc_main and pep_mmacc_split_subsidiary.
// It is used for verification.
// ==============================================================================================

module pep_mmacc_splitc_assembly
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import regf_common_param_pkg::*;
#(
  parameter  int RAM_LATENCY              = 2,
  parameter  int URAM_LATENCY             = 2,
  parameter  int SLR_LATENCY              = 2*3,    // Number of cycles for the other part to arrive.
  parameter  int PHYS_RAM_DEPTH           = 1024, // Physical RAM depth. Should be a power of 2
  localparam int MAIN_PSI                 = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV,
  localparam int SUBS_PSI                 = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV
)
(
  input  logic                                                   clk,        // clock
  input  logic                                                   s_rst_n,    // synchronous reset

  // ACC -> Decomposer
  output logic [ACC_DECOMP_COEF_NB-1:0]                          acc_decomp_data_avail,
  output logic                                                   acc_decomp_ctrl_avail,
  output logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0]             acc_decomp_data,
  output logic                                                   acc_decomp_sob,
  output logic                                                   acc_decomp_eob,
  output logic                                                   acc_decomp_sog,
  output logic                                                   acc_decomp_eog,
  output logic                                                   acc_decomp_sol,
  output logic                                                   acc_decomp_eol,
  output logic                                                   acc_decomp_soc,
  output logic                                                   acc_decomp_eoc,
  output logic [BPBS_ID_W-1:0]                                   acc_decomp_pbs_id,
  output logic                                                   acc_decomp_last_pbs,
  output logic                                                   acc_decomp_full_throughput,

  // NTT core -> ACC
  input  logic [PSI-1:0][R-1:0]                                  ntt_acc_data_avail,
  input  logic                                                   ntt_acc_ctrl_avail,
  input  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]                     ntt_acc_data,
  input  logic                                                   ntt_acc_sob,
  input  logic                                                   ntt_acc_eob,
  input  logic                                                   ntt_acc_sol,
  input  logic                                                   ntt_acc_eol,
  input  logic                                                   ntt_acc_sog,
  input  logic                                                   ntt_acc_eog,
  input  logic [BPBS_ID_W-1:0]                                   ntt_acc_pbs_id,

  // batch_cmd
  output logic [BR_BATCH_CMD_W-1:0]                              batch_cmd,
  output logic                                                   batch_cmd_avail,

  // Wr access to GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  input  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                     ldg_gram_main_wr_en,
  input  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] ldg_gram_main_wr_add,
  input  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]        ldg_gram_main_wr_data,

  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     ldg_gram_subs_wr_en,
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] ldg_gram_subs_wr_add,
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]        ldg_gram_subs_wr_data,

  output logic [GRAM_NB-1:0]                                     garb_ldg_main_avail_1h,
  output logic [GRAM_NB-1:0]                                     garb_ldg_subs_avail_1h,

  // SXT <-> regfile
  output logic                                                   sxt_regf_wr_req_vld,
  input  logic                                                   sxt_regf_wr_req_rdy,
  output logic [REGF_WR_REQ_W-1:0]                               sxt_regf_wr_req,

  output logic [REGF_COEF_NB-1:0]                                sxt_regf_wr_data_vld,
  input  logic [REGF_COEF_NB-1:0]                                sxt_regf_wr_data_rdy,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                   sxt_regf_wr_data,

  input  logic                                                   regf_sxt_wr_ack,

  // mmacc <-> pep_sequencer
  output logic                                                   pbs_seq_cmd_enquiry,
  input  logic [PBS_CMD_W-1:0]                                   seq_pbs_cmd,
  input  logic                                                   seq_pbs_cmd_avail,

  output logic                                                   sxt_seq_done,
  output logic [PID_W-1:0]                                       sxt_seq_done_pid,

  // From KS
  input  logic                                                   ks_boram_wr_en,
  input  logic [LWE_COEF_W-1:0]                                  ks_boram_data,
  input  logic [PID_W-1:0]                                       ks_boram_pid,
  input  logic                                                   ks_boram_parity,

  // BSK
  input  logic                                                   inc_bsk_wr_ptr,
  output logic                                                   inc_bsk_rd_ptr,

  // reset cache
  input  logic                                                   reset_cache,

  output pep_mmacc_error_t                                       mmacc_error,
  output pep_mmacc_counter_inc_t                                 mmacc_rif_counter_inc
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  generate
    if (SLR_LATENCY > 0 && SLR_LATENCY < 2) begin : __UNSUPPORTED_SLR_LATENCY_
      $fatal(1,"> ERROR: Unsupported SLR_LATENCY (%0d) value : should be 0 or >= 2", SLR_LATENCY);
    end
  endgenerate

  localparam SXT_SPLITC_COEF         = set_msplit_sxt_splitc_coef(MSPLIT_TYPE);

// ============================================================================================== --
// Signal
// ============================================================================================== --
  logic                                                   in_subs_main_ntt_acc_avail;
  logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]                in_subs_main_ntt_acc_data;
  logic                                                   in_subs_main_ntt_acc_sob;
  logic                                                   in_subs_main_ntt_acc_eob;
  logic                                                   in_subs_main_ntt_acc_sol;
  logic                                                   in_subs_main_ntt_acc_eol;
  logic                                                   in_subs_main_ntt_acc_sog;
  logic                                                   in_subs_main_ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                                   in_subs_main_ntt_acc_pbs_id;

  logic                                                   out_subs_main_ntt_acc_avail;
  logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]                out_subs_main_ntt_acc_data;
  logic                                                   out_subs_main_ntt_acc_sob;
  logic                                                   out_subs_main_ntt_acc_eob;
  logic                                                   out_subs_main_ntt_acc_sol;
  logic                                                   out_subs_main_ntt_acc_eol;
  logic                                                   out_subs_main_ntt_acc_sog;
  logic                                                   out_subs_main_ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                                   out_subs_main_ntt_acc_pbs_id;
  // main <-> subs : DRAM arbiter
  logic [GRAM_NB-1:0]                                     in_garb_feed_rot_avail_1h;
  logic [GRAM_NB-1:0]                                     in_garb_feed_dat_avail_1h;
  logic [GRAM_NB-1:0]                                     in_garb_acc_rd_avail_1h;
  logic [GRAM_NB-1:0]                                     in_garb_acc_wr_avail_1h;
  logic [GRAM_NB-1:0]                                     in_garb_sxt_avail_1h;
  logic [GRAM_NB-1:0]                                     in_garb_ldg_avail_1h;

  logic [GRAM_NB-1:0]                                     out_garb_feed_rot_avail_1h;
  logic [GRAM_NB-1:0]                                     out_garb_feed_dat_avail_1h;
  logic [GRAM_NB-1:0]                                     out_garb_acc_rd_avail_1h;
  logic [GRAM_NB-1:0]                                     out_garb_acc_wr_avail_1h;
  logic [GRAM_NB-1:0]                                     out_garb_sxt_avail_1h;
  logic [GRAM_NB-1:0]                                     out_garb_ldg_avail_1h;

  // main <-> subs : feed
  logic [MMACC_FEED_CMD_W-1:0]                            in_main_subs_feed_mcmd;
  logic                                                   in_main_subs_feed_mcmd_vld;
  logic                                                   in_main_subs_feed_mcmd_rdy;
  logic                                                   in_subs_main_feed_mcmd_ack;
  logic                                                   in_main_subs_feed_mcmd_ack_ack;

  logic [MMACC_FEED_CMD_W-1:0]                            out_main_subs_feed_mcmd;
  logic                                                   out_main_subs_feed_mcmd_vld;
  logic                                                   out_main_subs_feed_mcmd_rdy;
  logic                                                   out_subs_main_feed_mcmd_ack;
  logic                                                   out_main_subs_feed_mcmd_ack_ack;

  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                   in_main_subs_feed_data;
  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                   in_main_subs_feed_rot_data;
  logic                                                   in_main_subs_feed_data_avail;

  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                   out_main_subs_feed_data;
  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                   out_main_subs_feed_rot_data;
  logic                                                   out_main_subs_feed_data_avail;

  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]          in_main_subs_feed_part;
  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]          in_main_subs_feed_rot_part;
  logic                                                   in_main_subs_feed_part_avail;

  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]          out_main_subs_feed_part;
  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]          out_main_subs_feed_rot_part;
  logic                                                   out_main_subs_feed_part_avail;

  // main <-> subsidiary : SXT
  logic                                                   in_main_subs_sxt_cmd_vld;
  logic                                                   in_main_subs_sxt_cmd_rdy;
  logic [LWE_COEF_W-1:0]                                  in_main_subs_sxt_cmd_body;
  logic [MMACC_INTERN_CMD_W-1:0]                          in_main_subs_sxt_cmd_icmd;
  logic                                                   out_subs_main_sxt_cmd_ack;

  logic                                                   out_main_subs_sxt_cmd_vld;
  logic                                                   out_main_subs_sxt_cmd_rdy;
  logic [LWE_COEF_W-1:0]                                  out_main_subs_sxt_cmd_body;
  logic [MMACC_INTERN_CMD_W-1:0]                          out_main_subs_sxt_cmd_icmd;
  logic                                                   in_subs_main_sxt_cmd_ack;

  logic [SXT_SPLITC_COEF-1:0][MOD_Q_W-1:0]                in_subs_main_sxt_data_data;
  logic                                                   in_subs_main_sxt_data_vld;
  logic                                                   in_subs_main_sxt_data_rdy;

  logic [SXT_SPLITC_COEF-1:0][MOD_Q_W-1:0]                out_subs_main_sxt_data_data;
  logic                                                   out_subs_main_sxt_data_vld;
  logic                                                   out_subs_main_sxt_data_rdy;

  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]          in_subs_main_sxt_part_data;
  logic                                                   in_subs_main_sxt_part_vld;
  logic                                                   in_subs_main_sxt_part_rdy;

  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]          out_subs_main_sxt_part_data;
  logic                                                   out_subs_main_sxt_part_vld;
  logic                                                   out_subs_main_sxt_part_rdy;

// ============================================================================================== --
// Errors / inc
// ============================================================================================== --
  pep_mmacc_error_t       mmacc_errorD;
  pep_mmacc_counter_inc_t mmacc_rif_counter_incD;

  pep_mmacc_error_t       main_mmacc_error;
  pep_mmacc_error_t       subs_mmacc_error;
  pep_mmacc_counter_inc_t main_mmacc_rif_counter_inc;

  assign mmacc_errorD           = main_mmacc_error | subs_mmacc_error;
  assign mmacc_rif_counter_incD = main_mmacc_rif_counter_inc;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      mmacc_error           <= '0;
      mmacc_rif_counter_inc <= '0;
    end
    else begin
      mmacc_error           <= mmacc_errorD          ;
      mmacc_rif_counter_inc <= mmacc_rif_counter_incD;
    end

// ============================================================================================== --
// SLR
// ============================================================================================== --
  generate
    if (SLR_LATENCY == 0) begin : gen_no_slr_latency
      assign out_subs_main_ntt_acc_avail      = in_subs_main_ntt_acc_avail;
      assign out_subs_main_ntt_acc_data       = in_subs_main_ntt_acc_data;
      assign out_subs_main_ntt_acc_sob        = in_subs_main_ntt_acc_sob;
      assign out_subs_main_ntt_acc_eob        = in_subs_main_ntt_acc_eob;
      assign out_subs_main_ntt_acc_sol        = in_subs_main_ntt_acc_sol;
      assign out_subs_main_ntt_acc_eol        = in_subs_main_ntt_acc_eol;
      assign out_subs_main_ntt_acc_sog        = in_subs_main_ntt_acc_sog;
      assign out_subs_main_ntt_acc_eog        = in_subs_main_ntt_acc_eog;
      assign out_subs_main_ntt_acc_pbs_id     = in_subs_main_ntt_acc_pbs_id;

      assign out_garb_feed_rot_avail_1h       = in_garb_feed_rot_avail_1h;
      assign out_garb_feed_dat_avail_1h       = in_garb_feed_dat_avail_1h;
      assign out_garb_acc_rd_avail_1h         = in_garb_acc_rd_avail_1h;
      assign out_garb_acc_wr_avail_1h         = in_garb_acc_wr_avail_1h;
      assign out_garb_sxt_avail_1h            = in_garb_sxt_avail_1h;
      assign out_garb_ldg_avail_1h            = in_garb_ldg_avail_1h;

      assign out_main_subs_feed_mcmd          = in_main_subs_feed_mcmd;
      assign out_main_subs_feed_mcmd_vld      = in_main_subs_feed_mcmd_vld;
      assign in_main_subs_feed_mcmd_rdy       = out_main_subs_feed_mcmd_rdy;
      assign out_subs_main_feed_mcmd_ack      = in_subs_main_feed_mcmd_ack;
      assign out_main_subs_feed_mcmd_ack_ack  = in_main_subs_feed_mcmd_ack_ack;

      assign out_main_subs_feed_data          = in_main_subs_feed_data;
      assign out_main_subs_feed_rot_data      = in_main_subs_feed_rot_data;
      assign out_main_subs_feed_data_avail    = in_main_subs_feed_data_avail;

      assign out_main_subs_feed_part          = in_main_subs_feed_part;
      assign out_main_subs_feed_rot_part      = in_main_subs_feed_rot_part;
      assign out_main_subs_feed_part_avail    = in_main_subs_feed_part_avail;

      assign out_subs_main_sxt_cmd_ack        = in_subs_main_sxt_cmd_ack;

      assign out_main_subs_sxt_cmd_vld        = in_main_subs_sxt_cmd_vld;
      assign in_main_subs_sxt_cmd_rdy         = out_main_subs_sxt_cmd_rdy;
      assign out_main_subs_sxt_cmd_body       = in_main_subs_sxt_cmd_body;
      assign out_main_subs_sxt_cmd_icmd       = in_main_subs_sxt_cmd_icmd;

      assign out_subs_main_sxt_data_data      = in_subs_main_sxt_data_data;
      assign out_subs_main_sxt_data_vld       = in_subs_main_sxt_data_vld;
      assign in_subs_main_sxt_data_rdy        = out_subs_main_sxt_data_rdy;

      assign out_subs_main_sxt_part_data      = in_subs_main_sxt_part_data;
      assign out_subs_main_sxt_part_vld       = in_subs_main_sxt_part_vld;
      assign in_subs_main_sxt_part_rdy        = out_subs_main_sxt_part_rdy;

    end
    else begin : gen_slr_latency
      localparam int OUTWARD_SLR_LATENCY = SLR_LATENCY/2;
      localparam int RETURN_SLR_LATENCY  = SLR_LATENCY - OUTWARD_SLR_LATENCY;
      //== Subs -> main
      logic [RETURN_SLR_LATENCY-1:0][1+1-1:0] subs_main_ctrl_sr;
      logic [RETURN_SLR_LATENCY-1:0][1+1-1:0] subs_main_ctrl_srD;

      assign subs_main_ctrl_srD[0] = {in_subs_main_sxt_cmd_ack,
                                      in_subs_main_feed_mcmd_ack
                                      };

      assign {out_subs_main_sxt_cmd_ack,
              out_subs_main_feed_mcmd_ack} = subs_main_ctrl_sr[RETURN_SLR_LATENCY-1];

      logic [RETURN_SLR_LATENCY-1:0][MAIN_PSI*R*MOD_Q_W + 6 + BPBS_ID_W-1:0]   subs_main_ntt_acc_sr;
      logic [RETURN_SLR_LATENCY-1:0]                                           subs_main_ntt_acc_avail_sr;

      logic [RETURN_SLR_LATENCY-1:0][MAIN_PSI*R*MOD_Q_W + 6 + BPBS_ID_W-1:0]   subs_main_ntt_acc_srD;
      logic [RETURN_SLR_LATENCY-1:0]                                           subs_main_ntt_acc_avail_srD;

      assign subs_main_ntt_acc_srD[0]       = {in_subs_main_ntt_acc_data,
                                               in_subs_main_ntt_acc_sob,
                                               in_subs_main_ntt_acc_eob,
                                               in_subs_main_ntt_acc_sol,
                                               in_subs_main_ntt_acc_eol,
                                               in_subs_main_ntt_acc_sog,
                                               in_subs_main_ntt_acc_eog,
                                               in_subs_main_ntt_acc_pbs_id};
      assign subs_main_ntt_acc_avail_srD[0] = in_subs_main_ntt_acc_avail;

      assign {out_subs_main_ntt_acc_data,
              out_subs_main_ntt_acc_sob,
              out_subs_main_ntt_acc_eob,
              out_subs_main_ntt_acc_sol,
              out_subs_main_ntt_acc_eol,
              out_subs_main_ntt_acc_sog,
              out_subs_main_ntt_acc_eog,
              out_subs_main_ntt_acc_pbs_id} = subs_main_ntt_acc_sr[RETURN_SLR_LATENCY-1];
      assign out_subs_main_ntt_acc_avail = subs_main_ntt_acc_avail_sr[RETURN_SLR_LATENCY-1];

      //== main -> subs
      logic [OUTWARD_SLR_LATENCY-1:0][6*GRAM_NB-1:0]  garb_avail_1h_sr;

      logic [OUTWARD_SLR_LATENCY-1:0][6*GRAM_NB-1:0]  garb_avail_1h_srD;

      assign garb_avail_1h_srD[0] = {in_garb_feed_rot_avail_1h,
                                     in_garb_feed_dat_avail_1h,
                                     in_garb_acc_rd_avail_1h,
                                     in_garb_acc_wr_avail_1h,
                                     in_garb_sxt_avail_1h,
                                     in_garb_ldg_avail_1h};

      assign {out_garb_feed_rot_avail_1h,
              out_garb_feed_dat_avail_1h,
              out_garb_acc_rd_avail_1h,
              out_garb_acc_wr_avail_1h,
              out_garb_sxt_avail_1h,
              out_garb_ldg_avail_1h} = garb_avail_1h_sr[OUTWARD_SLR_LATENCY-1];


      logic [OUTWARD_SLR_LATENCY-1:0][1-1:0]              main_subs_ctrl_sr;

      logic [OUTWARD_SLR_LATENCY-1:0][1-1:0]              main_subs_ctrl_srD;

      assign main_subs_ctrl_srD[0] = {in_main_subs_feed_mcmd_ack_ack};

      assign {out_main_subs_feed_mcmd_ack_ack} = main_subs_ctrl_sr[OUTWARD_SLR_LATENCY-1];

      //== Complete sr
      if (RETURN_SLR_LATENCY > 1) begin
        assign subs_main_ctrl_srD[RETURN_SLR_LATENCY-1:1]          = subs_main_ctrl_sr[RETURN_SLR_LATENCY-2:0];
        assign subs_main_ntt_acc_srD[RETURN_SLR_LATENCY-1:1]       = subs_main_ntt_acc_sr[RETURN_SLR_LATENCY-2:0];
        assign subs_main_ntt_acc_avail_srD[RETURN_SLR_LATENCY-1:1] = subs_main_ntt_acc_avail_sr[RETURN_SLR_LATENCY-2:0];
      end
      if (OUTWARD_SLR_LATENCY > 1) begin
        assign garb_avail_1h_srD[OUTWARD_SLR_LATENCY-1:1]          = garb_avail_1h_sr[OUTWARD_SLR_LATENCY-2:0];
        assign main_subs_ctrl_srD[OUTWARD_SLR_LATENCY-1:1]         = main_subs_ctrl_sr[OUTWARD_SLR_LATENCY-2:0];
      end

      //== sr pipe
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          subs_main_ntt_acc_avail_sr <= '0;
          garb_avail_1h_sr           <= '0;
          subs_main_ctrl_sr          <= '0;
          main_subs_ctrl_sr          <= '0;
        end
        else begin
          subs_main_ntt_acc_avail_sr <= subs_main_ntt_acc_avail_srD;
          garb_avail_1h_sr           <= garb_avail_1h_srD;
          subs_main_ctrl_sr          <= subs_main_ctrl_srD;
          main_subs_ctrl_sr          <= main_subs_ctrl_srD;
        end

      always_ff @(posedge clk) begin
        subs_main_ntt_acc_sr <= subs_main_ntt_acc_srD;
      end

      //== with control flow
      fifo_element #(
        .WIDTH          (MMACC_FEED_CMD_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_feed_rcmd_fifo_element (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_main_subs_feed_mcmd),
        .in_vld  (in_main_subs_feed_mcmd_vld),
        .in_rdy  (in_main_subs_feed_mcmd_rdy),

        .out_data(out_main_subs_feed_mcmd),
        .out_vld (out_main_subs_feed_mcmd_vld),
        .out_rdy (out_main_subs_feed_mcmd_rdy)
      );

      fifo_element #(
        .WIDTH          (2 * MOD_Q_W*PSI/2*R),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_feed_data_fifo_element (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data ({in_main_subs_feed_data,in_main_subs_feed_rot_data}),
        .in_vld  (in_main_subs_feed_data_avail),
        .in_rdy  (/*UNUSED*/),

        .out_data({out_main_subs_feed_data,out_main_subs_feed_rot_data}),
        .out_vld (out_main_subs_feed_data_avail),
        .out_rdy (1'b1)
      );

      fifo_element #(
        .WIDTH          (2 * MOD_Q_W*PSI/MSPLIT_DIV*R),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_feed_part_fifo_element (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data ({in_main_subs_feed_part,in_main_subs_feed_rot_part}),
        .in_vld  (in_main_subs_feed_part_avail),
        .in_rdy  (/*UNUSED*/),

        .out_data({out_main_subs_feed_part,out_main_subs_feed_rot_part}),
        .out_vld (out_main_subs_feed_part_avail),
        .out_rdy (1'b1)
      );

      fifo_element #(
        .WIDTH          (LWE_COEF_W+MMACC_INTERN_CMD_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_sxt_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data ({in_main_subs_sxt_cmd_body,in_main_subs_sxt_cmd_icmd}),
        .in_vld  (in_main_subs_sxt_cmd_vld),
        .in_rdy  (in_main_subs_sxt_cmd_rdy),

        .out_data({out_main_subs_sxt_cmd_body,out_main_subs_sxt_cmd_icmd}),
        .out_vld (out_main_subs_sxt_cmd_vld),
        .out_rdy (out_main_subs_sxt_cmd_rdy)
      );

      fifo_element #(
        .WIDTH          (SXT_SPLITC_COEF*MOD_Q_W),
        .DEPTH          (RETURN_SLR_LATENCY),
        .TYPE_ARRAY     ({RETURN_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) subs_main_sxt_data_fifo_element (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_subs_main_sxt_data_data),
        .in_vld  (in_subs_main_sxt_data_vld),
        .in_rdy  (in_subs_main_sxt_data_rdy),

        .out_data(out_subs_main_sxt_data_data),
        .out_vld (out_subs_main_sxt_data_vld),
        .out_rdy (out_subs_main_sxt_data_rdy)
      );

      fifo_element #(
        .WIDTH          (PSI/MSPLIT_DIV*R*MOD_Q_W),
        .DEPTH          (RETURN_SLR_LATENCY),
        .TYPE_ARRAY     ({RETURN_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) subs_main_sxt_part_fifo_element (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_subs_main_sxt_part_data),
        .in_vld  (in_subs_main_sxt_part_vld),
        .in_rdy  (in_subs_main_sxt_part_rdy),

        .out_data(out_subs_main_sxt_part_data),
        .out_vld (out_subs_main_sxt_part_vld),
        .out_rdy (out_subs_main_sxt_part_rdy)
      );
    end
  endgenerate

// ============================================================================================== --
// main
// ============================================================================================== --
  pep_mmacc_splitc_main
  #(
    .RAM_LATENCY               (RAM_LATENCY),
    .URAM_LATENCY              (URAM_LATENCY),
    .PHYS_RAM_DEPTH            (PHYS_RAM_DEPTH)
  ) pep_mmacc_splitc_main (
    .clk                             (clk),
    .s_rst_n                         (s_rst_n),

    .reset_cache                     (reset_cache),

    .ldg_gram_wr_en                  (ldg_gram_main_wr_en),
    .ldg_gram_wr_add                 (ldg_gram_main_wr_add),
    .ldg_gram_wr_data                (ldg_gram_main_wr_data),

    .sxt_regf_wr_req_vld             (sxt_regf_wr_req_vld),
    .sxt_regf_wr_req_rdy             (sxt_regf_wr_req_rdy),
    .sxt_regf_wr_req                 (sxt_regf_wr_req),

    .sxt_regf_wr_data_vld            (sxt_regf_wr_data_vld),
    .sxt_regf_wr_data_rdy            (sxt_regf_wr_data_rdy),
    .sxt_regf_wr_data                (sxt_regf_wr_data),

    .regf_sxt_wr_ack                 (regf_sxt_wr_ack),

    .pbs_seq_cmd_enquiry             (pbs_seq_cmd_enquiry),
    .seq_pbs_cmd                     (seq_pbs_cmd),
    .seq_pbs_cmd_avail               (seq_pbs_cmd_avail),

    .sxt_seq_done                    (sxt_seq_done),
    .sxt_seq_done_pid                (sxt_seq_done_pid),

    .ks_boram_wr_en                  (ks_boram_wr_en),
    .ks_boram_data                   (ks_boram_data),
    .ks_boram_pid                    (ks_boram_pid),
    .ks_boram_parity                 (ks_boram_parity),

    .inc_bsk_wr_ptr                  (inc_bsk_wr_ptr),
    .inc_bsk_rd_ptr                  (inc_bsk_rd_ptr),

    .main_subs_garb_feed_rot_avail_1h(in_garb_feed_rot_avail_1h),
    .main_subs_garb_feed_dat_avail_1h(in_garb_feed_dat_avail_1h),
    .main_subs_garb_acc_rd_avail_1h  (in_garb_acc_rd_avail_1h),
    .main_subs_garb_acc_wr_avail_1h  (in_garb_acc_wr_avail_1h),
    .main_subs_garb_sxt_avail_1h     (in_garb_sxt_avail_1h),
    .main_subs_garb_ldg_avail_1h     (in_garb_ldg_avail_1h),

    .garb_ldg_avail_1h               (garb_ldg_main_avail_1h),

    .main_subs_feed_mcmd             (in_main_subs_feed_mcmd),
    .main_subs_feed_mcmd_vld         (in_main_subs_feed_mcmd_vld),
    .main_subs_feed_mcmd_rdy         (in_main_subs_feed_mcmd_rdy),
    .subs_main_feed_mcmd_ack         (out_subs_main_feed_mcmd_ack),
    .main_subs_feed_mcmd_ack_ack     (in_main_subs_feed_mcmd_ack_ack),

    .main_subs_feed_data             (in_main_subs_feed_data),
    .main_subs_feed_rot_data         (in_main_subs_feed_rot_data),
    .main_subs_feed_data_avail       (in_main_subs_feed_data_avail),

    .main_subs_feed_part             (in_main_subs_feed_part),
    .main_subs_feed_rot_part         (in_main_subs_feed_rot_part),
    .main_subs_feed_part_avail       (in_main_subs_feed_part_avail),

    .subs_main_ntt_acc_avail         (out_subs_main_ntt_acc_avail),
    .subs_main_ntt_acc_data          (out_subs_main_ntt_acc_data),
    .subs_main_ntt_acc_sob           (out_subs_main_ntt_acc_sob),
    .subs_main_ntt_acc_eob           (out_subs_main_ntt_acc_eob),
    .subs_main_ntt_acc_sol           (out_subs_main_ntt_acc_sol),
    .subs_main_ntt_acc_eol           (out_subs_main_ntt_acc_eol),
    .subs_main_ntt_acc_sog           (out_subs_main_ntt_acc_sog),
    .subs_main_ntt_acc_eog           (out_subs_main_ntt_acc_eog),
    .subs_main_ntt_acc_pbs_id        (out_subs_main_ntt_acc_pbs_id),

    .main_subs_sxt_cmd_vld           (in_main_subs_sxt_cmd_vld),
    .main_subs_sxt_cmd_rdy           (in_main_subs_sxt_cmd_rdy),
    .main_subs_sxt_cmd_body          (in_main_subs_sxt_cmd_body),
    .main_subs_sxt_cmd_icmd          (in_main_subs_sxt_cmd_icmd),
    .subs_main_sxt_cmd_ack           (out_subs_main_sxt_cmd_ack),

    .subs_main_sxt_data_data         (out_subs_main_sxt_data_data),
    .subs_main_sxt_data_vld          (out_subs_main_sxt_data_vld),
    .subs_main_sxt_data_rdy          (out_subs_main_sxt_data_rdy),

    .subs_main_sxt_part_data         (out_subs_main_sxt_part_data),
    .subs_main_sxt_part_vld          (out_subs_main_sxt_part_vld),
    .subs_main_sxt_part_rdy          (out_subs_main_sxt_part_rdy),

    .mmacc_error                     (main_mmacc_error),
    .mmacc_rif_counter_inc           (main_mmacc_rif_counter_inc),

    .batch_cmd                       (batch_cmd),
    .batch_cmd_avail                 (batch_cmd_avail)
  );

// ============================================================================================== --
// subsidiary
// ============================================================================================== --
  pep_mmacc_splitc_subsidiary
  #(
    .RAM_LATENCY               (RAM_LATENCY),
    .PHYS_RAM_DEPTH            (PHYS_RAM_DEPTH)
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

    .ntt_acc_data_avail              (ntt_acc_data_avail),
    .ntt_acc_ctrl_avail              (ntt_acc_ctrl_avail),
    .ntt_acc_data                    (ntt_acc_data),
    .ntt_acc_sob                     (ntt_acc_sob),
    .ntt_acc_eob                     (ntt_acc_eob),
    .ntt_acc_sol                     (ntt_acc_sol),
    .ntt_acc_eol                     (ntt_acc_eol),
    .ntt_acc_sog                     (ntt_acc_sog),
    .ntt_acc_eog                     (ntt_acc_eog),
    .ntt_acc_pbs_id                  (ntt_acc_pbs_id),

    .ldg_gram_wr_en                  (ldg_gram_subs_wr_en),
    .ldg_gram_wr_add                 (ldg_gram_subs_wr_add),
    .ldg_gram_wr_data                (ldg_gram_subs_wr_data),

    .garb_feed_rot_avail_1h          (out_garb_feed_rot_avail_1h),
    .garb_feed_dat_avail_1h          (out_garb_feed_dat_avail_1h),
    .garb_acc_rd_avail_1h            (out_garb_acc_rd_avail_1h),
    .garb_acc_wr_avail_1h            (out_garb_acc_wr_avail_1h),
    .garb_sxt_avail_1h               (out_garb_sxt_avail_1h),

    .main_subs_feed_mcmd             (out_main_subs_feed_mcmd),
    .main_subs_feed_mcmd_vld         (out_main_subs_feed_mcmd_vld),
    .main_subs_feed_mcmd_rdy         (out_main_subs_feed_mcmd_rdy),
    .subs_main_feed_mcmd_ack         (in_subs_main_feed_mcmd_ack),
    .main_subs_feed_mcmd_ack_ack     (out_main_subs_feed_mcmd_ack_ack),

    .main_subs_feed_data             (out_main_subs_feed_data),
    .main_subs_feed_rot_data         (out_main_subs_feed_rot_data),
    .main_subs_feed_data_avail       (out_main_subs_feed_data_avail),

    .main_subs_feed_part             (out_main_subs_feed_part),
    .main_subs_feed_rot_part         (out_main_subs_feed_rot_part),
    .main_subs_feed_part_avail       (out_main_subs_feed_part_avail),

    .subs_main_ntt_acc_avail         (in_subs_main_ntt_acc_avail),
    .subs_main_ntt_acc_data          (in_subs_main_ntt_acc_data),
    .subs_main_ntt_acc_sob           (in_subs_main_ntt_acc_sob),
    .subs_main_ntt_acc_eob           (in_subs_main_ntt_acc_eob),
    .subs_main_ntt_acc_sol           (in_subs_main_ntt_acc_sol),
    .subs_main_ntt_acc_eol           (in_subs_main_ntt_acc_eol),
    .subs_main_ntt_acc_sog           (in_subs_main_ntt_acc_sog),
    .subs_main_ntt_acc_eog           (in_subs_main_ntt_acc_eog),
    .subs_main_ntt_acc_pbs_id        (in_subs_main_ntt_acc_pbs_id),

    .main_subs_sxt_cmd_vld           (out_main_subs_sxt_cmd_vld),
    .main_subs_sxt_cmd_rdy           (out_main_subs_sxt_cmd_rdy),
    .main_subs_sxt_cmd_body          (out_main_subs_sxt_cmd_body),
    .main_subs_sxt_cmd_icmd          (out_main_subs_sxt_cmd_icmd),
    .subs_main_sxt_cmd_ack           (in_subs_main_sxt_cmd_ack),

    .subs_main_sxt_data_data         (in_subs_main_sxt_data_data),
    .subs_main_sxt_data_vld          (in_subs_main_sxt_data_vld),
    .subs_main_sxt_data_rdy          (in_subs_main_sxt_data_rdy),

    .subs_main_sxt_part_data         (in_subs_main_sxt_part_data),
    .subs_main_sxt_part_vld          (in_subs_main_sxt_part_vld),
    .subs_main_sxt_part_rdy          (in_subs_main_sxt_part_rdy),

    .mmacc_error                     (subs_mmacc_error)

  );


// ============================================================================================== --
// output
// ============================================================================================== --
  assign garb_ldg_subs_avail_1h = out_garb_ldg_avail_1h;

endmodule
