/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the PLDM parser structs and functions
 *
 * @file pldm_parser.c
 *
 */


/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <unistd.h>
#include "pldm_commands.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

/*
 * Parsing message fields
 */

#define BYTE_1_RQ_OFFSET ( 7 )
#define BYTE_1_RQ_MASK   ( 0x1 << BYTE_1_RQ_OFFSET )

#define BYTE_1_D_OFFSET ( 6 )
#define BYTE_1_D_MASK   ( 0x1 << BYTE_1_D_OFFSET )

#define BYTE_1_INST_ID_OFFSET ( 0 )
#define BYTE_1_INST_ID_MASK   ( 0x1F << BYTE_1_INST_ID_OFFSET )

#define BYTE_2_HDR_OFFSET ( 6 )
#define BYTE_2_HDR_MASK   ( 0x3 << BYTE_2_HDR_OFFSET )

#define BYTE_2_TYPE_OFFSET ( 0 )
#define BYTE_2_TYPE_MASK   ( 0x7 << BYTE_2_TYPE_OFFSET )

#define BYTE_3_CMD_OFFSET ( 0 )
#define BYTE_3_CMD_MASK   ( 0xFF << BYTE_3_CMD_OFFSET )

#define MAX_PAYLOAD_SIZE ( 128 )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  pldm_packet
 * @brief   Structure of the PLDM Packet
 */
typedef struct pldm_packet
{
    unsigned char rq_d_instanceID;
    unsigned char hdr_pldm_type;
    unsigned char pldm_cmd;
    unsigned char PayLoad[ MAX_PAYLOAD_SIZE ];

}pldm_packet;


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Clear the PLDM Packet
 */
void clear_pldm_packet( pldm_packet *pkt )
{
    /*
     * mem set 0 to pkt (sizeof pldm_packet)
     */
    uint8_t *ptr = ( uint8_t * ) pkt;
    int     i;

    for(i = 0; i < 3 + MAX_PAYLOAD_SIZE; i++)
    {
        ptr[ i ] = 0;
    }
}

/**
 * @brief   Initialise the data in the PLDM response
 */
void init_pldm_response( const pldm_packet *RqPkt, pldm_packet *RspPkt )
{
    RspPkt->rq_d_instanceID = RqPkt->rq_d_instanceID & ~( BYTE_1_RQ_MASK | BYTE_1_D_MASK );
    RspPkt->hdr_pldm_type   = RqPkt->hdr_pldm_type;
    RspPkt->pldm_cmd        = RqPkt->pldm_cmd;
}


/**
 * @brief   Process a PLDM message
 */
int process_pldm_request( void *ReqBuff, void *RespBuff, int request_pkt )
{
    int resp_size = 3;
    int ret       = 0;
    int type      = 0;
    int cmd       = 0;

    pldm_packet *req  = ReqBuff;
    pldm_packet *resp = RespBuff;

    PldmFunction processor = NULL;

    /*
     * todo: decide what to do if the header is incorrect.
     */
    if( request_pkt )
    {
        init_pldm_response( req, resp );
    }

    type = ( req->hdr_pldm_type & BYTE_2_TYPE_MASK ) >> BYTE_2_TYPE_OFFSET;

    cmd = ( req->pldm_cmd & BYTE_3_CMD_MASK ) >> BYTE_3_CMD_OFFSET;

    /*
     * todo: Verify for correct header information.
     */

    ret = get_pldm_func( type, cmd, &processor );

    if( ret != 0 )
    {
        resp->PayLoad[ 0 ] = ret;
        resp_size++;
    }
    else
    {
        /*
         * todo: Assert processor is not null
         */
        resp_size += processor( req->PayLoad, resp->PayLoad );
    }

    return resp_size;

}
