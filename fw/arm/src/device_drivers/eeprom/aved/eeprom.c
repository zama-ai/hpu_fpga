/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This implenents the functions for accessing the
 * manufacturing eeprom.
 *
 * @file eeprom.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <stdio.h>
#include <stdlib.h>

#include "util.h"
#include "pll.h"
#include "osal.h"

#include "eeprom.h"
#include "i2c.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/
#define EEPROM_ASCII_VAR( x ) ( ( x ) + 1 )
#define EEPROM_NAME                       "EEPROM"
#define EEPROM_2_BYTE_ADDRESS             ( 2 )
#define EEPROM_ADDRESS_SIZE_UNINITIALISED ( 0 )
#define EEPROM_WRITE_DELAY_MS             ( 10 )
#define EEPROM_ADDRESS_BYTE_ZERO          ( 0 )
#define EEPROM_ADDRESS_BYTE_ONE           ( 1 )
#define EEPROM_DATA_SINGLE_BYTE           ( 1 )
#define EEPROM_ONE_BYTE                   ( 1 )
#define EEPROM_TWO_BYTES                  ( 2 )
#define UPPER_FIREWALL                    ( 0xBABECAFE )
#define LOWER_FIREWALL                    ( 0xDEADFACE )
/* Current EEPROM versions supported */
#define EEPROM_V4_0 ( 0x342E3000u )
#define EEPROM_V3_1 ( 0x332E3100u )
#define EEPROM_V3_0 ( 0x332E3000u )

#define EEPROM_MAX_MAC                   ( 40 )
#define EEPROM_PAGE_SIZE_MAX             ( 255 )
#define EEPROM_ADDRESS_SIZE_MAX          ( 255 )
#define EEPROM_WRITE_MULTI_BYTE_SIZE_MAX ( 255 )
#define EEPROM_WRITE_BYTE_SIZE_MAX       ( 255 )

/* Default register content in EEPROM if a particular register has not been programmed */
#define EEPROM_DEFAULT_VAL ( 0xFF )

#define EEPROM_VERSION_OFFSET            ( 0x00 )
#define EEPROM_VERSION_SIZE              ( 4 )
#define EEPROM_BUF_SIZE                  ( 128 )
#define EEPROM_FIELD_NA_SIZE             ( 0 )                                 /* For non-existent fields */
#define EEPROM_DEVICE_ID_CHECK_TRY_COUNT ( 3 )

/* Verbose data log - disabled by default */
/* #define EEPROM_VERBOSE_DEBUG_ENABLE */

/* Version 4.0 field positions */
#define EEPROM_V4_0_DATA_CHECKSUM_LSB_OFFSET  ( 0x04 )
#define EEPROM_V4_0_DATA_CHECKSUM_MSB_OFFSET  ( 0x05 )
#define EEPROM_V4_0_ALVEO_PRODUCT_NAME_OFFSET ( 0x06 )                         /* Alveo Product Name  */
#define EEPROM_V4_0_ALVEO_PRODUCT_NAME_SIZE   ( 36 )
#define EEPROM_V4_0_ALVEO_PART_NUM_OFFSET     ( 0x2A )                         /* Alveo Part Number  */
#define EEPROM_V4_0_ALVEO_PART_NUM_SIZE       ( 24 )
#define EEPROM_V4_0_MFG_ALVEO_PART_NUM_OFFSET ( 0x42 )                         /* Manufacturing Alveo Part Number */
#define EEPROM_V4_0_MFG_ALVEO_PART_NUM_SIZE   ( 16 )
#define EEPROM_V4_0_MFG_ALVEO_PART_REV_OFFSET ( 0x52 )                         /* Manufacturing Alveo Part Revision */
#define EEPROM_V4_0_MFG_ALVEO_PART_REV_SIZE   ( 5 )
#define EEPROM_V4_0_PRODUCT_SERIAL_OFFSET     ( 0x57 )                         /* Product Serial Number */
#define EEPROM_V4_0_PRODUCT_SERIAL_SIZE       ( 14 )
#define EEPROM_V4_0_MFG_DATE_OFFSET           ( 0x65 )                         /* Manufacturing Date  */
#define EEPROM_V4_0_MFG_DATE_SIZE             ( 4 )
#define EEPROM_V4_0_TOT_MAC_ID_OFFSET         ( 0x69 )                         /* Number of MAC IDs */
#define EEPROM_V4_0_TOT_MAC_ID_SIZE           ( 1 )
#define EEPROM_V4_0_MAC_OFFSET                ( 0x6A )                         /* MAC ID 1 */
#define EEPROM_V4_0_MAC_SIZE                  ( 6 )
#define EEPROM_V4_0_UUID_OFFSET               ( 0x70 )                         /* UUID */
#define EEPROM_V4_0_UUID_SIZE                 ( 16 )
#define EEPROM_V4_0_CHECKSUM_START            ( 6 )
#define EEPROM_V4_0_CHECKSUM_END              ( 127 )

/* Version 3.1 field positions */
#define EEPROM_V3_1_PRODUCT_NAME_OFFSET      ( 0x08 )
#define EEPROM_V3_1_PRODUCT_NAME_SIZE        ( 24 )
#define EEPROM_V3_1_BOARD_REV_OFFSET         ( 0x20 )
#define EEPROM_V3_1_BOARD_REV_SIZE           ( 8 )
#define EEPROM_V3_1_BOARD_SERIAL_OFFSET      ( 0x28 )
#define EEPROM_V3_1_BOARD_SERIAL_SIZE        ( 14 )
#define EEPROM_V3_1_BOARD_TOT_MAC_ID_OFFSET  ( 0x36 )
#define EEPROM_V3_1_BOARD_TOT_MAC_ID_SIZE    ( 1 )
#define EEPROM_V3_1_BOARD_MAC_OFFSET         ( 0x37 )
#define EEPROM_V3_1_BOARD_MAC_SIZE           ( 6 )
#define EEPROM_V3_1_BOARD_ACT_PAS_OFFSET     ( 0x3D )
#define EEPROM_V3_1_BOARD_ACT_PAS_SIZE       ( 1 )
#define EEPROM_V3_1_BOARD_CONFIG_MODE_OFFSET ( 0x3E )
#define EEPROM_V3_1_BOARD_CONFIG_MODE_SIZE   ( 1 )
#define EEPROM_V3_1_MFG_DATE_OFFSET          ( 0x3F )
#define EEPROM_V3_1_MFG_DATE_SIZE            ( 3 )
#define EEPROM_V3_1_PART_NUM_OFFSET          ( 0x42 )
#define EEPROM_V3_1_PART_NUM_SIZE            ( 24 )
#define EEPROM_V3_1_UUID_OFFSET              ( 0x5A )
#define EEPROM_V3_1_UUID_SIZE                ( 16 )
#define EEPROM_V3_1_PCIE_INFO_OFFSET         ( 0x6A )
#define EEPROM_V3_1_PCIE_INFO_SIZE           ( 8 )
#define EEPROM_V3_1_MAX_POWER_MODE_OFFSET    ( 0x72 )
#define EEPROM_V3_1_MAX_POWER_MODE_SIZE      ( 1 )
#define EEPROM_V3_1_MEM_SIZE_OFFSET          ( 0x73 )
#define EEPROM_V3_1_MEM_SIZE_SIZE            ( 4 )
#define EEPROM_V3_1_OEMID_OFFSET             ( 0x77 )
#define EEPROM_V3_1_OEMID_SIZE               ( 4 )
#define EEPROM_V3_1_CAPABILITY_OFFSET        ( 0x7B )
#define EEPROM_V3_1_CAPABILITY_SIZE          ( 2 )
#define EEPROM_V3_1_CHECKSUM_LSB_OFFSET      ( 0x06 )
#define EEPROM_V3_1_CHECKSUM_MSB_OFFSET      ( 0x07 )
#define EEPROM_V3_1_CHECKSUM_START           ( 8 )
#define EEPROM_V3_1_CHECKSUM_END             ( 124 )

/* Version 3.0 field positions */
#define EEPROM_V3_0_PRODUCT_NAME_OFFSET      ( 0x08 )
#define EEPROM_V3_0_PRODUCT_NAME_SIZE        ( 24 )
#define EEPROM_V3_0_BOARD_REV_OFFSET         ( 0x20 )
#define EEPROM_V3_0_BOARD_REV_SIZE           ( 8 )
#define EEPROM_V3_0_BOARD_SERIAL_OFFSET      ( 0x28 )
#define EEPROM_V3_0_BOARD_SERIAL_SIZE        ( 14 )
#define EEPROM_V3_0_BOARD_TOT_MAC_ID_OFFSET  ( 0x36 )
#define EEPROM_V3_0_BOARD_TOT_MAC_ID_SIZE    ( 1 )
#define EEPROM_V3_0_BOARD_MAC_OFFSET         ( 0x37 )
#define EEPROM_V3_0_BOARD_MAC_SIZE           ( 6 )
#define EEPROM_V3_0_BOARD_ACT_PAS_OFFSET     ( 0x3D )
#define EEPROM_V3_0_BOARD_ACT_PAS_SIZE       ( 1 )
#define EEPROM_V3_0_BOARD_CONFIG_MODE_OFFSET ( 0x3E )
#define EEPROM_V3_0_BOARD_CONFIG_MODE_SIZE   ( 1 )
#define EEPROM_V3_0_MFG_DATE_OFFSET          ( 0x3F )
#define EEPROM_V3_0_MFG_DATE_SIZE            ( 3 )
#define EEPROM_V3_0_PART_NUM_OFFSET          ( 0x42 )
#define EEPROM_V3_0_PART_NUM_SIZE            ( 24 )
#define EEPROM_V3_0_UUID_OFFSET              ( 0x5A )
#define EEPROM_V3_0_UUID_SIZE                ( 16 )
#define EEPROM_V3_0_PCIE_INFO_OFFSET         ( 0x6A )
#define EEPROM_V3_0_PCIE_INFO_SIZE           ( 8 )
#define EEPROM_V3_0_MAX_POWER_MODE_OFFSET    ( 0x72 )
#define EEPROM_V3_0_MAX_POWER_MODE_SIZE      ( 1 )
#define EEPROM_V3_0_MEM_SIZE_OFFSET          ( 0x73 )
#define EEPROM_V3_0_MEM_SIZE_SIZE            ( 4 )
#define EEPROM_V3_0_OEMID_OFFSET             ( 0x77 )
#define EEPROM_V3_0_OEMID_SIZE               ( 4 )
#define EEPROM_V3_0_CAPABILITY_OFFSET        ( 0x7B )
#define EEPROM_V3_0_CAPABILITY_SIZE          ( 2 )
#define EEPROM_V3_0_CHECKSUM_LSB_OFFSET      ( 0x06 )
#define EEPROM_V3_0_CHECKSUM_MSB_OFFSET      ( 0x07 )
#define EEPROM_V3_0_CHECKSUM_START           ( 8 )
#define EEPROM_V3_0_CHECKSUM_END             ( 124 )

