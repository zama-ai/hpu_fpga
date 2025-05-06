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


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define EEPROM_ASCII_VAR( x )                    ( ( x ) + 1 )
#define EEPROM_NAME                              "EEPROM"
#define EEPROM_2_BYTE_ADDRESS                    ( 2 )
#define EEPROM_ADDRESS_SIZE_UNINITIALISED        ( 0 )
#define EEPROM_WRITE_DELAY_MS                    ( 10 )
#define EEPROM_ADDRESS_BYTE_ZERO                 ( 0 )
#define EEPROM_ADDRESS_BYTE_ONE                  ( 1 )
#define EEPROM_DATA_SINGLE_BYTE                  ( 1 )
#define EEPROM_ONE_BYTE                          ( 1 )
#define EEPROM_TWO_BYTES                         ( 2 )
#define UPPER_FIREWALL                           ( 0xBABECAFE )
#define LOWER_FIREWALL                           ( 0xDEADFACE )
     
#define EEPROM_MAX_MAC                           ( 40 )
#define EEPROM_PAGE_SIZE_MAX                     ( 255 )
#define EEPROM_ADDRESS_SIZE_MAX                  ( 255 )
#define EEPROM_WRITE_MULTI_BYTE_SIZE_MAX         ( 255 )
#define EEPROM_WRITE_BYTE_SIZE_MAX               ( 255 )
     
/* Default register content in EEPROM if a particular register has not been programmed */
#define EEPROM_DEFAULT_VAL                       ( 0xFF )
#define EEPROM_VERSION_SIZE                      ( 4 )
#define EEPROM_BUF_SIZE                          ( 128 )
#define EEPROM_FIELD_NA_SIZE                     ( 0 )  /* For non-existent fields */
#define EEPROM_DEVICE_ID_CHECK_TRY_COUNT         ( 3 )
     
/* Version 4.0 field positions */
#define EEPROM_V4_0_ALVEO_PRODUCT_NAME_SIZE      ( 36 )
#define EEPROM_V4_0_ALVEO_PART_NUM_SIZE          ( 24 )
#define EEPROM_V4_0_MFG_ALVEO_PART_NUM_SIZE      ( 16 )
#define EEPROM_V4_0_MFG_ALVEO_PART_REV_SIZE      ( 5 )
#define EEPROM_V4_0_PRODUCT_SERIAL_SIZE          ( 14 )
#define EEPROM_V4_0_MFG_DATE_SIZE                ( 4 )
#define EEPROM_V4_0_TOT_MAC_ID_SIZE              ( 1 )
#define EEPROM_V4_0_MAC_SIZE                     ( 6 )
#define EEPROM_V4_0_UUID_SIZE                    ( 16 )
#define EEPROM_V4_0_CHECKSUM_START               ( 6 )
#define EEPROM_V4_0_CHECKSUM_END                 ( 127 )

/* Version 3.1 field positions */
#define EEPROM_V3_1_PRODUCT_NAME_SIZE            ( 24 )
#define EEPROM_V3_1_BOARD_REV_SIZE               ( 8 )
#define EEPROM_V3_1_BOARD_SERIAL_SIZE            ( 14 )
#define EEPROM_V3_1_BOARD_TOT_MAC_ID_SIZE        ( 1 )
#define EEPROM_V3_1_BOARD_MAC_SIZE               ( 6 )
#define EEPROM_V3_1_BOARD_ACT_PAS_SIZE           ( 1 )
#define EEPROM_V3_1_BOARD_CONFIG_MODE_SIZE       ( 1 )
#define EEPROM_V3_1_MFG_DATE_SIZE                ( 3 )
#define EEPROM_V3_1_PART_NUM_SIZE                ( 24 )
#define EEPROM_V3_1_UUID_SIZE                    ( 16 )
#define EEPROM_V3_1_PCIE_INFO_SIZE               ( 8 )
#define EEPROM_V3_1_MAX_POWER_MODE_SIZE          ( 1 )
#define EEPROM_V3_1_MEM_SIZE_SIZE                ( 4 )
#define EEPROM_V3_1_OEMID_SIZE                   ( 4 )
#define EEPROM_V3_1_CAPABILITY_SIZE              ( 2 )
#define EEPROM_V3_1_CHECKSUM_START               ( 8 )
#define EEPROM_V3_1_CHECKSUM_END                 ( 124 )

