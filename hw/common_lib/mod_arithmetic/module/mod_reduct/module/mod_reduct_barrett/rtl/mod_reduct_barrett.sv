// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
//  Description  : Performs a modular reduction using Generalised Barrett algorithm
// ----------------------------------------------------------------------------------------------
//
//  Performs a fully pipelined reduction z = (a modulo mod_m) using a generalized barrett
//  modular reduction for integer.
//
//  BARRETT_CST = floor(2**(2*MOD_W+alpha)/MOD_M)
//  a is a 2*MOD_W+1 - bit input
//
//  Ref: Speeding up Barrett and Montgomery modular multiplication algo.2
//     The computed error is less than:
//     error <= floor(1+2^(MOD_W-alpha)+2^(beta+1)-1/(2^(alpha-beta)))
//
// ----------------------------------------------------------------------------------------------
//  The algorithm is the following :
//
//  b = a >> (MOD_W+beta)
//  c = b * BARRETT_CST
//  d = c >> (alpha-beta)
//  e = d*MOD_M
//  f = a - e
//
//  Correction to do "error" times:
//  if f >= M : f = f - MOD_M
//
//   return f
//
//  To support output of 2*MOD_W+1 bits
//  With: (chosen solution)
//    alpha = MOD_W+2
//    beta  = -2
//    to get an error of 1 (at most 1 correction at the end)
// ----------------------------------------------------------------------------------------------
//    alpha = MOD_W+1
//    beta  = -1
//    to get an error of 2 (at most 2 corrections at the end)
//
// ----------------------------------------------------------------------------------------------
//  LATENCY = IN_PIPE + 2*LAT_MULT + $countones(LAT_PIPE_MH)
// ==============================================================================================

module mod_reduct_barrett
  import common_definition_pkg::*;
#(
  parameter int          MOD_W      = 32,
  parameter [MOD_W-1:0]  MOD_M      = 2**MOD_W - 2**(MOD_W/2) + 1,
  parameter int          OP_W       = 2*MOD_W+1, // Should be in [MOD_W:2*MOD_W+1]
  parameter arith_mult_type_e       MULT_TYPE  = MULT_KARATSUBA,
  parameter bit          IN_PIPE    = 1,
  parameter int          SIDE_W     = 0, // Side data size. Set to 0 if not used
  parameter [1:0]        RST_SIDE   = 0  // If side data is used,
                                         // [0] (1) reset them to 0.
                                         // [1] (1) reset them to 1.

) (
    // System interface
    input  logic               clk,
    input  logic               s_rst_n,
    // Data interface
    input  logic [   OP_W-1:0] a,
    output logic [  MOD_W-1:0] z,
    // Control + side interface - optional
    input  logic               in_avail,
    output logic               out_avail,

    input  logic [SIDE_W-1:0]  in_side,
    output logic [SIDE_W-1:0]  out_side
);

  // This package contains internal pipes definition.
  import mod_reduct_barrett_pkg::*;

// ============================================================================================== //
// localparam
// ============================================================================================== //
 // Need (MOD_W + 2) x (MOD_W + 2)) multiplication
/*  localparam int ALPHA   = MOD_W + 2;
  localparam int BETA    = -2;
  localparam int CORR_NB = 1;
*/

  // Need : (MOD_W + 2) x (MOD_W + 1) multiplication
  localparam int ALPHA   = MOD_W + 1;
  localparam int BETA    = -1;
  localparam int CORR_NB = 2;


  localparam [MOD_W+ALPHA:0] BARRETT_CST_TMP = (2**(MOD_W+ALPHA)) / MOD_M;
  localparam [ALPHA:0]       BARRETT_CST     = BARRETT_CST_TMP[ALPHA:0];

  localparam int             PROC_W          = MOD_W*2+1;

  localparam int A_DATA_W = SIDE_W + PROC_W;
  localparam int F_DATA_W = SIDE_W + MOD_W + CORR_NB;
  localparam int Z_DATA_W = SIDE_W + MOD_W;

  // parameter check
  generate
    if (OP_W > PROC_W) begin : __UNSUPPORTED_PARAM_OP_W__
      $fatal(1, "> ERROR: Unsupported operand size OP_W. Should be less than %d.",PROC_W);
    end
    if (MOD_W + BETA < 0) begin : __UNSUPPORTED__MOD_W_LT_BETA__
      $fatal(1, "> ERROR : Unsupported MOD_W in mod_reduct_barrett : should be >= -beta");
    end
  endgenerate

