// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs a modular shift with a constant in goldilocks 64 field.
// ----------------------------------------------------------------------------------------------
//
// Performs a shift with a constant z = a << cst followed by a partial reduction in GF64.
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

module ntt_core_gf64_pmr_shift_cst #(
  parameter int            MOD_NTT_W = 64, // Should be 64 for GF64. Mainly used in verification
                                           // Should be even
  parameter int            OP_W      = MOD_NTT_W + 1 + 1, // 1 additional bit + 1bit of sign. Data are in 2s complement.
  parameter int            CST       = 2, // Shift constant.
  parameter bit            CST_SIGN  = 1'b1,
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
  localparam int MID_W      = MOD_NTT_W / 2;
  localparam int SHIFT      = CST % MID_W;
  localparam int C_W        = OP_W-1+SHIFT - MOD_NTT_W;
  localparam bit IS_4_PARTS = (OP_W + SHIFT) > 3*MID_W;

  generate
    if ((MOD_NTT_W % 2) != 0) begin : __UNSUPPORTED_MOD_NTT_W
      $fatal(1,"> ERROR: MOD_NTT_W (%0d) should be even!", MOD_NTT_W);
    end
    if (OP_W > MOD_NTT_W + MID_W) begin : __UNSUPPORTED_OP_W_1
      $fatal(1,"> ERROR: For partial modulo reduction the input should be at most MOD_NTT_W+MOD_NTT_W/2 bits (%0d). Here OP_W=%0d was connected.",MOD_NTT_W + MOD_NTT_W/2, OP_W);
    end
    if (CST >= MOD_NTT_W + MID_W) begin : __UNSUPPORTED_CST_0
      $fatal(1,"> ERROR: Unsupported constant shift (%0d). Should be less than MOD_NTT_W+MOD_NTT_W/2 (%0d)",CST,MOD_NTT_W+MOD_NTT_W/2);
    end
    // Code simplification made
    // Note that for GF64, the max shift is 31*3 = 93, support up to OP_W=67
    if ((OP_W + CST) > 5*MID_W) begin: __UNSUPPORTED_CST_1
      $fatal(1,"> ERROR: Unsupported constant shift. OP_W (%0d) + CST (%0d) should be less or equal to 5*MOD_NTT_W/2 (%0d)",OP_W,CST,5*MOD_NTT_W/2);
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
// Compute a << CST
// Use the following property for the partial reduction :
// 2**MOD_NTT_W = 2**(MOD_NTT_W/2) - 1
// 2**(MOD_NTT_W+MOD_NTT_W/2) = -1
//
// 3 ways to compute according to CST.
// 0         <= CST < MID_W
// MID_W     <= CST < MOD_NTT_W
// MOD_NTT_W <= CST < MOD_NTT_W + MID_W
//

  logic [OP_W+SHIFT-1:0] s0_z_tmp;
  logic [MOD_NTT_W+1:0]  s0_z;
  logic                  s0_sign;
  logic [C_W-1:0]        s0_carry;

  assign s0_z_tmp = s0_a << SHIFT;
  assign s0_sign  = s0_a[OP_W-1];
  assign s0_carry = s0_z_tmp[MOD_NTT_W+:C_W];

  // Note: write the *-1 manually, when CST_SIGN=1, since vivado does not do the simplification.
  generate
    if (CST_SIGN == 1'b0) begin : gen_pos
      //---------------------------
      // shifted word composed of 4 MID_W parts
      //---------------------------
      if (IS_4_PARTS) begin : gen_is_4_parts
        logic [1:0][MID_W-1:0] s0_carry_a;
        assign s0_carry_a = s0_carry;

        if (CST < MID_W) begin : gen_lt_mid_w
          assign s0_z = s0_z_tmp[MOD_NTT_W-1:0]
                        + {s0_carry_a[0],{MID_W{1'b0}}}
                        - s0_carry_a[0]
                        - s0_carry_a[1]
                        + {s0_sign, {C_W-MID_W{1'b0}}};
        end
        else if (CST < MOD_NTT_W) begin : gen_lt_mod_ntt_w
          assign s0_z = {s0_z_tmp[MID_W-1:0],{MID_W{1'b0}}}
                        +{s0_z_tmp[MID_W+:MID_W], {MID_W{1'b0}}}
                        - s0_z_tmp[MID_W+:MID_W]
                        - s0_carry_a
                        + {s0_sign, {C_W{1'b0}}};
        end
        else if (CST < MOD_NTT_W + MID_W) begin : gen_lt_mod_ntt_w_plus_mid_w
          // Actually this part is never used, since we have the assumption
          // (OP_W + CST) <= 5*MID_W
          assign s0_z = {s0_z_tmp[MID_W-1:0], {MID_W{1'b0}}}
                        - s0_z_tmp[MID_W-1:0]
                        - {s0_carry_a[0], s0_z_tmp[MID_W+:MID_W]}
                        + s0_carry_a[1]
                        - {s0_carry_a[1],{MID_W{1'b0}}}
                        - {s0_sign, {C_W-MID_W{1'b0}}}
                        + {s0_sign, {C_W{1'b0}}};

        end
      end // gen_is_4_parts
      //---------------------------
      // shifted word composed of 3 MID_W parts
      //---------------------------
      else begin : gen_not_is_4_parts
        if (CST < MID_W) begin : gen_lt_mid_w
          logic [MOD_NTT_W+1:0] s0_z_sign;
          assign s0_z_sign = {{MID_W{s0_sign}},{C_W{1'b0}}} ;// {s0_sign, {C_W + MID_W{1'b0}}} - {s0_sign, {C_W{1'b0}}}

    //      assign s0_z     = s0_z_tmp[MOD_NTT_W-1:0]
    //                      - s0_carry
    //                      + {s0_sign, {C_W{1'b0}}}
    //                      + {s0_carry, {MID_W{1'b0}}}
    //                      - {s0_sign, {C_W + MID_W{1'b0}}};

          if (C_W == 1) begin : gen_cw_eq_1
            logic [MOD_NTT_W+1:0] s0_z_carry;
            assign s0_z_carry = {MID_W{s0_carry}};
            assign s0_z     = s0_z_tmp[MOD_NTT_W-1:0]
                              + s0_z_carry
                              - s0_z_sign;

          end
          else begin : gen_cw_not_1
            assign s0_z     = s0_z_tmp[MOD_NTT_W-1:0]
                              - s0_carry
                              + {s0_carry, {MID_W{1'b0}}}
                              - s0_z_sign;
          end
        end
        else if (CST < MOD_NTT_W) begin : gen_lt_mod_ntt_w
          assign s0_z     = {s0_z_tmp[MID_W-1:0], {MID_W{1'b0}}}
                          + {s0_z_tmp[MID_W+:MID_W], {MID_W{1'b0}}}
                          - s0_z_tmp[MID_W+:MID_W]
                          - s0_carry
                          + {s0_sign, {C_W{1'b0}}};
        end
        else if (CST < MOD_NTT_W + MID_W) begin : gen_lt_mod_ntt_w_plus_mid_w
          assign s0_z     = {s0_z_tmp[MID_W-1:0], {MID_W{1'b0}}}
                          - s0_z_tmp[MID_W-1:0]
                          - {s0_carry, s0_z_tmp[MID_W+:MID_W]}
                          + {s0_sign, {C_W+MID_W{1'b0}}};
        end
      end // gen_not_is_4_parts
    end // gen_pos
    else begin : gen_no_pos
      //---------------------------
      // shifted word composed of 4 MID_W parts
      //---------------------------
      if (IS_4_PARTS) begin : gen_is_4_parts
        logic [1:0][MID_W-1:0] s0_carry_a;
        assign s0_carry_a = s0_carry;

        if (CST < MID_W) begin : gen_lt_mid_w
          assign s0_z = - s0_z_tmp[MOD_NTT_W-1:0]
                        - {s0_carry_a[0],{MID_W{1'b0}}}
                        + s0_carry_a[0]
                        + s0_carry_a[1]
                        - {s0_sign, {C_W-MID_W{1'b0}}};
        end
        else if (CST < MOD_NTT_W) begin : gen_lt_mod_ntt_w
          assign s0_z = - {s0_z_tmp[MID_W-1:0],{MID_W{1'b0}}}
                        - {s0_z_tmp[MID_W+:MID_W], {MID_W{1'b0}}}
                        + s0_z_tmp[MID_W+:MID_W]
                        + s0_carry_a
                        - {s0_sign, {C_W{1'b0}}};
        end
        else if (CST < MOD_NTT_W + MID_W) begin : gen_lt_mod_ntt_w_plus_mid_w
          // Actually this part is never used, since we have the assumption
          // (OP_W + CST) <= 5*MID_W
          assign s0_z = - {s0_z_tmp[MID_W-1:0], {MID_W{1'b0}}}
                        + s0_z_tmp[MID_W-1:0]
                        + {s0_carry_a[0], s0_z_tmp[MID_W+:MID_W]}
                        - s0_carry_a[1]
                        + {s0_carry_a[1],{MID_W{1'b0}}}
                        + {s0_sign, {C_W-MID_W{1'b0}}}
                        - {s0_sign, {C_W{1'b0}}};

        end
      end // gen_is_4_parts
      //---------------------------
      // shifted word composed of 3 MID_W parts
      //---------------------------
      else begin : gen_not_is_4_parts
        if (CST < MID_W) begin : gen_lt_mid_w
          logic [MOD_NTT_W+1:0] s0_z_sign;
          assign s0_z_sign = {{MID_W{s0_sign}},{C_W{1'b0}}} ;// {s0_sign, {C_W + MID_W{1'b0}}} - {s0_sign, {C_W{1'b0}}}

    //      assign s0_z     = - s0_z_tmp[MOD_NTT_W-1:0]
    //                      + s0_carry
    //                      - {s0_sign, {C_W{1'b0}}}
    //                      - {s0_carry, {MID_W{1'b0}}}
    //                      + {s0_sign, {C_W + MID_W{1'b0}}};

          if (C_W == 1) begin : gen_cw_eq_1
            logic [MOD_NTT_W+1:0] s0_z_carry;
            assign s0_z_carry = {MID_W{s0_carry}};
            assign s0_z     = - s0_z_tmp[MOD_NTT_W-1:0]
                              - s0_z_carry
                              + s0_z_sign;

          end
          else begin : gen_cw_not_1
            assign s0_z     = - s0_z_tmp[MOD_NTT_W-1:0]
                              + s0_carry
                              - {s0_carry, {MID_W{1'b0}}}
                              + s0_z_sign;
          end
        end
        else if (CST < MOD_NTT_W) begin : gen_lt_mod_ntt_w
          assign s0_z     = - {s0_z_tmp[MID_W-1:0], {MID_W{1'b0}}}
                          - {s0_z_tmp[MID_W+:MID_W], {MID_W{1'b0}}}
                          + s0_z_tmp[MID_W+:MID_W]
                          + s0_carry
                          - {s0_sign, {C_W{1'b0}}};
        end
        else if (CST < MOD_NTT_W + MID_W) begin : gen_lt_mod_ntt_w_plus_mid_w
          assign s0_z     = - {s0_z_tmp[MID_W-1:0], {MID_W{1'b0}}}
                          + s0_z_tmp[MID_W-1:0]
                          + {s0_carry, s0_z_tmp[MID_W+:MID_W]}
                          - {s0_sign, {C_W+MID_W{1'b0}}};
        end
      end // gen_not_is_4_parts
    end // gen_no_pos
  endgenerate

// ============================================================================================== //
// s1 : Output pipe
// ============================================================================================== //
// Output pipe
  logic [MOD_NTT_W+1:0] s1_z;
  logic                 s1_avail;
  logic [SIDE_W-1:0]    s1_side;

  always_ff @(posedge clk) begin
    s1_z <= s0_z;
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

  assign z         = s1_z;
  assign out_avail = s1_avail;
  assign out_side  = s1_side;

endmodule
