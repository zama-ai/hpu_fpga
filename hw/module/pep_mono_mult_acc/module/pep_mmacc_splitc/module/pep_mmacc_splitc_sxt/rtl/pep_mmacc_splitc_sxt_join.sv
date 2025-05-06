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

`include "pep_mmacc_splitc_sxt_macro_inc.sv"


module pep_mmacc_splitc_sxt_join
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_sxt_pkg::*;
#(
  parameter int HPSI_SET_ID  = 0,    // Indicates which of the two R*PSI/2 coef sets is processed here
  parameter int DATA_LATENCY = 6,     // Latency for read data to come back
  parameter bit CHECK_SYNCHRONIZATION = 1'b0 // Assertion : check that in0 and in1 are correctly synchronized.
)
(
  input  logic                                                           clk,        // clock
  input  logic                                                           s_rst_n,    // synchronous reset

  // Input data
  input  logic [PSI/4-1:0][R-1:0][MOD_Q_W-1:0]                           in0_rot_data,
  input  logic                                                           in0_vld,
  output logic                                                           in0_rdy,

  input  logic [PSI/4-1:0][R-1:0][MOD_Q_W-1:0]                           in1_rot_data,
  input  logic [1:0][PERM_W-1:0]                                         in1_perm_select, // last 2 levels of permutation
  input  logic [CMD_X_W-1:0]                                             in1_cmd,
  input  logic                                                           in1_vld,
  output logic                                                           in1_rdy,

  // Output data
  output logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                           out_rot_data,
  output logic [PERM_W-1:0]                                              out_perm_select, // last 2 levels of permutation
  output logic [CMD_X_W-1:0]                                             out_cmd,
  output logic                                                           out_vld,
  input  logic                                                           out_rdy,

  output logic                                                           buf_cnt_do_dec // output join_buffer is being read.

);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int QPSI = PSI / 4;
  localparam int HPSI = PSI / 2;

  localparam int PERM_SEL_OFS = HPSI*R*HPSI_SET_ID;

  `PEP_MMACC_SPLITC_SXT_LOCALPARAM(R,PSI,DATA_LATENCY,REGF_COEF_NB,REGF_COEF_PER_URAM_WORD,REGF_BLWE_WORD_PER_RAM,DATA_THRESHOLD)

//=================================================================================================
// Input pipe
//=================================================================================================
  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0] in0_dly_rot_data;
  logic                                in0_dly_vld;
  logic                                in0_dly_rdy;

  fifo_element #(
    .WIDTH          (QPSI*R*MOD_Q_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h1), // To delay the data / vld
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) in0_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (in0_rot_data),
    .in_vld  (in0_vld),
    .in_rdy  (in0_rdy),

    .out_data(in0_dly_rot_data),
    .out_vld (in0_dly_vld),
    .out_rdy (in0_dly_rdy)
  );

//=================================================================================================
// Permutation
//=================================================================================================
  logic [1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0] x3_rot_data;
  logic [PERM_W-1:0]                        x3_perm_select;
  logic                                     x3_vld;
  logic                                     x3_rdy;

  assign x3_rot_data[0] = in0_dly_rot_data;
  assign x3_rot_data[1] = in1_rot_data;

  assign x3_vld      = in0_dly_vld & in1_vld;
  assign in0_dly_rdy = in1_vld & x3_rdy;
  assign in1_rdy     = in0_dly_vld & x3_rdy;

  assign x3_perm_select = in1_perm_select[1]; // permutation level 1

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (CHECK_SYNCHRONIZATION) begin
        assert(in1_vld == in0_dly_vld)
        else begin
          $fatal(1,"%t > ERROR: QPSI coef not synchronized!" , $time);
        end
      end
    end
// pragma translate_on

  logic [1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0] x3_perm_data;

  assign x3_perm_data[0] = x3_perm_select[(PERM_SEL_OFS+0)/(2*QPSI*R)] ? x3_rot_data[1] : x3_rot_data[0];
  assign x3_perm_data[1] = x3_perm_select[(PERM_SEL_OFS+0)/(2*QPSI*R)] ? x3_rot_data[0] : x3_rot_data[1];

  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] x4_perm_data;
  logic [PERM_W-1:0]                   x4_perm_select;
  cmd_x_t                              x4_cmd;
  logic                                x4_vld;
  logic                                x4_rdy;

  fifo_element #(
    .WIDTH          ($bits(cmd_x_t)+PERM_W+HPSI*R*MOD_Q_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h1),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) x3_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({in1_cmd,in1_perm_select[0],x3_perm_data}),
    .in_vld  (x3_vld),
    .in_rdy  (x3_rdy),

    .out_data({x4_cmd,x4_perm_select,x4_perm_data}),
    .out_vld (x4_vld),
    .out_rdy (x4_rdy)
  );

//=================================================================================================
// Output FIFO
//=================================================================================================
  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0]  x5_perm_data;
  logic [PERM_W-1:0]                    x5_perm_select;
  cmd_x_t                               x5_cmd;
  logic                                 x5_vld;
  logic                                 x5_rdy;

  fifo_reg #(
    .WIDTH       (HPSI*R*MOD_Q_W + PERM_W + CMD_X_W),
    .DEPTH       (JOIN_FIFO_DEPTH),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) join_fifo (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({x4_cmd,x4_perm_select,x4_perm_data}),
    .in_vld  (x4_vld),
    .in_rdy  (x4_rdy),

    .out_data({x5_cmd,x5_perm_select,x5_perm_data}),
    .out_vld (x5_vld),
    .out_rdy (x5_rdy)
  );

  logic x5_buf_cnt_do_dec;

  assign x5_buf_cnt_do_dec = x5_vld & x5_rdy;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (x4_vld)
        assert(x4_rdy)
        else begin
          $fatal(1,"%t > ERROR: join_fifo overflow!",$time);
        end
    end
// pragma translate_on

//=================================================================================================
// Output
//=================================================================================================
  assign out_rot_data    = x5_perm_data;
  assign out_perm_select = x5_perm_select;
  assign out_cmd         = x5_cmd;
  assign out_vld         = x5_vld;
  assign x5_rdy          = out_rdy;

  always_ff @(posedge clk)
    if (!s_rst_n) buf_cnt_do_dec <= 1'b0;
    else          buf_cnt_do_dec <= x5_buf_cnt_do_dec;

endmodule
