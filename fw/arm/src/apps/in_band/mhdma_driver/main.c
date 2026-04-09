#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>
#include "../ucore.h"
#include "mhdma_driver.h"

#define UCORE_MHDMA_SIMU 1

extern uint8_t cur_iid;
extern uint8_t phys_hpu_id;
extern mhdma_element_t mhdma_table[IOP_ID_MAX_COUNT][FLAG_MAX_COUNT];
extern uint8_t mhdma_table_state[IOP_ID_MAX_COUNT][FLAG_MAX_COUNT];
extern iop_state_t iop_state[IOP_ID_MAX_COUNT];
extern dst_store_t dst_store;
extern src_store_t src_store;
extern uint8_t cluster_first_nid;
extern uint8_t cluster_last_nid;
uint64_t intr_readc_cnt = 0;

int output_pipe = 0;
int start_iop = 0;

void interrupt_notify_handler(uint64_t notify_data) {
  // read register
  mhdma_cmd_t notify;
  notify.raw = notify_data;

  // get iop_id, slave_hpu_id, src_ct_id, dst_ct_id, flag
  uint8_t iid = notify.fields.iid;
  uint8_t slave_hpu_id = notify.fields.hid;
  uint8_t mode = notify.fields.mode;
  // is also the nb_hpu in CMD_SRC
  uint8_t flag = notify.fields.flag;

  printf("notify recv: iid %d from %d mode %d flag %d\n", iid, slave_hpu_id, mode, flag);

  switch (mode) {
    case CMD_USER: {
      uint8_t current_state = mhdma_table_state[iid][flag];
      printf("notify user before: iid %d flag %d state %d\n", iid, flag, current_state);
      mhdma_table_state[iid][flag] = MHDMA_STATE_RECEIVED;
      if (current_state == MHDMA_STATE_LB2B_WAITING) {
        mhdma_table_state[iid][flag] = MHDMA_STATE_READING;
        generate_read_req(iid, flag);
      }
      printf("notify user after: iid %d flag %d state %d\n", iid, flag, mhdma_table_state[iid][flag]);
      break;
    }
    case CMD_DST: {
      uint8_t tid = (notify.fields.flag);
      uint8_t bid = (notify.fields._pad & 0xFF);
      // if dst is None it is probably an error
      //if dst is reading or resolved then there is nothing to do here
      if (dst_store.state[iid][tid][bid] == DST_STATE_WAIT_NOTIFY) {
        uint16_t target_cid = (tid << 8) | bid;
        generate_operand_read_req(iid, mode, slave_hpu_id, notify.fields.src_cid, notify.fields.dst_cid, target_cid);
        dst_store.state[iid][tid][bid] = DST_STATE_READING;
      }
      dst_store_print(iid);
      break;
    }
    case CMD_SRC: {
      iop_state_node_ack(iid, flag);
      printf("iop_state[%d] = %d\n", iid, iop_state[iid].state);

      if (iop_state[iid].state == IOP_STATE_DONE) {
        // if remote_src is state NONE, it means b2b_pool slot is not ready => do nothing here
        // if remote_src is state DMA pending, it means read of this src is already on-going => do nothing here
        // if remote_src is resolved, then nothing todo either
        uint16_t src_addr = src_store_get_waiting(cur_iid, iid);
        uint8_t tid = (src_addr >> 8) & 0xFF;
        uint8_t bid = (src_addr & 0xFF);
        while (src_addr != 0xFFFF) {
          // by design remote_src->state == OPERAND_STATE_READ_PENDING)
          generate_operand_read_req(iid, mode, src_store.owner[cur_iid][tid], src_store.cid_offset[cur_iid][tid] + bid, src_store.dst_cid[cur_iid][tid][bid], 0);
          // try to get next src pending
          src_addr = src_store_get_waiting(cur_iid, iid);
          tid = (src_addr >> 8) & 0xFF;
          bid = (src_addr & 0xFF);
 	}

        uint16_t b2b_free_cnt = b2b_pool_free(iid);
        printf("iop_teardown free b2b_pool slots: %d\n", b2b_free_cnt);

      }
      break;
    }
  }
}

