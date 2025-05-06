/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains PLDM enums, structures and functions
 *
 * @file pldm_processor.c
 *
 */


/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <unistd.h>
#include "pldm.h"
#include "pldm_response.h"
#include "pldm_commands_internal.h"
#include "pldm_pdr.h"
#include "util.h"
#include "pldm_sensors.h"
#include "bmc_proxy_driver.h"
#include "standard.h"
#include "pldm_processor.h"
#include "pll.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define PENDING_XFER_INIT_KEY  0x93
#define MAX_PLDM_RESPONSE_SIZE ( ( 128 ) - ( 3 ) )


/******************************************************************************/
/* Globals                                                                    */
/******************************************************************************/

static uint8_t _TID = 0x00;


/******************************************************************************/
/* Externs                                                                    */
/******************************************************************************/

extern int iSetNumericSensorEnable( uint16_t usSensorId,
                                    uint8_t ucRequestedSensorOperationalState,
                                    uint8_t *pucResponseMessage,
                                    int *piResponseSize );

extern int iGetNumericSensorReading( uint16_t usSensorId,
                                     uint8_t *pucCompletionCode,
                                     uint8_t *pucSensorOperationalState,
                                     int16_t *pssReading );


/******************************************************************************/
/* Function defintions                                                        */
/******************************************************************************/

/**
 * @brief   PLDM Set TID function
 */
int pldm_cmd_SetTID( const void *PayLoadIn, void *PayLoadOut )
{
    int           response_size = 0;
    const uint8_t *payload_req  = PayLoadIn;
    uint8_t       *payload_res  = PayLoadOut;

    _TID = payload_req[ 0 ];

    payload_res[ response_size++ ] = RESP_PLDM_SUCCESS;

    /*
     * todo: Make tid update asynchronous
     */
    update_tid( _TID );

    return response_size;
}

/**
 * @brief   PLDM Get TID function
 */
int pldm_cmd_GetTID( const void *PayLoadIn, void *PayLoadOut )
{
    int     response_size = 0;
    uint8_t *payload_res  = PayLoadOut;

    payload_res[ response_size++ ] = RESP_PLDM_SUCCESS;
    payload_res[ response_size++ ] = _TID;

    return response_size;
}

/**
 * @brief   PLDM Get PLDM version
 */
