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
#include "ucore.h"
#include "mhdma_driver/mhdma_driver.h"

uint8_t cur_iid;
IOpMapping_t cur_mapping;
uint8_t phys_hpu_id;
mhdma_element_t mhdma_table[IOP_ID_MAX_COUNT][FLAG_MAX_COUNT];

// IOP state
iop_state_t iop_state[IOP_ID_MAX_COUNT];

void iop_state_init(void) {
  for (int i = 0; i < IOP_ID_MAX_COUNT; i++) {
    iop_state[i].state  = IOP_STATE_UNKNOWN;
    iop_state[i].nb_hpu = 0xFF;
  }
}

void iop_state_node_ack(uint8_t iid, uint8_t nb_hpu) {
  printf("iop_state_node_ack iid %d nb_hpu %d (state %d)\n", iid, nb_hpu, iop_state[iid].state);
  if ((iop_state[iid].state == IOP_STATE_UNKNOWN)
   || (iop_state[iid].state == IOP_STATE_RUNNING)
   || (iop_state[iid].state == IOP_STATE_DONE)) {
    iop_state[iid].state = nb_hpu - 1;
  } else {
    iop_state[iid].state -= 1;
  }
  printf("iop_state_node_ack iid %d state %d nb_hpu %d\n", iid, iop_state[iid].state, iop_state[iid].nb_hpu);
}

// B2B Pool
uint8_t b2b_pool[B2B_POOL_SIZE];
uint16_t b2b_pool_head;
uint16_t b2b_pool_tail;
uint16_t b2b_pool_free_cnt;

void b2b_pool_init(void) {
  for (int i = 0; i < B2B_POOL_SIZE; i++) {
    b2b_pool[i] = 0xFF;
  }
  b2b_pool_head = 0;
  b2b_pool_tail = 0;
  b2b_pool_free_cnt = B2B_POOL_SIZE;
}

uint16_t b2b_pool_pop(uint8_t iid) {
  if (b2b_pool_free_cnt == 0) {
    return 0xFFFF; // this means no more empty slot
  }
  uint16_t alloc_slot = b2b_pool_head;
  b2b_pool_free_cnt--;
  b2b_pool_head = (b2b_pool_head + 1) % B2B_POOL_SIZE;
  b2b_pool[alloc_slot] = iid;
  return alloc_slot;
}

uint16_t b2b_pool_free(uint8_t iid) {
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
    b2b_pool[b2b_pool_tail] = 0xFF;
    b2b_pool_tail = (b2b_pool_tail + 1) % B2B_POOL_SIZE;
    b2b_pool_free_cnt++;
    free_cnt++;
  }
  return free_cnt;
}