STATIC_ASSERT( EEPROM_VERSION_SIZE < EEPROM_MAX_FIELD_SIZE );

STATIC_ASSERT( EEPROM_V4_0_ALVEO_PRODUCT_NAME_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V4_0_ALVEO_PART_NUM_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V4_0_MFG_ALVEO_PART_NUM_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V4_0_MFG_ALVEO_PART_REV_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V4_0_PRODUCT_SERIAL_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V4_0_MFG_DATE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V4_0_TOT_MAC_ID_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V4_0_MAC_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V4_0_UUID_SIZE < EEPROM_MAX_FIELD_SIZE );

STATIC_ASSERT( EEPROM_V3_0_PRODUCT_NAME_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_REV_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_SERIAL_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_TOT_MAC_ID_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_MAC_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_ACT_PAS_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_CONFIG_MODE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_MFG_DATE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_PART_NUM_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_UUID_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_PCIE_INFO_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_MAX_POWER_MODE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_MEM_SIZE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_OEMID_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_CAPABILITY_SIZE < EEPROM_MAX_FIELD_SIZE );

STATIC_ASSERT( EEPROM_V3_0_PRODUCT_NAME_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_REV_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_SERIAL_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_TOT_MAC_ID_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_MAC_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_ACT_PAS_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_BOARD_CONFIG_MODE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_MFG_DATE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_PART_NUM_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_UUID_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_PCIE_INFO_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_MAX_POWER_MODE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_MEM_SIZE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_OEMID_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_0_CAPABILITY_SIZE < EEPROM_MAX_FIELD_SIZE );

STATIC_ASSERT( EEPROM_V3_1_PRODUCT_NAME_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_BOARD_REV_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_BOARD_SERIAL_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_BOARD_TOT_MAC_ID_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_BOARD_MAC_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_BOARD_ACT_PAS_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_BOARD_CONFIG_MODE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_MFG_DATE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_PART_NUM_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_UUID_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_PCIE_INFO_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_MAX_POWER_MODE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_MEM_SIZE_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_OEMID_SIZE < EEPROM_MAX_FIELD_SIZE );
STATIC_ASSERT( EEPROM_V3_1_CAPABILITY_SIZE < EEPROM_MAX_FIELD_SIZE );

#define EEPROM_STATS( DO )                  \
	DO( EEPROM_STATS_INITIALISATION )   \
	DO( EEPROM_STATS_CHECKSUM )         \
	DO( EEPROM_STATS_READ_FIELD )       \
	DO( EEPROM_STAT_SINGLE_BYTE_READ )  \
	DO( EEPROM_STAT_MULTI_BYTE_READ )   \
	DO( EEPROM_STAT_SINGLE_BYTE_WRITE ) \
	DO( EEPROM_STAT_MULTI_BYTE_WRITE )  \
	DO( EEPROM_STATS_VERIFY_DEVICE_ID ) \
	DO( EEPROM_STATS_MAX )

#define EEPROM_ERROR( DO )                   \
	DO( EEPROM_ERROR_INITIALISATION )    \
	DO( EEPROM_ERROR_SINGLE_BYTE_READ )  \
	DO( EEPROM_ERROR_MULTI_BYTE_READ )   \
	DO( EEPROM_ERROR_SINGLE_BYTE_WRITE ) \
	DO( EEPROM_ERROR_MULTI_BYTE_WRITE )  \
	DO( EEPROM_ERROR_INVALID_VERSION )   \
	DO( EEPROM_ERROR_INCORRECT_VERSION ) \
	DO( EEPROM_ERROR_CHECKSUM )          \
	DO( EEPROM_ERROR_READ_FIELD )        \
	DO( EEPROM_ERROR_VALIDATION )        \
	DO( EEPROM_ERRORS_DEVICE_ID_READ )   \
	DO( EEPROM_ERRORS_VERIFY_DEVICE_ID ) \
	DO( EEPROM_ERROR_MAX )

