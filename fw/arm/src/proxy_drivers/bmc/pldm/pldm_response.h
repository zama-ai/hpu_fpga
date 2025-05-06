/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains PLDM response codes
 *
 * @file pldm_response.h
 *
 */

#ifndef PLDM_RESPONSE_H_
#define PLDM_RESPONSE_H_


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

/*
 * PLDM Base Completion code
 */
#define RESP_PLDM_SUCCESS             ( 0x00 )
#define RESP_PLDM_ERROR_GENERIC       ( 0x01 )                                 /* Generic failur message */
#define RESP_PLDM_ERROR_INVALID_DATA  ( 0x02 )                                 /* Payload contains invalid data */
#define RESP_PLDM_ERROR_INVALID_LEN   ( 0x03 )                                 /* Commad specific message lenght invalid */
#define RESP_PLDM_ERROR_NOT_READY     ( 0x04 )                                 /* BUSY */
#define RESP_PLDM_ERROR_PLDM_CMD_NS   ( 0x05 )                                 /* Not supported PLDM command */
#define RESP_PLDM_ERROR_PLDM_TYPE_INV ( 0x20 )                                 /* Invalid or not supported PLDM type*/

/*
 * Command specific completion code
 */
#define RESP_INVALID_DATA_XFER_HANDLE               ( 0x80 )
#define RESP_INVALID_XFER_OPERATION_FLAG            ( 0x81 )
#define RESP_INVALID_PLDM_TYPE_IN_REQUEST           ( 0x83 )
#define RESP_INVALID_PLDM_VERSION_IN_REQUEST        ( 0x84 )
#define RESP_INVALID_RECORD_HANDLE                  ( 0x82 )
#define RESP_INVALID_RECORD_CHANGE_NUMBER           ( 0x83 )
#define RESP_TRANSFER_TIMEOUT                       ( 0x84 )
#define RESP_REPOSITORY_UPDATE_IN_PROGRESS          ( 0x85 )
#define RESP_INVALID_SENSOR_ID                      ( 0x80 )
#define RESP_REARM_UNAVAILABLE_IN_PRESENT_STATE     ( 0x81 )
#define RESP_INVALID_SENSOR_OPERATIONAL_STATE       ( 0x81 )
#define RESP_EVENT_GENERATION_NOT_SUPPORTED         ( 0x82 )
#define RESP_PLDM_ERROR_INVALID_PROTOCOL_TYPE       ( 0x80 )
#define RESP_PLDM_ERROR_ENABLE_METHOD_NOT_SUPPORTED ( 0x81 )
#define RESP_INVALID_EFFECTER_ID                    ( 0x80 )

#endif /* PLDM_RESPONSE_H_ */