void interrupt_read_complete_handler(uint64_t rc_data) {
  // read register
  mhdma_cmd_t rc;
  rc.raw = rc_data;

  // get iop_id, slave_hpu_id, src_ct_id, dst_ct_id, flag
  uint8_t iid = rc.fields.iid;
  uint8_t slave_hpu_id = rc.fields.hid;
  uint8_t mode = rc.fields.mode;
  // is also the nb_hpu in CMD_SRC
  uint8_t flag = rc.fields.flag;

  printf("read_complete recv: iid %d from %d mode %d flag %d\n", iid, slave_hpu_id, mode, flag);

  switch (mode) {
    case CMD_USER: {
      printf("[HPU%d] read_complete user before: iid %d flag %d state %d\n", phys_hpu_id, iid, flag, mhdma_table_state[iid][flag]);
      // state should be MHDMA_STATE_READING
      if (mhdma_table_state[iid][flag] == MHDMA_STATE_READING) {
        mhdma_table_state[iid][flag] = MHDMA_STATE_RESOLVED;
      }
      printf("[HPU%d] read_complete user after: iid %d flag %d state %d\n", phys_hpu_id, iid, flag, mhdma_table_state[iid][flag]);
      break;
    }
    case CMD_DST: {
      uint8_t tid = rc.fields.flag;
      uint8_t bid = (rc.fields._pad & 0xFF);
      // state should be reading
      if (dst_store.state[iid][tid][bid] == DST_STATE_READING) {
        dst_store.state[iid][tid][bid] = DST_STATE_RESOLVED;
      }
      dst_store_print(iid);
      break;
    }
    case CMD_SRC: {
      uint8_t tid = rc.fields.flag;
      uint8_t bid = (rc.fields._pad & 0xFF);
      printf("read_complete recv: iid %d from %d tid %d bid %d state %d\n", iid, slave_hpu_id, tid, bid, src_store.state[cur_iid][tid][bid]);

      if (src_store.state[cur_iid][tid][bid] == OPERAND_STATE_DMA_PENDING) {
        src_store.state[cur_iid][tid][bid] = OPERAND_STATE_RESOLVED;
        printf("flag one src as resolved: %d %d %d\n",
            cur_iid,
            tid,
            bid);
      }
      break;
    }
  }
}

void interrupt_ack_handler(uint32_t ack) {
  // pop isc ack
  DOpu_t dop_ack;
  uint32_t popped_iop_ack = ack;
  dop_ack.raw = popped_iop_ack;
  printf("[HPU%d] recv ack: %08x opcode %06x iid %d flag %d is_inner %d\n",
      phys_hpu_id,
      dop_ack.raw,
      dop_ack.sync.opcode,
      dop_ack.sync.iid,
      dop_ack.sync.flag,
      dop_ack.sync.is_inner);

  if (dop_ack.sync.opcode == SYNC_OPCODE) {
    if (dop_ack.sync.is_inner == 1) {
      // internal ack
      generate_user_notify(dop_ack.sync.iid, dop_ack.sync.flag);
    } else {
      // iop ack
      uint8_t ack_iid = dop_ack.sync.iid;
      iop_teardown(ack_iid);
      printf("[HPU%d] iid %d teardown done", phys_hpu_id, ack_iid);
    }
  }
}

void generate_read_complete(uint64_t req) {
  mhdma_cmd_t rc_cmd;

  rc_cmd.raw = req;
  rc_cmd.fields.opcode = MHDMA_CMD_CT;

  if (output_pipe) {
    char* msg = malloc(32*sizeof(char));
    snprintf(msg, 32, "rc %d 0x%016lx", phys_hpu_id, rc_cmd.raw);
    write(output_pipe, msg, strlen(msg));
    free(msg);
  }
}

