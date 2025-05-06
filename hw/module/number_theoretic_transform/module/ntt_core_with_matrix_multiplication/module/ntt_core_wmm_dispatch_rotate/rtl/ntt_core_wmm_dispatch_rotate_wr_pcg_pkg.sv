// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// ntt_core_wmm_dispatch_rotate_wr_pcg package
// Contains functions related to ntt_core_wmm_dispatch_rotate_wr_pcg:
//   get_latency : output ntt_core_wmm_dispatch_rotate_wr_pcg latency value
//   (does not take into account IN_PIPE)
// ==============================================================================================

package ntt_core_wmm_dispatch_rotate_wr_pcg_pkg;
  localparam int           LAT_MAX     = 3;
  localparam [LAT_MAX-1:0] LAT_PIPE_MH = {1'b1,  // S2_S3
                                          1'b1,  // S1_S2
                                          1'b1}; // S0_S1

  function int get_cmd_latency();
    return $countones(LAT_PIPE_MH[0]);
  endfunction

  function int get_latency();
    return $countones(LAT_PIPE_MH);
  endfunction
endpackage

