// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// mod_reduct package
// Contains functions related to mod_reduct:
//   get_latency : output mod_reduct latency value (does not take into account IN_PIPE)
// ==============================================================================================

package mod_reduct_pkg;
  import common_definition_pkg::*;
  import mod_reduct_mersenne_pkg::*;
  import mod_reduct_barrett_pkg::*;
  import mod_reduct_solinas2_pkg::*;
  import mod_reduct_solinas3_pkg::*;
  import mod_reduct_64bgoldilocks_karatsuba_pkg::*;

  // LATENCY of mod_reduct.
  // This function enables parent module to have access to the default LATENCY value.
  // MULT_TYPE is only necessary with REDUCT_TYPE == "BARRETT"
  function int get_latency(input mod_reduct_type_e REDUCT_TYPE,
                           input arith_mult_type_e MULT_TYPE = MULT_UNKNOWN);
    int lat;
    lat = REDUCT_TYPE == MOD_REDUCT_MERSENNE ? mod_reduct_mersenne_pkg::get_latency():
          REDUCT_TYPE == MOD_REDUCT_BARRETT  ? mod_reduct_barrett_pkg::get_latency(MULT_TYPE):
          REDUCT_TYPE == MOD_REDUCT_SOLINAS2 ? mod_reduct_solinas2_pkg::get_latency():
          REDUCT_TYPE == MOD_REDUCT_SOLINAS3 ? mod_reduct_solinas3_pkg::get_latency():
          REDUCT_TYPE == MOD_REDUCT_GOLDILOCKS ? mod_reduct_64bgoldilocks_karatsuba_pkg::get_latency():
          0; // ERROR : unknown REDUCT_TYPE
    return lat;
  endfunction
endpackage

