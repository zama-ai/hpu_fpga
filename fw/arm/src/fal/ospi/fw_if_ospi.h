/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file containing the FW IF OSPI abstraction definitions.
 *
 * @file fw_if_ospi.h
 *
 */

#ifndef _FW_IF_OSPI_H_
#define _FW_IF_OSPI_H_


/*****************************************************************************/
/* Includes                                                                  */
/*****************************************************************************/

#include "fw_if.h"


/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/


/*****************************************************************************/
/* Enums                                                                     */
/*****************************************************************************/

/**
 * @enum FW_IF_OSPI_ERRORS
 * @brief Enumeration of OSPI return values
 */
typedef enum FW_IF_OSPI_ERRORS
{
    FW_IF_OSPI_ERRORS_INVALID_STATE = MAX_FW_IF_ERROR,
    FW_IF_OSPI_ERRORS_DRIVER_FAILURE,
    FW_IF_OSPI_ERRORS_DRIVER_INVALID_ADDRESS,

    MAX_FW_IF_OSPI_ERRORS

} FW_IF_OSPI_ERRORS;

/**
 * @enum FW_IF_OSPI_IOCTL
 * @brief ioctrl options for OSPI interfaces (generic across all OSPI interfaces)
 */
typedef enum FW_IF_OSPI_IOCTL
{
    FW_IF_OSPI_IOCTL_GET_PROGRESS = MAX_FW_IF_COMMON_IOCTRL_OPTION,

    MAX_FW_IF_OSPI_IOCTL

} FW_IF_OSPI_IOCTL;


/**
 * @enum FW_IF_OSPI_STATE
 * @brief ioctrl options for OSPI interfaces (generic across all OSPI interfaces)
 */
typedef enum FW_IF_OSPI_STATE
{
    FW_IF_OSPI_STATE_INIT,
    FW_IF_OSPI_STATE_OPENED,
    FW_IF_OSPI_STATE_CLOSED,
    FW_IF_OSPI_STATE_ERROR,

    MAX_FW_IF_OSPI_STATE

} FW_IF_OSPI_STATE;


/*****************************************************************************/
/* Structs                                                                   */
/*****************************************************************************/

/**
 * @struct  FW_IF_OSPI_INIT_CFG
 * @brief   config options for OSPI initialisation (generic across all OSPI interfaces)
 */
typedef struct FW_IF_OSPI_INIT_CFG
{
    uint8_t     ucOspiDeviceId;
    uint16_t    usPageSize;

} FW_IF_OSPI_INIT_CFG;

/**
 * @struct  FW_IF_OSPI_CFG
 * @brief   config options for OSPI interfaces (generic across all OSPI interfaces)
 */
typedef struct FW_IF_OSPI_CFG
{
    uint32_t            ulBaseAddress;
    uint32_t            ulLength;
    uint8_t             ucEraseBeforeWriteFlag;
    FW_IF_OSPI_STATE    xState;

} FW_IF_OSPI_CFG;


/*****************************************************************************/
/* Public Functions                                                          */
/*****************************************************************************/

/**
 * @brief   initialisation function for OSPI interfaces (generic across all OSPI interfaces)
 *
 * @param   pxInitCfg   pointer to the config to initialise the driver with
 *
 * @return  See FW_IF_ERRORS
 */
extern uint32_t ulFW_IF_OSPI_Init( FW_IF_OSPI_INIT_CFG *pxInitCfg );

/**
 * @brief   creates an instance of the OSPI interface
 *
 * @param   pxFWIf      fw_if handle to the interface instance
 * @param   pxOspiCfg   unique data of this instance
 *
 * @return  See FW_IF_ERRORS
 */
extern uint32_t ulFW_IF_OSPI_Create( FW_IF_CFG *pxFWIf, FW_IF_OSPI_CFG *pxOspiCfg );

/**
 *
 * @brief    Print all the stats gathered by the interface
 *
 * @return   OK                  Stats retrieved from fw_if_ospi successfully
 *           ERROR               Stats not retrieved successfully
 */
int iFW_IF_OSPI_PrintStatistics( void );

/**
 *
 * @brief    Clears all the stats gathered by the interface
 *
 * @return   OK                  Stats cleared successfully
 *           ERROR               Stats not cleared successfully
 */
int iFW_IF_OSPI_ClearStatistics( void );

#endif /* _FW_IF_OSPI_H_ */
