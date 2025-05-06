// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Structures used in pep_mono_mult_acc.
// ==============================================================================================

package pep_mmacc_common_param_pkg;
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;

// ============================================================================================== //
// localparam
// ============================================================================================== //
  // CRAM depth
  localparam int CRAM_PBS_OFS = GLWE_K_P1 * STG_ITER_NB;
  localparam int CRAM_DEPTH   = CRAM_PBS_OFS * BATCH_PBS_NB * 2; // *2 for the ping-pong between parities
  localparam int CRAM_ADD_W   = $clog2(CRAM_DEPTH);
  localparam int CS_ADD_W     = $clog2(CRAM_PBS_OFS);

  // Feed, SXT permutation - used in split version
  localparam int PERM_LVL_NB   = R_SZ + PSI_SZ;
  // First stage is done alone.
  // The next is also done alone, if PERM_LVL_NB-1 is odd. Then the permutation levels are done by 2.
  // The last 2 levels are not done in feed_rot / sxt_rot
  localparam int PERM_STAGE_NB = ((PERM_LVL_NB-2)+1)/2 + (1 - PERM_LVL_NB%2);
  localparam int PERM_CYCLE_NB = PERM_STAGE_NB-1; // at t0 first stage, at t0 + PERM_CYCLE_NB execution of last stage.
  localparam int PERM_W        = 2**(PERM_LVL_NB-1);

  // GRAM arbiter
  localparam int GARB_SLOT_CYCLE  = 4;
  localparam int GLWE_FEED_CYCLE  = (STG_ITER_NB * (GLWE_K+1) * PBS_L);
  localparam int GLWE_ACC_CYCLE   = (STG_ITER_NB * (GLWE_K+1));
  localparam int GLWE_SLOT_NB     = (GLWE_FEED_CYCLE + GARB_SLOT_CYCLE-1) / GARB_SLOT_CYCLE;
  localparam int ACC_ADD_SLOT     = 1;
  localparam int FEED_ADD_SLOT    = 1;
  localparam int ACC_WR_START_DLY_SLOT_NB   = 2; // Support delay between [8,12]
  localparam int ACC_WR_END_DLY_SLOT_NB     = ACC_WR_START_DLY_SLOT_NB+ACC_ADD_SLOT;
  localparam int FEED_DAT_START_DLY_SLOT_NB = PERM_CYCLE_NB/GARB_SLOT_CYCLE;
  localparam int FEED_DAT_END_DLY_SLOT_NB   = FEED_DAT_START_DLY_SLOT_NB+FEED_ADD_SLOT;
  localparam int MAX_END_DLY_SLOT_NB = ACC_WR_END_DLY_SLOT_NB > FEED_DAT_END_DLY_SLOT_NB ? ACC_WR_END_DLY_SLOT_NB : FEED_DAT_END_DLY_SLOT_NB;

  localparam int GARB_SLOT_NB     = GLWE_SLOT_NB + MAX_END_DLY_SLOT_NB + 1; // +1 because of the 1 slot of arbitration

  localparam int GARB_SLOT_CYCLE_W = $clog2(GARB_SLOT_CYCLE) == 0 ? 1 : $clog2(GARB_SLOT_CYCLE);
  localparam int GARB_SLOT_W       = $clog2(GARB_SLOT_NB) == 0 ? 1 : $clog2(GARB_SLOT_NB);
  localparam int GARB_SLOT_WW      = $clog2(GARB_SLOT_NB+1) == 0 ? 1 : $clog2(GARB_SLOT_NB+1);

  // Acc error
  localparam int ACC_ERROR_W      = 3;
  localparam int ACC_CORE_ERROR_W = 2; // sub set of acc errors

  localparam int ERROR_ACC_GRAM_ACCESS_OFS = 0;
  localparam int ERROR_ACC_INFIFO_OVF_OFS  = 1;
  localparam int ERROR_ACC_DONE_OVF_OFS    = 2; // For split

// ============================================================================================== //
// typedef
// ============================================================================================== //
  typedef struct packed {
    logic                 br_loop_parity;
    logic [BPBS_ID_W-1:0] map_idx;
    logic                 batch_first_ct;
    logic                 batch_last_ct;
    map_elt_t             map_elt;
  } mmacc_intern_cmd_t;

  localparam int MMACC_INTERN_CMD_W = $bits(mmacc_intern_cmd_t);

  typedef struct packed {
    logic                      is_flush;
    logic [LWE_K_W-1:0]        br_loop;
    logic [BPBS_NB_W-1:0]      ct_nb_m1;
    logic [BPBS_ID_W-1:0]      pbs_id;
    logic [BPBS_ID_W-1:0]      map_idx;
    logic                      batch_first_ct;
    logic                      batch_last_ct;
    map_elt_t                  map_elt;
  } mmacc_feed_cmd_t;

  localparam int MMACC_FEED_CMD_W = $bits(mmacc_feed_cmd_t);

  typedef struct packed {
    logic                    critical;
    logic [GRAM_ID_W-1:0]    grid;
  } garb_cmd_t;

  localparam int GARB_CMD_W = $bits(garb_cmd_t);

// ============================================================================================== //
// function
// ============================================================================================== //
  function int set_msplit_sxt_splitc_coef (msplit_name_e s);
    case (s)
      MSPLIT_NAME_M2_S2: return 2*R*PSI/4; // Or any value below that divides R*PSI/2
      MSPLIT_NAME_M3_S1: return 1*R*PSI/4 > 16 ? 16 : 1*R*PSI/4; // Or any value below that divides R*PSI/4
      MSPLIT_NAME_M1_S3: return 1*R*PSI/4; // Or any value below that divides 2*R*PSI/4
    endcase
  endfunction
endpackage
