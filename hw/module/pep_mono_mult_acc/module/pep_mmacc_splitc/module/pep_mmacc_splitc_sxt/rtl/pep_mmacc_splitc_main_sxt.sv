// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the sample extraction, and the rotation with b.
// It reads the coefficients from GRAM, and orders them according to b and, does the negation
// when necessary.
// Data in GRAM are assumed to be in reverse order.
//
// This module outputs REGF_COEF_NB coefficients at a time.
// If the number of coefficients of a BLWE is not a multiple of BLWE_COEF_NB, the last word
// is completed with garbage.
// ==============================================================================================

module pep_mmacc_splitc_main_sxt
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_sxt_pkg::*;
#(
  parameter  int DATA_LATENCY          = 5,   // RAM_LATENCY + 3 : Latency for read data to come back
  localparam int SXT_SPLITC_COEF       = set_msplit_sxt_splitc_coef(MSPLIT_TYPE),
  localparam int MAIN_PSI              = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV
)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  // From sfifo
  input  logic [MMACC_INTERN_CMD_W-1:0]                            sfifo_sxt_icmd,
  input  logic                                                     sfifo_sxt_vld,
  output logic                                                     sfifo_sxt_rdy,

  // sxt <-> body RAM
  input  logic [LWE_COEF_W-1:0]                                    boram_sxt_data,
  input  logic                                                     boram_sxt_data_vld,
  output logic                                                     boram_sxt_data_rdy,

  // main <-> subs cmd
  output logic                                                     subs_cmd_vld,
  input  logic                                                     subs_cmd_rdy,
  output logic [LWE_COEF_W-1:0]                                    subs_cmd_body,
  output logic [MMACC_INTERN_CMD_W-1:0]                            subs_cmd_icmd,
  input  logic                                                     subs_cmd_ack,

  // main <-> subs data
  // Not used if MSPLIT_SUBS_FACTOR = 1
  input  logic [SXT_SPLITC_COEF-1:0][MOD_Q_W-1:0]                  subs_data_data,
  input  logic                                                     subs_data_vld,
  output logic                                                     subs_data_rdy,

  // Used when MSPLIT_MAIN_FACTOR is odd
  input  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]            subs_part_data,
  input  logic                                                     subs_part_vld,
  output logic                                                     subs_part_rdy,

  // sxt <-> regfile
  // write
  output logic                                                     sxt_regf_wr_req_vld,
  input  logic                                                     sxt_regf_wr_req_rdy,
  output logic [REGF_WR_REQ_W-1:0]                                 sxt_regf_wr_req,

  output logic [REGF_COEF_NB-1:0]                                  sxt_regf_wr_data_vld,
  input  logic [REGF_COEF_NB-1:0]                                  sxt_regf_wr_data_rdy,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                     sxt_regf_wr_data,

  input  logic                                                     regf_sxt_wr_ack,

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]                                       garb_sxt_avail_1h,

  // GRAM
  output logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                     sxt_gram_rd_en,
  output logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] sxt_gram_rd_add,
  input  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]        gram_sxt_rd_data,
  input  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                     gram_sxt_rd_data_avail,

  // CT done
  output logic                                                     sxt_seq_done, // pulse
  output logic [PID_W-1:0]                                         sxt_seq_done_pid,

  // For register if
  output logic                                                     sxt_rif_cmd_wait_b_dur,
  output logic                                                     sxt_rif_rcp_dur,
  output logic                                                     sxt_rif_req_dur
);

// ============================================================================================= --
// localparam
// ============================================================================================= --
  localparam int SUBS_PSI           = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV;
  localparam int CORE_FACTOR        = (MSPLIT_MAIN_FACTOR%2) == 0 ? MSPLIT_MAIN_FACTOR : MSPLIT_MAIN_FACTOR + 1;
  localparam int CORE_PSI           = CORE_FACTOR * PSI / MSPLIT_DIV;
  localparam int CORE_CTRL_NB       = CORE_FACTOR / 2;
  localparam int FMT_FACTOR         = MSPLIT_SUBS_FACTOR - (MSPLIT_SUBS_FACTOR%2);
  localparam int FMT_PSI            = FMT_FACTOR * PSI / MSPLIT_DIV;

