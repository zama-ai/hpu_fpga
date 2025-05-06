// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs an accumulation on 2s complement values in
//                goldilocks 64 field. The result is partially modular reduced
//                to a 2s complement over MOD_NTT_W+2 bits.
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
// Definition of 2s complement representation:
// v[W:0] in 2s complement
// In Z, its value is : -2^W + v[W-1:0]
//
// Then the reduction of all the bits above MOD_NTT_W is done using the properties above.
// The result a 2s complement number with MOD_NTT_W + 2 bits.
//
// Note that the inputs are 2s complement numbers.
// ==============================================================================================

module ntt_core_gf64_pmr_acc #(
  parameter int            MOD_NTT_W = 64, // Should be 64 for GF64. Mainly used in verification
                                           // Should be even
  parameter int            OP_W      = MOD_NTT_W + 1 + 1, // 2 additional bits + 1bit of sign. Data are in 2s complement.
  parameter int            ELT_NB    = 3, // GLWE_K_P1 * PBS_L : Maximum number of elements to be accumulated
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

  // Control interface - mandatory
  input  logic                 in_sol,    // First coefficient
  input  logic                 in_eol,    // Last coefficient
  input  logic                 in_avail,
  output logic                 out_avail,

  // Side interface - optional
  input  logic [SIDE_W-1:0]    in_side,
  output logic [SIDE_W-1:0]    out_side
);

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  localparam int EXT_W = $clog2(ELT_NB);
  localparam int ACC_W = OP_W + EXT_W;

  // ============================================================================================== --
  // s0 : Input pipe
  // ============================================================================================== --
  //== Input pipe
  logic [OP_W-1:0]   s0_a;
  logic              s0_sol;
  logic              s0_eol;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;

  generate
    if (IN_PIPE) begin : gen_input_pipe
      always_ff @(posedge clk) begin
        s0_a   <= a;
        s0_sol <= in_sol;
        s0_eol <= in_eol;
      end
    end
    else begin : no_gen_input_pipe
      assign s0_a     = a;
      assign s0_sol   = in_sol;
      assign s0_eol   = in_eol;
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

  // ============================================================================================== --
  // s1 : Accumulation
  // ============================================================================================== --
  logic [ACC_W-1:0]  s1_acc;
  logic              s1_avail;
  logic [SIDE_W-1:0] s1_side;
  logic [ACC_W-1:0]  s1_accD;
  logic              s1_availD;
  logic [SIDE_W-1:0] s1_sideD;

  assign s1_availD = s0_avail & s0_eol;
  assign s1_accD   = s0_avail ? s0_sol ? {{EXT_W{s0_a[OP_W-1]}},s0_a} : s1_acc + {{EXT_W{s0_a[OP_W-1]}},s0_a} : // sign extension
                                s1_acc;
  assign s1_sideD  = s1_availD ? s0_side : s1_side;

  always_ff @(posedge clk) begin
    s1_acc  <= s1_accD;
    s1_side <= s1_sideD;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s1_avail <= 1'b0;
    else          s1_avail <= s1_availD;

  // ============================================================================================== --
  // s2 : Reduction
  // ============================================================================================== --
  logic [MOD_NTT_W+1:0] s2_result;
  logic                 s2_avail;
  logic [SIDE_W-1:0]    s2_side;

  ntt_core_gf64_pmr #(
    .MOD_NTT_W (MOD_NTT_W),
    .OP_W      (ACC_W),
    .IN_PIPE   (1'b0),
    .SIDE_W    (SIDE_W),
    .RST_SIDE  (RST_SIDE)
  ) ntt_core_gf64_pmr (
    .clk       (clk),
    .s_rst_n   (s_rst_n),

    .a         (s1_acc),
    .z         (s2_result),

    .in_avail  (s1_avail),
    .out_avail (s2_avail),
    .in_side   (s1_side),
    .out_side  (s2_side)
  );

  assign z         = s2_result;
  assign out_avail = s2_avail;
  assign out_side  = s2_side;
 endmodule
