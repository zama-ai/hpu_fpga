/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implementation for the Alveo External Device Control (AXC)
 * proxy driver.
 *
 * @file axc_proxy_driver.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"
#include "util.h"
#include "pll.h"
#include "osal.h"
#include "axc_proxy_driver.h"
#include "fw_if_muxed_device.h"

/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL                          ( 0xBABECAFE )
#define LOWER_FIREWALL                          ( 0xDEADFACE )

#define AXC_TASK_SLEEP_MS                       ( 100 )
#define AXC_TASK_SLEEP_1S                       ( 1*1000 )

#define AXC_NAME                                "AXC"

#define AXC_MAX_MSG_SIZE                        ( 64 )
#define AXC_MBOX_SIZE                           ( 10 )
#define AXC_EXTERNAL_DEVICE_TEMP_NOT_SET        ( 0  )
#define QSFP_MSB_TEMPERATURE_REG                ( 22 )
#define EXTERNAL_DEVICE_MSB_TO_HEX_BIT_SHIFT    ( 8  )
#define EXTERNAL_DEVICE_SINGLE_VALUE_SIZE       ( 1  )
#define AXC_PAGE_SELECT_BYTE                    ( 127 )
#define AXC_UPPER_PAGE_START_INDEX              ( 128 )
#define DIMM_TEMPERATURE_REG                    ( 5 )

/* Macro to define maximum possible positive temperature that can be read. */
#define QSFP_MAX_POSITIVE_TEMP                  ( 0x7FFF )
#define DIMM_MAX_POSITIVE_TEMP                  ( 0x03FF )

/* Macro to define maximum possible negative temperature that can be read */
#define QSFP_MAX_NEGATIVE_TEMP                  ( 0x8000 )

/* Macro to define mask for only the temperature bits discarding the signed bits. */
#define QSFP_TEMP_BIT_MASK                      ( 0x7FFF )
#define DIMM_TEMP_BIT_MASK                      ( 0x07FF )
#define DIMM_TEMP_UNUSED_BITS                   ( 2 )

#define QSFP_TEMPERATURE_RESOLUTION             ( 1.0/256.0 )
#define DIMM_TEMPERATURE_RESOLUTION             ( 1.0/4.0 )

/* Stat & Error definitions */
#define AXC_PROXY_STATS( DO )                           \
    DO( AXC_PROXY_STATS_INIT_OVERALL_COMPLETE )         \
    DO( AXC_PROXY_STATS_CREATE_TASK )                   \
    DO( AXC_PROXY_STATS_CREATE_MUTEX )                  \
    DO( AXC_PROXY_STATS_TAKE_MUTEX )                    \
    DO( AXC_PROXY_STATS_RELEASE_MUTEX )                 \
    DO( AXC_PROXY_STATS_FW_IF_OPEN )                    \
    DO( AXC_PROXY_STATS_FW_IF_WRITE )                   \
    DO( AXC_PROXY_STATS_FW_IF_READ )                    \
    DO( AXC_PROXY_STATS_FW_IF_IOCTRL )                  \
    DO( AXC_PROXY_STATS_TASK_TIME_MS )                  \
    DO( AXC_PROXY_STATS_STATUS_RETRIEVAL )              \
    DO( AXC_PROXY_STATS_MAX )

#define AXC_PROXY_ERRORS( DO )                            \
    DO( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )           \
    DO( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED )              \
    DO( AXC_PROXY_ERRORS_RAISE_EVENT_PRESENT_FAILED )     \
    DO( AXC_PROXY_ERRORS_RAISE_EVENT_NOT_PRESENT_FAILED ) \
    DO( AXC_PROXY_ERRORS_INIT_FW_IF_OPEN_FAILED )         \
    DO( AXC_PROXY_ERRORS_INIT_MUTEX_CREATE_FAILED )       \
    DO( AXC_PROXY_ERRORS_INIT_TASK_CREATE_FAILED )        \
    DO( AXC_PROXY_ERRORS_FW_IF_WRITE_FAILED )             \
    DO( AXC_PROXY_ERRORS_FW_IF_READ_FAILED )              \
    DO( AXC_PROXY_ERRORS_FW_IF_IOCTRL_FAILED )            \
    DO( AXC_PROXY_ERRORS_LIST_APPEND_FAILED )             \
    DO( AXC_PROXY_ERRORS_VALIDATION_FAILED )              \
    DO( AXC_PROXY_ERRORS_UNKNOWN_DEVICE )                 \
    DO( AXC_PROXY_ERRORS_INIT_EVL_RECORD_FAILED )         \
    DO( AXC_PROXY_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )             PLL_ERR( AXC_NAME, "%50s . . . . %d\r\n",          \
                                                     AXC_PROXY_STATS_STR[ x ],       \
                                                     pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x )            PLL_ERR( AXC_NAME, "%50s . . . . %d\r\n",          \
                                                     AXC_PROXY_ERRORS_STR[ x ],      \
                                                     pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )               { if( x < AXC_PROXY_STATS_MAX )pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x )              { if( x < AXC_PROXY_ERRORS_MAX )pxThis->pulErrorCounters[ x ]++; }
