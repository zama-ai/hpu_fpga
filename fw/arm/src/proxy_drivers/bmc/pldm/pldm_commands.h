/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains PLDM functions for processing specific message types
 *
 * @file pldm_commands.h
 *
 */

#ifndef PLDM_COMMANDS_H_
#define PLDM_COMMANDS_H_


/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "pldm.h"
#include "standard.h"


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   The PLDM function pointer definition
 *
 * @param   PayLoadIn   The received payload data to process
 * @param   PayloadOut  The response payload
 *
 * @return  Response size
 */
typedef int ( *PldmFunction )( const void *PayLoadIn, void *PayloadOut );

/**
 * @brief   Get the PLDM function for the type
 *
 * @param   pldm_type   The PLDM type
 * @param   pldm_cmd    The PLDM command
 * @param   func        Pointer to the PLDM function to call
 *
 * @return  RESP_PLDM_SUCCESS if successful, other error if type or command not supported
 */
int get_pldm_func( uint8_t pldm_type, uint8_t pldm_cmd, PldmFunction *func );

#endif /* PLDM_COMMANDS_H_ */
