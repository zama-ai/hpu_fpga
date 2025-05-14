// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : arith_mult_64bgoldilocks_karatsuba
// ----------------------------------------------------------------------------------------------
//
// arith_mult_64bgoldilocks_karatsuba : z = a * b
// with specific optimisations for the Goldilocks Prime 2^64-2^32+1.
//
// Optimisations:
//  - Number of Muliplications is reduced with Karatsuba
//  - Width of output z is reduced from 128 bits to 98 bits
//
// The latency of the module is LAT_KARATSUBA + 3
//
// Parameters :
//
//  Parameters related to Operand width are omitted as they are fixed.
//
// ==============================================================================================

module arith_mult_64bgoldilocks_karatsuba_cascade #(
  // PARAMETERS ====================================================================================
  parameter int   SIDE_W      = 0,    // Side data size. Set to 0 if not used
  parameter [1:0] RST_SIDE    = 2'b10 // If side data is used,
                                      // [0] (1) reset them to 0.
                                      // [1] (1) reset them to 1.
  ) (
  // ===============================================================================================
  // System interface ------------------------------------------------------------------------------
  input  logic              clk,
  input  logic              s_rst_n,
  // Data interface --------------------------------------------------------------------------------
  input  logic [      63:0] a,
  input  logic [      63:0] b,
  output logic [      97:0] z,
  // Control ---------------------------------------------------------------------------------------
  input  logic              in_avail,
  output logic              out_avail,
  input  logic [SIDE_W-1:0] in_side,
  output logic [SIDE_W-1:0] out_side
  );

  import arith_mult_64bgoldilocks_karatsuba_pkg::*;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  localparam int     OP_A_W         = 64;
  localparam int     OP_B_W         = 64;
  localparam int     KARATSUBA_OP_W = 32; // OP_A_W > OP_B_W ? OP_A_W/2 : OP_B_W/2;
  localparam int     LSB_W          = KARATSUBA_OP_W;
  localparam int     MSB_A_W        = 32; // OP_A_W - KARATSUBA_OP_W;
  localparam int     MSB_B_W        = 32; // OP_B_W - KARATSUBA_OP_W;
  localparam int     MAX_MSB_W      = 32; // MSB_A_W > MSB_B_W ? MSB_A_W : MSB_B_W;
  localparam int     MAX_SB_W       = 32; // LSB_W > MAX_MSB_W ? LSB_W : MAX_MSB_W;

  // -------------------------------------------------------------------------------------------- //
  // S0 : Input and CLB pre adder
  // -------------------------------------------------------------------------------------------- //
  logic [OP_A_W-1:0] s0_a;
  logic [OP_B_W-1:0] s0_b;
  logic [MAX_SB_W:0] s0_a_lo_plus_a_hi;
  logic [MAX_SB_W:0] s0_b_lo_plus_b_hi;

  always_ff @(posedge clk) begin
    s0_a <= a;
    s0_b <= b;
  end

  assign s0_a_lo_plus_a_hi = s0_a[0+:LSB_W] + s0_a[LSB_W+:MSB_A_W];
  assign s0_b_lo_plus_b_hi = s0_b[0+:LSB_W] + s0_b[LSB_W+:MSB_B_W];

  // -------------------------------------------------------------------------------------------- //
  // S1 : data pre-compute
  // Latency = 6 clock cycles
  // -------------------------------------------------------------------------------------------- //
  // Compute :
  // s1_a_hi_x_b_hi    :  a_hi * b_hi
  // s1_a_lo_x_b_lo    :  a_lo * b_lo
  // s1_sub_of_product : (a_lo * b_lo) - (a_hi * b_hi)
  // s1_product_of_sum : (a_lo + a_hi) * (b_lo + b_hi)
  //-------------------------------------------
  logic [MSB_A_W+MSB_B_W-1:0] s1_a_hi_x_b_hi;
  logic [        2*LSB_W-1:0] s1_a_lo_x_b_lo;
  logic [       2*MAX_SB_W:0] s1_sub_of_product;

  arith_mult_karatsuba_cascade #(
    .OP_A_W   (LSB_W    ),
    .OP_B_W   (LSB_W    ),
    .SIDE_W   (0        ),
    .RST_SIDE (0        )
  ) karatsuba_mult_s1_a_hi_x_b_hi (
    .clk      (clk                 ),
    .s_rst_n  (s_rst_n             ),
    .a        (s0_a[LSB_W+:MSB_A_W]),
    .b        (s0_b[LSB_W+:MSB_B_W]),
    .z        (s1_a_hi_x_b_hi      ),
    .in_avail ('x                  ),/*UNUSED*/
    .out_avail(/*UNUSED*/          ),
    .in_side  ('x                  ),/*UNUSED*/
    .out_side (/*UNUSED*/          )
  );

  arith_mult_karatsuba_cascade #(
    .OP_A_W   (LSB_W    ),
    .OP_B_W   (LSB_W    ),
    .SIDE_W   (0        ),
    .RST_SIDE (0        )
  ) karatsuba_mult_s1_a_lo_x_b_lo (
    .clk      (clk           ),
    .s_rst_n  (s_rst_n       ),
    .a        (s0_a[0+:LSB_W]),
    .b        (s0_b[0+:LSB_W]),
    .z        (s1_a_lo_x_b_lo),
    .in_avail ('x            ),/*UNUSED*/
    .out_avail(/*UNUSED*/    ),
    .in_side  ('x            ),/*UNUSED*/
    .out_side (/*UNUSED*/    )
  );

  assign s1_sub_of_product = s1_a_lo_x_b_lo - s1_a_hi_x_b_hi;

  //-------------------------------------------
  // Compute :
  // (a_lo + a_hi) * (b_lo + b_hi)
  //-------------------------------------------
  logic [2*(MAX_SB_W+1)-1:0] s1_product_of_sum;

  arith_mult_karatsuba_cascade #(
    .OP_A_W        (MAX_SB_W + 1),
    .OP_B_W        (MAX_SB_W + 1),
    .KARATSUBA_OP_W(16          ), // do not touch
    .SIDE_W        (0           ),
    .RST_SIDE      (0           )
  ) karatsuba_mult_s1_product_of_sum (
    .clk      (clk              ),
    .s_rst_n  (s_rst_n          ),
    .a        (s0_a_lo_plus_a_hi),
    .b        (s0_b_lo_plus_b_hi),
    .z        (s1_product_of_sum),
    .in_avail ('x               ),/*UNUSED*/
    .out_avail(/*UNUSED*/       ),
    .in_side  ('x               ),/*UNUSED*/
    .out_side (/*UNUSED*/       )
  );

  // -------------------------------------------------------------------------------------------- //
  // S2 : Final addition
  // -------------------------------------------------------------------------------------------- //
  logic [        2*LSB_W-1:0] s2_a_lo_x_b_lo;
  logic [       2*MAX_SB_W:0] s2_sub_of_product;
  logic [ 2*(MAX_SB_W+1)-1:0] s2_product_of_sum;
  logic [OP_A_W + OP_B_W-1:0] s2_result;

  always_ff @(posedge clk) begin
    s2_a_lo_x_b_lo    <= s1_a_lo_x_b_lo;
    s2_sub_of_product <= s1_sub_of_product;
    s2_product_of_sum <= s1_product_of_sum;
  end

  assign s2_result = s2_sub_of_product[2*MAX_SB_W] ?
                      ((s2_product_of_sum - s2_a_lo_x_b_lo) << LSB_W) - ({1'b0, ~s2_sub_of_product[2*MAX_SB_W-1:0]} + 1)
                    : ((s2_product_of_sum - s2_a_lo_x_b_lo) << LSB_W) + s2_sub_of_product;

  // -------------------------------------------------------------------------------------------- //
  // S3 : result
  // -------------------------------------------------------------------------------------------- //
  logic [OP_A_W + OP_B_W-1:0] s3_result;

  always_ff @(posedge clk) begin
    s3_result <= s2_result;
  end

  common_lib_delay_side #(
    .LATENCY    (arith_mult_64bgoldilocks_karatsuba_cascade_pkg::get_latency()),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) s1_delay_side (
    .clk      (clk          ),
    .s_rst_n  (s_rst_n      ),
    .in_avail (in_avail     ),
    .out_avail(out_avail    ),
    .in_side  (in_side      ),
    .out_side (out_side     )
  );

  assign z = s3_result;

endmodule
