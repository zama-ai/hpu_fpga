// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : arith_mult_kara_core
// ----------------------------------------------------------------------------------------------
//
// arith_mult_kara_core :
//         z_0 = (a_1 * b_1)
//         z_1 = (a_1 * b_1) + (a_0 * b_0)
//         z_2 = ((a_0 + a_1) * (b_0 + b_1)) - ((a_1 * b_1) + (a_0 * b_0))
//
// Latency of this module is fixed, the aim is to compute z in two DSPs without using CLBs
//
// Parameters :
//  OP_A_W,       : Operand width A and C
//  OP_B_W        : Operand width B and D
// ==============================================================================================

module arith_mult_kara_core #(
    parameter  int LSB_W            = 16,
    parameter  int MSB_A_W          = 16,
    parameter  int MSB_B_W          = 16,
    localparam int PROD_L_W         = 2*LSB_W,
    localparam int PROD_H_W         = MSB_A_W + MSB_B_W,
    localparam int SUM_OF_PRODUCT_W = PROD_H_W > PROD_L_W ? PROD_H_W + 1 : PROD_L_W + 1,
    localparam int SUM_A_W          = LSB_W > MSB_A_W ? LSB_W + 1 : MSB_A_W + 1,
    localparam int SUM_B_W          = LSB_W > MSB_B_W ? LSB_W + 1 : MSB_B_W + 1,
    localparam int PRODUCT_OF_SUM_W = SUM_B_W + SUM_A_W,
    localparam int DIFF_W           = PRODUCT_OF_SUM_W > SUM_OF_PRODUCT_W ? PRODUCT_OF_SUM_W : SUM_OF_PRODUCT_W
  ) (
    // System interface
    input  logic                        clk,
    // Data interface
    input  logic [LSB_W-1:0]            a_0,
    input  logic [LSB_W-1:0]            b_0,
    input  logic [MSB_A_W-1:0]          a_1,
    input  logic [MSB_B_W-1:0]          b_1,

    output logic [PROD_H_W-1:0]         z_0,
    output logic [SUM_OF_PRODUCT_W-1:0] z_1,
    output logic [DIFF_W:0]             z_2 // signed
  );

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  // DSP A :
  logic [MSB_A_W-1:0] row_dspa_a1 [1:0];
  logic [MSB_B_W-1:0] row_dspa_b1 [1:0];
  logic [PROD_H_W-1:0] multiplier_dsp_a [1:0];

  // Computes (a_1 * b_1) in one DSP
  // 1 x 2 inputs reg
  // 1 Multiplier reg
  // 1 Product reg
  always_ff @(posedge clk) begin : DSPA
    row_dspa_a1[1] <= a_1;
    row_dspa_b1[1] <= b_1;

    multiplier_dsp_a[0] <= row_dspa_a1[1] * row_dspa_b1[1];
    multiplier_dsp_a[1] <= multiplier_dsp_a[0];
  end

  // DSP B :
  logic [LSB_W-1:0] row_dspb_a0 [1:0];
  logic [LSB_W-1:0] row_dspb_b0 [1:0];
  logic [SUM_OF_PRODUCT_W-1:0] multiplier_dsp_b [1:0];

  // Computes (a_0 * b_0) + (a_1 * b_1) in one DSP
  // 2 x 2 input reg
  // 1 multiplier reg
  // 1 product (M + PCIN_DSP_A)
  always_ff @(posedge clk) begin : DSPB
    row_dspb_a0[0] <= a_0;
    row_dspb_b0[0] <= b_0;

    row_dspb_a0[1] <= row_dspb_a0[0];
    row_dspb_b0[1] <= row_dspb_b0[0];

    multiplier_dsp_b[0] <= row_dspb_a0[1] * row_dspb_b0[1];
    multiplier_dsp_b[1] <= multiplier_dsp_b[0] + multiplier_dsp_a[1];

  end

  // DSP C :
  logic [LSB_W-1:0]   temp_a0;
  logic [MSB_A_W-1:0] temp_a1;
  logic [LSB_W-1:0]   temp_b0;
  logic [MSB_B_W-1:0] temp_b1;

  // Buffer line before DSP C
  always_ff @(posedge clk) begin
    temp_a0 <= a_0;
    temp_a1 <= a_1;
    temp_b0 <= b_0;
    temp_b1 <= b_1;
  end

  logic [SUM_B_W-1:0] clb_addition;

  assign clb_addition = temp_b0 + temp_b1;


  logic [LSB_W-1:0]    row_dspc_a0;
  logic [MSB_A_W-1:0]  row_dspc_a1;
  logic [SUM_A_W-1:0]  dsp_addition;

  logic [SUM_B_W-1:0]  row_dspc_b [1:0];
  logic [DIFF_W:0]     multiplier_dsp_c [1:0];

  always_ff @(posedge clk) begin : DSPC
    // pre adder
    row_dspc_a0   <= temp_a0;
    row_dspc_a1   <= temp_a1;

    dsp_addition <= row_dspc_a0 + row_dspc_a1;

    // input register
    row_dspc_b[0] <= clb_addition;
    row_dspc_b[1] <= row_dspc_b[0];

    multiplier_dsp_c[0] <= dsp_addition * row_dspc_b[1];
    multiplier_dsp_c[1] <= multiplier_dsp_c[0] - multiplier_dsp_b[1] ;
  end

  assign z_0 = multiplier_dsp_a[1]; // (c * d)
  assign z_1 = multiplier_dsp_b[1]; // (a * b) + (c * d)
  assign z_2 = multiplier_dsp_c[1]; // (a + c) - [(a * b) + (c * d)]

endmodule
