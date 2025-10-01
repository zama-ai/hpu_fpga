// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package containing common localparams for PE PBS
// ==============================================================================================

package pep_common_param_pkg;
  import pep_msplit_definition_pkg::*;
  import pep_batch_definition_pkg::*;

  import param_tfhe_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import bsk_if_common_param_pkg::*;

//==================================================
// Export
//==================================================
  export pep_msplit_definition_pkg::MSPLIT_TYPE;
  export pep_msplit_definition_pkg::MSPLIT_DIV;
  export pep_msplit_definition_pkg::MSPLIT_MAIN_FACTOR;
  export pep_msplit_definition_pkg::MSPLIT_SUBS_FACTOR;

  // Maximum number of PBS per batch
  export pep_batch_definition_pkg::BATCH_PBS_NB;
  // Total number of PBS location
  export pep_batch_definition_pkg::TOTAL_PBS_NB;
  // Number of batches processed in parallel
  export pep_batch_definition_pkg::BATCH_NB;
  // Total number of batches
  export pep_batch_definition_pkg::TOTAL_BATCH_NB;
  // Total number of GRAMs
  export pep_batch_definition_pkg::GRAM_NB;

//==================================================
// Parameters
//==================================================
  localparam int GRAM_ID_W         = $clog2(GRAM_NB) == 0 ? 1 : $clog2(GRAM_NB);

  localparam int RANK_NB           = BATCH_PBS_NB / GRAM_NB;
  localparam int RANK_W            = $clog2(RANK_NB) == 0 ? 1 : $clog2(RANK_NB);
  localparam int PID_GRP_NB        = TOTAL_PBS_NB / GRAM_NB;
  localparam int PID_GRP_W         = $clog2(PID_GRP_NB) == 0 ? 1 : $clog2(PID_GRP_NB);
  localparam int GRAM_NB_W         = $clog2(GRAM_NB) == 0 ? 1 : $clog2(GRAM_NB);
  localparam int GRAM_NB_SZ        = $clog2(GRAM_NB);

  localparam int TIMEOUT_CNT_W     = 32; // Correspond to AXI reg size.

  // GRAM
  localparam int GLWE_RAM_DEPTH  = TOTAL_PBS_NB/GRAM_NB * STG_ITER_NB * GLWE_K_P1; // Should only take this value.
  localparam int GLWE_RAM_ADD_W  = $clog2(GLWE_RAM_DEPTH);

  // pep_load_glwe
  localparam int GLWE_ACS_W               = MOD_Q_W > 32 ? 64 : 32; // Read and write GLWE coef width. Should be >= MOD_Q_W
  localparam int GLWE_COEF_PER_AXI4_WORD  = AXI4_DATA_W/GLWE_ACS_W;
  localparam int GLWE_SPLITC_COEF         = GLWE_COEF_PER_AXI4_WORD < (R*PSI/4) ? GLWE_COEF_PER_AXI4_WORD : (R*PSI/4);

  // mmacc <-> decomp
  // Number of chunks sent per stg_iteration to the decomp. Only CHUNK_NB = PBS_L is supported for now
  localparam int CHUNK_NB            = PBS_L;
  localparam int ACC_DECOMP_COEF_NB  = (PSI*R + CHUNK_NB-1)/CHUNK_NB;
  localparam int CHUNK_NB_W          = $clog2(CHUNK_NB) == 0 ? 1 : $clog2(CHUNK_NB);

  // mmacc split
  localparam int LSB_W      = MOD_Q_W / 2;
  localparam int MSB_W      = MOD_Q_W - LSB_W;

  //== Batch
  localparam int BATCH_NB_W       = ($clog2(BATCH_NB) == 0) ? 1 : $clog2(BATCH_NB);
  localparam int BATCH_NB_WW      = ($clog2(BATCH_NB+1) == 0) ? 1 : $clog2(BATCH_NB+1);
  localparam int TOTAL_BATCH_NB_W = $clog2(TOTAL_BATCH_NB)== 0 ? 1 : $clog2(TOTAL_BATCH_NB);
  // Counter from 0 to BATCH_PBS_NB-1
  localparam int BPBS_ID_W        = ($clog2(BATCH_PBS_NB) == 0) ? 1 : $clog2(BATCH_PBS_NB);
  localparam int BPBS_NB_W        = ($clog2(BATCH_PBS_NB) == 0) ? 1 : $clog2(BATCH_PBS_NB);
  // Counter from 0 to BATCH_PBS_NB included
  localparam int BPBS_NB_WW       = ($clog2(BATCH_PBS_NB+1) == 0) ? 1 : $clog2(BATCH_PBS_NB+1);

  // Counter from 0 to TOTAL_PBS_NB-1
  localparam int PID_W            = ($clog2(TOTAL_PBS_NB) == 0) ? 1 : $clog2(TOTAL_PBS_NB);
  localparam int PID_WW           = ($clog2(TOTAL_PBS_NB+1) == 0) ? 1 : $clog2(TOTAL_PBS_NB+1);

  // Batch command buffer depth
  // To set the same buffer size for every modules that need to store the batch cmd.
  // Necessary to avoid discrepancy between modules (particularly between producer
  // and consumer)
  localparam int BATCH_CMD_BUFFER_DEPTH = TOTAL_BATCH_NB < 4 ? 4 : TOTAL_BATCH_NB;

  // ------------------------------------------------------------------------------------------- --
  // Mean compensation configuration
  // ------------------------------------------------------------------------------------------- --
  // Mean correction related
  localparam logic [127:0] KS_MAX_ABS_ERROR = (2**(MOD_KSK_W - LWE_COEF_W - 1) * LWE_K);
  localparam int unsigned KS_MAX_ERROR_W    = unsigned'($clog2(KS_MAX_ABS_ERROR+1) + 1); // The mod_switch_error is signed
  localparam int KS_CORR_W = MOD_KSK_W - LWE_COEF_W + 2; // 1 additional bit + 1 sign bit (2s complement)

  // The KS key mean is encoded in fixed point. The final encoded value is:
  //  KS_KEY_MEAN * 2**-KS_KEY_MEAN_F
  localparam real         KS_KEY_MEAN_R = 0.5;
  localparam int unsigned KS_KEY_MEAN_W = 1;
  localparam int unsigned KS_KEY_MEAN_F = 1; // Fixed point location index
  localparam int unsigned KS_KEY_MEAN   = KS_KEY_MEAN_R * (1 << KS_KEY_MEAN_F);
  // Note: An implicit conversion from a floating point value to an integer is implicitly
  // rounded as stated in the system verilog standard.
  // "Implicit conversion shall take place when a real number is assigned to an integer. The ties
  // shall be rounded away from zero."
