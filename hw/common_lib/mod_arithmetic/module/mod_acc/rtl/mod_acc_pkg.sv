// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// mod_acc package
// Contains functions related to mod_acc:
//   get_latency : output mod_acc latency value (does not take into account IN_PIPE nor OUT_PIPE)
// ==============================================================================================

package mod_acc_pkg;
  localparam int LATENCY = 1;
    // 3 cycles to output the result when the last data is received.
    // c1 : IN_PIPE : input reg : s0_avail
    // c2 : LATENCY : s0_out_avail
    // c3 : OUT_PIPE : s1_avail

  // LATENCY of mod_acc.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency();
    return LATENCY;
  endfunction
endpackage