// C bench
void *pipe_listener(void *arg) {
  uint8_t phys_hpu_id = *((uint8_t*)arg);
  char *pipe_name = malloc(12*sizeof(char));
  snprintf(pipe_name,12,"/tmp/hpu_%d", phys_hpu_id);

  // 1. Create the Named Pipe (FIFO)
  // 0666 = Read/Write permissions for everyone
  if (mkfifo(pipe_name, 0666) == -1) {
    if (errno != EEXIST) { // It's okay if it already exists
      perror("mkfifo");
      return NULL;
    }
  }

  printf("[Thread] FIFO created/opened at %s\n", pipe_name);

  // 2. Open the FIFO
  // CRITICAL: We use O_RDWR instead of O_RDONLY.
  // This keeps the pipe "alive" even when the writer (echo) disconnects.
  int fd = open(pipe_name, O_RDWR);
  if (fd == -1) {
    perror("open");
    return NULL;
  }

  char buffer[128];
  while (1) {
    // 3. Blocking Read
    // This thread sleeps here until data arrives.
    ssize_t bytes = read(fd, buffer, sizeof(buffer) - 1);

    if (bytes > 0) {
      buffer[bytes] = '\0'; // Null-terminate safely

      // Clean up newline often sent by 'echo'
      if (buffer[bytes-1] == '\n') buffer[bytes-1] = '\0';

      printf("[HPU%d] Received cmd: '%s'\n", phys_hpu_id, buffer);

      if (strncmp(buffer, "quit", 4) == 0) {
        printf("[HPU%d] Quit command received. Stopping thread.\n", phys_hpu_id);
        break;
      }
      if (strncmp(buffer, "start", 4) == 0) {
        printf("[HPU%d] recv start command\n", phys_hpu_id);
        start_iop = 1;
      }
      if (strncmp(buffer, "open", 4) == 0) {
        char* output_pipe_name = malloc(12*sizeof(char));
        sscanf(buffer, "open %s", output_pipe_name);
        printf("[HPU%d] opening file %s\n", phys_hpu_id, output_pipe_name);
        output_pipe = open(output_pipe_name, O_WRONLY | O_NONBLOCK);
        if (output_pipe == -1) {
          printf("[HPU%d] could not open %s\n", phys_hpu_id, output_pipe_name);
        }
        free(output_pipe_name);
      }

      if (strncmp(buffer, "notify", 6) == 0) {
        uint64_t notify_word = 0;
        uint8_t slave_hpu_id;
        sscanf(buffer, "notify %hhd 0x%016lx", &slave_hpu_id, &notify_word);
        printf("[HPU%d] Notify command received from %d: %016lx\n", phys_hpu_id, slave_hpu_id, notify_word);
        mhdma_cmd_t notify;
        notify.raw = notify_word;
        // check that MHDMA filter out
        if (notify.fields.hid == phys_hpu_id) {
          notify.fields.hid = slave_hpu_id;
          interrupt_notify_handler(notify.raw);
        } else {
          printf("[HPU%d] Notify from %d rejected\n", phys_hpu_id, slave_hpu_id);
        }
      }
      if (strncmp(buffer, "rc", 2) == 0) {
        uint64_t rc_word = 0;
        uint8_t slave_hpu_id;
        sscanf(buffer, "rc %hhd 0x%016lx", &slave_hpu_id, &rc_word);
        printf("[HPU%d] read complete command received from %d: %016lx\n", phys_hpu_id, slave_hpu_id, rc_word);
        mhdma_cmd_t rc;
        rc.raw = rc_word;
        rc.fields.hid = slave_hpu_id;
        interrupt_read_complete_handler(rc.raw);
      }
      if (strncmp(buffer, "rq", 2) == 0) {
        uint64_t rq_word = 0;
        uint8_t master_hpu_id;
        sscanf(buffer, "rq %hhd 0x%016lx", &master_hpu_id, &rq_word);
        printf("[HPU%d] read request command received from %d: %016lx\n", phys_hpu_id, master_hpu_id, rq_word);
        sleep(2);
        mhdma_cmd_t rq;
        rq.raw = rq_word;
        rq.fields.hid = master_hpu_id;
        generate_read_complete(rq.raw);
      }

      sleep(1);


    } else if (bytes == -1) {
      perror("read");
      break;
    }
    // With O_RDWR, bytes == 0 (EOF) never happens unless we close fd.
  }

  // Cleanup
  close(fd);
  unlink(pipe_name); // Delete the file from /tmp
  free(pipe_name);
  return NULL;
}

#define MAX_VALUES 100

