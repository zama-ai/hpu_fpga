// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// arith_mult_core package
// Contains functions related to arith_mult_core:
//   get_latency : output arith_mult_core latency value (does not take into account IN_PIPE)
// ==============================================================================================

package arith_mult_core_pkg;

  localparam int LATENCY  = 6; // Should be >= 1
                              // Number of cycles used for the multiplication.
                              // These cycles will be used by the synthesizer for infering the
                              // best implementation of this operation.
                              // Default value 5 chosen, for Xilinx DSP @ 400MHz, DSP48E2
                              // to support multiplication with operands >= 32b.
                              // Note that 4 should be enough, but 5 gives better timing results
                              // for the top design synthesis.

  // NOTE : This function should be updated according to the default value of the localparam
  // LATENCY of arith_mult_core.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency();
    return LATENCY;
  endfunction
endpackage
