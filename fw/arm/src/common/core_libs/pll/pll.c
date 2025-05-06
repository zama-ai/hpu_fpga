/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implementation of the Printing and Logging Library (PLL)
 *
 * @file pll.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

/* Standard includes */
#include <string.h>

#include "standard.h"
#include "util.h"
#include "osal.h"

#include "pll.h"

#include "profile_print.h"
#include "profile_hal.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL         ( 0xBABECAFE )
#define LOWER_FIREWALL         ( 0xDEADFACE )

#define PLL_NAME               "PLL"

#define PLL_SLEEP_INTERVAL_MS  ( 1000 )


/* Stat & Error definitions */
#define PLL_STATS( DO )                         \
    DO( PLL_STATS_INIT_OVERALL_COMPLETE )       \
    DO( PLL_STATS_CREATE_MUTEX )                \
    DO( PLL_STATS_CREATE_SEMAPHORE )            \
    DO( PLL_STATS_TAKE_MUTEX )                  \
    DO( PLL_STATS_RELEASE_MUTEX )               \
    DO( PLL_STATS_PEND_SEMAPHORE )              \
    DO( PLL_STATS_POST_SEMAPHORE )              \
    DO( PLL_STATS_THREAD_SAFE_PRINT_COUNT )     \
    DO( PLL_STATS_NON_THREAD_SAFE_PRINT_COUNT ) \
    DO( PLL_STATS_LEVEL_CHANGE )                \
    DO( PLL_STATS_LEVEL_RETRIEVAL )             \
    DO( PLL_STATS_LOG_COLLECT_SUCCESS )         \
    DO( PLL_STATS_MALLOC )                      \
    DO( PLL_STATS_FREE )                        \
    DO( PLL_STATS_MAX )

#define PLL_ERRORS( DO )                          \
    DO( PLL_ERRORS_INIT_TASK_CREATE_FAILED )      \
    DO( PLL_ERRORS_INIT_MUTEX_CREATE_FAILED )     \
    DO( PLL_ERRORS_INIT_SEMAPHORE_CREATE_FAILED ) \
    DO( PLL_ERRORS_MUTEX_RELEASE_FAILED )         \
    DO( PLL_ERRORS_MUTEX_TAKE_FAILED )            \
    DO( PLL_ERRORS_PEND_SEMAPHORE )               \
    DO( PLL_ERRORS_POST_SEMAPHORE )               \
    DO( PLL_ERRORS_VALIDATION_FAILED )            \
    DO( PLL_ERRORS_LOAD_PT_FAILED )               \
    DO( PLL_ERRORS_STORE_PT_FAILED )              \
    DO( PLL_ERRORS_LOG_COLLECT_FAILED )           \
    DO( PLL_ERRORS_MALLOC_FAILED )                \
    DO( PLL_ERRORS_MAX )


#define PRINT_STAT_COUNTER( x )     PLL_INF( PLL_NAME, "%50s . . . . %d\r\n",          \
                                             PLL_STATS_STR[ x ],                       \
                                             pxThis->ulStats[ x ] )
#define PRINT_ERROR_COUNTER( x )    PLL_INF( PLL_NAME, "%50s . . . . %d\r\n",          \
                                             PLL_ERRORS_STR[ x ],                      \
                                             pxThis->ulErrors[ x ] )

#define INC_STAT_COUNTER( x )       { if( x < PLL_STATS_MAX )pxThis->ulStats[ x ]++; }
#define INC_ERROR_COUNTER( x )      { if( x < PLL_ERRORS_MAX )pxThis->ulErrors[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    PLL_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( PLL_STATS, PLL_STATS, PLL_STATS_STR )

/**
 * @enum    PLL_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( PLL_ERRORS, PLL_ERRORS, PLL_ERRORS_STR )


/******************************************************************************/
/* Structs/Unions                                                             */
/******************************************************************************/

/**
 * @struct  PLL_PRIVATE_DATA
 * @brief   Locally held private data
 */