#define INC_ERROR_COUNTER_WITH_STATE( x )   { pxThis->xState = MODULE_STATE_ERROR; INC_ERROR_COUNTER( x ) }
#define SET_STAT_COUNTER( x, y )            { if( x < AXC_PROXY_ERRORS_MAX )pxThis->pulStatCounters[ x ] = y; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    AXC_EXTERNAL_DEVICE_STATUS
 * @brief   Status of External Device
 */
typedef enum
{
    AXC_STATUS_NOT_PRESENT = 0,
    AXC_STATUS_PRESENT,
    AXC_STATUS_FAILED,

    MAX_AXC_STATUS

} AXC_EXTERNAL_DEVICE_STATUS;

/**
 * @enum    AXC_PROXY_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( AXC_PROXY_STATS, AXC_PROXY_STATS, AXC_PROXY_STATS_STR )

/**
 * @enum    AXC_PROXY_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( AXC_PROXY_ERRORS, AXC_PROXY_ERRORS, AXC_PROXY_ERRORS_STR )

/******************************************************************************/
/* Structures                                                                 */
/******************************************************************************/

/**
 * @struct  AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST
 * @brief   Linked List Structure to hold EXTERNAL_DEVICE private data
 */
typedef struct AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST
{
    AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG         *pxExDevLocalDeviceCfg;
    AXC_EXTERNAL_DEVICE_STATUS                      xExDevStatus;
    float                                           fExDevTemperature;

    struct AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST  *pxNextExDev;


} AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST;

/**
 * @struct  AXC_PRIVATE_DATA
 * @brief   Structure to hold ths proxy driver's private data
 */
typedef struct AXC_PRIVATE_DATA
{
    uint32_t                                ulUpperFirewall;

    int                                     iInitialised;
    uint8_t                                 ucMyId;
    AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST *pxLinkedListHead;

    EVL_RECORD                              *pxEvlRecord;

    void *                                  pvOsalMutexHdl;
    void *                                  pvOsalTaskHdl;

    uint32_t                                pulStatCounters[ AXC_PROXY_STATS_MAX ];
    uint32_t                                pulErrorCounters[ AXC_PROXY_ERRORS_MAX ];

    MODULE_STATE                            xState;

    uint32_t                                ulLowerFirewall;

} AXC_PRIVATE_DATA;

/**
 * @struct  AXC_PRIVATE_EXTERNAL_DEVICE_TEMPERATURE_REQUEST
 * @brief   Structure to hold External Device temperature request data
 */
typedef struct AXC_PRIVATE_EXTERNAL_DEVICE_TEMPERATURE_REQUEST
{
    uint8_t     ucTemperatureMsb;
    uint8_t     ucTemperatureLsb;

} AXC_PRIVATE_EXTERNAL_DEVICE_TEMPERATURE_REQUEST;


/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

static AXC_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,              /* ulUpperFirewall */
    FALSE,                       /* iInitialised */
    0,                           /* ucMyId */
    NULL,                        /* pxLinkedListHead */
    NULL,                        /* pxEvlRecord */
    NULL,                        /* pvOsalMutexHdl */
    NULL,                        /* pvOsalTaskHdl */
    { 0 },                       /* pulStatCounters */
    { 0 },                       /* pulErrorCounters */
    MODULE_STATE_UNINITIALISED,  /* xState */
    LOWER_FIREWALL               /* ulLowerFirewall */
};
static AXC_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Local Function declarations                                                */
/******************************************************************************/

/**
 * @brief   Example task declaration
 *
 * @param   pvArgs  Pointer to task args (unused)
 *
 * @return  N/A
 *
 */
static void vProxyDriverTask( void *pvArgs );

/**
 * @brief   Insert External Device link into list at beginning
 *
 * @param   pxExDevCfg  Pointer to External Device device config
 *
 * @return  OK              External Device added to list
 *          ERROR           External Device not added to list
 *
 */
static int iInsertExDevListBegin( AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG *pxExDevCfg );

/**
 * @brief   Find External Device handle from link list based on unique ID
 *
 * @param   ppxCurrentExDev  Pointer to pointer of External Device linked list item
 *
 * @param   ucExDeviceId External Device Unique ID
 *
 * @return  OK              External Device handle found to match ID
 *          ERROR           No External Device handle found to match ID
 *
 */
static int iGetExDevFromList( AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST **ppxCurrentExDev, uint8_t ucExDeviceId );

/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/* Init functions *************************************************************/

