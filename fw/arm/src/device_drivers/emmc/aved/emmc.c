/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the user API definitions for the EMMC driver.
 *
 * @file emmc.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <stdio.h>
#include <stdlib.h>

#include "util.h"
#include "pll.h"
#include "osal.h"
#include "emmc.h"
#include "profile_hal.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL                          ( 0xBABECAFE )
#define LOWER_FIREWALL                          ( 0xDEADFACE )

#define EMMC_NAME                               "EMMC"
#define EMMC_WAIT_TIMEOUT_MS                    ( 100 )
#define EMMC_BLOCK_BITSHIFT                     ( 9 )
#define EMMC_ERASE_BLOCK_INCREMENT              ( 0x800000 )
#define EMMC_ERASE_BLOCK_INCREMENT_MINUS_ONE    ( EMMC_ERASE_BLOCK_INCREMENT - 1 )
#define EMMC_FINAL_BLOCK                        ( HAL_EMMC_MAX_BLOCKS - 1 )

/* Stat & Error definitions */
#define EMMC_STATS( DO )                                     \
    DO( EMMC_STATS_INIT_COMPLETED )                          \
    DO( EMMC_STATS_CREATE_MUTEX )                            \
    DO( EMMC_STATS_TAKE_MUTEX )                              \
    DO( EMMC_STATS_RELEASE_MUTEX )                           \
    DO( EMMC_STATS_EMMC_READ )                               \
    DO( EMMC_STATS_EMMC_WRITE )                              \
    DO( EMMC_STATS_EMMC_ERASE )                              \
    DO( EMMC_STATS_MAX )

