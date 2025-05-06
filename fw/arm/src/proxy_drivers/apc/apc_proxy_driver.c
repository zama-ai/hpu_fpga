/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implementation for the Alveo Programming Control (APC)
 * proxy driver.
 *
 * @file apc_proxy_driver.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "util.h"
#include "pll.h"
#include "osal.h"
#include "apc_proxy_driver.h"
#include "profile_hal.h"

/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL ( 0xBABECAFE )
#define LOWER_FIREWALL ( 0xDEADFACE )

#define APC_NAME "APC"

#define APC_TASK_SLEEP_MS ( 100 )

#define APC_MAX_MSG_SIZE ( 64 )
#define APC_MBOX_SIZE    ( 10 )

#define APC_FPT_HDR_SIZE ( 128 )
#define APC_FPT_PTN_SIZE ( 128 )

#define APC_POR_ENABLE ( 1 << 24 )
#define APC_MULTIBOOT_OFFSET( r ) ( ( r ) / ( 1024 * 32 ) )
#define APC_MULTIBOOT_REAL( r )   ( ( r ) * ( 1024 * 32 ) )

#define APC_PMC_BOOT_TAG( d ) ( *( uint32_t* )( ( d ) + HAL_APC_PDI_BIT_MASK ) )
#define APC_INVALID_PDI_TAG ( 0xFFFFFFFF )

#define APC_DEFAULT_PARTITION   ( 0 )
#define APC_BASE_PACKET_SIZE    ( 1024 )
#define APC_COPY_PACKET_SIZE_KB ( 32 )

#define APC_COPY_CHUNK_LEN ( 0x1000 )                                          /* 4KB */

#ifndef APC_FPT_HDR_MAGIC_NUM
#define APC_FPT_HDR_MAGIC_NUM ( 0x92F7A516 )
#endif

/* Stat & Error definitions */
#define APC_PROXY_STATS( DO )                            \
	DO( APC_PROXY_STATS_INIT_OVERALL_COMPLETE )      \
	DO( APC_PROXY_STATS_MUTEX_CREATE )               \
	DO( APC_PROXY_STATS_MUTEX_TAKE )                 \
	DO( APC_PROXY_STATS_MUTEX_RELEASE )              \
	DO( APC_PROXY_STATS_MBOX_CREATE )                \
	DO( APC_PROXY_STATS_MBOX_DOWNLOAD_POST )         \
	DO( APC_PROXY_STATS_MBOX_DOWNLOAD_PEND )         \
	DO( APC_PROXY_STATS_MBOX_COPY_POST )             \
	DO( APC_PROXY_STATS_MBOX_COPY_PEND )             \
	DO( APC_PROXY_STATS_MBOX_PTN_SELECT_POST )       \
	DO( APC_PROXY_STATS_MBOX_PTN_SELECT_PEND )       \
	DO( APC_PROXY_STATS_MBOX_HOT_RESET_ENABLE_POST ) \
	DO( APC_PROXY_STATS_MBOX_HOT_RESET_ENABLE_PEND ) \
	DO( APC_PROXY_STATS_TASK_CREATE )                \
	DO( APC_PROXY_STATS_FPT_CREATED )                \
	DO( APC_PROXY_STATS_FPT_HEADER_LOADED )          \
	DO( APC_PROXY_STATS_FPT_PARTITION_LOADED )       \
	DO( APC_PROXY_STATS_FPT_HEADER_READ )            \
	DO( APC_PROXY_STATS_FPT_PARTITION_READ )         \
	DO( APC_PROXY_STATS_IMAGE_DOWNLOAD_COMPLETE )    \
	DO( APC_PROXY_STATS_IMAGE_COPY_COMPLETE )        \
	DO( APC_PROXY_STATS_PARTITION_SELECTED )         \
	DO( APC_PROXY_STATS_HOT_RESET_ENABLED )          \
	DO( APC_PROXY_STATS_TASK_TIME_MS )               \
	DO( APC_PROXY_STATS_FPT_UPDATE )                 \
	DO( APC_PROXY_STATS_STATUS_RETRIEVAL )           \
	DO( APC_PROXY_STATS_NUM_BOOT_DEVICES )           \
	DO( APC_PROXY_STATS_MAX )

#define APC_PROXY_ERRORS( DO )                                   \
	DO( APC_PROXY_ERRORS_INIT_NOT_COMPLETE )                 \
	DO( APC_PROXY_ERRORS_FW_IF_OPEN_FAILED )                 \
	DO( APC_PROXY_ERRORS_FW_IF_WRITE_FAILED )                \
	DO( APC_PROXY_ERRORS_FW_IF_READ_FAILED )                 \
	DO( APC_PROXY_ERRORS_MUTEX_CREATE_FAILED )               \
	DO( APC_PROXY_ERRORS_MUTEX_TAKE_FAILED )                 \
	DO( APC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )              \
	DO( APC_PROXY_ERRORS_MBOX_CREATE_FAILED )                \
	DO( APC_PROXY_ERRORS_MBOX_DOWNLOAD_POST_FAILED )         \
	DO( APC_PROXY_ERRORS_MBOX_COPY_POST_FAILED )             \
	DO( APC_PROXY_ERRORS_MBOX_PTN_SELECT_POST_FAILED )       \
	DO( APC_PROXY_ERRORS_MBOX_HOT_RESET_ENABLE_POST_FAILED ) \
	DO( APC_PROXY_ERRORS_MBOX_PEND_FAILED )                  \
	DO( APC_PROXY_ERRORS_TASK_CREATE_FAILED )                \
	DO( APC_PROXY_ERRORS_LOAD_FPT_FAILED )                   \
	DO( APC_PROXY_ERRORS_FPT_NOT_CREATED )                   \
	DO( APC_PROXY_ERRORS_FPT_INVALID_HEADER )                \
	DO( APC_PROXY_ERRORS_FPT_INVALID_PARTITION )             \
	DO( APC_PROXY_ERRORS_FPT_HEADER_NOT_READ )               \
	DO( APC_PROXY_ERRORS_FPT_PARTITION_NOT_READ )            \
	DO( APC_PROXY_ERRORS_FPT_NO_ENTRIES )                    \
	DO( APC_PROXY_ERRORS_INVALID_FPT_PARTITION_REQUESTED )   \
	DO( APC_PROXY_ERRORS_IMAGE_SIZE_ERROR )                  \
	DO( APC_PROXY_ERRORS_PACKET_SIZE_ERROR )                 \
	DO( APC_PROXY_ERRORS_IMAGE_DOWNLOAD_FAILED )             \
	DO( APC_PROXY_ERRORS_IMAGE_COPY_FAILED )                 \
	DO( APC_PROXY_ERRORS_PARTITION_SELECTION_FAILED )        \
	DO( APC_PROXY_ERRORS_HOT_RESET_ENABLE_FAILED )           \
	DO( APC_PROXY_ERRORS_NO_PARTITION_SELECTED )             \
	DO( APC_PROXY_ERRORS_COPY_BUFFER_CREATION_FAILED )       \
	DO( APC_PROXY_ERRORS_RAISE_EVENT_FAILED )                \
	DO( APC_PROXY_ERRORS_VALIDATION_FAILED )                 \
	DO( APC_PROXY_ERRORS_INIT_EVL_RECORD_FAILED )            \
	DO( APC_PROXY_ERRORS_FPT_UPDATE_FAILED )                 \
	DO( APC_PROXY_ERRORS_FPT_UPDATE_EVENT_FAILED )           \
	DO( APC_PROXY_ERRORS_INVALID_BOOT_DEVICE )               \
	DO( APC_PROXY_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )  PLL_INF( APC_NAME,                 \
					  "%50s . . . . %d\r\n",    \
					  APC_PROXY_STATS_STR[ x ], \
					  pxThis->pulStats[ x ] )
#define PRINT_ERROR_COUNTER( x ) PLL_INF( APC_NAME,                  \
					  "%50s . . . . %d\r\n",     \
					  APC_PROXY_ERRORS_STR[ x ], \
					  pxThis->pulErrors[ x ] )

#define INC_STAT_COUNTER( x )             { if( x < APC_PROXY_STATS_MAX ) pxThis->pulStats[ x ]++; }
#define INC_ERROR_COUNTER( x )            { if( x < APC_PROXY_ERRORS_MAX ) pxThis->pulErrors[ x ]++; }
#define INC_ERROR_COUNTER_WITH_STATE( x ) { pxThis->xState = MODULE_STATE_ERROR; INC_ERROR_COUNTER( x ) }
#define SET_STAT_COUNTER( x, y )          { if( x < APC_PROXY_ERRORS_MAX ) pxThis->pulStats[ x ] = y; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    APC_PROXY_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( APC_PROXY_STATS, APC_PROXY_STATS, APC_PROXY_STATS_STR )