// ============================================================================================== //
// s0
// ============================================================================================== //
// input pipe
// start the compute :
//==== b = a >> (MOD_W+BETA)
//==== c = b * BARRETT_CST
//==== d = c >> (ALPHA-BETA)

  logic [PROC_W-1:0]     a_ext;
  logic [PROC_W-1:0]     s0_a;
  logic [MOD_W-BETA:0]   s0_b;
  logic                  s0_avail;
  logic [SIDE_W-1:0]     s0_side;

  logic [A_DATA_W-1:0]   in_a_data;
  logic [A_DATA_W-1:0]   s0_a_data;

  assign a_ext = a; // extend MSB with 0

  generate
    if (SIDE_W > 0) begin
      assign in_a_data       = {in_side, a_ext};
      assign {s0_side, s0_a} = s0_a_data;
    end
    else begin
      assign in_a_data = a_ext;
      assign s0_a      = s0_a_data;
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

  assign s0_b = s0_a[PROC_W-1 : MOD_W+BETA];

  logic [MOD_W-BETA+ALPHA+1:0] s1_c;
  logic [MOD_W+1:0]            s1_d;
  logic [A_DATA_W-1:0]         s1_a_data;
  logic                        s1_avail;

  arith_mult #(
  .OP_A_W         ($size(s0_b)       ),
  .OP_B_W         ($size(BARRETT_CST)),
  .MULT_TYPE      (MULT_TYPE         ),
  .IN_PIPE        (0                 ),
  .SIDE_W         (A_DATA_W          ),
  .RST_SIDE       (RST_SIDE          )
  ) s0_arith_mult (
    .clk       (clk        ),
    .s_rst_n   (s_rst_n    ),
    .a         (s0_b       ),
    .b         (BARRETT_CST),
    .z         (s1_c       ),
    .in_avail  (s0_avail   ),
    .out_avail (s1_avail   ),
    .in_side   (s0_a_data  ),
    .out_side  (s1_a_data  )
  );

  assign s1_d = s1_c[$left(s1_c):ALPHA-BETA];

// ============================================================================================== //
// s1
// ============================================================================================== //
// e = d*MOD_M
  logic [2*MOD_W+1:0]  s2_e;
  logic [PROC_W-1:0]   s2_a;
  logic [SIDE_W-1:0]   s2_side;
  logic                s2_avail;
  logic [A_DATA_W-1:0] s2_a_data;

  arith_mult #(
  .OP_A_W         ($size(s1_d) ),
  .OP_B_W         ($size(MOD_M)),
  .MULT_TYPE      (MULT_TYPE   ),
  .IN_PIPE        (0           ),
  .SIDE_W         (A_DATA_W    ),
  .RST_SIDE       (RST_SIDE    )
  ) s1_arith_mult (
    .clk       (clk        ),
    .s_rst_n   (s_rst_n    ),
    .a         (s1_d       ),
    .b         (MOD_M      ),
    .z         (s2_e       ),
    .in_avail  (s1_avail   ),
    .out_avail (s2_avail   ),
    .in_side   (s1_a_data  ),
    .out_side  (s2_a_data  )
  );

  generate
    if (SIDE_W > 0) begin
      assign {s2_side, s2_a} = s2_a_data;
    end
    else begin
      assign s2_a            = s2_a_data;
    end
  endgenerate

// ============================================================================================== //
// s2
// ============================================================================================== //
// f = a - e
  logic [2*MOD_W+2:0] s2_f;

  assign s2_f = {2'b00,s2_a} - {1'b0,s2_e};