/* Version 3.0 field positions */
#define EEPROM_V3_0_PRODUCT_NAME_SIZE            ( 24 )
#define EEPROM_V3_0_BOARD_REV_SIZE               ( 8 )
#define EEPROM_V3_0_BOARD_SERIAL_SIZE            ( 14 )
#define EEPROM_V3_0_BOARD_TOT_MAC_ID_SIZE        ( 1 )
#define EEPROM_V3_0_BOARD_MAC_SIZE               ( 6 )
#define EEPROM_V3_0_BOARD_ACT_PAS_SIZE           ( 1 )
#define EEPROM_V3_0_BOARD_CONFIG_MODE_SIZE       ( 1 )
#define EEPROM_V3_0_MFG_DATE_SIZE                ( 3 )
#define EEPROM_V3_0_PART_NUM_SIZE                ( 24 )
#define EEPROM_V3_0_UUID_SIZE                    ( 16 )
#define EEPROM_V3_0_PCIE_INFO_SIZE               ( 8 )
#define EEPROM_V3_0_MAX_POWER_MODE_SIZE          ( 1 )
#define EEPROM_V3_0_MEM_SIZE_SIZE                ( 4 )
#define EEPROM_V3_0_OEMID_SIZE                   ( 4 )
#define EEPROM_V3_0_CAPABILITY_SIZE              ( 2 )
#define EEPROM_V3_0_CHECKSUM_START               ( 8 )
#define EEPROM_V3_0_CHECKSUM_END                 ( 124 )

/* Eeprom Stub defines */
#define EEPROM_STUB_VERSION                      "Stb"
#define EEPROM_STUB_PRODUCT_NAME                 "Product Name Stub"
#define EEPROM_STUB_BOARD_REV                    "Stb"
#define EEPROM_STUB_BOARD_SERIAL                 "Serial Stub"
#define EEPROM_STUB_BOARD_PART_NUM               "Part Num Stub"

STATIC_ASSERT( EEPROM_VERSION_SIZE < EEPROM_MAX_FIELD_SIZE);

STATIC_ASSERT( EEPROM_V4_0_ALVEO_PRODUCT_NAME_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V4_0_ALVEO_PART_NUM_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V4_0_MFG_ALVEO_PART_NUM_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V4_0_MFG_ALVEO_PART_REV_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V4_0_PRODUCT_SERIAL_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V4_0_MFG_DATE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V4_0_TOT_MAC_ID_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V4_0_MAC_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V4_0_UUID_SIZE < EEPROM_MAX_FIELD_SIZE);

STATIC_ASSERT( EEPROM_V3_0_PRODUCT_NAME_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_REV_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_SERIAL_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_TOT_MAC_ID_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_MAC_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_ACT_PAS_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_CONFIG_MODE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_MFG_DATE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_PART_NUM_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_UUID_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_PCIE_INFO_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_MAX_POWER_MODE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_MEM_SIZE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_OEMID_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_CAPABILITY_SIZE < EEPROM_MAX_FIELD_SIZE);

STATIC_ASSERT( EEPROM_V3_0_PRODUCT_NAME_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_REV_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_SERIAL_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_TOT_MAC_ID_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_MAC_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_ACT_PAS_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_BOARD_CONFIG_MODE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_MFG_DATE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_PART_NUM_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_UUID_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_PCIE_INFO_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_MAX_POWER_MODE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_MEM_SIZE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_OEMID_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_0_CAPABILITY_SIZE < EEPROM_MAX_FIELD_SIZE);

STATIC_ASSERT( EEPROM_V3_1_PRODUCT_NAME_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_BOARD_REV_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_BOARD_SERIAL_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_BOARD_TOT_MAC_ID_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_BOARD_MAC_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_BOARD_ACT_PAS_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_BOARD_CONFIG_MODE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_MFG_DATE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_PART_NUM_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_UUID_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_PCIE_INFO_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_MAX_POWER_MODE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_MEM_SIZE_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_OEMID_SIZE < EEPROM_MAX_FIELD_SIZE);
STATIC_ASSERT( EEPROM_V3_1_CAPABILITY_SIZE < EEPROM_MAX_FIELD_SIZE);

#define EEPROM_STATS( DO )              \
    DO( EEPROM_STATS_INITIALISATION )   \
    DO( EEPROM_STATS_CHECKSUM )         \
    DO( EEPROM_STATS_READ_FIELD )       \
    DO( EEPROM_STAT_SINGLE_BYTE_READ )  \
    DO( EEPROM_STAT_MULTI_BYTE_READ )   \
    DO( EEPROM_STAT_SINGLE_BYTE_WRITE ) \
    DO( EEPROM_STAT_MULTI_BYTE_WRITE )  \
    DO( EEPROM_STATS_VERIFY_DEVICE_ID ) \
    DO( EEPROM_STATS_MAX )

