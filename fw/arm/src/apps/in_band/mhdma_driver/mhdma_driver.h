// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Header and constants used by ucore firmware
// ==============================================================================================

#include <stdint.h>
#include "../ucore.h"

#ifndef __MHDMA_H__
#define __MHDMA_H__

#define MHDMA_CMD_WRITE_REQ_ID        0x50100
#define MHDMA_CMD_WRITE_REQ_ADDR      0x50104
#define MHDMA_NOTIFY_DATA_REQ_ID      0x50108
#define MHDMA_NOTIFY_DATA_REQ_ADDR    0x5010c
#define MHDMA_READ_DONE_DATA_REQ_ID   0x50110
#define MHDMA_READ_DONE_DATA_REQ_ADDR 0x50114

struct mhdma_cmd_fields_t {
  uint32_t _pad: 8;
  uint8_t  flag: 6;
  uint8_t  mode: 2;
  uint8_t  hid: 4;
  uint8_t  opcode: 4;
  uint8_t  iid: 8;
  uint16_t src_cid: 16;
  uint16_t dst_cid: 16;
} __attribute__((packed));

typedef union {
  uint64_t raw;
  struct mhdma_cmd_fields_t fields;
} mhdma_cmd_t;

#define MHDMA_CMD_NOTIFY 2
#define MHDMA_CMD_ACK    3
#define MHDMA_CMD_READ   6
#define MHDMA_CMD_CT     7

#define CMD_USER 0 // commands used inside an IOp with flag, dealing with ct internal to an IOp 
#define CMD_SRC  1 // commands to mean an IOp is done on a node, dealing with source ct
#define CMD_DST  2 // commands used for IOp destination, dealing with destination ct

void generate_read_req(uint8_t iop_id, uint8_t flag);
void generate_operand_read_req(uint8_t iop_id, uint8_t mode, uint8_t slave_hpu_id, uint16_t src_cid, uint16_t dst_cid, uint16_t target_cid);

void generate_user_notify(uint8_t iop_id, uint8_t flag);
void generate_iop_notify(uint8_t iop_id, uint8_t nb_hpus, uint8_t master_hpu_id);
void generate_ucore_notify(uint8_t iid, uint8_t master_hpu_id, uint16_t src_cid, uint16_t dst_cid, uint16_t target_cid);

#endif // __MHDMA_H__