/**
 * @brief   Main initialisation point for the AXC Proxy Driver
 */
int iAXC_Initialise( uint8_t ucProxyId, uint32_t ulTaskPrio, uint32_t ulTaskStack )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) )
    {
        /* store parameters locally */
        pxThis->ucMyId     = ucProxyId;

        /* initalise evl record*/
        if ( OK != iEVL_CreateRecord( &pxThis->pxEvlRecord ) )
        {
            PLL_ERR( AXC_NAME, "Error initialising EVL_RECORD\r\n" );
            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_INIT_EVL_RECORD_FAILED );
        }
        else
        {
            /* initialise OSAL items */
            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvOsalMutexHdl, "axc_proxy mutex" ) )
            {
                PLL_ERR( AXC_NAME, "Error initialising mutex\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_INIT_MUTEX_CREATE_FAILED )
            }
            else if( OSAL_ERRORS_NONE != iOSAL_Task_Create( &pxThis->pvOsalTaskHdl,
                                                            vProxyDriverTask,
                                                            ulTaskStack,
                                                            NULL,
                                                            ulTaskPrio,
                                                            "axc_proxy task" ) )
            {
                PLL_ERR( AXC_NAME, "Error initialising task\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_INIT_TASK_CREATE_FAILED )
            }
            else
            {
                INC_STAT_COUNTER( AXC_PROXY_STATS_CREATE_MUTEX )
                INC_STAT_COUNTER( AXC_PROXY_STATS_CREATE_TASK )
                INC_STAT_COUNTER( AXC_PROXY_STATS_INIT_OVERALL_COMPLETE )
                pxThis->iInitialised = TRUE;
                pxThis->xState = MODULE_STATE_OK;
                iStatus = OK;
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Initialise new External Device device. AXC proxy will check status and temperature
 *          of this device.
 */
int iAXC_AddExternalDevice( AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG *pxExDeviceCfg )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxExDeviceCfg ) )
    {
        if( FW_IF_ERRORS_NONE != pxExDeviceCfg->pxExDevIf->open( pxExDeviceCfg->pxExDevIf ) )
        {
            PLL_ERR( AXC_NAME, "Error opening FW_IF\r\n" );
            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_INIT_FW_IF_OPEN_FAILED )
        }
        else
        {
            INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_OPEN )

            if( ( ERROR != iInsertExDevListBegin( pxExDeviceCfg ) ) &&
                ( NULL != pxThis->pxLinkedListHead ) )
            {
                iStatus = OK;
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Bind into this proxy driver
 */
int iAXC_BindCallback( EVL_CALLBACK *pxCallback )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxCallback ) &&
        ( NULL != pxThis->pxEvlRecord ) )
    {
        iStatus = iEVL_BindCallback( pxThis->pxEvlRecord, pxCallback );
    }

    return iStatus;
}

/* Set functions **************************************************************/

/**
 * @brief   Write byte value to desired External Device memory map
 */
int iAXC_SetByte( uint8_t ucExDeviceId, uint32_t ulPage, uint32_t ulByteOffset, uint8_t ucValue )
{
    int iStatus = ERROR;
    AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST *ppxCurrentExDev = NULL;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        if( ( OK == iGetExDevFromList( &ppxCurrentExDev, ucExDeviceId ) ) &&
            ( NULL != ppxCurrentExDev ) )
        {
            if( ( AXC_LOWER_PAGE_SIZE > ulByteOffset ) && ( 0 == ulPage ) )
            {
                /* assume lower page 00h */
                iStatus = OK;
            }
            else if( ( AXC_LOWER_PAGE_SIZE <= ulByteOffset ) && ( AXC_PAGE_SIZE > ulByteOffset ) )
            {
                /* set upper page number */
                /* take mutex */
                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                        OSAL_TIMEOUT_WAIT_FOREVER ) )
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_TAKE_MUTEX )

                    /* set hw config - External Device memory map */
                    if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->ioctrl( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                    FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP,
                                                                                                    NULL ) )
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_IOCTRL )

                        if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->write( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                    AXC_PAGE_SELECT_BYTE,
                                                                                                    ( uint8_t* )&ulPage,
                                                                                                    sizeof( uint8_t ),
                                                                                                    FW_IF_TIMEOUT_NO_WAIT ) )
                        {
                            INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_WRITE )
                            iStatus = OK;
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_WRITE_FAILED )
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_IOCTRL_FAILED )
                    }

                    /* release mutex */
                    if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED );
                        iStatus = ERROR;
                    }
                    else
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_RELEASE_MUTEX )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED );
                }
            }

            if( OK == iStatus )
            {
                /* take mutex */
                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                        OSAL_TIMEOUT_WAIT_FOREVER ) )
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_TAKE_MUTEX )

                    /* set hw config - External Device memory map */
                    if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->ioctrl( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                    FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP,
                                                                                                    NULL ) )
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_IOCTRL )

                        if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->write( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                    ( uint64_t )ulByteOffset,
                                                                                                    &ucValue,
                                                                                                    sizeof( uint8_t ),
                                                                                                    FW_IF_TIMEOUT_NO_WAIT ) )
                        {
                            INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_WRITE )
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_WRITE_FAILED )
                            iStatus = ERROR;
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_IOCTRL_FAILED )
                        iStatus = ERROR;
                    }

                    /* release mutex */
                    if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED );
                        iStatus = ERROR;
                    }
                    else
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_RELEASE_MUTEX )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED );
                    iStatus = ERROR;
                }
            }
        }
    }

    return iStatus;
}