typedef struct PLL_PRIVATE_DATA
{
    uint32_t            ulUpperFirewall;

    int                 iIsInitialised;

    PLL_OUTPUT_LEVEL    xOutputLevel;
    PLL_OUTPUT_LEVEL    xLoggingLevel;

    char                pcBootLogs[ PLL_LOG_MAX_RECS ][ PLL_LOG_ENTRY_SIZE ];
    int                 iBootLogIndex;
    int                 iIsLogReady;

    void                *pvMtxHdl;
    void                *pvSemHdl;

    uint32_t            ulStats[ PLL_STATS_MAX ];
    uint32_t            ulErrors[ PLL_ERRORS_MAX ];

    uint32_t            ulLowerFirewall;

} PLL_PRIVATE_DATA;


/******************************************************************************/
/* Local data                                                                 */
/******************************************************************************/

static PLL_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL, /* ulUpperFirewall   */

    FALSE,          /* iIsInitialised    */

    0,              /* xOutputLevel      */
    0,              /* xLoggingLevel     */

    { { 0 } },      /* pcBootLogs        */
    0,              /* iBootLogIndex     */
    FALSE,          /* iIsLogReady       */


    NULL,           /* pvMtxHdl          */
    NULL,           /* pvSemHdl          */

    { 0 },          /* ulStats           */
    { 0 },          /* ulErrors          */

    LOWER_FIREWALL
};

static PLL_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Local Function definitions                                                 */
/******************************************************************************/

/**
 * @brief         Logs messages into shared memory.
 *
 * @param pcBuf   Buffer to store into shared memory.
 *
 * @return        OK if message logged successfully.
 *                ERROR log message failed.
 */
static int iLogCollect( char *pcBuf );


/******************************************************************************/
/* Public function implementations                                            */
/******************************************************************************/

/**
 * @brief   Initialise the PLL
 */
int iPLL_Initialise( PLL_OUTPUT_LEVEL xOutputLevel, PLL_OUTPUT_LEVEL xLoggingLevel )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iIsInitialised ) )
    {
        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvMtxHdl, "PLL_Mutex" ) )
        {
            PLL_ERR( PLL_NAME, "Error initialising mutex\r\n" );
            INC_ERROR_COUNTER( PLL_ERRORS_INIT_MUTEX_CREATE_FAILED )
        }
        else if( OSAL_ERRORS_NONE != iOSAL_Semaphore_Create( &pxThis->pvSemHdl,
                                                             1,
                                                             1,
                                                             "PLL_Semaphore" ) )
        {
            PLL_ERR( PLL_NAME, "Error initialising semaphore\r\n" );
            INC_ERROR_COUNTER( PLL_ERRORS_INIT_SEMAPHORE_CREATE_FAILED )
        }
        else
        {
            INC_STAT_COUNTER( PLL_STATS_CREATE_MUTEX )
            INC_STAT_COUNTER( PLL_STATS_CREATE_SEMAPHORE )

            pxThis->xOutputLevel = xOutputLevel;
            pxThis->xLoggingLevel = xLoggingLevel;

            INC_STAT_COUNTER( PLL_STATS_INIT_OVERALL_COMPLETE )
            pxThis->iIsInitialised = TRUE;

            iStatus = OK;
        }
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Sets PLL output verbosity level
 */
int iPLL_SetOutputLevel( PLL_OUTPUT_LEVEL xOutputLevel )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( MAX_PLL_OUTPUT_LEVEL > xOutputLevel ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvMtxHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( PLL_STATS_TAKE_MUTEX );

            pxThis->xOutputLevel = xOutputLevel;

            INC_STAT_COUNTER( PLL_STATS_LEVEL_CHANGE );

            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvMtxHdl ) )
            {
                INC_STAT_COUNTER( PLL_STATS_RELEASE_MUTEX );
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( PLL_ERRORS_MUTEX_RELEASE_FAILED );
            }
        }
        else
        {
            INC_ERROR_COUNTER( PLL_ERRORS_MUTEX_TAKE_FAILED );
        }
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED );
    }

    return iStatus;
}

/**
 * @brief   Gets current PLL output verbosity level
 */
