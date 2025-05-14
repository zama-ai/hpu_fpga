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
// Retrieved Hpu IOp fmt header for use of Operands/Immediats
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
#define CT_MEM_SLOT 4096
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

// Convenience function to extract kind for DOp union
DOpKind_t get_kind(DOpu_t *dop) {
  uint8_t opcode = dop->raw_field.opcode;

  return ((DOpKind_t) (opcode >> 4));
}

// Patching function
// ============================================================================================= //
// Patch templated memory instruction
// NB: IOp have variable destination and source operands
// TODO Add error handling for out_of_range patching
void patch_mem_dop(DOpu_t *dop, OperandBundle_t *iop_dst, OperandBundle_t *iop_src) {

  switch (dop->mem.mode) {
    case MEM_ADDR: { // Already an explicit ADDR -> No need to patch
      break;}
    case MEM_HEAP: { // Heap template
      // Replace Heap offset by concrete addr and toggle the mode
      dop->mem.slot = HEAP_START_SLOT - dop->mem.slot;
      dop->mem.mode = MEM_ADDR;
      break;
    }
    case MEM_SRC: { // Src template
      // Replace mem (tid,bid) by concrete addr and toggle the mode
      uint8_t tid = (dop->mem.slot >> 8) & 0xff;
      uint8_t bid = dop->mem.slot & 0xff;
      dop->mem.slot = iop_src->operand[tid].cid_ofst + bid;
      dop->mem.mode = MEM_ADDR;
      break;
    }
    case MEM_DST: { // Dst template
      // Replace mem (tid,bid) by concrote addr and toggle the mode
      uint8_t tid = (dop->mem.slot >> 8) & 0xff;
      uint8_t bid = dop->mem.slot & 0xff;
      dop->mem.slot = iop_dst->operand[tid].cid_ofst + bid;
      dop->mem.mode = MEM_ADDR;
      break;
    }
  }
}

// Patch arith message instruction
// TODO Add error handling for out_of_range patching
void patch_imm_dop(DOpu_t *dop, ImmediatBundle_t *iop_imm) {
  switch (dop->arith_msg.msg_mode) {
    case IMM_CST: { // Already an explicit CONSTANT -> No need to patch
      break;}
    case IMM_VAR: { // Immediat template
      // Replace imm (tid,bid) by concrete constant and toggle the mode
      uint8_t tid = (dop->arith_msg.msg_cst >> 8) & 0xff;
      uint8_t bid = dop->arith_msg.msg_cst & 0xff;
      // Immediat value are packed uint16_t array
      // Compute slot_id and offset
      uint8_t slot_id = (bid*MSG_WIDTH) / (8* sizeof(uint16_t));
      uint8_t offset = (bid*MSG_WIDTH) % (8* sizeof(uint16_t));

      // TODO: Let crop be configured by user ?
      // In theory we could add up to MSG_WIDTH + CARRY_WIDTH. Current crop may be to strong in some cases.
      dop->arith_msg.msg_cst = ((iop_imm->cst[tid].msg[slot_id]) >> offset) & ((1 << MSG_WIDTH) -1);
      dop->arith_msg.msg_mode = IMM_CST;
      break;
    }
  }
}

// Global template patching
// ============================================================================================= //

// Utilities function to patch DOp
void patch_dop(DOpu_t *dop,
               OperandBundle_t *dst,
               OperandBundle_t *src,
               ImmediatBundle_t *imm) {
  DOpKind_t kind = get_kind(dop);

  switch (kind) {
    case DOPK_MEM: {
      patch_mem_dop(dop, dst, src);
      break;
    }
    case DOPK_ARITH: {
      // Check if its a scalar arith operation
      if ((dop->raw_field.opcode & IMM_FLAG) == IMM_FLAG) {
        patch_imm_dop(dop, imm);
      }
      break;
    }
    case DOPK_SYNC:
    case DOPK_PBS: { // Nothing to do
      break;
    }
  }
}

#endif //__HPU_DOP_FMT_H__
