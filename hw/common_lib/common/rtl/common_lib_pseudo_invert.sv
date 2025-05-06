// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module invert the value according to a base B, and a step.
//
// For a value v in 0...B^S-1, if we decompose it in the B-base:
//    v = v_0*B^0 + v_1*B^1 + ... v_(S-1)*B^(S-1)
//    where v_j (a digit) is in 0...B-1
// ----------------------------------------------------------------------------------------------
//    The pseudo invert order, at step s, of v in base B, for a number of S stages is:
//    pseudo_invert_order(v) = v_(S-1-step)*B^(S-1) + v_(S-1-step-1)*B^(S-2) +...+v_0*B^(step)+v_(S-1-step+1)*B^(step-1)+..+v_(S-2)*B^1+v_(S-1)*B^0
// ----------------------------------------------------------------------------------------------
//    B is a power of 2, >= 2
//    step in in 0..S-1
//    S >=2
//
//    step = 0 <=> invert entirely
//
// ==============================================================================================

module common_lib_pseudo_invert
#(
  parameter  int S   = 4,
  parameter  int B   = 2,
  localparam int B_W = $clog2(B),
  localparam int S_W = $clog2(S)
)
(
  input  logic [S-1:0][B_W-1:0] v,
  input  logic [S_W-1:0]        step,

  output logic [S-1:0][B_W-1:0] z
);

  always_comb begin
    for (int s=0; s<S; s=s+1) begin
      if (s < step) z[s] = v[S-1-s];
      else          z[s] = v[s-step];
     end
  end

endmodule
