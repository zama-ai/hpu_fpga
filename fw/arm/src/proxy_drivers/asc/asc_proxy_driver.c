/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implementation for the Alveo Sensor Control (ASC)
 * proxy driver.
 *
 * @file asc_proxy_driver.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "util.h"
#include "pll.h"
#include "osal.h"
#include "asc_proxy_driver.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL ( 0xBABECAFE )
#define LOWER_FIREWALL ( 0xDEADFACE )

#define ASC_TASK_SLEEP_MS ( 100 )

#define ASC_NAME "ASC"

/* Stat & Error definitions */
#define ASC_PROXY_STATS( DO )                                  \
        DO( ASC_PROXY_STATS_INIT_OVERALL_COMPLETE )            \
        DO( ASC_PROXY_STATS_CREATE_MUTEX )                     \
        DO( ASC_PROXY_STATS_TAKE_MUTEX )                       \
        DO( ASC_PROXY_STATS_RELEASE_MUTEX )                    \
        DO( ASC_PROXY_STATS_GET_ALL_SENSOR_DATA )              \
        DO( ASC_PROXY_STATS_GET_SINGLE_SENSOR_DATA_BY_ID )     \
        DO( ASC_PROXY_STATS_GET_SINGLE_SENSOR_DATA_BY_NAME )   \
        DO( ASC_PROXY_STATS_RESET_ALL_SENSOR_DATA )            \
        DO( ASC_PROXY_STATS_RESET_SINGLE_SENSOR_DATA_BY_ID )   \
        DO( ASC_PROXY_STATS_RESET_SINGLE_SENSOR_DATA_BY_NAME ) \
        DO( ASC_PROXY_STATS_TASK_TIME_MS )                     \
        DO( ASC_PROXY_STATS_STATUS_RETRIEVAL )                 \
        DO( ASC_PROXY_STATS_SET_SENSOR_THRESHOLD_BY_ID )       \
        DO( ASC_PROXY_GET_OPERATIONAL_STATE )                  \
        DO( ASC_PROXY_STATS_SET_OPERATIONAL_STATE_BY_ID )      \
        DO( ASC_PROXY_STATS_GET_OPERATIONAL_STATE_BY_ID )      \
        DO( ASC_PROXY_STATS_MAX )

#define ASC_PROXY_ERRORS( DO )                                  \
        DO( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )             \
        DO( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )                \
        DO( ASC_PROXY_ERRORS_MEM_ALLOC_FAILED )                 \
        DO( ASC_PROXY_ERRORS_GET_ALL_SENSOR_DATA )              \
        DO( ASC_PROXY_ERRORS_GET_SINGLE_SENSOR_DATA_BY_ID )     \
        DO( ASC_PROXY_ERRORS_GET_SINGLE_SENSOR_DATA_BY_NAME )   \
        DO( ASC_PROXY_ERRORS_RESET_ALL_SENSOR_DATA )            \
        DO( ASC_PROXY_ERRORS_RESET_SINGLE_SENSOR_DATA_BY_ID )   \
        DO( ASC_PROXY_ERRORS_RESET_SINGLE_SENSOR_DATA_BY_NAME ) \
        DO( ASC_PROXY_ERRORS_RAISE_EVENT_FAILED )               \
        DO( ASC_PROXY_ERRORS_INIT_FW_IF_OPEN_FAILED )           \
        DO( ASC_PROXY_ERRORS_INIT_MUTEX_CREATE_FAILED )         \
        DO( ASC_PROXY_ERRORS_INIT_TASK_CREATE_FAILED )          \
        DO( ASC_PROXY_ERRORS_VALIDATION_FAILED )                \
        DO( ASC_PROXY_ERRORS_UNKNOWN_RETURN_CODE )              \
        DO( ASC_PROXY_ERRORS_BIND_CB_FAILED )                   \
        DO( ASC_PROXY_ERRORS_INIT_EVL_RECORD_FAILED )           \
        DO( ASC_PROXY_ERRORS_SET_SENSOR_THRESHOLD_BY_ID )       \
        DO( ASC_PROXY_ERRORS_GET_OPERATIONAL_STATE_BY_ID )      \
        DO( ASC_PROXY_ERRORS_SET_OPERATIONAL_STATE_BY_ID )      \
        DO( ASC_PROXY_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )  PLL_INF( ASC_NAME,                 \
                                          "%50s . . . . %d\r\n",    \
                                          ASC_PROXY_STATS_STR[ x ], \
                                          pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x ) PLL_INF( ASC_NAME,                  \
                                          "%50s . . . . %d\r\n",     \
                                          ASC_PROXY_ERRORS_STR[ x ], \
                                          pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )             { if( x < ASC_PROXY_STATS_MAX ) pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x )            { if( x < ASC_PROXY_ERRORS_MAX ) pxThis->pulErrorCounters[ x ]++; }