int iPLL_GetOutputLevel( PLL_OUTPUT_LEVEL *pxOutputLevel )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pxOutputLevel ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvMtxHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( PLL_STATS_TAKE_MUTEX );

            *pxOutputLevel = pxThis->xOutputLevel;

            INC_STAT_COUNTER( PLL_STATS_LEVEL_RETRIEVAL );

            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvMtxHdl ) )
            {
                INC_STAT_COUNTER( PLL_STATS_RELEASE_MUTEX );
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( PLL_ERRORS_MUTEX_RELEASE_FAILED );
            }
        }
        else
        {
            INC_ERROR_COUNTER( PLL_ERRORS_MUTEX_TAKE_FAILED );
        }
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED );
    }

    return iStatus;
}

/**
 * @brief   Sets PLL logging verbosity level
 */
int iPLL_SetLoggingLevel( PLL_OUTPUT_LEVEL xLoggingLevel )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( MAX_PLL_OUTPUT_LEVEL > xLoggingLevel ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvMtxHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( PLL_STATS_TAKE_MUTEX );

            pxThis->xLoggingLevel = xLoggingLevel;

            INC_STAT_COUNTER( PLL_STATS_LEVEL_CHANGE );

            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvMtxHdl ) )
            {
                INC_STAT_COUNTER( PLL_STATS_RELEASE_MUTEX );
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( PLL_ERRORS_MUTEX_RELEASE_FAILED );
            }
        }
        else
        {
            INC_ERROR_COUNTER( PLL_ERRORS_MUTEX_TAKE_FAILED );
        }
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED );
    }

    return iStatus;
}

/**
 * @brief   Gets current PLL logging verbosity level
 */
int iPLL_GetLoggingLevel( PLL_OUTPUT_LEVEL *pxLoggingLevel )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pxLoggingLevel ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvMtxHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( PLL_STATS_TAKE_MUTEX );

            *pxLoggingLevel = pxThis->xLoggingLevel;

            INC_STAT_COUNTER( PLL_STATS_LEVEL_RETRIEVAL );

            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvMtxHdl ) )
            {
                INC_STAT_COUNTER( PLL_STATS_RELEASE_MUTEX );
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( PLL_ERRORS_MUTEX_RELEASE_FAILED );
            }
        }
        else
        {
            INC_ERROR_COUNTER( PLL_ERRORS_MUTEX_TAKE_FAILED );
        }
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED );
    }

    return iStatus;
}

/**
 * @brief   Function for task/thread safe prints with verbosity
 */
void vPLL_Output( PLL_OUTPUT_LEVEL xOutputLevel, const char *pcFormat, ... )
{
    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcFormat ) &&
        ( PRINT_BUFFER_SIZE >= strlen( pcFormat ) ) )
    {
        char pcBuffer[ PRINT_BUFFER_SIZE ] = { 0 };
        va_list xArgs = { 0 };

        va_start( xArgs, pcFormat );
        vsnprintf( pcBuffer, PRINT_BUFFER_SIZE, pcFormat, xArgs );

        if( OSAL_ERRORS_NONE == iOSAL_Semaphore_Pend( pxThis->pvSemHdl, OSAL_TIMEOUT_TASK_WAIT_MS ) )
        {
            INC_STAT_COUNTER( PLL_STATS_PEND_SEMAPHORE );

            /* Check output level */
            if( pxThis->xOutputLevel >= xOutputLevel )
            {
                PRINT( "%s", pcBuffer );
                INC_STAT_COUNTER( PLL_STATS_THREAD_SAFE_PRINT_COUNT );
            }

            /* Check logging level */
            if( pxThis->xLoggingLevel >= xOutputLevel )
            {
                if( OK == iLogCollect( pcBuffer ) )
                {
                    INC_STAT_COUNTER( PLL_STATS_LOG_COLLECT_SUCCESS )
                }
                else
                {
                    INC_ERROR_COUNTER( PLL_ERRORS_LOG_COLLECT_FAILED )
                }
            }

            if( OSAL_ERRORS_NONE == iOSAL_Semaphore_Post( pxThis->pvSemHdl ) )
            {
                INC_STAT_COUNTER( PLL_STATS_POST_SEMAPHORE );
            }
            else
            {
                INC_ERROR_COUNTER( PLL_ERRORS_POST_SEMAPHORE );
            }
        }
        else
        {
            /* not thread safe - semaphore timeout */
            PRINT( "%s", pcBuffer );

            INC_STAT_COUNTER( PLL_STATS_NON_THREAD_SAFE_PRINT_COUNT );
        }

        va_end( xArgs );
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED );
    }
}

