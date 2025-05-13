// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : mod_reduct_solinas2_half
// ----------------------------------------------------------------------------------------------
//
// Modular reduction with specific modulo value:
//  MOD_M = 2**MOD_W - 2**INT_POW + 1
//  where INT_POW <= MOD_W/2, and INT_POW > 1.
//
// Can deal with input up to 2*MOD_W bits.
// This is the size of the multiplication of values % MOD_M.
//
// LATENCY = IN_PIPE + $countone(LAT_PIPE_MH)
// ==============================================================================================

module  mod_reduct_solinas2_half
  import mod_reduct_solinas2_pkg::*;
#(
  parameter int          MOD_W      = 64,
  parameter [MOD_W-1:0]  MOD_M      = 2**MOD_W - 2**(MOD_W/2) + 1,
  parameter int          OP_W       = 2*MOD_W,
  parameter bit          IN_PIPE    = 1,
  parameter int          SIDE_W     = 0, // Side data size. Set to 0 if not used
  parameter [1:0]        RST_SIDE   = 0  // If side data is used,
                                         // [0] (1) reset them to 0.
                                         // [1] (1) reset them to 1.
)
(
  // System interface
  input  logic               clk,
  input  logic               s_rst_n,
  // Data interface
  input  logic [OP_W-1:0]    a,
  output logic [MOD_W-1:0]   z,
  // Control + side interface - optional
  input  logic               in_avail,
  output logic               out_avail,

  input  logic [SIDE_W-1:0]  in_side,
  output logic [SIDE_W-1:0]  out_side

);
  // ============================================================================================ //
  // Localparam
  // ============================================================================================ //
  // Since MOD_M has the following form:
  // MOD_M = 2**MOD_W - 2**INT_POW + 1
  // We can retrieve INT_POW

  localparam int         INT_POW   = $clog2(2**MOD_W+1 - MOD_M);
  localparam int         PROC_W    = MOD_W*2;
  localparam int         INT_W     = MOD_W - INT_POW; // INT stands for intermediate

  localparam int         A_DATA_W  = SIDE_W + OP_W;

  localparam [MOD_W:0]   MINUS_MOD_M = ~{1'b0, MOD_M} + 1; // signed

  // parameter check
  generate
    if (OP_W > PROC_W) begin : __UNSUPPORTED_PARAM_OP_W__
      $fatal(1, "> ERROR: Unsupported operand size. Should be less than %d.",PROC_W);
    end
    if (OP_W != 2*MOD_W) begin : __UNSUPPORTED_PARAM_OP_W_2_
      $fatal(1, "> ERROR: Unsupported operand size. Should be less than %d.",PROC_W);
    end
    if (INT_POW > MOD_W/2) begin : __UNSUPPORTED_PARAM_INT_POW__
      $fatal(1, "> ERROR: Unsupported (MOD_W(%0d), INT_POW(%0d)). Constraints not respected, INT_POW should satisfy <= MOD_W/2.",MOD_W,INT_POW);
    end
    if (INT_POW < 2) begin : __UNSUPPORTED_PARAM_INT_POW_BIS__
      $fatal(1, "> ERROR: Unsupported INT_POW. Should be greater or equal to 2");
    end
    if (MOD_M != 2**MOD_W-2**INT_POW+1) begin : __NOT_A_SOLINAS2_MOD__
      $fatal(1, "> ERROR: The modulo is not a Solinas 2 modulo 0x%0x",MOD_M);
    end
    if (MOD_M[MOD_W-1] == 0) begin : __ERROR_MODULO_MSB__
      $fatal(1, "> ERROR: The modulo [MOD_W-1]=[%0d] bit should be 1 : 0x%0x", MOD_W-1,MOD_M);
    end
  endgenerate

  // ============================================================================================ //
  // Input registers
  // ============================================================================================ //
  logic [OP_W-1:0]       s0_a;
  logic                  s0_avail;
  logic [SIDE_W-1:0]     s0_side;

  logic [A_DATA_W-1:0]   in_a_data;
  logic [A_DATA_W-1:0]   s0_a_data;

  generate
    if (SIDE_W > 0) begin
      assign in_a_data       = {in_side, a};
      assign {s0_side, s0_a} = s0_a_data;
    end
    else begin
      assign in_a_data = a;
      assign s0_a      = s0_a_data;
      assign s0_side   = 'x;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE ),
    .SIDE_W     (A_DATA_W),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail ),
    .out_avail(s0_avail ),

    .in_side  (in_a_data),
    .out_side (s0_a_data)
  );

  // ============================================================================================ //
  // s0 : Partial additions
  // ============================================================================================ //
  // d = a[MOD_W-1:0] - a[2*MOD_W-1:MOD_W]
  // c = {a[MOD_W+:INT_W], {INT_W{1'b0}}}
  //     +{a[MOD_W+INT_W+:INT_W], {INT_W{1'b0}}}
  //     - a[MOD_W+INT_W+:INT_W]
  // res = d+c
  // correction(res)
  //
  // Considering INT_POW features, c is a positive or null value.

  logic [MOD_W:0] s0_d; // 2's complement
  logic [MOD_W:0] s0_c; // Positive value

  assign s0_d = {1'b0,s0_a[MOD_W-1:0]} - {1'b0,s0_a[2*MOD_W-1:MOD_W]};
  assign s0_c =  {s0_a[MOD_W+:INT_W],         {INT_POW{1'b0}}}
                +{s0_a[MOD_W+INT_W+:INT_POW], {INT_POW{1'b0}}}
                - s0_a[MOD_W+INT_W+:INT_POW];

  // ============================================================================================ //
  // s1 : Intermediate addition
  // ============================================================================================ //
  logic [MOD_W:0]     s1_d; // 2's complement
  logic [MOD_W:0]     s1_c;
  logic               s1_avail;
  logic [SIDE_W-1:0]  s1_side;

  generate
    if (LAT_PIPE_MH[0]) begin : gen_pipe_0
      always_ff @(posedge clk) begin
        s1_d <= s0_d;
        s1_c <= s0_c;
      end
    end
    else begin : no_gen_pipe_0
      assign  s1_d = s0_d;
      assign  s1_c = s0_c;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[0]),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s0_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s0_avail ),
    .out_avail(s1_avail ),

    .in_side  (s0_side  ),
    .out_side (s1_side  )
  );

  logic [MOD_W+2:0] s1_sum; // 2s complement
  logic [MOD_W+1:0] s1_sum_plus_2mod;

  assign s1_sum = {2'b00,s1_c} + {{2{s1_d[MOD_W]}},s1_d};
  assign s1_sum_plus_2mod  = s1_sum[MOD_W+1:0] + {MOD_M[MOD_W-1:0], 1'b0};

  // ============================================================================================ //
  // s2 : Correction
  // ============================================================================================ //
  logic [MOD_W+2:0] s2_sum;
  logic [MOD_W+1:0] s2_sum_plus_2mod;

  logic               s2_avail;
  logic [SIDE_W-1:0]  s2_side;

  generate
    if (LAT_PIPE_MH[1]) begin : gen_pipe_1
      always_ff @(posedge clk) begin
        s2_sum <= s1_sum;
        s2_sum_plus_2mod <= s1_sum_plus_2mod;
      end
    end
    else begin : no_gen_pipe_1
      assign  s2_sum = s1_sum;
      assign  s2_sum_plus_2mod = s1_sum_plus_2mod;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[1]),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s1_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s1_avail ),
    .out_avail(s2_avail ),

    .in_side  (s1_side  ),
    .out_side (s2_side  )
  );

  logic [MOD_W+1:0] s2_sum_pos;
  logic             s2_ge_2mod;
  logic             s2_ge_mod;
  logic [MOD_W:0]   s2_dec;
  logic [MOD_W-1:0] s2_result;

  // If sum is negative, consider sum + 2*Mod, which is positive.
  assign s2_sum_pos = s2_sum[MOD_W+2] ? s2_sum_plus_2mod : s2_sum[MOD_W+1:0];

  // MOD has the following form : 111..100..001
  // Therefore the comparison to MOD and 2*MOD is easy.
  //assign s2_ge_mod  = ((s2_sum_pos[MOD_W-1:INT_POW] == '1) & (s2_sum_pos[INT_POW-1:0] != '0)) | s2_sum_pos[MOD_W];
  //assign s2_ge_2mod = ((s2_sum_pos[MOD_W:INT_POW+1] == '1) & (s2_sum_pos[INT_POW:1] != '0)) | s2_sum_pos[MOD_W+1];
  // The following writing is 2 CLB smaller.
  assign s2_ge_mod  = s2_sum_pos >= MOD_M;
  assign s2_ge_2mod = s2_sum_pos >= 2*MOD_M;
  assign s2_dec     = s2_ge_2mod ? {MOD_M[MOD_W-1:0], 1'b0} : s2_ge_mod ? {1'b0,MOD_M[MOD_W-1:0]} : '0;
  assign s2_result  = s2_sum_pos[MOD_W-1:0] - s2_dec[MOD_W-1:0];

  // ============================================================================================ //
  // s3 : Output
  // ============================================================================================ //
  logic [MOD_W-1:0]  s3_result;
  logic              s3_avail;
  logic [SIDE_W-1:0] s3_side;

  generate
    if (LAT_PIPE_MH[2]) begin : gen_pipe_2
      always_ff @(posedge clk) begin
        s3_result <= s2_result;
      end
    end
    else begin : no_gen_pipe_2
      assign s3_result = s2_result;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[2]),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s2_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s2_avail ),
    .out_avail(s3_avail ),

    .in_side  (s2_side  ),
    .out_side (s3_side  )
  );

  assign z         = s3_result;
  assign out_avail = s3_avail;
  assign out_side  = s3_side;

endmodule