// ============================================================================================= --
// Signals
// ============================================================================================= --
  logic [LWE_COEF_W-1:0]                 sm1_body;
  logic                                  sm1_body_vld;
  logic                                  sm1_body_rdy;

  logic                                  main_cmd_vld;
  logic                                  main_cmd_rdy;
  logic [LWE_COEF_W-1:0]                 main_cmd_body;
  logic [MMACC_INTERN_CMD_W-1:0]         main_cmd_icmd;

  logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0] main_data_data;
  logic [PERM_W-1:0]                     main_data_perm_select;
  logic [CMD_X_W-1:0]                    main_data_cmd;
  logic                                  main_data_vld;
  logic                                  main_data_rdy;

  logic [FMT_PSI-1:0][R-1:0][MOD_Q_W-1:0] subs_fmt_data;
  logic                                  subs_fmt_vld;
  logic                                  subs_fmt_rdy;

// ============================================================================================= --
// Format
// ============================================================================================= --
  generate
    if (FMT_PSI > 0) begin : gen_format
      stream_disp_format
      #(
        .OP_W       (MOD_Q_W),
        .IN_COEF    (SXT_SPLITC_COEF),
        .OUT_COEF   (FMT_PSI*R),
        .IN_PIPE    (1'b1)
      ) stream_disp_format (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (subs_data_data),
        .in_vld   (subs_data_vld),
        .in_rdy   (subs_data_rdy),

        .out_data (subs_fmt_data),
        .out_vld  (subs_fmt_vld),
        .out_rdy  (subs_fmt_rdy)
      );
    end
    else begin : gen_no_format
      // These signals are unused
      assign subs_fmt_data = 'x;
      assign subs_fmt_vld  = 1'b0;
      assign subs_data_rdy = 1'b0;
    end
  endgenerate

// ============================================================================================= --
// SXT entry
// ============================================================================================= --
  pep_mmacc_splitc_sxt_entry
  pep_mmacc_splitc_sxt_entry
  (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .sfifo_sxt_icmd         (sfifo_sxt_icmd),
    .sfifo_sxt_vld          (sfifo_sxt_vld),
    .sfifo_sxt_rdy          (sfifo_sxt_rdy),

    .boram_sxt_data         (boram_sxt_data),
    .boram_sxt_data_vld     (boram_sxt_data_vld),
    .boram_sxt_data_rdy     (boram_sxt_data_rdy),

    .subs_cmd_body          (subs_cmd_body),
    .subs_cmd_icmd          (subs_cmd_icmd),
    .subs_cmd_vld           (subs_cmd_vld),
    .subs_cmd_rdy           (subs_cmd_rdy),

    .main_cmd_body          (main_cmd_body),
    .main_cmd_icmd          (main_cmd_icmd),
    .main_cmd_vld           (main_cmd_vld),
    .main_cmd_rdy           (main_cmd_rdy),

    .sxt_rif_cmd_wait_b_dur (sxt_rif_cmd_wait_b_dur)
  );

