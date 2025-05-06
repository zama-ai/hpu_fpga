/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file containing the FW IF GCQ abstraction definitions.
 *
 * @file fw_if_gcq.h
 *
 */

#ifndef _FW_IF_GCQ_H_
#define _FW_IF_GCQ_H_


/*****************************************************************************/
/* Includes                                                                  */
/*****************************************************************************/

#include "fw_if.h"


/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/

#define FW_IF_GCQ_UDID_LEN                  ( 16 )


/*****************************************************************************/
/* Enums                                                                     */
/*****************************************************************************/

/**
 * @enum FW_IF_GCQ_MODE_TYPE
 * @brief Enumeration of GCQ mode as 'producer' or a 'consumer'
 */
typedef enum _FW_IF_GCQ_MODE_TYPE
{
    FW_IF_GCQ_MODE_PRODUCER = 0,
    FW_IF_GCQ_MODE_CONSUMER,

    MAX_FW_IF_GCQ_MODE

} FW_IF_GCQ_MODE_TYPE;

/**
 * @enum FW_IF_GCQ_INTERRUPT_MODE_TYPE
 * @brief Enumeration of the mechanisum used to trigger interrupt 
 */
typedef enum _FW_IF_GCQ_INTERRUPT_MODE_TYPE
{
    FW_IF_GCQ_INTERRUPT_MODE_NONE = 0,                      /* No interrupts enabled */
    FW_IF_GCQ_INTERRUPT_MODE_TAIL_POINTER_TRIGGER,          /* Interrupt is triggered on a write operation to the tail pointer register */
    FW_IF_GCQ_INTERRUPT_MODE_MANUAL_TRIGGER,                /* Interrupt is triggered by setting the interrupt field of the interrupt register */

    MAX_FW_IF_GCQ_INTERRUPT_MODE

} FW_IF_GCQ_INTERRUPT_MODE_TYPE;

/**
 * @enum    FW_IF_GCQ_EVENTS
 * @brief   GCQ events raised in the callback (generic across all GCQ interface)
 */
typedef enum _FW_IF_GCQ_EVENTS
{
    FW_IF_GCQ_INTERRUPT_TRIGGERED = MAX_FW_IF_COMMON_EVENT,

    MAX_FW_IF_GCQ_EVENT

} FW_IF_GCQ_EVENTS;

/**
 * @enum FW_IF_GCQ_ERROR_TYPE
 * @brief Enumeration of GCQ return values
 */
typedef enum _FW_IF_GCQ_ERRORS_TYPE
{
    FW_IF_GCQ_ERRORS_NO_FREE_PROFILES = MAX_FW_IF_ERROR,
    FW_IF_GCQ_ERRORS_INVALID_PROFILE,
    FW_IF_GCQ_ERRORS_NOT_SUPPORTED,
    FW_IF_GCQ_ERRORS_DRIVER_NOT_INITIALISED,
    FW_IF_GCQ_ERRORS_DRIVER_NO_FREE_INSTANCES,
    FW_IF_GCQ_ERRORS_DRIVER_INVALID_INSTANCE,
    FW_IF_GCQ_ERRORS_DRIVER_INVALID_ARG,
    FW_IF_GCQ_ERRORS_DRIVER_INVALID_SLOT_SIZE,
    FW_IF_GCQ_ERRORS_DRIVER_INVALID_VERSION,
    FW_IF_GCQ_ERRORS_DRIVER_INVALID_NUM_SLOTS,
    FW_IF_GCQ_ERRORS_DRIVER_CONSUMER_NOT_ATTACHED,
    FW_IF_GCQ_ERRORS_DRIVER_CONSUMER_NOT_AVAILABLE,
    FW_IF_GCQ_ERRORS_DRIVER_CONSUMER_NO_DATA_RECEIVED,
    FW_IF_GCQ_ERRORS_DRIVER_PRODUCER_NO_FREE_SLOTS,

    MAX_FW_IF_GCQ_ERROR

} FW_IF_GCQ_ERRORS_TYPE;

/**
 * @enum _FW_IF_GCQ_IOCTL_TYPE
 * @brief ioctrl options for GCQ interfaces (generic across all GCQ interfaces)
 */
typedef enum _FW_IF_GCQ_IOCTL_TYPE
{
    FW_IF_GCQ_IOCTRL_SET_OPAQUE_HANDLE = MAX_FW_IF_COMMON_IOCTRL_OPTION,
    FW_IF_GCQ_IOCTRL_GET_OPAQUE_HANDLE,

    MAX_FW_IF_GCQ_IOCTRL_OPTION

} _FW_IF_GCQ_IOCTL_TYPE;


/*****************************************************************************/
/* Structs                                                                   */
/*****************************************************************************/

/**
 * @struct  FW_IF_GCQ_INIT_CFG
 * @brief   config options for GCQ initialisation (generic across all GCQ interfaces)
 */
typedef struct _FW_IF_GCQ_INIT_CFG
{
    void                                *pvIOAccess;

} FW_IF_GCQ_INIT_CFG;

/**
 * @struct  FW_IF_GCQ_CFG
 * @brief   config options for GCQ interfaces (generic across all GCQ interfaces)
 */
typedef struct _FW_IF_GCQ_CFG
{
    uint64_t                            ullBaseAddress;
    FW_IF_GCQ_MODE_TYPE                 xMode;
    FW_IF_GCQ_INTERRUPT_MODE_TYPE       xInterruptMode;
    uint64_t                            ullRingAddress;
    uint32_t                            ulRingLength;
    uint32_t                            ulCompletionQueueSlotSize;
    uint32_t                            ulSubmissionQueueSlotSize;
    uint8_t                             udid[ FW_IF_GCQ_UDID_LEN ];

    void                                *pvProfile;      /* opaque handle to store internal context */

} FW_IF_GCQ_CFG;


/*****************************************************************************/
/* Public Functions                                                          */
/*****************************************************************************/

/*******************************************************************************************
 * @brief   initialisation function for GCQ interfaces (generic across all GCQ interfaces)
 *
 * @param   xInitCfg    pointer to the config to initialise the driver with
 *
 * @return  See FW_IF_ERRORS
 ******************************************************************************************/
extern uint32_t ulFW_IF_GCQ_Init( FW_IF_GCQ_INIT_CFG *pxInitCfg );

/*******************************************************************************************
 * @brief   creates an instance of the GCQ interface
 *
 * @param   xFWIf       fw_if handle to the interface instance
 * @param   xGCQCfg     unique data of this instance
 *
 * @return  See FW_IF_ERRORS
 ******************************************************************************************/
extern uint32_t ulFW_IF_GCQ_Create( FW_IF_CFG *pxFwIf, FW_IF_GCQ_CFG *pxGCQCfg );

/**
 *
 * @brief    Print all the stats gathered by the interface
 *
 * @return   OK                  Stats retrieved from gcq successfully
 *           ERROR               Stats not retrieved successfully
 * 
 *
 */
int iFW_IF_GCQ_PrintStatistics( void );

/**
 *
 * @brief    Clears all the stats gathered by the interface
 *
 * @return   OK                  Stats cleared successfully
 *           ERROR               Stats not cleared successfully
 * 
 *
 */
int iFW_IF_GCQ_ClearStatistics( void );

#endif
