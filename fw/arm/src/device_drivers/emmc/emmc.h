/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains structures, type definitions and function declarations
 * for the EMMC driver.
 *
 * @file emmc.h
 *
 */

#ifndef _EMMC_H_
#define _EMMC_H_

#include "standard.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/


/******************************************************************************/
/* Typedefs                                                                   */
/******************************************************************************/


/******************************************************************************/
/* Driver External APIs                                                       */
/******************************************************************************/

/**
 * @brief   Initialises the EMMC driver.
 *
 * @param   ucDeviceId          The EMMC device ID
 *
 * @return  OK                  Driver successfully init
 *          ERROR               Driver init failed
 */
int iEMMC_Initialise( uint16_t ucDeviceId );

/**
 * @brief   Read from the EMMC.
 *
 * @param   ullAddress          The EMMC address to read from
 * @param   ulBlockCount        The number of blocks to read
 * @param   pucReadBuff         A pointer to the buffer to read into
 *
 * @return  OK                  Read was successful
 *          ERROR               Read failed
 */
int iEMMC_Read( uint64_t ullAddress, uint32_t ulBlockCount, uint8_t *pucReadBuff );

/**
 * @brief   Write to the EMMC.
 *
 * @param   ullAddress          The EMMC address to write to
 * @param   ulBlockCount        The number of blocks to write
 * @param   pucWriteBuff        A pointer to the write buffer
 *
 * @return  OK                  Write was successful
 *          ERROR               Write failed
 */
int iEMMC_Write( uint64_t ullAddress, uint32_t ulBlockCount, const uint8_t *pucWriteBuff );

/**
 * @brief   Erase blocks in the EMMC.
 * @param   ulStartBlockAddress Address of the first write block to be erased.
 * @param   ulEndBlockAddress   Address of the last write block of the continuous
 *                              range to be erased.
 *
 * @return  OK                  Erase was successful
 *          ERROR               Erase failed
 */
int iEMMC_Erase( uint64_t ullStartBlockAddress, uint64_t ullEndBlockAddress );

/**
 * @brief   Erase all the blocks in the EMMC.
 *
 * @return  OK                  Erase was successful
 *          ERROR               Erase failed
 */
int iEMMC_EraseAll( void );

/**
 * @brief   Print the EMMC detected device details.
 *
 * @return  OK                  Details printed successfully
 *          ERROR               Details not printed
 */
int iEMMC_PrintInstanceDetails( void );

/**
 * @brief   Print all the stats gathered by the driver
 *
 * @return  OK                  Stats retrieved from driver successfully
 *          ERROR               Stats not retrieved successfully
 *
 */
int iEMMC_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the driver
 *
 * @return  OK                  Stats cleared successfully
 *          ERROR               Stats not cleared successfully
 *
 */
int iEMMC_ClearStatistics( void );

#endif /* _EMMC_H_ */
