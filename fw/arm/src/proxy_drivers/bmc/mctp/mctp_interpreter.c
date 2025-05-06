/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the MCTP Interpreter functionality
 *
 * @file pldm_mctp_interpreter.c
 *
 */


/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <util.h>
#include "bmc_proxy_driver.h"

/* Include PMCI header files */
#include "pldm.h"
#include "mctp.h"
#include "pll.h"
#include "bmc_proxy_driver.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define MCTP_MESSAGE_DELAY_MS  ( 10 )
#define PLDM_HDR_BYTE1_REQ_MSG ( 0x80 )
#define MCTP_MIN_NUM_BYTES     ( 10 )
#define PLDM_HDR_VER           ( 0x01 )
#define PLDM_TAG_BYTE          ( 0xC8 )

#define BOTH_SOM_EOM_HEADER                          3
#define ONLY_SOM_HEADER                              1
#define ONLY_EOM_HEADER                              2
#define NEITHER_SOM_NOR_EOM_HEADER                   0
#define MCTP_HEADER                                  7                         //Medium specific Header + MCTP transport Header
#define PKT_SEQ_MODULO                               4
#define MAX_MULTIPART_BUFFER_SIZE                    1024
#define SPDM_OOB_THREAD_FLASH_SET_RESYNC_FLAG_BITSET 0x80

/******************************************************************************/
/* Locals                                                                     */
/******************************************************************************/

uint8_t multiPartReqBuffer[ MAX_MULTIPART_BUFFER_SIZE ] =
{
    0
};

int request_pkt = TRUE;

uint8_t BMC_endpoint_id_g     = 0;
uint8_t SC_endpoint_id_g      = 0;
uint8_t MCTP_header_version_g = 0;
uint8_t BMC_slave_address_g   = 0;


/******************************************************************************/
/* Externs                                                                    */
/******************************************************************************/

extern uint16_t _EID;                                                          /* Stores assigned EID value */
extern int iResponseDataWrite( uint8_t *pucData, uint16_t usDataSize );


/******************************************************************************/
/* Enums                                                                    */
/******************************************************************************/

/**
 * @enum    OoB_RequestType
 * @brief   Possible Out Of Bound request types
 */
typedef enum OoB_RequestType
{
    OoB_REQ_TYPE_UNKNOWN        = ( 0x0 ),
    OoB_REQ_TYPE_FRU_ONLY       = ( 0x1 ),
    OoB_REQ_TYPE_SMBUS_DEFAULT  = ( 0x2 ),
    OoB_REQ_TYPE_SMBUS_STANDARD = ( 0x3 ),
    OoB_REQ_TYPE_PLDM_MCTP      = ( 0x4 ),
    MAX_OoB_REQ_TYPE

} OoB_RequestType;

/**
 * @brief   Send response to MCTP message
 */
static int send_mctp_response( uint8_t *buffer, size_t len )
{
    int retVal = 0;

    retVal = iResponseDataWrite( buffer, ( uint16_t )len );

    return ( retVal );
}

/**
 * @brief   Process the MCTP request message
 */
uint16_t process_request( mctp_message *req, mctp_message *resp )
{
    unsigned    payload_size = 0U;
    mctp_packet *temp        = ( mctp_packet * )req->mctp_msg_header;

    {
        /* DSP0236 sec 11.5 if bit rq == 1b, packet is request packet else it is response packet */
        if( temp->rq == 1 )
        {
            request_pkt = TRUE;
        }
        else
        {
            request_pkt = FALSE;
        }

        /* differentiate between MCTP Vs PLDM commands */
        if( req->payl.msg_type == MCTP_MSG_MCTP_CONTROL )
        {
            resp->payl.msg_type = MCTP_MSG_MCTP_CONTROL;
            payload_size        = process_mctp_request( req->mctp_msg_header, resp->mctp_msg_header, request_pkt );
        }
        else if( req->payl.msg_type == MCTP_MSG_MCTP_PLDM )
        {
            resp->payl.msg_type = MCTP_MSG_MCTP_PLDM;
            payload_size        = process_pldm_request( req->mctp_msg_header, resp->mctp_msg_header, request_pkt );
        }
    }

    return ( payload_size += 1 );                                              /* account for the msg_type byte that is included in the first response packet */
}

