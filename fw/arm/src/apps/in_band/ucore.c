// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// ucore firmware
//
// Continuously:
// *  Read IOPs from work queue
// *  Parse them to extract OpCode and src/dest ops
// *  Read corresponding DOps stream from translation table
// *  If DOp src/dst match template pattern, patch Opcode with real IOps args
// *  Send patched DOps to HW
//
// Behind the scene, an interrput handler wait on Hw DOps ack and forward them to host throught
// the ack queue.
// ==============================================================================================

#include "profile_hal.h"
#ifndef UCORE_MHDMA_SIMU
#include "pll.h"
#include "stream_isc.h"
#endif
#include "ucore.h"
#include "mhdma_driver/mhdma_driver.h"
#include <stdbool.h>

uint8_t cur_iid = 1;
IOpMapping_t cur_mapping;
uint8_t phys_hpu_id;
uint8_t node_mask;
uint16_t b2b_pool_start_addr = 12288;
uint16_t b2b_pool_size = 4096;
volatile mhdma_element_t mhdma_table[IOP_ID_MAX_COUNT][FLAG_MAX_COUNT];
volatile uint8_t mhdma_table_state[IOP_ID_MAX_COUNT][FLAG_MAX_COUNT];
extern uint64_t intr_readc_cnt;
extern uint32_t debug_intr_global_cnt;

#ifndef UCORE_MHDMA_SIMU
// DDR debug trace
volatile uint32_t *debugPtrAddr = ( volatile uint32_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + DEBUG_PTR);
volatile uint32_t *debugZoneAddr = ( volatile uint32_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + DEBUG_ADDR);
uint32_t debugZonePtr = 0;

void print_ddr_debug(uint32_t data) {
  volatile uint32_t* debug_idx = debugZoneAddr + (debugZonePtr % DEBUG_SIZE);
  *debug_idx = data;
  HAL_FLUSH_CACHE_DATA( (uintptr_t)debug_idx, sizeof(uint32_t));
  debugZonePtr += 1;
  *debugPtrAddr = (debugZonePtr % DEBUG_SIZE);
  HAL_FLUSH_CACHE_DATA( (uintptr_t)debugPtrAddr, sizeof(uint32_t));
}
#else
void print_ddr_debug(uint32_t data) {
  while(0);
}
#endif

// mhdma_table (User data)
void mhdma_table_reset(void) {
  memset((void*)mhdma_table_state, MHDMA_STATE_EMPTY, sizeof(mhdma_table_state));
}
void mhdma_table_reset_iop(uint8_t iid) {
  memset((void*)mhdma_table_state[iid], MHDMA_STATE_EMPTY, sizeof(mhdma_table_state[iid]));
}

// IOP state
volatile iop_state_t iop_state[IOP_ID_MAX_COUNT];

void iop_state_init(void) {
  for (int i = 0; i < IOP_ID_MAX_COUNT; i++) {
    iop_state[i].state  = IOP_STATE_UNKNOWN;
    iop_state[i].nb_hpu = 0xFF;
  }
}

void iop_state_node_ack(uint8_t iid, uint8_t nb_hpu) {
  if ((iop_state[iid].state == IOP_STATE_UNKNOWN)
   || (iop_state[iid].state == IOP_STATE_RUNNING)
   || (iop_state[iid].state == IOP_STATE_DONE)) {
    iop_state[iid].state = nb_hpu - 1;
  } else {
    iop_state[iid].state -= 1;
  }
}

// ugly debug fct (should not be used)
void print_iop_state(void) {
    PLL_ERR("ucore", "[HPU%d] cur_iid %d state %d (-2 %d:%d -1 %d:%d +1 %d:%d +2 %d:%d)",
            phys_hpu_id,
            cur_iid,
            iop_state[cur_iid].state,
            (uint8_t)(cur_iid-2),
            iop_state[(uint8_t)(cur_iid-2)].state,
            (uint8_t)(cur_iid-1),
            iop_state[(uint8_t)(cur_iid-1)].state,
            (uint8_t)(cur_iid+1),
            iop_state[(uint8_t)(cur_iid+1)].state,
            (uint8_t)(cur_iid+2),
            iop_state[(uint8_t)(cur_iid+2)].state);
}

// B2B Pool
uint8_t b2b_pool[B2B_POOL_SIZE];
uint16_t b2b_pool_head;
uint16_t b2b_pool_tail;
uint16_t b2b_pool_free_cnt;

void b2b_pool_init(void) {
  if (b2b_pool_size != B2B_POOL_SIZE) {
    PLL_ERR("ucore", "[HPU%d] b2b_pool size is incorrect (fw %d, sw %d)",
        phys_hpu_id,
        B2B_POOL_SIZE,
        b2b_pool_size);
  }
  memset(b2b_pool, 0x0, sizeof(b2b_pool));
  b2b_pool_head = 0;
  b2b_pool_tail = 0;
  b2b_pool_free_cnt = B2B_POOL_SIZE;
}

uint16_t b2b_pool_pop(uint8_t iid) {
  vOSAL_EnterCritical();
  if (b2b_pool_free_cnt == 0) {
    return 0xFFFF; // this means no more empty slot
  }
  uint16_t alloc_slot = b2b_pool_head;
  b2b_pool_free_cnt--;
  b2b_pool_head = (b2b_pool_head + 1) % B2B_POOL_SIZE;
  b2b_pool[alloc_slot] = iid;
  vOSAL_ExitCritical();
  return (alloc_slot + b2b_pool_start_addr);
}

uint16_t b2b_pool_free(uint8_t iid) {
  vOSAL_EnterCritical();
  if (b2b_pool_free_cnt == B2B_POOL_SIZE) {
    // we should not be doing a free
    // maybe this iop did not use any slot
    return 0;
  }
  if (b2b_pool[b2b_pool_tail] != iid) {
    // at tail, we should find iid we are trying to free
    return 0;
  }
  uint16_t free_cnt = 0;
  while (b2b_pool[b2b_pool_tail] == iid && b2b_pool_free_cnt < B2B_POOL_SIZE) {
    b2b_pool[b2b_pool_tail] = 0x0;
    b2b_pool_tail = (b2b_pool_tail + 1) % B2B_POOL_SIZE;
    b2b_pool_free_cnt++;
    free_cnt++;
  }
  print_ddr_debug(0xB2B00000+iid);
  print_ddr_debug((b2b_pool_free_cnt << 16) + free_cnt);
  vOSAL_ExitCritical();
  return free_cnt;
}

