/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the FW IF GCQ abstraction for AMC.
 *
 * @file fw_if_gcq_amc.c
 *
 */

/*****************************************************************************/
/* Includes                                                                  */
/*****************************************************************************/

/* FreeRTOS includes */
#include <assert.h>
#include "FreeRTOS.h"

#include "util.h"
#include "osal.h"
#include "fw_if_gcq.h"
#include "gcq.h"
#include "profile_hal.h"
#include "profile_fal.h"


/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/

#define FW_IF_GCQ_NAME                  "FW_IF_GCQ"

#define GCQ_UPPER_FIREWALL              ( 0xBEEFCAFE )
#define GCQ_LOWER_FIREWALL              ( 0xDEADFACE )

#define CHECK_DRIVER                    ( FW_IF_FALSE == pxThis->iInitialised )
#define CHECK_FIREWALLS( f )            ( ( f->upperFirewall != GCQ_UPPER_FIREWALL ) &&\
                                          ( f->lowerFirewall != GCQ_LOWER_FIREWALL ) )
#define CHECK_NULL( f )                 ( NULL == f )
#define CHECK_NOT_NULL( f )             ( NULL != f )
#define CHECK_CFG( f )                  ( NULL == ( f )->cfg )

#define CHECK_PROFILE( f )              ( NULL == ( f )->pvProfile )

#define CHECK_INVALID_STATE( f )        ( ( FW_IF_GCQ_STATE_OPENED != ( f )->xState ) &&\
                                          ( FW_IF_GCQ_STATE_ATTACHED != ( f )->xState ) )

/* Stat & Error definitions */
#define FW_IF_GCQ_STATS( DO )                          \
    DO( FW_IF_GCQ_STATS_INIT_OVERALL_COMPLETE_COUNT )  \
    DO( FW_IF_GCQ_STATS_OPEN_COUNT )                   \
    DO( FW_IF_GCQ_STATS_ATTACHED_COUNT )               \
    DO( FW_IF_GCQ_STATS_CLOSE_COUNT )                  \
    DO( FW_IF_GCQ_STATS_BIND_CALLBACK_CALLED_COUNT )   \
    DO( FW_IF_GCQ_STATS_INSTANCE_CREATE_COUNT )        \
    DO( FW_IF_GCQ_STATS_READ_COUNT )                   \
    DO( FW_IF_GCQ_STATS_WRITE_COUNT )                  \
    DO( FW_IF_GCQ_STATS_MAX )

#define FW_IF_GCQ_ERRORS( DO )                         \
    DO( FW_IF_ERRORS_PARAMS_COUNT )                    \
    DO( FW_IF_ERRORS_DRIVER_IN_USE_COUNT )             \
    DO( FW_IF_ERRORS_DRIVER_NOT_INITIALISED_COUNT )    \
    DO( FW_IF_ERRORS_INVALID_CFG_COUNT )               \
    DO( FW_IF_ERRORS_INVALID_HANDLE_COUNT )            \
    DO( FW_IF_GCQ_ERRORS_NO_FREE_PROFILES_COUNT )      \
    DO( FW_IF_GCQ_ERRORS_VALIDATION_FAILED_COUNT )     \
    DO( FW_IF_GCQ_ERRORS_INVALID_PROFILE_COUNT )       \
    DO( FW_IF_GCQ_ERRORS_NOT_SUPPORTED_COUNT )         \
    DO( FW_IF_GCQ_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )             PLL_INF( FW_IF_GCQ_NAME, "%50s . . . . %d\r\n",          \
                                                     FW_IF_GCQ_STATS_STR[ x ],                       \
                                                     pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x )            PLL_INF( FW_IF_GCQ_NAME, "%50s . . . . %d\r\n",          \
                                                     FW_IF_GCQ_ERRORS_STR[ x ],                      \
                                                     pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )               { if( x < FW_IF_GCQ_STATS_MAX )pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x )              { if( x < FW_IF_GCQ_ERRORS_MAX )pxThis->pulErrorCounters[ x ]++; }


/*****************************************************************************/
/* Enums                                                                     */
/*****************************************************************************/

/**
 * @struct  FW_IF_GCQ_STATE
 * 
 * @brief   The internal GCQ IF state
 */
