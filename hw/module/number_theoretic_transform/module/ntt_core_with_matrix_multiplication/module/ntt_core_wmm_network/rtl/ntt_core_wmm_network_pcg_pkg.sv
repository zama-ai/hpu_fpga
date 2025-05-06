// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// ntt_core_wmm_network package
// Contains functions related to ntt_core_wmm_network:
//   get_latency : output ntt_core_wmm_network latency value
//   (does not take into account IN_PIPE)
// ==============================================================================================

package ntt_core_wmm_network_pcg_pkg;
  import ntt_core_wmm_ram_rd_pcg_pkg::*;
  import ntt_core_wmm_dispatch_rotate_rd_pcg_pkg::*;

  localparam bit DRW_OUT_PIPE = 1;
  localparam bit DRR_IN_PIPE  = 1;

  // Latency to the data out of the network, once the seq_rden is received.
  function int get_read_latency(int RAM_LATENCY);
    return ntt_core_wmm_ram_rd_pcg_pkg::get_read_latency(RAM_LATENCY)
         + ntt_core_wmm_dispatch_rotate_rd_pcg_pkg::get_latency()
         + DRR_IN_PIPE;
  endfunction

endpackage


