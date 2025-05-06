/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the in band telemetry defintions
 *
 * @file in_band_telemetry.h
 *
 */

#ifndef _IN_BAND_TELEMETRY_H_
#define _IN_BAND_TELEMETRY_H_


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Initialise the in band telemetry application layer
 *          used to handle events and communication between the host
 *          and the sensors
 * 
 * @param   ullSharedMemBaseAddr  The base address of the shared memory
 *
 * @return  OK          Success
 *          ERROR       Failure
 */
int iIN_BAND_TELEMETRY_Initialise( uint64_t ullSharedMemBaseAddr );

/**
 * @brief   Print all the stats gathered by the application
 *
 * @return  OK          Stats retrieved from proxy driver successfully
 *          ERROR       Stats not retrieved successfully
 *
 */
int iIN_BAND_TELEMETRY_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the application
 *
 * @return  OK          Stats cleared successfully
 *          ERROR       Stats not cleared successfully
 *
 */
int iIN_BAND_TELEMETRY_ClearStatistics( void );

/**
 * @brief   Activating/Deactivating Test Mode
 * 
 * @param   iActivate   Setting test mode activated or deactivated
 *                      TRUE for activating
 *                      FALSE for deactivating
 *
 * @return  OK          Test mode is activated/deactivated successfully
 *          ERROR       Test mode is not activated/deactivated successfully
 *
 */
int iIN_BAND_TELEMETRY_TestMode( int iActivate );

#endif /* _IN_BAND_TELEMETRY_H_ */