/**
 * @enum    APC_PROXY_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( APC_PROXY_ERRORS, APC_PROXY_ERRORS, APC_PROXY_ERRORS_STR )

/**
 * @enum    APC_MSG_TYPES
 * @brief   Enumeration of mbox message types for this proxy
 */
typedef enum
{
	APC_MSG_TYPE_DOWNLOAD_PDI = 0,
	APC_MSG_TYPE_COPY_PDI,
	APC_MSG_TYPE_PARTITION_SELECT,
	APC_MSG_TYPE_ENABLE_HOT_RESET,
	MAX_APC_MSG_TYPE

} APC_MSG_TYPES;


/******************************************************************************/
/* Structures                                                                 */
/******************************************************************************/

/**
 * @struct  APC_PRIVATE_DATA
 * @brief   Structure to hold ths proxy driver's private data
 */
typedef struct APC_PRIVATE_DATA
{
	uint32_t ulUpperFirewall;

	int iInitialised;
	uint8_t ucMyId;

	FW_IF_CFG                      *ppxFwIf[ MAX_APC_BOOT_DEVICES ];

	EVL_RECORD                     *pxEvlRecord;

	void                           *pvOsalMutexHdl;
	void                           *pvOsalFlashLockHdl;
	void                           *pvOsalMBoxHdl;
	void                           *pvOsalTaskHdl;

	int piValidFpt[ MAX_APC_BOOT_DEVICES ];
	APC_PROXY_DRIVER_FPT_HEADER pxFptHeader[ MAX_APC_BOOT_DEVICES ];
	APC_PROXY_DRIVER_FPT_PARTITION *ppxFptPartitions[ MAX_APC_BOOT_DEVICES ];

	uint8_t pucChunkBuffer[ APC_COPY_CHUNK_LEN ];

	uint32_t ulNextBootAddr;

	MODULE_STATE xState;

	uint32_t pulStats[ APC_PROXY_STATS_MAX ];
	uint32_t pulErrors[ APC_PROXY_ERRORS_MAX ];

	uint32_t ulLowerFirewall;

} APC_PRIVATE_DATA;

/**
 * @struct  APC_MBOX_DOWNLOAD_IMAGE
 * @brief   Structure to post the image download data in the mailbox
 */
typedef struct APC_MBOX_DOWNLOAD_IMAGE
{
	APC_BOOT_DEVICES xBootDevice;                                          /* target boot device */
	int iPartition;
	int iUpdateFpt;
	int iLastPacket;
	uint32_t ulImageSize;
	uint32_t ulSrcAddr;
	uint16_t usPacketNum;
	uint16_t usPacketSize;

} APC_MBOX_DOWNLOAD_IMAGE;

/**
 * @struct  APC_MBOX_COPY_IMAGE
 * @brief   Structure to post the image copy data in the mailbox
 */
typedef struct APC_MBOX_COPY_IMAGE
{
	uint32_t ulAllocatedSize;
	uint32_t ulCpyAddr;
	APC_BOOT_DEVICES xSrcBootDevice;                                       /* boot device to copy from */
	int iSrcPartition;                                                     /* partition to copy from */
	APC_BOOT_DEVICES xDestBootDevice;                                      /* boot device to copy to */
	int iDestPartition;                                                    /* partition to copy to */

} APC_MBOX_COPY_IMAGE;

/**
 * @struct  APC_MBOX_MSG
 * @brief   Data posted via the APC Proxy driver mailbox
 */
typedef struct APC_MBOX_MSG
{
	APC_MSG_TYPES eMsgType;
	uint8_t ucRequestId;

	union
	{
		APC_MBOX_DOWNLOAD_IMAGE xDownloadImageData;
		APC_MBOX_COPY_IMAGE xCopyImageData;
		int iSelectedPartition;

	};

} APC_MBOX_MSG;


/******************************************************************************/
/* Local Function declarations                                                */
/******************************************************************************/

/**
 * @brief   APC proxy task
 *
 * @param   pArg    Pointer to task args (unused)
 *
 * @return  N/A (does not return)
 */
static void vProxyDriverTask( void *pArg );

/**
 * @brief   Load entire FPT from Flash device
 *
 * @param   xBootDevice    Target boot device, to load FPT from
 *
 * @return  OK if the FPT was successfully loaded
 *          ERROR if the FPT was not successfully loaded
 */
static int iLoadFpt( APC_BOOT_DEVICES xBootDevice );

/**
 * @brief   Load an FPT partition entry from flash device
 *
 * @param   xBootDevice     Target boot device, to load partition from
 * @param   iPartition      FPT partition to load
 * @param   ulPartitionAddr Address to read FPT partition from
 *
 * @return  OK if the FPT partition was loaded successfully
 *          ERROR if the FPT partition was not loaded
 */
static int iLoadFptPartition( APC_BOOT_DEVICES xBootDevice, int iPartition, uint32_t ulPartitionAddr );

/**
 * @brief   Download new image to flash
 *
 * @param   pxImageData Pointer to data regarding the image to download
 *
 * @return  OK if the image was successfully downloaded
 *          ERROR if the image was not successfully downloaded
 */
static int iDownloadImage( APC_MBOX_DOWNLOAD_IMAGE *pxImageData );

/**
 * @brief   Copy image from one partition to another
 *
 * @param   pxCopyData Pointer to data regarding the image to copy
 *
 * @return  OK if the image was successfully copied
 *          ERROR if the image was not successfully copied
 */
static int iCopyImage( APC_MBOX_COPY_IMAGE *pxCopyData );

/**
 * @brief   Select partition (from primary boot device) to boot from next
 *
 * @param   iPartition  Partition to select
 *
 * @return  OK if the partition was successfully selected
 *          ERROR if the partition was not successfully selected
 */
static int iSelectPartition( int iPartition );

/**
 * @brief   Enable hot reset capability
 *
 * @return  N/A
 */
static void vEnableHotReset( void );

/**
 * @brief   Verify that the values downloaded to flash match the source
 *
 * @param   pxImageData Pointer to data regarding the image to verify
 *
 * @return  OK if the verification passed
 *          ERROR if the verification failed
 */
static int iVerifyDownload( APC_MBOX_DOWNLOAD_IMAGE *pxImageData );

/**
 * @brief   Attempt to reload all FPT data, from target boot device
 *
 * @param   xBootDevice Target boot device
 *
 * @return  OK or ERROR
 */
static int iRefreshFptData( APC_BOOT_DEVICES xBootDevice );


/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

static APC_PRIVATE_DATA xLocalData =
{
	UPPER_FIREWALL,                                                        /* ulUpperFirewall */
	FALSE,                                                                 /* iInitialised */
	0,                                                                     /* ucMyId */
	{
		NULL
	},                                                                     /* ppxFwIf */
	NULL,                                                                  /* pxEvlRecord */
	NULL,                                                                  /* pvOsalMutexHdl */
	NULL,                                                                  /* pvOsalFlashLockHdl */
	NULL,                                                                  /* pvOsalMBoxHdl */
	NULL,                                                                  /* pvOsalTaskHdl */
	{
		FALSE
	},                                                                     /* piValidFpt */
	{ {
		  0
	  } },                                                                 /* pxFptHeader */
	{
		NULL
	},                                                                     /* ppxFptPartitions */
	{
		0
	},                                                                     /* pucChunkBuffer */
	0,                                                                     /* ulNextBootAddr */
	MODULE_STATE_UNINITIALISED,                                            /* xState */
	{
		0
	},                                                                     /* pulStats */
	{
		0
	},                                                                     /* puErrors */
	LOWER_FIREWALL                                                         /* ulLowerFirewall */
};
static APC_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/**
 * @brief   Main initialisation point for the APC Proxy Driver
 *
 * @note    A Primary Firmware Interface handle must be passed to iAPC_Initialise,
 *          the secondary Firmware Interface handle however is optional
 *          and can be set to NULL.
 */