// ============================================================================================= --
// SXT core
// ============================================================================================= --
  logic [CORE_PSI-1:0][R-1:0][MOD_Q_W-1:0] core_rot_data;
  logic [PERM_W-1:0]                       core_data_perm_select;
  logic [CMD_X_W-1:0]                      core_data_cmd;
  logic [CORE_FACTOR/2-1:0]                core_data_vld;
  logic [CORE_FACTOR/2-1:0]                core_data_rdy;

  pep_mmacc_splitc_sxt_core
  #(
    .DATA_LATENCY       (DATA_LATENCY),
    .WAIT_FOR_ACK       (1'b0),
    .MSPLIT_FACTOR      (MSPLIT_MAIN_FACTOR),
    .HPSI_SET_ID        (1),
    .JOIN_LIMIT         (1'b0)
  ) pep_mmacc_splitc_sxt_core (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .in_cmd_vld             (main_cmd_vld),
    .in_cmd_rdy             (main_cmd_rdy),
    .in_cmd_body            (main_cmd_body),
    .in_cmd_icmd            (main_cmd_icmd),

    .icmd_ack               (subs_cmd_ack),
    .icmd_loopback          (),/*UNUSED*/

    .garb_sxt_avail_1h      (garb_sxt_avail_1h),

    .sxt_gram_rd_en         (sxt_gram_rd_en),
    .sxt_gram_rd_add        (sxt_gram_rd_add),
    .gram_sxt_rd_data       (gram_sxt_rd_data),
    .gram_sxt_rd_data_avail (gram_sxt_rd_data_avail),

    .out_rot_data           (core_rot_data),
    .out_perm_select        (core_data_perm_select),
    .out_cmd                (core_data_cmd),
    .out_vld                (core_data_vld),
    .out_rdy                (core_data_rdy),

    .in_rot_data            (subs_part_data),
    .in_vld                 (subs_part_vld),
    .in_rdy                 (subs_part_rdy),

    .sxt_rif_req_dur        (sxt_rif_req_dur)

  );

// ============================================================================================= --
// SXT final
// ============================================================================================= --
  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0] in0_rot_data;
  logic                                 in0_data_vld;
  logic                                 in0_data_rdy;

  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0] in1_rot_data;
  logic                                 in1_data_vld;
  logic                                 in1_data_rdy;

  // (MSPLIT_MAIN_FACTOR < MSPLIT_DIV-1) means that there are at least 2 elements in subs.
  // Therefore, a join was done in subs, and we need to use this result here.

  generate
    if (MSPLIT_MAIN_FACTOR < MSPLIT_DIV-1) begin : gen_use_fmt
      assign {in1_rot_data, in0_rot_data}  = {core_rot_data, subs_fmt_data};
      assign {in1_data_vld, in0_data_vld}  = {core_data_vld,subs_fmt_vld};
      assign {core_data_rdy, subs_fmt_rdy} = {in1_data_rdy, in0_data_rdy};
    end
    else begin : gen_no_use_fmt
      assign {in1_rot_data, in0_rot_data} = core_rot_data;
      assign {in1_data_vld, in0_data_vld} = core_data_vld;
      assign core_data_rdy = {in1_data_rdy, in0_data_rdy};
      assign subs_fmt_rdy = 1'b0; // UNUSED
    end
  endgenerate

  pep_mmacc_splitc_sxt_final
  #(
    .INPUT_PIPE    (1'b0),
    .DATA_LATENCY  (DATA_LATENCY)
  ) pep_mmacc_splitc_sxt_final (
    .clk                   (clk),
    .s_rst_n               (s_rst_n),

    .in0_data_data         (in0_rot_data),
    .in0_data_vld          (in0_data_vld),
    .in0_data_rdy          (in0_data_rdy),

    .in1_data_data         (in1_rot_data),
    .in1_data_vld          (in1_data_vld),
    .in1_data_rdy          (in1_data_rdy),
    .in1_data_perm_select  (core_data_perm_select),
    .in1_data_cmd          (core_data_cmd),

    .sxt_regf_wr_req_vld   (sxt_regf_wr_req_vld),
    .sxt_regf_wr_req_rdy   (sxt_regf_wr_req_rdy),
    .sxt_regf_wr_req       (sxt_regf_wr_req),

    .sxt_regf_wr_data_vld  (sxt_regf_wr_data_vld),
    .sxt_regf_wr_data_rdy  (sxt_regf_wr_data_rdy),
    .sxt_regf_wr_data      (sxt_regf_wr_data),

    .regf_sxt_wr_ack       (regf_sxt_wr_ack),

    .sxt_seq_done          (sxt_seq_done),
    .sxt_seq_done_pid      (sxt_seq_done_pid),

    .sxt_rif_rcp_dur       (sxt_rif_rcp_dur)
  );

endmodule
