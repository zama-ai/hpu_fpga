// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// HPU Operation format definition
// Also provide simple parsing logic and associated types
// Parsing logic define here to keep the current build process but must be updated later on
// ==============================================================================================

#ifndef __HPU_DOP_FMT_H__
#define __HPU_DOP_FMT_H__

// Headers
// ============================================================================================= //
#include <stdint.h>
// Retrived Hpu IOp fmt header for use of Operands/Immediats
#include "hpu_iop_fmt.h"

// Constants
// ============================================================================================= //
// Define MSG_WIDTH/CARRY_WIDTH
// Used for immediat packing/unpacking
#define MSG_WIDTH 2
#define CARRY_WIDTH 2

// Memory layaut
// -------------------------------------------------------
// cid_0
// cid_1
//  |   User memory goes downside
// \/
// Heap --------------------------------------------------
//  ^   Heap memory goes upside
//  |
// cid_max
// -------------------------------------------------------
// NB: No check for heap overflow is done at runtime. This is enforce by the backend during
//     translation table generation
// ============================================================================================= //
// TODO: Add RTL register for heap_start.
// This will enable the FW to use this value instead of currently hardcoded one.
// NB: Currently the value is hardcoded, since the ublaze in u55c can't read the register file
#define CT_MEM_SLOT 32768
#define HEAP_START_SLOT ((CT_MEM_SLOT) -1)

// Type
// NB: Gcc packed struct are defined from LSB field to MSB one.
// ============================================================================================= //
// Raw DOp format used to extract opcode only
struct dop_raw_t {
  uint32_t _reserved: 26;
  uint8_t opcode: 6;
} __attribute__((packed));

// PeArith DOp format
struct dop_arith_t {
  uint8_t dst_rid: 7;
  uint8_t src0_rid: 7;
  uint8_t src1_rid: 7;
  uint8_t mul_factor: 5;
  uint8_t opcode: 6;
} __attribute__((packed));

// PeArithMsg DOp format
struct dop_arith_msg_t {
  uint8_t dst_rid: 7;
  uint8_t src0_rid: 7;
  uint8_t msg_mode: 1;
  uint16_t msg_cst: 11;
  uint8_t opcode: 6;
} __attribute__((packed));

// Constant used to decode msg_mode
#define IMM_CST 0b0
#define IMM_VAR 0b1


// DOp mem field definition
struct dop_mem_t {
  uint8_t rid:7;
  uint8_t _pad: 1;
  uint8_t mode: 2;
  uint16_t slot: 16;
  uint8_t opcode:6;
} __attribute__((packed));

// Constant used to decode memory mode
#define MEM_ADDR 0x0
#define MEM_HEAP 0x1
#define MEM_SRC 0x2
#define MEM_DST 0x3

// DOp Pbs field definition
struct dop_pbs_t {
  uint8_t dst_rid:7;
  uint8_t src_rid:7;
  uint16_t gid: 12;
  uint8_t opcode:6;
} __attribute__((packed));

struct dop_sync_t {
  uint32_t sid: 26;
  uint8_t opcode:6;
} __attribute__((packed));

// DOp field wrapped view
// Use to cast between field struct and raw integer
typedef union {
  uint32_t raw;
  struct dop_raw_t raw_field;
  struct dop_arith_t arith;
  struct dop_arith_msg_t arith_msg;
  struct dop_mem_t mem;
  struct dop_pbs_t pbs;
  struct dop_sync_t sync;
} DOpu_t;


// Opcode kind definition and extraction
// ============================================================================================= //
typedef enum {
  DOPK_ARITH = 0b00,
  DOPK_SYNC = 0b01,
  DOPK_MEM = 0b10,
  DOPK_PBS = 0b11,
}DOpKind_t ;

// Multibit enum to extract some DOp properties
enum DOpArithFlag {
  IMM_FLAG = 0b1000,
  MUL_FLAG = 0b0100,
  SUB_FLAG = 0b0010,
  ADD_FLAG = 0b0001,
};


#endif //__HPU_DOP_FMT_H__