/* Get functions **************************************************************/

/**
 * @brief   Read real-time byte value from desired External Device memory map
 */
int iAXC_GetByte( uint8_t ucExDeviceId, uint32_t ulPage, uint32_t ulByteOffset, uint8_t *pucValue )
{
    int iStatus = ERROR;
    uint32_t ulValueSize = EXTERNAL_DEVICE_SINGLE_VALUE_SIZE;
    AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST *ppxCurrentExDev = NULL;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucValue ) )
    {
        if( ( OK == iGetExDevFromList( &ppxCurrentExDev, ucExDeviceId ) ) &&
            ( NULL != ppxCurrentExDev ) )
        {
            if( ( AXC_LOWER_PAGE_SIZE > ulByteOffset ) && ( 0 == ulPage ) )
            {
                /* assume lower page 00h */
                iStatus = OK;
            }
            else if( ( AXC_LOWER_PAGE_SIZE <= ulByteOffset ) && ( AXC_PAGE_SIZE > ulByteOffset ) )
            {
                /* set upper page number */
                /* take mutex */
                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                        OSAL_TIMEOUT_WAIT_FOREVER ) )
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_TAKE_MUTEX )

                    /* set hw config - External Device memory map */
                    if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->ioctrl( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                    FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP,
                                                                                                    NULL ) )
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_IOCTRL )

                        if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->write( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                    AXC_PAGE_SELECT_BYTE,
                                                                                                    ( uint8_t* )&ulPage,
                                                                                                    sizeof( uint8_t ),
                                                                                                    FW_IF_TIMEOUT_NO_WAIT ) )
                        {
                            INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_WRITE )
                            iStatus = OK;
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_WRITE_FAILED )
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_IOCTRL_FAILED )
                    }

                    /* release mutex */
                    if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED );
                        iStatus = ERROR;
                    }
                    else
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_RELEASE_MUTEX )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED );
                }
            }

            if( OK == iStatus )
            {
                /* take mutex */
                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                        OSAL_TIMEOUT_WAIT_FOREVER ) )
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_TAKE_MUTEX )

                    /* set hw config - External Device memory map */
                    if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->ioctrl( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                    FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP,
                                                                                                    NULL ) )
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_IOCTRL )

                        if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->read( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                    ( uint64_t )ulByteOffset,
                                                                                                    pucValue,
                                                                                                    &ulValueSize,
                                                                                                    FW_IF_TIMEOUT_NO_WAIT ) )
                        {
                            INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_READ )

                            if( EXTERNAL_DEVICE_SINGLE_VALUE_SIZE != ulValueSize )
                            {
                                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_READ_FAILED )
                                iStatus = ERROR;
                            }
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_READ_FAILED )
                            iStatus = ERROR;
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_IOCTRL_FAILED )
                        iStatus = ERROR;
                    }

                    /* release mutex */
                    if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED );
                        iStatus = ERROR;
                    }
                    else
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_RELEASE_MUTEX )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED );
                    iStatus = ERROR;
                }
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Read real-time memory map from desired DEVICE page
 */
