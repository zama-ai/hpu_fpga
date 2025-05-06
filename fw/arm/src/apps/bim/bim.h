/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the public API of the Built in Monitoring (BIM) Application.
 *
 * @file bim.h
 *
 */
#ifndef _BIM_H_
#define _BIM_H_


/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"
#include "osal.h"

#include "amc_cfg.h"


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    BIM_STATUS
 * @brief   Status levels for the overall health of AMC.
 */
typedef enum BIM_STATUS
{
    BIM_STATUS_HEALTHY = 0,
    BIM_STATUS_DEGRADED,
    BIM_STATUS_CRITICAL,
    BIM_STATUS_FATAL,
    MAX_BIM_STATUS

} BIM_STATUS;


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  BIM_EVENTS
 * @brief   Structure to hold individual event info.
 */
typedef struct BIM_EVENTS
{
    uint32_t   ulEventId;
    uint32_t   ulCallCount;
    BIM_STATUS xContextStatus;

} BIM_EVENTS;

/**
 * @struct  BIM_MODULES
 * @brief   Structure to hold individual module health info.
 */
typedef struct BIM_MODULES
{
    AMC_CFG_UNIQUE_IDS xModuleId;
    BIM_STATUS         xCurrentStatus;
    BIM_STATUS         xContextStatus;
    BIM_EVENTS         *pxEvents;
    uint32_t           ulEventsLen;

} BIM_MODULES;


/******************************************************************************/
/* Public function declarations                                               */
/******************************************************************************/

/**
 * @brief   Main initialisation point for the Built in Monitoring (BIM) Application.
 *
 * @param   pxModuleData Pointer to module data array
 *
 * @return  OK     if the application is initialised and running successfully
 *          ERROR  if the application is not initialised
 */
int iBIM_Initialise( BIM_MODULES *pxModuleData );

/**
 * @brief   Returns the current health status of the AMC.
 *
 * @param   pxStatus Pointer to status level
 *
 * @return  OK     if successful
 *          ERROR  if not successful
 */
int iBIM_GetOverallHealthStatus( BIM_STATUS *pxStatus );

/**
 * @brief   Updates the overall health status of the AMC
 *
 * @param   xStatus BIM_STATUS - Health status level
 *
 * @return  OK     if successful
 *          ERROR  if not successful
 */
int iBIM_SetOverallHealthStatus( BIM_STATUS xStatus );

/**
 * @brief   Print all the stats gathered by the library
 *
 * @return  OK          Stats retrieved from library successfully
 *          ERROR       Stats not retrieved successfully
 *
 */
int iBIM_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the library
 *
 * @return  OK          Stats cleared successfully
 *          ERROR       Stats not cleared successfully
 *
 */
int iBIM_ClearStatistics( void );

#endif