#define EEPROM_ERROR( DO )               \
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

#define PRINT_STAT( x )       PLL_INF( EEPROM_NAME, "%30s. . . .%d\r\n", EEPROM_STATS_STR[ x ], pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_STAT( x ) PLL_INF( EEPROM_NAME, "%30s. . . .%d\r\n", EEPROM_ERROR_STR[ x ], pxThis->pulStatErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )               { if( x < EEPROM_STATS_MAX )pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x )              { if( x < EEPROM_ERROR_MAX )pxThis->pulStatErrorCounters[ x ]++; }


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
    uint8_t ucPartNumber[ EEPROM_ASCII_VAR( EEPROM_V4_0_ALVEO_PART_NUM_SIZE ) ];
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
    uint8_t ucEepromVersion [ EEPROM_ASCII_VAR( EEPROM_VERSION_SIZE ) ];
    uint8_t ucProductName [ EEPROM_ASCII_VAR( EEPROM_V3_0_PRODUCT_NAME_SIZE ) ];
    uint8_t ucBoardRev [ EEPROM_ASCII_VAR( EEPROM_V3_0_BOARD_REV_SIZE ) ];
    uint8_t ucBoardSerial [ EEPROM_ASCII_VAR( EEPROM_V3_0_BOARD_SERIAL_SIZE ) ];
    uint8_t ucNumMacIds;
    uint8_t ucBoardMac [ EEPROM_ASCII_VAR( EEPROM_V3_0_BOARD_MAC_SIZE ) ];
    uint8_t ucBoardActivePassive [ EEPROM_ASCII_VAR( EEPROM_V3_0_BOARD_ACT_PAS_SIZE ) ];
    uint8_t ucBoardConfigMode [ EEPROM_ASCII_VAR( EEPROM_V3_0_BOARD_CONFIG_MODE_SIZE ) ];
    uint8_t ucBoardMfgDate [ EEPROM_ASCII_VAR( EEPROM_V3_0_MFG_DATE_SIZE ) ];
    uint8_t ucBoarPartNum [ EEPROM_ASCII_VAR( EEPROM_V3_0_PART_NUM_SIZE ) ];
    uint8_t ucBoardUuid [ EEPROM_ASCII_VAR( EEPROM_V3_0_UUID_SIZE ) ];
    uint8_t ucBoardPcieInfo [ EEPROM_ASCII_VAR( EEPROM_V3_0_PCIE_INFO_SIZE ) ];
    uint8_t ucBoardMaxPowerMode [ EEPROM_ASCII_VAR( EEPROM_V3_0_MAX_POWER_MODE_SIZE ) ];
    uint8_t ucMemorySize [ EEPROM_ASCII_VAR( EEPROM_V3_0_MEM_SIZE_SIZE ) ];
    uint8_t ucOemId [ EEPROM_ASCII_VAR( EEPROM_V3_0_OEMID_SIZE ) ];
    uint8_t ucCapability [ EEPROM_ASCII_VAR( EEPROM_V3_0_CAPABILITY_SIZE ) ];

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
    uint32_t                ulUpperFirewall;
    int                     iEepromInitialised;
    EEPROM_CFG              xEepromCfg;
    EEPROM_VERSION          xEepromExpectedVersion;
    EEPROM_VERSION          xEepromActualVersion;
    union EEPROM_BOARDINFO  xBoardInfo;
    uint8_t*                pucEepromVersion;
    uint8_t*                pucProductName;
    uint8_t*                pucBoardRev;
    uint8_t*                pucBoardSerial;
    uint8_t                 ucNumMacIds;
    uint8_t*                pucBoardMac;
    uint8_t*                pucBoardActivePassive;
    uint8_t*                pucBoardConfigMode;
    uint8_t*                pucBoardMfgDate;
    uint8_t*                pucBoardPartNum;
    uint8_t*                pucBoardUuid;
    uint8_t*                pucBoardPcieInfo;
    uint8_t*                pucBoardMaxPowerMode;
    uint8_t*                pucMemorySize;
    uint8_t*                pucOemId;
    uint8_t*                pucCapability;
    uint8_t*                pucMfgPartNum;

    uint8_t                 ucSizeEepromVersion;
    uint8_t                 ucSizeProductName;
    uint8_t                 ucSizeBoardRev;
    uint8_t                 ucSizeBoardSerial;
    uint8_t                 ucSizeumMacIds;
    uint8_t                 ucSizeBoardMac;
    uint8_t                 ucSizeBoardActivePassive;
    uint8_t                 ucSizeBoardConfigMode;
    uint8_t                 ucSizeBoardMfgDate;
    uint8_t                 ucSizeBoardPartNum;
    uint8_t                 ucSizeBoardUuid;
    uint8_t                 ucSizeBoardPcieInfo;
    uint8_t                 ucSizeBoardMaxPowerMode;
    uint8_t                 ucSizeMemorySize;
    uint8_t                 ucSizeOemId;
    uint8_t                 ucSizeCapability;
    uint8_t                 ucSizeMfgPartNum;

    uint8_t                 ucOffsetEepromVersion;
    uint8_t                 ucOffsetProductName;
    uint8_t                 ucOffsetBoardRev;
    uint8_t                 ucOffsetBoardSerial;
    uint8_t                 ucOffsetumMacIds;
    uint8_t                 ucOffsetBoardMac;
    uint8_t                 ucOffsetBoardActivePassive;
    uint8_t                 ucOffsetBoardConfigMode;
    uint8_t                 ucOffsetBoardMfgDate;
    uint8_t                 ucOffsetBoardPartNum;
    uint8_t                 ucOffsetBoardUuid;
    uint8_t                 ucOffsetBoardPcieInfo;
    uint8_t                 ucOffsetBoardMaxPowerMode;
    uint8_t                 ucOffsetMemorySize;
    uint8_t                 ucOffsetOemId;
    uint8_t                 ucOffsetCapability;
    uint8_t                 ucOffsetMfgPartNum;

    uint8_t                 ucOffsetChecksumLsb;
    uint8_t                 ucOffsetChecksumMsb;
    uint8_t                 ucChecksumStart;
    uint8_t                 ucChecksumEnd;

    uint32_t                pulStatCounters[ EEPROM_STATS_MAX ];
    uint32_t                pulStatErrorCounters[ EEPROM_ERROR_MAX ];

    uint32_t                ulLowerFirewall;

} EEPROM_PRIVATE_DATA;