#define INC_ERROR_COUNTER_WITH_STATE( x ) { pxThis->xState = MODULE_STATE_ERROR; INC_ERROR_COUNTER( x ) }
#define SET_STAT_COUNTER( x, y )          { if( x < ASC_PROXY_ERRORS_MAX ) pxThis->pulStatCounters[ x ] = y; }
#define ASC_ELAPSED_TIME_MS( x, y )       ( ( x - y ) / 10 );


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    ASC_PROXY_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( ASC_PROXY_STATS, ASC_PROXY_STATS, ASC_PROXY_STATS_STR )

/**
 * @enum    ASC_PROXY_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( ASC_PROXY_ERRORS, ASC_PROXY_ERRORS, ASC_PROXY_ERRORS_STR )

/******************************************************************************/
/* Structures                                                                 */
/******************************************************************************/
/**
 * @brief   Structure to hold ths proxy driver's private data
 */
typedef struct ASC_PRIVATE_DATA
{
    uint32_t                     ulUpperFirewall;

    int                          iInitialised;
    uint8_t                      ucMyId;

    EVL_RECORD                   *pxEvlRecord;

    void                         *pvOsalMutexHdl;
    void                         *pvOsalTaskHdl;

    ASC_PROXY_DRIVER_SENSOR_DATA *pxSensorData;
    uint8_t                      ucNumSensors;

    uint32_t                     pulStatCounters[ ASC_PROXY_STATS_MAX ];
    uint32_t                     pulErrorCounters[ ASC_PROXY_ERRORS_MAX ];

    MODULE_STATE                 xState;

    uint32_t                     ulLowerFirewall;

} ASC_PRIVATE_DATA;


/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

static ASC_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                                                            /* ulUpperFirewall */
    FALSE,                                                                     /* iInitialised */
    0,                                                                         /* ucMyId */
    NULL,                                                                      /* pxEvlRecord */
    NULL,                                                                      /* pvOsalMutexHdl */
    NULL,                                                                      /* pvOsalTaskHdl */
    NULL,                                                                      /* pxSensorData */
    0,                                                                         /* ucNumSensors */
    {
        0
    },                                                                         /* pulStatCounters */
    {
        0
    },                                                                         /* pulErrorCounters */
    MODULE_STATE_UNINITIALISED,                                                /* xState */
    LOWER_FIREWALL                                                             /* ulLowerFirewall */
};
static ASC_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Local Function declarations                                                */
/******************************************************************************/

/**
 * @brief   Task declaration
 *
 * @param   pvArgs  Pointer to task args (unused)
 *
 * @return  N/A
 *
 */
static void vProxyDriverTask( void *pvArgs );


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/* Init functions *************************************************************/

/**
 * @brief   Main initialisation point for the ASC Proxy Driver
 */