typedef enum FW_IF_GCQ_STATE
{
    FW_IF_GCQ_STATE_CLOSED = 0,
    FW_IF_GCQ_STATE_INIT,
    FW_IF_GCQ_STATE_OPENED,
    FW_IF_GCQ_STATE_ATTACHED,

    FW_IF_GCQ_STATE_MAX

} FW_IF_GCQ_STATE;

/**
 * @enum    FW_IF_GCQ_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( FW_IF_GCQ_STATS, FW_IF_GCQ_STATS, FW_IF_GCQ_STATS_STR )

/**
 * @enum    FW_IF_GCQ_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( FW_IF_GCQ_ERRORS, FW_IF_GCQ_ERRORS, FW_IF_GCQ_ERRORS_STR )


/*****************************************************************************/
/* Structs                                                                   */
/*****************************************************************************/

/**
 * @struct  FW_IF_GCQ_PROFILE_TYPE
 * @brief   The definition of a profile, used to store internal
 *          state & ptr to driver instance
 */
typedef struct FW_IF_GCQ_PROFILE_TYPE
{
    uint32_t ulIOHandle;
    FW_IF_GCQ_STATE xState;
    struct GCQ_INSTANCE_TYPE *pxGCQInstance;

} FW_IF_GCQ_PROFILE_TYPE;

/**
 * @struct  FW_IF_GCQ_PRIVATE_DATA
 * @brief   Structure to hold this modules private data
 */
typedef struct FW_IF_GCQ_PRIVATE_DATA
{
    uint32_t                ulUpperFirewall;
 
    FW_IF_GCQ_INIT_CFG      xLocalCfg;
    GCQ_IO_ACCESS_TYPE      xGcqIoAccess;
    int                     iInitialised;
    FW_IF_GCQ_PROFILE_TYPE  xGcqProfile[ GCQ_MAX_INSTANCES ];
    uint32_t                ulProfilesAllocated;

    uint32_t                pulStatCounters[ FW_IF_GCQ_STATS_MAX ];
    uint32_t                pulErrorCounters[ FW_IF_GCQ_ERRORS_MAX ];

    uint32_t                ulLowerFirewall;

} FW_IF_GCQ_PRIVATE_DATA;


/*****************************************************************************/
/* Local Variables                                                           */
/*****************************************************************************/

static FW_IF_GCQ_PRIVATE_DATA xLocalData =
{
    GCQ_UPPER_FIREWALL,     /* ulUpperFirewall */   

    { 0 },                  /* xLocalCfg */
    { 0 },                  /* xGcqIoAccess */
    FALSE,                  /* iInitialised */
    { { 0 } },              /* xGcqProfile */
    0,                      /* ulProfilesAllocated */

    { 0 },                  /* pulStatCounters */
    { 0 },                  /* pulErrorCounters */

    GCQ_LOWER_FIREWALL      /* ulLowerFirewall */
};
static FW_IF_GCQ_PRIVATE_DATA *pxThis = &xLocalData;


/*****************************************************************************/
/* Local Functions                                                           */
/*****************************************************************************/

/**
 *
 * @brief   Handle memory & register writes in AMC
 *
 * @param   ullDestAddr is the destination address
 * @param   ulValue is the 32-bit value to write
 *
 * @return  N/A
 * 
 *
 */
static inline void prvvWriteMemReg32( uint64_t ullDestAddr, uint32_t ulValue )
{
    /* PLL_DBG( FW_IF_GCQ_NAME, "W [0x%llx: 0x%lx]\r\n", ullDestAddr, ulValue ); */
    HAL_IO_WRITE32( ulValue, ullDestAddr );
}

/**
 *
 * @brief   Handle memory & register reads in AMC
 *
 * @param   ullSrcAddr is the source address
 *
 * @return  the 32-bit value read
 * 
 *
 */
static inline uint32_t prvulReadMemReg32( uint64_t ullSrcAddr )
{
    uint32_t ulValue = HAL_IO_READ32( ullSrcAddr );
    /* PLL_DBG( FW_IF_GCQ_NAME, "R [0x%llx: 0x%lx]\r\n", ullSrcAddr, ulValue ); */
    return ( ulValue );
}

/**
 *
 * @brief   Map interface error return code
 *
 * @param   error is the return code returned by the gcq driver
 *
 * @return  the mapped interface return code
 * 
 *
 */
