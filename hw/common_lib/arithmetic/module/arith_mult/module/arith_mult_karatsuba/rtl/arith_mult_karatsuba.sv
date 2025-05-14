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
// The latency of the module is IN_PIPE + LAT_MULT + 1 + 1
//
// Parameters :
//  IN_PIPE        : Instantiate a pipe for input signals.
//  KARATSUBA_OP_W : Karatsuba algorithm LSB part width.
//  OP_A_W,
//  OP_B_W        : Operand width
// ==============================================================================================

module arith_mult_karatsuba #(
  // PARAMETERS ====================================================================================
  parameter int     OP_A_W = 33,
  parameter int     OP_B_W = 33,
  // Karatsuba -------------------------------------------------------------------------------------
  parameter int     KARATSUBA_OP_W = (OP_A_W > OP_B_W) ? OP_A_W/2 : OP_B_W/2, //(OP_A_W > OP_B_W) ? (OP_B_W > 17) ? 17 : // 17 : Xilinx multiplier input width
                                                                              //                          (OP_A_W/2 >= OP_B_W) ? OP_B_W-1 : OP_A_W/2 :
                                                                              //          (OP_A_W > 17) ? 17 : // 17 : Xilinx multiplier input width
                                                                              //                          (OP_B_W/2 >= OP_A_W) ? OP_A_W-1 : OP_B_W/2,
  parameter bit     IN_PIPE        = 1,
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
  localparam int     LSB_W      = KARATSUBA_OP_W;
  localparam int     MSB_A_W    = OP_A_W - KARATSUBA_OP_W;
  localparam int     MSB_B_W    = OP_B_W - KARATSUBA_OP_W;
  localparam int     MAX_MSB_W  = MSB_A_W > MSB_B_W ? MSB_A_W : MSB_B_W;
  localparam int     MAX_SB_W   = LSB_W > MAX_MSB_W ? LSB_W : MAX_MSB_W;

  // Check parameters
  generate
    if ((OP_A_W <= KARATSUBA_OP_W) || (OP_B_W <= KARATSUBA_OP_W)) begin: __UNSUPPORTED_KARATSUBA_OP_W__
      $fatal(1,"> ERROR: Unsupported KARATSUBA_OP_W and OP_A_W, OP_B_W. The operands size are too small.");
    end
  endgenerate

  // ============================================================================================ //
  // arith_mult_karatsuba
  // ============================================================================================ //
  // -------------------------------------------------------------------------------------------- //
  // Input pipe
  // -------------------------------------------------------------------------------------------- //
  logic [OP_A_W-1:0] s0_a;
  logic [OP_B_W-1:0] s0_b;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;
  generate
    if (IN_PIPE) begin
      always_ff @(posedge clk) begin
        s0_a <= a;
        s0_b <= b;
      end
    end else begin
      assign s0_a     = a;
      assign s0_b     = b;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) s0_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail ),
    .out_avail(s0_avail ),

    .in_side  (in_side  ),
    .out_side (s0_side  )
  );

  // -------------------------------------------------------------------------------------------- //
  // S0 : data pre-compute
  // Two stages induced from LAT_MUL
  // -------------------------------------------------------------------------------------------- //
  // Let's name :
  // a = a_lo + 2^KARATSUBA_OP_W * a_hi
  // b = b_lo + 2^KARATSUBA_OP_W * b_hi
  //-------------------------------------------
  // Compute :
  // a_hi * b_hi
  // a_lo * b_lo
  // (a_hi * b_hi) + (a_lo * b_lo)
  //-------------------------------------------
  logic [MSB_A_W+MSB_B_W-1:0] s0_a_hi_x_b_hi;
  logic [        2*LSB_W-1:0] s0_a_lo_x_b_lo;
  logic [       2*MAX_SB_W:0] s0_sum_of_product;

  logic [MSB_A_W+MSB_B_W-1:0] s1_a_hi_x_b_hi;
  logic [        2*LSB_W-1:0] s1_a_lo_x_b_lo;
  logic [       2*MAX_SB_W:0] s1_sum_of_product;

  arith_mult_core #(
    .IN_PIPE(0      ),
    .OP_A_W (MSB_A_W),
    .OP_B_W (MSB_B_W)
  ) arith_mult_s0_a_hi_x_b_hi (
    .clk(clk),
    .a  (s0_a[LSB_W+:MSB_A_W]),
    .b  (s0_b[LSB_W+:MSB_B_W]),
    .z  (s0_a_hi_x_b_hi      )
  );

  arith_mult_core #(
    .IN_PIPE(0    ),
    .OP_A_W (LSB_W),
    .OP_B_W (LSB_W)
  ) arith_mult_s0_a_lo_x_b_lo (
    .clk(clk),
    .a  (s0_a[0+:LSB_W]),
    .b  (s0_b[0+:LSB_W]),
    .z  (s0_a_lo_x_b_lo)
  );

  assign s0_sum_of_product = s0_a_hi_x_b_hi + s0_a_lo_x_b_lo;

  always_ff @(posedge clk) begin
    s1_a_hi_x_b_hi    <= s0_a_hi_x_b_hi;
    s1_a_lo_x_b_lo    <= s0_a_lo_x_b_lo;
    s1_sum_of_product <= s0_sum_of_product;
  end

  //-------------------------------------------
  // Compute :
  // a_lo + a_hi
  // b_lo + b_hi
  // (a_lo + a_hi) * (b_lo + b_hi)
  //-------------------------------------------
  logic [MAX_SB_W:0]               s0_a_lo_plus_a_hi;
  logic [MAX_SB_W:0]               s0_b_lo_plus_b_hi;
  logic [MAX_SB_W:0]               s0_a_lo_plus_a_hi_dly;
  logic [MAX_SB_W:0]               s0_b_lo_plus_b_hi_dly;
  logic [2*(MAX_SB_W+1)-1:0]       s1_product_of_sum;
  logic                            s0_avail_dly;
  logic [SIDE_W-1:0]               s0_side_dly;
  logic                            s1_avail;
  logic [SIDE_W-1:0]               s1_side;

  assign s0_a_lo_plus_a_hi = s0_a[0+:LSB_W] + s0_a[LSB_W+:MSB_A_W];
  assign s0_b_lo_plus_b_hi = s0_b[0+:LSB_W] + s0_b[LSB_W+:MSB_B_W];

  always_ff @(posedge clk) begin
    s0_a_lo_plus_a_hi_dly <= s0_a_lo_plus_a_hi;
    s0_b_lo_plus_b_hi_dly <= s0_b_lo_plus_b_hi;
  end

  common_lib_delay_side #(
    .LATENCY    (1),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) s0_dly_delay_side (
    .clk      (clk          ),
    .s_rst_n  (s_rst_n      ),
    .in_avail (s0_avail     ),
    .out_avail(s0_avail_dly ),
    .in_side  (s0_side      ),
    .out_side (s0_side_dly  )
  );

  arith_mult_core_with_side #(
    .IN_PIPE (0           ),
    .OP_A_W  (MAX_SB_W + 1),
    .OP_B_W  (MAX_SB_W + 1),
    .SIDE_W  (SIDE_W      ),
    .RST_SIDE(RST_SIDE    )
  ) arith_mult_s0_product_of_sum (
    .clk      (clk                  ),
    .s_rst_n  (s_rst_n              ),
    .a        (s0_a_lo_plus_a_hi_dly),
    .b        (s0_b_lo_plus_b_hi_dly),
    .z        (s1_product_of_sum    ),

    .in_avail (s0_avail_dly         ),
    .out_avail(s1_avail             ),
    .in_side  (s0_side_dly          ),
    .out_side (s1_side              )

  );

  // -------------------------------------------------------------------------------------------- //
  // S1 : Final addition
  // -------------------------------------------------------------------------------------------- //
  logic [OP_A_W + OP_B_W-1:0] s1_result;

  assign s1_result = (s1_a_hi_x_b_hi << (2 * LSB_W))
                      + s1_a_lo_x_b_lo
                      + ((s1_product_of_sum - s1_sum_of_product) << LSB_W);

  // -------------------------------------------------------------------------------------------- //
  // S2 : result
  // -------------------------------------------------------------------------------------------- //
  logic [OP_A_W + OP_B_W-1:0] s2_result;
  logic                       s2_avail;
  logic [SIDE_W-1:0]          s2_side;


  // LAT_PIPE_MH[2]
  always_ff @(posedge clk) begin
    s2_result <= s1_result;
  end

  common_lib_delay_side #(
    .LATENCY    (1),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) s1_delay_side (
    .clk      (clk          ),
    .s_rst_n  (s_rst_n      ),
    .in_avail (s1_avail     ),
    .out_avail(s2_avail     ),
    .in_side  (s1_side      ),
    .out_side (s2_side      )
  );

  assign z         = s2_result;
  assign out_avail = s2_avail;
  assign out_side  = s2_side;
endmodule