/******************************************************************************/
/* Local Variables                                                            */
/******************************************************************************/

static EEPROM_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                     /* ulUpperFirewall       */
    FALSE,                              /* iEepromInitialised    */
    { 0 },                              /* xEepromCfg            */
    EEPROM_VERSION_MAX,                 /* xEepromExpectedVersion*/
    EEPROM_VERSION_MAX,                 /* xEepromActualVersion  */
    { { { 0 } } },                      /* xBoardInfo            */
    NULL,                               /* pucEepromVersion      */
    NULL,                               /* pucProductName        */
    NULL,                               /* pucBoardRev           */
    NULL,                               /* pucBoardSerial        */
    0,                                  /* ucNumMacIds           */
    NULL,                               /* pucBoardMac           */
    NULL,                               /* pucBoardActivePassive */
    NULL,                               /* pucBoardConfigMode    */
    NULL,                               /* pucBoardMfgDate       */
    NULL,                               /* pucBoardPartNum       */
    NULL,                               /* pucBoardUuid          */
    NULL,                               /* pucBoardPcieInfo      */
    NULL,                               /* pucBoardMaxPowerMode  */
    NULL,                               /* pucMemorySize         */
    NULL,                               /* pucOemId              */
    NULL,                               /* pucCapability         */
    NULL,                               /* pucMfgPartNum         */

    0,                                  /* ucSizeEepromVersion       */
    0,                                  /* ucSizeProductName         */
    0,                                  /* ucSizeBoardRev            */
    0,                                  /* ucSizeBoardSerial         */
    0,                                  /* cNSizeumMacIds            */
    0,                                  /* ucSizeBoardMac            */
    0,                                  /* ucSizeBoardActivePassive  */
    0,                                  /* ucSizeBoardConfigMode     */
    0,                                  /* ucSizeBoardMfgDate        */
    0,                                  /* ucSizeBoardPartNum        */
    0,                                  /* ucSizeBoardUuid           */
    0,                                  /* ucSizeBoardPcieInfo       */
    0,                                  /* ucSizeBoardMaxPowerMode   */
    0,                                  /* ucSizeMemorySize          */
    0,                                  /* ucSizeOemId               */
    0,                                  /* ucSizeCapability          */
    0,                                  /* ucSizeMfgPartNum          */

    0,                                  /* ucOffsetEepromVersion       */
    0,                                  /* ucOffsetProductName         */
    0,                                  /* ucOffsetBoardRev            */
    0,                                  /* ucOffsetBoardSerial         */
    0,                                  /* cNOffsetumMacIds            */
    0,                                  /* ucOffsetBoardMac            */
    0,                                  /* ucOffsetBoardActivePassive  */
    0,                                  /* ucOffsetBoardConfigMode     */
    0,                                  /* ucOffsetBoardMfgDate        */
    0,                                  /* ucOffsetBoardPartNum        */
    0,                                  /* ucOffsetBoardUuid           */
    0,                                  /* ucOffsetBoardPcieInfo       */
    0,                                  /* ucOffsetBoardMaxPowerMode   */
    0,                                  /* ucOffsetMemorySize          */
    0,                                  /* ucOffsetOemId               */
    0,                                  /* ucOffsetCapability          */
    0,                                  /* ucOffsetMfgPartNum          */

    0,                                  /* ucOffsetChecksumLsb         */
    0,                                  /* ucOffsetChecksumMsb         */
    0,                                  /* ucChecksumStart             */
    0,                                  /* ucChecksumEnd               */

    { 0 },                              /* pulStatCounters[ EEPROM_STATS_MAX ]      */
    { 0 },                              /* pulStatErrorCounters[ EEPROM_ERROR_MAX ] */

    LOWER_FIREWALL     /* ulLowerFirewall             */
};

