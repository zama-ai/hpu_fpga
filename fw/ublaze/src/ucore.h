// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Header and constants used by ucore firmware
// ==============================================================================================

#include "hpu_dop_fmt.h"
#include "hpu_iop_fmt.h"

// Headers
// ============================================================================================= //
#include <stdio.h>

// Mandatory : enable/disable cache functions
#include "../../gen/ublaze/ip_ublaze/bsp/include/xil_cache.h"

// All parameters of the ublaze
#include "../../gen/ublaze/ip_ublaze/bsp/include/xparameters.h"

// Read/write for AXIDP
#include "../../gen/ublaze/ip_ublaze/bsp/include/xil_io.h"
#include "../../gen/ublaze/ip_ublaze/bsp/include/xil_mem.h"

// ublaze Pseudo-asm Macros and Interrupt Handling APIs
#include "../../gen/ublaze/ip_ublaze/bsp/include/mb_interface.h"

// Interruptions
#include "../../gen/ublaze/ip_ublaze/bsp/include/xintc.h"
#include "../../gen/ublaze/ip_ublaze/bsp/include/xstatus.h"
#include "../../gen/ublaze/ip_ublaze/bsp/include/xil_exception.h"


// Constants
// ============================================================================================= //
#define UCORE_VERSION_MAJOR              (2)
#define UCORE_VERSION_MINOR              (0)
#define UCORE_VERSION_IOPCODE            (0xFE)

#define DOP_LUT_ADDR ((size_t) XPAR_AXI_MP_BASEADDR)
// Opcode is 8bit -> 256 words entry per blk_w
#define DOP_LUT_RANGE ((size_t) 0x100)
#define SYNC_DOP_WORD 0x4000ffff

//Axi stream id
#define ACKQ_MAXIS_ID  0
#define WORKQ_SAXIS_ID 0
#define DOP_MAXIS_ID   1
#define ACK_SAXIS_ID   1

// Local Ack -> IOp lookup
#define ACK_IOP_DEPTH 256



// Type
// ============================================================================================= //
// Lookup entry
typedef struct {
  size_t offset;
  size_t len;
} Lookup_t;

// Local Ack -> IOp lookup
// Use to store match between received ack and corresponding IOp
typedef struct {
  uint32_t iop[ACK_IOP_DEPTH];
  size_t wr_idx;
  size_t rd_idx;
} AckIopLut_t;

// Utilities function to init and manipulate ackiop lookup
void init(AckIopLut_t* lut) {
  lut->wr_idx = 0;
  lut->rd_idx = 0;
}

void push(AckIopLut_t* lut, uint32_t iop) {
  size_t wr_pos = lut->wr_idx % ACK_IOP_DEPTH;
  lut->iop[wr_pos] = iop;
  lut->wr_idx++;
}

uint32_t pop(AckIopLut_t* lut) {
  size_t rd_pos = lut->rd_idx % ACK_IOP_DEPTH;
  uint32_t iop = lut->iop[rd_pos];
  lut->rd_idx++;

  return iop;
}
