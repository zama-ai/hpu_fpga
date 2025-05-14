// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module multiplies the input with a constant. Here the constant is a inverse
// of solinas2_44_14 constant (2**76+2**46-2**32+2**16-2**3)
// TODO TODO => only valid for solinas2_44_14 with precision = 44+32
// ==============================================================================================

module arith_mult_cst_solinas2_44_14_inv
  import arith_mult_cst_solinas2_44_14_inv_pkg::*;
#(
  parameter int         IN_W           = 44,
  parameter int         CST_W          = 77,
  parameter [CST_W-1:0] CST            = 2**76+2**46-2**32+2**16-2**3, // Should be a the inverse of a solinas2_44_14
  parameter             IN_PIPE        = 1'b1,
  parameter int         SIDE_W         = 0,// Side data size. Set to 0 if not used
  parameter [1:0]       RST_SIDE       = 0 // If side data is used,
                                       // [0] (1) reset them to 0.
                                       // [1] (1) reset them to 1.
)
(
  input  logic                  clk,        // clock
  input  logic                  s_rst_n,    // synchronous reset

  input  logic [IN_W-1:0]       a,
  output logic [IN_W+CST_W-1:0] z,
  input  logic                  in_avail,
  output logic                  out_avail,
  input  logic [SIDE_W-1:0]     in_side,
  output logic [SIDE_W-1:0]     out_side

);

// ============================================================================================== --
// localparam
// ============================================================================================== --

// ============================================================================================== --
// Check parameters
// ============================================================================================== --
  generate
    if ((CST != 2**76+2**46-2**32+2**16-2**3) || (CST_W != 77)) begin : __ERROR_NOT_A_solinas2_44_14_INV__
      $fatal(1,"> ERROR: CST 0x%0x is not a solinas2_44_14 inverse number with size %0d.", CST, CST_W);
    end
  endgenerate

// ============================================================================================== --
// arith_mult_cst_solinas2_44_14
// ============================================================================================== --
  // -------------------------------------------------------------------------------------------- //
  // Input pipe
  // -------------------------------------------------------------------------------------------- //
  logic [IN_W-1:0]   s0_data;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;
  generate
    if (IN_PIPE) begin
      always_ff @(posedge clk) begin
        s0_data <= a;
      end
    end else begin
      assign s0_data = a;
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
  // S0 : Compute part 1
  // -------------------------------------------------------------------------------------------- //
  logic [IN_W+CST_W-1:0] s0_result_1;
  logic [IN_W+CST_W-1:0] s0_result_2;

  assign s0_result_1 = {s0_data, {76{1'b0}}}
                     + {s0_data, {46{1'b0}}}
                     + {s0_data, {16{1'b0}}};

  assign s0_result_2 = {s0_data, {32{1'b0}}}
                     + {s0_data, {3{1'b0}}};

  // -------------------------------------------------------------------------------------------- //
  // S1 : Compute part 2
  // -------------------------------------------------------------------------------------------- //
  logic [IN_W+CST_W-1:0] s1_result_1;
  logic [IN_W+CST_W-1:0] s1_result_2;
  logic [IN_W+CST_W-1:0] s1_result;

  always_ff @(posedge clk) begin
    s1_result_1 <= s0_result_1;
    s1_result_2 <= s0_result_2;
  end

  assign s1_result = s1_result_1 - s1_result_2;

  logic [IN_W+CST_W-1:0] s2_result;
  logic                  s2_avail;
  logic [SIDE_W-1:0]     s2_side;

  always_ff @(posedge clk) begin
    s2_result <= s1_result;
  end

  common_lib_delay_side #(
    .LATENCY    (2),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) s1_delay_side (
    .clk      (clk          ),
    .s_rst_n  (s_rst_n      ),
    .in_avail (s0_avail     ),
    .out_avail(s2_avail     ),
    .in_side  (s0_side      ),
    .out_side (s2_side      )
  );

  assign z         = s2_result;
  assign out_avail = s2_avail;
  assign out_side  = s2_side;

endmodule
