// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module assembles pep_mmacc_splitc_acc_main and pep_mmacc_split_acc_subs.
// It is used for verification.
// ==============================================================================================

module pep_mmacc_splitc_acc_assembly
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
#(
  parameter  int DATA_LATENCY          = 5, // Latency for read data to come back
  parameter  int RAM_LATENCY           = 2,
  parameter  int FIFO_NTT_ACC_DEPTH    = 1024, // Physical RAM depth. Should be a power of 2
  parameter  int SLR_LATENCY           = 2*3    // Number of cycles for the other part to arrive.
)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  // NTT core -> ACC
  input  logic [PSI-1:0][R-1:0]                                    ntt_acc_data_avail,
  input  logic                                                     ntt_acc_ctrl_avail,
  input  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]                       ntt_acc_data,
  input  logic                                                     ntt_acc_sob,
  input  logic                                                     ntt_acc_eob,
  input  logic                                                     ntt_acc_sol,
  input  logic                                                     ntt_acc_eol,
  input  logic                                                     ntt_acc_sog,
  input  logic                                                     ntt_acc_eog,
  input  logic [BPBS_ID_W-1:0]                                     ntt_acc_pbs_id,

  // GRAM arbiter
  output logic [GARB_CMD_W-1:0]                                    acc_garb_req,
  output logic                                                     acc_garb_req_vld,
  input  logic                                                     acc_garb_req_rdy,

  input  logic [GRAM_NB-1:0]                                       garb_acc_rd_avail_1h,
  input  logic [GRAM_NB-1:0]                                       garb_acc_wr_avail_1h,

  // GRAM access
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                       acc_gram_rd_en,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]   acc_gram_rd_add,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0]          gram_acc_rd_data,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                       gram_acc_rd_data_avail,

  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                       acc_gram_wr_en,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]   acc_gram_wr_add,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0]          acc_gram_wr_data,

  // From afifo
  input  logic [MMACC_INTERN_CMD_W-1:0]                            main_afifo_acc_icmd,
  input  logic                                                     main_afifo_acc_vld,
  output logic                                                     main_afifo_acc_rdy,

  input  logic [MMACC_INTERN_CMD_W-1:0]                            subs_afifo_acc_icmd,
  input  logic                                                     subs_afifo_acc_vld,
  output logic                                                     subs_afifo_acc_rdy,

  // To sfifo
  output logic [MMACC_INTERN_CMD_W-1:0]                            main_acc_sfifo_icmd,
  output logic                                                     main_acc_sfifo_avail,

  // Status
  output logic                                                     main_acc_feed_done,
  output logic [BPBS_ID_W-1:0]                                     main_acc_feed_done_map_idx,
  output logic                                                     main_br_loop_proc_done,

  output logic                                                     subs_acc_feed_done,
  output logic [BPBS_ID_W-1:0]                                     subs_acc_feed_done_map_idx,
  output logic                                                     subs_br_loop_proc_done,

  output logic [ACC_CORE_ERROR_W-1:0]                              error
);

// ============================================================================================= --
// localparam
// ============================================================================================= --
  generate
    if (SLR_LATENCY < 2) begin : __UNSUPPORTED_SLR_LATENCY_
      $fatal(1,"> ERROR: Unsupported SLR_LATENCY (%0d) value : should be >= 2", SLR_LATENCY);
    end
  endgenerate

  localparam int OUTWARD_SLR_LATENCY = SLR_LATENCY/2;
  localparam int RETURN_SLR_LATENCY  = SLR_LATENCY - OUTWARD_SLR_LATENCY;
  localparam int MAIN_PSI            = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV;
  localparam int SUBS_PSI            = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV;
  localparam int QPSI                = PSI / MSPLIT_DIV;

