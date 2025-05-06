/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implemenation for the Event Library
 *
 * @file evl.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "util.h"
#include "pll.h"
#include "osal.h"

#include "evl.h"

/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL ( 0xBABECAFE )
#define LOWER_FIREWALL ( 0xDEADFACE )

#define EVL_NAME "EVL"

#define EVL_STATS( DO )                       \
        DO( EVL_STATS_INITIALISED )           \
        DO( EVL_STATS_RECORDS )               \
        DO( EVL_STATS_BINDINGS )              \
        DO( EVL_STATS_SIGNALS )               \
        DO ( EVL_STATS_LOG_RETRIEVED )        \
        DO( EVL_STATS_LOG_MUTEX_CREATED )     \
        DO( EVL_STATS_LOG_MUTEX_GRABBED )     \
        DO( EVL_STATS_LOG_MUTEX_RELEASED )    \
        DO( EVL_STATS_RECORD_MUTEX_CREATED )  \
        DO( EVL_STATS_RECORD_MUTEX_GRABBED )  \
        DO( EVL_STATS_RECORD_MUTEX_RELEASED ) \
        DO( EVL_STATS_VERBOSITY_SET )         \
        DO( EVL_STATS_MAX )


#define EVL_ERRORS( DO )                       \
        DO( EVL_ERRORS_BINDINGS )              \
        DO( EVL_ERRORS_CALLBACKS )             \
        DO( EVL_ERRORS_VALIDATION )            \
        DO( EVL_ERRORS_LOG_MUTEX_CREATED )     \
        DO( EVL_ERRORS_LOG_MUTEX_GRABBED )     \
        DO( EVL_ERRORS_LOG_MUTEX_RELEASED )    \
        DO( EVL_ERRORS_RECORD_MUTEX_CREATED )  \
        DO( EVL_ERRORS_RECORD_MUTEX_GRABBED )  \
        DO( EVL_ERRORS_RECORD_MUTEX_RELEASED ) \
        DO( EVL_ERRORS_RECORD_MALLOC )         \
        DO( EVL_ERRORS_BINDINGS_MALLOC )       \
        DO( EVL_ERRORS_NO_BINDINGS )           \
        DO( EVL_ERRORS_VERBOSITY_NOT_SET )     \
        DO( EVL_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )  PLL_INF( EVL_NAME,              \
                                          "%50s . . . . %d\r\n", \
                                          EVL_STATS_STR[ x ],    \
                                          pxThis->ulStats[ x ] )
#define PRINT_ERROR_COUNTER( x ) PLL_INF( EVL_NAME,              \
                                          "%50s . . . . %d\r\n", \
                                          EVL_ERRORS_STR[ x ],   \
                                          pxThis->ulErrors[ x ] )

#define INC_STAT_COUNTER( x )  { if( x < EVL_STATS_MAX ) pxThis->ulStats[ x ]++; }
#define INC_ERROR_COUNTER( x ) { if( x < EVL_ERRORS_MAX ) pxThis->ulErrors[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    EVL_STATS
 * @brief   Enumeration of stats counters for this library
 */
UTIL_MAKE_ENUM_AND_STRINGS( EVL_STATS, EVL_STATS, EVL_STATS_STR )

/**
 * @enum    EVL_ERRORS
 * @brief   Enumeration of stats errors for this library
 */