#define PRINT_STAT( x )       PLL_INF( EEPROM_NAME,           \
				       "%30s. . . .%d\r\n",   \
				       EEPROM_STATS_STR[ x ], \
				       pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_STAT( x ) PLL_INF( EEPROM_NAME,           \
				       "%30s. . . .%d\r\n",   \
				       EEPROM_ERROR_STR[ x ], \
				       pxThis->pulStatErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )  { if( x < EEPROM_STATS_MAX ) pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x ) { if( x < EEPROM_ERROR_MAX ) pxThis->pulStatErrorCounters[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    EEPROM_STATS
 * @brief   Enumeration of stats counters for this driver
 */
UTIL_MAKE_ENUM_AND_STRINGS( EEPROM_STATS, EEPROM_STATS, EEPROM_STATS_STR )

/**
 * @enum    EEPROM_ERROR
 * @brief   Enumeration of stats errors for this driver
 */
UTIL_MAKE_ENUM_AND_STRINGS( EEPROM_ERROR, EEPROM_ERROR, EEPROM_ERROR_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  EEPROM_V4_0_BOARDINFO
 * @brief   Structure to hold the fields for version 4.0 EEPROM data
 */
typedef struct EEPROM_V4_0_BOARDINFO
{
	uint8_t ucEepromVersion[ EEPROM_ASCII_VAR( EEPROM_VERSION_SIZE ) ];
	uint8_t ucProductName[ EEPROM_ASCII_VAR( EEPROM_V4_0_ALVEO_PRODUCT_NAME_SIZE ) ];
	uint8_t ucPartNumber[ EEPROM_ASCII_VAR( EEPROM_V4_0_ALVEO_PART_NUM_OFFSET ) ];
	uint8_t ucMfgPartNumber[ EEPROM_ASCII_VAR( EEPROM_V4_0_MFG_ALVEO_PART_NUM_SIZE ) ];
	uint8_t ucMfgPartRevision[ EEPROM_ASCII_VAR( EEPROM_V4_0_MFG_ALVEO_PART_REV_SIZE ) ];
	uint8_t ucProductSerial[ EEPROM_ASCII_VAR( EEPROM_V4_0_PRODUCT_SERIAL_SIZE ) ];
	uint8_t ucMfgDate[ EEPROM_ASCII_VAR( EEPROM_V4_0_MFG_DATE_SIZE ) ];
	uint8_t ucNumMacIds;
	uint8_t ucMac[ EEPROM_ASCII_VAR( EEPROM_V4_0_MAC_SIZE ) ];
	uint8_t ucUuid[ EEPROM_ASCII_VAR( EEPROM_V4_0_UUID_SIZE ) ];

} EEPROM_V4_0_BOARDINFO;

/**
 * @struct  EEPROM_V3_1_BOARDINFO
 * @brief   Structure to hold the fields for version 3.1 EEPROM data
 */
typedef struct EEPROM_V3_1_BOARDINFO
{
	uint8_t ucEepromVersion[ EEPROM_ASCII_VAR( EEPROM_VERSION_SIZE ) ];
	uint8_t ucProductName[ EEPROM_ASCII_VAR( EEPROM_V3_1_PRODUCT_NAME_SIZE ) ];
	uint8_t ucBoardRev[ EEPROM_ASCII_VAR( EEPROM_V3_1_BOARD_REV_SIZE ) ];
	uint8_t ucBoardSerial[ EEPROM_ASCII_VAR( EEPROM_V3_1_BOARD_SERIAL_SIZE ) ];
	uint8_t ucNumMacIds;
	uint8_t ucBoardMac[ EEPROM_ASCII_VAR( EEPROM_V3_1_BOARD_MAC_SIZE ) ];
	uint8_t ucBoardActivePassive[ EEPROM_ASCII_VAR( EEPROM_V3_1_BOARD_ACT_PAS_SIZE ) ];
	uint8_t ucBoardConfigMode[ EEPROM_ASCII_VAR( EEPROM_V3_1_BOARD_CONFIG_MODE_SIZE ) ];
	uint8_t ucBoardMfgDate[ EEPROM_ASCII_VAR( EEPROM_V3_1_MFG_DATE_SIZE ) ];
	uint8_t ucBoarPartNum[ EEPROM_ASCII_VAR( EEPROM_V3_1_PART_NUM_SIZE ) ];
	uint8_t ucBoardUuid[ EEPROM_ASCII_VAR( EEPROM_V3_1_UUID_SIZE ) ];
	uint8_t ucBoardPcieInfo[ EEPROM_ASCII_VAR( EEPROM_V3_1_PCIE_INFO_SIZE ) ];
	uint8_t ucBoardMaxPowerMode[ EEPROM_ASCII_VAR( EEPROM_V3_1_MAX_POWER_MODE_SIZE ) ];
	uint8_t ucMemorySize[ EEPROM_ASCII_VAR( EEPROM_V3_1_MEM_SIZE_SIZE ) ];
	uint8_t ucOemId[ EEPROM_ASCII_VAR( EEPROM_V3_1_OEMID_SIZE ) ];
	uint8_t ucCapability[ EEPROM_ASCII_VAR( EEPROM_V3_1_CAPABILITY_SIZE ) ];

} EEPROM_V3_1_BOARDINFO;

/**
 * @struct  EEPROM_V3_0_BOARDINFO
 * @brief   Structure to hold the fields for version 3.0 EEPROM data
 */
typedef struct EEPROM_V3_0_BOARDINFO
{
	uint8_t ucEepromVersion[ EEPROM_ASCII_VAR( EEPROM_VERSION_SIZE ) ];
	uint8_t ucProductName[ EEPROM_ASCII_VAR( EEPROM_V3_0_PRODUCT_NAME_SIZE ) ];
	uint8_t ucBoardRev[ EEPROM_ASCII_VAR( EEPROM_V3_0_BOARD_REV_SIZE ) ];
	uint8_t ucBoardSerial[ EEPROM_ASCII_VAR( EEPROM_V3_0_BOARD_SERIAL_SIZE ) ];
	uint8_t ucNumMacIds;
	uint8_t ucBoardMac[ EEPROM_ASCII_VAR( EEPROM_V3_0_BOARD_MAC_SIZE ) ];
	uint8_t ucBoardActivePassive[ EEPROM_ASCII_VAR( EEPROM_V3_0_BOARD_ACT_PAS_SIZE ) ];
	uint8_t ucBoardConfigMode[ EEPROM_ASCII_VAR( EEPROM_V3_0_BOARD_CONFIG_MODE_SIZE ) ];
	uint8_t ucBoardMfgDate[ EEPROM_ASCII_VAR( EEPROM_V3_0_MFG_DATE_SIZE ) ];
	uint8_t ucBoarPartNum[ EEPROM_ASCII_VAR( EEPROM_V3_0_PART_NUM_SIZE ) ];
	uint8_t ucBoardUuid[ EEPROM_ASCII_VAR( EEPROM_V3_0_UUID_SIZE ) ];
	uint8_t ucBoardPcieInfo[ EEPROM_ASCII_VAR( EEPROM_V3_0_PCIE_INFO_SIZE ) ];
	uint8_t ucBoardMaxPowerMode[ EEPROM_ASCII_VAR( EEPROM_V3_0_MAX_POWER_MODE_SIZE ) ];
	uint8_t ucMemorySize[ EEPROM_ASCII_VAR( EEPROM_V3_0_MEM_SIZE_SIZE ) ];
	uint8_t ucOemId[ EEPROM_ASCII_VAR( EEPROM_V3_0_OEMID_SIZE ) ];
	uint8_t ucCapability[ EEPROM_ASCII_VAR( EEPROM_V3_0_CAPABILITY_SIZE ) ];

} EEPROM_V3_0_BOARDINFO;

/**
 * @struct  EEPROM_BOARDINFO
 * @brief   Structure to hold the fields for EEPROM data, version depends on the product
 */
typedef union EEPROM_BOARDINFO
{
	EEPROM_V4_0_BOARDINFO xBoardInfoV4_0;
	EEPROM_V3_1_BOARDINFO xBoardInfoV3_1;
	EEPROM_V3_0_BOARDINFO xBoardInfoV3_0;

} EEPROM_BOARDINFO;

/**
 * @struct  EEPROM_PRIVATE_DATA
 * @brief   Structure to hold ths driver's private data
 */
typedef struct EEPROM_PRIVATE_DATA
{
	uint32_t ulUpperFirewall;
	int iEepromInitialised;
	EEPROM_CFG xEepromCfg;
	EEPROM_VERSION xEepromExpectedVersion;
	EEPROM_VERSION xEepromActualVersion;
	union EEPROM_BOARDINFO xBoardInfo;
	uint8_t                *pucEepromVersion;
	uint8_t                *pucProductName;
	uint8_t                *pucBoardRev;
	uint8_t                *pucBoardSerial;
	uint8_t ucNumMacIds;
	uint8_t                *pucBoardMac;
	uint8_t                *pucBoardActivePassive;
	uint8_t                *pucBoardConfigMode;
	uint8_t                *pucBoardMfgDate;
	uint8_t                *pucBoardPartNum;
	uint8_t                *pucBoardUuid;
	uint8_t                *pucBoardPcieInfo;
	uint8_t                *pucBoardMaxPowerMode;
	uint8_t                *pucMemorySize;
	uint8_t                *pucOemId;
	uint8_t                *pucCapability;
	uint8_t                *pucMfgPartNum;

	uint8_t ucSizeEepromVersion;
	uint8_t ucSizeProductName;
	uint8_t ucSizeBoardRev;
	uint8_t ucSizeBoardSerial;
	uint8_t ucSizeumMacIds;
	uint8_t ucSizeBoardMac;
	uint8_t ucSizeBoardActivePassive;
	uint8_t ucSizeBoardConfigMode;
	uint8_t ucSizeBoardMfgDate;
	uint8_t ucSizeBoardPartNum;
	uint8_t ucSizeBoardUuid;
	uint8_t ucSizeBoardPcieInfo;
	uint8_t ucSizeBoardMaxPowerMode;
	uint8_t ucSizeMemorySize;
	uint8_t ucSizeOemId;
	uint8_t ucSizeCapability;
	uint8_t ucSizeMfgPartNum;

	uint8_t ucOffsetEepromVersion;
	uint8_t ucOffsetProductName;
	uint8_t ucOffsetBoardRev;
	uint8_t ucOffsetBoardSerial;
	uint8_t ucOffsetumMacIds;
	uint8_t ucOffsetBoardMac;
	uint8_t ucOffsetBoardActivePassive;
	uint8_t ucOffsetBoardConfigMode;
	uint8_t ucOffsetBoardMfgDate;
	uint8_t ucOffsetBoardPartNum;
	uint8_t ucOffsetBoardUuid;
	uint8_t ucOffsetBoardPcieInfo;
	uint8_t ucOffsetBoardMaxPowerMode;
	uint8_t ucOffsetMemorySize;
	uint8_t ucOffsetOemId;
	uint8_t ucOffsetCapability;
	uint8_t ucOffsetMfgPartNum;

	uint8_t ucOffsetChecksumLsb;
	uint8_t ucOffsetChecksumMsb;
	uint8_t ucChecksumStart;
	uint8_t ucChecksumEnd;

	uint32_t pulStatCounters[ EEPROM_STATS_MAX ];
	uint32_t pulStatErrorCounters[ EEPROM_ERROR_MAX ];

	uint32_t ulLowerFirewall;

} EEPROM_PRIVATE_DATA;


/******************************************************************************/
/* Local Variables                                                            */
/******************************************************************************/

static EEPROM_PRIVATE_DATA xLocalData =
{
	UPPER_FIREWALL,                                                        /* ulUpperFirewall       */
	FALSE,                                                                 /* iEepromInitialised    */
	{
		0
	},                                                                     /* xEepromCfg            */
	EEPROM_VERSION_MAX,                                                    /* xEepromExpectedVersion*/
	EEPROM_VERSION_MAX,                                                    /* xEepromActualVersion  */
	{ { {
		    0
	    } } },                                                             /* xBoardInfo            */
	NULL,                                                                  /* pucEepromVersion      */
	NULL,                                                                  /* pucProductName        */
	NULL,                                                                  /* pucBoardRev           */
	NULL,                                                                  /* pucBoardSerial        */
	0,                                                                     /* ucNumMacIds           */
	NULL,                                                                  /* pucBoardMac           */
	NULL,                                                                  /* pucBoardActivePassive */
	NULL,                                                                  /* pucBoardConfigMode    */
	NULL,                                                                  /* pucBoardMfgDate       */
	NULL,                                                                  /* pucBoardPartNum       */
	NULL,                                                                  /* pucBoardUuid          */
	NULL,                                                                  /* pucBoardPcieInfo      */
	NULL,                                                                  /* pucBoardMaxPowerMode  */
	NULL,                                                                  /* pucMemorySize         */
	NULL,                                                                  /* pucOemId              */
	NULL,                                                                  /* pucCapability         */
	NULL,                                                                  /* pucMfgPartNum         */

	0,                                                                     /* ucSizeEepromVersion       */
	0,                                                                     /* ucSizeProductName         */
	0,                                                                     /* ucSizeBoardRev            */
	0,                                                                     /* ucSizeBoardSerial         */
	0,                                                                     /* cNSizeumMacIds            */
	0,                                                                     /* ucSizeBoardMac            */
	0,                                                                     /* ucSizeBoardActivePassive  */
	0,                                                                     /* ucSizeBoardConfigMode     */
	0,                                                                     /* ucSizeBoardMfgDate        */
	0,                                                                     /* ucSizeBoardPartNum        */
	0,                                                                     /* ucSizeBoardUuid           */
	0,                                                                     /* ucSizeBoardPcieInfo       */
	0,                                                                     /* ucSizeBoardMaxPowerMode   */
	0,                                                                     /* ucSizeMemorySize          */
	0,                                                                     /* ucSizeOemId               */
	0,                                                                     /* ucSizeCapability          */
	0,                                                                     /* ucSizeMfgPartNum          */

	0,                                                                     /* ucOffsetEepromVersion       */
	0,                                                                     /* ucOffsetProductName         */
	0,                                                                     /* ucOffsetBoardRev            */
	0,                                                                     /* ucOffsetBoardSerial         */
	0,                                                                     /* cNOffsetumMacIds            */
	0,                                                                     /* ucOffsetBoardMac            */
	0,                                                                     /* ucOffsetBoardActivePassive  */
	0,                                                                     /* ucOffsetBoardConfigMode     */
	0,                                                                     /* ucOffsetBoardMfgDate        */
	0,                                                                     /* ucOffsetBoardPartNum        */
	0,                                                                     /* ucOffsetBoardUuid           */
	0,                                                                     /* ucOffsetBoardPcieInfo       */
	0,                                                                     /* ucOffsetBoardMaxPowerMode   */
	0,                                                                     /* ucOffsetMemorySize          */
	0,                                                                     /* ucOffsetOemId               */
	0,                                                                     /* ucOffsetCapability          */
	0,                                                                     /* ucOffsetMfgPartNum          */

	0,                                                                     /* ucOffsetChecksumLsb         */
	0,                                                                     /* ucOffsetChecksumMsb         */
	0,                                                                     /* ucChecksumStart             */
	0,                                                                     /* ucChecksumEnd               */

	{
		0
	},                                                                     /* pulStatCounters[ EEPROM_STATS_MAX ]      */
	{
		0
	},                                                                     /* pulStatErrorCounters[ EEPROM_ERROR_MAX ] */

	LOWER_FIREWALL                                                         /* ulLowerFirewall             */
};

static EEPROM_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Private Function declarations                                              */
/******************************************************************************/

/**
 * @brief   Write a single byte to the EEPROM
 *
 * @param   ucAddressOffset     Address offset of register to write
 * @param   ucRegisterValue     Value to write
 *
 * @return  OK                  Bytes successfully written
 *          ERROR               Bytes write failed
 */
static int ucEepromWriteByte( uint8_t ucAddressOffset, uint8_t ucRegisterValue );

/**
 * @brief   Write one or more bytes to the EEPROM up to the page size
 *
 * @param   ucAddressOffset     Address offset of register to write
 * @param   pucData             Data to write
 * @param   ucWriteSize         Number of bytes to write
 *
 * @return  OK                  Bytes successfully written
 *          ERROR               Bytes write failed
 */
static int ucEepromWriteMultiBytes( uint8_t ucAddressOffset, uint8_t *pucData, uint8_t ucWriteSize );

/**
 * @brief   Read multiple bytes from the EEPROM
 *
 * @param   ucAddressOffset     Address offset of register to read
 * @param   pucRegisterValue    Pointer to the array to hold the read values
 * @param   ucReadSize          Number of bytes to read
 *
 * @return  OK                  Bytes successfully read
 *          ERROR               Bytes read failed
 */
static int ucEepromReadMultiBytes( uint8_t ucAddressOffset, uint8_t *pucRegisterValue, uint8_t ucReadSize );

/**
 * @brief   Read a single byte from the EEPROM
 *
 * @param   ucAddressOffset     Address offset of register to read
 * @param   pucRegisterValue    Pointer to the array to hold the read values
 *
 * @return  OK                  Byte successfully read
 *          ERROR               Byte read failed
 */
static int ucEepromReadByte( uint8_t ucAddressOffset, uint8_t *pucRegisterValue );

/**
 * @brief   Read the EEPROM Field
 *
 * @param   ucAddressOffset     Address offset of register to read
 * @param   pucData             Pointer to the array to hold the read values
 * @param   iIsMac             Is the field a MAC address, formatting treated differently
 *
 * @return  OK                  Field successfully read
 *          ERROR               Field read failed
 */
static int iEepromReadField( uint8_t ucAddressOffset, uint8_t *pucData, uint8_t ucReadSize, int iIsMac );

/**
 * @brief   Point the fields to the required  EEPROM version
 *
 * @param   xVersion            Version of EEPROM data
 *
 * @return  N/A
 */
static void vEepromInitialiseVersionFields( EEPROM_VERSION xVersion );

/**
 * @brief   Verify that the checksum for the EEPROM fields is correct
 *
 * @return  OK                  Checksum successfully verified
 *          ERROR               Checksum verification failed
 */
static int iEepromVerifyChecksum( void );

/**
 * @brief   Verify the EEPROM device ID.
 *
 * @return  OK if successful, else ERROR.
 */
static int iEeprom_VerifyDeviceId( void );

#ifdef EEPROM_VERBOSE_DEBUG_ENABLE
/**
 * @brief   Dump out all the EEPROM contents
 *
 * @return  OK                  Successs
 *          ERROR               Failure
 */
static int iEepromDumpContents( void );
#endif

/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/
/**
 * @brief   Initialises the EEPROM driver.
 */
int iEEPROM_Initialise( EEPROM_VERSION xEepromVersion, EEPROM_CFG *pxEepromCfg )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( FALSE == pxThis->iEepromInitialised )  &&
	    ( NULL != pxEepromCfg ) &&
	    ( ( uint16_t ) EEPROM_WRITE_BYTE_SIZE_MAX >= ( uint16_t ) ( pxEepromCfg->ucEepromAddressSize + 1 ) ) &&
	    ( ( uint16_t ) EEPROM_WRITE_MULTI_BYTE_SIZE_MAX >=
	      ( uint16_t ) ( pxEepromCfg->ucEepromAddressSize + pxEepromCfg->ucEepromPageSize ) ) )
	{
		pxThis->xEepromExpectedVersion = xEepromVersion;
		pvOSAL_MemCpy( &pxThis->xEepromCfg, pxEepromCfg, sizeof( pxThis->xEepromCfg ) );
		vEepromInitialiseVersionFields( pxThis->xEepromExpectedVersion );

		iStatus = iEeprom_VerifyDeviceId();
		if( OK == iStatus )
		{
			/* First lets read the EEPROM Version if possible */
			iStatus = iEepromReadField( pxThis->ucOffsetEepromVersion,
			                            pxThis->pucEepromVersion,
			                            pxThis->ucSizeEepromVersion,
			                            FALSE );
			if( OK == iStatus )
			{
				uint32_t ulEepromVersion = ( ( pxThis->pucEepromVersion[ 0 ] << 24 ) |
				                             ( pxThis->pucEepromVersion[ 1 ] << 16 ) |
				                             ( pxThis->pucEepromVersion[ 2 ] << 8 ) |
				                             ( pxThis->pucEepromVersion[ 3 ] ) );
				/* The i2c read passed now check what it read */
				switch( ulEepromVersion )
				{
				case EEPROM_V4_0:
				{
					pxThis->xEepromActualVersion = EEPROM_VERSION_4_0;
					break;
				}

				case EEPROM_V3_1:
				{
					pxThis->xEepromActualVersion = EEPROM_VERSION_3_1;
					break;
				}

				case EEPROM_V3_0:
				{
					pxThis->xEepromActualVersion = EEPROM_VERSION_3_0;
					break;
				}

				default:
				{
					iStatus = ERROR;
					PLL_ERR( EEPROM_NAME, "Version error %X\r\n", ulEepromVersion );
					INC_ERROR_COUNTER( EEPROM_ERROR_INVALID_VERSION );
				}
				}

				if( OK == iStatus )
				{
					if( pxThis->xEepromExpectedVersion != pxThis->xEepromActualVersion )
					{
						PLL_WRN( EEPROM_NAME, "Unexpected EEPROM version\r\n" );
						INC_ERROR_COUNTER( EEPROM_ERROR_INCORRECT_VERSION );

						/* Re-initialise fields for the actual version */
						vEepromInitialiseVersionFields( pxThis->xEepromActualVersion );
					}
				}
			}
			else
			{
				INC_ERROR_COUNTER( EEPROM_ERROR_READ_FIELD );
			}

			if( OK == iStatus )
			{
				iStatus = iEepromVerifyChecksum();
				if( OK == iStatus )
				{
					/* If EEPROM Version was read ok now read the other fields */
					if( OK == iStatus )
					{
						iStatus = iEepromReadField( pxThis->ucOffsetProductName,
						                            pxThis->pucProductName,
						                            pxThis->ucSizeProductName,
						                            FALSE );
					}

					if( OK == iStatus )
					{
						iStatus = iEepromReadField( pxThis->ucOffsetBoardRev,
						                            pxThis->pucBoardRev,
						                            pxThis->ucSizeBoardRev,
						                            FALSE );
					}

					if( OK == iStatus )
					{
						iStatus = iEepromReadField( pxThis->ucOffsetBoardSerial,
						                            pxThis->pucBoardSerial,
						                            pxThis->ucSizeBoardSerial,
						                            FALSE );
					}

					if( OK == iStatus )
					{
						uint8_t ucNumMacIdsArray[ EEPROM_V4_0_TOT_MAC_ID_SIZE ] =
						{
							0
						};
						iStatus = iEepromReadField( pxThis->ucOffsetumMacIds,
						                            ucNumMacIdsArray,
						                            pxThis->ucSizeumMacIds,
						                            FALSE );

						if( OK == iStatus )
						{
							pxThis->ucNumMacIds = ucNumMacIdsArray[ 0 ];
						}
					}

					if( OK == iStatus )
					{
						iStatus = iEepromReadField( pxThis->ucOffsetBoardMac,
						                            pxThis->pucBoardMac,
						                            pxThis->ucSizeBoardMac,
						                            TRUE );
					}

					if( OK == iStatus )
					{
						iStatus = iEepromReadField( pxThis->ucOffsetBoardMfgDate,
						                            pxThis->pucBoardMfgDate,
						                            pxThis->ucSizeBoardMfgDate,
						                            FALSE );
					}

					if( OK == iStatus )
					{
						iStatus = iEepromReadField( pxThis->ucOffsetBoardPartNum,
						                            pxThis->pucBoardPartNum,
						                            pxThis->ucSizeBoardPartNum,
						                            FALSE );
					}

					if( OK == iStatus )
					{
						iStatus = iEepromReadField( pxThis->ucOffsetBoardUuid,
						                            pxThis->pucBoardUuid,
						                            pxThis->ucSizeBoardUuid,
						                            FALSE );
					}

					if( ( EEPROM_VERSION_3_0 == pxThis->xEepromActualVersion ) ||
					    ( EEPROM_VERSION_3_1 == pxThis->xEepromActualVersion ) )
					{
						if( OK == iStatus )
						{
							iStatus = iEepromReadField( pxThis->ucOffsetBoardActivePassive,
							                            pxThis->pucBoardActivePassive,
							                            pxThis->ucSizeBoardActivePassive,
							                            FALSE );
						}

						if( OK == iStatus )
						{
							iStatus = iEepromReadField( pxThis->ucOffsetBoardConfigMode,
							                            pxThis->pucBoardConfigMode,
							                            pxThis->ucSizeBoardConfigMode,
							                            FALSE );
						}

						if( OK == iStatus )
						{
							iStatus = iEepromReadField( pxThis->ucOffsetBoardPcieInfo,
							                            pxThis->pucBoardPcieInfo,
							                            pxThis->ucSizeBoardPcieInfo,
							                            FALSE );
						}

						if( OK == iStatus )
						{
							iStatus = iEepromReadField( pxThis->ucOffsetBoardMaxPowerMode,
							                            pxThis->pucBoardMaxPowerMode,
							                            pxThis->ucSizeBoardMaxPowerMode,
							                            FALSE );
						}

						if( OK == iStatus )
						{
							iStatus = iEepromReadField( pxThis->ucOffsetMemorySize,
							                            pxThis->pucMemorySize,
							                            pxThis->ucSizeMemorySize,
							                            FALSE );
						}

						if( OK == iStatus )
						{
							iStatus = iEepromReadField( pxThis->ucOffsetOemId,
							                            pxThis->pucOemId,
							                            pxThis->ucSizeOemId,
							                            FALSE );
						}

						if( OK == iStatus )
						{
							iStatus = iEepromReadField( pxThis->ucOffsetCapability,
							                            pxThis->pucCapability,
							                            pxThis->ucSizeCapability,
							                            FALSE );
						}
					}
					else if( EEPROM_VERSION_4_0 == pxThis->xEepromActualVersion )
					{
						if( OK == iStatus )
						{
							iStatus = iEepromReadField( pxThis->ucOffsetMfgPartNum,
							                            pxThis->pucMfgPartNum,
							                            pxThis->ucSizeMfgPartNum,
							                            FALSE );
						}
					}
				}

				if( OK == iStatus )
				{
					pxThis->iEepromInitialised = TRUE;
				}
			}
			else
			{
				INC_ERROR_COUNTER( EEPROM_ERROR_CHECKSUM );
			}
		}
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	if( OK == iStatus )
	{
		INC_STAT_COUNTER( EEPROM_STATS_INITIALISATION );
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_INITIALISATION );
	}

#ifdef EEPROM_VERBOSE_DEBUG_ENABLE
	iEepromDumpContents();
#endif

	return iStatus;
}

/**
 * @brief   Read the EEPROM Version
 */
int iEEPROM_GetEepromVersion( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucEepromVersion, pxThis->ucSizeEepromVersion );
		*pucSizeBytes = pxThis->ucSizeEepromVersion;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the Product Name
 */
int iEEPROM_GetProductName( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucProductName, pxThis->ucSizeProductName );
		*pucSizeBytes = pxThis->ucSizeProductName;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the Product Revision
 */
int iEEPROM_GetProductRevision( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucBoardRev, pxThis->ucSizeBoardRev );
		*pucSizeBytes = pxThis->ucSizeBoardRev;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the board serial number
 */
int iEEPROM_GetSerialNumber( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucBoardSerial, pxThis->ucSizeBoardSerial );
		*pucSizeBytes = pxThis->ucSizeBoardSerial;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the number of MAC addresses
 */
int iEEPROM_GetMacAddressCount( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, &pxThis->ucNumMacIds, pxThis->ucSizeumMacIds );
		*pucSizeBytes = pxThis->ucSizeumMacIds;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the First MAC Address
 */
int iEEPROM_GetFirstMacAddress( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucBoardMac, pxThis->ucSizeBoardMac );
		*pucSizeBytes = pxThis->ucSizeBoardMac;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the Active/Passive state
 */
int iEEPROM_GetActiveState( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucBoardActivePassive, pxThis->ucSizeBoardActivePassive );
		*pucSizeBytes = pxThis->ucSizeBoardActivePassive;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the Config Mode
 */
int iEEPROM_GetConfigMode( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucBoardConfigMode, pxThis->ucSizeBoardConfigMode );
		*pucSizeBytes = pxThis->ucSizeBoardConfigMode;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the Manufacturing Date
 */
int iEEPROM_GetManufacturingDate( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucBoardMfgDate, pxThis->ucSizeBoardMfgDate );
		*pucSizeBytes = pxThis->ucSizeBoardMfgDate;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the Part Number
 */
int iEEPROM_GetPartNumber( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucBoardPartNum, pxThis->ucSizeBoardPartNum );
		*pucSizeBytes = pxThis->ucSizeBoardPartNum;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the Manufacturer Part Number
 */
int iEEPROM_GetMfgPartNumber( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucMfgPartNum, pxThis->ucSizeMfgPartNum );
		*pucSizeBytes = pxThis->ucSizeMfgPartNum;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the UUID
 */
int iEEPROM_GetUuid( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucBoardUuid, pxThis->ucSizeBoardUuid );
		*pucSizeBytes = pxThis->ucSizeBoardUuid;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the PCIe ID
 */
int iEEPROM_GetPcieId( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucBoardPcieInfo, pxThis->ucSizeBoardPcieInfo );
		*pucSizeBytes = pxThis->ucSizeBoardPcieInfo;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the Max Power Mode
 */
int iEEPROM_GetMaxPowerMode( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucBoardMaxPowerMode, pxThis->ucSizeBoardMaxPowerMode );
		*pucSizeBytes = pxThis->ucSizeBoardMaxPowerMode;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the Memory Size
 */
int iEEPROM_GetMemorySize( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucMemorySize, pxThis->ucSizeMemorySize );
		*pucSizeBytes = pxThis->ucSizeMemorySize;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read the OEM ID
 */
int iEEPROM_GetOemId( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucOemId, pxThis->ucSizeOemId );
		*pucSizeBytes = pxThis->ucSizeOemId;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}


	return iStatus;
}

