// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : arith_mult_karatsuba
// ----------------------------------------------------------------------------------------------
//
// arith_mult_karatsuba : z = a * b
// with Karatsuba algorithm.
//
// The latency of the module is fixed to 6 clock cycles
//
// Parameters :
//  KARATSUBA_OP_W : Karatsuba algorithm LSB part width.
//  OP_A_W,
//  OP_B_W        : Operand width
// ==============================================================================================

module arith_mult_karatsuba_cascade #(
  // PARAMETERS ====================================================================================
  parameter int     OP_A_W = 33,
  parameter int     OP_B_W = 33,
  // Karatsuba -------------------------------------------------------------------------------------
  parameter int     KARATSUBA_OP_W = 16,
  parameter int     SIDE_W         = 0,// Side data size. Set to 0 if not used
  parameter [1:0]   RST_SIDE       = 0 // If side data is used,
                                       // [0] (1) reset them to 0.
                                       // [1] (1) reset them to 1.
) (
  // ===============================================================================================
  // System interface ------------------------------------------------------------------------------
  input  logic                       clk,
  input  logic                       s_rst_n,
  // Data interface --------------------------------------------------------------------------------
  input  logic [         OP_A_W-1:0] a,
  input  logic [         OP_B_W-1:0] b,
  output logic [OP_A_W + OP_B_W-1:0] z,
  // Control ---------------------------------------------------------------------------------------
  input  logic                       in_avail,
  output logic                       out_avail,
  input  logic [         SIDE_W-1:0] in_side,
  output logic [         SIDE_W-1:0] out_side
);

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  localparam int LSB_W            = KARATSUBA_OP_W;
  localparam int MSB_A_W          = OP_A_W - KARATSUBA_OP_W;
  localparam int MSB_B_W          = OP_B_W - KARATSUBA_OP_W;
  localparam int PROD_L_W         = 2*LSB_W;
  localparam int PROD_H_W         = MSB_A_W + MSB_B_W;
  localparam int SUM_OF_PRODUCT_W = PROD_H_W > PROD_L_W ? PROD_H_W + 1 : PROD_L_W + 1;
  localparam int SUM_A_W          = LSB_W > MSB_A_W ? LSB_W + 1 : MSB_A_W + 1;
  localparam int SUM_B_W          = LSB_W > MSB_B_W ? LSB_W + 1 : MSB_B_W + 1;
  localparam int PRODUCT_OF_SUM_W = SUM_B_W + SUM_A_W;
  localparam int DIFF_W           = PRODUCT_OF_SUM_W > SUM_OF_PRODUCT_W ? PRODUCT_OF_SUM_W : SUM_OF_PRODUCT_W;

  // Check parameters
  generate
    if ((OP_A_W <= KARATSUBA_OP_W) || (OP_B_W <= KARATSUBA_OP_W)) begin: __UNSUPPORTED_KARATSUBA_OP_W__
      $fatal(1, "> ERROR: Unsupported KARATSUBA_OP_W (%0d) and OP_A_W (%0d), OP_B_W (%0d). The operands size are too small.",KARATSUBA_OP_W, OP_A_W, OP_B_W);
    end
    
    if ( (!((OP_A_W == 32 || OP_A_W==33) && (OP_B_W == 32 || OP_B_W==33) && (KARATSUBA_OP_W == 16 || KARATSUBA_OP_W == 17)))) begin: __UNSUPPORTED_KARATSUBA_CASCADE_PARAM__
      $fatal(1, "> ERROR: Unsupported KARATSUBA_OP_W (%0d) and OP_A_W (%0d), OP_B_W (%0d) for cascading.", KARATSUBA_OP_W, OP_A_W, OP_B_W);
    end 
  endgenerate

  // -------------------------------------------------------------------------------------------- //
  // Karatsuba core
  // -------------------------------------------------------------------------------------------- //
  logic [PROD_H_W-1:0]         s0_a_hi_x_b_hi;
  logic [SUM_OF_PRODUCT_W-1:0] s1_sum_of_product;
  logic [DIFF_W:0]             s2_diff; // signed


  // Stage 0 : 3CC
  arith_mult_kara_core #(
    .LSB_W    (LSB_W  ),
    .MSB_A_W  (MSB_A_W),
    .MSB_B_W  (MSB_B_W)
  ) arith_mult_kara_core_inst (
    .clk (clk ),
    .a_0 (a[0+:LSB_W]      ),
    .b_0 (b[0+:LSB_W]      ),
    .a_1 (a[LSB_W+:MSB_A_W]),
    .b_1 (b[LSB_W+:MSB_B_W]),
    .z_0 (s0_a_hi_x_b_hi   ), // z_0 = (a_1 * b_1)
    .z_1 (s1_sum_of_product), // z_1 = (a_1 * b_1) + (a_0 * b_0)
    .z_2 (s2_diff)            // z_2 = ((a_0 + a_1) * (b_0 + b_1)) - ((a_1 * b_1) + (a_0 * b_0))
  );

  // Stage 1 :
  // z_0 is ready, we register it
  logic [PROD_H_W-1:0] s1_a_hi_x_b_hi;

  always_ff @(posedge clk) begin
    s1_a_hi_x_b_hi <= s0_a_hi_x_b_hi;
  end

  // Stage 2 :
  // z_1 is ready, we compute s2_a_lo_x_b_lo and register s2_a_hi_x_b_hi
  logic [OP_A_W + OP_B_W-1:0] s1_result_part1;
  logic [OP_A_W + OP_B_W-1:0] s2_result_part1;

  // Write the following way, so that vivado does not optimize this into a DSP.
  (* USE_DSP = "no" *) logic [2*LSB_W-1:0]  s1_a_lo_x_b_lo;
  assign s1_a_lo_x_b_lo = s1_sum_of_product - s1_a_hi_x_b_hi;
  assign s1_result_part1 = {s1_a_hi_x_b_hi,s1_a_lo_x_b_lo}; 
  // If the flag "USE_DSP" does not work : write the following way, so that vivado does not optimize this into a DSP.
  // But the adder used will be larger.
  // assign s1_result_part1 = (s1_a_hi_x_b_hi << (2*LSB_W)) + s1_sum_of_product - s1_a_hi_x_b_hi;

  always_ff @(posedge clk) begin
    s2_result_part1 <= s1_result_part1;
  end

  // Stage 3 :
  // z2 is ready, we do the final computation
  logic [OP_A_W + OP_B_W-1:0] s3_result;

  always_ff @(posedge clk) begin
    s3_result <= s2_result_part1+
                ({{OP_A_W+OP_B_W-DIFF_W{s2_diff[DIFF_W]}},s2_diff} << LSB_W);
  end

  // -------------------------------------------------------------------------------------------- //
  // Delay line
  // -------------------------------------------------------------------------------------------- //
  common_lib_delay_side #(
    .LATENCY    (6),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) s1_delay_side (
    .clk      (clk          ),
    .s_rst_n  (s_rst_n      ),
    .in_avail (in_avail     ),
    .out_avail(out_avail     ),
    .in_side  (in_side      ),
    .out_side (out_side      )
  );

  // -------------------------------------------------------------------------------------------- //
  // Output assignation
  // -------------------------------------------------------------------------------------------- //
  assign z         = s3_result;

endmodule