int pldm_cmd_GetPLDMVersion( const void *PayLoadIn, void *PayLoadOut )
{
    int       response_size      = 0;
    const int max_version_to_get = 8;                                          /* maximum number of version to process in request */
    int       start_index        = 0;
    int       isMoreVersion      = 0;
    int       ret                = 0;
    uint32_t  crc32_val          = 0;

    enum ReqOperationFlag
    {
        EGetNextPart = 0x0,
        EGetFirstPart

    };

    enum ResTransferFlag
    {
        EStart       = 0x1,
        EMiddle      = 0x2,
        EEnd         = 0x4,
        EStartAndEnd = 0x5

    };

    typedef struct
    {
        uint8_t initialized;                                                   /* Initkey = 0x93 */
        uint8_t next_start;

    } PendingTransfers;

    static PendingTransfers GetVersionPendingXfers[ 64 ];
    PendingTransfers        *pendingInfo = NULL;

    const struct __attribute__ ( ( __packed__ ) )
    {
        uint32_t TransferHandle;
        uint8_t  OperationFlag;                                                /* can use packed enum as well */
        uint8_t  type;
    }

    *payload_req = PayLoadIn;

    struct  __attribute__ ( ( __packed__ ) )
    {
        uint8_t  CompletionCode;
        uint32_t NextTransferHandle;
        uint8_t  TransferFlag;
        uint8_t  VersionList[ 0 ];                                             /* variable length version */
    }

    *payload_res = PayLoadOut;

    if( !IsPldmTypeSupported( payload_req->type ) )
    {
        payload_res->CompletionCode = RESP_INVALID_PLDM_TYPE_IN_REQUEST;
        response_size++;
        return response_size;
    }

    switch( payload_req->OperationFlag )
    {
    case EGetNextPart:
    {
        pendingInfo = ( PendingTransfers * )( uintptr_t )payload_req->TransferHandle;
        if( pendingInfo == NULL || pendingInfo->initialized != PENDING_XFER_INIT_KEY )
        {
            payload_res->CompletionCode = RESP_INVALID_DATA_XFER_HANDLE;
            response_size++;
            return response_size;
        }
        start_index = pendingInfo->next_start;
        /*
         * todo: Assert, Start_index cannot be zero here
         */
        break;
    }

    case EGetFirstPart:
    {
        pendingInfo = ( GetVersionPendingXfers + payload_req->type );
        if( pendingInfo->initialized == PENDING_XFER_INIT_KEY )
        {
            /*
             * Todo: Flag a warning.
             * This means the last xfer was incomplement. And there may be something
             * wrong on the host request sequencing.
             */
        }
        /*
         * Clear Pending info
         */
        pendingInfo->initialized = 0;
        pendingInfo->next_start  = 0;
        break;
    }

    default:
    {
        /*
         * Invalid Operation Flag
         */
        payload_res->CompletionCode = RESP_INVALID_XFER_OPERATION_FLAG;
        response_size++;
        return response_size;
    }
        /* unreachable break; */
    }

    ret = getPldmVersionSupport( payload_req->type,
                                 payload_res->VersionList,
                                 start_index,
                                 max_version_to_get,
                                 &isMoreVersion );

    if( ret == 0 )
    {
        payload_res->CompletionCode = RESP_PLDM_ERROR_GENERIC;
        response_size++;
        return response_size;
    }

    response_size += sizeof( *payload_res ) + ret;

    payload_res->CompletionCode = RESP_PLDM_SUCCESS;

    if( isMoreVersion )
    {
        pendingInfo->next_start        += max_version_to_get;
        payload_res->NextTransferHandle = ( uint32_t )( uintptr_t )pendingInfo;
        if( pendingInfo->initialized != PENDING_XFER_INIT_KEY )
        {
            pendingInfo->initialized  = PENDING_XFER_INIT_KEY;
            payload_res->TransferFlag = EStart;
        }
        else
        {
            payload_res->TransferFlag = EMiddle;
        }
    }
    else
    {
        payload_res->NextTransferHandle = 0;

        if( ( pendingInfo->initialized == PENDING_XFER_INIT_KEY ) && start_index != 0 ) /* need not to check start_index */
        {
            pendingInfo->initialized  = 0;
            pendingInfo->next_start   = 0;
            payload_res->TransferFlag = EEnd;
        }
        else
        {
            payload_res->TransferFlag = EStartAndEnd;
        }
    }

    /*
     * Add crc32 for the version information.
     */

    crc32_val = ulGetCrc32( payload_res->VersionList, ret );

    *( ( uint32_t * )( payload_res->VersionList + ret ) ) = crc32_val;
    response_size += 4;

    return response_size;
}

/**
 * @brief   PLDM Get PLDM Type
 */
int pldm_cmd_GetPLDMType( const void *PayLoadIn, void *PayLoadOut )
{
    int     response_size = 0;
    uint8_t *payload_res  = PayLoadOut;

    int ret;

    ret = getPldmTypeSupport( payload_res + 1 );

    if( ret != 0 )
    {
        payload_res[ response_size++ ] = RESP_PLDM_SUCCESS;
        response_size                 += ret;
    }
    else
    {
        payload_res[ response_size++ ] = RESP_PLDM_ERROR_GENERIC;
    }

    return response_size;
}

/**
 * @brief   PLDM Get PLDM Command
 */
int pldm_cmd_GetPLDMCommand( const void *PayLoadIn, void *PayLoadOut )
{
    int response_size = 0;
    int ret           = 0;

    const struct
    {
        uint8_t type;
        uint8_t version[ 4 ];

    }

    *payload_req = PayLoadIn;

    uint8_t *payload_res = PayLoadOut;

    if( !IsPldmTypeSupported( payload_req->type ) )
    {
        payload_res[ response_size++ ] = RESP_INVALID_PLDM_TYPE_IN_REQUEST;
        return response_size;
    }

    if( !IsPldmVersionSupported( payload_req->type, payload_req->version ) )
    {
        payload_res[ response_size++ ] = RESP_INVALID_PLDM_VERSION_IN_REQUEST;
        return response_size;
    }

    ret = getPldmCmdSupport( payload_req->type, payload_req->version, payload_res + 1 );

    if( ret != 0 )
    {
        payload_res[ response_size++ ] = RESP_PLDM_SUCCESS;
        response_size                 += ret;
    }
    else
    {
        payload_res[ response_size++ ] = RESP_PLDM_ERROR_GENERIC;
    }

    return response_size;
}

