/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the MCTP message handling functions
 *
 * @file mctp_commands.c
 *
 */


/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <unistd.h>
#include <string.h>
#include "mctp.h"
#include "util.h"
#include "bmc_proxy_driver.h"


/******************************************************************************/
/* Defines                                                                   */
/******************************************************************************/

#define MCTP_TYPE_CONTROL_MSG ( 0x0 )
#define MCTP_TYPE_PLDM        ( 0x1 )
#define MCTP_TYPE_SPDM        ( 0x05 )

/* Base & protocol for DSP0236_1.3.1 Versions */

#define MCTP_BASE_SPEC_VER_1_3_0 0xf1f3f000
#define MCTP_BASE_SPEC_VER_1_3_1 0xf1f3f100

#define MCTP_CTRL_PROTOCOL_VER_1_3_0 0xf1f3f000
#define MCTP_CTRL_PROTOCOL_VER_1_3_1 0xf1f3f100

/* PLDM over MCTP Binding Specification */
#define PLDM_OVER_MCTP_DSP0241_VER_1_0_0 0xf1f0f000


#define BYTE_SWAP32( val ) ( ( ( ( val ) & 0xff000000 ) >> 24 ) | \
                             ( ( ( val ) & 0x00ff0000 ) >>  8 ) | \
                             ( ( ( val ) & 0x0000ff00 ) <<  8 ) | \
                             ( ( ( val ) & 0x000000ff ) << 24 ) )

/* DSP0236: Table 18 - Get MCTP version support message */
#define MCTP_GET_VERSION_BASE_SPEC             0xFF
#define MCTP_GET_VERSION_CONTROL_PROTOCOL_SPEC 0x00
#define MCTP_GET_VERSION_DSP0241               0x01

#define SINGLE_ENDPOINT_NOT_MCTP_BRIDGE 0x00
#define MAX_EID_SUPPORTED_RANGE         1

#define SETEID_RESP_EIDASSIGN_STATUS_OFFSET ( 4 )


/******************************************************************************/
/* Externs                                                                    */
/******************************************************************************/

extern int iGetUuid( uint8_t *pucUuid );


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    mctpCtrlCmdID
 * @brief   MCTP Command ID values
 *          Refer Table 12 of DSP0236_1.3.0 - MCTP Base Spec
 */
enum mctpCtrlCmdID
{
    MCTP_CMD_SETEID              = ( 0x1 ),
    MCTP_CMD_GETEID              = ( 0x2 ),
    MCTP_CMD_GETUUID             = ( 0x3 ),
    MCTP_CMD_GETVERSION          = ( 0x4 ),
    MCTP_CMD_GETMSGTYPE          = ( 0x5 ),
    MCTP_CMD_ROUTING_INFO_UPDATE = ( 0x9 ),
    MAX_MCTP_CTRL_COMMAND

};

/**
 * @enum    setEIDOperations_req
 * @brief   Set EID Operations
 */
enum setEIDOperations_req
{
    SET_EID             = ( 0x00 ),
    FORCE_EID           = ( 0x01 ),
    RESET_EID           = ( 0x02 ),
    SET_DISCOVERED_FLAG = ( 0x03 )

};

/**
 * @enum    setEIDassigmntStatus_resp
 * @brief   Set EID Responses
 */
enum setEIDassigmntStatus_resp
{
    EID_ASSIGNMENT_ACCEPTED = ( 0x0 ),
    EID_ASSIGNMENT_REJECTED = ( 0x1 )

};


/******************************************************************************/
/* Local Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Handle the set EID command
 *
 * @param   payloadIn   Received message payload
 * @param   payloadOut  Response message payload
 *
 * @return  Size of response
 */
uint8_t mctp_cmd_SetEID( const void *payloadIn, void *payloadOut );

/**
 * @brief   Handle the get EID command
 *
 * @param   payloadIn   Received message payload
 * @param   payloadOut  Response message payload
 *
 * @return  Size of response
 */
uint8_t mctp_cmd_GetEID( const void *payloadIn, void *payloadOut );

/**
 * @brief   Handle the get UUID command
 *
 * @param   payloadIn   Received message payload
 * @param   payloadOut  Response message payload
 *
 * @return  Size of response
 */
uint8_t mctp_cmd_GetUUID( const void *payloadIn, void *payloadOut );

/**
 * @brief   Handle the get MCTP version command
 *
 * @param   payloadIn   Received message payload
 * @param   payloadOut  Response message payload
 *
 * @return  Size of response
 */
uint8_t mctp_cmd_GetMCTPVersion( const void *payloadIn, void *payloadOut );

/**
 * @brief   Determine the MCTP message type from the payload
 *
 * @param   payloadIn   Received message payload
 * @param   payloadOut  Response message payload
 *
 * @return  Size of response
 */
uint8_t mctp_cmd_GetMCTPMsgType( const void *payloadIn, void *payloadOut );


/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

uint16_t _EID = 0;

