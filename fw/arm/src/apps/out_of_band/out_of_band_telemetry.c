/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the amc oo band telemetry implementation
 *
 * @file out_of_band_telemetry.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

/* common includes */
#include "standard.h"
#include "util.h"
#include "pll.h"
#include "amc_cfg.h"
#include "asdm.h"

/* profile */
#include "profile_hal.h"

/* core_libs */
#include "evl.h"

/* proxy drivers */
#include "asc_proxy_driver.h"
#include "bmc_proxy_driver.h"

/* apps */
#include "out_of_band_telemetry.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define OUT_OF_BAND_NAME "AMC_OUT_OF_BAND"

#define UPPER_FIREWALL ( 0xBABECAFE )
#define LOWER_FIREWALL ( 0xDEADFACE )


/* Stat & Error definitions */
#define OUT_OF_BAND_STATS( DO )                           \
        DO( OUT_OF_BAND_STATS_INIT_OVERALL_COMPLETE )     \
        DO( OUT_OF_BAND_STATS_TAKE_MUTEX )                \
        DO( OUT_OF_BAND_STATS_RELEASE_MUTEX )             \
        DO( OUT_OF_BAND_STATS_BMC_SENSOR_INFO_REQUEST )   \
        DO( OUT_OF_BAND_STATS_BMC_SENSOR_ENABLE_REQUEST ) \
        DO( OUT_OF_BAND_STATS_BMC_PDR_REQUEST )           \
        DO( OUT_OF_BAND_STATS_BMC_PDR_INFO_REQUEST )      \
        DO( OUT_OF_BAND_STATS_BMC_UNSUPPORTED_REQUEST )   \
        DO( OUT_OF_BAND_STATS_MAX )