//==================================================
// Structure
//==================================================
  typedef struct packed {
    logic [BPBS_NB_WW-1:0] pbs_nb; // Number of PBS in the batch
    logic [LWE_K_W-1:0]   br_loop;
  } br_batch_cmd_t;

  localparam int BR_BATCH_CMD_W = $bits(br_batch_cmd_t);

  typedef struct packed {
    logic [PID_W-1:0]     pid;
    logic [PID_GRP_W-1:0] grof;
    logic [GRAM_ID_W-1:0] grid;
  } pid_t;

  typedef struct packed {
    logic [GID_W-1:0]     gid;
    pid_t                 pid;
  } load_glwe_cmd_t;

  localparam int LOAD_GLWE_CMD_W = $bits(load_glwe_cmd_t);

  typedef struct packed {
    logic [RID_W-1:0] src_rid;
    logic [PID_W-1:0] pid;
  } load_blwe_cmd_t;

  localparam int LOAD_BLWE_CMD_W = $bits(load_blwe_cmd_t);

  typedef struct packed {
    logic             c;
    logic [PID_W-1:0] pt;
  } pointer_t;

  typedef struct packed {
    logic                  ks_loop_c;
    logic [LWE_K_P1_W-1:0] ks_loop;
    pointer_t              wp;
    pointer_t              rp;
  } ks_cmd_t;

  localparam int KS_CMD_W = $bits(ks_cmd_t);

  typedef struct packed {
    logic [BATCH_PBS_NB-1:0][KS_CORR_W-1:0]  corr_a;
    logic [BATCH_PBS_NB-1:0][LWE_COEF_W-1:0] lwe_a;
    logic [LWE_K_P1_W-1:0]                   ks_loop;
    pointer_t                                wp;
    pointer_t                                rp;
  } ks_result_t;

  localparam int KS_RESULT_W = $bits(ks_result_t);

  typedef struct packed {
    logic                    avail;
    logic                    first;
    logic                    last;
    logic                    br_loop_parity; // First br_loop_c
    logic [LOG_LUT_NB_W-1:0] log_lut_nb;
    logic [RID_W-1:0]        dst_rid;
    logic [LWE_COEF_W-1:0]   lwe;
    pid_t                    pid;
  } map_elt_t;

  localparam int MAP_ELT_W = $bits(map_elt_t);

  typedef struct packed {
    logic                                is_flush;
    logic [LWE_K_W-1:0]                  br_loop;
    logic [BPBS_NB_W-1:0]                ct_nb_m1;
    map_elt_t [RANK_NB-1:0][GRAM_NB-1:0] map;
  } pbs_cmd_t;

  localparam int PBS_CMD_W = $bits(pbs_cmd_t);

