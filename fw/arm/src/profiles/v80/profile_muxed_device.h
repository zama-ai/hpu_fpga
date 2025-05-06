/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the muxed device profile for V80
 *
 * @file profile_muxed_device.h
 *
 */

#ifndef _PROFILE_MUXED_DEVICE_H_
#define _PROFILE_MUXED_DEVICE_H_

#include "eeprom.h"
#include "pll.h"

/**
 * @brief   Calculate the number of expected QSFP and DIMM interfaces
 *
 * @param   iExpMax Expected maximum number
 *
 * @return  The number of available external devices (0) if none or if unable to calculate
 */
static inline int iGetNumExternalDevices( int iExpMax )
{
    static int     iNumQsfps          = 0;
    static uint8_t ucProductNameCheck = FALSE;

    if( FALSE == ucProductNameCheck )
    {
        uint8_t pucField[ EEPROM_MAX_FIELD_SIZE ] =
        { 0 };
        uint8_t ucSizeBytes = 0;

        if( OK == iEEPROM_GetProductName( pucField, &ucSizeBytes ) )
        {
            if( ( NULL != strstr( ( char* )pucField, "v80" ) ) ||
                ( NULL != strstr( ( char* )pucField, "V80" ) ) )
            {
                if( ( NULL == strstr( ( char* )pucField, "80p" ) ) &&
                    ( NULL == strstr( ( char* )pucField, "80P" ) ) )
                {
                    /* Running on a v80 but not a v80p */
                    iNumQsfps = iExpMax;
                }
            }

            ucProductNameCheck = TRUE;
        }
    }

    return iNumQsfps;
}

#define MAX_NUM_EXTERNAL_DEVICES_AVAILABLE iGetNumExternalDevices( 5 )

#define QSFP_1_REG_BIT_OFFSET ( 1 << 0 )
#define QSFP_2_REG_BIT_OFFSET ( 1 << 1 )
#define QSFP_3_REG_BIT_OFFSET ( 1 << 2 )
#define QSFP_4_REG_BIT_OFFSET ( 1 << 3 )

#define MUXED_DEVICE_MUX_1_ADDR    ( 0x70 )
#define MUXED_DEVICE_MUX_2_ADDR    ( 0x71 )
#define MUXED_DEVICE_MUX_3_ADDR    ( 0x72 )
#define MUXED_DEVICE_MUX_REG_BIT_1 ( 1 << 0 )
#define MUXED_DEVICE_MUX_REG_BIT_2 ( 1 << 1 )
#define MUXED_DEVICE_MUX_REG_BIT_3 ( 1 << 2 )
#define MUXED_DEVICE_MUX_REG_BIT_4 ( 1 << 3 )

#define QSFP_POWER_IO_EXPANDER_I2C_ADDR ( 0x21 )
#define QSFP_IO_EXPANDER_I2C_ADDR       ( 0x20 )
#define QSFP_I2C_ADDR                   ( 0x50 )
#define DIMM_I2C_ADDR                   ( 0x18 )

#endif
