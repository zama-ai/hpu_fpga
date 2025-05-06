// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the feeding of the processing path, in pe_pbs
// The command is given by the pep_sequencer.
// It reads the data from the GRAM.
// It processes the rotation of the monomial multiplication. The end of the computation is done
// in the main part.
//
// For P&R reason, GRAM is split into LSB and MSB. Therefore this module is also split into
// several parts. There are a LSB and a MSB parts, each addressing a part of the GRAM.
//
// This modules deals with the GRAM arbiter requests and the sending of batch_cmd.
//
// Notation:
// GRAM : stands for GLWE RAM
// LRAM : stands for LWE RAM
//
// ==============================================================================================

module pep_mmacc_splitc_subs_feed
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_feed_pkg::*;
#(
  parameter  int DATA_LATENCY          = 5, // RAM_LATENCY + 3 : Latency for read data to come back
  localparam int SUBS_PSI              = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV,
  localparam int MAIN_PSI              = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV
)
(
  input  logic                                                           clk,        // clock
  input  logic                                                           s_rst_n,    // synchronous reset

  // Input command from main
  input  logic [MMACC_FEED_CMD_W-1:0]                                    subs_mcmd,
  input  logic                                                           subs_mcmd_vld,
  output logic                                                           subs_mcmd_rdy,
  output logic                                                           subs_mcmd_loopback,
  input  logic                                                           subs_mcmd_ack_ack,

  // GRAM arbiter
  input  logic [GRAM_NB-1:0]                                             garb_feed_rot_avail_1h,
  input  logic [GRAM_NB-1:0]                                             garb_feed_dat_avail_1h,

  // To afifo
  output logic [MMACC_INTERN_CMD_W-1:0]                                  feed_afifo_icmd,
  output logic                                                           feed_afifo_vld,
  input  logic                                                           feed_afifo_rdy,

  // From acc
  input  logic                                                           acc_feed_done,
  input  logic [BPBS_ID_W-1:0]                                           acc_feed_done_map_idx,

  // GRAM
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][1:0]                      feed_gram_rd_en,
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][1:0][GLWE_RAM_ADD_W-1:0]  feed_gram_rd_add,
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][1:0][MOD_Q_W-1:0]         gram_feed_rd_data,
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][1:0]                      gram_feed_rd_data_avail,

  // Input data
  input  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                           main_data,
  input  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                           main_rot_data,
  input  logic                                                           main_data_avail,

  input  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]                  main_part,
  input  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]                  main_rot_part,
  input  logic                                                           main_part_avail,

  // Output data
  output logic [ACC_DECOMP_COEF_NB-1:0]                                  acc_decomp_data_avail,
  output logic                                                           acc_decomp_ctrl_avail,
  output logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0]                     acc_decomp_data,
  output logic                                                           acc_decomp_sob,
  output logic                                                           acc_decomp_eob,
  output logic                                                           acc_decomp_sog,
  output logic                                                           acc_decomp_eog,
  output logic                                                           acc_decomp_sol,
  output logic                                                           acc_decomp_eol,
  output logic                                                           acc_decomp_soc,
  output logic                                                           acc_decomp_eoc,
  output logic [BPBS_ID_W-1:0]                                           acc_decomp_pbs_id,
  output logic                                                           acc_decomp_last_pbs,
  output logic                                                           acc_decomp_full_throughput

);

//=================================================================================================
// localparam
//=================================================================================================
  generate
    if (MSPLIT_DIV != 4) begin : __UNSUPPORTED_MSPLIT_DIV
      $fatal(1,"> ERROR: Unsupported MSPLIT_DIV (%0d). Support only 4",MSPLIT_DIV);
    end
  endgenerate

  localparam int CORE_FACTOR = (MSPLIT_SUBS_FACTOR + 1)/2 * 2;
  localparam int CORE_PSI    = PSI * CORE_FACTOR / MSPLIT_DIV;

//=================================================================================================
// signals
//=================================================================================================
  logic [CORE_PSI-1:0][R-1:0][MOD_Q_W-1:0] core_data;
  logic [CORE_PSI-1:0][R-1:0][MOD_Q_W-1:0] core_rot_data;
  logic [PERM_W-1:0]                       core_perm_select; // last 2 levels of permutation
  logic [LWE_COEF_W:0]                     core_coef_rot_id0;
  logic [REQ_CMD_W-1:0]                    core_rcmd;
  logic                                    core_data_avail;

