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

module pep_mmacc_splitc_subsidiary
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import regf_common_param_pkg::*;
#(
  parameter  int RAM_LATENCY              = 2,
  parameter  int URAM_LATENCY             = 3,
  parameter  int PHYS_RAM_DEPTH           = 1024, // Physical RAM depth. Should be a power of 2
  localparam int SUBS_PSI                 = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV,
  localparam int MAIN_PSI                 = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV,
  localparam int SXT_SPLITC_COEF          = set_msplit_sxt_splitc_coef(MSPLIT_TYPE)
)
(
  input                                                              clk,        // clock
  input                                                              s_rst_n,    // synchronous reset

  // Output data
  output logic [ACC_DECOMP_COEF_NB-1:0]                              acc_decomp_data_avail,
  output logic                                                       acc_decomp_ctrl_avail,
  output logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0]                 acc_decomp_data,
  output logic                                                       acc_decomp_sob,
  output logic                                                       acc_decomp_eob,
  output logic                                                       acc_decomp_sog,
  output logic                                                       acc_decomp_eog,
  output logic                                                       acc_decomp_sol,
  output logic                                                       acc_decomp_eol,
  output logic                                                       acc_decomp_soc,
  output logic                                                       acc_decomp_eoc,
  output logic [BPBS_ID_W-1:0]                                       acc_decomp_pbs_id,
  output logic                                                       acc_decomp_last_pbs,
  output logic                                                       acc_decomp_full_throughput,

  // NTT core -> ACC
  input  logic [PSI-1:0][R-1:0]                                      ntt_acc_data_avail,
  input  logic                                                       ntt_acc_ctrl_avail,
  input  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]                         ntt_acc_data,
  input  logic                                                       ntt_acc_sob,
  input  logic                                                       ntt_acc_eob,
  input  logic                                                       ntt_acc_sol,
  input  logic                                                       ntt_acc_eol,
  input  logic                                                       ntt_acc_sog,
  input  logic                                                       ntt_acc_eog,
  input  logic [BPBS_ID_W-1:0]                                       ntt_acc_pbs_id,

  // Wr access to GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                    ldg_gram_wr_en,
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]ldg_gram_wr_add,
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]       ldg_gram_wr_data,

  // main <-> subs : DRAM arbiter
  input  logic [GRAM_NB-1:0]                                         garb_feed_rot_avail_1h,
  input  logic [GRAM_NB-1:0]                                         garb_feed_dat_avail_1h,
  input  logic [GRAM_NB-1:0]                                         garb_acc_rd_avail_1h,
  input  logic [GRAM_NB-1:0]                                         garb_acc_wr_avail_1h,
  input  logic [GRAM_NB-1:0]                                         garb_sxt_avail_1h,

  // main <-> subs : feed
  input  logic [MMACC_FEED_CMD_W-1:0]                                main_subs_feed_mcmd,
  input  logic                                                       main_subs_feed_mcmd_vld,
  output logic                                                       main_subs_feed_mcmd_rdy,
  output logic                                                       subs_main_feed_mcmd_ack,
  input  logic                                                       main_subs_feed_mcmd_ack_ack,

  input  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                       main_subs_feed_data,
  input  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                       main_subs_feed_rot_data,
  input  logic                                                       main_subs_feed_data_avail,

  input  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]              main_subs_feed_part,
  input  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]              main_subs_feed_rot_part,
  input  logic                                                       main_subs_feed_part_avail,

  // main <-> subs : accumulate
  // NTT core -> ACC : from main
  output logic                                                       subs_main_ntt_acc_avail,
  output logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]                    subs_main_ntt_acc_data,
  output logic                                                       subs_main_ntt_acc_sob,
  output logic                                                       subs_main_ntt_acc_eob,
  output logic                                                       subs_main_ntt_acc_sol,
  output logic                                                       subs_main_ntt_acc_eol,
  output logic                                                       subs_main_ntt_acc_sog,
  output logic                                                       subs_main_ntt_acc_eog,
  output logic [BPBS_ID_W-1:0]                                       subs_main_ntt_acc_pbs_id,

  // main <-> subsidiary : SXT
  input  logic                                                       main_subs_sxt_cmd_vld,
  output logic                                                       main_subs_sxt_cmd_rdy,
  input  logic [LWE_COEF_W-1:0]                                      main_subs_sxt_cmd_body,
  input  logic [MMACC_INTERN_CMD_W-1:0]                              main_subs_sxt_cmd_icmd,
  output logic                                                       subs_main_sxt_cmd_ack,

  output logic [SXT_SPLITC_COEF-1:0][MOD_Q_W-1:0]                    subs_main_sxt_data_data,
  output logic                                                       subs_main_sxt_data_vld,
  input  logic                                                       subs_main_sxt_data_rdy,

  output logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]              subs_main_sxt_part_data,
  output logic                                                       subs_main_sxt_part_vld,
  input  logic                                                       subs_main_sxt_part_rdy,

  output pep_mmacc_error_t                                           mmacc_error
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
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
    if (MSPLIT_SUBS_FACTOR < 1 || MSPLIT_SUBS_FACTOR > 3) begin : __UNSUPPORTED_MSPLIT_FACTOR
      $fatal(1,"> ERROR: Unsupported MSPLIT_SUBS_FACTOR (%0d) value. With MSPLIT_DIV equals 4, we support only 1,2 and 3 for the factor.",MSPLIT_DIV);
    end
  endgenerate

