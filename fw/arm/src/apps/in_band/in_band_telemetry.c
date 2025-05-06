/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the amc in band telemetry implementation
 *
 * @file in_band_telemetry.c
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

/* profile */
#include "profile_hal.h"

/* core_libs */
#include "evl.h"
#include "xparameters.h"

/* drivers */
#include "eeprom.h"
#include "stream_isc.h"

/* proxy drivers */
#include "ami_proxy_driver.h"
#include "axc_proxy_driver.h"
#include "apc_proxy_driver.h"

/* apps */
#include "asdm.h"
#include "in_band_telemetry.h"

/* HPU related */
#include "ucore.h"

/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define IN_BAND_NAME "AMC_IN_BAND"

#define UPPER_FIREWALL ( 0xBABECAFE )
#define LOWER_FIREWALL ( 0xDEADFACE )

#define SENSOR_RESPONSE_VALUES  ( 0x3 )
#define SENSOR_RESP_BUFFER_SIZE ( 512 )
#define INVALID_SENSOR_ID       ( 0xFF )

/* Stat & Error definitions */
#define IN_BAND_STATS( DO )                             \
        DO( IN_BAND_STATS_INIT_OVERALL_COMPLETE )       \
        DO( IN_BAND_STATS_AMI_SENSOR_REQUEST )          \
        DO( IN_BAND_STATS_AMI_UNSUPPORTED_REQUEST )     \
        DO( IN_BAND_STATS_AMI_SENSOR_REQUEST_SUCCESS )  \
        DO( IN_BAND_STATS_AMI_EEPROM_RW_REQUEST )       \
        DO( IN_BAND_STATS_AMI_MODULE_RW_REQUEST )       \
        DO( IN_BAND_STATS_AMI_DEBUG_VERBOSITY_REQUEST ) \
        DO( IN_BAND_STATS_INIT_MUTEX )                  \
        DO( IN_BAND_STATS_TAKE_MUTEX )                  \
        DO( IN_BAND_STATS_RELEASE_MUTEX )               \
        DO( IN_BAND_STATS_MAX )

