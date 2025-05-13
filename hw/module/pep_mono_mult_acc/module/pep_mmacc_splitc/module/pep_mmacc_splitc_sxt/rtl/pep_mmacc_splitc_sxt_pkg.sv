// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Structures used in pep_mmacc_splitc_sxt.
// ==============================================================================================

package pep_mmacc_splitc_sxt_pkg;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import regf_common_param_pkg::*;

//=================================================================================================
// localparam
//=================================================================================================
  // Number of data to be sent to the regfile at once. In regfile word unit.
  localparam int DATA_THRESHOLD    = 8;
  localparam int DATA_THRESHOLD_WW = $clog2(DATA_THRESHOLD+1) == 0 ? 1 : $clog2(DATA_THRESHOLD+1);

  localparam int RD_COEF_NB       = R * PSI; /* for readability */
  localparam int RD_COEF_W        = $clog2(RD_COEF_NB);

  localparam bit DO_ACC           = RD_COEF_NB < REGF_COEF_NB; // Need to accumulate GRAM words to form regfile words
  localparam int GRAM_CHUNK_NB    = DO_ACC ? 1 : RD_COEF_NB / REGF_COEF_NB;
  localparam int CHUNK_GRAM_NB    = DO_ACC ? REGF_COEF_NB / RD_COEF_NB : 1;
  localparam int GRAM_CHUNK_NB_W  = $clog2(GRAM_CHUNK_NB) == 0 ? 1 : $clog2(GRAM_CHUNK_NB);
  localparam int CHUNK_GRAM_NB_W  = $clog2(CHUNK_GRAM_NB) == 0 ? 1 : $clog2(CHUNK_GRAM_NB);

  // We need to have a ping pong of 2*DATA_THRESHOLD regfile word unit.
  // This is done with 2 FIFO. One at the output of the read, and one at the output of the final module.
  // In read module, the unit is GRAM words, in the final module, the unit is regfile words.
  // Compute here these FIFO depths.
  localparam int DATA_THRESHOLD_GUNIT    = gunit_depth(DATA_THRESHOLD);
  localparam int DATA_THRESHOLD_GUNIT_WW = $clog2(DATA_THRESHOLD_GUNIT+1) == 0 ? 1 : $clog2(DATA_THRESHOLD_GUNIT+1);

//=================================================================================================
// type
//=================================================================================================
  typedef struct packed {
    logic [PID_W-1:0]            pid;
    logic [REGF_REGID_W-1:0]     dst_rid;
    logic [N_W-1:0]              id_0;
    logic [STG_ITER_W-1:0]       add_local;
    logic [LWE_COEF_W-1:0]       rot_factor;
    logic                        is_body;
    logic                        is_last;
  } cmd_ss2_t;

  localparam CMD_SS2_W = $bits(cmd_ss2_t);

  typedef struct packed {
    logic [PID_W-1:0]            pid;
    logic [REGF_REGID_W-1:0]     dst_rid;
    logic [N_W-1:0]              id_0;
    logic                        is_body;
    logic                        is_last;
  } cmd_x_t;

  localparam CMD_X_W = $bits(cmd_x_t);

// ============================================================================================= --
// function
// ============================================================================================= --
  // Reverse in base R, on S digits
  function [N_W-1:0] rev_order_n(logic[N_W-1:0] v);
    logic [S-1:0][R_SZ-1:0] r_v;
    logic [S-1:0][R_SZ-1:0] v_a;

    v_a = v;

    for (int i=0; i<S; i=i+1)
      r_v[i] = v_a[S-1-i];
    return r_v;
  endfunction

  function int gunit_depth(int d);
    // Additional locations to compensation the FIFO output pipe
    gunit_depth = DO_ACC ? d * CHUNK_GRAM_NB + CHUNK_GRAM_NB: (d + GRAM_CHUNK_NB-1)/ GRAM_CHUNK_NB + 1;
  endfunction



endpackage