static EEPROM_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Private Function declarations                                              */
/******************************************************************************/

/*
 * @brief   Point the fields to the required  EEPROM version
 *
 * @param   xVersion            Version of EEPROM data
 *
 * @return  N/A
 */
static void vEepromInitialiseVersionFields( EEPROM_VERSION xVersion );

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
        ( ( uint16_t ) EEPROM_WRITE_MULTI_BYTE_SIZE_MAX >= ( uint16_t ) ( pxEepromCfg->ucEepromAddressSize + pxEepromCfg->ucEepromPageSize ) ))
    {
        pvOSAL_MemCpy( &pxThis->xEepromCfg, pxEepromCfg, sizeof( pxThis->xEepromCfg ) );
        pxThis->iEepromInitialised = TRUE;
        iStatus = OK;

        /* Initialize Eeprom Version Fields with predefined values*/
        vEepromInitialiseVersionFields( xEepromVersion );
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        iStatus = OK;
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
        pvOSAL_MemCpy( pucField, pxThis->pucOemId, pxThis->ucSizeOemId);
        *pucSizeBytes = pxThis->ucSizeOemId;
        iStatus = OK;
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
        iStatus = OK;
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
        ( EEPROM_MAX_DATA_SIZE >= ucSizeBytes) )
    {
        iStatus = OK;

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
        PLL_INF( EEPROM_NAME, "======================================\n\r");
        PLL_INF( EEPROM_NAME, "Statistics:\n\r");
        for( i = 0; i < EEPROM_STATS_MAX; i++ )
        {
            PRINT_STAT( i );
        }
        PLL_INF( EEPROM_NAME, "--------------------------------------\n\r");
        PLL_INF( EEPROM_NAME, "Errors:\n\r");
        for( i = 0; i < EEPROM_ERROR_MAX; i++ )
        {
            PRINT_ERROR_STAT( i );
        }
        PLL_INF( EEPROM_NAME, "======================================\n\r");
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

        PLL_INF( EEPROM_NAME, "EEPROM Version        : %s\n\r",
                 pxThis->pucEepromVersion );
        PLL_INF( EEPROM_NAME, "product name          : %s\n\r",
                 pxThis->pucProductName );
        PLL_INF( EEPROM_NAME, "board rev             : %s\n\r",
                 pxThis->pucBoardRev );
        PLL_INF( EEPROM_NAME, "board serial          : %s\n\r",
                 pxThis->pucBoardSerial );
        PLL_INF( EEPROM_NAME, "# MACS                : %d\n\r",
                 pxThis->ucNumMacIds );
        PLL_INF( EEPROM_NAME, "1st MAC               : %02x:%02x:%02x:%02x:%02x:%02x\n\r",
                 pxThis->pucBoardMac[ 0 ],
                 pxThis->pucBoardMac[ 1 ],
                 pxThis->pucBoardMac[ 2 ],
                 pxThis->pucBoardMac[ 3 ],
                 pxThis->pucBoardMac[ 4 ],
                 pxThis->pucBoardMac[ 5 ] );
        PLL_INF( EEPROM_NAME, "MFG DATE              : %02x%02x%02x\n\r",
                 pxThis->pucBoardMfgDate[ 0 ],
                 pxThis->pucBoardMfgDate[ 1 ],
                 pxThis->pucBoardMfgDate[ 2 ] );
        PLL_INF( EEPROM_NAME, "board part num        : %s\n\r",
                 pxThis->pucBoardPartNum );
        PLL_INF( EEPROM_NAME, "UUID                  : %02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x\n\r",
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
        if( ( EEPROM_VERSION_3_0 == pxThis->xEepromActualVersion ) || ( EEPROM_VERSION_3_1 == pxThis->xEepromActualVersion ) )
        {
            PLL_INF( EEPROM_NAME, "board A/P             : %s\n\r",
                     pxThis->pucBoardActivePassive );
            PLL_INF( EEPROM_NAME, "board config mode     : %02x\n\r",
                     pxThis->pucBoardConfigMode[ 0 ] );
            PLL_INF( EEPROM_NAME, "PCIe Info             : %02x%02x, %02x%02x, %02x%02x, %02x%02x\n\r",
                     pxThis->pucBoardPcieInfo[ 0 ],
                     pxThis->pucBoardPcieInfo[ 1 ],
                     pxThis->pucBoardPcieInfo[ 2 ],
                     pxThis->pucBoardPcieInfo[ 3 ],
                     pxThis->pucBoardPcieInfo[ 4 ],
                     pxThis->pucBoardPcieInfo[ 5 ],
                     pxThis->pucBoardPcieInfo[ 6 ],
                     pxThis->pucBoardPcieInfo[ 7 ] );
            PLL_INF( EEPROM_NAME, "board max power mode  : %d\n\r",
                     pxThis->pucBoardMaxPowerMode[ 0 ] );
            PLL_INF( EEPROM_NAME, "Memory Size           : %s\n\r",
                     pxThis->pucMemorySize        );
            PLL_INF( EEPROM_NAME, "OEM ID                : %02x%02x%02x%02x\n\r",
                     pxThis->pucOemId[ 3 ],
                     pxThis->pucOemId[ 2 ],
                     pxThis->pucOemId[ 1 ],
                     pxThis->pucOemId[ 0 ] );
            PLL_INF( EEPROM_NAME, "Capability            : %02x%02x\n\r",
                     pxThis->pucCapability[ 1 ],
                     pxThis->pucCapability[ 0 ] );
        }
        else if( EEPROM_VERSION_4_0 == pxThis->xEepromActualVersion )
        {
            PLL_INF( EEPROM_NAME, "MFG part number       : %s\n\r", pxThis->pucMfgPartNum );
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
 * @brief   Point the fields to the required  EEPROM version
 */
static void vEepromInitialiseVersionFields( EEPROM_VERSION xVersion )
{
    if( EEPROM_VERSION_4_0 == xVersion )
    {
        pxThis->pucEepromVersion            = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucEepromVersion );
        pxThis->pucProductName              = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucProductName );
        pxThis->pucBoardPartNum             = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucPartNumber );
        pxThis->pucMfgPartNum               = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucMfgPartNumber );
        pxThis->pucBoardRev                 = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucMfgPartRevision );
        pxThis->pucBoardSerial              = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucProductSerial );
        pxThis->pucBoardMfgDate             = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucMfgDate );
        pxThis->ucNumMacIds                 =              ( pxThis->xBoardInfo.xBoardInfoV4_0.ucNumMacIds );
        pxThis->pucBoardMac                 = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucMac );
        pxThis->pucBoardUuid                = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV4_0.ucUuid );

        pxThis->ucSizeEepromVersion         = EEPROM_VERSION_SIZE;
        pxThis->ucSizeProductName           = EEPROM_V4_0_ALVEO_PRODUCT_NAME_SIZE;
        pxThis->ucSizeBoardPartNum          = EEPROM_V4_0_ALVEO_PART_NUM_SIZE;
        pxThis->ucSizeBoardRev              = EEPROM_V4_0_MFG_ALVEO_PART_REV_SIZE;
        pxThis->ucSizeBoardSerial           = EEPROM_V4_0_PRODUCT_SERIAL_SIZE;
        pxThis->ucSizeumMacIds              = EEPROM_V4_0_TOT_MAC_ID_SIZE;
        pxThis->ucSizeBoardMac              = EEPROM_V4_0_MAC_SIZE;
        pxThis->ucSizeBoardMfgDate          = EEPROM_V4_0_MFG_DATE_SIZE;
        pxThis->ucSizeBoardUuid             = EEPROM_V4_0_UUID_SIZE;
        pxThis->ucSizeMfgPartNum            = EEPROM_V4_0_MFG_ALVEO_PART_NUM_SIZE;
        pxThis->ucSizeBoardActivePassive    = EEPROM_FIELD_NA_SIZE;
        pxThis->ucSizeBoardConfigMode       = EEPROM_FIELD_NA_SIZE;
        pxThis->ucSizeBoardPcieInfo         = EEPROM_FIELD_NA_SIZE;
        pxThis->ucSizeBoardMaxPowerMode     = EEPROM_FIELD_NA_SIZE;
        pxThis->ucSizeMemorySize            = EEPROM_FIELD_NA_SIZE;
        pxThis->ucSizeOemId                 = EEPROM_FIELD_NA_SIZE;
        pxThis->ucSizeCapability            = EEPROM_FIELD_NA_SIZE;

        pxThis->ucChecksumStart             = EEPROM_V4_0_CHECKSUM_START;
        pxThis->ucChecksumEnd               = EEPROM_V4_0_CHECKSUM_END;
    }
    else if( EEPROM_VERSION_3_1 == xVersion )
    {
        pxThis->pucEepromVersion            = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucEepromVersion );
        pxThis->pucProductName              = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucProductName );
        pxThis->pucBoardRev                 = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardRev );
        pxThis->pucBoardSerial              = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardSerial );
        pxThis->ucNumMacIds                 =              ( pxThis->xBoardInfo.xBoardInfoV3_1.ucNumMacIds );
        pxThis->pucBoardMac                 = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardMac );
        pxThis->pucBoardActivePassive       = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardActivePassive );
        pxThis->pucBoardConfigMode          = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardConfigMode );
        pxThis->pucBoardMfgDate             = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardMfgDate );
        pxThis->pucBoardPartNum             = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoarPartNum );
        pxThis->pucBoardUuid                = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardUuid );
        pxThis->pucBoardPcieInfo            = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardPcieInfo );
        pxThis->pucBoardMaxPowerMode        = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucBoardMaxPowerMode );
        pxThis->pucMemorySize               = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucMemorySize );
        pxThis->pucOemId                    = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucOemId );
        pxThis->pucCapability               = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_1.ucCapability );

        pxThis->ucSizeEepromVersion         = EEPROM_VERSION_SIZE;
        pxThis->ucSizeProductName           = EEPROM_V3_1_PRODUCT_NAME_SIZE;
        pxThis->ucSizeBoardRev              = EEPROM_V3_1_BOARD_REV_SIZE;
        pxThis->ucSizeBoardSerial           = EEPROM_V3_1_BOARD_SERIAL_SIZE;
        pxThis->ucSizeumMacIds              = EEPROM_V3_1_BOARD_TOT_MAC_ID_SIZE;
        pxThis->ucSizeBoardMac              = EEPROM_V3_1_BOARD_MAC_SIZE;
        pxThis->ucSizeBoardActivePassive    = EEPROM_V3_1_BOARD_ACT_PAS_SIZE;
        pxThis->ucSizeBoardConfigMode       = EEPROM_V3_1_BOARD_CONFIG_MODE_SIZE;
        pxThis->ucSizeBoardMfgDate          = EEPROM_V3_1_MFG_DATE_SIZE;
        pxThis->ucSizeBoardPartNum          = EEPROM_V3_1_PART_NUM_SIZE;
        pxThis->ucSizeBoardUuid             = EEPROM_V3_1_UUID_SIZE;
        pxThis->ucSizeMfgPartNum            = EEPROM_FIELD_NA_SIZE;
        pxThis->ucSizeBoardPcieInfo         = EEPROM_V3_1_PCIE_INFO_SIZE;
        pxThis->ucSizeBoardMaxPowerMode     = EEPROM_V3_1_MAX_POWER_MODE_SIZE;
        pxThis->ucSizeMemorySize            = EEPROM_V3_1_MEM_SIZE_SIZE;
        pxThis->ucSizeOemId                 = EEPROM_V3_1_OEMID_SIZE;
        pxThis->ucSizeCapability            = EEPROM_V3_1_CAPABILITY_SIZE;

        pxThis->ucChecksumStart             = EEPROM_V3_1_CHECKSUM_START;
        pxThis->ucChecksumEnd               = EEPROM_V3_1_CHECKSUM_END;
    }
    else if( EEPROM_VERSION_3_0 == xVersion )
    {
        pxThis->pucEepromVersion            = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucEepromVersion );
        pxThis->pucProductName              = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucProductName );
        pxThis->pucBoardRev                 = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardRev );
        pxThis->pucBoardSerial              = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardSerial );
        pxThis->ucNumMacIds                 =              ( pxThis->xBoardInfo.xBoardInfoV3_0.ucNumMacIds );
        pxThis->pucBoardMac                 = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardMac );
        pxThis->pucBoardActivePassive       = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardActivePassive );
        pxThis->pucBoardConfigMode          = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardConfigMode );
        pxThis->pucBoardMfgDate             = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardMfgDate );
        pxThis->pucBoardPartNum             = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoarPartNum );
        pxThis->pucBoardUuid                = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardUuid );
        pxThis->pucBoardPcieInfo            = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardPcieInfo );
        pxThis->pucBoardMaxPowerMode        = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucBoardMaxPowerMode );
        pxThis->pucMemorySize               = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucMemorySize );
        pxThis->pucOemId                    = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucOemId );
        pxThis->pucCapability               = ( uint8_t * )( pxThis->xBoardInfo.xBoardInfoV3_0.ucCapability );

        pxThis->ucSizeEepromVersion         = EEPROM_VERSION_SIZE;
        pxThis->ucSizeProductName           = EEPROM_V3_0_PRODUCT_NAME_SIZE;
        pxThis->ucSizeBoardRev              = EEPROM_V3_0_BOARD_REV_SIZE;
        pxThis->ucSizeBoardSerial           = EEPROM_V3_0_BOARD_SERIAL_SIZE;
        pxThis->ucSizeumMacIds              = EEPROM_V3_0_BOARD_TOT_MAC_ID_SIZE;
        pxThis->ucSizeBoardMac              = EEPROM_V3_0_BOARD_MAC_SIZE;
        pxThis->ucSizeBoardActivePassive    = EEPROM_V3_0_BOARD_ACT_PAS_SIZE;
        pxThis->ucSizeBoardConfigMode       = EEPROM_V3_0_BOARD_CONFIG_MODE_SIZE;
        pxThis->ucSizeBoardMfgDate          = EEPROM_V3_0_MFG_DATE_SIZE;
        pxThis->ucSizeBoardPartNum          = EEPROM_V3_0_PART_NUM_SIZE;
        pxThis->ucSizeBoardUuid             = EEPROM_V3_0_UUID_SIZE;
        pxThis->ucSizeMfgPartNum            = EEPROM_FIELD_NA_SIZE;
        pxThis->ucSizeBoardPcieInfo         = EEPROM_V3_0_PCIE_INFO_SIZE;
        pxThis->ucSizeBoardMaxPowerMode     = EEPROM_V3_0_MAX_POWER_MODE_SIZE;
        pxThis->ucSizeMemorySize            = EEPROM_V3_0_MEM_SIZE_SIZE;
        pxThis->ucSizeOemId                 = EEPROM_V3_0_OEMID_SIZE;
        pxThis->ucSizeCapability            = EEPROM_V3_0_CAPABILITY_SIZE;

        pxThis->ucChecksumStart             = EEPROM_V3_0_CHECKSUM_START;
        pxThis->ucChecksumEnd               = EEPROM_V3_0_CHECKSUM_END;
    }

    sprintf( ( char * ) pxThis->pucEepromVersion, EEPROM_STUB_VERSION );
    sprintf( ( char * ) pxThis->pucProductName, EEPROM_STUB_PRODUCT_NAME );
    sprintf( ( char * ) pxThis->pucBoardRev, EEPROM_STUB_BOARD_REV );
    sprintf( ( char * ) pxThis->pucBoardSerial, EEPROM_STUB_BOARD_SERIAL );
    sprintf( ( char * ) pxThis->pucBoardPartNum, EEPROM_STUB_BOARD_PART_NUM );
}

/**
 * @brief   Dump out all the EEPROM contents
 */
#ifdef EEPROM_VERBOSE_DEBUG_ENABLE
static int iEepromDumpContents( void )
{
    uint8_t pucDataBuff[ pxThis->xEepromCfg.ucEepromPageSize ] = { 0 };
    int iStatus = ERROR;
    int iPageId = 0;
    int i = 0;

    for( iPageId = 0; iPageId < pxThis->xEepromCfg.ucEepromNumPages; iPageId++ )
    {
        iStatus = iEEPROM_ReadRawValue( pucDataBuff, pxThis->xEepromCfg.ucEepromPageSize, ( pxThis->xEepromCfg.ucEepromPageSize * iPageId) ) ;
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
                    vPLL_Printf( "\t[ 0x%04X ]. . . . . :", ( iPageId * pxThis->xEepromCfg.ucEepromPageSize) );
                }
                vPLL_Printf( " %02X", pucDataBuff[ i ] );
            }
        }

        vPLL_Printf( "\r\n" );
    }

    return ( iStatus );
}
#endif
