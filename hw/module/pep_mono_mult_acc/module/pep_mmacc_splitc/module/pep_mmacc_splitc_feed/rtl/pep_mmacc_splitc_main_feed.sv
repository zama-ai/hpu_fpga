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
// It processes the rotation of the monomial multiplication, and the subtraction
// of the CMUX.
//
// For P&R reason, GRAM is split into several parts.
//
// Notation:
// GRAM : stands for GLWE RAM
//
// ==============================================================================================

module pep_mmacc_splitc_main_feed
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_feed_pkg::*;
#(
  parameter  int DATA_LATENCY          = 5, // RAM_LATENCY + 3 : Latency for read data to come back
  localparam int MAIN_PSI              = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV,
  localparam int QPSI                  = PSI / MSPLIT_DIV
)
(
  input  logic                                                           clk,        // clock
  input  logic                                                           s_rst_n,    // synchronous reset

  // From ffifo : command from sequencer
  input  logic [PBS_CMD_W-1:0]                                           ffifo_feed_pcmd,
  input  logic                                                           ffifo_feed_vld,
  output logic                                                           ffifo_feed_rdy,

  // Output command for subs
  output logic [MMACC_FEED_CMD_W-1:0]                                    subs_mcmd,
  output logic                                                           subs_mcmd_vld,
  input  logic                                                           subs_mcmd_rdy,
  input  logic                                                           subs_mcmd_ack,
  output logic                                                           subs_mcmd_loopback_ack,

  // GRAM arbiter
  output logic [GARB_CMD_W-1:0]                                          feed_garb_req,
  output logic                                                           feed_garb_req_vld,
  input  logic                                                           feed_garb_req_rdy,

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
  output logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][1:0]                    feed_gram_rd_en,
  output logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][1:0][GLWE_RAM_ADD_W-1:0]feed_gram_rd_add,
  input  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][1:0][MOD_Q_W-1:0]       gram_feed_rd_data,
  input  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][1:0]                    gram_feed_rd_data_avail,

  // Output data
  output logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                            main_data,
  output logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                            main_rot_data,
  output logic                                                            main_data_avail,

  output logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0]                             main_part,
  output logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0]                             main_rot_part,
  output logic                                                            main_part_avail,


  output logic [BR_BATCH_CMD_W-1:0]                                       batch_cmd,
  output logic                                                            batch_cmd_avail,

  // bsk filling status
  input  logic                                                            inc_bsk_wr_ptr,

  // reset cache
  input  logic                                                            reset_cache,

  // Control
  output logic                                                            br_loop_flush_done
);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int CORE_FACTOR = (MSPLIT_MAIN_FACTOR /2) * 2;
  localparam int CORE_PSI    = PSI * CORE_FACTOR / MSPLIT_DIV;

//=================================================================================================
// signals
//=================================================================================================
  logic [MMACC_FEED_CMD_W-1:0]          main_mcmd;
  logic                                 main_mcmd_vld;
  logic                                 main_mcmd_rdy;

//=================================================================================================
// feed entry
//=================================================================================================
  pep_mmacc_splitc_feed_entry
  pep_mmacc_splitc_feed_entry
  (
    .clk             (clk),
    .s_rst_n         (s_rst_n),

    .ffifo_feed_pcmd (ffifo_feed_pcmd),
    .ffifo_feed_vld  (ffifo_feed_vld),
    .ffifo_feed_rdy  (ffifo_feed_rdy),

    .main_mcmd       (main_mcmd),
    .main_vld        (main_mcmd_vld),
    .main_rdy        (main_mcmd_rdy),

    .subs_mcmd       (subs_mcmd),
    .subs_vld        (subs_mcmd_vld),
    .subs_rdy        (subs_mcmd_rdy),

    .inc_bsk_wr_ptr  (inc_bsk_wr_ptr),

    .reset_cache     (reset_cache)
  );

//=================================================================================================
// feed core
//=================================================================================================
  logic [CORE_PSI-1:0][R-1:0][MOD_Q_W-1:0]  core_data;
  logic [CORE_PSI-1:0][R-1:0][MOD_Q_W-1:0]  core_rot_data;
  logic                                     core_data_avail;

  generate
    if (CORE_PSI > 0) begin : gen_data
      assign main_data       = core_data;
      assign main_rot_data   = core_rot_data;
      assign main_data_avail = core_data_avail;
    end
    else begin : gen_no_data
      assign main_data       = 'x;
      assign main_rot_data   = 'x;
      assign main_data_avail = 1'b0;
    end
  endgenerate


  pep_mmacc_splitc_feed_core
  #(
    .DATA_LATENCY        (DATA_LATENCY),
    .WAIT_FOR_ACK        (1),
    .MSPLIT_FACTOR       (MSPLIT_MAIN_FACTOR),
    .HPSI_SET_ID         (1)
  ) pep_mmacc_splitc_feed_core (
    .clk                     (clk),
    .s_rst_n                 (s_rst_n),

    .in_mcmd                 (main_mcmd),
    .in_mcmd_vld             (main_mcmd_vld),
    .in_mcmd_rdy             (main_mcmd_rdy),

    .mcmd_ack                (subs_mcmd_ack), /*UNUSED*/
    .mcmd_ack_ack            (1'bx),          /*UNUSED*/
    .mcmd_loopback           (),              /*UNUSED*/
    .mcmd_loopback_ack       (subs_mcmd_loopback_ack),

    .feed_garb_req           (feed_garb_req    ),
    .feed_garb_req_vld       (feed_garb_req_vld),
    .feed_garb_req_rdy       (feed_garb_req_rdy),

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
    .out_perm_select         (), /*UNUSED*/
    .out_coef_rot_id0        (), /*UNUSED*/
    .out_rcmd                (), /*UNUSED*/
    .out_data_avail          (core_data_avail),

    .out_part                (main_part),
    .out_rot_part            (main_rot_part),
    .out_part_avail          (main_part_avail),

    .in_data                 (), /*UNUSED*/
    .in_rot_data             (), /*UNUSED*/
    .in_data_avail           (), /*UNUSED*/

    .br_loop_flush_done      (br_loop_flush_done),

    .batch_cmd               (batch_cmd),
    .batch_cmd_avail         (batch_cmd_avail)
  );

endmodule