// ============================================================================================= --
// Signals
// ============================================================================================= --
  // To main
  logic [MAIN_PSI-1:0][R-1:0]             in_subs_main_ntt_acc_data_avail;
  logic                                   in_subs_main_ntt_acc_ctrl_avail;
  logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]in_subs_main_ntt_acc_data;
  logic                                   in_subs_main_ntt_acc_sob;
  logic                                   in_subs_main_ntt_acc_eob;
  logic                                   in_subs_main_ntt_acc_sol;
  logic                                   in_subs_main_ntt_acc_eol;
  logic                                   in_subs_main_ntt_acc_sog;
  logic                                   in_subs_main_ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                   in_subs_main_ntt_acc_pbs_id;

  logic [MAIN_PSI-1:0][R-1:0]             out_subs_main_ntt_acc_data_avail;
  logic                                   out_subs_main_ntt_acc_ctrl_avail;
  logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]out_subs_main_ntt_acc_data;
  logic                                   out_subs_main_ntt_acc_sob;
  logic                                   out_subs_main_ntt_acc_eob;
  logic                                   out_subs_main_ntt_acc_sol;
  logic                                   out_subs_main_ntt_acc_eol;
  logic                                   out_subs_main_ntt_acc_sog;
  logic                                   out_subs_main_ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                   out_subs_main_ntt_acc_pbs_id;

  logic [ACC_CORE_ERROR_W-1:0]            in_subs_main_error;
  logic [ACC_CORE_ERROR_W-1:0]            out_subs_main_error;

  // GRAM arbiter - from subs
  logic [GRAM_NB-1:0]                     in_main_subs_garb_acc_rd_avail_1h;
  logic [GRAM_NB-1:0]                     in_main_subs_garb_acc_wr_avail_1h;

  logic [GRAM_NB-1:0]                     out_main_subs_garb_acc_rd_avail_1h;
  logic [GRAM_NB-1:0]                     out_main_subs_garb_acc_wr_avail_1h;

  logic [MSPLIT_DIV-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                       acc_gram_rd_en_l;
  logic [MSPLIT_DIV-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]   acc_gram_rd_add_l;
  logic [MSPLIT_DIV-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]          gram_acc_rd_data_l;
  logic [MSPLIT_DIV-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                       gram_acc_rd_data_avail_l;

  logic [MSPLIT_DIV-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                       acc_gram_wr_en_l;
  logic [MSPLIT_DIV-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]   acc_gram_wr_add_l;
  logic [MSPLIT_DIV-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]          acc_gram_wr_data_l;

  always_comb
    for (int i=0; i<MSPLIT_DIV; i=i+1)
      for (int g=0; g<GRAM_NB; g=g+1)
        for (int p=0; p<QPSI; p=p+1) begin
          acc_gram_rd_en[g][i*QPSI+p]      = acc_gram_rd_en_l[i][g][p];
          acc_gram_rd_add[g][i*QPSI+p]     = acc_gram_rd_add_l[i][g][p];
          gram_acc_rd_data_l[i][g][p]       = gram_acc_rd_data[g][i*QPSI+p];
          gram_acc_rd_data_avail_l[i][g][p] = gram_acc_rd_data_avail[g][i*QPSI+p];

          acc_gram_wr_en[g][i*QPSI+p]   = acc_gram_wr_en_l[i][g][p];
          acc_gram_wr_add[g][i*QPSI+p]  = acc_gram_wr_add_l[i][g][p];
          acc_gram_wr_data[g][i*QPSI+p] = acc_gram_wr_data_l[i][g][p];
        end

// ============================================================================================= --
// SLR crossing
// ============================================================================================= --
  logic [OUTWARD_SLR_LATENCY-1:0][MAIN_PSI-1:0][R-1:0]             subs_main_ntt_acc_data_avail_sr;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_ctrl_avail_sr;
  logic [OUTWARD_SLR_LATENCY-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]subs_main_ntt_acc_data_sr;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_sob_sr;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_eob_sr;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_sol_sr;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_eol_sr;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_sog_sr;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_eog_sr;
  logic [OUTWARD_SLR_LATENCY-1:0][BPBS_ID_W-1:0]                   subs_main_ntt_acc_pbs_id_sr;

  logic [OUTWARD_SLR_LATENCY-1:0][MAIN_PSI-1:0][R-1:0]             subs_main_ntt_acc_data_avail_srD;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_ctrl_avail_srD;
  logic [OUTWARD_SLR_LATENCY-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]subs_main_ntt_acc_data_srD;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_sob_srD;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_eob_srD;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_sol_srD;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_eol_srD;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_sog_srD;
  logic [OUTWARD_SLR_LATENCY-1:0]                                  subs_main_ntt_acc_eog_srD;
  logic [OUTWARD_SLR_LATENCY-1:0][BPBS_ID_W-1:0]                   subs_main_ntt_acc_pbs_id_srD;

  logic [RETURN_SLR_LATENCY-1:0][2*GRAM_NB-1:0]                    main_subs_garb_acc_avail_1h_sr;
  logic [RETURN_SLR_LATENCY-1:0][2*GRAM_NB-1:0]                    main_subs_garb_acc_avail_1h_srD;
  logic [RETURN_SLR_LATENCY-1:0][ACC_CORE_ERROR_W-1:0]             subs_main_error_sr;
  logic [RETURN_SLR_LATENCY-1:0][ACC_CORE_ERROR_W-1:0]             subs_main_error_srD;


  assign subs_main_ntt_acc_data_avail_srD[0] = in_subs_main_ntt_acc_data_avail;
  assign subs_main_ntt_acc_ctrl_avail_srD[0] = in_subs_main_ntt_acc_ctrl_avail;
  assign subs_main_ntt_acc_data_srD[0]       = in_subs_main_ntt_acc_data;
  assign subs_main_ntt_acc_sob_srD[0]        = in_subs_main_ntt_acc_sob;
  assign subs_main_ntt_acc_eob_srD[0]        = in_subs_main_ntt_acc_eob;
  assign subs_main_ntt_acc_sol_srD[0]        = in_subs_main_ntt_acc_sol;
  assign subs_main_ntt_acc_eol_srD[0]        = in_subs_main_ntt_acc_eol;
  assign subs_main_ntt_acc_sog_srD[0]        = in_subs_main_ntt_acc_sog;
  assign subs_main_ntt_acc_eog_srD[0]        = in_subs_main_ntt_acc_eog;
  assign subs_main_ntt_acc_pbs_id_srD[0]     = in_subs_main_ntt_acc_pbs_id;

  generate
    if (OUTWARD_SLR_LATENCY > 1) begin
      assign subs_main_ntt_acc_data_avail_srD[OUTWARD_SLR_LATENCY-1:1] = subs_main_ntt_acc_data_avail_sr[OUTWARD_SLR_LATENCY-2:0];
      assign subs_main_ntt_acc_ctrl_avail_srD[OUTWARD_SLR_LATENCY-1:1] = subs_main_ntt_acc_ctrl_avail_sr[OUTWARD_SLR_LATENCY-2:0];
      assign subs_main_ntt_acc_data_srD[OUTWARD_SLR_LATENCY-1:1]       = subs_main_ntt_acc_data_sr[OUTWARD_SLR_LATENCY-2:0];
      assign subs_main_ntt_acc_sob_srD[OUTWARD_SLR_LATENCY-1:1]        = subs_main_ntt_acc_sob_sr[OUTWARD_SLR_LATENCY-2:0];
      assign subs_main_ntt_acc_eob_srD[OUTWARD_SLR_LATENCY-1:1]        = subs_main_ntt_acc_eob_sr[OUTWARD_SLR_LATENCY-2:0];
      assign subs_main_ntt_acc_sol_srD[OUTWARD_SLR_LATENCY-1:1]        = subs_main_ntt_acc_sol_sr[OUTWARD_SLR_LATENCY-2:0];
      assign subs_main_ntt_acc_eol_srD[OUTWARD_SLR_LATENCY-1:1]        = subs_main_ntt_acc_eol_sr[OUTWARD_SLR_LATENCY-2:0];
      assign subs_main_ntt_acc_sog_srD[OUTWARD_SLR_LATENCY-1:1]        = subs_main_ntt_acc_sog_sr[OUTWARD_SLR_LATENCY-2:0];
      assign subs_main_ntt_acc_eog_srD[OUTWARD_SLR_LATENCY-1:1]        = subs_main_ntt_acc_eog_sr[OUTWARD_SLR_LATENCY-2:0];
      assign subs_main_ntt_acc_pbs_id_srD[OUTWARD_SLR_LATENCY-1:1]     = subs_main_ntt_acc_pbs_id_sr[OUTWARD_SLR_LATENCY-2:0];
    end
  endgenerate

  assign out_subs_main_ntt_acc_data_avail = subs_main_ntt_acc_data_avail_sr[OUTWARD_SLR_LATENCY-1];
  assign out_subs_main_ntt_acc_ctrl_avail = subs_main_ntt_acc_ctrl_avail_sr[OUTWARD_SLR_LATENCY-1];
  assign out_subs_main_ntt_acc_data       = subs_main_ntt_acc_data_sr[OUTWARD_SLR_LATENCY-1];
  assign out_subs_main_ntt_acc_sob        = subs_main_ntt_acc_sob_sr[OUTWARD_SLR_LATENCY-1];
  assign out_subs_main_ntt_acc_eob        = subs_main_ntt_acc_eob_sr[OUTWARD_SLR_LATENCY-1];
  assign out_subs_main_ntt_acc_sol        = subs_main_ntt_acc_sol_sr[OUTWARD_SLR_LATENCY-1];
  assign out_subs_main_ntt_acc_eol        = subs_main_ntt_acc_eol_sr[OUTWARD_SLR_LATENCY-1];
  assign out_subs_main_ntt_acc_sog        = subs_main_ntt_acc_sog_sr[OUTWARD_SLR_LATENCY-1];
  assign out_subs_main_ntt_acc_eog        = subs_main_ntt_acc_eog_sr[OUTWARD_SLR_LATENCY-1];
  assign out_subs_main_ntt_acc_pbs_id     = subs_main_ntt_acc_pbs_id_sr[OUTWARD_SLR_LATENCY-1];

  assign main_subs_garb_acc_avail_1h_srD[0] = {in_main_subs_garb_acc_rd_avail_1h, in_main_subs_garb_acc_wr_avail_1h};
  assign {out_main_subs_garb_acc_rd_avail_1h,
          out_main_subs_garb_acc_wr_avail_1h}  = main_subs_garb_acc_avail_1h_sr[RETURN_SLR_LATENCY-1];
  assign subs_main_error_srD[0]              = in_subs_main_error;
  assign out_subs_main_error                 = subs_main_error_sr[RETURN_SLR_LATENCY-1];
  generate
    if (RETURN_SLR_LATENCY > 1) begin
      assign main_subs_garb_acc_avail_1h_srD[RETURN_SLR_LATENCY-1:1] = main_subs_garb_acc_avail_1h_sr[RETURN_SLR_LATENCY-2:0];
      assign subs_main_error_srD[RETURN_SLR_LATENCY-1:1]             = subs_main_error_sr[RETURN_SLR_LATENCY-2:0];
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      subs_main_ntt_acc_data_avail_sr <= '0;
      subs_main_ntt_acc_ctrl_avail_sr <= '0;

      main_subs_garb_acc_avail_1h_sr <= '0;
      subs_main_error_sr             <= '0;
    end
    else begin
      subs_main_ntt_acc_data_avail_sr <= subs_main_ntt_acc_data_avail_srD;
      subs_main_ntt_acc_ctrl_avail_sr <= subs_main_ntt_acc_ctrl_avail_srD;

      main_subs_garb_acc_avail_1h_sr <= main_subs_garb_acc_avail_1h_srD;
      subs_main_error_sr             <= subs_main_error_srD;
    end

  always_ff @(posedge clk) begin
    subs_main_ntt_acc_data_sr   <= subs_main_ntt_acc_data_srD;
    subs_main_ntt_acc_sob_sr    <= subs_main_ntt_acc_sob_srD;
    subs_main_ntt_acc_eob_sr    <= subs_main_ntt_acc_eob_srD;
    subs_main_ntt_acc_sol_sr    <= subs_main_ntt_acc_sol_srD;
    subs_main_ntt_acc_eol_sr    <= subs_main_ntt_acc_eol_srD;
    subs_main_ntt_acc_sog_sr    <= subs_main_ntt_acc_sog_srD;
    subs_main_ntt_acc_eog_sr    <= subs_main_ntt_acc_eog_srD;
    subs_main_ntt_acc_pbs_id_sr <= subs_main_ntt_acc_pbs_id_srD;
  end

// ============================================================================================= --
// main
// ============================================================================================= --
  assign in_main_subs_garb_acc_rd_avail_1h = garb_acc_rd_avail_1h;
  assign in_main_subs_garb_acc_wr_avail_1h = garb_acc_wr_avail_1h;

  pep_mmacc_splitc_main_acc
  #(
    .DATA_LATENCY         (DATA_LATENCY),
    .RAM_LATENCY          (RAM_LATENCY),
    .FIFO_NTT_ACC_DEPTH   (FIFO_NTT_ACC_DEPTH)
  ) pep_mmacc_splitc_main_acc (
    .clk                     (clk),
    .s_rst_n                 (s_rst_n),

    .main_ntt_acc_data_avail (out_subs_main_ntt_acc_data_avail),
    .main_ntt_acc_ctrl_avail (out_subs_main_ntt_acc_ctrl_avail),
    .main_ntt_acc_data       (out_subs_main_ntt_acc_data),
    .main_ntt_acc_sob        (out_subs_main_ntt_acc_sob),
    .main_ntt_acc_eob        (out_subs_main_ntt_acc_eob),
    .main_ntt_acc_sol        (out_subs_main_ntt_acc_sol),
    .main_ntt_acc_eol        (out_subs_main_ntt_acc_eol),
    .main_ntt_acc_sog        (out_subs_main_ntt_acc_sog),
    .main_ntt_acc_eog        (out_subs_main_ntt_acc_eog),
    .main_ntt_acc_pbs_id     (out_subs_main_ntt_acc_pbs_id),

    .acc_garb_req            (acc_garb_req),
    .acc_garb_req_vld        (acc_garb_req_vld),
    .acc_garb_req_rdy        (acc_garb_req_rdy),

    .garb_acc_rd_avail_1h    (garb_acc_rd_avail_1h),
    .garb_acc_wr_avail_1h    (garb_acc_wr_avail_1h),

    .acc_gram_rd_en          (acc_gram_rd_en_l[MSPLIT_SUBS_FACTOR+:MSPLIT_MAIN_FACTOR]),
    .acc_gram_rd_add         (acc_gram_rd_add_l[MSPLIT_SUBS_FACTOR+:MSPLIT_MAIN_FACTOR]),
    .gram_acc_rd_data        (gram_acc_rd_data_l[MSPLIT_SUBS_FACTOR+:MSPLIT_MAIN_FACTOR]),
    .gram_acc_rd_data_avail  (gram_acc_rd_data_avail_l[MSPLIT_SUBS_FACTOR+:MSPLIT_MAIN_FACTOR]),

    .acc_gram_wr_en          (acc_gram_wr_en_l[MSPLIT_SUBS_FACTOR+:MSPLIT_MAIN_FACTOR]),
    .acc_gram_wr_add         (acc_gram_wr_add_l[MSPLIT_SUBS_FACTOR+:MSPLIT_MAIN_FACTOR]),
    .acc_gram_wr_data        (acc_gram_wr_data_l[MSPLIT_SUBS_FACTOR+:MSPLIT_MAIN_FACTOR]),

    .afifo_acc_icmd          (main_afifo_acc_icmd),
    .afifo_acc_vld           (main_afifo_acc_vld),
    .afifo_acc_rdy           (main_afifo_acc_rdy),

    .acc_sfifo_icmd          (main_acc_sfifo_icmd),
    .acc_sfifo_avail         (main_acc_sfifo_avail),

    .acc_feed_done           (main_acc_feed_done),
    .acc_feed_done_map_idx   (main_acc_feed_done_map_idx),
    .br_loop_proc_done       (main_br_loop_proc_done),

    .subs_error              (out_subs_main_error),
    .error                   (error)
  );

// ============================================================================================= --
// subs
// ============================================================================================= --
  pep_mmacc_splitc_subs_acc
  #(
    .DATA_LATENCY         (DATA_LATENCY),
    .RAM_LATENCY          (RAM_LATENCY),
    .FIFO_NTT_ACC_DEPTH   (FIFO_NTT_ACC_DEPTH)
  ) pep_mmacc_splitc_subs_acc (
    .clk                       (clk),
    .s_rst_n                   (s_rst_n),

    .ntt_acc_data_avail        (ntt_acc_data_avail),
    .ntt_acc_ctrl_avail        (ntt_acc_ctrl_avail),
    .ntt_acc_data              (ntt_acc_data),
    .ntt_acc_sob               (ntt_acc_sob),
    .ntt_acc_eob               (ntt_acc_eob),
    .ntt_acc_sol               (ntt_acc_sol),
    .ntt_acc_eol               (ntt_acc_eol),
    .ntt_acc_sog               (ntt_acc_sog),
    .ntt_acc_eog               (ntt_acc_eog),
    .ntt_acc_pbs_id            (ntt_acc_pbs_id),

    .main_ntt_acc_data_avail   (in_subs_main_ntt_acc_data_avail),
    .main_ntt_acc_ctrl_avail   (in_subs_main_ntt_acc_ctrl_avail),
    .main_ntt_acc_data         (in_subs_main_ntt_acc_data),
    .main_ntt_acc_sob          (in_subs_main_ntt_acc_sob),
    .main_ntt_acc_eob          (in_subs_main_ntt_acc_eob),
    .main_ntt_acc_sol          (in_subs_main_ntt_acc_sol),
    .main_ntt_acc_eol          (in_subs_main_ntt_acc_eol),
    .main_ntt_acc_sog          (in_subs_main_ntt_acc_sog),
    .main_ntt_acc_eog          (in_subs_main_ntt_acc_eog),
    .main_ntt_acc_pbs_id       (in_subs_main_ntt_acc_pbs_id),

    .garb_acc_rd_avail_1h      (out_main_subs_garb_acc_rd_avail_1h),
    .garb_acc_wr_avail_1h      (out_main_subs_garb_acc_wr_avail_1h),

    .acc_gram_rd_en            (acc_gram_rd_en_l[0+:MSPLIT_SUBS_FACTOR]),
    .acc_gram_rd_add           (acc_gram_rd_add_l[0+:MSPLIT_SUBS_FACTOR]),
    .gram_acc_rd_data          (gram_acc_rd_data_l[0+:MSPLIT_SUBS_FACTOR]),
    .gram_acc_rd_data_avail    (gram_acc_rd_data_avail_l[0+:MSPLIT_SUBS_FACTOR]),

    .acc_gram_wr_en            (acc_gram_wr_en_l[0+:MSPLIT_SUBS_FACTOR]),
    .acc_gram_wr_add           (acc_gram_wr_add_l[0+:MSPLIT_SUBS_FACTOR]),
    .acc_gram_wr_data          (acc_gram_wr_data_l[0+:MSPLIT_SUBS_FACTOR]),

    .afifo_acc_icmd            (subs_afifo_acc_icmd),
    .afifo_acc_vld             (subs_afifo_acc_vld),
    .afifo_acc_rdy             (subs_afifo_acc_rdy),

    .acc_feed_done             (subs_acc_feed_done),
    .acc_feed_done_map_idx     (subs_acc_feed_done_map_idx),
    .br_loop_proc_done         (subs_br_loop_proc_done),

    .subs_error                (in_subs_main_error)

  );

endmodule