/**
 * @brief   Read the Capability
 */
int iEEPROM_GetCapability( uint8_t *pucField, uint8_t *pucSizeBytes )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucField ) &&
	    ( NULL != pucSizeBytes ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		pvOSAL_MemCpy( pucField, pxThis->pucCapability, pxThis->ucSizeCapability );
		*pucSizeBytes = pxThis->ucSizeCapability;
		iStatus       = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read raw data
 */
int iEEPROM_ReadRawValue( uint8_t *pucData, uint8_t ucSizeBytes, uint8_t ucEepromAddr )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucData ) &&
	    ( EEPROM_ADDRESS_SIZE_UNINITIALISED != pxThis->xEepromCfg.ucEepromAddressSize ) &&
	    ( EEPROM_MAX_DATA_SIZE >= ucSizeBytes ) )
	{
		iStatus = OK;
		if( OK != ucEepromReadMultiBytes( ucEepromAddr, pucData, ucSizeBytes ) )
		{
			iStatus = ERROR;
		}
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Write raw data
 */
int iEEPROM_WriteRawValue( uint8_t *pucData, uint8_t ucSizeBytes, uint8_t ucEepromAddr )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( NULL != pucData ) &&
	    ( EEPROM_ADDRESS_SIZE_UNINITIALISED != pxThis->xEepromCfg.ucEepromAddressSize ) &&
	    ( EEPROM_MAX_DATA_SIZE >= ucSizeBytes ) )
	{
		iStatus = OK;

		if( EEPROM_DATA_SINGLE_BYTE == ucSizeBytes )
		{
			if( OK != ucEepromWriteByte( ucEepromAddr, pucData[ EEPROM_ADDRESS_BYTE_ZERO ] ) )
			{
				iStatus = ERROR;
			}
		}
		else
		{
			uint8_t ucOffset           = ucEepromAddr;
			uint8_t ucBytesToWrite     = 0;
			uint8_t ucBytesInFirstPage = 0;

			if( ucOffset % pxThis->xEepromCfg.ucEepromPageSize )
			{
				ucBytesInFirstPage = ( pxThis->xEepromCfg.ucEepromPageSize -
				                       ( ucEepromAddr % pxThis->xEepromCfg.ucEepromPageSize ) );
				if( ucBytesInFirstPage > ucSizeBytes )
				{
					ucBytesInFirstPage = ucSizeBytes;
				}
				iStatus = ucEepromWriteMultiBytes( ucOffset, pucData, ucBytesInFirstPage );
				if( OK == iStatus )
				{
					ucOffset += ucBytesInFirstPage;
				}
			}

			if( OK == iStatus )
			{
				ucBytesToWrite = ucSizeBytes - ucBytesInFirstPage;

				while( 0 < ucBytesToWrite )
				{
					uint8_t ucBytesToWriteNextPage = 0;

					/* Either write a page or the remainder of a page */
					if( pxThis->xEepromCfg.ucEepromPageSize <= ucBytesToWrite )
					{
						ucBytesToWriteNextPage = pxThis->xEepromCfg.ucEepromPageSize;
						ucBytesToWrite        -= pxThis->xEepromCfg.ucEepromPageSize;
					}
					else
					{
						ucBytesToWriteNextPage = ucBytesToWrite;
						ucBytesToWrite         = 0;
					}

					iStatus = ucEepromWriteMultiBytes( ucOffset,
					                                   &pucData[ ucOffset - ucEepromAddr ],
					                                   ucBytesToWriteNextPage );
					if( OK != iStatus )
					{
						/* Failure counter set within function, break and return */
						break;
					}
					ucOffset += ucBytesToWriteNextPage;
				}
			}
		}
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Print all the stats gathered by the eeprom driver
 */
int iEEPROM_PrintStatistics( void )
{
	int iStatus = ERROR;
	int i       = 0;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
	{
		PLL_INF( EEPROM_NAME, "======================================\n\r" );
		PLL_INF( EEPROM_NAME, "Statistics:\n\r" );
		for( i = 0; i < EEPROM_STATS_MAX; i++ )
		{
			PRINT_STAT( i );
		}
		PLL_INF( EEPROM_NAME, "--------------------------------------\n\r" );
		PLL_INF( EEPROM_NAME, "Errors:\n\r" );
		for( i = 0; i < EEPROM_ERROR_MAX; i++ )
		{
			PRINT_ERROR_STAT( i );
		}
		PLL_INF( EEPROM_NAME, "======================================\n\r" );
		iStatus = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Clear all the stats in the eeprom driver
 */
int iEEPROM_ClearStatistics( void )
{
	int iStatus = ERROR;
	int i       = 0;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
	{
		for( i = 0; i < EEPROM_STATS_MAX; i++ )
		{
			pxThis->pulStatCounters[ i ] = 0;
		}
		for( i = 0; i < EEPROM_ERROR_MAX; i++ )
		{
			pxThis->pulStatErrorCounters[ i ] = 0;
		}
		iStatus = OK;
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Display all the EEPROM fields
 */
int iEEPROM_DisplayEepromValues( void )
{
	int iStatus = ERROR;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
	    ( TRUE == pxThis->iEepromInitialised ) )
	{
		iStatus = OK;

		PLL_LOG( EEPROM_NAME,
		         "Manufacturing INFO: EEPROM Version        : %s\n\r",
		         pxThis->pucEepromVersion );
		PLL_LOG( EEPROM_NAME,
		         "Manufacturing INFO: Name                  : %s\n\r",
		         pxThis->pucProductName );
		PLL_LOG( EEPROM_NAME,
		         "Manufacturing INFO: Board Rev             : %s\n\r",
		         pxThis->pucBoardRev );
		PLL_LOG( EEPROM_NAME,
		         "Manufacturing INFO: Serial Number         : %s\n\r",
		         pxThis->pucBoardSerial );
		PLL_LOG( EEPROM_NAME,
		         "Manufacturing INFO: # MACS                : %d\n\r",
		         pxThis->ucNumMacIds );
		PLL_LOG( EEPROM_NAME,
		         "Manufacturing INFO: Mac Address 1         : %02x:%02x:%02x:%02x:%02x:%02x\n\r",
		         pxThis->pucBoardMac[ 0 ],
		         pxThis->pucBoardMac[ 1 ],
		         pxThis->pucBoardMac[ 2 ],
		         pxThis->pucBoardMac[ 3 ],
		         pxThis->pucBoardMac[ 4 ],
		         pxThis->pucBoardMac[ 5 ] );
		PLL_LOG( EEPROM_NAME,
		         "Manufacturing INFO: MFG DATE              : %02x%02x%02x\n\r",
		         pxThis->pucBoardMfgDate[ 0 ],
		         pxThis->pucBoardMfgDate[ 1 ],
		         pxThis->pucBoardMfgDate[ 2 ] );
		PLL_LOG( EEPROM_NAME,
		         "Manufacturing INFO: Board Part Num        : %s\n\r",
		         pxThis->pucBoardPartNum );
		PLL_LOG( EEPROM_NAME,
		         "Manufacturing INFO: UUID                  : %02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x\n\r",
		         pxThis->pucBoardUuid[ 0 ],
		         pxThis->pucBoardUuid[ 1 ],
		         pxThis->pucBoardUuid[ 2 ],
		         pxThis->pucBoardUuid[ 3 ],
		         pxThis->pucBoardUuid[ 4 ],
		         pxThis->pucBoardUuid[ 5 ],
		         pxThis->pucBoardUuid[ 6 ],
		         pxThis->pucBoardUuid[ 7 ],
		         pxThis->pucBoardUuid[ 8 ],
		         pxThis->pucBoardUuid[ 9 ],
		         pxThis->pucBoardUuid[ 10 ],
		         pxThis->pucBoardUuid[ 11 ],
		         pxThis->pucBoardUuid[ 12 ],
		         pxThis->pucBoardUuid[ 13 ],
		         pxThis->pucBoardUuid[ 14 ],
		         pxThis->pucBoardUuid[ 15 ] );
		if( ( EEPROM_VERSION_3_0 == pxThis->xEepromActualVersion ) ||
		    ( EEPROM_VERSION_3_1 == pxThis->xEepromActualVersion ) )
		{
			PLL_LOG( EEPROM_NAME,
			         "Manufacturing INFO: Board A/P             : %s\n\r",
			         pxThis->pucBoardActivePassive );
			PLL_LOG( EEPROM_NAME,
			         "Manufacturing INFO: Board config mode     : %02x\n\r",
			         pxThis->pucBoardConfigMode[ 0 ] );
			PLL_LOG( EEPROM_NAME,
			         "Manufacturing INFO: PCIe Info             : %02x%02x, %02x%02x, %02x%02x, %02x%02x\n\r",
			         pxThis->pucBoardPcieInfo[ 0 ],
			         pxThis->pucBoardPcieInfo[ 1 ],
			         pxThis->pucBoardPcieInfo[ 2 ],
			         pxThis->pucBoardPcieInfo[ 3 ],
			         pxThis->pucBoardPcieInfo[ 4 ],
			         pxThis->pucBoardPcieInfo[ 5 ],
			         pxThis->pucBoardPcieInfo[ 6 ],
			         pxThis->pucBoardPcieInfo[ 7 ] );
			PLL_LOG( EEPROM_NAME,
			         "Manufacturing INFO: board max power mode  : %d\n\r",
			         pxThis->pucBoardMaxPowerMode[ 0 ] );
			PLL_LOG( EEPROM_NAME,
			         "Manufacturing INFO: Memory Size           : %s\n\r",
			         pxThis->pucMemorySize );
			PLL_LOG( EEPROM_NAME,
			         "Manufacturing INFO: OEM ID                : %02x%02x%02x%02x\n\r",
			         pxThis->pucOemId[ 3 ],
			         pxThis->pucOemId[ 2 ],
			         pxThis->pucOemId[ 1 ],
			         pxThis->pucOemId[ 0 ] );
			PLL_LOG( EEPROM_NAME,
			         "Manufacturing INFO: Capability            : %02x%02x\n\r",
			         pxThis->pucCapability[ 1 ],
			         pxThis->pucCapability[ 0 ] );
		}
		else if( EEPROM_VERSION_4_0 == pxThis->xEepromActualVersion )
		{
			PLL_LOG( EEPROM_NAME, "Manufacturing INFO: MFG part number       : %s\n\r", pxThis->pucMfgPartNum );
		}
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}


/******************************************************************************/
/* Private Function declarations                                              */
/******************************************************************************/

/**
 * @brief   Write a single byte to the EEPROM
 */
static int ucEepromWriteByte( uint8_t ucAddressOffset, uint8_t ucRegisterValue )
{
	int iStatus = ERROR;
	uint8_t pucBuffer[ EEPROM_WRITE_BYTE_SIZE_MAX ] =
	{
		0
	};

	if( ( EEPROM_ONE_BYTE <= pxThis->xEepromCfg.ucEepromAddressSize ) &&
	    ( EEPROM_TWO_BYTES >= pxThis->xEepromCfg.ucEepromAddressSize ) )
	{
		uint32_t ulDataLen = pxThis->xEepromCfg.ucEepromAddressSize + EEPROM_DATA_SINGLE_BYTE;

		if( EEPROM_2_BYTE_ADDRESS == pxThis->xEepromCfg.ucEepromAddressSize )
		{
			pucBuffer[ EEPROM_ADDRESS_BYTE_ONE ]     = ucAddressOffset;
			pucBuffer[ EEPROM_ADDRESS_BYTE_ONE + 1 ] = ucRegisterValue;
		}
		else
		{
			pucBuffer[ EEPROM_ADDRESS_BYTE_ZERO ]     = ucAddressOffset;
			pucBuffer[ EEPROM_ADDRESS_BYTE_ZERO + 1 ] = ucRegisterValue;
		}

		iStatus = iI2C_Send( pxThis->xEepromCfg.ucEepromI2cBus,
		                     pxThis->xEepromCfg.ucEepromSlaveAddress,
		                     pucBuffer,
		                     ulDataLen );
		if( ERROR == iStatus )
		{
			INC_ERROR_COUNTER( EEPROM_ERROR_SINGLE_BYTE_WRITE );
		}
		else
		{
			INC_STAT_COUNTER( EEPROM_STAT_SINGLE_BYTE_WRITE );
		}
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Write one or more bytes to the EEPROM up to the page size
 */
static int ucEepromWriteMultiBytes( uint8_t ucAddressOffset, uint8_t *pucData, uint8_t ucWriteSize )
{
	int iStatus = ERROR;
	uint8_t pucBuffer[ EEPROM_WRITE_MULTI_BYTE_SIZE_MAX ] =
	{
		0
	};

	if( ( EEPROM_ONE_BYTE <= pxThis->xEepromCfg.ucEepromAddressSize ) &&
	    ( EEPROM_TWO_BYTES >= pxThis->xEepromCfg.ucEepromAddressSize ) &&
	    ( pxThis->xEepromCfg.ucEepromPageSize >= ucWriteSize ) )
	{
		uint32_t ulDataLen = pxThis->xEepromCfg.ucEepromAddressSize + ucWriteSize;

		if( EEPROM_2_BYTE_ADDRESS == pxThis->xEepromCfg.ucEepromAddressSize )
		{
			pucBuffer[ EEPROM_ADDRESS_BYTE_ONE ] = ucAddressOffset;
			pvOSAL_MemCpy( &pucBuffer[ EEPROM_ADDRESS_BYTE_ONE + 1 ], pucData, ucWriteSize );
		}
		else
		{
			pucBuffer[ EEPROM_ADDRESS_BYTE_ZERO ] = ucAddressOffset;
			pvOSAL_MemCpy( &pucBuffer[ EEPROM_ADDRESS_BYTE_ZERO + 1 ], pucData, ucWriteSize );
		}

		iStatus = iI2C_Send( pxThis->xEepromCfg.ucEepromI2cBus,
		                     pxThis->xEepromCfg.ucEepromSlaveAddress,
		                     pucBuffer,
		                     ulDataLen );
		if( ERROR == iStatus )
		{
			INC_ERROR_COUNTER( EEPROM_ERROR_MULTI_BYTE_WRITE );
		}
		else
		{
			/* Small delay required between each write */
			iOSAL_Task_SleepMs( EEPROM_WRITE_DELAY_MS );
			INC_STAT_COUNTER( EEPROM_STAT_MULTI_BYTE_WRITE );
		}
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read a single byte from the EEPROM
 */
static int ucEepromReadByte( uint8_t ucAddressOffset, uint8_t *pucRegisterValue )
{
	int iStatus = ERROR;
	uint8_t pucAddressOffset[ EEPROM_ADDRESS_SIZE_MAX ] =
	{
		0
	};

	if( ( NULL != pucRegisterValue ) &&
	    ( EEPROM_ONE_BYTE <= pxThis->xEepromCfg.ucEepromAddressSize ) &&
	    ( EEPROM_TWO_BYTES >= pxThis->xEepromCfg.ucEepromAddressSize ) )
	{
		if( EEPROM_2_BYTE_ADDRESS == pxThis->xEepromCfg.ucEepromAddressSize )
		{
			pucAddressOffset[ EEPROM_ADDRESS_BYTE_ONE ] = ucAddressOffset;
		}
		else
		{
			pucAddressOffset[ EEPROM_ADDRESS_BYTE_ZERO ] = ucAddressOffset;
		}

		iStatus = iI2C_SendRecv( pxThis->xEepromCfg.ucEepromI2cBus,
		                         pxThis->xEepromCfg.ucEepromSlaveAddress,
		                         pucAddressOffset,
		                         pxThis->xEepromCfg.ucEepromAddressSize,
		                         pucRegisterValue,
		                         EEPROM_DATA_SINGLE_BYTE );
		if( ERROR == iStatus )
		{
			INC_ERROR_COUNTER( EEPROM_ERROR_SINGLE_BYTE_READ );
		}
		else
		{
			INC_STAT_COUNTER( EEPROM_STAT_SINGLE_BYTE_READ );
		}
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Read multiple bytes from the EEPROM
 */
static int ucEepromReadMultiBytes( uint8_t ucAddressOffset, uint8_t *pucRegisterValue, uint8_t ucReadSize )
{
	int iStatus = ERROR;
	uint8_t pucAddressOffset[ EEPROM_ADDRESS_SIZE_MAX ] =
	{
		0
	};

	if( ( NULL != pucRegisterValue ) &&
	    ( EEPROM_ONE_BYTE <= pxThis->xEepromCfg.ucEepromAddressSize ) &&
	    ( EEPROM_TWO_BYTES >= pxThis->xEepromCfg.ucEepromAddressSize ) )
	{
		if( EEPROM_2_BYTE_ADDRESS == pxThis->xEepromCfg.ucEepromAddressSize )
		{
			pucAddressOffset[ EEPROM_ADDRESS_BYTE_ONE ] = ucAddressOffset;
		}
		else
		{
			pucAddressOffset[ EEPROM_ADDRESS_BYTE_ZERO ] = ucAddressOffset;
		}

		iStatus = iI2C_SendRecv( pxThis->xEepromCfg.ucEepromI2cBus,
		                         pxThis->xEepromCfg.ucEepromSlaveAddress,
		                         pucAddressOffset,
		                         pxThis->xEepromCfg.ucEepromAddressSize,
		                         pucRegisterValue,
		                         ucReadSize );
		if( ERROR == iStatus )
		{
			INC_ERROR_COUNTER( EEPROM_ERROR_MULTI_BYTE_READ );
		}
		else
		{
			INC_STAT_COUNTER( EEPROM_STAT_MULTI_BYTE_READ );
		}
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}


	return iStatus;
}

/**
 * @brief   Read the EEPROM Field
 *
 * @return  N/A
 */
static int iEepromReadField( uint8_t ucAddressOffset, uint8_t *pucData, uint8_t ucReadSize, int iIsMac )
{
	int iStatus = ERROR;
	int i       = 0;

	if( ( NULL != pucData ) &&
	    ( EEPROM_ONE_BYTE <= pxThis->xEepromCfg.ucEepromAddressSize ) &&
	    ( EEPROM_TWO_BYTES >= pxThis->xEepromCfg.ucEepromAddressSize ) )
	{
		for( i = 0; i < ucReadSize; i++ )
		{
			iStatus = ucEepromReadByte( ucAddressOffset++, &pucData[ i ] );
			if( FALSE == iIsMac )
			{
				if( pucData[ i ] == EEPROM_DEFAULT_VAL )
				{
					pucData[ i ] = '\0';
				}
			}
			if( ERROR == iStatus )
			{
				break;
			}
		}

		/* Explicitly set \0 at the end of field string */
		pucData[ ucReadSize ] = '\0';
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	if( ERROR == iStatus )
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_READ_FIELD );
	}
	else
	{
		INC_STAT_COUNTER( EEPROM_STATS_READ_FIELD );
	}

	return iStatus;
}

/**
 * @brief   Point the fields to the required  EEPROM version
 */
static void vEepromInitialiseVersionFields( EEPROM_VERSION xVersion )
{
	if( EEPROM_VERSION_4_0 == xVersion )
	{
		pxThis->pucEepromVersion = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucEepromVersion );
		pxThis->pucProductName   = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucProductName );
		pxThis->pucBoardPartNum  = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucPartNumber );
		pxThis->pucMfgPartNum    = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucMfgPartNumber );
		pxThis->pucBoardRev      = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucMfgPartRevision );
		pxThis->pucBoardSerial   = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucProductSerial );
		pxThis->pucBoardMfgDate  = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucMfgDate );
		pxThis->ucNumMacIds      = ( pxThis->xBoardInfo.xBoardInfoV4_0.ucNumMacIds );
		pxThis->pucBoardMac      = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucMac );
		pxThis->pucBoardUuid     = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucUuid );

		pxThis->ucSizeEepromVersion      = EEPROM_VERSION_SIZE;
		pxThis->ucSizeProductName        = EEPROM_V4_0_ALVEO_PRODUCT_NAME_SIZE;
		pxThis->ucSizeBoardPartNum       = EEPROM_V4_0_ALVEO_PART_NUM_SIZE;
		pxThis->ucSizeBoardRev           = EEPROM_V4_0_MFG_ALVEO_PART_REV_SIZE;
		pxThis->ucSizeBoardSerial        = EEPROM_V4_0_PRODUCT_SERIAL_SIZE;
		pxThis->ucSizeumMacIds           = EEPROM_V4_0_TOT_MAC_ID_SIZE;
		pxThis->ucSizeBoardMac           = EEPROM_V4_0_MAC_SIZE;
		pxThis->ucSizeBoardMfgDate       = EEPROM_V4_0_MFG_DATE_SIZE;
		pxThis->ucSizeBoardUuid          = EEPROM_V4_0_UUID_SIZE;
		pxThis->ucSizeMfgPartNum         = EEPROM_V4_0_MFG_ALVEO_PART_NUM_SIZE;
		pxThis->ucSizeBoardActivePassive = EEPROM_FIELD_NA_SIZE;
		pxThis->ucSizeBoardConfigMode    = EEPROM_FIELD_NA_SIZE;
		pxThis->ucSizeBoardPcieInfo      = EEPROM_FIELD_NA_SIZE;
		pxThis->ucSizeBoardMaxPowerMode  = EEPROM_FIELD_NA_SIZE;
		pxThis->ucSizeMemorySize         = EEPROM_FIELD_NA_SIZE;
		pxThis->ucSizeOemId              = EEPROM_FIELD_NA_SIZE;
		pxThis->ucSizeCapability         = EEPROM_FIELD_NA_SIZE;

		pxThis->ucOffsetEepromVersion = EEPROM_VERSION_OFFSET;
		pxThis->ucOffsetProductName   = EEPROM_V4_0_ALVEO_PRODUCT_NAME_OFFSET;
		pxThis->ucOffsetBoardRev      = EEPROM_V4_0_MFG_ALVEO_PART_REV_OFFSET;
		pxThis->ucOffsetBoardSerial   = EEPROM_V4_0_PRODUCT_SERIAL_OFFSET;
		pxThis->ucOffsetumMacIds      = EEPROM_V4_0_TOT_MAC_ID_OFFSET;
		pxThis->ucOffsetBoardMac      = EEPROM_V4_0_MAC_OFFSET;
		pxThis->ucOffsetBoardMfgDate  = EEPROM_V4_0_MFG_DATE_OFFSET;
		pxThis->ucOffsetBoardPartNum  = EEPROM_V4_0_ALVEO_PART_NUM_OFFSET;
		pxThis->ucOffsetMfgPartNum    = EEPROM_V4_0_MFG_ALVEO_PART_NUM_OFFSET;
		pxThis->ucOffsetBoardUuid     = EEPROM_V4_0_UUID_OFFSET;

		pxThis->ucOffsetChecksumLsb = EEPROM_V4_0_DATA_CHECKSUM_LSB_OFFSET;
		pxThis->ucOffsetChecksumMsb = EEPROM_V4_0_DATA_CHECKSUM_MSB_OFFSET;
		pxThis->ucChecksumStart     = EEPROM_V4_0_CHECKSUM_START;
		pxThis->ucChecksumEnd       = EEPROM_V4_0_CHECKSUM_END;
	}
	else if( EEPROM_VERSION_3_1 == xVersion )
	{
		pxThis->pucEepromVersion      = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucEepromVersion );
		pxThis->pucProductName        = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucProductName );
		pxThis->pucBoardRev           = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardRev );
		pxThis->pucBoardSerial        = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardSerial );
		pxThis->ucNumMacIds           = ( pxThis->xBoardInfo.xBoardInfoV3_1.ucNumMacIds );
		pxThis->pucBoardMac           = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardMac );
		pxThis->pucBoardActivePassive = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardActivePassive );
		pxThis->pucBoardConfigMode    = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardConfigMode );
		pxThis->pucBoardMfgDate       = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardMfgDate );
		pxThis->pucBoardPartNum       = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoarPartNum );
		pxThis->pucBoardUuid          = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardUuid );
		pxThis->pucBoardPcieInfo      = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardPcieInfo );
		pxThis->pucBoardMaxPowerMode  = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardMaxPowerMode );
		pxThis->pucMemorySize         = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucMemorySize );
		pxThis->pucOemId              = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucOemId );
		pxThis->pucCapability         = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucCapability );

		pxThis->ucSizeEepromVersion      = EEPROM_VERSION_SIZE;
		pxThis->ucSizeProductName        = EEPROM_V3_1_PRODUCT_NAME_SIZE;
		pxThis->ucSizeBoardRev           = EEPROM_V3_1_BOARD_REV_SIZE;
		pxThis->ucSizeBoardSerial        = EEPROM_V3_1_BOARD_SERIAL_SIZE;
		pxThis->ucSizeumMacIds           = EEPROM_V3_1_BOARD_TOT_MAC_ID_SIZE;
		pxThis->ucSizeBoardMac           = EEPROM_V3_1_BOARD_MAC_SIZE;
		pxThis->ucSizeBoardActivePassive = EEPROM_V3_1_BOARD_ACT_PAS_SIZE;
		pxThis->ucSizeBoardConfigMode    = EEPROM_V3_1_BOARD_CONFIG_MODE_SIZE;
		pxThis->ucSizeBoardMfgDate       = EEPROM_V3_1_MFG_DATE_SIZE;
		pxThis->ucSizeBoardPartNum       = EEPROM_V3_1_PART_NUM_SIZE;
		pxThis->ucSizeBoardUuid          = EEPROM_V3_1_UUID_SIZE;
		pxThis->ucSizeMfgPartNum         = EEPROM_FIELD_NA_SIZE;
		pxThis->ucSizeBoardPcieInfo      = EEPROM_V3_1_PCIE_INFO_SIZE;
		pxThis->ucSizeBoardMaxPowerMode  = EEPROM_V3_1_MAX_POWER_MODE_SIZE;
		pxThis->ucSizeMemorySize         = EEPROM_V3_1_MEM_SIZE_SIZE;
		pxThis->ucSizeOemId              = EEPROM_V3_1_OEMID_SIZE;
		pxThis->ucSizeCapability         = EEPROM_V3_1_CAPABILITY_SIZE;

		pxThis->ucOffsetEepromVersion      = EEPROM_VERSION_OFFSET;
		pxThis->ucOffsetProductName        = EEPROM_V3_1_PRODUCT_NAME_OFFSET;
		pxThis->ucOffsetBoardRev           = EEPROM_V3_1_BOARD_REV_OFFSET;
		pxThis->ucOffsetBoardSerial        = EEPROM_V3_1_BOARD_SERIAL_OFFSET;
		pxThis->ucOffsetumMacIds           = EEPROM_V3_1_BOARD_TOT_MAC_ID_OFFSET;
		pxThis->ucOffsetBoardMac           = EEPROM_V3_1_BOARD_MAC_OFFSET;
		pxThis->ucOffsetBoardActivePassive = EEPROM_V3_1_BOARD_ACT_PAS_OFFSET;
		pxThis->ucOffsetBoardConfigMode    = EEPROM_V3_1_BOARD_CONFIG_MODE_OFFSET;
		pxThis->ucOffsetBoardMfgDate       = EEPROM_V3_1_MFG_DATE_OFFSET;
		pxThis->ucOffsetBoardPartNum       = EEPROM_V3_1_PART_NUM_OFFSET;
		pxThis->ucOffsetBoardUuid          = EEPROM_V3_1_UUID_OFFSET;
		pxThis->ucOffsetBoardPcieInfo      = EEPROM_V3_1_PCIE_INFO_OFFSET;
		pxThis->ucOffsetBoardMaxPowerMode  = EEPROM_V3_1_MAX_POWER_MODE_OFFSET;
		pxThis->ucOffsetMemorySize         = EEPROM_V3_1_MEM_SIZE_OFFSET;
		pxThis->ucOffsetOemId              = EEPROM_V3_1_OEMID_OFFSET;
		pxThis->ucOffsetCapability         = EEPROM_V3_1_CAPABILITY_OFFSET;

		pxThis->ucOffsetChecksumLsb = EEPROM_V3_1_CHECKSUM_LSB_OFFSET;
		pxThis->ucOffsetChecksumMsb = EEPROM_V3_1_CHECKSUM_MSB_OFFSET;
		pxThis->ucChecksumStart     = EEPROM_V3_1_CHECKSUM_START;
		pxThis->ucChecksumEnd       = EEPROM_V3_1_CHECKSUM_END;
	}
	else if( EEPROM_VERSION_3_0 == xVersion )
	{
		pxThis->pucEepromVersion      = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucEepromVersion );
		pxThis->pucProductName        = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucProductName );
		pxThis->pucBoardRev           = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardRev );
		pxThis->pucBoardSerial        = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardSerial );
		pxThis->ucNumMacIds           = ( pxThis->xBoardInfo.xBoardInfoV3_0.ucNumMacIds );
		pxThis->pucBoardMac           = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardMac );
		pxThis->pucBoardActivePassive = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardActivePassive );
		pxThis->pucBoardConfigMode    = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardConfigMode );
		pxThis->pucBoardMfgDate       = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardMfgDate );
		pxThis->pucBoardPartNum       = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoarPartNum );
		pxThis->pucBoardUuid          = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardUuid );
		pxThis->pucBoardPcieInfo      = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardPcieInfo );
		pxThis->pucBoardMaxPowerMode  = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardMaxPowerMode );
		pxThis->pucMemorySize         = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucMemorySize );
		pxThis->pucOemId              = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucOemId );
		pxThis->pucCapability         = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucCapability );

		pxThis->ucSizeEepromVersion      = EEPROM_VERSION_SIZE;
		pxThis->ucSizeProductName        = EEPROM_V3_0_PRODUCT_NAME_SIZE;
		pxThis->ucSizeBoardRev           = EEPROM_V3_0_BOARD_REV_SIZE;
		pxThis->ucSizeBoardSerial        = EEPROM_V3_0_BOARD_SERIAL_SIZE;
		pxThis->ucSizeumMacIds           = EEPROM_V3_0_BOARD_TOT_MAC_ID_SIZE;
		pxThis->ucSizeBoardMac           = EEPROM_V3_0_BOARD_MAC_SIZE;
		pxThis->ucSizeBoardActivePassive = EEPROM_V3_0_BOARD_ACT_PAS_SIZE;
		pxThis->ucSizeBoardConfigMode    = EEPROM_V3_0_BOARD_CONFIG_MODE_SIZE;
		pxThis->ucSizeBoardMfgDate       = EEPROM_V3_0_MFG_DATE_SIZE;
		pxThis->ucSizeBoardPartNum       = EEPROM_V3_0_PART_NUM_SIZE;
		pxThis->ucSizeBoardUuid          = EEPROM_V3_0_UUID_SIZE;
		pxThis->ucSizeMfgPartNum         = EEPROM_FIELD_NA_SIZE;
		pxThis->ucSizeBoardPcieInfo      = EEPROM_V3_0_PCIE_INFO_SIZE;
		pxThis->ucSizeBoardMaxPowerMode  = EEPROM_V3_0_MAX_POWER_MODE_SIZE;
		pxThis->ucSizeMemorySize         = EEPROM_V3_0_MEM_SIZE_SIZE;
		pxThis->ucSizeOemId              = EEPROM_V3_0_OEMID_SIZE;
		pxThis->ucSizeCapability         = EEPROM_V3_0_CAPABILITY_SIZE;

		pxThis->ucOffsetEepromVersion      = EEPROM_VERSION_OFFSET;
		pxThis->ucOffsetProductName        = EEPROM_V3_0_PRODUCT_NAME_OFFSET;
		pxThis->ucOffsetBoardRev           = EEPROM_V3_0_BOARD_REV_OFFSET;
		pxThis->ucOffsetBoardSerial        = EEPROM_V3_0_BOARD_SERIAL_OFFSET;
		pxThis->ucOffsetumMacIds           = EEPROM_V3_0_BOARD_TOT_MAC_ID_OFFSET;
		pxThis->ucOffsetBoardMac           = EEPROM_V3_0_BOARD_MAC_OFFSET;
		pxThis->ucOffsetBoardActivePassive = EEPROM_V3_0_BOARD_ACT_PAS_OFFSET;
		pxThis->ucOffsetBoardConfigMode    = EEPROM_V3_0_BOARD_CONFIG_MODE_OFFSET;
		pxThis->ucOffsetBoardMfgDate       = EEPROM_V3_0_MFG_DATE_OFFSET;
		pxThis->ucOffsetBoardPartNum       = EEPROM_V3_0_PART_NUM_OFFSET;
		pxThis->ucOffsetBoardUuid          = EEPROM_V3_0_UUID_OFFSET;
		pxThis->ucOffsetBoardPcieInfo      = EEPROM_V3_0_PCIE_INFO_OFFSET;
		pxThis->ucOffsetBoardMaxPowerMode  = EEPROM_V3_0_MAX_POWER_MODE_OFFSET;
		pxThis->ucOffsetMemorySize         = EEPROM_V3_0_MEM_SIZE_OFFSET;
		pxThis->ucOffsetOemId              = EEPROM_V3_0_OEMID_OFFSET;
		pxThis->ucOffsetCapability         = EEPROM_V3_0_CAPABILITY_OFFSET;

		pxThis->ucOffsetChecksumLsb = EEPROM_V3_0_CHECKSUM_LSB_OFFSET;
		pxThis->ucOffsetChecksumMsb = EEPROM_V3_0_CHECKSUM_MSB_OFFSET;
		pxThis->ucChecksumStart     = EEPROM_V3_0_CHECKSUM_START;
		pxThis->ucChecksumEnd       = EEPROM_V3_0_CHECKSUM_END;
	}
}

