// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package containing common localparams used in regfile.
// ==============================================================================================

package regf_common_param_pkg;
  import param_tfhe_pkg::*;
  import regf_common_definition_pkg::*;

  // Number of registers in the regfile
  export regf_common_definition_pkg::REGF_REG_NB;
  export regf_common_definition_pkg::REGF_COEF_NB;
  export regf_common_definition_pkg::REGF_SEQ;

  localparam int PE_NB  = 3;
  localparam int PEA_ID = 0; // Most priority
  localparam int PEM_ID = 1;
  localparam int PEP_ID = 2;

  localparam int PE_ID_W = $clog2(PE_NB) == 0 ? 1 : $clog2(PE_NB);

  // ------------------------------------------------------------------------------------------- --
  // Derived localparam
  // ------------------------------------------------------------------------------------------- --
  localparam int REGF_REGID_W = $clog2(REGF_REG_NB) == 0 ? 1 : $clog2(REGF_REG_NB);

  // A URAM can contain 4K words of 72bits
  // A "RAM" is composed of 1 or several URAM. This "RAM" deals with
  // REGF_COEF_PER_URAM_WORD coefficients.
  localparam int REGF_COEF_PER_URAM_WORD = 72 / MOD_Q_W;
  localparam int REGF_RAM_NB             = REGF_COEF_NB / REGF_COEF_PER_URAM_WORD;
  localparam int REGF_URAM_PER_RAM       = (REGF_REG_NB * BLWE_K + (REGF_RAM_NB * 4096 * REGF_COEF_PER_URAM_WORD-1)) / (REGF_RAM_NB * 4096 * REGF_COEF_PER_URAM_WORD);
  localparam int REGF_BLWE_COEF_PER_RAM  = BLWE_K  / REGF_RAM_NB;
  localparam int REGF_BLWE_WORD_PER_RAM  = REGF_BLWE_COEF_PER_RAM / REGF_COEF_PER_URAM_WORD;
  localparam int REGF_RAM_WORD_DEPTH     = REGF_URAM_PER_RAM * 4096; // In word unit
  localparam int REGF_RAM_WORD_ADD_W     = $clog2(REGF_RAM_WORD_DEPTH) == 0 ? 1 : $clog2(REGF_RAM_WORD_DEPTH);

  localparam int REGF_SEQ_COEF_NB        = REGF_COEF_NB / REGF_SEQ;
  localparam int REGF_SEQ_WORD_NB        = REGF_SEQ_COEF_NB / REGF_COEF_PER_URAM_WORD;
  localparam int REGF_BLWE_WORD_CNT_W    = $clog2(REGF_BLWE_WORD_PER_RAM+1) == 0 ? 1 : $clog2(REGF_BLWE_WORD_PER_RAM+1); // Counts the body.
  localparam int REGF_BLWE_WORD_CNT_WW   = $clog2(REGF_BLWE_WORD_PER_RAM+2) == 0 ? 1 : $clog2(REGF_BLWE_WORD_PER_RAM+2); // Counts the body: from 0 to REGF_BLWE_WORD_PER_RAM+1 included

  localparam int REGF_WORD_NB            = REGF_COEF_NB / REGF_COEF_PER_URAM_WORD;
  localparam int REGF_WORD_W             = MOD_Q_W * REGF_COEF_PER_URAM_WORD;
  localparam int REGF_COEF_ID_W          = $clog2(REGF_COEF_NB) == 0 ? 1 : $clog2(REGF_COEF_NB);
  localparam int REGF_SEQ_W              = $clog2(REGF_SEQ) == 0 ? 1 : $clog2(REGF_SEQ);

  // ------------------------------------------------------------------------------------------- --
  // Structure
  // ------------------------------------------------------------------------------------------- --
  typedef struct packed {
    logic                            do_2_read;
    logic [REGF_REGID_W-1:0]         reg_id_1; // in case 2 readings
    logic [REGF_REGID_W-1:0]         reg_id;
    logic [REGF_BLWE_WORD_CNT_W-1:0] start_word;
    logic [REGF_BLWE_WORD_CNT_W-1:0] word_nb_m1;
  } regf_rd_req_t;

  localparam int REGF_RD_REQ_W = $bits(regf_rd_req_t);

  typedef struct packed {
    logic [REGF_REGID_W-1:0]         reg_id;
    logic [REGF_BLWE_WORD_CNT_W-1:0] start_word;
    logic [REGF_BLWE_WORD_CNT_W-1:0] word_nb_m1;
  } regf_wr_req_t;

  localparam int REGF_WR_REQ_W = $bits(regf_wr_req_t);

  typedef struct packed {
    logic               last_mask;
    logic               last_word;
    logic [PE_ID_W-1:0] pe_id;
  } regf_side_t;

  localparam int REGF_SIDE_W = $bits(regf_side_t);

endpackage
