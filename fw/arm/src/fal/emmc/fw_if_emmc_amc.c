/**
* Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
* SPDX-License-Identifier: MIT
*
* This file contains the FW IF EMMC interface implementation for AMC.
*
* @file fw_if_emmc_amc.c
*
*/


/*****************************************************************************/
/* includes                                                                  */
/*****************************************************************************/

#include "fw_if_emmc.h"
#include "emmc.h"
#include "profile_hal.h"

#include <stdio.h>
#include <string.h>
#include "pll.h"
#include "util.h"


/*****************************************************************************/
/* defines                                                                   */
/*****************************************************************************/

#define FW_IF_EMMC_NAME         "FW_IF_EMMC"
#define EMMC_UPPER_FIREWALL     ( 0xBEEFCAFE )
#define EMMC_LOWER_FIREWALL     ( 0xDEADFACE )

#define CHECK_DRIVER            if( FW_IF_FALSE == pxThis->iInitialised ) return FW_IF_ERRORS_DRIVER_NOT_INITIALISED
#define CHECK_FIREWALLS( f )    if( ( f->upperFirewall != EMMC_UPPER_FIREWALL ) &&\
                                    ( f->lowerFirewall != EMMC_LOWER_FIREWALL ) ) return FW_IF_ERRORS_INVALID_HANDLE
#define CHECK_HDL( f )          if( NULL == f ) return FW_IF_ERRORS_INVALID_HANDLE
#define CHECK_CFG( f )          if( NULL == ( f )->cfg  ) return FW_IF_ERRORS_INVALID_CFG

/* Stat & Error definitions */
#define FW_IF_EMMC_STAT_COUNTS( DO )   \
    DO( FW_IF_EMMC_STATS_INIT_OVERALL_COMPLETE )         \
    DO( FW_IF_EMMC_STATS_INSTANCE_CREATE )               \
    DO( FW_IF_EMMC_STATS_OPEN )                          \
    DO( FW_IF_EMMC_STATS_CLOSE )                         \
    DO( FW_IF_EMMC_STATS_READ )                          \
    DO( FW_IF_EMMC_STATS_WRITE )                         \
    DO( FW_IF_EMMC_STATS_IO_CTRL )                       \
    DO( FW_IF_EMMC_STATS_MAX )

#define FW_IF_EMMC_ERROR_COUNTS( DO )    \
    DO( FW_IF_EMMC_STATS_INIT_OVERALL_FAILED )           \
    DO( FW_IF_EMMC_ERRORS_INSTANCE_CREATE_FAILED )       \
    DO( FW_IF_EMMC_ERRORS_OPEN_FAILED )                  \
    DO( FW_IF_EMMC_ERRORS_CLOSE_FAILED )                 \
    DO( FW_IF_EMMC_ERRORS_READ_FAILED )                  \
    DO( FW_IF_EMMC_ERRORS_WRITE_FAILED )                 \
    DO( FW_IF_EMMC_ERRORS_IO_CTRL_FAILED )               \
    DO( FW_IF_EMMC_ERRORS_VALIDATION_FAILED )            \
    DO( FW_IF_EMMC_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )             PLL_INF( FW_IF_EMMC_NAME, "%50s . . . . %d\r\n",    \
                                                     FW_IF_EMMC_STAT_COUNTS_STR[ x ],           \
                                                     pxThis->pulStatCounters[ x ] )

#define PRINT_ERROR_COUNTER( x )            PLL_INF( FW_IF_EMMC_NAME, "%50s . . . . %d\r\n",    \
                                                     FW_IF_EMMC_ERROR_COUNTS_STR[ x ],          \
                                                     pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )               { if( x < FW_IF_EMMC_STATS_MAX )pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x )              { if( x < FW_IF_EMMC_ERRORS_MAX )pxThis->pulErrorCounters[ x ]++; }
                                                    

/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    FW_IF_EMMC_STAT_COUNTS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( FW_IF_EMMC_STAT_COUNTS, FW_IF_EMMC_STAT_COUNTS, FW_IF_EMMC_STAT_COUNTS_STR )

/**
 * @enum    FW_IF_EMMC_ERROR_COUNTS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( FW_IF_EMMC_ERROR_COUNTS, FW_IF_EMMC_ERROR_COUNTS, FW_IF_EMMC_ERROR_COUNTS_STR )


/*****************************************************************************/
/* structures                                                                */
/*****************************************************************************/

