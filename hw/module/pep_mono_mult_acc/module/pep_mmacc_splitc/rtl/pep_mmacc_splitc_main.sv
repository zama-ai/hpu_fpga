// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with :
// - the monomial multiplication (which consists in rotating the data)
// - build a factor for the CMUX
// - accumulate the external multiplication results with the corresponding data.
//
// NOTE : a FIFO on the NTT_ACC path is necessary, to bufferize the data, due to the
//   access to the GRAM: to avoid collision.
//
// Notation:
// GRAM : stands for GLWE RAM
// ==============================================================================================

module pep_mmacc_splitc_main
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
  parameter  int PHYS_RAM_DEPTH           = 1024, // Physical RAM depth. Should be a power of 2
  localparam int MAIN_PSI                 = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV,
  localparam int SXT_SPLITC_COEF          = set_msplit_sxt_splitc_coef(MSPLIT_TYPE)
)
(
  input                                                              clk,        // clock
  input                                                              s_rst_n,    // synchronous reset

  // reset cache
  input  logic                                                       reset_cache,

  // Wr access to GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  input  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                    ldg_gram_wr_en,
  input  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]ldg_gram_wr_add,
  input  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]       ldg_gram_wr_data,

  // SXT <-> regfile
  output logic                                                       sxt_regf_wr_req_vld,
  input  logic                                                       sxt_regf_wr_req_rdy,
  output logic [REGF_WR_REQ_W-1:0]                                   sxt_regf_wr_req,

  output logic [REGF_COEF_NB-1:0]                                    sxt_regf_wr_data_vld,
  input  logic [REGF_COEF_NB-1:0]                                    sxt_regf_wr_data_rdy,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                       sxt_regf_wr_data,

  input  logic                                                       regf_sxt_wr_ack,

  // mmacc <-> pep_sequencer
  output logic                                                       pbs_seq_cmd_enquiry,
  input  logic [PBS_CMD_W-1:0]                                       seq_pbs_cmd,
  input  logic                                                       seq_pbs_cmd_avail,

  output logic                                                       sxt_seq_done,
  output logic [PID_W-1:0]                                           sxt_seq_done_pid,

  // From KS
  input  logic                                                       ks_boram_wr_en,
  input  logic [MOD_KSK_W-1:0]                                       ks_boram_data,
  input  logic [PID_W-1:0]                                           ks_boram_pid,
  input  logic                                                       ks_boram_parity,

  input  logic                                                       seq_boram_corr_wr_en,
  input  logic [KS_CORR_W-1:0]                                       seq_boram_corr_data,
  input  logic [PID_W-1:0]                                           seq_boram_corr_pid,

  // BSK
  input  logic                                                       inc_bsk_wr_ptr,
  output logic                                                       inc_bsk_rd_ptr,

  // main <-> subs : GRAM arbiter
  output logic [GRAM_NB-1:0]                                         main_subs_garb_feed_rot_avail_1h,
  output logic [GRAM_NB-1:0]                                         main_subs_garb_feed_dat_avail_1h,
  output logic [GRAM_NB-1:0]                                         main_subs_garb_acc_rd_avail_1h,
  output logic [GRAM_NB-1:0]                                         main_subs_garb_acc_wr_avail_1h,
  output logic [GRAM_NB-1:0]                                         main_subs_garb_sxt_avail_1h,
  output logic [GRAM_NB-1:0]                                         main_subs_garb_ldg_avail_1h,

  output logic [GRAM_NB-1:0]                                         garb_ldg_avail_1h,

  // main <-> subs : feed
  output logic [MMACC_FEED_CMD_W-1:0]                                main_subs_feed_mcmd,
  output logic                                                       main_subs_feed_mcmd_vld,
  input  logic                                                       main_subs_feed_mcmd_rdy,
  input  logic                                                       subs_main_feed_mcmd_ack, // start process on this signal
  output logic                                                       main_subs_feed_mcmd_ack_ack,

  output logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                       main_subs_feed_data,
  output logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                       main_subs_feed_rot_data,
  output logic                                                       main_subs_feed_data_avail,

  output logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]              main_subs_feed_part,
  output logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]              main_subs_feed_rot_part,
  output logic                                                       main_subs_feed_part_avail,

  // main <-> subs : accumulate
  // NTT core -> ACC : to subs
  input  logic                                                       subs_main_ntt_acc_avail,
  input  logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]                    subs_main_ntt_acc_data,
  input  logic                                                       subs_main_ntt_acc_sob,
  input  logic                                                       subs_main_ntt_acc_eob,
  input  logic                                                       subs_main_ntt_acc_sol,
  input  logic                                                       subs_main_ntt_acc_eol,
  input  logic                                                       subs_main_ntt_acc_sog,
  input  logic                                                       subs_main_ntt_acc_eog,
  input  logic [BPBS_ID_W-1:0]                                       subs_main_ntt_acc_pbs_id,


  // main <-> subsidiary : SXT
  output logic                                                       main_subs_sxt_cmd_vld,
  input  logic                                                       main_subs_sxt_cmd_rdy,
  output logic [LWE_COEF_W-1:0]                                      main_subs_sxt_cmd_body,
  output logic [MMACC_INTERN_CMD_W-1:0]                              main_subs_sxt_cmd_icmd,
  input  logic                                                       subs_main_sxt_cmd_ack,

  input  logic [SXT_SPLITC_COEF-1:0][MOD_Q_W-1:0]                    subs_main_sxt_data_data,
  input  logic                                                       subs_main_sxt_data_vld,
  output logic                                                       subs_main_sxt_data_rdy,

  input  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]              subs_main_sxt_part_data,
  input  logic                                                       subs_main_sxt_part_vld,
  output logic                                                       subs_main_sxt_part_rdy,

  output pep_mmacc_error_t                                           mmacc_error,
  output pep_mmacc_counter_inc_t                                     mmacc_rif_counter_inc,

  // batch cmd
  output logic [BR_BATCH_CMD_W-1:0]                                  batch_cmd,
  output logic                                                       batch_cmd_avail

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
// Count from 0 to BATCH_NB included.
  localparam bit GRAM_IN_PIPE     = 1'b1;
  localparam bit GRAM_OUT_PIPE    = 1'b1;
  localparam int GRAM_DATA_LATENCY= RAM_LATENCY + GRAM_IN_PIPE + GRAM_OUT_PIPE + 1; // +1 : arbiter pipe

  // The FIFO_NTT_ACC, between the NTT output and the monomult, is used in unfold architecture
  // to solve conflicting accesses in GRAM. This FIFO bufferized the data, waiting for an arbitration slot to be
  // freed.
  localparam int FIFO_NTT_ACC_DEPTH = PHYS_RAM_DEPTH; // We assume that 1 PBS does not fill the entire processing pipeline.

  localparam int QPSI = PSI / MSPLIT_DIV;

  generate
    if (STG_ITER_NB * GLWE_K_P1 >= FIFO_NTT_ACC_DEPTH) begin : __UNSUPPORTED_FIFO_NTT_ACC_DEPTH_
      $fatal(1,"> ERROR: Infifo is not big enough to store a whole CT seen:%0d need:%0d",FIFO_NTT_ACC_DEPTH, STG_ITER_NB * GLWE_K_P1);
    end
    if (MSPLIT_DIV != 4) begin : __UNSUPPORTED_MSPLIT_DIV
      $fatal(1,"> ERROR: Unsupported MSPLIT_DIV (%0d) value. Should be equal to 4.",MSPLIT_DIV);
    end
    if (MSPLIT_MAIN_FACTOR < 1 || MSPLIT_MAIN_FACTOR > 3) begin : __UNSUPPORTED_MSPLIT_FACTOR
      $fatal(1,"> ERROR: Unsupported MSPLIT_MAIN_FACTOR (%0d) value. With MSPLIT_DIV equals 4, we support only 1,2 and 3 for the factor.",MSPLIT_DIV);
    end
  endgenerate