/**
 * @brief   Verify that the checksum for the EEPROM fields is correct
 */
static int iEepromVerifyChecksum( void )
{
	int iStatus                    = ERROR;
	unsigned char pucData[ EEPROM_BUF_SIZE ] =
	{
		0
	};
	uint8_t ucAddressOffset      = 0;
	int i                    = 0;
	uint16_t usCalculatedChecksum = 0;
	uint16_t usExpectedChecksum   = 0;

	iStatus = ucEepromReadMultiBytes( ucAddressOffset, &pucData[ i ], EEPROM_BUF_SIZE );
	if( OK == iStatus )
	{
		usExpectedChecksum = ( ( pucData[ pxThis->ucOffsetChecksumMsb ] <<
		                         8 ) | pucData[ pxThis->ucOffsetChecksumLsb ] );

		for( i = pxThis->ucChecksumStart; i <= pxThis->ucChecksumEnd; ++i )
		{
			usCalculatedChecksum += ( uint16_t ) pucData[ i ];
		}

		usCalculatedChecksum = ( ( uint16_t )0 - usCalculatedChecksum );

		if( usCalculatedChecksum != usExpectedChecksum )
		{
			iStatus = ERROR;
			INC_ERROR_COUNTER( EEPROM_ERROR_CHECKSUM );
		}
		else
		{
			INC_STAT_COUNTER( EEPROM_STATS_CHECKSUM );
		}
	}

	return iStatus;
}

