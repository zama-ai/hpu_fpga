/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains MCTP enums and structs
 *
 * @file mctp.h
 *
 */

#ifndef INC_MCTP_H_
#define INC_MCTP_H_

#include "standard.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define MCTP_MAX_PAYLOAD_SIZE  ( 64 )                                          // Max MCTP payload size allowed; segment anything larger than this
#define MCTP_COMMAND_CODE      ( 0x0F )
#define PLDM_HDR_BYTE1_REQ_MSG ( 0x80 )
#define MCTP_MIN_NUM_BYTES     ( 10 )
#define PLDM_HDR_VER           ( 0x01 )
#define PLDM_TAG_BYTE          ( 0xC8 )

/*
 * MCTP Control Messages Completion code
 */
#define RESP_MCTP_CTRL_MSG_SUCCESS            ( 0x00 )
#define RESP_MCTP_CTRL_MSG_ERROR_GENERIC      ( 0x01 )                         /* Generic failure message */
#define RESP_MCTP_CTRL_MSG_ERROR_INVALID_DATA ( 0x02 )                         /* Payload contains invalid data */
#define RESP_MCTP_CTRL_MSG_ERROR_INVALID_LEN  ( 0x03 )                         /* Commad specific message lenght invalid */
#define RESP_MCTP_CTRL_MSG_ERROR_NOT_READY    ( 0x04 )                         /* BUSY */
#define RESP_MCTP_CTRL_MSG_ERROR_MCTP_CMD_NS  ( 0x05 )                         /* Not supported MCTP command */
#define RESP_MCTP_CTRL_MSG_TYPE_UNSUPPORTED   ( 0x80 )                         /* Not supported MCTP command */

/*
 * Command specific completion code
 */
#define RESP_INVALID_DATA_XFER_HANDLE    ( 0x80 )
#define RESP_INVALID_XFER_OPERATION_FLAG ( 0x81 )

#define RESP_INVALID_PLDM_TYPE_IN_REQUEST    ( 0x83 )
#define RESP_INVALID_PLDM_VERSION_IN_REQUEST ( 0x84 )

#define RESP_INVALID_RECORD_HANDLE         ( 0x82 )
#define RESP_INVALID_RECORD_CHANGE_NUMBER  ( 0x83 )
#define RESP_TRANSFER_TIMEOUT              ( 0x84 )
#define RESP_REPOSITORY_UPDATE_IN_PROGRESS ( 0x85 )

#define RESP_INVALID_SENSOR_ID                  ( 0x80 )
#define RESP_REARM_UNAVAILABLE_IN_PRESENT_STATE ( 0x81 )


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    MCTP_Msg_Type
 * @brief   MCTP Message Types
 */
typedef enum MCTP_Msg_Type
{
    MCTP_MSG_MCTP_CONTROL       = 0x00,
    MCTP_MSG_MCTP_PLDM          = 0x01,
    MCTP_MSG_NCSI_OVER_MCTP     = 0x02,
    MCTP_MSG_ETHERNET_OVER_MCTP = 0x03,
    MCTP_MSG_NVM_EXPRESS        = 0x04,
    MCTP_MSG_SPDM_OVER_MCTP     = 0x05,
    MCTP_MSG_VENDOR_PCI         = 0x7e,
    MCTP_MSG_VENDOR_IANA        = 0x7f

} MCTP_Msg_Type_e;


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  mctp_message
 * @brief   Structure to hold an MCTP message
 */
typedef struct __attribute__( ( __packed__ ) ) mctp_message
{
    uint8_t dest_slave_addr;
    /* uint8_t cmd_code; */
    uint8_t byte_count;
    uint8_t src_slave_addr;
    uint8_t hdr_version;
    uint8_t dest_ep_id;
    uint8_t src_ep_id;
    // bit fields for metadata
    uint8_t tag : 3;
    uint8_t to : 1;
    uint8_t seq_num : 2;
    uint8_t eom : 1;
    uint8_t som : 1;
    // end bit fields for metadata
    // start of MCTP payload (max payload length counts from here)
    union
    {
        uint8_t msg_type;                                                      // ignoring ic bit.  Assuming it is 0 in the request
        uint8_t mctp_msg_payload[ 0 ];

    }
    payl;

    // start of MCTP header/data
    uint8_t mctp_msg_header[ 0 ];                                              // PLDM/MCTP messages start here
    /*
     * PEC is at the variable offset
     */
} mctp_message;

/**
 * @struct  mctp_packet
 * @brief   Structure to hold an MCTP packet
 */
typedef struct __attribute__( ( __packed__ ) ) mctp_packet
{
    //unsigned char msg_type;
    unsigned char instanceID : 5;
    unsigned char rsvd : 1;
    unsigned char d : 1;
    unsigned char rq : 1;
    unsigned char mctp_cmd;
    unsigned char payLoad[ MCTP_MAX_PAYLOAD_SIZE ];
} mctp_packet;


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Process data received in an MCTP message
 *
 * @param   ReqBuff         Pointer to the request
 * @param   RespBuff        Pointer to the response
 * @param   request_pkt     Request or response
 *
 * @return                  The number of bytes in the response
 *
 */
int process_mctp_request( void *ReqBuff, void *RespBuff, int request_pkt );

/**
 * @brief   Function pointer definition of functions to handle MCTP message types
 *
 * @param   PayLoadIn   The payload of the request message
 * @param   PayloadOut  The payload of the response message
 *
 * @return              Size of the response message
 */
typedef uint8_t ( *mctpFunction )( const void *PayLoadIn, void *PayloadOut );

/**
 * @brief   Function to determine the MCTP function from the command
 *
 * @param   mctp_cmd    MCTP command byte
 * @param   func        Pointer to the function to process the message
 *
 * @return              RESP_MCTP_CTRL_MSG_SUCCESS or RESP_MCTP_CTRL_MSG_ERROR_MCTP_CMD_NS
 */
int get_mctp_func( uint8_t mctp_cmd, mctpFunction *func );

#endif /* INC_MCTP_H_ */