//=================================================================================================
// feed core
//=================================================================================================
  pep_mmacc_splitc_feed_core
  #(
    .DATA_LATENCY        (DATA_LATENCY),
    .WAIT_FOR_ACK        (2),
    .MSPLIT_FACTOR       (MSPLIT_SUBS_FACTOR),
    .HPSI_SET_ID         (0)
  ) pep_mmacc_splitc_feed_core (
    .clk                     (clk),
    .s_rst_n                 (s_rst_n),

    .in_mcmd                 (subs_mcmd),
    .in_mcmd_vld             (subs_mcmd_vld),
    .in_mcmd_rdy             (subs_mcmd_rdy),

    .mcmd_ack                (1'bx),               /* UNUSED*/
    .mcmd_ack_ack            (subs_mcmd_ack_ack),
    .mcmd_loopback           (subs_mcmd_loopback),
    .mcmd_loopback_ack       (),                   /*UNUSED*/

    .feed_garb_req           (),/*UNUSED*/
    .feed_garb_req_vld       (),/*UNUSED*/
    .feed_garb_req_rdy       (1'b1),/*UNUSED*/

    .garb_feed_rot_avail_1h  (garb_feed_rot_avail_1h),
    .garb_feed_dat_avail_1h  (garb_feed_dat_avail_1h),

    .feed_afifo_icmd         (feed_afifo_icmd),
    .feed_afifo_vld          (feed_afifo_vld),
    .feed_afifo_rdy          (feed_afifo_rdy),

    .acc_feed_done           (acc_feed_done),
    .acc_feed_done_map_idx   (acc_feed_done_map_idx),

    .feed_gram_rd_en         (feed_gram_rd_en),
    .feed_gram_rd_add        (feed_gram_rd_add),
    .gram_feed_rd_data       (gram_feed_rd_data),
    .gram_feed_rd_data_avail (gram_feed_rd_data_avail),

    .out_data                (core_data),
    .out_rot_data            (core_rot_data),
    .out_perm_select         (core_perm_select),
    .out_coef_rot_id0        (core_coef_rot_id0),
    .out_rcmd                (core_rcmd),
    .out_data_avail          (core_data_avail),

    .out_part                (), /*UNUSED*/
    .out_rot_part            (), /*UNUSED*/
    .out_part_avail          (), /*UNUSED*/

    .in_data                 (main_part),
    .in_rot_data             (main_rot_part),
    .in_data_avail           (main_part_avail),

    .br_loop_flush_done      (), /*UNUSED*/

    .batch_cmd               (), /*UNUSED*/
    .batch_cmd_avail         ()  /*UNUSED*/
  );

//=================================================================================================
// feed final
//=================================================================================================
  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0] in0_data;
  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0] in0_rot_data;
  logic                                 in0_data_avail;

  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0] in1_data;
  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0] in1_rot_data;
  logic                                 in1_data_avail;

  assign in0_data       = core_data[PSI/2-1:0];
  assign in0_rot_data   = core_rot_data[PSI/2-1:0];
  assign in0_data_avail = core_data_avail;

  generate
    if (MSPLIT_SUBS_FACTOR < MSPLIT_DIV -1) begin : gen_use_main
      assign in1_data       = main_data      ;
      assign in1_rot_data   = main_rot_data  ;
      assign in1_data_avail = main_data_avail;
    end
    else begin : gen_no_use_main
      assign in1_data       = core_data[PSI/2+:PSI/2];
      assign in1_rot_data   = core_rot_data[PSI/2+:PSI/2];
      assign in1_data_avail = core_data_avail;
    end
  endgenerate

  pep_mmacc_splitc_feed_final
  #(
    .INPUT_PIPE (1'b0)
  ) pep_mmacc_splitc_feed_final (
    .clk                        (clk),
    .s_rst_n                    (s_rst_n),

    .in0_data                   (in0_data),
    .in0_rot_data               (in0_rot_data),
    .in0_data_avail             (in0_data_avail),

    .in1_data                   (in1_data),
    .in1_rot_data               (in1_rot_data),
    .in1_data_avail             (in1_data_avail),

    .in_perm_select             (core_perm_select),
    .in_coef_rot_id0            (core_coef_rot_id0),
    .in_rcmd                    (core_rcmd),

    .acc_decomp_data_avail      (acc_decomp_data_avail),
    .acc_decomp_ctrl_avail      (acc_decomp_ctrl_avail),
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
    .acc_decomp_full_throughput (acc_decomp_full_throughput)
  );

endmodule