int iASC_Initialise( uint8_t ucProxyId,
                     uint32_t ulTaskPrio,
                     uint32_t ulTaskStack,
                     ASC_PROXY_DRIVER_SENSOR_DATA *pxSensorData,
                     uint8_t ucNumSensors )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) &&
        ( NULL != pxSensorData ) )
    {
        /* store parameters locally */
        pxThis->ucMyId = ucProxyId;

        /* initalise evl record*/
        if( OK != iEVL_CreateRecord( &pxThis->pxEvlRecord ) )
        {
            PLL_ERR( ASC_NAME, "Error initialising EVL_RECORD\r\n" );
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_INIT_EVL_RECORD_FAILED );

        }
        else
        {
            /* initialise OSAL items */
            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvOsalMutexHdl, "asc_proxy mutex" ) )
            {
                PLL_ERR( ASC_NAME, "Error initialising mutex\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_INIT_MUTEX_CREATE_FAILED )
            }
            else
            {
                INC_STAT_COUNTER( ASC_PROXY_STATS_CREATE_MUTEX )
                INC_STAT_COUNTER( ASC_PROXY_STATS_INIT_OVERALL_COMPLETE )
                pxThis->pxSensorData =
                    ( ASC_PROXY_DRIVER_SENSOR_DATA * )pvOSAL_MemAlloc( sizeof ( ASC_PROXY_DRIVER_SENSOR_DATA ) *
                                                                       ucNumSensors );

                if( NULL != pxThis->pxSensorData )
                {
                    pvOSAL_MemCpy( pxThis->pxSensorData,
                                   pxSensorData,
                                   sizeof( ASC_PROXY_DRIVER_SENSOR_DATA ) * ucNumSensors );
                    pxThis->ucNumSensors = ucNumSensors;
                    if( OSAL_ERRORS_NONE != iOSAL_Task_Create( &pxThis->pvOsalTaskHdl,
                                                               vProxyDriverTask,
                                                               ulTaskStack,
                                                               NULL,
                                                               ulTaskPrio,
                                                               "asc_proxy task" ) )
                    {
                        PLL_ERR( ASC_NAME, "Error initialising task\r\n" );
                        INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_INIT_TASK_CREATE_FAILED )
                    }
                    else
                    {
                        pxThis->iInitialised = TRUE;
                        pxThis->xState       = MODULE_STATE_OK;
                        iStatus              = OK;
                    }
                }
                else
                {
                    PLL_ERR( ASC_NAME, "pvOSAL_MemAlloc failed\r\n" );
                    INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MEM_ALLOC_FAILED )
                }
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Bind into this proxy driver
 */
int iASC_BindCallback( EVL_CALLBACK *pxCallback )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxCallback ) &&
        ( NULL != pxThis->pxEvlRecord ) )
    {
        iStatus = iEVL_BindCallback( pxThis->pxEvlRecord, pxCallback );
        if( ERROR == iStatus )
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_BIND_CB_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/* Set functions **************************************************************/

/**
 * @brief   Reset all sensor data
 */
int iASC_ResetAllSensorData( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_TAKE_MUTEX )

            int i = 0;
            int j = 0;

            for( i = 0; i < pxThis->ucNumSensors; i++ )
            {
                for( j = 0; j < MAX_ASC_PROXY_DRIVER_SENSOR_TYPE; j++ )
                {
                    pxThis->pxSensorData[ i ].pxReadings[ j ].ulSensorValue = 0;
                    pxThis->pxSensorData[ i ].pxReadings[ j ].xSensorStatus =
                        ASC_PROXY_DRIVER_SENSOR_STATUS_NOT_PRESENT;
                    pxThis->pxSensorData[ i ].pxReadings[ j ].ulAverageSensorValue     = 0;
                    pxThis->pxSensorData[ i ].pxReadings[ j ].ulMaxSensorValue         = 0;
                    pxThis->pxSensorData[ i ].pxReadings[ j ].xSensorOperationalStatus =
                        ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_ENABLED;
                }
            }

            INC_STAT_COUNTER( ASC_PROXY_STATS_RESET_ALL_SENSOR_DATA );
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }

        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            iStatus = ERROR;

        }
        else
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Reset single sensor data by ID
 */
