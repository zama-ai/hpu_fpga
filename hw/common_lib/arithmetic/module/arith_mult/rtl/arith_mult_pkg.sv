// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// arith_mult package
// Contains functions related to arith_mult:
//   get_latency : output arith_mult latency value (does not take into account IN_PIPE)
// ==============================================================================================

package arith_mult_pkg;
  import common_definition_pkg::*;
  import arith_mult_core_pkg::*;
  import arith_mult_karatsuba_pkg::*;
  import arith_mult_karatsuba_cascade_pkg::*;
  import arith_mult_64bgoldilocks_karatsuba_pkg::*;
  import arith_mult_64bgoldilocks_karatsuba_cascade_pkg::*;

  localparam int INTL_PIPE = 1;

  // LATENCY of arith_mult.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency(input arith_mult_type_e MULT_TYPE);
    int lat;
    lat = MULT_TYPE == MULT_CORE      ? arith_mult_core_pkg::get_latency():
          MULT_TYPE == MULT_KARATSUBA ? arith_mult_karatsuba_pkg::get_latency():
          MULT_TYPE == MULT_KARATSUBA_CASCADE ? arith_mult_karatsuba_cascade_pkg::get_latency():
          MULT_TYPE == MULT_GOLDILOCKS    ? arith_mult_64bgoldilocks_karatsuba_pkg::get_latency() + INTL_PIPE:
          MULT_TYPE == MULT_GOLDILOCKS_CASCADE    ? arith_mult_64bgoldilocks_karatsuba_cascade_pkg::get_latency():
          0; // ERROR : unknown MULT_TYPE
    return lat;
  endfunction
endpackage
