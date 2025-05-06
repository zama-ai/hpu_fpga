/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implementation for the Alveo Management Interface (AMI)
 * proxy driver.
 *
 * @file ami_proxy_driver.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <string.h>

#include "xil_types.h"
#include "util.h"
#include "pll.h"
#include "osal.h"
#include "ami_proxy_driver.h"
#include "ucore.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL                  ( 0xBABECAFE )
#define LOWER_FIREWALL                  ( 0xDEADFACE )
#define AMC_TRIGGERED_COMMAND_ID        ( 0xF00D )

#define AMI_TASK_SLEEP_MS               ( 100 )

#define AMI_NAME                        "AMI"

#define AMI_MAX_MSG_SIZE                ( 64 )
#define AMI_MBOX_SIZE                   ( 10 )

/* Maximum number of in flight requests/responses */
#define AMI_RXDATA_SIZE                 ( 8 )
#define AMI_CHECK_VALID_INDEX( x )      ( x < AMI_RXDATA_SIZE )

#define AMI_RESPONSE_HDR_SIZE           ( 1 )
#define AMI_RESPONSE_PAYLOAD_SIZE       ( 2 )
#define AMI_RESPONSE_SIZE               ( 4 )
#define AMI_REQUEST_HDR_SIZE            ( 2 )

#define APC_LOAD_VER_MAJOR( v )         ( ( v )           & 0x000000FF )
#define APC_LOAD_VER_MINOR( v )         ( ( ( v ) << 8 )  & 0x0000FF00 )
#define APC_LOAD_VER_PATCH( v )         ( ( ( v ) << 16 ) & 0x00FF0000 )
#define APC_LOAD_LOCAL_CHANGES( v )     ( ( ( v ) << 24 ) & 0xFF000000 )
#define APC_LOAD_DEV_COMMITS( v )       ( ( v )           & 0x0000FFFF )
#define APC_LOAD_LINK_VER_MAJOR( v )    ( ( ( v ) << 16 ) & 0x00FF0000 )
#define APC_LOAD_LINK_VER_MINOR( v )    ( ( ( v ) << 24 ) & 0xFF000000 )

/* Stat & Error definitions */
#define AMI_PROXY_STATS( DO )   \
    DO( AMI_PROXY_STATS_INIT_OVERALL_COMPLETE )        \
    DO( AMI_PROXY_STATS_CREATE_MUTEX )                 \
    DO( AMI_PROXY_STATS_CREATE_MBOX )                  \
    DO( AMI_PROXY_STATS_TAKE_MUTEX )                   \
    DO( AMI_PROXY_STATS_RELEASE_MUTEX )                \
    DO( AMI_PROXY_STATS_PDI_DOWNLOAD_MBOX_POST )       \
    DO( AMI_PROXY_STATS_PDI_COPY_MBOX_POST )           \
    DO( AMI_PROXY_STATS_SENSOR_MBOX_POST )             \
    DO( AMI_PROXY_STATS_IDENTITY_MBOX_POST )           \
    DO( AMI_PROXY_STATS_BOOT_SELECT_MBOX_POST )        \
    DO( AMI_PROXY_STATS_HEARTBEAT_MBOX_POST )          \
    DO( AMI_PROXY_STATS_EEPROM_RW_MBOX_POST )          \
    DO( AMI_PROXY_STATS_PEEK_POKE_MBOX_POST )          \
    DO( AMI_PROXY_STATS_UCORE_VERSION_MBOX_POST )      \
    DO( AMI_PROXY_STATS_MODULE_RW_MBOX_POST )          \
    DO( AMI_PROXY_STATS_DEBUG_VERBOSITY_MBOX_PEND )    \
    DO( AMI_PROXY_STATS_PDI_DOWNLOAD_MBOX_PEND )       \
    DO( AMI_PROXY_STATS_PDI_COPY_MBOX_PEND )           \
    DO( AMI_PROXY_STATS_SENSOR_MBOX_PEND )             \
    DO( AMI_PROXY_STATS_IDENTITY_MBOX_PEND )           \
    DO( AMI_PROXY_STATS_BOOT_SELECT_MBOX_PEND )        \
    DO( AMI_PROXY_STATS_HEARTBEAT_MBOX_PEND )          \
    DO( AMI_PROXY_STATS_EEPROM_RW_MBOX_PEND )          \
    DO( AMI_PROXY_STATS_PEEK_POKE_MBOX_PEND )          \
    DO( AMI_PROXY_STATS_UCORE_VERSION_MBOX_PEND )      \
    DO( AMI_PROXY_STATS_MODULE_RW_MBOX_PEND )          \
    DO( AMI_PROXY_STATS_GET_PDI_DOWNLOAD_REQUEST )     \
    DO( AMI_PROXY_STATS_GET_PDI_COPY_REQUEST )         \
    DO( AMI_PROXY_STATS_GET_SENSOR_REQUEST )           \
    DO( AMI_PROXY_STATS_GET_BOOT_SELECT_REQUEST )      \
    DO( AMI_PROXY_STATS_TASK_TIME_MS )                 \
    DO( AMI_PROXY_STATS_GET_EEPROM_RW_REQUEST )        \
    DO( AMI_PROXY_STATS_GET_PL_RW_REQUEST )            \
    DO( AMI_PROXY_STATS_STATUS_RETRIEVAL )             \
    DO( AMI_PROXY_STATS_GET_MODULE_RW_REQUEST )        \
    DO( AMI_PROXY_STATS_MAX )

#define AMI_PROXY_ERRORS( DO )    \
    DO( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )        \
    DO( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )           \
    DO( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )         \
    DO( AMI_PROXY_ERRORS_PDI_DOWNLOAD_REQUEST )        \
    DO( AMI_PROXY_ERRORS_PDI_COPY_REQUEST )            \
    DO( AMI_PROXY_ERRORS_EEPROM_RW_REQUEST )           \
    DO( AMI_PROXY_ERRORS_MODULE_RW_REQUEST )           \
    DO( AMI_PROXY_ERRORS_DEBUG_VERBOSITY_REQUEST )     \
    DO( AMI_PROXY_ERRORS_GET_SENSOR_REQUEST )          \
    DO( AMI_PROXY_ERRORS_GET_BOOT_SELECT_REQUEST )     \
    DO( AMI_PROXY_ERRORS_GET_HEARTBEAT_REQUEST )       \
    DO( AMI_PROXY_ERRORS_GET_EEPROM_RW_REQUEST )       \
    DO( AMI_PROXY_ERRORS_GET_MODULE_RW_REQUEST )       \
    DO( AMI_PROXY_ERRORS_GET_DEBUG_VERBOSITY_REQUEST ) \
    DO( AMI_PROXY_RAISE_EVENT_PDI_DOWNLOAD_FAILED )    \
    DO( AMI_PROXY_RAISE_EVENT_PDI_COPY_FAILED )        \
    DO( AMI_PROXY_RAISE_EVENT_GET_IDENTIFY_FAILED )    \
    DO( AMI_PROXY_RAISE_EVENT_GET_UCOREVER_FAILED )    \
    DO( AMI_PROXY_RAISE_EVENT_SENSOR_READ_FAILED )     \
    DO( AMI_PROXY_RAISE_EVENT_BOOT_SELECT_FAILED )     \
    DO( AMI_PROXY_RAISE_EVENT_HEARTBEAT_FAILED )       \
    DO( AMI_PROXY_RAISE_EVENT_EEPROM_RW_FAILED )       \
    DO( AMI_PROXY_RAISE_EVENT_MODULE_RW_FAILED )       \
    DO( AMI_PROXY_RAISE_EVENT_DEBUG_VERBOSITY_FAILED ) \
    DO( AMI_PROXY_INIT_FW_IF_OPEN_FAILED )             \
    DO( AMI_PROXY_INIT_MUTEX_CREATE_FAILED )           \
    DO( AMI_PROXY_INIT_MBOX_CREATE_FAILED )            \
    DO( AMI_PROXY_INIT_TASK_CREATE_FAILED )            \
    DO( AMI_PROXY_VALIDATION_FAILED )                  \
    DO( AMI_PROXY_UNSUPPORTED_OPCODE_RX )              \
    DO( AMI_PROXY_UNKNOWN_MAILBOX_MSG )                \
    DO( AMI_PROXY_UNKNOWN_RETURN_CODE )                \
    DO( AMI_PROXY_FW_IF_WRITE_FAILED )                 \
    DO( AMI_PROXY_BIND_CB_FAILED )                     \
    DO( AMI_PROXY_RX_DATA_INDEX_FAILED )               \
    DO( AMI_PROXY_ERRORS_INIT_EVL_RECORD_FAILED )      \
    DO( AMI_PROXY_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )             PLL_INF( AMI_NAME, "%50s . . . . %d\r\n",          \
                                                     AMI_PROXY_STATS_STR[ x ],                 \
                                                     pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x )            PLL_INF( AMI_NAME, "%50s . . . . %d\r\n",          \
                                                     AMI_PROXY_ERRORS_STR[ x ],                \
                                                     pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )               { if( x < AMI_PROXY_STATS_MAX )pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x )              { if( x < AMI_PROXY_ERRORS_MAX )pxThis->pulErrorCounters[ x ]++; }
