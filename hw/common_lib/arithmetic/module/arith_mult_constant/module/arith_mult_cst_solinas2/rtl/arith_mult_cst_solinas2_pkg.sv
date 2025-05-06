// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// arith_mult_cst_solinas2 package
// Contains functions related to arith_mult_cst_solinas2:
//   get_latency : output arith_mult_cst_solinas2 latency value (does not take into account IN_PIPE)
// ==============================================================================================

package arith_mult_cst_solinas2_pkg;
  // LATENCY of mod_reduct_solinas2.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency();
    return 1; // output register
  endfunction
endpackage

