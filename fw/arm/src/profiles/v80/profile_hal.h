/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the hal profile for the V80
 *
 * @file profile_hal.h
 *
 */

#ifndef _PROFILE_HAL_H_
#define _PROFILE_HAL_H_

#include "eeprom.h"
#include "xparameters.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xsdps.h"

#define HAL_UUID_SIZE       ( 16 )
#define HAL_EMMC_FEATURE    ( 1 )
#define HAL_EMMC_DEVICE_ID  ( XPAR_XSDPS_0_DEVICE_ID )
#define HAL_EMMC_BLOCK_SIZE ( 512 )
#define HAL_EMMC_MAX_BLOCKS ( 0x7690000 )                                      /* 64 GBytes / 512 Bytes */

#define HAL_EEPROM_VERSION            ( EEPROM_VERSION_4_0 )
#define HAL_EEPROM_I2C_BUS            ( 0 )
#define HAL_EEPROM_SLAVE_ADDRESS      ( 0x52 )
#define HAL_EEPROM_ADDRESS_SIZE       ( 1 )
#define HAL_EEPROM_PAGE_SIZE          ( 16 )
#define HAL_EEPROM_NUM_PAGES          ( 16 )
#define HAL_EEPROM_DEVICE_ID          ( 0x0A01 )
#define HAL_EEPROM_DEVICE_ID_ADDRESS  ( 0x1A )
#define HAL_EEPROM_DEVICE_ID_REGISTER ( 0x07 )

#define HAL_AMC_CLOCK_CONTROL ( 1 )
#if ( 0 != HAL_AMC_CLOCK_CONTROL )
#ifdef XPAR_SHELL_UTILS_UCC_0_BASEADDR
#define HAL_USER_CLOCK_CONTROL_BASE_ADDRESS ( XPAR_SHELL_UTILS_UCC_0_BASEADDR )
#else
#define HAL_USER_CLOCK_CONTROL_BASE_ADDRESS ( 0x1 )
#endif
#endif

/* Apps */
/* AMC */
#define HAL_PARTITION_TABLE_SIZE                ( 0x1000 )
#define HAL_PARTITION_TABLE_MAGIC_NO            ( 0x564D5230 )
#define HAL_ENABLE_AMI_COMMS                    ( 0x1 )
#define HAL_RPU_RING_BUFFER_LEN                 ( 0x1000 )
#define HAL_RPU_SHARED_MEMORY_BASE_ADDR         ( 0x38000000 )
#define HAL_RPU_SHARED_MEMORY_END_ADDR          ( 0x3FFFF000 )
#define HAL_RPU_SHARED_MEMORY_SIZE              ( HAL_RPU_SHARED_MEMORY_END_ADDR - HAL_RPU_SHARED_MEMORY_BASE_ADDR )
#define HAL_RPU_RING_BUFFER_BASE                ( HAL_RPU_SHARED_MEMORY_BASE_ADDR + HAL_PARTITION_TABLE_SIZE )
#define HAL_BASE_LOGIC_GCQ_M2R_S01_AXI_BASEADDR ( XPAR_SHELL_WRAPPER_BASE_LOGIC_GCQ_M2R_S01_AXI_BASEADDR )

#define HAL_FLUSH_CACHE_DATA( addr, size ) Xil_DCacheFlushRange( addr, size )
#define HAL_INVALIDATE_CACHE_DATA( addr, size ) Xil_DCacheInvalidateRange( addr, size )

/* Definitions for peripheral CIPS_PSPMC_0_PSV_I2C_0 */
#define HAL_I2C_BUS_0_DEVICE_ID       ( XPAR_SHELL_WRAPPER_CIPS_PSPMC_0_PSV_I2C_0_DEVICE_ID )
#define HAL_I2C_BUS_0_BASEADDR        ( XPAR_SHELL_WRAPPER_CIPS_PSPMC_0_PSV_I2C_0_BASEADDR )
#define HAL_I2C_BUS_0_HIGHADDR        ( XPAR_SHELL_WRAPPER_CIPS_PSPMC_0_PSV_I2C_0_HIGHADDR )
#define HAL_I2C_BUS_0_I2C_CLK_FREQ_HZ ( UTIL_100KHZ )
#define HAL_I2C_BUS_0_RESET_ON_INIT   ( TRUE )
#define HAL_I2C_BUS_0_HW_DEVICE_RESET ( FALSE )

/* Definitions for peripheral CIPS_PSPMC_0_PSV_I2C_1 */
#define HAL_I2C_BUS_1_DEVICE_ID       ( XPAR_SHELL_WRAPPER_CIPS_PSPMC_0_PSV_I2C_1_DEVICE_ID )
#define HAL_I2C_BUS_1_BASEADDR        ( XPAR_SHELL_WRAPPER_CIPS_PSPMC_0_PSV_I2C_1_BASEADDR )
#define HAL_I2C_BUS_1_HIGHADDR        ( XPAR_SHELL_WRAPPER_CIPS_PSPMC_0_PSV_I2C_1_HIGHADDR )
#define HAL_I2C_BUS_1_I2C_CLK_FREQ_HZ ( UTIL_100KHZ )
#define HAL_I2C_BUS_1_RESET_ON_INIT   ( FALSE )
#define HAL_I2C_BUS_1_HW_DEVICE_RESET ( TRUE )