// ============================================================================================== --
// Error
// ============================================================================================== --
  pep_mmacc_error_t     mmacc_errorD;

  pep_mmacc_acc_error_t acc_error;
  logic                 gram_error;

  always_comb begin
    mmacc_errorD          = '0;

    mmacc_errorD.acc      = acc_error;
    mmacc_errorD.gram_acs = gram_error;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) mmacc_error <= '0;
    else          mmacc_error <= mmacc_errorD;

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
// In subsidiary, there is only the FIFO between feed and acc.

  mmacc_intern_cmd_t           afifo_in_icmd;
  logic                        afifo_in_vld;
  logic                        afifo_in_rdy;
  mmacc_intern_cmd_t           afifo_out_icmd;
  logic                        afifo_out_vld;
  logic                        afifo_out_rdy;

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
// Feed process
//-------------------------------------------------------------------------------------------------
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][1:0]                     feed_gram_rd_en;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][1:0][GLWE_RAM_ADD_W-1:0] feed_gram_rd_add;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][1:0][MOD_Q_W-1:0]        gram_feed_rd_data;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][1:0]                     gram_feed_rd_data_avail;

  // From accumulator
  logic                                                          acc_feed_done;
  logic [BPBS_ID_W-1:0]                                          acc_feed_done_map_idx;

  pep_mmacc_splitc_subs_feed #(
    .DATA_LATENCY         (GRAM_DATA_LATENCY)
  ) pep_mmacc_splitc_subs_feed (
    .clk                           (clk),
    .s_rst_n                       (s_rst_n),

    .subs_mcmd                     (main_subs_feed_mcmd),
    .subs_mcmd_vld                 (main_subs_feed_mcmd_vld),
    .subs_mcmd_rdy                 (main_subs_feed_mcmd_rdy),
    .subs_mcmd_loopback            (subs_main_feed_mcmd_ack),
    .subs_mcmd_ack_ack             (main_subs_feed_mcmd_ack_ack),

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

    .acc_decomp_data_avail         (acc_decomp_data_avail),
    .acc_decomp_ctrl_avail         (acc_decomp_ctrl_avail),
    .acc_decomp_data               (acc_decomp_data),
    .acc_decomp_sob                (acc_decomp_sob),
    .acc_decomp_eob                (acc_decomp_eob),
    .acc_decomp_sog                (acc_decomp_sog),
    .acc_decomp_eog                (acc_decomp_eog),
    .acc_decomp_sol                (acc_decomp_sol),
    .acc_decomp_eol                (acc_decomp_eol),
    .acc_decomp_soc                (acc_decomp_soc),
    .acc_decomp_eoc                (acc_decomp_eoc),
    .acc_decomp_pbs_id             (acc_decomp_pbs_id),
    .acc_decomp_last_pbs           (acc_decomp_last_pbs),
    .acc_decomp_full_throughput    (acc_decomp_full_throughput)
  );