static FW_IF_GCQ_ERRORS_TYPE prvxMapIFDriverReturnCode( GCQ_ERRORS_TYPE xError )
{
    FW_IF_GCQ_ERRORS_TYPE xMappedErr = MAX_FW_IF_GCQ_ERROR;

    switch( xError )
    {
        case GCQ_ERRORS_NONE:                       xMappedErr = FW_IF_ERRORS_NONE; break;
        case GCQ_ERRORS_DRIVER_NOT_INITIALISED:     xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_NOT_INITIALISED; break;
        case GCQ_ERRORS_NO_FREE_INSTANCES:          xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_NO_FREE_INSTANCES; break;
        case GCQ_ERRORS_INVALID_INSTANCE:           xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_INVALID_INSTANCE; break;
        case GCQ_ERRORS_INVALID_ARG:                xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_INVALID_ARG; break;
        case GCQ_ERRORS_INVALID_SLOT_SIZE:          xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_INVALID_SLOT_SIZE; break;
        case GCQ_ERRORS_INVALID_VERSION:            xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_INVALID_VERSION; break;
        case GCQ_ERRORS_INVALID_NUM_SLOTS:          xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_INVALID_NUM_SLOTS; break;
        case GCQ_ERRORS_CONSUMER_NOT_ATTACHED:      xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_CONSUMER_NOT_ATTACHED; break;
        case GCQ_ERRORS_CONSUMER_NOT_AVAILABLE:     xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_CONSUMER_NOT_AVAILABLE; break;
        case GCQ_ERRORS_CONSUMER_NO_DATA_RECEIVED:  xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_CONSUMER_NO_DATA_RECEIVED; break;
        case GCQ_ERRORS_PRODUCER_NO_FREE_SLOTS:     xMappedErr = FW_IF_GCQ_ERRORS_DRIVER_PRODUCER_NO_FREE_SLOTS; break;
        case MAX_GCQ_ERRORS_TYPE:
        default:
            assert( 0 );
            break;
    }

    return ( xMappedErr );
}

/**
 *
 * @brief   Map interrupt mode
 *
 * @param   xInterruptMode is the interface interrupt mode
 *
 * @return  the mapped gcq driver interrupt mode
 * 
 *
 */
static GCQ_INTERRUPT_MODE_TYPE prvxMapInterruptMode( FW_IF_GCQ_INTERRUPT_MODE_TYPE xInterruptMode )
{
    GCQ_INTERRUPT_MODE_TYPE  xMappedMode = MAX_GCQ_INTERRUPT_MODE;

    switch( xInterruptMode )
    {
        case FW_IF_GCQ_INTERRUPT_MODE_NONE:                 xMappedMode = GCQ_INTERRUPT_MODE_POLLING; break;
        case FW_IF_GCQ_INTERRUPT_MODE_TAIL_POINTER_TRIGGER: xMappedMode = GCQ_INTERRUPT_MODE_TAIL_POINTER; break;
        case FW_IF_GCQ_INTERRUPT_MODE_MANUAL_TRIGGER:       xMappedMode = GCQ_INTERRUPT_MODE_INTERRUPT_REG; break;
        case MAX_FW_IF_GCQ_INTERRUPT_MODE:
        default:
            assert( 0 );
            break;
    }

    return ( xMappedMode );
}

/**
 *
 * @brief   Map consumer/producer mode
 *
 * @param   xMode is the interface mode (producer/consumer)
 *
 * @return  the mapped gcq driver interface mode
 * 
 *
 */
static GCQ_MODE_TYPE prvxMapMode( FW_IF_GCQ_MODE_TYPE xMode )
{
    GCQ_MODE_TYPE xMappedMode = MAX_GCQ_MODE_TYPE;

    switch( xMode )
    {
        case FW_IF_GCQ_MODE_PRODUCER:   xMappedMode = GCQ_MODE_TYPE_PRODUCER_MODE; break;
        case FW_IF_GCQ_MODE_CONSUMER:   xMappedMode = GCQ_MODE_TYPE_CONSUMER_MODE; break;
        case MAX_FW_IF_GCQ_MODE:
        default:
            assert( 0 );
            break;
    }

    return ( xMappedMode );
}

/**
 * @brief   Local implementation of FW_IF_open
 */