int iAPC_Initialise( uint8_t ucProxyId,
                     FW_IF_CFG *pxPrimaryFwIf,
                     FW_IF_CFG *pxSecondaryFwIf,
                     uint32_t ulTaskPrio,
                     uint32_t ulTaskStack )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( FALSE == pxThis->iInitialised ) &&
	    ( NULL != pxPrimaryFwIf ) )
	{
		/* store parameters locally */
		pxThis->ucMyId = ucProxyId;
		pxThis->ppxFwIf[ APC_BOOT_DEVICE_PRIMARY ]   = pxPrimaryFwIf;
		pxThis->ppxFwIf[ APC_BOOT_DEVICE_SECONDARY ] = pxSecondaryFwIf;

		/* used for primary boot device only */
		pxThis->ulNextBootAddr = APC_MULTIBOOT_REAL( HAL_IO_READ32( HAL_APC_PMC_BOOT_REG ) );

		/* initalise evl record*/
		if( OK != iEVL_CreateRecord( &pxThis->pxEvlRecord ) )
		{
			PLL_ERR( APC_NAME, "Error initialising EVL_RECORD\r\n" );
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_INIT_EVL_RECORD_FAILED );
		}
		else
		{
			/* open and load FPT data for each boot device */
			int i = 0;
			for( i = APC_BOOT_DEVICE_PRIMARY; i < MAX_APC_BOOT_DEVICES; i++ )
			{
				if( NULL != pxThis->ppxFwIf[ i ] )
				{
					INC_STAT_COUNTER( APC_PROXY_STATS_NUM_BOOT_DEVICES )
					if( FW_IF_ERRORS_NONE != pxThis->ppxFwIf[ i ]->open( pxThis->ppxFwIf[ i ] ) )
					{
						INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_OPEN_FAILED )
					}
					else
					{
						if( ERROR == iLoadFpt( i ) )
						{
							INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_LOAD_FPT_FAILED )
						}
					}
				}
			}

			/* init APC proxy */
			if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvOsalMutexHdl, "apc_proxy mutex" ) )
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_CREATE_FAILED )
			}
			if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvOsalFlashLockHdl, "apc_proxy fl_lock" ) )
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_CREATE_FAILED )
			}
			else if( OSAL_ERRORS_NONE != iOSAL_MBox_Create( &pxThis->pvOsalMBoxHdl,
			                                                APC_MBOX_SIZE,
			                                                sizeof( APC_MBOX_MSG ),
			                                                "apc_proxy mbox" ) )
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MBOX_CREATE_FAILED )
			}
			else if( OSAL_ERRORS_NONE != iOSAL_Task_Create( &pxThis->pvOsalTaskHdl,
			                                                vProxyDriverTask,
			                                                ulTaskStack,
			                                                NULL,
			                                                ulTaskPrio,
			                                                "apc_proxy task" ) )
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_TASK_CREATE_FAILED )
			}
			else
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_CREATE )
				INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_CREATE )
				INC_STAT_COUNTER( APC_PROXY_STATS_MBOX_CREATE )
				INC_STAT_COUNTER( APC_PROXY_STATS_TASK_CREATE )

				INC_STAT_COUNTER( APC_PROXY_STATS_INIT_OVERALL_COMPLETE )
				pxThis->iInitialised = TRUE;
				pxThis->xState       = MODULE_STATE_OK;
				iStatus              = OK;
			}
		}
	}

	if( OK != iStatus )
	{
		INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_INIT_NOT_COMPLETE )
	}

	return iStatus;
}

/**
 * @brief   Bind into this proxy driver
 */

int iAPC_BindCallback( EVL_CALLBACK *pxCallback )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( TRUE == pxThis->iInitialised ) &&
	    ( NULL != pxCallback ) &&
	    ( NULL != pxThis->pxEvlRecord ) )
	{
		iStatus = iEVL_BindCallback( pxThis->pxEvlRecord, pxCallback );
	}

	return iStatus;
}

/**
 * @brief   Print all the stats gathered by the proxy driver
 */
int iAPC_PrintStatistics( void )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
	{
		int i = 0;
		PLL_INF( APC_NAME, "============================================================\n\r" );
		PLL_INF( APC_NAME, "APC Proxy Statistics:\n\r" );
		for( i = 0; i < APC_PROXY_STATS_MAX; i++ )
		{
			PRINT_STAT_COUNTER( i );
		}
		PLL_INF( APC_NAME, "------------------------------------------------------------\n\r" );
		PLL_INF( APC_NAME, "APC Proxy Errors:\n\r" );
		for( i = 0; i < APC_PROXY_ERRORS_MAX; i++ )
		{
			PRINT_ERROR_COUNTER( i );
		}
		PLL_INF( APC_NAME, "============================================================\n\r" );
		PLL_INF( APC_NAME,
		         "FPT for primary device is %s\r\n",
		         ( TRUE == pxThis->piValidFpt[ APC_BOOT_DEVICE_PRIMARY ] )?( "valid" ):( "invalid" ) );
		PLL_INF( APC_NAME,
		         "FPT for secondary device is %s\r\n",
		         ( TRUE == pxThis->piValidFpt[ APC_BOOT_DEVICE_SECONDARY ] )?( "valid" ):( "invalid" ) );
		PLL_INF( APC_NAME, "============================================================\n\r" );
		iStatus = OK;
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_VALIDATION_FAILED )
	}

	return iStatus;
}

/**
 * @brief   Clear all the stats in the proxy driver
 */
int iAPC_ClearStatistics( void )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( TRUE == pxThis->iInitialised ) )
	{
		pvOSAL_MemSet( pxThis->pulStats, 0, sizeof( pxThis->pulStats ) );
		pvOSAL_MemSet( pxThis->pulErrors, 0, sizeof( pxThis->pulErrors ) );
		iStatus = OK;
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_VALIDATION_FAILED )
	}

	return iStatus;
}

/**
 * @brief   Download an image to a location in NV memory
 */
int iAPC_DownloadImage( EVL_SIGNAL *pxSignal,
                        APC_BOOT_DEVICES xBootDevice,
                        int iPartition,
                        uint32_t ulSrcAddr,
                        uint32_t ulImageSize,
                        uint16_t usPacketNum,
                        uint16_t usPacketSize )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( TRUE == pxThis->iInitialised ) &&
	    ( MAX_APC_BOOT_DEVICES > xBootDevice ) &&
	    ( TRUE == pxThis->piValidFpt[ xBootDevice ] ) &&
	    ( NULL != pxSignal ) &&
	    ( 0 != ulImageSize ) )
	{
		if( iPartition < pxThis->pxFptHeader[ xBootDevice ].ucNumEntries )
		{
			APC_MBOX_MSG xMsg =
			{
				0
			};
			xMsg.eMsgType                        = APC_MSG_TYPE_DOWNLOAD_PDI;
			xMsg.ucRequestId                     = pxSignal->ucInstance;
			xMsg.xDownloadImageData.xBootDevice  = xBootDevice;
			xMsg.xDownloadImageData.iPartition   = iPartition;
			xMsg.xDownloadImageData.iUpdateFpt   = FALSE;
			xMsg.xDownloadImageData.ulImageSize  = ulImageSize;
			xMsg.xDownloadImageData.ulSrcAddr    = ulSrcAddr;
			xMsg.xDownloadImageData.usPacketNum  = usPacketNum;
			xMsg.xDownloadImageData.usPacketSize = usPacketSize;

			if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
			                                         ( void* )&xMsg,
			                                         OSAL_TIMEOUT_NO_WAIT ) )
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_MBOX_DOWNLOAD_POST )
				iStatus = OK;
			}
			else
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MBOX_DOWNLOAD_POST_FAILED )
			}
		}
		else
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_INVALID_FPT_PARTITION_REQUESTED )
		}
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_VALIDATION_FAILED )
	}

	return iStatus;
}

/**
 * @brief   Download an image with an FPT
 */