#define INC_ERROR_COUNTER_WITH_STATE( x )   { pxThis->xState = MODULE_STATE_ERROR; INC_ERROR_COUNTER( x ) }
#define SET_STAT_COUNTER( x, y )            { if( x < AMI_PROXY_ERRORS_MAX )pxThis->pulStatCounters[ x ] = y; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    AMI_MSG_TYPES
 * @brief   Enumeration of mbox message types for this proxy
 */
typedef enum AMI_MSG_TYPES
{
    AMI_MSG_TYPE_PDI_DOWNLOAD_COMPLETE = 0,
    AMI_MSG_TYPE_PDI_COPY_COMPLETE,
    AMI_MSG_TYPE_SENSOR_COMPLETE,
    AMI_MSG_TYPE_IDENTITY_COMPLETE,
    AMI_MSG_TYPE_BOOT_SELECT_COMPLETE,
    AMI_MSG_TYPE_HEARTBEAT_COMPLETE,
    AMI_MSG_TYPE_EEPROM_RW_COMPLETE,
    AMI_MSG_TYPE_MODULE_RW_COMPLETE,
    AMI_MSG_TYPE_DEBUG_VERBOSITY_COMPLETE,
    AMI_MSG_TYPE_PEEK_POKE_COMPLETE,
    AMI_MSG_TYPE_UCORE_VERSION_COMPLETE,

    MAX_AMI_MSG_TYPE

} AMI_MSG_TYPES;

/**
 * @enum    AMI_CMD_OPCODE_REQ
 * @brief   Internal message opcode
 */
typedef enum AMI_CMD_OPCODE_REQ
{
    AMI_CMD_OPCODE_BOOT_SEL_REQ        = 0x0,
    AMI_CMD_OPCODE_HEARTBEAT_REQ       = 0x2,
    AMI_CMD_OPCODE_EEPROM_RW_REQ       = 0x3,
    AMI_CMD_OPCODE_MODULE_RW_REQ       = 0x4,
    AMI_CMD_OPCODE_DEBUG_VERBOSITY_REQ = 0x5,
    AMI_CMD_OPCODE_PDI_DOWNLOAD_REQ    = 0xA,
    AMI_CMD_OPCODE_SENSOR_REQ          = 0xC,
    AMI_CMD_OPCODE_PDI_COPY_REQ        = 0xD,
    AMI_CMD_OPCODE_IDENTIFY_REQ        = 0x202,
    AMI_CMD_OPCODE_UCORE_VERSION       = 0x203,
    AMI_CMD_OPCODE_PEEK_POKE           = 0xDEC,

    MAX_AMI_CMD_OPCODE

} AMI_CMD_OPCODE_REQ;

/**
 * @enum    AMI_CMD_STATE
 * @brief   Internal command state
 */
typedef enum AMI_CMD_STATE
{
    AMI_CMD_STATE_COMPLETED = 0,
    AMI_CMD_STATE_ABORTED,
    AMI_CMD_STATE_TIMEOUT,
    AMI_CMD_STATE_INVALID,
    AMI_CMD_STATE_CONFLICT_ID,

    MAX_AMI_CMD_STATE

} AMI_CMD_STATE;

/**
 * @enum    AMI_PROXY_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( AMI_PROXY_STATS, AMI_PROXY_STATS, AMI_PROXY_STATS_STR )

/**
 * @enum    AMI_PROXY_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( AMI_PROXY_ERRORS, AMI_PROXY_ERRORS, AMI_PROXY_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  AMI_RX_DATA
 * @brief   Structure to hold rx'd data received from FW_IF
 */
typedef struct AMI_RX_DATA
{
    uint8_t ucInUse;
    AMI_CMD_OPCODE_REQ xOpCode;
    uint16_t usCid;
    union
    {
        AMI_PROXY_PDI_DOWNLOAD_REQUEST     xDownloadRequest;
        AMI_PROXY_PDI_COPY_REQUEST         xCopyRequest;
        AMI_PROXY_SENSOR_REQUEST           xSensorRequest;
        AMI_PROXY_BOOT_SELECT_REQUEST      xBootSelectRequest;
        AMI_PROXY_EEPROM_RW_REQUEST        xEepromReadWriteRequest;
        AMI_PROXY_PEEK_POKE_REQUEST        xPeekPokeRequest;
        AMI_PROXY_MODULE_RW_REQUEST        xModuleReadWriteRequest;
        uint8_t                            ucDebugVerbosityRequest;
    };

} AMI_RX_DATA;

/**
 * @struct  AMI_PRIVATE_DATA
 * @brief   Structure to hold ths proxy driver's private data
 */
typedef struct AMI_PRIVATE_DATA
{
    uint32_t        ulUpperFirewall;

    int             iInitialised;
    uint8_t         ucMyId;

    FW_IF_CFG *     pxFwIf;
    uint32_t        ulFwIfPort;

    EVL_RECORD      *pxEvlRecord;

    void *          pvOsalMutexHdl;
    void *          pvOsalMBoxHdl;
    void *          pvOsalTaskHdl;

    AMI_RX_DATA     xRxData[ AMI_RXDATA_SIZE ];

    uint32_t        pulStatCounters[ AMI_PROXY_STATS_MAX ];
    uint32_t        pulErrorCounters[ AMI_PROXY_ERRORS_MAX ];

    MODULE_STATE    xState;

    uint32_t        ulLowerFirewall;

} AMI_PRIVATE_DATA;

/**
 * @struct  AMI_MBOX_MSG
 * @brief   Data posted via the AMI Proxy driver mailbox
 */
typedef struct AMI_MBOX_MSG
{
    AMI_MSG_TYPES eMsgType;
    uint8_t ucRxDataIndex;
    AMI_PROXY_RESULT xResult;
    union
    {
        AMI_PROXY_IDENTITY_RESPONSE xIdentity;
        AMI_PROXY_HEARTBEAT_RESPONSE xHeartbeat;
    };

} AMI_MBOX_MSG;

/**
 * @struct  AMI_CMD_RESPONSE_HDR
 * @brief   The command response header
 */
typedef struct AMI_CMD_RESPONSE_HDR
{
    union
    {
        struct
        {
            uint16_t usCid;
            uint16_t usCState:14;
            uint16_t usSpecific:1;
            uint16_t usState:1;
        };
        uint32_t ulHeader[ AMI_RESPONSE_HDR_SIZE ];
    };

} AMI_CMD_RESPONSE_HDR;

/**
 * @struct  AMI_CMD_RESPONSE
 * @brief   The command response header and payload
 */
typedef struct AMI_CMD_RESPONSE
{
    union
    {
        struct
        {
            AMI_CMD_RESPONSE_HDR xHdr;
            uint32_t ulPayload[ AMI_RESPONSE_PAYLOAD_SIZE ];
            uint32_t ulRCode;
        };
        uint32_t ulData[ AMI_RESPONSE_SIZE ];
    };

} AMI_CMD_RESPONSE;
STATIC_ASSERT( sizeof( AMI_CMD_RESPONSE ) == AMI_PROXY_RESPONSE_SIZE );

/**
 * @struct  AMI_CMD_REQUEST_HDR
 * @brief   The request header
 */
typedef struct AMI_CMD_REQUEST_HDR
{
    union
    {
        struct
        {
            uint32_t ulOpCode:16; /* [15-0]   */
            uint32_t ulCount:15;  /* [30-16] */
            uint32_t ulState:1;   /* [31] */
            uint16_t usCid;
            union
            {
                uint16_t usRsvd;
                struct
                {
                    uint16_t usCUIdx:12;
                    uint16_t usCUDomain:4;
                };
            };
        };
        uint32_t ulHeader[ AMI_REQUEST_HDR_SIZE ];
    };

} AMI_CMD_REQUEST_HDR;

/**
 * @struct  AMI_CMD_REQ_SENSOR_PAYLOAD
 * @brief   The sensor request payload
 */
typedef struct AMI_CMD_REQ_SENSOR_PAYLOAD
{
    uint64_t ullAddress;
    uint32_t ulSize;
    uint32_t ulOffset;
    uint32_t ulAID:8;
    uint32_t ulSID:8;
    uint32_t ulAddrType:3;
    uint32_t ulSensorId:8;
    uint32_t ulResvd:5;
    uint32_t ulPad;

} AMI_CMD_REQ_SENSOR_PAYLOAD;

/**
 * @struct  AMI_CMD_DATA_PAYLOAD
 * @brief   The data request payload
 */
typedef struct AMI_CMD_DATA_PAYLOAD
{
    uint64_t ullAddress;
    uint32_t ulSize;
    uint32_t ulRemainSize;
    uint32_t ulSrcPartition:4;
    uint32_t ulDestPartition:4;
    uint32_t ulPartitionSel:4;
    uint32_t ulUpdateFpt:1;
    uint32_t ulBootDevice:1;
    uint32_t ulSrcDevice:1;
    uint32_t ulDestDevice:1;
    uint32_t ulPartitionRsvd:16;
    uint16_t usLastPacket:1;
    uint16_t usPacketNum:15;
    uint16_t usPacketSize; /* packet size in KB */
    uint32_t ulPad;

} AMI_CMD_DATA_PAYLOAD;

/**
 * @struct  AMI_CMD_HEARTBEAT_PAYLOAD
 * @brief   The heartbeat payload
 */