UTIL_MAKE_ENUM_AND_STRINGS( EVL_ERRORS, EVL_ERRORS, EVL_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  EVL_PRIVATE_DATA
 * @brief   Local data struct
 */
typedef struct EVL_PRIVATE_DATA
{
    uint32_t   ulUpperFirewall;

    int        iIsInitialised;

    void       *pxLogMtx;
    int        iLogIdx;
    EVL_SIGNAL pxEvlLog[ EVL_LOG_LEN ];
    uint32_t   pulLogTimes[ EVL_LOG_LEN ];

    uint32_t   ulStats[ EVL_STATS_MAX ];
    uint32_t   ulErrors[ EVL_ERRORS_MAX ];

    uint32_t   ulLowerFirewall;

} EVL_PRIVATE_DATA;

/**
 * @struct EVL_CALLBACK_NODE
 * @brief Node for the EVL_CALLBACK Linked List
 */
typedef struct EVL_CALLBACK_NODE
{
    EVL_CALLBACK             *pxCallback;
    struct EVL_CALLBACK_NODE *pxNext;

} EVL_CALLBACK_NODE;

/**
 * @struct  EVL_RECORD
 * @brief   Record of EVL bindings
 */
typedef struct EVL_RECORD
{
    EVL_CALLBACK_NODE *pxFirstBinding;
    int               iNumBindings;
    void              *pxMtx;

} EVL_RECORD;


/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

static EVL_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                                                            /* ulUpperFirewall */
    FALSE,                                                                     /* iIsInitialised */
    NULL,                                                                      /* pxLogMtx */
    0,                                                                         /* iLogIdx */
    { {
          0
      } },                                                                     /* pxEvlLog */
    {
        0
    },                                                                         /* pulLogTimes */
    {
        0
    },                                                                         /* ulStats */
    {
        0
    },                                                                         /* ulErrors */
    LOWER_FIREWALL                                                             /* LOWER_FIREWALL */
};

static EVL_PRIVATE_DATA *pxThis = &xLocalData;

static int iEvlVerbosity = FALSE;


/******************************************************************************/
/* Public function implementations                                            */
/******************************************************************************/

/**
 * @brief   Initalise Event Library
 */
int iEVL_Initialise( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iIsInitialised ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Create( &pxThis->pxLogMtx, "EVL Log Mutex" ) )
        {
            INC_STAT_COUNTER( EVL_STATS_LOG_MUTEX_CREATED );
            INC_STAT_COUNTER( EVL_STATS_INITIALISED );
            pxThis->iIsInitialised = TRUE;
            iStatus                = OK;
        }
        else
        {
            INC_ERROR_COUNTER( EVL_ERRORS_LOG_MUTEX_CREATED );
        }
    }
    else
    {
        INC_ERROR_COUNTER( EVL_ERRORS_VALIDATION );
    }

    return iStatus;
}

/**
 * @brief Initialise the record
 */
int iEVL_CreateRecord( EVL_RECORD **ppxRecord )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != ppxRecord ) &&
        ( NULL == *ppxRecord ) )
    {
        EVL_RECORD *pxNewRecord = ( EVL_RECORD * ) pvOSAL_MemAlloc( sizeof( EVL_RECORD ) );
        if( NULL != pxNewRecord )
        {
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Create( &pxNewRecord->pxMtx, "EVL Record Mutex" ) )
            {
                INC_STAT_COUNTER( EVL_STATS_RECORD_MUTEX_CREATED );
                pxNewRecord->iNumBindings   = 0;
                pxNewRecord->pxFirstBinding = NULL;
                *ppxRecord                  = pxNewRecord;
                iStatus                     = OK;
            }
            else
            {
                INC_ERROR_COUNTER( EVL_ERRORS_RECORD_MUTEX_CREATED );
                vOSAL_MemFree( ( void** )&pxNewRecord );
            }
        }
        else
        {
            INC_ERROR_COUNTER( EVL_ERRORS_RECORD_MALLOC );
        }
    }
    else
    {
        INC_ERROR_COUNTER( EVL_ERRORS_VALIDATION );
    }

    return iStatus;
}

/**
 * @brief   Bind a callback into a module
 */
