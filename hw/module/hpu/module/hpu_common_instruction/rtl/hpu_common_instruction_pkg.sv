// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ==============================================================================================

package hpu_common_instruction_pkg;
  import regf_common_param_pkg::*;

//==================================================
// Integer opcode
//==================================================
// Only used in testbench,
// Must be moved to a testbench only package
  localparam int IOP_W = 8;

//==================================================
// Digit opcode
// [5:4]{Type}[3:0]{Subtype}
// * Type 0b00 -> Arith
//  Subtype meaning
//    [3] : Use msg constant
//    [2] : mult by cst
//    [1:0] : arith op {0: nothing, 1: Add, 2: Sub, 3: Sub (used in constant sub : cst - reg)}
//
// * Type 0b01 -> Sync
//  Subtype unused
//
// * Type 0b10 -> Mem (i.e. Load/Store)
//  Subtype meaning
//    [3:0] : ld/st op {0: load, 1: store}
//
// * Type 0b11 -> PBS
//    [3]: have_flush
//    [2:0] ManyLut cfg { 0: Single Pbs, 1: ML2 Pbs, 2: Ml4 Pbs, 3: ML8 Pbs}
//==================================================
  localparam int DOPT_W  = 2;
  localparam int DOPST_W = 4;
  localparam int DOP_W   = DOPT_W + DOPST_W;

  typedef enum bit [DOP_W-1:0]{
    // --> Arith
    DOP_ADD     = 6'b00_0001,
    DOP_SUB     = 6'b00_0010,
    DOP_MAC     = 6'b00_0101,
    // --> ArithMsg
    DOP_ADDS    = 6'b00_1001,
    DOP_SUBS    = 6'b00_1010,
    DOP_SSUB    = 6'b00_1011,
    DOP_MULS    = 6'b00_1100,
    // --> Sync 
    // NB: Only viewed by the scheduler, never reach PE
    DOP_SYNC    = 6'b01_0000,
    // --> load store in mem
    DOP_LD      = 6'b10_0000,
    DOP_ST      = 6'b10_0001,

    // --> PBS + KS
    DOP_PBS       = 6'b11_0000,
    DOP_PBS_ML2   = 6'b11_0001,
    DOP_PBS_ML4   = 6'b11_0010,
    DOP_PBS_ML8   = 6'b11_0011,
    DOP_PBS_F     = 6'b11_1000,
    DOP_PBS_ML2_F = 6'b11_1001,
    DOP_PBS_ML4_F = 6'b11_1010,
    DOP_PBS_ML8_F = 6'b11_1011
  } dop_e;

  typedef enum bit [DOPT_W-1:0]{
    // --> Arith
    DOPT_ARITH = 2'b00,
    // --> Sync 
    // NB: Only viewed by the scheduler, never reach PE
    DOPT_SYNC = 2'b01,
    // --> load store in mem
    DOPT_LS = 2'b10,
    // --> PBS + KS
    DOPT_PBS = 2'b11
  } dopt_e;

  typedef struct packed {
    logic [DOPT_W-1:0]  kind;     // Kind 
    logic [DOPST_W-1:0] sub_kind; // Sub Kind
  } dop_t;

//==================================================
// localparam
//==================================================
  localparam int RID_W          = 7; // Support up to 128 reg in the regfile
  localparam int GID_W          = 12;
  localparam int CID_W          = 16;
  localparam int MEM_MODE_W     = 2;
  localparam int MSG_CST_W      = 11;
  localparam int MSG_MODE_W     = 1;
  localparam int MUL_FACTOR_W   = 5;
  localparam int LOG_LUT_NB_W   = 2;
  localparam int LOG_MAX_LUT_NB = (1 << LOG_LUT_NB_W) - 1;
  localparam int MAX_LUT_NB     = 2**LOG_MAX_LUT_NB;

  localparam int PE_INST_W    = 32;
  // The following PE*_INST_W should be equal to PE_INST_W

//==================================================
// Structure
//==================================================
  typedef struct packed {
    logic [DOPT_W-1:0]       kind;
    logic                    flush_pbs;
    logic _padding;
    logic [LOG_LUT_NB_W-1:0] log_lut_nb; // log2(#luts), ie: 0 -> 1lut, 1 -> 2luts, etc
  } pep_dop_t;

  typedef struct packed {
    logic [DOP_W-1:0]      dop;
    logic [CID_W-1:0]      cid;
    logic [MEM_MODE_W-1:0] mode;
    logic _padding;
    logic [RID_W-1:0]      rid;
  } pem_inst_t;

  localparam int PEM_INST_W = $bits(pem_inst_t);

  typedef struct packed {
    pep_dop_t         dop;
    logic [GID_W-1:0] gid;
    logic [RID_W-1:0] src_rid;
    logic [RID_W-1:0] dst_rid;
  } pep_inst_t;

  localparam int PEP_INST_W = $bits(pep_inst_t);


  typedef struct packed {
    logic [DOP_W-1:0]        dop;
    logic [MUL_FACTOR_W-1:0] mul_factor;
    logic [RID_W-1:0]        src1_rid;
    logic [RID_W-1:0]        src0_rid;
    logic [RID_W-1:0]        dst_rid;
  } pea_mac_inst_t;

  localparam int PEA_MAC_INST_W = $bits(pea_mac_inst_t);


  typedef struct packed {
    logic [DOP_W-1:0]      dop;
    logic [MSG_CST_W-1:0]  msg_cst;
    logic [MSG_MODE_W-1:0] msg_mode;
    logic [RID_W-1:0]      src0_rid;
    logic [RID_W-1:0]      dst_rid;
  } pea_msg_inst_t;

  localparam int PEM_MSG_INST_W = $bits(pea_msg_inst_t);

endpackage