// ============================================================================================== --
// Errors / inc
// ============================================================================================== --
  pep_mmacc_error_t       mmacc_errorD;
  pep_mmacc_counter_inc_t mmacc_rif_counter_incD;

  logic                 gram_error;
  pep_mmacc_acc_error_t acc_error;
  logic                 flush_error;
  logic                 sfifo_ovf_error;
  logic                 sxt_cmd_wait_b_dur;
  logic                 sxt_req_dur;
  logic                 sxt_rcp_dur;

  always_comb begin
    mmacc_errorD                 = '0;
    mmacc_rif_counter_incD       = '0;

    mmacc_errorD.gram_acs        = gram_error;
    mmacc_errorD.acc             = acc_error;
    mmacc_errorD.flush_ovf       = flush_error;
    mmacc_errorD.sfifo_ovf       = sfifo_ovf_error;
    mmacc_errorD.feed_ofifo_ovf  = 1'b0; // TODO
    mmacc_rif_counter_incD.sxt_cmd_wait_b_dur = sxt_cmd_wait_b_dur;
    mmacc_rif_counter_incD.sxt_req_dur        = sxt_req_dur;
    mmacc_rif_counter_incD.sxt_rcp_dur        = sxt_rcp_dur;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      mmacc_error           <= '0;
      mmacc_rif_counter_inc <= '0;
    end
    else begin
      mmacc_error           <= mmacc_errorD;
      mmacc_rif_counter_inc <= mmacc_rif_counter_incD;
    end