#define OUT_OF_BAND_ERRORS( DO )                                         \
        DO( OUT_OF_BAND_ERRORS_INIT_MUTEX_FAILED )                       \
        DO( OUT_OF_BAND_ERRORS_INIT_BIND_BMC_CB_FAILED )                 \
        DO( OUT_OF_BAND_ERRORS_INIT_OVERALL_FAILED )                     \
        DO( OUT_OF_BAND_ERRORS_MUTEX_RELEASE_FAILED )                    \
        DO( OUT_OF_BAND_ERRORS_MUTEX_TAKE_FAILED )                       \
        DO( OUT_OF_BAND_ERRORS_MALLOC_FAILED )                           \
        DO( OUT_OF_BAND_ERRORS_BMC_GET_SENSOR_REQUEST_FAILED )           \
        DO( OUT_OF_BAND_ERRORS_ASC_GET_SENSOR_DATA_FAILED )              \
        DO( OUT_OF_BAND_ERRORS_ASC_SET_SENSOR_OPERATIONAL_STATE_FAILED ) \
        DO( OUT_OF_BAND_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )  PLL_INF( OUT_OF_BAND_NAME,           \
                                          "%50s . . . . %d\r\n",      \
                                          OUT_OF_BAND_STATS_STR[ x ], \
                                          pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x ) PLL_INF( OUT_OF_BAND_NAME,            \
                                          "%50s . . . . %d\r\n",       \
                                          OUT_OF_BAND_ERRORS_STR[ x ], \
                                          pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )  { if( x < OUT_OF_BAND_STATS_MAX ) pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x ) { if( x < OUT_OF_BAND_ERRORS_MAX ) pxThis->pulErrorCounters[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    OUT_OF_BAND_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( OUT_OF_BAND_STATS, OUT_OF_BAND_STATS, OUT_OF_BAND_STATS_STR )

/**
 * @enum    OUT_OF_BAND_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( OUT_OF_BAND_ERRORS, OUT_OF_BAND_ERRORS, OUT_OF_BAND_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                     */
/******************************************************************************/

/**
 * @struct  OUT_OF_BAND_PRIVATE_DATA
 * @brief   Structure to hold the out of band telemetry private data
 */
typedef struct OUT_OF_BAND_PRIVATE_DATA
{
    uint32_t ulUpperFirewall;
    int      iInitialised;
    void     *pvOsalMutexHdl;
    uint32_t pulStatCounters[ OUT_OF_BAND_STATS_MAX ];
    uint32_t pulErrorCounters[ OUT_OF_BAND_ERRORS_MAX ];
    uint32_t ulLowerFirewall;

} OUT_OF_BAND_PRIVATE_DATA;


/******************************************************************************/
/* Local Variables                                                            */
/******************************************************************************/

static OUT_OF_BAND_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                                                            /* ulUpperFirewall      */
    FALSE,                                                                     /* iInitialised         */
    NULL,                                                                      /* pvOsalMutexHdl       */
    {
        0
    },                                                                         /* pulStatCounters       */
    {
        0
    },                                                                         /* pulErrorCounters      */
    LOWER_FIREWALL                                                             /* ulLowerFirewall      */
};
static OUT_OF_BAND_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* EVL Callback Declarations                                                  */
/******************************************************************************/

/**
 * @brief   EVL Callbacks for binding to Proxy Drivers
 *
 * @param   pxSignal     Event raised
 *
 * @return  OK if no errors were raised in the callback
 *          ERROR if an error was raised in the callback
 */
static int iBmcProxyCallback( EVL_SIGNAL *pxSignal );


/******************************************************************************/
/* Function Implementations                                                   */
/******************************************************************************/

/**
 * @brief   Initialise the out of band telemetry application layer
 *          used to handle events and communication with RMI handler
 *
 */
int iOUT_OF_BAND_TELEMETRY_Initialise( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) )
    {
        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvOsalMutexHdl, "out of band" ) )
        {
            INC_ERROR_COUNTER( OUT_OF_BAND_ERRORS_INIT_MUTEX_FAILED )
        }
        else
        {
            if( OK == iBMC_BindCallback( &iBmcProxyCallback ) )
            {
                PLL_DBG( OUT_OF_BAND_NAME, "BMC proxy bound\r\n" );
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( OUT_OF_BAND_ERRORS_INIT_BIND_BMC_CB_FAILED )
                iStatus = ERROR;
            }

            if( OK == iStatus )
            {
                pxThis->iInitialised = TRUE;
                INC_STAT_COUNTER( OUT_OF_BAND_STATS_INIT_OVERALL_COMPLETE )
            }
            else
            {
                INC_ERROR_COUNTER( OUT_OF_BAND_ERRORS_INIT_OVERALL_FAILED )
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Print all the stats gathered by the application
 *
 */
int iOUT_OF_BAND_TELEMETRY_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( OUT_OF_BAND_NAME, "============================================================\n\r" );
        PLL_INF( OUT_OF_BAND_NAME, "Out of Band App Statistics:\n\r" );
        for( i = 0; i < OUT_OF_BAND_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( OUT_OF_BAND_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( OUT_OF_BAND_NAME, "Out of Band App Errors:\n\r" );
        for( i = 0; i < OUT_OF_BAND_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( OUT_OF_BAND_NAME, "============================================================\n\r" );

        iStatus = OK;
    }

    return iStatus;
}

/**
 * @brief   Clear all the stats in the application
 *
 */
int iOUT_OF_BAND_TELEMETRY_ClearStatistics( void )
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

    return iStatus;
}


/******************************************************************************/
/* EVL Callback Implementations                                               */
/******************************************************************************/

/**
 * @brief   RMI Handler EVL callback
 */
static int iBmcProxyCallback( EVL_SIGNAL *pxSignal )
{
    int iStatus = ERROR;

    if( ( NULL != pxSignal ) && ( AMC_CFG_UNIQUE_ID_BMC == pxSignal->ucModule ) )
    {
        if( MAX_BMC_PROXY_DRIVER_EVENTS >= pxSignal->ucEventType )
        {
            switch( pxSignal->ucEventType )
            {
            case BMC_PROXY_DRIVER_E_GET_PDR:
            {
                INC_STAT_COUNTER( OUT_OF_BAND_STATS_BMC_PDR_REQUEST )
                break;
            }

            case BMC_PROXY_DRIVER_E_GET_PDR_REPOSITORY_INFO:
            {
                INC_STAT_COUNTER( OUT_OF_BAND_STATS_BMC_PDR_INFO_REQUEST )
                break;

            }

            case BMC_PROXY_DRIVER_E_GET_SENSOR_INFO:
            {
                INC_STAT_COUNTER( OUT_OF_BAND_STATS_BMC_SENSOR_INFO_REQUEST )

                int16_t ssSensorDataResponse = 0;
                int16_t ssSensorId = 0;
                ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS ucSensorOperationalState = 0;
                uint32_t ulSensorType = 0;

                /* call into BMC Proxy to get required sensor id */
                if( OK != iBMC_GetSensorIdRequest( pxSignal, &ssSensorId, ( uint8_t * )&ucSensorOperationalState ) )
                {
                    INC_ERROR_COUNTER( OUT_OF_BAND_ERRORS_BMC_GET_SENSOR_REQUEST_FAILED )
                }
                else
                {
                    uint32_t ulSensorId = 0;

                    ASC_PROXY_DRIVER_SENSOR_DATA xSensorData =
                    {
                        0
                    };

                    /* decode PLDM sensor ID to AMC ID */
                    ulSensorId = ssSensorId & 0xFF;

                    BMC_GET_SENSOR_RESPONSE xSensorResponse = BMC_GET_SENSOR_RESP_INVALID_SENSOR_ID;
                    if( OK != iASC_GetSingleSensorDataById( ulSensorId, &xSensorData ) )
                    {
                        INC_ERROR_COUNTER( OUT_OF_BAND_ERRORS_ASC_GET_SENSOR_DATA_FAILED );
                        iBMC_SendResponseForGetSensor( pxSignal,
                                                       ssSensorId,
                                                       ssSensorDataResponse,
                                                       ucSensorOperationalState,
                                                       xSensorResponse );
                    }
                    else
                    {
                        ulSensorType = ssSensorId >> 8;

                        if( OK != iASC_GetSingleSensorOperationalStateById( ulSensorId,
                                                                            ulSensorType,
                                                                            &ucSensorOperationalState ) )
                        {
                            INC_ERROR_COUNTER( OUT_OF_BAND_ERRORS_ASC_GET_SENSOR_DATA_FAILED );
                            iBMC_SendResponseForGetSensor( pxSignal,
                                                           ssSensorId,
                                                           ssSensorDataResponse,
                                                           ucSensorOperationalState,
                                                           xSensorResponse );
                        }
                        else
                        {
                            ssSensorDataResponse =
                                ( int16_t )xSensorData.pxReadings[ ulSensorType ].ulSensorValue;
                            xSensorResponse = BMC_GET_SENSOR_RESP_OK;
                            iBMC_SendResponseForGetSensor( pxSignal,
                                                           ssSensorId,
                                                           ssSensorDataResponse,
                                                           ucSensorOperationalState,
                                                           xSensorResponse );
                        }
                    }
                }
                break;

            }

            case BMC_PROXY_DRIVER_E_ENABLE_SENSOR:
            {
                INC_STAT_COUNTER( OUT_OF_BAND_STATS_BMC_SENSOR_ENABLE_REQUEST )

                int16_t ssSensorId = 0;
                uint8_t ucSensorOperationalState = 0;

                /* call into BMC Proxy to get required sensor id */
                if( OK != iBMC_GetSensorIdRequest( pxSignal, &ssSensorId, &ucSensorOperationalState ) )
                {
                    INC_ERROR_COUNTER( OUT_OF_BAND_ERRORS_BMC_GET_SENSOR_REQUEST_FAILED )
                }
                else
                {
                    uint32_t ulSensorId   = 0;
                    uint32_t ulSensorType = 0;

                    /* decode PLDM sensor ID to AMC ID */
                    ulSensorId   = ssSensorId & 0xFF;
                    ulSensorType = ssSensorId >> 8;

                    BMC_GET_SENSOR_RESPONSE xSensorResponse = BMC_GET_SENSOR_RESP_INVALID_SENSOR_ID;

                    if( OK != iASC_SetSingleSensorOperationalStateById( ulSensorId,
                                                                        ulSensorType,
                                                                        ucSensorOperationalState ) )
                    {
                        INC_ERROR_COUNTER( OUT_OF_BAND_ERRORS_ASC_SET_SENSOR_OPERATIONAL_STATE_FAILED );

                        BMC_GET_SENSOR_RESPONSE xSensorResponse = BMC_GET_SENSOR_RESP_INVALID_SENSOR_ID;
                        iBMC_SetResponse( pxSignal,
                                          ssSensorId,
                                          xSensorResponse );
                    }
                    else
                    {
                        xSensorResponse = BMC_GET_SENSOR_RESP_OK;
                        iBMC_SetResponse( pxSignal,
                                          ssSensorId,
                                          xSensorResponse );
                    }
                }
                break;
            }

            default:
            {
                INC_STAT_COUNTER( OUT_OF_BAND_STATS_BMC_UNSUPPORTED_REQUEST )
                break;
            }
            }

            iStatus = OK;
        }
    }

    return iStatus;
}
