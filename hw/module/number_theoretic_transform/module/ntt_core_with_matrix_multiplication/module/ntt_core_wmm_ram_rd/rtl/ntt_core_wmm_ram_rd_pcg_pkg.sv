// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// ntt_core_wmm_ram_rd_pcg package
// Contains functions related to ntt_core_wmm_ram_rd:
//   get_latency : output ntt_core_wmm_ram_rd latency value
//   (does not take into account IN_PIPE)
// ==============================================================================================

package ntt_core_wmm_ram_rd_pcg_pkg;
  localparam int           LAT_MAX     = 1;
  localparam [LAT_MAX-1:0] LAT_PIPE_MH = {1'b1}; // reg on RAM read command
  // RAM read command latency
  function int get_ram_cmd_latency();
    return $countones(LAT_PIPE_MH);
  endfunction
  // RAM read latency
  function int get_ram_latency(int RAM_LATENCY);
    return get_ram_cmd_latency() + RAM_LATENCY;
  endfunction
  // Latency to get the data once the seq_rden is received.
  // +2 : corresponds to the internal pipe to process the seq_rden
  function int get_read_latency(int RAM_LATENCY);
    return get_ram_latency(RAM_LATENCY) + 2;
  endfunction

endpackage

