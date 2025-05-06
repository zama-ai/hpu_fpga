// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// mod_mult package
// Contains functions related to mod_mult:
//   get_latency : output mod_mult latency value (does not take into account IN_PIPE)
// ==============================================================================================

package mod_mult_pkg;
  import common_definition_pkg::*;
  import mod_reduct_pkg::*;
  import arith_mult_pkg::*;

  // LATENCY of mod_mult.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency(input mod_mult_type_e MOD_MULT_TYPE, input arith_mult_type_e MULT_TYPE=MULT_UNKNOWN);
    int with_reduct_lat;
    with_reduct_lat = MULT_TYPE == MULT_GOLDILOCKS_CASCADE ? arith_mult_pkg::get_latency(MULT_TYPE) : arith_mult_pkg::get_latency(MULT_TYPE) + 1 ; // TODO
    with_reduct_lat = with_reduct_lat +
          (MOD_MULT_TYPE == MOD_MULT_MERSENNE
          || MOD_MULT_TYPE == MOD_MULT_BARRETT
          || MOD_MULT_TYPE == MOD_MULT_SOLINAS2
          || MOD_MULT_TYPE == MOD_MULT_SOLINAS3
          || MOD_MULT_TYPE == MOD_MULT_GOLDILOCKS ? mod_reduct_pkg::get_latency(common_definition_pkg::get_mod_reduct(MOD_MULT_TYPE), MULT_TYPE):
             0); // ERROR : unknown MOD_MULT_TYPE
    return with_reduct_lat;
  endfunction
endpackage
