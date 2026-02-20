/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the main entry point for the Alveo Management Controller
 *
 * @file amc.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

/* common includes */
#include "standard.h"
#include "util.h"
#include "amc_cfg.h"
#include "amc_version.h"

#include "xil_io.h"
#include "xscugic.h"
/* osal */
#include "osal.h"
#include <stdint.h>

/* core_libs */
#include "pll.h"
#include "evl.h"
#include "dal.h"

/* device drivers */
#include "i2c.h"
#include "eeprom.h"
#include "sys_mon.h"
#include "gcq.h"

/* fal */
#include "fw_if_test.h"
#include "fw_if_gcq.h"
#include "fw_if_ospi.h"
#include "fw_if_muxed_device.h"

/* proxy drivers */
#include "axc_proxy_driver.h"
#include "apc_proxy_driver.h"
#include "asc_proxy_driver.h"
#include "ami_proxy_driver.h"
#include "bmc_proxy_driver.h"

/* bim app data */
#include "profile_bim.h"

/* apps */
#include "asdm.h"
#include "in_band_telemetry.h"
#include "out_of_band_telemetry.h"
#include "bim.h"

/* PDR data */
#include "profile_pdr.h"

/* sensor data */
#include "profile_sensors.h"

/* hardware definitions */
#include "profile_hal.h"
#include "profile_fal.h"
#include "profile_muxed_device.h"
#include "profile_debug_menu.h"

#include "stream_isc.h"

/* HPU related */
#include "ucore.h"
#include "mhdma_driver.h"

/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define AMC_OUTPUT_LEVEL  ( PLL_OUTPUT_LEVEL_ERROR )
#define AMC_LOGGING_LEVEL ( PLL_OUTPUT_LEVEL_ERROR )

#define AMC_NAME "AMC"

#define AMC_HASH_LEN ( 7 )
#define AMC_DATE_LEN ( 8 )

#define AMC_TASK_DEFAULT_STACK ( 0x1000 )
#define AMC_PROXY_NAME_LEN     ( 15 )

#define AMC_TASK_SLEEP_MS             ( 100 )
#define AMC_GET_PROJECT_INFO_SLEEP_MS ( 1000 )

/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    AMC_TASK_PRIOS
 * @brief   AMC Task priorities
 */
typedef enum AMC_TASK_PRIOS
{
    AMC_TASK_PRIO_RSVD = 5,                                                    /* TODO: get actual value from osal.h */

    AMC_TASK_PRIO_DEFAULT,
    MAX_AMC_TASK_PRIO

} AMC_TASK_PRIOS;

typedef enum {
  MHDMA_CMD_PRINT_ERR = 0,
  MHDMA_CMD_IOP_TEARDOWN,
  MHDMA_CMD_IOP_READSRC,
} MhdmaCmdType_t;

typedef struct {
  MhdmaCmdType_t cmdID;
  uint32_t payload;
} MhdmaCommand_t;

void *xMhdmaCommandMbox = NULL;
void *xMhdmaWorkerTask = NULL;

/******************************************************************************/
/* EVL Callback Declarations                                                  */
/******************************************************************************/

/**
 * @brief   EVL Callbacks for binding to Proxy Drivers
 *
 * @param   pxSignal     Event raised
 *
 * @return  OK if no errors were raised in the callback
 *          ERROR if an error was raised in the callback
 *
 */
static int iApcCallback( EVL_SIGNAL *pxSignal );
static int iAmiCallback( EVL_SIGNAL *pxSignal );
static int iAxcCallback( EVL_SIGNAL *pxSignal );
static int iBmcCallback( EVL_SIGNAL *pxSignal );


/******************************************************************************/
/* Local Function Declarations                                                */
/******************************************************************************/

/**
 * @brief   Get project info
 *
 * @return  N/A
 *
 */
static void vGetProjectInfo( void );

/**
 * @brief   Initialise core libraries
 *
 * @return  OK if all core libraries initialised successfully
 *          ERROR if any or all core libraries not initialised
 *
 */
static int iInitCoreLibs( void );

/**
 * @brief   Initialise device drivers
 *
 * @return  OK if all device drivers initialised and created successfully
 *          ERROR if any or all device drivers not initialised
 *
 */
static int iInitDeviceDrivers( void );

/**
 * @brief   Initialise Proxy Driver layer
 *
 * @return  OK if all Proxy Drivers initialised and bound successfully
 *          ERROR if any or all proxy drivers not initialised
 *
 */
static int iInitProxies( void );

/**
 * @brief   Initialise App layer
 *
 * @return  OK if all Apps initialised and created successfully
 *          ERROR if any or all apps not initialised
 *
 */
static int iInitApp( void );

/**
 * @brief   The main task that init the FAL & proxy drivers
 *
 * @return  N/A
 */
static void vTaskFuncMain( void );

/**
 * @brief   Configure the partition table stored at the start of
 *          shared memory and used by the AMI to deremine the AMC state
 * @return  N/A
 */
static void vConfigurePartitionTable( void );

/**
 * @brief Read runtime configuration from memory
 *        Discard cache status to enforce that it's latest version of the cfg
 */
static void updt_ucore_cfg(UcoreCfg_t* cfg);

/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

/* Note: the default I2C clock frequency isn't used */
static I2C_CFG_TYPE xI2cCfg[ I2C_NUM_INSTANCES ] =
{ {
      HAL_I2C_BUS_0_DEVICE_ID,
      ( uint64_t )HAL_I2C_BUS_0_BASEADDR,
      HAL_I2C_BUS_0_I2C_CLK_FREQ_HZ,
      HAL_I2C_RETRY_COUNT,
      HAL_I2C_BUS_0_SW_RESET_OFFSET,
      HAL_I2C_BUS_0_RESET_ON_INIT,
      HAL_I2C_BUS_0_HW_RESET_ADDR,
      HAL_I2C_BUS_0_HW_RESET_MASK,
      HAL_I2C_BUS_0_HW_DEVICE_RESET
  },
  {
      HAL_I2C_BUS_1_DEVICE_ID,
      ( uint64_t )HAL_I2C_BUS_1_BASEADDR,
      HAL_I2C_BUS_1_I2C_CLK_FREQ_HZ,
      HAL_I2C_RETRY_COUNT,
      HAL_I2C_BUS_1_SW_RESET_OFFSET,
      HAL_I2C_BUS_1_RESET_ON_INIT,
      HAL_I2C_BUS_1_HW_RESET_ADDR,
      HAL_I2C_BUS_1_HW_RESET_MASK,
      HAL_I2C_BUS_1_HW_DEVICE_RESET
  } };
static EEPROM_CFG xEepromCfg =
{
    HAL_EEPROM_I2C_BUS,
    HAL_EEPROM_SLAVE_ADDRESS,
    HAL_EEPROM_ADDRESS_SIZE,
    HAL_EEPROM_PAGE_SIZE,
    HAL_EEPROM_NUM_PAGES,
    HAL_EEPROM_DEVICE_ID_ADDRESS,
    HAL_EEPROM_DEVICE_ID_REGISTER,
    HAL_EEPROM_DEVICE_ID
};

/* AXC External Device configs */
AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG xQsfpDevice1 =
{
    &xQsfpIf1, 0
};
AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG xQsfpDevice2 =
{
    &xQsfpIf2, 1
};
AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG xQsfpDevice3 =
{
    &xQsfpIf3, 2
};
AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG xQsfpDevice4 =
{
    &xQsfpIf4, 3
};
AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG xDimmDevice =
{
    &xDimmIf, 4
};

uint64_t ullAmcInitStatus = 0;
uint64_t isc_intr_global_cnt = 0;
uint64_t debug_intr_global_cnt = 0;
uint64_t intr_notify_cnt = 0;
uint32_t intr_notify_data = 0;
uint64_t intr_readc_cnt = 0;
uint32_t ackq_head = 0;
uint32_t ackq_tail = 0;
volatile uint32_t *toAmiIopAckqHead = ( volatile uint32_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + OFFSET_TO_AMI_IOPACKQ_HEAD );
volatile uint32_t *toAmiIopAckqTail = ( volatile uint32_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + OFFSET_TO_AMI_IOPACKQ_TAIL );
volatile uint32_t *toAmiIopAckqData = ( volatile uint32_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + OFFSET_TO_AMI_IOPACKQ_DATA_START );

#define HIGH_PRIORITY_INTR  0xA0 // default is around 0xA0 and lower val means higher priority
#define EDGE_SENSITIVE_INTR 0x3  // triggers on posedge of interrupt signal
#define ACTIVE_ONE_INTR     0x1  // default value, triggers when signal is at 1

extern XScuGic xInterruptController;

