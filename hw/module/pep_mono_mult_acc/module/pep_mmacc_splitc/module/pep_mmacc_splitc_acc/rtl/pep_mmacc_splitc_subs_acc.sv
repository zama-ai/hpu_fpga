// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the accumulation part of the CMUX process.
// It reads the data from the GRAM, and wait for the external multiplication results.
// It does the addition, and writes the result back in GRAM.
//
// This module is the core of the module.
//
// Notation:
// GRAM : stands for GLWE RAM
// ==============================================================================================

module pep_mmacc_splitc_subs_acc
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
  localparam int SUBS_PSI              = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV,
  localparam int MAIN_PSI              = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV
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

  // To main
  output logic                                                     main_ntt_acc_avail,
  output logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]                  main_ntt_acc_data,
  output logic                                                     main_ntt_acc_sob,
  output logic                                                     main_ntt_acc_eob,
  output logic                                                     main_ntt_acc_sol,
  output logic                                                     main_ntt_acc_eol,
  output logic                                                     main_ntt_acc_sog,
  output logic                                                     main_ntt_acc_eog,
  output logic [BPBS_ID_W-1:0]                                     main_ntt_acc_pbs_id,

  // GRAM arbiter
  input  logic [GRAM_NB-1:0]                                       garb_acc_rd_avail_1h,
  input  logic [GRAM_NB-1:0]                                       garb_acc_wr_avail_1h,

  // GRAM access
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     acc_gram_rd_en,
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] acc_gram_rd_add,
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]        gram_acc_rd_data,
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     gram_acc_rd_data_avail,

  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     acc_gram_wr_en,
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] acc_gram_wr_add,
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]        acc_gram_wr_data,

  // From afifo
  input  logic [MMACC_INTERN_CMD_W-1:0]                            afifo_acc_icmd,
  input  logic                                                     afifo_acc_vld,
  output logic                                                     afifo_acc_rdy,

  // Status
  output logic                                                     acc_feed_done,
  output logic [BPBS_ID_W-1:0]                                     acc_feed_done_map_idx,
  output logic                                                     br_loop_proc_done,

  output logic [ACC_CORE_ERROR_W-1:0]                              subs_error

);

//=================================================================================================
// Fork
//=================================================================================================
  assign main_ntt_acc_avail      = ntt_acc_ctrl_avail;
  assign main_ntt_acc_data       = ntt_acc_data[SUBS_PSI+:MAIN_PSI];
  assign main_ntt_acc_sob        = ntt_acc_sob;
  assign main_ntt_acc_eob        = ntt_acc_eob;
  assign main_ntt_acc_sol        = ntt_acc_sol;
  assign main_ntt_acc_eol        = ntt_acc_eol;
  assign main_ntt_acc_sog        = ntt_acc_sog;
  assign main_ntt_acc_eog        = ntt_acc_eog;
  assign main_ntt_acc_pbs_id     = ntt_acc_pbs_id;

//=================================================================================================
// core
//=================================================================================================
  pep_mmacc_splitc_acc_core
  #(
    .DATA_LATENCY         (DATA_LATENCY),
    .RAM_LATENCY          (RAM_LATENCY),
    .HPSI_SET_ID          (0),
    .MSPLIT_FACTOR        (MSPLIT_SUBS_FACTOR),
    .FIFO_NTT_ACC_DEPTH   (FIFO_NTT_ACC_DEPTH)
  ) pep_mmacc_splitc_acc_core (
    .clk                    (clk),        // clock
    .s_rst_n                (s_rst_n),    // synchronous reset

    .ntt_acc_avail          (ntt_acc_ctrl_avail),
    .ntt_acc_data           (ntt_acc_data[SUBS_PSI-1:0]),
    .ntt_acc_sob            (ntt_acc_sob),
    .ntt_acc_eob            (ntt_acc_eob),
    .ntt_acc_sol            (ntt_acc_sol),
    .ntt_acc_eol            (ntt_acc_eol),
    .ntt_acc_sog            (ntt_acc_sog),
    .ntt_acc_eog            (ntt_acc_eog),
    .ntt_acc_pbs_id         (ntt_acc_pbs_id),

    .acc_garb_req           (), /*UNUSED*/
    .acc_garb_req_vld       (), /*UNUSED*/
    .acc_garb_req_rdy       (1'b1), /*UNUSED*/

    .garb_acc_rd_avail_1h   (garb_acc_rd_avail_1h),
    .garb_acc_wr_avail_1h   (garb_acc_wr_avail_1h),

    .acc_gram_rd_en         (acc_gram_rd_en),
    .acc_gram_rd_add        (acc_gram_rd_add),
    .gram_acc_rd_data       (gram_acc_rd_data),
    .gram_acc_rd_data_avail (gram_acc_rd_data_avail),

    .acc_gram_wr_en         (acc_gram_wr_en),
    .acc_gram_wr_add        (acc_gram_wr_add),
    .acc_gram_wr_data       (acc_gram_wr_data),

    .afifo_acc_icmd         (afifo_acc_icmd),
    .afifo_acc_vld          (afifo_acc_vld),
    .afifo_acc_rdy          (afifo_acc_rdy),

    .acc_sfifo_icmd         (/*UNUSED*/),
    .acc_sfifo_avail        (/*UNUSED*/),

    .acc_feed_done          (acc_feed_done),
    .acc_feed_done_map_idx  (acc_feed_done_map_idx),
    .br_loop_proc_done      (br_loop_proc_done),

    .error                  (subs_error)
  );

endmodule
