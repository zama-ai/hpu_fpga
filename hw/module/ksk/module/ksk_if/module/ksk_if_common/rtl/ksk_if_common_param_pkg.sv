// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Common localparams for ksk_if
// ==============================================================================================

package ksk_if_common_param_pkg;
  import param_tfhe_pkg::*;
  import pep_ks_common_param_pkg::*;
  import ksk_mgr_common_param_pkg::*;
  import axi_if_ksk_axi_pkg::*;

  //===============================
  // Parameters
  //===============================
  //----------------------
  // KSK RAM access
  //----------------------
  localparam int KSK_ACS_W                 = (LBZ * MOD_KSK_W) > 32 ? 64 : 32; // Read and write KSK coef width. Should be >= MOD_KSK_W
  localparam int KSK_COEF_PER_AXI4_WORD    = AXI4_DATA_W/KSK_ACS_W;

  //===============================
  // Type
  //===============================
  typedef struct packed {
    logic [KSK_SLOT_W-1:0]     slot_id;
    logic [KS_BLOCK_COL_W-1:0] ks_loop;
  } ksk_read_cmd_t;

  localparam int KSK_READ_CMD_W = $bits(ksk_read_cmd_t);
endpackage