/**
 * @struct  FW_IF_EMMC_PRIVATE_DATA
 * @brief   Structure to hold this FAL's private data
 */
typedef struct FW_IF_EMMC_PRIVATE_DATA
{
    uint32_t                ulUpperFirewall;

    FW_IF_EMMC_INIT_CFG     xLocalCfg;
    int                     iInitialised;

    uint32_t                pulStatCounters[ FW_IF_EMMC_STATS_MAX ];
    uint32_t                pulErrorCounters[ FW_IF_EMMC_ERRORS_MAX ];

    uint32_t                ulLowerFirewall;

} FW_IF_EMMC_PRIVATE_DATA;


/*****************************************************************************/
/* local variables                                                           */
/*****************************************************************************/

static FW_IF_EMMC_PRIVATE_DATA xLocalData = 
{
    EMMC_UPPER_FIREWALL,    /* ulUpperFirewall */

    { 0 },                  /* xLocalCfg       */
    FW_IF_FALSE,            /* iInitialised    */

    { 0 },                  /* pulStatCounters */
    { 0 },                  /* pulErrorCounters */

    EMMC_LOWER_FIREWALL     /* ulLowerFirewall */
};
static FW_IF_EMMC_PRIVATE_DATA *pxThis = &xLocalData;


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
static uint32_t ulEmmcOpen( void *pvFwIf );

/**
 * @brief   Local implementation of FW_IF_close
 *
 * @param   pvFwIf          Pointer to this fw_if
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulEmmcClose( void *pvFwIf );

/**
 * @brief   Local implementation of FW_IF_write
 *
 * @param   pvFwIf          Pointer to this fw_if
 * @param   ullAddrOffset   The address offset from the start address specified in the create
 * @param   pucData         Data buffer to write
 * @param   ulLength        Number of bytes in data buffer
 * @param   ulTimeoutMs     Time (in ms) to wait for write to complete
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulEmmcWrite( void *pvFwIf,
                             uint64_t ullAddrOffset,
                             uint8_t *pucData,
                             uint32_t ulLength,
                             uint32_t ulTimeoutMs );

/**
 * @brief   Local implementation of FW_IF_read
 *
 * @param   pvFwIf          Pointer to this fw_if
 * @param   ullAddrOffset   The address offset from the start address specified in the create
 * @param   pucData         Data buffer to read
 * @param   pulLength       Pointer to maximum number of bytes allowed in data buffer
 *                          This value is updated to the actual number of bytes read
 * @param   ulTimeoutMs     Time (in ms) to wait for read to complete
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulEmmcRead( void *pvFwIf,
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
static uint32_t ulEmmcIoCtrl( void *pvFwIf, uint32_t ulOption, void *pvValue );

/**
 * @brief   Local implementation of FW_IF_bindCallback
 *
 * @param   pvFwIf          Pointer to this fw_if
 * @param   pxNewFunc       Function pointer to call
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulEmmcBindCallback( void *pvFwIf, FW_IF_callback *pxNewFunc );

/**
 * @brief   Validate the read/write access address is in range
 *
 * @param   pxCfg           The interface config options
 * @param   ullAddrOffset   The address offset from the base address specified in the create
 * @param   ulLength        Number of bytes in data buffer
 *
 * @return  See FW_IF_ERRORS
 */
static uint32_t ulValidateAddressRange( FW_IF_EMMC_CFG *pxCfg, uint64_t ullAddrOffset, uint32_t ulLength );


/*****************************************************************************/
/* local functions                                                           */
/*****************************************************************************/

/**
 * @brief   Local implementation of FW_IF_open
 */
static uint32_t ulEmmcOpen( void *pvFwIf )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );    
    CHECK_DRIVER;

    FW_IF_EMMC_CFG *pxCfg = ( FW_IF_EMMC_CFG* )pxThisIf->cfg;

    if( FW_IF_EMMC_STATE_CREATED == pxCfg->xState )
    {
        pxCfg->xState = FW_IF_EMMC_STATE_OPENED;
        INC_STAT_COUNTER( FW_IF_EMMC_STATS_OPEN )
    }
    else
    {
        ulStatus = FW_IF_EMMC_ERRORS_INVALID_STATE;
        INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_OPEN_FAILED )
        PLL_ERR( FW_IF_EMMC_NAME, "Open() should only be called from created state\r\n" );
    }

    return ulStatus;
}