typedef struct AMI_CMD_HEARTBEAT_PAYLOAD
{
    uint8_t ucHeartbeatCount;

} AMI_CMD_HEARTBEAT_PAYLOAD;

/**
 * @struct  AMI_CMD_EEPROM_PAYLOAD
 * @brief   The eeprom payload
 */
typedef struct AMI_CMD_EEPROM_PAYLOAD
{
    uint64_t ullAddress;
    uint32_t ucReqType:1;
    uint32_t ucLen:8;
    uint32_t ucOffset:8;
    uint32_t ucReserved:15;

} AMI_CMD_EEPROM_PAYLOAD;

/**
 * @struct  AMI_CMD_PEEK_POKE_PAYLOAD
 * @brief   The peek/poke payload
 */
typedef struct AMI_CMD_PEEK_POKE_PAYLOAD
{
    uint64_t ullAddress;
    uint32_t ucReqType:1;
    uint32_t ucLen:8;
    uint32_t ucOffset:20;
    uint32_t ucReserved:3;

} AMI_CMD_PEEK_POKE_PAYLOAD;

/**
 * @struct  AMI_CMD_MODULE_PAYLOAD
 * @brief   The module payload
 */
typedef struct AMI_CMD_MODULE_PAYLOAD
{
    uint64_t ullAddress;
    uint8_t  ucExDeviceId;
    uint8_t  ucPage;
    uint8_t  ucByteOffset;
    uint8_t  ucLen;
    uint32_t ulReqType:1;
    uint32_t ulReserved:31;

} AMI_CMD_MODULE_PAYLOAD;

/**
 * @struct  AMI_CMD_REQUEST
 * @brief   The request command header & payload
 */
typedef struct AMI_CMD_REQUEST
{
    struct AMI_CMD_REQUEST_HDR xHdr;
    union
    {
        AMI_CMD_REQ_SENSOR_PAYLOAD xSensorPayload;
        AMI_CMD_DATA_PAYLOAD xPdiDownloadPayload;
        AMI_CMD_DATA_PAYLOAD xPdiCopyPayload;
        AMI_CMD_DATA_PAYLOAD xBootSelect;
        AMI_CMD_HEARTBEAT_PAYLOAD xHeartbeatPayload;
        AMI_CMD_EEPROM_PAYLOAD xEepromPayload;
        AMI_CMD_PEEK_POKE_PAYLOAD xPeekPokePayload;
        AMI_CMD_MODULE_PAYLOAD xModulePayload;
        uint8_t ucDebugVerbosityPayload;
    };

} AMI_CMD_REQUEST;
STATIC_ASSERT( sizeof( AMI_CMD_RESPONSE ) < AMI_PROXY_REQUEST_SIZE );


/******************************************************************************/
/* Local Variables                                                            */
/******************************************************************************/

static AMI_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,             /* ulUpperFirewall */
    FALSE,                      /* iInitialised */
    0,                          /* ucMyId */
    NULL,                       /* pxFwIf */
    0,                          /* ulFwIfPort */
    NULL,                       /* pxEvlRecord */
    NULL,                       /* pvOsalMutexHdl */
    NULL,                       /* pvOsalMBoxHdl */
    NULL,                       /* pvOsalTaskHdl */
    { { 0 } },                  /* xRxData */
    { 0 },                      /* pulStatCounters */
    { 0 },                      /* pulErrorCounters */
    MODULE_STATE_UNINITIALISED, /* xState */
    LOWER_FIREWALL              /* ulLowerFirewall */
};
static AMI_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Local Function Declarations                                                */
/******************************************************************************/

/**
 * @brief   Task declaration
 *
 * @param   pvArgs  Pointer to task args (unused)
 *
 * @return  N/A
 *
 */
static void vProxyDriverTask( void *pvArgs );

/**
 * @brief   Find the next free data index
 *
 * @param   pucIndex The next free index
 *
 * @return  OK/ERROR
 *
 */
static int iFindNextFreeRxDataIndex( uint8_t *pucIndex );

/**
 * @brief   Handle the heartbeat request
 *
 * @param   pxCmdRequest The request details
 *
 * @return  OK/ERROR
 *
 */
static int iHandleHeartbeatRequest( AMI_CMD_REQUEST *pxCmdRequest );

/**
 * @brief   Handle the eeprom request
 *
 * @param   pxCmdRequest The request details
 *
 * @return  OK/ERROR
 *
 */
static int iHandleEepromRequest( AMI_CMD_REQUEST *pxCmdRequest );

/**
 * @brief   Handle the HPU register read/write request
 *
 * @param   pxCmdRequest The request details
 *
 * @return  OK/ERROR
 *
 */
static int iHandlePeekPokeRequest( AMI_CMD_REQUEST *pxCmdRequest );

/**
 * @brief   Handle the module request
 *
 * @param   pxCmdRequest The request details
 *
 * @return  OK/ERROR
 *
 */
static int iHandleModuleRequest( AMI_CMD_REQUEST *pxCmdRequest );

/**
 * @brief   Handle the debug verbosity request
 *
 * @param   pxCmdRequest The request details
 *
 * @return  OK/ERROR
 *
 */
static int iHandleDebugVerbosityRequest( AMI_CMD_REQUEST *pxCmdRequest );


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/
/* Init Functions *************************************************************/

/**
 * @brief   Main initialisation point for the AMI Proxy Driver
 */
int iAMI_Initialise( uint8_t ucProxyId, FW_IF_CFG *pxFwIf, uint32_t ulFwIfPort,
                     uint32_t ulTaskPrio, uint32_t ulTaskStack )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) &&
        ( NULL != pxFwIf ) )
    {
        /* Store parameters locally */
        pxThis->ucMyId     = ucProxyId;
        pxThis->pxFwIf     = pxFwIf;
        pxThis->ulFwIfPort = ulFwIfPort;

        /* initalise evl record*/
        if ( OK != iEVL_CreateRecord( &pxThis->pxEvlRecord ) )
        {
            PLL_ERR( AMI_NAME, "Error initialising EVL_RECORD\r\n" );
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_INIT_EVL_RECORD_FAILED );
        }
        else
        {

            if( FW_IF_ERRORS_NONE != pxThis->pxFwIf->open( pxThis->pxFwIf ) )
            {
                PLL_ERR( AMI_NAME, "Error opening FW_IF\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_INIT_FW_IF_OPEN_FAILED )
            }
            else
            {
                /* Initialise OSAL items */
                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvOsalMutexHdl,
                                                                "ami_proxy mutex" ) )
                {
                    PLL_ERR( AMI_NAME, "Error initialising mutex\r\n" );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_INIT_MUTEX_CREATE_FAILED )
                }
                else if( OSAL_ERRORS_NONE != iOSAL_MBox_Create( &pxThis->pvOsalMBoxHdl, AMI_MBOX_SIZE,
                                                    sizeof( AMI_MBOX_MSG ), "ami_proxy mbox" ) )
                {
                    PLL_ERR( AMI_NAME, "Error initialising mbox\r\n" );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_INIT_MBOX_CREATE_FAILED )
                }
                else if( OSAL_ERRORS_NONE != iOSAL_Task_Create( &pxThis->pvOsalTaskHdl,
                                                                vProxyDriverTask,
                                                                ulTaskStack,
                                                                NULL,
                                                                ulTaskPrio,
                                                                "ami_proxy task" ) )
                {
                    PLL_ERR( AMI_NAME, "Error initialising task\r\n" );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_INIT_TASK_CREATE_FAILED )
                }
                else
                {
                    INC_STAT_COUNTER( AMI_PROXY_STATS_CREATE_MUTEX )
                    INC_STAT_COUNTER( AMI_PROXY_STATS_CREATE_MBOX )
                    INC_STAT_COUNTER( AMI_PROXY_STATS_INIT_OVERALL_COMPLETE )
                    pxThis->iInitialised = TRUE;
                    pxThis->xState = MODULE_STATE_OK;
                    iStatus = OK;
                }
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Bind into this proxy driver
 */
int iAMI_BindCallback( EVL_CALLBACK *pxCallback )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxCallback ) &&
        ( NULL != pxThis->pxEvlRecord ) )
    {
        iStatus = iEVL_BindCallback( pxThis->pxEvlRecord, pxCallback );
        if( ERROR == iStatus )
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_BIND_CB_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}


/* Set Functions **************************************************************/

/**
 * Set the pdi download response once complete
 */
int iAMI_SetPdiDownloadCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxSignal ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        AMI_MBOX_MSG xMsg = { 0 };
        xMsg.ucRxDataIndex = pxSignal->ucInstance;
        xMsg.eMsgType = AMI_MSG_TYPE_PDI_DOWNLOAD_COMPLETE;
        xMsg.xResult = xResult;
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
                                                 ( void* )&xMsg,
                                                 OSAL_TIMEOUT_NO_WAIT ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_PDI_DOWNLOAD_MBOX_POST )
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * Set the pdi copy response once complete
 */
int iAMI_SetPdiCopyCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxSignal ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        AMI_MBOX_MSG xMsg = { 0 };
        xMsg.ucRxDataIndex = pxSignal->ucInstance;
        xMsg.eMsgType = AMI_MSG_TYPE_PDI_COPY_COMPLETE;
        xMsg.xResult = xResult;
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
                                                 ( void* )&xMsg,
                                                 OSAL_TIMEOUT_NO_WAIT ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_PDI_COPY_MBOX_POST )
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * Set the sensor response once the data has been read
 */
