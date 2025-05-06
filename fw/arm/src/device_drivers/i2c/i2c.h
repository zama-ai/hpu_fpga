/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains structures, type definitions and function declarations
 * for the I2C driver.
 *
 * @file i2c.h
 *
 */

#ifndef _I2C_H_
#define _I2C_H_

#include "standard.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define I2C_NUM_INSTANCES            ( 2 )
#define I2C_DEFAULT_BUS_IDLE_WAIT_MS ( 2 * 1000 )


/******************************************************************************/
/* Typedefs                                                                   */
/******************************************************************************/

/**
 * @struct  I2C_CFG_TYPE
 * @brief   The I2C device configuration
 */
typedef struct I2C_CFG_TYPE
{
    uint8_t  ucDeviceId;                                                       /* Unique ID  of device */
    uint64_t ullBaseAddress;                                                   /* Base address of the device */
    uint32_t ulInputClockHz;                                                   /* Input clock frequency */
    uint8_t  ucReTryCount;                                                     /* Retry count in case of any communication failure */
    uint32_t ulSwResetOffset;                                                  /* Offset from the Base Address of the SW Reset Register */
    uint8_t  ucResetDuringInit;                                                /* Do software reset during initialisation */
    uint32_t ulHwResetAddress;                                                 /* Address of the HW Reset Register */
    uint32_t ulHwResetMask;                                                    /* Bit mask of the bit to toggle in HW Reset Register */
    uint8_t  ucHwResetDuringInit;                                              /* Do hardware reset during initialisation */

} I2C_CFG_TYPE;


/******************************************************************************/
/* Driver External APIs                                                       */
/******************************************************************************/

/**
 * @brief   Re-initialise the I2C driver.
 *
 * @param   ucDeviceId          The device id
 *
 * @return  OK                  If everything went well.
 *          ERROR               If the send data failed.
 */
int iI2C_ReInit( uint8_t ucDeviceId );

/**
 * @brief   Initialises the I2C driver.
 *
 * @param   pxI2cCfg            The configuration parameters for all I2C devices
 * @param   usBusIdleWaitMs     The maximum timeout waiting for the bus to become idle
 *
 * @return  OK                  Driver successfully init
 *          ERROR               Driver init failed
 */
int iI2C_Init( I2C_CFG_TYPE *pxI2cCfg, uint16_t usBusIdleWaitMs );

/**
 * @brief   This function reads data from the I2C device into a specified buffer.
 *
 * @param   ucDeviceId          the device id
 * @param   ucAddr              is the address of the slave we are sending to
 * @param   pucDataBuff         is the pointer to the send buffer
 * @param   ulLength            is the number of bytes to be sent
 *
 * @return  OK                  If everything went well.
 *          ERROR               If the send data failed.
 */
int iI2C_Send( uint8_t ucDeviceId,
               uint8_t ucAddr,
               uint8_t *pucDataBuff,
               uint32_t ulLength );

/**
 * @brief   This function write data from the I2C device into a specified buffer.
 *
 * @param   ucDeviceId          the device id
 * @param   ucAddr              is the address of the slave we are receiving from
 * @param   pucDataBuff         is the pointer to the receive buffer
 * @param   ulLength            is the number of bytes to be received
 *
 * @return  OK                  If everything went well.
 *          ERROR               If the receive data failed.
 */
int iI2C_Recv( uint8_t ucDeviceId,
               uint8_t ucAddr,
               uint8_t *pucDataBuff,
               uint32_t ulLength );

/**
 * @brief   This function sends data from the I2C device and waits for a response coming back.
 *
 * @param   ucDeviceId          the device id
 * @param   ucWriteAddr         is the address of the slave we are sending/receiving to
 * @param   pucWriteDataBuff    is the pointer to the send buffer
 * @param   ulWriteLength       is the number of bytes to be sent
 * @param   pucReadDataBuff     is the pointer to the receive buffer
 * @param   ulReadLength        is the number of bytes to be received
 *
 * @return  OK                  If everything went well.
 *          ERROR               If the send or receive failed.
 */
int iI2C_SendRecv( uint8_t ucDeviceId,
                   uint8_t ucWriteAddr,
                   uint8_t *pucWriteDataBuff,
                   uint32_t ulWriteLength,
                   uint8_t *pucReadDataBuff,
                   uint32_t ulReadLength );

/**
 * @brief   Print all the stats gathered by the driver
 *
 * @return  OK                  Stats retrieved from proxy driver successfully
 *          ERROR               Stats not retrieved successfully
 *
 */
int iI2C_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the driver
 *
 * @return  OK                  Stats cleared successfully
 *          ERROR               Stats not cleared successfully
 *
 */
int iI2C_ClearStatistics( void );

/**
 * @brief   Print the circular log
 *
 * @param   iDevice             The device id
 *
 * @return  OK                  Stats cleared successfully
 *          ERROR               Stats not cleared successfully
 *
 */
int iI2C_PrintLog( int iDevice );

#endif /* _I2C_H_ */