const static uint8_t mctpSupportedMsgTypes[] =
{
    MCTP_TYPE_CONTROL_MSG,
    MCTP_TYPE_PLDM
};

const static mctpFunction mctp_func[ MAX_MCTP_CTRL_COMMAND ] =
{
    [ MCTP_CMD_SETEID ]     = mctp_cmd_SetEID,
    [ MCTP_CMD_GETEID ]     = mctp_cmd_GetEID,
    [ MCTP_CMD_GETUUID ]    = mctp_cmd_GetUUID,
    [ MCTP_CMD_GETVERSION ] = mctp_cmd_GetMCTPVersion,
    [ MCTP_CMD_GETMSGTYPE ] = mctp_cmd_GetMCTPMsgType

};

/* Flag to Maintain status of EID assignment */
static uint8_t eidSetFlag = 0;


/******************************************************************************/
/* Function definitions                                                       */
/******************************************************************************/

/**
 * @brief   Get the correct MCTP function to process the message
 */
int get_mctp_func( uint8_t mctp_cmd, mctpFunction *func )
{
    *func = NULL;
    if( mctp_func[ mctp_cmd ] != NULL )
    {
        *func = mctp_func[ mctp_cmd ];
        return RESP_MCTP_CTRL_MSG_SUCCESS;                                     // success
    }

    return RESP_MCTP_CTRL_MSG_ERROR_MCTP_CMD_NS;
}


/**
 * @brief   Handle the set EID command
 */
uint8_t mctp_cmd_SetEID( const void *payloadIn, void *payloadOut )
{
    uint8_t response_size = 0;

    const struct __attribute__ ( ( __packed__ ) )
    {
        uint8_t operation;
        uint8_t endPointId;
    }

    *mctp_setEID_req_s = payloadIn;

    struct __attribute__ ( ( __packed__ ) )
    {
        uint8_t complnCode;
        uint8_t EIDAssignAllocStatus;
        uint8_t EIDSetting;
        uint8_t EIDPoolSize;
    }

    *mctp_setEID_resp_s = payloadOut;

    /*
     * Check if the EID received is Valid
     */
    if( ( mctp_setEID_req_s->endPointId  != 0x00 ) &&
        ( mctp_setEID_req_s->endPointId != 0xFF ) )
    {
        switch( mctp_setEID_req_s->operation )
        {
        case SET_EID:
        {
            if( !eidSetFlag )
            {
                /* EID Not yet SET */
                _EID = mctp_setEID_req_s->endPointId;

                /* Fill response pkt */
                response_size += sizeof( *mctp_setEID_resp_s );

                mctp_setEID_resp_s->complnCode = RESP_MCTP_CTRL_MSG_SUCCESS;

                /* [ 5:4 ] = 00b , [ 1:0 ] = 00b */
                mctp_setEID_resp_s->EIDAssignAllocStatus |=
                    ( EID_ASSIGNMENT_ACCEPTED << SETEID_RESP_EIDASSIGN_STATUS_OFFSET );

                mctp_setEID_resp_s->EIDSetting  = mctp_setEID_req_s->endPointId;
                mctp_setEID_resp_s->EIDPoolSize = 0x00;
                /* Set the Flag to 1*/
                eidSetFlag = 1;
            }
            else
            {
                //EID already set
                response_size                 += sizeof( *mctp_setEID_resp_s );
                mctp_setEID_resp_s->complnCode = RESP_MCTP_CTRL_MSG_SUCCESS;

                /* [ 5:4 ] = 01b , [ 1:0 ] = 00b */
                mctp_setEID_resp_s->EIDAssignAllocStatus |=
                    ( EID_ASSIGNMENT_REJECTED << SETEID_RESP_EIDASSIGN_STATUS_OFFSET );
                mctp_setEID_resp_s->EIDSetting  = mctp_setEID_req_s->endPointId;
                mctp_setEID_resp_s->EIDPoolSize = 0x00;
            }

        }
        break;

        case FORCE_EID:
        {
            _EID = mctp_setEID_req_s->endPointId;

            /* Fill response pkt */
            response_size += sizeof( *mctp_setEID_resp_s );

            mctp_setEID_resp_s->complnCode = RESP_MCTP_CTRL_MSG_SUCCESS;

            /* [ 5:4 ] = 00b , [ 1:0 ] = 00b */
            mctp_setEID_resp_s->EIDAssignAllocStatus |=
                ( EID_ASSIGNMENT_ACCEPTED << SETEID_RESP_EIDASSIGN_STATUS_OFFSET );

            mctp_setEID_resp_s->EIDSetting  = mctp_setEID_req_s->endPointId;
            mctp_setEID_resp_s->EIDPoolSize = 0x00;
        }
        break;

        case RESET_EID:
        {
            response_size                 += sizeof( *mctp_setEID_resp_s );
            mctp_setEID_resp_s->complnCode = RESP_MCTP_CTRL_MSG_ERROR_INVALID_DATA;
        }
        break;

        case SET_DISCOVERED_FLAG:
        {
            response_size                 += sizeof( *mctp_setEID_resp_s );
            mctp_setEID_resp_s->complnCode = RESP_MCTP_CTRL_MSG_ERROR_INVALID_DATA;
        }
        break;

        default:
        {
            break;
        }
        }

    }
    else
    {
        response_size                 += sizeof( *mctp_setEID_resp_s );
        mctp_setEID_resp_s->complnCode = RESP_MCTP_CTRL_MSG_ERROR_INVALID_DATA;

    }

    return response_size;
}

