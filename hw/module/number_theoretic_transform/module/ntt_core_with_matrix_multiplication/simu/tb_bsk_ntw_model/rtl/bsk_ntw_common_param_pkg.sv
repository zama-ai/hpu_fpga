// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// bsk_network package
// Contains localparams and localparam needed for the bsk network.
// ==============================================================================================

package bsk_ntw_common_param_pkg;

  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_ntw_common_definition_pkg::*;

  export bsk_ntw_common_definition_pkg::BSK_DIST_COEF_NB;

  /* Number of BSK coefficients to sent per batch */
  localparam int BSK_BATCH_COEF_NB    = N*GLWE_K_P1*INTL_L;
  /* Number of BSK coefficients to sent per iteration */
  localparam int BSK_ITER_COEF_NB     = PSI*R*GLWE_K_P1;
  /* Counters for the coefficient distribution unit and group*/
  localparam int BSK_UNIT_NB          = BSK_ITER_COEF_NB / BSK_DIST_COEF_NB;
  localparam int BSK_GROUP_NB         = STG_ITER_NB * INTL_L;
  /* Number of iterations for the distribution of a batch BSk coefficients */
  localparam int BSK_DIST_ITER_NB     = BSK_BATCH_COEF_NB / BSK_DIST_COEF_NB;

  localparam int SRV_CMD_FIFO_DEPTH   = 4; // Just enough to hide the command distribution latency
  localparam int SRV_ERROR_NB         = 1;
  localparam int CLT_ERROR_NB         = 2;

  /*=== Counters size */
  localparam int BSK_UNIT_W           = $clog2(BSK_UNIT_NB) == 0 ? 1 : $clog2(BSK_UNIT_NB);
  localparam int BSK_GROUP_W          = $clog2(BSK_GROUP_NB) == 0 ? 1 : $clog2(BSK_GROUP_NB);
  localparam int BSK_DIST_ITER_W      = $clog2(BSK_DIST_ITER_NB) == 0 ? 1 : $clog2(BSK_DIST_ITER_NB);

endpackage