/**
 * @brief   Function for task/thread safe prints without verbosity checking
 */
void vPLL_Printf( const char *pcFormat, ... )
{
    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pcFormat ) &&
        ( PRINT_BUFFER_SIZE >= strlen( pcFormat ) ) )
    {
        char pcBuffer[ PRINT_BUFFER_SIZE ] = { 0 };
        va_list xArgs = { 0 };

        va_start( xArgs, pcFormat );
        vsnprintf( pcBuffer, PRINT_BUFFER_SIZE, pcFormat, xArgs );

        if( TRUE == pxThis->iIsInitialised )
        {
            if( OSAL_ERRORS_NONE == iOSAL_Semaphore_Pend( pxThis->pvSemHdl, OSAL_TIMEOUT_TASK_WAIT_MS ) )
            {
                INC_STAT_COUNTER( PLL_STATS_PEND_SEMAPHORE );

                PRINT( "%s", pcBuffer );

                INC_STAT_COUNTER( PLL_STATS_THREAD_SAFE_PRINT_COUNT );

                if( OSAL_ERRORS_NONE == iOSAL_Semaphore_Post( pxThis->pvSemHdl ) )
                {
                    INC_STAT_COUNTER( PLL_STATS_POST_SEMAPHORE );
                }
                else
                {
                    INC_ERROR_COUNTER( PLL_ERRORS_POST_SEMAPHORE );
                }
            }
            else
            {
                /* not thread safe - semaphore timeout */
                PRINT( "%s", pcBuffer );

                INC_STAT_COUNTER( PLL_STATS_NON_THREAD_SAFE_PRINT_COUNT );
            }
        }
        else
        {
            /* not thread safe - module not initialised */
            PRINT( "%s", pcBuffer );

            INC_STAT_COUNTER( PLL_STATS_NON_THREAD_SAFE_PRINT_COUNT );
        }

        va_end( xArgs );
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED );
    }
}

/**
 * @brief   Dumps logs from shared memory.
 */
