#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include "mhdma_driver.h"
#ifndef UCORE_MHDMA_SIMU
#include "pll.h"
#include "profile_hal.h"
#else
#include <unistd.h>
#endif

extern uint8_t phys_hpu_id;
extern mhdma_element_t mhdma_table[IOP_ID_MAX_COUNT][FLAG_MAX_COUNT];

#ifdef UCORE_MHDMA_SIMU
  extern int output_pipe;

  void write_read_req_command(uint8_t master_hpu_id, uint64_t cmd) {
    if (output_pipe) {
      char* msg = malloc(25*sizeof(char));
      snprintf(msg, 25, "rq %d 0x%016lx", master_hpu_id, cmd);
      write(output_pipe, msg, strlen(msg));
      free(msg);
    }
  }

  void write_notify_command(uint8_t slave_hpu_id, uint64_t cmd) {
    if (output_pipe) {
      char* msg = malloc(32*sizeof(char));
      snprintf(msg, 32, "notify %d 0x%016lx", slave_hpu_id, cmd);
      write(output_pipe, msg, strlen(msg));
      free(msg);
    }
  }
#else
  volatile uint32_t *cmd_req_id = (volatile uint32_t*)(XPAR_AXI_LPD_BASEADDR + MHDMA_CMD_WRITE_REQ_ID );
  volatile uint32_t *cmd_req_addr = (volatile uint32_t*)(XPAR_AXI_LPD_BASEADDR + MHDMA_CMD_WRITE_REQ_ADDR );

  void write_notify_command(uint8_t slave_hpu_id, uint64_t cmd) {
    (void)slave_hpu_id;
    //PLL_ERR("mhdma_driver", "write notify %08x:%08x %08x:%08x",
    //    (uintptr_t)cmd_req_id,
    //    (cmd & 0xFFFFFFFF),
    //    (uintptr_t)cmd_req_addr,
    //    ((cmd >> 32) & 0xFFFFFFFF));
    vOSAL_EnterCritical();
    *cmd_req_id = cmd & 0xFFFFFFFF;
    HAL_FLUSH_CACHE_DATA( (uintptr_t)cmd_req_id, sizeof(uint32_t));
    *cmd_req_addr = (cmd >> 32) & 0xFFFFFFFF;
    HAL_FLUSH_CACHE_DATA( (uintptr_t)cmd_req_addr, sizeof(uint32_t));
    vOSAL_ExitCritical();
  }
  void write_read_req_command(uint8_t master_hpu_id, uint64_t cmd) {
    write_notify_command(master_hpu_id, cmd);
  }
#endif

void generate_read_req(uint8_t iop_id, uint8_t flag) {
  mhdma_element_t *current_elt = &mhdma_table[iop_id][flag];
  //PLL_INF("mhdma", "[HPU%d] generate read req for iop %d flag %d to hpu %d src_ct_id %d dst_ct_id %d state %d",
  //    phys_hpu_id,
  //    iop_id,
  //    flag,
  //    current_elt->slave_hpu_id,
  //    current_elt->src_ct_id,
  //    current_elt->dst_ct_id,
  //    current_elt->state);
  mhdma_cmd_t read_req;
  read_req.raw = 0;
  read_req.fields.dst_cid = current_elt->dst_ct_id;
  read_req.fields.src_cid = current_elt->src_ct_id;
  read_req.fields.iid = iop_id;
  read_req.fields.opcode = MHDMA_CMD_READ;
  read_req.fields.hid = current_elt->slave_hpu_id;
  read_req.fields.mode = CMD_USER;
  read_req.fields.flag = flag;

  write_read_req_command(phys_hpu_id, read_req.raw);
}