int iAPC_UpdateFpt( EVL_SIGNAL *pxSignal,
                    APC_BOOT_DEVICES xBootDevice,
                    uint32_t ulSrcAddr,
                    uint32_t ulImageSize,
                    uint16_t usPacketNum,
                    uint16_t usPacketSize,
                    int iLastPacket )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( TRUE == pxThis->iInitialised ) &&
	    ( NULL != pxSignal ) &&
	    ( MAX_APC_BOOT_DEVICES > xBootDevice ) &&
	    ( NULL != pxThis->ppxFwIf[ xBootDevice ] ) &&
	    ( 0 != ulImageSize ) )
	{
		/* Partition is unused */
		APC_MBOX_MSG xMsg =
		{
			0
		};
		xMsg.eMsgType                        = APC_MSG_TYPE_DOWNLOAD_PDI;
		xMsg.ucRequestId                     = pxSignal->ucInstance;
		xMsg.xDownloadImageData.xBootDevice  = xBootDevice;
		xMsg.xDownloadImageData.iUpdateFpt   = TRUE;
		xMsg.xDownloadImageData.ulImageSize  = ulImageSize;
		xMsg.xDownloadImageData.ulSrcAddr    = ulSrcAddr;
		xMsg.xDownloadImageData.usPacketNum  = usPacketNum;
		xMsg.xDownloadImageData.usPacketSize = usPacketSize;
		xMsg.xDownloadImageData.iLastPacket  = iLastPacket;

		if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
		                                         ( void* )&xMsg,
		                                         OSAL_TIMEOUT_NO_WAIT ) )
		{
			INC_STAT_COUNTER( APC_PROXY_STATS_MBOX_DOWNLOAD_POST )
			iStatus = OK;
		}
		else
		{
			INC_ERROR_COUNTER( APC_PROXY_ERRORS_MBOX_DOWNLOAD_POST_FAILED )
		}
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_VALIDATION_FAILED )
	}

	return iStatus;
}

/**
 * @brief   Copy an image from one partition to another
 */
int iAPC_CopyImage( EVL_SIGNAL *pxSignal,
                    APC_BOOT_DEVICES xSrcBootDevice,
                    int iSrcPartition,
                    APC_BOOT_DEVICES xDestBootDevice,
                    int iDestPartition,
                    uint32_t ulCpyAddr,
                    uint32_t ulAllocatedSize )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( TRUE == pxThis->iInitialised ) &&
	    ( MAX_APC_BOOT_DEVICES > xSrcBootDevice ) &&
	    ( MAX_APC_BOOT_DEVICES > xDestBootDevice ) &&
	    ( TRUE == pxThis->piValidFpt[ xSrcBootDevice ] ) &&
	    ( TRUE == pxThis->piValidFpt[ xDestBootDevice ] ) &&
	    ( NULL != pxSignal ) )
	{
		if( ( iSrcPartition < pxThis->pxFptHeader[ xSrcBootDevice ].ucNumEntries ) &&
		    ( iDestPartition < pxThis->pxFptHeader[ xDestBootDevice ].ucNumEntries ) &&
		    ( ( xSrcBootDevice != xDestBootDevice ) || ( iSrcPartition != iDestPartition ) ) )
		{
			APC_MBOX_MSG xMsg =
			{
				0
			};
			xMsg.eMsgType                       = APC_MSG_TYPE_COPY_PDI;
			xMsg.ucRequestId                    = pxSignal->ucInstance;
			xMsg.xCopyImageData.ulAllocatedSize = ulAllocatedSize;
			xMsg.xCopyImageData.ulCpyAddr       = ulCpyAddr;
			xMsg.xCopyImageData.xSrcBootDevice  = xSrcBootDevice;
			xMsg.xCopyImageData.iSrcPartition   = iSrcPartition;
			xMsg.xCopyImageData.xDestBootDevice = xDestBootDevice;
			xMsg.xCopyImageData.iDestPartition  = iDestPartition;

			if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
			                                         ( void* )&xMsg,
			                                         OSAL_TIMEOUT_NO_WAIT ) )
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_MBOX_COPY_POST )
				iStatus = OK;
			}
			else
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MBOX_COPY_POST_FAILED )
			}
		}
		else
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_INVALID_FPT_PARTITION_REQUESTED )
		}
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_VALIDATION_FAILED )
	}

	return iStatus;
}

/**
 * @brief   Select which partition to boot from
 */
int iAPC_SetNextPartition( EVL_SIGNAL *pxSignal, int iPartition )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( TRUE == pxThis->iInitialised ) &&
	    ( TRUE == pxThis->piValidFpt[ APC_BOOT_DEVICE_PRIMARY ] ) &&
	    ( NULL != pxSignal ) )
	{
		if( iPartition < pxThis->pxFptHeader[ APC_BOOT_DEVICE_PRIMARY ].ucNumEntries )
		{
			APC_MBOX_MSG xMsg =
			{
				0
			};
			xMsg.eMsgType           = APC_MSG_TYPE_PARTITION_SELECT;
			xMsg.ucRequestId        = pxSignal->ucInstance;
			xMsg.iSelectedPartition = iPartition;

			if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
			                                         ( void* )&xMsg,
			                                         OSAL_TIMEOUT_NO_WAIT ) )
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_MBOX_PTN_SELECT_POST )
				iStatus = OK;
			}
			else
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MBOX_PTN_SELECT_POST_FAILED )
			}
		}
		else
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_INVALID_FPT_PARTITION_REQUESTED )
		}
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_VALIDATION_FAILED )
	}

	return iStatus;
}

/**
 * @brief   Enable the hot reset capability
 */
int iAPC_EnableHotReset( EVL_SIGNAL *pxSignal )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( TRUE == pxThis->iInitialised ) &&
	    ( TRUE == pxThis->piValidFpt[ APC_BOOT_DEVICE_PRIMARY ] ) &&
	    ( NULL != pxSignal ) )
	{
		APC_MBOX_MSG xMsg =
		{
			0
		};
		xMsg.eMsgType    = APC_MSG_TYPE_ENABLE_HOT_RESET;
		xMsg.ucRequestId = pxSignal->ucInstance;

		if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
		                                         ( void* )&xMsg,
		                                         OSAL_TIMEOUT_NO_WAIT ) )
		{
			INC_STAT_COUNTER( APC_PROXY_STATS_MBOX_HOT_RESET_ENABLE_POST )
			iStatus = OK;
		}
		else
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MBOX_HOT_RESET_ENABLE_POST_FAILED )
		}
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_VALIDATION_FAILED )
	}

	return iStatus;
}

/**
 * @brief   Get the Flash Partition Table (FPT)
 */
int iAPC_GetFptHeader( APC_BOOT_DEVICES xBootDevice, APC_PROXY_DRIVER_FPT_HEADER *pxFptHeader )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( TRUE == pxThis->iInitialised ) &&
	    ( MAX_APC_BOOT_DEVICES > xBootDevice ) &&
	    ( NULL != pxThis->ppxFwIf[ xBootDevice ] ) &&
	    ( NULL != pxFptHeader ) )
	{
		if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
		{
			INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_TAKE )

			if( NULL != pvOSAL_MemCpy( pxFptHeader,
			                           &pxThis->pxFptHeader[ xBootDevice ],
			                           sizeof( APC_PROXY_DRIVER_FPT_HEADER ) ) )
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_FPT_HEADER_READ )

				if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
				{
					INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_RELEASE )
					iStatus = OK;
				}
				else
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
				}
			}
			else
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FPT_HEADER_NOT_READ )
			}
		}
		else
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
		}
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_VALIDATION_FAILED )
	}

	return iStatus;
}

/**
 * @brief   Get a Flash Partition Table (FPT) Partition
 */
int iAPC_GetFptPartition( APC_BOOT_DEVICES xBootDevice, int iPartition, APC_PROXY_DRIVER_FPT_PARTITION *pxFptPartition )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( TRUE == pxThis->iInitialised ) &&
	    ( MAX_APC_BOOT_DEVICES > xBootDevice ) &&
	    ( TRUE == pxThis->piValidFpt[ xBootDevice ] ) &&
	    ( NULL != pxFptPartition ) )
	{
		if( iPartition < pxThis->pxFptHeader[ xBootDevice ].ucNumEntries )
		{
			if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_TAKE )

				if( NULL != pvOSAL_MemCpy( pxFptPartition,
				                           &pxThis->ppxFptPartitions[ xBootDevice ][ iPartition ],
				                           sizeof( APC_PROXY_DRIVER_FPT_PARTITION ) ) )
				{
					INC_STAT_COUNTER( APC_PROXY_STATS_FPT_PARTITION_READ )

					if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
					{
						INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_RELEASE )
						iStatus = OK;
					}
					else
					{
						INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
					}
				}
				else
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FPT_PARTITION_NOT_READ )
				}
			}
			else
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
			}
		}
		else
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_INVALID_FPT_PARTITION_REQUESTED )
		}
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_VALIDATION_FAILED )
	}

	return iStatus;
}

/**
 * @brief   Gets the current state of the proxy
 */