int iASC_ResetSingleSensorDataById( uint8_t ucId )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_TAKE_MUTEX )

            int i = 0;
            int j = 0;

            for( i = 0; i < pxThis->ucNumSensors; i++ )
            {
                if( pxThis->pxSensorData[ i ].ucSensorId == ucId )
                {
                    for( j = 0; j < MAX_ASC_PROXY_DRIVER_SENSOR_TYPE; j++ )
                    {
                        pxThis->pxSensorData[ i ].pxReadings[ j ].ulSensorValue = 0;
                        pxThis->pxSensorData[ i ].pxReadings[ j ].xSensorStatus =
                            ASC_PROXY_DRIVER_SENSOR_STATUS_NOT_PRESENT;
                        pxThis->pxSensorData[ i ].pxReadings[ j ].ulAverageSensorValue     = 0;
                        pxThis->pxSensorData[ i ].pxReadings[ j ].ulMaxSensorValue         = 0;
                        pxThis->pxSensorData[ i ].pxReadings[ j ].xSensorOperationalStatus =
                            ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_ENABLED;
                    }

                    INC_STAT_COUNTER( ASC_PROXY_STATS_RESET_SINGLE_SENSOR_DATA_BY_ID );
                    iStatus = OK;
                    break;
                }
            }

            if( ERROR == iStatus )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_RESET_SINGLE_SENSOR_DATA_BY_NAME )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Reset single sensor data name
 */
int iASC_ResetSingleSensorDataByName( const char *pcName )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pcName ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_TAKE_MUTEX )

            int i = 0;
            int j = 0;

            for( i = 0; i < pxThis->ucNumSensors; i++ )
            {
                if( 0 == strncmp( pxThis->pxSensorData[ i ].pcSensorName, pcName, ASC_SENSOR_NAME_MAX ) )
                {
                    for( j = 0; j < MAX_ASC_PROXY_DRIVER_SENSOR_TYPE; j++ )
                    {
                        pxThis->pxSensorData[ i ].pxReadings[ j ].ulSensorValue = 0;
                        pxThis->pxSensorData[ i ].pxReadings[ j ].xSensorStatus =
                            ASC_PROXY_DRIVER_SENSOR_STATUS_NOT_PRESENT;
                        pxThis->pxSensorData[ i ].pxReadings[ j ].ulAverageSensorValue     = 0;
                        pxThis->pxSensorData[ i ].pxReadings[ j ].ulMaxSensorValue         = 0;
                        pxThis->pxSensorData[ i ].pxReadings[ j ].xSensorOperationalStatus =
                            ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_ENABLED;
                    }

                    INC_STAT_COUNTER( ASC_PROXY_STATS_RESET_SINGLE_SENSOR_DATA_BY_NAME );
                    iStatus = OK;
                    break;
                }
            }

            if( ERROR == iStatus )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_RESET_SINGLE_SENSOR_DATA_BY_NAME )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/* Get functions **************************************************************/

/**
 * @brief   Get all sensor data
 */
int iASC_GetAllSensorData( ASC_PROXY_DRIVER_SENSOR_DATA *pxData, uint8_t *pucNumSensors )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxData ) &&
        ( NULL != pucNumSensors ) )
    {
        INC_STAT_COUNTER( ASC_PROXY_STATS_GET_ALL_SENSOR_DATA )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_TAKE_MUTEX )

            if( pxThis->ucNumSensors <= *pucNumSensors )
            {
                pvOSAL_MemCpy( pxData,
                               pxThis->pxSensorData,
                               sizeof( ASC_PROXY_DRIVER_SENSOR_DATA ) * pxThis->ucNumSensors );
                *pucNumSensors = pxThis->ucNumSensors;
                iStatus        = OK;
            }
            else
            {
                *pucNumSensors = 0;
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_GET_ALL_SENSOR_DATA )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Get single sensor data by its ID
 */
int iASC_GetSingleSensorDataById( uint8_t ucId, ASC_PROXY_DRIVER_SENSOR_DATA *pxData )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxData ) )
    {
        INC_STAT_COUNTER( ASC_PROXY_STATS_GET_SINGLE_SENSOR_DATA_BY_ID )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_TAKE_MUTEX )

            int i = 0;

            for( i = 0; i < pxThis->ucNumSensors; i++ )
            {
                if( pxThis->pxSensorData[ i ].ucSensorId == ucId )
                {
                    pvOSAL_MemCpy( pxData, &pxThis->pxSensorData[ i ], sizeof( ASC_PROXY_DRIVER_SENSOR_DATA ) );
                    iStatus = OK;
                    break;
                }
            }

            if( ERROR == iStatus )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_RESET_SINGLE_SENSOR_DATA_BY_ID )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Get single sensor data by its name
 */
