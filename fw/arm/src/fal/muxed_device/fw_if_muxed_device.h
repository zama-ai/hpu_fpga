/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains the FW IF Muxed Device abstraction definitions.
 *
 * @file fw_if_muxed_device.h
 *
 */

#ifndef _FW_IF_MUXED_DEVICE_H_
#define _FW_IF_MUXED_DEVICE_H_

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
 * @enum  FW_IF_MUXED_DEVICE_HW_LEVEL_TYPE
 * @brief Enumeration of hw level for read/write functionality
 *        QSFP IO expander control lines, or QSFP or DIMM mem map registers
 */
typedef enum _FW_IF_MUXED_DEVICE_HW_LEVEL_TYPE
{
    FW_IF_MUXED_DEVICE_HW_LEVEL_IO_EXPANDER = 0,
    FW_IF_MUXED_DEVICE_HW_LEVEL_MEMORY_MAP,

    MAX_FW_IF_MUXED_DEVICE_HW_LEVEL

} FW_IF_MUXED_DEVICE_HW_LEVEL_TYPE;

/**
 * @enum _FW_IF_MUXED_DEVICE_IOCTL_TYPE
 * @brief ioctrl options for Muxed Device interfaces (generic across all Muxed Device interfaces)
 */
typedef enum _FW_IF_MUXED_DEVICE_IOCTL_TYPE
{
    FW_IF_MUXED_DEVICE_IOCTL_SET_IO_EXPANDER = MAX_FW_IF_COMMON_IOCTRL_OPTION,
    FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP,

    MAX_FW_IF_MUXED_DEVICE_IOCTL_TYPE

} FW_IF_MUXED_DEVICE_IOCTL_TYPE;


/**
 * @enum FW_IF_DEVICE_TYPE
 * @brief Device type for FW_IF Mux interface
 */
typedef enum FW_IF_DEVICE_TYPE
{
    FW_IF_DEVICE_QSFP = 0,
    FW_IF_DEVICE_DIMM,

    MAX_FW_IF_DEVICE_TYPE

} FW_IF_DEVICE_TYPE;

/**
 * @enum FW_IF_MUX_ADDRESS_TYPE
 * @brief Enumeration for non selected mux addresses
 */
typedef enum FW_IF_MUX_ADDRESS_TYPE
{
    FW_IF_MUX_ADDRESS_0 = 0,
    FW_IF_MUX_ADDRESS_1,

    MAX_FW_IF_MUX_ADDRESS

} FW_IF_MUX_ADDRESS_TYPE;


/*****************************************************************************/
/* Structs                                                                   */
/*****************************************************************************/

/**
 * @struct  FW_IF_MUXED_DEVICE_INIT_CFG
 * @brief   config options for Muxed Device initialisation
 *          (generic across all Muxed Device interfaces)
 */
typedef struct _FW_IF_MUXED_DEVICE_INIT_CFG
{
    char            *pcDriverName;
    uint8_t         ulI2CBusNum;

} FW_IF_MUXED_DEVICE_INIT_CFG;

/**
 * @struct  FW_IF_MUXED_DEVICE_CFG
 * @brief   config options for Muxed Device interfaces
 *          (generic across all Muxed Device interfaces)
 */
typedef struct _FW_IF_MUXED_DEVICE_CFG
{
    FW_IF_DEVICE_TYPE                   xDevice;
    uint8_t                             ucPowerIoExpanderAddr;
    uint8_t                             ucPowerIoExpanderRegBit;
    uint8_t                             ucSelectedMuxAddr;
    uint8_t                             pucUnselectedMuxAddr[ MAX_FW_IF_MUX_ADDRESS ];
    uint32_t                            ulMuxRegBitIoExpander;
    uint32_t                            ulMuxRegBit;
    uint8_t                             ucIoExpanderAddr;
    uint8_t                             ucDeviceI2cAddr;
    FW_IF_MUXED_DEVICE_HW_LEVEL_TYPE    xHwLevel;

} FW_IF_MUXED_DEVICE_CFG;

/*****************************************************************************/
/* Public Functions                                                          */
/*****************************************************************************/

/**
 * @brief   initialisation function for MUXED_DEVICE interfaces
 *          (generic across all MUXED_DEVICE interfaces)
 *
 * @param   xInitCfg         pointer to the config to initialise the driver with
 *
 * @return  See FW_IF_ERRORS
 */
extern uint32_t ulFW_IF_MUXED_DEVICE_Init( FW_IF_MUXED_DEVICE_INIT_CFG *pxInitCfg );

/**
 * @brief   creates an instance of the MUXED_DEVICE interface
 *
 * @param   xFwIf       fw_if handle to the interface instance
 * @param   xQsfpCfg    unique data of this instance (port, address, etc)
 *
 * @return  See FW_IF_ERRORS
 */
extern uint32_t ulFW_IF_MUXED_DEVICE_Create( FW_IF_CFG *pxFwIf, FW_IF_MUXED_DEVICE_CFG *pxQsfpCfg );

/**
 * @brief   Print all the stats gathered by the application
 *
 * @return  See FW_IF_ERRORS
 *
 */
extern uint32_t ulFW_IF_MUXED_DEVICE_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the application
 *
 * @return  See FW_IF_ERRORS
 *
 */
extern uint32_t ulFW_IF_MUXED_DEVICE_ClearStatistics( void );

#endif
