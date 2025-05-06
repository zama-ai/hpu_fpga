/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains the function declarations for the CAT34TS02
 * sensor.
 *
 * @file cat34ts02.h
 *
 */

#ifndef _CAT34TS02_H_
#define _CAT34TS02_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"


/******************************************************************************/
/* Function declaratations                                                    */
/******************************************************************************/

/**
 * @brief   Read temperature using CAT34TS02 sensor
 *
 * @param   ucI2cNum       I2C bus number
 * @param   ucSlaveAddr    I2C slave address
 * @param   ucChannelNum   Channel number (unused)
 * @param   pfTemperature  Pointer to temperature in Celcius
 *
 * @return  OK             Temperature read successfully
 *          ERROR          Temperature not read successfully
 *
 */
int iCAT34TS02_ReadTemperature( uint8_t ucI2cNum, uint8_t ucSlaveAddr, uint8_t ucChannelNum, float *pfTemperature );

/**
 * @brief   Print all the stats gathered by the driver
 *
 * @return  OK     Stats retrieved from driver successfully
 *          ERROR  Stats not retrieved successfully
 *
 */
int iCAT34TS02_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the driver
 *
 * @return  OK     Stats cleared successfully
 *          ERROR  Stats not cleared successfully
 *
 */
int iCAT34TS02_ClearStatistics( void );

#endif