// HPU global variables
extern uint8_t cur_iid;
extern uint8_t phys_hpu_id;
extern iop_state_t iop_state[IOP_ID_MAX_COUNT];
extern dst_store_t dst_store;
extern mhdma_element_t mhdma_table[IOP_ID_MAX_COUNT][FLAG_MAX_COUNT];

/******************************************************************************/
/* Function implementations                                                   */
/******************************************************************************/
/*
 * @brief   the IOp ack interrupt handler
 */
void vInterruptHandler_isc_ack( void* pvCallBackRef ) {
    isc_intr_global_cnt = isc_intr_global_cnt + 1;

    // NB: Head is only written by AMC after init
    // -> No need to invalidate the cache
    ackq_head = * toAmiIopAckqHead;
    HAL_INVALIDATE_CACHE_DATA( (uintptr_t)toAmiIopAckqTail, sizeof(uint32_t) );
    ackq_tail = * toAmiIopAckqTail;
    uint32_t ackq_free_words = AMI_IOPACKQ_MAX_WORDS + ackq_tail - ackq_head;
    //PLL_INF("AMC", "IOP Ack pending %d, AckQ [head 0x%x; tail 0x%x; free_w %d]", read_isc_ack_cnt(), ackq_head, ackq_tail, ackq_free_words);

    //PLL_INF("AMC", "IOpAck queue is full, abort isc ack forwarding");
    if (ackq_free_words != 0) {
        // Write ack value in queue body
        uint32_t popped_iop_ack = pop_isc_ack();

        if (popped_iop_ack > 0) {
            DOpu_t dop_ack;
            dop_ack.raw = popped_iop_ack;
            //PLL_INF("AMC", "[HPU%d] recv ack: %08x opcode %06x iid %d flag %d is_inner %d\n",
            //    phys_hpu_id,
            //    dop_ack.raw,
            //    dop_ack.sync.opcode,
            //    dop_ack.sync.iid,
            //    dop_ack.sync.flag,
            //    dop_ack.sync.is_inner);

            if (dop_ack.sync.opcode == SYNC_OPCODE) {
              if (dop_ack.sync.is_inner == 1) {
                // internal ack
                generate_user_notify(dop_ack.sync.iid, dop_ack.sync.flag);
              } else {
                MhdmaCommand_t cmd;
                cmd.cmdID = MHDMA_CMD_IOP_TEARDOWN;
                cmd.payload = popped_iop_ack;
                if (xMhdmaCommandMbox) {
                    iOSAL_MBox_PostFromISR(xMhdmaCommandMbox,
                                          (void*)&cmd);
                }
              }
            }
        }
    }
}

/*
 * @brief   debug only interrupt handler
 */
void vInterruptHandler_debug( void* pvCallBackRef ) {
    debug_intr_global_cnt = debug_intr_global_cnt + 1;
    // write int register at 0 to stop interrupt
    // write cnt in upper 16b
    *( ( volatile uint32_t * )(XPAR_AXI_LPD_BASEADDR + 0x20200) ) = ((debug_intr_global_cnt & 0xFFFF) << 16) | 0x0;
}

/*
 * @brief   debug only interrupt handler
 */
void vInterruptHandler_mhdma_notify( void* pvCallBackRef ) {
    intr_notify_cnt = intr_notify_cnt + 1;
    uint64_t notify_data = 0;
    uint32_t notify_tmp_req_id = 0;
    uint32_t notify_tmp_req_addr = 0;
    // read request::notify 0x50108
    HAL_INVALIDATE_CACHE_DATA( (uintptr_t)(XPAR_AXI_LPD_BASEADDR + MHDMA_NOTIFY_DATA_REQ_ID) , sizeof(uint32_t) );
    notify_tmp_req_id = * (volatile uint32_t *) (XPAR_AXI_LPD_BASEADDR + MHDMA_NOTIFY_DATA_REQ_ID);
    HAL_INVALIDATE_CACHE_DATA( (uintptr_t)(XPAR_AXI_LPD_BASEADDR + MHDMA_NOTIFY_DATA_REQ_ADDR) , sizeof(uint32_t) );
    notify_tmp_req_addr = * (volatile uint32_t *) (XPAR_AXI_LPD_BASEADDR + MHDMA_NOTIFY_DATA_REQ_ADDR);
    notify_data = (((uint64_t)notify_tmp_req_addr) << 32) | notify_tmp_req_id;
    // read register
    mhdma_cmd_t notify;
    notify.raw = notify_data;

    // get iop_id, slave_hpu_id, src_ct_id, dst_ct_id, flag
    uint8_t iid = notify.fields.iid;
    uint8_t slave_hpu_id = notify.fields.hid;
    uint8_t mode = notify.fields.mode;
    // is also the nb_hpu in CMD_SRC
    uint8_t flag = notify.fields.flag;

    MhdmaCommand_t cmd;
    cmd.cmdID = MHDMA_CMD_PRINT_ERR;
    cmd.payload = (iid << 24 | slave_hpu_id << 16 | mode << 8 | flag);
    if (xMhdmaCommandMbox) {
        iOSAL_MBox_PostFromISR(xMhdmaCommandMbox,
                              (void*)&cmd);
    }

    switch (mode) {
      case CMD_USER: {
        mhdma_element_t *current_elt = &mhdma_table[iid][flag];
        //printf("notify user before: iid %d flag %d state %d\n", iid, flag, current_elt->state);
        uint8_t current_state = current_elt->state;
        current_elt->state = MHDMA_STATE_RECEIVED;
        if (current_state == MHDMA_STATE_LB2B_WAITING) {
          current_elt->state = MHDMA_STATE_READING;
          generate_read_req(iid, flag);
        }
        //printf("notify user after: iid %d flag %d state %d\n", iid, flag, current_elt->state);
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
        //dst_store_print(iid);
        break;
      }
      case CMD_SRC: {
        iop_state_node_ack(iid, flag);
        //printf("iop_state[%d] = %d\n", iid, iop_state[iid].state);

        if (iop_state[iid].state == IOP_STATE_DONE) {
          MhdmaCommand_t cmd;
          cmd.cmdID = MHDMA_CMD_IOP_READSRC;
          cmd.payload = iid << 24 | mode << 8;
          if (xMhdmaCommandMbox) {
              iOSAL_MBox_PostFromISR(xMhdmaCommandMbox,
                                    (void*)&cmd);
          }
        }
        break;
      }
    }
}

/*
 * @brief   debug only interrupt handler
 */
void vInterruptHandler_mhdma_read_complete( void* pvCallBackRef ) {
  intr_readc_cnt = intr_readc_cnt + 1;
  uint64_t rc_data = 0;
  uint32_t rc_tmp_req_id = 0;
  uint32_t rc_tmp_req_addr = 0;
  // read request::rc 0x50108
  HAL_INVALIDATE_CACHE_DATA( (uintptr_t)(XPAR_AXI_LPD_BASEADDR + MHDMA_NOTIFY_DATA_REQ_ID) , sizeof(uint32_t) );
  rc_tmp_req_id = * (volatile uint32_t *) (XPAR_AXI_LPD_BASEADDR + MHDMA_READ_DONE_DATA_REQ_ID);
  HAL_INVALIDATE_CACHE_DATA( (uintptr_t)(XPAR_AXI_LPD_BASEADDR + MHDMA_NOTIFY_DATA_REQ_ADDR) , sizeof(uint32_t) );
  rc_tmp_req_addr = * (volatile uint32_t *) (XPAR_AXI_LPD_BASEADDR + MHDMA_READ_DONE_DATA_REQ_ADDR);
  rc_data = (((uint64_t)rc_tmp_req_addr) << 32) | rc_tmp_req_id;
  // read register
  mhdma_cmd_t rc;
  rc.raw = rc_data;

  // get iop_id, slave_hpu_id, src_ct_id, dst_ct_id, flag
  uint8_t iid = rc.fields.iid;
  uint8_t slave_hpu_id = rc.fields.hid;
  uint8_t mode = rc.fields.mode;
  // is also the nb_hpu in CMD_SRC
  uint8_t flag = rc.fields.flag;

  MhdmaCommand_t cmd;
  cmd.cmdID = MHDMA_CMD_PRINT_ERR;
  cmd.payload = (iid << 24 | slave_hpu_id << 16 | mode << 8 | flag) | 0x80000000;
  if (xMhdmaCommandMbox) {
      iOSAL_MBox_PostFromISR(xMhdmaCommandMbox,
                            (void*)&cmd);
  }

  switch (mode) {
    case CMD_USER: {
      mhdma_element_t *current_elt = &mhdma_table[iid][flag];
      //printf("[HPU%d] read_complete user before: iid %d flag %d state %d\n", phys_hpu_id, iid, flag, current_elt->state);
      // state should be MHDMA_STATE_READING
      if (current_elt->state == MHDMA_STATE_READING) {
        current_elt->state = MHDMA_STATE_RESOLVED;
      }
      //printf("[HPU%d] read_complete user after: iid %d flag %d state %d\n", phys_hpu_id, iid, flag, current_elt->state);
      break;
    }
    case CMD_DST: {
      uint8_t tid = rc.fields.flag;
      uint8_t bid = (rc.fields._pad & 0xFF);
      // state should be reading
      if (dst_store.state[iid][tid][bid] == DST_STATE_READING) {
        dst_store.state[iid][tid][bid] = DST_STATE_RESOLVED;
      }
      //dst_store_print(iid);
      break;
    }
    case CMD_SRC: {
      // there may be a src identification issue here
      //uint8_t tid = (rc.fields.src_cid >> 8) & 0xFF;
      //uint8_t bid = (rc.fields.src_cid & 0xFF);

      // here there is no verification read complete is exactly about source requested
      RemoteOperand_t *remote_src = src_notifyq_find_by_state(iid, OPERAND_STATE_DMA_PENDING);
      if (remote_src != NULL) {
        // by design remote_src->state == OPERAND_STATE_DMA_PENDING
        remote_src->state = OPERAND_STATE_RESOLVED;
        //printf("flag one src as resolved: %d %d %d\n",
        //    remote_src->iid,
        //    (remote_src->src_cid >> 8) & 0xFF,
        //    (remote_src->src_cid & 0xFF));
      }
      //src_notifyq_print(iid);
      break;
    }
  }
}