int iAMI_SetSensorCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxSignal ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        AMI_MBOX_MSG xMsg = { 0 };
        xMsg.ucRxDataIndex = pxSignal->ucInstance;
        xMsg.eMsgType = AMI_MSG_TYPE_SENSOR_COMPLETE;
        xMsg.xResult = xResult;
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
                                                 ( void* )&xMsg,
                                                 OSAL_TIMEOUT_NO_WAIT ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_SENSOR_MBOX_POST )
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set the identity major/minor response
 */
int iAMI_SetIdentityResponse( EVL_SIGNAL *pxSignal,
                              AMI_PROXY_RESULT xResult,
                              AMI_PROXY_IDENTITY_RESPONSE *pxIdentityResponse )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) &&
        ( NULL != pxIdentityResponse ) )
    {
        AMI_MBOX_MSG xMsg = { 0 };
        xMsg.ucRxDataIndex = pxSignal->ucInstance;
        xMsg.eMsgType = AMI_MSG_TYPE_IDENTITY_COMPLETE;
        xMsg.xResult = xResult;
        pvOSAL_MemCpy( &xMsg.xIdentity, pxIdentityResponse, sizeof( xMsg.xIdentity ) );
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
                                                 ( void* )&xMsg,
                                                 OSAL_TIMEOUT_NO_WAIT ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_IDENTITY_MBOX_POST )
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set the boot select response
 */
int iAMI_SetBootSelectCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) )
    {
        AMI_MBOX_MSG xMsg = { 0 };
        xMsg.ucRxDataIndex = pxSignal->ucInstance;
        xMsg.eMsgType = AMI_MSG_TYPE_BOOT_SELECT_COMPLETE;
        xMsg.xResult = xResult;
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
                                                 ( void* )&xMsg,
                                                 OSAL_TIMEOUT_NO_WAIT ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_BOOT_SELECT_MBOX_POST )
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set the EEPROM read/write response
 */
int iAMI_SetEepromReadWriteCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) )
    {
        AMI_MBOX_MSG xMsg = { 0 };
        xMsg.ucRxDataIndex = pxSignal->ucInstance;
        xMsg.eMsgType = AMI_MSG_TYPE_EEPROM_RW_COMPLETE;
        xMsg.xResult = xResult;
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
                                                 ( void* )&xMsg,
                                                 OSAL_TIMEOUT_NO_WAIT ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_EEPROM_RW_MBOX_POST )
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set the Peek/Poke response
 */
int iAMI_SetPeekPokeReadWriteCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult ) {
    int iStatus = ERROR;

    PLL_INF("AMC", "iAMI_SetPeekPokeReadWriteCompleteResponse");

    if( NULL != pxSignal ) {
        AMI_MBOX_MSG xMsg = { 0 };
        xMsg.ucRxDataIndex = pxSignal->ucInstance;
        xMsg.eMsgType = AMI_MSG_TYPE_PEEK_POKE_COMPLETE;
        xMsg.xResult = xResult;
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Post(
            pxThis->pvOsalMBoxHdl,
            ( void* )&xMsg,
            OSAL_TIMEOUT_NO_WAIT)
        ) {
            INC_STAT_COUNTER( AMI_PROXY_STATS_PEEK_POKE_MBOX_POST )
            iStatus = OK;
        } else {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
        }
    } else {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }
    return iStatus;
}

/**
 * @brief   Set the ucore version response
 */
int iAMI_SetUcoreVersionCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult ) {
    int iStatus = ERROR;

    PLL_INF("AMC", "iAMI_SetUcoreVersionReadCompleteResponse");

    if( NULL != pxSignal ) {
        AMI_MBOX_MSG xMsg = { 0 };
        xMsg.ucRxDataIndex = pxSignal->ucInstance;
        xMsg.eMsgType = AMI_MSG_TYPE_UCORE_VERSION_COMPLETE;
        xMsg.xResult = xResult;
	xMsg.xIdentity.ucVerMajor = (UCORE_VERSION_MAJOR & 0xFF);
	xMsg.xIdentity.ucVerMinor = (UCORE_VERSION_MINOR & 0xFF);
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Post(
            pxThis->pvOsalMBoxHdl,
            ( void* )&xMsg,
            OSAL_TIMEOUT_NO_WAIT)
        ) {
            INC_STAT_COUNTER( AMI_PROXY_STATS_UCORE_VERSION_MBOX_POST )
            iStatus = OK;
        } else {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
        }
    } else {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }
    return iStatus;
}

/**
 * @brief   Set the module read/write response
 */
int iAMI_SetModuleReadWriteCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) )
    {
        AMI_MBOX_MSG xMsg = { 0 };
        xMsg.ucRxDataIndex = pxSignal->ucInstance;
        xMsg.eMsgType = AMI_MSG_TYPE_MODULE_RW_COMPLETE;
        xMsg.xResult = xResult;
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
                                                 ( void* )&xMsg,
                                                 OSAL_TIMEOUT_NO_WAIT ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_MODULE_RW_MBOX_POST )
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set the debug verbosity response
 */
int iAMI_SetDebugVerbosityResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) )
    {
        AMI_MBOX_MSG xMsg = { 0 };
        xMsg.ucRxDataIndex = pxSignal->ucInstance;
        xMsg.eMsgType = AMI_MSG_TYPE_DEBUG_VERBOSITY_COMPLETE;
        xMsg.xResult = xResult;
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
                                                 ( void* )&xMsg,
                                                 OSAL_TIMEOUT_NO_WAIT ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_MODULE_RW_MBOX_POST )
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/* Get Functions **************************************************************/

/**
 * @brief   Get the data associated with the PDI download
 */
