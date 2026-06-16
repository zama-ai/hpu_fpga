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

#ifndef UCORE_MHDMA_SIMU
#include "profile_hal.h"
#endif

#ifndef __UCORE_H__
#define __UCORE_H__

#ifdef UCORE_MHDMA_SIMU
#define PLL_INF( t, m, ... ) printf( m "\n", ##__VA_ARGS__ )  /* used for syst info (stats) */
#define PLL_ERR( t, m, ... ) printf( m "\n", ##__VA_ARGS__ )  /* used for errors            */
#define PLL_WRN( t, m, ... ) printf( m "\n", ##__VA_ARGS__ )  /* used for warnings          */
#define PLL_LOG( t, m, ... ) printf( m "\n", ##__VA_ARGS__ )  /* used for general printing  */
#define PLL_DBG( t, m, ... ) printf( m "\n", ##__VA_ARGS__ )  /* used for debug prints      */

#define HAL_INVALIDATE_CACHE_DATA(a,b) printf("invalidate cache\n")
#define iOSAL_Task_SleepTicks(n) while(0)
#define vOSAL_EnterCritical() while(0);
#define vOSAL_ExitCritical() while(0);
#endif


// Constants
// ============================================================================================= //
#define UCORE_VERSION_MAJOR              (3)
#define UCORE_VERSION_MINOR              (0)

#define OFFSET_TO_AMI_IOPACKQ_HEAD       (0x200000)
#define OFFSET_TO_AMI_IOPACKQ_DATA_START (0x200004)
#define OFFSET_TO_AMI_IOPACKQ_TAIL       (0x210004)
#define AMI_IOPACKQ_MAX_WORDS            (0x4000)

#define OFFSET_FROM_AMI_IOPQ_HEAD        (0x7000000)
#define OFFSET_FROM_AMI_IOPQ_DATA_START  (0x7000004)
#define OFFSET_FROM_AMI_IOPQ_TAIL        (0x7020000)
#define AMI_IOPQ_MAX_BYTES               (0x10000)

// Begin of DOP_FW_ADDR is reserved for runtime configuration structure
#define DOP_FW_ADDR  ((size_t) 0x39000000)
#define FW_RUNTIME_MAX_WORD ((size_t) 0x40)

#define DOP_LUT_ADDR  ((size_t) DOP_FW_ADDR + FW_RUNTIME_MAX_WORD*sizeof(uint32_t))
// Opcode is 8bit -> 256 words entry per blk_w
#define IOP_NUMBER ((size_t) 0x100)
#define MAX_HPU_IN_CLUSTER 8
#define FW_TABLE_ENTRY 128
#define MAX_FW_TABLE_ENTRY_OFST ((IOP_NUMBER*MAX_HPU_IN_CLUSTER*FW_TABLE_ENTRY)*sizeof(uint32_t))
#define MAX_FW_SIZE 0x2000000
#define SYNC_DOP_WORD 0xBC000000

// WARN seems to have limitation on isc_write
#define DOP_BUFFER_LOG2_SIZE 8
#define DOP_BUFFER_SIZE (1 << DOP_BUFFER_LOG2_SIZE)
#define MIN_DOP_FLUSH 10

// Local Ack -> IOp lookup
#define ACK_IOP_DEPTH 256

#define IOP_ID_MAX_COUNT  256
#define MAX_DST_VARS      64
#define MAX_VAR_BLKS      128
#define HPU_MAX_COUNT     7
#define FLAG_MAX_COUNT    64
#define B2B_POOL_SIZE     4096
#define DST_NOTIFYQ_SIZE  256

#define MHDMA_STATE_EMPTY          0 // no info
#define MHDMA_STATE_NOTIFY_PENDING 1 // sync has been added, waiting on ISC before notify
#define MHDMA_STATE_LB2B_WAITING   2 // load b2b has been seen, waiting on notify to trigger read
#define MHDMA_STATE_RECEIVED       3 // notify received
#define MHDMA_STATE_READING        4 // DMA request sent, waiting for data
#define MHDMA_STATE_RESOLVED       5 // data has been received

#define DST_STATE_NONE        0 // it means this dst is not needed for this iop
#define DST_STATE_WAIT_NOTIFY 1 // reset value of dst store elt, it means dst is expecting data (local or remote)
#define DST_STATE_READING     2 // remote dst read triggered but not done yet
#define DST_STATE_RESOLVED    3 // dst locally available

#define OPERAND_STATE_NONE         5 // no info on this operand
#define OPERAND_STATE_READ_PENDING 6 // source/dst is needed and should be read as soon as IOp producing it is done or notify is received
#define OPERAND_STATE_DMA_PENDING  7 // read request sent, waiting for data
#define OPERAND_STATE_RESOLVED     8 // source/dst is ready locally

#define IOP_STATE_UNKNOWN  0xF // iop unknown
#define IOP_STATE_RUNNING  0xE // iop running
#define IOP_STATE_DONE     0   // iop finished

#define DEBUG_PTR  0x7F00000
#define DEBUG_ADDR 0x7F00004
// 0x20000 uint32_t means max should be at 0x7F80004 (0x3FF80004)
#define DEBUG_SIZE 0x20000

