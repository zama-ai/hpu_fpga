// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module find the position of the last bit equals to 1.
// The result is given in 1-hot or extended to MSB.
// The result is found in log2(NB_BITS) stages.
//
// Assumption : NB_BITS >= 2
// ==============================================================================================

module common_lib_find_last_bit_equal_to_1
#(
    parameter int NB_BITS = 8
)
(
  input  [NB_BITS-1:0] in_vect_mh,
  output [NB_BITS-1:0] out_vect_1h,
  output [NB_BITS-1:0] out_vect_ext_to_lsb
);

// ============================================================================================= --
// localparam
// ============================================================================================= --
  localparam int STAGE_NB   = $clog2(NB_BITS);

// ============================================================================================= --
// common_lib_find_last_bit_equal_to_1
// ============================================================================================= --
  wire [NB_BITS-1:0] vect_array[0:STAGE_NB-1];

  genvar gen_i;

  assign  vect_array[0] = in_vect_mh | {1'b0, in_vect_mh[NB_BITS-1:1]};
  generate
    for(gen_i=1; gen_i<STAGE_NB; gen_i=gen_i+1) begin
      assign  vect_array[gen_i] = vect_array[gen_i-1] | {{2**gen_i{1'b0}},vect_array[gen_i-1][NB_BITS-1:(2**gen_i)]};
    end
  endgenerate

  assign out_vect_1h         = in_vect_mh & {1'b1,~vect_array[STAGE_NB-1][NB_BITS-1:1]};
  assign out_vect_ext_to_lsb = vect_array[STAGE_NB-1][NB_BITS-1:0];

endmodule

