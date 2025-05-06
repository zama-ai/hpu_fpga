/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains the function declarations for the ISL68221
 * sensor.
 *
 * @file isl68221.h
 *
 */

#ifndef _ISL68221_H_
#define _ISL68221_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    ISL68221_SENSOR_PAGE_ENUM
 * @brief   Sensor page to read
 */
typedef enum ISL68821_SENSOR_PAGE_ENUM
{
    ISL68221_SENSOR_PAGE_0 = 0,
    ISL68221_SENSOR_PAGE_1,
    ISL68221_SENSOR_PAGE_2,

    MAX_ISL68221_SENSOR_PAGE

} ISL68221_SENSOR_PAGE_ENUM;


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Read voltage using ISL68221 sensor
 *
 * @param   ucBusNum       I2C bus number
 * @param   ucSlaveAddr    I2C slave address
 * @param   ucPageNum      Page number
 * @param   pfVoltageInMV  Pointer to voltage in milli Volts
 *
 * @return  OK             Voltage read successfully
 *          ERROR          Voltage not read successfully
 * 
 */
int iISL68221_ReadVoltage( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucPageNum, float *pfVoltageInMV );

/**
 * @brief   Read current using ISL68221 sensor
 *
 * @param   ucBusNum      I2C bus number
 * @param   ucSlaveAddr   I2C slave address
 * @param   ucPageNum     Page number
 * @param   pfCurrentInA  Pointer to current in Amps
 *
 * @return  OK            Current read successfully
 *          ERROR         Current not read successfully
 * 
 */
int iISL68221_ReadCurrent( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucPageNum, float *pfCurrentInA );

/**
 * @brief   Read temperature using ISL68221 sensor
 *
 * @param   ucBusNum       I2C bus number
 * @param   ucSlaveAddr    I2C slave address
 * @param   ucPageNum      Page number
 * @param   pfTemperature  Pointer to temperature in Celcius
 *
 * @return  OK             Temperature read successfully
 *          ERROR          Temperature not read successfully
 * 
 */
int iISL68221_ReadTemperature( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucPageNum, float *pfTemperature );

/**
 * @brief   Print all the stats gathered by the driver
 *
 * @return  OK     Stats retrieved from driver successfully
 *          ERROR  Stats not retrieved successfully
 * 
 */
int iISL68221_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the driver
 *
 * @return  OK     Stats cleared successfully
 *          ERROR  Stats not cleared successfully
 * 
 */
int iISL68221_ClearStatistics( void );

#endif