int iAMI_GetPdiDownloadRequest( EVL_SIGNAL *pxSignal,
                                AMI_PROXY_PDI_DOWNLOAD_REQUEST *pxDownloadRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) &&
        ( NULL != pxDownloadRequest ) )
    {
        INC_STAT_COUNTER( AMI_PROXY_STATS_GET_PDI_DOWNLOAD_REQUEST )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            uint8_t ucIndex = pxSignal->ucInstance;

            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            if( AMI_CHECK_VALID_INDEX( ucIndex ) &&
                ( TRUE == pxThis->xRxData[ ucIndex ].ucInUse ) &&
                AMI_CMD_OPCODE_PDI_DOWNLOAD_REQ == pxThis->xRxData[ ucIndex ].xOpCode )
            {
                pxDownloadRequest->iBootDevice =
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.iBootDevice;
                pxDownloadRequest->ullAddress =
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.ullAddress;
                pxDownloadRequest->ulLength =
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.ulLength;
                pxDownloadRequest->ulPartitionSel =
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.ulPartitionSel;
                pxDownloadRequest->usPacketNum =
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.usPacketNum;
                pxDownloadRequest->usPacketSize =
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.usPacketSize;
                pxDownloadRequest->iUpdateFpt =
                             pxThis->xRxData[ ucIndex ].xDownloadRequest.iUpdateFpt;
                pxDownloadRequest->iLastPacket =
                             pxThis->xRxData[ ucIndex ].xDownloadRequest.iLastPacket;
                iStatus = OK;
            }
            else
            {
                PLL_ERR( AMI_NAME, "Error invalid PDI download request for instance\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_PDI_DOWNLOAD_REQUEST )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Get the data associated with the PDI copy
 */
int iAMI_GetPdiCopyRequest( EVL_SIGNAL *pxSignal,
                            AMI_PROXY_PDI_COPY_REQUEST *pxCopyRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) &&
        ( NULL != pxCopyRequest ) )
    {
        INC_STAT_COUNTER( AMI_PROXY_STATS_GET_PDI_COPY_REQUEST )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            uint8_t ucIndex = pxSignal->ucInstance;

            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            if( AMI_CHECK_VALID_INDEX( ucIndex ) &&
                ( TRUE == pxThis->xRxData[ ucIndex ].ucInUse ) &&
                AMI_CMD_OPCODE_PDI_COPY_REQ == pxThis->xRxData[ ucIndex ].xOpCode )
            {
                pxCopyRequest->ullAddress =
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ullAddress;
                pxCopyRequest->ulMaxLength =
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ulMaxLength;
                pxCopyRequest->ulSrcDevice =
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ulSrcDevice;
                pxCopyRequest->ulSrcPartition =
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ulSrcPartition;
                pxCopyRequest->ulDestDevice =
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ulDestDevice;
                pxCopyRequest->ulDestPartition =
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ulDestPartition;
                iStatus = OK;
            }
            else
            {
                PLL_ERR( AMI_NAME, "Error invalid PDI copy request for instance\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_PDI_COPY_REQUEST )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Get the data associated with the sensor
 */
int iAMI_GetSensorRequest( EVL_SIGNAL *pxSignal,
                           AMI_PROXY_SENSOR_REQUEST *pxSensorRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) &&
        ( NULL != pxSensorRequest ) )
    {
        INC_STAT_COUNTER( AMI_PROXY_STATS_GET_SENSOR_REQUEST )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            uint8_t ucIndex = pxSignal->ucInstance;

            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            if( AMI_CHECK_VALID_INDEX( ucIndex ) &&
                ( TRUE == pxThis->xRxData[ ucIndex ].ucInUse ) &&
                AMI_CMD_OPCODE_SENSOR_REQ == pxThis->xRxData[ ucIndex ].xOpCode )
            {
                pxSensorRequest->ullAddress =
                            pxThis->xRxData[ ucIndex ].xSensorRequest.ullAddress;
                pxSensorRequest->ulLength =
                            pxThis->xRxData[ ucIndex ].xSensorRequest.ulLength;
                pxSensorRequest->ulSensorId =
                            pxThis->xRxData[ ucIndex ].xSensorRequest.ulSensorId;
                pxSensorRequest->xRepo =
                            pxThis->xRxData[ ucIndex ].xSensorRequest.xRepo;
                pxSensorRequest->xRequest =
                            pxThis->xRxData[ ucIndex ].xSensorRequest.xRequest;
                iStatus = OK;
            }
            else
            {
                PLL_ERR( AMI_NAME, "Error invalid get sensor request for instance\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_GET_SENSOR_REQUEST )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Get the boot selection request
 */
int iAMI_GetBootSelectRequest( EVL_SIGNAL *pxSignal,
                               AMI_PROXY_BOOT_SELECT_REQUEST *pxBootSelectRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) &&
        ( NULL != pxBootSelectRequest ) )
    {
        INC_STAT_COUNTER( AMI_PROXY_STATS_GET_BOOT_SELECT_REQUEST )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            uint8_t ucIndex = pxSignal->ucInstance;

            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            if( AMI_CHECK_VALID_INDEX( ucIndex ) &&
                ( TRUE == pxThis->xRxData[ ucIndex ].ucInUse ) &&
                AMI_CMD_OPCODE_BOOT_SEL_REQ == pxThis->xRxData[ ucIndex ].xOpCode )
            {
                pxBootSelectRequest->ulPartitionSel =
                            pxThis->xRxData[ ucIndex ].xBootSelectRequest.ulPartitionSel;
                iStatus = OK;
            }
            else
            {
                PLL_ERR( AMI_NAME, "Error invalid get boot select request for instance\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_GET_BOOT_SELECT_REQUEST )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Get the eeprom read write request
 */
int iAMI_GetEepromReadWriteRequest( EVL_SIGNAL *pxSignal,
                                    AMI_PROXY_EEPROM_RW_REQUEST *pxEepromReadWriteRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) &&
        ( NULL != pxEepromReadWriteRequest ) )
    {
        INC_STAT_COUNTER( AMI_PROXY_STATS_GET_EEPROM_RW_REQUEST )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            uint8_t ucIndex = pxSignal->ucInstance;

            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            if( AMI_CHECK_VALID_INDEX( ucIndex ) &&
                ( TRUE == pxThis->xRxData[ ucIndex ].ucInUse ) &&
                AMI_CMD_OPCODE_EEPROM_RW_REQ == pxThis->xRxData[ ucIndex ].xOpCode )
            {
                pxEepromReadWriteRequest->xRequest =
                            pxThis->xRxData[ ucIndex ].xEepromReadWriteRequest.xRequest;
                pxEepromReadWriteRequest->ullAddress =
                            pxThis->xRxData[ ucIndex ].xEepromReadWriteRequest.ullAddress;
                pxEepromReadWriteRequest->ulLength =
                            pxThis->xRxData[ ucIndex ].xEepromReadWriteRequest.ulLength;
                pxEepromReadWriteRequest->ulOffset =
                            pxThis->xRxData[ ucIndex ].xEepromReadWriteRequest.ulOffset;

                iStatus = OK;
            }
            else
            {
                PLL_ERR( AMI_NAME, "Error invalid get eeprom request for instance\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_EEPROM_RW_REQUEST )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Get the HPÜ registers read write requests
 */
int iAMI_GetPeekPokeRequest(
    EVL_SIGNAL *pxSignal,
    AMI_PROXY_PEEK_POKE_REQUEST *pxPeekPokeRequest
) {
    int iStatus = ERROR;

    if((NULL != pxSignal) && (NULL != pxPeekPokeRequest)) {
        INC_STAT_COUNTER( AMI_PROXY_STATS_GET_PL_RW_REQUEST )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_WAIT_FOREVER)) {
            uint8_t ucIndex = pxSignal->ucInstance;

            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            if( AMI_CHECK_VALID_INDEX( ucIndex ) && ( TRUE == pxThis->xRxData[ ucIndex ].ucInUse ) && AMI_CMD_OPCODE_PEEK_POKE == pxThis->xRxData[ ucIndex ].xOpCode ) {
                pxPeekPokeRequest->xRequest   = pxThis->xRxData[ ucIndex ].xPeekPokeRequest.xRequest;
                pxPeekPokeRequest->ullAddress = pxThis->xRxData[ ucIndex ].xPeekPokeRequest.ullAddress;
                pxPeekPokeRequest->ulLength   = pxThis->xRxData[ ucIndex ].xPeekPokeRequest.ulLength;
                pxPeekPokeRequest->ulOffset   = pxThis->xRxData[ ucIndex ].xPeekPokeRequest.ulOffset;
                iStatus = OK;
            } else {
                PLL_ERR( AMI_NAME, "Error invalid peek poke instance\r\n" );
            }

            if (OSAL_ERRORS_NONE != iOSAL_Mutex_Release(pxThis->pvOsalMutexHdl)) {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            } else {
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
            }
        } else {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    } else {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }
    return iStatus;
}

/**
 * @brief   Get the module read write request
 */
int iAMI_GetModuleReadWriteRequest( EVL_SIGNAL *pxSignal,
                                    AMI_PROXY_MODULE_RW_REQUEST *pxModuleReadWriteRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) &&
        ( NULL != pxModuleReadWriteRequest ) )
    {
        INC_STAT_COUNTER( AMI_PROXY_STATS_GET_MODULE_RW_REQUEST )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            uint8_t ucIndex = pxSignal->ucInstance;

            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            if( AMI_CHECK_VALID_INDEX( ucIndex ) &&
                ( TRUE == pxThis->xRxData[ ucIndex ].ucInUse ) &&
                ( AMI_CMD_OPCODE_MODULE_RW_REQ == pxThis->xRxData[ ucIndex ].xOpCode ) )
            {
                pxModuleReadWriteRequest->xRequest =
                            pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.xRequest;
                pxModuleReadWriteRequest->ullAddress =
                            pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.ullAddress;
                pxModuleReadWriteRequest->ucExDeviceId =
                            pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.ucExDeviceId;
                pxModuleReadWriteRequest->ucPage =
                            pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.ucPage;
                pxModuleReadWriteRequest->ucByteOffset =
                            pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.ucByteOffset;
                pxModuleReadWriteRequest->ucLength =
                            pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.ucLength;

                iStatus = OK;
            }
            else
            {
                PLL_ERR( AMI_NAME, "Error invalid get module request for instance\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MODULE_RW_REQUEST )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Get the debug verbosity request
 */
int iAMI_GetDebugVerbosityRequest( EVL_SIGNAL *pxSignal,
                                   uint8_t *pucDebugVerbosityRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) &&
        ( NULL != pucDebugVerbosityRequest ) )
    {
        INC_STAT_COUNTER( AMI_PROXY_STATS_GET_MODULE_RW_REQUEST )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            uint8_t ucIndex = pxSignal->ucInstance;

            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            if( AMI_CHECK_VALID_INDEX( ucIndex ) &&
                ( TRUE == pxThis->xRxData[ ucIndex ].ucInUse ) &&
                ( AMI_CMD_OPCODE_DEBUG_VERBOSITY_REQ == pxThis->xRxData[ ucIndex ].xOpCode ) )
            {
                *pucDebugVerbosityRequest = pxThis->xRxData[ ucIndex ].ucDebugVerbosityRequest;
                iStatus = OK;
            }
            else
            {
                PLL_ERR( AMI_NAME, "Error invalid get module request for instance\r\n" );
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_DEBUG_VERBOSITY_REQUEST )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iAMI_PrintStatistics( void )
{
     int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( AMI_NAME, "============================================================\n\r" );
        PLL_INF( AMI_NAME, "AMI Proxy Statistics:\n\r" );
        for( i = 0; i < AMI_PROXY_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( AMI_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( AMI_NAME, "AMI Proxy Errors:\n\r" );
        for( i = 0; i < AMI_PROXY_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( AMI_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iAMI_ClearStatistics( void )
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
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Gets the current state of the proxy
 */
int iAMI_GetState( MODULE_STATE *pxState )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxState ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_TASK_WAIT_MS ) )
        {
            *pxState = pxThis->xState;

            INC_STAT_COUNTER( AMI_PROXY_STATS_STATUS_RETRIEVAL )

            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }

        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            iStatus = ERROR;
        }
        else
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}


/******************************************************************************/
/* Local Function Implementations                                             */
/******************************************************************************/

/**
 * @brief   Task to handle incoming requests and handle responses being send
 *          out the message queue.
 */
static void vProxyDriverTask( void *pvArgs )
{
    AMI_MBOX_MSG xMBoxData = { 0 };
    AMI_CMD_REQUEST xCmdRequest = { { { { 0 } } } };
    uint32_t ulStartMs = 0;

    FOREVER
    {
        ulStartMs = ulOSAL_GetUptimeMs();
        uint32_t ulCmdRequestSize = sizeof(AMI_CMD_REQUEST);

        /* Check on incoming FW_IF data (rx path) */
        if( FW_IF_ERRORS_NONE == pxThis->pxFwIf->read( pxThis->pxFwIf, ( uint64_t )pxThis->ulFwIfPort,
                                                       ( uint8_t* )&xCmdRequest, &ulCmdRequestSize,
                                                       FW_IF_TIMEOUT_NO_WAIT ) )
        {
            int iStatus = ERROR;
            uint8_t ucIndex = 0;

            /* Handle request based on opcode, Store data internally and raise event */
            switch( xCmdRequest.xHdr.ulOpCode )
            {
                case AMI_CMD_OPCODE_PDI_DOWNLOAD_REQ:
                {
                    if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                              OSAL_TIMEOUT_WAIT_FOREVER ) )
                    {
                        INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

                        iStatus = iFindNextFreeRxDataIndex( &ucIndex );
                        if( ERROR != iStatus )
                        {
                            pxThis->xRxData[ ucIndex ].usCid = xCmdRequest.xHdr.usCid;
                            pxThis->xRxData[ ucIndex ].xOpCode = xCmdRequest.xHdr.ulOpCode;
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.iBootDevice =
                                                                xCmdRequest.xPdiDownloadPayload.ulBootDevice;
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.ullAddress =
                                                                xCmdRequest.xPdiDownloadPayload.ullAddress;
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.ulLength =
                                                                xCmdRequest.xPdiDownloadPayload.ulSize;
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.ulPartitionSel =
                                                                xCmdRequest.xPdiDownloadPayload.ulPartitionSel;
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.usPacketNum =
                                                                xCmdRequest.xPdiDownloadPayload.usPacketNum;
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.usPacketSize =
                                                                xCmdRequest.xPdiDownloadPayload.usPacketSize;
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.iUpdateFpt =
                                                                xCmdRequest.xPdiDownloadPayload.ulUpdateFpt;
                            pxThis->xRxData[ ucIndex ].xDownloadRequest.iLastPacket =
                                                                xCmdRequest.xPdiDownloadPayload.usLastPacket;
                            pxThis->xRxData[ ucIndex ].ucInUse = TRUE;
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
                        }

                        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                        }

                        if( ERROR != iStatus )
                        {
                            INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )

                            /* Raise event using the index as the method to track the event */
                            EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                                    AMI_PROXY_DRIVER_E_PDI_DOWNLOAD_START,
                                                    ucIndex,
                                                    0 };
                            iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                            if( ERROR == iStatus )
                            {
                                PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                                         AMI_PROXY_DRIVER_E_PDI_DOWNLOAD_START );
                                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_PDI_DOWNLOAD_FAILED )
                            }
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
                    }
                    break;
                }
                case AMI_CMD_OPCODE_PDI_COPY_REQ:
                {
                    if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                              OSAL_TIMEOUT_WAIT_FOREVER ) )
                    {
                        INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

                        iStatus = iFindNextFreeRxDataIndex( &ucIndex );
                        if( ERROR != iStatus )
                        {
                            pxThis->xRxData[ ucIndex ].usCid = xCmdRequest.xHdr.usCid;
                            pxThis->xRxData[ ucIndex ].xOpCode = xCmdRequest.xHdr.ulOpCode;
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ullAddress =
                                                                xCmdRequest.xPdiCopyPayload.ullAddress;
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ulMaxLength =
                                                                xCmdRequest.xPdiCopyPayload.ulSize;
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ulSrcDevice =
                                                                xCmdRequest.xPdiCopyPayload.ulSrcDevice;
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ulSrcPartition =
                                                                xCmdRequest.xPdiCopyPayload.ulSrcPartition;
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ulDestDevice =
                                                                xCmdRequest.xPdiCopyPayload.ulDestDevice;
                            pxThis->xRxData[ ucIndex ].xCopyRequest.ulDestPartition =
                                                                xCmdRequest.xPdiCopyPayload.ulDestPartition;
                            pxThis->xRxData[ ucIndex ].ucInUse = TRUE;
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
                        }

                        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                        }

                        if( ERROR != iStatus )
                        {
                            INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )

                            /* Raise event using the index as the method to track the event */
                            EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                                    AMI_PROXY_DRIVER_E_PDI_COPY_START,
                                                    ucIndex,
                                                    0 };
                            iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                            if( ERROR == iStatus )
                            {
                                PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                                         AMI_PROXY_DRIVER_E_PDI_COPY_START );
                                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_PDI_COPY_FAILED )
                            }
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
                    }
                    break;
                }
                case AMI_CMD_OPCODE_SENSOR_REQ:
                {
                    if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                              OSAL_TIMEOUT_WAIT_FOREVER ) )
                    {
                        INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

                        iStatus = iFindNextFreeRxDataIndex( &ucIndex );
                        if( ERROR != iStatus )
                        {
                            pxThis->xRxData[ ucIndex ].usCid = xCmdRequest.xHdr.usCid;
                            pxThis->xRxData[ ucIndex ].xOpCode = xCmdRequest.xHdr.ulOpCode;
                            pxThis->xRxData[ ucIndex ].xSensorRequest.ullAddress =
                                                            xCmdRequest.xSensorPayload.ullAddress;
                            pxThis->xRxData[ ucIndex ].xSensorRequest.ulLength =
                                                            xCmdRequest.xSensorPayload.ulSize;
                            pxThis->xRxData[ ucIndex ].xSensorRequest.ulSensorId =
                                                            xCmdRequest.xSensorPayload.ulSensorId;
                            pxThis->xRxData[ ucIndex ].xSensorRequest.xRepo =
                                                            xCmdRequest.xSensorPayload.ulSID;
                            pxThis->xRxData[ ucIndex ].xSensorRequest.xRequest =
                                                            xCmdRequest.xSensorPayload.ulAID;
                            pxThis->xRxData[ ucIndex ].ucInUse = TRUE;
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
                        }

                        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                        }

                        if( ERROR != iStatus )
                        {
                            INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )

                            /* Raise event using the index as the method to track the event */
                            EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                                    AMI_PROXY_DRIVER_E_SENSOR_READ, ucIndex, 0 };
                            iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                            if( ERROR == iStatus )
                            {
                                PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                                         AMI_PROXY_DRIVER_E_SENSOR_READ );
                                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_SENSOR_READ_FAILED )
                            }
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
                    }
                    break;
                }
                case AMI_CMD_OPCODE_IDENTIFY_REQ:
                {
                    if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                              OSAL_TIMEOUT_WAIT_FOREVER ) )
                    {
                        INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

                        iStatus = iFindNextFreeRxDataIndex( &ucIndex );
                        if( ERROR != iStatus )
                        {
                            pxThis->xRxData[ ucIndex ].usCid = xCmdRequest.xHdr.usCid;
                            pxThis->xRxData[ ucIndex ].xOpCode = xCmdRequest.xHdr.ulOpCode;
                            pxThis->xRxData[ ucIndex ].ucInUse = TRUE;
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
                        }

                        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                        }

                        if( ERROR != iStatus )
                        {
                            INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )

                            /* Raise event using the index as the method to track the event */
                            EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                                    AMI_PROXY_DRIVER_E_GET_IDENTITY,
                                                    ucIndex,
                                                    0 };
                            iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                            if( ERROR == iStatus )
                            {
                                PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                                         AMI_PROXY_DRIVER_E_GET_IDENTITY );
                                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_GET_IDENTIFY_FAILED )
                            }
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
                    }
                    break;
                }
                case AMI_CMD_OPCODE_BOOT_SEL_REQ:
                {
                    if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                              OSAL_TIMEOUT_WAIT_FOREVER ) )
                    {
                        INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

                        iStatus = iFindNextFreeRxDataIndex( &ucIndex );
                        if( ERROR != iStatus )
                        {
                            pxThis->xRxData[ ucIndex ].usCid = xCmdRequest.xHdr.usCid;
                            pxThis->xRxData[ ucIndex ].xOpCode = xCmdRequest.xHdr.ulOpCode;
                            pxThis->xRxData[ ucIndex ].xBootSelectRequest.ulPartitionSel =
                                                            xCmdRequest.xBootSelect.ulPartitionSel;
                            pxThis->xRxData[ ucIndex ].ucInUse = TRUE;
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
                        }

                        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                        }

                        if( ERROR != iStatus )
                        {
                            INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )

                            /* Raise event using the index as the method to track the event */
                            EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                                    AMI_PROXY_DRIVER_E_BOOT_SELECT,
                                                    ucIndex,
                                                    0 };
                            iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                            if( ERROR == iStatus )
                            {
                                PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                                         AMI_PROXY_DRIVER_E_BOOT_SELECT );
                                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_BOOT_SELECT_FAILED )
                            }
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
                    }
                    break;
                }
                case AMI_CMD_OPCODE_UCORE_VERSION:
                {
                    if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                              OSAL_TIMEOUT_WAIT_FOREVER ) )
                    {
                        INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

                        iStatus = iFindNextFreeRxDataIndex( &ucIndex );
                        if( ERROR != iStatus )
                        {
                            pxThis->xRxData[ ucIndex ].usCid = xCmdRequest.xHdr.usCid;
                            pxThis->xRxData[ ucIndex ].xOpCode = xCmdRequest.xHdr.ulOpCode;
                            pxThis->xRxData[ ucIndex ].ucInUse = TRUE;
                        }
                        else
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
                        }

                        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                        }

                        if( ERROR != iStatus )
                        {
                            INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )

                            /* Raise event using the index as the method to track the event */
                            EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                                    AMI_PROXY_DRIVER_E_GET_UCORE_VERSION,
                                                    ucIndex,
                                                    0 };
                            iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                            if( ERROR == iStatus )
                            {
                                PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                                         AMI_PROXY_DRIVER_E_GET_UCORE_VERSION );
                                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_GET_UCOREVER_FAILED )
                            }
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
                    }
                    break;
                }
                case AMI_CMD_OPCODE_HEARTBEAT_REQ:
                {
                    iStatus = iHandleHeartbeatRequest( &xCmdRequest );
                    if( ERROR == iStatus )
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_GET_HEARTBEAT_REQUEST )
                    }
                    break;
                }
                case AMI_CMD_OPCODE_EEPROM_RW_REQ:
                {
                    iStatus = iHandleEepromRequest( &xCmdRequest );
                    if( ERROR == iStatus )
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_GET_EEPROM_RW_REQUEST )
                    }
                    break;
                }
                case AMI_CMD_OPCODE_PEEK_POKE:
                {
                    iStatus = iHandlePeekPokeRequest( &xCmdRequest );
                    if( ERROR == iStatus ) {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_GET_EEPROM_RW_REQUEST )
                    }
                    break;
                }
                case AMI_CMD_OPCODE_MODULE_RW_REQ:
                {
                    iStatus = iHandleModuleRequest( &xCmdRequest );
                    if( ERROR == iStatus )
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_GET_MODULE_RW_REQUEST )
                    }
                    break;
                }
                case AMI_CMD_OPCODE_DEBUG_VERBOSITY_REQ:
                {
                    iStatus = iHandleDebugVerbosityRequest( &xCmdRequest );
                    if( ERROR == iStatus )
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_GET_DEBUG_VERBOSITY_REQUEST )
                    }
                    break;
                }
                default:
                    PLL_ERR( AMI_NAME, "Error unsupported opcode received 0x%x\r\n", xCmdRequest.xHdr.ulOpCode );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_UNSUPPORTED_OPCODE_RX )
                    break;
            }
        }

        /* Check for new MBox data (tx path) */
        if( OSAL_ERRORS_NONE == iOSAL_MBox_Pend( pxThis->pvOsalMBoxHdl,
                                                 ( void* )&xMBoxData,
                                                 OSAL_TIMEOUT_NO_WAIT ) )
        {
            AMI_CMD_RESPONSE xCmdResponse = { { { { { { 0 } } } } } };
            uint32_t xCmdResponseSize = sizeof( AMI_CMD_RESPONSE );
            uint32_t ulValidMsg = TRUE;
            uint8_t ucIndex = xMBoxData.ucRxDataIndex;

            switch( xMBoxData.eMsgType )
            {
                case AMI_MSG_TYPE_IDENTITY_COMPLETE:
                {
                    INC_STAT_COUNTER( AMI_PROXY_STATS_IDENTITY_MBOX_PEND )
                    xCmdResponse.ulPayload[ 0 ]  = APC_LOAD_VER_MAJOR( xMBoxData.xIdentity.ucVerMajor );
                    xCmdResponse.ulPayload[ 0 ] |= APC_LOAD_VER_MINOR( xMBoxData.xIdentity.ucVerMinor );
                    xCmdResponse.ulPayload[ 0 ] |= APC_LOAD_VER_PATCH( xMBoxData.xIdentity.ucVerPatch );
                    xCmdResponse.ulPayload[ 0 ] |= APC_LOAD_LOCAL_CHANGES( xMBoxData.xIdentity.ucLocalChanges );
                    xCmdResponse.ulPayload[ 1 ]  = APC_LOAD_DEV_COMMITS( xMBoxData.xIdentity.usDevCommits );
                    xCmdResponse.ulPayload[ 1 ] |= APC_LOAD_LINK_VER_MAJOR( xMBoxData.xIdentity.ucLinkVerMajor );
                    xCmdResponse.ulPayload[ 1 ] |= APC_LOAD_LINK_VER_MINOR( xMBoxData.xIdentity.ucLinkVerMinor );
                    break;
                }
                case AMI_MSG_TYPE_SENSOR_COMPLETE:
                    /* No payload associated with response */
                    INC_STAT_COUNTER( AMI_PROXY_STATS_SENSOR_MBOX_PEND )
                    break;
                case AMI_MSG_TYPE_PDI_DOWNLOAD_COMPLETE:
                    /* No payload associated with response */
                    INC_STAT_COUNTER( AMI_PROXY_STATS_PDI_DOWNLOAD_MBOX_PEND )
                    break;
                case AMI_MSG_TYPE_PDI_COPY_COMPLETE:
                    /* No payload associated with response */
                    INC_STAT_COUNTER( AMI_PROXY_STATS_PDI_COPY_MBOX_PEND )
                    break;
                case AMI_MSG_TYPE_BOOT_SELECT_COMPLETE:
                    /* No payload associated with response */
                    INC_STAT_COUNTER( AMI_PROXY_STATS_BOOT_SELECT_MBOX_PEND )
                    break;
                case AMI_MSG_TYPE_HEARTBEAT_COMPLETE:
                    INC_STAT_COUNTER( AMI_PROXY_STATS_HEARTBEAT_MBOX_PEND )
                    xCmdResponse.ulPayload[ 0 ] = xMBoxData.xHeartbeat.ucHeartbeatCount;
                    break;
                case AMI_MSG_TYPE_EEPROM_RW_COMPLETE:
                    INC_STAT_COUNTER( AMI_PROXY_STATS_EEPROM_RW_MBOX_PEND )
                    break;
                case AMI_MSG_TYPE_PEEK_POKE_COMPLETE:
                    INC_STAT_COUNTER( AMI_PROXY_STATS_PEEK_POKE_MBOX_PEND )
                    break;
		case AMI_MSG_TYPE_UCORE_VERSION_COMPLETE:
                    xCmdResponse.ulPayload[ 0 ]  = APC_LOAD_VER_MAJOR( xMBoxData.xIdentity.ucVerMajor );
                    xCmdResponse.ulPayload[ 0 ] |= APC_LOAD_VER_MINOR( xMBoxData.xIdentity.ucVerMinor );
                    PLL_ERR( AMI_NAME, "UCORE version complete %d %d %d\r\n", xMBoxData.xIdentity.ucVerMajor, xMBoxData.xIdentity.ucVerMinor, xCmdResponse.ulPayload[ 0 ] );
                    INC_STAT_COUNTER( AMI_PROXY_STATS_UCORE_VERSION_MBOX_PEND )
		    break;
                case AMI_MSG_TYPE_MODULE_RW_COMPLETE:
                    INC_STAT_COUNTER( AMI_PROXY_STATS_MODULE_RW_MBOX_PEND )
                    break;
                case AMI_MSG_TYPE_DEBUG_VERBOSITY_COMPLETE:
                    INC_STAT_COUNTER( AMI_PROXY_STATS_DEBUG_VERBOSITY_MBOX_PEND )
                    break;

                default:
                    PLL_ERR( AMI_NAME, "Error unknown mailbox message type 0x%x\r\n", xMBoxData.eMsgType );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_UNKNOWN_MAILBOX_MSG )
                    ulValidMsg = FALSE;
                    break;
            }

            if( TRUE == ulValidMsg )
            {
                xCmdResponse.xHdr.usCid = pxThis->xRxData[ ucIndex ].usCid;

                xCmdResponse.xHdr.usCState = AMI_CMD_STATE_COMPLETED;
                xCmdResponse.ulRCode = xMBoxData.xResult ;
                int iStatus = pxThis->pxFwIf->write( pxThis->pxFwIf, ( uint64_t )pxThis->ulFwIfPort,
                                                 ( uint8_t* )&xCmdResponse,
                                                  xCmdResponseSize,
                                                  FW_IF_TIMEOUT_NO_WAIT );
                if( FW_IF_ERRORS_NONE == iStatus )
                {
                    if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                              OSAL_TIMEOUT_WAIT_FOREVER ) )
                    {
                        INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

                        pxThis->xRxData[ ucIndex ].ucInUse = FALSE;
                        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                        {
                            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                        }
                        else
                        {
                            INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
                    }
                }
                else
                {
                    PLL_ERR( AMI_NAME, "Error FW_IF write failed 0x%x\r\n", iStatus );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_FW_IF_WRITE_FAILED )
                }
            }
        }
        pxThis->pulStatCounters[ AMI_PROXY_STATS_TASK_TIME_MS ] = UTIL_ELAPSED_TIME_MS( ulStartMs )
        iOSAL_Task_SleepMs( AMI_TASK_SLEEP_MS );
    }
}