int iASC_GetSingleSensorDataByName( const char *pcName, ASC_PROXY_DRIVER_SENSOR_DATA *pxData )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pcName ) &&
        ( NULL != pxData ) )
    {
        INC_STAT_COUNTER( ASC_PROXY_STATS_GET_SINGLE_SENSOR_DATA_BY_NAME )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_TAKE_MUTEX )

            int i = 0;

            for( i = 0; i < pxThis->ucNumSensors; i++ )
            {
                if( 0 == strncmp( pxThis->pxSensorData[ i ].pcSensorName, pcName, ASC_SENSOR_NAME_MAX ) )
                {
                    pvOSAL_MemCpy( pxData, &pxThis->pxSensorData[ i ], sizeof( ASC_PROXY_DRIVER_SENSOR_DATA ) );
                    iStatus = OK;
                    break;
                }
            }

            if( ERROR == iStatus )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_RESET_SINGLE_SENSOR_DATA_BY_NAME )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Sets the threshold status of a single sensor
 */
int iASC_SetSingleSensorThresholdStatusById( uint8_t ucId, ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS xStatus )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_TAKE_MUTEX )

            int i = 0;

            for( i = 0; i < pxThis->ucNumSensors; i++ )
            {
                if( pxThis->pxSensorData[ i ].ucSensorId == ucId )
                {
                    pxThis->pxSensorData[ i ].ulThresholdStatus = xStatus;

                    iStatus = OK;

                    INC_STAT_COUNTER( ASC_PROXY_STATS_SET_SENSOR_THRESHOLD_BY_ID )

                    break;
                }
            }
            /* No sensor match found */
            if( ERROR == iStatus )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_SET_SENSOR_THRESHOLD_BY_ID )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set single sensor operational state by ID
 */
int iASC_SetSingleSensorOperationalStateById( uint8_t ucId,
                                              uint8_t ucSensorType,
                                              ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS ucOperationalState )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_TAKE_MUTEX )

            int i = 0;

            for( i = 0; i < pxThis->ucNumSensors; i++ )
            {
                if( pxThis->pxSensorData[ i ].ucSensorId == ucId )
                {
                    pxThis->pxSensorData[ i ].pxReadings[ ucSensorType ].xSensorOperationalStatus = ucOperationalState;
                    INC_STAT_COUNTER( ASC_PROXY_STATS_SET_OPERATIONAL_STATE_BY_ID );
                    iStatus = OK;
                    break;
                }
            }

            if( ERROR == iStatus )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_SET_OPERATIONAL_STATE_BY_ID )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Get single sensor operational state by ID
 */
int iASC_GetSingleSensorOperationalStateById( uint8_t ucId,
                                              uint8_t ucSensorType,
                                              ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS *pucOperationalState )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucOperationalState ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_TAKE_MUTEX )

            int i = 0;

            for( i = 0; i < pxThis->ucNumSensors; i++ )
            {
                if( pxThis->pxSensorData[ i ].ucSensorId == ucId )
                {
                    if( TRUE == pxThis->pxSensorData[ i ].pxSensorEnabled() )
                    {
                        *pucOperationalState =
                            pxThis->pxSensorData[ i ].pxReadings[ ucSensorType ].xSensorOperationalStatus;
                    }
                    else
                    {
                        *pucOperationalState = ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_UNAVAILABLE;
                    }
                    INC_STAT_COUNTER( ASC_PROXY_STATS_GET_OPERATIONAL_STATE_BY_ID );
                    iStatus = OK;
                    break;
                }
            }

            if( ERROR == iStatus )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_GET_OPERATIONAL_STATE_BY_ID )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iASC_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( ASC_NAME, "============================================================\n\r" );
        PLL_INF( ASC_NAME, "ASC Proxy Statistics:\n\r" );
        for( i = 0; i < ASC_PROXY_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( ASC_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( ASC_NAME, "ASC Proxy Errors:\n\r" );
        for( i = 0; i < ASC_PROXY_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( ASC_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iASC_ClearStatistics( void )
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
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Gets the current state of the proxy
 */
int iASC_GetState( MODULE_STATE *pxState )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxState ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_TASK_WAIT_MS ) )
        {
            *pxState = pxThis->xState;

            INC_STAT_COUNTER( ASC_PROXY_STATS_STATUS_RETRIEVAL );

            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }

        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            iStatus = ERROR;

        }
        else
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ASC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}


