// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package containing common localparams for PE memory.
// ==============================================================================================

package pem_common_param_pkg;
  import param_tfhe_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import hpu_common_instruction_pkg::*;
  import regf_common_param_pkg::*;
  import top_common_param_pkg::*;

//==================================================
// localparams
//==================================================
  // NOTE : support only PEM_PC that divides BLWE_K

  localparam int BLWE_ACS_W               = MOD_Q_W > 32 ? 64 : 32;
  localparam int AXI4_WORD_PER_BLWE       = (BLWE_K*BLWE_ACS_W + AXI4_DATA_W-1)/AXI4_DATA_W;
  localparam int AXI4_WORD_PER_PC         = AXI4_WORD_PER_BLWE / PEM_PC;
  localparam int AXI4_WORD_PER_PC0        = AXI4_WORD_PER_PC + 1; // PC0 also deals with the word containing the body.

  localparam int BLWE_COEF_PER_AXI4_WORD  = AXI4_DATA_W / BLWE_ACS_W;
  localparam int REGF_COEF_PER_PC         = REGF_COEF_NB / PEM_PC;

  localparam [AXI4_ID_W-1:0] BLWE_AXI_ARID = '0; // Use the same ID for the read and the write => ensure the order.

  // Align on Page
  localparam int CT_MEM_BYTES             = (((AXI4_WORD_PER_PC0 * AXI4_DATA_BYTES) + PAGE_BYTES-1)/ PAGE_BYTES) * PAGE_BYTES;

//==================================================
// Size localparam
//==================================================
  localparam int AXI4_WORD_PER_PC_W     = $clog2(AXI4_WORD_PER_PC)==0 ? 1 : $clog2(AXI4_WORD_PER_PC);
  localparam int AXI4_WORD_PER_PC_WW    = $clog2(AXI4_WORD_PER_PC+1)==0 ? 1 : $clog2(AXI4_WORD_PER_PC+1); // count from 0 to AXI4_WORD_PER_PC included

  localparam int AXI4_WORD_PER_PC0_W    = $clog2(AXI4_WORD_PER_PC0)==0 ? 1 : $clog2(AXI4_WORD_PER_PC0);
  localparam int AXI4_WORD_PER_PC0_WW   = $clog2(AXI4_WORD_PER_PC0+1)==0 ? 1 : $clog2(AXI4_WORD_PER_PC0+1); // count from 0 to AXI4_WORD_PER_PC0 included

//==================================================
// Structure
//==================================================
  typedef struct packed {
    logic [REGF_REGID_W-1:0] reg_id;
    logic [CID_W-1:0]        cid;
  } pem_cmd_t;

  localparam int PEM_CMD_W = $bits(pem_cmd_t);

  //== Counters
  typedef struct packed {
    logic ack_inc;
    logic inst_inc;
  } pem_ld_counter_inc_t;

  localparam int PEM_LD_COUNTER_INC_W = $bits(pem_ld_counter_inc_t);

  typedef struct packed {
    logic ack_inc;
    logic inst_inc;
  } pem_st_counter_inc_t;

  localparam int PEM_ST_COUNTER_INC_W = $bits(pem_st_counter_inc_t);

  typedef struct packed {
    pem_ld_counter_inc_t load;
    pem_st_counter_inc_t store;
  } pem_counter_inc_t;

  localparam int PEM_COUNTER_INC_W = $bits(pem_counter_inc_t);

  typedef struct packed {
    logic [PEM_PC_MAX-1:0][AXI4_ADD_W-1:0] add;
    logic [PEM_PC_MAX-1:0][3:0][31:0]      data;
  } pem_ld_info_t;

  localparam int PEM_LD_INFO_W = $bits(pem_ld_info_t);

  typedef struct packed {
    logic [7:0]            c0_cmd_cnt;
    logic [PEM_PC_MAX-1:0][7:0] brsp_ack_seen;
    logic [PEM_PC_MAX-1:0][7:0] brsp_bresp_cnt;
    logic [PEM_PC_MAX-1:0][7:0] c0_free_loc_cnt;
    logic [PEM_PC_MAX-1:0] c0_enough_location;
    logic [PEM_PC_MAX-1:0] m_axi4_awready;
    logic [PEM_PC_MAX-1:0] m_axi4_awvalid;
    logic [PEM_PC_MAX-1:0] m_axi4_wready;
    logic [PEM_PC_MAX-1:0] m_axi4_wvalid;
    logic [PEM_PC_MAX-1:0] m_axi4_bready;
    logic [PEM_PC_MAX-1:0] m_axi4_bvalid;
    logic [PEM_PC_MAX:0] s0_cmd_rdy;
    logic [PEM_PC_MAX:0] s0_cmd_vld; 
    logic [PEM_PC_MAX-1:0] r2_axi_vld;
    logic [PEM_PC_MAX-1:0] r2_axi_rdy;
    logic [PEM_PC_MAX-1:0] rcp_fifo_in_rdy;
    logic [PEM_PC_MAX-1:0] rcp_fifo_in_vld;
    logic [PEM_PC_MAX-1:0] brsp_fifo_in_rdy;
    logic [PEM_PC_MAX-1:0] brsp_fifo_in_vld;
    logic pem_regf_rd_req_rdy;
    logic pem_regf_rd_req_vld;
    logic cmd_rdy;
    logic cmd_vld;
    //logic [PEM_PC_MAX-1:0][AXI4_ADD_W-1:0] add;
    //logic [PEM_PC_MAX-1:0][3:0][31:0]      data;
  } pem_st_info_t;

  localparam int PEM_ST_INFO_W = $bits(pem_st_info_t);

  typedef struct packed {
    pem_ld_info_t load;
    pem_st_info_t store;
  } pem_info_t;

  localparam int PEM_INFO_W = $bits(pem_info_t);

endpackage