/**
 * @brief   PLDM Set Sensor Enable
 */
int pldm_cmd_SetNumericSensorEnable( const void *PayLoadIn, void *PayLoadOut )
{
    int response_size = 0;

    const struct __attribute__ ( ( __packed__ ) )
    {
        uint16_t sensorID;
        uint8_t  sensorOperationalState;
        uint8_t  sensorEventMessageEnable;
    }

    *payload_req = PayLoadIn;

    uint8_t *payload_res = PayLoadOut;

    if( ( payload_req->sensorOperationalState != eSensorOpStateEnabled ) &&
        ( payload_req->sensorOperationalState != eSensorOpStateDisabled ) &&
        ( payload_req->sensorOperationalState != eSensorOpStateUnavailable ) )
    {
        payload_res[ response_size++ ] = RESP_INVALID_SENSOR_OPERATIONAL_STATE;
    }
    else
    {
        if( payload_req->sensorEventMessageEnable != eSensorNoEventGeneration )
        {
            payload_res[ response_size++ ] = RESP_EVENT_GENERATION_NOT_SUPPORTED;
        }
        else
        {
            iSetNumericSensorEnable( payload_req->sensorID,
                                     payload_req->sensorOperationalState,
                                     payload_res,
                                     &response_size );
        }
    }

    return response_size;
}

/**
 * @brief   PLDM Get Sensor Reading
 */
int pldm_cmd_GetSensorReading( const void *PayLoadIn, void *PayLoadOut )
{
    int response_size = 0;

/*  NumericSensors *handle       = NULL; */
/*  sensor_values temp_state    =
        {
                0
        }; */

    const struct __attribute__ ( ( __packed__ ) )
    {
        uint16_t sensorID;
        uint8_t  rearmEventState;
    }

    *payload_req = PayLoadIn;

    struct __attribute__ ( ( __packed__ ) )
    {
        uint8_t CompletionCode;
        uint8_t sensorDataSize;
        uint8_t sensorOperationalState;
        uint8_t sensorEventMessageEnable;
        uint8_t presentState;
        uint8_t previousState;
        uint8_t eventState;
        /* Reading will be added at the end*/
        uint8_t reading[ 0 ];
    }

    *payload_res = PayLoadOut;

    uint8_t ucCompletionCode;
    uint8_t ucSensorOperationalState;
    int16_t ssReading;

    if( OK == iGetNumericSensorReading( payload_req->sensorID,
                                        &ucCompletionCode,
                                        &ucSensorOperationalState,
                                        &ssReading ) )
    {
        if( RESP_INVALID_SENSOR_ID == ucCompletionCode )
        {
            payload_res->CompletionCode = ucCompletionCode;
            response_size++;
        }
        else
        {
            if( payload_req->rearmEventState != 0 )
            {
                /*
                 * We don't support rearming
                 */
                payload_res->CompletionCode = RESP_REARM_UNAVAILABLE_IN_PRESENT_STATE;
                response_size++;
            }
            else
            {
                response_size += sizeof( *payload_res );

                payload_res->CompletionCode = RESP_PLDM_SUCCESS;
                payload_res->sensorDataSize = EDataTypeSInt16;



                payload_res->sensorOperationalState   = ucSensorOperationalState;
                payload_res->sensorEventMessageEnable = eSensorNoEventGeneration;

                if( eSensorOpStateEnabled != ucSensorOperationalState )
                {
                    payload_res->presentState                      = Unknown;
                    payload_res->previousState                     = Unknown;
                    payload_res->eventState                        = Unknown;
                    ( ( int16_t * )( payload_res->reading ) )[ 0 ] = 0;
                }
                else
                {
                    payload_res->presentState                      = Normal;
                    payload_res->previousState                     = Unknown;
                    payload_res->eventState                        = Normal;
                    ( ( int16_t * )( payload_res->reading ) )[ 0 ] = ssReading;
                }

                response_size += sizeof( int16_t );
            }
        }
    }
    else
    {
        payload_res->CompletionCode = RESP_INVALID_SENSOR_ID;
        response_size++;
    }

    return response_size;
}

/**
 * @brief   PLDM Get PDR Repo Info
 */