/**
 * @brief   Find the next free rxdata instance, should be called within mutex to protect data
 */
static int iFindNextFreeRxDataIndex( uint8_t *pucIndex )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        int i = 0;
        for( i = 0; i < AMI_RXDATA_SIZE; i++ )
        {
            if( FALSE == pxThis->xRxData[ i ].ucInUse )
            {
                *pucIndex = i;
                iStatus = OK;
                break;
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( AMI_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Handle the heartbeat request
 */
static int iHandleHeartbeatRequest( AMI_CMD_REQUEST *pxCmdRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxCmdRequest ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        uint8_t ucIndex = 0;

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            iStatus = iFindNextFreeRxDataIndex( &ucIndex );
            if( ERROR != iStatus )
            {
                pxThis->xRxData[ ucIndex ].usCid = pxCmdRequest->xHdr.usCid;
                pxThis->xRxData[ ucIndex ].xOpCode = pxCmdRequest->xHdr.ulOpCode;
                pxThis->xRxData[ ucIndex ].ucInUse = TRUE;
            }
            else
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            }

            if( ERROR != iStatus )
            {
                /* raise event with the current heartbeat counter to anyone interested */
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
                EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                          AMI_PROXY_DRIVER_E_HEARTBEAT,
                                          pxCmdRequest->xHeartbeatPayload.ucHeartbeatCount,
                                          0 };
                iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                if( ERROR == iStatus )
                {
                    PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                             AMI_PROXY_DRIVER_E_HEARTBEAT );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_HEARTBEAT_FAILED )
                }
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }

        /* Respond to heartbeat request via the mailbox */
        if( OK == iStatus )
        {
            AMI_MBOX_MSG xMsg = { 0 };
            AMI_PROXY_HEARTBEAT_RESPONSE xHeartbeatResponse = { 0 };

            xMsg.ucRxDataIndex = ucIndex;
            xMsg.eMsgType = AMI_MSG_TYPE_HEARTBEAT_COMPLETE;
            xMsg.xResult = AMI_PROXY_RESULT_SUCCESS;
            xHeartbeatResponse.ucHeartbeatCount = pxCmdRequest->xHeartbeatPayload.ucHeartbeatCount;
            pvOSAL_MemCpy( &xMsg.xHeartbeat, &xHeartbeatResponse, sizeof( xMsg.xHeartbeat ) );
            if( OSAL_ERRORS_NONE == iOSAL_MBox_Post( pxThis->pvOsalMBoxHdl,
                                                     ( void* )&xMsg,
                                                     OSAL_TIMEOUT_NO_WAIT ) )
            {
                INC_STAT_COUNTER( AMI_PROXY_STATS_HEARTBEAT_MBOX_POST )
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MAILBOX_POST_FAILED )
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Handle the eeprom request
 */
static int iHandleEepromRequest( AMI_CMD_REQUEST *pxCmdRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxCmdRequest ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        uint8_t ucIndex = 0;

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            iStatus = iFindNextFreeRxDataIndex( &ucIndex );
            if( ERROR != iStatus )
            {
                pxThis->xRxData[ ucIndex ].usCid = pxCmdRequest->xHdr.usCid;
                pxThis->xRxData[ ucIndex ].xOpCode = pxCmdRequest->xHdr.ulOpCode;
                pxThis->xRxData[ ucIndex ].xEepromReadWriteRequest.xRequest =
                    pxCmdRequest->xEepromPayload.ucReqType;
                pxThis->xRxData[ ucIndex ].xEepromReadWriteRequest.ullAddress =
                    pxCmdRequest->xEepromPayload.ullAddress;
                pxThis->xRxData[ ucIndex ].xEepromReadWriteRequest.ulLength =
                    pxCmdRequest->xEepromPayload.ucLen;
                pxThis->xRxData[ ucIndex ].xEepromReadWriteRequest.ulOffset =
                    pxCmdRequest->xEepromPayload.ucOffset;
                pxThis->xRxData[ ucIndex ].ucInUse = TRUE;
            }
            else
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            }

            if( ERROR != iStatus )
            {
                /* raise event with the current heartbeat counter to anyone interested */
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
                EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                          AMI_PROXY_DRIVER_E_EEPROM_READ_WRITE,
                                          ucIndex,
                                          0 };
                iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                if( ERROR == iStatus )
                {
                    PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                                 AMI_PROXY_DRIVER_E_HEARTBEAT );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_EEPROM_RW_FAILED )
                }
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }

    return iStatus;
}

