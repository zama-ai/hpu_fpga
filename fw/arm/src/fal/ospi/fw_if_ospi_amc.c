/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the FW IF OSPI AMC abstraction.
 *
 * @file fw_if_ospi_amc.c
 *
 */

/*****************************************************************************/
/* Includes                                                                  */
/*****************************************************************************/

#include <stdio.h>
#include <string.h>

#include "util.h"
#include "osal.h"
#include "ospi.h"
#include "standard.h"

#include "fw_if_ospi.h"
#include "profile_fal.h"


/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/

#define FW_IF_OSPI_NAME                 "FW_IF_OSPI"
#define OSPI_UPPER_FIREWALL             ( 0xBEEFCAFE )
#define OSPI_LOWER_FIREWALL             ( 0xDEADFACE )

#define CHECK_DRIVER                    ( FW_IF_FALSE == pxThis->iInitialised )
#define CHECK_FIREWALLS( f )            ( ( f->upperFirewall != OSPI_UPPER_FIREWALL ) && \
                                          ( f->lowerFirewall != OSPI_LOWER_FIREWALL ) )

#define CHECK_HDL( f )                  ( NULL == f )
#define CHECK_CFG( f )                  ( NULL == ( f )->cfg )

/* Stat & Error definitions */
#define FW_IF_OSPI_STAT_COUNTS( DO )                    \
    DO( FW_IF_OSPI_STATS_INIT_OVERALL_COMPLETE_COUNT )  \
    DO( FW_IF_OSPI_STATS_INSTANCE_CREATE_COUNT )        \
    DO( FW_IF_OSPI_STATS_OPEN_COUNT )                   \
    DO( FW_IF_OSPI_STATS_CLOSE_COUNT )                  \
    DO( FW_IF_OSPI_IO_CTRL_COUNT )                      \
    DO( FW_IF_OSPI_STATS_BIND_CALLBACK_CALLED_COUNT )   \
    DO( FW_IF_OSPI_STATS_READ_COUNT )                   \
    DO( FW_IF_OSPI_STATS_WRITE_COUNT )                  \
    DO( FW_IF_OSPI_STATS_MAX_COUNT )

#define FW_IF_OSPI_ERROR_COUNTS( DO )                  \
    DO( FW_IF_ERRORS_PARAMS_COUNT )                    \
    DO( FW_IF_ERRORS_DRIVER_IN_USE_COUNT )             \
    DO( FW_IF_ERRORS_DRIVER_NOT_INITIALISED_COUNT )    \
    DO( FW_IF_OSPI_ERRORS_DRIVER_FAILURE_COUNT )       \
    DO( FW_IF_ERRORS_INVALID_CFG_COUNT )               \
    DO( FW_IF_ERRORS_INVALID_HANDLE_COUNT )            \
    DO( FW_IF_OSPI_ERRORS_NO_FREE_PROFILES_COUNT )     \
    DO( FW_IF_OSPI_ERRORS_VALIDATION_FAILED_COUNT )    \
    DO( FW_IF_OSPI_ERRORS_INVALID_PROFILE_COUNT )      \
    DO( FW_IF_OSPI_ERRORS_NOT_SUPPORTED_COUNT )        \
    DO( FW_IF_OSPI_ERRORS_INVALID_STATE_COUNT )        \
    DO( FW_IF_OSPI_ERRORS_MAX_COUNT )                          

#define PRINT_STAT_COUNTER( x )             PLL_INF( FW_IF_OSPI_NAME, "%50s . . . . %d\r\n",          \
                                                     FW_IF_OSPI_STAT_COUNTS_STR[ x ],       \
                                                     pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x )            PLL_INF( FW_IF_OSPI_NAME, "%50s . . . . %d\r\n",          \
                                                     FW_IF_OSPI_ERROR_COUNTS_STR[ x ],      \
                                                     pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )               { if( x < FW_IF_OSPI_STATS_MAX_COUNT )pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x )              { if( x < FW_IF_OSPI_ERRORS_MAX_COUNT )pxThis->pulErrorCounters[ x ]++; }


/*****************************************************************************/
/* Enums                                                                     */
/*****************************************************************************/