#define HAL_I2C_SW_RESET_BASEADDR     ( XPAR_SHELL_WRAPPER_CIPS_PSPMC_0_PSV_CRL_0_S_AXI_BASEADDR )
#define HAL_I2C_BUS_0_SW_RESET_OFFSET ( 0x330 )
#define HAL_I2C_BUS_1_SW_RESET_OFFSET ( 0x334 )
#define HAL_I2C_BUS_0_HW_RESET_ADDR   ( 0 )
#define HAL_I2C_BUS_0_HW_RESET_MASK   ( 0 )
#define HAL_I2C_BUS_1_HW_RESET_ADDR   ( 0xFF0B0040 )
#define HAL_I2C_BUS_1_HW_RESET_MASK   ( 1 << 13 )


#define HAL_I2C_DEFAULT_SCLK_RATE ( 33333333 )
#define HAL_I2C_RETRY_COUNT       ( 5 )

/* Definitions OSPI */
#define HAL_OSPI_0_DEVICE_ID              ( XPAR_XOSPIPSV_0_DEVICE_ID )
#define HAL_PSV_PMC_GLOBAL_0_AXI_BASEADDR ( XPAR_PSV_PMC_GLOBAL_0_S_AXI_BASEADDR )

/* FAL */
/* GCQ */
#ifndef HAL_IO_WRITE32
#define HAL_IO_WRITE32( val, addr ) ( { Xil_Out32( addr, val ); \
                                        Xil_DCacheFlushRange( addr, sizeof( uint32_t ) ); } )
#endif

#ifndef HAL_IO_WRITE32_NO_FLUSH
#define HAL_IO_WRITE32_NO_FLUSH( val, addr ) ( { Xil_Out32( addr, val ); } )
#endif

#ifndef HAL_IO_READ32
#define HAL_IO_READ32( addr ) ( { Xil_DCacheFlushRange( addr, sizeof( uint32_t ) ); \
                                  Xil_In32( addr ); } )
#endif

#ifndef HAL_IO_READ32_NO_FLUSH
#define HAL_IO_READ32_NO_FLUSH( addr ) ( { Xil_In32( addr ); } )
#endif

/* Proxies */
/* APC */
#define HAL_APC_PMC_BOOT_REG ( XPAR_PSV_PMC_GLOBAL_0_S_AXI_BASEADDR + 0x00004 )
#define HAL_APC_PMC_SRST_REG ( XPAR_PSV_PMC_GLOBAL_0_S_AXI_BASEADDR + 0x20084 )
#define HAL_APC_PDI_BIT_MASK ( 0x14 )

/* Core libs */
/* PLL */
#define HAL_FSBL_LOG_ADDRESS ( 0xF2019000 )
#define HAL_FSBL_LOG_SIZE    ( 0x4000 )

/**
 * @struct  HAL_PARTITION_TABLE_RING_BUFFER
 *
 * @brief   Stores the ring buffer info - part of the partition table.
 */
typedef struct HAL_PARTITION_TABLE_RING_BUFFER
{
    uint32_t ulRingBufferOff;
    uint32_t ulRingBufferLen;

} HAL_PARTITION_TABLE_RING_BUFFER;

/**
 * @struct  HAL_PARTITION_TABLE_STATUS
 *
 * @brief   Stores the AMC status info - part of the partition table.
 */
typedef struct HAL_PARTITION_TABLE_STATUS
{
    uint32_t ulStatusOff;
    uint32_t ulStatusLen;

} HAL_PARTITION_TABLE_STATUS;

/**
 * @struct  HAL_PARTITION_TABLE_LOG_MSG
 *
 * @brief   Stores the AMC logs and info - part of the partition table.
 */
typedef struct HAL_PARTITION_TABLE_LOG_MSG
{
    uint32_t ulLogMsgIndex;
    uint32_t ulLogMsgBufferOff;
    uint32_t ulLogMsgBufferLen;

} HAL_PARTITION_TABLE_LOG_MSG;

/**
 * @struct  HAL_PARTITION_TABLE_DATA
 *
 * @brief   Stores the AMC data - part of the partition table.
 */
typedef struct HAL_PARTITION_TABLE_DATA
{
    uint32_t ulDataStart;
    uint32_t ulDataEnd;

} HAL_PARTITION_TABLE_DATA;

/**
 * @struct  HAL_PARTITION_TABLE
 *
 * @brief   Table stored at the top of the shared memory and used by
 *          AMI to read offsets & state.
 */
typedef struct HAL_PARTITION_TABLE
{
    uint32_t                        ulMagicNum;
    HAL_PARTITION_TABLE_RING_BUFFER xRingBuffer;
    HAL_PARTITION_TABLE_STATUS      xStatus;
    HAL_PARTITION_TABLE_LOG_MSG     xLogMsg;
    HAL_PARTITION_TABLE_DATA        xData;

} HAL_PARTITION_TABLE;

#endif