/******************************************************************************/
/* Local Function implementations                                             */
/******************************************************************************/

/**
 * @brief   Task to handle incoming requests and handle responses being sent out from the message queue
 */
static void vProxyDriverTask( void *pvArgs )
{
    EVL_SIGNAL xNewSignal =
    {
        pxThis->ucMyId,
        MAX_ASC_PROXY_DRIVER_EVENTS,
        0,
        0
    };

    int iNumberOfReadings[ pxThis->ucNumSensors ][ MAX_ASC_PROXY_DRIVER_SENSOR_TYPE ];

    pvOSAL_MemSet( iNumberOfReadings, 0, pxThis->ucNumSensors * sizeof( int ) * MAX_ASC_PROXY_DRIVER_SENSOR_TYPE );

    uint32_t ulSumOfSensorValues[ pxThis->ucNumSensors ][ MAX_ASC_PROXY_DRIVER_SENSOR_TYPE ];
    pvOSAL_MemSet( ulSumOfSensorValues,
                   0,
                   pxThis->ucNumSensors * sizeof( uint32_t ) * MAX_ASC_PROXY_DRIVER_SENSOR_TYPE );

    uint32_t ulStartMs = 0;

    FOREVER
    {
        ulStartMs = ulOSAL_GetUptimeTicks();
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASC_PROXY_STATS_TAKE_MUTEX )

            int i = 0;
            int j = 0;

            for( i = 0; i < pxThis->ucNumSensors; i++ )
            {
                if( TRUE == pxThis->pxSensorData[ i ].pxSensorEnabled() )
                {
                    for( j = 0; j < MAX_ASC_PROXY_DRIVER_SENSOR_TYPE; j++ )
                    {
                        if( NULL != pxThis->pxSensorData[ i ].ppxReadSensorFunc[ j ] )
                        {
                            float fTempSensorVal = 0.0;

                            if( OK == pxThis->pxSensorData[ i ].ppxReadSensorFunc[ j ]( ASC_SENSOR_I2C_BUS_NUM,
                                                                                        pxThis->pxSensorData[ i ].
                                                                                        ucSensorAddress,
                                                                                        pxThis->pxSensorData[ i ].
                                                                                        ucChannelNumber[ j ],
                                                                                        &fTempSensorVal ) )
                            {
                                /* Assigning float to uint32_t sensor value */
                                pxThis->pxSensorData[ i ].pxReadings[ j ].ulSensorValue = fTempSensorVal;
                                pxThis->pxSensorData[ i ].pxReadings[ j ].xSensorStatus =
                                    ASC_PROXY_DRIVER_SENSOR_STATUS_PRESENT_AND_VALID;

                                iNumberOfReadings[ i ][ j ]++;
                                ulSumOfSensorValues[ i ][ j ] +=
                                    pxThis->pxSensorData[ i ].pxReadings[ j ].ulSensorValue;

                                pxThis->pxSensorData[ i ].pxReadings[ j ].ulAverageSensorValue =
                                    ( pxThis->pxSensorData[ i ].pxReadings[ j ].ulAverageSensorValue
                                      - ( pxThis->pxSensorData[ i ].pxReadings[ j ].ulAverageSensorValue /
                                          iNumberOfReadings[ i ][ j ] )
                                      + ( fTempSensorVal / iNumberOfReadings[ i ][ j ] ) );

                                if( pxThis->pxSensorData[ i ].pxReadings[ j ].ulSensorValue >
                                    pxThis->pxSensorData[ i ].pxReadings[ j ].ulMaxSensorValue )
                                {
                                    pxThis->pxSensorData[ i ].pxReadings[ j ].ulMaxSensorValue =
                                        pxThis->pxSensorData[ i ].pxReadings[ j ].ulSensorValue;
                                }
                            }
                            else
                            {
                                pxThis->pxSensorData[ i ].pxReadings[ j ].xSensorStatus =
                                    ASC_PROXY_DRIVER_SENSOR_STATUS_DATA_NOT_AVAILABLE;
                            }
                        }
                    }
                }
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            }
            else
            {
                INC_STAT_COUNTER( ASC_PROXY_STATS_RELEASE_MUTEX )

                /* Signal event if sensor reading exceeds thresholds */
                for( i = 0; i < pxThis->ucNumSensors; i++ )
                {
                    if( TRUE == pxThis->pxSensorData[ i ].pxSensorEnabled() )
                    {
                        xNewSignal.ucInstance = pxThis->pxSensorData[ i ].ucSensorId;

                        for( j = 0; j < MAX_ASC_PROXY_DRIVER_SENSOR_TYPE; j++ )
                        {
                            /* Record Sensor type in the event */
                            xNewSignal.ucAdditionalData = j;
                            if( ( ASC_SENSOR_INVALID_VAL !=
                                  pxThis->pxSensorData[ i ].pxReadings[ j ].ulUpperFatalLimit ) &&
                                ( pxThis->pxSensorData[ i ].pxReadings[ j ].ulSensorValue >=
                                  pxThis->pxSensorData[ i ].pxReadings[ j ].ulUpperFatalLimit ) )
                            {
                                xNewSignal.ucEventType = ASC_PROXY_DRIVER_E_SENSOR_UPPER_FATAL;

                                if( ERROR == iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal ) )
                                {
                                    PLL_ERR( ASC_NAME,
                                             "Error attempting to raise event 0x%x\r\n",
                                             ASC_PROXY_DRIVER_E_SENSOR_UPPER_FATAL );
                                    INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_RAISE_EVENT_FAILED )
                                }
                            }
                            else if( ( ASC_SENSOR_INVALID_VAL !=
                                       pxThis->pxSensorData[ i ].pxReadings[ j ].ulUpperCriticalLimit ) &&
                                     ( pxThis->pxSensorData[ i ].pxReadings[ j ].ulSensorValue >=
                                       pxThis->pxSensorData[ i ].pxReadings[ j ].ulUpperCriticalLimit ) )
                            {
                                xNewSignal.ucEventType = ASC_PROXY_DRIVER_E_SENSOR_UPPER_CRITICAL;

                                if( ERROR == iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal ) )
                                {
                                    PLL_ERR( ASC_NAME,
                                             "Error attempting to raise event 0x%x\r\n",
                                             ASC_PROXY_DRIVER_E_SENSOR_UPPER_CRITICAL );
                                    INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_RAISE_EVENT_FAILED )
                                }
                            }
                            else if( ( ASC_SENSOR_INVALID_VAL !=
                                       pxThis->pxSensorData[ i ].pxReadings[ j ].ulUpperWarningLimit ) &&
                                     ( pxThis->pxSensorData[ i ].pxReadings[ j ].ulSensorValue >=
                                       pxThis->pxSensorData[ i ].pxReadings[ j ].ulUpperWarningLimit ) )
                            {
                                xNewSignal.ucEventType = ASC_PROXY_DRIVER_E_SENSOR_UPPER_WARNING;

                                if( ERROR == iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal ) )
                                {
                                    PLL_ERR( ASC_NAME,
                                             "Error attempting to raise event 0x%x\r\n",
                                             ASC_PROXY_DRIVER_E_SENSOR_UPPER_WARNING );
                                    INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_RAISE_EVENT_FAILED )
                                }
                            }
                        }
                    }
                }

                /* Signal event once all the data has been read */
                xNewSignal.ucEventType = ASC_PROXY_DRIVER_E_SENSOR_UPDATE_COMPLETE;
                xNewSignal.ucInstance  = 0;

                if( ERROR == iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal ) )
                {
                    PLL_ERR( ASC_NAME,
                             "Error attempting to raise event 0x%x\r\n",
                             ASC_PROXY_DRIVER_E_SENSOR_UPDATE_COMPLETE );
                    INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_RAISE_EVENT_FAILED )
                }
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( ASC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
        pxThis->pulStatCounters[ ASC_PROXY_STATS_TASK_TIME_MS ] = ASC_ELAPSED_TIME_MS( ulOSAL_GetUptimeTicks(),
                                                                                       ulStartMs )
                                                                  iOSAL_Task_SleepMs( ASC_TASK_SLEEP_MS );
    }
}