static uint32_t prvGCQOpen( void *pvFWIf )
{
    FW_IF_GCQ_ERRORS_TYPE xRet = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFWIf;
    if( CHECK_NULL( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }

    if( CHECK_CFG( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_CFG;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_CFG_COUNT );

    }

    if( CHECK_FIREWALLS( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }

    if( CHECK_DRIVER )
    {
        xRet = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
        INC_ERROR_COUNTER( FW_IF_ERRORS_DRIVER_NOT_INITIALISED_COUNT );
    }

    FW_IF_GCQ_CFG *pxCfg = ( FW_IF_GCQ_CFG* )pxThisIf->cfg;
    if( CHECK_PROFILE( pxCfg ) )
    {
        xRet = FW_IF_GCQ_ERRORS_INVALID_PROFILE;
        INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_INVALID_PROFILE_COUNT );
    }

    if( prvxMapIFDriverReturnCode( FW_IF_ERRORS_NONE ) == xRet )
    {
        GCQ_FLAGS_TYPE xFlags = 0;
        GCQ_INTERRUPT_MODE_TYPE xIntMode = prvxMapInterruptMode( pxCfg->xInterruptMode );
        GCQ_MODE_TYPE xMode = prvxMapMode( pxCfg->xMode );

        /* Initially only interrupt polling mode supported */
        if( xIntMode == GCQ_INTERRUPT_MODE_POLLING )
        {
            FW_IF_GCQ_PROFILE_TYPE *pxProfile = ( FW_IF_GCQ_PROFILE_TYPE* )pxCfg->pvProfile;
            pxProfile->pxGCQInstance = NULL;

            GCQ_ERRORS_TYPE xStatus = xGCQInit( &pxProfile->pxGCQInstance,
                                                pxThis->xLocalCfg.pvIOAccess,
                                                xMode,
                                                xIntMode,
                                                xFlags,
                                                pxCfg->ullBaseAddress,
                                                pxCfg->ullRingAddress,
                                                pxCfg->ulRingLength,
                                                pxCfg->ulSubmissionQueueSlotSize,
                                                pxCfg->ulCompletionQueueSlotSize );

                /* Update state & attach if in consumer mode */
                if( GCQ_ERRORS_NONE == xStatus )
                {
                    INC_STAT_COUNTER( FW_IF_GCQ_STATS_OPEN_COUNT );
                    pxProfile->xState = FW_IF_GCQ_STATE_OPENED;
                    PLL_DBG( FW_IF_GCQ_NAME, "FW_IF_GCQ_open (%s)\r\n", ( FW_IF_GCQ_MODE_PRODUCER == pxCfg->xMode )
                             ? ( "Producer" ):( "Consumer" ));

                    if( FW_IF_GCQ_MODE_CONSUMER == pxCfg->xMode )
                    {
                        xStatus = xGCQAttachConsumer( pxProfile->pxGCQInstance );
                        if( GCQ_ERRORS_NONE == xStatus )
                        {
                            pxProfile->xState = FW_IF_GCQ_STATE_ATTACHED;
                            PLL_DBG( FW_IF_GCQ_NAME, "Attached ok!\r\n" );
                            INC_STAT_COUNTER( FW_IF_GCQ_STATS_ATTACHED_COUNT );
                        }
                    }
                }

            /* Map return code */
            xRet = prvxMapIFDriverReturnCode( xStatus );
        }
        else
        {
            xRet = FW_IF_GCQ_ERRORS_NOT_SUPPORTED;
            INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_NOT_SUPPORTED_COUNT );
        }
    }

    return xRet;
}

/**
 * @brief   Local implementation of FW_IF_close
 */
static uint32_t prvGCQClose( void *pvFWIf )
{
    FW_IF_GCQ_ERRORS_TYPE xRet = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFWIf;
    if( CHECK_NULL( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }
    if( CHECK_CFG( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_CFG;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_CFG_COUNT );
    }
    if( CHECK_FIREWALLS( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }
    if( CHECK_DRIVER )
    {
        xRet = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
        INC_ERROR_COUNTER( FW_IF_ERRORS_DRIVER_NOT_INITIALISED_COUNT );
    }

    FW_IF_GCQ_CFG *pxCfg = ( FW_IF_GCQ_CFG* )pxThisIf->cfg;
    if( CHECK_PROFILE( pxCfg ) )
    {
        xRet = FW_IF_GCQ_ERRORS_INVALID_PROFILE;
        INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_INVALID_PROFILE_COUNT );
    }

    FW_IF_GCQ_PROFILE_TYPE *pxProfile = ( FW_IF_GCQ_PROFILE_TYPE* )pxCfg->pvProfile;
    if( CHECK_INVALID_STATE ( pxProfile ) )
    {
        xRet = FW_IF_GCQ_ERRORS_NOT_SUPPORTED;
        INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_NOT_SUPPORTED_COUNT );
    }

    if( prvxMapIFDriverReturnCode( FW_IF_ERRORS_NONE ) == xRet )
    {
        /*
        * Currently there is no dynamic behavior with the open/close,
        * so this is here to satisfy the interface.
        */
        pxProfile->xState = FW_IF_GCQ_STATE_CLOSED;
        INC_STAT_COUNTER( FW_IF_GCQ_STATS_CLOSE_COUNT );
    }

    return xRet;
}