/**
 * @brief   Verify the device ID of EEPROM
 */
static int iEeprom_VerifyDeviceId( void )
{
	int iStatus = ERROR;
	uint8_t pucWriteBuf[ EEPROM_WRITE_MULTI_BYTE_SIZE_MAX ] =
	{
		0
	};
	uint8_t pucReadBuf[ EEPROM_2_BYTE_ADDRESS ] =
	{
		0
	};
	uint16_t usDeviceId = 0;

	if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
	    ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
	{
		int i = 0;

		pucWriteBuf[ 0 ] = pxThis->xEepromCfg.ucEepromDeviceIdRegister;
		for( i = 0; i < EEPROM_DEVICE_ID_CHECK_TRY_COUNT; i++ )
		{
			iStatus = iI2C_SendRecv( pxThis->xEepromCfg.ucEepromI2cBus,
			                         pxThis->xEepromCfg.ucEepromDeviceIdAddress,
			                         pucWriteBuf,
			                         1,
			                         &pucReadBuf[ 0 ],
			                         EEPROM_2_BYTE_ADDRESS );
			if( ERROR == iStatus )
			{
				INC_ERROR_COUNTER( EEPROM_ERRORS_DEVICE_ID_READ );
			}
			else
			{
				usDeviceId = ( pucReadBuf[ 0 ] << 8 ) | pucReadBuf[ 1 ];
				if( pxThis->xEepromCfg.usEepromDeviceId == usDeviceId )
				{
					INC_STAT_COUNTER( EEPROM_STATS_VERIFY_DEVICE_ID );
					break;
				}
				else
				{
					INC_ERROR_COUNTER( EEPROM_ERRORS_VERIFY_DEVICE_ID );
				}
			}
		}
	}
	else
	{
		INC_ERROR_COUNTER( EEPROM_ERROR_VALIDATION );
	}

	return iStatus;
}