//==================================================
// Functions
//==================================================
  function logic [PID_WW-1:0] pt_elt_nb (input [PID_W:0] wp, input [PID_W:0] rp);
    logic [PID_WW-1:0] tmp;
    tmp = {1'b0,wp[PID_W-1:0]} - {1'b0, rp[PID_W-1:0]};
    pt_elt_nb = (rp[PID_W] ^ wp[PID_W]) == 1'b1 ? tmp + TOTAL_PBS_NB : tmp;
  endfunction

//==================================================
// Error
//==================================================
  //== MMACC errors
  typedef struct packed {
    logic acc_ififo_ovf;    // infifo from NTT overflow
    logic acc_gram_wr_acs;  // acc write access to GRAM
  } pep_mmacc_acc_error_t;

  typedef struct packed {
    pep_mmacc_acc_error_t acc;
    logic feed_ofifo_ovf;   // Feed ofifo overflow
    logic sfifo_ovf;        // Acc done sfifo overflow
    logic flush_ovf;        // flush overflow
    logic gram_acs;         // GRAM access
  } pep_mmacc_error_t;

  localparam int PEP_MMACC_ERROR_W = $bits(pep_mmacc_error_t);

  //== BSK errors
  typedef struct packed {
    logic cmd_ovf;         // Input FIFO command overflow
  } pep_bsk_error_t;

  localparam int PEP_BSK_ERROR_W   = $bits(pep_bsk_error_t);

  //== KSK errors
  typedef struct packed {
    logic cmd_ovf;         // Input FIFO command overflow
  } pep_ksk_error_t;

  localparam int PEP_KSK_ERROR_W   = $bits(pep_ksk_error_t);

  //== SEQ errors
  typedef struct packed {
    logic ks_enq_ovf;     // KS enquiry buffer overflow
    logic pbs_enq_ovf;    // PBS enquiry buffer overflow
  } pep_seq_error_t;

  localparam int PEP_SEQ_ERROR_W   = $bits(pep_seq_error_t);

  //== KS errors
  typedef struct packed {
    logic ksk_udf;         // KSK not avail when needed
  } pep_ks_error_t;

  localparam int PEP_KS_ERROR_W   = $bits(pep_ks_error_t);

  //== NTT errors
  typedef struct packed {
    logic       in_ovf;      // Overflow at the input of the NTT
    logic [1:0] twd_phru;    // TODO : description
    logic [1:0] ntt;         // TODO : description
  } pep_ntt_error_t;

  localparam int PEP_NTT_ERROR_W   = $bits(pep_ntt_error_t);

  //== LDG errors
  typedef struct packed {
    logic done_ovf;         // Done FIFO overflow
  } pep_ldg_error_t;

  localparam int PEP_LDG_ERROR_W   = $bits(pep_seq_error_t);

  typedef struct packed {
    pep_ldg_error_t   ldg;
    pep_ntt_error_t   ntt;
    pep_seq_error_t   seq;
    pep_mmacc_error_t mmacc;
    pep_ks_error_t    ks;
    pep_ksk_error_t   ksk_mgr;
    pep_bsk_error_t   bsk_mgr;
  } pep_error_t;

  localparam int PEP_ERROR_W = $bits(pep_error_t);

