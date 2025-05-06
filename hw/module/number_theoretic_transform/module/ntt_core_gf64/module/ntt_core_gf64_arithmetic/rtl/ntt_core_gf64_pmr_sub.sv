// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs a modular subtraction in goldilocks 64 field.
// ----------------------------------------------------------------------------------------------
//
// Performs an addition z = a - b followed by a partial reduction in GF64.
//
// GF64 prime is a solinas2 with this form :
// 2**MOD_NTT_W - 2**(MOD_NTT_W/2) + 1
// with MOD_NTT_W an even number.
//
// The following property is used here :
// 2**MOD_NTT_W = 2**(MOD_NTT_W/2) - 1
//
// Then the reduction of all the bits above MOD_NTT_W is done using the property above.
// The result a signed number with MOD_NTT_W + 1 + 1b sign bits.
//
// Note that the inputs are 2s complement numbers.
// ==============================================================================================

module ntt_core_gf64_pmr_sub #(
  parameter int            MOD_NTT_W = 64, // Should be 64 for GF64. Mainly used in verification
                                           // Should be even
  parameter int            OP_W      = MOD_NTT_W + 1 + 1, // 1 additional bit + 1bit of sign. Data are in 2s complement.
  parameter bit            INVERSE   = 1'b0, // (0) a-b, (1) b-a
  parameter bit            IN_PIPE   = 1'b1, // Recommended
  parameter int            SIDE_W    = 0, // Side data size. Set to 0 if not used
  parameter [1:0]          RST_SIDE  = 0  // If side data is used,
                                          // [0] (1) reset them to 0.
                                          // [1] (1) reset them to 1.
) (
  // System interface
  input  logic                 clk,
  input  logic                 s_rst_n,

  // Data interface
  input  logic [OP_W-1:0]      a, // 2s complement
  input  logic [OP_W-1:0]      b, // 2s complement
  output logic [MOD_NTT_W+1:0] z, // 2s complement

  // Control + side interface - optional
  input  logic                 in_avail,
  output logic                 out_avail,
  input  logic [SIDE_W-1:0]    in_side,
  output logic [SIDE_W-1:0]    out_side
);
// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int MID_W   = MOD_NTT_W / 2;
  localparam int CARRY_W = OP_W-1-MOD_NTT_W;
  localparam int C_W     = CARRY_W + 1; // +1bit, because of the addition.

  generate
    if ((MOD_NTT_W % 2) != 0) begin : __UNSUPPORTED_MOD_NTT_W
      $fatal(1,"> ERROR: MOD_NTT_W (%0d) should be even!", MOD_NTT_W);
    end
    if (CARRY_W < 1) begin : __UNSUPPORTED_OP_W_0
      $fatal(1,"> ERROR: For partial modulo reduction the input should be at least MOD_NTT_W+2 bits (%0d). Here only OP_W=%0d was connected.",MOD_NTT_W + 2, OP_W);
    end
    if (OP_W > MOD_NTT_W + MOD_NTT_W/2) begin : __UNSUPPORTED_OP_W_1
      $fatal(1,"> ERROR: For partial modulo reduction the input should be at most MOD_NTT_W+MOD_NTT_W/2 bits (%0d). Here OP_W=%0d was connected.",MOD_NTT_W + MOD_NTT_W/2, OP_W);
    end
  endgenerate

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  logic [OP_W-1:0]   s0_a;
  logic [OP_W-1:0]   s0_b;
  generate
    if (IN_PIPE) begin : gen_input_pipe
      always_ff @(posedge clk) begin
        s0_a <= a;
        s0_b <= b;
      end
    end else begin : no_gen_input_pipe
      assign s0_a = a;
      assign s0_b = b;
    end
  endgenerate

  logic              s1_avail;
  logic [SIDE_W-1:0] s1_side;
  common_lib_delay_side #(
    .LATENCY    (IN_PIPE + 1),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail ),
    .out_avail(s1_avail ),

    .in_side  (in_side  ),
    .out_side (s1_side  )
  );

// ============================================================================================== //
// s0 + s1
// ============================================================================================== //
// Compute a - b
// Use the following property for the partial reduction :
// 2**MOD_NTT_W = 2**(MOD_NTT_W/2) - 1

//  assign s0_z     = s0_z_tmp[MOD_NTT_W-1:0]
//                    - s0_carry
//                    + {s0_sign, {C_W{1'b0}}}
//                    + {s0_carry, {MID_W{1'b0}}}
//                    - {s0_sign, {C_W + MID_W{1'b0}}};

  logic [OP_W:0]        s0_z_tmp;
  logic [OP_W:0]        s1_z_tmp;

  generate
    if (INVERSE) begin : gen_b_minus_a
      assign s0_z_tmp = {s0_b[OP_W-1],s0_b} - {s0_a[OP_W-1],s0_a};
    end
    else begin : gen_a_minus_b
      assign s0_z_tmp = {s0_a[OP_W-1],s0_a} - {s0_b[OP_W-1],s0_b};
    end
  endgenerate

  always_ff @(posedge clk)
    s1_z_tmp <= s0_z_tmp;

  logic [MOD_NTT_W+1:0] s1_z;
  logic                 s1_sign;
  logic [C_W-1:0]       s1_carry;
  logic [MOD_NTT_W+1:0] s1_z_sign;

  assign s1_sign  = s1_z_tmp[OP_W];
  assign s1_carry = s1_z_tmp[OP_W-1:MOD_NTT_W];
  assign s1_z_sign = {{MID_W{s1_sign}},{C_W{1'b0}}} ;// {s1_sign, {C_W + MID_W{1'b0}}} - {s1_sign, {C_W{1'b0}}}

  generate
    if (C_W == 1) begin : gen_cw_eq_1
      logic [MOD_NTT_W+1:0] s1_z_carry;
      assign s1_z_carry = {MID_W{s1_carry}};
      assign s1_z     = s1_z_tmp[MOD_NTT_W-1:0]
                        + s1_z_carry
                        - s1_z_sign;

    end
    else begin : gen_cw_not_1
      assign s1_z     = s1_z_tmp[MOD_NTT_W-1:0]
                        - s1_carry
                        + {s1_carry, {MID_W{1'b0}}}
                        - s1_z_sign;
    end
  endgenerate

// ============================================================================================== //
// s1 : Output pipe
// ============================================================================================== //
// Output pipe
  logic [MOD_NTT_W+1:0] s2_z;
  logic                 s2_avail;
  logic [SIDE_W-1:0]    s2_side;

  always_ff @(posedge clk) begin
    s2_z <= s1_z;
  end

  common_lib_delay_side #(
    .LATENCY    (1),
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

  assign z         = s2_z;
  assign out_avail = s2_avail;
  assign out_side  = s2_side;

endmodule
