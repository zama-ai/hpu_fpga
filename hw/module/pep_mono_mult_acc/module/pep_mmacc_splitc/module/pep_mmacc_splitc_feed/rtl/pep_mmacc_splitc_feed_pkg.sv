// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Structures used in pep_mmacc_splitc_feed.
// ==============================================================================================

package pep_mmacc_splitc_feed_pkg;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;

//=================================================================================================
// localparam
//=================================================================================================
  localparam int SS          = STG_ITER_SZ / R_SZ;

//=================================================================================================
// type
//=================================================================================================
  // Feed request
  typedef struct packed {
    logic [GLWE_RAM_ADD_W-1:0] add_ofs;
    logic [GLWE_K_P1_W-1:0]    poly_id;
    logic [STG_ITER_W-1:0]     stg_iter;
    logic [LWE_COEF_W-1:0]     rot_factor;
    logic [BPBS_ID_W-1:0]      pbs_id;
    logic [LWE_K_W-1:0]        br_loop;
    logic                      batch_first_ct;
    logic                      batch_last_ct;
    map_elt_t                  map_elt;
  } req_cmd_t;

  localparam int REQ_CMD_W = $bits(req_cmd_t);

//=================================================================================================
// Function
//=================================================================================================
  function [N_W-1:0] rev_order_n(logic[N_W-1:0] v);
    logic [S-1:0][R_SZ-1:0] r_v;
    logic [S-1:0][R_SZ-1:0] v_a;

    v_a = v;

    for (int i=0; i<S; i=i+1)
      r_v[i] = v_a[S-1-i];
    return r_v;
  endfunction

  function [STG_ITER_W-1:0] rev_order_stgiter(logic[STG_ITER_W-1:0] v);
    logic [SS-1:0][R_SZ-1:0] r_v;
    logic [SS-1:0][R_SZ-1:0] v_a;

    v_a = v;

    for (int i=0; i<SS; i=i+1)
      r_v[i] = v_a[SS-1-i];
    return r_v;
  endfunction

  function [R_SZ+PSI_SZ-1:0] rev_order_rpsi(logic[R_SZ+PSI_SZ-1:0] v);
    logic [(PSI_SZ+R_SZ)/R_SZ-1:0][R_SZ-1:0] r_v;
    logic [(PSI_SZ+R_SZ)/R_SZ-1:0][R_SZ-1:0] v_a;

    v_a = v;

    for (int i=0; i<(PSI_SZ+R_SZ)/R_SZ; i=i+1)
      r_v[i] = v_a[(PSI_SZ+R_SZ)/R_SZ-1-i];
    return r_v;
  endfunction

  // From a position (natural order), and the rotation factor.
  // Extract the add = stg_iter where the rotated value belongs to.
  function [STG_ITER_W-1:0] get_rot_add (logic [N_W-1:0]        pos,
                                         logic [LWE_COEF_W-1:0] rot_factor);
    logic [N_W-1:0]                  pos_rev; // rev : reverse
    logic [LWE_COEF_W:0]             pos_rev_plus_rot; // LWE_COEF_W = $clog2(2*N) > N_W

    pos_rev          = rev_order_n(pos);
    pos_rev_plus_rot = pos_rev + rot_factor;
    // Back to natural index to retreive the address
    get_rot_add      = rev_order_stgiter(pos_rev_plus_rot[STG_ITER_W-1:0]);

  endfunction

endpackage