// ============================================================================================== --
// GRAM arbiter
// ============================================================================================== --
  logic [GARB_CMD_W-1:0] feed_garb_req;
  logic                  feed_garb_req_vld;
  logic                  feed_garb_req_rdy;

  logic [GARB_CMD_W-1:0] acc_garb_req;
  logic                  acc_garb_req_vld;
  logic                  acc_garb_req_rdy;

  logic [GRAM_NB-1:0]    garb_feed_rot_avail_1h;
  logic [GRAM_NB-1:0]    garb_feed_dat_avail_1h;
  logic [GRAM_NB-1:0]    garb_acc_rd_avail_1h;
  logic [GRAM_NB-1:0]    garb_acc_wr_avail_1h;
  logic [GRAM_NB-1:0]    garb_sxt_avail_1h;

  pep_mmacc_gram_arb
  pep_mmacc_gram_arb (
    .clk                     (clk    ),
    .s_rst_n                 (s_rst_n),

    .mmfeed_garb_req         (feed_garb_req),
    .mmfeed_garb_req_vld     (feed_garb_req_vld),
    .mmfeed_garb_req_rdy     (feed_garb_req_rdy),

    .mmacc_garb_req          (acc_garb_req),
    .mmacc_garb_req_vld      (acc_garb_req_vld),
    .mmacc_garb_req_rdy      (acc_garb_req_rdy),

    .garb_mmfeed_grant       (/*UNUSED*/),
    .garb_mmacc_grant        (/*UNUSED*/),

    .garb_mmfeed_rot_avail_1h(garb_feed_rot_avail_1h),
    .garb_mmfeed_dat_avail_1h(garb_feed_dat_avail_1h),
    .garb_mmacc_rd_avail_1h  (garb_acc_rd_avail_1h),
    .garb_mmacc_wr_avail_1h  (garb_acc_wr_avail_1h),
    .garb_mmsxt_avail_1h     (garb_sxt_avail_1h),
    .garb_ldg_avail_1h       (garb_ldg_avail_1h)
  );

// ============================================================================================== --
// Arbitration signals
// ============================================================================================== --
  assign main_subs_garb_feed_rot_avail_1h = garb_feed_rot_avail_1h;
  assign main_subs_garb_feed_dat_avail_1h = garb_feed_dat_avail_1h;
  assign main_subs_garb_acc_rd_avail_1h   = garb_acc_rd_avail_1h;
  assign main_subs_garb_acc_wr_avail_1h   = garb_acc_wr_avail_1h;
  assign main_subs_garb_sxt_avail_1h      = garb_sxt_avail_1h;
  assign main_subs_garb_ldg_avail_1h      = garb_ldg_avail_1h;

// ============================================================================================== --
// Process
// ============================================================================================== --
// There are 3 processes:
// - the first one feeds the remaining processing pipe in data
// - the second one is in charge of the accumulation of the corresponding results.
// - the third one is in charge of the sample extraction.
// They work in parallel.
// Thanks to the gram arbiter they do not work on the same GRAM.
// Commands are exchanged via FIFOs.

  pbs_cmd_t                    ffifo_in_pcmd ;
  logic                        ffifo_in_vld;
  logic                        ffifo_in_rdy;
  pbs_cmd_t                    ffifo_out_pcmd;
  logic                        ffifo_out_vld;
  logic                        ffifo_out_rdy;

  mmacc_intern_cmd_t           afifo_in_icmd;
  logic                        afifo_in_vld;
  logic                        afifo_in_rdy;
  mmacc_intern_cmd_t           afifo_out_icmd;
  logic                        afifo_out_vld;
  logic                        afifo_out_rdy;

  mmacc_intern_cmd_t           sfifo_in_icmd;
  logic                        sfifo_in_vld;
  logic                        sfifo_in_rdy;
  mmacc_intern_cmd_t           sfifo_out_icmd;
  logic                        sfifo_out_vld;
  logic                        sfifo_out_rdy;

  logic [PID_W-1:0]            bfifo_in_pid;
  logic                        bfifo_in_parity;
  logic                        bfifo_in_vld;
  logic                        bfifo_in_rdy;
  logic [PID_W-1:0]            bfifo_out_pid;
  logic                        bfifo_out_parity;
  logic                        bfifo_out_vld;
  logic                        bfifo_out_rdy;

  assign ffifo_in_vld  = seq_pbs_cmd_avail;
  assign ffifo_in_pcmd = seq_pbs_cmd;

// pragma translate_off
  always_ff @(posedge clk)
    if (ffifo_in_vld)
      assert(ffifo_in_rdy)
      else begin
        $fatal(1,"%t > ERROR: Feed FIFO overflow (not ready when needed)", $time);
      end