void b2b_pool_print(void) {
  PLL_ERR("ucore", "[HPU%d] b2b_pool head %d (iid %d) tail %d (iid %d) free %d",
      phys_hpu_id,
      b2b_pool_head,
      b2b_pool[b2b_pool_head],
      b2b_pool_tail,
      b2b_pool[b2b_pool_tail],
      b2b_pool_free_cnt);
}

// dst notify queue
RemoteOperand_t dst_notifyq[DST_NOTIFYQ_SIZE];
uint16_t dst_notifyq_head;
uint16_t dst_notifyq_tail;
uint16_t dst_notifyq_tail_nofree;
uint16_t dst_notifyq_free_cnt;

void dst_notifyq_init(void) {
  for (int i = 0; i < DST_NOTIFYQ_SIZE; i++) {
    dst_notifyq[i].state = OPERAND_STATE_NONE;
  }
  dst_notifyq_head = 0;
  dst_notifyq_tail = 0;
  dst_notifyq_tail_nofree = 0;
  dst_notifyq_free_cnt = DST_NOTIFYQ_SIZE;
}

RemoteOperand_t *dst_notifyq_pop(uint8_t iid) {
  if (dst_notifyq_free_cnt == 0) {
    return NULL; // this means no more empty slot
  }
  uint16_t alloc_slot = dst_notifyq_head;
  dst_notifyq_free_cnt--;
  dst_notifyq_head = (dst_notifyq_head + 1) % DST_NOTIFYQ_SIZE;
  dst_notifyq[alloc_slot].iid = iid;
  return &dst_notifyq[alloc_slot];
}

void dst_notifyq_print(uint8_t iid) {
  PLL_INF("ucore", "[HPU%d] dst_notifyq head %d tail %d nofree_tail %d free %d",
      phys_hpu_id,
      dst_notifyq_head,
      dst_notifyq_tail,
      dst_notifyq_tail_nofree,
      dst_notifyq_free_cnt);
  uint16_t index = (dst_notifyq_head - 1) % DST_NOTIFYQ_SIZE;
  while (dst_notifyq[index].iid == iid) {
    PLL_INF("ucore", "[HPU%d] dst_notifyq iid %d pos %d state %d src %d dst %04x target %d",
        phys_hpu_id,
        iid,
        dst_notifyq[index].pos,
        dst_notifyq[index].state,
        dst_notifyq[index].src_cid,
        dst_notifyq[index].dst_cid,
        dst_notifyq[index].target_cid);
    if (index == dst_notifyq_tail) {
      break;
    }
    index = (index - 1) % DST_NOTIFYQ_SIZE;
  }
}

RemoteOperand_t *dst_notifyq_getdst(uint8_t iid) {
  if (dst_notifyq_free_cnt == DST_NOTIFYQ_SIZE) {
    return NULL; // this means no data available
  }
  uint16_t free_slot = dst_notifyq_tail;
  if (dst_notifyq[free_slot].iid == iid) {
    dst_notifyq_free_cnt++;
    dst_notifyq_tail = (dst_notifyq_tail + 1) % DST_NOTIFYQ_SIZE;
    return &dst_notifyq[free_slot];
  }
  return NULL;
}

void dst_notifyq_reset_tails() {
    dst_notifyq_tail_nofree = dst_notifyq_tail;
}

RemoteOperand_t *dst_notifyq_getdst_nofree(uint8_t iid) {
  if (dst_notifyq_free_cnt == DST_NOTIFYQ_SIZE) {
    return NULL; // this means no data available
  }
  uint16_t slot = dst_notifyq_tail_nofree;
  if (dst_notifyq[slot].iid == iid) {
    dst_notifyq_tail_nofree = (dst_notifyq_tail_nofree + 1) % DST_NOTIFYQ_SIZE;
    return &dst_notifyq[slot];
  }
  return NULL;
}

RemoteOperand_t *dst_notifyq_find(uint8_t iid, uint8_t dst_hpu_id, uint16_t dst_cid) {
  if (dst_notifyq_free_cnt == DST_NOTIFYQ_SIZE) {
    return NULL; // there is no dst in the queue
  }
  uint16_t index = (dst_notifyq_head - 1) % DST_NOTIFYQ_SIZE;
  while (dst_notifyq[index].iid != iid
      || dst_notifyq[index].pos != dst_hpu_id
      || dst_notifyq[index].dst_cid != dst_cid) {
    if (index == dst_notifyq_tail) {
      return NULL;
    }
    index = (index - 1) % DST_NOTIFYQ_SIZE;
  }
  return &dst_notifyq[index];
}

// src store
volatile src_store_t src_store;

void src_store_init(void) {
  memset((void*)src_store.state, OPERAND_STATE_NONE, sizeof(src_store.state));
}

void src_store_reset_iop(uint8_t iid) {
  memset((void*)src_store.state[iid], OPERAND_STATE_NONE, sizeof(src_store.state[iid]));
}

void src_store_inits(uint8_t iid, OperandBundle_t *iop_src) {
  for (int i = 0; i < MAX_DST_VARS; i++) {
    uint8_t blk_start = 0;
    if (i < iop_src->len) { // used src
      src_store.cid_offset[iid][i] = iop_src->operand[i].cid_ofst;
      src_store.owner[iid][i] = iop_src->operand[i].pos;
      src_store.src_iid[iid][i] = iop_src->operand[i].iid;
      blk_start = iop_src->operand[i].block;
      for (int k = 0; k < blk_start; k++) {
        src_store.state[iid][i][k] = OPERAND_STATE_NONE;
      }
    }
  }
}

uint16_t src_store_get_waiting(uint8_t iid, uint8_t src_iid) {
  for (int i = 0; i < MAX_DST_VARS; i++) {
    for (int j = 0; j < MAX_VAR_BLKS; j++) {
      if (src_store.state[iid][i][j] == OPERAND_STATE_READ_PENDING
        && src_store.src_iid[iid][i] == src_iid) {
        return ((i << 8) + j);
      }
    }
  }
  return 0xFFFF;
}