#define EMMC_ERRORS( DO )                                    \
    DO( EMMC_ERRORS_VALIDATION_FAILED )                      \
    DO( EMMC_ERRORS_XSDPS_CFGINITIALIZE_FAILED )             \
    DO( EMMC_ERRORS_XSDPS_CARDINIIALIZE_FAILED )             \
    DO( EMMC_ERRORS_MUTEX_CREATE_FAILED )                    \
    DO( EMMC_ERRORS_MUTEX_RELEASE_FAILED )                   \
    DO( EMMC_ERRORS_MUTEX_TAKE_FAILED )                      \
    DO( EMMC_ERRORS_EMMC_READ_FAILED )                       \
    DO( EMMC_ERRORS_EMMC_WRITE_FAILED )                      \
    DO( EMMC_ERRORS_EMMC_ERASE_FAILED )                      \
    DO( EMMC_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )         PLL_INF( EMMC_NAME, "%50s . . . . %d\r\n",          \
                                                 EMMC_STATS_STR[ x ],                       \
                                                 pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x )        PLL_INF( EMMC_NAME, "%50s . . . . %d\r\n",          \
                                                 EMMC_ERRORS_STR[ x ],                      \
                                                 pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )           { if( x < EMMC_STATS_MAX )pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x )          { if( x < EMMC_ERRORS_MAX )pxThis->pulErrorCounters[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    EMMC_STATS
 * @brief   Enumeration of stats counters for this driver
 */
UTIL_MAKE_ENUM_AND_STRINGS( EMMC_STATS, EMMC_STATS, EMMC_STATS_STR )

/**
 * @enum    EMMC_ERRORS
 * @brief   Enumeration of stats errors for this driver
 */
UTIL_MAKE_ENUM_AND_STRINGS( EMMC_ERRORS, EMMC_ERRORS, EMMC_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  EMMC_PRIVATE_DATA
 * @brief   Structure to hold ths driver's private data
 */
typedef struct EMMC_PRIVATE_DATA
{
    uint32_t        ulUpperFirewall;

    uint16_t        ucDeviceId;
    XSdPs           xSdInstance;
    XSdPs_Config    *pxEmmcConfig;
    int             iInitialised;

    void            *pvOsalMutexHdl;

    uint32_t        pulStatCounters[ EMMC_STATS_MAX ];
    uint32_t        pulErrorCounters[ EMMC_ERRORS_MAX ];

    uint32_t        ulLowerFirewall;

} EMMC_PRIVATE_DATA;


/******************************************************************************/
/* Local Variables                                                            */
/******************************************************************************/

static EMMC_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                         /* ulUpperFirewall */
    0,                                      /* ucDeviceId */
    { { 0 } },                              /* xSdInstance */
    NULL,                                   /* pxEmmcConfig */
    FALSE,                                  /* iInitialised */
    NULL,                                   /* pvOsalMutexHdl */
    { 0 },                                  /* pulStatCounters */
    { 0 },                                  /* pulErrorCounters */
    LOWER_FIREWALL                          /* ulLowerFirewall */
};
static EMMC_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Private Function declarations                                              */
/******************************************************************************/

/**
 * @brief   Check the parameters are valid
 *
 * @param   ullBlockAddress    The address of the initial block
 * @param   ulBlockCount       The total number of blocks
 *
 * @return  OK                 The parameters are valid
 *          ERROR              The parameters are not valid
 */
static int iValidateBlockCount( uint64_t ullBlockAddress, uint32_t ulBlockCount );


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/**
 * @brief   Initializes the EMMC driver.
 */
int iEMMC_Initialise( uint16_t ucDeviceId )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) )
    {
        pxThis->ucDeviceId = ucDeviceId;
        pxThis->pxEmmcConfig = XSdPs_LookupConfig( ucDeviceId );

        if ( NULL != pxThis->pxEmmcConfig )
        {
            iStatus = XSdPs_CfgInitialize( &( pxThis->xSdInstance ), pxThis->pxEmmcConfig,
                                            pxThis->pxEmmcConfig->BaseAddress );
        }

        if( OK == iStatus )
        {
            iStatus = XSdPs_CardInitialize( &( pxThis->xSdInstance ) );

            if( OK != iStatus )
            {
                PLL_ERR( EMMC_NAME, "Error XSdPs_CardInitialize( ) failed: %d\r\n", iStatus );
                INC_ERROR_COUNTER( EMMC_ERRORS_XSDPS_CARDINIIALIZE_FAILED )
            }
        }
        else
        {
            PLL_ERR( EMMC_NAME, "Error XSdPs_CfgInitialize( ) failed: %d\r\n", iStatus );
            INC_ERROR_COUNTER( EMMC_ERRORS_XSDPS_CFGINITIALIZE_FAILED )
        }

        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &( pxThis->pvOsalMutexHdl ),
                                                    "EMMC mutex" ) )
        {
            PLL_ERR( EMMC_NAME, "Error initialising mutex\r\n" );
            INC_ERROR_COUNTER( EMMC_ERRORS_MUTEX_CREATE_FAILED )
            iStatus = ERROR;
        }
        else
        {
            INC_STAT_COUNTER( EMMC_STATS_CREATE_MUTEX )
        }

        if( OK == iStatus )
        {
            pxThis->iInitialised = TRUE;
            INC_STAT_COUNTER( EMMC_STATS_INIT_COMPLETED )
        }

    }
    else
    {
        INC_ERROR_COUNTER( EMMC_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Read from the EMMC.
 */
int iEMMC_Read( uint64_t ullAddress, uint32_t ulBlockCount , uint8_t *pucReadBuff )
{
    int iStatus = ERROR;

    if( ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucReadBuff ) &&
        ( OK == iValidateBlockCount( ullAddress, ulBlockCount ) ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  EMMC_WAIT_TIMEOUT_MS ) )
        {
            INC_STAT_COUNTER( EMMC_STATS_TAKE_MUTEX )

            uint32_t ulBlockAddress = ullAddress >> EMMC_BLOCK_BITSHIFT;

            iStatus = XSdPs_ReadPolled( &( pxThis->xSdInstance ), ulBlockAddress, ulBlockCount, pucReadBuff );
            if( OK == iStatus )
            {
                INC_STAT_COUNTER( EMMC_STATS_EMMC_READ )
            }
            else
            {
                INC_ERROR_COUNTER( EMMC_ERRORS_EMMC_READ_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER( EMMC_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( EMMC_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER( EMMC_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    return iStatus;
}

/**
 * @brief   Write to the EMMC.
 */
int iEMMC_Write( uint64_t ullAddress, uint32_t ulBlockCount , const uint8_t *pucWriteBuff )
{
    int iStatus = ERROR;

    if( ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucWriteBuff ) &&
        ( OK == iValidateBlockCount( ullAddress, ulBlockCount ) ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  EMMC_WAIT_TIMEOUT_MS ) )
        {
            INC_STAT_COUNTER( EMMC_STATS_TAKE_MUTEX )

            uint32_t ulBlockAddress = ullAddress >> EMMC_BLOCK_BITSHIFT;

            iStatus = XSdPs_WritePolled( &( pxThis->xSdInstance ), ulBlockAddress, ulBlockCount, pucWriteBuff );
            if( OK == iStatus )
            {
                INC_STAT_COUNTER( EMMC_STATS_EMMC_WRITE )
            }
            else
            {
                INC_ERROR_COUNTER( EMMC_ERRORS_EMMC_WRITE_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER( EMMC_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( EMMC_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER( EMMC_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    return iStatus;
}


/**
 * @brief   Erase blocks in the EMMC.
 */
int iEMMC_Erase( uint64_t ullStartBlockAddress, uint64_t ullEndBlockAddress )
{
    int iStatus = ERROR;

    if( ( TRUE == pxThis->iInitialised ) &&
        ( 0 == ( ullStartBlockAddress % pxThis->xSdInstance.BlkSize ) ) &&
        ( 0 == ( ullEndBlockAddress % pxThis->xSdInstance.BlkSize ) ) &&
        ( pxThis->xSdInstance.BlkSize > ( ullStartBlockAddress >> EMMC_BLOCK_BITSHIFT ) ) &&
        ( pxThis->xSdInstance.BlkSize > ( ullEndBlockAddress >> EMMC_BLOCK_BITSHIFT ) ) &&
        ( ullEndBlockAddress >= ullStartBlockAddress ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  EMMC_WAIT_TIMEOUT_MS ) )
        {
            INC_STAT_COUNTER( EMMC_STATS_TAKE_MUTEX )

            uint32_t ulStartBlock = ( ullStartBlockAddress >> EMMC_BLOCK_BITSHIFT );
            uint32_t ulEndBlock = ( ullEndBlockAddress >> EMMC_BLOCK_BITSHIFT );

            iStatus = XSdPs_Erase( &( pxThis->xSdInstance ), ulStartBlock, ulEndBlock );
            if( OK == iStatus )
            {
                INC_STAT_COUNTER( EMMC_STATS_EMMC_ERASE )
            }
            else
            {
                INC_ERROR_COUNTER( EMMC_ERRORS_EMMC_ERASE_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER( EMMC_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( EMMC_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER( EMMC_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    return iStatus;
}

/**
 * @brief   Erase all blocks in the EMMC.
 */
int iEMMC_EraseAll( void )
{
    int iStatus = ERROR;

    if( TRUE == pxThis->iInitialised )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  EMMC_WAIT_TIMEOUT_MS ) )
        {
            uint32_t ulStartBlock = 0;
            uint32_t ulEndBlock = 0;

            INC_STAT_COUNTER( EMMC_STATS_TAKE_MUTEX )

            for( ulStartBlock = 0; ulStartBlock < HAL_EMMC_MAX_BLOCKS; ulStartBlock += EMMC_ERASE_BLOCK_INCREMENT )
            {
                ulEndBlock = ulStartBlock + EMMC_ERASE_BLOCK_INCREMENT_MINUS_ONE;
                if( HAL_EMMC_MAX_BLOCKS <= ulEndBlock )
                {
                    ulEndBlock = EMMC_FINAL_BLOCK;
                }

                iStatus = XSdPs_Erase( &( pxThis->xSdInstance ), ulStartBlock, ulEndBlock );
                if( OK == iStatus )
                {
                    INC_STAT_COUNTER( EMMC_STATS_EMMC_ERASE )
                }
                else
                {
                    INC_ERROR_COUNTER( EMMC_ERRORS_EMMC_ERASE_FAILED )
                    break;
                }
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER( EMMC_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( EMMC_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER( EMMC_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    return iStatus;
}

/**
 * @brief   Print the EMMC detected device details.
 */
int iEMMC_PrintInstanceDetails( void )
{
    int iStatus = ERROR;

    if( TRUE == pxThis->iInitialised )
    {
        PLL_LOG( EMMC_NAME, "CONFIG:\n\r" );
        PLL_LOG( EMMC_NAME, "DeviceId:              0x%x\n\r", pxThis->pxEmmcConfig->DeviceId );
        PLL_LOG( EMMC_NAME, "BaseAddress:           0x%x\n\r", pxThis->pxEmmcConfig->BaseAddress );
        PLL_LOG( EMMC_NAME, "InputClockHz:          0x%x\n\r", pxThis->pxEmmcConfig->InputClockHz );
        PLL_LOG( EMMC_NAME, "CardDetect:            0x%x\n\r", pxThis->pxEmmcConfig->CardDetect );
        PLL_LOG( EMMC_NAME, "WriteProtect:          0x%x\n\r", pxThis->pxEmmcConfig->WriteProtect );
        PLL_LOG( EMMC_NAME, "BusWidth:              0x%x\n\r", pxThis->pxEmmcConfig->BusWidth );
        PLL_LOG( EMMC_NAME, "BankNumber:            0x%x\n\r", pxThis->pxEmmcConfig->BankNumber );
        PLL_LOG( EMMC_NAME, "HasEMIO:               0x%x\n\r", pxThis->pxEmmcConfig->HasEMIO );
        PLL_LOG( EMMC_NAME, "SlotType:              0x%x\n\r", pxThis->pxEmmcConfig->SlotType );
        PLL_LOG( EMMC_NAME, "IsCacheCoherent:       0x%x\n\r", pxThis->pxEmmcConfig->IsCacheCoherent );
        PLL_LOG( EMMC_NAME, "ITapDly_SDR_Clk50:     0x%x\n\r", pxThis->pxEmmcConfig->ITapDly_SDR_Clk50 );
        PLL_LOG( EMMC_NAME, "OTapDly_SDR_Clk50:     0x%x\n\r", pxThis->pxEmmcConfig->OTapDly_SDR_Clk50 );
        PLL_LOG( EMMC_NAME, "ITapDly_DDR_Clk50:     0x%x\n\r", pxThis->pxEmmcConfig->ITapDly_DDR_Clk50 );
        PLL_LOG( EMMC_NAME, "OTapDly_DDR_Clk50:     0x%x\n\r", pxThis->pxEmmcConfig->OTapDly_DDR_Clk50 );
        PLL_LOG( EMMC_NAME, "OTapDly_SDR_Clk100:    0x%x\n\r", pxThis->pxEmmcConfig->OTapDly_SDR_Clk100 );
        PLL_LOG( EMMC_NAME, "OTapDly_SDR_Clk200:    0x%x\n\r\n\r",
                                                               pxThis->pxEmmcConfig->OTapDly_SDR_Clk200 );

        PLL_LOG( EMMC_NAME, "INSTANCE:\n\r" );
        PLL_LOG( EMMC_NAME, "IsReady:               0x%x\n\r", pxThis->xSdInstance.IsReady );       /**< Device is initialized and ready */
        PLL_LOG( EMMC_NAME, "Host_Caps:             0x%x\n\r", pxThis->xSdInstance.Host_Caps );     /**< Capabilities of host controller */
        PLL_LOG( EMMC_NAME, "Host_CapsExt:          0x%x\n\r", pxThis->xSdInstance.Host_CapsExt );  /**< Extended Capabilities */
        PLL_LOG( EMMC_NAME, "HCS:                   0x%x\n\r", pxThis->xSdInstance.HCS );           /**< High capacity support in card */
        PLL_LOG( EMMC_NAME, "CardType:              0x%x\n\r", pxThis->xSdInstance.CardType );      /**< Type of card - SD/MMC/eMMC */
        PLL_LOG( EMMC_NAME, "Card_Version:          0x%x\n\r", pxThis->xSdInstance.Card_Version );  /**< Card version */
        PLL_LOG( EMMC_NAME, "HC_Version:            0x%x\n\r", pxThis->xSdInstance.HC_Version );    /**< Host controller version */
        PLL_LOG( EMMC_NAME, "BusWidth:              0x%x\n\r", pxThis->xSdInstance.BusWidth );      /**< Current operating bus width */
        PLL_LOG( EMMC_NAME, "BusSpeed:              0x%x\n\r", pxThis->xSdInstance.BusSpeed );      /**< Current operating bus speed */
        PLL_LOG( EMMC_NAME, "Switch1v8:             0x%x\n\r", pxThis->xSdInstance.Switch1v8 );     /**< 1.8V Switch support */
        PLL_LOG( EMMC_NAME, "CardID:                0x%x 0x%x 0x%x 0x%x\n\r",
                                                               pxThis->xSdInstance.CardID[0],
                                                               pxThis->xSdInstance.CardID[1],
                                                               pxThis->xSdInstance.CardID[2],
                                                               pxThis->xSdInstance.CardID[3] );     /**< Card ID Register */
        PLL_LOG( EMMC_NAME, "RelCardAddr:           0x%x\n\r", pxThis->xSdInstance.RelCardAddr );   /**< Relative Card Address */
        PLL_LOG( EMMC_NAME, "CardSpecData:          0x%x 0x%x 0x%x 0x%x\n\r",
                                                               pxThis->xSdInstance.CardSpecData[0],
                                                               pxThis->xSdInstance.CardSpecData[1],
                                                               pxThis->xSdInstance.CardSpecData[2],
                                                               pxThis->xSdInstance.CardSpecData[3] );
                                                                                                    /**< Card Specific Data Register */
	PLL_LOG( EMMC_NAME, "SectorCount:           0x%x\n\r", pxThis->xSdInstance.SectorCount );   /**< Sector Count */
        PLL_LOG( EMMC_NAME, "SdCardConfig:          0x%x\n\r", pxThis->xSdInstance.SdCardConfig );  /**< Sd Card Configuration Register */
        PLL_LOG( EMMC_NAME, "Mode:                  0x%x\n\r", pxThis->xSdInstance.Mode );          /**< Bus Speed Mode */
        PLL_LOG( EMMC_NAME, "OTapDelay:             0x%x\n\r", pxThis->xSdInstance.OTapDelay );     /**< Output Tap Delay */
        PLL_LOG( EMMC_NAME, "ITapDelay:             0x%x\n\r", pxThis->xSdInstance.ITapDelay );     /**< Input Tap Delay */
        PLL_LOG( EMMC_NAME, "Dma64BitAddr:          0x%llx\n\r",
                                                               pxThis->xSdInstance.Dma64BitAddr );  /**< 64 Bit DMA Address */
        PLL_LOG( EMMC_NAME, "TransferMode:          0x%x\n\r", pxThis->xSdInstance.TransferMode );  /**< Transfer Mode */
        PLL_LOG( EMMC_NAME, "SlcrBaseAddr:          0x%x\n\r", pxThis->xSdInstance.SlcrBaseAddr );  /**< SLCR base address*/
        PLL_LOG( EMMC_NAME, "IsBusy:                0x%x\n\r", pxThis->xSdInstance.IsBusy );        /**< Busy Flag*/
        PLL_LOG( EMMC_NAME, "BlkSize:               0x%x\n\r", pxThis->xSdInstance.BlkSize );       /**< Block Size*/
        PLL_LOG( EMMC_NAME, "IsTuningDone:          0x%x\n\r", pxThis->xSdInstance.IsTuningDone );  /**< Flag to indicate HS200 tuning complete */

        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( EMMC_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Print all the stats gathered by the driver
 */
int iEMMC_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( EMMC_NAME, "============================================================\n\r" );
        PLL_INF( EMMC_NAME, "EMMC Statistics:\n\r" );
        for( i = 0; i < EMMC_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( EMMC_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( EMMC_NAME, "EMMC Errors:\n\r" );
        for( i = 0; i < EMMC_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( EMMC_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( EMMC_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Clear all the stats in the driver
 */
int iEMMC_ClearStatistics( void )
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
        INC_ERROR_COUNTER( EMMC_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Check the parameters are valid
 */
static int iValidateBlockCount( uint64_t ullAddress, uint32_t ulBlockCount )
{
    int         iStatus = ERROR;
    uint32_t    ulBlockAddress = 0;

    if( TRUE == pxThis->iInitialised )
    {
        if( 0 == ( ullAddress % pxThis->xSdInstance.BlkSize ) )
        {
            ulBlockAddress = ullAddress >> EMMC_BLOCK_BITSHIFT;
            if( ( ulBlockAddress + ulBlockCount ) <= pxThis->xSdInstance.SectorCount )
            {
                iStatus = OK;
            }
        }
    }

    return iStatus;
}
