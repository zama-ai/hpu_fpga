// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs a modular reduction on an 2scomplement value in
//                goldilocks 64 field.
// ----------------------------------------------------------------------------------------------
//
// GF64 prime is a solinas2 with this form :
// 2**MOD_NTT_W - 2**(MOD_NTT_W/2) + 1
// with MOD_NTT_W an even number.
//
// The following properties are used here :
// 2**MOD_NTT_W = 2**(MOD_NTT_W/2) - 1
// 2**(MOD_NTT_W+MOD_NTT_W/2) = -1
//
// First do a partial reduction of the sign to an unsigned value of MOD_NTT_W+1 bits.
// Second, do the complete reduction.
// ==============================================================================================

module ntt_core_gf64_sign_reduction #(
  parameter int            MOD_NTT_W = 64, // Should be 64 for GF64. Mainly used in verification
                                           // Should be even
  parameter int            OP_W      = MOD_NTT_W + 1 + 1,
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
  output logic [MOD_NTT_W-1:0] z,

  // Control + side interface - optional
  input  logic                 in_avail,
  output logic                 out_avail,
  input  logic [SIDE_W-1:0]    in_side,
  output logic [SIDE_W-1:0]    out_side
);
// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int             MID_W   = MOD_NTT_W / 2;
  localparam int             C_W     = OP_W-1-MOD_NTT_W;
  localparam [MOD_NTT_W-1:0] MOD_NTT = 2**MOD_NTT_W - 2**MID_W + 1;

  generate
    if ((MOD_NTT_W % 2) != 0) begin : __UNSUPPORTED_MOD_NTT_W
      $fatal(1,"> ERROR: MOD_NTT_W (%0d) should be even!", MOD_NTT_W);
    end
    if (C_W < 1) begin : __UNSUPPORTED_OP_W_0
      $fatal(1,"> ERROR: For partial modulo reduction the input should be at least MOD_NTT_W+2 bits (%0d). Here only OP_W=%0d was connected.",MOD_NTT_W + 2, OP_W);
    end
    if (OP_W > MOD_NTT_W + MID_W) begin : __UNSUPPORTED_OP_W_1
      $fatal(1,"> ERROR: For partial modulo reduction the input should be at most MOD_NTT_W+MOD_NTT_W/2 bits (%0d). Here OP_W=%0d was connected.",MOD_NTT_W + MOD_NTT_W/2, OP_W);
    end
    // Simplifications have been made in the code
    if (OP_W <= MOD_NTT_W) begin : __UNSUPPORTED_OP_W_2
      $fatal(1,"> ERROR: OP_W (%0d) should be greater than MOD_NTT_W (%0d)", OP_W, MOD_NTT_W);
    end
  endgenerate

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  logic [OP_W-1:0]   s0_a;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;
  generate
    if (IN_PIPE) begin : gen_input_pipe
      always_ff @(posedge clk) begin
        s0_a <= a;
      end
    end else begin : no_gen_input_pipe
      assign s0_a = a;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE ),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail ),
    .out_avail(s0_avail ),

    .in_side  (in_side  ),
    .out_side (s0_side  )
  );

// ============================================================================================== //
// s0
// ============================================================================================== //
//  Reduce the sign : partial modular reduction
  logic [MOD_NTT_W:0] s1_pmr_a; // unsigned
  logic               s1_avail;
  logic [SIDE_W-1:0]  s1_side;

  ntt_core_gf64_pmr_sign #(
    .MOD_NTT_W (MOD_NTT_W),
    .OP_W      (OP_W),
    .IN_PIPE   (0),
    .SIDE_W    (SIDE_W),
    .RST_SIDE  (RST_SIDE)
  ) ntt_core_gf64_pmr_sign (
  // System interface
    .clk       (clk),
    .s_rst_n   (s_rst_n),

    .a         (s0_a),
    .z         (s1_pmr_a),

    .in_avail  (s0_avail),
    .out_avail (s1_avail),
    .in_side   (s0_side),
    .out_side  (s1_side)
);

// ============================================================================================== //
// s1 : Final complete modular reduction
// ============================================================================================== //
  logic [MOD_NTT_W-1:0] s1_z;
  logic [MOD_NTT_W+1:0] s1_a_minus_2mod;
  logic [MOD_NTT_W+1:0] s1_a_minus_1mod;
  logic                 s1_a_ge_2mod;
  logic                 s1_a_ge_1mod;

  assign s1_a_minus_2mod = s1_pmr_a - 2*MOD_NTT;
  assign s1_a_minus_1mod = s1_pmr_a - MOD_NTT;
  assign s1_a_ge_2mod    = ~s1_a_minus_2mod[MOD_NTT_W+1];
  assign s1_a_ge_1mod    = ~s1_a_minus_1mod[MOD_NTT_W+1];

  assign s1_z = s1_a_ge_2mod ? s1_a_minus_2mod[MOD_NTT_W-1:0] :
                s1_a_ge_1mod ? s1_a_minus_1mod[MOD_NTT_W-1:0] :
                s1_pmr_a[MOD_NTT_W-1:0];

// ============================================================================================== //
// s2 : Output pipe
// ============================================================================================== //
  logic [MOD_NTT_W-1:0] s2_z;
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
