// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// CLBU+PP model : data description package
//
// ==============================================================================================

package tb_ntt_core_wmm_clbu_pp_model_pkg;
  import param_ntt_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;

  localparam int BATCH_NB_W = 16;

  typedef struct packed {
    logic [MOD_NTT_W-1:BATCH_NB_W+BPBS_ID_W+STG_ITER_W] val;
    logic [BATCH_NB_W-1:0]                        batch_id;
    logic [BPBS_ID_W-1:0]                          pbs_id;
    logic [STG_ITER_W-1:0]                        stg_iter;
  } clbu_pp_data_t;
endpackage