// pragma translate_off
// Check the value of s2_f
  always_ff @(posedge clk)
    if (s2_f !== 'x) begin
      assert(s2_f[$left(s2_f)] == 0)
      else begin
        $display("%t > ERROR: Barrett reduction underflow ! mod_m=0x%0x barrett_cst=0x%0x in=0x%0x",
                    $time, MOD_M, BARRETT_CST, s2_a);
        $finish;
      end

      assert(s2_f[2*MOD_W:0] < (1+CORR_NB)*MOD_M)
      else begin
        $display("%t > ERROR: Barrett reduction overflow (CORR_NB=%1d)! mod_m=0x%0x barrett_cst=0x%0x in=0x%0x seen=0x%0x",
                  $time, CORR_NB, MOD_M, BARRETT_CST, s2_a, s2_f);
        $finish;
      end
    end
// pragma translate_on

// ============================================================================================== //
// s3
// ============================================================================================== //
// Correction
  logic [MOD_W+CORR_NB-1:0]              s3_f;
  logic [MOD_W-1:0]                      s3_z;
  logic [CORR_NB-1:0][MOD_W+CORR_NB:0]   s3_f_minus_m;
  logic [CORR_NB-1:-1][MOD_W+CORR_NB:0]  s3_f_minus_m_ext;
  logic [CORR_NB-1:0]                    s3_sign;

  logic [SIDE_W-1:0]                     s3_side;
  logic                                  s3_avail;
  logic [F_DATA_W-1:0]                   s2_f_data;
  logic [F_DATA_W-1:0]                   s3_f_data;

  generate
    if (SIDE_W > 0) begin
      assign s2_f_data       = {s2_side, s2_f[MOD_W+CORR_NB-1:0]};// Drop the MSB that are not necessary
      assign {s3_side, s3_f} = s3_f_data;
    end
    else begin
      assign s2_f_data       = s2_f[MOD_W+CORR_NB-1:0];// Drop the MSB that are not necessary
      assign s3_f            = s3_f_data;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[0]),
    .SIDE_W     (F_DATA_W),
    .RST_SIDE   (RST_SIDE)
  ) s2_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
                        
    .in_avail (s2_avail ),
    .out_avail(s3_avail ),
                        
    .in_side  (s2_f_data),
    .out_side (s3_f_data)
  );

  always_comb
    for (int i=0; i<CORR_NB; i=i+1) begin
      s3_f_minus_m[i] = {1'b0, s3_f} - ({{(CORR_NB+1){1'b0}}, MOD_M} << i);
      s3_sign[i]      = s3_f_minus_m[i][MOD_W+CORR_NB];
    end

  assign s3_f_minus_m_ext = {s3_f_minus_m, {1'b0, s3_f}};

  always_comb begin
    logic [MOD_W-1:0] tmp;
    tmp = s3_f_minus_m[CORR_NB-1][MOD_W-1:0];
    for (int i=CORR_NB-1; i>=0; i=i-1)
      tmp = s3_sign[i] ? s3_f_minus_m_ext[i-1][MOD_W-1:0] : tmp;
    s3_z = tmp;
  end

// ============================================================================================== //
// Output pipe
// ============================================================================================== //
  logic [MOD_W-1:0]    s4_z;
  logic [SIDE_W-1:0]   s4_side;
  logic                s4_avail;
  logic [Z_DATA_W-1:0] s3_z_data;
  logic [Z_DATA_W-1:0] s4_z_data;

  generate
    if (SIDE_W > 0) begin
      assign s3_z_data       = {s3_side, s3_z};
      assign {s4_side, s4_z} = s4_z_data;
    end
    else begin
      assign s3_z_data       = s3_z;
      assign s4_z            = s4_z_data;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[1]),
    .SIDE_W     (Z_DATA_W),
    .RST_SIDE   (RST_SIDE)
  ) s3_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
                        
    .in_avail (s3_avail ),
    .out_avail(s4_avail ),
                        
    .in_side  (s3_z_data),
    .out_side (s4_z_data)
  );

  assign z         = s4_z;
  assign out_avail = s4_avail;
  assign out_side  = s4_side;

// pragma translate_off
  `include "cov_mod_reduct_barrett.sv"
// pragma translate_on
 
endmodule
