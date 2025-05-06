// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// arith_mult_cst_goldilocks package
// Contains functions related to arith_mult_cst_goldilocks:
//   get_latency : output arith_mult_cst_goldilocks latency value (does not take into account IN_PIPE)
// ==============================================================================================

package arith_mult_cst_goldilocks_inv_pkg;
  // LATENCY of arith_mult_cst__goldilocks_inv.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency();
    return 1; // output register
  endfunction
endpackage

