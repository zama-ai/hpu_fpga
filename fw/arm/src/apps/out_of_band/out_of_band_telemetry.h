/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the out of band telemetry defintions
 *
 * @file out_of_band_telemetry.h
 *
 */

#ifndef _OUT_OF_BAND_TELEMETRY_H_
#define _OUT_OF_BAND_TELEMETRY_H_


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Initialise the out of band telemetry application layer
 *          used to handle events and communication with RMI
 *
 * @return  OK          Success
 *          ERROR       Failure
 */
int iOUT_OF_BAND_TELEMETRY_Initialise( void );

/**
 * @brief   Print all the stats gathered by the application
 *
 * @return  OK          Stats retrieved from proxy driver successfully
 *          ERROR       Stats not retrieved successfully
 *
 */
int iOUT_OF_BAND_TELEMETRY_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the application
 *
 * @return  OK          Stats cleared successfully
 *          ERROR       Stats not cleared successfully
 *
 */
int iOUT_OF_BAND_TELEMETRY_ClearStatistics( void );

#endif /* _OUT_OF_BAND_TELEMETRY_H_ */