/**
 * @brief   Handle the get EID command
 */
uint8_t mctp_cmd_GetEID( const void *payloadIn, void *payloadOut )
{
    uint8_t response_size = 0;

    struct __attribute__ ( ( __packed__ ) )
    {
        uint8_t complnCode;
        uint8_t endPointID;
        uint8_t endPointType;
        uint8_t mediumSpecfInfo;
    }

    *mctp_getEID_resp_s = payloadOut;

    response_size += sizeof( *mctp_getEID_resp_s );

    mctp_getEID_resp_s->complnCode = RESP_MCTP_CTRL_MSG_SUCCESS;

    if( !eidSetFlag )
    {
        /* EID Not yet Set */
        mctp_getEID_resp_s->endPointID = 0x00;
    }
    else
    {
        mctp_getEID_resp_s->endPointID = _EID;
    }

    mctp_getEID_resp_s->endPointType    = 0x01;                                // Simple EndPoint(0x0), Static EID Supported(0x1)
    mctp_getEID_resp_s->mediumSpecfInfo = 0x00;

    return response_size;
}


/**
 * @brief   Handle the get UUID command
 */
uint8_t mctp_cmd_GetUUID( const void *payloadIn, void *payloadOut )
{
    uint8_t response_size      = 0;
    uint8_t *mctp_getUUID_resp = payloadOut;

    mctp_getUUID_resp[ response_size++ ] = RESP_MCTP_CTRL_MSG_SUCCESS;

    response_size += iGetUuid( &mctp_getUUID_resp[ 1 ] );

    return response_size;
}

/**
 * @brief   Handle the get MCTP version command
 */
uint8_t mctp_cmd_GetMCTPVersion( const void *payloadIn, void *payloadOut )
{
    uint8_t count         = 0;
    uint8_t response_size = 0;

    struct __attribute__ ( ( __packed__ ) )
    {
        uint8_t msg_type_num;
    }

    const *mctp_get_version_req_s = payloadIn;

    struct __attribute__ ( ( __packed__ ) )
    {
        uint8_t  completion_code;
        uint8_t  ver_type_count;
        uint32_t versions [];
    }

    *mctp_get_version_resp_s = payloadOut;

    switch( mctp_get_version_req_s->msg_type_num )
    {
    case MCTP_GET_VERSION_BASE_SPEC:
    case MCTP_GET_VERSION_CONTROL_PROTOCOL_SPEC:
    {
        /* Return MCTP base and control version as 1.3.1  */
        mctp_get_version_resp_s->versions[ count++ ] = BYTE_SWAP32( MCTP_BASE_SPEC_VER_1_3_1 );
        mctp_get_version_resp_s->ver_type_count      = count;
        break;
    }

    case MCTP_GET_VERSION_DSP0241:
    {
        /* Return PLDM over MCTP binding specification version as 1.0.0 */
        mctp_get_version_resp_s->versions[ count++ ] = BYTE_SWAP32( PLDM_OVER_MCTP_DSP0241_VER_1_0_0 );
        mctp_get_version_resp_s->ver_type_count      = count;
        break;
    }

    default:
    {
        mctp_get_version_resp_s->completion_code = RESP_MCTP_CTRL_MSG_TYPE_UNSUPPORTED;
        break;
    }
    }

    if( mctp_get_version_resp_s->completion_code != 0 )
    {
        return response_size = 1;
    }
    else
    {
        mctp_get_version_resp_s->completion_code = 0;
        response_size = ( ( sizeof( uint32_t ) * count ) + sizeof( *mctp_get_version_resp_s ) );
    }

    return response_size;

}

/**
 * @brief   Determine the MCTP message type from the payload
 */
uint8_t mctp_cmd_GetMCTPMsgType( const void *payloadIn, void *payloadOut )
{
    uint8_t count                     = 0;
    uint8_t response_size             = 0;
    uint8_t *mctp_getMCTPMsgType_resp = payloadOut;

    mctp_getMCTPMsgType_resp[ response_size++ ] = RESP_MCTP_CTRL_MSG_SUCCESS;

    // Total number of Supported MCTP Message Types
    mctp_getMCTPMsgType_resp[ response_size++ ] = ARRAY_LEN( mctpSupportedMsgTypes );

    // Supported Message Types
    for( count = 0; count < ARRAY_LEN( mctpSupportedMsgTypes ) ; count++)
    {
        mctp_getMCTPMsgType_resp[ response_size++ ] = mctpSupportedMsgTypes[ count ];
    }

    return response_size;
}
