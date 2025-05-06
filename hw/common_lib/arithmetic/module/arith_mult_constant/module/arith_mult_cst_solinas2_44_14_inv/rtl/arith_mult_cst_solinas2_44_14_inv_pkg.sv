// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// arith_mult_cst_solinas2_44_14 package
// Contains functions related to arith_mult_cst_solinas2_44_14:
//   get_latency : output arith_mult_cst_solinas2_44_14 latency value (does not take into account IN_PIPE)
// ==============================================================================================

package arith_mult_cst_solinas2_44_14_inv_pkg;
  // LATENCY of arith_mult_cst__solinas2_44_14_inv.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency();
    return 2; // 1 + output register
  endfunction
endpackage