/**
 * @brief   Local implementation of FW_IF_write
 */
static uint32_t prvGCQWrite( void *pvFWIf, uint64_t ullDstPort, uint8_t *pucData, uint32_t ulSize, uint32_t ulTimeoutMs )
{
    FW_IF_GCQ_ERRORS_TYPE xRet = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFWIf;
    if( CHECK_NULL( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }

    if( CHECK_CFG( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_CFG;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_CFG_COUNT );

    }

    if( CHECK_FIREWALLS( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }

    if( CHECK_DRIVER )
    {
        xRet = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
        INC_ERROR_COUNTER( FW_IF_ERRORS_DRIVER_NOT_INITIALISED_COUNT );
    }


    FW_IF_GCQ_CFG *pxCfg = ( FW_IF_GCQ_CFG* )pxThisIf->cfg;
    if( CHECK_PROFILE( pxCfg ) )
    {
        xRet = FW_IF_GCQ_ERRORS_INVALID_PROFILE;
        INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_INVALID_PROFILE_COUNT );
    }

    FW_IF_GCQ_PROFILE_TYPE *pxProfile = ( FW_IF_GCQ_PROFILE_TYPE* )pxCfg->pvProfile;
    if( CHECK_INVALID_STATE ( pxProfile ) )
    {
        xRet = FW_IF_GCQ_ERRORS_NOT_SUPPORTED;
        INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_NOT_SUPPORTED_COUNT );
    }

    if( prvxMapIFDriverReturnCode( FW_IF_ERRORS_NONE ) == xRet )
    {
        /* vTaskDelay is used outside of function as a block as opposed to a spin on the timeout */
        GCQ_ERRORS_TYPE xStatus = xGCQProduceData( pxProfile->pxGCQInstance, pucData, ulSize );
        
        if( GCQ_ERRORS_NONE == xStatus )
        {
            INC_STAT_COUNTER( FW_IF_GCQ_STATS_READ_COUNT );
        }

        /* Map error return code */
        xRet = prvxMapIFDriverReturnCode( xStatus );
    }

    return xRet;
}

/**
 * @brief   Local implementation of FW_IF_read
 */
static uint32_t prvGCQRead( void *pvFWIf, uint64_t ullSrcPort, uint8_t *pucData, uint32_t *pulSize, uint32_t ulTimeoutMs )
{
    FW_IF_GCQ_ERRORS_TYPE xRet = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFWIf;

    if( CHECK_NULL( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }

    if( CHECK_CFG( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_CFG;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_CFG_COUNT );
    }

    if( CHECK_FIREWALLS( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }

    if( CHECK_DRIVER )
    {
        xRet = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
        INC_ERROR_COUNTER( FW_IF_ERRORS_DRIVER_NOT_INITIALISED_COUNT );
    }

    if( CHECK_NULL( pulSize ) )
    {
        xRet = FW_IF_ERRORS_PARAMS;
        INC_ERROR_COUNTER( FW_IF_ERRORS_PARAMS_COUNT );
    }

    if( CHECK_NULL( pucData ) )
    {
        xRet = FW_IF_ERRORS_PARAMS;
        INC_ERROR_COUNTER( FW_IF_ERRORS_PARAMS_COUNT );
    }

    if( prvxMapIFDriverReturnCode( FW_IF_ERRORS_NONE ) == xRet )
    {
        FW_IF_GCQ_CFG *pxCfg = ( FW_IF_GCQ_CFG* )pxThisIf->cfg;
        if( CHECK_PROFILE( pxCfg ) )
        { 
            xRet = FW_IF_GCQ_ERRORS_INVALID_PROFILE;
            INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_INVALID_PROFILE_COUNT );
        }

        FW_IF_GCQ_PROFILE_TYPE *pxProfile = ( FW_IF_GCQ_PROFILE_TYPE* )pxCfg->pvProfile;
        if( CHECK_INVALID_STATE ( pxProfile ) )
        {
            xRet = FW_IF_GCQ_ERRORS_NOT_SUPPORTED;
            INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_NOT_SUPPORTED_COUNT );
        }

        /* vTaskDelay is used outside of function as a block as opposed to a spin on the timeout */
        GCQ_ERRORS_TYPE xStatus = xGCQConsumeData( pxProfile->pxGCQInstance, pucData, *pulSize );
       
        if( GCQ_ERRORS_NONE == xStatus )
        {
            INC_STAT_COUNTER( FW_IF_GCQ_STATS_WRITE_COUNT );
        }

        if( prvxMapIFDriverReturnCode( FW_IF_ERRORS_NONE ) == xRet )
        {
            xRet = prvxMapIFDriverReturnCode( xStatus );
        }
    }

    return xRet;
}