/**
 * @brief   Local implementation of FW_IF_close
 */
static uint32_t ulEmmcClose( void *pvFwIf )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );    
    CHECK_DRIVER;

    FW_IF_EMMC_CFG *pxCfg = ( FW_IF_EMMC_CFG* )pxThisIf->cfg;

    if( FW_IF_EMMC_STATE_OPENED == pxCfg->xState )
    {
        pxCfg->xState = FW_IF_EMMC_STATE_CLOSED;
        INC_STAT_COUNTER( FW_IF_EMMC_STATS_CLOSE )
    }
    else
    {
        ulStatus = FW_IF_EMMC_ERRORS_INVALID_STATE;
        INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_CLOSE_FAILED )
        PLL_ERR( FW_IF_EMMC_NAME, "Close() should only be called from opened state\r\n" );
    }

    return ulStatus;
}

/**
 * @brief   Local implementation of FW_IF_write
 */
static uint32_t ulEmmcWrite( void *pvFwIf,
                             uint64_t ullAddrOffset,
                             uint8_t *pucData,
                             uint32_t ulLength,
                             uint32_t ulTimeoutMs )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );    
    CHECK_DRIVER;

    if( NULL != pucData )
    {   
        FW_IF_EMMC_CFG *pxCfg = ( FW_IF_EMMC_CFG* )pxThisIf->cfg;

        if( FW_IF_EMMC_STATE_OPENED == pxCfg->xState )
        {
            uint64_t ullAddr = pxCfg->ullBaseAddress + ullAddrOffset;
            ulStatus = ulValidateAddressRange( pxCfg, ullAddr, ulLength );

            if( FW_IF_ERRORS_NONE == ulStatus )
            {
                uint32_t ulTotalBytesWritten = 0;
                uint32_t ulBytesToWrite = ulLength;
                uint64_t ullAddrBlockOffset = ullAddr % HAL_EMMC_BLOCK_SIZE;
                int iReadStatus = ERROR;
                int iWriteStatus = ERROR;

                /*
                 * The implementation of eMMC FW_IF_write for AMC will be a multi-step process,
                 * due to the eMMC driver requiring read/write commands to be block aligned.
                 */

                /*
                 * Step 1: Handle the address offset, if not block aligned.
                 *         This will require reading the first full eMMC block into a temp array, 
                 *         copying the required data from the address offset into this array, 
                 *         and re-writting this first full block.
                 */
                if( 0 != ullAddrBlockOffset )
                {
                    /* create temp buffer for first block */
                    uint8_t pucFirstBlockData[ HAL_EMMC_BLOCK_SIZE ] = { 0 };

                    /* update addr to start of block */
                    ullAddr = ullAddr - ullAddrBlockOffset;

                    /* read first full block into temp buffer */
                    iReadStatus = iEMMC_Read( ullAddr, 1, pucFirstBlockData );

                    if( OK == iReadStatus )
                    {
                        /* Set required bytes to write */
                        ulBytesToWrite = ( ulLength < ( HAL_EMMC_BLOCK_SIZE - ullAddrBlockOffset ) ) ? ( ulLength ):( HAL_EMMC_BLOCK_SIZE - ullAddrBlockOffset );
                        /* copy required data for first block into temp buffer */
                        pvOSAL_MemCpy( &pucFirstBlockData[ ullAddrBlockOffset ], &pucData[ ulTotalBytesWritten ], ulBytesToWrite );

                        /* re-write first full block */
                        iWriteStatus = iEMMC_Write( ullAddr, 1, pucFirstBlockData );

                        if( OK == iWriteStatus )
                        {
                            /* update counts */
                            ulTotalBytesWritten += ulBytesToWrite;
                            ulBytesToWrite = ulLength - ulTotalBytesWritten;   

                            /* set addr to start of next block */
                            ullAddr = ullAddr + HAL_EMMC_BLOCK_SIZE;
                        }
                    }
                }
                else
                {
                    iWriteStatus = OK;
                }

                if( ( OK == iWriteStatus ) && ( ulTotalBytesWritten < ulLength ) )
                {
                    uint32_t ulCurrentBytesWritten = 0;
                    uint32_t ulBlockCount = ( ulBytesToWrite / HAL_EMMC_BLOCK_SIZE ); /* calc minimum eMMC block count */
                    
                    /*
                     * Step 2: Write as many full blocks as possible, directly from pucData
                     */
                    if( 0 < ulBlockCount )
                    {   
                        iWriteStatus = iEMMC_Write( ullAddr, ulBlockCount, &pucData[ ulTotalBytesWritten ] );

                        if( OK == iWriteStatus )
                        {
                            /* update counts */
                            ulCurrentBytesWritten = ( ulBlockCount * HAL_EMMC_BLOCK_SIZE );
                            ulTotalBytesWritten = ulTotalBytesWritten + ulCurrentBytesWritten;
                            ulBytesToWrite = ulBytesToWrite - ulTotalBytesWritten;
                        }
                    }

                    /*
                     * Step 3: Handle any remaining bytes (not block aligned) 
                     *         This will require reading a final full eMMC block into a temp array, 
                     *         copying the required data for the last block into this array, 
                     *         and re-writting this final full block.
                     */
                    if( ( OK == iWriteStatus ) && 
                        ( 0 != ulBytesToWrite % HAL_EMMC_BLOCK_SIZE ) )
                    {
                        /* create temp buffer for final block */
                        uint8_t pucFinalBlockData[ HAL_EMMC_BLOCK_SIZE ] = { 0 };

                        /* update addr to end of last read block */
                        ullAddr = ullAddr + ( uint64_t )ulCurrentBytesWritten;

                        /* read final block into temp buffer */
                        iReadStatus = iEMMC_Read( ullAddr, 1, pucFinalBlockData );

                        if( OK == iReadStatus )
                        {
                            /* copy required data for last block into temp buffer */
                            pvOSAL_MemCpy( &pucFinalBlockData[ 0 ], &pucData[ ulTotalBytesWritten ], ulBytesToWrite );

                            /* re-write last full block */
                            iWriteStatus = iEMMC_Write( ullAddr, 1, pucFinalBlockData );
                            ulTotalBytesWritten = ulTotalBytesWritten + ulBytesToWrite;
                        }
                    }
                }

                if( OK == iWriteStatus )
                {
                    INC_STAT_COUNTER( FW_IF_EMMC_STATS_WRITE )
                }
                else
                {
                    ulStatus = FW_IF_ERRORS_WRITE;
                    INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_WRITE_FAILED )
                }
            }
        }
        else
        {
            ulStatus = FW_IF_EMMC_ERRORS_INVALID_STATE;
            INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_WRITE_FAILED )
            PLL_ERR( FW_IF_EMMC_NAME, "Write() should only be called from opened state\r\n" );
        }
    }
    else
    {
        ulStatus = FW_IF_ERRORS_PARAMS;
    }

    return ulStatus;
}

