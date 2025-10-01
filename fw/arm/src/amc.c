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
uint64_t intr_global_var = 5;

/******************************************************************************/
/* Function implementations                                                   */
/******************************************************************************/

void vInterruptHandler_zama0( void* pvCallBackRef ) {
    intr_global_var = intr_global_var + 1;
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

     // Init IOpAck queue descriptor
    volatile uint32_t *toAmiIopAckqHead = NULL;
    volatile uint32_t *toAmiIopAckqTail = NULL;
    toAmiIopAckqHead = ( volatile uint32_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + OFFSET_TO_AMI_IOPACKQ_HEAD );
    toAmiIopAckqTail = ( volatile uint32_t* )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + OFFSET_TO_AMI_IOPACKQ_TAIL );
    volatile uintptr_t toAmiIopAckqData = (volatile uintptr_t )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + OFFSET_TO_AMI_IOPACKQ_DATA_START );

    // Upon init retrieved Head and Tail to be align with the driver
    // Read driver tail position and aligned head to have empty queue
    HAL_INVALIDATE_CACHE_DATA( (uintptr_t) (toAmiIopAckqTail), sizeof(uint32_t) );
    // HAL_INVALIDATE_CACHE_DATA( (uintptr_t) (toAmiIopAckqHead), sizeof(uint32_t) );
    uint32_t ackq_tail = * toAmiIopAckqTail;
    uint32_t ackq_head = ackq_tail;
    *toAmiIopAckqHead = ackq_head;
    HAL_FLUSH_CACHE_DATA( (uintptr_t) (toAmiIopAckqHead), sizeof(uint32_t) );


    // IOp/Dop translation buffer
    uint32_t iop_buffer[IOP_MAX_WORDS];
    uint32_t dop_buffer[DOP_BUFFER_SIZE];
    // Various structure used by iop parser
    IOpHeader_t header;
    IOpOperand_t operand;
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
        // First forward Isc Ack to Host if any
        // In this (i.e. IOpAck queue) AMC is the producer
        // NB: Ack are pushed one by one to prevent handling of queue data boundaries crossing
        // -> No real impact on performances
        while (read_isc_ack_cnt() != 0) {
            // NB: Head is only written by AMC after init
            // -> No need to invalidate the cache
            ackq_head = * toAmiIopAckqHead;
            HAL_INVALIDATE_CACHE_DATA( (uintptr_t)toAmiIopAckqTail, sizeof(uint32_t) );
            ackq_tail = * toAmiIopAckqTail;
            uint32_t ackq_free_words = AMI_IOPACKQ_MAX_WORDS + ackq_tail - ackq_head;
            PLL_INF("AMC", "IOP Ack pending %d, AckQ [head 0x%x; tail 0x%x; free_w %d]", read_isc_ack_cnt(), ackq_head, ackq_tail, ackq_free_words);

            if (ackq_free_words == 0) {
                PLL_INF("AMC", "IOpAck queue is full, abort isc ack forwarding");
                break;
            } else {
                // Write ack value in queue body
                volatile uint32_t* ackq_idx = toAmiIopAckqData + ((ackq_head % AMI_IOPACKQ_MAX_WORDS) * sizeof(uint32_t));
                *ackq_idx = pop_isc_ack();
                HAL_FLUSH_CACHE_DATA( (uintptr_t)ackq_idx, sizeof(uint32_t));

                // Update queue head
                ackq_head += 1;
                *toAmiIopAckqHead = ackq_head;
                HAL_FLUSH_CACHE_DATA( (uintptr_t)toAmiIopAckqHead, sizeof(uint32_t));
            }
        }


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
            PLL_INF("AMC", "Fw received IOP request, translation into DOP needed [head 0x%x; tail 0x%x]", iopq_head, iopq_tail);

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
            uint32_t iop_complete_len = parse_iop(iop_buffer, read_bytes, &header, &operand, &imm_header, &dst_bundle, &src_bundle, &imm_bundle);
            PLL_INF("ParseIOp", "IOp [0x%x] [dst %d] [src %d] [imm %d] [stream_len %d]", header.header.opcode, dst_bundle.len, src_bundle.len, imm_bundle.len, iop_complete_len);

            if (iop_complete_len != 0) {
                // Update tail of IOp queue
                iopq_tail += iop_complete_len;
                *fromAmiIopqTail = iopq_tail;
                HAL_FLUSH_CACHE_DATA((uintptr_t)fromAmiIopqTail, sizeof(uint32_t));
                PLL_INF("AMC", "One IOp processed [head 0x%x, tail 0x%x]", iopq_head, iopq_tail);


                // Retrieved DOp stream, patch it and send it to Isc
                if (get_lookup(header, &dop_entry)) {
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
                  patch_dop(&dop, &dst_bundle, &src_bundle, &imm_bundle);
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
                dop_buffer[dop_entry.len % DOP_BUFFER_SIZE] = SYNC_DOP_WORD;
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
