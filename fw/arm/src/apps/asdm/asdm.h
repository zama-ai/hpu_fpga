/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the header for the ASDM (Alveo Data Store Model) API's
 *
 * @file asdm.h
 *
 */

#ifndef _ASDM_H_
#define _ASDM_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "util.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

/* ASDM API Completion */
#define ASDM_SDR_RESP_BYTE_CC                   ( 0x0 )
#define ASDM_SDR_RESP_BYTE_REPO_TYPE            ( 0x1 )
#define ASDM_SDR_RESP_BYTE_SIZE                 ( 0x2 )


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    ASDM_API_ID_TYPE
 * @brief   is a unique number that represents API ID type
 */
typedef enum ASDM_API_ID_TYPE
{
    ASDM_API_ID_TYPE_GET_SDR_SIZE           = 1,
    ASDM_API_ID_TYPE_GET_SDR                = 2,
    ASDM_API_ID_TYPE_GET_SINGLE_SENSOR_DATA = 3,
    ASDM_API_ID_TYPE_GET_ALL_SENSOR_DATA    = 4,
    ASDM_API_ID_TYPE_GET_SDR_V2             = 5,
    ASDM_API_ID_TYPE_GET_ALL_SENSOR_DATA_V2 = 6,
    ASDM_API_ID_TYPE_CONFIG_WRITES          = 7, /* Not sensor related, should be rejected by ASDM */
    ASDM_API_ID_TYPE_SEND_EVENTS            = 8, /* Not sensor related, should be rejected by ASDM */

    ASDM_API_ID_TYPE_MAX

} ASDM_API_ID_TYPE;

/**
 * @enum    ASDM_REPOSITORY_TYPE
 * @brief   is a unique number that represents each repo type
 */
typedef enum ASDM_REPOSITORY_TYPE
{
    ASDM_REPOSITORY_TYPE_BOARD_INFO  = 0xC0,
    ASDM_REPOSITORY_TYPE_TEMP        = 0xC1,
    ASDM_REPOSITORY_TYPE_VOLTAGE     = 0xC2,
    ASDM_REPOSITORY_TYPE_CURRENT     = 0xC3,
    ASDM_REPOSITORY_TYPE_POWER       = 0xC4,
    ASDM_REPOSITORY_TYPE_TOTAL_POWER = 0xC6,
    ASDM_REPOSITORY_TYPE_FPT         = 0xF0,

    ASDM_REPOSITORY_TYPE_MAX

} ASDM_REPOSITORY_TYPE;

/**
 * @enum    ASDM_SDR_COMPLETION_CODE
 * @brief   the request completion code
 */
typedef enum ASDM_SDR_COMPLETION_CODE
{
    ASDM_SDR_COMPLETION_CODE_NOT_AVAILABLE = 0x00,
    ASDM_SDR_COMPLETION_CODE_OPERATION_SUCCESS,
    ASDM_SDR_COMPLETION_CODE_OPERATION_FAILED,

    ASDM_SDR_COMPLETION_CODE_MAX

} ASDM_SDR_COMPLETION_CODE;


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Initialise the ASDM application layer
 *
 * @param   ucNumSensors          Number of sensors in the profile
 * 
 * @return  OK          Successfully initilaised the layer
 *          ERROR       Failed to initialise
 */
int iASDM_Initialise( uint8_t ucNumSensors );

/**
 * @brief   Returns the buffer populated with associated response
 *
 * @param   xApiType          The associated API type
 * @param   xAsdmRepo         The repo type
 * @param   ucSensorId        The sensor ID, if applicable 
 * @param   pucRespBuff       The buffer to be populated with the response
 * @param   pusRespSizeBytes  Max buffer size passed in, number of bytes populated returned
 *
 * @return  OK          Successfully populated the response
 *          ERROR       Failed to populate the response
 */
int iASDM_PopulateResponse( ASDM_API_ID_TYPE xApiType,
                            ASDM_REPOSITORY_TYPE xAsdmRepo,
                            uint8_t ucSensorId,
                            uint8_t *pucRespBuff,
                            uint16_t *pusRespSizeBytes );

/**
 * @brief   Print all the stats gathered by the application
 *
 * @return  OK          Stats retrieved from proxy driver successfully
 *          ERROR       Stats not retrieved successfully
 *
 */
int iASDM_PrintStatistics( void );
 
/**
 * @brief   Clear all the stats in the application
 *
 * @return  OK          Stats cleared successfully
 *          ERROR       Stats not cleared successfully
 *
 */
int iASDM_ClearStatistics( void );

/**
 * @brief   Print out the internal ASDM repo data
 *
 * @param   iRepoIndex         The repo index
 *
 * @return  OK          Stats retrieved from proxy driver successfully
 *          ERROR       Stats not retrieved successfully
 *
 */
int iASDM_PrintAsdmRepoData( int iRepoIndex );


#endif /*_ASDM_H_ */
