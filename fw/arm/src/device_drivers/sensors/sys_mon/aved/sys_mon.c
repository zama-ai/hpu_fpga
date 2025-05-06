/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains the function implementations for the System Monnitor
 * sensor.
 *
 * @file sys_mon.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"
#include "util.h"
#include "pll.h"

#include "xstatus.h"
#include "xsysmonpsv.h"

#include "osal.h"

#include "sys_mon.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL                  ( 0xBABECAFE )
#define LOWER_FIREWALL                  ( 0xDEADFACE )

#define SYS_MON_NAME                    "SYS_MON"

#define SYS_MON_DEFAULT_V_TYPE          ( VCCAUX )

#define SYS_MON_STATS( DO )             \
    DO( SYS_MON_STATS_INITIALISED )     \
    DO( SYS_MON_STATS_MUTEX_CREATED )   \
    DO( SYS_MON_STATS_MUTEX_TAKEN )     \
    DO( SYS_MON_STATS_MUTEX_RELEASED )  \
    DO( SYS_MON_STATS_VOLTAGE_READ )    \
    DO( SYS_MON_STATS_TEMP_READ )       \
    DO( SYS_MON_STATS_MAX )

#define SYS_MON_ERRORS( DO )            \
    DO( SYS_MON_ERRORS_MUTEX_CREATED )  \
    DO( SYS_MON_ERRORS_MUTEX_TAKEN )    \
    DO( SYS_MON_ERRORS_MUTEX_RELEASED ) \
    DO( SYS_MON_ERRORS_VALIDATION )     \
    DO( SYS_MON_ERRORS_INSTANCE )       \
    DO( SYS_MON_ERRORS_VOLTAGE_READ )   \
    DO( SYS_MON_ERRORS_TEMP_READ )      \
    DO( SYS_MON_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )         PLL_INF( SYS_MON_NAME, "%50s . . . . %d\r\n",          \
                                                 SYS_MON_STATS_STR[ x ],                       \
                                                 pxThis->ulStats[ x ] )
#define PRINT_ERROR_COUNTER( x )        PLL_INF( SYS_MON_NAME, "%50s . . . . %d\r\n",          \
                                                 SYS_MON_ERRORS_STR[ x ],                      \
                                                 pxThis->ulErrors[ x ] )

#define INC_STAT_COUNTER( x )           { if( x < SYS_MON_STATS_MAX )pxThis->ulStats[ x ]++; }
#define INC_ERROR_COUNTER( x )          { if( x < SYS_MON_ERRORS_MAX )pxThis->ulErrors[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    SYS_MON_STATS
 * @brief   Enumeration of stats counters for this library
 */
UTIL_MAKE_ENUM_AND_STRINGS( SYS_MON_STATS, SYS_MON_STATS, SYS_MON_STATS_STR )

/**
 * @enum    SYS_MON_ERRORS
 * @brief   Enumeration of stats errors for this library
 */
UTIL_MAKE_ENUM_AND_STRINGS( SYS_MON_ERRORS, SYS_MON_ERRORS, SYS_MON_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  SYS_MON_PRIVATE_DATA
 * @brief   Private driver data
 */
typedef struct SYS_MON_PRIVATE_DATA
{
    uint32_t    ulUpperFirewall;

    int         iIsInitialised;
    XSysMonPsv  xCfgInstance;

    float       fLatestTemperature;
    float       fLatestVoltageInV;

    void        *pvMtxHdl;

    uint32_t    ulStats[ SYS_MON_STATS_MAX  ];
    uint32_t    ulErrors[ SYS_MON_ERRORS_MAX ];

    uint32_t    ulLowerFirewall;

} SYS_MON_PRIVATE_DATA;


/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

static SYS_MON_PRIVATE_DATA xPrivateData =
{
    UPPER_FIREWALL,     /* ulUpperFirewall */
    FALSE,              /* iIsInitialised */
    { { 0 } },          /* xCfgInstance */
    0.0,                /* fLastTemperature */
    0.0,                /* fLastVoltage */
    NULL,               /* pvMtxHdl */
    { 0 },              /* ulStats */
    { 0 },              /* ulErrors */
    LOWER_FIREWALL      /* ulLowerFirewall */
};

static SYS_MON_PRIVATE_DATA *pxThis = &xPrivateData;


/******************************************************************************/
/* Public function implementations                                             */
/******************************************************************************/

/**
 * @brief   Initialise System Monitor
 */
int iSYS_MON_Initialise( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iIsInitialised ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Create( &pxThis->pvMtxHdl, "SYS_MON Mtx" ) )
        {
            INC_STAT_COUNTER( SYS_MON_STATS_MUTEX_CREATED );
            if( XST_SUCCESS == XSysMonPsv_Init( &pxThis->xCfgInstance, NULL ) )
            {
                INC_STAT_COUNTER( SYS_MON_STATS_INITIALISED );
                pxThis->iIsInitialised = TRUE;
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( SYS_MON_ERRORS_INSTANCE );
            }
        }
        else
        {
            INC_ERROR_COUNTER( SYS_MON_ERRORS_MUTEX_CREATED );
        }
    }
    else
    {
        INC_ERROR_COUNTER( SYS_MON_ERRORS_VALIDATION );
    }

    return iStatus;
}

