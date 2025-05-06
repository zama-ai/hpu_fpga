// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core with matrix multiplication (ntt_core_wmm) package.
// This package should be imported by every module of ntt_core_wmm.
// It contains commonly used constants and type.
// ==============================================================================================

package ntt_core_wmm_pkg;
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;

  //=== Architecture dependent localparams
  // For network which purpose is to reconstruct a single PBS for the next stage.
  // Used when the reading is done right away.
  localparam int CROSS_TOKEN_W = $clog2(PBS_L+1);
  // For network that needs to store a whole batch
  localparam int BATCH_TOKEN_W = ($clog2(BATCH_PBS_NB+1) == 0) ? 1 : $clog2(BATCH_PBS_NB+1);

endpackage