/**
 * @enum    FW_IF_OSPI_STAT_COUNTS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( FW_IF_OSPI_STAT_COUNTS, FW_IF_OSPI_STAT_COUNTS, FW_IF_OSPI_STAT_COUNTS_STR )

/**
 * @enum    FW_IF_OSPI_ERROR_COUNTS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( FW_IF_OSPI_ERROR_COUNTS, FW_IF_OSPI_ERROR_COUNTS, FW_IF_OSPI_ERROR_COUNTS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  FW_IF_OSPI_PRIVATE_DATA
 * @brief   Structure to hold this modules private data
 */
typedef struct FW_IF_OSPI_PRIVATE_DATA
{
    uint32_t                ulUpperFirewall;

    FW_IF_OSPI_INIT_CFG     xLocalCfg;
    int                     iInitialised;

    uint32_t                pulStatCounters[ FW_IF_OSPI_STATS_MAX_COUNT ];
    uint32_t                pulErrorCounters[ FW_IF_OSPI_ERRORS_MAX_COUNT ];

    uint32_t                ulLowerFirewall;

} FW_IF_OSPI_PRIVATE_DATA;


/*****************************************************************************/
/* Local Variables                                                           */
/*****************************************************************************/

static const char* const pcOspiStateModeStr[ ] = { FAL_OSPI_STATE_ENTRY( INIT ),
                                                   FAL_OSPI_STATE_ENTRY( OPENED ),
                                                   FAL_OSPI_STATE_ENTRY( CLOSED ),
                                                   FAL_OSPI_STATE_ENTRY( ERROR ) };

static FW_IF_OSPI_PRIVATE_DATA xLocalData =
{
    OSPI_UPPER_FIREWALL,    /* ulUpperFirewall */   

    { 0 },                  /* xLocalCfg */
    FALSE,                  /* iInitialised */

    { 0 },                  /* pulStatCounters */
    { 0 },                  /* pulErrorCounters */

    OSPI_LOWER_FIREWALL     /* ulLowerFirewall */
};
static FW_IF_OSPI_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Local Function Declarations                                                */
/******************************************************************************/

/**
 * @brief   Local implementation of FW_IF_open
 *
 * @param   pvFwIf          Pointer to this fw_if
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulOspiOpen( void *pvFwIf );

/**
 * @brief   Local implementation of FW_IF_close
 *
 * @param   pvFwIf          Pointer to this fw_if
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulOspiClose( void *pvFwIf );

/**
 * @brief   Writes data from an instance of the specific fw_if
 *
 * @param   pvFwIf          Local implementation of FW_IF_write
 * @param   ullAddrOffset   The address offset from the base address specified in the create
 * @param   pucData         Data buffer to write
 * @param   ulLength        Number of bytes in data buffer
 * @param   ulTimeoutMs     Time (in ms) to wait for write to complete
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulOspiWrite( void *pvFwIf,
                             uint64_t ullAddrOffset,
                             uint8_t *pucData,
                             uint32_t ulLength,
                             uint32_t ulTimeoutMs );

/**
 * @brief   Local implementation of FW_IF_read
 *
 * @param   pvFwIf          Pointer to this fw_if
 * @param   ullAddrOffset   The address offset from the base address specified in the create
 * @param   pucData         Data buffer to read
 * @param   pulLength       Pointer to maximum number of bytes allowed in data buffer
 *                          This value is updated to the actual number of bytes read
 * @param   ulTimeoutMs     Time (in ms) to wait for read to complete
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulOspiRead( void *pvFwIf,
                            uint64_t ullAddrOffset,
                            uint8_t *pucData,
                            uint32_t *pulLength,
                            uint32_t ulTimeoutMs );

/**
 * @brief   Local implementation of FW_IF_ioctrl
 *
 * @param   pvFwIf          Pointer to this fw_if
 * @param   ulOption        Unique IO Ctrl option to set/get
 * @param   pvValue         Pointer to value to set/get
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulOspiIoCtrl( void *pvFwIf, uint32_t ulOption, void *pvValue );

/**
 * @brief   Local implementation of FW_IF_bindCallback
 *
 * @parmam  vFwIf           Pointer to this fw_if
 * @param   pxNewFunc       Function pointer to call
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulOspiBindCallback( void *vFwIf, FW_IF_callback *pxNewFunc );

/**
 * @brief   Validate the read/write access address is in range
 *
 * @param   pxCfg           The interface config options
 * @param   ulAddrOffset    The address offset from the base address specified in the create
 * @param   ulLength        Number of bytes in data buffer
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulValidateAddressRange( FW_IF_OSPI_CFG *pxCfg, uint32_t ulAddrOffset, uint32_t ulLength );


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/**
 * @brief   initialisation function for OSPI interfaces (generic across all OSPI interfaces)
 */