/**
 * @brief   Local implementation of FW_IF_read
 */
static uint32_t ulEmmcRead( void *pvFwIf,
                            uint64_t ullAddrOffset,
                            uint8_t *pucData,
                            uint32_t *pulLength,
                            uint32_t ulTimeoutMs )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );    
    CHECK_DRIVER;

    if( ( NULL != pucData ) && ( NULL != pulLength ) && ( 0 != *pulLength ) )
    {   
        FW_IF_EMMC_CFG *pxCfg = ( FW_IF_EMMC_CFG* )pxThisIf->cfg;

        if( FW_IF_EMMC_STATE_OPENED == pxCfg->xState )
        {
            uint64_t ullAddr = pxCfg->ullBaseAddress + ullAddrOffset;
            ulStatus = ulValidateAddressRange( pxCfg, ullAddr, *pulLength );

            if( FW_IF_ERRORS_NONE == ulStatus )
            {
                uint32_t ulTotalBytesRead = 0;
                uint32_t ulBytesToRead = *pulLength;
                uint64_t ullAddrBlockOffset = ullAddr % HAL_EMMC_BLOCK_SIZE;
                int iReadStatus = ERROR;

                /*
                 * The implementation of eMMC FW_IF_read for AMC will be a multi-step process,
                 * due to the eMMC driver requiring read commands to be block aligned.
                 */

                /*
                 * Step 1: Handle the address offset, if not block aligned.
                 *         This will require reading the first full eMMC block into a temp array, 
                 *         and copying back only the required data.
                 */
                if( 0 != ullAddrBlockOffset )
                {
                    /* create temp buffer for first block */
                    uint8_t pucFirstBlockData[ HAL_EMMC_BLOCK_SIZE ] = { 0 };

                    /* update addr to start of block */
                    ullAddr = ullAddr - ullAddrBlockOffset;

                    /* read first full block into temp buffer */
                    iReadStatus = iEMMC_Read( ullAddr, 1, pucFirstBlockData );

                    if( OK == iReadStatus )
                    {
                        /* Set required bytes to read */
                        ulBytesToRead = ( *pulLength < ( HAL_EMMC_BLOCK_SIZE - ullAddrBlockOffset ) ) ? ( *pulLength ):( HAL_EMMC_BLOCK_SIZE - ullAddrBlockOffset );
                        pvOSAL_MemCpy( &pucData[ ulTotalBytesRead ], &pucFirstBlockData[ ullAddrBlockOffset ], ulBytesToRead );

                        /* update counts */
                        ulTotalBytesRead += ulBytesToRead;
                        ulBytesToRead = *pulLength - ulTotalBytesRead;

                        /* set addr to start of next block */
                        ullAddr = ullAddr + HAL_EMMC_BLOCK_SIZE;
                    }
                }
                else
                {
                    iReadStatus = OK;
                }

                if( ( OK == iReadStatus ) && ( ulTotalBytesRead < *pulLength ) )
                {
                    uint32_t ulCurrentBytesRead = 0;
                    uint32_t ulBlockCount = ( ulBytesToRead / HAL_EMMC_BLOCK_SIZE ); /* calc minimum eMMC block count */

                    /*
                     * Step 2: Read as many full blocks as possible, directly into pucData
                     */
                    if( 0 < ulBlockCount )
                    {
                        iReadStatus = iEMMC_Read( ullAddr, ulBlockCount, &pucData[ ulTotalBytesRead ] );

                        if( OK == iReadStatus )
                        {
                            /* update counts */
                            ulCurrentBytesRead = ( ulBlockCount * HAL_EMMC_BLOCK_SIZE );
                            ulTotalBytesRead = ulTotalBytesRead + ulCurrentBytesRead;
                            ulBytesToRead = ulBytesToRead - ulTotalBytesRead;
                        }
                    }

                    /*
                     * Step 3: Handle any remaining bytes (not block aligned) 
                     *         This will require reading a final full eMMC block into a temp array, 
                     *         and copying back the required final bytes.
                     */
                    if( ( OK == iReadStatus ) &&
                        ( 0 != ulBytesToRead % HAL_EMMC_BLOCK_SIZE ) )
                    {
                        /* create temp buffer for final block */
                        uint8_t pucFinalBlockData[ HAL_EMMC_BLOCK_SIZE ] = { 0 };

                        /* update addr to end of last read block */
                        ullAddr = ullAddr + ( uint64_t )ulCurrentBytesRead;

                        /* read final block into temp buffer */
                        iReadStatus = iEMMC_Read( ullAddr, 1, pucFinalBlockData );

                        /* only copy back the required data */
                        pvOSAL_MemCpy( &pucData[ ulTotalBytesRead ], &pucFinalBlockData[ 0 ], ulBytesToRead );
                        ulTotalBytesRead = ulTotalBytesRead + ulBytesToRead;
                    }
                }

                if( OK == iReadStatus )
                {
                    *pulLength = ulTotalBytesRead;
                    INC_STAT_COUNTER( FW_IF_EMMC_STATS_READ )
                }
                else
                {
                    *pulLength = 0;
                    ulStatus = FW_IF_ERRORS_READ;
                    INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_READ_FAILED )
                }
            }
        }
        else
        {
            ulStatus = FW_IF_EMMC_ERRORS_INVALID_STATE;
            INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_READ_FAILED )
            PLL_ERR( FW_IF_EMMC_NAME, "Read() should only be called from opened state\r\n" );
        }
    }
    else
    {
        ulStatus = FW_IF_ERRORS_PARAMS;
    }

    return ulStatus;
}