void b2b_pool_print(void) {
  printf("b2b_pool head %d (iid %d) tail %d (iid %d)free %d\n",
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
uint16_t dst_notifyq_free_cnt;

void dst_notifyq_init(void) {
  for (int i = 0; i < DST_NOTIFYQ_SIZE; i++) {
    dst_notifyq[i].state = OPERAND_STATE_NONE;
  }
  dst_notifyq_head = 0;
  dst_notifyq_tail = 0;
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
  printf("dst_notifyq head %d tail %d free %d\n", dst_notifyq_head, dst_notifyq_tail, dst_notifyq_free_cnt);
  uint16_t index = (dst_notifyq_head - 1) % DST_NOTIFYQ_SIZE;
  while (dst_notifyq[index].iid == iid) {
    printf("dst_notifyq iid %d pos %d state %d src %d dst %04x target %d\n",
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

RemoteOperand_t *dst_notifyq_find(uint8_t iid, uint8_t dst_hpu_id, uint16_t dst_cid) {
  if (dst_notifyq_free_cnt == DST_NOTIFYQ_SIZE) {
    return NULL; // there is no dst in the queue
  }
  uint16_t index = dst_notifyq_head;
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

// src notify queue
RemoteOperand_t src_notifyq[SRC_NOTIFYQ_SIZE];
uint16_t src_notifyq_head;
uint16_t src_notifyq_tail;
uint16_t src_notifyq_free_cnt;

void src_notifyq_init(void) {
  for (int i = 0; i < SRC_NOTIFYQ_SIZE; i++) {
    src_notifyq[i].state = OPERAND_STATE_NONE;
    src_notifyq[i].iid = 0;
  }
  src_notifyq_head = 0;
  src_notifyq_tail = 0;
  src_notifyq_free_cnt = SRC_NOTIFYQ_SIZE;
}

RemoteOperand_t *src_notifyq_pop(uint8_t iid) {
  if (src_notifyq_free_cnt == 0) {
    return NULL; // this means no more empty slot
  }
  uint16_t alloc_slot = src_notifyq_head;
  src_notifyq_free_cnt--;
  src_notifyq_head = (src_notifyq_head + 1) % SRC_NOTIFYQ_SIZE;
  src_notifyq[alloc_slot].iid = iid;
  return &src_notifyq[alloc_slot];
}

uint16_t src_notifyq_free(uint8_t iid) {
  if (src_notifyq_free_cnt == SRC_NOTIFYQ_SIZE) {
    return 0; // this means there is nothing to free
  }
  uint16_t free_cnt = 0;
  while ((src_notifyq[src_notifyq_tail].iid == iid
        || src_notifyq[src_notifyq_tail].iid == 0)
      && src_notifyq_free_cnt < SRC_NOTIFYQ_SIZE) {
    src_notifyq[src_notifyq_tail].state = OPERAND_STATE_NONE;
    src_notifyq[src_notifyq_tail].iid = 0;
    src_notifyq_tail = (src_notifyq_tail + 1) % SRC_NOTIFYQ_SIZE;
    src_notifyq_free_cnt++;
    free_cnt++;
  }
  return free_cnt;
}

RemoteOperand_t *src_notifyq_find_by_state(uint8_t iid, uint8_t state) {
  if (src_notifyq_free_cnt == SRC_NOTIFYQ_SIZE) {
    return NULL; // there is no src in the queue
  }
  uint16_t index = (src_notifyq_head - 1) % SRC_NOTIFYQ_SIZE;
  while ((src_notifyq[index].iid != iid)
      && (src_notifyq[index].state != state)) {
    if (index == src_notifyq_tail) {
      return NULL;
    }
    index = (index - 1) % SRC_NOTIFYQ_SIZE;
  }
  return &src_notifyq[index];
}

void src_notifyq_print(uint8_t iid) {
  printf("src_notifyq head %d tail %d free %d\n", src_notifyq_head, src_notifyq_tail, src_notifyq_free_cnt);
  uint16_t index = (src_notifyq_head - 1) % SRC_NOTIFYQ_SIZE;
  while (src_notifyq[index].iid == iid) {
    printf("src_notifyq iid %d pos %d state %d src %d dst %d\n",
        iid,
        src_notifyq[index].pos,
        src_notifyq[index].state,
        src_notifyq[index].src_cid,
        src_notifyq[index].dst_cid);
    if (index == src_notifyq_tail) {
      break;
    }
    index = (index - 1) % SRC_NOTIFYQ_SIZE;
  }
}

// dst_store tracking all dst block to know when IOp is really done
dst_store_t dst_store;

void dst_store_init(void) {
  for (int k = 0; k < IOP_ID_MAX_COUNT; k++) {
    for (int i = 0; i < MAX_DST_VARS; i++) {
      dst_store.owner[k][i] = 0xFF;
      for (int j = 0; j < MAX_VAR_BLKS; j++) {
        dst_store.state[k][i][j] = DST_STATE_WAIT_NOTIFY;
      }
    }
  }
}

void dst_store_reset_iop(uint8_t iid) {
  for (int i = 0; i < MAX_DST_VARS; i++) {
    dst_store.owner[iid][i] = 0xFF;
    for (int j = 0; j < MAX_VAR_BLKS; j++) {
      dst_store.state[iid][i][j] = DST_STATE_WAIT_NOTIFY;
    }
  }
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

void dst_store_print(uint8_t iid) {
  for (int i = 0; i < MAX_DST_VARS; i++) {
    if (dst_store.owner[iid][i] != 0xFF) {
      printf("dst_store: IOP %d dst %d owner %d: ", iid, i, dst_store.owner[iid][i]);
      for (int j = 0; j < 7; j++) {
        printf("%d", dst_store.state[iid][i][j]);
      }
      printf("\n");
    }
  }
}

// fct to locally close an IOp
void iop_teardown(uint8_t iid) {
  //flush dst_notifyq
  RemoteOperand_t *remote_operand = dst_notifyq_getdst(iid);
  while (remote_operand != NULL) {
    printf("iop_teardown remote_operand iid %d pos %d state %d src %d dst %04x target %d\n",
        iid,
        remote_operand->pos,
        remote_operand->state,
        remote_operand->src_cid,
        remote_operand->dst_cid,
        remote_operand->target_cid);
    remote_operand->state = OPERAND_STATE_READ_PENDING;
    generate_ucore_notify(iid, remote_operand->pos, remote_operand->src_cid, remote_operand->dst_cid, remote_operand->target_cid);
    remote_operand = dst_notifyq_getdst(iid);
    sleep(3);
  }
  //flush remote source queue
  uint16_t src_free_cnt = src_notifyq_free(iid);
  printf("iop_teardown free source slots: %d\n", src_free_cnt);

  //wait dst owned by local hpu but produced somewhere else
  dst_store_print(iid);
  uint16_t non_resolved_owned_dst = dst_store_get_owned(iid, phys_hpu_id);
  while (non_resolved_owned_dst != 0xFFFF) {
    // wait until notify or read ct is received
    //iOSAL_Task_SleepTicks(1);
    uint8_t tid = (non_resolved_owned_dst >> 8) & 0xFF;
    uint8_t bid = non_resolved_owned_dst & 0xFF;
    while (dst_store.state[iid][tid][bid] != DST_STATE_RESOLVED) {
      printf("iop_teardown wait on iop %d hpu_id %d tid %d bid %d - being resolved\n",
          iid,
          phys_hpu_id,
          tid,
          bid);
      sleep(10);
    }
    non_resolved_owned_dst = dst_store_get_owned(iid, phys_hpu_id);
  }

  // notify IOp locally done to all HPU but local one
  for (int i = 0; i < MAX_HPU_IN_CLUSTER; i++) {
    if (i != phys_hpu_id) {
      generate_iop_notify(iid, iop_state[iid].nb_hpu, i);
      sleep(1);
    }
  }
  // update iop_state
  iop_state_node_ack(iid, iop_state[iid].nb_hpu);

  // release b2b pool slot for this IOp
  if (iop_state[iid].state == IOP_STATE_DONE) {
    uint16_t b2b_free_cnt = b2b_pool_free(iid);
    printf("iop_teardown free b2b_pool slots: %d\n", b2b_free_cnt);
  }

  // reset all dst of iop for next execution of this iid
  dst_store_reset_iop(iid);
  // debug
  dst_store_print(iid);
  src_notifyq_print(iid);
  src_notifyq_print(0);
  dst_notifyq_print(iid);
  b2b_pool_print();
}

// Ops functions body
// ============================================================================================= //
// Parse an IOp from stream
// returns the number of bytes used by parsed IOp
// Currently there is no way to report error back to host -> No check are implemented during parsing
// TODO implement error return through ACKQ and implement check during parsing
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
  printf("IOP HDR opcode %d src_align %d dst_align %d\n",
	header->header.opcode,
	header->header.src_align,
	header->header.dst_align);

  //2. Get mapping
  mapping->raw = stream[stream_pos];
  stream_pos++;

  if ((stream_pos*sizeof(uint32_t)) > iop_pending_bytes) {
    PLL_ERR("parse_iop", "not enough bytes after mapping");
    return 0;
  }
  printf("IOP mapping 0 %d:%d 1 %d:%d 2 %d:%d\n",
	mapping->header.used_0,
	mapping->header.phys_0,
	mapping->header.used_1,
	mapping->header.phys_1,
	mapping->header.used_2,
	mapping->header.phys_2);

  //3. Get list of destination operands
  uint32_t dst_pos = 0;
  do {
    operand_prop->raw = stream[stream_pos];
    stream_pos++;
    operand_addr->raw = stream[stream_pos];
    stream_pos++;

    if ((stream_pos*sizeof(uint32_t)) > iop_pending_bytes) {
      for (int i =0; i < 7; i++) {
          PLL_ERR("parse_iop", "Fail parse_iop dsts", "@%d -> 0x%x", i, Xil_EndianSwap32(stream[i]));
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
    printf("DST iid %d pos %d block_nb %d cid_ofst %d\n",
	dst->operand[dst_pos].iid,
	dst->operand[dst_pos].pos,
        dst->operand[dst_pos].block,
 	dst->operand[dst_pos].cid_ofst);
    dst_pos +=1;
  } while (!operand_prop->operand_prop.is_last);


  cur_iid = dst->operand[0].iid;
  cur_mapping.raw = mapping->raw;
  iop_state[cur_iid].state  = IOP_STATE_RUNNING;
  iop_state[cur_iid].nb_hpu = number_of_hpu(*mapping);
  printf("parse_iop starting iop %d state %d nb_hpu %d\n", cur_iid, iop_state[cur_iid].state, iop_state[cur_iid].nb_hpu);
  // Fill bundle length
  dst->len = dst_pos;
  dst_store_initd(cur_iid, dst);

  //4. Get list of source operands
  uint32_t src_pos = 0;
  do {
    operand_prop->raw = stream[stream_pos];
    stream_pos++;
    operand_addr->raw = stream[stream_pos];
    stream_pos++;
    if ((stream_pos*sizeof(uint32_t)) > iop_pending_bytes) {
      for (int i =0; i < 7; i++) {
          PLL_ERR("parse_iop", "Fail parse_iop srcs", "@%d -> 0x%x", i, Xil_EndianSwap32(stream[i]));
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
    printf("SRC iid %d pos %d block_nb %d cid_ofst %d\n",
	src->operand[src_pos].iid,
	src->operand[src_pos].pos,
        src->operand[src_pos].block,
 	src->operand[src_pos].cid_ofst);
    src_pos +=1;
  } while (!operand_prop->operand_prop.is_last);

  // Fill bundle length
  src->len = src_pos;

  //5. Get list of immediat operands (if needed)
  if (header->header.has_imm) {
    uint32_t imm_pos = 0;
    do {
      // Read Imm header
      imm_header->raw =stream[stream_pos];
      stream_pos++;

      if ((stream_pos*sizeof(uint32_t)) > iop_pending_bytes) {
        for (int i =0; i < 7; i++) {
            PLL_ERR("parse_iop", "Fail parse_iop imms", "@%d -> 0x%x", i, Xil_EndianSwap32(stream[i]));
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
      dop->mem.mode = MEM_ADDR;
      if (iop_src->operand[tid].pos == phys_hpu_id) {
        // local access
        dop->mem.slot = iop_src->operand[tid].cid_ofst + bid;
      } else {
        // remote source
        uint8_t src_iid = iop_src->operand[tid].iid;
        uint8_t src_hpu_id = iop_src->operand[tid].pos;
        uint8_t src_cid = iop_src->operand[tid].cid_ofst + bid;
        RemoteOperand_t *remote_src = src_notifyq_pop(src_iid);
        if (remote_src == NULL) {
          PLL_ERR("patch_mem_dop", "Could not get a free slot in src_notifyq (%04x,%04x,%d)", src_notifyq_head, src_notifyq_tail, src_notifyq_free_cnt);
          break;
        }
        remote_src->iid = src_iid;
        remote_src->pos = src_hpu_id;
        remote_src->src_cid = src_cid;
        remote_src->state = OPERAND_STATE_NONE;

        // if state is anything else than NONE it means
        // b2b_pool slot was already allocated and that
        // iop is not done or DMA read is already pending
        // => doing something here only if state is None
        if (remote_src->state == OPERAND_STATE_NONE) {
          uint16_t dst_cid = b2b_pool_pop(cur_iid);
          if (dst_cid == 0xFFFF) {
            PLL_ERR("patch_mem_dop", "Could not get a free slot in b2b_pool (%04x,%04x,%d)", b2b_pool_head, b2b_pool_tail, b2b_pool_free_cnt);
            break;
          }
          remote_src->dst_cid = dst_cid;
          // issue read immediately if src comes from a done iop or if iid = 0 which means src is coming from Host
          if (iop_state[src_iid].state == IOP_STATE_DONE || src_iid == 0) {
            remote_src->state = OPERAND_STATE_DMA_PENDING;
            generate_operand_read_req(src_iid, CMD_SRC, remote_src->pos, remote_src->src_cid, remote_src->dst_cid, 0);
          } else {
            remote_src->state = OPERAND_STATE_READ_PENDING;
          }
          src_notifyq_print(src_iid);
        }

        while (remote_src->state != OPERAND_STATE_RESOLVED) {
          // wait until notify or read ct is received
          //iOSAL_Task_SleepTicks(1);
          printf("iop %d wait on remote src - src_iid %d src_hpu_id %d src_cid %d\n",
              cur_iid,
              src_iid,
              src_hpu_id,
              src_cid);
          sleep(10);
        }
        dop->mem.slot = remote_src->dst_cid;
      }
      break;
    }
    case MEM_DST: { // Dst template
      // Replace mem (tid,bid) by concrete addr and toggle the mode
      uint8_t tid = (dop->mem.slot >> 8) & 0xff;
      uint8_t bid = dop->mem.slot & 0xff;
      printf("iop %d mem_dst %08x %04x %d %d\n", cur_iid, dop->raw, dop->mem.slot, tid, bid);
      if (iop_src->operand[tid].pos == phys_hpu_id) {
        // local access
        dop->mem.slot = iop_dst->operand[tid].cid_ofst + bid;
        dst_store.state[cur_iid][tid][bid] = DST_STATE_RESOLVED;
      } else {
        uint16_t local_cid = b2b_pool_pop(cur_iid);
        if (local_cid == 0xFFFF) {
          PLL_ERR("patch_mem_dop", "Could not get a free slot in b2b_pool (%04x,%04x,%d)", b2b_pool_head, b2b_pool_tail, b2b_pool_free_cnt);
          break;
        }
        uint8_t dst_hpu_id = iop_dst->operand[tid].pos;
        uint8_t dst_cid = iop_dst->operand[tid].cid_ofst + bid;
        RemoteOperand_t *remote_dst = dst_notifyq_pop(cur_iid);
        if (remote_dst == NULL) {
          PLL_ERR("patch_mem_dop", "Could not get a free slot in dst_notifyq (%04x,%04x,%d)", src_notifyq_head, src_notifyq_tail, src_notifyq_free_cnt);
          break;
        }
        remote_dst->iid = cur_iid;
        remote_dst->pos = dst_hpu_id;
        remote_dst->dst_cid = (tid << 8) | bid;
        remote_dst->src_cid = local_cid;
        remote_dst->state = OPERAND_STATE_NONE;
        remote_dst->target_cid = dst_cid;
        dop->mem.slot = local_cid;
        dst_notifyq_print(cur_iid);
      }
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

uint16_t get_raw_ct_id(DOpu_t *dop) {
  uint16_t raw_ct_id = 0;
  switch (dop->ucore.mode) {
    case MEM_ADDR: { // Already an explicit ADDR -> No need to patch
      raw_ct_id = dop->ucore.slot;
      break;
    }
    case MEM_HEAP: { // Heap templateb
      // Replace Heap offset by concrete addr and toggle the mode
      raw_ct_id = HEAP_START_SLOT - dop->ucore.slot;
      dop->ucore.mode = MEM_ADDR;
      break;
    }
  }
  return raw_ct_id;
}


// Process ucore instructions
int process_ucore_dop(DOpu_t *dop) {
  switch (dop->ucore.opcode & 0xF) {
    case DOPS_NOTIFY: {
      uint16_t raw_ct_id = get_raw_ct_id(dop);
      mhdma_element_t *current_elt = &mhdma_table[cur_iid][dop->ucore.flag];
      current_elt->state = MHDMA_STATE_NOTIFY_PENDING;
      current_elt->src_ct_id = raw_ct_id;
      current_elt->slave_hpu_id = phys_hpu_id;
      current_elt->master_hpu_id = get_phys_of(dop->ucore.hid, cur_mapping);
      printf("process_ucore_dop DOPS_NOTIFY iid %d slave %d master %d state %d\n",
          cur_iid,
          current_elt->slave_hpu_id,
          current_elt->master_hpu_id,
          current_elt->state);

      //replace notify by sync DOp
      dop->sync.flag = dop->ucore.flag;
      dop->sync.opcode = SYNC_OPCODE;
      dop->sync.is_inner = 1;
      dop->sync.iid = cur_iid;

      break;
    }
    case DOPS_WAIT: {
      mhdma_element_t *current_elt = &mhdma_table[cur_iid][dop->ucore.flag];
      bool data_required = (dop->ucore.hid != 0);

      while (  (data_required && current_elt->state < MHDMA_STATE_RESOLVED)
            || (!data_required && current_elt->state < MHDMA_STATE_RECEIVED) ) {
        // wait until notify or read ct is received
        //iOSAL_Task_SleepTicks(1);
        printf("wait on iop_id %d flag %d state %d\n", cur_iid, dop->ucore.flag, current_elt->state);
        sleep(10);
      }
      // This DOp needs to be removed from DOp stream given to ISC
      return 1;
      break;
    }
    case DOPS_LD_B2B: {
      mhdma_element_t *current_elt = &mhdma_table[cur_iid][dop->ucore.flag];
      uint16_t raw_ct_id = get_raw_ct_id(dop);
      current_elt->dst_ct_id = raw_ct_id;
      current_elt->master_hpu_id = phys_hpu_id;
      // todo: check if DOp really contains from HPU id
      current_elt->slave_hpu_id = dop->ucore.hid;
      switch (current_elt->state) {
        case MHDMA_STATE_RESOLVED: break; // nothing to do
        case MHDMA_STATE_RECEIVED: { // must read asap
          current_elt->state = MHDMA_STATE_READING;
          generate_read_req(cur_iid, dop->ucore.flag);
          break;
        }
        default: { // must wait for notify
          current_elt->state = MHDMA_STATE_LB2B_WAITING;
          break;
        }
      }
      // This DOp needs to be removed from DOp stream given to ISC
      return 1;
      break;
    }
  }
  return 0;
}

// Global template patching
// ============================================================================================= //

// Utilities function to patch DOp
int patch_dop(DOpu_t *dop,
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
    case DOPK_UCORE: {
      if (process_ucore_dop(dop)) {
        return 1;
      }
      break;
    }
    case DOPK_PBS: { // Nothing to do
      break;
    }
  }
  return 0;
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
// Get phys_id for a given virt_id
uint8_t get_phys_of(uint8_t vid, IOpMapping_t mapping) {
  for (int i = 0; i < 8; i++) {
    if ( ((mapping.raw >>((4*i)+1)) & 0x7) == vid ) {
      return i;
    }
  }
  return 0xFF;
}
// Get used bit for a given phys_id
uint8_t get_used_of(uint8_t pid, IOpMapping_t mapping) {
  return (mapping.raw >>(4*pid)) & 0x1;
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

