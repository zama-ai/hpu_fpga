// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : mod_reduct_solinas2
// ----------------------------------------------------------------------------------------------
//
// Modular reduction with specific modulo value:
//  MOD_M = 2**MOD_W - 2**INT_POW + 1
//
// Some simplifications are made in the RTL that makes the support for all values
// with the form described above not possible.
// Indeed the wrap done to get e and f is only done once in the code.
// For some value of INT_POW, repetition of this wrapping is necessary. Particularly when
// (MOD_W-INT_POW) is small.
//
// Can deal with input up to 2*MOD_W+1 bits.
// This is the size of the sum of the 2 results of multiplication of 2
// values % MOD_M.
//
// LATENCY = IN_PIPE + $countone(LAT_PIPE_MH)
// ==============================================================================================

module mod_reduct_solinas2_general #(
  parameter int          MOD_W      = 64,
  parameter [MOD_W-1:0]  MOD_M      = 2**MOD_W - 2**(MOD_W/2) + 1,
  parameter int          OP_W       = 2*MOD_W+1, // Should be in [MOD_W:2*MOD_W+1]
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

  import mod_reduct_solinas2_pkg::*;

  // ============================================================================================ //
  // Localparam
  // ============================================================================================ //
  // Since MOD_M has the following form:
  // MOD_M = 2**MOD_W - 2**INT_POW + 1
  // We can retrieve INT_POW

  localparam int         INT_POW   = $clog2(2**MOD_W+1 - MOD_M);
  localparam int         PROC_W    = MOD_W*2+1;
  localparam int         INT_W     = MOD_W - INT_POW; // INT stands for intermediate
  localparam int         C_PART_NB = (MOD_W+INT_W-1) / INT_W;
  localparam int         C_ADD_BIT = $clog2(C_PART_NB);

  localparam int         A_DATA_W  = SIDE_W + OP_W;

  localparam [MOD_W:0]   MINUS_MOD_M = ~{1'b0, MOD_M} + 1; // signed

  // parameter check
  generate
    if (OP_W > PROC_W) begin : __UNSUPPORTED_PARAM_OP_W__
      $fatal(1, "> ERROR: Unsupported operand size. Should be less than %d.",PROC_W);
    end
    if (INT_POW==1 || INT_POW==MOD_W-1) begin : __UNSUPPORTED_PARAM_INT_POW__
      $fatal(1, "> ERROR: Unsupported (MOD_W, INT_POW). Constraints not respected.");
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
  // In the stage, partial additions are done.
  // The first one d, is the accumulation of MOD_W sub-word, at INT_W intervals.
  // The second one c, is the accumulation of INT_W sub-word, at INT_W intervals.
  // For both the bit [2*MOD_W] is subtracted.
  //
  // For example, with MOD_W=33, and INT_POW=20, the partial addition is:
  // d = a[65:33] + a[66:46] + a[66:59]- a[66]
  // c = a[45:33] + a[58:46] + a[66:59]- a[66]
  //
  // During this stage, we also compute the distance between a[MOD_W-1:0] and MOD_M
  // reduced to MOD_M.
  //
  // The FPGA timing enables us to do this additional compute :
  // e = c[12:0] + c[14:13]
  // f = d[33:0] + c[14:13]

  logic [PROC_W+MOD_W-1:0]    s0_a_ext; // Extend a with 0
  logic [MOD_W:0]             s0_d;
  logic [INT_W+C_ADD_BIT-1:0] s0_c;

  assign s0_a_ext = s0_a; // MSB are extended with 0

  always_comb begin
    logic [MOD_W:0] tmp;
    tmp = 0;
    for (int i = MOD_W; i<PROC_W; i=i+INT_W) begin
      tmp = tmp + s0_a_ext[i+:MOD_W];
    end
    s0_d = tmp - s0_a_ext[PROC_W-1];
  end

  always_comb begin
    logic [INT_W+C_ADD_BIT-1:0] tmp;
    tmp = 0;
    for (int i = MOD_W; i<PROC_W; i=i+INT_W) begin
      tmp = tmp + s0_a_ext[i+:INT_W];
    end
    s0_c = tmp - s0_a_ext[PROC_W-1];
  end

  logic [INT_W:0] s0_e;
  logic [MOD_W:0] s0_f;
  assign s0_e = s0_c[INT_W-1:0] + s0_c[INT_W+C_ADD_BIT-1:INT_W];
  assign s0_f = s0_d            + s0_c[INT_W+C_ADD_BIT-1:INT_W];


  // ============================================================================================ //
  // s1 : final addition
  // ============================================================================================ //
  logic [MOD_W-1:0]           s1_a;
  logic [MOD_W:0]             s1_f;
  logic [INT_W:0]             s1_e;
  logic                       s1_avail;
  logic [SIDE_W-1:0]          s1_side;

  generate
    if (LAT_PIPE_MH[0]) begin : gen_pipe_0
      always_ff @(posedge clk) begin
        s1_a <= s0_a;
        s1_f <= s0_f;
        s1_e <= s0_e;
      end
    end
    else begin : no_gen_pipe_0
      assign  s1_a = s0_a;
      assign  s1_f = s0_f;
      assign  s1_e = s0_e;
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

  logic [MOD_W+1:0] s1_sum; // signed
  assign s1_sum = {2'b00,s1_a} + {1'b0,s1_e,{INT_POW{1'b0}}} - {1'b0,s1_f};

  // comparisons
  logic [MOD_W+1:0] s1_mod_inc; // signed
  logic [MOD_W+1:0] s1_sum_op_mod;

  assign s1_mod_inc    = s1_sum[MOD_W+1]       ? {1'b0,MOD_M, 1'b0} : // negative sum
                         s1_sum[MOD_W+:2] != 0 ? {MINUS_MOD_M[MOD_W],MINUS_MOD_M} : // greater or equal to 2**MOD_W
                         0;
  assign s1_sum_op_mod = s1_sum + s1_mod_inc;

// pragma translate_off
  always_ff @(posedge clk) begin
    if (s1_sum !== 'x) begin
      if (s1_sum[MOD_W+1]) begin
        logic [MOD_W+1:0] _s1_sum_abs;
        _s1_sum_abs = ~s1_sum + 1;
        assert(_s1_sum_abs < 2*MOD_M)
        else $fatal(1,"> ERROR: Reduction underflow : sum is less than -2*MOD_M 0x%x (abs=0x%0x)",s1_sum, _s1_sum_abs);
      end
      else begin
        assert(s1_sum < 3*MOD_M)
        else $fatal(1,"> ERROR: Reduction overflow : sum is greater than 2*MOD_M 0x%x",s1_sum);
      end

      assert(s1_sum_op_mod[MOD_W+1] == 0)
      else $fatal(1,"> ERROR: Negative value after 1rst correction : 0x%0x -> 0x%0x", s1_sum, s1_sum_op_mod);
    end
  end
// pragma translate_on

  // ============================================================================================ //
  // s2 : Modulo correction
  // ============================================================================================ //
  logic [MOD_W:0]    s2_sum_op_mod;
  logic              s2_avail;
  logic [SIDE_W-1:0] s2_side;

  generate
    if (LAT_PIPE_MH[1]) begin : gen_pipe_1
      always_ff @(posedge clk) begin
        s2_sum_op_mod <= s1_sum_op_mod[MOD_W:0];
      end
    end
    else begin : no_gen_pipe_1
      assign s2_sum_op_mod = s1_sum_op_mod[MOD_W:0];
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


  logic [MOD_W+1:0] s2_sum_op_minus_mod;

  assign s2_sum_op_minus_mod = {1'b0, s2_sum_op_mod} - MOD_M;

  logic [MOD_W-1:0]  s2_result;

  assign s2_result = s2_sum_op_minus_mod[MOD_W+1] ? s2_sum_op_mod[MOD_W-1:0]
                                                  : s2_sum_op_minus_mod[MOD_W-1:0];

  // ============================================================================================ //
  // s3 : output
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