uint8_t src_store_get_waiting_cnt(uint8_t iid) {
  uint8_t cnt = 0;
  for (int i = 0; i < MAX_DST_VARS; i++) {
    for (int j = 0; j < MAX_VAR_BLKS; j++) {
      if (src_store.state[iid][i][j] == OPERAND_STATE_READ_PENDING
        || src_store.state[iid][i][j] == OPERAND_STATE_DMA_PENDING) {
        cnt++;
      }
    }
  }
  return cnt;
}

void src_store_print(uint8_t iid) {
  for (int i = 0; i < MAX_DST_VARS; i++) {
    for (int j = 0; j < MAX_VAR_BLKS; j++) {
      if (src_store.state[iid][i][j] != OPERAND_STATE_NONE) {
        PLL_INF("ucore", "[HPU%d] src_store: IOP %d tid %d bid %d state: %d", phys_hpu_id, iid, i, j, src_store.state[iid][i][j]);
      }
    }
  }
  PLL_INF("ucore", "[HPU%d] end of src_store", phys_hpu_id);
}

// dst_store tracking all dst block to know when IOp is really done
volatile dst_store_t dst_store;

void dst_store_init(void) {
  // not sure we need to reset owner
  memset((void*)dst_store.owner, 0xFF, sizeof(dst_store.owner));
  memset((void*)dst_store.state, DST_STATE_WAIT_NOTIFY, sizeof(dst_store.state));
}

void dst_store_reset_iop(uint8_t iid) {
  // not sure we need to reset owner
  memset((void*)dst_store.owner[iid], 0xFF, sizeof(dst_store.owner[iid]));
  memset((void*)dst_store.state[iid], DST_STATE_WAIT_NOTIFY, sizeof(dst_store.state[iid]));
}

void dst_store_initd(uint8_t iid, OperandBundle_t *iop_dst) {
  for (int i = 0; i < MAX_DST_VARS; i++) {
    uint8_t blk_start = 0;
    if (i < iop_dst->len) { // used dst
      dst_store.owner[iid][i] = iop_dst->operand[i].pos;
      blk_start = iop_dst->operand[i].block;
    }
    for (int j = blk_start; j < MAX_VAR_BLKS; j++) {
      dst_store.state[iid][i][j] = DST_STATE_NONE;
    }
  }
}

uint16_t dst_store_get_owned(uint8_t iid, uint8_t hid) {
  for (int i = 0; i < MAX_DST_VARS; i++) {
    if (dst_store.owner[iid][i] == hid) {
      for (int j = 0; j < MAX_VAR_BLKS; j++) {
        if (dst_store.state[iid][i][j] == DST_STATE_WAIT_NOTIFY
          || dst_store.state[iid][i][j] == DST_STATE_READING) {
          return ((i << 8) + j);
        }
      }
    }
  }
  return 0xFFFF;
}

uint16_t dst_store_get_owned_cnt(uint8_t iid, uint8_t hid) {
  uint8_t cnt_owned = 0;
  uint8_t cnt_waiting = 0;
  for (int i = 0; i < MAX_DST_VARS; i++) {
    if (dst_store.owner[iid][i] == hid) {
      cnt_owned+=1;
      for (int j = 0; j < MAX_VAR_BLKS; j++) {
        if (dst_store.state[iid][i][j] == DST_STATE_WAIT_NOTIFY
          || dst_store.state[iid][i][j] == DST_STATE_READING) {
          cnt_waiting+=1;
        }
      }
    }
  }
  return (cnt_owned << 8 | cnt_waiting);
}

void dst_store_print(uint8_t iid) {
  for (int i = 0; i < 2; i++) {
    if (phys_hpu_id == 1) {
      char msg[10];
      for (int j = 0; j < 4; j++) {
        msg[j] = dst_store.state[iid][i][j] + '0';
      }
      msg[4] = '\0';
      PLL_ERR("dst_store_print", "[HPU%d] iop %d dst %d owner %d: %s", phys_hpu_id, iid, i, dst_store.owner[iid][i], msg);
      iOSAL_Task_SleepTicks(10);
    }
  }
}