void vMhdmaWorkerTask(void *pvParameters) {
  MhdmaCommand_t rxCmd;
  // Infinite loop for the task
  FOREVER {
    if ( OSAL_ERRORS_NONE == iOSAL_MBox_Pend( xMhdmaCommandMbox, (void*)&rxCmd, OSAL_TIMEOUT_WAIT_FOREVER) ) {
      PLL_ERR("MhdmaWorker", "rcv cmd %d %08x", rxCmd.cmdID, rxCmd.payload);
      switch (rxCmd.cmdID) {
        case MHDMA_CMD_IOP_TEARDOWN:
          DOpu_t dop;
          dop.raw = rxCmd.payload;
          uint8_t ack_iid = dop.sync.iid;
          iop_teardown(ack_iid);

          // Write ack value in queue body
          volatile uint32_t* ackq_idx = toAmiIopAckqData + (ackq_head % AMI_IOPACKQ_MAX_WORDS);
          *ackq_idx = dop.raw;
          HAL_FLUSH_CACHE_DATA( (uintptr_t)ackq_idx, sizeof(uint32_t));
          // Update queue head
          ackq_head += 1;
          *toAmiIopAckqHead = ackq_head;
          HAL_FLUSH_CACHE_DATA( (uintptr_t)toAmiIopAckqHead, sizeof(uint32_t));
          break;

        case MHDMA_CMD_IOP_READSRC:
          uint8_t iid = (rxCmd.payload >> 24) & 0xFF;
          uint8_t mode = (rxCmd.payload >> 8) & 0xFF;
          // if remote_src is state NONE, it means b2b_pool slot is not ready => do nothing here
          // if remote_src is state DMA pending, it means read of this src is already on-going => do nothing here
          // if remote_src is resolved, then nothing todo either
          RemoteOperand_t *remote_src = src_notifyq_find_by_state(iid, OPERAND_STATE_READ_PENDING);
          while (remote_src != NULL) {
            // by design remote_src->state == OPERAND_STATE_READ_PENDING)
            PLL_ERR("MhdmaWorker", "iop read src %d from %d src %04X dst %04X", iid, remote_src->pos, remote_src->src_cid, remote_src->dst_cid);
            generate_operand_read_req(iid, mode, remote_src->pos, remote_src->src_cid, remote_src->dst_cid, 0);
            remote_src->state = OPERAND_STATE_DMA_PENDING;
          }

          // local b2b pool linked to this IOp (for dst) are not needed anymore
          uint16_t b2b_free_cnt = b2b_pool_free(iid);
          PLL_ERR("MhdmaWorker", "iop read src clean local b2bpool (%d slots)", b2b_free_cnt);

        case MHDMA_CMD_PRINT_ERR:
          PLL_ERR("MhdmaWorker", "data: %08x", rxCmd.payload);
          break;

        default:
          PLL_ERR("MhdmaWorker", "rcv mhdma cmd unknown %d %08x", rxCmd.cmdID, rxCmd.payload);
          break;
      }
    }
  }
}

/*
 * @brief   The main task
 */
