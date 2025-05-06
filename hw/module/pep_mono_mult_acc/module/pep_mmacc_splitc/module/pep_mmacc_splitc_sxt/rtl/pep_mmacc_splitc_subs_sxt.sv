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

module pep_mmacc_splitc_subs_sxt
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
  localparam int SUBS_PSI              = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV

)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  // main <-> subs cmd
  input  logic                                                     subs_cmd_vld,
  output logic                                                     subs_cmd_rdy,
  input  logic [LWE_COEF_W-1:0]                                    subs_cmd_body,
  input  logic [MMACC_INTERN_CMD_W-1:0]                            subs_cmd_icmd,
  output logic                                                     subs_cmd_ack,

  // main <-> subs data
  // Not used if SUBS_MSPLIT_FACTOR = 1
  output logic [SXT_SPLITC_COEF-1:0][MOD_Q_W-1:0]                  subs_data_data,
  output logic                                                     subs_data_vld,
  input  logic                                                     subs_data_rdy,

  // Used when MSPLIT_SUBS_FACTOR is odd
  output logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]            subs_part_data,
  output logic                                                     subs_part_vld,
  input  logic                                                     subs_part_rdy,

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]                                       garb_sxt_avail_1h,

  // GRAM
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     sxt_gram_rd_en,
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] sxt_gram_rd_add,
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]        gram_sxt_rd_data,
  input  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     gram_sxt_rd_data_avail,

  // For register if
  output logic                                                     sxt_rif_req_dur
);

// ============================================================================================= --
// localparam
// ============================================================================================= --
  localparam int QPSI = PSI / MSPLIT_DIV;

  localparam int CORE_FACTOR        = MSPLIT_SUBS_FACTOR;
  localparam int CORE_PSI           = CORE_FACTOR * PSI / MSPLIT_DIV;
  localparam int CORE_CTRL_NB       = (CORE_FACTOR+1) / 2;

  localparam int DISP_FACTOR        = MSPLIT_SUBS_FACTOR > 1 ? (MSPLIT_SUBS_FACTOR / 2) * 2: 1;
  localparam int DISP_PSI           = PSI * DISP_FACTOR / MSPLIT_DIV;
  localparam int USE_FORMAT         = (MSPLIT_SUBS_FACTOR > 1) && (SXT_SPLITC_COEF < R*DISP_PSI);

  generate
    if (SXT_SPLITC_COEF > R*SUBS_PSI) begin : __UNSUPPORTED_SXT_SPLITC_COEF
      $fatal(1,"> ERROR: SXT_SPLITC_COEF (%0d) should be less or equal to R*SUBS_PSI (%0d).",SXT_SPLITC_COEF,R*SUBS_PSI);
    end
  endgenerate

// ============================================================================================= --
// SXT core
// ============================================================================================= --
  logic [CORE_PSI-1:0][R-1:0][MOD_Q_W-1:0] sxt_data_data;
  logic [CORE_CTRL_NB-1:0]                 sxt_data_vld;
  logic [CORE_CTRL_NB-1:0]                 sxt_data_rdy;

  pep_mmacc_splitc_sxt_core
  #(
    .DATA_LATENCY       (DATA_LATENCY),
    .WAIT_FOR_ACK       (1'b0),
    .MSPLIT_FACTOR      (MSPLIT_SUBS_FACTOR),
    .HPSI_SET_ID        (0),
    .JOIN_LIMIT         (USE_FORMAT)
  ) pep_mmacc_splitc_sxt_core (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .in_cmd_vld             (subs_cmd_vld),
    .in_cmd_rdy             (subs_cmd_rdy),
    .in_cmd_body            (subs_cmd_body),
    .in_cmd_icmd            (subs_cmd_icmd),

    .icmd_ack               (),/*UNUSED*/
    .icmd_loopback          (subs_cmd_ack),

    .garb_sxt_avail_1h      (garb_sxt_avail_1h),

    .sxt_gram_rd_en         (sxt_gram_rd_en),
    .sxt_gram_rd_add        (sxt_gram_rd_add),
    .gram_sxt_rd_data       (gram_sxt_rd_data),
    .gram_sxt_rd_data_avail (gram_sxt_rd_data_avail),

    .out_rot_data           (sxt_data_data),
    .out_perm_select        (),/*UNUSED*/
    .out_cmd                (),/*UNUSED*/
    .out_vld                (sxt_data_vld),
    .out_rdy                (sxt_data_rdy),

    .in_rot_data            ('x),  /*UNUSED*/
    .in_vld                 (1'b0),/*UNUSED*/
    .in_rdy                 (),    /*UNUSED*/

    .sxt_rif_req_dur        (sxt_rif_req_dur)

  );

// ============================================================================================= --
// Format
// ============================================================================================= --
  generate
    if (MSPLIT_SUBS_FACTOR > 1) begin: gen_msplit_factor_gt_1
      // If USE_FORMAT == 0, this module does nothing
      stream_disp_format
      #(
        .OP_W       (MOD_Q_W),
        .IN_COEF    (DISP_PSI * R),
        .OUT_COEF   (SXT_SPLITC_COEF),
        .IN_PIPE    (1'b1)
      ) stream_disp_format (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (sxt_data_data[0+:DISP_PSI]),
        .in_vld   (sxt_data_vld[0]),
        .in_rdy   (sxt_data_rdy[0]),

        .out_data (subs_data_data),
        .out_vld  (subs_data_vld),
        .out_rdy  (subs_data_rdy)
      );

    end
    else begin : gen_msplit_factor_le_1
      // This path is unused
      assign subs_data_data = 'x;
      assign subs_data_vld  = 1'b0;
    end

    if ((MSPLIT_SUBS_FACTOR % 2) == 1) begin : gen_part
      assign subs_part_data               = sxt_data_data[SUBS_PSI-1-:QPSI];
      assign subs_part_vld                = sxt_data_vld[CORE_CTRL_NB-1];
      assign sxt_data_rdy[CORE_CTRL_NB-1] = subs_part_rdy;
      if (CORE_CTRL_NB > 2) begin : gen_core_ctrl_nb_gt_2
        assign sxt_data_rdy[CORE_CTRL_NB-2:1] = {CORE_CTRL_NB-2{sxt_data_rdy[0]}};
      end
    end
    else begin : gen_no_part
      assign subs_part_data                = 'x;
      assign subs_part_vld                 = 1'b0;
      if (CORE_CTRL_NB > 1) begin : gen_core_ctrl_nb_gt_1
        assign sxt_data_rdy[CORE_CTRL_NB-1:1] = {CORE_CTRL_NB-1{sxt_data_rdy[0]}};
      end
    end
  endgenerate
endmodule