// fct to locally close an IOp
void iop_teardown(uint8_t iid) {
  //flush dst_notifyq
  RemoteOperand_t *remote_operand = dst_notifyq_getdst(iid);
  while (remote_operand != NULL) {
    if (remote_operand->state == OPERAND_STATE_NONE) { // store+sync => notify on ack has not happened
      //PLL_DBG("ucore", "[HPU%d] teardown notify rdst iid %d pos %d state %d src %d dst %04x target %d",
      //    phys_hpu_id,
      //    iid,
      //    remote_operand->pos,
      //    remote_operand->state,
      //    remote_operand->src_cid,
      //    remote_operand->dst_cid,
      //    remote_operand->target_cid);
      remote_operand->state = OPERAND_STATE_READ_PENDING;
      vOSAL_EnterCritical();
      generate_ucore_notify(iid, remote_operand->pos, remote_operand->src_cid, remote_operand->dst_cid, remote_operand->target_cid);
      vOSAL_ExitCritical();
    }
    remote_operand = dst_notifyq_getdst(iid);
#ifdef UCORE_MHDMA_SIMU
    sleep(3);
#endif
  }
  //reset tails in remote dst queue
  dst_notifyq_reset_tails();
  //flush remote source queue
  src_store_reset_iop(iid);
  //reset mhdma_table for this IOp (all local notify & ld_b2b & wait)
  mhdma_table_reset_iop(iid);
  //cnt remote dst to be sent
  uint16_t dst_cnts = dst_store_get_owned_cnt(iid, phys_hpu_id);
  uint8_t dst_cnt_owned = (dst_cnts >> 8) & 0XFF;
  uint8_t dst_cnt_waiting = (dst_cnts & 0XFF);
  PLL_DBG("ucore", "[HPU%d] iop_teardown iid %d dst waiting: %d/%d iop_state %d/%d", phys_hpu_id, iid, dst_cnt_owned, dst_cnt_waiting, iop_state[iid].state, iop_state[iid].nb_hpu);

  //wait dst owned by local hpu but produced somewhere else
  //dst_store_print(iid);
  uint16_t non_resolved_owned_dst = dst_store_get_owned(iid, phys_hpu_id);
  while (non_resolved_owned_dst != 0xFFFF) {
    // wait until notify or read ct is received
    uint8_t tid = (non_resolved_owned_dst >> 8) & 0xFF;
    uint8_t bid = non_resolved_owned_dst & 0xFF;

    uint32_t wait_cnt = 0;
    while (dst_store.state[iid][tid][bid] != DST_STATE_RESOLVED) {
      if ((wait_cnt+1)%1000 == 0) {
        PLL_DBG("ucore", "[HPU%d] iop_teardown wait on dst iop %d tid %d bid %d - being resolved",
            phys_hpu_id,
            iid,
            tid,
            bid);
      }
      wait_cnt++;
      if (wait_cnt > 10000) {
#ifdef UCORE_MHDMA_SIMU
        sleep(10);
#else
        iOSAL_Task_SleepTicks(1);
#endif
      }
    }
    non_resolved_owned_dst = dst_store_get_owned(iid, phys_hpu_id);
  }

  // notify IOp locally done to all HPU but local one
  for (int i = 0; i < MAX_HPU_IN_CLUSTER; i++) {
    if ((i != phys_hpu_id) // Not local
        && ( ((node_mask >> i) & 0x1) == 0x1)) // active in cluster
    {
      vOSAL_EnterCritical();
      generate_iop_notify(iid, iop_state[iid].nb_hpu, i);
      vOSAL_ExitCritical();
#ifdef UCORE_MHDMA_SIMU
      sleep(1);
#endif
    }
  }
  vOSAL_EnterCritical();
  // update iop_state
  iop_state_node_ack(iid, iop_state[iid].nb_hpu);
  if (debug_intr_global_cnt%2 == 1) {
    print_ddr_debug(0xBEE20000 | ((uint32_t)iid << 8) | iop_state[iid].nb_hpu << 4 | iop_state[iid].state);
  }
  vOSAL_ExitCritical();

  // release b2b pool slot for this IOp
  if (iop_state[iid].state == IOP_STATE_DONE) {
    (void)b2b_pool_free(iid);
  }

  // reset all dst of iop for next execution of this iid
  dst_store_reset_iop(iid);
  // debug
  //dst_store_print(iid);
  //src_notifyq_print(iid);
  //src_notifyq_print(0);
  //dst_notifyq_print(iid);
  //b2b_pool_print();
}

// Ops functions body
// ============================================================================================= //
// Parse an IOp from stream
// returns the number of bytes used by parsed IOp
// Currently there is no way to report error back to host -> No check are implemented during parsing
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
     ImmediatBundle_t* imm) {

  // TODO Correctly invalidate cache_data
  // Should be handled outside of the function by the GCQ reader
  // HAL_INVALIDATE_CACHE_DATA( (uintptr_t)(stream), bytes_len);

  uint32_t stream_pos = 0;
  //1. Get header
  header->raw = stream[stream_pos];
  stream_pos++;

  if ((stream_pos*sizeof(uint32_t)) > iop_pending_bytes) {
    PLL_ERR("parse_iop", "not enough bytes after header");
    return 0;
  }

  //2. Get mapping
  mapping->raw = stream[stream_pos];
  stream_pos++;

  if ((stream_pos*sizeof(uint32_t)) > iop_pending_bytes) {
    PLL_ERR("parse_iop", "not enough bytes after mapping");
    return 0;
  }

  //3. Get list of destination operands
  uint32_t dst_pos = 0;
  do {
    operand_prop->raw = stream[stream_pos];
    stream_pos++;
    operand_addr->raw = stream[stream_pos];
    stream_pos++;

    if ((stream_pos*sizeof(uint32_t)) > iop_pending_bytes) {
      for (int i =0; i < 7; i++) {
          PLL_ERR("parse_iop", "Fail parse_iop dsts @%d -> 0x%x", i, Xil_EndianSwap32(stream[i]));
      }
      PLL_ERR("parse_iop", "not enough bytes to reach last destination");
      return 0;
    }

    // Fill current slot
    dst->operand[dst_pos].cid_ofst = operand_addr->operand_addr.base_cid;
    dst->operand[dst_pos].iid = operand_prop->operand_prop.iid;
    dst->operand[dst_pos].pos = operand_prop->operand_prop.pos;
    dst->operand[dst_pos].len = operand_prop->operand_prop.vec_size +1;
    dst->operand[dst_pos].block = operand_prop->operand_prop.block +1;
    dst_pos +=1;
  } while (!operand_prop->operand_prop.is_last);


  cur_iid = dst->operand[0].iid;
  cur_mapping.raw = mapping->raw;
  uint8_t nb_hpu = number_of_hpu(*mapping);
  vOSAL_EnterCritical();
  if (iop_state[cur_iid].state >= nb_hpu || iop_state[cur_iid].state == IOP_STATE_DONE) {
    iop_state[cur_iid].state  = IOP_STATE_RUNNING;
  }
  iop_state[cur_iid].nb_hpu = nb_hpu;
  if (debug_intr_global_cnt%2 == 1) {
    print_ddr_debug(0xBEE10000 | ((uint32_t)cur_iid << 8) | iop_state[cur_iid].nb_hpu << 4 | iop_state[cur_iid].state);
  }
  vOSAL_ExitCritical();
  PLL_INF("parse_iop", "[HPU%d] parse_iop starting iop %d (virt hid %d) state %d nb_hpu %d",
      phys_hpu_id,
      cur_iid,
      get_virt_of(phys_hpu_id, *mapping),
      iop_state[cur_iid].state,
      iop_state[cur_iid].nb_hpu);

  // Fill bundle length
  dst->len = dst_pos;
  dst_store_initd(cur_iid, dst);
  uint16_t dst_cnts = dst_store_get_owned_cnt(cur_iid, phys_hpu_id);
  uint8_t dst_cnt_owned = (dst_cnts >> 8) & 0XFF;
  uint8_t dst_cnt_waiting = (dst_cnts & 0XFF);
  PLL_DBG("parse_iop", "[HPU%d] parse_iop iop %d dst ct owned %d/%d",
          phys_hpu_id,
          cur_iid,
          dst_cnt_owned,
          dst_cnt_waiting);
  //dst_store_print(cur_iid);

  //4. Get list of source operands
  uint32_t src_pos = 0;
  do {
    operand_prop->raw = stream[stream_pos];
    stream_pos++;
    operand_addr->raw = stream[stream_pos];
    stream_pos++;
    if ((stream_pos*sizeof(uint32_t)) > iop_pending_bytes) {
      for (int i =0; i < 7; i++) {
          PLL_ERR("parse_iop", "Fail parse_iop srcs @%d -> 0x%x", i, Xil_EndianSwap32(stream[i]));
      }
      PLL_ERR("parse_iop", "not enough bytes to reach last source");
      return 0;
    }

    // Fill current slot
    src->operand[src_pos].cid_ofst = operand_addr->operand_addr.base_cid;
    src->operand[src_pos].iid = operand_prop->operand_prop.iid;
    src->operand[src_pos].pos = operand_prop->operand_prop.pos;
    src->operand[src_pos].len = operand_prop->operand_prop.vec_size +1;
    src->operand[src_pos].block = operand_prop->operand_prop.block +1;
    PLL_INF("ucore", "[HPU%d] parse_iop src %d.%d pos %d",
        phys_hpu_id,
        src_pos,
        src->operand[src_pos].block,
        src->operand[src_pos].pos);
    src_pos +=1;
  } while (!operand_prop->operand_prop.is_last);

  // Fill bundle length
  src->len = src_pos;
  src_store_inits(cur_iid, src);

  //5. Get list of immediat operands (if needed)
  if (header->header.has_imm) {
    uint32_t imm_pos = 0;
    do {
      // Read Imm header
      imm_header->raw =stream[stream_pos];
      stream_pos++;

      if ((stream_pos*sizeof(uint32_t)) > iop_pending_bytes) {
        for (int i =0; i < 7; i++) {
            PLL_ERR("parse_iop", "Fail parse_iop imms @%d -> 0x%x", i, Xil_EndianSwap32(stream[i]));
        }
        PLL_ERR("parse_iop", "not enough bytes to reach last immediate");
        return 0;
      }

      // Extract lsb from header
      imm->cst[imm_pos].msg[0] = imm_header->header.lsb_msg;

      uint32_t msg_pos = 1;
      while ( imm_header->header.block > ((8*sizeof(uint16_t))/MSG_WIDTH)*msg_pos) {
        uint32_t bfr;
        bfr =stream[stream_pos];
        stream_pos++;

        // Fill current slot
        imm->cst[imm_pos].msg[msg_pos] = bfr & 0xffff;
        imm->cst[imm_pos].msg[msg_pos+1] = (bfr>> 16) & 0xffff;
        msg_pos +=2;
      };
      // Fill immediat length
      imm->cst[imm_pos].len = msg_pos;

      imm_pos += 1;
    } while (!imm_header->header.is_last);
    // Fill immediat bundle length
    imm->len = imm_pos;
  } else {
    imm->len = 0;
  }
  return (stream_pos*sizeof(uint32_t));
}