static void vTaskFuncMain( void )
{
    int iStatus = ERROR;

    vConfigurePartitionTable();

    if( OK == iInitCoreLibs() ) {
        PLL_LOG( AMC_NAME, "Core Libs initialised OK\r\n" );
        iStatus = OK;
    } else {
        PLL_LOG( AMC_NAME, "Core Libs initialisation ERROR\t\n" );
    }

    if( OK == iInitDeviceDrivers() ) {
        PLL_LOG( AMC_NAME, "Device drivers Initialised OK\r\n" );
        iStatus = OK;
    } else {
        PLL_LOG( AMC_NAME, "Device drivers Initialisation ERROR\r\n" );
    }

    if( OK == iFAL_Initialise( &ullAmcInitStatus ) ) {
        PLL_LOG( AMC_NAME, "FAL Initialised OK\r\n" );
    } else {
        PLL_LOG( AMC_NAME, "FAL Initialisation ERROR\r\n" );
    }

    if( OK == iInitProxies() ) {
        PLL_LOG( AMC_NAME, "Proxy Drivers Initialised OK\r\n" );
        iStatus = OK;
    } else {
        PLL_LOG( AMC_NAME, "Proxy Drivers Initialisation ERROR\r\n" );
    }

    if( OK == iInitApp() ) {
        PLL_LOG( AMC_NAME, "Apps Initialised OK\r\n" );
    } else {
        PLL_LOG( AMC_NAME, "Apps Initialisation ERROR\r\n" );
        iStatus = ERROR;
    }

    if( ERROR == iStatus ) {
        /*
         * The final step before starting the main task is to configure the start
         * of the shared memory with the information needed by the AMI.
         */
        PLL_ERR( AMC_NAME, "Error Main Task has initialisation failures\r\n" );
    }

    PLL_INF( AMC_NAME, "ullAmcInitStatus:\n\r" );
    PLL_INF( AMC_NAME, "ucPllInitialised                %s\n\r", ( ullAmcInitStatus & AMC_CFG_PLL_INITIALISED              ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucEvlInitialised                %s\n\r", ( ullAmcInitStatus & AMC_CFG_EVL_INITIALISED              ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucI2cInitialised                %s\n\r", ( ullAmcInitStatus & AMC_CFG_I2C_INITIALISED              ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucEepromInitialised             %s\n\r", ( ullAmcInitStatus & AMC_CFG_EEPROM_INITIALISED           ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucSysmonInitialised             %s\n\r", ( ullAmcInitStatus & AMC_CFG_SYSMON_INITIALISED           ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucSmbusPcieLinkInitialised      %s\n\r", ( ullAmcInitStatus & AMC_CFG_SMBUS_PCIE_LINK_INITIALISED  ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucMuxedDeviceFalInitialised     %s\n\r", ( ullAmcInitStatus & AMC_CFG_MUXED_DEVICE_FAL_INITIALISED ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucGcqFalInitialised             %s\n\r", ( ullAmcInitStatus & AMC_CFG_MUXED_DEVICE_FAL_CREATED     ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucEmmcFalInitialised            %s\n\r", ( ullAmcInitStatus & AMC_CFG_GCQ_FAL_INITIALISED          ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucOspiFalInitialised            %s\n\r", ( ullAmcInitStatus & AMC_CFG_GCQ_FAL_CREATED              ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucSmbusFalInitialised           %s\n\r", ( ullAmcInitStatus & AMC_CFG_EMMC_FAL_INITIALISED         ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucMuxedDeviceFalCreated         %s\n\r", ( ullAmcInitStatus & AMC_CFG_EMMC_FAL_CREATED             ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucGcqFalCreated                 %s\n\r", ( ullAmcInitStatus & AMC_CFG_OSPI_FAL_INITIALISED         ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucEmmcFalCreated                %s\n\r", ( ullAmcInitStatus & AMC_CFG_OSPI_FAL_CREATED             ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucOspiFalCreated                %s\n\r", ( ullAmcInitStatus & AMC_CFG_SMBUS_FAL_INITIALISED        ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucSmbusFalCreated               %s\n\r", ( ullAmcInitStatus & AMC_CFG_SMBUS_FAL_CREATED            ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucApcInitialised                %s\n\r", ( ullAmcInitStatus & AMC_CFG_APC_INITIALISED              ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucAxcInitialised                %s\n\r", ( ullAmcInitStatus & AMC_CFG_AXC_INITIALISED              ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucAscInitialised                %s\n\r", ( ullAmcInitStatus & AMC_CFG_ASC_INITIALISED              ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucAmiInitialised                %s\n\r", ( ullAmcInitStatus & AMC_CFG_AMI_INITIALISED              ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucBmcInitialised                %s\n\r", ( ullAmcInitStatus & AMC_CFG_BMC_INITIALISED              ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucAsdmInitialised               %s\n\r", ( ullAmcInitStatus & AMC_CFG_ASDM_INITIALISED             ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucInBandInitialised             %s\n\r", ( ullAmcInitStatus & AMC_CFG_IN_BAND_INITIALISED          ? "TRUE" : "FALSE" ) );
    PLL_INF( AMC_NAME, "ucOutOfBandInitialised          %s\n\r", ( ullAmcInitStatus & AMC_CFG_OUT_OF_BAND_INITIALISED      ? "TRUE" : "FALSE" ) );

    // Upon init retrieved ack queue Head and Tail to be align with the driver
    // Read driver tail position and aligned head to have empty queue
    HAL_INVALIDATE_CACHE_DATA( (uintptr_t) (toAmiIopAckqTail), sizeof(uint32_t) );
    ackq_tail = * toAmiIopAckqTail;
    ackq_head = ackq_tail;
    *toAmiIopAckqHead = ackq_head;
    HAL_FLUSH_CACHE_DATA( (uintptr_t) (toAmiIopAckqHead), sizeof(uint32_t) );

    // create queue for mhdma related actions
    if ( OSAL_ERRORS_NONE != iOSAL_MBox_Create(&xMhdmaCommandMbox, 10, sizeof(MhdmaCommand_t),"Mhdma Queue") ) {
       PLL_ERR( AMC_NAME, "failed creating MHDMA MBOX\r\n" );
    } else {
       PLL_ERR( AMC_NAME, "MHDMA MBOX initialised\r\n" );
    }

    if ( OSAL_ERRORS_NONE != iOSAL_Task_Create(&xMhdmaWorkerTask, vMhdmaWorkerTask, 4096, NULL, AMC_TASK_PRIO_DEFAULT, "Mhdma Worker") ) {
       PLL_ERR( AMC_NAME, "failed creating MHDMA worker task\r\n" );
    } else {
       PLL_ERR( AMC_NAME, "MHDMA worker task initialised\r\n" );
    }

    // Initialise Interrupts
    if( OSAL_ERRORS_NONE != iOSAL_Interrupt_Setup( XPAR_FABRIC_RTL_INTERRUPT_1_INTR, vInterruptHandler_isc_ack, NULL ) ) {
       PLL_ERR( AMC_NAME, "failed init isc interruption\r\n" );
    } else {
       PLL_ERR( AMC_NAME, "interrupt handler on isc interrupt initialised\r\n" );
    }
    XScuGic_SetPriorityTriggerType(
       &xInterruptController,
       XPAR_FABRIC_RTL_INTERRUPT_1_INTR,
       HIGH_PRIORITY_INTR,
       EDGE_SENSITIVE_INTR
    );
    if( OSAL_ERRORS_NONE != iOSAL_Interrupt_Enable( XPAR_FABRIC_RTL_INTERRUPT_1_INTR) ) {
       PLL_ERR( AMC_NAME, "failed enabling isc interrupt\r\n" );
    } else {
       PLL_ERR( AMC_NAME, "enabling isc interrupt on rising edge\r\n" );
    }
    if( OSAL_ERRORS_NONE != iOSAL_Interrupt_Setup( XPAR_FABRIC_RTL_INTERRUPT_0_INTR, vInterruptHandler_debug, NULL ) ) {
       PLL_ERR( AMC_NAME, "failed init interrupt hpu_interrupt[0](debug)\r\n" );
    } else {
       PLL_INF( AMC_NAME, "interrupt handler on hpu_interrupt[0](debug) initialised\r\n" );
    }
    if( OSAL_ERRORS_NONE != iOSAL_Interrupt_Enable( XPAR_FABRIC_RTL_INTERRUPT_0_INTR) ) {
       PLL_ERR( AMC_NAME, "failed enabling interrupt hpu_interrupt[0](debug)\r\n" );
    } else {
       PLL_INF( AMC_NAME, "enabling hpu_interrupt[0](debug) on level\r\n" );
    }
    if( OSAL_ERRORS_NONE != iOSAL_Interrupt_Setup( XPAR_FABRIC_RTL_INTERRUPT_3_INTR, vInterruptHandler_mhdma_notify, NULL ) ) {
       PLL_ERR( AMC_NAME, "failed init interrupt hpu_interrupt[3](notify)\r\n" );
    } else {
       PLL_INF( AMC_NAME, "interrupt handler on hpu_interrupt[3](notify) initialised\r\n" );
    }
    if( OSAL_ERRORS_NONE != iOSAL_Interrupt_Enable( XPAR_FABRIC_RTL_INTERRUPT_3_INTR) ) {
       PLL_ERR( AMC_NAME, "failed enabling interrupt hpu_interrupt[3](notify)\r\n" );
    } else {
       PLL_INF( AMC_NAME, "enabling hpu_interrupt[3](notify) on level\r\n" );
    }
    if( OSAL_ERRORS_NONE != iOSAL_Interrupt_Setup( XPAR_FABRIC_RTL_INTERRUPT_4_INTR, vInterruptHandler_mhdma_read_complete, NULL ) ) {
       PLL_ERR( AMC_NAME, "failed init interrupt hpu_interrupt[4](read_complete)\r\n" );
    } else {
       PLL_INF( AMC_NAME, "interrupt handler on hpu_interrupt[4](read_complete) initialised\r\n" );
    }
    if( OSAL_ERRORS_NONE != iOSAL_Interrupt_Enable( XPAR_FABRIC_RTL_INTERRUPT_4_INTR) ) {
       PLL_ERR( AMC_NAME, "failed enabling interrupt hpu_interrupt[4](read_complete)\r\n" );
    } else {
       PLL_INF( AMC_NAME, "enabling hpu_interrupt[4](read_complete) on level\r\n" );
    }
  
    // init
    {
      iop_state_init();
      b2b_pool_init();
      dst_notifyq_init();
      src_notifyq_init();
      dst_store_init();
    }

    // Init IOp queue descriptor
    volatile uint32_t *fromAmiIopqHead = NULL;
    volatile uint32_t *fromAmiIopqTail = NULL;
    fromAmiIopqHead = ( volatile uint32_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + OFFSET_FROM_AMI_IOPQ_HEAD );
    fromAmiIopqTail = ( volatile uint32_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + OFFSET_FROM_AMI_IOPQ_TAIL );
    // invalidate bytes in cache, data in cache is lost and not written in DDR
    volatile uintptr_t fromAmiIopqData  = (volatile uintptr_t)( HAL_RPU_SHARED_MEMORY_BASE_ADDR + OFFSET_FROM_AMI_IOPQ_DATA_START);

    // Upon init retrieved Head and Tail to be align with the driver
    // Read driver head position and aligned tail to have an empty queue
    HAL_INVALIDATE_CACHE_DATA( (uintptr_t) (fromAmiIopqHead), sizeof(uint32_t) );
    HAL_INVALIDATE_CACHE_DATA( (uintptr_t) (fromAmiIopqTail), sizeof(uint32_t) );
    uint32_t iopq_head = * fromAmiIopqHead;
    uint32_t iopq_tail = iopq_head;
    * fromAmiIopqTail = iopq_tail;
    HAL_FLUSH_CACHE_DATA( (uintptr_t) (fromAmiIopqTail), sizeof(uint32_t) );

    // Runtime configuration
    UcoreCfg_t ucore_cfg = {0};

    // IOp/Dop translation buffer
    uint32_t iop_buffer[IOP_MAX_WORDS];
    uint32_t dop_buffer[DOP_BUFFER_SIZE];
    // Various structure used by iop parser
    IOpHeader_t header;
    IOpMapping_t mapping;
    IOpOperandProp_t operand_prop;
    IOpOperandAddr_t operand_addr;
    IOpImmHeader_t imm_header;
    OperandBundle_t dst_bundle;
    OperandBundle_t src_bundle;
    ImmediatBundle_t imm_bundle;

    Lookup_t dop_entry;
    DOpu_t   dop;
    bool stop_consuming_iop = false;

    FOREVER {
        uint32_t write_isc_rv = OK;
        // ----------------------------------------------------------------------------------------
        // Second handle IOp queue containing IOp pushed by AMI driver
        // Update queue pointer
        // NB: Tail is only written by AMC after init
        // -> No need to invalidate the cache
        HAL_INVALIDATE_CACHE_DATA( (uintptr_t) (fromAmiIopqHead), sizeof(uint32_t) );
        iopq_head = * fromAmiIopqHead;
        iopq_tail = * fromAmiIopqTail;

        uint32_t iopq_used_bytes = iopq_head - iopq_tail;

        // NB: AMI push IOp in an atomic pattern
        // -> i.e. Head pointer move only once per IOp, thus if queue isn't empty it contain at least a full Iop
        // NB': IOp words could crossed the queue bondaries and thus could be split on two chunks. To prevent issue with IOp parsing,
        //      they are copied in a continuous buffer before parsing.
        //      This buffer have the depth of the longest supported IOp (Currently fixed at compile time)
        //      After parsing only the used bytes are consumed from the queue
        if (iopq_used_bytes != 0 && !stop_consuming_iop) {
            if (debug_intr_global_cnt%2 == 0) {
                PLL_ERR("AMC", "interrupt[1](isc) count %d edges", isc_intr_global_cnt);
                PLL_ERR("AMC", "interrupt[0](debug) count %d level at 1", debug_intr_global_cnt);
                PLL_ERR("AMC", "interrupt[3](mhdma notify) count %d", intr_notify_cnt);
                PLL_ERR("AMC", "interrupt[4](mhdma readc) count %x", intr_readc_cnt);
                PLL_ERR("AMC", "iop_state: %d/%d %d/%d", iop_state[1].state, iop_state[1].nb_hpu, iop_state[2].state, iop_state[2].nb_hpu);
            }
            PLL_INF("AMC", "Fw received IOP request, translation into DOP needed [head 0x%x; tail 0x%x]", iopq_head, iopq_tail);

            // Update ucore configuration
            updt_ucore_cfg(&ucore_cfg);
            PLL_ERR("AMC", "Current core config: node_id %d", ucore_cfg.node_id);
            phys_hpu_id = ucore_cfg.node_id;
            PLL_ERR("AMC", "Current core config: phys_hpu_id %d", phys_hpu_id);

            // 1. Compute bytes to read from queue
            uint32_t read_bytes = (iopq_used_bytes > IOP_MAX_BYTES)? IOP_MAX_BYTES: iopq_used_bytes;

            // 2. Compute chunks index and size
            uint32_t chunk_idx = iopq_tail % AMI_IOPQ_MAX_BYTES;
            uint32_t chunk_size = ((AMI_IOPQ_MAX_BYTES -chunk_idx) < read_bytes)? (AMI_IOPQ_MAX_BYTES - chunk_idx): read_bytes;
            uint32_t wrap_chunk_size = read_bytes - chunk_size;

            // 3. Read Data from the queue
            if (chunk_size > 0) {
                volatile uintptr_t data_ptr = fromAmiIopqData + chunk_idx;
                HAL_INVALIDATE_CACHE_DATA(data_ptr, chunk_size);
                for (uint32_t i =0; i < chunk_size/sizeof(uint32_t); i++) {
                    iop_buffer[i] = * (uint32_t *)(data_ptr + i*sizeof(uint32_t));
                }
            } else {
                if (iopq_used_bytes > 0) {
                    PLL_ERR("IOpQ", "iopq_used_bytes %d > 0 but chunk_size = %d (tail %x head %x)", iopq_used_bytes, chunk_size, iopq_tail, iopq_head);
                }
            }
            if (wrap_chunk_size > 0) {
                volatile uintptr_t data_ptr = fromAmiIopqData;
                HAL_INVALIDATE_CACHE_DATA( data_ptr, wrap_chunk_size);
                for (uint32_t i = 0; i < wrap_chunk_size/sizeof(uint32_t); i++) {
                    iop_buffer[i+chunk_size/sizeof(uint32_t)] = * (uint32_t *)(data_ptr + i*sizeof(uint32_t));
                }
            }
            for (int i =0; i < IOP_MAX_WORDS; i++) {
                PLL_DBG("IOpQ", "@%d -> 0x%x", i, iop_buffer[i]);
            }

            // Parse IOp and store in lookup for ack
            // uint32_t iop_complete_len = 0x10;
            PLL_INF("ParseIOp", "@slot[%d] header 0x%x [len_bytes %d]", chunk_idx, iop_buffer[0], read_bytes);
            uint32_t iop_complete_len = parse_iop(iop_buffer, read_bytes, &header, &mapping, &operand_prop, &operand_addr, &imm_header, &dst_bundle, &src_bundle, &imm_bundle);
            PLL_INF("ParseIOp", "IOp [0x%x] [map %x] [dst %d] [src %d] [imm %d] [stream_len %d]", header.header.opcode, mapping.raw, dst_bundle.len, src_bundle.len, imm_bundle.len, iop_complete_len);
            PLL_ERR("AMC", "Current iid: %d", cur_iid);

            if (iop_complete_len != 0) {
                // Update tail of IOp queue
                iopq_tail += iop_complete_len;
                *fromAmiIopqTail = iopq_tail;
                HAL_FLUSH_CACHE_DATA((uintptr_t)fromAmiIopqTail, sizeof(uint32_t));
                PLL_INF("AMC", "One IOp parsed [head 0x%x, tail 0x%x]", iopq_head, iopq_tail);


                // Retrieved DOp stream, patch it and send it to Isc
                if (get_lookup(header, mapping, ucore_cfg.node_id, &dop_entry)) {
                    PLL_ERR("IOpQ", "Incorrect IOp processed [head 0x%x, last-tail 0x%x, current-tail 0x%x]", iopq_head, iopq_tail, (iopq_tail - iop_complete_len));
                    PLL_ERR("IOpQ", "chunk_idx %x chunk_size %d iop_complete_len %d", chunk_idx, chunk_size, iop_complete_len);
                    iOSAL_Task_SleepTicks(2000);
                    for (int i =0; i < 7; i++) {
                        PLL_ERR("IOpQ", "@%d -> 0x%x", i, Xil_EndianSwap32(iop_buffer[i]));
                        iOSAL_Task_SleepTicks(2000);
                    }
                    stop_consuming_iop = true;
                    iOSAL_Task_SleepTicks(2000);
                }

                PLL_DBG("UCORE", "Translation will patch and push %d dops @0x%x", dop_entry.len, dop_entry.ptr);
                // Patch and stream DOps to HW
                for (int i=0; i< dop_entry.len; i++) {
                  dop.raw = *(dop_entry.ptr + i);
                  if (patch_dop(&dop, &dst_bundle, &src_bundle, &imm_bundle)) {
                    // it means current DOp was a UCORE DOp that got processed and removed from stream
                    continue;
                  }
                  dop_buffer[i%DOP_BUFFER_SIZE] = dop.raw;

                  // Flush buffer if full
                  if (((i+1) % DOP_BUFFER_SIZE) == 0) {
                    PLL_INF("UCORE", "flush %d value to isc (i %d, len %d)", DOP_BUFFER_SIZE, i, dop_entry.len);
                    PLL_DBG("UCORE", "dop_buffer %x %x %x",dop_buffer[0], dop_buffer[1], dop_buffer[2]);
                    write_isc_rv = write_isc(dop_buffer, (uint32_t) (DOP_BUFFER_SIZE * sizeof(uint32_t)));
                    while (write_isc_rv == RETRY) {
                        PLL_INF("UCORE", "retry flush %d value to isc (i %d, len %d)", DOP_BUFFER_SIZE, i, dop_entry.len);
                        iOSAL_Task_SleepTicks(20);
                        write_isc_rv = write_isc(dop_buffer, (uint32_t) (DOP_BUFFER_SIZE * sizeof(uint32_t)));
                    }
                  }
                }

                // Add DOp sync
                DOpu_t dop_sync;
                dop_sync.sync.opcode = SYNC_OPCODE;
                dop_sync.sync.iid = cur_iid;
                dop_sync.sync.is_inner = 0;
                dop_sync.sync.flag = 0;
                dop_sync.sync._pad = 0;
                dop_buffer[dop_entry.len % DOP_BUFFER_SIZE] = dop_sync.raw;
                // Correctly handle full buffer flush
                uint32_t remaining_dop = (((dop_entry.len+1)%DOP_BUFFER_SIZE) == 0)? DOP_BUFFER_SIZE:(dop_entry.len+1)%DOP_BUFFER_SIZE;
                PLL_INF("UCORE", "flush %d remaining value to isc", remaining_dop);
                write_isc_rv = write_isc(dop_buffer, (uint32_t) (remaining_dop * sizeof(uint32_t)));
                while (write_isc_rv == RETRY) {
                    PLL_INF("UCORE", "retry flush %d remaining value to isc", remaining_dop);
                    iOSAL_Task_SleepTicks(20);
                    write_isc_rv = write_isc(dop_buffer, (uint32_t) (remaining_dop * sizeof(uint32_t)));
                }
            } else {
                PLL_ERR("IOpQ", "Invalid IOp at %x stream ABORT dequeue (%d, %d, tail %x, head %x))", chunk_idx, chunk_size, wrap_chunk_size, iopq_tail, iopq_head);
                for (int i =0; i < 7; i++) {
                    PLL_ERR("IOpQ", "invalid @%d -> 0x%x", i, Xil_EndianSwap32(iop_buffer[i]));
                    iOSAL_Task_SleepTicks(2000);
                }
                stop_consuming_iop = true;
                iOSAL_Task_SleepTicks(2000);
            }
        }
        // Give hand back to scheduler for other tasks
        iOSAL_Task_SleepTicks(1);
    }
}

/**
 * @brief   Main entry point
 */
int main( void )
{
    void *pvMainTaskHandle = NULL;

    if( OSAL_ERRORS_OS_NOT_STARTED != iOSAL_StartOS( TRUE,
                                                     &pvMainTaskHandle,
                                                     &vTaskFuncMain,
                                                     AMC_TASK_DEFAULT_STACK,
                                                     AMC_TASK_PRIO_DEFAULT ) )
    {
        PLL_ERR( AMC_NAME, "Error failed to start the OS Task\r\n" );
    }

    return -1;
}


/******************************************************************************/
/* EVL Callback Implementations                                               */
/******************************************************************************/

/**
 * @brief   AXC Proxy Driver EVL callback
 */
static int iAxcCallback( EVL_SIGNAL *pxSignal )
{
    int iStatus = ERROR;

    if( ( NULL != pxSignal ) && ( AMC_CFG_UNIQUE_ID_AXC == pxSignal->ucModule ) )
    {
        switch( pxSignal->ucEventType )
        {
        case AXC_PROXY_DRIVER_E_QSFP_PRESENT:
        {
            iStatus = OK;
            break;
        }

        case AXC_PROXY_DRIVER_E_QSFP_NOT_PRESENT:
        {
            iStatus = OK;
            break;
        }

        default:
        {
            break;
        }
        }
    }

    return iStatus;
}

/**
 * @brief   APC Proxy Driver EVL callback
 */
static int iApcCallback( EVL_SIGNAL *pxSignal )
{
    int iStatus = ERROR;

    if( ( NULL != pxSignal ) && ( AMC_CFG_UNIQUE_ID_APC == pxSignal->ucModule ) )
    {
        switch( pxSignal->ucEventType )
        {
        case APC_PROXY_DRIVER_E_DOWNLOAD_STARTED:
        {
            iStatus = OK;
            break;
        }

        case APC_PROXY_DRIVER_E_DOWNLOAD_COMPLETE:
        {
            iStatus = iAMI_SetPdiDownloadCompleteResponse( pxSignal, AMI_PROXY_RESULT_SUCCESS );
            break;
        }

        case APC_PROXY_DRIVER_E_DOWNLOAD_FAILED:
        {
            iStatus = iAMI_SetPdiDownloadCompleteResponse( pxSignal, AMI_PROXY_RESULT_FAILURE );
            break;
        }

        case APC_PROXY_DRIVER_E_DOWNLOAD_BUSY:
        {
            iStatus = iAMI_SetPdiDownloadCompleteResponse( pxSignal, AMI_PROXY_RESULT_ALREADY_IN_PROGRESS );
            break;
        }

        case APC_PROXY_DRIVER_E_COPY_STARTED:
        {
            iStatus = OK;
            break;
        }

        case APC_PROXY_DRIVER_E_COPY_COMPLETE:
        {
            iStatus = iAMI_SetPdiCopyCompleteResponse( pxSignal, AMI_PROXY_RESULT_SUCCESS );
            break;
        }

        case APC_PROXY_DRIVER_E_COPY_FAILED:
        {
            iStatus = iAMI_SetPdiCopyCompleteResponse( pxSignal, AMI_PROXY_RESULT_FAILURE );
            break;
        }

        case APC_PROXY_DRIVER_E_COPY_BUSY:
        {
            iStatus = iAMI_SetPdiCopyCompleteResponse( pxSignal, AMI_PROXY_RESULT_ALREADY_IN_PROGRESS );
            break;
        }

        case APC_PROXY_DRIVER_E_PARTITION_SELECTED:
        {
            iStatus = iAMI_SetBootSelectCompleteResponse( pxSignal, AMI_PROXY_RESULT_SUCCESS );
            break;
        }

        case APC_PROXY_DRIVER_E_PARTITION_SELECTION_FAILED:
        {
            iStatus = iAMI_SetBootSelectCompleteResponse( pxSignal, AMI_PROXY_RESULT_FAILURE );
            break;
        }

        default:
        {
            break;
        }
        }
    }

    return iStatus;
}

/**
 * @brief   AMI Proxy Driver EVL callback
 */
static int iAmiCallback( EVL_SIGNAL *pxSignal )
{
    int iStatus = ERROR;

    if( ( NULL != pxSignal ) && ( AMC_CFG_UNIQUE_ID_AMI == pxSignal->ucModule ) )
    {
        switch( pxSignal->ucEventType )
        {
        case AMI_PROXY_DRIVER_E_GET_IDENTITY:
        {
            PLL_DBG( AMC_NAME, "Event Get Identity (0x%02X)\r\n", pxSignal->ucEventType );

            AMI_PROXY_RESULT xResult = AMI_PROXY_RESULT_SUCCESS;

            GCQ_VERSION_TYPE xGcqVersion =
            {
                0
            };
            if( OK != iGCQGetVersion( &xGcqVersion ) )
            {
                PLL_DBG( AMC_NAME, "Error getting GCQ version\r\n" );
                xResult = AMI_PROXY_RESULT_FAILURE;
            }

            AMI_PROXY_IDENTITY_RESPONSE xIdentityResponse =
            {
                .ucVerMajor     = ( uint8_t )GIT_TAG_VER_MAJOR,
                .ucVerMinor     = ( uint8_t )GIT_TAG_VER_MINOR,
                .ucVerPatch     = ( uint8_t )GIT_TAG_VER_PATCH,
                .ucLocalChanges = ( uint8_t )( GIT_STATUS )?( 1 ):( 0 ),
                .usDevCommits   = ( uint16_t )GIT_TAG_VER_DEV_COMMITS,
                .ucLinkVerMajor = xGcqVersion.ucVerMajor,
                .ucLinkVerMinor = xGcqVersion.ucVerMinor
            };
            iStatus = iAMI_SetIdentityResponse( pxSignal, xResult, &xIdentityResponse );

            /* AMI is ready - enable hot reset */
            if( OK == iAPC_EnableHotReset( pxSignal ) )
            {
                PLL_DBG( AMC_NAME, "Hot reset enabled\r\n" );
            }

            if( OK == iPLL_SendBootRecords() )
            {
                PLL_INF( AMC_NAME, "Boot logs sent OK\r\n" );
                iStatus = OK;
            }
            else
            {
                PLL_ERR( AMC_NAME, "ERROR sending boot logs\r\n" );
            }

            break;
        }

        default:
        {
            iStatus = OK;
            break;
        }
        }
    }

    return iStatus;
}

/**
 * @brief   BMC Proxy Driver EVL callback
 */
static int iBmcCallback( EVL_SIGNAL *pxSignal )
{
    int iStatus = ERROR;

    if( ( NULL != pxSignal ) && ( AMC_CFG_UNIQUE_ID_BMC == pxSignal->ucModule ) )
    {
        switch( pxSignal->ucEventType )
        {
        default:
        {
            break;
        }
        }
    }

    return iStatus;
}

/**
 * @brief   Get project info
 */
static void vGetProjectInfo( void )
{
    char    pcOsName[ OSAL_OS_NAME_LEN ] = "unknown";
    uint8_t ucVerMaj                     = 0, ucVerMin = 0, ucVerBld = 0;

    iOSAL_GetOsVersion( pcOsName, &ucVerMaj, &ucVerMin, &ucVerBld );

    /* Sleep so we don't interfere with any other prints. */
    iOSAL_Task_SleepMs( AMC_GET_PROJECT_INFO_SLEEP_MS );

    vPLL_Printf( "\r\n" );
    vPLL_Printf( "###############################################################\r\n" );
    vPLL_Printf( "#                                                             #\r\n" );
    vPLL_Printf( "#                             AMC                             #\r\n" );
    vPLL_Printf( "#                                                             #\r\n" );
    vPLL_Printf( "# Copyright (c) 2024 Advanced Micro Devices, Inc.             #\r\n" );
    vPLL_Printf( "# All rights reserved.                                        #\r\n" );
    vPLL_Printf( "#                                                             #\r\n" );
    vPLL_Printf( "# SPDX-License-Identifier: MIT                                #\r\n" );
    vPLL_Printf( "#                                                             #\r\n" );
    vPLL_Printf( "###############################################################\r\n" );
    PLL_LOG( AMC_NAME,
             "AMC: %d.%d.%d-%d.%.*s.%.*s%c\r\n",
             GIT_TAG_VER_MAJOR,
             GIT_TAG_VER_MINOR,
             GIT_TAG_VER_PATCH,
             GIT_TAG_VER_DEV_COMMITS,
             AMC_HASH_LEN,
             GIT_HASH,
             AMC_DATE_LEN,
             GIT_DATE,
             ( GIT_STATUS )?( '*' ):( ' ' ) );
    PLL_LOG( AMC_NAME,
             "OS:  %s v%u.%u.%u\r\n",
             pcOsName,
             ucVerMaj,
             ucVerMin,
             ucVerBld );
    vPLL_Printf( "\r\n\r\n" );
}

/**
 * @brief   Initialise core libraries
 */
static int iInitCoreLibs( void )
{
    int iStatus = ERROR;

    if( OK == iPLL_Initialise( AMC_OUTPUT_LEVEL, AMC_LOGGING_LEVEL ) )
    {
        PLL_INF( AMC_NAME, "PLL initialised OK\r\n" );
        iStatus           = OK;
        ullAmcInitStatus |= AMC_CFG_PLL_INITIALISED;
    }
    else
    {
        PLL_ERR( AMC_NAME, "PLL initialisation ERROR\r\n" );
    }

    if( OK == iEVL_Initialise() )
    {
        PLL_INF( AMC_NAME, "EVL initialised OK\r\n" );
        iStatus           = OK;
        ullAmcInitStatus |= AMC_CFG_EVL_INITIALISED;
    }
    else
    {
        PLL_ERR( AMC_NAME, "EVL initialisation ERROR\r\n" );
    }

    return iStatus;
}

/**
 * @brief   Initialise device drivers
 */
static int iInitDeviceDrivers( void )
{
    int iStatus = OK;

    if( OK == iI2C_Init( xI2cCfg, I2C_DEFAULT_BUS_IDLE_WAIT_MS ) )
    {
        PLL_INF( AMC_NAME, "I2C driver Initialised OK\r\n" );
        ullAmcInitStatus |= AMC_CFG_I2C_INITIALISED;
    }
    else
    {
        PLL_ERR( AMC_NAME, "I2C driver Initialisation ERROR\r\n" );
        iStatus = ERROR;
    }

    if( AMC_CFG_I2C_INITIALISED == ( ullAmcInitStatus & AMC_CFG_I2C_INITIALISED ) )
    {
        if( OK == iEEPROM_Initialise( HAL_EEPROM_VERSION, &xEepromCfg ) )
        {
            PLL_INF( AMC_NAME, "iEEPROM_Initialised OK\r\n" );
            ullAmcInitStatus |= AMC_CFG_EEPROM_INITIALISED;

            if( ERROR == iEEPROM_DisplayEepromValues( ) )
            {
                PLL_ERR( AMC_NAME, "iEEPROM_DisplayEepromValues FAILED\r\n" );
            }
        }
        else
        {
            PLL_ERR( AMC_NAME, "iEEPROM_Initialised FAILED\r\n" );
        }
    }

    if( OK == iSYS_MON_Initialise() )
    {
        PLL_INF( AMC_NAME, "SysMon Driver Initialised OK\r\n" );
        ullAmcInitStatus |= AMC_CFG_SYSMON_INITIALISED;
    }
    else
    {
        PLL_ERR( AMC_NAME, "SysMon Driver Initialisation ERROR\r\n" );
        iStatus = ERROR;
    }

    return iStatus;
}

/**
 * @brief   Initialise Proxy Driver layer
 */
static int iInitProxies( void )
{
    int iStatus = OK;

    if( AMC_CFG_APC_PREREQUISITES == ( ullAmcInitStatus & AMC_CFG_APC_PREREQUISITES ) )
    {
        if( OK == iAPC_Initialise( AMC_CFG_UNIQUE_ID_APC,
                                   pxOspiIf,
                                   pxEmmcIf,
                                   AMC_TASK_PRIO_DEFAULT,
                                   AMC_TASK_DEFAULT_STACK ) )
        {
            if( OK == iAPC_BindCallback( &iApcCallback ) )
            {
                PLL_INF( AMC_NAME, "APC Proxy Driver initialised and bound\r\n" );
            }
            else
            {
                PLL_ERR( AMC_NAME, "Error binding to APC Proxy Driver\r\n" );
            }
            ullAmcInitStatus |= AMC_CFG_APC_INITIALISED;
        }
        else
        {
            PLL_ERR( AMC_NAME, "Error initialising APC Proxy Driver\r\n" );
            iStatus = ERROR;
        }
    }

    if( 0 != MAX_NUM_EXTERNAL_DEVICES_AVAILABLE )
    {
        if( AMC_CFG_AXC_PREREQUISITES == ( ullAmcInitStatus & AMC_CFG_AXC_PREREQUISITES ) )
        {
            if( OK == iAXC_Initialise( AMC_CFG_UNIQUE_ID_AXC, AMC_TASK_PRIO_DEFAULT, AMC_TASK_DEFAULT_STACK ) )
            {
                if( OK == iAXC_BindCallback( &iAxcCallback ) )
                {
                    if( ( OK == iAXC_AddExternalDevice( &xQsfpDevice1 ) ) &&
                        ( OK == iAXC_AddExternalDevice( &xQsfpDevice2 ) ) &&
                        ( OK == iAXC_AddExternalDevice( &xQsfpDevice3 ) ) &&
                        ( OK == iAXC_AddExternalDevice( &xQsfpDevice4 ) ) &&
                        ( OK == iAXC_AddExternalDevice( &xDimmDevice ) ) )
                    {
                        PLL_INF( AMC_NAME, "AXC Proxy Driver initialised and bound\r\n" );
                        ullAmcInitStatus |= AMC_CFG_AXC_INITIALISED;
                    }
                    else
                    {
                        PLL_ERR( AMC_NAME, "Error adding External Device to AXC Proxy Driver\r\n" );
                    }
                }
                else
                {
                    PLL_ERR( AMC_NAME, "Error binding to AXC Proxy Driver\r\n" );
                    iStatus = ERROR;
                }
            }
            else
            {
                PLL_ERR( AMC_NAME, "Error initialising AXC Proxy Driver\r\n" );
                iStatus = ERROR;
            }
        }
    }
    else
    {
        PLL_INF( AMC_NAME, "No external devices available - skipping AXC initialisation\r\n" );
        ullAmcInitStatus |= AMC_CFG_AXC_INITIALISED;
    }

    if( AMC_CFG_ASC_PREREQUISITES == ( ullAmcInitStatus & AMC_CFG_ASC_PREREQUISITES ) )
    {
        if( OK == iASC_Initialise( AMC_CFG_UNIQUE_ID_ASC,
                                   AMC_TASK_PRIO_DEFAULT,
                                   AMC_TASK_DEFAULT_STACK,
                                   PROFILE_SENSORS_SENSOR_DATA,
                                   PROFILE_SENSORS_NUM_SENSORS ) )
        {
            PLL_INF( AMC_NAME, "ASC Proxy Driver initialised\r\n" );
            ullAmcInitStatus |= AMC_CFG_ASC_INITIALISED;
        }
        else
        {
            PLL_ERR( AMC_NAME, "Error initialising ASC Proxy Driver\r\n" );
            iStatus = ERROR;
        }
    }

    if( AMC_CFG_AMI_PREREQUISITES == ( ullAmcInitStatus & AMC_CFG_AMI_PREREQUISITES ) )
    {
        if( OK == iAMI_Initialise( AMC_CFG_UNIQUE_ID_AMI,
                                   &xGcqIf,
                                   0,
                                   AMC_TASK_PRIO_DEFAULT,
                                   AMC_TASK_DEFAULT_STACK ) )
        {
            if( OK == iAMI_BindCallback( &iAmiCallback ) )
            {
                PLL_INF( AMC_NAME, "AMI Proxy Driver initialised and bound\r\n" );
                ullAmcInitStatus |= AMC_CFG_AMI_INITIALISED;
            }
            else
            {
                PLL_ERR( AMC_NAME, "Error binding to AMI Proxy Driver\r\n" );
            }
        }
        else
        {
            PLL_ERR( AMC_NAME, "Error initialising AMI Proxy Driver\r\n" );
            iStatus = ERROR;
        }
    }

    if( NULL != pxSMBusIf )
    {
        /* Get the UUID */
        uint8_t ucUuidSize               = 0;
        uint8_t pucUuid[ HAL_UUID_SIZE ] =
        {
            0
        };

        if( AMC_CFG_I2C_INITIALISED == ( ullAmcInitStatus & AMC_CFG_I2C_INITIALISED ) )
        {
            if( AMC_CFG_EEPROM_INITIALISED == ( ullAmcInitStatus & AMC_CFG_EEPROM_INITIALISED ) )
            {
                iStatus = iEEPROM_GetUuid( pucUuid, &ucUuidSize );
                if( OK == iStatus )
                {
                    if( HAL_UUID_SIZE != ucUuidSize )
                    {
                        PLL_ERR( AMC_NAME, "UUID Size incorrect\r\n" );
                        iStatus = ERROR;
                    }
                }
                else
                {
                    PLL_ERR( AMC_NAME, "Unable to read UUID\r\n" );
                }
            }
            else
            {
                /* Use the default (all 0s) UUID */
            }

            if( AMC_CFG_BMC_PREREQUISITES == ( ullAmcInitStatus & AMC_CFG_BMC_PREREQUISITES ) )
            {
                if( OK == iBMC_Initialise( AMC_CFG_UNIQUE_ID_BMC,
                                           pxSMBusIf,
                                           0,
                                           AMC_TASK_PRIO_DEFAULT,
                                           AMC_TASK_DEFAULT_STACK,
                                           pxPdrTemperatureSensors,
                                           TOTAL_PDR_TEMPERATURE,
                                           pxPdrVoltageSensors,
                                           TOTAL_PDR_VOLTAGE,
                                           pxPdrCurrentSensors,
                                           TOTAL_PDR_CURRENT,
                                           pxPdrPowerSensors,
                                           TOTAL_PDR_POWER,
                                           pxPdrSensorNames,
                                           TOTAL_PDR_NUMERIC_ASCI_SENSORS,
                                           pucUuid ) )
                {
                    if( OK == iBMC_BindCallback( &iBmcCallback ) )
                    {
                        PLL_INF( AMC_NAME, "BMC Proxy Driver initialised and bound\r\n" );
                        ullAmcInitStatus |= AMC_CFG_BMC_INITIALISED;
                    }
                    else
                    {
                        PLL_ERR( AMC_NAME, "Error binding to BMC Proxy Driver\r\n" );
                    }
                }
                else
                {
                    PLL_ERR( AMC_NAME, "Error initialising BMC Proxy Driver\r\n" );
                    iStatus = ERROR;
                }
            }
        }
    }
    return iStatus;
}

/**
 * @brief   Initialise App layer
 */
static int iInitApp( void )
{
    int iStatus = OK;

    if( AMC_CFG_ASDM_PREREQUISITES == ( ullAmcInitStatus & AMC_CFG_ASDM_PREREQUISITES ) )
    {
        if( OK != iASDM_Initialise( PROFILE_SENSORS_NUM_SENSORS ) )
        {
            PLL_ERR( AMC_NAME, "ASDM Initialisation ERROR\r\n" );
            iStatus = ERROR;
        }
        else
        {
            ullAmcInitStatus |= AMC_CFG_ASDM_INITIALISED;
        }
    }

    if( AMC_CFG_IN_BAND_PREREQUISITES == ( ullAmcInitStatus & AMC_CFG_IN_BAND_PREREQUISITES ) )
    {
        if( OK != iIN_BAND_TELEMETRY_Initialise( HAL_RPU_SHARED_MEMORY_BASE_ADDR ) )
        {
            PLL_ERR( AMC_NAME, "In Band Telemetry Initialisation ERROR\r\n" );
            iStatus = ERROR;
        }
        else
        {
            ullAmcInitStatus |= AMC_CFG_IN_BAND_INITIALISED;
            PLL_INF( AMC_NAME, "In-band service: ready\r\n" );
        }
    }

    if( AMC_CFG_OUT_OF_BAND_PREREQUISITES == ( ullAmcInitStatus & AMC_CFG_OUT_OF_BAND_PREREQUISITES ) )
    {
        if( OK != iOUT_OF_BAND_TELEMETRY_Initialise() )
        {
            PLL_ERR( AMC_NAME, "Out of Band Telemetry Initialisation ERROR\r\n" );
            iStatus = ERROR;
        }
        else
        {
            ullAmcInitStatus |= AMC_CFG_OUT_OF_BAND_INITIALISED;
            PLL_INF( AMC_NAME, "Out-of-band service: ready\r\n" );
        }
    }

    if( OK != iBIM_Initialise( PROFILE_BIM_MODULE_DATA ) )
    {
        PLL_ERR( AMC_NAME, "Built in Monitoring Initialisation ERROR\r\n" );
        iStatus = ERROR;
    }
    else
    {
        PLL_LOG( AMC_NAME, "Built in Monitoring (BIM) application started\r\n" );
    }

    return iStatus;
}

/**
 * @brief   Configure the partition table stored at the start of
 *          shared memory and used by the AMI to determine the AMC state
 */
static void vConfigurePartitionTable( void )
{
    HAL_PARTITION_TABLE xPartTable =
    {
        0
    };
    uint8_t *pucDestAdd = NULL;

    xPartTable.ulMagicNum                  = HAL_PARTITION_TABLE_MAGIC_NO;
    xPartTable.xRingBuffer.ulRingBufferOff = HAL_PARTITION_TABLE_SIZE;
    xPartTable.xRingBuffer.ulRingBufferLen = HAL_RPU_RING_BUFFER_LEN;
    xPartTable.xStatus.ulStatusOff         = HAL_PARTITION_TABLE_SIZE + HAL_RPU_RING_BUFFER_LEN;
    xPartTable.xStatus.ulStatusLen         = sizeof( uint32_t );
    xPartTable.xLogMsg.ulLogMsgIndex       = 0;
    xPartTable.xLogMsg.ulLogMsgBufferOff   = xPartTable.xStatus.ulStatusOff + xPartTable.xStatus.ulStatusLen;
    xPartTable.xLogMsg.ulLogMsgBufferLen   = PLL_LOG_BUF_LEN;
    xPartTable.xData.ulDataStart           = xPartTable.xLogMsg.ulLogMsgBufferOff +
                                             xPartTable.xLogMsg.ulLogMsgBufferLen;
    xPartTable.xData.ulDataEnd = HAL_RPU_SHARED_MEMORY_SIZE;

    /* Copy the populated table into the start of shared memory */
    pucDestAdd = ( uint8_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR );
    pvOSAL_MemCpy( pucDestAdd, ( uint8_t* )&xPartTable, sizeof( xPartTable ) );
    HAL_FLUSH_CACHE_DATA( HAL_RPU_SHARED_MEMORY_BASE_ADDR, sizeof( xPartTable ) );

    /* Flush stale logs */
    if( PLL_LOG_BUF_LEN >= xPartTable.xLogMsg.ulLogMsgBufferLen )
    {
        pvOSAL_MemSet( ( uint8_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + xPartTable.xLogMsg.ulLogMsgBufferOff ),
                       0,
                       xPartTable.xLogMsg.ulLogMsgBufferLen );
        HAL_FLUSH_CACHE_DATA( HAL_RPU_SHARED_MEMORY_BASE_ADDR + xPartTable.xLogMsg.ulLogMsgBufferOff,
                              xPartTable.xLogMsg.ulLogMsgBufferLen );
    }

    /*
     * AMI is waiting for the status to be set to a value of 0x1, currently we have no
     * concept of stopping/starting the AMC so once initialised this will always be valid
     */
    pucDestAdd = ( uint8_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + xPartTable.xStatus.ulStatusOff );
    pvOSAL_MemSet( pucDestAdd, HAL_ENABLE_AMI_COMMS, xPartTable.xStatus.ulStatusLen );
    HAL_FLUSH_CACHE_DATA( ( HAL_RPU_SHARED_MEMORY_BASE_ADDR + xPartTable.xStatus.ulStatusOff ),
                          xPartTable.xStatus.ulStatusLen );
}

/**
 * @brief Read runtime configuration from memory
 *        Discard cache status to enforce that it's latest version of the cfg
 */
static void updt_ucore_cfg(UcoreCfg_t* cfg)
{
  // Invalidate cache
  HAL_INVALIDATE_CACHE_DATA( (uintptr_t)DOP_FW_ADDR , FW_RUNTIME_MAX_WORD * sizeof(uint32_t));
  // Read value
  // NB: pvOSAL_MemCpy seems completly bugged on small size. replace it with explicit pointer read
  // pvOSAL_MemCpy((void*)DOP_FW_ADDR, (void*) cfg, sizeof(UcoreCfg_t));
  *cfg = *((volatile UcoreCfg_t*) DOP_FW_ADDR);
}

