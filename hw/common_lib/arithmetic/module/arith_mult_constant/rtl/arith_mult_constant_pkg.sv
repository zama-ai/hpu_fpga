// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// arith_mult_constant package
// Contains functions related to arith_mult_constant:
//   get_latency : output arith_mult_constant latency value (does not take into account IN_PIPE)
// ==============================================================================================

package arith_mult_constant_pkg;
  import common_definition_pkg::*;
  import arith_mult_cst_solinas3_pkg::*;
  import arith_mult_cst_solinas2_pkg::*;
  import arith_mult_cst_mersenne_pkg::*;
  import arith_mult_cst_goldilocks_inv_pkg::*;
  import arith_mult_cst_solinas2_44_14_inv_pkg::*;
  import arith_mult_pkg::*;

  // LATENCY of arith_mult_constant.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency(input int_type_e CST_TYPE, input arith_mult_type_e MULT_TYPE);
    int lat;
    lat = CST_TYPE == MERSENNE     ? arith_mult_cst_mersenne_pkg::get_latency():
          CST_TYPE == SOLINAS2     ? arith_mult_cst_solinas2_pkg::get_latency():
          CST_TYPE == SOLINAS3     ? arith_mult_cst_solinas3_pkg::get_latency():
          CST_TYPE == GOLDILOCKS_INV ? arith_mult_cst_goldilocks_inv_pkg::get_latency():
          CST_TYPE == SOLINAS2_44_14_INV ? arith_mult_cst_goldilocks_inv_pkg::get_latency():
          // not recognized constant type
          arith_mult_pkg::get_latency(MULT_TYPE);
    return lat;
  endfunction
endpackage