int iAXC_GetPage( uint8_t ucExDeviceId, uint32_t ulPage, AXC_PROXY_DRIVER_PAGE_DATA *pxData )
{
    int iStatus = ERROR;
    AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST *ppxCurrentExDev = NULL;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxData ) )
    {
        if( ( OK == iGetExDevFromList( &ppxCurrentExDev, ucExDeviceId ) ) &&
            ( NULL != ppxCurrentExDev ) )
        {
            /* set upper page number */
            /* take mutex */
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                    OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                INC_STAT_COUNTER( AXC_PROXY_STATS_TAKE_MUTEX )

                /* set hw config - External Device memory map */
                if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->ioctrl( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP,
                                                                                                NULL ) )
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_IOCTRL )

                    if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->write( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                AXC_PAGE_SELECT_BYTE,
                                                                                                ( uint8_t* )&ulPage,
                                                                                                sizeof( uint8_t ),
                                                                                                FW_IF_TIMEOUT_NO_WAIT ) )
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_WRITE )
                        iStatus = OK;
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_WRITE_FAILED )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_IOCTRL_FAILED )
                }

                /* release mutex */
                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED );
                    iStatus = ERROR;
                }
                else
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_RELEASE_MUTEX )
                }
            }
            else
            {
                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED );
            }

            /* Read upper page */
            if( OK == iStatus )
            {
                pxData->ulPageDataSize = AXC_UPPER_PAGE_SIZE;
                /* take mutex */
                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                        OSAL_TIMEOUT_WAIT_FOREVER ) )
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_TAKE_MUTEX )

                    /* set hw config - External Device memory map */
                    if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->ioctrl( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                    FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP,
                                                                                                    NULL ) )
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_IOCTRL )

                        if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->read( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                    AXC_UPPER_PAGE_START_INDEX,
                                                                                                    pxData->pucPageData,
                                                                                                    &pxData->ulPageDataSize,
                                                                                                    FW_IF_TIMEOUT_NO_WAIT ) )
                        {
                            INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_READ )

                            if( AXC_UPPER_PAGE_SIZE != pxData->ulPageDataSize )
                            {
                                iStatus = ERROR;
                            }
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_READ_FAILED )
                            iStatus = ERROR;
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_IOCTRL_FAILED )
                        iStatus = ERROR;
                    }

                    /* release mutex */
                    if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED );
                        iStatus = ERROR;
                    }
                    else
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_RELEASE_MUTEX )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED );
                    iStatus = ERROR;
                }
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Read single status from QSFP IO Expander
 */
int iAXC_GetSingleIoStatus( uint8_t ucExDeviceId, AXC_PROXY_DRIVER_QSFP_IO xIoControlLine, uint8_t *pucIoStatus )
{
    int iStatus = ERROR;
    uint8_t ucIoExpanderByte = 0;
    uint32_t ucIoExpanderByteSize = sizeof( ucIoExpanderByte );
    AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST *ppxCurrentExDev = NULL;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( MAX_AXC_PROXY_DRIVER_QSFP_IO > xIoControlLine ) &&
        ( NULL != pucIoStatus ) )
    {

        if( ( OK == iGetExDevFromList( &ppxCurrentExDev, ucExDeviceId ) ) &&
            ( NULL != ppxCurrentExDev ) )
        {
            /* take mutex */
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                        OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                INC_STAT_COUNTER( AXC_PROXY_STATS_TAKE_MUTEX )

                /* set hw config - IO Expander */
                if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->ioctrl( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP,
                                                                                                NULL ) )
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_IOCTRL )

                    if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->read( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                0,
                                                                                                &ucIoExpanderByte,
                                                                                                &ucIoExpanderByteSize,
                                                                                                FW_IF_TIMEOUT_NO_WAIT ) )
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_READ )

                        /* return status */
                        *pucIoStatus = ( 0 == ( ucIoExpanderByte & ( 1 << xIoControlLine ) ) ) ? ( FALSE ):( TRUE );
                        iStatus = OK;
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_READ_FAILED )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_IOCTRL_FAILED )
                }

                /* release mutex */
                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED );
                    iStatus = ERROR;
                }
                else
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_RELEASE_MUTEX )
                }
            }
            else
            {
                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED );
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Read all statuses from QSFP IO Expander
 */
int iAXC_GetAllIoStatuses( uint8_t ucExDeviceId, AXC_PROXY_DRIVER_QSFP_IO_STATUSES *pxIoStatuses )
{
    int iStatus = ERROR;
    uint8_t ucIoExpanderByte = 0;
    uint32_t ucIoExpanderByteSize = sizeof( ucIoExpanderByte );
    AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST *ppxCurrentExDev = NULL;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxIoStatuses ) )
    {
        if( ( OK == iGetExDevFromList( &ppxCurrentExDev, ucExDeviceId ) ) &&
            ( NULL != ppxCurrentExDev ) )
        {
            /* take mutex */
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                        OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                INC_STAT_COUNTER( AXC_PROXY_STATS_TAKE_MUTEX )

                /* set hw config - IO Expander */
                if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->ioctrl( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP,
                                                                                                NULL ) )
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_IOCTRL )

                    if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->read( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                0,
                                                                                                &ucIoExpanderByte,
                                                                                                &ucIoExpanderByteSize,
                                                                                                FW_IF_TIMEOUT_NO_WAIT ) )
                    {
                        INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_READ )

                        /* return each status */
                        pxIoStatuses->ucModSel    = ( 0 == ( ucIoExpanderByte & ( 1 << AXC_PROXY_DRIVER_QSFP_IO_MODSEL    ) ) ) ? ( FALSE ):( TRUE );
                        pxIoStatuses->ucReset     = ( 0 == ( ucIoExpanderByte & ( 1 << AXC_PROXY_DRIVER_QSFP_IO_RESET     ) ) ) ? ( FALSE ):( TRUE );
                        pxIoStatuses->ucLpMode    = ( 0 == ( ucIoExpanderByte & ( 1 << AXC_PROXY_DRIVER_QSFP_IO_LPMODE    ) ) ) ? ( FALSE ):( TRUE );
                        pxIoStatuses->ucModPrs    = ( 0 == ( ucIoExpanderByte & ( 1 << AXC_PROXY_DRIVER_QSFP_IO_MODPRS    ) ) ) ? ( FALSE ):( TRUE );
                        pxIoStatuses->ucInterrupt = ( 0 == ( ucIoExpanderByte & ( 1 << AXC_PROXY_DRIVER_QSFP_IO_INTERRUPT ) ) ) ? ( FALSE ):( TRUE );

                        iStatus = OK;
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_READ_FAILED )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_IOCTRL_FAILED )
                }

                /* release mutex */
                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED );
                    iStatus = ERROR;
                }
                else
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_RELEASE_MUTEX )
                }
            }
            else
            {
                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED );
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Read real-time temperature value from desired External Device memory map
 */
