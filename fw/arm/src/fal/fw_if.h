/**
* Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
* SPDX-License-Identifier: MIT
*
* This file contains the API for a generic Firmware Interface abstraction
*
* @file fw_if.h
*
*/

#ifndef _FW_IF_H_
#define _FW_IF_H_

/*****************************************************************************/
/* includes                                                                  */
/*****************************************************************************/

#include "stdint.h"


/*****************************************************************************/
/* defines                                                                   */
/*****************************************************************************/

#define FW_IF_TRUE                  ( 1 )
#define FW_IF_FALSE                 ( 0 )

#define FW_IF_TIMEOUT_NO_WAIT       ( 0 )
#define FW_IF_TIMEOUT_WAIT_FOREVER  ( -1 )


/*****************************************************************************/
/* typedefs                                                                  */
/*****************************************************************************/

/**
 * @brief   Callback to raise to calling layer
 *
 * @param   usEventId   Unique ID to identify the event
 * @param   pucData     Pointer to data buffer
 * @param   ulSize      Number of bytes in data
 *
 * @return  See FW_IF_ERRORS
 */
typedef uint32_t ( FW_IF_callback )( uint16_t usEventId, uint8_t *pucData, uint32_t ulSize );

/**
 * @brief   Open the specific fw_if
 *
 * @param   pvFwIf        Pointer to this fw_if
 *
 * @return  See FW_IF_ERRORS
 */
typedef uint32_t ( FW_IF_open )( void *pvFwIf );

/**
 * @brief   Close the specific fw_if
 *
 * @param   pvFwIf        Pointer to this fw_if
 *
 * @return  See FW_IF_ERRORS
 */
typedef uint32_t ( FW_IF_close )( void *pvFwIf );

/**
 * @brief   Writes data from an instance of the specific fw_if
 *
 * @param   pvFwIf      Pointer to this fw_if
 * @param   ullDstPort  Remote port to write to
 * @param   pucData     Data buffer to write
 * @param   ulSize      Number of bytes in data buffer
 * @param   ulTimeoutMs Time (in ms) to wait for write to complete
 *
 * @return  See FW_IF_ERRORS
 */
typedef uint32_t ( FW_IF_write )( void *pvFwIf, uint64_t ullDstPort, uint8_t *pucData, uint32_t ulSize, uint32_t ulTimeoutMs );

/**
 * @brief   Reads data from an instance of the specific fw_if
 *
 * @param   pvFwIf      Pointer to this fw_if
 * @param   ullSrcPort  Remote port to read from
 * @param   pucData     Data buffer to read
 * @param   pulSize     Pointer to maximum number of bytes allowed in data buffer
 *                      This value is updated to the actual number of bytes read
 * @param   ulTimeoutMs Time (in ms) to wait for read to complete
 *
 * @return  See FW_IF_ERRORS
 */
typedef uint32_t ( FW_IF_read )( void *pvFwIf, uint64_t ullSrcPort, uint8_t *pucData, uint32_t *pulSize, uint32_t ulTimeoutMs );

/**
 * @brief   Set/get specific IO options to/from the specific fw_if
 *
 * @param   pvFwIf      Pointer to this fw_if
 * @param   ulOption    Unique IO Ctrl option to set/get
 * @param   pvValue     Pointer to value to set/get
 *
 * @return  See FW_IF_ERRORS
 */
typedef uint32_t ( FW_IF_ioctrl )( void *pvFwIf, uint32_t ulOption, void *pvValue );

/**
 * @brief   Binds a user-defined callback into the fw_if
 *
 * @param   pvFwIf      Pointer too this fw_if
 * @param   pxNewFunc   Function pointer to call
 *
 * @return  See FW_IF_ERRORS
 */
typedef uint32_t ( FW_IF_bindCallback )( void *pvFwIf, FW_IF_callback *pxNewFunc );


/*****************************************************************************/
/* enums                                                                     */
/*****************************************************************************/

/**
 * @enum    FW_IF_ERRORS
 *
 * @brief   Return values from an fw_if function
 */