uint32_t get_lookup(IOpHeader_t header, IOpMapping_t mapping, uint8_t hid, Lookup_t* lookup) {
  // Read translation offset for the given entry
  // Offset is computed based on max blk_width to correctly handle asym IOp such as Cmp
  uint8_t max_align = (header.header.dst_align > header.header.src_align)? header.header.dst_align: header.header.src_align;
  if (max_align >= FW_TABLE_ENTRY) {
    PLL_ERR("get_lookup", "max_align is wrong src %d dst %d", header.header.src_align, header.header.dst_align);
    lookup->len = 0;
    lookup->ptr = NULL;
    return 1;
  }

  // Get virtual id and check for usage
  uint8_t vid = get_virt_of(hid, mapping);
  if (!get_used_of(hid, mapping)) {
    PLL_ERR("get_lookup", "Current hid %x is not involved in the IOp mapping", hid);
  }
  uintptr_t integer_w_bucket = (uintptr_t) (DOP_LUT_ADDR + ((IOP_NUMBER * MAX_HPU_IN_CLUSTER * max_align) * sizeof(uint32_t)));
  uintptr_t iop_bucket = (uintptr_t) (integer_w_bucket + (header.header.opcode * MAX_HPU_IN_CLUSTER * sizeof(uint32_t)));
  uintptr_t entry_addr = (uintptr_t) (iop_bucket + vid * sizeof(uint32_t));

  if ( (entry_addr < DOP_LUT_ADDR) ||
       (entry_addr > (DOP_LUT_ADDR + MAX_FW_TABLE_ENTRY_OFST))) {
    PLL_ERR("get_lookup", "entry_addr is not in expected range %lx, max_align %d, opcode %d header %x", entry_addr, max_align, header.header.opcode, header.raw);
    lookup->len = 0;
    lookup->ptr = NULL;
    return 1;
  }
  HAL_INVALIDATE_CACHE_DATA(entry_addr, sizeof(uint32_t));
  size_t entry = *((uint32_t* ) entry_addr);
  if ( (entry < MAX_FW_TABLE_ENTRY_OFST) ||
       (entry > MAX_FW_SIZE) ) {
    PLL_ERR("get_lookup", "entry offset @%lx is wrong %lx must be within [%lx,%x]", entry_addr, entry, MAX_FW_TABLE_ENTRY_OFST, MAX_FW_SIZE);
    lookup->len = 0;
    lookup->ptr = NULL;
    return 1;
  }

  // Each translation slot start with translation unit length
  // Invalidate the associated word from the cache, retrieved the entry length
  // Then invalidate the translation slot entry
  HAL_INVALIDATE_CACHE_DATA( (uintptr_t) (DOP_LUT_ADDR + entry), sizeof(uint32_t));
  lookup->len = *((volatile uint32_t*) (DOP_LUT_ADDR + entry));
  lookup->ptr =  (volatile uint32_t*) (DOP_LUT_ADDR + entry + sizeof(uint32_t));
  HAL_INVALIDATE_CACHE_DATA( (uintptr_t) lookup->ptr, lookup->len*sizeof(uint32_t));

  return 0;
}