/**
 * @brief   Local implementation of FW_IF_ioctrl
 */
static uint32_t prvGCQIOCtrl( void *pvFWIf, uint32_t ulOption, void *pvValue )
{
    FW_IF_GCQ_ERRORS_TYPE xRet = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFWIf;
    if( CHECK_NULL( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }
    if( CHECK_CFG( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_CFG;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_CFG_COUNT );

    }
    if( CHECK_FIREWALLS( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }
    if( CHECK_DRIVER )
    {
        xRet = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
        INC_ERROR_COUNTER( FW_IF_ERRORS_DRIVER_NOT_INITIALISED_COUNT );
    }


    if( prvxMapIFDriverReturnCode( FW_IF_ERRORS_NONE ) == xRet )
    {
        FW_IF_GCQ_CFG *pxCfg = ( FW_IF_GCQ_CFG* )pxThisIf->cfg;
        if( CHECK_PROFILE( pxCfg ) )
        {
            xRet = FW_IF_GCQ_ERRORS_INVALID_PROFILE_COUNT;
            INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_INVALID_PROFILE_COUNT );
        }

        FW_IF_GCQ_PROFILE_TYPE *pxProfile = ( FW_IF_GCQ_PROFILE_TYPE* ) &pxCfg->pvProfile;


        /* Specialization options supported outside definition of standard API. */
        switch( ulOption )
        {
            case FW_IF_COMMON_IOCTRL_FLUSH_TX:
            case FW_IF_COMMON_IOCTRL_FLUSH_RX:
                /* Handle common IOCTL's. */
                break;

            case FW_IF_COMMON_IOCTRL_GET_RX_MODE:
                if( FW_IF_GCQ_INTERRUPT_MODE_NONE == pxCfg->xInterruptMode )
                {
                    *( uint32_t* )pvValue = FW_IF_RX_MODE_POLLING;
                }
                else
                {
                    *( uint32_t* )pvValue = FW_IF_RX_MODE_EVENT;
                }
                break;

            case FW_IF_GCQ_IOCTRL_SET_OPAQUE_HANDLE:
                /* Set the opaque handle used by calling API to store a reference. */
                pxProfile->ulIOHandle = *( uint32_t* )pvValue;
                PLL_DBG( FW_IF_GCQ_NAME, "GCQ IOCTL - set opaque handle 0x%lx\r\n", pxProfile->ulIOHandle );
                break;

            case FW_IF_GCQ_IOCTRL_GET_OPAQUE_HANDLE:
                /* Get the opaque handle used by calling API to retreive a reference. */
                PLL_DBG( FW_IF_GCQ_NAME, "GCQ IOCTL - get opaque handle 0x%lx\r\n", pxProfile->ulIOHandle );
                *( uint32_t* )pvValue = pxProfile->ulIOHandle;
                break;

            default:
                xRet = FW_IF_ERRORS_UNRECOGNISED_OPTION;
                PLL_ERR( FW_IF_GCQ_NAME, "Error:  GCQ IOCTL unrecognised option\r\n" );
                break;
        }
    }

    return xRet;
}


/**
 * @brief   Local implementation of FW_IF_bindCallback
 */
static uint32_t prvGCQBindCallback( void *pvFWIf, FW_IF_callback *pxNewFunc )
{
    FW_IF_GCQ_ERRORS_TYPE xRet = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFWIf;
    if( CHECK_NULL( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }

    if( CHECK_CFG( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_CFG;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_CFG_COUNT );
    }

    if( CHECK_FIREWALLS( pxThisIf ) )
    {
        xRet = FW_IF_ERRORS_INVALID_HANDLE;
        INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_HANDLE_COUNT );
    }

    if( CHECK_DRIVER )
    {
        xRet = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
        INC_ERROR_COUNTER( FW_IF_ERRORS_DRIVER_NOT_INITIALISED_COUNT );
    }

    if( CHECK_NULL( pxNewFunc ) )
    {
        xRet = FW_IF_ERRORS_PARAMS;
        INC_ERROR_COUNTER( FW_IF_ERRORS_PARAMS_COUNT );
    }
    
    if( prvxMapIFDriverReturnCode( FW_IF_ERRORS_NONE ) == xRet )
    {
        /*
        * Binds in callback provided to the FW_IF.
        * Callback will be invoked when by the driver when event occurs.
        */
        pxThisIf->raiseEvent = pxNewFunc;
        PLL_DBG( FW_IF_GCQ_NAME, "FW_IF_bindCallback called\r\n" );
        INC_STAT_COUNTER( FW_IF_GCQ_STATS_BIND_CALLBACK_CALLED_COUNT );
    }

    return xRet;
}


/*****************************************************************************/
/* public functions                                                          */
/*****************************************************************************/

/**
 * @brief   initialisation function for GCQ interfaces (generic across all GCQ interfaces)
 */
uint32_t ulFW_IF_GCQ_Init( FW_IF_GCQ_INIT_CFG *pxCfg )
{
    FW_IF_GCQ_ERRORS_TYPE xRet = FW_IF_GCQ_ERRORS_DRIVER_INVALID_ARG;

    if( ( GCQ_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( GCQ_LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) )
    {   
        xRet = FW_IF_ERRORS_NONE;

        if( CHECK_NULL( pxCfg ) )
        {
            xRet = FW_IF_ERRORS_PARAMS;
            INC_ERROR_COUNTER( FW_IF_ERRORS_PARAMS_COUNT );
        }

        if( CHECK_NOT_NULL( pxCfg->pvIOAccess ) )
        {
            xRet = FW_IF_ERRORS_PARAMS;
            INC_ERROR_COUNTER( FW_IF_ERRORS_PARAMS_COUNT );
        }

        if( FW_IF_FALSE != pxThis->iInitialised )
        {
            xRet = FW_IF_ERRORS_DRIVER_IN_USE;
            INC_ERROR_COUNTER( FW_IF_ERRORS_DRIVER_IN_USE_COUNT );
        }
    
        if( prvxMapIFDriverReturnCode( FW_IF_ERRORS_NONE ) == xRet )
        {
            /*
            * Bind in register and memory R/W function pointers
            * and assign to the local profile to be used by all
            * GCQ instances
            */
            pxThis->xGcqIoAccess.xGCQReadMem32 = prvulReadMemReg32;
            pxThis->xGcqIoAccess.xGCQWriteMem32 = prvvWriteMemReg32;
            pxThis->xGcqIoAccess.xGCQReadReg32 = prvulReadMemReg32;
            pxThis->xGcqIoAccess.xGCQWriteReg32 = prvvWriteMemReg32;
            pxThis->xLocalCfg.pvIOAccess = &pxThis->xGcqIoAccess;
            pxThis->iInitialised = FW_IF_TRUE;

            PLL_DBG( FW_IF_GCQ_NAME, "FW_IF_GCQ_init\r\n" );
            INC_STAT_COUNTER( FW_IF_GCQ_STATS_INIT_OVERALL_COMPLETE_COUNT )
        }
    }

    return xRet;
}

/**
 * @brief   opens an instance of the GCQ interface
 */
uint32_t ulFW_IF_GCQ_Create( FW_IF_CFG *pxFWIf, FW_IF_GCQ_CFG *pxGCQCfg )
{
    FW_IF_GCQ_ERRORS_TYPE xRet = FW_IF_GCQ_ERRORS_DRIVER_INVALID_ARG;

    if( ( GCQ_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( GCQ_LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {   
        xRet = FW_IF_ERRORS_NONE;
        if( CHECK_DRIVER )
        { 
            xRet = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
            INC_ERROR_COUNTER( FW_IF_ERRORS_DRIVER_NOT_INITIALISED_COUNT );
        }

        if( CHECK_NULL( pxFWIf ) )
        {
            xRet = FW_IF_ERRORS_INVALID_CFG;
            INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_CFG_COUNT );
        }

        if( CHECK_NULL( pxGCQCfg ) )
        {
            xRet = FW_IF_ERRORS_INVALID_CFG;
            INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_CFG_COUNT );
        }

        if( prvxMapIFDriverReturnCode( FW_IF_ERRORS_NONE ) == xRet )
        {
            /* Validate the configuration provided */
            if( pxThis->ulProfilesAllocated > ( GCQ_MAX_INSTANCES - 1 ) )
            {
                xRet = FW_IF_GCQ_ERRORS_NO_FREE_PROFILES;
                INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_NO_FREE_PROFILES_COUNT );
            }
            else if( ( MAX_FW_IF_GCQ_MODE > pxGCQCfg->xMode ) &&
                    ( MAX_FW_IF_GCQ_INTERRUPT_MODE > pxGCQCfg->xInterruptMode ) )
            {
                FW_IF_CFG myLocalIf =
                {
                    .upperFirewall  = GCQ_UPPER_FIREWALL,
                    .open           = &prvGCQOpen,
                    .close          = &prvGCQClose,
                    .write          = &prvGCQWrite,
                    .read           = &prvGCQRead,
                    .ioctrl         = &prvGCQIOCtrl,
                    .bindCallback   = &prvGCQBindCallback,
                    .cfg            = ( void* )pxGCQCfg,
                    .lowerFirewall  = GCQ_LOWER_FIREWALL
                };

                pvOSAL_MemCpy( pxFWIf, &myLocalIf, sizeof( FW_IF_CFG ) );

                FW_IF_GCQ_CFG *pxCfg = ( FW_IF_GCQ_CFG* )pxFWIf->cfg;
                pxThis->xGcqProfile[ pxThis->ulProfilesAllocated ].ulIOHandle = 0;
                pxThis->xGcqProfile[ pxThis->ulProfilesAllocated ].xState = FW_IF_GCQ_STATE_INIT;
                pxThis->xGcqProfile[ pxThis->ulProfilesAllocated ].pxGCQInstance = NULL;
                pxCfg->pvProfile = &pxThis->xGcqProfile[ pxThis->ulProfilesAllocated ];
                pxThis->ulProfilesAllocated++;

                PLL_DBG( FW_IF_GCQ_NAME, "FW_IF_GCQ_create\r\n" );
                INC_STAT_COUNTER( FW_IF_GCQ_STATS_INSTANCE_CREATE_COUNT )
            }
            else
            {
                xRet = FW_IF_ERRORS_INVALID_CFG;
                INC_ERROR_COUNTER( FW_IF_ERRORS_INVALID_CFG_COUNT );
            }
        }
    }
    return xRet;
}

/**
 * @brief    Print all the stats gathered by the driver
 */
int iFW_IF_GCQ_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( GCQ_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( GCQ_LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( FW_IF_GCQ_NAME, "============================================================\r\n" );
        PLL_INF( FW_IF_GCQ_NAME, "FW IF GCQ Statistics:\n\r" );
        for( i = 0; i < FW_IF_GCQ_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( FW_IF_GCQ_NAME, "------------------------------------------------------------\r\n" );
        PLL_INF( FW_IF_GCQ_NAME, "FW IF GCQ Errors:\n\r" );
        for( i = 0; i < FW_IF_GCQ_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( FW_IF_GCQ_NAME, "============================================================\r\n" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_VALIDATION_FAILED_COUNT )
    }

    return iStatus;
}

/**
 * @brief    Clears all the stats gathered by the driver
 */
int iFW_IF_GCQ_ClearStatistics( void )
{
    int iStatus = ERROR;

    if( ( GCQ_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( GCQ_LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        pvOSAL_MemSet( pxThis->pulStatCounters, 0, sizeof( pxThis->pulStatCounters ) );
        pvOSAL_MemSet( pxThis->pulErrorCounters, 0, sizeof( pxThis->pulErrorCounters ) );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( FW_IF_GCQ_ERRORS_VALIDATION_FAILED_COUNT )
    }

    return iStatus;
}