//==================================================
// Info
//==================================================
  //== info
  typedef struct packed {
    logic [LWE_K_W-1:0]    ipip_flush_last_pbs_in_loop;
    logic                  br_loop_c;
    logic [LWE_K_W-1:0]    br_loop  ;
    logic                  ks_loop_c;
    logic [LWE_K_P1_W-1:0] ks_loop  ;
    pointer_t              pool_rp  ;
    pointer_t              pool_wp  ;
    pointer_t              ldg_pt   ;
    pointer_t              ldb_pt   ;
    pointer_t              ks_in_rp ;
    pointer_t              ks_in_wp ;
    pointer_t              ks_out_rp;
    pointer_t              ks_out_wp;
    pointer_t              pbs_in_rp;
    pointer_t              pbs_in_wp;
  } pep_seq_info_t;

  localparam int PEP_SEQ_INFO_W = $bits(pep_seq_info_t);

  typedef struct packed {
    bskif_info_t bskif;
    pep_seq_info_t seq;
  } pep_info_t;

  localparam int PEP_INFO_W = $bits(pep_info_t);

  //== Counters
  typedef struct packed {
    logic ack_inc;
    logic inst_inc;
  } pep_common_counter_inc_t;

  localparam int PEP_COMMON_COUNTER_INC_W = $bits(pep_common_counter_inc_t);

  typedef struct packed {
    logic                    ipip_flush_inc;
    logic                    bpip_waiting_batch_inc;
    logic [BATCH_PBS_NB-1:0] bpip_batch_filling_inc;
    logic                    bpip_batch_flush_inc;
    logic                    bpip_batch_timeout_inc;
    logic                    bpip_batch_inc;
    logic                    load_ack_inc;
    logic                    cmux_not_full_batch_inc;
  } pep_seq_counter_inc_t;

  localparam int SEQ_COUNTER_INC_W = $bits(pep_seq_counter_inc_t);

  typedef struct packed {
    logic                  req_dur;
    logic [MSPLIT_DIV-1:0] rcp_dur;
  } pep_ldg_counter_inc_t;

  typedef struct packed {
    logic                  rcp_dur;
  } pep_ldb_counter_inc_t;

  typedef struct packed {
    pep_ldg_counter_inc_t ldg;
    pep_ldb_counter_inc_t ldb;
  } pep_ld_counter_inc_t;

  localparam int LD_COUNTER_INC_W = $bits(pep_ld_counter_inc_t);

  typedef struct packed {
    logic [KSK_PC_MAX-1:0] load_ksk_dur;
    logic [BSK_PC_MAX-1:0] load_bsk_dur;
  } pep_key_counter_inc_t;

  localparam int KEY_COUNTER_INC_W = $bits(pep_key_counter_inc_t);

  typedef struct packed {
    logic sxt_req_dur;
    logic sxt_rcp_dur;
    logic sxt_cmd_wait_b_dur;
  } pep_mmacc_counter_inc_t;

  localparam int MMACC_COUNTER_INC_W = $bits(pep_mmacc_counter_inc_t);

  typedef struct packed {
    pep_common_counter_inc_t common;
    pep_seq_counter_inc_t    seq;
    pep_ld_counter_inc_t     ld;
    pep_key_counter_inc_t    key;
    pep_mmacc_counter_inc_t  mmacc;
  } pep_counter_inc_t;

  localparam int PEP_COUNTER_INC_W = $bits(pep_counter_inc_t);

endpackage
