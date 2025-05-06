/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the API for the Alveo Programming Control (APC) proxy driver
 *
 * @file apc_proxy_driver.h
 *
 */

#ifndef _APC_PROXY_DRIVER_H_
#define _APC_PROXY_DRIVER_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"
#include "evl.h"
#include "fw_if.h"


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    APC_PROXY_DRIVER_EVENTS
 * @brief   Events raised by this proxy driver
 */
typedef enum APC_PROXY_DRIVER_EVENTS
{
    APC_PROXY_DRIVER_E_DOWNLOAD_STARTED = 0,
    APC_PROXY_DRIVER_E_DOWNLOAD_COMPLETE,
    APC_PROXY_DRIVER_E_DOWNLOAD_BUSY,
    APC_PROXY_DRIVER_E_DOWNLOAD_FAILED,
    APC_PROXY_DRIVER_E_FPT_UPDATE,
    APC_PROXY_DRIVER_E_COPY_STARTED,
    APC_PROXY_DRIVER_E_COPY_COMPLETE,
    APC_PROXY_DRIVER_E_COPY_BUSY,
    APC_PROXY_DRIVER_E_COPY_FAILED,
    APC_PROXY_DRIVER_E_PARTITION_SELECTED,
    APC_PROXY_DRIVER_E_PARTITION_SELECTION_FAILED,

    MAX_APC_PROXY_DRIVER_EVENTS

} APC_PROXY_DRIVER_EVENTS;

/**
 * @enum    APC_BOOT_DEVICES
 * @brief   Enumeration of boot devices available
 */
typedef enum
{
    APC_BOOT_DEVICE_PRIMARY = 0,
    APC_BOOT_DEVICE_SECONDARY,

    MAX_APC_BOOT_DEVICES

} APC_BOOT_DEVICES;


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  APC_PROXY_DRIVER_FPT_HEADER
 * @brief   Structure to hold the FPT Header
 */
typedef struct APC_PROXY_DRIVER_FPT_HEADER
{
    uint32_t    ulMagicNum;
    uint8_t     ucFptVersion;
    uint8_t     ucFptHeaderSize;
    uint8_t     ucEntrySize;
    uint8_t     ucNumEntries;

} APC_PROXY_DRIVER_FPT_HEADER;

/**
 * @struct  APC_PROXY_DRIVER_FPT_PARTITION
 * @brief   Structure to hold a single FPT partition
 */
typedef struct APC_PROXY_DRIVER_FPT_PARTITION
{
    uint32_t    ulPartitionType;
    uint32_t    ulPartitionBaseAddr;
    uint32_t    ulPartitionSize;

} APC_PROXY_DRIVER_FPT_PARTITION;


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Main initialisation point for the APC Proxy Driver
 *
 * @param   ucProxyId       Unique ID for this Proxy driver
 * @param   pxPrimaryFwIf   Handle to the primary Firmware Interface to use
 * @param   pxSecondaryFwIf Handle to the secondary Firmware Interface to use
 * @param   ulTaskPrio      Priority of the Proxy driver task (if RR disabled)
 * @param   ulTaskStack     Stack size of the Proxy driver task
 *
 * @return  OK          Proxy driver initialised correctly
 *          ERROR       Proxy driver not initialised, or was already initialised
 * 
 * @note    A Primary Firmware Interface handle must be passed to iAPC_Initialise, 
 *          the secondary Firmware Interface handle however is optional 
 *          and can be set to NULL.
 * 
 */
int iAPC_Initialise( uint8_t ucProxyId, FW_IF_CFG *pxPrimaryFwIf, FW_IF_CFG *pxSecondaryFwIf,
                     uint32_t ulTaskPrio, uint32_t ulTaskStack );

/**
 * @brief   Bind into this proxy driver
 *
 * @param   pxCallback  Callback to bind into the proxy driver
 *
 * @return  OK          Callback successfully bound
 *          ERROR       Callback not bound
 * 
 */
int iAPC_BindCallback( EVL_CALLBACK *pxCallback );

/**
 * @brief   Download an image to a location in NV memory
 *
 * @param   pxSignal     Current event occurance (used for tracking)
 * @param   xBootDevice  Target boot device
 * @param   iPartition   The partition in the FPT to store this image in
 * @param   ulSrcAddr    Address (in RAM) to read the image from
 * @param   ulImageSize  Size of image (in bytes)
 * @param   usPacketNum  Image packet number
 * @param   usPacketSize Size of image packet (in KB)
 *
 * @return  OK           Image downloaded successfully
 *          ERROR        Image not downloaded successfully
 * 
 */