int iAPC_GetState( MODULE_STATE *pxState )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pxState ) )
	{
		if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_TASK_WAIT_MS ) )
		{
			*pxState = pxThis->xState;

			INC_STAT_COUNTER( APC_PROXY_STATS_STATUS_RETRIEVAL )

			iStatus = OK;
		}
		else
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
		}

		if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
			iStatus = ERROR;
		}
		else
		{
			INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_RELEASE )
		}
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_VALIDATION_FAILED )
	}

	return iStatus;
}


/******************************************************************************/
/* Local Function implementations                                             */
/******************************************************************************/

/**
 * @brief   APC proxy task
 */
static void vProxyDriverTask( void *pArg )
{
	APC_MBOX_MSG xMBoxData =
	{
		0
	};

	uint32_t ulStartMs = 0;

	FOREVER
	{
		ulStartMs = ulOSAL_GetUptimeMs();
		if( OSAL_ERRORS_NONE == iOSAL_MBox_Pend( pxThis->pvOsalMBoxHdl,
		                                         ( void* )&xMBoxData,
		                                         OSAL_TIMEOUT_WAIT_FOREVER ) )
		{
			EVL_SIGNAL xSignal =
			{
				pxThis->ucMyId, 0, xMBoxData.ucRequestId, 0
			};

			switch( xMBoxData.eMsgType )
			{
			case APC_MSG_TYPE_DOWNLOAD_PDI:
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_MBOX_DOWNLOAD_PEND )

				xSignal.ucEventType = APC_PROXY_DRIVER_E_DOWNLOAD_STARTED;
				if( OK != iEVL_RaiseEvent( pxThis->pxEvlRecord, &xSignal ) )
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_RAISE_EVENT_FAILED )
				}
				else
				{
					if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalFlashLockHdl, OSAL_TIMEOUT_NO_WAIT ) )
					{
						INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_TAKE )

						if( OK == iDownloadImage( &xMBoxData.xDownloadImageData ) )
						{
							/* Check if we need to update FPT */
							if( ( TRUE == xMBoxData.xDownloadImageData.iLastPacket ) &&
							    ( TRUE == xMBoxData.xDownloadImageData.iUpdateFpt ) )
							{
								INC_STAT_COUNTER( APC_PROXY_STATS_FPT_UPDATE )

								if( OK == iRefreshFptData( xMBoxData.xDownloadImageData.xBootDevice ) )
								{
									xSignal.ucEventType = APC_PROXY_DRIVER_E_FPT_UPDATE;

									if( OK != iEVL_RaiseEvent( pxThis->pxEvlRecord, &xSignal ) )
									{
										INC_ERROR_COUNTER( APC_PROXY_ERRORS_FPT_UPDATE_EVENT_FAILED )
										INC_ERROR_COUNTER( APC_PROXY_ERRORS_RAISE_EVENT_FAILED )
										xSignal.ucEventType = APC_PROXY_DRIVER_E_DOWNLOAD_FAILED;
									}
									else
									{
										INC_STAT_COUNTER( APC_PROXY_STATS_IMAGE_DOWNLOAD_COMPLETE )
										xSignal.ucEventType = APC_PROXY_DRIVER_E_DOWNLOAD_COMPLETE;
									}
								}
								else
								{
									INC_ERROR_COUNTER( APC_PROXY_ERRORS_FPT_UPDATE_FAILED )
									INC_ERROR_COUNTER( APC_PROXY_ERRORS_IMAGE_DOWNLOAD_FAILED )
									xSignal.ucEventType = APC_PROXY_DRIVER_E_DOWNLOAD_FAILED;
								}
							}
							else
							{
								INC_STAT_COUNTER( APC_PROXY_STATS_IMAGE_DOWNLOAD_COMPLETE )
								xSignal.ucEventType = APC_PROXY_DRIVER_E_DOWNLOAD_COMPLETE;
							}
						}
						else
						{
							INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_IMAGE_DOWNLOAD_FAILED )
							xSignal.ucEventType = APC_PROXY_DRIVER_E_DOWNLOAD_FAILED;
						}

						if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvOsalFlashLockHdl ) )
						{
							INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_RELEASE )
						}
						else
						{
							INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
						}
					}
					else
					{
						INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
						xSignal.ucEventType = APC_PROXY_DRIVER_E_DOWNLOAD_BUSY;
					}

					if( OK != iEVL_RaiseEvent( pxThis->pxEvlRecord, &xSignal ) )
					{
						INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_RAISE_EVENT_FAILED )
					}
				}
			}
			break;

			case APC_MSG_TYPE_COPY_PDI:
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_MBOX_COPY_PEND )

				xSignal.ucEventType = APC_PROXY_DRIVER_E_COPY_STARTED;
				if( OK != iEVL_RaiseEvent( pxThis->pxEvlRecord, &xSignal ) )
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_RAISE_EVENT_FAILED )
				}
				else
				{
					if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalFlashLockHdl, OSAL_TIMEOUT_NO_WAIT ) )
					{
						INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_TAKE )

						if( OK == iCopyImage( &xMBoxData.xCopyImageData ) )
						{
							INC_STAT_COUNTER( APC_PROXY_STATS_IMAGE_COPY_COMPLETE )
							xSignal.ucEventType = APC_PROXY_DRIVER_E_COPY_COMPLETE;
						}
						else
						{
							INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_IMAGE_COPY_FAILED )
							xSignal.ucEventType = APC_PROXY_DRIVER_E_COPY_FAILED;
						}

						if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvOsalFlashLockHdl ) )
						{
							INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_RELEASE )
						}
						else
						{
							INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
						}
					}
					else
					{
						INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
						xSignal.ucEventType = APC_PROXY_DRIVER_E_COPY_BUSY;
					}

					if( OK != iEVL_RaiseEvent( pxThis->pxEvlRecord, &xSignal ) )
					{
						INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_RAISE_EVENT_FAILED )
					}
				}
			}
			break;

			case APC_MSG_TYPE_PARTITION_SELECT:
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_MBOX_PTN_SELECT_PEND )

				if( OK == iSelectPartition( xMBoxData.iSelectedPartition ) )
				{
					INC_STAT_COUNTER( APC_PROXY_STATS_PARTITION_SELECTED )
					xSignal.ucEventType = APC_PROXY_DRIVER_E_PARTITION_SELECTED;
				}
				else
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_PARTITION_SELECTION_FAILED )
					xSignal.ucEventType = APC_PROXY_DRIVER_E_PARTITION_SELECTION_FAILED;
				}

				if( OK != iEVL_RaiseEvent( pxThis->pxEvlRecord, &xSignal ) )
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_RAISE_EVENT_FAILED )
				}
			}
			break;

			case APC_MSG_TYPE_ENABLE_HOT_RESET:
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_MBOX_HOT_RESET_ENABLE_PEND )

				if( 0 == pxThis->ulNextBootAddr )
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_NO_PARTITION_SELECTED );
					PLL_DBG( APC_NAME,
					         "No boot address loaded - defaulting to partition %d\r\n",
					         APC_DEFAULT_PARTITION );
					if( OK == iSelectPartition( APC_DEFAULT_PARTITION ) )
					{
						INC_STAT_COUNTER( APC_PROXY_STATS_HOT_RESET_ENABLED )
					}
					else
					{
						INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_HOT_RESET_ENABLE_FAILED );
					}
				}
				else
				{
					vEnableHotReset();
					INC_STAT_COUNTER( APC_PROXY_STATS_HOT_RESET_ENABLED )
				}
			}
			break;

			default:
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_MBOX_PEND_FAILED )
				PLL_ERR( APC_NAME, "Error: unknown command type (%d)\r\n", xMBoxData.eMsgType );
				break;
			}
			}
		}
		pxThis->pulStats[ APC_PROXY_STATS_TASK_TIME_MS ] = UTIL_ELAPSED_TIME_MS( ulStartMs )
		                                                   iOSAL_Task_SleepMs( APC_TASK_SLEEP_MS );
	}
}

/**
 * @brief   Refresh FPT data from flash/boot device
 */
