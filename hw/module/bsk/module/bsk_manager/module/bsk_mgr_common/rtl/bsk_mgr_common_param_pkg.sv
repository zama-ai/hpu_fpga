// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package containing common localparams used in key_switch.
// ==============================================================================================

package bsk_mgr_common_param_pkg;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_mgr_common_cut_definition_pkg::*;
  import bsk_mgr_common_slot_definition_pkg::*;

  export bsk_mgr_common_slot_definition_pkg::BSK_SLOT_NB;
  export bsk_mgr_common_cut_definition_pkg::BSK_CUT_NB;

  localparam int BSK_SLOT_DEPTH = INTL_L * STG_ITER_NB;
  localparam int BSK_RAM_DEPTH  = BSK_SLOT_NB * BSK_SLOT_DEPTH;

  //=== localparam
  localparam int BSK_SLOT_W        = $clog2(BSK_SLOT_NB) == 0 ? 1 : $clog2(BSK_SLOT_NB);
  localparam int BSK_SLOT_ADD_W    = $clog2(BSK_SLOT_DEPTH);
  localparam int BSK_RAM_ADD_W     = $clog2(BSK_RAM_DEPTH);

  localparam int BSK_CUT_W            = $clog2(BSK_CUT_NB) == 0 ? 1 : $clog2(BSK_CUT_NB);
  localparam int BSK_CUT_FCOEF_NB     = ((R*PSI)+BSK_CUT_NB-1) / BSK_CUT_NB; // Front coef
  localparam int BSK_CUT_GCOL_COEF_NB = ((N*GLWE_K_P1*PBS_L)+BSK_CUT_NB-1) / BSK_CUT_NB;

  //=== Typedef
  typedef struct packed {
  logic                     buf_in_avail;
  logic                     ram_rd_enD;
  logic [BSK_RAM_ADD_W-1:0] ram_rd_addD;
  } node_cmd_t;

  localparam int NODE_CMD_W = $bits(node_cmd_t);

endpackage
