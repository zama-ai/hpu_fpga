/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the API for the Alveo Management Interface (BMC) proxy driver
 *
 * @file mctp_parser.c
 *
 */

#include <unistd.h>
#include "standard.h"
#include "mctp.h"

/******************************************************************************/
/* Local Function Declarations                                                */
/******************************************************************************/

/**
 * @brief   Create the initial data for an MCTP response message
 *
 * @param   RqPkt         Pointer to the MCTP request packet
 * @param   RspPkt        Pointer to the MCTP response packet
 *
 */
void init_mctp_response( const mctp_packet *RqPkt, mctp_packet *RspPkt );


/******************************************************************************/
/* Local Function Implementations                                             */
/******************************************************************************/

/**
 * @brief   Create the initial data for an MCTP response message
 *
 */
void init_mctp_response( const mctp_packet *RqPkt, mctp_packet *RspPkt )
{
    RspPkt->instanceID = RqPkt->instanceID;
    RspPkt->rq         = 0;                                                    // this is a response, not a request (per DSP0236 sec 11.5)
    RspPkt->d          = 0;                                                    // MDH - DSP0236 11.5 seems to indicate this should be 0 for control message responses
    RspPkt->mctp_cmd   = RqPkt->mctp_cmd;
}


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/**
 * @brief   Process data received in an MCTP message
 *
 * @return  The number of bytes in the response
 */
int process_mctp_request( void *ReqBuff, void *RespBuff, int request_pkt )
{
    int resp_size = 2;
    int cmd       = 0;
    int ret       = 0;

    mctpFunction processor = NULL;
    mctp_packet  *req      = ReqBuff;
    mctp_packet  *resp     = RespBuff;

    if( TRUE == request_pkt )
    {
        init_mctp_response( req, resp );
    }

    cmd = req->mctp_cmd;

    ret = get_mctp_func( cmd, &processor );
    if( ret != 0 )
    {
        resp->payLoad[ 0 ] = ret;
        resp_size++;
    }
    else
    {
        if( NULL != processor )
        {
            resp_size += processor( req->payLoad, resp->payLoad );
        }
    }
    return resp_size;
}
