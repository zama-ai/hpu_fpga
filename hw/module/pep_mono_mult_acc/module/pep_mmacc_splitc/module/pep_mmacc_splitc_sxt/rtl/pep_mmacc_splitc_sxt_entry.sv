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

module pep_mmacc_splitc_sxt_entry
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
(
  input  logic                                                   clk,        // clock
  input  logic                                                   s_rst_n,    // synchronous reset

  // From sfifo
  input  logic [MMACC_INTERN_CMD_W-1:0]                          sfifo_sxt_icmd,
  input  logic                                                   sfifo_sxt_vld,
  output logic                                                   sfifo_sxt_rdy,

  // sxt <-> body RAM
  input  logic [LWE_COEF_W-1:0]                                  boram_sxt_data,
  input  logic                                                   boram_sxt_data_vld,
  output logic                                                   boram_sxt_data_rdy,


  // Output cmd
  output logic                                                   subs_cmd_vld,
  input  logic                                                   subs_cmd_rdy,
  output logic [LWE_COEF_W-1:0]                                  subs_cmd_body,
  output logic [MMACC_INTERN_CMD_W-1:0]                          subs_cmd_icmd,

  output logic                                                   main_cmd_vld,
  input  logic                                                   main_cmd_rdy,
  output logic [LWE_COEF_W-1:0]                                  main_cmd_body,
  output logic [MMACC_INTERN_CMD_W-1:0]                          main_cmd_icmd,

  // For register if
  output logic                                                   sxt_rif_cmd_wait_b_dur

);

// ============================================================================================= --
// Input pipe
// ============================================================================================= --
  //== body
  logic [LWE_COEF_W-1:0]  sm1_body;
  logic                   sm1_body_vld;
  logic                   sm1_body_rdy;
  fifo_element #(
    .WIDTH          (LWE_COEF_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) body_fifo_element (
    .clk     (clk),
    .s_rst_n(s_rst_n),

    .in_data (boram_sxt_data),
    .in_vld  (boram_sxt_data_vld),
    .in_rdy  (boram_sxt_data_rdy),

    .out_data(sm1_body),
    .out_vld (sm1_body_vld),
    .out_rdy (sm1_body_rdy)
  );

// ============================================================================================= --
// Sm1
// ============================================================================================= --
// Synchronize command and body paths.
  logic sm1_vld;
  logic sm1_rdy;

  assign sm1_vld       = sfifo_sxt_vld && sm1_body_vld;
  assign sm1_body_rdy  = sm1_rdy & sfifo_sxt_vld;
  assign sfifo_sxt_rdy = sm1_rdy & sm1_body_vld;

  mmacc_intern_cmd_t sm1_icmd;

  assign sm1_icmd = sfifo_sxt_icmd;

  logic                   s0_vld;
  logic                   s0_rdy;
  mmacc_intern_cmd_t      s0_icmd;
  logic [LWE_COEF_W-1:0]  s0_body;

  fifo_element #(
    .WIDTH          (LWE_COEF_W+MMACC_INTERN_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) sm1_fifo_element (
    .clk     (clk),
    .s_rst_n(s_rst_n),

    .in_data ({sm1_body, sm1_icmd}),
    .in_vld  (sm1_vld),
    .in_rdy  (sm1_rdy),

    .out_data({s0_body, s0_icmd}),
    .out_vld (s0_vld),
    .out_rdy (s0_rdy)
  );

// ============================================================================================= --
// S0
// ============================================================================================= --
  // Fork between main and subsidiary part.
  logic     subs_in_vld;
  logic     subs_in_rdy;

  logic     main_in_vld;
  logic     main_in_rdy;

  assign subs_in_vld = s0_vld & main_in_rdy;
  assign main_in_vld = s0_vld & subs_in_rdy;
  assign s0_rdy      = subs_in_rdy & main_in_rdy;

  fifo_element #(
    .WIDTH          (LWE_COEF_W + MMACC_INTERN_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) subs_in_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({s0_body, s0_icmd}),
    .in_vld  (subs_in_vld),
    .in_rdy  (subs_in_rdy),

    .out_data({subs_cmd_body, subs_cmd_icmd}),
    .out_vld (subs_cmd_vld),
    .out_rdy (subs_cmd_rdy)
  );

  fifo_element #(
    .WIDTH          (LWE_COEF_W + MMACC_INTERN_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) main_in_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({s0_body, s0_icmd}),
    .in_vld  (main_in_vld),
    .in_rdy  (main_in_rdy),

    .out_data({main_cmd_body, main_cmd_icmd}),
    .out_vld (main_cmd_vld),
    .out_rdy (main_cmd_rdy)
  );

// ============================================================================================= --
// Info for register if
// ============================================================================================= --
  logic sxt_rif_cmd_wait_b_durD;

  assign sxt_rif_cmd_wait_b_durD = sfifo_sxt_vld & ~sm1_body_vld;

  always_ff @(posedge clk)
    if (!s_rst_n) sxt_rif_cmd_wait_b_dur <= 1'b0;
    else          sxt_rif_cmd_wait_b_dur <= sxt_rif_cmd_wait_b_durD;

endmodule
