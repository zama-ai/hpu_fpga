// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// HPU Operation format definition
// Also provide simple parsing logic and associated types
// Parsing logic define here to keep the current build process but must be updated later on
// ==============================================================================================

#ifndef __HPU_IOP_FMT_H__
#define __HPU_IOP_FMT_H__
// Headers
// ============================================================================================= //
#include <stdint.h>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpacked-bitfield-compat"

// Type
// NB: Gcc packed struct are defined from LSB field to MSB one.
// ============================================================================================= //

//  IOpHeader -----------------------------------------------------------------
struct iop_header_t  {
  uint8_t src_align: 8;
  uint8_t dst_align: 8;
  uint8_t opcode: 8;
  uint8_t has_imm: 1;
  uint8_t fw_mode: 1;
  uint8_t _reserved: 6;
} __attribute__((packed));

// Constant used to decode fw_mode
#define FW_DYNAMIC true
#define FW_STATIC false

// Union for casting between raw and inner type
typedef union {
  uint32_t raw;
  struct iop_header_t header;
} IOpHeader_t;

//  IOpMapping ----------------------------------------------------------------
struct iop_mapping_t  {
  uint8_t used_0: 1;
  uint8_t phys_0: 3;
  uint8_t used_1: 1;
  uint8_t phys_1: 3;
  uint8_t used_2: 1;
  uint8_t phys_2: 3;
  uint8_t used_3: 1;
  uint8_t phys_3: 3;
  uint8_t used_4: 1;
  uint8_t phys_4: 3;
  uint8_t used_5: 1;
  uint8_t phys_5: 3;
  uint8_t used_6: 1;
  uint8_t phys_6: 3;
  uint8_t used_7: 1;
  uint8_t phys_7: 3;
} __attribute__((packed));

// Union for casting between raw and inner type
typedef union {
  uint32_t raw;
  struct iop_mapping_t header;
} IOpMapping_t;

//  OperandProperties ---------------------------------------------------------
struct iop_operand_properties_t {
  uint8_t _pad: 5;
  uint8_t block: 8;
  uint8_t vec_size: 5;
  uint8_t iid: 8;
  uint8_t pos: 3;
  uint8_t is_last: 1;
  uint8_t kind: 2;
} __attribute__((packed));

// Union for casting between raw and inner type
typedef union {
  uint32_t raw;
  struct iop_operand_properties_t operand_prop;
} IOpOperandProp_t;

//  OperandAddr ---------------------------------------------------------------
struct iop_operand_addr_t {
  uint16_t base_cid: 16;
  uint16_t _pad: 16;
} __attribute__((packed));

// Union for casting between raw and inner type
typedef union {
  uint32_t raw;
  struct iop_operand_addr_t operand_addr;
} IOpOperandAddr_t;

//  ImmHeader -----------------------------------------------------------------
// Constant used to decode kind
#define KIND_SRC 0x0
#define KIND_DST 0x1
#define KIND_IMM 0x2
#define KIND_UNKNOWN 0x3

struct iop_imm_header_t  {
  uint16_t lsb_msg: 16;
  uint16_t block: 12;
  uint8_t is_last: 1;
  uint8_t _reserved: 1;
  uint8_t kind: 2;
} __attribute__((packed));

// Union for casting between raw and inner type
typedef union {
  uint32_t raw;
  struct iop_imm_header_t header;
} IOpImmHeader_t;

// Depict Operand/Immediat bundle
// ============================================================================================= //
// To prevent the need of allocation at runtime maximum bundle size is fixed at compile time
// TODO Temporary defines
// Fw must retrived those value from configuration structure. Then two solutions:
// * Dynamic allocation if Rtos is capable
// * Runtime check that user configuration don't overflow with static allocation
#define OPERAND_BUNDLE_MAX_SLOT 32
#define IMMEDIAT_BUNDLE_MAX_SLOT 4
#define IMMEDIAT_MSG_MAX_SLOT 6
// NB: Two words are used for each operands (i.e. props and addr)
#define IOP_MAX_WORDS (2 + 2*(2*OPERAND_BUNDLE_MAX_SLOT) + IMMEDIAT_BUNDLE_MAX_SLOT*(IMMEDIAT_MSG_MAX_SLOT/2))
#define IOP_MAX_BYTES (IOP_MAX_WORDS * sizeof(uint32_t))

// src/dst ct
typedef struct {
  uint16_t src_cid;
  uint16_t dst_cid;
  uint8_t iid;
  uint8_t pos;
  uint8_t state;
  uint16_t target_cid;
} RemoteOperand_t;

// Operand are depict as vector starting from cid_ofst
typedef struct {
  uint16_t cid_ofst;
  uint8_t block;
  uint8_t len;
  uint8_t iid;
  uint8_t pos;
} Operand_t;

// IOp Src/Dst have variable length
typedef struct {
  uint8_t len;
  Operand_t operand[OPERAND_BUNDLE_MAX_SLOT];
} OperandBundle_t;

// Immediat has variable bitwidth
// len depict the number of uint16_t words
typedef struct {
  uint8_t len;
  uint16_t msg[IMMEDIAT_MSG_MAX_SLOT];
} Immediate_t;

// IOp Imm has variable length
typedef struct {
  uint8_t len;
  Immediate_t cst[IMMEDIAT_BUNDLE_MAX_SLOT];
} ImmediatBundle_t;

#pragma GCC diagnostic pop
#endif //__HPU_IOP_FMT_H__
