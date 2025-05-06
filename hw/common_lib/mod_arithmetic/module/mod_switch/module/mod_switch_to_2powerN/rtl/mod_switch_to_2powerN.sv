// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Modulo switch to a power of 2
// ----------------------------------------------------------------------------------------------
//
// The modulo switch takes as input:
//  - an input coefficient 'a' in modulo p
//  - an output coefficient 'z' in a power-of-2 modulo q
//
// The operation is the following:
//   z = round((a * MOD_Q * 2**PRECISION_W)/(MOD_P * 2**PRECISION_W))
//   We compute the constant : (MOD_Q * 2**PRECISION_W)/MOD_P.
//
// Notes :
//   - Modulo q must be of the form 2**MOD_Q_W for this modulo switch to work
//   - This module requires a multiplication constant with a precision of MULT_CST_W bits
//     defined as `round(MOD_Q/MOD_P*2**MULT_CST_W)`
//     The precision has an effect on the error of the modulo switch result.
//
// Parameters :
//  - Width of power-of-2 modulo q: MOD_Q_W
//  - Width of input modulo p: MOD_P_W
//  - Modulo p: MOD_P
//  - The precision width: PRECISION_W.
//
// ==============================================================================================

module mod_switch_to_2powerN
  import mod_switch_to_2powerN_pkg::*;
  import common_definition_pkg::*;
#(
  parameter int           MOD_Q_W        = 32,  // Width of Modulo q
  parameter int           MOD_P_W        = 32,  // Width of Modulo p
  parameter [MOD_P_W-1:0] MOD_P          = 2 ** 32 - 2 ** 17 - 2 ** 13 + 1,
  parameter int_type_e    MOD_P_INV_TYPE = INT_UNKNOWN, // If the inverse is of a particular type, this could accelerate the mult
  parameter arith_mult_type_e MULT_TYPE  = MULT_KARATSUBA, // in case there is no acceleration for x MOD_P_INV
  parameter int           PRECISION_W    = 33,
  parameter bit           IN_PIPE        = 1'b1,
  parameter int           SIDE_W         = 0,// Side data size. Set to 0 if not used
  parameter [1:0]         RST_SIDE       = 0 // If side data is used,
                                             // [0] (1) reset them to 0.
                                             // [1] (1) reset them to 1.
)
(
  input  logic                 clk,        // clock
  input  logic                 s_rst_n,    // synchronous reset
  input  logic [MOD_P_W-1:0]   a,
  output logic [MOD_Q_W-1:0]   z,
  input  logic                 in_avail,
  output logic                 out_avail,
  input  logic [SIDE_W-1:0]    in_side,
  output logic [SIDE_W-1:0]    out_side
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
// Additional bit because 2**(MOD_Q_W+PRECISION_W) is MOD_Q_W+PRECISION_W+1 bit
  localparam int             CST_W_TMP= MOD_Q_W+PRECISION_W+1;
  localparam [CST_W_TMP-1:0] CST_TMP  = (2**(MOD_Q_W+PRECISION_W)) / MOD_P;
  localparam int             CST_W    = MOD_Q_W+PRECISION_W-MOD_P_W+1;
  localparam [CST_W-1:0]     CST_MULT = CST_TMP;

// ============================================================================================== --
// Input register
// ============================================================================================== --
  logic [MOD_P_W-1:0] s0_ms_in;
  logic               s0_avail;
  logic [SIDE_W-1:0]  s0_side;

  generate
    if (IN_PIPE) begin : gen_in_reg
      always_ff @(posedge clk) begin
        s0_ms_in <= a;
      end
    end else begin : gen_in
      assign s0_ms_in = a;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail ),
    .out_avail(s0_avail ),

    .in_side  (in_side  ),
    .out_side (s0_side  )
  );

// ============================================================================================== --
// s0 : multiply by MULT_CST
// ============================================================================================== --
  logic [MOD_P_W+CST_W-1:0]   s1_mod_switch_x_cst;
  logic                       s1_avail;
  logic [SIDE_W-1:0]          s1_side;

  //assign s1_mod_switch_x_cst = (s1_ms_in * CST_MULT);
  arith_mult_constant #(
    .IN_PIPE        (LAT_PIPE_MH[0]),
    .IN_W           (MOD_P_W       ),
    .CST_W          (CST_W         ),
    .CST            (CST_MULT      ),
    .CST_TYPE       (MOD_P_INV_TYPE),
    .MULT_TYPE      (MULT_TYPE ),
    .SIDE_W         (SIDE_W    ),
    .RST_SIDE       (RST_SIDE  )
  ) arith_mult_constant (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
    .a        (s0_ms_in     ),
    .z        (s1_mod_switch_x_cst),
    .in_avail (s0_avail ),
    .out_avail(s1_avail),
    .in_side  (s0_side  ),
    .out_side (s1_side )
  );

// ============================================================================================== --
// s1 : Rounding
// ============================================================================================== --
  logic [MOD_Q_W-1:0] s1_result;

  // Check highest discarded bit to check if an upwards rounding is required
  assign s1_result = (s1_mod_switch_x_cst[PRECISION_W-1]) ?
      (s1_mod_switch_x_cst[MOD_P_W+CST_W-2:PRECISION_W] + 1'b1) :
      s1_mod_switch_x_cst[MOD_P_W+CST_W-2:PRECISION_W];

// pragma translate_off
  always_ff @(posedge clk)
  if (!s_rst_n) begin
    // do nothing
  end
  else begin
    if (s1_avail)
      assert(s1_mod_switch_x_cst[MOD_P_W+CST_W-1] == 1'b0)
      else begin
        $fatal(1, "%t > ERROR: MSB of s1_mod_switch_x_cst is 1 : overflow!", $time);
      end
  end
// pragma translate_on

// ============================================================================================== --
// Output register
// ============================================================================================== --
  logic [MOD_Q_W-1:0] s2_result;
  logic               s2_avail;
  logic [SIDE_W-1:0]  s2_side;

  generate
    if (LAT_PIPE_MH[1]) begin : gen_out_reg
      always_ff @(posedge clk) begin
        s2_result <= s1_result;
      end
    end else begin : gen_out
      assign s2_result = s1_result;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[1]),
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

// ============================================================================================== --
// Assign Output
// ============================================================================================== --
  assign z         = s2_result;
  assign out_avail = s2_avail;
  assign out_side  = s2_side;


endmodule