/**
 * @brief   Handle the HPU register read/write request
 */
static int iHandlePeekPokeRequest( AMI_CMD_REQUEST *pxCmdRequest )
{
    int iStatus = ERROR;

    if( ( NULL != pxCmdRequest ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        uint8_t ucIndex = 0;

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            iStatus = iFindNextFreeRxDataIndex( &ucIndex );
            if( ERROR != iStatus ) {
                pxThis->xRxData[ ucIndex ].usCid                       = pxCmdRequest->xHdr.usCid;
                pxThis->xRxData[ ucIndex ].xOpCode                     = pxCmdRequest->xHdr.ulOpCode;
                pxThis->xRxData[ ucIndex ].xPeekPokeRequest.xRequest   = pxCmdRequest->xPeekPokePayload.ucReqType;
                pxThis->xRxData[ ucIndex ].xPeekPokeRequest.ullAddress = pxCmdRequest->xPeekPokePayload.ullAddress;
                pxThis->xRxData[ ucIndex ].xPeekPokeRequest.ulLength   = pxCmdRequest->xPeekPokePayload.ucLen;
                pxThis->xRxData[ ucIndex ].xPeekPokeRequest.ulOffset   = pxCmdRequest->xPeekPokePayload.ucOffset;
                pxThis->xRxData[ ucIndex ].ucInUse                     = TRUE;
            } else {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) ) {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            }

            if( ERROR != iStatus ) {
                /* raise event with the current heartbeat counter to anyone interested */
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
                EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                          AMI_PROXY_DRIVER_E_PEEK_POKE,
                                          ucIndex,
                                          0 };
                iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                if( ERROR == iStatus )
                {
                    PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                                 AMI_PROXY_DRIVER_E_HEARTBEAT );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_EEPROM_RW_FAILED )
                }
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }

    return iStatus;
}