static int iRefreshFptData( APC_BOOT_DEVICES xBootDevice )
{
	int iStatus = ERROR;

	if( MAX_APC_BOOT_DEVICES > xBootDevice )
	{
		if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
		{
			INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_TAKE )

			pvOSAL_MemSet( &pxThis->pxFptHeader[ xBootDevice ], 0x00, sizeof( pxThis->pxFptHeader[ xBootDevice ] ) );

			if( NULL != pxThis->ppxFptPartitions[ xBootDevice ] )
			{
				vOSAL_MemFree( ( void** )&pxThis->ppxFptPartitions[ xBootDevice ] );
			}

			iStatus = iLoadFpt( xBootDevice );

			if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_MUTEX_RELEASE )
			}
			else
			{
				INC_ERROR_COUNTER( APC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
			}
		}
		else
		{
			INC_ERROR_COUNTER( APC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
		}
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_INVALID_BOOT_DEVICE )
	}

	return iStatus;
}

/**
 * @brief   Load entire FPT from Flash
 */
static int iLoadFpt( APC_BOOT_DEVICES xBootDevice )
{
	int iStatus = ERROR;

	if( MAX_APC_BOOT_DEVICES > xBootDevice )
	{
		APC_PROXY_DRIVER_FPT_HEADER xFptHeader =
		{
			0
		};
		uint32_t ulFptLen = sizeof( xFptHeader );

		if( ( FW_IF_ERRORS_NONE == pxThis->ppxFwIf[ xBootDevice ]->read( pxThis->ppxFwIf[ xBootDevice ],
		                                                                 0,
		                                                                 ( uint8_t* )&xFptHeader,
		                                                                 &ulFptLen,
		                                                                 0 ) ) &&
		    ( sizeof( xFptHeader ) == ulFptLen ) )
		{
			pvOSAL_MemCpy( &pxThis->pxFptHeader[ xBootDevice ],
			               &xFptHeader,
			               sizeof( pxThis->pxFptHeader[ xBootDevice ] ) );

			if( ( APC_FPT_HDR_MAGIC_NUM == xFptHeader.ulMagicNum ) &&
			    ( APC_FPT_HDR_SIZE == xFptHeader.ucFptHeaderSize ) )
			{
				INC_STAT_COUNTER( APC_PROXY_STATS_FPT_HEADER_LOADED )
				pxThis->piValidFpt[ xBootDevice ] = TRUE;

				if( 0 != pxThis->pxFptHeader[ xBootDevice ].ucNumEntries )
				{
					pxThis->ppxFptPartitions[ xBootDevice ] =
						pvOSAL_MemAlloc( sizeof( APC_PROXY_DRIVER_FPT_PARTITION ) *
						                 pxThis->pxFptHeader[ xBootDevice ].
						                 ucNumEntries );
					if( NULL != pxThis->ppxFptPartitions[ xBootDevice ] )
					{
						int i        = 0;
						uint32_t ulOffset = APC_FPT_HDR_SIZE;

						INC_STAT_COUNTER( APC_PROXY_STATS_FPT_CREATED )
						iStatus = OK;

						for( i = 0; i < pxThis->pxFptHeader[ xBootDevice ].ucNumEntries; i++ )
						{
							iStatus = iLoadFptPartition( xBootDevice, i, ulOffset );
							if( OK != iStatus )
							{
								break;
							}

							ulOffset += APC_FPT_PTN_SIZE;
						}
					}
					else
					{
						INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FPT_NOT_CREATED )
					}
				}
				else
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FPT_NO_ENTRIES )
				}
			}
			else
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FPT_INVALID_HEADER )
			}
		}
		else
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_READ_FAILED )
		}
	}
	else
	{
		INC_ERROR_COUNTER( APC_PROXY_ERRORS_INVALID_BOOT_DEVICE )
	}

	return iStatus;
}

/**
 * @brief   Load an FPT partition entry from flash
 */
static int iLoadFptPartition( APC_BOOT_DEVICES xBootDevice, int iPartition, uint32_t ulPartitionAddr )
{
	int iStatus = ERROR;

	if( ( MAX_APC_BOOT_DEVICES > xBootDevice ) && ( iPartition < pxThis->pxFptHeader[ xBootDevice ].ucNumEntries ) )
	{
		APC_PROXY_DRIVER_FPT_PARTITION xFptPartition =
		{
			0
		};
		uint32_t ulFptLen = sizeof( xFptPartition );

		if( ( FW_IF_ERRORS_NONE == pxThis->ppxFwIf[ xBootDevice ]->read( pxThis->ppxFwIf[ xBootDevice ],
		                                                                 ( uint64_t )ulPartitionAddr,
		                                                                 ( uint8_t* )&xFptPartition,
		                                                                 &ulFptLen,
		                                                                 0 ) ) &&
		    ( ulFptLen == sizeof( xFptPartition ) ) )
		{
			INC_STAT_COUNTER( APC_PROXY_STATS_FPT_PARTITION_LOADED )
			pvOSAL_MemCpy( &pxThis->ppxFptPartitions[ xBootDevice ][ iPartition ],
			               &xFptPartition,
			               sizeof( pxThis->ppxFptPartitions[ xBootDevice ][ iPartition ] ) );
			iStatus = OK;
		}
		else
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FPT_INVALID_PARTITION )
		}
	}
	else
	{
		INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_INVALID_FPT_PARTITION_REQUESTED )
	}

	return iStatus;
}

/**
 * @brief   Download new image to flash and update metadata
 */
static int iDownloadImage( APC_MBOX_DOWNLOAD_IMAGE *pxImageData )
{
	int iStatus = ERROR;

	if( ( NULL != pxImageData ) && ( MAX_APC_BOOT_DEVICES > pxImageData->xBootDevice ) )
	{
		int iPartition  = pxImageData->iPartition;
		uint32_t ulImageSize = pxImageData->ulImageSize;
		uint8_t  *pucPdiData = ( uint8_t* )( uintptr_t )( pxImageData->ulSrcAddr );

		HAL_FLUSH_CACHE_DATA( ( uintptr_t )( pxImageData->ulSrcAddr ), ulImageSize ); /* flush shared memory buff before use */

		/* Check if image is smaller than a chunk */
		if( ulImageSize < ( pxImageData->usPacketSize * APC_BASE_PACKET_SIZE ) )
		{
			PLL_WRN( APC_NAME,
			         "Image size (%d) is smaller than the chunk size (%d)\r\n",
			         ulImageSize,
			         ( pxImageData->usPacketSize * APC_BASE_PACKET_SIZE ) );
		}

		/* Check partition size if we are not updating the FPT.  */
		if( ( FALSE == pxImageData->iUpdateFpt ) &&
		    ( ulImageSize > pxThis->ppxFptPartitions[ pxImageData->xBootDevice ][ iPartition ].ulPartitionSize ) )
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_IMAGE_SIZE_ERROR )
			PLL_ERR( APC_NAME,
			         "ERROR: %d bytes is bigger than allocated %d bytes\r\n",
			         ulImageSize,
			         pxThis->ppxFptPartitions[ pxImageData->xBootDevice ][ iPartition ].ulPartitionSize );
		}
		else if( 0 == pxImageData->usPacketSize )
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_PACKET_SIZE_ERROR )
			PLL_ERR( APC_NAME, "ERROR: packet size set to %d KB\r\n", pxImageData->usPacketSize );
		}
		else
		{
			uint32_t ulDestAddr = pxImageData->usPacketNum * ( pxImageData->usPacketSize * APC_BASE_PACKET_SIZE );
			uint32_t ulStartMs  = ulOSAL_GetUptimeMs();

			if( FALSE == pxImageData->iUpdateFpt )
			{
				ulDestAddr += pxThis->ppxFptPartitions[ pxImageData->xBootDevice ][ iPartition ].ulPartitionBaseAddr;

				PLL_DBG( APC_NAME,
				         "Downloading %d bytes to FPT partition %d\r\n",
				         ulImageSize,
				         iPartition );
			}
			else
			{
				PLL_DBG( APC_NAME,
				         "Downloading %d bytes - updating FPT;"
				         " ignore partition numbers in debug output\r\n",
				         ulImageSize );
			}

			PLL_DBG( APC_NAME, "Src:  0x%08x\r\n", pxImageData->ulSrcAddr );
			PLL_DBG( APC_NAME, "Dest: 0x%08x\r\n", ulDestAddr );
			PLL_DBG( APC_NAME, "===== Writing P.%d =====\r\n", iPartition );

			if( ( TRUE == pxImageData->iUpdateFpt ) ||
			    ( ( ulDestAddr + ulImageSize ) <=
			      ( pxThis->ppxFptPartitions[ pxImageData->xBootDevice ][ iPartition ].ulPartitionBaseAddr +
			        pxThis->ppxFptPartitions[ pxImageData->xBootDevice ][ iPartition ].ulPartitionSize ) ) )
			{
				if( FW_IF_ERRORS_NONE ==
				    pxThis->ppxFwIf[ pxImageData->xBootDevice ]->write( pxThis->ppxFwIf[ pxImageData->xBootDevice ],
				                                                        ( uint64_t )ulDestAddr,
				                                                        pucPdiData,
				                                                        ulImageSize,
				                                                        0 ) )
				{
					PLL_DBG( APC_NAME, "===== Verifying write =====\r\n" );
					if( OK == iVerifyDownload( pxImageData ) )
					{
						iStatus = OK;
					}
					else
					{
						INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_WRITE_FAILED )
					}

					/* Invalidate FPT */
					if( ( TRUE == pxImageData->iUpdateFpt ) && ( 0 == pxImageData->usPacketNum ) )
					{
						/* Will need to reset this when the download is complete */
						pxThis->piValidFpt[ pxImageData->xBootDevice ] = FALSE;
					}

					PLL_DBG( APC_NAME,
					         "Write %d %s - %dms\r\n",
					         iPartition,
					         ( OK == iStatus )?( "complete" ):( "failure" ),
					         ulOSAL_GetUptimeMs() - ulStartMs );
				}
				else
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_WRITE_FAILED )
					PLL_ERR( APC_NAME, "ERROR writing to flash\r\n" );
				}
			}
			else
			{
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_IMAGE_SIZE_ERROR )
				PLL_ERR( APC_NAME, "ERROR: %d bytes will overwrite partition\r\n", ulImageSize );
			}
		}
	}

	return iStatus;
}

