// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Parameters that define the hpu partition.
//
// ==============================================================================================

package hpu_part_definition_pkg;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;

  //== If split in 3 parts
  // 1in3 outward
  localparam int HEAD_S_NB    = 0;
  localparam int HEAD_USE_PP  = 0;

  // 2in3 outward
  localparam int MID0_S_NB    = DELTA+1;
  localparam int MID0_USE_PP  = 0;
  localparam int MID0_S_INIT  = S-1;

  // 3in3
  localparam int MID1_S_NB    = 2*S-2*(DELTA+1);
  localparam int MID1_USE_PP  = 1;
  localparam int MID1_S_INIT  = S-1 - (DELTA+1);

  // 2in3 return
  localparam int MID2_S_NB    = DELTA+1;
  localparam int MID2_USE_PP  = 0;
  localparam int MID2_S_INIT  = 2*S-1 - DELTA;

  // 1in3 return
  localparam int MID3_S_NB    = 0;
  localparam int MID3_USE_PP  = 0;
  localparam int MID3_S_INIT  = S;

endpackage
