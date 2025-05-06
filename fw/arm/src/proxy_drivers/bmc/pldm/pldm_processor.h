/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains PLDM enums, structures and functions
 *
 * @file pldm_processor.h
 *
 */

#ifndef PLDM_PROCESSOR_H_
#define PLDM_PROCESSOR_H_


/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "mctp.h"
#include "util.h"
#include "pldm_sensors.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define ASYNC_EVENT_FORMAT_VERSION    0x01
#define PLDM_TYPE_2                   0x02
#define PLDM_ASYNC_EVENT_COMMAND_CODE 0x0A


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    PLDMTransport
 * @brief   Enumeration of sensor event values
 */
typedef enum
{
    ePLDMTransportMCTP   = 0x00,
    ePLDMTransportNCSI   = 0x01,
    ePLDMTransportVendor = 0xff

} PLDMTransport;

/**
 * @enum    Type0CmdID
 * @brief   Type 0 Request processing
 */
enum Type0CmdID
{
    PLDM_CMD_SETTID     = ( 0x1 ),
    PLDM_CMD_GETTID     = ( 0x2 ),
    PLDM_CMD_GETVERSION = ( 0x3 ),
    PLDM_CMD_GETTYPE    = ( 0x4 ),
    PLDM_CMD_GETCOMMAND = ( 0x5 ),
    MAX_PLDM_0_COMMAND

};

/**
 * @enum    Type2CmdID
 * @brief   Type 2 Request processing
 */
enum Type2CmdID
{
/*
 * Command 1 and 2 are same as type0
 *
 * PLDM_CMD_SETTID  =   (0x1),
 * PLDM_CMD_GETTID  =   (0x2),
 *
 */
    PLDM_CMD_SET_EVENT_RECEIVER          = ( 0x04 ),
    PLDM_CMD_GET_EVENT_RECEIVER          = ( 0x05 ),
    PLDM_CMD_ACK_ASYNC_EVENT             = ( 0x0A ),
    PLDM_CMD_EVENT_MESSAGE_SUPPORTED     = ( 0x0C ),
    PLDM_CMD_SET_NUMERIC_SENSOR_ENABLE   = ( 0x10 ),
    PLDM_CMD_GET_SENSOR_READING          = ( 0x11 ),
    PLDM_CMD_GET_SENSOR_THRESHOLDS       = ( 0x12 ),
    PLDM_CMD_SET_NUMERIC_EFFECTER_ENABLE = ( 0x30 ),
    PLDM_CMD_SET_NUMERIC_EFFECTER_VALUE  = ( 0x31 ),
    PLDM_CMD_GET_NUMERIC_EFFECTER_VALUE  = ( 0x32 ),
    PLDM_CMD_GET_PDR_REPO_INFO           = ( 0x50 ),
    PLDM_CMD_GET_PDR                     = ( 0x51 ),
    PLDM_CMD_GET_PDR_REPO_SIGNATURE      = ( 0x53 ),
    MAX_PLDM_2_COMMAND

};

/**
 * @enum    Type5CmdID
 * @brief   Type 5 Request processing
 */
enum Type5CmdID
{
    PLDM_CMD_QUERY_DEVICE_IDENTIFIERS = ( 0x01 ),
    PLDM_CMD_GET_FIRMWARE_PARAMETERS  = ( 0x02 ),
    PLDM_CMD_REQUEST_UPDATE           = ( 0x10 ),
    PLDM_CMD_PASS_COMPONENT_TABLE     = ( 0x13 ),
    PLDM_CMD_UPDATE_COMPONENT         = ( 0x14 ),
    PLDM_CMD_REQUEST_FIRMWARE_DATA    = ( 0x15 ),
    PLDM_CMD_TRANSFER_COMPLETE        = ( 0x16 ),
    PLDM_CMD_VERIFY_COMPLETE          = ( 0x17 ),
    PLDM_CMD_APPLY_COMPLETE           = ( 0x18 ),
    PLDM_CMD_ACTIVATE_FIRMWARE        = ( 0x1A ),
    PLDM_CMD_GET_STATUS               = ( 0x1B ),
    PLDM_CMD_CANCEL_UPDATE_COMPONENT  = ( 0x1C ),
    PLDM_CMD_CANCEL_UPDATE            = ( 0x1D ),
    MAX_PLDM_5_COMMAND

};


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   PLDM Set TID function
 *
 * @param   PayLoadIn   Pointer to the incoming payload
 * @param   PayLoadOut  Pointer to the outgoing payload
 *
 * @return  Size of outgoing payload
 *
 */
int pldm_cmd_SetTID( const void *PayLoadIn, void *PayLoadOut );

/**
 * @brief   PLDM Set TID function
 *
 * @param   PayLoadIn   Pointer to the incoming payload
 * @param   PayLoadOut  Pointer to the outgoing payload
 *
 * @return  Size of outgoing payload
 *
 */
int pldm_cmd_GetTID( const void *PayLoadIn, void *PayLoadOut );

/**
 * @brief   Get PLDM Version function
 *
 * @param   PayLoadIn   Pointer to the incoming payload
 * @param   PayLoadOut  Pointer to the outgoing payload
 *
 * @return  Size of outgoing payload
 *
 */
int pldm_cmd_GetPLDMVersion( const void *PayLoadIn, void *PayLoadOut );

/**
 * @brief   Get PLDM Type function
 *
 * @param   PayLoadIn   Pointer to the incoming payload
 * @param   PayLoadOut  Pointer to the outgoing payload
 *
 * @return  Size of outgoing payload
 *
 */
int pldm_cmd_GetPLDMType( const void *PayLoadIn, void *PayLoadOut );

/**
 * @brief   Get PLDM Command function
 *
 * @param   PayLoadIn   Pointer to the incoming payload
 * @param   PayLoadOut  Pointer to the outgoing payload
 *
 * @return  Size of outgoing payload
 *
 */
int pldm_cmd_GetPLDMCommand( const void *PayLoadIn, void *PayLoadOut );

/**
 * @brief   PLDM Set Sensor Enable function
 *
 * @param   PayLoadIn   Pointer to the incoming payload
 * @param   PayLoadOut  Pointer to the outgoing payload
 *
 * @return  Size of outgoing payload
 *
 */
int pldm_cmd_SetNumericSensorEnable( const void *PayLoadIn, void *PayLoadOut );

/**
 * @brief   PLDM Get Sensor Reading function
 *
 * @param   PayLoadIn   Pointer to the incoming payload
 * @param   PayLoadOut  Pointer to the outgoing payload
 *
 * @return  Size of outgoing payload
 *
 */
int pldm_cmd_GetSensorReading( const void *PayLoadIn, void *PayLoadOut );

/**
 * @brief   PLDM Get PDR Repo Info function
 *
 * @param   PayLoadIn   Pointer to the incoming payload
 * @param   PayLoadOut  Pointer to the outgoing payload
 *
 * @return  Size of outgoing payload
 *
 */
int pldm_cmd_GetPDRRepositoryInfo( const void *PayLoadIn, void *PayLoadOut );

/**
 * @brief   PLDM Get PDR function
 *
 * @param   PayLoadIn   Pointer to the incoming payload
 * @param   PayLoadOut  Pointer to the outgoing payload
 *
 * @return  Size of outgoing payload
 *
 */
int pldm_cmd_GetPDR( const void *PayLoadIn, void *PayLoadOut );

#endif /* PLDM_PROCESSOR_H_ */