int iAPC_DownloadImage( EVL_SIGNAL *pxSignal, APC_BOOT_DEVICES xBootDevice, int iPartition, uint32_t ulSrcAddr,
                        uint32_t ulImageSize, uint16_t usPacketNum, uint16_t usPacketSize );

/**
 * @brief   Download an image with an FPT to a location in NV memory
 *
 * @param   pxSignal     Current event occurance (used for tracking)
 * @param   xBootDevice  Target boot device
 * @param   ulSrcAddr    Address (in RAM) to read the image from
 * @param   ulImageSize  Size of image (in bytes)
 * @param   usPacketNum  Image packet number
 * @param   usPacketSize Size of image packet (in KB)
 * @param   iLastPacket  Boolean indicating if this is the last data packet
 *
 * @return  OK           Image downloaded successfully
 *          ERROR        Image not downloaded successfully
 * 
 */
int iAPC_UpdateFpt( EVL_SIGNAL *pxSignal, APC_BOOT_DEVICES xBootDevice, uint32_t ulSrcAddr, uint32_t ulImageSize,
                    uint16_t usPacketNum, uint16_t usPacketSize, int iLastPacket );

/**
 * @brief   Copy an image from one partition to another
 *
 * @param   pxSignal        Current event occurance (used for tracking)
 * @param   xSrcBootDevice  Target boot device to copy from
 * @param   iSrcPartition   The partition in the FPT to copy this image from
 * @param   xDestBootDevice Target boot device to copy to
 * @param   iDestPartition  The partition in the FPT to copy this image to
 * @param   ulCpyAddr       Address (in RAM) to copy the source partition to before writing it
 * @param   ulAllocatedSize Maximum size available to copy
 *
 * @return  OK          Image copied successfully
 *          ERROR       Image not copied successfully
 * 
 */
int iAPC_CopyImage( EVL_SIGNAL *pxSignal, APC_BOOT_DEVICES xSrcBootDevice, int iSrcPartition, 
                    APC_BOOT_DEVICES xDestBootDevice, int iDestPartition, uint32_t ulCpyAddr, uint32_t ulAllocatedSize );

/**
 * @brief   Select which partition (from primary boot device) to boot from
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 * @param   iPartition  The partition to boot from on the next reset
 *
 * @return  OK          Partition successfully selected
 *          ERROR       Partition not selected
 */
int iAPC_SetNextPartition( EVL_SIGNAL *pxSignal, int iPartition );

/**
 * @brief   Enable the hot reset capability (from primary boot device)
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 *
 * @return  OK          Hot reset successfully enabled
 *          ERROR       Hot reset not enabled
 */
int iAPC_EnableHotReset( EVL_SIGNAL *pxSignal );

/**
 * @brief   Get the Flash Partition Table (FPT) Header
 *
 * @param   xBootDevice     Target boot device
 * @param   pxFptHeader     Pointer to the FPT header data
 *
 * @return  OK              FPT header retrieved successfully
 *          ERROR           FPT header not retrieved successfully
 * 
 */
int iAPC_GetFptHeader( APC_BOOT_DEVICES xBootDevice, APC_PROXY_DRIVER_FPT_HEADER *pxFptHeader );

/**
 * @brief   Get a Flash Partition Table (FPT) Partition
 *
 * @param   xBootDevice     Target boot device
 * @param   iPartition      Index of partition to retrieve (0 is the 1st partition)
 * @param   pxFptPartition  Pointer to the FPT partition data
 *
 * @return  OK              FPT partition retrieved successfully
 *          ERROR           FPT partition not retrieved successfully
 * 
 */
int iAPC_GetFptPartition( APC_BOOT_DEVICES xBootDevice, int iPartition, APC_PROXY_DRIVER_FPT_PARTITION *pxFptPartition );

/**
 * @brief   Print all the stats gathered by the proxy driver
 *
 * @return  OK          Stats retrieved from proxy driver successfully
 *          ERROR       Stats not retrieved successfully
 * 
 */
int iAPC_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the proxy driver
 *
 * @return  OK          Stats cleared successfully
 *          ERROR       Stats not cleared successfully
 * 
 */
int iAPC_ClearStatistics( void );

/**
 * @brief   Gets the current state of the proxy driver
 *
 * @param   pxState         Pointer to the state
 *
 * @return  OK              If successful
 *          ERROR           If not successful
 */
int iAPC_GetState( MODULE_STATE *pxState );

#endif
