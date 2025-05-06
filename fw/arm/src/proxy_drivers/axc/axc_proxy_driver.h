/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the API for the AVED EXternal Device Control (AXC) proxy driver
 *
 * @file axc_proxy_driver.h
 *
 */

#ifndef _AXC_PROXY_DRIVER_H_
#define _AXC_PROXY_DRIVER_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"
#include "evl.h"
#include "fw_if.h"

#define AXC_LOWER_PAGE_SIZE ( 128 )
#define AXC_UPPER_PAGE_SIZE ( 128 )
#define AXC_PAGE_SIZE       ( AXC_LOWER_PAGE_SIZE + AXC_UPPER_PAGE_SIZE )

/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    AXC_PROXY_DRIVER_EVENTS
 * @brief   Events raised by this proxy driver
 */
typedef enum AXC_PROXY_DRIVER_EVENTS
{
    AXC_PROXY_DRIVER_E_QSFP_PRESENT  = 0x00,
    AXC_PROXY_DRIVER_E_QSFP_NOT_PRESENT,

    MAX_AXC_PROXY_DRIVER_EVENTS

} AXC_PROXY_DRIVER_EVENTS;

/**
 * @enum    AXC_PROXY_DRIVER_QSFP_IO
 * @brief   IO control lines of a QSFP module
 */
typedef enum AXC_PROXY_DRIVER_QSFP_IO
{
    AXC_PROXY_DRIVER_QSFP_IO_MODSEL = 0,
    AXC_PROXY_DRIVER_QSFP_IO_RESET,
    AXC_PROXY_DRIVER_QSFP_IO_LPMODE,
    AXC_PROXY_DRIVER_QSFP_IO_MODPRS,
    AXC_PROXY_DRIVER_QSFP_IO_INTERRUPT,

    MAX_AXC_PROXY_DRIVER_QSFP_IO

} AXC_PROXY_DRIVER_QSFP_IO;


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  AXC_PROXY_DRIVER_PAGE_DATA
 * @brief   Structure to hold device memory map data
 */
typedef struct AXC_PROXY_DRIVER_PAGE_DATA
{
    uint8_t     pucPageData[ AXC_UPPER_PAGE_SIZE ];
    uint32_t    ulPageDataSize;

} AXC_PROXY_DRIVER_PAGE_DATA;

/**
 * @struct  AXC_PROXY_DRIVER_QSFP_IO_STATUSES
 * @brief   Structure to hold QSFP IO statuses
 */
typedef struct AXC_PROXY_DRIVER_QSFP_IO_STATUSES
{
    uint8_t    ucModSel;
    uint8_t    ucReset;
    uint8_t    ucLpMode;
    uint8_t    ucModPrs;
    uint8_t    ucInterrupt;

} AXC_PROXY_DRIVER_QSFP_IO_STATUSES;

/**
 * @struct  AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG
 * @brief   Structure to hold unique ID for each External Device
 */
typedef struct AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG
{
    FW_IF_CFG   *pxExDevIf;
    uint8_t     ucExDeviceId;

} AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG;


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/* Init functions *************************************************************/

/**
 * @brief   Main initialisation point for the AXC Proxy Driver
 *
 * @param   ucProxyId   Unique ID for this Proxy driver
 * @param   ulTaskPrio  Priority of the Proxy driver task (if RR disabled)
 * @param   ulTaskStack Stack size of the Proxy driver task
 *
 * @return  OK          Proxy driver initialised correctly
 *          ERROR       Proxy driver not initialised, or was already initialised
 *
 * @note    Proxy drivers can have 0 or more firmware interfaces
 */
int iAXC_Initialise( uint8_t ucProxyId, uint32_t ulTaskPrio, uint32_t ulTaskStack );

/**
 * @brief   Initialise new External device. AXC proxy will check status and temperature
 *          of this device.
 *
 * @param   pxExDeviceCfg    Pointer to external device config
 *
 * @return  OK               Callback successfully bound
 *          ERROR            Callback not bound
 *
 */
int iAXC_AddExternalDevice( AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG *pxExDeviceCfg );

/**
 * @brief   Bind into this proxy driver
 *
 * @param   pxCallback  Callback to bind into the proxy driver
 *
 * @return  OK          Callback successfully bound
 *          ERROR       Callback not bound
 *
 */
int iAXC_BindCallback( EVL_CALLBACK *pxCallback );


/* Set functions **************************************************************/