int iPLL_DumpLog( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) )
    {
        HAL_PARTITION_TABLE_LOG_MSG xLogMsg = { 0 };
        uintptr_t ulLogMsgSrcAddr = HAL_RPU_SHARED_MEMORY_BASE_ADDR + offsetof( HAL_PARTITION_TABLE, xLogMsg );

        if( NULL != pvOSAL_MemCpy( &xLogMsg, ( void * )ulLogMsgSrcAddr, sizeof( xLogMsg ) ) )
        {
            vPLL_Printf( "\r\n======================================================================\r\n" );
            vPLL_Printf( "Dumping log from shared memory...\r\n" );
            vPLL_Printf( "======================================================================\r\n\r\n" );

            HAL_FLUSH_CACHE_DATA( HAL_RPU_SHARED_MEMORY_BASE_ADDR, sizeof( HAL_PARTITION_TABLE ) );

            int i = 0;
            for( i = 0; i < PLL_LOG_MAX_RECS; i++ )
            {
                PLL_LOG_MSG xMsg = { 0 };

                /* Calculate the address of the log message for the current index */
                uintptr_t ulLogMsgAddr = ( uintptr_t )( HAL_RPU_SHARED_MEMORY_BASE_ADDR + xLogMsg.ulLogMsgBufferOff ) + ( i * sizeof( PLL_LOG_MSG ) );

                pvOSAL_MemCpy( &xMsg, ( uint32_t* )ulLogMsgAddr, sizeof( PLL_LOG_MSG ) );

                if( 0 != strlen( xMsg.pcBuff ) )
                {
                    vPLL_Printf( "%s\r\n", xMsg.pcBuff );
                }
            }

            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER( PLL_ERRORS_LOAD_PT_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Clears shared memory log buffer.
 */
int iPLL_ClearLog( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) )
    {
        HAL_PARTITION_TABLE_LOG_MSG xLogMsg = { 0 };
        uintptr_t ulLogMsgSrcAddr = HAL_RPU_SHARED_MEMORY_BASE_ADDR + offsetof( HAL_PARTITION_TABLE, xLogMsg );

        /* Load partition table */
        if( NULL != pvOSAL_MemCpy( &xLogMsg, ( void * )ulLogMsgSrcAddr, sizeof( xLogMsg ) ) )
        {
            uintptr_t ulLogBufStartAddr = HAL_RPU_SHARED_MEMORY_BASE_ADDR + xLogMsg.ulLogMsgBufferOff;

            if( PLL_LOG_BUF_LEN >= xLogMsg.ulLogMsgBufferLen )
            {
                pvOSAL_MemSet( ( uint8_t* )ulLogBufStartAddr, 0, xLogMsg.ulLogMsgBufferLen );
                HAL_FLUSH_CACHE_DATA( ulLogBufStartAddr, xLogMsg.ulLogMsgBufferLen );

                iStatus = OK;
            }
        }
        else
        {
            INC_ERROR_COUNTER( PLL_ERRORS_LOAD_PT_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief    Reads and dumps the FSBL (First-Stage Bootloader) log
 */
int iPLL_DumpFsblLog( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) )
    {
        char *pcFsblLogBuffer = NULL;

        PLL_LOG( PLL_NAME, "FSBL boot logs:\r\n" );

        pcFsblLogBuffer = pvOSAL_MemAlloc( HAL_FSBL_LOG_SIZE );
        if( NULL != pcFsblLogBuffer )
        {
            char *pcCurrentMessage = NULL;
            char *pcNextMessage = NULL;

            INC_STAT_COUNTER( PLL_STATS_MALLOC )

            pvOSAL_MemCpy( pcFsblLogBuffer, ( uint32_t* )HAL_FSBL_LOG_ADDRESS, HAL_FSBL_LOG_SIZE );

            /* We keep track of two messages to avoid printing any uninitialised data at the end */
            pcCurrentMessage = strtok( pcFsblLogBuffer, "\r\n" );
            pcNextMessage = strtok( NULL, "\r\n" );

            while( NULL != pcNextMessage )
            {
                PLL_LOG( PLL_NAME, "%s\r\n", pcCurrentMessage );

                pcCurrentMessage = pcNextMessage;
                pcNextMessage = strtok( NULL, "\r\n" );
            }

            vOSAL_MemFree( ( void** )&pcFsblLogBuffer );
            INC_STAT_COUNTER( PLL_STATS_FREE )

            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER( PLL_ERRORS_MALLOC_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief    Sends collected AMC boot records to the log once communciation is available
 */
int iPLL_SendBootRecords( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        char *pcFsblLogBuffer = NULL;
        uintptr_t ulLogMsgAddr = HAL_RPU_SHARED_MEMORY_BASE_ADDR + offsetof( HAL_PARTITION_TABLE, xLogMsg );

        HAL_IO_WRITE32( 0, ulLogMsgAddr );

        /* Enable logging comms */
        pxThis->iIsLogReady = TRUE;

        /* FSBL records */
        pcFsblLogBuffer = pvOSAL_MemAlloc( HAL_FSBL_LOG_SIZE );
        if( NULL != pcFsblLogBuffer )
        {
            char *pcCurrentMessage = NULL;
            char *pcNextMessage = NULL;

            INC_STAT_COUNTER( PLL_STATS_MALLOC )

            pvOSAL_MemCpy( pcFsblLogBuffer, ( uint32_t* )HAL_FSBL_LOG_ADDRESS, HAL_FSBL_LOG_SIZE );

            pcCurrentMessage = strtok( pcFsblLogBuffer, "\r\n" );
            pcNextMessage    = strtok( NULL, "\r\n" );
            
            while( NULL != pcNextMessage )
            {
                iLogCollect( pcCurrentMessage );

                pcCurrentMessage = pcNextMessage;
                pcNextMessage = strtok( NULL, "\r\n" );
            }

            vOSAL_MemFree( ( void** )&pcFsblLogBuffer );
            INC_STAT_COUNTER( PLL_STATS_FREE )
        }
                
        /* Sleep is needed to allow the first chunk to be read fully before we overwrite the ring buffer */
        iOSAL_Task_SleepMs( PLL_SLEEP_INTERVAL_MS );

        /* AMC boot records */
        for( i = 0; i < PLL_LOG_MAX_RECS; i++ )
        {
            if( '\0' != pxThis->pcBootLogs[ i ][ 0 ] )
            {                
                iLogCollect( pxThis->pcBootLogs[ i ] );
            }
        }

        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iPLL_PrintStatistics( void )
{
     int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( PLL_NAME, "============================================================\n\r" );
        PLL_INF( PLL_NAME, "PLL Library Statistics:\n\r" );
        for( i = 0; i < PLL_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( PLL_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( PLL_NAME, "PLL Library Errors:\n\r" );
        for( i = 0; i < PLL_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( PLL_NAME, "============================================================\n\r" );

        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iPLL_ClearStatistics( void )
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
        INC_ERROR_COUNTER( PLL_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/******************************************************************************/
/* Local Function implementations                                             */
/******************************************************************************/

/**
 * @brief Collects and stores logs in shared memory.
 */
static int iLogCollect( char *pcBuf )
{
    int iStatus = ERROR;

    HAL_PARTITION_TABLE_LOG_MSG xLogMsg = { 0 };
    uintptr_t ulLogMsgAddr = HAL_RPU_SHARED_MEMORY_BASE_ADDR + offsetof( HAL_PARTITION_TABLE, xLogMsg );

    /* Logging is enabled, we can send logs directly to shared memory */
    if( TRUE == pxThis->iIsLogReady )
    {
        /* Load partition table */
        if( NULL != pvOSAL_MemCpy( &xLogMsg, ( void * )ulLogMsgAddr, sizeof( xLogMsg ) ) )
        {
            uint32_t ulMsgBufAddr = HAL_RPU_SHARED_MEMORY_BASE_ADDR + xLogMsg.ulLogMsgBufferOff;
            char pcTempBuf[PLL_LOG_ENTRY_SIZE] = { 0 };
            uint32_t ulLogIdx = 0;
            PLL_LOG_MSG xLog = { 0 };

            /* Read current index */
            ulLogIdx = HAL_IO_READ32( ulLogMsgAddr );

            pcOSAL_StrNCpy( pcTempBuf, pcBuf, sizeof( pcTempBuf ) );
            pcTempBuf[ strcspn( pcTempBuf, "\r\n" ) ] = 0;

            pcOSAL_StrNCpy( xLog.pcBuff, pcTempBuf, sizeof( xLog.pcBuff ) );

            /* Copy log into shared memory */
            if( NULL != pvOSAL_MemCpy( ( void * )( ulMsgBufAddr + ( sizeof( xLog ) * ulLogIdx ) ), &xLog, sizeof( xLog ) ) )
            {
                /* Flush updated chunk */
                HAL_FLUSH_CACHE_DATA( ulMsgBufAddr + ( sizeof( xLog ) * ulLogIdx ), sizeof( xLog ) );

                ulLogIdx = ( ulLogIdx + 1 ) % PLL_LOG_MAX_RECS;

                /* Update new log index into shared memory */
                HAL_IO_WRITE32( ulLogIdx, ulLogMsgAddr );

                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( PLL_ERRORS_STORE_PT_FAILED )
            }
        }
        else
        {
            INC_ERROR_COUNTER( PLL_ERRORS_LOAD_PT_FAILED )
        }
    }
    /* Logging is disabled - we store logs locally first and send them over when the feature is available */
    else
    {
        char pcTempBuf[ PLL_LOG_ENTRY_SIZE ] = { 0 };

        /* Trim new lines */
        pcOSAL_StrNCpy( pcTempBuf, pcBuf, sizeof( pcTempBuf ) );
        pcTempBuf[ strcspn( pcTempBuf, "\r\n" ) ] = 0;

        /* Copy buffer into local array */
        pxThis->iBootLogIndex = ( pxThis->iBootLogIndex + 1 ) % PLL_LOG_MAX_RECS;
        pcOSAL_StrNCpy( pxThis->pcBootLogs[ pxThis->iBootLogIndex ], pcTempBuf, sizeof( pxThis->pcBootLogs[ pxThis->iBootLogIndex ] ) );

        iStatus = OK;
    }

    return iStatus;
}
