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
// LRAM : stands for LWE RAM
//
// ==============================================================================================

module pep_mmacc_splitc_feed_join
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_feed_pkg::*;
#(
  parameter int HPSI_SET_ID = 0,// Indicates which of the two R*PSI/2 coef sets is processed here
  parameter int CMD_ID      = 1 // Data to which the cmd are synchronized.
                                // If 0 : we need to delay them, to use them ar the correct moment.
)
(
  input  logic                                                           clk,        // clock
  input  logic                                                           s_rst_n,    // synchronous reset

  // Input data
  input  logic [PSI/4-1:0][R-1:0][MOD_Q_W-1:0]                           in0_data,
  input  logic [PSI/4-1:0][R-1:0][MOD_Q_W-1:0]                           in0_rot_data,
  input  logic                                                           in0_data_avail,

  input  logic [PSI/4-1:0][R-1:0][MOD_Q_W-1:0]                           in1_data,
  input  logic [PSI/4-1:0][R-1:0][MOD_Q_W-1:0]                           in1_rot_data,
  input  logic                                                           in1_data_avail,

  input  logic [1:0][PERM_W-1:0]                                         in_perm_select, // last 2 levels of permutation
  input  logic [LWE_COEF_W:0]                                            in_coef_rot_id0,
  input  logic [REQ_CMD_W-1:0]                                           in_rcmd,

  // Output data
  output logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                           out_data,
  output logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                           out_rot_data,
  output logic [PERM_W-1:0]                                              out_perm_select, // last 2 levels of permutation
  output logic [LWE_COEF_W:0]                                            out_coef_rot_id0,
  output logic [REQ_CMD_W-1:0]                                           out_rcmd,
  output logic                                                           out_data_avail
);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int QPSI = PSI / 4;
  localparam int HPSI = PSI / 2;

  localparam int PERM_SEL_OFS = HPSI*R*HPSI_SET_ID;

//=================================================================================================
// Input delay
//=================================================================================================
  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0] in0_data_dly;
  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0] in0_rot_data_dly;
  logic                                in0_data_avail_dly;

  always_ff @(posedge clk)
    if (!s_rst_n) in0_data_avail_dly <= '0;
    else          in0_data_avail_dly <= in0_data_avail;

  always_ff @(posedge clk) begin
    in0_data_dly     <= in0_data;
    in0_rot_data_dly <= in0_rot_data;
  end

  logic [LWE_COEF_W:0]    s3_coef_rot_id0;
  logic [REQ_CMD_W-1:0]   s3_rcmd;
  logic [1:0][PERM_W-1:0] s3_perm_select;

  generate
    if (CMD_ID == 0) begin : gen_dly_cmd
      // Synchronize like in0 data
      logic [LWE_COEF_W:0]    in0_coef_rot_id0_dly;
      logic [REQ_CMD_W-1:0]   in0_rcmd_dly;
      logic [1:0][PERM_W-1:0] in0_perm_select_dly;

      always_ff @(posedge clk) begin
        in0_coef_rot_id0_dly <= in_coef_rot_id0;
        in0_rcmd_dly         <= in_rcmd;
        in0_perm_select_dly  <= in_perm_select;
      end

      assign s3_coef_rot_id0 = in0_coef_rot_id0_dly;
      assign s3_rcmd         = in0_rcmd_dly;
      assign s3_perm_select  = in0_perm_select_dly;
    end
    else begin : gen_no_dly_cmd
      // Synchronize like in1 data
      assign s3_coef_rot_id0 = in_coef_rot_id0;
      assign s3_rcmd         = in_rcmd;
      assign s3_perm_select  = in_perm_select;
    end
  endgenerate

//=================================================================================================
// Permutation
//=================================================================================================
  logic [1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0] s3_rot_data;
  logic [1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0] s3_data;
  logic [1:0]                               s3_data_avail;
  logic [PERM_W-1:0]                        s3_perm_select_lv1;

  assign s3_rot_data[0] = in0_rot_data_dly;
  assign s3_rot_data[1] = in1_rot_data;

  assign s3_data[0] = in0_data_dly;
  assign s3_data[1] = in1_data;

  assign s3_data_avail[0] = in0_data_avail_dly;
  assign s3_data_avail[1] = in1_data_avail;

  assign s3_perm_select_lv1 = s3_perm_select[1]; // permutation level 1

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(s3_data_avail[0] == s3_data_avail[1])
      else begin
        $fatal(1,"%t > ERROR: QPSI coef not synchronized!" , $time);
      end
    end
// pragma translate_on

  logic [1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0] s4_rot_dataD;

  assign s4_rot_dataD[0] = s3_perm_select_lv1[(PERM_SEL_OFS+0)/(2*QPSI*R)] ? s3_rot_data[1] : s3_rot_data[0];
  assign s4_rot_dataD[1] = s3_perm_select_lv1[(PERM_SEL_OFS+0)/(2*QPSI*R)] ? s3_rot_data[0] : s3_rot_data[1];

//=================================================================================================
// Output
//=================================================================================================
  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] s4_data;
  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] s4_rot_data;
  logic                                s4_data_avail;
  logic [PERM_W-1:0]                   s4_perm_select;
  logic [LWE_COEF_W:0]                 s4_coef_rot_id0;
  logic [REQ_CMD_W-1:0]                s4_rcmd;

  always_ff @(posedge clk)
    if (!s_rst_n) s4_data_avail <= '0;
    else          s4_data_avail <= s3_data_avail[0]; // Both bits should be equal

  always_ff @(posedge clk) begin
    s4_data         <= s3_data;
    s4_rot_data     <= s4_rot_dataD;
    s4_perm_select  <= s3_perm_select[0]; // permutation level 0
    s4_coef_rot_id0 <= s3_coef_rot_id0;
    s4_rcmd         <= s3_rcmd;
  end

  assign out_data         = s4_data;
  assign out_rot_data     = s4_rot_data;
  assign out_perm_select  = s4_perm_select;
  assign out_coef_rot_id0 = s4_coef_rot_id0;
  assign out_rcmd         = s4_rcmd;

  assign out_data_avail   = s4_data_avail;

endmodule
