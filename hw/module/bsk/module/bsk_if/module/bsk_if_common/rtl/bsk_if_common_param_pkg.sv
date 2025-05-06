// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Common localparams for bsk_if
// ==============================================================================================

package bsk_if_common_param_pkg;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import bsk_mgr_common_param_pkg::*;
  import axi_if_bsk_axi_pkg::*;

  //===============================
  // Parameters
  //===============================
  //----------------------
  // BSK RAM access
  //----------------------
  localparam int BSK_ACS_W                 = MOD_NTT_W > 32 ? 64 : 32; // Read and write BSK coef width.
  localparam int BSK_COEF_PER_AXI4_WORD    = AXI4_DATA_W/BSK_ACS_W;

  //===============================
  // Type
  //===============================
  typedef struct packed {
    logic [BSK_SLOT_W-1:0] slot_id;
    logic [LWE_K_W-1:0]    br_loop;
  } bsk_read_cmd_t;

  localparam int BSK_READ_CMD_W = $bits(bsk_read_cmd_t);

  //===============================
  // Info for regif
  //===============================
  typedef struct packed {
    logic             req_assigned;
    logic             req_parity;
    logic [LWE_K_W:0] req_prf_br_loop;
    logic [LWE_K_W:0] req_br_loop_wp;
    logic [LWE_K_W:0] req_br_loop_rp;
  } bskif_info_t;

  localparam int BSKIF_INFO_W = $bits(bskif_info_t);


endpackage