/**
 * @brief   Write byte value to desired External Device memory map
 *
 * @param   ucExDeviceId    External Device Unique ID
 * @param   ulPage          Page to be accessed within QSFP memory map
 *                          N/A for DIMM
 * @param   ulByteOffset    Byte address/offset within memory map page
 * @param   ucValue         Value to be set
 *
 * @return  OK              Data passed to proxy driver successfully
 *          ERROR           Data not passed successfully
 *
 * @note    Byte offset range 0-127 will write a byte value to the lower page 00h.
 *
 *          Byte offset range 127-255 will write a byte value to the upper page.
 *          Use ulPage to specify which upper-page to be used.
 *
 */
int iAXC_SetByte( uint8_t ucExDeviceId, uint32_t ulPage, uint32_t ulByteOffset, uint8_t ucValue );


/* Get functions **************************************************************/

/**
 * @brief   Read real-time byte value from desired External Device memory map
 *
 * @param   ucExDeviceId    External Device Unique ID
 * @param   ulPage          Page to be accessed within QSFP memory map
 *                          N/A for DIMM
 * @param   ulByteOffset    Byte address/offset within memory map page
 * @param   pucValue        Pointer to retrieved value
 *
 * @return  OK              Data retrieved from proxy driver successfully
 *          ERROR           Data not retrieved successfully
 *
 * @note    Byte offset range 0-127 will read a byte value from the lower page 00h.
 *
 *          Byte offset range 127-255 will read a byte value from the upper page.
 *          Use ulPage to specify which upper-page to be used.
 */
int iAXC_GetByte( uint8_t ucExDeviceId, uint32_t ulPage, uint32_t ulByteOffset, uint8_t *pucValue );

/**
 * @brief   Read real-time memory map from desired QSFP
 *
 * @param   ucExDeviceId    External Device Unique ID
 * @param   ulPage          Page to be retrieved within QSFP memory map
 * @param   pxData          Pointer to retrieved data
 *
 * @return  OK              Data retrieved from proxy driver successfully
 *          ERROR           Data not retrieved successfully
 *
 * @note    This API will return the specified upper page from QSFP memory map
 */
int iAXC_GetPage( uint8_t ucExDeviceId, uint32_t ulPage, AXC_PROXY_DRIVER_PAGE_DATA *pxData );

/**
 * @brief   Read single status from QSFP IO Expander
 *
 * @param   ucExDeviceId    External Device Unique ID
 * @param   xIoControlLine  IO control line to be read
 * @param   pucIoStatus     Pointer to retrieved value
 *
 * @return  OK              Data retrieved from proxy driver successfully
 *          ERROR           Data not retrieved successfully
 *
 */
int iAXC_GetSingleIoStatus( uint8_t ucExDeviceId, AXC_PROXY_DRIVER_QSFP_IO xIoControlLine, uint8_t *pucIoStatus );

/**
 * @brief   Read all statuses from QSFP IO Expander
 *
 * @param   ucExDeviceId    External Device Unique ID
 * @param   pxIoStatuses    Pointer to data to get
 *
 * @return  OK              Data retrieved from proxy driver successfully
 *          ERROR           Data not retrieved successfully
 *
 */
int iAXC_GetAllIoStatuses( uint8_t ucExDeviceId, AXC_PROXY_DRIVER_QSFP_IO_STATUSES *pxIoStatuses );

/**
 * @brief   Read real-time temperature value from desired External Device memory map
 *
 * @param   ucExDeviceId    External Device Unique ID
 * @param   pfTemperature   Pointer to retrieved temperature value
 *
 * @return  OK              Data retrieved from proxy driver successfully
 *          ERROR           Data not retrieved successfully
 *
 * @note    pfTemperature   will be returned in degrees Celsius
 */
int iAXC_GetTemperature( uint8_t ucExDeviceId, float *pfTemperature );

/**
 * @brief   Gets the current state of the proxy driver
 *
 * @param   pxState         Pointer to the state
 *
 * @return  OK              If successful
 *          ERROR           If not successful
 */
int iAXC_GetState( MODULE_STATE *pxState );

/* Utility functions **********************************************************/

/**
 * @brief   Print all the stats gathered by the application
 *
 * @return  OK          Stats retrieved from proxy driver successfully
 *          ERROR       Stats not retrieved successfully
 *
 */
int iAXC_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the application
 *
 * @return  OK          Stats cleared successfully
 *          ERROR       Stats not cleared successfully
 *
 */
int iAXC_ClearStatistics( void );

/**
 * @brief   Check if a device exists and the page/byte offset are valid
 *
 * @return  OK          Provided values are valid
 *          ERROR       Device does not exist or values are invalid
 *
 */
int iAXC_ValidateRequest( uint8_t ucExDeviceId, uint32_t ulPage, uint32_t ulByteOffset );

#endif