/**
 * @brief   Local implementation of FW_IF_ioctrl
 */
static uint32_t ulEmmcIoCtrl( void *pvFwIf, uint32_t ulOption, void *pvValue )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );    
    CHECK_DRIVER;

    FW_IF_EMMC_CFG *pxCfg = ( FW_IF_EMMC_CFG* )pxThisIf->cfg;

    if( FW_IF_EMMC_STATE_OPENED == pxCfg->xState )
    {
        switch( ulOption )
        {
            case FW_IF_COMMON_IOCTRL_FLUSH_TX:
            case FW_IF_COMMON_IOCTRL_FLUSH_RX:
            case FW_IF_COMMON_IOCTRL_GET_RX_MODE:
                /*
                * Handle common IOCTL's.
                */
                break;

            case FW_IF_EMMC_IOCTRL_PRINT_INSTANCE_DETAILS:
            {
                if( OK != iEMMC_PrintInstanceDetails() )
                {
                    ulStatus = FW_IF_ERRORS_IOCTRL;
                    INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_IO_CTRL_FAILED )
                }
                break;
            }

            case FW_IF_EMMC_IOCTRL_ERASE_ALL:
            {
                if( OK != iEMMC_EraseAll() )
                {
                    ulStatus = FW_IF_ERRORS_IOCTRL;
                    INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_IO_CTRL_FAILED )
                }
                break;
            }
            
            default:
                ulStatus = FW_IF_ERRORS_UNRECOGNISED_OPTION;
                break;
        }

        if( FW_IF_ERRORS_NONE == ulStatus )
        {
            INC_STAT_COUNTER( FW_IF_EMMC_STATS_IO_CTRL )
            PLL_DBG( FW_IF_EMMC_NAME, "FW_IF_ioctrl for if.%u (%s), (option %u)\r\n",
                    ( unsigned int )pxCfg->ulIfId,
                    pxCfg->pcIfName,
                    ( unsigned int )ulOption );
        }
    }
    else
    {
        ulStatus = FW_IF_EMMC_ERRORS_INVALID_STATE;
        INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_IO_CTRL_FAILED )
        PLL_ERR( FW_IF_EMMC_NAME, "ioctrl() should only be called from opened state\r\n" );
    }

    return ulStatus;
}