int read_remote_src(int blocking, OperandBundle_t *iop_src, uint8_t tid, uint8_t bid, uint32_t *dop_buffer, int dop_buffer_pos) {
  int return_value = 0;
  // remote source
  uint8_t src_iid = iop_src->operand[tid].iid;
  uint8_t src_hpu_id = iop_src->operand[tid].pos;
  uint16_t src_cid = iop_src->operand[tid].cid_ofst + bid;
  uint16_t target_cid = (tid << 8) | bid;
  //PLL_DBG("ucore", "[HPU%d] iop %d read remote src - src_iid %d src_hpu_id %d tid %d bid %d state %d",
  //    phys_hpu_id,
  //    cur_iid,
  //    src_iid,
  //    src_hpu_id,
  //    tid,
  //    bid,
  //    src_store.state[cur_iid][tid][bid]);
  //iOSAL_Task_SleepTicks(10);

  if (src_store.state[cur_iid][tid][bid] == OPERAND_STATE_NONE) {
    vOSAL_EnterCritical();
    uint16_t dst_cid = b2b_pool_pop(cur_iid);
    if (dst_cid == 0xFFFF) {
      PLL_ERR("patch_mem_dop", "Could not get a free slot in b2b_pool (%04x,%04x,%d)", b2b_pool_head, b2b_pool_tail, b2b_pool_free_cnt);
    }
    src_store.dst_cid[cur_iid][tid][bid] = dst_cid;
    src_store.state[cur_iid][tid][bid] = OPERAND_STATE_READ_PENDING;
    //PLL_DBG("ucore", "[HPU%d] iop %d src prepare - src_iid %d src_hpu_id %d src_cid %d dst_cid %d state %d",
    //    phys_hpu_id,
    //    cur_iid,
    //    src_iid,
    //    src_hpu_id,
    //    src_cid,
    //    dst_cid,
    //    src_store.state[cur_iid][tid][bid]);
    vOSAL_ExitCritical();
    //iOSAL_Task_SleepTicks(1);
  }
  // issue read immediately if src comes from a done iop or if iid = 0 which means src is coming from Host
  if ((iop_state[src_iid].state == IOP_STATE_DONE || src_iid == 0) && src_store.state[cur_iid][tid][bid] == OPERAND_STATE_READ_PENDING) {
    vOSAL_EnterCritical();
    generate_operand_read_req(
            cur_iid,
            CMD_SRC,
            src_hpu_id,
            src_cid,
            src_store.dst_cid[cur_iid][tid][bid],
            target_cid);
    src_store.state[cur_iid][tid][bid] = OPERAND_STATE_DMA_PENDING;
    //PLL_DBG("ucore", "[HPU%d] iop %d src read - src_iid %d src_hpu_id %d tg %d state %d",
    //    phys_hpu_id,
    //    cur_iid,
    //    src_iid,
    //    src_hpu_id,
    //    target_cid,
    //    src_store.state[cur_iid][tid][bid]);
    vOSAL_ExitCritical();
    //iOSAL_Task_SleepTicks(1);
  }

  if (blocking == 1) {
    // if we need to wait, flush
#ifndef UCORE_MHDMA_SIMU
    if ((dop_buffer_pos%DOP_BUFFER_SIZE) > MIN_DOP_FLUSH && src_store.state[cur_iid][tid][bid] != OPERAND_STATE_RESOLVED) {
      flush_dop_buffer_to_isc(dop_buffer, (dop_buffer_pos%DOP_BUFFER_SIZE));
      return_value = (dop_buffer_pos%DOP_BUFFER_SIZE);
    }
#endif
    uint32_t wait_cnt = 0;
    while (src_store.state[cur_iid][tid][bid] != OPERAND_STATE_RESOLVED) {
      // wait until notify or read ct is received
      if ((wait_cnt+1)%1000 == 0) {
        PLL_DBG("ucore", "[HPU%d] iop %d wait src: src_iid %d src_hid %d src_cid %d tg %d rc_irq %ld state %d",
            phys_hpu_id,
            cur_iid,
            src_iid,
            src_hpu_id,
            src_cid,
            target_cid,
            intr_readc_cnt,
            src_store.state[cur_iid][tid][bid]);
      }
      wait_cnt++;
      if (wait_cnt > 10000) {
#ifdef UCORE_MHDMA_SIMU
        sleep(10);
#else
        iOSAL_Task_SleepTicks(1);
#endif
      }
    }
  }

  return return_value;
}

int read_local_src(OperandBundle_t *iop_src, uint8_t tid, uint32_t *dop_buffer, int dop_buffer_pos) {
  int return_value = 0;
  // local source
  uint8_t src_iid = iop_src->operand[tid].iid;

  // exit immediately if src is available (from host or from done IOp)
  if (iop_state[src_iid].state == IOP_STATE_DONE || src_iid == 0) {
    return 0;
  }

  // if we need to wait, flush already translated DOp
#ifndef UCORE_MHDMA_SIMU
  if ((dop_buffer_pos%DOP_BUFFER_SIZE) > MIN_DOP_FLUSH) {
    flush_dop_buffer_to_isc(dop_buffer, (dop_buffer_pos%DOP_BUFFER_SIZE));
    return_value = (dop_buffer_pos%DOP_BUFFER_SIZE);
  }
#endif
  uint32_t wait_cnt = 0;
  while (iop_state[src_iid].state != IOP_STATE_DONE) {
    // wait until
    if ((wait_cnt+1)%1000 == 0) {
      PLL_DBG("ucore", "[HPU%d] iop %d wait iop: src_iid %d state %d",
          phys_hpu_id,
          cur_iid,
          src_iid,
          iop_state[src_iid].state);
    }
    wait_cnt++;
    if (wait_cnt > 10000) {
#ifdef UCORE_MHDMA_SIMU
        sleep(10);
#else
        iOSAL_Task_SleepTicks(1);
#endif
    }
  }

  return return_value;
}

