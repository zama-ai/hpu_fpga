// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package containing common localparams used in hpu.
// ==============================================================================================

package hpu_common_param_pkg;
  import hpu_part_definition_pkg::*;
  import hpu_twdfile_definition_pkg::*;
  import common_definition_pkg::*;
  import param_ntt_pkg::*;
  import regf_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pem_common_param_pkg::*;

  // Used when hpu is split into 3 parts.
  export hpu_part_definition_pkg::HEAD_S_NB;
  export hpu_part_definition_pkg::HEAD_USE_PP;
  export hpu_part_definition_pkg::MID0_S_NB;
  export hpu_part_definition_pkg::MID0_USE_PP;
  export hpu_part_definition_pkg::MID0_S_INIT;
  export hpu_part_definition_pkg::MID1_S_NB;
  export hpu_part_definition_pkg::MID1_USE_PP;
  export hpu_part_definition_pkg::MID1_S_INIT;
  export hpu_part_definition_pkg::MID2_S_NB;
  export hpu_part_definition_pkg::MID2_USE_PP;
  export hpu_part_definition_pkg::MID2_S_INIT;
  export hpu_part_definition_pkg::MID3_S_NB;
  export hpu_part_definition_pkg::MID3_USE_PP;
  export hpu_part_definition_pkg::MID3_S_INIT;

  export hpu_twdfile_definition_pkg::TWD_IFNL_FILE_PREFIX;
  export hpu_twdfile_definition_pkg::TWD_PHRU_FILE_PREFIX;
  export hpu_twdfile_definition_pkg::TWD_GF64_FILE_PREFIX;

  // TOREVIEW: Could be refined
  //== PE
  localparam int               PEA_OUT_FIFO_DEPTH  = 2;
  localparam int               PEA_ALU_NB          = 1;

  localparam int               PEA_REGF_PERIOD_TMP = REGF_COEF_NB / PEA_ALU_NB;
  localparam int               PEA_REGF_PERIOD     = PEA_REGF_PERIOD_TMP > 1 ? PEA_REGF_PERIOD_TMP : 2;
  localparam int               PEM_REGF_PERIOD_TMP1= REGF_SEQ / PEM_PC; // #cycles to received data from regfile
  localparam int               PEM_REGF_PERIOD_TMP2= (REGF_COEF_NB / PEM_PC) / BLWE_COEF_PER_AXI4_WORD; // #Cycles to send 1 regfile word to mem
  localparam int               PEM_REGF_PERIOD_TMP3= PEM_REGF_PERIOD_TMP1 > PEM_REGF_PERIOD_TMP2 ? PEM_REGF_PERIOD_TMP1 : PEM_REGF_PERIOD_TMP2;
  localparam int               PEM_REGF_PERIOD     = PEM_REGF_PERIOD_TMP3 > 1 ? PEM_REGF_PERIOD_TMP3 : 2; // leave 1 to PEP
  localparam int               PEP_REGF_PERIOD     = 1;

  localparam int               PEA_INST_FIFO_DEPTH = 8;
  localparam int               PEM_INST_FIFO_DEPTH = 8;
  localparam int               PEP_INST_FIFO_DEPTH = 8;

  //== Instruction scheduler
  // Currently not configurable from top
  // cf instruction_scheduler_pkg

  //== RAM latency
  localparam int               RAM_LATENCY          = 2;
  localparam int               ROM_LATENCY          = 2;
  localparam int               URAM_LATENCY         = RAM_LATENCY + 2;
  localparam int               PHYS_RAM_DEPTH       = 1024; // Physical RAM depth. Should be a power of 2. In Xilinx is BRAM depth for 32b words
  localparam int               DESYNC_DEPTH         = 2; // Maximum desynchronization introduced when crossing the SLR

  //== PBS
  // Operator type
  localparam mod_mult_type_e   MOD_MULT_TYPE       = set_mod_mult_type(MOD_NTT_TYPE, OPTIMIZATION_NAME_CLB);
  localparam mod_reduct_type_e REDUCT_TYPE         = set_mod_reduct_type(MOD_NTT_TYPE, OPTIMIZATION_NAME_CLB);
  localparam arith_mult_type_e MULT_TYPE           = MULT_CORE;
  localparam arith_mult_type_e PHI_MULT_TYPE       = set_ntt_mult_type(MOD_NTT_W,MOD_NTT_TYPE, OPTIMIZATION_NAME_CLB);
  localparam mod_mult_type_e   PP_MOD_MULT_TYPE    = set_mod_mult_type(MOD_NTT_TYPE, OPTIMIZATION_NAME_CLB);
  localparam arith_mult_type_e PP_MULT_TYPE        = set_ntt_mult_type(MOD_NTT_W,MOD_NTT_TYPE, OPTIMIZATION_NAME_CLB);
  localparam int               MODSW_2_PRECISION_W = MOD_NTT_W + 32;
  localparam arith_mult_type_e MODSW_2_MULT_TYPE   = set_mult_type(MODSW_2_PRECISION_W, OPTIMIZATION_NAME_CLB);
  localparam arith_mult_type_e MODSW_MULT_TYPE     = set_mult_type(MOD_NTT_W, OPTIMIZATION_NAME_CLB);
  // Regfile info
  localparam int               REGF_RD_LATENCY      = URAM_LATENCY + 4; // minimum latency to get the data
  localparam int               KS_IF_COEF_NB        = (LBY < REGF_COEF_NB) ? LBY : REGF_SEQ_COEF_NB;
  localparam int               KS_IF_SUBW_NB        = (LBY < REGF_COEF_NB) ? 1 : REGF_SEQ;

  //== Trace
  localparam int               TRC_DEPTH            = 1024; // Physical RAM depth to store the info
  localparam int               TRC_MEM_DEPTH        = 32;   // HBM depth in MByte unit

endpackage