/**
 * @brief   Copy image from one partition to another
 */
static int iCopyImage( APC_MBOX_COPY_IMAGE *pxCopyData )
{
	int iStatus = ERROR;

	if( ( NULL != pxCopyData ) &&
	    ( MAX_APC_BOOT_DEVICES > pxCopyData->xSrcBootDevice ) &&
	    ( MAX_APC_BOOT_DEVICES > pxCopyData->xDestBootDevice ) )
	{
		uint32_t ulAllocatedSize = pxCopyData->ulAllocatedSize;
		uint8_t          *pucCpyData     = ( uint8_t* )( uintptr_t )( pxCopyData->ulCpyAddr );
		APC_BOOT_DEVICES xSrcBootDevice  = pxCopyData->xSrcBootDevice;
		int iSrcPartition   = pxCopyData->iSrcPartition;
		APC_BOOT_DEVICES xDestBootDevice = pxCopyData->xDestBootDevice;
		int iDestPartition  = pxCopyData->iDestPartition;

		if( pxThis->ppxFptPartitions[ xSrcBootDevice ][ iSrcPartition ].ulPartitionSize >
		    pxThis->ppxFptPartitions[ xDestBootDevice ][ iDestPartition ].ulPartitionSize )
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_IMAGE_SIZE_ERROR )
			PLL_ERR( APC_NAME,
			         "ERROR: %d bytes is bigger than allocated %d bytes\r\n",
			         pxThis->ppxFptPartitions[ xSrcBootDevice ][ iSrcPartition ].ulPartitionSize,
			         pxThis->ppxFptPartitions[ xDestBootDevice ][ iDestPartition ].ulPartitionSize );
		}
		else if( pxThis->ppxFptPartitions[ xSrcBootDevice ][ iSrcPartition ].ulPartitionSize > ulAllocatedSize )
		{
			INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_IMAGE_SIZE_ERROR )
			PLL_ERR( APC_NAME, "ERROR: insufficient memory (%d bytes) reserved for copy\r\n", ulAllocatedSize );
		}
		else
		{
			uint32_t ulCopySize = 0;
			uint32_t ulSrcAddr  =
				pxThis->ppxFptPartitions[ xSrcBootDevice ][ iSrcPartition ].ulPartitionBaseAddr;
			uint32_t ulStartMs           = ulOSAL_GetUptimeMs();
			uint32_t ulTotalBytesWritten = 0;
			uint32_t ulBootTag           = 0;
			APC_MBOX_DOWNLOAD_IMAGE xImageData          =
			{
				.xBootDevice  = xSrcBootDevice,
				.iPartition   = iSrcPartition,
				.ulImageSize  = ( APC_COPY_PACKET_SIZE_KB ) *( APC_BASE_PACKET_SIZE ),
				.ulSrcAddr    = pxCopyData->ulCpyAddr,
				.usPacketNum  = 0,
				.usPacketSize = APC_COPY_PACKET_SIZE_KB
			};

			/* ensure that the smallest safe value is copied */
			if( ulAllocatedSize < pxThis->ppxFptPartitions[ xSrcBootDevice ][ iSrcPartition ].ulPartitionSize )
			{
				ulCopySize = ulAllocatedSize;
			}
			else
			{
				ulCopySize = pxThis->ppxFptPartitions[ xSrcBootDevice ][ iSrcPartition ].ulPartitionSize;
			}

			while( ulCopySize > ulTotalBytesWritten )
			{
				/* set packet size */
				if( ulCopySize < ( ulTotalBytesWritten + ( xImageData.usPacketSize * APC_BASE_PACKET_SIZE ) ) )
				{
					xImageData.ulImageSize = ulCopySize - ulTotalBytesWritten; /* remaining bytes */
				}
				else
				{
					xImageData.ulImageSize = xImageData.usPacketSize * APC_BASE_PACKET_SIZE; /* full packet size */
				}

				/* Read each packet into the shared memory */
				PLL_DBG( APC_NAME,
				         "===== Reading packet %d from P.%d to RAM =====\r\n",
				         xImageData.usPacketNum,
				         iSrcPartition );
				if( ( FW_IF_ERRORS_NONE == pxThis->ppxFwIf[ xSrcBootDevice ]->read( pxThis->ppxFwIf[ xSrcBootDevice ],
				                                                                    ( uint64_t )( ulSrcAddr +
				                                                                                  ( xImageData.
				                                                                                    usPacketNum *
				                                                                                    ( xImageData.
				                                                                                      usPacketSize *
				                                                                                      APC_BASE_PACKET_SIZE )
				                                                                                  ) ),
				                                                                    ( pucCpyData +
				                                                                      ( xImageData.usPacketNum *
				                                                                        ( xImageData.usPacketSize *
				                                                                          APC_BASE_PACKET_SIZE ) ) ),
				                                                                    &xImageData.ulImageSize,
				                                                                    0 ) ) &&
				    ( xImageData.ulImageSize <=
				      pxThis->ppxFptPartitions[ xSrcBootDevice ][ iSrcPartition ].ulPartitionSize ) &&
				    ( xImageData.ulImageSize <= ulAllocatedSize ) &&
				    ( 0 < xImageData.ulImageSize ) )
				{
					if( 0 != xImageData.usPacketNum )
					{
						xImageData.ulSrcAddr   = ( pxCopyData->ulCpyAddr +
						                           ( xImageData.usPacketNum *
						                             ( xImageData.usPacketSize * APC_BASE_PACKET_SIZE ) ) );
						xImageData.xBootDevice = xSrcBootDevice;
						xImageData.iPartition  = iSrcPartition;

						PLL_DBG( APC_NAME, "===== Verifying packet %d =====\r\n", xImageData.usPacketNum );
						if( OK == iVerifyDownload( &xImageData ) )
						{
							PLL_DBG( APC_NAME,
							         "Packet %d of partition %d successfully copied to RAM\r\n",
							         xImageData.usPacketNum,
							         iSrcPartition );

							xImageData.xBootDevice = xDestBootDevice;
							xImageData.iPartition  = iDestPartition;
							if( OK == iDownloadImage( &xImageData ) )
							{
								PLL_DBG( APC_NAME,
								         "Packet %d of RAM contents successfully copied to partition %d\r\n",
								         xImageData.usPacketNum,
								         iDestPartition );
								ulTotalBytesWritten += xImageData.ulImageSize;
							}
							else
							{
								INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_WRITE_FAILED )
								PLL_ERR( APC_NAME,
								         "ERROR copying packet %d of RAM contents to partition %d\r\n",
								         xImageData.usPacketNum,
								         iDestPartition );
								break;
							}
						}
						else
						{
							INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_READ_FAILED )
							PLL_ERR( APC_NAME, "ERROR copying partition %d to RAM\r\n", iSrcPartition );
							break;
						}
					}
					else
					{
						/* invalidate the PDI magic number, to ensure it isn't bootable until complete */
						ulBootTag = APC_PMC_BOOT_TAG( pucCpyData ); /* save boot tag */
						APC_PMC_BOOT_TAG( pucCpyData ) = APC_INVALID_PDI_TAG; /* invalidate boot tag */
						xImageData.ulSrcAddr           = pxCopyData->ulCpyAddr;
						xImageData.xBootDevice         = xDestBootDevice;
						xImageData.iPartition          = iDestPartition;

						if( OK == iDownloadImage( &xImageData ) )
						{
							PLL_DBG( APC_NAME,
							         "Packet %d (with invalidated PDI magic number) of RAM contents successfully copied to partition %d\r\n",
							         xImageData.usPacketNum,
							         iDestPartition );
							ulTotalBytesWritten += xImageData.ulImageSize;
						}
						else
						{
							INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_WRITE_FAILED )
							PLL_ERR( APC_NAME,
							         "ERROR copying packet %d of RAM contents to partition %d\r\n",
							         xImageData.usPacketNum,
							         iDestPartition );
							break;
						}
					}
				}
				else
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_READ_FAILED )
					PLL_ERR( APC_NAME, "ERROR reading to 0x%08x from 0x%08x\r\n", pxCopyData->ulCpyAddr, ulSrcAddr );
					break;
				}

				xImageData.usPacketNum++;
			}

			if( ulCopySize == ulTotalBytesWritten )
			{
				/* PDI is now bootable - re-validate the PDI magic number - re-download first packet */
				APC_PMC_BOOT_TAG( pucCpyData ) = ulBootTag;
				PLL_DBG( APC_NAME, "Tag:  0x%08x\r\n", APC_PMC_BOOT_TAG( pucCpyData ) );

				xImageData.xBootDevice = xSrcBootDevice;
				xImageData.iPartition  = iSrcPartition;
				xImageData.usPacketNum = 0;
				xImageData.ulSrcAddr   = pxCopyData->ulCpyAddr;
				xImageData.ulImageSize = xImageData.usPacketSize * APC_BASE_PACKET_SIZE; /* full packet size */

				PLL_DBG( APC_NAME, "===== Verifying packet %d =====\r\n", xImageData.usPacketNum );
				if( OK == iVerifyDownload( &xImageData ) )
				{
					PLL_DBG( APC_NAME,
					         "Packet %d of partition %d successfully copied to RAM\r\n",
					         xImageData.usPacketNum,
					         iSrcPartition );

					xImageData.xBootDevice = xDestBootDevice;
					xImageData.iPartition  = iDestPartition;
					if( OK == iDownloadImage( &xImageData ) )
					{
						PLL_DBG( APC_NAME,
						         "Packet %d of RAM contents successfully copied to partition %d\r\n",
						         xImageData.usPacketNum,
						         iDestPartition );
						iStatus = OK;
					}
					else
					{
						INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_WRITE_FAILED )
						PLL_ERR( APC_NAME,
						         "ERROR copying packet %d of RAM contents to partition %d\r\n",
						         xImageData.usPacketNum,
						         iDestPartition );
					}
				}
				else
				{
					INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_READ_FAILED )
					PLL_ERR( APC_NAME, "ERROR copying partition %d to RAM\r\n", iSrcPartition );
				}
			}
			else
			{
				PLL_ERR( APC_NAME, "ERROR copying RAM contents to partition %d\r\n", iDestPartition );
			}

			PLL_DBG( APC_NAME,
			         "Copy %d-->%d %s - %dms\r\n",
			         iSrcPartition,
			         iDestPartition,
			         ( OK == iStatus )?( "complete" ):( "failure" ),
			         ulOSAL_GetUptimeMs() - ulStartMs );
		}
	}

	return iStatus;
}