/**
 * @brief   Process a received PMCI message
 *
 */
void process_pmci_request( int i2cSlaveReadCount )
{
    unsigned pkt_size     = 0U;
    unsigned ret_size     = 0U;
    unsigned sent_size    = 0U;
    unsigned payload_size = 0U;
    uint8_t  saved_byte   = 0U;
    uint8_t  byte_count   = 0U;

    mctp_message *req  = ( mctp_message * ) ReqBuffer;
    mctp_message *resp = ( mctp_message * ) RespBuffer;

    uint8_t         SOM               = req->som;
    uint8_t         EOM               = ( req->eom ) << 1;
    uint8_t         flag              = SOM | EOM;
    uint8_t         seq_num           = req->seq_num;
    uint8_t         expected_seq_num  = 0;
    static uint8_t  prv_seq_num       = 0;
    static uint32_t staging_buff_size = 0;

    /* collect source and destination eid's
     * will be help full to raise an request to BMC
     */
    BMC_endpoint_id_g     = req->src_ep_id;
    SC_endpoint_id_g      = req->dest_ep_id;
    MCTP_header_version_g = req->hdr_version;
    BMC_slave_address_g   = req->src_slave_addr;

    if( i2cSlaveReadCount < ( sizeof( mctp_message ) ) /*  || req->cmd_code != MCTP_COMMAND_CODE */ ) /* Not a valid MCTP message */
    {
        PLL_INF( BMC_NAME, "\n\r Invalid mctp request\n\r" );
        PLL_INF( BMC_NAME,
                 "\n\r i2cSlaveReadCount %d sizeof( mctp_message ) %d\n\r",
                 i2cSlaveReadCount,
                 sizeof( mctp_message ) );
        return;
    }

    /*
     * Drop the the request if the PEC is incorrect
     * incoming request doesn't have msp432 slave address passed in message.
     * Add the slave address.
     */
    /* This is the address we set our SMBus up with */
    req->dest_slave_addr = ( 0x18 << 1 );

#if defined( SPDM_DEBUG )
    /*
     * Print the request command packet
     */
    uint8_t print_req_pkt[ 64 ] =
    {
        0x00
    };
    pvOSAL_MemCpy( print_req_pkt, req, req->byte_count + 4 );
    PLL_INF( BMC_NAME, "Request Packet : " );

    int req_pkt_print_index = 0;
    for(req_pkt_print_index = 0; req_pkt_print_index < ( req->byte_count + 4 ); req_pkt_print_index++)
    {
        PLL_INF( BMC_NAME, "0x%x ", print_req_pkt[ req_pkt_print_index ] );
    }
    PLL_INF( BMC_NAME, "\r\n" );
#endif

    byte_count = req->byte_count + 2;
    if( byte_count != i2cSlaveReadCount )
    {
        PLL_INF( BMC_NAME, "Invalid mctp request - byte count is wrong\n\r" );
        return;
    }

    /*
     * Drop the request when EID is
     * Not NUll & not equal to Assigned EID through SET_EID command
     */
    if( ( req->dest_ep_id != _EID ) && ( req->dest_ep_id != 0 ) )
    {
        PLL_INF( BMC_NAME, "\n\r EID not matched , ignoring the packet\n\r" );
        return;
    }

    /* multi part receive */
    switch( flag )
    {
    case BOTH_SOM_EOM_HEADER:                                                  //single packet
    {
        payload_size = process_request( req, resp );

        /* LOG_ERROR_MSG("SIN_PKT : DS %d CC %d BC %d SA %d MH %d DEID %d SEID %d SOM %d EOM %d TO %d Tag %d \n",
                             req->dest_slave_addr,req->cmd_code,req->byte_count,req->src_slave_addr,
                             req->mctp_msg_header,req->dest_ep_id,req->src_ep_id,req->som,
                             req->eom,req->to,req->tag); */

        break;
    }

    case ONLY_SOM_HEADER:
    {
        /* start of a new message - start the new context for
         * future message reception. If an existing context is
         * already present, drop it.
           LOG_ERROR_MSG("START : DS %d CC %d BC %d SA %d MH %d DEID %d SEID %d SOM %d EOM %d TO %d Tag %d \n",
                     req->dest_slave_addr,req->cmd_code,req->byte_count,req->src_slave_addr,
                     req->mctp_msg_header,req->dest_ep_id,req->src_ep_id,req->som,
                     req->eom,req->to,req->tag); */

        pvOSAL_MemSet( multiPartReqBuffer, '0', sizeof( multiPartReqBuffer ) );

        if( staging_buff_size == 0 )
        {
            pvOSAL_MemCpy( multiPartReqBuffer, req, byte_count );
            staging_buff_size = byte_count;
            prv_seq_num       = seq_num;
        }
        else
        {
            pvOSAL_MemSet( multiPartReqBuffer, '0', sizeof( multiPartReqBuffer ) );
            staging_buff_size = 0;
            prv_seq_num       = 0;
        }
        return;
    }

    case ONLY_EOM_HEADER:                                                      /* End of Packet */
    {
        /* LOG_ERROR_MSG("END : DS %d CC %d BC %d SA %d MH %d DEID %d SEID %d SOM %d EOM %d TO %d Tag %d \n",
                     req->dest_slave_addr,req->cmd_code,req->byte_count,req->src_slave_addr,
                     req->mctp_msg_header,req->dest_ep_id,req->src_ep_id,req->som,
                     req->eom,req->to,req->tag); */

        /* Out-of-sequence packet sequence number - DSP0236 sec 8.8 */
        expected_seq_num = ( prv_seq_num + 1 ) % PKT_SEQ_MODULO;

        if( expected_seq_num != req->seq_num )
        {
            PLL_INF( BMC_NAME, "\r\nSequence number %d does not match expected %d", req->seq_num, expected_seq_num );
            pvOSAL_MemSet( multiPartReqBuffer, '0', sizeof( multiPartReqBuffer ) );
            staging_buff_size = 0;
            prv_seq_num       = 0;
            return;
        }

        pvOSAL_MemCpy( multiPartReqBuffer + staging_buff_size, req->payl.mctp_msg_payload, byte_count - MCTP_HEADER );
        staging_buff_size = staging_buff_size + byte_count - MCTP_HEADER;
        payload_size      = process_request( ( mctp_message * )multiPartReqBuffer, resp );
        staging_buff_size = 0;
        prv_seq_num       = 0;
        break;
    }

    case NEITHER_SOM_NOR_EOM_HEADER:                                           //Middle Packet
    {
        /* Neither SOM nor EOM
           LOG_ERROR_MSG("MIDDLE : DS %d CC %d BC %d SA %d MH %d DEID %d SEID %d SOM %d EOM %d TO %d Tag %d \n",
                     req->dest_slave_addr,req->cmd_code,req->byte_count,req->src_slave_addr,
                     req->mctp_msg_header,req->dest_ep_id,req->src_ep_id,req->som,
                     req->eom,req->to,req->tag);*/

        /* Out-of-sequence packet sequence number - DSP0236 sec 8.8 */
        expected_seq_num = ( prv_seq_num + 1 ) % PKT_SEQ_MODULO;

        if( expected_seq_num != req->seq_num )
        {
            PLL_INF( BMC_NAME, "\r\nSequence number %d does not match expected %d", req->seq_num, expected_seq_num );
            pvOSAL_MemSet( multiPartReqBuffer, '0', sizeof( multiPartReqBuffer ) );
            staging_buff_size = 0;
            prv_seq_num       = 0;
            return;
        }

        pvOSAL_MemCpy( multiPartReqBuffer + staging_buff_size, req->payl.mctp_msg_payload, byte_count - MCTP_HEADER );
        staging_buff_size += ( byte_count - MCTP_HEADER );
        prv_seq_num        = seq_num;
        return;
    }
    }

    if( request_pkt )
    {
        /*
         * Preparing the Response header
         */
        /* We only respond to MCTP command so removed cmd_code from struct
           resp->cmd_code = MCTP_COMMAND_CODE;
         */

        resp->src_slave_addr = ( 0x18 << 1 ) | 0x1;
        resp->hdr_version    = req->hdr_version;
        resp->dest_ep_id     = req->src_ep_id;
        resp->src_ep_id      = req->dest_ep_id;
        /* SOM = first time through loop */
        /* EOM = remaining size <= MCTP_MAX_PAYLOAD_SIZE */
        resp->tag     = req->tag;
        resp->seq_num = 0;
        resp->som     = 1;
        while( payload_size > 0 )                                              /* implement MCTP message disassembly to enforce maximum payload size */
        {
            if( payload_size > MCTP_MAX_PAYLOAD_SIZE )
            {
                pkt_size   = MCTP_MAX_PAYLOAD_SIZE;
                resp->eom  = 0;                                                /* not the last packet */
                saved_byte = resp->payl.mctp_msg_payload[ MCTP_MAX_PAYLOAD_SIZE ]; /* save byte that will get wiped out by PEC */
            }
            else
            {
                pkt_size  = payload_size;
                resp->eom = 1;                                                 /* last packet */
            }
            /* Destination address needs to be 7-bit address */
            resp->dest_slave_addr = ( ( req->src_slave_addr & ~( 0x1 ) ) >> 1 );
            /* Update the byte count at the end before pec calculation */
            ret_size         = MCTP_HEADER + pkt_size;                         /* add 7 bytes of header (dest addr through msg_tag) */
            resp->byte_count = ret_size - 2;                                   /* subtract dest addr and byte count; */

#if defined( SPDM_DEBUG )
            /*
             * Print the Response command packet
             */
            uint8_t print_resp_pkt[ 64 ] =
            {
                0x00
            };
            pvOSAL_MemCpy( &print_resp_pkt[ 0 ], RespBuffer, ret_size );
            PLL_INF( BMC_NAME, "Response Packet : " );

            int resp_pkt_print_index = 0;
            for(resp_pkt_print_index = 0; resp_pkt_print_index < ret_size; resp_pkt_print_index++)
            {
                PLL_INF( BMC_NAME, "0x%x ", print_resp_pkt[ resp_pkt_print_index ] );
            }
            PLL_INF( BMC_NAME, "\r\n" );
#endif

            /* send MCTP response */
            sent_size = send_mctp_response( RespBuffer, ret_size );

            if( sent_size != ret_size )
            {
                return;                                                        /* send failed; abort */
            }

            payload_size -= pkt_size;                                          /* calculate the remaining payload */
            if( payload_size > 0 )
            {
                iOSAL_Task_SleepMs( MCTP_MESSAGE_DELAY_MS );
                resp->payl.mctp_msg_payload[ MCTP_MAX_PAYLOAD_SIZE ] = saved_byte; /* restore byte wiped out by PEC */
                resp->seq_num += 1;                                            /* increment sequence number */
                resp->som      = 0;                                            /* no longer start of message */

                vOSAL_MemMove( resp->payl.mctp_msg_payload,
                               &resp->payl.mctp_msg_payload[ MCTP_MAX_PAYLOAD_SIZE ],
                               payload_size );                                 /* move remaining payload to the start of the payload buffer */
            }
        }
        if( ret_size )
        {
            //PLL_INF( BMC_NAME, "\n\r MCTP response Success \n\r");
#if defined( SPDM_DEBUG )
            PLL_INF( BMC_NAME,
                     "\r\nTime taken to process the SPDM command : %d ms \r\n",
                     spdm_tick_stop_time - spdm_tick_start_time );
#endif
        }
        else
        {
            PLL_INF( BMC_NAME, "PLDM processing failed\n\r" );
        }

    }

}
