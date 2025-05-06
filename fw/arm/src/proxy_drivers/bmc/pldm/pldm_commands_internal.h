/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the PLDM support functions
 *
 * @file pldm_commands_internal.h
 *
 */

#ifndef PLDM_COMMANDS_INTERNAL_H_
#define PLDM_COMMANDS_INTERNAL_H_


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Get PLDM Type Support
 *
 * @param   typeSupported     Pointer to the request message
 *
 * @return  Max number of PLDM Types
 */
int getPldmTypeSupport( uint8_t *typeSupported );

/**
 * @brief   Check if PLDM Command is supported
 *
 * @param   type            The PLDM type
 * @param   ver             Pointer to the version
 * @param   cmdSupported    Pointer to update if command is supported
 *
 * @return  Response size
 */
int getPldmCmdSupport( const uint8_t type, const uint8_t *ver, uint8_t *cmdSupported );

/**
 * @brief   Check if PLDM Version is supported
 *
 * @param   type            The PLDM type
 * @param   ver             Pointer to the version
 * @param   start_version   Start check from this version
 * @param   num_version     Number of versions
 * @param   moreAvailable   Pointer to update if more versions are available
 *
 * @return  1 Version supported, 0 if not supported
 */
int getPldmVersionSupport( const uint8_t type,
                           uint8_t *ver,
                           const uint32_t start_version,
                           const uint32_t num_version,
                           int *moreAvailable );

/**
 * @brief   Get PLDM Type Support
 *
 * @param   type     The PLDM type
 *
 * @return  1 Type supported, 0 if not supported
 */
int IsPldmTypeSupported( const uint8_t type );

/**
 * @brief   Check if PLDM Version is supported
 *
 * @param   type    The PLDM type
 * @param   ver     Pointer to the version
 *
 *
 * @return  1 Version supported, 0 if not supported
 */
int IsPldmVersionSupported( const uint8_t type, const uint8_t *ver );

#endif /* PLDM_COMMANDS_INTERNAL_H_*/