/**
 * @brief   Local implementation of FW_IF_bindCallback
 */
static uint32_t ulEmmcBindCallback( void *pvFwIf, FW_IF_callback *pxNewFunc )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );    
    CHECK_DRIVER;

    if( NULL != pxNewFunc )
    {   
        /*
         * Binds in callback provided to the FW_IF.
         * Callback will be invoked when by the driver when event occurs.
         */
        FW_IF_EMMC_CFG *pxCfg = ( FW_IF_EMMC_CFG* )pxThisIf->cfg;
        pxThisIf->raiseEvent = pxNewFunc;
    
        PLL_DBG( FW_IF_EMMC_NAME, "FW_IF_bindCallback called for if.%u (%s)\r\n",
                 ( unsigned int )pxCfg->ulIfId,
                 pxCfg->pcIfName );
    }
    else
    {
        ulStatus = FW_IF_ERRORS_PARAMS;
    }

    return ulStatus;
}

/**
 * @brief   Validate the read/write access address is in range
 */
static uint32_t ulValidateAddressRange( FW_IF_EMMC_CFG *pxCfg, uint64_t ullAddrOffset, uint32_t ulLength )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    if( NULL != pxCfg )
    {
        /*
         * Test the offset plus the length is less than the total length
         */
        if( ( ullAddrOffset + ( uint64_t )ulLength ) >= pxCfg->ullLength )
        {
            ulStatus = FW_IF_EMMC_ERRORS_DRIVER_INVALID_ADDRESS;
        }
    }
    else
    {
        ulStatus = FW_IF_ERRORS_PARAMS;
    }

    return ulStatus;
}


/*****************************************************************************/
/* public functions                                                          */
/*****************************************************************************/

/**
 * @brief   initialisation function for EMMC interfaces (generic across all EMMC interfaces)
 */