// pragma translate_on

//-------------------------------------------------------------------------------------------------
// Feed FIFO
//-------------------------------------------------------------------------------------------------
  pbs_cmd_t                    ffifo_out_pcmd_tmp;
  logic                        ffifo_out_vld_tmp;
  logic                        ffifo_out_rdy_tmp;
  fifo_element #(
    .WIDTH          (PBS_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) feed_fifo_0 (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (ffifo_in_pcmd),
    .in_vld   (ffifo_in_vld),
    .in_rdy   (ffifo_in_rdy),

    .out_data (ffifo_out_pcmd_tmp),
    .out_vld  (ffifo_out_vld_tmp),
    .out_rdy  (ffifo_out_rdy_tmp)
  );

  fifo_element #(
    .WIDTH          (PBS_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h1),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) feed_fifo_1 (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (ffifo_out_pcmd_tmp),
    .in_vld   (ffifo_out_vld_tmp),
    .in_rdy   (ffifo_out_rdy_tmp),

    .out_data (ffifo_out_pcmd),
    .out_vld  (ffifo_out_vld),
    .out_rdy  (ffifo_out_rdy)
  );

//-- Enquiry
  // Build the very first enquiry after the reset
  // Set it some cycle after the reset. TOREVIEW
  localparam int ENQ_DEPTH = 8;
  logic [ENQ_DEPTH-1:0] enq_init;
  logic [ENQ_DEPTH-1:0] enq_initD;

  logic pbs_seq_cmd_enquiryD;

  assign enq_initD = enq_init << 1;
  assign pbs_seq_cmd_enquiryD = enq_init[ENQ_DEPTH-1] | (ffifo_out_vld_tmp & ffifo_out_rdy_tmp); // TOREVIEW

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      enq_init            <= 1;
      pbs_seq_cmd_enquiry <= 1'b0;
    end
    else begin
      enq_init            <= enq_initD;
      pbs_seq_cmd_enquiry <= pbs_seq_cmd_enquiryD;
    end

//-------------------------------------------------------------------------------------------------
// Accumulate FIFO
//-------------------------------------------------------------------------------------------------
  fifo_reg #(
    .WIDTH       (MMACC_INTERN_CMD_W),
    .DEPTH       (BATCH_PBS_NB+2), // TOREVIEW : should be enough, since the processing time of acc is almost the same as feed
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) acc_fifo (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (afifo_in_icmd),
    .in_vld   (afifo_in_vld),
    .in_rdy   (afifo_in_rdy),

    .out_data (afifo_out_icmd),
    .out_vld  (afifo_out_vld),
    .out_rdy  (afifo_out_rdy)
  );

// pragma translate_off
  logic _afifo_vld_not_rdy;

  always_ff @(posedge clk)
    if (!s_rst_n) _afifo_vld_not_rdy <= 1'b0;
    else          _afifo_vld_not_rdy <= (afifo_in_vld & ~afifo_in_rdy);

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (afifo_in_vld && !_afifo_vld_not_rdy) begin // print only on 1rst cycle
        assert(afifo_in_rdy)
        else begin
          $display("%t > INFO: afifo not ready! Maybe a sign that the number of PBS in the batch is not enough", $time);
        end
      end
    end
// pragma translate_on

//-------------------------------------------------------------------------------------------------
// Sample extract FIFO / Body RAM FIFO
//-------------------------------------------------------------------------------------------------
  logic                  sfifo_in_vld_tmp;
  logic                  sfifo_in_rdy_tmp;

  fifo_reg #(
    .WIDTH       (MMACC_INTERN_CMD_W),
    .DEPTH       (BATCH_PBS_NB),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) sxt_fifo (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (sfifo_in_icmd),
    .in_vld   (sfifo_in_vld),
    .in_rdy   (sfifo_in_rdy),

    .out_data (sfifo_out_icmd),
    .out_vld  (sfifo_out_vld),
    .out_rdy  (sfifo_out_rdy)
  );

  fifo_reg #(
    .WIDTH       (PID_W+1),
    .DEPTH       (BATCH_PBS_NB),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) boram_fifo (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  ({bfifo_in_parity,bfifo_in_pid}),
    .in_vld   (bfifo_in_vld),
    .in_rdy   (bfifo_in_rdy),

    .out_data ({bfifo_out_parity,bfifo_out_pid}),
    .out_vld  (bfifo_out_vld),
    .out_rdy  (bfifo_out_rdy)
  );

  // Fork between SXT and body RAM.
  assign sfifo_in_vld      = sfifo_in_vld_tmp & bfifo_in_rdy;
  assign bfifo_in_vld      = sfifo_in_vld_tmp & sfifo_in_rdy;
  assign sfifo_in_rdy_tmp  = bfifo_in_rdy & sfifo_in_rdy;;
  assign bfifo_in_pid      = sfifo_in_icmd.map_elt.pid.pid;
  assign bfifo_in_parity   = sfifo_in_icmd.map_elt.br_loop_parity;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (sfifo_in_vld) begin
        assert(sfifo_in_rdy)
        else begin
          $fatal(1,"%t > ERROR: sfifo overflow!", $time);
        end
      end
    end
