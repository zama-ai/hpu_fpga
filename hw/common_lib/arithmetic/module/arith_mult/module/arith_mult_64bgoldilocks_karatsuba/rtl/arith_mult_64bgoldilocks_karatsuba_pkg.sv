// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// arith_mult_64bgoldilocks_karatsuba package
// Contains functions related to arith_mult_64bgoldilocks_karatsuba:
//   get_latency : output arith_mult_64bgoldilocks_karatsuba latency value
//                 (does not take into account IN_PIPE & INTL_PIPE)
// ==============================================================================================

package arith_mult_64bgoldilocks_karatsuba_pkg;
  import arith_mult_karatsuba_pkg::*;

  localparam int INTERNAL_PIPE = 2;

  // LATENCY of arith_mult_64bgoldilocks_karatsuba_pkg.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency();
    return arith_mult_karatsuba_pkg::get_latency()  + INTERNAL_PIPE;
  endfunction
  
endpackage