int iAXC_GetTemperature( uint8_t ucExDeviceId, float *pfTemperature )
{
    int iStatus = ERROR;
    AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST *ppxCurrentExDev = NULL;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pfTemperature ) )
    {
        if( ( OK == iGetExDevFromList( &ppxCurrentExDev, ucExDeviceId ) ) &&
            ( NULL != ppxCurrentExDev ) )
        {
            FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->cfg;
            if( FW_IF_DEVICE_QSFP == pxCfg->xDevice )
            {
                if( AXC_STATUS_PRESENT == ppxCurrentExDev->xExDevStatus )
                {
                    /* return temperature value */
                    *pfTemperature = ppxCurrentExDev->fExDevTemperature;
                    iStatus = OK;
                }
            }
            else
            {
                /* return temperature value */
                *pfTemperature = ppxCurrentExDev->fExDevTemperature;
                iStatus = OK;
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Gets the current state of the proxy
 */
int iAXC_GetState( MODULE_STATE *pxState )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxState ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_TASK_WAIT_MS ) )
        {
            *pxState = pxThis->xState;

            INC_STAT_COUNTER( AXC_PROXY_STATS_STATUS_RETRIEVAL );

            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }

        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
        {
            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            iStatus = ERROR;
        }
        else
        {
            INC_STAT_COUNTER( AXC_PROXY_STATS_RELEASE_MUTEX )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AXC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/* Utility functions **********************************************************/

/**
 * @brief   Print all the stats gathered by the application
 */
int iAXC_PrintStatistics( void )
{
     int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( AXC_NAME, "============================================================\n\r" );
        PLL_INF( AXC_NAME, "AXC Proxy Statistics:\n\r" );
        for( i = 0; i < AXC_PROXY_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( AXC_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( AXC_NAME, "AXC Proxy Errors:\n\r" );
        for( i = 0; i < AXC_PROXY_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( AXC_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( AXC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Clear all the stats in the application
 */
int iAXC_ClearStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        pvOSAL_MemSet( pxThis->pulStatCounters, 0, sizeof( pxThis->pulStatCounters ) );
        pvOSAL_MemSet( pxThis->pulErrorCounters, 0, sizeof( pxThis->pulErrorCounters ) );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( AXC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Check if a get/set request is valid
 */
int iAXC_ValidateRequest( uint8_t ucExDeviceId, uint32_t ulPage, uint32_t ulByteOffset )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST *ppxCurrentExDev = NULL;

        if( ( OK == iGetExDevFromList( &ppxCurrentExDev, ucExDeviceId ) ) &&
            ( NULL != ppxCurrentExDev ) &&
            ( AXC_STATUS_PRESENT == ppxCurrentExDev->xExDevStatus ) &&
            ( ( ( AXC_LOWER_PAGE_SIZE > ulByteOffset ) && ( 0 == ulPage ) ) ||
              ( ( AXC_LOWER_PAGE_SIZE <= ulByteOffset ) && ( AXC_PAGE_SIZE > ulByteOffset ) ) ) )
        {
            iStatus = OK;
        }
    }
    else
    {
        INC_ERROR_COUNTER( AXC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}


/******************************************************************************/
/* Local Function implementations                                             */
/******************************************************************************/

/**
 * @brief   AXC Task to check status and temperature of each External Device.
 */
static void vProxyDriverTask( void *pvArgs )
{
    AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST *ppxCurrentExDev = pxThis->pxLinkedListHead;
    AXC_PRIVATE_EXTERNAL_DEVICE_TEMPERATURE_REQUEST ucTemperatureReq = { 0 };
    uint32_t ulTemperatureBytes = sizeof( AXC_PRIVATE_EXTERNAL_DEVICE_TEMPERATURE_REQUEST );
    AXC_EXTERNAL_DEVICE_STATUS xNewExDevStatus = AXC_STATUS_FAILED;
    uint16_t  usTemperatureHexValue = 0;
    uint32_t ulStartMs = 0;

    /* Add a delay at the start of the process */
    iOSAL_Task_SleepMs( AXC_TASK_SLEEP_1S );

    FOREVER
    {
        /* Loop over each External Device held within linked list */
        ulStartMs = ulOSAL_GetUptimeMs();
        ppxCurrentExDev = pxThis->pxLinkedListHead;

        while( NULL != ppxCurrentExDev )
        {
            FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->cfg;
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                      OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                INC_STAT_COUNTER( AXC_PROXY_STATS_TAKE_MUTEX )

                /* set hw config - External Device memory map */
                if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->ioctrl( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP,
                                                                                                NULL ) )
                {
                    INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_IOCTRL )

                    switch( pxCfg->xDevice )
                    {
                        case FW_IF_DEVICE_QSFP:
                        {
                            if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->read( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                        QSFP_MSB_TEMPERATURE_REG,
                                                                                                        ( uint8_t* )&ucTemperatureReq,
                                                                                                        &ulTemperatureBytes,
                                                                                                        FW_IF_TIMEOUT_NO_WAIT ) )
                            {
                                INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_READ )

                                /* read temperature success - device available */
                                xNewExDevStatus = AXC_STATUS_PRESENT;

                                /*
                                * Calculate temperature value in celsius
                                *
                                * QSFP Temperature reading is a signed 16 bit value with a resolution of 1/256 C.
                                * The total range is from -128 to +128
                                *
                                */
                                usTemperatureHexValue = ( ucTemperatureReq.ucTemperatureMsb << EXTERNAL_DEVICE_MSB_TO_HEX_BIT_SHIFT ) | ucTemperatureReq.ucTemperatureLsb;

                                if( QSFP_MAX_POSITIVE_TEMP >= usTemperatureHexValue ) /* +ve Temperature */
                                {
                                    ppxCurrentExDev->fExDevTemperature = usTemperatureHexValue * QSFP_TEMPERATURE_RESOLUTION;
                                }
                                else /* -ve Temperature */
                                {
                                    /*
                                    * Ignore the signed bit here, since we have already determined that it is a
                                    * negative temperature
                                    */
                                    usTemperatureHexValue = usTemperatureHexValue & QSFP_TEMP_BIT_MASK;
                                    ppxCurrentExDev->fExDevTemperature = ( QSFP_MAX_NEGATIVE_TEMP - usTemperatureHexValue ) * QSFP_TEMPERATURE_RESOLUTION * ( -1 );
                                }
                            }
                            else
                            {
                                INC_ERROR_COUNTER( AXC_PROXY_ERRORS_FW_IF_READ_FAILED )

                                /* read temperature error - device not available */
                                xNewExDevStatus = AXC_STATUS_NOT_PRESENT;
                            }
                            break;
                        }

                        case FW_IF_DEVICE_DIMM:
                        {
                            /* DIMM */
                            if( FW_IF_ERRORS_NONE == ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf->read( ppxCurrentExDev->pxExDevLocalDeviceCfg->pxExDevIf,
                                                                                                        DIMM_TEMPERATURE_REG,
                                                                                                        ( uint8_t* )&ucTemperatureReq,
                                                                                                        &ulTemperatureBytes,
                                                                                                        FW_IF_TIMEOUT_NO_WAIT ) )
                            {
                                INC_STAT_COUNTER( AXC_PROXY_STATS_FW_IF_READ )
                                xNewExDevStatus = AXC_STATUS_PRESENT;

                                /*
                                * Calculate temperature value in celsius
                                */
                                usTemperatureHexValue = ( ucTemperatureReq.ucTemperatureMsb << EXTERNAL_DEVICE_MSB_TO_HEX_BIT_SHIFT ) | ucTemperatureReq.ucTemperatureLsb;
                                usTemperatureHexValue = ( ( usTemperatureHexValue >> DIMM_TEMP_UNUSED_BITS ) & DIMM_TEMP_BIT_MASK );
                                if( DIMM_MAX_POSITIVE_TEMP >= usTemperatureHexValue ) /* +ve Temperature */
                                {
                                    ppxCurrentExDev->fExDevTemperature = usTemperatureHexValue * DIMM_TEMPERATURE_RESOLUTION;
                                }
                                else /* -ve Temperature */
                                {
                                    /*
                                    * Do a 2's complement calculation on the negative number
                                    * Toggle all bits, mask to ignore sign bit and above
                                    */
                                    ppxCurrentExDev->fExDevTemperature = (  ( ~usTemperatureHexValue & DIMM_MAX_POSITIVE_TEMP ) + 1 )
                                     * DIMM_TEMPERATURE_RESOLUTION * ( -1 );
                                }
                            }
                            else
                            {
                                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_READ_FAILED )

                                /* read temperature error - device not available */
                                xNewExDevStatus = AXC_STATUS_NOT_PRESENT;
                            }
                            break;
                        }

                        default:
                            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_UNKNOWN_DEVICE )
                            break;
                    }
                }
                else
                {
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_FW_IF_IOCTRL_FAILED )
                }
            }
            else
            {
                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_TAKE_FAILED );
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_MUTEX_RELEASE_FAILED );
            }
            else
            {
                INC_STAT_COUNTER( AXC_PROXY_STATS_RELEASE_MUTEX )
            }

            switch( pxCfg->xDevice )
            {
                case FW_IF_DEVICE_QSFP:
                {
                    if( ppxCurrentExDev->xExDevStatus != xNewExDevStatus )
                    {
                        ppxCurrentExDev->xExDevStatus = xNewExDevStatus;

                        /* Raise event using Device ID as the method to track the event */
                        EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                                MAX_AXC_PROXY_DRIVER_EVENTS,
                                                ppxCurrentExDev->pxExDevLocalDeviceCfg->ucExDeviceId,
                                                0 };

                        if( AXC_STATUS_PRESENT == xNewExDevStatus )
                        {
                            xNewSignal.ucEventType = AXC_PROXY_DRIVER_E_QSFP_PRESENT;
                        }
                        else
                        {
                            xNewSignal.ucEventType = AXC_PROXY_DRIVER_E_QSFP_NOT_PRESENT;
                        }

                        if( ERROR == iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal ) )
                        {
                            PLL_ERR( AXC_NAME, "Error attempting to raise event 0x%x\r\n",
                                    xNewSignal.ucEventType );

                            if( AXC_STATUS_PRESENT == xNewExDevStatus )
                            {
                                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_RAISE_EVENT_PRESENT_FAILED )
                            }
                            else
                            {
                                INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_RAISE_EVENT_NOT_PRESENT_FAILED )
                            }
                        }
                    }
                    break;
                }

                case FW_IF_DEVICE_DIMM:
                    /* No events raised fro DIMM as it's not removable */
                    break;

                default:
                    INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_UNKNOWN_DEVICE )
                    break;
            }
            /* Move to next External Device held within linked list */
            ppxCurrentExDev = ppxCurrentExDev->pxNextExDev;
        }
        pxThis->pulStatCounters[ AXC_PROXY_STATS_TASK_TIME_MS ] = UTIL_ELAPSED_TIME_MS( ulStartMs )
        iOSAL_Task_SleepMs( AXC_TASK_SLEEP_MS );
    }
}

