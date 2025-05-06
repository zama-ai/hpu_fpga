// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Fake CT
// ----------------------------------------------------------------------------------------------
//
// Used to test mdc network.
//
// ==============================================================================================

module ntt_radix_cooley_tukey
  import common_definition_pkg::*;
#(
  parameter int        R             = 8,
  parameter mod_reduct_type_e     REDUCT_TYPE   = MOD_REDUCT_SOLINAS2,
  parameter mod_mult_type_e       MOD_MULT_TYPE = MOD_MULT_SOLINAS2,
  parameter arith_mult_type_e     MULT_TYPE     = MULT_KARATSUBA,
  parameter int        OP_W          = 32,
  parameter [OP_W-1:0] MOD_M         = 2**OP_W - 2**(OP_W/2) + 1,
  parameter int        OMG_SEL_NB    = 2,
  parameter bit        IN_PIPE       = 1'b1,
  parameter int        SIDE_W        = 0,// Side data size. Set to 0 if not used
  parameter [1:0]      RST_SIDE      = 0, // If side data is used,
                                       // [0] (1) reset them to 0.
                                       // [1] (1) reset them to 1.
  parameter  bit       USE_MOD_MULT  = 0,
  parameter  bit       OUT_NATURAL_ORDER = 1, //(0) Output in reverse2 order, (1) natural order
  localparam int       OMG_SEL_W     = OMG_SEL_NB == 1 ? 1 : $clog2(OMG_SEL_NB)
)
(
  // System interface
  input  logic                                     clk,
  input  logic                                     s_rst_n,
  // Data inteface
  input  logic [R-1:0][OP_W-1:0]                   xt_a,
  output logic [R-1:0][OP_W-1:0]                   xf_a,
  input  logic [R-1:1][OP_W-1:0]                   phi_a,   // Phi root of unity
  input  logic [OMG_SEL_NB-1:0][R/2-1:0][OP_W-1:0] omg_a,   // quasi static signal
  input  logic [OMG_SEL_W-1:0]                     omg_sel, // data dependent selector
  // Control
  input  logic                                     in_avail,
  output logic                                     out_avail,
  // Optional
  input  logic [SIDE_W-1:0]                        in_side,
  output logic [SIDE_W-1:0]                        out_side
);


  always_ff @(posedge clk)
    if (!s_rst_n) begin
      out_avail <= '0;
    end
    else begin
      out_avail <= in_avail;
    end

  always_ff @(posedge clk) begin
    xf_a     <= xt_a;
    out_side <= in_side;
  end

endmodule

