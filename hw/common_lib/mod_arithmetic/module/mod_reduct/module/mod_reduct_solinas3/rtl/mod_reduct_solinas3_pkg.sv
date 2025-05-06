// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// mod_reduct_solinas3 package
// Contains functions related to mod_reduct_solinas3:
//   get_latency : output mod_reduct_solinas3 latency value (does not take into account IN_PIPE)
// ==============================================================================================

package mod_reduct_solinas3_pkg;

  localparam int           LAT_MAX     = 4;
  localparam [LAT_MAX-1:0] LAT_PIPE_MH = {1'b1, // Output pipe
                                          1'b1,
                                          1'b0, // Set to 1 if frequency is higher than 300MHz
                                          1'b1};

  // LATENCY of mod_reduct_solinas3.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency();
    return $countones(LAT_PIPE_MH);
  endfunction
endpackage