void generate_operand_read_req(uint8_t iop_id, uint8_t mode, uint8_t slave_hpu_id, uint16_t src_cid, uint16_t dst_cid, uint16_t target_cid) {
  //PLL_INF("mhdma", "[HPU%d] generate operand read req for iop %d mode %d to hpu %d src_ct_id %d dst_ct_id %d target_cid %d",
  //    phys_hpu_id,
  //    iop_id,
  //    mode,
  //    slave_hpu_id,
  //    src_cid,
  //    dst_cid,
  //    target_cid);
  mhdma_cmd_t read_req;
  read_req.raw = 0;
  read_req.fields.dst_cid = dst_cid;
  read_req.fields.src_cid = src_cid;
  read_req.fields.iid = iop_id;
  read_req.fields.opcode = MHDMA_CMD_READ;
  read_req.fields.hid = slave_hpu_id;
  read_req.fields.mode = mode;
  read_req.fields.flag = (target_cid >> 8) & 0x3F;
  read_req.fields._pad = target_cid & 0xFF;

  write_read_req_command(phys_hpu_id, read_req.raw);
}

void generate_user_notify(uint8_t iop_id, uint8_t flag) {
  mhdma_element_t *current_elt = &mhdma_table[iop_id][flag];
  //PLL_INF("mhdma", "[HPU%d] generate notify for iop %d mode %d flag %d from hpu %d to hpu %d src_ct_id %d state %d",
  //    phys_hpu_id,
  //    iop_id,
  //    CMD_USER,
  //    flag,
  //    current_elt->slave_hpu_id,
  //    current_elt->master_hpu_id,
  //    current_elt->src_ct_id,
  //    current_elt->state);
  mhdma_cmd_t nc;
  nc.raw = 0;
  nc.fields.dst_cid = 0;
  nc.fields.src_cid = current_elt->src_ct_id;
  nc.fields.iid = iop_id;
  nc.fields.opcode = MHDMA_CMD_NOTIFY;
  nc.fields.hid = current_elt->master_hpu_id;
  nc.fields.mode = CMD_USER;
  nc.fields.flag = flag;

  write_notify_command(phys_hpu_id, nc.raw);
}

void generate_iop_notify(uint8_t iop_id, uint8_t nb_hpus, uint8_t master_hpu_id) {
  PLL_DBG("mhdma", "[HPU%d] iop notify iid %d mode %d from hpu %d to hpu %d nb_hpu %d",
      phys_hpu_id,
      iop_id,
      CMD_SRC,
      phys_hpu_id,
      master_hpu_id,
      nb_hpus);
  mhdma_cmd_t nc;
  nc.raw = 0;
  nc.fields.dst_cid = 0;
  nc.fields.src_cid = 0;
  nc.fields.iid = iop_id;
  nc.fields.opcode = MHDMA_CMD_NOTIFY;
  nc.fields.hid = master_hpu_id;
  nc.fields.mode = CMD_SRC;
  nc.fields.flag = nb_hpus;

  write_notify_command(phys_hpu_id, nc.raw);
}

void generate_ucore_notify(uint8_t iid, uint8_t master_hpu_id, uint16_t src_cid, uint16_t dst_cid, uint16_t target_cid) {
  //PLL_ERR("mhdma", "[HPU%d] generate notify for iop %d mode %d dst from hpu %d to hpu %d src_ct_id %d dst_ct_id %d dst tid %d bid %d",
  //    phys_hpu_id,
  //    iid,
  //    CMD_DST,
  //    phys_hpu_id,
  //    master_hpu_id,
  //    src_cid,
  //    target_cid,
  //    (dst_cid >> 8) & 0x3F,
  //    (dst_cid & 0xFF));
  mhdma_cmd_t nc;
  nc.raw = 0;
  nc.fields.dst_cid = target_cid;
  nc.fields.src_cid = src_cid;
  nc.fields.iid = iid;
  nc.fields.opcode = MHDMA_CMD_NOTIFY;
  nc.fields.hid = master_hpu_id;
  nc.fields.mode = CMD_DST;
  nc.fields.flag = (dst_cid >> 8) & 0x3F;
  nc.fields._pad = dst_cid & 0xFF;

  write_notify_command(phys_hpu_id, nc.raw);
}