//-------------------------------------------------------------------------------------------------
// Accumulate process
//-------------------------------------------------------------------------------------------------
  // GRAM access
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     acc_gram_rd_en;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] acc_gram_rd_add;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]        gram_acc_rd_data;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     gram_acc_rd_data_avail;

  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     acc_gram_wr_en;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] acc_gram_wr_add;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]        acc_gram_wr_data;

  pep_mmacc_splitc_subs_acc #(
    .DATA_LATENCY         (GRAM_DATA_LATENCY),
    .RAM_LATENCY          (URAM_LATENCY), // Use URAM
    .FIFO_NTT_ACC_DEPTH   (FIFO_NTT_ACC_DEPTH)
  ) pep_mmacc_splitc_subs_acc (
    .clk                          (clk),
    .s_rst_n                      (s_rst_n),

    .ntt_acc_data_avail           (ntt_acc_data_avail),
    .ntt_acc_ctrl_avail           (ntt_acc_ctrl_avail),
    .ntt_acc_data                 (ntt_acc_data),
    .ntt_acc_sob                  (ntt_acc_sob),
    .ntt_acc_eob                  (ntt_acc_eob),
    .ntt_acc_sol                  (ntt_acc_sol),
    .ntt_acc_eol                  (ntt_acc_eol),
    .ntt_acc_sog                  (ntt_acc_sog),
    .ntt_acc_eog                  (ntt_acc_eog),
    .ntt_acc_pbs_id               (ntt_acc_pbs_id),

    .main_ntt_acc_avail           (subs_main_ntt_acc_avail),
    .main_ntt_acc_data            (subs_main_ntt_acc_data),
    .main_ntt_acc_sob             (subs_main_ntt_acc_sob),
    .main_ntt_acc_eob             (subs_main_ntt_acc_eob),
    .main_ntt_acc_sol             (subs_main_ntt_acc_sol),
    .main_ntt_acc_eol             (subs_main_ntt_acc_eol),
    .main_ntt_acc_sog             (subs_main_ntt_acc_sog),
    .main_ntt_acc_eog             (subs_main_ntt_acc_eog),
    .main_ntt_acc_pbs_id          (subs_main_ntt_acc_pbs_id),

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

    .acc_feed_done                (acc_feed_done),
    .acc_feed_done_map_idx        (acc_feed_done_map_idx),

    .br_loop_proc_done            (), /*UNUSED*/
    .subs_error                   (acc_error)
  );

//-------------------------------------------------------------------------------------------------
// Sample extract
//-------------------------------------------------------------------------------------------------
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     sxt_gram_rd_en;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] sxt_gram_rd_add;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]        gram_sxt_rd_data;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     gram_sxt_rd_data_avail;

  pep_mmacc_splitc_subs_sxt
  #(
    .DATA_LATENCY         (GRAM_DATA_LATENCY)
  ) pep_mmacc_splitc_subs_sxt (
    .clk                     (clk),
    .s_rst_n                 (s_rst_n),

    .subs_cmd_vld            (main_subs_sxt_cmd_vld),
    .subs_cmd_rdy            (main_subs_sxt_cmd_rdy),
    .subs_cmd_body           (main_subs_sxt_cmd_body),
    .subs_cmd_icmd           (main_subs_sxt_cmd_icmd),
    .subs_cmd_ack            (subs_main_sxt_cmd_ack),

    .subs_data_data          (subs_main_sxt_data_data),
    .subs_data_vld           (subs_main_sxt_data_vld),
    .subs_data_rdy           (subs_main_sxt_data_rdy),

    .subs_part_data          (subs_main_sxt_part_data),
    .subs_part_vld           (subs_main_sxt_part_vld),
    .subs_part_rdy           (subs_main_sxt_part_rdy),

    .garb_sxt_avail_1h       (garb_sxt_avail_1h),

    .sxt_gram_rd_en          (sxt_gram_rd_en),
    .sxt_gram_rd_add         (sxt_gram_rd_add),
    .gram_sxt_rd_data        (gram_sxt_rd_data),
    .gram_sxt_rd_data_avail  (gram_sxt_rd_data_avail),

    .sxt_rif_req_dur         (/*UNUSED*/) // TODO
  );

// ============================================================================================== --
// GRAM
// ============================================================================================== --
  logic                          gram_errorD;
  logic [MSPLIT_SUBS_FACTOR-1:0] gram_error_l;
  assign gram_errorD = |gram_error_l;
  always_ff @(posedge clk)
    if (!s_rst_n) gram_error <= '0;
    else          gram_error <= gram_errorD;

  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          ldg_gram_wr_en_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      ldg_gram_wr_add_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]             ldg_gram_wr_data_l;

  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0]                     feed_gram_rd_en_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0][GLWE_RAM_ADD_W-1:0] feed_gram_rd_add_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0][MOD_Q_W-1:0]        gram_feed_rd_data_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0]                     gram_feed_rd_data_avail_l;

  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          acc_gram_rd_en_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      acc_gram_rd_add_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]             gram_acc_rd_data_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          gram_acc_rd_data_avail_l;

  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          acc_gram_wr_en_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      acc_gram_wr_add_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]             acc_gram_wr_data_l;

  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          sxt_gram_rd_en_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      sxt_gram_rd_add_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]             gram_sxt_rd_data_l;
  logic [MSPLIT_SUBS_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                          gram_sxt_rd_data_avail_l;

  always_comb
    for (int i=0; i<MSPLIT_SUBS_FACTOR; i=i+1) begin
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
    for (genvar gen_i=0; gen_i<MSPLIT_SUBS_FACTOR; gen_i=gen_i+1) begin : gen_dpsi_loop
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
      ) dpsi_pep_mmacc_glwe_ram (
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

endmodule
