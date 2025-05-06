/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains structures, type definitions and function declarations
 * for the OSPI driver.
 *
 * @file ospi.h
 *
 */

#ifndef _OSPI_H_
#define _OSPI_H_


/******************************************************************************/
/* Typedefs                                                                   */
/******************************************************************************/

/**
 * @struct  OSPI_CFG_TYPE
 * @brief   The OSPI device configuration
 */
typedef struct OSPI_CFG_TYPE
{
    uint8_t ucDeviceId;
    uint16_t usPageSize;

} OSPI_CFG_TYPE;


/******************************************************************************/
/* Driver External APIs                                                       */
/******************************************************************************/

/**
 * @brief   Initialises the OSPI driver.
 *
 * @param   pxOspiCfg           The configuration parameters for the OSPI device
 *
 * @return  OK if successful, else ERROR.
 */
int iOSPI_FlashInit( OSPI_CFG_TYPE *pxOspiCfg );

/**
 * @brief   Function to erase the flash device.
 *
 * @param   ulAddr              The start address to erase
 * @param   ulLength            The total number of bytes to be erased
 *
 * @return  OK if successful, else ERROR.
 */
int iOSPI_FlashErase( uint32_t ulAddr, uint32_t ulLength );

/**
 * @brief   Function to read a number of bytes from the flash device.
 *
 * @param   ulAddr              The start address to read the data
 * @param   pucReadBuffer       Pointer to buffer to populate with the bytes read
 * @param   pulLength           Length of read buffer passed in, updated to the length of response in bytes
 *
 * @return  OK if successful, else ERROR.
 */
int iOSPI_FlashRead( uint32_t ulAddr, uint8_t *pucReadBuffer, uint32_t *pulLength );

/**
 * @brief   Function to write a number of bytes to the flash device.
 *
 * @param   ulAddr              The start address to write the data
 * @param   pucWriteBuffer      Pointer to buffer containing the bytes to write
 * @param   pulLength           Length of write buffer
 *
 * @return  OK if successful, else ERROR.
 */
int iOSPI_FlashWrite( uint32_t ulAddr, uint8_t *pucWriteBuffer, uint32_t ulLength );

/**
 * @brief   Return the progress of the current operation
 *
 * @param   pucPercentage       The percentage
 *
 * @return  OK if successful, else ERROR.
 */
int iOSPI_GetOperationProgress( uint8_t *pucPercentage );

/**
 * @brief   Print all the stats gathered by the driver
 *
 * @return  OK                  Stats retrieved from proxy driver successfully
 *          ERROR               Stats not retrieved successfully
 */
int iOSPI_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the driver
 *
 * @return  OK                  Stats cleared successfully
 *          ERROR               Stats not cleared successfully
 */
int iOSPI_ClearStatistics( void );

#endif /* _OSPI_H_ */
