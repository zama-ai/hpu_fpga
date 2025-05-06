/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the event definitions and the initialisation status
 * bitmasks for the AMC
 *
 * @file amc_cfg.h
 *
 */

#ifndef _AMC_CFG_H_
#define _AMC_CFG_H_


/******************************************************************************/
/* Defines                                                                      */
/******************************************************************************/

/* Initialise core libraries */
#define AMC_CFG_PLL_INITIALISED ( ( uint64_t )1 << 0 )
#define AMC_CFG_EVL_INITIALISED ( ( uint64_t )1 << 1 )

/* Initialise device drivers */
#define AMC_CFG_I2C_INITIALISED    ( ( uint64_t )1 << 5 )
#define AMC_CFG_EEPROM_INITIALISED ( ( uint64_t )1 << 6 )
#define AMC_CFG_SYSMON_INITIALISED ( ( uint64_t )1 << 7 )

/* Initialise FAL layer */
#define AMC_CFG_SMBUS_PCIE_LINK_INITIALISED  ( ( uint64_t )1 << 12 )
#define AMC_CFG_MUXED_DEVICE_FAL_INITIALISED ( ( uint64_t )1 << 20 )
#define AMC_CFG_MUXED_DEVICE_FAL_CREATED     ( ( uint64_t )1 << 21 )
#define AMC_CFG_GCQ_FAL_INITIALISED          ( ( uint64_t )1 << 22 )
#define AMC_CFG_GCQ_FAL_CREATED              ( ( uint64_t )1 << 23 )
#define AMC_CFG_EMMC_FAL_INITIALISED         ( ( uint64_t )1 << 24 )
#define AMC_CFG_EMMC_FAL_CREATED             ( ( uint64_t )1 << 25 )
#define AMC_CFG_OSPI_FAL_INITIALISED         ( ( uint64_t )1 << 26 )
#define AMC_CFG_OSPI_FAL_CREATED             ( ( uint64_t )1 << 27 )
#define AMC_CFG_SMBUS_FAL_INITIALISED        ( ( uint64_t )1 << 28 )
#define AMC_CFG_SMBUS_FAL_CREATED            ( ( uint64_t )1 << 29 )

/* Initialise Proxies */
#define AMC_CFG_APC_INITIALISED ( ( uint64_t )1 << 40 )
#define AMC_CFG_AXC_INITIALISED ( ( uint64_t )1 << 41 )
#define AMC_CFG_ASC_INITIALISED ( ( uint64_t )1 << 42 )
#define AMC_CFG_AMI_INITIALISED ( ( uint64_t )1 << 43 )
#define AMC_CFG_BMC_INITIALISED ( ( uint64_t )1 << 44 )

/* Initialise Applications */
#define AMC_CFG_ASDM_INITIALISED        ( ( uint64_t )1 << 51 )
#define AMC_CFG_IN_BAND_INITIALISED     ( ( uint64_t )1 << 52 )
#define AMC_CFG_OUT_OF_BAND_INITIALISED ( ( uint64_t )1 << 53 )

#define AMC_CFG_APC_PREREQUISITES ( ( uint64_t )( AMC_CFG_OSPI_FAL_INITIALISED ) )

#define AMC_CFG_AXC_PREREQUISITES ( ( uint64_t )( AMC_CFG_I2C_INITIALISED | \
                                                  AMC_CFG_MUXED_DEVICE_FAL_INITIALISED ) )

#define AMC_CFG_ASC_PREREQUISITES ( ( uint64_t )( AMC_CFG_I2C_INITIALISED |              \
                                                  AMC_CFG_MUXED_DEVICE_FAL_INITIALISED | \
                                                  AMC_CFG_AXC_INITIALISED ) )

#define AMC_CFG_AMI_PREREQUISITES ( ( uint64_t )( AMC_CFG_GCQ_FAL_INITIALISED ) )

#define AMC_CFG_BMC_PREREQUISITES ( ( uint64_t )( AMC_CFG_SMBUS_PCIE_LINK_INITIALISED | \
                                                  AMC_CFG_SMBUS_FAL_INITIALISED ) )

#define AMC_CFG_ASDM_PREREQUISITES ( ( uint64_t )( AMC_CFG_APC_INITIALISED | \
                                                   AMC_CFG_ASC_INITIALISED | \
                                                   AMC_CFG_EEPROM_INITIALISED ) )

#define AMC_CFG_IN_BAND_PREREQUISITES ( ( uint64_t )( AMC_CFG_AMI_INITIALISED | \
                                                      AMC_CFG_ASDM_INITIALISED ) )

#define AMC_CFG_OUT_OF_BAND_PREREQUISITES ( ( uint64_t )( AMC_CFG_ASC_INITIALISED | \
                                                          AMC_CFG_BMC_INITIALISED ) )


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    AMC_EVENT_UNIQUE_IDS
 * @brief   Unique ID of each proxy driver
 */
typedef enum AMC_CFG_UNIQUE_IDS
{
    AMC_CFG_UNIQUE_ID_AXC,
    AMC_CFG_UNIQUE_ID_APC,
    AMC_CFG_UNIQUE_ID_ASC,
    AMC_CFG_UNIQUE_ID_AMI,
    AMC_CFG_UNIQUE_ID_BMC,
    MAX_AMC_CFG_UNIQUE_ID

} AMC_CFG_UNIQUE_IDS;

#endif /* _AMC_CFG_H_ */
