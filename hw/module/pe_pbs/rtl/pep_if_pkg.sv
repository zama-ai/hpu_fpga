// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Structures used to define pe_pbs interfaces.
// ==============================================================================================

package pep_if_pkg;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import regf_common_param_pkg::*;

  // ============================================================================================ //
  // Structures
  // ============================================================================================ //
  //== garb arbitration
  typedef struct packed {
    logic [GRAM_NB-1:0] feed_rot;
    logic [GRAM_NB-1:0] feed_dat;
    logic [GRAM_NB-1:0] acc_rd;
    logic [GRAM_NB-1:0] acc_wr;
    logic [GRAM_NB-1:0] sxt;
    logic [GRAM_NB-1:0] ldg;
  } garb_avail_1h_t;

  localparam int GARB_AVAIL_1H_W = $bits(garb_avail_1h_t);

  // mmacc_feed in internal data
  typedef struct packed {
    logic [MOD_Q_W-1:0] data;
    logic [MOD_Q_W-1:0] rot_data;
  } mainsubs_feed_elt_t;

  localparam int MAINSUBS_FEED_DATA_ELT_W = $bits(mainsubs_feed_elt_t);

  // ============================================================================================ //
  // Define structures for main <-> subs interface
  // ============================================================================================ //
  // -------------------------------------------------------------------------------------------- //
  // MMACC feed
  // -------------------------------------------------------------------------------------------- //
  typedef struct packed {
    logic [MMACC_FEED_CMD_W-1:0] mcmd;
  } mainsubs_feed_cmd_t;

  localparam int MAINSUBS_FEED_CMD_W = $bits(mainsubs_feed_cmd_t);

  typedef struct packed {
    mainsubs_feed_elt_t [PSI/2-1:0][R-1:0] elt;
  } mainsubs_feed_data_t;

  localparam int MAINSUBS_FEED_DATA_W = $bits(mainsubs_feed_data_t);

  typedef struct packed {
    mainsubs_feed_elt_t [PSI/MSPLIT_DIV-1:0][R-1:0] elt;
  } mainsubs_feed_part_t;

  localparam int MAINSUBS_FEED_PART_W = $bits(mainsubs_feed_part_t);

  // -------------------------------------------------------------------------------------------- //
  // MMACC sxt
  // -------------------------------------------------------------------------------------------- //
  typedef struct packed {
    logic [LWE_COEF_W-1:0]         body;
    logic [MMACC_INTERN_CMD_W-1:0] icmd;
  } mainsubs_sxt_cmd_t;

  localparam int MAINSUBS_SXT_CMD_W = $bits(mainsubs_sxt_cmd_t);

  localparam SXT_SPLITC_COEF = set_msplit_sxt_splitc_coef(MSPLIT_TYPE);
  typedef struct packed {
    logic [SXT_SPLITC_COEF-1:0][MOD_Q_W-1:0] data;
  } subsmain_sxt_data_t;

  localparam int SUBSMAIN_SXT_DATA_W = $bits(subsmain_sxt_data_t);

  typedef struct packed {
    logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0] data;
  } subsmain_sxt_part_t;

  localparam int SUBSMAIN_SXT_PART_W = $bits(subsmain_sxt_part_t);

  // -------------------------------------------------------------------------------------------- //
  // MMACC acc
  // -------------------------------------------------------------------------------------------- //
  localparam MAIN_PSI = PSI * MSPLIT_MAIN_FACTOR / MSPLIT_DIV;
  typedef struct packed {
    logic [MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0] data;
    logic                                    sob;
    logic                                    eob;
    logic                                    sol;
    logic                                    eol;
    logic                                    sog;
    logic                                    eog;
    logic [BPBS_ID_W-1:0]                    pbs_id;
  } subsmain_acc_data_t;

  localparam int SUBSMAIN_ACC_DATA_W = $bits(subsmain_acc_data_t);

  // -------------------------------------------------------------------------------------------- //
  // ldg
  // -------------------------------------------------------------------------------------------- //
  typedef struct packed {
    logic [LOAD_GLWE_CMD_W-1:0] cmd;
  } mainsubs_ldg_cmd_t;

  localparam int MAINSUBS_LDG_CMD_W = $bits(mainsubs_ldg_cmd_t);

  typedef struct packed {
    logic [GLWE_SPLITC_COEF-1:0][MOD_Q_W-1:0] data;
  } mainsubs_ldg_data_t;

  localparam int MAINSUBS_LDG_DATA_W = $bits(mainsubs_ldg_data_t);

  // -------------------------------------------------------------------------------------------- //
  // MMACC side
  // -------------------------------------------------------------------------------------------- //
  //== side
  typedef struct packed {
    logic                          ldg_cmd_done;
    logic                          sxt_cmd_ack;
    logic                          feed_mcmd_ack;
  } subsmain_proc_t;

  localparam int SUBSMAIN_PROC_W = $bits(subsmain_proc_t);

  typedef struct packed {
    subsmain_proc_t              proc;
  } subsmain_side_t;

  localparam int SUBSMAIN_SIDE_W = $bits(subsmain_side_t);

  typedef struct packed {
    garb_avail_1h_t              garb_avail_1h;
    logic                        feed_mcmd_ack_ack;
  } mainsubs_proc_t;

  localparam int MAINSUBS_PROC_W = $bits(mainsubs_proc_t);

  typedef struct packed {
    mainsubs_proc_t              proc;
  } mainsubs_side_t;

  localparam int MAINSUBS_SIDE_W = $bits(mainsubs_side_t);

  // ============================================================================================ //
  // Define structures for entry <-> bsk
  // ============================================================================================ //
  // bsk
  typedef struct packed {
    logic [TOTAL_BATCH_NB-1:0] inc_rd_ptr;
    logic [TOTAL_BATCH_NB-1:0] batch_start_1h;
  } entrybsk_proc_t;

  localparam int ENTRYBSK_PROC_W = $bits(entrybsk_proc_t);

  typedef struct packed {
    logic [TOTAL_BATCH_NB-1:0]  inc_wr_ptr;
  } bskentry_proc_t;

  localparam int BSKENTRY_PROC_W = $bits(bskentry_proc_t);

  // ============================================================================================ //
  // Define structures for NTT data path
  // ============================================================================================ //
  // Data path
  typedef struct packed {
    logic [PSI-1:0][R-1:0][NTT_OP_W-1:0]data;
    logic                               sob;
    logic                               eob;
    logic                               sol;
    logic                               eol;
    logic                               sos;
    logic                               eos;
    logic [BPBS_ID_W-1:0]               pbs_id;
  } ntt_proc_data_t;

  localparam int NTT_PROC_DATA_W = $bits(ntt_proc_data_t);

  // ============================================================================================ //
  // Define structures for NTT cmd path
  // ============================================================================================ //
  typedef struct packed {
    br_batch_cmd_t batch_cmd;
  } ntt_proc_cmd_t;

  localparam int NTT_PROC_CMD_W = $bits(ntt_proc_cmd_t);

  // ============================================================================================ //
  // pep <-> rif
  // ============================================================================================ //
  typedef struct packed {
    pep_error_t         error;
    pep_info_t          rif_info;
    pep_counter_inc_t   rif_counter_inc;
  } pep_rif_elt_t;

  localparam int PEP_RIF_ELT_W = $bits(pep_rif_elt_t);

  // ============================================================================================ //
  // Top level interfaces
  // ============================================================================================ //
  typedef struct packed {
    logic [PSI-1:0][R-1:0][PBS_B_W:0] data; // 2s complement
    logic                             sob;
    logic                             eob;
    logic                             sog;
    logic                             eog;
    logic                             sol;
    logic                             eol;
    logic [BPBS_ID_W-1:0]             pbs_id;
    logic                             last_pbs;
    logic                             full_throughput;
  } decomp_ntt_data_t;

  typedef struct packed {
    logic [PSI-1:0][R-1:0]            data_avail;
    logic                             ctrl_avail;
  } decomp_ntt_ctrl_t;

  typedef struct packed {
    // Mod switch
    logic [PSI-1:0][R-1:0][MOD_Q_W-1:0] data;
    logic                               sob;
    logic                               eob;
    logic                               sol;
    logic                               eol;
    logic                               sog;
    logic                               eog;
    logic [BPBS_ID_W-1:0]               pbs_id;
  } ntt_acc_modsw_data_t;

  typedef struct packed {
    // Mod switch
    logic [PSI-1:0][R-1:0]              data_avail;
    logic                               ctrl_avail;
  } ntt_acc_modsw_ctrl_t;

  typedef struct packed {
    logic [PSI-1:0][R-1:0]              data_avail;
    logic                               ctrl_avail;
  } ntt_proc_ctrl_t;

  typedef struct packed {
    decomp_ntt_data_t                   decomp_ntt_data;
    ntt_proc_cmd_t                      ntt_proc_cmd;
  } p1_p2_sll_data_t;

  typedef struct packed {
    decomp_ntt_ctrl_t                   decomp_ntt_ctrl;
    logic                               ntt_proc_cmd_avail;
    entrybsk_proc_t                     bsk_ctrl;
  } p1_p2_sll_ctrl_t;

  typedef struct packed {
    ntt_acc_modsw_data_t                ntt_acc_modsw_data;
  } p2_p1_sll_data_t;

  typedef struct packed {
    ntt_acc_modsw_ctrl_t                ntt_acc_modsw_ctrl;
    bskentry_proc_t                     bsk_ctrl;
  } p2_p1_sll_ctrl_t;

  typedef struct packed {
    ntt_proc_data_t                     ntt_proc_data;
    ntt_proc_cmd_t                      ntt_proc_cmd;
  } p2_p3_sll_data_t;

  typedef struct packed {
    ntt_proc_ctrl_t                     ntt_ctrl;
    pep_rif_elt_t                       pep_rif_elt;
    logic                               ntt_proc_cmd_avail;
    entrybsk_proc_t                     bsk_ctrl;
  } p2_p3_sll_ctrl_t;

  typedef struct packed {
    ntt_proc_data_t                     ntt_proc_data;
  } p3_p2_sll_data_t;

  typedef struct packed {
    ntt_proc_ctrl_t                     ntt_ctrl;
    bskentry_proc_t                     bsk_ctrl;
  } p3_p2_sll_ctrl_t;

endpackage