typedef enum _FW_IF_ERRORS
{
    FW_IF_ERRORS_NONE = 0,                  /* no errors, call was successful */
    FW_IF_ERRORS_PARAMS,                    /* invalid parameters passed in to function */
    FW_IF_ERRORS_INVALID_HANDLE,            /* invalid handle to the fw_if */
    FW_IF_ERRORS_INVALID_CFG,               /* invalid config in the fw_if */
    FW_IF_ERRORS_UNRECOGNISED_OPTION,       /* invalid option passed in to ioctrl function */
    FW_IF_ERRORS_DRIVER_IN_USE,             /* driver was in use by another process */
    FW_IF_ERRORS_DRIVER_NOT_INITIALISED,    /* driver was not initialised correctly */
    FW_IF_ERRORS_DRIVER_RX_MODE,            /* driver was requested to operate in a mode with which it is not compatible */
    FW_IF_ERRORS_TIMEOUT,                   /* a non-0 timeout value was requested and expired */
    FW_IF_ERRORS_BINDING,                   /* the callback was not successfully bound in */
    FW_IF_ERRORS_OPEN,                      /* this should cause a driver-specific event to be raised to the bound callback */
    FW_IF_ERRORS_CLOSE,                     /* this should cause a driver-specific event to be raised to the bound callback */
    FW_IF_ERRORS_WRITE,                     /* this should cause a driver-specific event to be raised to the bound callback */
    FW_IF_ERRORS_READ,                      /* this should cause a driver-specific event to be raised to the bound callback */
    FW_IF_ERRORS_IOCTRL,                    /* this should cause a driver-specific event to be raised to the bound callback */

    MAX_FW_IF_ERROR,

} FW_IF_ERRORS;

/**
 * @enum    FW_IF_COMMON_IOCTRL_OPTIONS
 *
 * @brief   IO ctrl options common to all fw_ifs
 */
typedef enum _FW_IF_COMMON_IOCTRL_OPTIONS
{
    FW_IF_COMMON_IOCTRL_FLUSH_TX = 0,
    FW_IF_COMMON_IOCTRL_FLUSH_RX,
    FW_IF_COMMON_IOCTRL_GET_RX_MODE,
    FW_IF_COMMON_IOCTRL_ENABLE_DEBUG_PRINT,
    FW_IF_COMMON_IOCTRL_DISABLE_DEBUG_PRINT,

    MAX_FW_IF_COMMON_IOCTRL_OPTION

} FW_IF_COMMON_IOCTRL_OPTIONS;

/**
 * @enum    FW_IF_COMMON_EVENTS
 *
 * @brief   common events raised in the callback (generic across all interfaces)
 */
typedef enum _FW_IF_COMMON_EVENTS
{
    FW_IF_COMMON_EVENT_NEW_RX_DATA,
    FW_IF_COMMON_EVENT_NEW_TX_COMPLETE,
    FW_IF_COMMON_EVENT_WARNING,
    FW_IF_COMMON_EVENT_ERROR,

    MAX_FW_IF_COMMON_EVENT

} FW_IF_COMMON_EVENTS;

/**
 *  @enum   FW_IF_RX_MODE
 *
 *  @brief  Mode of Rx operation
 */
typedef enum _FW_IF_RX_MODE
{
    FW_IF_RX_MODE_POLLING   = 0x01,         /* driver must be polled for new data */
    FW_IF_RX_MODE_EVENT     = 0x02,         /* driver will raise an event to announce new data */

} FW_IF_DRIVER_RX_MODE;

/*****************************************************************************/
/* structs                                                                   */
/*****************************************************************************/

/**
 * @struct  FW_IF_CFG
 *
 * @brief   Structure to hold a fw_if instance
 */
typedef struct _FW_IF_CFG
{
    uint32_t            upperFirewall;

    FW_IF_open          *open;
    FW_IF_close         *close;
    FW_IF_write         *write;
    FW_IF_read          *read;
    FW_IF_ioctrl        *ioctrl;
    FW_IF_bindCallback  *bindCallback;

    FW_IF_callback      *raiseEvent;

    void                *cfg;

    uint32_t            lowerFirewall;

} FW_IF_CFG;

#endif