// Patching function
// ============================================================================================= //
// Patch templated memory instruction
// NB: IOp have variable destination and source operands
// TODO Add error handling for out_of_range patching
int patch_mem_dop(DOpu_t *dop, OperandBundle_t *iop_dst, OperandBundle_t *iop_src, uint32_t *dop_buffer, int dop_buffer_pos) {
  int return_value = 0;
  //PLL_INF("patch_mem_dop", "[HPU%d] dop %08X opcode %d dop->mem.mode %d dop->mem.slot %04X tid %d bid %d",
  //        phys_hpu_id,
  //        dop->raw,
  //        dop->mem.opcode,
  //        dop->mem.mode,
  //        dop->mem.slot,
  //        (dop->mem.slot >> 8) & 0xff,
  //        dop->mem.slot & 0xff);

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
      dop->mem.mode = MEM_ADDR;
      if (iop_src->operand[tid].pos == phys_hpu_id) {
        // local access
        return_value = read_local_src(iop_src, tid, dop_buffer, dop_buffer_pos);
        dop->mem.slot = iop_src->operand[tid].cid_ofst + bid;
        src_store.state[cur_iid][tid][bid] = OPERAND_STATE_RESOLVED;
      } else {
        // blocking read on LD
        return_value = read_remote_src(1, iop_src, tid, bid, dop_buffer, dop_buffer_pos);
        //PLL_DBG("patch_mem_dop", "[HPU%d] iid %d LD SRC %d %d -> r%d (from %04x)",
        //        phys_hpu_id,
        //        cur_iid,
        //        tid,
        //        bid,
        //        dop->mem.rid,
        //        src_store.dst_cid[cur_iid][tid][bid]);

        dop->mem.slot = src_store.dst_cid[cur_iid][tid][bid];
      }
      break;
    }
    case MEM_DST: { // Dst template
      // Replace mem (tid,bid) by concrete addr and toggle the mode
      uint8_t tid = (dop->mem.slot >> 8) & 0xff;
      uint8_t bid = dop->mem.slot & 0xff;
      if (iop_dst->operand[tid].pos == phys_hpu_id) {
        // local access
        dop->mem.slot = iop_dst->operand[tid].cid_ofst + bid;
        dst_store.state[cur_iid][tid][bid] = DST_STATE_RESOLVED;
      } else {
        vOSAL_EnterCritical();
        uint16_t local_cid = b2b_pool_pop(cur_iid);
        vOSAL_ExitCritical();
        if (local_cid == 0xFFFF) {
          PLL_ERR("patch_mem_dop", "Could not get a free slot in b2b_pool (%04x,%04x,%d)", b2b_pool_head, b2b_pool_tail, b2b_pool_free_cnt);
          break;
        }
        uint8_t dst_hpu_id = iop_dst->operand[tid].pos;
        uint16_t dst_cid = iop_dst->operand[tid].cid_ofst + bid;
        RemoteOperand_t *remote_dst = dst_notifyq_pop(cur_iid);
        if (remote_dst == NULL) {
          PLL_ERR("patch_mem_dop", "Could not get a free slot in dst_notifyq (%04x,%04x,%d)", dst_notifyq_head, dst_notifyq_tail, dst_notifyq_free_cnt);
          break;
        }
        remote_dst->iid = cur_iid;
        remote_dst->pos = dst_hpu_id;
        remote_dst->dst_cid = (tid << 8) | bid;
        remote_dst->src_cid = local_cid;
        remote_dst->state = OPERAND_STATE_NONE;
        remote_dst->target_cid = dst_cid;

        //PLL_DBG("patch_mem_dop", "[HPU%d] dst store iid %d pos %d src(b2b) %d dst %d(%d/%d) target %d",
        //        phys_hpu_id,
        //        cur_iid,
        //        dst_hpu_id,
        //        remote_dst->src_cid,
        //        remote_dst->dst_cid,
        //        tid,
        //        bid,
        //        remote_dst->target_cid);

        dop->mem.slot = local_cid;
        // add sync to notify DST asap !!
        // this tells loop in main task to add SYNC
        return_value = 0x00010000;
      }
      dop->mem.mode = MEM_ADDR;
      break;
    }
  }
  return return_value;
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

uint16_t get_raw_ct_id(DOpu_t *dop) {
  uint16_t raw_ct_id = 0;
  switch (dop->ucore.mode) {
    case MEM_ADDR: { // Already an explicit ADDR -> No need to patch
      raw_ct_id = dop->ucore.slot;
      break;
    }
    case MEM_HEAP: { // Heap template
      // Replace Heap offset by concrete addr and toggle the mode
      raw_ct_id = HEAP_START_SLOT - dop->ucore.slot;
      dop->ucore.mode = MEM_ADDR;
      break;
    }
  }
  return raw_ct_id;
}