int pldm_cmd_GetPDRRepositoryInfo( const void *PayLoadIn, void *PayLoadOut )
{
    int response_size                   = 0;
    const PDR_RepositoryInfo *repo_info = getPDRRepository();

    struct __attribute__ ( ( __packed__ ) )
    {
        uint8_t   CompletionCode;
        enum8_t   repositoryState;
        TimeStamp updateTime;
        TimeStamp OEMUpdateTime;
        uint32_t  recordCount;
        uint32_t  repositorySize;
        uint32_t  largestRecordSize;
        uint8_t   dataTransferHandleTimeout;
    }

    *payload_res = PayLoadOut;

    response_size += sizeof( *payload_res );

    payload_res->CompletionCode  = RESP_PLDM_SUCCESS;
    payload_res->repositoryState = repo_info->repositoryState;

    memcpy( &payload_res->updateTime, &repo_info->updateTimestamp, sizeof( TimeStamp ) );
    memcpy( &payload_res->OEMUpdateTime, &repo_info->OEMUpdateTimestamp, sizeof( TimeStamp ) );

    PLL_DBG( BMC_NAME,  "\n\rrecordCount %d\n\r", repo_info->recordCount );
    PLL_DBG( BMC_NAME,  "\n\rrepositorySize %d\n\r", repo_info->repositorySize );
    PLL_DBG( BMC_NAME,  "\n\rlargestRecordSize %d\n\r", repo_info->largestRecordSize );
    PLL_DBG( BMC_NAME,  "\n\rdataTransferHandleTimeout %d\n\r", repo_info->dataTransferHandleTimeout );


    payload_res->recordCount               = repo_info->recordCount;
    payload_res->repositorySize            = repo_info->repositorySize;
    payload_res->largestRecordSize         = repo_info->largestRecordSize;
    payload_res->dataTransferHandleTimeout = repo_info->dataTransferHandleTimeout;

    return response_size;
}

/**
 * @brief   PLDM Get PDR Repo
 */