uint32_t ulFW_IF_EMMC_Init( FW_IF_EMMC_INIT_CFG *pxInitCfg )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    if( FW_IF_FALSE != pxThis->iInitialised )
    {
        ulStatus = FW_IF_ERRORS_DRIVER_IN_USE;
    }
    else if ( NULL == pxInitCfg )
    {
        ulStatus = FW_IF_ERRORS_PARAMS;
    }
    else
    {
        /*
         * Initilise config data shared between all instances of EMMC.
         */
        pvOSAL_MemCpy( &pxThis->xLocalCfg, pxInitCfg, sizeof( pxThis->xLocalCfg ) );

        /*
         * Initialise the driver based on the device id supplied in the cfg
         */
        ulStatus = iEMMC_Initialise( pxThis->xLocalCfg.usDeviceId );
        if( OK != ulStatus )
        {
            ulStatus = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
            INC_ERROR_COUNTER( FW_IF_EMMC_STATS_INIT_OVERALL_FAILED )
        }
        else
        {
            PLL_DBG( FW_IF_EMMC_NAME, "ulFW_IF_EMMC_Init for driver (%s)\r\n",
            pxThis->xLocalCfg.pcDriverName );
            pxThis->iInitialised = FW_IF_TRUE;
            INC_STAT_COUNTER( FW_IF_EMMC_STATS_INIT_OVERALL_COMPLETE )
        }
    }

    return ulStatus;
}

/**
 * @brief   opens an instance of the EMMC interface
 */
uint32_t ulFW_IF_EMMC_Create( FW_IF_CFG *pxFwIf, FW_IF_EMMC_CFG *pxEmmcCfg )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    CHECK_DRIVER;

    if( ( NULL != pxFwIf ) && ( NULL != pxEmmcCfg ) )
    {
        FW_IF_CFG myLocalIf =
        {
            .upperFirewall  = EMMC_UPPER_FIREWALL,
            .open           = &ulEmmcOpen,
            .close          = &ulEmmcClose,
            .write          = &ulEmmcWrite,
            .read           = &ulEmmcRead,
            .ioctrl         = &ulEmmcIoCtrl,
            .bindCallback   = &ulEmmcBindCallback,
            .cfg            = ( void* )pxEmmcCfg,
            .lowerFirewall  = EMMC_LOWER_FIREWALL
        };

        pvOSAL_MemCpy( pxFwIf, &myLocalIf, sizeof( *pxFwIf ) );

        FW_IF_EMMC_CFG *pxCfg = ( FW_IF_EMMC_CFG* )pxFwIf->cfg;

        PLL_DBG( FW_IF_EMMC_NAME, "ulFW_IF_EMMC_Create for if.%u (%s)\r\n",
                 ( unsigned int )pxCfg->ulIfId,
                 pxCfg->pcIfName );

        /* Configuration options, base address will the RPU/APU or SC address within the flash device */
        PLL_DBG( FW_IF_EMMC_NAME, "Start Address: 0x%llx\r\n", pxCfg->ullBaseAddress );
        PLL_DBG( FW_IF_EMMC_NAME, "Length: 0x%llx\r\n", pxCfg->ullLength );

        pxCfg->xState = FW_IF_EMMC_STATE_CREATED;
        INC_STAT_COUNTER( FW_IF_EMMC_STATS_INSTANCE_CREATE )
    }
    else
    {
        ulStatus = FW_IF_ERRORS_PARAMS;
        INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_INSTANCE_CREATE_FAILED )
    }
        
    return ulStatus;
}

/**
 * @brief   Print all the stats gathered by the interface
 */
int iFW_IF_EMMC_PrintStatistics( void )
{
    int iStatus = FW_IF_ERRORS_NONE;

    if( ( EMMC_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( EMMC_LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FW_IF_TRUE == pxThis->iInitialised ) )
    {
        int i = 0;
        PLL_INF( FW_IF_EMMC_NAME, "============================================================\n\r" );
        PLL_INF( FW_IF_EMMC_NAME, "FWIF EMMC Statistics:\n\r" );
        for( i = 0; i < FW_IF_EMMC_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( FW_IF_EMMC_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( FW_IF_EMMC_NAME, "FWIF EMMC Errors:\n\r" );
        for( i = 0; i < FW_IF_EMMC_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( FW_IF_EMMC_NAME, "============================================================\n\r" );
    }
    else
    {
        INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_VALIDATION_FAILED )
        iStatus = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
    }

    return iStatus;
}

/**
 *  @brief Clears all the stats gathered by the interface
*/
int iFW_IF_EMMC_ClearStatistics( void )
{
    int iStatus = FW_IF_ERRORS_NONE;

    if( ( EMMC_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( EMMC_LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        pvOSAL_MemSet( pxThis->pulStatCounters, 0, sizeof( pxThis->pulStatCounters ) );
        pvOSAL_MemSet( pxThis->pulErrorCounters, 0, sizeof( pxThis->pulErrorCounters ) );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( FW_IF_EMMC_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

