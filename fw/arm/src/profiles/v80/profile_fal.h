/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the fal profile for the V80
 *
 * @file profile_fal.h
 *
 */

#ifndef _PROFILE_FAL_H_
#define _PROFILE_FAL_H_

#include "util.h"
#include "pll.h"
#include "fw_if.h"
#include "profile_hal.h"
#include "amc_cfg.h"

/* QSFP */
#define FAL_QSFP_PROCESS_TIME_MS              ( 2 )
#define FAL_QSFP_PROCESS_TIME_TICKS           ( 10 )
#define FAL_QSFP_MAX_DATA                     ( 256 )
#define FAL_QSFP_READ_DEFAULT_SIZE            ( 1 )
#define FAL_QSFP_WRITE_DEFAULT_SIZE           ( 2 )
#define FAL_QSFP_MODPRES_L_BIT_MASK           ( 1 << 3 )
#define FAL_QSFP_MODSEL_L_BIT_MASK            ( 1 << 0 )
#define FAL_QSFP_MODSELL_L_SET_LOW            ( 0xFE )
#define FAL_QSFP_MODSELL_L_SET_HIGH           ( 0x01 )
#define FAL_QSFP_POWER_IO_EXPANDER_NUM_INPUTS ( 4 )
#define FAL_QSFP_ALL_OUTPUTS_HIGH             ( 0xFF )
/* defines for IO expander registers */
#define FAL_QSFP_IO_EXPANDER_INPUT_PORT_REG         ( 0 )
#define FAL_QSFP_IO_EXPANDER_OUTPUT_PORT_REG        ( 1 )
#define FAL_QSFP_IO_EXPANDER_POLARITY_INVERSION_REG ( 2 )
#define FAL_QSFP_IO_EXPANDER_CONFIGURATION_REG      ( 3 )
#define FAL_QSFP_MUX_IO_EXPANDER_DESELECTED         ( 0 )

/* OSPI */
#define FAL_OSPI_STATE_ENTRY( _s ) [ FW_IF_OSPI_STATE_ ## _s ] = #_s

/* SMBus */
#define FAL_SMBUS_INTERRUPT ( HAL_SMBUS_INTERRUPT )

typedef enum FW_IF_SMBUS_COMMAND_CODES
{
    FW_IF_SMBUS_COMMAND_CODE_QUICK_COMMAND_LO                    = 0x80,
    FW_IF_SMBUS_COMMAND_CODE_QUICK_COMMAND_HI                    = 0x81,
    FW_IF_SMBUS_COMMAND_CODE_SEND_BYTE                           = 0x82,
    FW_IF_SMBUS_COMMAND_CODE_RECEIVE_BYTE                        = 0x83,
    FW_IF_SMBUS_COMMAND_CODE_WRITE_BYTE                          = 0x84,
    FW_IF_SMBUS_COMMAND_CODE_WRITE_WORD                          = 0x85,
    FW_IF_SMBUS_COMMAND_CODE_READ_BYTE                           = 0x86,
    FW_IF_SMBUS_COMMAND_CODE_READ_WORD                           = 0x87,
    FW_IF_SMBUS_COMMAND_CODE_PROCESS_CALL                        = 0x88,
    FW_IF_SMBUS_COMMAND_CODE_BLOCK_WRITE                         = 0x0F,
    FW_IF_SMBUS_COMMAND_CODE_BLOCK_READ                          = 0x8A,
    FW_IF_SMBUS_COMMAND_CODE_BLOCK_WRITE_BLOCK_READ_PROCESS_CALL = 0x8B,
    FW_IF_SMBUS_COMMAND_CODE_HOST_NOTIFY                         = 0x8C,
    FW_IF_SMBUS_COMMAND_CODE_WRITE_32                            = 0x8D,
    FW_IF_SMBUS_COMMAND_CODE_READ_32                             = 0x8E,
    FW_IF_SMBUS_COMMAND_CODE_WRITE_64                            = 0x8F,
    FW_IF_SMBUS_COMMAND_CODE_READ_64                             = 0x90,
    FW_IF_SMBUS_COMMAND_CODE_PREPARE_TO_ARP                      = 0x91,
    FW_IF_SMBUS_COMMAND_CODE_RESET_DEVICE                        = 0x92,
    FW_IF_SMBUS_COMMAND_CODE_GET_UDID                            = 0x93,
    FW_IF_SMBUS_COMMAND_CODE_ASSIGN_ADDRESS                      = 0x94,
    FW_IF_SMBUS_COMMAND_CODE_GET_UDID_DIRECTED                   = 0x95,
    FW_IF_SMBUS_COMMAND_CODE_RESET_DEVICE_DIRECTED               = 0x96,
    FW_IF_SMBUS_COMMAND_CODE_NONE                                = 0x97,
    MAX_FW_IF_SMBUS_COMMAND_CODE

} FW_IF_SMBUS_COMMAND_CODES;

/* FAL objects */
extern FW_IF_CFG xGcqIf;
extern FW_IF_CFG *pxOspiIf;
extern FW_IF_CFG *pxEmmcIf;
extern FW_IF_CFG xQsfpIf1;
extern FW_IF_CFG xQsfpIf2;
extern FW_IF_CFG xQsfpIf3;
extern FW_IF_CFG xQsfpIf4;
extern FW_IF_CFG xDimmIf;
extern FW_IF_CFG *pxSMBusIf;

/**
 * @brief   Initialise FAL layer
 *
 * @param   pullAmcInitStatus   Pointer to the uint64_t bitmask of the
 *                              initialisation status of each component
 *
 * @return  OK if all FAL objects initialised and created successfully
 *          ERROR if any or all FAL objects not initialised or created
 *
 */
int iFAL_Initialise( uint64_t *pullAmcInitStatus );

/**
 * @brief   Initialise FAL Debug monitoring
 *
 * @return  none.
 *
 */
void vFAL_DebugInitialise( void );

#endif