int iEVL_BindCallback( EVL_RECORD *pxRecord, EVL_CALLBACK *pxNewCallback )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pxRecord ) &&
        ( NULL != pxNewCallback ) )
    {
        if( pxRecord->iNumBindings < EVL_MAX_BINDINGS )
        {
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxRecord->pxMtx, OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                INC_STAT_COUNTER( EVL_STATS_RECORD_MUTEX_GRABBED );
                if( 0 == pxRecord->iNumBindings )
                {
                    EVL_CALLBACK_NODE *pxNewNode =
                        ( EVL_CALLBACK_NODE * ) pvOSAL_MemAlloc( sizeof( EVL_CALLBACK_NODE ) );
                    if( NULL != pxNewNode )
                    {
                        pxNewNode->pxCallback = pxNewCallback;
                        pxNewNode->pxNext     = NULL;
                        INC_STAT_COUNTER( EVL_STATS_RECORDS );
                        pxRecord->pxFirstBinding = pxNewNode;
                        pxRecord->iNumBindings++;
                        INC_STAT_COUNTER( EVL_STATS_BINDINGS );
                        iStatus = OK;
                    }
                    else
                    {
                        INC_ERROR_COUNTER( EVL_ERRORS_BINDINGS_MALLOC );
                    }
                }
                else
                {
                    if( NULL != pxRecord->pxFirstBinding )
                    {
                        EVL_CALLBACK_NODE *pxNewNode =
                            ( EVL_CALLBACK_NODE * ) pvOSAL_MemAlloc( sizeof( EVL_CALLBACK_NODE ) );
                        if( NULL != pxNewNode )
                        {
                            pxNewNode->pxCallback = pxNewCallback;
                            pxNewNode->pxNext     = NULL;

                            EVL_CALLBACK_NODE *pxLastBinding = pxRecord->pxFirstBinding;
                            while( NULL != pxLastBinding->pxNext )
                            {
                                pxLastBinding = pxLastBinding->pxNext;
                            }
                            pxLastBinding->pxNext = pxNewNode;
                            pxRecord->iNumBindings++;
                            INC_STAT_COUNTER( EVL_STATS_BINDINGS );
                            iStatus = OK;
                        }
                        else
                        {
                            INC_ERROR_COUNTER( EVL_ERRORS_BINDINGS_MALLOC );
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER( EVL_ERRORS_NO_BINDINGS );
                    }
                }
                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxRecord->pxMtx ) )
                {
                    INC_STAT_COUNTER( EVL_STATS_RECORD_MUTEX_RELEASED );
                }
                else
                {
                    INC_ERROR_COUNTER( EVL_ERRORS_RECORD_MUTEX_RELEASED );
                }
            }
            else
            {
                INC_ERROR_COUNTER( EVL_ERRORS_RECORD_MUTEX_GRABBED );
            }
        }
        else
        {
            INC_ERROR_COUNTER( EVL_ERRORS_BINDINGS );
        }
    }
    else
    {
        INC_ERROR_COUNTER( EVL_ERRORS_VALIDATION );
    }

    return iStatus;
}

/**
 * @brief   Raise an event to each bound-in callback
 */