/**
 * @brief   Dump out all the EEPROM contents
 */
#ifdef EEPROM_VERBOSE_DEBUG_ENABLE
static int iEepromDumpContents( void )
{
	uint8_t pucDataBuff[ pxThis->xEepromCfg.ucEepromPageSize ] =
	{
		0
	};
	int iStatus = ERROR;
	int iPageId = 0;
	int i       = 0;

	for( iPageId = 0; iPageId < pxThis->xEepromCfg.ucEepromNumPages; iPageId++ )
	{
		iStatus = iEEPROM_ReadRawValue( pucDataBuff,
		                                pxThis->xEepromCfg.ucEepromPageSize,
		                                ( pxThis->xEepromCfg.ucEepromPageSize * iPageId ) );
		if( OK == iStatus )
		{
			for( i = 0; i < pxThis->xEepromCfg.ucEepromPageSize; i++ )
			{
				if( 0 == ( i % pxThis->xEepromCfg.ucEepromPageSize ) )
				{
					if( 0 != i )
					{
						vPLL_Printf( "\r\n" );
					}
					vPLL_Printf( "\t[ 0x%04X ]. . . . . :", ( iPageId * pxThis->xEepromCfg.ucEepromPageSize ) );
				}
				vPLL_Printf( " %02X", pucDataBuff[ i ] );
			}
		}

		vPLL_Printf( "\r\n" );
	}

	return ( iStatus );
}
#endif
