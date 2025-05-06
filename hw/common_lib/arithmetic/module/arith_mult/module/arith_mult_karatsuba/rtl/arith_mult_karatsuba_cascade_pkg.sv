// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// arith_mult_karatsuba_cascade package
// Contains functions related to arith_mult_karatsuba_cascade:
//   get_latency : output arith_mult_karatsuba_cascade latency value
// ==============================================================================================

package arith_mult_karatsuba_cascade_pkg;
import arith_mult_core_pkg::*;

// LATENCY of arith_mult_karatsuba_cascade.
// This function enables parent module to have access to the default LATENCY value.
function int get_latency();
  return 6;
endfunction
endpackage