int iEVL_RaiseEvent( EVL_RECORD *pxRecord, EVL_SIGNAL *pxSignal )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pxRecord ) &&
        ( NULL != pxSignal ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pxLogMtx, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( EVL_STATS_LOG_MUTEX_GRABBED );

            pxThis->pulLogTimes[ pxThis->iLogIdx ] = ulOSAL_GetUptimeMs();
            pvOSAL_MemCpy( &pxThis->pxEvlLog[ pxThis->iLogIdx++ ], pxSignal, sizeof( EVL_SIGNAL ) );

            if( EVL_LOG_LEN <= pxThis->iLogIdx )
            {
                pxThis->iLogIdx = 0;
            }

            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pxLogMtx ) )
            {
                INC_STAT_COUNTER( EVL_STATS_LOG_MUTEX_RELEASED );
                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxRecord->pxMtx, OSAL_TIMEOUT_WAIT_FOREVER ) )
                {
                    INC_STAT_COUNTER( EVL_STATS_RECORD_MUTEX_GRABBED );

                    EVL_CALLBACK_NODE *pxCurrentNode = pxRecord->pxFirstBinding;
                    while( NULL != pxCurrentNode )
                    {
                        INC_STAT_COUNTER( EVL_STATS_SIGNALS );
                        if( OK != pxCurrentNode->pxCallback( pxSignal ) )
                        {
                            INC_ERROR_COUNTER( EVL_ERRORS_CALLBACKS );
                            iStatus = ERROR;
                        }
                        pxCurrentNode = pxCurrentNode->pxNext;
                    }
                    if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxRecord->pxMtx ) )
                    {
                        INC_STAT_COUNTER( EVL_STATS_RECORD_MUTEX_RELEASED );
                        iStatus = OK;

                        if( TRUE == iEvlVerbosity )
                        {
                            PLL_INF( EVL_NAME,
                                     "EVL Signal raised: Module [ 0x%02X ], Type [ 0x%02X ], Instance [ 0x%02X ], Additional data [ 0x%02X ]\r\n",
                                     pxSignal->ucModule,
                                     pxSignal->ucEventType,
                                     pxSignal->ucInstance,
                                     pxSignal->ucAdditionalData );
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER( EVL_ERRORS_RECORD_MUTEX_RELEASED );
                    }
                }
                else
                {
                    INC_ERROR_COUNTER( EVL_ERRORS_RECORD_MUTEX_GRABBED );
                }
            }
            else
            {
                INC_ERROR_COUNTER( EVL_ERRORS_LOG_MUTEX_RELEASED );
            }
        }
        else
        {
            INC_ERROR_COUNTER( EVL_ERRORS_LOG_MUTEX_GRABBED );
        }
    }
    else
    {
        INC_ERROR_COUNTER( EVL_ERRORS_VALIDATION );
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iEVL_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( EVL_NAME,  "============================================================\n\r" );
        PLL_INF( EVL_NAME,  "EVL Statistics:\n\r" );
        for( i = 0; i < EVL_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( EVL_NAME,  "------------------------------------------------------------\n\r" );
        PLL_INF( EVL_NAME,  "EVL Errors:\n\r" );
        for( i = 0; i < EVL_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( EVL_NAME,  "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( EVL_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iEVL_ClearStatistics( void )
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
        INC_ERROR_COUNTER( EVL_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Retrieve the EVL log
 */
int iEVL_PrintLog( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) )
    {
        int i = 0, iRow = EVL_LOG_LEN;

        PLL_INF( EVL_NAME,  "EVL log:\r\n" );
        PLL_INF( EVL_NAME,  "============================================================\r\n" );

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pxLogMtx, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( EVL_STATS_LOG_MUTEX_GRABBED );

            for( i = pxThis->iLogIdx; i < EVL_LOG_LEN; i++ )
            {
                PLL_INF( EVL_NAME,
                         "%08d::%04d -Module: 0x%02X | Event: 0x%02X | Instance: 0x%02X\r\n",
                         pxThis->pulLogTimes[ i ],
                         iRow--,
                         pxThis->pxEvlLog[ i ].ucModule,
                         pxThis->pxEvlLog[ i ].ucEventType,
                         pxThis->pxEvlLog[ i ].ucInstance );
            }
            for( i = 0; i < pxThis->iLogIdx; i++ )
            {
                PLL_INF( EVL_NAME,
                         "%08d::%04d - Module: 0x%02X | Event: 0x%02X | Instance: 0x%02X\r\n",
                         pxThis->pulLogTimes[ i ],
                         iRow--,
                         pxThis->pxEvlLog[ i ].ucModule,
                         pxThis->pxEvlLog[ i ].ucEventType,
                         pxThis->pxEvlLog[ i ].ucInstance );
            }

            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pxLogMtx ) )
            {
                INC_STAT_COUNTER( EVL_STATS_LOG_MUTEX_RELEASED );
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( EVL_ERRORS_LOG_MUTEX_RELEASED );
            }
        }
        else
        {
            INC_ERROR_COUNTER( EVL_ERRORS_LOG_MUTEX_GRABBED );
        }

        PLL_INF( EVL_NAME,  "============================================================\r\n" );

        INC_STAT_COUNTER( EVL_STATS_LOG_RETRIEVED );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( EVL_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Enable verbosity of EVL, pass parameter TRUE or FALSE
 */
void vEVL_SetVerbosity( int iVerbosity )
{
    iEvlVerbosity = iVerbosity;
}