// Process ucore instructions
int process_ucore_dop(DOpu_t *dop, OperandBundle_t *iop_src, uint32_t *dop_buffer, int dop_buffer_pos) {
  int return_value = 0;
  //PLL_DBG("process_ucore_dop", "[HPU%d] %08x", phys_hpu_id, dop->raw);
  uint8_t current_flag = dop->ucore.flag;
  switch (dop->ucore.opcode & 0xF) {
    case DOPS_NOTIFY: {
      uint16_t raw_ct_id = get_raw_ct_id(dop);
      volatile mhdma_element_t *current_elt = &mhdma_table[cur_iid][current_flag];
      mhdma_table_state[cur_iid][current_flag] = MHDMA_STATE_NOTIFY_PENDING;
      current_elt->src_ct_id = raw_ct_id;
      current_elt->slave_hpu_id = phys_hpu_id;
      current_elt->master_hpu_id = get_phys_of(dop->ucore.hid, cur_mapping);

      //replace notify by sync DOp
      dop->sync.flag = current_flag;
      dop->sync.opcode = SYNC_OPCODE;
      dop->sync.is_inner = 1;
      dop->sync.iid = cur_iid;
      dop->sync._pad = 0;

      break;
    }
    case DOPS_WAIT: {
      bool data_required = (dop->ucore.hid != 0);
      // if we need to wait, flush
#ifndef UCORE_MHDMA_SIMU
      if ((dop_buffer_pos%DOP_BUFFER_SIZE) > MIN_DOP_FLUSH
          && ((data_required && mhdma_table_state[cur_iid][current_flag] < MHDMA_STATE_RESOLVED)
          || (!data_required && mhdma_table_state[cur_iid][current_flag] < MHDMA_STATE_RECEIVED))) {
        flush_dop_buffer_to_isc(dop_buffer, (dop_buffer_pos%DOP_BUFFER_SIZE));
        return_value = (dop_buffer_pos%DOP_BUFFER_SIZE);
      }
#endif
      uint32_t wait_cnt = 0;
      while (  (data_required && mhdma_table_state[cur_iid][current_flag] < MHDMA_STATE_RESOLVED)
            || (!data_required && mhdma_table_state[cur_iid][current_flag] < MHDMA_STATE_RECEIVED) ) {
        // wait until notify or read ct is received
        if ((wait_cnt+1)%1000 == 0) {
          PLL_DBG("ucore", "[HPU%d] dop wait on iop_id %d flag %d state %d", phys_hpu_id, cur_iid, dop->ucore.flag, mhdma_table_state[cur_iid][current_flag]);
        }
        wait_cnt++;
        if (wait_cnt > 10000) {
#ifdef UCORE_MHDMA_SIMU
          sleep(12);
#else
          iOSAL_Task_SleepTicks(1);
#endif
        }
      }
      // This DOp needs to be removed from DOp stream given to ISC
      return_value = 0x8000 | return_value;
      break;
    }
    case DOPS_LD_B2B: {
      if (current_flag > 0) { // F0 is reserved for pre-load of sources
        volatile mhdma_element_t *current_elt = &mhdma_table[cur_iid][current_flag];
        uint16_t raw_ct_id = get_raw_ct_id(dop);
        current_elt->dst_ct_id = raw_ct_id;
        current_elt->master_hpu_id = phys_hpu_id;
        // Here main task reads intermediate ct state and modifies it
        // so we do not want an ISR to update it in parallel
        vOSAL_EnterCritical();
        switch (mhdma_table_state[cur_iid][current_flag]) {
          case MHDMA_STATE_RESOLVED: break; // nothing to do
          case MHDMA_STATE_RECEIVED: { // must read asap
            mhdma_table_state[cur_iid][current_flag] = MHDMA_STATE_READING;
            PLL_DBG("process_ucore_dop", "[HPU%d] generate user read on iid %d flag %d (%04x -> %04x)",
                    phys_hpu_id,
                    cur_iid,
                    current_flag,
                    current_elt->src_ct_id,
                    current_elt->dst_ct_id);
            generate_read_req(cur_iid, current_flag);
            break;
          }
          default: { // must wait for notify
            mhdma_table_state[cur_iid][current_flag] = MHDMA_STATE_LB2B_WAITING;
            PLL_DBG("process_ucore_dop", "[HPU%d] ld b2b waiting on iid %d flag %d (?? -> %04x)",
                    phys_hpu_id,
                    cur_iid,
                    current_flag,
                    current_elt->dst_ct_id);
            break;
          }
        }
        vOSAL_ExitCritical();
      } else { // this is a remote src
        if (dop->ucore.mode != MEM_HEAP) {
          PLL_ERR("process_ucore_dop", "[HPU%d] LD_B2B with flag 0 but not about a source!! %08x", phys_hpu_id, dop->raw);
        } else {
          uint8_t tid = (dop->ucore.slot >> 8) & 0xff;
          uint8_t bid = dop->ucore.slot & 0xff;
          // non-blocking read on LD_B2B
          return_value = read_remote_src(0, iop_src, tid, bid, dop_buffer, dop_buffer_pos);
        }
      }
      // This DOp needs to be removed from DOp stream given to ISC
      return_value = 0x8000 | return_value;
      break;
    }
  }
  return return_value;
}

// Global template patching
// ============================================================================================= //

// Utilities function to patch DOp
int patch_dop(DOpu_t *dop,
               OperandBundle_t *dst,
               OperandBundle_t *src,
               ImmediatBundle_t *imm,
               uint32_t *dop_buffer,
               int dop_buffer_pos) {
  DOpKind_t kind = get_kind(dop);
  int return_value = 0;

  switch (kind) {
    case DOPK_MEM: {
      return_value = patch_mem_dop(dop, dst, src, dop_buffer, dop_buffer_pos);
      break;
    }
    case DOPK_ARITH: {
      // Check if its a scalar arith operation
      if ((dop->raw_field.opcode & IMM_FLAG) == IMM_FLAG) {
        patch_imm_dop(dop, imm);
      }
      break;
    }
    case DOPK_UCORE: {
      return_value = process_ucore_dop(dop, src, dop_buffer, dop_buffer_pos);
      break;
    }
    case DOPK_PBS: { // Nothing to do
      break;
    }
  }
  return return_value;
}

// Utilites function
// ============================================================================================= //
// Convenience function to extract kind for DOp union
DOpKind_t get_kind(DOpu_t *dop) {
  uint8_t opcode = dop->raw_field.opcode;

  return ((DOpKind_t) (opcode >> 4));
}

// Convenience function to extract sub-type of Sync DOp
DOpSync_t get_sync_opcode(DOpu_t *dop) {
  uint8_t opcode = dop->raw_field.opcode;

  return ((DOpSync_t) (opcode & 0xF));
}

// Get virt_id of given phys_id
uint8_t get_virt_of(uint8_t pid, IOpMapping_t mapping) {
  return (mapping.raw >>((4*pid)+1)) & 0x7;
}
// Get used bit for a given phys_id
uint8_t get_used_of(uint8_t pid, IOpMapping_t mapping) {
  return (mapping.raw >>(4*pid)) & 0x1;
}
// Get phys_id for a given virt_id
uint8_t get_phys_of(uint8_t vid, IOpMapping_t mapping) {
  for (int i = 0; i < 8; i++) {
    if ( ((mapping.raw >>((4*i)+1)) & 0x7) == vid && get_used_of(i, mapping) == 1) {
      return i;
    }
  }
  return 0xFF;
}
uint8_t number_of_hpu(IOpMapping_t mapping) {
  uint8_t hpu_cnt = 0;
  for (int i = 0; i<8; i++) {
    if (get_used_of(i, mapping) == 1) {
      hpu_cnt++;
    }
  }
  return hpu_cnt;
}