int pldm_cmd_GetPDR( const void *PayLoadIn, void *PayLoadOut )
{
    int response_size                   = 0;
    const PDR_RepositoryInfo *repo_info = getPDRRepository();
    const CommonPDRFormat    *current_record;
    uint32_t                 record_handle = 0;
    uint8_t                  *data;
    uint32_t                 max_data_len = MAX_PLDM_RESPONSE_SIZE;
    uint32_t                 start_index  = 0;
    uint32_t                 pdr_size     = 0;

    enum ReqOperationFlag
    {
        EGetNextPart = 0x0,
        EGetFirstPart

    };

    enum ResTransferFlag
    {
        EStart       = 0x0,
        EMiddle      = 0x1,
        EEnd         = 0x4,
        EStartAndEnd = 0x5

    };

    typedef struct
    {
        uint8_t initialized;                                                   /* Initkey = 0x93 */
        uint8_t next_start;

    } PendingTransfers;

    static PendingTransfers GetPDRPendingXfers[ 100 ];
    PendingTransfers        *pendingInfo = NULL;

    const struct __attribute__ ( ( __packed__ ) )
    {
        uint32_t recordHandle;
        uint32_t dataTransferHandle;
        uint8_t  OperationFlag;                                                /* can use packed enum as well */
        uint16_t requestCount;
        uint16_t recordChangeNumber;
    }

    *payload_req = PayLoadIn;

    struct __attribute__ ( ( __packed__ ) )
    {
        uint8_t  CompletionCode;
        uint32_t nextRecordHandle;
        uint32_t nextDataTransferHandle;
        uint8_t  transferFlag;
        uint16_t responseCount;
        uint8_t  recordData[ 0 ];
        /*
         * CRC is conditional and hence will be appended as needed
         */
    }

    *payload_res = PayLoadOut;


    record_handle = payload_req->recordHandle;

    if( repo_info->repositoryState == ERepoStateUpdateInprogress )
    {
        payload_res->CompletionCode = RESP_REPOSITORY_UPDATE_IN_PROGRESS;
        response_size              += 1;
        return response_size;
    }

    if( record_handle >= repo_info->recordCount )
    {
        payload_res->CompletionCode = RESP_INVALID_RECORD_HANDLE;
        response_size              += 1;
        return response_size;
    }

    current_record = repo_info->PDRRecords[ record_handle ];

    switch( payload_req->OperationFlag )
    {
    case EGetNextPart:
    {
        pendingInfo = ( PendingTransfers * )( uintptr_t )payload_req->dataTransferHandle;
        /*
         * todo: Sanity check if the handle is incorrect
         */
        if( pendingInfo == NULL || pendingInfo->initialized != PENDING_XFER_INIT_KEY )
        {
            payload_res->CompletionCode = RESP_INVALID_DATA_XFER_HANDLE;
            response_size++;
            return response_size;
        }

        if( payload_req->recordChangeNumber != current_record->recordChangeNumber )
        {
            payload_res->CompletionCode = RESP_INVALID_RECORD_CHANGE_NUMBER;
            response_size++;
            return response_size;
        }

        start_index = pendingInfo->next_start;
        /*
         * todo: Assert, Start_index cannot be zero here
         */
        break;
    }

    case EGetFirstPart:
    {
        pendingInfo = ( GetPDRPendingXfers + payload_req->recordHandle );
        if( pendingInfo->initialized == PENDING_XFER_INIT_KEY )
        {
            /*
             * This is also a valid scenario.
             * Just discard the last transfer.
             */
        }
        /*
         * Clear Pending info
         */
        pendingInfo->initialized = 0;
        pendingInfo->next_start  = 0;
        break;
    }

    default:
    {
        /*
         * Invalid Operation Flag
         */
        payload_res->CompletionCode = RESP_INVALID_XFER_OPERATION_FLAG;
        response_size++;
        return response_size;
    }
        /* unreachable break; */
    }

    response_size += sizeof( *payload_res );

    max_data_len -= response_size;

    if( payload_req->requestCount < max_data_len )
    {
        max_data_len = payload_req->requestCount;
    }

    pdr_size = ( current_record->dataLength ) + sizeof( CommonPDRFormat );

    payload_res->CompletionCode   = RESP_PLDM_SUCCESS;
    payload_res->nextRecordHandle = ( record_handle + 1 ) % repo_info->recordCount;
    payload_res->responseCount    = pdr_size - start_index;

    if( payload_res->responseCount > max_data_len )
    {
        pendingInfo->next_start            += max_data_len;
        payload_res->nextDataTransferHandle = ( uint32_t )( uintptr_t )pendingInfo;
        payload_res->responseCount          = max_data_len;
        if( pendingInfo->initialized != PENDING_XFER_INIT_KEY )
        {
            pendingInfo->initialized  = PENDING_XFER_INIT_KEY;
            payload_res->transferFlag = EStart;
        }
        else
        {
            payload_res->transferFlag = EMiddle;
        }
    }
    else
    {
        payload_res->nextDataTransferHandle = 0x0;

        if( ( pendingInfo->initialized == PENDING_XFER_INIT_KEY ) && start_index != 0 ) /* need not to check start_index */
        {
            pendingInfo->initialized  = 0;
            pendingInfo->next_start   = 0;
            payload_res->transferFlag = EEnd;
        }
        else
        {
            payload_res->transferFlag = EStartAndEnd;
        }
    }
    /*
     * assert for response size should be >0
     */

    data = ( uint8_t * ) current_record;

    memcpy( payload_res->recordData, data + start_index, payload_res->responseCount );

    response_size += payload_res->responseCount;

    if( payload_res->transferFlag == EEnd )
    {
        payload_res->recordData[ payload_res->responseCount ] = ucGetCrc8( data, pdr_size );
        response_size++;
    }

    return response_size;
}


/**
 * @brief   Get a CRC 32 for supplied data
 *
 */
uint32_t ulGetCrc32( const uint8_t data[], size_t size )
{
    int           i;
    unsigned long crc = 0xFFFFFFFF;

    static const unsigned long CRCTable[ 256 ] =
    {
        0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA,
        0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
        0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988,
        0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
        0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE,
        0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
        0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC,
        0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
        0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172,
        0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
        0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940,
        0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
        0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116,
        0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
        0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924,
        0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
        0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A,
        0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
        0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818,
        0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
        0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E,
        0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
        0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C,
        0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
        0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2,
        0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
        0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0,
        0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
        0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086,
        0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
        0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4,
        0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
        0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A,
        0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
        0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8,
        0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
        0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE,
        0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
        0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC,
        0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
        0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252,
        0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
        0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60,
        0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
        0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236,
        0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
        0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04,
        0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
        0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A,
        0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
        0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38,
        0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
        0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E,
        0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
        0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C,
        0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
        0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2,
        0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
        0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0,
        0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
        0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6,
        0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
        0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94,
        0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
    };

    for(i = 0; i < size; i++)
    {
        crc = CRCTable[ ( crc ^ data[ i ] ) & 0xFF ] ^ ( crc >> 8 );
    }

    return ( crc ^ 0xFFFFFFFF );
}

