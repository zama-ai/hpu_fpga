// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package containing common localparams used in key_switch.
// ==============================================================================================

package ksk_mgr_common_param_pkg;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import ksk_mgr_common_cut_definition_pkg::*;
  import ksk_mgr_common_slot_definition_pkg::*;

  export ksk_mgr_common_slot_definition_pkg::KSK_SLOT_NB;
  export ksk_mgr_common_cut_definition_pkg::KSK_CUT_NB;

  localparam int KSK_SLOT_DEPTH = KS_BLOCK_LINE_NB * KS_LG_NB;
  localparam int KSK_RAM_DEPTH  = KSK_SLOT_NB * KSK_SLOT_DEPTH;

  //=== localparam
  localparam int KSK_SLOT_W        = $clog2(KSK_SLOT_NB) == 0 ? 1 : $clog2(KSK_SLOT_NB);
  localparam int KSK_SLOT_ADD_W    = $clog2(KSK_SLOT_DEPTH);
  localparam int KSK_RAM_ADD_W     = $clog2(KSK_RAM_DEPTH);

  localparam int KSK_CUT_W            = $clog2(KSK_CUT_NB) == 0 ? 1 : $clog2(KSK_CUT_NB);
  localparam int KSK_CUT_FCOEF_NB     = (LBY+KSK_CUT_NB-1) / KSK_CUT_NB; // Front coef
  localparam int KSK_CUT_BCOL_COEF_NB = ((LBY*KS_BLOCK_LINE_NB*KS_LG_NB)+KSK_CUT_NB-1) / KSK_CUT_NB;

  //=== Typedef
  typedef struct packed {
  logic                     buf_in_avail;
  logic                     buf_shift;
  logic                     ram_rd_enD;
  logic [KSK_RAM_ADD_W-1:0] ram_rd_addD;
  } node_cmd_t;

  localparam int NODE_CMD_W = $bits(node_cmd_t);

endpackage