/**
 * @brief   Handle the module request
 */
static int iHandleModuleRequest( AMI_CMD_REQUEST *pxCmdRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxCmdRequest ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        uint8_t ucIndex = 0;

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            iStatus = iFindNextFreeRxDataIndex( &ucIndex );
            if( ERROR != iStatus )
            {
                pxThis->xRxData[ ucIndex ].usCid = pxCmdRequest->xHdr.usCid;
                pxThis->xRxData[ ucIndex ].xOpCode = pxCmdRequest->xHdr.ulOpCode;
                pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.xRequest =
                    pxCmdRequest->xModulePayload.ulReqType;
                pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.ullAddress =
                    pxCmdRequest->xModulePayload.ullAddress;
                pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.ucExDeviceId =
                    pxCmdRequest->xModulePayload.ucExDeviceId;
                pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.ucPage =
                    pxCmdRequest->xModulePayload.ucPage;
                pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.ucByteOffset =
                    pxCmdRequest->xModulePayload.ucByteOffset;
                pxThis->xRxData[ ucIndex ].xModuleReadWriteRequest.ucLength =
                    pxCmdRequest->xModulePayload.ucLen;
                pxThis->xRxData[ ucIndex ].ucInUse = TRUE;
            }
            else
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            }

            if( ERROR != iStatus )
            {
                /* raise event with the current heartbeat counter to anyone interested */
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
                EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                          AMI_PROXY_DRIVER_E_MODULE_READ_WRITE,
                                          ucIndex,
                                          0 };
                iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                if( ERROR == iStatus )
                {
                    PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                                 AMI_PROXY_DRIVER_E_HEARTBEAT );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_MODULE_RW_FAILED )
                }
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }

    return iStatus;
}

/**
 * @brief   Handle the debug verbosity request
 */
static int iHandleDebugVerbosityRequest( AMI_CMD_REQUEST *pxCmdRequest )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxCmdRequest ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        uint8_t ucIndex = 0;

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( AMI_PROXY_STATS_TAKE_MUTEX )

            iStatus = iFindNextFreeRxDataIndex( &ucIndex );
            if( ERROR != iStatus )
            {
                pxThis->xRxData[ ucIndex ].usCid = pxCmdRequest->xHdr.usCid;
                pxThis->xRxData[ ucIndex ].xOpCode = pxCmdRequest->xHdr.ulOpCode;
                pxThis->xRxData[ ucIndex ].ucDebugVerbosityRequest = pxCmdRequest->ucDebugVerbosityPayload;
                pxThis->xRxData[ ucIndex ].ucInUse = TRUE;
            }
            else
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RX_DATA_INDEX_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            }

            if( ERROR != iStatus )
            {
                INC_STAT_COUNTER( AMI_PROXY_STATS_RELEASE_MUTEX )
                EVL_SIGNAL xNewSignal = { pxThis->ucMyId,
                                          AMI_PROXY_DRIVER_E_DEBUG_VERBOSITY,
                                          ucIndex,
                                          0 };
                iStatus = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
                if( ERROR == iStatus )
                {
                    PLL_ERR( AMI_NAME, "Error attempting to raise event 0x%x\r\n",
                             AMI_PROXY_DRIVER_E_DEBUG_VERBOSITY );
                    INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_RAISE_EVENT_DEBUG_VERBOSITY_FAILED )
                }
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( AMI_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }

    return iStatus;
}