int main(int argc, char *argv[]) {
  printf("MHDMA firmware prototype\n");
  FILE *fp;
  if (argc < 4) {
    printf("needs iop and dop file and hpu_id\n");
    return 1;
  }
  char *filename_iop = argv[1];
  char *filename_dop = argv[2];
  phys_hpu_id = strtoul(argv[3], NULL, 0);
  uint32_t iop[MAX_VALUES];
  uint32_t dop[MAX_VALUES];
  int count_iop = 0;
  int count_dop = 0;
  cluster_first_nid = 0;
  cluster_last_nid = 1;

  // 1. Open IOp the file
  fp = fopen(filename_iop, "r");
  if (fp == NULL) {
    perror("Error opening iop file");
    return 1;
  }

  // 2. Read values loop
  // %x automatically handles "0x" prefix and whitespace/newlines
  // We check if count < MAX_VALUES to prevent buffer overflow
  while (count_iop < MAX_VALUES && fscanf(fp, "%x", &iop[count_iop]) == 1) {
    count_iop++;
  }

  // 3. Close the file
  fclose(fp);

  // 1. Open DOp the file
  fp = fopen(filename_dop, "r");
  if (fp == NULL) {
    perror("Error opening dop file");
    return 1;
  }

  // 2. Read values loop
  // %x automatically handles "0x" prefix and whitespace/newlines
  // We check if count < MAX_VALUES to prevent buffer overflow
  while (count_dop < MAX_VALUES && fscanf(fp, "%x", &dop[count_dop]) == 1) {
    count_dop++;
  }

  // 3. Close the file
  fclose(fp);

  // 4. Verify output (Print the first few read values)
  printf("Successfully read %d iop words %d dop words\n", count_iop, count_dop);
  for (int i = 0; i < count_iop; i++) {
    printf("IOp [%d]: 0x%08X\n", i, iop[i]);
  }
  for (int i = 0; i < count_dop; i++) {
    printf("DOp [%d]: 0x%08X\n", i, dop[i]);
  }

  pthread_t tid;

  // Start the listener thread
  if (pthread_create(&tid, NULL, pipe_listener, (void *)(&phys_hpu_id)) != 0) {
    perror("pthread_create");
    return 1;
  }

  // init
  {
    iop_state_init();
    b2b_pool_init();
    dst_notifyq_init();
    src_store_init();
    dst_store_init();
  }

  IOpHeader_t header;
  IOpMapping_t mapping;
  IOpOperandProp_t operand_prop;
  IOpOperandAddr_t operand_addr;
  IOpImmHeader_t imm_header;
  OperandBundle_t dst_bundle;
  OperandBundle_t src_bundle;
  ImmediatBundle_t imm_bundle;

  while (start_iop == 0) {
    sleep(2);
  }

  uint32_t iop_complete_len = parse_iop(iop, 4*count_iop, &header, &mapping, &operand_prop, &operand_addr, &imm_header, &dst_bundle, &src_bundle, &imm_bundle);

  cur_iid = dst_bundle.operand[0].iid;
  printf("IOp id %d [0x%x] [dst %d] [src %d] [imm %d] [stream_len %d]\n", cur_iid, header.header.opcode, dst_bundle.len, src_bundle.len, imm_bundle.len, iop_complete_len);

  printf("local phys_hpu_id %d virt_hpu_id %d\n", phys_hpu_id, get_virt_of(phys_hpu_id, mapping));
  // prepare IOp
  dst_store_initd(cur_iid, &dst_bundle);

  dst_store_print(cur_iid);
  //
  DOpu_t cur_dop;
  for (int i = 0; i < count_dop; i++) {
    cur_dop.raw = dop[i];
    uint32_t patch_rc = patch_dop(&cur_dop, &dst_bundle, &src_bundle, &imm_bundle, NULL, 0);
    // patch_rc: bit 16: need to insert SYNC (to notify DST available)
    //           bit 15: need to skip this DOp (LD_B2B or WAIT...)
    //           bit 14..0: number of DOp sent to ISC before waiting
    if ((patch_rc & 0x8000) != 0) {
      // it means current DOp was a UCORE DOp that got processed and removed from stream
      continue;
    }
    printf("dop %08x: opcode %d\n", cur_dop.raw, cur_dop.raw_field.opcode);
    if ((patch_rc & 0x10000) != 0) { // insert inner SYNC
      printf("dop: opcode SYNC inserted for dst notify\n");
    }
    switch (get_kind(&cur_dop)) {
      case DOPK_MEM: {
        printf("mem dop %08x: slot %d mode %d rid %d\n", cur_dop.raw, cur_dop.mem.slot, cur_dop.mem.mode, cur_dop.mem.rid);
        break;
      }
      case DOPK_UCORE: {
        printf("ucore dop %08x: slot %d mode %d rid %d\n", cur_dop.raw, cur_dop.ucore.slot, cur_dop.ucore.mode, cur_dop.ucore.flag);
        break;
      }
      default: {
        break;
      }
    }
    if (cur_dop.raw_field.opcode == SYNC_OPCODE) {
      interrupt_ack_handler(cur_dop.raw);
      sleep(2);
    }
  }
  cur_dop.sync.opcode = SYNC_OPCODE;
  cur_dop.sync.iid = cur_iid;
  cur_dop.sync.is_inner = 0;
  cur_dop.sync.flag = 0;
  cur_dop.sync._pad = 0;
  printf("dop %08x: opcode %d\n", cur_dop.raw, cur_dop.raw_field.opcode);
  // return from ISC
  interrupt_ack_handler(cur_dop.raw);

  while(1);

  return 0;
}
