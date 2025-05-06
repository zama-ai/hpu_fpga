// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Modulo Switch from a power of 2
// ----------------------------------------------------------------------------------------------
//
// The modulo switch takes as input:
//  - a signed input coefficient 'a' in a power-of-2 modulo q
//  - an unsigned output coefficient 'z' in modulo p
//
// Notes :
//   - Modulo q must be of the form 2**MOD_Q_W for this modulo switch to work
//   - Pipeline register corresponding to LAT_PIPE_MH[2] is larger than needed,
//     let synthesizer handle its optimisation.
//
// Parameters :
//  - Width of power-of-2 modulo q: MOD_Q_W
//  - Power-of-2 modulo q: MOD_Q
//  - Width of NTT-friendly prime p: MOD_P_W
//  - NTT-friendly prime p: MOD_P
//  - Decomposition base log: IN_W
//    The width of a subword is IN_W+1.
//
// ==============================================================================================

module mod_switch_from_2powerN
  import mod_switch_from_2powerN_pkg::*;
  import common_definition_pkg::*;
#(
  parameter int           MOD_Q_W    = 32,  // Width of Modulo q
  parameter int           MOD_P_W    = 32,  // Width of Modulo p
  parameter [MOD_P_W-1:0] MOD_P      = 2 ** 32 - 2 ** 17 - 2 ** 13 + 1,
  parameter int           IN_W       = 8,   // Input data width
  parameter int_type_e    MOD_P_TYPE = SOLINAS3,
  parameter arith_mult_type_e MULT_TYPE  = MULT_KARATSUBA, // in case there is no acceleration for x MOD_P
  parameter bit           IN_PIPE    = 1'b1,
  parameter int           SIDE_W     = 0,// Side data size. Set to 0 if not used
  parameter [1:0]         RST_SIDE   = 0 // If side data is used,
                                         // [0] (1) reset them to 0.
                                         // [1] (1) reset them to 1.
) (
  input  logic                 clk,
  input  logic                 s_rst_n,
  input  logic [IN_W:0]        a, // 2's complement signed
  output logic [MOD_P_W-1:0]   z, // unsigned
  input  logic                 in_avail,
  output logic                 out_avail,
  input  logic [SIDE_W-1:0]    in_side,
  output logic [SIDE_W-1:0]    out_side
);

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  localparam [MOD_Q_W:0] MOD_Q = 2 ** MOD_Q_W;

  // ============================================================================================== --
  // Input register
  // ============================================================================================== --
  logic [IN_W:0]     s0_ms_in;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;

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
  // s0 : Absolute Value
  // ============================================================================================== --
  // The input value is a signed value, in 2s complement
  // Reduce it to an unsigned value in [0:MOD_Q-1]
  logic [MOD_Q_W-1:0] s0_abs_mod_switch;

  // s0_absolute value of the decomposer output
  assign s0_abs_mod_switch = (s0_ms_in[IN_W] == 1'b1) ?
                          {1'b0, MOD_Q} + {{(MOD_Q_W-IN_W-1){1'b1}}, s0_ms_in} :
                          {{(MOD_Q_W-IN_W-1){1'b0}}, s0_ms_in};

  // ============================================================================================== --
  // s0_bis : Multiply Abs Value by MOD_P
  // ============================================================================================== --
  logic [MOD_Q_W+MOD_P_W-1:0] s1_mod_switch_x_mod_p;
  logic                       s1_avail;
  logic [SIDE_W-1:0]          s1_side;

  //assign s1_mod_switch_x_mod_p = (s1_abs_mod_switch * MOD_P);
  arith_mult_constant #(
    .IN_PIPE        (LAT_PIPE_MH[0]),
    .IN_W           (MOD_Q_W   ),
    .CST_W          (MOD_P_W   ),
    .CST            (MOD_P     ),
    .CST_TYPE       (MOD_P_TYPE),
    .MULT_TYPE      (MULT_TYPE ),
    .SIDE_W         (SIDE_W    ),
    .RST_SIDE       (RST_SIDE  )
  ) arith_mult_constant (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
    .a        (s0_abs_mod_switch      ),
    .z        (s1_mod_switch_x_mod_p),
    .in_avail (s0_avail ),
    .out_avail(s1_avail),
    .in_side  (s0_side  ),
    .out_side (s1_side )
  );

  // ============================================================================================== --
  // s1 : Rounding
  // ============================================================================================== --
  logic [MOD_P_W-1:0] s1_result;

  // Check highest discarded bit to check if an upwards rounding is required
  assign s1_result = (s1_mod_switch_x_mod_p[MOD_Q_W-1]) ?
      (s1_mod_switch_x_mod_p[MOD_P_W+MOD_Q_W-1:MOD_Q_W] + 1'b1) :
      s1_mod_switch_x_mod_p[MOD_P_W+MOD_Q_W-1:MOD_Q_W];

  // ============================================================================================== --
  // Output register
  // ============================================================================================== --
  logic [MOD_P_W-1:0] s2_result;
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
