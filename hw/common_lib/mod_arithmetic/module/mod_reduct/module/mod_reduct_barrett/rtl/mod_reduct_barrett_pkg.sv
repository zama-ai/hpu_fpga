// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// mod_reduct_barrett package
// Contains functions related to mod_reduct_barrett:
//   get_latency : output mod_reduct_barrett latency value (does not take into account IN_PIPE)
// ==============================================================================================

package mod_reduct_barrett_pkg;
  import common_definition_pkg::*;
  import arith_mult_pkg::*;

  // Internal pipes
  localparam int LAT_MAX = 2;
  localparam [LAT_MAX-1:0] LAT_PIPE_MH = {1'b1,  // output pipe - recommended
                                          1'b0}; // internal pipe

  // LATENCY of mod_reduct_barrett.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency(input arith_mult_type_e MULT_TYPE);
    return 2*arith_mult_pkg::get_latency(MULT_TYPE) + $countones(LAT_PIPE_MH);
  endfunction
endpackage
