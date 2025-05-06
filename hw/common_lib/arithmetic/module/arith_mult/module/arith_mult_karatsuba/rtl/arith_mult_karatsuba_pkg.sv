// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// arith_mult_karatsuba package
// Contains functions related to arith_mult_karatsuba:
//   get_latency : output arith_mult_karatsuba latency value (does not take into account IN_PIPE)
// ==============================================================================================

package arith_mult_karatsuba_pkg;
  import arith_mult_core_pkg::*;

  // LATENCY of arith_mult_karatsuba.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency();
    return arith_mult_core_pkg::get_latency() + 1 + 1;
  endfunction
endpackage