// pragma translate_on

//-------------------------------------------------------------------------------------------------
// Feed process
//-------------------------------------------------------------------------------------------------
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][1:0]                     feed_gram_rd_en;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][1:0][GLWE_RAM_ADD_W-1:0] feed_gram_rd_add;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][1:0][MOD_Q_W-1:0]        gram_feed_rd_data;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][1:0]                     gram_feed_rd_data_avail;

  // From accumulator
  logic                                                        acc_feed_done;
  logic [BPBS_ID_W-1:0]                                        acc_feed_done_map_idx;

  logic                                                        br_loop_flush_done;

  pep_mmacc_splitc_main_feed #(
    .DATA_LATENCY         (GRAM_DATA_LATENCY)
  ) pep_mmacc_splitc_main_feed (
    .clk                           (clk),
    .s_rst_n                       (s_rst_n),

    .ffifo_feed_pcmd               (ffifo_out_pcmd),
    .ffifo_feed_vld                (ffifo_out_vld),
    .ffifo_feed_rdy                (ffifo_out_rdy),

    .subs_mcmd                     (main_subs_feed_mcmd),
    .subs_mcmd_vld                 (main_subs_feed_mcmd_vld),
    .subs_mcmd_rdy                 (main_subs_feed_mcmd_rdy),
    .subs_mcmd_ack                 (subs_main_feed_mcmd_ack),
    .subs_mcmd_loopback_ack        (main_subs_feed_mcmd_ack_ack),

    .feed_garb_req                 (feed_garb_req),
    .feed_garb_req_vld             (feed_garb_req_vld),
    .feed_garb_req_rdy             (feed_garb_req_rdy),

    .garb_feed_rot_avail_1h        (garb_feed_rot_avail_1h),
    .garb_feed_dat_avail_1h        (garb_feed_dat_avail_1h),

    .feed_afifo_icmd               (afifo_in_icmd),
    .feed_afifo_vld                (afifo_in_vld),
    .feed_afifo_rdy                (afifo_in_rdy),

    .acc_feed_done                 (acc_feed_done),
    .acc_feed_done_map_idx         (acc_feed_done_map_idx),

    .feed_gram_rd_en               (feed_gram_rd_en),
    .feed_gram_rd_add              (feed_gram_rd_add),
    .gram_feed_rd_data             (gram_feed_rd_data),
    .gram_feed_rd_data_avail       (gram_feed_rd_data_avail),

    .main_data                     (main_subs_feed_data),
    .main_rot_data                 (main_subs_feed_rot_data),
    .main_data_avail               (main_subs_feed_data_avail),

    .main_part                     (main_subs_feed_part),
    .main_rot_part                 (main_subs_feed_rot_part),
    .main_part_avail               (main_subs_feed_part_avail),

    .inc_bsk_wr_ptr                (inc_bsk_wr_ptr),

    .reset_cache                   (reset_cache),

    .br_loop_flush_done            (br_loop_flush_done),

    .batch_cmd                     (batch_cmd),
    .batch_cmd_avail               (batch_cmd_avail)
  );

//-------------------------------------------------------------------------------------------------
// Accumulate process
//-------------------------------------------------------------------------------------------------
  // GRAM access
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                     acc_gram_rd_en;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] acc_gram_rd_add;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]        gram_acc_rd_data;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                     gram_acc_rd_data_avail;

  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                     acc_gram_wr_en;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] acc_gram_wr_add;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]        acc_gram_wr_data;

  logic                                                     br_loop_proc_done;
  logic                                                     sfifo_in_avail;
  logic                                                     sfifo_ovf_errorD;

  assign sfifo_in_vld_tmp = sfifo_in_avail;
  assign sfifo_ovf_errorD = sfifo_in_avail & ~sfifo_in_rdy_tmp;

  always_ff @(posedge clk)
    if (!s_rst_n) sfifo_ovf_error <= 1'b0;
    else          sfifo_ovf_error <= sfifo_ovf_errorD;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(!sfifo_ovf_error)
      else begin
        $fatal(1,"%t > ERROR: sfifo overflows!",$time);
      end
    end