/**
 * @brief   Get a CRC 8 for supplied data
 *
 */
uint8_t ucGetCrc8( const uint8_t data[], size_t len )
{
    static const uint8_t CRCTable[ 256 ] =
    {
        0x00, 0x07, 0x0E, 0x09, 0x1C, 0x1B, 0x12, 0x15,
        0x38, 0x3F, 0x36, 0x31, 0x24, 0x23, 0x2A, 0x2D,
        0x70, 0x77, 0x7E, 0x79, 0x6C, 0x6B, 0x62, 0x65,
        0x48, 0x4F, 0x46, 0x41, 0x54, 0x53, 0x5A, 0x5D,
        0xE0, 0xE7, 0xEE, 0xE9, 0xFC, 0xFB, 0xF2, 0xF5,
        0xD8, 0xDF, 0xD6, 0xD1, 0xC4, 0xC3, 0xCA, 0xCD,
        0x90, 0x97, 0x9E, 0x99, 0x8C, 0x8B, 0x82, 0x85,
        0xA8, 0xAF, 0xA6, 0xA1, 0xB4, 0xB3, 0xBA, 0xBD,
        0xC7, 0xC0, 0xC9, 0xCE, 0xDB, 0xDC, 0xD5, 0xD2,
        0xFF, 0xF8, 0xF1, 0xF6, 0xE3, 0xE4, 0xED, 0xEA,
        0xB7, 0xB0, 0xB9, 0xBE, 0xAB, 0xAC, 0xA5, 0xA2,
        0x8F, 0x88, 0x81, 0x86, 0x93, 0x94, 0x9D, 0x9A,
        0x27, 0x20, 0x29, 0x2E, 0x3B, 0x3C, 0x35, 0x32,
        0x1F, 0x18, 0x11, 0x16, 0x03, 0x04, 0x0D, 0x0A,
        0x57, 0x50, 0x59, 0x5E, 0x4B, 0x4C, 0x45, 0x42,
        0x6F, 0x68, 0x61, 0x66, 0x73, 0x74, 0x7D, 0x7A,
        0x89, 0x8E, 0x87, 0x80, 0x95, 0x92, 0x9B, 0x9C,
        0xB1, 0xB6, 0xBF, 0xB8, 0xAD, 0xAA, 0xA3, 0xA4,
        0xF9, 0xFE, 0xF7, 0xF0, 0xE5, 0xE2, 0xEB, 0xEC,
        0xC1, 0xC6, 0xCF, 0xC8, 0xDD, 0xDA, 0xD3, 0xD4,
        0x69, 0x6E, 0x67, 0x60, 0x75, 0x72, 0x7B, 0x7C,
        0x51, 0x56, 0x5F, 0x58, 0x4D, 0x4A, 0x43, 0x44,
        0x19, 0x1E, 0x17, 0x10, 0x05, 0x02, 0x0B, 0x0C,
        0x21, 0x26, 0x2F, 0x28, 0x3D, 0x3A, 0x33, 0x34,
        0x4E, 0x49, 0x40, 0x47, 0x52, 0x55, 0x5C, 0x5B,
        0x76, 0x71, 0x78, 0x7F, 0x6A, 0x6D, 0x64, 0x63,
        0x3E, 0x39, 0x30, 0x37, 0x22, 0x25, 0x2C, 0x2B,
        0x06, 0x01, 0x08, 0x0F, 0x1A, 0x1D, 0x14, 0x13,
        0xAE, 0xA9, 0xA0, 0xA7, 0xB2, 0xB5, 0xBC, 0xBB,
        0x96, 0x91, 0x98, 0x9F, 0x8A, 0x8D, 0x84, 0x83,
        0xDE, 0xD9, 0xD0, 0xD7, 0xC2, 0xC5, 0xCC, 0xCB,
        0xE6, 0xE1, 0xE8, 0xEF, 0xFA, 0xFD, 0xF4, 0xF3U
    };

    uint8_t crc = 0;
    int     i;

    for(i = 0; i < len; i++)
    {
        crc = CRCTable[ crc ^ data[ i ] ];
    }
    return crc;
}
