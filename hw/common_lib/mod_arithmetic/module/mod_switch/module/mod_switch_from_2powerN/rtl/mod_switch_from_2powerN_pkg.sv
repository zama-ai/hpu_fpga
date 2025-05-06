// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// mod_switch_from_2powerN package
// Contains functions related to mod_switch_from_2powerN:
//   get_latency : output mod_switch_from_2powerN latency value (does not take into account IN_PIPE)
// ==============================================================================================

package mod_switch_from_2powerN_pkg;
  import common_definition_pkg::*;
  import arith_mult_constant_pkg::*;

  localparam int           LAT_MAX     = 2;
  localparam [LAT_MAX-1:0] LAT_PIPE_MH = {1'b1,  // Output pipe
                                          1'b0};// multiplier input pipe

  // LATENCY of mod_switch_from_2powerN_pkg.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency(input int_type_e MOD_P_TYPE, input arith_mult_type_e MULT_TYPE);
    return $countones(LAT_PIPE_MH) + arith_mult_constant_pkg::get_latency(MOD_P_TYPE,MULT_TYPE);
  endfunction
endpackage

