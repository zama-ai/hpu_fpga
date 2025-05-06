// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module reverse the value according to a base B, and a step.
//
// For a value v in 0...B^S-1, if we decompose it in the B-base:
//    v = v_0*B^0 + v_1*B^1 + ... v_(S-1)*B^(S-1)
//    where v_j (a digit) is in 0...B-1
// ----------------------------------------------------------------------------------------------
//    The pseudo reverse order, at step s, of v in base B, for a number of S stages is:
//    pseudo_reverse_order(v) = v_step*B^(S-1) + v_(step+1)*B^(S-2) +...+v_(S-1)*B^(step)+v_(step-1)*B^(step-1)+..+v_1*B^1+v_0*B^0
//
//    B is a power of 2, >= 2
//    step in in 0..S-1
//    S >=2
//
//    step = 0 <=> reverse entirely
//
// ==============================================================================================

module common_lib_pseudo_reverse
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
      if (s < step) z[s] = v[s];
      else          z[s] = v[S-1-(s-step)];
     end
  end

endmodule