/**
 * @brief   Insert  External Device link into list at beginning
 */
static int iInsertExDevListBegin( AXC_PROXY_DRIVER_EXTERNAL_DEVICE_CONFIG *pxExDevCfg )
{
    int iStatus = ERROR;

    if( NULL != pxExDevCfg )
    {
        /* create link */
        AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST *pxLink = ( AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST* )pvOSAL_MemAlloc( sizeof( AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST ) );

        if( NULL != pxLink )
        {
            /* set data */
            pxLink->pxExDevLocalDeviceCfg = pxExDevCfg;
            pxLink->fExDevTemperature = AXC_EXTERNAL_DEVICE_TEMP_NOT_SET;
            pxLink->xExDevStatus = AXC_STATUS_FAILED;

            /* point this link to old first link */
            pxLink->pxNextExDev = pxThis->pxLinkedListHead;

            /* point head to new first link */
            pxThis->pxLinkedListHead = pxLink;
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AXC_PROXY_ERRORS_LIST_APPEND_FAILED )
        }
    }

    return iStatus;
}

/**
 * @brief   Find External Device handle from link list based on unique ID
 */
static int iGetExDevFromList( AXC_PRIVATE_EXTERNAL_DEVICE_LINKED_LIST **ppxCurrentExDev, uint8_t ucExDeviceId )
{
    int iStatus = ERROR;

    if( NULL != ppxCurrentExDev )
    {
        *ppxCurrentExDev = pxThis->pxLinkedListHead;

        /* find required External Device from list */
        while( ( NULL != *ppxCurrentExDev ) &&
            ( ucExDeviceId != ( *ppxCurrentExDev )->pxExDevLocalDeviceCfg->ucExDeviceId ) )
        {
            *ppxCurrentExDev = ( *ppxCurrentExDev )->pxNextExDev;
        }

        if( NULL != *ppxCurrentExDev )
        {
            iStatus = OK;
        }
    }

    return iStatus;
}
