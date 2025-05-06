/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains the function declarations for the INA3221
 * sensor.
 *
 * @file ina3221.h
 *
 */

#ifndef _INA3221_H_
#define _INA3221_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Read voltage using INA3221 sensor
 *
 * @param   ucBusNum       I2C bus number
 * @param   ucSlaveAddr    I2C slave address
 * @param   ucChannelNum   Channel number
 * @param   pfVoltageInMV  Pointer to voltage in milli Volts
 *
 * @return  OK             Voltage read successfully
 *          ERROR          Voltage not read successfully
 * 
 */
int iINA3221_ReadVoltage( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucChannelNum, float *pfVoltageInMV );

/**
 * @brief   Read current using INA3221 sensor
 *
 * @param   ucBusNum       I2C bus number
 * @param   ucSlaveAddr    I2C slave address
 * @param   ucChannelNum   Channel number
 * @param   pfCurrentInmA  Pointer to current in milli Amps
 *
 * @return  OK             Current read successfully
 *          ERROR          Current not read successfully
 * 
 */
int iINA3221_ReadCurrent( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucChannelNum, float *pfCurrentInmA );

/**
 * @brief   Calculate power using INA3221 voltage and current reads
 *
 * @param   ucBusNum      I2C bus number
 * @param   ucSlaveAddr   I2C slave address
 * @param   ucChannelNum  Channel number
 * @param   pfPowerInmW   Pointer to power in milli Watts
 *
 * @return  OK            Power read successfully
 *          ERROR         Power not read successfully
 * 
 */
int iINA3221_ReadPower( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucChannelNum, float *pfPowerInmW );

/**
 * @brief   Print all the stats gathered by the driver
 *
 * @return  OK                  Stats retrieved from driver successfully
 *          ERROR               Stats not retrieved successfully
 * 
 */
int iINA3221_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the driver
 *
 * @return  OK                  Stats cleared successfully
 *          ERROR               Stats not cleared successfully
 * 
 */
int iINA3221_ClearStatistics( void );

#endif
