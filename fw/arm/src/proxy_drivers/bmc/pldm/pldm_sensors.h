/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains PLDM sensor enums
 *
 * @file pldm_sensors.h
 *
 */

#ifndef SRC_PLDM_SENSORS_H_
#define SRC_PLDM_SENSORS_H_


/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    sensor_state
 * @brief   Enumeration of sensor state values
 */
typedef enum
{
    Unknown,
    Normal,
    Warning,
    Critical,
    Fatal,
    LowerWarning,
    LowerCritical,
    LowerFatal,
    UpperWarning,
    UpperCritical,
    UpperFatal

} sensor_state;

/**
 * @enum    sensor_operational_state
 * @brief   Enumeration of sensor operational state values
 */
typedef enum
{
    eSensorOpStateEnabled,
    eSensorOpStateDisabled,
    eSensorOpStateUnavailable,
    eSensorOpStateStatusUnknown,
    eSensorOpStateFailed,
    eSensorOpStateInitializing,
    eSensorOpStateShuttingDown,
    eSensorOpStateInTest

}sensor_operational_state;

/**
 * @enum    sensor_event
 * @brief   Enumeration of sensor event values
 */
typedef enum
{
    eSensorNoEventGeneration,
    eSensorEventsDisabled,
    eSensorEventsEnabled,
    eSensorOpEventsOnlyEnabled,
    eSensorStateEventsOnlyEnabled

}sensor_event;


#endif /* SRC_PLDM_SENSORS_H_ */