uint32_t ulFW_IF_OSPI_Init( FW_IF_OSPI_INIT_CFG *xInitCfg )
{
    FW_IF_OSPI_ERRORS xRet = FW_IF_OSPI_ERRORS_DRIVER_FAILURE;

    if( ( OSPI_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( OSPI_LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) )
    {  
        xRet = FW_IF_ERRORS_NONE;

        if( FW_IF_FALSE != pxThis->iInitialised )
        {
            xRet = FW_IF_ERRORS_DRIVER_IN_USE;
        }
        else if ( NULL != xInitCfg )
        {
            OSPI_CFG_TYPE pxOspiCfg = { 0 };
            int iStatus = ERROR;

            /*
             * Initilise config data shared between all instances of OSPI.
             */
            pvOSAL_MemCpy( &pxThis->xLocalCfg, xInitCfg, sizeof( FW_IF_OSPI_INIT_CFG ) );

            /*
             * Initialise the driver based on the device id supplied in the xparameters.h
             * and the page size.
             */
            PLL_DBG( FW_IF_OSPI_NAME, "Device Id:%d\r\n", pxThis->xLocalCfg.ucOspiDeviceId );
            PLL_DBG( FW_IF_OSPI_NAME, "Page Size:%d\r\n", pxThis->xLocalCfg.usPageSize );

            pxOspiCfg.ucDeviceId = pxThis->xLocalCfg.ucOspiDeviceId;
            pxOspiCfg.usPageSize = pxThis->xLocalCfg.usPageSize;
            iStatus = iOSPI_FlashInit( &pxOspiCfg );
            if( OK != iStatus )
            {
                xRet = FW_IF_OSPI_ERRORS_DRIVER_FAILURE;
            }
            else
            {
                xRet = FW_IF_ERRORS_NONE;
                pxThis->iInitialised = FW_IF_TRUE;
                INC_STAT_COUNTER( FW_IF_OSPI_STATS_INIT_OVERALL_COMPLETE_COUNT );
            }
        }
        else
        {
            xRet = FW_IF_ERRORS_PARAMS;
            INC_ERROR_COUNTER( FW_IF_ERRORS_PARAMS_COUNT );
        }
    }

    return xRet;
}

/**
 * @brief   opens an instance of the OSPI interface
 */
uint32_t ulFW_IF_OSPI_Create( FW_IF_CFG *pxFwIf, FW_IF_OSPI_CFG *pxOspiCfg )
{
    FW_IF_OSPI_ERRORS xRet = FW_IF_OSPI_ERRORS_DRIVER_FAILURE;

    if( ( OSPI_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( OSPI_LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    { 
        xRet = FW_IF_ERRORS_NONE;

        if( CHECK_DRIVER )
        {
            xRet = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
            INC_ERROR_COUNTER( FW_IF_ERRORS_DRIVER_NOT_INITIALISED_COUNT );
        }

        if( ( NULL != pxFwIf ) &&
            ( NULL != pxOspiCfg ) )
        {

            FW_IF_CFG myLocalIf =
            {
                .upperFirewall  = OSPI_UPPER_FIREWALL,
                .open           = &ulOspiOpen,
                .close          = &ulOspiClose,
                .write          = &ulOspiWrite,
                .read           = &ulOspiRead,
                .ioctrl         = &ulOspiIoCtrl,
                .bindCallback   = &ulOspiBindCallback,
                .cfg            = ( void* )pxOspiCfg,
                .lowerFirewall  = OSPI_LOWER_FIREWALL
            };

            pvOSAL_MemCpy( pxFwIf, &myLocalIf, sizeof( FW_IF_CFG ) );

            FW_IF_OSPI_CFG *pxCfg = ( FW_IF_OSPI_CFG* )pxFwIf->cfg;

            /* Configuration options, base address will the RPU/APU or SC address within the flash device */
            PLL_DBG( FW_IF_OSPI_NAME, "Start Address: 0x%x\r\n", pxCfg->ulBaseAddress );
            PLL_DBG( FW_IF_OSPI_NAME, "Length: 0x%x\r\n", pxCfg->ulLength );
            PLL_DBG( FW_IF_OSPI_NAME, "Flag Erase Before Write: %d\r\n", pxCfg->ucEraseBeforeWriteFlag );
            pxCfg->xState = FW_IF_OSPI_STATE_INIT;

            INC_STAT_COUNTER( FW_IF_OSPI_STATS_INSTANCE_CREATE_COUNT );
        }
        else
        {
            xRet = FW_IF_ERRORS_PARAMS;
            INC_ERROR_COUNTER( FW_IF_ERRORS_PARAMS_COUNT );
        }
    }

    return xRet;
}


/******************************************************************************/
/* Local Function Implementations                                             */
/******************************************************************************/

/**
 * @brief   Local implementation of FW_IF_open
 */
static uint32_t ulOspiOpen( void *pvFwIf )
{
    FW_IF_OSPI_ERRORS xRet = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    if( CHECK_HDL( pxThisIf ) )
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

    FW_IF_OSPI_CFG *pxCfg = ( FW_IF_OSPI_CFG* )pxThisIf->cfg;
    if( FW_IF_OSPI_STATE_INIT == pxCfg->xState )
    {
        pxCfg->xState = FW_IF_OSPI_STATE_OPENED;
        INC_STAT_COUNTER( FW_IF_OSPI_STATS_OPEN_COUNT );
    }
    else
    {
        xRet = FW_IF_OSPI_ERRORS_INVALID_STATE;
        PLL_ERR( FW_IF_OSPI_NAME, "Error: open() should only be called from init state [%s]\r\n",
                 pcOspiStateModeStr[ pxCfg->xState ] );
        INC_ERROR_COUNTER( FW_IF_OSPI_ERRORS_INVALID_STATE_COUNT );
    }

    return xRet;
}

/**
 * @brief   Local implementation of FW_IF_close
 */
static uint32_t ulOspiClose( void *pvFwIf )
{
    FW_IF_OSPI_ERRORS xRet = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    if( CHECK_HDL( pxThisIf ) )
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

    FW_IF_OSPI_CFG *pxCfg = ( FW_IF_OSPI_CFG* )pxThisIf->cfg;
    if( FW_IF_OSPI_STATE_OPENED == pxCfg->xState )
    {
        pxCfg->xState = FW_IF_OSPI_STATE_CLOSED;
        INC_STAT_COUNTER( FW_IF_OSPI_STATS_CLOSE_COUNT );
    }
    else
    {
        xRet = FW_IF_OSPI_ERRORS_INVALID_STATE;
        PLL_ERR( FW_IF_OSPI_NAME, "Error: close() should only be called from opened state [%s]\r\n",
                 pcOspiStateModeStr[ pxCfg->xState ] );
        INC_ERROR_COUNTER( FW_IF_OSPI_ERRORS_INVALID_STATE_COUNT );
    }

    return xRet;
}

/**
 * @brief   Local implementation of FW_IF_write
 */
static uint32_t ulOspiWrite( void *pvFwIf,
                             uint64_t ullAddrOffset,
                             uint8_t *pucData,
                             uint32_t ulLength,
                             uint32_t ulTimeoutMs )
{
    FW_IF_ERRORS xRet = FW_IF_ERRORS_NONE;
    uint32_t ulAddrOffset = ( uint32_t )ullAddrOffset;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    if( CHECK_HDL( pxThisIf ) )
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

    if( FW_IF_ERRORS_NONE == xRet )
    {
        FW_IF_OSPI_CFG *pxCfg = ( FW_IF_OSPI_CFG* )pxThisIf->cfg;

        if( ( NULL != pucData ) )
        {
            if( FW_IF_OSPI_STATE_OPENED == pxCfg->xState )
            {
                uint32_t ulAddr = pxCfg->ulBaseAddress + ulAddrOffset;
                xRet = ulValidateAddressRange( pxCfg, ulAddrOffset, ulLength );
                if( FW_IF_ERRORS_NONE == xRet )
                {
                    int iStatus = ERROR;

                    /* Check flag to see if erase if required before write */
                    if( FW_IF_TRUE == pxCfg->ucEraseBeforeWriteFlag )
                    {
                        iStatus = iOSPI_FlashErase( ulAddr, ulLength );
                    }
                    else
                    {
                        iStatus = OK;
                    }

                    if( OK == iStatus )
                    {
                        iStatus = iOSPI_FlashWrite( ulAddr, pucData, ulLength );
                    }

                    if( OK != iStatus )
                    {
                        xRet = FW_IF_OSPI_ERRORS_DRIVER_FAILURE;
                        INC_ERROR_COUNTER( FW_IF_OSPI_ERRORS_DRIVER_FAILURE_COUNT );
                    }
                    else
                    {
                        xRet = FW_IF_ERRORS_NONE;
                        INC_STAT_COUNTER( FW_IF_OSPI_STATS_WRITE_COUNT );
                    }
                }
            }
            else
            {
                xRet = FW_IF_OSPI_ERRORS_INVALID_STATE;
                PLL_ERR( FW_IF_OSPI_NAME, "Error: write() should only be called from opened state [%s]\r\n",
                        pcOspiStateModeStr[ pxCfg->xState ] );
                INC_ERROR_COUNTER( FW_IF_OSPI_ERRORS_INVALID_STATE_COUNT );
            }
        }
        else
        {
            xRet = FW_IF_ERRORS_PARAMS;
        }
    }
    
    return xRet;
}

/**
 * @brief   Local implementation of FW_IF_read
 */
static uint32_t ulOspiRead( void *pvFwIf,
                            uint64_t ullAddrOffset,
                            uint8_t *pucData,
                            uint32_t *pulLength,
                            uint32_t ulTimeoutMs )
{
    FW_IF_ERRORS xRet = FW_IF_ERRORS_NONE;
    uint32_t ulAddrOffset = ( uint32_t )ullAddrOffset;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    if( CHECK_HDL( pxThisIf ) )
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

    if( FW_IF_ERRORS_NONE == xRet )
    {
        FW_IF_OSPI_CFG *pxCfg = ( FW_IF_OSPI_CFG* )pxThisIf->cfg;

        if( ( NULL != pucData ) &&
            ( NULL != pulLength ) )
        {
            if( FW_IF_OSPI_STATE_OPENED == pxCfg->xState )
            {
                uint32_t ulAddr = pxCfg->ulBaseAddress + ulAddrOffset;
                xRet = ulValidateAddressRange( pxCfg, ulAddrOffset, *pulLength);
                if( FW_IF_ERRORS_NONE == xRet )
                {
                    int iStatus = ERROR;
                    iStatus = iOSPI_FlashRead( ulAddr, pucData, pulLength );
                    if( OK != iStatus )
                    {
                        xRet = FW_IF_OSPI_ERRORS_DRIVER_FAILURE;
                        INC_ERROR_COUNTER( FW_IF_OSPI_ERRORS_DRIVER_FAILURE_COUNT );
                    }
                    else
                    {
                        xRet = FW_IF_ERRORS_NONE;
                        INC_STAT_COUNTER( FW_IF_OSPI_STATS_READ_COUNT );
                    }
                }
            }
            else
            {
                xRet = FW_IF_OSPI_ERRORS_INVALID_STATE;
                PLL_ERR( FW_IF_OSPI_NAME, "Error: write() should only be called from opened state [%s]\r\n",
                        pcOspiStateModeStr[ pxCfg->xState ] );
                INC_ERROR_COUNTER( FW_IF_OSPI_ERRORS_INVALID_STATE_COUNT );
            }
        }
        else
        {
            xRet = FW_IF_ERRORS_PARAMS;
        }
    }

    return xRet;
}

/**
 * @brief   Local implementation of FW_IF_ioctrl
 */
static uint32_t ulOspiIoCtrl( void *pvFwIf, uint32_t ulOption, void *pvValue )
{
    FW_IF_ERRORS xRet = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    if( CHECK_HDL( pxThisIf ) )
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

    /*
     * Specialization options supported outside definition of standard API.
     */
    switch( ulOption )
    {
    case FW_IF_COMMON_IOCTRL_FLUSH_TX:
    case FW_IF_COMMON_IOCTRL_FLUSH_RX:
    case FW_IF_COMMON_IOCTRL_GET_RX_MODE:
        /*
         * Handle common IOCTL's.
         */
        break;

    case FW_IF_OSPI_IOCTL_GET_PROGRESS:
    {
        int iStatus = ERROR;
        uint8_t ucFlashProgress = 0;

        iStatus = iOSPI_GetOperationProgress( &ucFlashProgress );
        if( OK == iStatus )
        {
            *( uint32_t* )pvValue = ucFlashProgress;
            xRet = FW_IF_ERRORS_NONE;
        }
        else
        {
            xRet = FW_IF_OSPI_ERRORS_DRIVER_FAILURE;
            INC_ERROR_COUNTER( FW_IF_OSPI_ERRORS_DRIVER_FAILURE_COUNT );
        }
        break;
    }

    default:
        xRet = FW_IF_ERRORS_UNRECOGNISED_OPTION;
        PLL_ERR( FW_IF_OSPI_NAME, "OSPI IOCTL - Unrecognised option\r\n" );
        break;
    }

    if( FW_IF_ERRORS_NONE == xRet )
    {
        PLL_ERR( FW_IF_OSPI_NAME, "OSPI FW_IF_ioctl\r\n" );
        INC_STAT_COUNTER( FW_IF_OSPI_IO_CTRL_COUNT );
    }

    return xRet;
}

/**
 * @brief   Local implementation of FW_IF_bindCallback
 */
static uint32_t ulOspiBindCallback( void *pvFwIf, FW_IF_callback *pxNewFunc )
{
    FW_IF_OSPI_ERRORS xRet = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    if( CHECK_HDL( pxThisIf ) )
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

    if( NULL != pxNewFunc )
    {
        /*
         * Binds in callback provided to the FW_IF.
         * Callback will be invoked when by the driver when event occurs.
         */
        pxThisIf->raiseEvent = pxNewFunc;
        PLL_DBG( FW_IF_OSPI_NAME, "OSPI FW_IF_bindCallback called\r\n" );
        INC_STAT_COUNTER( FW_IF_OSPI_STATS_BIND_CALLBACK_CALLED_COUNT );
    }
    else
    {
        xRet = FW_IF_ERRORS_PARAMS;
        INC_ERROR_COUNTER( FW_IF_ERRORS_PARAMS_COUNT );
    }

    return xRet;
}

/**
 * @brief   Validate the read/write access address is in range
 */
static uint32_t ulValidateAddressRange( FW_IF_OSPI_CFG *pxCfg, uint32_t ulAddrOffset, uint32_t ulLength )
{
    FW_IF_OSPI_ERRORS xRet = FW_IF_OSPI_ERRORS_DRIVER_INVALID_ADDRESS;

    if( NULL != pxCfg )
    {
        /*
         * Test the offset plus the length is less than the total length
         */
        if( ( ulAddrOffset + ulLength ) <= pxCfg->ulLength )
        {
            xRet = FW_IF_ERRORS_NONE;
        }
    }

    return xRet;
}

/**
 * @brief    Print all the stats gathered by the driver
 */
int iFW_IF_OSPI_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( OSPI_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( OSPI_LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( FW_IF_OSPI_NAME, "============================================================\r\n" );
        PLL_INF( FW_IF_OSPI_NAME, "FW IF OSPI Statistics:\n\r" );
        for( i = 0; i < FW_IF_OSPI_STATS_MAX_COUNT; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( FW_IF_OSPI_NAME, "------------------------------------------------------------\r\n" );
        PLL_INF( FW_IF_OSPI_NAME, "FW IF OSPI Errors:\n\r" );
        for( i = 0; i < FW_IF_OSPI_ERRORS_MAX_COUNT; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( FW_IF_OSPI_NAME, "============================================================\r\n" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( FW_IF_OSPI_ERRORS_VALIDATION_FAILED_COUNT )
    }

    return iStatus;
}

/**
 * @brief    Clears all the stats gathered by the driver
 */
int iFW_IF_OSPI_ClearStatistics( void )
{
    int iStatus = ERROR;

    if( ( OSPI_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( OSPI_LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        pvOSAL_MemSet( pxThis->pulStatCounters, 0, sizeof( pxThis->pulStatCounters ) );
        pvOSAL_MemSet( pxThis->pulErrorCounters, 0, sizeof( pxThis->pulErrorCounters ) );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( FW_IF_OSPI_ERRORS_VALIDATION_FAILED_COUNT )
    }

    return iStatus;
}
