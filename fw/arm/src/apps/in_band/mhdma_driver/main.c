#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include "../ucore.h"

#define IOP_ID_MAX_COUNT  256
#define HPU_MAX_COUNT     7
#define FLAG_MAX_COUNT    64

#define MHDMA_STATE_EMPTY    0
#define MHDMA_STATE_WAITING  1
#define MHDMA_STATE_RECEIVED 2
#define MHDMA_STATE_READING  3
#define MHDMA_STATE_RESOLVED 4

uint8_t local_hid = 1;

typedef struct {
  uint8_t  state;
  uint8_t  from_hpu_id;
  uint16_t dst_addr;
  uint16_t src_addr;
  uint8_t  lb2b_state;
} mhdma_element_t;

static mhdma_element_t mhdma_table[IOP_ID_MAX_COUNT][FLAG_MAX_COUNT];

void generate_read_req(uint8_t iop_id, uint8_t flag) {
  mhdma_element_t *current_elt = &mhdma_table[iop_id][flag];
  printf("generate read req for iop %d flag %d to hpu %d src_addr %d dst_addr %d",
      iop_id,
      flag,
      current_elt->from_hpu_id,
      current_elt->src_addr,
      current_elt->dst_addr);
}

void generate_notify(uint8_t iop_id, uint8_t flag, uint8_t hid) {
  mhdma_element_t *current_elt = &mhdma_table[iop_id][flag];
  printf("generate notify for iop %d flag %d to hpu %d src_addr %d",
      iop_id,
      flag,
      hid,
      current_elt->src_addr);
}

void interrupt_notify_handler(void) {
  // read register
  
  // get iop_id, from_hpu_id, src_addr, dst_addr, flag
  uint8_t iop_id = 2;
  uint8_t flag = 4;
  mhdma_element_t *current_elt = &mhdma_table[iop_id][flag];
  uint8_t current_state = current_elt->state;
  current_elt->state = MHDMA_STATE_RECEIVED;
  if (current_state == MHDMA_STATE_WAITING) {
    current_elt->state = MHDMA_STATE_READING;
    generate_read_req(iop_id, flag);
  }
}

void interrupt_read_complete_handler(void) {
  // read register
  
  // get iop_id, from_hpu_id, src_addr, dst_addr, flag
  uint8_t iop_id = 2;
  uint8_t flag = 4;
  mhdma_element_t *current_elt = &mhdma_table[iop_id][flag];
  current_elt->state = MHDMA_STATE_RESOLVED;
}

// Utilities function to patch DOp
//void patch_dop(DOpu_t *dop,
//               uint8_t iop_id, // should be read in dst
//               OperandBundle_t *dst,
//               OperandBundle_t *src,
//               ImmediatBundle_t *imm) {
//  DOpKind_t kind = get_kind(dop);
//
//  switch (kind) {
//    case DOPK_MEM: {
//      patch_mem_dop(dop, dst, src);
//      break;
//    }
//    case DOPK_ARITH: {
//      // Check if its a scalar arith operation
//      if ((dop->raw_field.opcode & IMM_FLAG) == IMM_FLAG) {
//        patch_imm_dop(dop, imm);
//      }
//      break;
//    }
//    case DOPK_SYNC: {
//      DOpSync_t sync_opcode = get_sync_opcode(dop);
//      switch (sync_opcode) {
//        case DOPS_NOTIFY: {
//          uint8_t flag = dop->sync.flag;
//
//          //insert SYNC and wait on ACK
//          break;
//        }
//        case DOPS_WAIT: {
//          uint8_t flag = dop->sync.flag;
//          uint8_t is_hard_wait = dop->sync.wait_mode;
//          uint8_t current_elt_state = mhdma_table[iop_id][flag].state;
//
//          while ( (is_hard_wait == 1 && current_elt_state < MHDMA_STATE_RESOLVED)
//               || (is_hard_wait == 0 && current_elt_state < MHDMA_STATE_RECEIVED)) {
//            // wait until notify or read ct is received
//            //iOSAL_Task_SleepTicks(1);
//            printf("wait on iop_id %d flag %d\n", iop_id, flag);
//            sleep(1);
//          }
//          break;
//        }
//        case DOPS_LD_B2B: {
//          uint8_t flag = dop->sync.flag;
//          mhdma_element_t *current_elt = &mhdma_table[iop_id][flag];
//          switch (current_elt->state) {
//            case MHDMA_STATE_RESOLVED: break; // nothing to do
//            case MHDMA_STATE_RECEIVED: { // must read asap
//              current_elt->state = MHDMA_STATE_READING;
//              generate_read_req(iop_id, flag);
//              break;
//            } 
//            default: { // must wait for notify
//              current_elt->state = MHDMA_STATE_WAITING;
//              break;
//            }
//          }
//          break;
//        }
//      }
//      break;
//    }
//    case DOPK_PBS: { // Nothing to do
//      break;
//    }
//  }
//}

#define MAX_VALUES 100

int main(void) {
  printf("MHDMA firmware prototype\n");
  FILE *fp;
  char *filename = "iop0.hex";
  uint32_t data[MAX_VALUES];
  int count = 0;

  // 1. Open the file
  fp = fopen(filename, "r");
  if (fp == NULL) {
      perror("Error opening iop file");
      return 1;
  }

  // 2. Read values loop
  // %x automatically handles "0x" prefix and whitespace/newlines
  // We check if count < MAX_VALUES to prevent buffer overflow
  while (count < MAX_VALUES && fscanf(fp, "%x", &data[count]) == 1) {
      count++;
  }

  // 3. Close the file
  fclose(fp);

  // 4. Verify output (Print the first few read values)
  printf("Successfully read %d values:\n", count);
  for (int i = 0; i < count; i++) {
      // %08X prints 8 digits of hex, padding with zeros
      printf("[%d]: 0x%08X\n", i, data[i]);
  }

  if (count == MAX_VALUES) {
      printf("Warning: Buffer full. There might be more data in the file.\n");
  }

  IOpHeader_t header;
  IOpMapping_t mapping;
  IOpOperandProp_t operand_prop;
  IOpOperandAddr_t operand_addr;
  IOpImmHeader_t imm_header;
  OperandBundle_t dst_bundle;
  OperandBundle_t src_bundle;
  ImmediatBundle_t imm_bundle;

  uint32_t iop_complete_len = parse_iop(data, 40, &header, &mapping, &operand_prop, &operand_addr, &imm_header, &dst_bundle, &src_bundle, &imm_bundle);

  uint8_t current_iid = dst_bundle.operand[0].iid;
  printf("IOp id %d [0x%x] [dst %d] [src %d] [imm %d] [stream_len %d]\n", current_iid, header.header.opcode, dst_bundle.len, src_bundle.len, imm_bundle.len, iop_complete_len);


  return 0;
}