/**
 * @brief   Read temperature from System Monitor
 */
int iSYS_MON_ReadTemperature( float *pfTemperatureInC )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pfTemperatureInC ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvMtxHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( SYS_MON_STATS_MUTEX_TAKEN );

            if( XST_SUCCESS == XSysMonPsv_ReadTempProcessed( &pxThis->xCfgInstance,
                                                             XSYSMONPSV_TEMP,
                                                             &pxThis->fLatestTemperature ) )
            {
                INC_STAT_COUNTER( SYS_MON_STATS_TEMP_READ );

                *pfTemperatureInC = pxThis->fLatestTemperature;

                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvMtxHdl ) )
                {
                    INC_STAT_COUNTER( SYS_MON_STATS_MUTEX_RELEASED );
                    iStatus = OK;
                }
                else
                {
                    INC_ERROR_COUNTER( SYS_MON_ERRORS_MUTEX_RELEASED );
                }
            }
            else
            {
                INC_ERROR_COUNTER( SYS_MON_ERRORS_TEMP_READ );
            }
        }
        else
        {
            INC_ERROR_COUNTER( SYS_MON_ERRORS_MUTEX_TAKEN );
        }
    }
    else
    {
        INC_ERROR_COUNTER( SYS_MON_ERRORS_VALIDATION );
    }

    return iStatus;
}

/**
 * @brief   Read voltage from System Monitor
 */
int iSYS_MON_ReadVoltage( SYS_MON_VOLTAGES_ENUM xVoltageType, float *pfVoltageInMV )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( MAX_SYS_MON_VOLTAGE > xVoltageType ) &&
        ( NULL != pfVoltageInMV ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvMtxHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            int iMappedVType = 0;

            INC_STAT_COUNTER( SYS_MON_STATS_MUTEX_TAKEN );

            switch( xVoltageType )
            {
            case SYS_MON_VOLTAGES_VCCAUX:
                iMappedVType = VCCAUX;
                break;
            case SYS_MON_VOLTAGES_VCCAUXSMON:
                iMappedVType = VCCAUXSMON;
                break;
            case SYS_MON_VOLTAGES_VCCAUXPMC:
                iMappedVType = VCCAUXPMC;
                break;
            default:
                iMappedVType = SYS_MON_DEFAULT_V_TYPE;
                break;
            }

            if( XST_SUCCESS == XSysMonPsv_ReadSupplyProcessed( &pxThis->xCfgInstance,
                                                             iMappedVType,
                                                             &pxThis->fLatestVoltageInV ) )
            {
                INC_STAT_COUNTER( SYS_MON_STATS_VOLTAGE_READ );

                *pfVoltageInMV = pxThis->fLatestVoltageInV * 1000.0;

                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvMtxHdl ) )
                {
                    INC_STAT_COUNTER( SYS_MON_STATS_MUTEX_RELEASED );
                    iStatus = OK;
                }
                else
                {
                    INC_ERROR_COUNTER( SYS_MON_ERRORS_MUTEX_RELEASED );
                }
            }
            else
            {
                INC_ERROR_COUNTER( SYS_MON_ERRORS_VOLTAGE_READ );
            }
        }
        else
        {
            INC_ERROR_COUNTER( SYS_MON_ERRORS_MUTEX_TAKEN );
        }
    }
    else
    {
        INC_ERROR_COUNTER( SYS_MON_ERRORS_VALIDATION );
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iSYS_MON_PrintStatistics( void )
{
     int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( SYS_MON_NAME, "============================================================\n\r" );
        PLL_INF( SYS_MON_NAME, "SYS_MON Statistics:\n\r" );
        for( i = 0; i < SYS_MON_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( SYS_MON_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( SYS_MON_NAME, "SYS_MON Errors:\n\r" );
        for( i = 0; i < SYS_MON_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( SYS_MON_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( SYS_MON_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iSYS_MON_ClearStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) )
    {
        pvOSAL_MemSet( pxThis->ulStats, 0, sizeof( pxThis->ulStats ) );
        pvOSAL_MemSet( pxThis->ulErrors, 0, sizeof( pxThis->ulErrors ) );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( SYS_MON_ERRORS_VALIDATION )
    }

    return iStatus;
}

