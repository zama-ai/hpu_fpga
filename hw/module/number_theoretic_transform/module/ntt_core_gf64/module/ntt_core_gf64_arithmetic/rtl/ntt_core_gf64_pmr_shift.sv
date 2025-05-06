// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs a modular shift in goldilocks 64 field.
// ----------------------------------------------------------------------------------------------
//
// Performs a shift with a constant z = a << s followed by a partial reduction in GF64.
//
// GF64 prime is a solinas2 with this form :
// 2**MOD_NTT_W - 2**(MOD_NTT_W/2) + 1
// with MOD_NTT_W an even number.
//
// The following properties are used here :
// 2**MOD_NTT_W = 2**(MOD_NTT_W/2) - 1
// 2**(MOD_NTT_W+MOD_NTT_W/2) = -1
//
// Then the reduction of all the bits above MOD_NTT_W is done using the property above.
// The result a signed number with MOD_NTT_W + 1 + 1b sign bits.
//
// Note that the inputs are 2s complement numbers.
// ==============================================================================================

module ntt_core_gf64_pmr_shift #(
  parameter  int            MOD_NTT_W = 64, // Should be 64 for GF64. Mainly used in verification
                                           // For this module, optimized for a power of 2
  parameter  int            OP_W      = MOD_NTT_W + 1 + 1, // 1 additional bit + 1bit of sign. Data are in 2s complement.
  localparam int            SHIFT_W   = $clog2(MOD_NTT_W + MOD_NTT_W/2), // max shift supported.
  parameter  bit            IN_PIPE   = 1'b1, // Recommended
  parameter  int            SIDE_W    = 0, // Side data size. Set to 0 if not used
  parameter  [1:0]          RST_SIDE  = 0  // If side data is used,
                                          // [0] (1) reset them to 0.
                                          // [1] (1) reset them to 1.
) (
  // System interface
  input  logic                 clk,
  input  logic                 s_rst_n,

  // Data interface
  input  logic [OP_W-1:0]      a, // 2s complement
  input  logic [SHIFT_W-1:0]   s, // Value in [0,MOD_NTT_W+MOD_NTT_W/2[
  input  logic                 s_sign, // (0) positive, (1) negative
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
  localparam int MID_SZ  = $clog2(MID_W);
  localparam int SH_W    = $clog2(MID_W) == 0 ? 1 : $clog2(MID_W);
  localparam int C_W     = OP_W-1-MID_W;
  localparam int S_W     = C_W+1;

  generate
    if (CARRY_W < 1) begin : __UNSUPPORTED_OP_W_0
      $fatal(1,"> ERROR: For partial modulo reduction the input should be at least MOD_NTT_W+2 bits (%0d). Here only OP_W=%0d was connected.",MOD_NTT_W + 2, OP_W);
    end

    if (OP_W > MOD_NTT_W + MID_W) begin : __UNSUPPORTED_OP_W_1
      $fatal(1,"> ERROR: For partial modulo reduction the input should be at most MOD_NTT_W+MOD_NTT_W/2 bits (%0d). Here OP_W=%0d was connected.",MOD_NTT_W + MOD_NTT_W/2, OP_W);
    end

    // The following RTL has been optimized for MOD_NTT_W as a power of 2.
    if (2**$clog2(MOD_NTT_W) != MOD_NTT_W) begin: __UNSUPPORTED_MOD_NTT_W_0
      $fatal(1,"> ERROR: Support only power of 2 MOD_NTT_W (%0d).",MOD_NTT_W);
    end

    if (MID_W < 2) begin: __UNSUPPORTED_MOD_NTT_W_1
      $fatal(1,"> ERROR: MOD_NTT_W (%0d) should be greater or equal to 4", MOD_NTT_W);
    end
  endgenerate

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  logic [OP_W-1:0]    s0_a;
  logic [SHIFT_W-1:0] s0_s;
  logic               s0_s_sign;
  logic               s0_avail;
  logic [SIDE_W-1:0]  s0_side;
  generate
    if (IN_PIPE) begin : gen_input_pipe
      always_ff @(posedge clk) begin
        s0_a      <= a;
        s0_s      <= s;
        s0_s_sign <= s_sign;
      end
    end else begin : no_gen_input_pipe
      assign s0_a      = a;
      assign s0_s      = s;
      assign s0_s_sign = s_sign;
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

// pragma translate_off
  always_ff @(posedge clk)
    if (in_avail) begin
      assert((s + OP_W) <= 5*MID_W)
      else begin
        $fatal(1,"%t > ERROR: Unsupported shift value (%0d). OP_W (%0d) + s should be less than 5*MID_W (%0d)", $time, s,OP_W,5*MID_W);
      end

      assert(a != {1'b1,{OP_W-1{1'b0}}})
      else begin
        $fatal(1,"%t > ERROR: Unsupported input data value 0x%0x. Minimal negative value is 0x%0x",$time,a,{1'b1,{OP_W-2{1'b0}},1'b1});
      end
    end
// pragma translate_on

// ============================================================================================== //
// s0
// ============================================================================================== //
// Compute a << s
// Extend with the sign.
// Then reduce.
//
// Use the following property for the partial reduction :
// 2**MOD_NTT_W = 2**(MOD_NTT_W/2) - 1
// 2**(MOD_NTT_W+MOD_NTT_W/2) = -1
//

  logic [SH_W-1:0]        s0_shift;
  logic                   s0_shift_lt_mid;
  logic                   s0_shift_lt_2mid;

  logic [OP_W+MID_W-1-1:0] s0_a_shifted; // max shift : a << (MID_W-1)
  logic [4:0][MID_W-1:0]   s0_a_shifted_ext;
  logic [4:0][MID_W-1:0]   s0_z_tmp;
  logic [OP_W-1:0]         s0_a_inv;

  assign s0_a_inv         = (s0_a ^ {OP_W{s0_s_sign}}) + s0_s_sign;

  assign s0_shift_lt_mid  = s0_s < MID_W;
  assign s0_shift_lt_2mid = s0_s < 2*MID_W;
  assign s0_shift         = s0_s[SH_W-1:0]; // (s%MID_W)

  assign s0_a_shifted = {{MID_W-1{s0_a_inv[OP_W-1]}},s0_a_inv} << s0_shift;
  assign s0_a_shifted_ext = {{5*MID_W-(OP_W+MID_W-1){s0_a_shifted[OP_W+MID_W-1-1]}},s0_a_shifted}; // extend with the sign
  assign s0_z_tmp     = s0_shift_lt_mid  ? s0_a_shifted_ext :
                        s0_shift_lt_2mid ? {s0_a_shifted_ext[0+:4],{MID_W{1'b0}}}:
                        {s0_a_shifted_ext[0+:3],{2*MID_W{1'b0}}};

// ============================================================================================== //
// s1 : Partial reduction
// ============================================================================================== //
  logic [4:0][MID_W-1:0]  s1_z_tmp;
  logic                   s1_avail;
  logic [SIDE_W-1:0]      s1_side;

  always_ff @(posedge clk) begin
    s1_z_tmp  <= s0_z_tmp;
  end

  common_lib_delay_side #(
    .LATENCY    (1),
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

  logic [MOD_NTT_W+1:0] s1_z;

  assign s1_z = {s1_z_tmp[1],s1_z_tmp[0]}
                +{s1_z_tmp[2],{MID_W{1'b0}}}
                -s1_z_tmp[2]
                -{s1_z_tmp[4][MID_W-2:0],s1_z_tmp[3]}
                +{s1_z_tmp[4][MID_W-1],{2*MID_W-1{1'b0}}};

// ============================================================================================== //
// s2 : Output pipe
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