// pragma translate_on

  pep_mmacc_splitc_main_acc #(
    .DATA_LATENCY         (GRAM_DATA_LATENCY),
    .RAM_LATENCY          (URAM_LATENCY), // Use URAM
    .FIFO_NTT_ACC_DEPTH   (FIFO_NTT_ACC_DEPTH)
  ) pep_mmacc_splitc_main_acc (
    .clk                          (clk),
    .s_rst_n                      (s_rst_n),

    .main_ntt_acc_avail           (subs_main_ntt_acc_avail),
    .main_ntt_acc_data            (subs_main_ntt_acc_data),
    .main_ntt_acc_sob             (subs_main_ntt_acc_sob),
    .main_ntt_acc_eob             (subs_main_ntt_acc_eob),
    .main_ntt_acc_sol             (subs_main_ntt_acc_sol),
    .main_ntt_acc_eol             (subs_main_ntt_acc_eol),
    .main_ntt_acc_sog             (subs_main_ntt_acc_sog),
    .main_ntt_acc_eog             (subs_main_ntt_acc_eog),
    .main_ntt_acc_pbs_id          (subs_main_ntt_acc_pbs_id),

    .acc_garb_req                 (acc_garb_req),
    .acc_garb_req_vld             (acc_garb_req_vld),
    .acc_garb_req_rdy             (acc_garb_req_rdy),

    .garb_acc_rd_avail_1h         (garb_acc_rd_avail_1h),
    .garb_acc_wr_avail_1h         (garb_acc_wr_avail_1h),

    .acc_gram_rd_en               (acc_gram_rd_en),
    .acc_gram_rd_add              (acc_gram_rd_add),
    .gram_acc_rd_data             (gram_acc_rd_data),
    .gram_acc_rd_data_avail       (gram_acc_rd_data_avail),

    .acc_gram_wr_en               (acc_gram_wr_en),
    .acc_gram_wr_add              (acc_gram_wr_add),
    .acc_gram_wr_data             (acc_gram_wr_data),

    .afifo_acc_icmd               (afifo_out_icmd),
    .afifo_acc_vld                (afifo_out_vld),
    .afifo_acc_rdy                (afifo_out_rdy),

    .acc_sfifo_icmd               (sfifo_in_icmd),
    .acc_sfifo_avail              (sfifo_in_avail),

    .acc_feed_done                (acc_feed_done),
    .acc_feed_done_map_idx        (acc_feed_done_map_idx),

    .br_loop_proc_done            (br_loop_proc_done),

    .error                        (acc_error)
  );

//-------------------------------------------------------------------------------------------------
// Sample extract
//-------------------------------------------------------------------------------------------------
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                     sxt_gram_rd_en;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] sxt_gram_rd_add;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]        gram_sxt_rd_data;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                     gram_sxt_rd_data_avail;

  logic [LWE_COEF_W-1:0]                                    boram_sxt_data;
  logic                                                     boram_sxt_data_vld;
  logic                                                     boram_sxt_data_rdy;

  pep_mmacc_splitc_main_sxt
  #(
    .DATA_LATENCY         (GRAM_DATA_LATENCY)
  ) pep_mmacc_splitc_main_sxt (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .sfifo_sxt_icmd         (sfifo_out_icmd),
    .sfifo_sxt_vld          (sfifo_out_vld),
    .sfifo_sxt_rdy          (sfifo_out_rdy),

    .boram_sxt_data         (boram_sxt_data),
    .boram_sxt_data_vld     (boram_sxt_data_vld),
    .boram_sxt_data_rdy     (boram_sxt_data_rdy),

    .subs_cmd_vld           (main_subs_sxt_cmd_vld),
    .subs_cmd_rdy           (main_subs_sxt_cmd_rdy),
    .subs_cmd_body          (main_subs_sxt_cmd_body),
    .subs_cmd_icmd          (main_subs_sxt_cmd_icmd),
    .subs_cmd_ack           (subs_main_sxt_cmd_ack),

    .subs_data_data         (subs_main_sxt_data_data),
    .subs_data_vld          (subs_main_sxt_data_vld),
    .subs_data_rdy          (subs_main_sxt_data_rdy),

    .subs_part_data         (subs_main_sxt_part_data),
    .subs_part_vld          (subs_main_sxt_part_vld),
    .subs_part_rdy          (subs_main_sxt_part_rdy),

    .sxt_regf_wr_req_vld    (sxt_regf_wr_req_vld),
    .sxt_regf_wr_req_rdy    (sxt_regf_wr_req_rdy),
    .sxt_regf_wr_req        (sxt_regf_wr_req),

    .sxt_regf_wr_data_vld   (sxt_regf_wr_data_vld),
    .sxt_regf_wr_data_rdy   (sxt_regf_wr_data_rdy),
    .sxt_regf_wr_data       (sxt_regf_wr_data),

    .regf_sxt_wr_ack        (regf_sxt_wr_ack),

    .garb_sxt_avail_1h      (garb_sxt_avail_1h),

    .sxt_gram_rd_en         (sxt_gram_rd_en),
    .sxt_gram_rd_add        (sxt_gram_rd_add),
    .gram_sxt_rd_data       (gram_sxt_rd_data),
    .gram_sxt_rd_data_avail (gram_sxt_rd_data_avail),

    .sxt_seq_done           (sxt_seq_done),
    .sxt_seq_done_pid       (sxt_seq_done_pid),

    .sxt_rif_cmd_wait_b_dur (sxt_cmd_wait_b_dur),
    .sxt_rif_req_dur        (sxt_req_dur),
    .sxt_rif_rcp_dur        (sxt_rcp_dur)
  );

