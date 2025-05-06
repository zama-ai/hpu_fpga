// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// mod_add_sub package
// Contains functions related to mod_add and mod_sub:
//   get_latency : output mod_add and mod_sub latency value (does not take into account IN_PIPE
//   nor OUT_PIPE)
// ==============================================================================================

package mod_add_sub_pkg;

  // LATENCY of mod_add and mod_sub.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency();
    return 0; // No internal pipe
  endfunction
endpackage