typedef struct {
  uint8_t state;
  uint8_t nb_hpu;
} iop_state_t;

typedef struct {
  volatile uint8_t owner[IOP_ID_MAX_COUNT][MAX_DST_VARS];
  volatile uint8_t state[IOP_ID_MAX_COUNT][MAX_DST_VARS][MAX_VAR_BLKS];
} dst_store_t;

typedef struct {
  volatile uint8_t owner[IOP_ID_MAX_COUNT][MAX_DST_VARS];
  volatile uint8_t src_iid[IOP_ID_MAX_COUNT][MAX_DST_VARS];
  volatile uint16_t cid_offset[IOP_ID_MAX_COUNT][MAX_DST_VARS];
  volatile uint16_t dst_cid[IOP_ID_MAX_COUNT][MAX_DST_VARS][MAX_VAR_BLKS];
  volatile uint8_t state[IOP_ID_MAX_COUNT][MAX_DST_VARS][MAX_VAR_BLKS];
} src_store_t;

// master HPU is read initiator
// slave HPU is notified master, is receiving read and sending ct to master
typedef struct {
  uint8_t  slave_hpu_id;
  uint8_t  master_hpu_id;
  uint16_t src_ct_id;
  uint16_t dst_ct_id;
} mhdma_element_t;

// Type
// ============================================================================================= //
// Runtime configuration for Ucore
// A fixed size of FW_RUNTIME_MAX_WORD is reserved at the beginning of the FW memory for this structure
typedef struct {
  uint8_t  node_id;
  uint32_t timestamp;
  uint8_t  node_mask;
  uint16_t ct_user_size;
  uint16_t b2b_size;
  // TODO extend this with required runtime informations
  // WARN: configuration structure within backend must be updated accordingly
} UcoreCfg_t;

// Lookup entry
typedef struct {
  volatile uint32_t* ptr;
  size_t len;
} Lookup_t;

// Local Ack -> IOp lookup
// Use to store match between received ack and corresponding IOp
typedef struct {
  uint32_t iop[ACK_IOP_DEPTH];
  size_t wr_idx;
  size_t rd_idx;
} AckIopLut_t;

// Hpu functions prototypes
// ============================================================================================= //
void print_ddr_debug(uint32_t data);
void mhdma_table_reset(void);
void iop_state_init(void);
void iop_state_node_ack(uint8_t iid, uint8_t nb_hpu);
void b2b_pool_init(void);
uint16_t b2b_pool_pop(uint8_t iid);
uint16_t b2b_pool_free(uint8_t iid);
void dst_notifyq_init(void);
RemoteOperand_t *dst_notifyq_getdst_nofree(uint8_t iid);
void src_store_init(void);
void src_store_reset_iop(uint8_t iid);
void src_store_inits(uint8_t iid, OperandBundle_t *iop_src);
void src_store_print(uint8_t iid);
uint16_t src_store_get_waiting(uint8_t iid, uint8_t src_iid);
uint8_t src_store_get_waiting_cnt(uint8_t iid);
void src_notifyq_print(uint8_t iid);
void dst_store_reset_iop(uint8_t iid);
void dst_store_init(void);
void dst_store_initd(uint8_t iid, OperandBundle_t *iop_dst);
void dst_store_print(uint8_t iid);
void iop_teardown(uint8_t iid);
uint32_t parse_iop(
     uint32_t *stream,
     uint32_t iop_pending_bytes,
     // Static allocated buffer used during IOp parsing
     IOpHeader_t *header,
     IOpMapping_t *mapping,
     IOpOperandProp_t *operand_prop,
     IOpOperandAddr_t *operand_addr,
     IOpImmHeader_t *imm_header,
     // Operand/Immediat bundle generated by the parser
     OperandBundle_t* dst,
     OperandBundle_t* src,
     ImmediatBundle_t* imm);
uint32_t get_lookup(IOpHeader_t header, IOpMapping_t mapping, uint8_t hid, Lookup_t* lookup);
int patch_mem_dop(DOpu_t *dop, OperandBundle_t *iop_dst, OperandBundle_t *iop_src, uint32_t *dop_buffer, int dop_buffer_pos);
void patch_imm_dop(DOpu_t *dop, ImmediatBundle_t *iop_imm);
int patch_dop(DOpu_t *dop,
               OperandBundle_t *dst,
               OperandBundle_t *src,
               ImmediatBundle_t *imm,
               uint32_t *dop_buffer,
               int dop_buffer_pos);
DOpKind_t get_kind(DOpu_t *dop);
DOpSync_t get_sync_opcode(DOpu_t *dop);

// Utilities function to get used/virt_id for a given phys_id
// NB: easier to stay generic on `raw` format
uint8_t get_virt_of(uint8_t phys, IOpMapping_t mapping);
uint8_t get_phys_of(uint8_t vid, IOpMapping_t mapping);
uint8_t get_used_of(uint8_t vid, IOpMapping_t mapping);
uint8_t number_of_hpu(IOpMapping_t mapping);

#endif //__UCORE_H__