// ============================================================================================== --
// Body RAM
// ============================================================================================== --
  pep_mmacc_body_ram
  pep_mmacc_body_ram (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),
    .reset_cache            (reset_cache),

    .ks_boram_wr_en         (ks_boram_wr_en),
    .ks_boram_wr_data       (ks_boram_data),
    .ks_boram_wr_pid        (ks_boram_pid),
    .ks_boram_wr_parity     (ks_boram_parity),

    .seq_boram_corr_wr_en   (seq_boram_corr_wr_en),
    .seq_boram_corr_wr_data (seq_boram_corr_data),
    .seq_boram_corr_wr_pid  (seq_boram_corr_pid),

    .boram_rd_pid           (bfifo_out_pid),
    .boram_rd_parity        (bfifo_out_parity),
    .boram_rd_vld           (bfifo_out_vld),
    .boram_rd_rdy           (bfifo_out_rdy),

    .boram_sxt_data         (boram_sxt_data),
    .boram_sxt_data_vld     (boram_sxt_data_vld),
    .boram_sxt_data_rdy     (boram_sxt_data_rdy)
  );

// ============================================================================================== --
// GRAM
// ============================================================================================== --
  // The GRAM arbiter is in the subsidiary part.

  //-----------------------------------
  // GLWE RAM
  //-----------------------------------
  logic                          gram_errorD;
  logic [MSPLIT_MAIN_FACTOR-1:0] gram_error_l;
  assign gram_errorD = |gram_error_l;
  always_ff @(posedge clk)
    if (!s_rst_n) gram_error <= '0;
    else          gram_error <= gram_errorD;

  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          ldg_gram_wr_en_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      ldg_gram_wr_add_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]             ldg_gram_wr_data_l;

  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0]                     feed_gram_rd_en_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0][GLWE_RAM_ADD_W-1:0] feed_gram_rd_add_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0][MOD_Q_W-1:0]        gram_feed_rd_data_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0]                     gram_feed_rd_data_avail_l;

  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          acc_gram_rd_en_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      acc_gram_rd_add_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]             gram_acc_rd_data_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          gram_acc_rd_data_avail_l;

  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          acc_gram_wr_en_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      acc_gram_wr_add_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]             acc_gram_wr_data_l;

  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          sxt_gram_rd_en_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      sxt_gram_rd_add_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]             gram_sxt_rd_data_l;
  logic [MSPLIT_MAIN_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          gram_sxt_rd_data_avail_l;

  always_comb
    for (int i=0; i<MSPLIT_MAIN_FACTOR; i=i+1) begin
      for (int g=0; g<GRAM_NB; g=g+1) begin
        ldg_gram_wr_en_l[i][g]                   = ldg_gram_wr_en[g][i*QPSI+:QPSI];
        ldg_gram_wr_add_l[i][g]                  = ldg_gram_wr_add[g][i*QPSI+:QPSI];
        ldg_gram_wr_data_l[i][g]                 = ldg_gram_wr_data[g][i*QPSI+:QPSI];

        feed_gram_rd_en_l[i][g]                  = feed_gram_rd_en[g][i*QPSI+:QPSI];
        feed_gram_rd_add_l[i][g]                 = feed_gram_rd_add[g][i*QPSI+:QPSI];
        gram_feed_rd_data[g][i*QPSI+:QPSI]       = gram_feed_rd_data_l[i][g];
        gram_feed_rd_data_avail[g][i*QPSI+:QPSI] = gram_feed_rd_data_avail_l[i][g];

        acc_gram_rd_en_l[i][g]                   = acc_gram_rd_en[g][i*QPSI+:QPSI];
        acc_gram_rd_add_l[i][g]                  = acc_gram_rd_add[g][i*QPSI+:QPSI];
        gram_acc_rd_data[g][i*QPSI+:QPSI]        = gram_acc_rd_data_l[i][g];
        gram_acc_rd_data_avail[g][i*QPSI+:QPSI]  = gram_acc_rd_data_avail_l[i][g];

        acc_gram_wr_en_l[i][g]                   = acc_gram_wr_en[g][i*QPSI+:QPSI];
        acc_gram_wr_add_l[i][g]                  = acc_gram_wr_add[g][i*QPSI+:QPSI];
        acc_gram_wr_data_l[i][g]                 = acc_gram_wr_data[g][i*QPSI+:QPSI];

        sxt_gram_rd_en_l[i][g]                   = sxt_gram_rd_en[g][i*QPSI+:QPSI];
        sxt_gram_rd_add_l[i][g]                  = sxt_gram_rd_add[g][i*QPSI+:QPSI];
        gram_sxt_rd_data[g][i*QPSI+:QPSI]        = gram_sxt_rd_data_l[i][g];
        gram_sxt_rd_data_avail[g][i*QPSI+:QPSI]  = gram_sxt_rd_data_avail_l[i][g];
      end
    end

  generate
    for (genvar gen_i=0; gen_i<MSPLIT_MAIN_FACTOR; gen_i=gen_i+1) begin : gen_dpsi_loop
      pep_mmacc_glwe_ram
      #(
        .OP_W           (MOD_Q_W),
        .PSI            (QPSI),
        .R              (R),
        .RAM_LATENCY    (RAM_LATENCY),
        .GRAM_NB        (GRAM_NB),
        .GLWE_RAM_DEPTH (GLWE_RAM_DEPTH),
        .IN_PIPE        (GRAM_IN_PIPE),
        .OUT_PIPE       (GRAM_OUT_PIPE)
      ) qpsi__pep_mmacc_glwe_ram ( // Use this particular prefix for P&R script recognition
        .clk                    (clk),
        .s_rst_n                (s_rst_n),

        .ext_gram_wr_en         (ldg_gram_wr_en_l[gen_i]),
        .ext_gram_wr_add        (ldg_gram_wr_add_l[gen_i]),
        .ext_gram_wr_data       (ldg_gram_wr_data_l[gen_i]),

        .sxt_gram_rd_en         (sxt_gram_rd_en_l[gen_i]),
        .sxt_gram_rd_add        (sxt_gram_rd_add_l[gen_i]),
        .gram_sxt_rd_data       (gram_sxt_rd_data_l[gen_i]),
        .gram_sxt_rd_data_avail (gram_sxt_rd_data_avail_l[gen_i]),

        .feed_gram_rd_en        (feed_gram_rd_en_l[gen_i]),
        .feed_gram_rd_add       (feed_gram_rd_add_l[gen_i]),
        .gram_feed_rd_data      (gram_feed_rd_data_l[gen_i]),
        .gram_feed_rd_data_avail(gram_feed_rd_data_avail_l[gen_i]),

        .acc_gram_rd_en         (acc_gram_rd_en_l[gen_i]),
        .acc_gram_rd_add        (acc_gram_rd_add_l[gen_i]),
        .gram_acc_rd_data       (gram_acc_rd_data_l[gen_i]),
        .gram_acc_rd_data_avail (gram_acc_rd_data_avail_l[gen_i]),

        .acc_gram_wr_en         (acc_gram_wr_en_l[gen_i]),
        .acc_gram_wr_add        (acc_gram_wr_add_l[gen_i]),
        .acc_gram_wr_data       (acc_gram_wr_data_l[gen_i]),

        .error                  (gram_error_l[gen_i])
      );
    end // gen_dpsi_loop
  endgenerate

// ============================================================================================== --
// Inc BSK read pointer
// ============================================================================================== --
  logic br_loop_flush_done_vld;
  logic br_loop_flush_done_rdy;
  logic inc_bsk_rd_ptrD;

  common_lib_pulse_to_rdy_vld
  #(
    .FIFO_DEPTH (2) // TOREVIEW
  ) common_lib_pulse_to_rdy_vld (
    .clk (clk),
    .s_rst_n  (s_rst_n),

    .in_pulse (br_loop_flush_done),

    .out_vld  (br_loop_flush_done_vld),
    .out_rdy  (br_loop_flush_done_rdy),

    .error    (flush_error)
  );

  assign inc_bsk_rd_ptrD        = br_loop_proc_done | br_loop_flush_done_vld;
  assign br_loop_flush_done_rdy = ~br_loop_proc_done;

  always_ff @(posedge clk)
    if (!s_rst_n) inc_bsk_rd_ptr <= '0;
    else          inc_bsk_rd_ptr <= inc_bsk_rd_ptrD;

endmodule