/**
 * @brief   Select partition to boot from next
 */
static int iSelectPartition( int iPartition )
{
	int iStatus = ERROR;

	if( iPartition < pxThis->pxFptHeader[ APC_BOOT_DEVICE_PRIMARY ].ucNumEntries )
	{
		pxThis->ulNextBootAddr = pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_PRIMARY ][ iPartition ].ulPartitionBaseAddr;

		vEnableHotReset();

		PLL_DBG( APC_NAME,
		         "Next boot address: 0x%08x [0x%08x] (partition %d) - actual 0x%08x\r\n",
		         pxThis->ulNextBootAddr,
		         APC_MULTIBOOT_OFFSET( pxThis->ulNextBootAddr ),
		         iPartition,
		         HAL_IO_READ32( HAL_APC_PMC_BOOT_REG ) );

		iStatus = OK;
	}

	return iStatus;
}

/**
 * @brief   Enable hot reset capability
 */
static void vEnableHotReset( void )
{
	PLL_DBG( APC_NAME,
	         "Next boot address: 0x%08x [0x%08x]\r\n",
	         pxThis->ulNextBootAddr,
	         APC_MULTIBOOT_OFFSET( pxThis->ulNextBootAddr ) );

	HAL_IO_WRITE32( APC_POR_ENABLE, HAL_APC_PMC_SRST_REG );
	HAL_IO_WRITE32( APC_MULTIBOOT_OFFSET( pxThis->ulNextBootAddr ), HAL_APC_PMC_BOOT_REG );
}

/**
 * @brief   Verify that the values downloaded to flash match the source
 */
static int iVerifyDownload( APC_MBOX_DOWNLOAD_IMAGE *pxImageData )
{
	int iStatus = ERROR;

	if( ( NULL != pxImageData ) && ( MAX_APC_BOOT_DEVICES > pxImageData->xBootDevice ) )
	{
		uint8_t  *pucPdiData   = ( uint8_t* )( uintptr_t )( pxImageData->ulSrcAddr );
		uint8_t  *pucSrcOffset = &pucPdiData[ 0 ];
		uint32_t ulDestOffset  = pxImageData->usPacketNum * ( pxImageData->usPacketSize * APC_BASE_PACKET_SIZE );
		uint32_t ulImageSize   = pxImageData->ulImageSize;
		uint32_t ulRemLen      = ulImageSize;
		uint32_t ulVerLen      = APC_COPY_CHUNK_LEN;
		uint32_t ulStartMs     = ulOSAL_GetUptimeMs();

		if( FALSE == pxImageData->iUpdateFpt )
		{
			ulDestOffset +=
				pxThis->ppxFptPartitions[ pxImageData->xBootDevice ][ pxImageData->iPartition ].ulPartitionBaseAddr;
		}

		pvOSAL_MemSet( pxThis->pucChunkBuffer, 0x00, APC_COPY_CHUNK_LEN );
		while( 0 < ulRemLen )
		{
			if( ulRemLen < APC_COPY_CHUNK_LEN )
			{
				ulVerLen = ulRemLen;
			}
			else
			{
				ulVerLen = APC_COPY_CHUNK_LEN;
			}

			if( ( FW_IF_ERRORS_NONE ==
			      pxThis->ppxFwIf[ pxImageData->xBootDevice ]->read( pxThis->ppxFwIf[ pxImageData->xBootDevice ],
			                                                         ( uint64_t )ulDestOffset, pxThis->pucChunkBuffer,
			                                                         &ulVerLen, 0 ) ) &&
			    ( 0 < ulVerLen ) )
			{
				if( 0 == iOSAL_MemCmp( pxThis->pucChunkBuffer, pucSrcOffset, ulVerLen ) )
				{
					ulRemLen     -= ulVerLen;
					pucSrcOffset += ulVerLen;
					ulDestOffset += ulVerLen;
					iStatus       = OK;
				}
				else
				{
					PLL_DBG( APC_NAME,
					         "Bytes at offset 0x%08x (flash) and 0x%08x (RAM) differ (%d remaining)\r\n",
					         ulDestOffset,
					         ( uint32_t )( uintptr_t )pucSrcOffset,
					         ulRemLen );
					iStatus = ERROR;
					break;
				}
			}
			else
			{
				PLL_ERR( APC_NAME, "Read ERROR (%d bytes) with %d bytes remaining\r\n", ulVerLen, ulRemLen );
				INC_ERROR_COUNTER_WITH_STATE( APC_PROXY_ERRORS_FW_IF_READ_FAILED )
			}
		}

		PLL_DBG( APC_NAME,
		         "Verification %s - %dms\r\n",
		         ( OK == iStatus )?( "complete" ):( "failure" ),
		         ulOSAL_GetUptimeMs() - ulStartMs );
	}

	return iStatus;
}