#define IN_BAND_ERRORS( DO )                                \
        DO( IN_BAND_ERRORS_INIT_MUTEX_FAILED )              \
        DO( IN_BAND_ERRORS_INIT_BIND_AMI_CB_FAILED )        \
        DO( IN_BAND_ERRORS_INIT_OVERALL_FAILED )            \
        DO( IN_BAND_ERRORS_AMI_SENSOR_RESP_SIZE_TOO_SMALL ) \
        DO( IN_BAND_ERRORS_AMI_SENSOR_REQUEST_EMPTY_SDR )   \
        DO( IN_BAND_ERRORS_AMI_SENSOR_REQUEST_UNKNOWN_API ) \
        DO( IN_BAND_ERRORS_AMI_SENSOR_REQUEST_FAILED )      \
        DO( IN_BAND_ERRORS_AMI_UNSUPPORTED_REPO )           \
        DO( IN_BAND_ERRORS_AMI_EEPROM_RW_UNKNOWN_REQ )      \
        DO( IN_BAND_ERRORS_AMI_MODULE_RW_UNKNOWN_REQ )      \
        DO( IN_BAND_ERRORS_MUTEX_RELEASE_FAILED )           \
        DO( IN_BAND_ERRORS_MUTEX_TAKE_FAILED )              \
        DO( IN_BAND_ERRORS_MALLOC_FAILED )                  \
        DO( IN_BAND_ERRORS_MAP_REQUEST_FAILED )             \
        DO( IN_BAND_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )  PLL_INF( IN_BAND_NAME,           \
                                          "%50s . . . . %d\r\n",  \
                                          IN_BAND_STATS_STR[ x ], \
                                          pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x ) PLL_INF( IN_BAND_NAME,            \
                                          "%50s . . . . %d\r\n",   \
                                          IN_BAND_ERRORS_STR[ x ], \
                                          pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )  { if( x < IN_BAND_STATS_MAX ) pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x ) { if( x < IN_BAND_ERRORS_MAX ) pxThis->pulErrorCounters[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    IN_BAND_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( IN_BAND_STATS, IN_BAND_STATS, IN_BAND_STATS_STR )

/**
 * @enum    IN_BAND_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( IN_BAND_ERRORS, IN_BAND_ERRORS, IN_BAND_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                     */
/******************************************************************************/

/**
 * @struct  IN_BAND_PRIVATE_DATA
 * @brief   Structure to hold ths in band telemetry private data
 */
typedef struct IN_BAND_PRIVATE_DATA
{
    uint32_t ulUpperFirewall;
    void     *pvOsalMutexHdl;
    uint64_t ullSharedMemBaseAddr;
    uint32_t pulStatCounters[ IN_BAND_STATS_MAX ];
    uint32_t pulErrorCounters[ IN_BAND_ERRORS_MAX ];
    int      iInitialised;
    int      iInBandTestMode;
    uint32_t ulLowerFirewall;

} IN_BAND_PRIVATE_DATA;


/******************************************************************************/
/* Local Variables                                                            */
/******************************************************************************/

static IN_BAND_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                                                            /* ulUpperFirewall */
    NULL,                                                                      /* pvOsalMutexHdl */
    0,                                                                         /* ullSharedMemBaseAddr*/
    {
        0
    },                                                                         /* pulStatCounters */
    {
        0
    },                                                                         /* pulErrorCounters */
    FALSE,                                                                     /* iInitialised */
    FALSE,                                                                     /* iInBandTestMode */
    LOWER_FIREWALL                                                             /* ulLowerFirewall */

};
static IN_BAND_PRIVATE_DATA *pxThis = &xLocalData;

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
static int iAmiCallback( EVL_SIGNAL *pxSignal );

/**
 * @brief   Map the request repo into the ASDM version
 *
 * @param   xRepo     The proxy request repo
 * @param   pxRepo    The ASDM repo
 *
 * @return  OK or ERROR
 */
static int iMapAmiProxyRequestRepo( AMI_PROXY_CMD_SENSOR_REPO xRepo,
                                    ASDM_REPOSITORY_TYPE *pxRepo );


/******************************************************************************/
/* Function Implementations                                                   */
/******************************************************************************/

/**
 * @brief  The initilisation function that build up the ASDM
 *         and binds in the callbacks
 */
int iIN_BAND_TELEMETRY_Initialise( uint64_t ullSharedMemBaseAddr )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) )
    {
        /* Create mutex to protect ASDM access */
        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvOsalMutexHdl,
                                                    "in band mutex" ) )
        {
            INC_ERROR_COUNTER( IN_BAND_ERRORS_INIT_MUTEX_FAILED )
        }
        else
        {
            INC_STAT_COUNTER( IN_BAND_STATS_INIT_MUTEX )
            if( OK == iAMI_BindCallback( &iAmiCallback ) )
            {
                PLL_DBG( IN_BAND_NAME, "AMI Proxy Driver bound\r\n" );
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( IN_BAND_ERRORS_INIT_BIND_AMI_CB_FAILED )
                iStatus = ERROR;
            }

            if( OK == iStatus )
            {
                pxThis->ullSharedMemBaseAddr = ullSharedMemBaseAddr;
                pxThis->iInitialised         = TRUE;
                INC_STAT_COUNTER( IN_BAND_STATS_INIT_OVERALL_COMPLETE )
            }
            else
            {
                INC_ERROR_COUNTER( IN_BAND_ERRORS_INIT_OVERALL_FAILED )
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iIN_BAND_TELEMETRY_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( IN_BAND_NAME, "============================================================\n\r" );
        PLL_INF( IN_BAND_NAME, "In Band App Statistics:\n\r" );
        for( i = 0; i < IN_BAND_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( IN_BAND_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( IN_BAND_NAME, "In Band App Errors:\n\r" );
        for( i = 0; i < IN_BAND_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( IN_BAND_NAME, "============================================================\n\r" );
        if( TRUE == pxThis->iInBandTestMode )
        {
            PLL_INF( IN_BAND_NAME, "In Band App Test Mode:\n\r" );
            PLL_INF( IN_BAND_NAME, "Test mode is activated\n\r" );
        }
        PLL_INF( IN_BAND_NAME, "============================================================\n\r" );

        iStatus = OK;
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iIN_BAND_TELEMETRY_ClearStatistics( void )
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

/**
 * @brief   Set test mode activated/deactivated
 */
int iIN_BAND_TELEMETRY_TestMode( int iActivate )
{
    int iStatus = OK;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        pxThis->iInBandTestMode = iActivate;
    }

    return iStatus;
}


/******************************************************************************/
/* EVL Callback Implementations                                               */
/******************************************************************************/

/**
 * @brief   AMI Proxy Driver EVL callback
 */
static int iAmiCallback( EVL_SIGNAL *pxSignal )
{
    int iStatus = ERROR;

    if( ( NULL != pxSignal ) &&
        ( AMC_CFG_UNIQUE_ID_AMI == pxSignal->ucModule ) &&
        ( TRUE != pxThis->iInBandTestMode ) )
    {
        switch( pxSignal->ucEventType )
        {
        case AMI_PROXY_DRIVER_E_SENSOR_READ:
        {
            AMI_PROXY_SENSOR_REQUEST xSensorRequest =
            {
                0
            };
            INC_STAT_COUNTER( IN_BAND_STATS_AMI_SENSOR_REQUEST )

            iStatus = iAMI_GetSensorRequest( pxSignal, &xSensorRequest );
            if( OK == iStatus )
            {
                ASDM_REPOSITORY_TYPE xRepo          = 0;
                AMI_PROXY_RESULT     xResult        = AMI_PROXY_RESULT_INVALID_VALUE;
                uint16_t             usResponseSize = 0;
                uint8_t              ucRespBuffer[ SENSOR_RESP_BUFFER_SIZE ] =
                {
                    0
                };
                uintptr_t ullDestAddr = ( pxThis->ullSharedMemBaseAddr + xSensorRequest.ullAddress );
                uint8_t   *pucDestAdd = ( uint8_t* )( ullDestAddr );

                /* Reset iStatus */
                iStatus = ERROR;

                if( SENSOR_RESP_BUFFER_SIZE > xSensorRequest.ulLength )
                {
                    PLL_DBG( IN_BAND_NAME,
                             "Response size 0x%x exceeding request size 0x%x",
                             SENSOR_RESP_BUFFER_SIZE,
                             xSensorRequest.ulLength );
                    INC_ERROR_COUNTER( IN_BAND_ERRORS_AMI_SENSOR_RESP_SIZE_TOO_SMALL )
                }
                else
                {
                    iStatus = iMapAmiProxyRequestRepo( xSensorRequest.xRepo, &xRepo );
                    if( OK == iStatus )
                    {
                        /* Populate the response back to the AMI */
                        switch( xSensorRequest.xRequest )
                        {
                        case AMI_PROXY_CMD_SENSOR_REQUEST_GET_SIZE:
                        {
                            /* Return the size of the SDR, including Header, Sensor Records and End of Repo marker */
                            iStatus = iASDM_PopulateResponse( ASDM_API_ID_TYPE_GET_SDR_SIZE,
                                                              xRepo,
                                                              INVALID_SENSOR_ID,
                                                              ucRespBuffer,
                                                              &usResponseSize );
                            break;
                        }

                        case AMI_PROXY_CMD_SENSOR_REQUEST_GET_SDR:
                        {
                            /* Return the entire SDR – Header, Sensor Records and End of Repo marker. */
                            iStatus = iASDM_PopulateResponse( ASDM_API_ID_TYPE_GET_SDR,
                                                              xRepo,
                                                              INVALID_SENSOR_ID,
                                                              ucRespBuffer,
                                                              &usResponseSize );
                            break;
                        }

                        case AMI_PROXY_CMD_SENSOR_REQUEST_GET_SINGLE_SDR:
                        {
                            /* Return the instantaneous sensor data based on the input sensor ID */
                            iStatus = iASDM_PopulateResponse( ASDM_API_ID_TYPE_GET_SINGLE_SENSOR_DATA,
                                                              xRepo,
                                                              xSensorRequest.ulSensorId,
                                                              ucRespBuffer,
                                                              &usResponseSize );
                            break;
                        }

                        case AMI_PROXY_CMD_SENSOR_REQUEST_ALL_SDR:
                        {
                            /* Return the instantaneous sensor data for all sensors in a given SDR */
                            iStatus = iASDM_PopulateResponse( ASDM_API_ID_TYPE_GET_ALL_SENSOR_DATA,
                                                              xRepo,
                                                              INVALID_SENSOR_ID,
                                                              ucRespBuffer,
                                                              &usResponseSize );
                            break;
                        }

                        default:
                        {
                            INC_ERROR_COUNTER( IN_BAND_ERRORS_AMI_SENSOR_REQUEST_UNKNOWN_API )
                            iStatus = ERROR;
                            break;
                        }
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER( IN_BAND_ERRORS_MAP_REQUEST_FAILED )
                    }
                }

                /* Check the response is not greater than the shared memory supplied */
                if( ( OK == iStatus ) &&
                    ( usResponseSize <= xSensorRequest.ulLength ) )
                {
                    /* Copy the data into the shared memory */
                    pvOSAL_MemCpy( pucDestAdd, ucRespBuffer, usResponseSize );

                    /* This is required on the target to flush the data */
                    HAL_FLUSH_CACHE_DATA( ullDestAddr, usResponseSize );

                    xResult = AMI_PROXY_RESULT_SUCCESS;
                    INC_STAT_COUNTER( IN_BAND_STATS_AMI_SENSOR_REQUEST_SUCCESS )
                }
                else
                {
                    /* Single byte response for failure */
                    pucDestAdd[ ASDM_SDR_RESP_BYTE_CC ]   = ASDM_SDR_COMPLETION_CODE_OPERATION_FAILED;
                    pucDestAdd[ ASDM_SDR_RESP_BYTE_SIZE ] = 1;
                    INC_ERROR_COUNTER( IN_BAND_ERRORS_AMI_SENSOR_REQUEST_FAILED )
                }

                iStatus = iAMI_SetSensorCompleteResponse( pxSignal, xResult );
            }
            break;
        }

        case AMI_PROXY_DRIVER_E_EEPROM_READ_WRITE:
        {
            AMI_PROXY_EEPROM_RW_REQUEST xEepromReadWriteRequest =
            {
                0
            };
            INC_STAT_COUNTER( IN_BAND_STATS_AMI_EEPROM_RW_REQUEST )

            iStatus = iAMI_GetEepromReadWriteRequest( pxSignal, &xEepromReadWriteRequest );
            if( OK == iStatus )
            {
                uintptr_t        ullDestAddr  = ( pxThis->ullSharedMemBaseAddr + xEepromReadWriteRequest.ullAddress );
                uint8_t          *pucDestAddr = ( uint8_t* )( ullDestAddr );
                AMI_PROXY_RESULT xResult      = AMI_PROXY_RESULT_FAILURE;

                switch( xEepromReadWriteRequest.xRequest )
                {
                case AMI_PROXY_CMD_RW_REQUEST_READ:
                {
                    iStatus = iEEPROM_ReadRawValue( pucDestAddr,
                                                    xEepromReadWriteRequest.ulLength,
                                                    xEepromReadWriteRequest.ulOffset );

                    /* Flush shared memory so the latest data is available in cache. */
                    HAL_FLUSH_CACHE_DATA(
                        ullDestAddr,
                        xEepromReadWriteRequest.ulLength
                        );
                    break;
                }

                case AMI_PROXY_CMD_RW_REQUEST_WRITE:
                {
                    /* Flush shared memory so the latest data is available in cache. */
                    HAL_FLUSH_CACHE_DATA(
                        ullDestAddr,
                        xEepromReadWriteRequest.ulLength
                        );

                    iStatus = iEEPROM_WriteRawValue( pucDestAddr,
                                                     xEepromReadWriteRequest.ulLength,
                                                     xEepromReadWriteRequest.ulOffset );
                    break;
                }

                default:
                {
                    INC_ERROR_COUNTER( IN_BAND_ERRORS_AMI_EEPROM_RW_UNKNOWN_REQ )
                    iStatus = ERROR;
                    break;
                }
                }

                if( OK == iStatus )
                {
                    xResult = AMI_PROXY_RESULT_SUCCESS;
                }

                iStatus = iAMI_SetEepromReadWriteCompleteResponse( pxSignal, xResult );
            }
            break;
        }

        case AMI_PROXY_DRIVER_E_PEEK_POKE:
        {
            AMI_PROXY_PEEK_POKE_REQUEST xPeekPokeRequest = {0};

            iStatus = iAMI_GetPeekPokeRequest( pxSignal, &xPeekPokeRequest );
            if( OK == iStatus ) {
                uintptr_t ullDestAddr    = ( pxThis->ullSharedMemBaseAddr + xPeekPokeRequest.ullAddress );
                uint32_t *pucDestAddr    = ( uint32_t* )( ullDestAddr );
                AMI_PROXY_RESULT xResult = AMI_PROXY_RESULT_FAILURE;

                switch( xPeekPokeRequest.xRequest ) {
                    case AMI_PROXY_CMD_RW_REQUEST_READ:
                    {
                        for (uint8_t i = 0; i < xPeekPokeRequest.ulLength/4; i++) {
                            // Read and loads up memory
                            *(pucDestAddr+i) =  * (volatile uint32_t *) (XPAR_AXI_LPD_BASEADDR + xPeekPokeRequest.ulOffset + i*4);
                        }

                        // length of the request is fixed to axi bus length
                        HAL_FLUSH_CACHE_DATA(ullDestAddr, xPeekPokeRequest.ulLength);

                        break;
                    }
                    case AMI_PROXY_CMD_RW_REQUEST_WRITE:
                    {
                        // lenght of the flush is fixed here, 32bits
                        HAL_FLUSH_CACHE_DATA(ullDestAddr, xPeekPokeRequest.ulLength);

                        *( ( volatile uint32_t * )(XPAR_AXI_LPD_BASEADDR + xPeekPokeRequest.ulOffset) ) = *pucDestAddr;

                        break;
                    }
                    default:
                    {
                        iStatus = ERROR;
                        break;
                    }
                }

                if( OK == iStatus ) {
                    xResult = AMI_PROXY_RESULT_SUCCESS;
                }

                iStatus = iAMI_SetPeekPokeReadWriteCompleteResponse( pxSignal, xResult );
            }
            break;
        }

        case AMI_PROXY_DRIVER_E_MODULE_READ_WRITE:
        {
            AMI_PROXY_MODULE_RW_REQUEST xModuleReadWriteRequest =
            {
                0
            };
            INC_STAT_COUNTER( IN_BAND_STATS_AMI_MODULE_RW_REQUEST )

            iStatus = iAMI_GetModuleReadWriteRequest( pxSignal, &xModuleReadWriteRequest );
            if( OK == iStatus )
            {
                uintptr_t        ullDestAddr  = ( pxThis->ullSharedMemBaseAddr + xModuleReadWriteRequest.ullAddress );
                uint8_t          *pucDestAddr = ( uint8_t* )( ullDestAddr );
                AMI_PROXY_RESULT xResult      = AMI_PROXY_RESULT_FAILURE;

                /* Check if the request is valid */
                iStatus = iAXC_ValidateRequest(
                    xModuleReadWriteRequest.ucExDeviceId,
                    xModuleReadWriteRequest.ucPage,
                    xModuleReadWriteRequest.ucByteOffset
                    );

                if( OK == iStatus )
                {
                    switch( xModuleReadWriteRequest.xRequest )
                    {
                    case AMI_PROXY_CMD_RW_REQUEST_READ:
                    {
                        if( 1 < xModuleReadWriteRequest.ucLength )
                        {
                            /* TODO: Implement block read. */
                            iStatus = ERROR;
                        }
                        else
                        {
                            /* Single byte read. */
                            iStatus = iAXC_GetByte(
                                xModuleReadWriteRequest.ucExDeviceId,
                                xModuleReadWriteRequest.ucPage,
                                xModuleReadWriteRequest.ucByteOffset,
                                pucDestAddr
                                );
                        }

                        /* Flush shared memory so the latest data is available in cache. */
                        HAL_FLUSH_CACHE_DATA( ullDestAddr, xModuleReadWriteRequest.ucLength );
                        break;
                    }

                    case AMI_PROXY_CMD_RW_REQUEST_WRITE:
                    {
                        /* Flush shared memory so the latest data is available in cache. */
                        HAL_FLUSH_CACHE_DATA( ullDestAddr, xModuleReadWriteRequest.ucLength );

                        if( 1 < xModuleReadWriteRequest.ucLength )
                        {
                            /* TODO: Implement block write. */
                            iStatus = ERROR;
                        }
                        else
                        {
                            /* Single byte write. */
                            iStatus = iAXC_SetByte(
                                xModuleReadWriteRequest.ucExDeviceId,
                                xModuleReadWriteRequest.ucPage,
                                xModuleReadWriteRequest.ucByteOffset,
                                pucDestAddr[ 0 ]
                                );
                        }
                        break;
                    }

                    default:
                    {
                        INC_ERROR_COUNTER( IN_BAND_ERRORS_AMI_MODULE_RW_UNKNOWN_REQ )
                        iStatus = ERROR;
                        break;
                    }
                    }
                }
                else
                {
                    xResult = AMI_PROXY_RESULT_INVALID_CONFIGURATION;
                }

                if( OK == iStatus )
                {
                    xResult = AMI_PROXY_RESULT_SUCCESS;
                }

                iStatus = iAMI_SetModuleReadWriteCompleteResponse( pxSignal, xResult );
            }
            break;
        }

        case AMI_PROXY_DRIVER_E_PDI_DOWNLOAD_START:
        {
            AMI_PROXY_PDI_DOWNLOAD_REQUEST xDownloadRequest =
            {
                0
            };
            PLL_LOG( IN_BAND_NAME, "PDI download has started\r\n" );

            if( OK == iAMI_GetPdiDownloadRequest( pxSignal, &xDownloadRequest ) )
            {
                PLL_DBG( IN_BAND_NAME, "Target boot device   : 0x%x\r\n",   xDownloadRequest.iBootDevice );
                PLL_DBG( IN_BAND_NAME, "PDI download address : 0x%llx\r\n", xDownloadRequest.ullAddress );
                PLL_DBG( IN_BAND_NAME, "PDI download length  : 0x%x\r\n",   xDownloadRequest.ulLength );
                PLL_DBG( IN_BAND_NAME, "PDI partition        : 0x%x\r\n",   xDownloadRequest.ulPartitionSel );
                PLL_DBG( IN_BAND_NAME, "PDI has FPT          : 0x%x\r\n",   xDownloadRequest.iUpdateFpt );
                PLL_DBG( IN_BAND_NAME, "PDI last packet      : 0x%x\r\n",   xDownloadRequest.iLastPacket );
                PLL_DBG( IN_BAND_NAME, "PDI packet number    : 0x%hx\r\n",  xDownloadRequest.usPacketNum );
                PLL_DBG( IN_BAND_NAME, "PDI packet size (KB) : 0x%hx\r\n",  xDownloadRequest.usPacketSize );

                if( TRUE == xDownloadRequest.iUpdateFpt )
                {
                    iStatus = iAPC_UpdateFpt( pxSignal,
                                              xDownloadRequest.iBootDevice,
                                              ( uint32_t )xDownloadRequest.ullAddress +
                                              ( uint32_t )HAL_RPU_SHARED_MEMORY_BASE_ADDR,
                                              xDownloadRequest.ulLength,
                                              xDownloadRequest.usPacketNum,
                                              xDownloadRequest.usPacketSize,
                                              xDownloadRequest.iLastPacket );
                }
                else
                {
                    iStatus = iAPC_DownloadImage( pxSignal,
                                                  xDownloadRequest.iBootDevice,
                                                  ( int )xDownloadRequest.ulPartitionSel,
                                                  ( uint32_t )xDownloadRequest.ullAddress +
                                                  ( uint32_t )HAL_RPU_SHARED_MEMORY_BASE_ADDR,
                                                  xDownloadRequest.ulLength,
                                                  xDownloadRequest.usPacketNum,
                                                  xDownloadRequest.usPacketSize );
                }

                if( OK != iStatus )
                {
                    iStatus = iAMI_SetPdiDownloadCompleteResponse( pxSignal, AMI_PROXY_RESULT_PROCESS_REQUEST_FAILED );
                }
            }
            else
            {
                iStatus = iAMI_SetPdiDownloadCompleteResponse( pxSignal, AMI_PROXY_RESULT_GET_REQUEST_FAILED );
            }

            if( OK != iStatus )
            {
                PLL_ERR( IN_BAND_NAME, "Error downloading to partition %d\r\n", xDownloadRequest.ulPartitionSel );
            }
            break;
        }

        case AMI_PROXY_DRIVER_E_PDI_COPY_START:
        {
            AMI_PROXY_PDI_COPY_REQUEST xCopyRequest =
            {
                0
            };
            PLL_LOG( IN_BAND_NAME, "PDI copy has started\r\n" );

            if( OK == iAMI_GetPdiCopyRequest( pxSignal, &xCopyRequest ) )
            {
                PLL_DBG( IN_BAND_NAME, "PDI copy address     : 0x%llx\r\n", xCopyRequest.ullAddress );
                PLL_DBG( IN_BAND_NAME, "PDI max copy length  : 0x%x\r\n",   xCopyRequest.ulMaxLength );
                PLL_DBG( IN_BAND_NAME, "PDI src device       : 0x%x\r\n",   xCopyRequest.ulSrcDevice );
                PLL_DBG( IN_BAND_NAME, "PDI src partition    : 0x%x\r\n",   xCopyRequest.ulSrcPartition );
                PLL_DBG( IN_BAND_NAME, "PDI dst device       : 0x%x\r\n",   xCopyRequest.ulDestDevice );
                PLL_DBG( IN_BAND_NAME, "PDI dst partition    : 0x%x\r\n",   xCopyRequest.ulDestPartition );
                if( OK == iAPC_CopyImage( pxSignal,
                                          xCopyRequest.ulSrcDevice,
                                          ( int )xCopyRequest.ulSrcPartition,
                                          xCopyRequest.ulDestDevice,
                                          ( int )xCopyRequest.ulDestPartition,
                                          ( uint32_t )xCopyRequest.ullAddress +
                                          ( uint32_t )HAL_RPU_SHARED_MEMORY_BASE_ADDR,
                                          xCopyRequest.ulMaxLength ) )
                {
                    iStatus = OK;
                }
                else
                {
                    iStatus = iAMI_SetPdiCopyCompleteResponse( pxSignal, AMI_PROXY_RESULT_PROCESS_REQUEST_FAILED );
                }
            }
            else
            {
                iStatus = iAMI_SetPdiCopyCompleteResponse( pxSignal, AMI_PROXY_RESULT_GET_REQUEST_FAILED );
            }

            if( OK != iStatus )
            {
                PLL_ERR( IN_BAND_NAME,
                         "Error copying p%d to p%d\r\n",
                         xCopyRequest.ulSrcPartition,
                         xCopyRequest.ulDestPartition );
            }
            break;
        }

        case AMI_PROXY_DRIVER_E_BOOT_SELECT:
        {
            AMI_PROXY_BOOT_SELECT_REQUEST xBootSelRequest =
            {
                0
            };
            PLL_DBG( IN_BAND_NAME, "Event Boot Select Request (0x%02X)\r\n", pxSignal->ucEventType );

            if( OK == iAMI_GetBootSelectRequest( pxSignal, &xBootSelRequest ) )
            {
                PLL_DBG( IN_BAND_NAME, "Selecting partition %d\r\n", xBootSelRequest.ulPartitionSel );
                if( OK == iAPC_SetNextPartition( pxSignal, ( int )xBootSelRequest.ulPartitionSel ) )
                {
                    iStatus = OK;
                }
                else
                {
                    iStatus = iAMI_SetBootSelectCompleteResponse( pxSignal, AMI_PROXY_RESULT_PROCESS_REQUEST_FAILED );
                }
            }
            else
            {
                iStatus = iAMI_SetPdiCopyCompleteResponse( pxSignal, AMI_PROXY_RESULT_GET_REQUEST_FAILED );
            }

            if( OK != iStatus )
            {
                PLL_ERR( IN_BAND_NAME, "Error selecting partition %d\r\n", xBootSelRequest.ulPartitionSel );
            }
            break;
        }

        case AMI_PROXY_DRIVER_E_DEBUG_VERBOSITY:
        {
            uint8_t ucDebugVerbosityRequest = 0;
            INC_STAT_COUNTER( IN_BAND_STATS_AMI_DEBUG_VERBOSITY_REQUEST )
            PLL_DBG( IN_BAND_NAME, "Event debug verbosity request\r\n" );

            iStatus = iAMI_GetDebugVerbosityRequest( pxSignal, &ucDebugVerbosityRequest );

            if( OK == iStatus )
            {
                AMI_PROXY_RESULT xResult = AMI_PROXY_RESULT_SUCCESS;

                if( ( MAX_PLL_OUTPUT_LEVEL <= ucDebugVerbosityRequest ) ||
                    ( OK != iPLL_SetLoggingLevel( ucDebugVerbosityRequest ) ) )
                {
                    xResult = AMI_PROXY_RESULT_PROCESS_REQUEST_FAILED;
                }

                iStatus = iAMI_SetDebugVerbosityResponse( pxSignal, xResult );
            }

            if( OK != iStatus )
            {
                PLL_ERR( IN_BAND_NAME, "Error updating debug verbosity level\r\n" );
            }
            break;
        }

        case AMI_PROXY_DRIVER_E_GET_UCORE_VERSION:
        {
            PLL_DBG( IN_BAND_NAME, "Event Get Ucore Version (0x%02X)\r\n", pxSignal->ucEventType );

            AMI_PROXY_RESULT xResult = AMI_PROXY_RESULT_SUCCESS;

            iStatus = iAMI_SetUcoreVersionCompleteResponse( pxSignal, xResult );

            break;
        }
        case AMI_PROXY_DRIVER_E_GET_IDENTITY:
        case AMI_PROXY_DRIVER_E_HEARTBEAT:
        default:
        {
            INC_STAT_COUNTER( IN_BAND_STATS_AMI_UNSUPPORTED_REQUEST )
            iStatus = OK;
            break;
        }
        }
    }

    return iStatus;
}

/*
 * @brief   Map the request repo into the inband version
 */
static int iMapAmiProxyRequestRepo( AMI_PROXY_CMD_SENSOR_REPO xRepo, ASDM_REPOSITORY_TYPE *pxRepo )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxRepo ) )
    {
        switch( xRepo )
        {
        case AMI_PROXY_CMD_SENSOR_REPO_BDINFO:
        {
            *pxRepo = ASDM_REPOSITORY_TYPE_BOARD_INFO;
            iStatus = OK;
            break;
        }

        case AMI_PROXY_CMD_SENSOR_REPO_TEMP:
        {
            *pxRepo = ASDM_REPOSITORY_TYPE_TEMP;
            iStatus = OK;
            break;
        }

        case AMI_PROXY_CMD_SENSOR_REPO_VOLTAGE:
        {
            *pxRepo = ASDM_REPOSITORY_TYPE_VOLTAGE;
            iStatus = OK;
            break;
        }

        case AMI_PROXY_CMD_SENSOR_REPO_CURRENT:
        {
            *pxRepo = ASDM_REPOSITORY_TYPE_CURRENT;
            iStatus = OK;
            break;
        }

        case AMI_PROXY_CMD_SENSOR_REPO_POWER:
        {
            *pxRepo = ASDM_REPOSITORY_TYPE_POWER;
            iStatus = OK;
            break;
        }

        case AMI_PROXY_CMD_SENSOR_REPO_TOTAL_POWER:
        {
            /* return the total power repo as opposed to the individual power sensor values */
            *pxRepo = ASDM_REPOSITORY_TYPE_TOTAL_POWER;
            iStatus = OK;
            break;
        }

        case AMI_PROXY_CMD_SENSOR_REPO_FPT:
        {
            *pxRepo = ASDM_REPOSITORY_TYPE_FPT;
            iStatus = OK;
            break;
        }

        default:
        case AMI_PROXY_CMD_SENSOR_REPO_ALL:
        case AMI_PROXY_CMD_SENSOR_REPO_GET_SIZE:
        {
            INC_ERROR_COUNTER( IN_BAND_ERRORS_AMI_UNSUPPORTED_REPO )
            break;
        }
        }
    }

    return ( iStatus );
}
