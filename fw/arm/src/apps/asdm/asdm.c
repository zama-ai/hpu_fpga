/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the ASDM (Alveo Data Store Model) implementation details
 *
 * @file asdm.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

/* common includes */
#include "standard.h"
#include "util.h"
#include "pll.h"
#include "amc_cfg.h"
#include "asdm.h"

/* profile */
#include "profile_hal.h"

/* core_libs */
#include "evl.h"

/* drivers */
#include "eeprom.h"

/* proxy drivers */
#include "asc_proxy_driver.h"
#include "ami_proxy_driver.h"
#include "apc_proxy_driver.h"


/******************************************************************************/
/* Defines                                                                   */
/******************************************************************************/

#define ASDM_NAME "ASDM"

#define UPPER_FIREWALL ( 0xBABECAFE )
#define LOWER_FIREWALL ( 0xDEADFACE )

#define ASDM_RECORD_FIELD_BYTES_MAX   ( 30 )
#define ASDM_RECORD_FIELD_LENGTH_MASK ( 0x3F )
#define ASDM_RECORD_FIELD_TYPE_MASK   ( 0x03 )
#define ASDM_RECORD_FIELD_TYPE_POS    ( 0x06 )

#define ASDM_SDR_THRESHOLD_MAX_LEN             ( 4 )
#define ASDM_SDR_THRESHOLD_UPPER_WARNING_MASK  ( 0x01 << 0 )
#define ASDM_SDR_THRESHOLD_UPPER_CRITICAL_MASK ( 0x01 << 1 )
#define ASDM_SDR_THRESHOLD_UPPER_FATAL_MASK    ( 0x01 << 2 )
#define ASDM_SDR_THRESHOLD_LOWER_WARNING_MASK  ( 0x01 << 3 )
#define ASDM_SDR_THRESHOLD_LOWER_CRITICAL_MASK ( 0x01 << 4 )
#define ASDM_SDR_THRESHOLD_LOWER_FATAL_MASK    ( 0x01 << 5 )
#define ASDM_SDR_THRESHOLD_SENSOR_AVG_MASK     ( 0x01 << 6 )
#define ASDM_SDR_THRESHOLD_SENSOR_MAX_MASK     ( 0x01 << 7 )

#define ASDM_EOR_BYTES  ( 3 )
#define ASDM_EOR_MARKER ( "END" )                                              /* End Of Repository (EOR) - 0x454E44 */

/* Definitions for supported sensor sizes in bytes */
#define AMC_ASDM_SENSOR_SIZE_1B ( 0x1 )
#define AMC_ASDM_SENSOR_SIZE_2B ( 0x2 )
#define AMC_ASDM_SENSOR_SIZE_4B ( 0x4 )

/* default empty SDR size */
#define AMC_ASDM_EMPTY_SDR_SIZE ( 0 )

/* Used to round up the total byte count to be the next multiple of 8 */
#define TOTAL_NUM_BYTES_MULTIPLE ( 0x8 )

/* Value, Max & Average */
#define SENSOR_RESPONSE_VALUES ( 0x3 )

#define SENSOR_RESP_BUFFER_SIZE ( 512 )

#define TOTAL_POWER_NUM_RECORDS ( 1 )
#define FPT_NUM_RECORDS         ( 1 )
#define BOARD_INFO_NUM_RECORDS  ( 1 )

#define ASDM_HEADER_DEFAULT_BYTES ( sizeof( ASDM_SENSOR_HEADER ) + ASDM_EOR_BYTES )

#define ASDM_SDR_DEFAULT_VAL ( 0x7F )

#define ASDM_HEADER_VER ( 0x1 )

/* Stat & Error definitions */
#define ASDM_STATS( DO )                            \
        DO( ASDM_STATS_INIT_OVERALL_COMPLETE )      \
        DO( ASDM_STATS_ASC_SENSOR_UPDATE_EVENT )    \
        DO( ASDM_STATS_ASC_SENSOR_OTHER_EVENT )     \
        DO( ASDM_STATS_AMI_SENSOR_REQUEST )         \
        DO( ASDM_STATS_AMI_UNSUPPORTED_REQUEST )    \
        DO( ASDM_STATS_ASDM_GET_SDR_API )           \
        DO( ASDM_STATS_ASDM_GET_ALL_SENSOR_API )    \
        DO( ASDM_STATS_ASDM_GET_SDR_SIZE_API )      \
        DO( ASDM_STATS_ASDM_GET_SINGLE_SENSOR_API ) \
        DO( ASDM_STATS_ASDM_POPULATE_SDR_SUCCESS )  \
        DO( ASDM_STATS_TAKE_MUTEX )                 \
        DO( ASDM_STATS_RELEASE_MUTEX )              \
        DO( ASDM_STATS_MALLOC )                     \
        DO( ASDM_STATS_FREE )                       \
        DO( ASDM_STATS_GET_FPT_HEADER )             \
        DO( ASDM_STATS_GET_FPT_PARTITION )          \
        DO( ASDM_STATS_APC_FPT_UPDATE_EVENT )       \
        DO( ASDM_STATS_MAX )

#define ASDM_ERRORS( DO )                                \
        DO( ASDM_ERRORS_INIT_MUTEX_FAILED )              \
        DO( ASDM_ERRORS_INIT_BIND_ASC_CB_FAILED )        \
        DO( ASDM_ERRORS_INIT_BIND_APC_CB_FAILED )        \
        DO( ASDM_ERRORS_INIT_OVERALL_FAILED )            \
        DO( ASDM_ERRORS_ASC_GET_SENSORS_FAILED )         \
        DO( ASDM_ERRORS_ASC_GET_SINGLE_SENSOR_FAILED )   \
        DO( ASDM_ERRORS_AMI_SENSOR_REQUEST_EMPTY_SDR )   \
        DO( ASDM_ERRORS_AMI_SENSOR_REQUEST_UNKNOWN_API ) \
        DO( ASDM_ERRORS_AMI_SENSOR_REQUEST_FAILED )      \
        DO( ASDM_ERRORS_AMI_UNSUPPORTED_REPO )           \
        DO( ASDM_ERRORS_MUTEX_RELEASE_FAILED )           \
        DO( ASDM_ERRORS_MUTEX_TAKE_FAILED )              \
        DO( ASDM_ERRORS_MALLOC_FAILED )                  \
        DO( ASDM_ERRORS_ASC_BITFIELD_MAPPING )           \
        DO( ASDM_ERRORS_ASDM_REPO_MAPPING )              \
        DO( ASDM_ERRORS_ASDM_UNIT_MODIFIER_MAPPING )     \
        DO( ASDM_ERRORS_ASDM_SENSOR_NAME_LENGTH )        \
        DO( ASDM_ERRORS_ASDM_POPULATE_SDR_FAILED )       \
        DO( ASDM_ERRORS_ASDM_POPULATE_SDS_FAILED )       \
        DO( ASDM_ERRORS_ASDM_GET_SDR_FAILED )            \
        DO( ASDM_ERRORS_TOTAL_POWER_FAILED )             \
        DO( ASDM_ERRORS_APC_PARTITION_HEADER )           \
        DO( ASDM_ERRORS_APC_PARTITION_INFO )             \
        DO( ASDM_ERRORS_ASDM_POPULATE_BDINFO_FAILED )    \
        DO( ASDM_ERRORS_APC_FPT_UPDATE_FAILED )          \
        DO( ASDM_ERRORS_SENSOR_TAG_MAPPING )             \
        DO( ASDM_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )  PLL_INF( ASDM_NAME,             \
                                          "%50s . . . . %d\r\n", \
                                          ASDM_STATS_STR[ x ],   \
                                          pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x ) PLL_INF( ASDM_NAME,             \
                                          "%50s . . . . %d\r\n", \
                                          ASDM_ERRORS_STR[ x ],  \
                                          pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )  { if( x < ASDM_STATS_MAX ) pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x ) { if( x < ASDM_ERRORS_MAX ) pxThis->pulErrorCounters[ x ]++; }


/**
 * @brief   Function pointer called in profile to enable sensors
 *
 * @return  TRUE to indictate sensor is enabled
 */
static inline int iSensorIsEnabled( void )
{
    return TRUE;
}

ASC_PROXY_DRIVER_SENSOR_DATA xTotalPowerData[ TOTAL_POWER_NUM_RECORDS ] =
{
    {
        "Total_Power", 1, ASC_PROXY_DRIVER_SENSOR_BITFIELD_POWER, FALSE, 0x0, {
            ASC_SENSOR_I2C_BUS_INVALID, ASC_SENSOR_I2C_BUS_INVALID, ASC_SENSOR_I2C_BUS_INVALID,
            ASC_SENSOR_I2C_BUS_INVALID
        }, iSensorIsEnabled, {
            NULL, NULL, NULL, NULL
        }, {
            {
                0, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL,
                ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, 0, 0, ASC_PROXY_DRIVER_SENSOR_STATUS_NOT_PRESENT,
                ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_ENABLED, ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_NONE
            },
            {
                0, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL,
                ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, 0, 0, ASC_PROXY_DRIVER_SENSOR_STATUS_NOT_PRESENT,
                ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_ENABLED, ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_NONE
            },
            {
                0, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL,
                ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, 0, 0, ASC_PROXY_DRIVER_SENSOR_STATUS_NOT_PRESENT,
                ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_ENABLED, ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_NONE
            },
            {
                0, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL,
                ASC_SENSOR_INVALID_VAL, ASC_SENSOR_INVALID_VAL, 0, 0, ASC_PROXY_DRIVER_SENSOR_STATUS_NOT_PRESENT,
                ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_ENABLED, ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_MILLI
            }
        }
    }
};


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    AMC_ASDM_SUPPORTED_REPO
 * @brief   the repo type
 */
typedef enum AMC_ASDM_SUPPORTED_REPO
{
    AMC_ASDM_SUPPORTED_REPO_TEMP = 0,
    AMC_ASDM_SUPPORTED_REPO_VOLTAGE,
    AMC_ASDM_SUPPORTED_REPO_CURRENT,
    AMC_ASDM_SUPPORTED_REPO_POWER,
    AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER,
    AMC_ASDM_SUPPORTED_REPO_FPT,
    AMC_ASDM_SUPPORTED_REPO_BOARD_INFO,
    AMC_ASDM_SUPPORTED_REPO_MAX

} AMC_ASDM_SUPPORTED_REPO;

/**
 * @enum    ASDM_RECORD_FIELD_TYPE_CODE
 * @brief   either ASCII string or a number
 * */
typedef enum ASDM_RECORD_FIELD_TYPE_CODE
{
    ASDM_RECORD_FIELD_TYPE_CODE_NUM         = 0,
    ASDM_RECORD_FIELD_TYPE_CODE_BYTE_ARRAY  = 1,
    ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII = 3,
    ASDM_RECORD_FIELD_TYPE_CODE_MAX

} ASDM_RECORD_FIELD_TYPE_CODE;

/**
 * @enum    ASDM_SDR_SENSOR_STATUS
 * @brief   the sensor status
 */
typedef enum ASDM_SDR_SENSOR_STATUS
{
    ASDM_SDR_SENSOR_STATUS_NOT_PRESENT = 0,
    ASDM_SDR_SENSOR_STATUS_PRESENT_VALID,
    ASDM_SDR_SENSOR_STATUS_NOT_AVAILABLE,
    ASDM_SDR_SENSOR_STATUS_DEFAULT     = ASDM_SDR_DEFAULT_VAL,
    ASDM_SDR_SENSOR_STATUS_MAX

} ASDM_SDR_SENSOR_STATUS;

/**
 * @enum    ASDM_SDR_UNIT_MODIFIER
 * @brief   the unit modifier mapping
 */
typedef enum ASDM_SDR_UNIT_MODIFIER
{
    ASDM_SDR_UNIT_MODIFIER_MICRO = -6,
    ASDM_SDR_UNIT_MODIFIER_MILLI = -3,
    ASDM_SDR_UNIT_MODIFIER_NONE  = 0,
    ASDM_SDR_UNIT_MODIFIER_KILO  = 3,
    ASDM_SDR_UNIT_MODIFIER_MEGA  = 6,
    ASDM_SDR_UNIT_MODIFIER_MAX

} ASDM_SDR_UNIT_MODIFIER;

/**
 * @enum    ASDM_SDS_SENSOR_TAG
 * @brief   tags used in the SDS structure
 */
typedef enum ASDM_SDS_SENSOR_TAG
{
    ASDM_SDS_SENSOR_TAG_BOARD_INFO = 0,
    ASDM_SDS_SENSOR_TAG_BOARD_TEMP,
    ASDM_SDS_SENSOR_TAG_DEVICE_TEMP,
    ASDM_SDS_SENSOR_TAG_QSFP_TEMP,
    ASDM_SDS_SENSOR_TAG_VOLTAGE,
    ASDM_SDS_SENSOR_TAG_CURRENT,
    ASDM_SDS_SENSOR_TAG_POWER,
    ASDM_SDS_SENSOR_TAG_MAX

} ASDM_SDS_SENSOR_TAG;

/**
 * @enum    ASDM_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( ASDM_STATS, ASDM_STATS, ASDM_STATS_STR )

/**
 * @enum    ASDM_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( ASDM_ERRORS, ASDM_ERRORS, ASDM_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  ASDM_SENSOR_LIST
 * @brief   List of sensors IDs stored per repo type
 */
typedef struct ASDM_SENSOR_LIST
{
    uint8_t ucNumFound;
    uint8_t *pucSensorIndex;
    uint8_t *pucSensorId;

} ASDM_SENSOR_LIST;

/**
 * @struct  ASDM_SENSOR_HEADER
 * @brief   the SDR/SDS header format
 *
 * @note    Packed to 5 bytes to maintain layout for parsing in AMI
 */
typedef struct __attribute__( ( __packed__ ) ) ASDM_SENSOR_HEADER
{
    uint8_t  ucRepoType;                                                       /* is a unique number that represents the SDR */
    uint8_t  ucRepoVersionNum;                                                 /* is used to differentiate multiple versions of SDRs */
    uint8_t  ucTotalNumRecords;                                                /* total number of sensor records within each SDR type */
    uint16_t usTotalNumBytes;                                                  /* is represented in multiple of 8s (i.e.) a record of 80 bytes
                                                                                  long will be represented as 10 */
}
ASDM_SENSOR_HEADER;

/**
 * @struct ASDM_FPT_HEADER
 * @brief  the fpt header
 */
typedef struct ASDM_FPT_HEADER
{
    uint8_t ucFptVersion;
    uint8_t ucFptHeaderSize;
    uint8_t ucFptEntrySize;
    uint8_t ucNumEnteries;

} ASDM_FPT_HEADER;

/**
 * @struct ASDM_FPT_ENTRY
 * @brief  a single FPT entry
 */
typedef struct ASDM_FPT_ENTRY
{
    uint32_t ulType;
    uint32_t ulBaseAddr;
    uint32_t ulPartitionSize;

} ASDM_FPT_ENTRY;

/**
 * @struct ASDM_FPT_RECORD
 * @brief  the fpt header and records
 */
typedef struct ASDM_FPT_RECORD
{
    ASDM_FPT_HEADER xFptHdrPrimary;
    ASDM_FPT_ENTRY  *pxFptEntryPrimary;
    ASDM_FPT_HEADER xFptHdrSecondary;
    ASDM_FPT_ENTRY  *pxFptEntrySecondary;

} ASDM_FPT_RECORD;

/**
 * @struct  ASDM_RECORD_FIELD
 * @brief   the record field format
 */
typedef struct ASDM_RECORD_FIELD
{
    uint8_t ucType;
    uint8_t ucLength;
    union
    {
        uint8_t  pucBytesValue[ ASDM_RECORD_FIELD_BYTES_MAX ];
        uint32_t ulValue;

    };

} ASDM_RECORD_FIELD;

/**
 * @struct ASDM_BOARD_INFO_RECORD
 * @brief  the board info record
 */
typedef struct ASDM_BOARD_INFO_RECORD
{
    ASDM_RECORD_FIELD xEepromVersion;                                          /* ASCII */
    ASDM_RECORD_FIELD xProductName;                                            /* ASCII */
    ASDM_RECORD_FIELD xBoardRev;                                               /* ASCII */
    ASDM_RECORD_FIELD xBoardSerial;                                            /* ASCII */
    ASDM_RECORD_FIELD xMacAddressCount;                                        /* Literal/Binary */
    ASDM_RECORD_FIELD xFirstMacAddress;                                        /* Literal/Binary */
    ASDM_RECORD_FIELD xActiveState;                                            /* ASCII */
    ASDM_RECORD_FIELD xConfigMode;                                             /* Literal/Binary */
    ASDM_RECORD_FIELD xManufacturingDate;                                      /* Literal/Binary */
    ASDM_RECORD_FIELD xPartNumber;                                             /* ASCII */
    ASDM_RECORD_FIELD xUuid;                                                   /* Literal/Binary */
    ASDM_RECORD_FIELD xPcieId;                                                 /* Literal/Binary */
    ASDM_RECORD_FIELD xMaxPowerMode;                                           /* Literal/Binary */
    ASDM_RECORD_FIELD xMemorySize;                                             /* ASCII */
    ASDM_RECORD_FIELD xOemId;                                                  /* Literal/Binary */
    ASDM_RECORD_FIELD xCapability;                                             /* Literal/Binary */
    ASDM_RECORD_FIELD xMfgPartNumber;                                          /* ASCII */

} ASDM_BOARD_INFO_RECORD;

/**
 * @struct ASDM_SDR_RECORD
 * @brief  a single SDR sensor record
 */
typedef struct ASDM_SDR_RECORD
{
    uint8_t           ucId;                                                    /* uniquely identifies each sensor record within the SDR */
    ASDM_RECORD_FIELD xSensorName;
    ASDM_RECORD_FIELD xSensorValue;
    ASDM_RECORD_FIELD xSensorBaseUnit;
    char              cUnitModifier;
    uint8_t           ucThresholdSupportedBitMask;
    uint32_t          ulLowerFatalLimit;
    uint32_t          ulLowerCritLimit;
    uint32_t          ulLowerWarnLimit;
    uint32_t          ulUpperWarnLimit;
    uint32_t          ulUpperCritLimit;
    uint32_t          ulUpperFatalLimit;
    uint8_t           ucSensorStatus;
    uint32_t          ulMaxValue;
    uint32_t          ulAverageValue;

} ASDM_SDR_RECORD;

/**
 * @struct ASDM_SDR
 * @brief  represents a single SDR instance
 */
typedef struct ASDM_SDR
{
    ASDM_SENSOR_HEADER xHdr;
    union
    {
        ASDM_SDR_RECORD        *pxSensorRecord;
        ASDM_FPT_RECORD        xFptRecord;
        ASDM_BOARD_INFO_RECORD *pxBoardInfo;

    };

    uint8_t pucAsdmEor[ ASDM_EOR_BYTES ];

} ASDM_SDR;

/**
 * @struct ASDM_SDS_RECORD
 * @brief  represents a single SDS sensor record
 */
typedef struct ASDM_SDS_RECORD
{
    uint8_t           ucId;
    ASDM_RECORD_FIELD xSensorValue;
    uint8_t           ucSensorStatus;
    uint8_t           ucSensorTag;
    uint8_t           ucRsvd;

} ASDM_SDS_RECORD;

/**
 * @struct ASDM_SDS
 * @brief  represents a single SDS instance
 */
typedef struct ASDM_SDS
{
    ASDM_SENSOR_HEADER xHdr;
    ASDM_SDS_RECORD    *pxSensorRecord;
    uint8_t            pucAsdmEor[ ASDM_EOR_BYTES ];

} ASDM_SDS;

/**
 * @struct  ASDM_PRIVATE_DATA
 * @brief   Structure to hold this applications private data
 */
typedef struct ASDM_PRIVATE_DATA
{
    uint32_t                       ulUpperFirewall;
    int                            iSensorListInitialised;
    int                            iInitialised;
    ASC_PROXY_DRIVER_SENSOR_DATA   *pxAscData;
    uint8_t                        ucAscNumSensors;
    ASDM_SENSOR_LIST               pxSensorList[ AMC_ASDM_SUPPORTED_REPO_MAX ];
    ASDM_SDR                       *pxAsdmSdrInfo;                             /* pointer to the dynamically allocated ASDM */
    ASDM_SDS                       *pxAsdmSdsInfo;                             /* pointer to the dynamically allocated SDS */
    void                           *pvOsalMutexHdl;                            /* mutex to protect access to ASDM */
    uint32_t                       ulPowerCalcIterations;
    uint32_t                       ulAveragePower;
    uint32_t                       ulMaxPower;
    APC_PROXY_DRIVER_FPT_HEADER    pxFptHeader[ MAX_APC_BOOT_DEVICES ];
    APC_PROXY_DRIVER_FPT_PARTITION *ppxFptPartitions[ MAX_APC_BOOT_DEVICES ];
    ASDM_BOARD_INFO_RECORD         *pxBoardInfo;
    uint32_t                       pulStatCounters[ ASDM_STATS_MAX ];
    uint32_t                       pulErrorCounters[ ASDM_ERRORS_MAX ];
    uint32_t                       ulLowerFirewall;

} ASDM_PRIVATE_DATA;


/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

static ASDM_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                                                            /* ulUpperFirewall */
    FALSE,                                                                     /* iSensorListInitialised */
    FALSE,                                                                     /* iInitialised */
    NULL,                                                                      /* pxAscData */
    0,                                                                         /* ucAscNumSensors */
    { {
          0
      } },                                                                     /* pxSensorList */
    NULL,                                                                      /* pxAsdmSdrInfo */
    NULL,                                                                      /* pxAsdmSdsInfo */
    NULL,                                                                      /* pvOsalMutexHdl */
    0,                                                                         /* ulPowerCalcIterations */
    0,                                                                         /* ulAveragePower */
    0,                                                                         /* ulMaxPower */
    { {
          0
      } },                                                                     /* pxFptHeader */
    {
        NULL
    },                                                                         /* ppxFptPartitions */
    NULL,                                                                      /* pxBoardInfo */
    {
        0
    },                                                                         /* pulStatCounters */
    {
        0
    },                                                                         /* pulErrorCounters */
    LOWER_FIREWALL                                                             /* ulLowerFirewall */
};
static ASDM_PRIVATE_DATA *pxThis = &xLocalData;

static ASDM_SENSOR_HEADER xAsdmHeaderInfo[] =
{
    /* Record Type  | Hdr Version | Record Count | NumBytes */
    {
        ASDM_REPOSITORY_TYPE_TEMP,          ASDM_HEADER_VER, 0, 0
    },
    {
        ASDM_REPOSITORY_TYPE_VOLTAGE,       ASDM_HEADER_VER, 0, 0
    },
    {
        ASDM_REPOSITORY_TYPE_CURRENT,       ASDM_HEADER_VER, 0, 0
    },
    {
        ASDM_REPOSITORY_TYPE_POWER,         ASDM_HEADER_VER, 0, 0
    },                                                                         /* Individual Power Values */
    {
        ASDM_REPOSITORY_TYPE_TOTAL_POWER,   ASDM_HEADER_VER, 0, 0
    },                                                                         /* Total Power */
    {
        ASDM_REPOSITORY_TYPE_FPT,           ASDM_HEADER_VER, 0, 0
    },
    {
        ASDM_REPOSITORY_TYPE_BOARD_INFO,    ASDM_HEADER_VER, 0, 0
    },
};

#define MAX_ASDM_SDR_REPO ( sizeof( xAsdmHeaderInfo ) / sizeof( xAsdmHeaderInfo[ 0 ] ) )

static const char *pcConvertRepoBaseUnitStr[] =
{
    [ ASDM_REPOSITORY_TYPE_TEMP ]        = "Celsius",
    [ ASDM_REPOSITORY_TYPE_VOLTAGE ]     = "Volts",
    [ ASDM_REPOSITORY_TYPE_CURRENT ]     = "Amps",
    [ ASDM_REPOSITORY_TYPE_POWER ]       = "Watts",
    [ ASDM_REPOSITORY_TYPE_TOTAL_POWER ] = "Watts",
};

static const char *pcConvertRepoStr[] =
{
    [ ASDM_REPOSITORY_TYPE_TEMP ]        = "TEMP",
    [ ASDM_REPOSITORY_TYPE_VOLTAGE ]     = "VOLTAGE",
    [ ASDM_REPOSITORY_TYPE_CURRENT ]     = "CURRENT",
    [ ASDM_REPOSITORY_TYPE_POWER ]       = "POWER",
    [ ASDM_REPOSITORY_TYPE_TOTAL_POWER ] = "TOTAL POWER",
    [ ASDM_REPOSITORY_TYPE_FPT ]         = "FPT",
    [ ASDM_REPOSITORY_TYPE_BOARD_INFO ]  = "BDINFO",
};

/**
 * @brief   Debug function used to print out the unit modifier
 *
 * @param   xUnit    The unit modifier
 *
 * @return  The string representation
 */
static inline const char *pcConvertUnitModStr( ASDM_SDR_UNIT_MODIFIER xUnit )
{
    /* Note: this is stored in the ASDM as -3 to +3*/
    switch( xUnit )
    {
    case ASDM_SDR_UNIT_MODIFIER_MEGA:
    {
        return "Mega";
    }

    case ASDM_SDR_UNIT_MODIFIER_KILO:
    {
        return "Kilo";
    }

    case ASDM_SDR_UNIT_MODIFIER_MILLI:
    {
        return "Milli";
        break;
    }

    case ASDM_SDR_UNIT_MODIFIER_MICRO:
    {
        return "Micro";
    }

    case ASDM_SDR_UNIT_MODIFIER_NONE:
    default:
    {
        return "None";
    }
    }
}


/******************************************************************************/
/* Local function definition                                                  */
/******************************************************************************/

/**
 * @brief   EVL Callbacks for binding to Proxy Drivers
 *
 * @param   pxSignal     Event raised
 *
 * @return  OK if no errors were raised in the callback
 *          ERROR if an error was raised in the callback
 */
static int iAscCallback( EVL_SIGNAL *pxSignal );
static int iApcCallback( EVL_SIGNAL *pxSignal );

/**
 * @brief   Initialise the global ASDM table
 *
 * @param   ucNumSensors    The number of sensors
 *
 * @return  OK or ERROR
 *
 */
static int iInitAsdm( uint8_t ucNumSensors );

/**
 * @brief   Update the global ASDM table sensor values
 *
 * @return  OK or ERROR
 *
 */
static int iUpdateAsdmValues( void );

/**
 * @brief   Build up a list of sensors for a particular repo type
 *
 * @param   ucNumSensors    The number of sensors in the ASC list
 * @param   xRepo           The repo type (temp, voltage or current)
 * @param   pxList          The returned list
 *
 * @return  OK or ERROR
 */
static int iPopulateRepoSensorList( uint8_t ucNumSensors,
                                    AMC_ASDM_SUPPORTED_REPO xRepo,
                                    ASDM_SENSOR_LIST *pxList );
/**
 * @brief   Populate a single SDR instance
 *
 * @param   ucIndex         The ASDM index used to set sensor id
 * @param   ucRepoType      The ASDM repo type
 * @param   pxData          The sensor list returned from the ASC
 * @param   pxSdr           The SDR to be populated
 * @param   pusByteCount    The size of the SDR in bytes
 *
 * @return  OK or ERROR
 */
static int iPopulateSdr( uint8_t ucIndex,
                         uint8_t ucRepoType,
                         ASC_PROXY_DRIVER_SENSOR_DATA *pxData,
                         ASDM_SDR_RECORD *pxSdr,
                         uint16_t *pusByteCount );

/**
 * @brief   Populate a single SDS instance
 *
 * @param   ucIndex         The ASDM index used to set sensor id
 * @param   ucRepoType      The ASDM repo type
 * @param   pxData          The sensor list returned from the ASC
 * @param   pxSds           The SDS to be populated
 * @param   pusByteCount    The size of the SDS in bytes
 *
 * @return  OK or ERROR
 */
static int iPopulateSds( uint8_t ucIndex,
                         uint8_t ucRepoType,
                         ASC_PROXY_DRIVER_SENSOR_DATA *pxData,
                         ASDM_SDS_RECORD *pxSds,
                         uint16_t *pusByteCount );

/**
 * @brief   Map the ASDM repo type to the supported repo type
 *
 * @param   xAsdmRepo      The ASDM repo type
 * @param   pxInBandRepo   The mapped application repo type
 *
 * @return  OK or ERROR
 */
static int iMapAsdmRepo( ASDM_REPOSITORY_TYPE xAsdmRepo,
                         AMC_ASDM_SUPPORTED_REPO *pxInBandRepo );

/**
 * @brief   Map the application unit mod to the ASDM unit mode
 *
 * @param   xUnitMod      The application repo type
 * @param   pxSdrMod      The mapped ASDM repo type
 *
 * @return  OK or ERROR
 */
static int iMapUnitModifier( ASC_PROXY_DRIVER_SENSOR_UNIT_MOD xUnitMod,
                             ASDM_SDR_UNIT_MODIFIER *pxSdrMod );

/**
 * @brief   Populate the threshold values of an SDR
 *
 * @param   pxData          The sensor list returned from the ASC
 * @param   pxSdr           The SDR to be populated
 * @param   ucSnsrValueLen  The sensor length (1,2 or 4 bytes)
 * @param   ucInBandRepo    The application repo type
 * @param   pusByteCount    The returned bytes used when populating
 *
 * @return  OK or ERROR
 */
static int iPopulateSdrThresholds( ASC_PROXY_DRIVER_SENSOR_DATA *pxData,
                                   ASDM_SDR_RECORD *pxSdr,
                                   uint8_t ucSnsrValueLen,
                                   uint8_t ucInBandRepo,
                                   uint16_t *pusByteCount );

/**
 * @brief   Populate the get SDR response back to the AMI proxy
 *
 * @param   xRepo               The repository type
 * @param   pucRespBuff         The response buffer to populate
 * @param   pusRespSizeBytes    The size of the response
 *
 * @return  OK or ERROR
 */
static int iPopulateAsdmGetSdrResponse( ASDM_REPOSITORY_TYPE xRepo,
                                        uint8_t *pucRespBuff,
                                        uint16_t *pusRespSizeBytes );

/**
 * @brief   Populate the get all sensors response back to the AMI proxy
 *
 * @param   xRepo               The repository type
 * @param   pucRespBuff         The response buffer to populate
 * @param   pusRespSizeBytes    The size of the response
 *
 * @return  OK or ERROR
 */
static int iPopulateAsdmGetAllSensorDataResponse( ASDM_REPOSITORY_TYPE xRepo,
                                                  uint8_t *pucRespBuff,
                                                  uint16_t *pusRespSizeBytes );

/**
 * @brief   Populate the get sdr size response back to the AMI proxy
 *
 * @param   xRepo               The repository type
 * @param   pucRespBuff         The response buffer to populate
 * @param   pusRespSizeBytes    The size of the response
 *
 * @return  OK or ERROR
 */
static int iPopulateAsdmGetSizeResponse( ASDM_REPOSITORY_TYPE xRepo,
                                         uint8_t *pucRespBuff,
                                         uint16_t *pusRespSizeBytes );

/**
 * @brief   Populate the get single sensor data response back to the AMI proxy
 *
 * @param   xRepo               The repository type
 * @param   ucSensorId          The sensor ID, if applicable
 * @param   pucRespBuff         The response buffer to populate
 * @param   pusRespSizeBytes    The size of the response
 *
 * @return  OK or ERROR
 */
static int iPopulateAsdmGetSingleSensorResponse( ASDM_REPOSITORY_TYPE xRepo,
                                                 uint8_t ucSensorId,
                                                 uint8_t *pucRespBuff,
                                                 uint16_t *pusRespSizeBytes );

/**
 * @brief   Calculate the total power using the data received from the ASC
 *
 * @return  OK or ERROR
 */
static int iCalculateTotalPower( void );

/**
 * @brief   Get the FPT data from the APC
 *
 * @return  OK or ERROR
 */
static int iGetFptData( void );

/**
 * @brief   Populate the FPT ASDM
 *
 * @param   pusByteCount    The returned bytes used when populating
 *
 * @return  OK or ERROR
 */
static int iPopulateAsdmFpt( uint16_t *pusByteCount );

/**
 * @brief   Get the Board info data from the EEPROM driver
 *
 * @return  OK or ERROR
 */
static int iGetBoardInfoData( void );

/**
 * @brief   Populate the Board Info ASDM
 *
 * @param   pusByteCount    The returned bytes used when populating
 *
 * @return  OK or ERROR
 */
static int iPopulateAsdmBoardInfo( uint16_t *pusByteCount );

/**
 * @brief   Populate the Board Info ASDM
 *
 * @param   xRepo               The inband repo type
 * @param   pucRespBuff         The response buffer to populate
 * @param   pusRespSizeBytes    The response size in bytes
 *
 * @return  OK or ERROR
 */
static int iPopulateAsdmSdrBoardInfoResponse( ASDM_REPOSITORY_TYPE xRepo,
                                              uint8_t *pucRespBuff,
                                              uint16_t *pusRespSizeBytes );

/**
 * @brief   Refresh all cached FPT data
 *
 * @note    This function will destroy the current FPT data and attempt to
 *          re-initialise it; it will then call `iUpdateAsdmFpt` to update
 *          the ASDM SDR
 *
 * @return  OK or ERROR
 */
static int iRefreshFptData( void );

/**
 * @brief   Repopulate FPT ASDM data
 *
 * @note    This function should not be called directly -
 *          use `iRefreshFptData` instead
 *
 * @return  OK or ERROR
 */
static int iUpdateAsdmFpt( void );

/**
 * @brief   Populate the SDR response back to the RMI Handler
 *
 * @param   xRepo               The asdm repo type
 * @param   pucRespBuff         The response buffer to populate
 * @param   pusRespSizeBytes    The response size in bytes
 *
 * @return  OK or ERROR
 */
static int iPopulateAsdmGetSdrResponseV2( ASDM_REPOSITORY_TYPE xRepo,
                                          uint8_t *pucRespBuff,
                                          uint16_t *pusRespSizeBytes );

/**
 * @brief   Populate the get all sensors response back to the RMI Handler
 *
 * @param   xRepo               The asdm repo type
 * @param   pucRespBuff         The response buffer to populate
 * @param   pusRespSizeBytes    The response size in bytes
 *
 * @return  OK or ERROR
 */
static int iPopulateAsdmGetAllSensorDataResponseV2( ASDM_REPOSITORY_TYPE xRepo,
                                                    uint8_t *pucRespBuff,
                                                    uint16_t *pusRespSizeBytes );

/**
 * @brief   Maps the asdm repo type to a SDS sensor tag
 *
 * @param   xAsdmRepo           The asdm repo type
 * @param   pxSensorTag         Pointer to the sensor tag
 *
 * @return  OK or ERROR
 */
static int iMapSensorTag( AMC_ASDM_SUPPORTED_REPO xAsdmRepo,
                          ASDM_SDS_SENSOR_TAG *pxSensorTag );


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Initialise the ASDM repo application layer
 */
int iASDM_Initialise( uint8_t ucNumSensors )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) )
    {
        /* Create mutex to protect ASDM access */
        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvOsalMutexHdl, "asdm mutex" ) )
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_INIT_MUTEX_FAILED )
        }
        else
        {
            iStatus = OK;
        }

        /* Build up ASDM table */
        if( OK == iStatus )
        {
            /* Store copy of number of profile sensors */
            pxThis->ucAscNumSensors = ucNumSensors;

            /* Allocate memory to store the ASC data */
            pxThis->pxAscData = pvOSAL_MemAlloc( sizeof ( ASC_PROXY_DRIVER_SENSOR_DATA ) * ucNumSensors );
            if( NULL != pxThis->pxAscData )
            {
                INC_STAT_COUNTER( ASDM_STATS_MALLOC )
                if( OK == iASC_GetAllSensorData( pxThis->pxAscData, &ucNumSensors ) )
                {
                    pxThis->iSensorListInitialised = TRUE;

                    int iRepoIndex = 0;
                    for( iRepoIndex = 0; iRepoIndex < MAX_ASDM_SDR_REPO; iRepoIndex++ )
                    {
                        pxThis->pxSensorList[ iRepoIndex ].pucSensorId = pvOSAL_MemAlloc( ucNumSensors *
                                                                                          sizeof( uint8_t ) );
                        if( NULL == pxThis->pxSensorList[ iRepoIndex ].pucSensorId )
                        {
                            INC_ERROR_COUNTER( ASDM_ERRORS_MALLOC_FAILED )
                            iStatus = ERROR;
                            break;
                        }
                        INC_STAT_COUNTER( ASDM_STATS_MALLOC )

                        pxThis->pxSensorList[ iRepoIndex ].pucSensorIndex = pvOSAL_MemAlloc( ucNumSensors *
                                                                                             sizeof( uint8_t ) );
                        if( NULL == pxThis->pxSensorList[ iRepoIndex ].pucSensorIndex )
                        {
                            INC_ERROR_COUNTER( ASDM_ERRORS_MALLOC_FAILED )
                            iStatus = ERROR;
                            break;
                        }
                        INC_STAT_COUNTER( ASDM_STATS_MALLOC )
                    }

                    if( OK != iStatus )
                    {
                        /* Free allocated memory an a failure */
                        for( iRepoIndex = 0; iRepoIndex < MAX_ASDM_SDR_REPO; iRepoIndex++ )
                        {
                            if( pxThis->pxSensorList[ iRepoIndex ].pucSensorId )
                            {
                                vOSAL_MemFree( ( void** )&pxThis->pxSensorList[ iRepoIndex ].pucSensorId );
                                INC_STAT_COUNTER( ASDM_STATS_FREE )
                            }
                            if( pxThis->pxSensorList[ iRepoIndex ].pucSensorIndex )
                            {
                                vOSAL_MemFree( ( void** )&pxThis->pxSensorList[ iRepoIndex ].pucSensorIndex );
                                INC_STAT_COUNTER( ASDM_STATS_FREE )
                            }
                            if( pxThis->pxAscData )
                            {
                                vOSAL_MemFree( ( void** )&pxThis->pxAscData );
                                INC_STAT_COUNTER( ASDM_STATS_FREE )
                            }
                        }
                    }
                }
                else
                {
                    INC_ERROR_COUNTER( ASDM_ERRORS_ASC_GET_SENSORS_FAILED )
                }

                /* Initialise  ASDM */
                iStatus = iInitAsdm( ucNumSensors );
            }
            else
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_MALLOC_FAILED )
                iStatus = ERROR;
            }
        }

        /* Bind Callbacks */
        if( OK == iASC_BindCallback( &iAscCallback ) )
        {
            PLL_DBG( ASDM_NAME, "ASC Proxy Driver bound\r\n" );
        }
        else
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_INIT_BIND_ASC_CB_FAILED )
            iStatus = ERROR;
        }

        if( OK == iAPC_BindCallback( &iApcCallback ) )
        {
            PLL_DBG( ASDM_NAME, "APC Proxy Driver bound\r\n" );
        }
        else
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_INIT_BIND_APC_CB_FAILED )
            iStatus = ERROR;
        }

        if( OK == iStatus )
        {
            pxThis->iInitialised = TRUE;
            INC_STAT_COUNTER( ASDM_STATS_INIT_OVERALL_COMPLETE )
        }
        else
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_INIT_OVERALL_FAILED )
        }
    }

    return iStatus;
}

/**
 * @brief   Returns the buffer populated with associated response
 */
int iASDM_PopulateResponse( ASDM_API_ID_TYPE xApiType,
                            ASDM_REPOSITORY_TYPE xAsdmRepo,
                            uint8_t ucSensorId,
                            uint8_t *pucRespBuff,
                            uint16_t *pusRespSizeBytes )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucRespBuff ) &&
        ( NULL != pusRespSizeBytes ) )
    {
        switch( xApiType )
        {
        case ASDM_API_ID_TYPE_GET_SDR_SIZE:
        {
            iStatus = iPopulateAsdmGetSizeResponse( xAsdmRepo, pucRespBuff, pusRespSizeBytes );
            break;
        }

        case ASDM_API_ID_TYPE_GET_SDR:
        {
            iStatus = iPopulateAsdmGetSdrResponse( xAsdmRepo, pucRespBuff, pusRespSizeBytes );
            break;
        }

        case ASDM_API_ID_TYPE_GET_SINGLE_SENSOR_DATA:
        {
            iStatus = iPopulateAsdmGetSingleSensorResponse( xAsdmRepo, ucSensorId, pucRespBuff, pusRespSizeBytes );
            break;
        }

        case ASDM_API_ID_TYPE_GET_ALL_SENSOR_DATA:
        {
            iStatus = iPopulateAsdmGetAllSensorDataResponse( xAsdmRepo, pucRespBuff, pusRespSizeBytes );
            break;
        }

        case ASDM_API_ID_TYPE_GET_SDR_V2:
        {
            iStatus = iPopulateAsdmGetSdrResponseV2( xAsdmRepo, pucRespBuff, pusRespSizeBytes );
            break;
        }

        case ASDM_API_ID_TYPE_GET_ALL_SENSOR_DATA_V2:
        {
            iStatus = iPopulateAsdmGetAllSensorDataResponseV2( xAsdmRepo, pucRespBuff, pusRespSizeBytes );
            break;
        }

        case ASDM_API_ID_TYPE_CONFIG_WRITES:
        case ASDM_API_ID_TYPE_SEND_EVENTS:
        {
            /* TODO: not sensor related, should be rejected by ASDM */
            break;
        }

        default:
        {
            /* TODO: unknown request should be rejected */
            break;
        }
        }
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iASDM_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( ASDM_NAME, "============================================================\n\r" );
        PLL_INF( ASDM_NAME, "ASDM App Statistics:\n\r" );
        for( i = 0; i < ASDM_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( ASDM_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( ASDM_NAME, "ASDM App Errors:\n\r" );
        for( i = 0; i < ASDM_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( ASDM_NAME, "============================================================\n\r" );

        iStatus = OK;
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iASDM_ClearStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        pvOSAL_MemSet( pxThis->pulStatCounters, 0, sizeof( pxThis->pulStatCounters ) );
        pvOSAL_MemSet( pxThis->pulErrorCounters, 0, sizeof( pxThis->pulErrorCounters ) );
        iStatus = OK;
    }

    return iStatus;
}

/**
 * @brief   Print out the internal ASDM repo data
 */
int iASDM_PrintAsdmRepoData( int iRepoIndex )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxThis->pxAsdmSdrInfo ) &&
        ( iRepoIndex < AMC_ASDM_SUPPORTED_REPO_MAX ) )
    {
        int iSensorIdx = 0;

        iStatus = OK;

        PLL_INF( ASDM_NAME, "\r\n" );
        PLL_INF( ASDM_NAME,
                 "===============================================================================================================\r\n" );
        PLL_INF( ASDM_NAME, "Repo Type\t\tVersion\t\tNum SDR\t\tSize(bytes(mult*8))\r\n" );
        PLL_INF( ASDM_NAME,
                 "===============================================================================================================\r\n" );

        PLL_INF( ASDM_NAME,
                 "%s\t\t\t0x%02x\t\t0x%02x\t\t0x%02x\r\n",
                 pcConvertRepoStr[ pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucRepoType ],
                 pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucRepoVersionNum,
                 pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucTotalNumRecords,
                 pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.usTotalNumBytes );
        PLL_INF( ASDM_NAME,
                 "===============================================================================================================\r\n" );
        PLL_INF( ASDM_NAME, "\r\n" );
        PLL_INF( ASDM_NAME, "%s:\r\n", pcConvertRepoStr[ pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucRepoType ] );
        PLL_INF( ASDM_NAME, "\r\n" );

        PLL_INF( ASDM_NAME, "\r\n" );
        PLL_INF( ASDM_NAME, "SDR:\r\n" );
        PLL_INF( ASDM_NAME, "\r\n" );

        switch( iRepoIndex )
        {
        case AMC_ASDM_SUPPORTED_REPO_TEMP:
        case AMC_ASDM_SUPPORTED_REPO_VOLTAGE:
        case AMC_ASDM_SUPPORTED_REPO_CURRENT:
        case AMC_ASDM_SUPPORTED_REPO_POWER:
        case AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER:
        {
            for( iSensorIdx = 0; iSensorIdx < pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucTotalNumRecords; iSensorIdx++ )
            {
                uint8_t ucId     = pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].ucId;
                uint8_t *pucName =
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].xSensorName.pucBytesValue;
                uint32_t ulValue =
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].xSensorValue.ulValue;
                uint8_t *pucBase =
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].xSensorBaseUnit.pucBytesValue;
                int8_t ucUnitmod =
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].cUnitModifier;
                uint8_t ucThresholdByte =
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].ucThresholdSupportedBitMask;

                uint32_t ulUpperFatalLimit =
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].ulUpperFatalLimit;
                uint32_t ulUpperCritLimit =
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].ulUpperCritLimit;
                uint32_t ulUpperWarnLimit =
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].ulUpperWarnLimit;

                /* Dump out thresholds for upper only ATM as lower not supported */
                if( ucThresholdByte == ( ASDM_SDR_THRESHOLD_UPPER_FATAL_MASK |
                                         ASDM_SDR_THRESHOLD_UPPER_CRITICAL_MASK |
                                         ASDM_SDR_THRESHOLD_UPPER_WARNING_MASK |
                                         ASDM_SDR_THRESHOLD_SENSOR_AVG_MASK |
                                         ASDM_SDR_THRESHOLD_SENSOR_MAX_MASK ) )
                {
                    PLL_INF( ASDM_NAME,
                             "[%04d] %20s\t%06d\t%9s\t%s\t0%02x %02d:%02d:%02d\r\n",
                             ucId,
                             pucName,
                             ulValue,
                             pucBase,
                             pcConvertUnitModStr( ucUnitmod ),
                             ucThresholdByte,
                             ulUpperFatalLimit,
                             ulUpperCritLimit,
                             ulUpperWarnLimit );
                }
                else
                {
                    PLL_INF( ASDM_NAME,
                             "[%04d] %20s\t%06d\t%9s\t%s\t0x%02x\r\n",
                             ucId,
                             pucName,
                             ulValue,
                             pucBase,
                             pcConvertUnitModStr( ucUnitmod ),
                             ucThresholdByte );
                }
            }

            PLL_INF( ASDM_NAME, "\r\n" );
            PLL_INF( ASDM_NAME, "SDS:\r\n" );
            PLL_INF( ASDM_NAME, "\r\n" );

            for( iSensorIdx = 0; iSensorIdx < pxThis->pxAsdmSdsInfo[ iRepoIndex ].xHdr.ucTotalNumRecords; iSensorIdx++ )
            {
                uint8_t ucId =
                    pxThis->pxAsdmSdsInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].ucId;
                uint8_t ucSize =
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].xSensorValue.ucLength;
                uint32_t ulValue =
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].xSensorValue.ulValue;
                uint8_t ucSensorStatus =
                    pxThis->pxAsdmSdsInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].ucSensorStatus;
                uint8_t ucSensorTag =
                    pxThis->pxAsdmSdsInfo[ iRepoIndex ].pxSensorRecord[ iSensorIdx ].ucSensorTag;

                PLL_INF( ASDM_NAME,
                         "[%04d]\t %04d\t%06d\t0x%x\t0x%x\r\n",
                         ucId,
                         ucSize,
                         ulValue,
                         ucSensorStatus,
                         ucSensorTag );
            }

            break;
        }

        case AMC_ASDM_SUPPORTED_REPO_FPT:
        {
            int i = 0;
            PLL_INF( ASDM_NAME, "Primary Boot Device:\r\n" );
            PLL_INF( ASDM_NAME,
                     "Version: 0x%x\r\n",
                     pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrPrimary.ucFptVersion );
            PLL_INF( ASDM_NAME,
                     "Num enteries: 0x%x\r\n",
                     pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrPrimary.ucNumEnteries );
            PLL_INF( ASDM_NAME,
                     "Entry size: 0x%x\r\n",
                     pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrPrimary.ucFptEntrySize );
            PLL_INF( ASDM_NAME,
                     "Header size: 0x%x\r\n",
                     pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrPrimary.ucFptHeaderSize );
            for( i = 0; i < pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrPrimary.ucNumEnteries; i++ )
            {
                PLL_INF( ASDM_NAME,
                         "\t[%d] Type: 0x%x\r\n",
                         i,
                         pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary[ i ].ulType );
                PLL_INF( ASDM_NAME,
                         "\t[%d] Base Address: 0x%x\r\n",
                         i,
                         pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary[ i ].ulBaseAddr );
                PLL_INF( ASDM_NAME,
                         "\t[%d] Partition size: 0x%x\r\n",
                         i,
                         pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary[ i ].ulPartitionSize );
            }
            PLL_INF( ASDM_NAME, "\r\n" );

            PLL_INF( ASDM_NAME, "Secondary Boot Device:\r\n" );
            PLL_INF( ASDM_NAME,
                     "Version: 0x%x\r\n",
                     pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrSecondary.ucFptVersion );
            PLL_INF( ASDM_NAME,
                     "Num enteries: 0x%x\r\n",
                     pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrSecondary.ucNumEnteries );
            PLL_INF( ASDM_NAME,
                     "Entry size: 0x%x\r\n",
                     pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrSecondary.ucFptEntrySize );
            PLL_INF( ASDM_NAME,
                     "Header size: 0x%x\r\n",
                     pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrSecondary.ucFptHeaderSize );
            for( i = 0; i < pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrSecondary.ucNumEnteries; i++ )
            {
                PLL_INF( ASDM_NAME,
                         "\t[%d] Type: 0x%x\r\n",
                         i,
                         pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary[ i ].ulType );
                PLL_INF( ASDM_NAME,
                         "\t[%d] Base Address: 0x%x\r\n",
                         i,
                         pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary[ i ].ulBaseAddr );
                PLL_INF( ASDM_NAME,
                         "\t[%d] Partition size: 0x%x\r\n",
                         i,
                         pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary[ i ].ulPartitionSize );
            }
            break;
        }

        case AMC_ASDM_SUPPORTED_REPO_BOARD_INFO:
        {
            uint8_t *pucEepromVersion =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xEepromVersion.pucBytesValue;
            uint8_t *pucProductName =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xProductName.pucBytesValue;
            uint8_t *pucBoardRevision =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xBoardRev.pucBytesValue;
            uint8_t *pucBoardSerial =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xBoardSerial.pucBytesValue;
            uint32_t ulMacCount =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xMacAddressCount.ulValue;
            uint8_t *pucFirstMacAddress =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xFirstMacAddress.pucBytesValue;
            uint8_t *pucActiveState =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xActiveState.pucBytesValue;
            uint8_t *pucConfigMode =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xConfigMode.pucBytesValue;
            uint8_t *pucManufacturingDate =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xManufacturingDate.pucBytesValue;
            uint8_t *pucPartNumber =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xPartNumber.pucBytesValue;
            uint8_t *pucUuid =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xUuid.pucBytesValue;
            uint8_t *pucPcieId =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xPcieId.pucBytesValue;
            uint8_t *pucPowerMode =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xMaxPowerMode.pucBytesValue;
            uint8_t *pucMemorySize =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xMemorySize.pucBytesValue;
            uint8_t *pucOemId =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xOemId.pucBytesValue;
            uint8_t *pucCapability =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xCapability.pucBytesValue;
            uint8_t *pucMfgPartNumber =
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xMfgPartNumber.pucBytesValue;

            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xEepromVersion.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME, "Eeprom version: %s\r\n", pucEepromVersion );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xProductName.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME, "Product name: %s\r\n", pucProductName );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xBoardRev.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME, "Board Version: %s\r\n", pucBoardRevision );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xBoardSerial.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME, "Board Serial: %s\r\n", pucBoardSerial );
            }
            PLL_INF( ASDM_NAME, "MAC count: %d\r\n", ulMacCount );
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xFirstMacAddress.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME,
                         "First Mac Address: %02x:%02x:%02x:%02x:%02x:%02x\n\r",
                         pucFirstMacAddress[ 0 ],
                         pucFirstMacAddress[ 1 ],
                         pucFirstMacAddress[ 2 ],
                         pucFirstMacAddress[ 3 ],
                         pucFirstMacAddress[ 4 ],
                         pucFirstMacAddress[ 5 ] );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xManufacturingDate.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME,
                         "Manufacturing date: %02x%02x%02x\r\n",
                         pucManufacturingDate[ 0 ],
                         pucManufacturingDate[ 1 ],
                         pucManufacturingDate[ 2 ] );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xPartNumber.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME, "Part number: %s\r\n", pucPartNumber );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xUuid.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME,
                         "UUID: %02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x\r\n",
                         pucUuid[ 0 ],
                         pucUuid[ 1 ],
                         pucUuid[ 2 ],
                         pucUuid[ 3 ],
                         pucUuid[ 4 ],
                         pucUuid[ 5 ],
                         pucUuid[ 6 ],
                         pucUuid[ 7 ],
                         pucUuid[ 8 ],
                         pucUuid[ 9 ],
                         pucUuid[ 10 ],
                         pucUuid[ 11 ],
                         pucUuid[ 12 ],
                         pucUuid[ 13 ],
                         pucUuid[ 14 ],
                         pucUuid[ 15 ] );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xActiveState.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME, "Active state: %c\r\n", pucActiveState[ 0 ] );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xConfigMode.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME, "Config mode: %02x\r\n", pucConfigMode[ 0 ] );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xPcieId.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME,
                         "PCIe id: %02x%02x, %02x%02x, %02x%02x, %02x%02x\n\r",
                         pucPcieId[ 0 ],
                         pucPcieId[ 1 ],
                         pucPcieId[ 2 ],
                         pucPcieId[ 3 ],
                         pucPcieId[ 4 ],
                         pucPcieId[ 5 ],
                         pucPcieId[ 6 ],
                         pucPcieId[ 7 ] );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xMaxPowerMode.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME, "Power Mode: %d\r\n", pucPowerMode[ 0 ] );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xMemorySize.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME, "Memory size: %s\r\n", pucMemorySize );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xOemId.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME,
                         "OEM id: %02x%02x%02x%02x\r\n",
                         pucOemId[ 3 ],
                         pucOemId[ 2 ],
                         pucOemId[ 1 ],
                         pucOemId[ 0 ] );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xCapability.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME,
                         "Capability: %02x%02x\r\n",
                         pucCapability[ 1 ],
                         pucCapability[ 0 ] );
            }
            if( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo->xMfgPartNumber.ucLength > 0 )
            {
                PLL_INF( ASDM_NAME, "Mfg Part number: %s\r\n", pucMfgPartNumber );
            }
            break;
        }

        default:
        {
            break;
        }
        }
        PLL_INF( ASDM_NAME, "\r\n" );
        PLL_INF( ASDM_NAME,
                 "EOR 0x%x%x%x\r\n",
                 pxThis->pxAsdmSdrInfo[ iRepoIndex ].pucAsdmEor[ 0 ],
                 pxThis->pxAsdmSdrInfo[ iRepoIndex ].pucAsdmEor[ 1 ],
                 pxThis->pxAsdmSdrInfo[ iRepoIndex ].pucAsdmEor[ 2 ] );
        PLL_INF( ASDM_NAME, "\r\n" );

        PLL_INF( ASDM_NAME,
                 "===============================================================================================================\r\n" );
        PLL_INF( ASDM_NAME, "\r\n" );
    }

    return ( iStatus );
}

/**
 * @brief   ASC Proxy Driver EVL callback
 */
static int iAscCallback( EVL_SIGNAL *pxSignal )
{
    int iStatus = ERROR;

    if( ( NULL != pxSignal ) &&
        ( NULL != pxThis->pxAscData ) &&
        ( AMC_CFG_UNIQUE_ID_ASC == pxSignal->ucModule ) )
    {
        switch( pxSignal->ucEventType )
        {
        case ASC_PROXY_DRIVER_E_SENSOR_UPDATE_COMPLETE:
        {
            uint8_t ucNumSensors = pxThis->ucAscNumSensors;
            iStatus = iASC_GetAllSensorData( pxThis->pxAscData, &ucNumSensors );
            if( OK == iStatus )
            {
                INC_STAT_COUNTER( ASDM_STATS_ASC_SENSOR_UPDATE_EVENT )
                iStatus = iUpdateAsdmValues( );
            }
            else
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_ASC_GET_SENSORS_FAILED )
            }
            break;
        }

        case ASC_PROXY_DRIVER_E_SENSOR_UNAVAILABLE:
        case ASC_PROXY_DRIVER_E_SENSOR_COMMS_FAILURE:
        case ASC_PROXY_DRIVER_E_SENSOR_WARNING:
        case ASC_PROXY_DRIVER_E_SENSOR_CRITICAL:
        case ASC_PROXY_DRIVER_E_SENSOR_FATAL:
        case ASC_PROXY_DRIVER_E_SENSOR_LOWER_WARNING:
        case ASC_PROXY_DRIVER_E_SENSOR_LOWER_CRITICAL:
        case ASC_PROXY_DRIVER_E_SENSOR_LOWER_FATAL:
        {
            INC_STAT_COUNTER( ASDM_STATS_ASC_SENSOR_OTHER_EVENT )
            iStatus = OK;
            break;
        }

        case ASC_PROXY_DRIVER_E_SENSOR_UPPER_WARNING:
        {
            iStatus = iASC_GetSingleSensorDataById( pxSignal->ucInstance, pxThis->pxAscData );
            if( OK != iStatus )
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_ASC_GET_SINGLE_SENSOR_FAILED )
            }
            break;
        }

        case ASC_PROXY_DRIVER_E_SENSOR_UPPER_CRITICAL:
        {
            iStatus = iASC_GetSingleSensorDataById( pxSignal->ucInstance, pxThis->pxAscData );
            if( OK != iStatus )
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_ASC_GET_SINGLE_SENSOR_FAILED )
            }
            break;
        }

        case ASC_PROXY_DRIVER_E_SENSOR_UPPER_FATAL:
        {
            iStatus = iASC_GetSingleSensorDataById( pxSignal->ucInstance, pxThis->pxAscData );
            if( OK != iStatus )
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_ASC_GET_SINGLE_SENSOR_FAILED )
            }
            break;
        }

        default:
        {
            break;
        }
        }
    }

    return iStatus;
}

/**
 * @brief   APC Proxy Driver EVL callback
 */
static int iApcCallback( EVL_SIGNAL *pxSignal )
{
    int iStatus = ERROR;

    if( ( NULL != pxSignal ) && ( AMC_CFG_UNIQUE_ID_APC == pxSignal->ucModule ) )
    {
        switch( pxSignal->ucEventType )
        {
        case APC_PROXY_DRIVER_E_FPT_UPDATE:
        {
            INC_STAT_COUNTER( ASDM_STATS_APC_FPT_UPDATE_EVENT )

            if( OK == iRefreshFptData() )
            {
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_APC_FPT_UPDATE_FAILED )
            }
            break;
        }

        default:
        {
            INC_STAT_COUNTER( ASDM_STATS_AMI_UNSUPPORTED_REQUEST )
            iStatus = OK;
            break;
        }
        }
    }

    return iStatus;
}

/**
 * @brief   Dynamically build up the ASDM table
 */
static int iInitAsdm( uint8_t ucNumSensors )
{
    int      iStatus           = ERROR;
    int      iRepoIndex        = 0;
    uint16_t usAllocateSizeSdr = 0;
    uint16_t usAllocateSizeSds = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxThis->pxAscData ) &&
        ( NULL == pxThis->pxAsdmSdrInfo ) )
    {
        pxThis->pxAsdmSdrInfo =
            ( ASDM_SDR * )pvOSAL_MemAlloc( MAX_ASDM_SDR_REPO * sizeof( ASDM_SDR ) );
        pxThis->pxAsdmSdsInfo =
            ( ASDM_SDS * )pvOSAL_MemAlloc( MAX_ASDM_SDR_REPO * sizeof( ASDM_SDS ) );
        if( NULL != pxThis->pxAsdmSdrInfo )
        {
            INC_STAT_COUNTER( ASDM_STATS_MALLOC )

            /* Allocate memory for SDR/SDS and sensor list */
            pvOSAL_MemSet( pxThis->pxAsdmSdrInfo, 0x00, ( MAX_ASDM_SDR_REPO * sizeof( ASDM_SDR ) ) );
            pvOSAL_MemSet( pxThis->pxAsdmSdsInfo, 0x00, ( MAX_ASDM_SDR_REPO * sizeof( ASDM_SDS ) ) );

            for( iRepoIndex = 0; iRepoIndex < MAX_ASDM_SDR_REPO; iRepoIndex++ )
            {
                /* Initial total bytes made up of header & EOR */
                uint16_t usTotalByteCount = ASDM_HEADER_DEFAULT_BYTES;

                /* Parse the ASC data list and get the number for each supported repo type */
                switch( iRepoIndex )
                {
                case AMC_ASDM_SUPPORTED_REPO_TEMP:
                case AMC_ASDM_SUPPORTED_REPO_VOLTAGE:
                case AMC_ASDM_SUPPORTED_REPO_CURRENT:
                case AMC_ASDM_SUPPORTED_REPO_POWER:
                {
                    iStatus = iPopulateRepoSensorList( ucNumSensors,
                                                       iRepoIndex,
                                                       &pxThis->pxSensorList[ iRepoIndex ] );
                    if( OK != iStatus )
                    {
                        /* To deal with invalid sensor data -
                           force the rest of the ASDM to be populated */
                        pxThis->pxSensorList[ iRepoIndex ].ucNumFound = 0;
                        iStatus = OK;
                    }
                    break;
                }

                /* ASDM headers/EOR still required for non ASC sensor repo types */
                case AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER:
                {
                    if( TRUE == pxThis->iSensorListInitialised )
                    {
                        pxThis->pxSensorList[ iRepoIndex ].ucNumFound = TOTAL_POWER_NUM_RECORDS;
                        iStatus = OK;
                    }
                    else
                    {
                        /* To deal with invalid sensor data -
                           force the rest of the ASDM to be populated */
                        pxThis->pxSensorList[ iRepoIndex ].ucNumFound = 0;
                        iStatus = OK;
                    }

                    break;
                }

                case AMC_ASDM_SUPPORTED_REPO_FPT:
                {
                    iStatus = iGetFptData();
                    if( OK == iStatus )
                    {
                        pxThis->pxSensorList[ iRepoIndex ].ucNumFound = FPT_NUM_RECORDS;
                    }
                    else
                    {
                        /* To deal with scenario that invalid FTP header is returned -
                           force the rest of the ASDM to be populated */
                        pxThis->pxSensorList[ iRepoIndex ].ucNumFound = 0;
                        iStatus = OK;
                    }
                    break;
                }

                case AMC_ASDM_SUPPORTED_REPO_BOARD_INFO:
                {
                    iStatus = iGetBoardInfoData();
                    if( OK == iStatus )
                    {
                        pxThis->pxSensorList[ iRepoIndex ].ucNumFound = BOARD_INFO_NUM_RECORDS;
                    }
                    else
                    {
                        /* To deal with invalid board info data -
                           force the rest of the ASDM to be populated */
                        pxThis->pxSensorList[ iRepoIndex ].ucNumFound = 0;
                        iStatus = OK;
                    }
                    break;
                }

                default:
                {
                    break;
                }
                }

                if( OK == iStatus )
                {
                    /* Fill ASDM SDR Header */
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucRepoType =
                        xAsdmHeaderInfo[ iRepoIndex ].ucRepoType;
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucRepoVersionNum =
                        xAsdmHeaderInfo[ iRepoIndex ].ucRepoVersionNum;
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucTotalNumRecords =
                        pxThis->pxSensorList[ iRepoIndex ].ucNumFound;
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.usTotalNumBytes =
                        xAsdmHeaderInfo[ iRepoIndex ].usTotalNumBytes;

                    /* Fill ASDM SDS Header */
                    pxThis->pxAsdmSdsInfo[ iRepoIndex ].xHdr.ucRepoType =
                        xAsdmHeaderInfo[ iRepoIndex ].ucRepoType;
                    pxThis->pxAsdmSdsInfo[ iRepoIndex ].xHdr.ucRepoVersionNum =
                        xAsdmHeaderInfo[ iRepoIndex ].ucRepoVersionNum;
                    pxThis->pxAsdmSdsInfo[ iRepoIndex ].xHdr.ucTotalNumRecords =
                        pxThis->pxSensorList[ iRepoIndex ].ucNumFound;
                    pxThis->pxAsdmSdsInfo[ iRepoIndex ].xHdr.usTotalNumBytes =
                        xAsdmHeaderInfo[ iRepoIndex ].usTotalNumBytes;

                    /* Based on Number of Records allocate memory for all the Sensor Records */
                    if( pxThis->pxSensorList[ iRepoIndex ].ucNumFound > 0 )
                    {
                        uint16_t usByteCount = 0;

                        switch( iRepoIndex )
                        {
                        case AMC_ASDM_SUPPORTED_REPO_TEMP:
                        case AMC_ASDM_SUPPORTED_REPO_VOLTAGE:
                        case AMC_ASDM_SUPPORTED_REPO_CURRENT:
                        case AMC_ASDM_SUPPORTED_REPO_POWER:
                        case AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER:
                        {
                            usAllocateSizeSdr = sizeof( ASDM_SDR_RECORD ) *
                                                pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucTotalNumRecords;
                            pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord =
                                ( ASDM_SDR_RECORD * )pvOSAL_MemAlloc( usAllocateSizeSdr );

                            usAllocateSizeSds = sizeof( ASDM_SDS_RECORD ) *
                                                pxThis->pxAsdmSdsInfo[ iRepoIndex ].xHdr.ucTotalNumRecords;

                            pxThis->pxAsdmSdsInfo[ iRepoIndex ].pxSensorRecord =
                                ( ASDM_SDS_RECORD * )pvOSAL_MemAlloc( usAllocateSizeSds );
                            if( NULL != pxThis->pxAsdmSdsInfo[ iRepoIndex ].pxSensorRecord )
                            {
                                int i = 0;

                                INC_STAT_COUNTER( ASDM_STATS_MALLOC )
                                pvOSAL_MemSet( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord,
                                               0x00,
                                               usAllocateSizeSdr );

                                ASDM_SDR_RECORD *pxSdr = pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord;
                                ASDM_SDS_RECORD *pxSds = pxThis->pxAsdmSdsInfo[ iRepoIndex ].pxSensorRecord;

                                /* Populate each SDR / SDS */
                                for( i = 0; i < pxThis->pxSensorList[ iRepoIndex ].ucNumFound; i++ )
                                {
                                    uint8_t ucSensorListIndex = pxThis->pxSensorList[ iRepoIndex ].pucSensorIndex[ i ];
                                    uint8_t ucRepoType        = pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucRepoType;
                                    usByteCount = 0;

                                    /* Populate SDR */
                                    if( AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER == iRepoIndex )
                                    {
                                        iStatus = iPopulateSdr( i,
                                                                ucRepoType,
                                                                &xTotalPowerData[ i ],
                                                                pxSdr,
                                                                &usByteCount );
                                    }
                                    else
                                    {
                                        iStatus = iPopulateSdr( i,
                                                                ucRepoType,
                                                                &pxThis->pxAscData[ ucSensorListIndex ],
                                                                &pxSdr[ i ],
                                                                &usByteCount );
                                    }

                                    /* Populate SDS */
                                    if( AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER == iRepoIndex )
                                    {
                                        iStatus = iPopulateSds( i,
                                                                ucRepoType,
                                                                &xTotalPowerData[ i ],
                                                                pxSds,
                                                                &usByteCount );
                                    }
                                    else
                                    {
                                        iStatus = iPopulateSds( i,
                                                                ucRepoType,
                                                                &pxThis->pxAscData[ ucSensorListIndex ],
                                                                &pxSds[ i ],
                                                                &usByteCount );
                                    }

                                    if( ERROR == iStatus )
                                    {
                                        /* Free SDR memory */
                                        if( NULL != pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord )
                                        {
                                            vOSAL_MemFree(
                                                ( void** )&pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxSensorRecord );
                                            INC_STAT_COUNTER( ASDM_STATS_FREE )
                                        }

                                        /* Reset the ASDM header on failure */
                                        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.ucTotalNumRecords = 0;
                                        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.usTotalNumBytes   = 0;
                                        INC_ERROR_COUNTER( ASDM_ERRORS_ASDM_POPULATE_SDR_FAILED )

                                        /* Free SDS memory */
                                        if( NULL != pxThis->pxAsdmSdsInfo[ iRepoIndex ].pxSensorRecord )
                                        {
                                            vOSAL_MemFree(
                                                ( void** )&pxThis->pxAsdmSdsInfo[ iRepoIndex ].pxSensorRecord );
                                            INC_STAT_COUNTER( ASDM_STATS_FREE )
                                        }

                                        /* Reset the ASDM header on failure */
                                        pxThis->pxAsdmSdsInfo[ iRepoIndex ].xHdr.ucTotalNumRecords = 0;
                                        pxThis->pxAsdmSdsInfo[ iRepoIndex ].xHdr.usTotalNumBytes   = 0;
                                        INC_ERROR_COUNTER( ASDM_ERRORS_ASDM_POPULATE_SDS_FAILED )
                                        break;
                                    }

                                    /* Increment the total count after each SDR is populated */
                                    usTotalByteCount += usByteCount;
                                    INC_STAT_COUNTER( ASDM_STATS_ASDM_POPULATE_SDR_SUCCESS )
                                }
                            }
                            else
                            {
                                INC_ERROR_COUNTER( ASDM_ERRORS_MALLOC_FAILED )
                                iStatus = ERROR;
                            }
                            break;
                        }

                        case AMC_ASDM_SUPPORTED_REPO_FPT:
                        {
                            usByteCount = 0;
                            iStatus     = iPopulateAsdmFpt( &usByteCount );
                            if( OK == iStatus )
                            {
                                usTotalByteCount += usByteCount;
                            }
                            break;
                        }

                        case AMC_ASDM_SUPPORTED_REPO_BOARD_INFO:
                        {
                            usByteCount = 0;
                            iStatus     = iPopulateAsdmBoardInfo( &usByteCount );
                            if( OK == iStatus )
                            {
                                usTotalByteCount += usByteCount;
                            }
                            break;
                        }

                        default:
                        {
                            iStatus = ERROR;
                            break;
                        }
                        }
                    }

                    if( OK == iStatus )
                    {
                        /* Copy EOR */
                        pvOSAL_MemCpy( pxThis->pxAsdmSdrInfo[ iRepoIndex ].pucAsdmEor,
                                       ASDM_EOR_MARKER,
                                       ASDM_EOR_BYTES );
                        pvOSAL_MemCpy( pxThis->pxAsdmSdsInfo[ iRepoIndex ].pucAsdmEor,
                                       ASDM_EOR_MARKER,
                                       ASDM_EOR_BYTES );

                        /*
                         * Update the Byte Count for this record in Multiple of 8
                         * if not an exact multiple, add pad bytes to round it off
                         */
                        if( 0 != ( usTotalByteCount % TOTAL_NUM_BYTES_MULTIPLE ) )
                        {
                            uint8_t ucTmp = ( usTotalByteCount % TOTAL_NUM_BYTES_MULTIPLE );
                            usTotalByteCount += ( TOTAL_NUM_BYTES_MULTIPLE - ucTmp );
                        }

                        /* This is represented in multiple of 8s (i.e.) a record of 80 bytes long will be represented as 10 */
                        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.usTotalNumBytes =
                            ( usTotalByteCount / TOTAL_NUM_BYTES_MULTIPLE );
                    }
                }
                else
                {
                    PLL_ERR( ASDM_NAME, "Error failed to populate sensor list\r\n" );
                    iStatus = ERROR;
                }

                if( ERROR == iStatus )
                {
                    /* If there has been a failure no point in parsing the rest */
                    break;
                }
            }
        }
        else
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_MALLOC_FAILED )
            iStatus = ERROR;
        }
    }
    return iStatus;
}

/**
 * @brief Update the global ASDM table sensor values
 */
static int iUpdateAsdmValues( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxThis->pxAscData ) &&
        ( NULL != pxThis->pxAsdmSdrInfo ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            int iRepoIdx = 0;

            INC_STAT_COUNTER( ASDM_STATS_TAKE_MUTEX )

            /*
             * Sensor values stored on a per repo basis
             * limit the ASC update to the temp/current/voltage & power
             */
            for( iRepoIdx = 0; iRepoIdx < AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER; iRepoIdx++ )
            {
                uint8_t ucTotalNumRecords = pxThis->pxSensorList[ iRepoIdx ].ucNumFound;
                int     iSensorIdx        = 0;

                /* Internal sensor list contains index's into the ASC sensor table  */
                for( iSensorIdx = 0; iSensorIdx < ucTotalNumRecords; iSensorIdx++ )
                {
                    /* Pointer to the ASDM sensor record */
                    ASDM_SDR_RECORD *pxSensorRecordSdr = pxThis->pxAsdmSdrInfo[ iRepoIdx ].pxSensorRecord;
                    ASDM_SDS_RECORD *pxSensorRecordSds = pxThis->pxAsdmSdsInfo[ iRepoIdx ].pxSensorRecord;

                    /* Matching index into the ASC data */
                    int iAscDataIdx = pxThis->pxSensorList[ iRepoIdx ].pucSensorIndex[ iSensorIdx ];

                    /* Update sensor with the latest values */
                    pxSensorRecordSdr[ iSensorIdx ].xSensorValue.ulValue =
                        pxThis->pxAscData[ iAscDataIdx ].pxReadings[ iRepoIdx ].ulSensorValue;
                    pxSensorRecordSdr[ iSensorIdx ].ulAverageValue =
                        pxThis->pxAscData[ iAscDataIdx ].pxReadings[ iRepoIdx ].ulAverageSensorValue;
                    pxSensorRecordSdr[ iSensorIdx ].ulMaxValue =
                        pxThis->pxAscData[ iAscDataIdx ].pxReadings[ iRepoIdx ].ulMaxSensorValue;
                    pxSensorRecordSdr[ iSensorIdx ].ucSensorStatus =
                        pxThis->pxAscData[ iAscDataIdx ].pxReadings[ iRepoIdx ].xSensorStatus;

                    /* Update sensor with the latest values */
                    pxSensorRecordSds[ iSensorIdx ].xSensorValue.ulValue =
                        pxThis->pxAscData[ iAscDataIdx ].pxReadings[ iRepoIdx ].ulSensorValue;
                    pxSensorRecordSds[ iSensorIdx ].ucSensorStatus =
                        pxThis->pxAscData[ iAscDataIdx ].pxReadings[ iRepoIdx ].xSensorStatus;
                }
            }

            /* Calculate power & update ASDM */
            iStatus = iCalculateTotalPower( );
            if( ERROR == iStatus )
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_TOTAL_POWER_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( ASDM_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_TAKE_FAILED )
            iStatus = ERROR;
        }
    }

    return iStatus;
}

/**
 * @brief  Build up a list of sensors for a particular repo type
 */
static int iPopulateRepoSensorList( uint8_t ucNumSensors,
                                    AMC_ASDM_SUPPORTED_REPO xRepo,
                                    ASDM_SENSOR_LIST *pxList )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iSensorListInitialised ) &&
        ( NULL != pxThis->pxAscData ) &&
        ( NULL != pxList ) )
    {
        uint8_t ucBit = 0;

        switch( xRepo )
        {
        case AMC_ASDM_SUPPORTED_REPO_TEMP:
        {
            ucBit   = ASC_PROXY_DRIVER_SENSOR_BITFIELD_TEMPERATURE;
            iStatus = OK;
            break;
        }

        case AMC_ASDM_SUPPORTED_REPO_VOLTAGE:
        {
            ucBit   = ASC_PROXY_DRIVER_SENSOR_BITFIELD_VOLTAGE;
            iStatus = OK;
            break;
        }

        case AMC_ASDM_SUPPORTED_REPO_CURRENT:
        {
            ucBit   = ASC_PROXY_DRIVER_SENSOR_BITFIELD_CURRENT;
            iStatus = OK;
            break;
        }

        case AMC_ASDM_SUPPORTED_REPO_POWER:
        case AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER:
        {
            ucBit   = ASC_PROXY_DRIVER_SENSOR_BITFIELD_POWER;
            iStatus = OK;
            break;
        }

        case AMC_ASDM_SUPPORTED_REPO_FPT:
        case AMC_ASDM_SUPPORTED_REPO_BOARD_INFO:
        {
            /* Supported but not used in the sensor list from ASC so ignore */
            iStatus = OK;
            break;
        }

        default:
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_ASC_BITFIELD_MAPPING )
            break;
        }
        }

        if( OK == iStatus )
        {
            int i = 0;
            for( i = 0; i < ucNumSensors; i++ )
            {
                if( pxThis->pxAscData[ i ].ucSensorType & ucBit )
                {
                    /* check if sensor is enabled */
                    if( TRUE == pxThis->pxAscData[ i ].pxSensorEnabled() )
                    {
                        /* update list to add matching sensor type */
                        pxList->pucSensorIndex[ pxList->ucNumFound ] = i;
                        pxList->pucSensorId[ pxList->ucNumFound ]    = pxThis->pxAscData[ i ].ucSensorId;
                        pxList->ucNumFound++;
                    }
                }
            }
        }
    }

    return iStatus;
}

/**
 * @brief  Populate a single SDR instance
 */
static int iPopulateSdr( uint8_t ucIndex,
                         uint8_t ucRepoType,
                         ASC_PROXY_DRIVER_SENSOR_DATA *pxData,
                         ASDM_SDR_RECORD *pxSdr,
                         uint16_t *pusByteCount )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxData ) &&
        ( NULL != pusByteCount ) &&
        ( NULL != pxSdr ) )
    {
        uint8_t ucInBandRepo = 0;

        /* We use ASC_PROXY_DRIVER_SENSOR_TYPE_POWER for both single / total power */
        if( ASDM_REPOSITORY_TYPE_TOTAL_POWER == ucRepoType )
        {
            ucInBandRepo = AMC_ASDM_SUPPORTED_REPO_POWER;
            iStatus      = OK;
        }
        else
        {
            iStatus = iMapAsdmRepo( ucRepoType, ( AMC_ASDM_SUPPORTED_REPO* )&ucInBandRepo );
        }

        if( OK == iStatus )
        {
            uint8_t  ucSnsrValueLen  = AMC_ASDM_SENSOR_SIZE_4B;
            uint16_t usSensorNameLen = 0;
            uint16_t usByteCount     = 0;

            /* 1. Sensor Id - starts at index 1 */
            pxSdr->ucId  = ucIndex + 1;
            usByteCount += sizeof( pxSdr->ucId );

            /* 2. Sensor Name (string field) */
            usSensorNameLen = strlen( pxData->pcSensorName ) + 1;
            if( usSensorNameLen >= ASDM_RECORD_FIELD_BYTES_MAX )
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_ASDM_SENSOR_NAME_LENGTH )
                iStatus = ERROR;
            }
            else
            {
                pxSdr->xSensorName.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII;
                pxSdr->xSensorName.ucLength = ( usSensorNameLen & ASDM_RECORD_FIELD_LENGTH_MASK );
                pcOSAL_StrNCpy( ( char* )pxSdr->xSensorName.pucBytesValue, pxData->pcSensorName, usSensorNameLen );
                pxSdr->xSensorName.pucBytesValue[ usSensorNameLen ] = '\0';
                usByteCount += usSensorNameLen;
                iStatus      = OK;
            }

            /* 3. Sensor Value (number) */
            /* 4. Sensor Units (string) */
            /* 5. Sensor Unit Modifier */
            if( OK == iStatus )
            {
                ASDM_SDR_UNIT_MODIFIER xSdrUnitMod    = ASDM_SDR_UNIT_MODIFIER_MAX;
                uint8_t                ucSnsrUnitsLen = strlen( pcConvertRepoBaseUnitStr[ ucRepoType ] ) + 1;

                pxSdr->xSensorValue.ucLength = ( ucSnsrValueLen & ASDM_RECORD_FIELD_LENGTH_MASK );
                pxSdr->xSensorValue.ulValue  = pxData->pxReadings[ ucInBandRepo ].ulSensorValue;
                usByteCount                 += ucSnsrValueLen;

                pxSdr->xSensorBaseUnit.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII;
                pxSdr->xSensorBaseUnit.ucLength = ( ucSnsrUnitsLen & ASDM_RECORD_FIELD_LENGTH_MASK );
                pcOSAL_StrNCpy( ( char * )pxSdr->xSensorBaseUnit.pucBytesValue,
                                pcConvertRepoBaseUnitStr[ ucRepoType ],
                                ucSnsrUnitsLen );
                pxSdr->xSensorBaseUnit.pucBytesValue[ ucSnsrUnitsLen ] = '\0';
                usByteCount += ucSnsrUnitsLen;

                iStatus = iMapUnitModifier( pxData->pxReadings[ ucInBandRepo ].xSensorUnitModifier,
                                            &xSdrUnitMod );
                if( OK == iStatus )
                {
                    pxSdr->cUnitModifier = xSdrUnitMod;
                    usByteCount         += sizeof( pxSdr->cUnitModifier );
                }
            }

            /* 6. Sensor Threshold Supported Byte - value set within the iPopulateSdrThresholds( ) */
            /* 7. Thresholds */
            if( OK == iStatus )
            {
                uint16_t usThresByteCount = 0;
                pxSdr->ucThresholdSupportedBitMask = 0;
                usByteCount += sizeof( pxSdr->ucThresholdSupportedBitMask );

                iStatus = iPopulateSdrThresholds( pxData,
                                                  pxSdr,
                                                  ucSnsrValueLen,
                                                  ucInBandRepo,
                                                  &usThresByteCount );
                if( OK == iStatus )
                {
                    usByteCount += sizeof( usThresByteCount );
                }
            }

            /* 8. Sensor Status */
            /* 9. Max Value */
            /* 10. Average Value */
            if( OK == iStatus )
            {
                pxSdr->ucSensorStatus = ASDM_SDR_SENSOR_STATUS_PRESENT_VALID;
                usByteCount          += sizeof( pxSdr->ucSensorStatus );
                if( ASC_SENSOR_INVALID_VAL != pxData->pxReadings[ ucInBandRepo ].ulMaxSensorValue )
                {
                    pxSdr->ulMaxValue                   = pxData->pxReadings[ ucInBandRepo ].ulMaxSensorValue;
                    pxSdr->ucThresholdSupportedBitMask |= ASDM_SDR_THRESHOLD_SENSOR_AVG_MASK;
                    usByteCount += sizeof( ucSnsrValueLen );
                }
                if( ASC_SENSOR_INVALID_VAL != pxData->pxReadings[ ucInBandRepo ].ulAverageSensorValue )
                {
                    pxSdr->ulAverageValue               = pxData->pxReadings[ ucInBandRepo ].ulAverageSensorValue;
                    pxSdr->ucThresholdSupportedBitMask |= ASDM_SDR_THRESHOLD_SENSOR_MAX_MASK;
                    usByteCount += sizeof( ucSnsrValueLen );
                }
                *pusByteCount = usByteCount;
            }
        }
        else
        {
            PLL_ERR( ASDM_NAME, "Error failed to map repo type\r\n" );
            iStatus = ERROR;
        }
    }

    return ( iStatus );
}

/**
 * @brief  Populate a single SDS instance
 */
static int iPopulateSds( uint8_t ucIndex,
                         uint8_t ucRepoType,
                         ASC_PROXY_DRIVER_SENSOR_DATA *pxData,
                         ASDM_SDS_RECORD *pxSds,
                         uint16_t *pusByteCount )
{
    int iStatus = ERROR;

    if( ( NULL != pxData ) &&
        ( NULL != pusByteCount ) &&
        ( NULL != pxSds ) )
    {
        uint8_t ucAsdmRepo = 0;

        iStatus = iMapAsdmRepo( ucRepoType, ( AMC_ASDM_SUPPORTED_REPO* )&ucAsdmRepo );

        if( OK == iStatus )
        {
            uint16_t usByteCount    = 0;
            uint8_t  ucSnsrValueLen = AMC_ASDM_SENSOR_SIZE_4B;
            uint8_t  ucSensorTag    = 0;

            /* 1. Sensor ID */
            pxSds->ucId  = ucIndex + 1;
            usByteCount += sizeof( pxSds->ucId );

            /* 2. Sensor Size / Value */
            pxSds->xSensorValue.ucLength = ( ucSnsrValueLen & ASDM_RECORD_FIELD_LENGTH_MASK );
            pxSds->xSensorValue.ulValue  = pxData->pxReadings[ ucAsdmRepo ].ulSensorValue;
            usByteCount                 += ucSnsrValueLen;

            /* 4. Sensor Status */
            pxSds->ucSensorStatus = pxData->pxReadings[ ucAsdmRepo ].xSensorStatus;
            usByteCount          += sizeof( pxSds->ucSensorStatus );

            /* 5. Sensor Tag */
            iStatus = iMapSensorTag( ( AMC_ASDM_SUPPORTED_REPO )ucAsdmRepo, ( ASDM_SDS_SENSOR_TAG* )&ucSensorTag );

            if( OK == iStatus )
            {
                pxSds->ucSensorTag = ucSensorTag;
                usByteCount       += sizeof( pxSds->ucSensorTag );
            }
            else
            {
                /* invalid sensor tag */
                pxSds->ucSensorTag = 0;
                usByteCount       += sizeof( pxSds->ucSensorTag );
            }

            /* 6. Reserved bytes for allignment */
            pvOSAL_MemSet( &pxSds->ucRsvd, 0, sizeof( pxSds->ucRsvd ) );
            usByteCount += sizeof( pxSds->ucRsvd );

            *pusByteCount = usByteCount;
        }
        else
        {
            PLL_ERR( ASDM_NAME, "Error failed to map repo type\r\n" );
            iStatus = ERROR;
        }
    }

    return iStatus;
}

/**
 * @brief  Map the ASDM repo type to the application repo type
 */
static int iMapAsdmRepo( ASDM_REPOSITORY_TYPE xAsdmRepo,
                         AMC_ASDM_SUPPORTED_REPO *pxInBandRepo )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxInBandRepo ) )
    {
        *pxInBandRepo = AMC_ASDM_SUPPORTED_REPO_MAX;
        switch( xAsdmRepo )
        {
        case ASDM_REPOSITORY_TYPE_TEMP:
        {
            *pxInBandRepo = AMC_ASDM_SUPPORTED_REPO_TEMP;
            iStatus       = OK;
            break;
        }

        case ASDM_REPOSITORY_TYPE_VOLTAGE:
        {
            *pxInBandRepo = AMC_ASDM_SUPPORTED_REPO_VOLTAGE;
            iStatus       = OK;
            break;
        }

        case ASDM_REPOSITORY_TYPE_CURRENT:
        {
            *pxInBandRepo = AMC_ASDM_SUPPORTED_REPO_CURRENT;
            iStatus       = OK;
            break;
        }

        case ASDM_REPOSITORY_TYPE_POWER:
        {
            *pxInBandRepo = AMC_ASDM_SUPPORTED_REPO_POWER;
            iStatus       = OK;
            break;
        }

        case ASDM_REPOSITORY_TYPE_TOTAL_POWER:
        {
            *pxInBandRepo = AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER;
            iStatus       = OK;
            break;
        }

        case ASDM_REPOSITORY_TYPE_BOARD_INFO:
        {
            *pxInBandRepo = AMC_ASDM_SUPPORTED_REPO_BOARD_INFO;
            iStatus       = OK;
            break;
        }

        case ASDM_REPOSITORY_TYPE_FPT:
        {
            *pxInBandRepo = AMC_ASDM_SUPPORTED_REPO_FPT;
            iStatus       = OK;
            break;
        }

        default:
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_ASDM_REPO_MAPPING )
            break;
        }
        }
    }

    return iStatus;
}

/**
 * @brief  Map the ASC unit mod into the ASDM mod
 */
static int iMapUnitModifier( ASC_PROXY_DRIVER_SENSOR_UNIT_MOD xUnitMod,
                             ASDM_SDR_UNIT_MODIFIER *pxSdrMod )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxSdrMod ) )
    {
        *pxSdrMod = ASDM_SDR_UNIT_MODIFIER_MAX;

        switch( xUnitMod )
        {
        case ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_MEGA:
        {
            *pxSdrMod = ASDM_SDR_UNIT_MODIFIER_MEGA;
            iStatus   = OK;
            break;
        }

        case ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_KILO:
        {
            *pxSdrMod = ASDM_SDR_UNIT_MODIFIER_KILO;
            iStatus   = OK;
            break;
        }

        case ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_NONE:
        {
            *pxSdrMod = ASDM_SDR_UNIT_MODIFIER_NONE;
            iStatus   = OK;
            break;
        }

        case ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_MILLI:
        {
            *pxSdrMod = ASDM_SDR_UNIT_MODIFIER_MILLI;
            iStatus   = OK;
            break;
        }

        case ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_MICRO:
        {
            *pxSdrMod = ASDM_SDR_UNIT_MODIFIER_MICRO;
            iStatus   = OK;
            break;
        }

        default:
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_ASDM_UNIT_MODIFIER_MAPPING )
            break;
        }
        }
    }

    return iStatus;
}

/**
 * @brief  Populate an SDR's threshold values instance
 */
static int iPopulateSdrThresholds( ASC_PROXY_DRIVER_SENSOR_DATA *pxData,
                                   ASDM_SDR_RECORD *pxSdr,
                                   uint8_t ucSnsrValueLen,
                                   uint8_t ucInBandRepo,
                                   uint16_t *pusByteCount )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxData ) &&
        ( NULL != pxSdr ) &&
        ( NULL != pusByteCount ) )
    {
        uint16_t usByteCount = 0;

        /* Lower Fatal Threshold*/
        if( ASC_SENSOR_INVALID_VAL != pxData->pxReadings[ ucInBandRepo ].ulLowerFatalLimit )
        {
            pxSdr->ulLowerFatalLimit            = pxData->pxReadings[ ucInBandRepo ].ulLowerFatalLimit;
            pxSdr->ucThresholdSupportedBitMask |= ASDM_SDR_THRESHOLD_LOWER_FATAL_MASK;
            usByteCount += sizeof( ucSnsrValueLen );
        }

        /* Lower Critical Threshold*/
        if( ASC_SENSOR_INVALID_VAL != pxData->pxReadings[ ucInBandRepo ].ulLowerCriticalLimit )
        {
            pxSdr->ulLowerCritLimit             = pxData->pxReadings[ ucInBandRepo ].ulLowerCriticalLimit;
            pxSdr->ucThresholdSupportedBitMask |= ASDM_SDR_THRESHOLD_LOWER_CRITICAL_MASK;
            usByteCount += sizeof( ucSnsrValueLen );
        }

        /* Lower Warning Threshold*/
        if( ASC_SENSOR_INVALID_VAL != pxData->pxReadings[ ucInBandRepo ].ulLowerWarningLimit )
        {
            pxSdr->ulLowerWarnLimit             = pxData->pxReadings[ ucInBandRepo ].ulLowerWarningLimit;
            pxSdr->ucThresholdSupportedBitMask |= ASDM_SDR_THRESHOLD_LOWER_WARNING_MASK;
            usByteCount += sizeof( ucSnsrValueLen );
        }

        /* Upper Fatal Threshold*/
        if( ASC_SENSOR_INVALID_VAL != pxData->pxReadings[ ucInBandRepo ].ulUpperFatalLimit )
        {
            pxSdr->ulUpperFatalLimit            = pxData->pxReadings[ ucInBandRepo ].ulUpperFatalLimit;
            pxSdr->ucThresholdSupportedBitMask |= ASDM_SDR_THRESHOLD_UPPER_FATAL_MASK;
            usByteCount += sizeof( ucSnsrValueLen );
        }

        /* Upper Critical Threshold*/
        if( ASC_SENSOR_INVALID_VAL != pxData->pxReadings[ ucInBandRepo ].ulUpperCriticalLimit )
        {
            pxSdr->ulUpperCritLimit             = pxData->pxReadings[ ucInBandRepo ].ulUpperCriticalLimit;
            pxSdr->ucThresholdSupportedBitMask |= ASDM_SDR_THRESHOLD_UPPER_CRITICAL_MASK;
            usByteCount += sizeof( ucSnsrValueLen );
        }

        /* Upper Warning Threshold*/
        if( ASC_SENSOR_INVALID_VAL != pxData->pxReadings[ ucInBandRepo ].ulUpperWarningLimit )
        {
            pxSdr->ulUpperWarnLimit             = pxData->pxReadings[ ucInBandRepo ].ulUpperWarningLimit;
            pxSdr->ucThresholdSupportedBitMask |= ASDM_SDR_THRESHOLD_UPPER_WARNING_MASK;
            usByteCount += sizeof( ucSnsrValueLen );
        }

        /* Return the number of bytes allocated */
        *pusByteCount = usByteCount;

        iStatus = OK;

    }

    return iStatus;
}

/**
 * @brief   Populate the get individual SDR response back to the AMI proxy
 */
static int iPopulateAsdmGetSdrResponse( ASDM_REPOSITORY_TYPE xRepo,
                                        uint8_t *pucRespBuff,
                                        uint16_t *pusRespSizeBytes )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pucRespBuff ) &&
        ( NULL != pusRespSizeBytes ) )
    {
        INC_STAT_COUNTER( ASDM_STATS_ASDM_GET_SDR_API )

        AMC_ASDM_SUPPORTED_REPO xAsdmRepo = AMC_ASDM_SUPPORTED_REPO_MAX;

        /* Map the internal repo type from the AMI request */
        iStatus = iMapAsdmRepo( xRepo, &xAsdmRepo );

        if( OK == iStatus )
        {
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                      OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                uint16_t usByteCount = 0;
                uint8_t  ucSize      = 0;
                int      i           = 0;

                INC_STAT_COUNTER( ASDM_STATS_TAKE_MUTEX )

                /* SDR Completion code */
                pucRespBuff[ usByteCount++ ] = ASDM_SDR_COMPLETION_CODE_OPERATION_SUCCESS;

                /* SDR Header */
                ucSize = sizeof( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xHdr );
                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xHdr,
                               ucSize );
                usByteCount += ucSize;

                switch( xAsdmRepo )
                {
                case AMC_ASDM_SUPPORTED_REPO_TEMP:
                case AMC_ASDM_SUPPORTED_REPO_VOLTAGE:
                case AMC_ASDM_SUPPORTED_REPO_CURRENT:
                case AMC_ASDM_SUPPORTED_REPO_POWER:
                case AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER:
                {
                    if( 0 < pxThis->pxSensorList[ xAsdmRepo ].ucNumFound )
                    {
                        /* Populate each SDR */
                        for( i = 0; i < pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xHdr.ucTotalNumRecords; i++ )
                        {
                            uint8_t ucSensorValueLen   = 0;
                            uint8_t ucValueLen         = 0;
                            uint8_t ucBaseUnitValueLen = 0;
                            uint8_t ucType             = 0;
                            uint8_t ucTypeLenField     = 0;

                            /* Id */
                            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucId;

                            /* Sensor Name */
                            ucSensorValueLen =
                                ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorName.ucLength
                                  & ASDM_RECORD_FIELD_LENGTH_MASK );
                            ucType = ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorName.ucType
                                       & ASDM_RECORD_FIELD_TYPE_MASK );
                            ucTypeLenField = ( ucSensorValueLen | ( ucType <<
                                                                    ASDM_RECORD_FIELD_TYPE_POS ) );
                            pucRespBuff[ usByteCount++ ] = ucTypeLenField;
                            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorName.
                                           pucBytesValue,
                                           ucSensorValueLen );
                            usByteCount += ucSensorValueLen;
                            /* Sensor Value */
                            ucValueLen = ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorValue.ucLength
                                           & ASDM_RECORD_FIELD_LENGTH_MASK );
                            ucType = ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorValue.ucType
                                       & ASDM_RECORD_FIELD_TYPE_MASK );
                            ucTypeLenField               = ( ucValueLen | ( ucType << ASDM_RECORD_FIELD_TYPE_POS ) );
                            pucRespBuff[ usByteCount++ ] = ucTypeLenField;
                            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorValue.ulValue,
                                           ucValueLen );
                            usByteCount += ucValueLen;

                            /* Base Unit */
                            ucBaseUnitValueLen =
                                ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorBaseUnit.ucLength
                                  & ASDM_RECORD_FIELD_LENGTH_MASK );
                            ucType = ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorBaseUnit.ucType
                                       & ASDM_RECORD_FIELD_TYPE_MASK );
                            ucTypeLenField = ( ucBaseUnitValueLen | ( ucType <<
                                                                      ASDM_RECORD_FIELD_TYPE_POS ) );
                            pucRespBuff[ usByteCount++ ] = ucTypeLenField;
                            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorBaseUnit.
                                           pucBytesValue,
                                           ucBaseUnitValueLen );
                            usByteCount += ucBaseUnitValueLen;

                            /* Unit Modifier*/
                            pucRespBuff[ usByteCount++ ] =
                                pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].cUnitModifier;

                            /* Threshold Support Byte */
                            pucRespBuff[ usByteCount++ ] =
                                pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask;

                            /* Lower Fatal Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_LOWER_FATAL_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulLowerFatalLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Lower Critical Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_LOWER_CRITICAL_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulLowerCritLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Lower Warning Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_LOWER_WARNING_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulLowerWarnLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Upper Fatal Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_UPPER_FATAL_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulUpperFatalLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Upper Critical Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_UPPER_CRITICAL_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulUpperCritLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Upper Warning Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_UPPER_WARNING_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulUpperWarnLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Sensor Status */
                            pucRespBuff[ usByteCount++ ] =
                                pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucSensorStatus;

                            /* Average Value */
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_SENSOR_AVG_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulAverageValue,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Max Value */
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_SENSOR_MAX_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulMaxValue,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }
                        }
                    }
                    else
                    {
                        /* no sensor data found, return OK to return empty SDR */
                        INC_ERROR_COUNTER( ASDM_ERRORS_AMI_SENSOR_REQUEST_EMPTY_SDR )
                        usByteCount += AMC_ASDM_EMPTY_SDR_SIZE;
                        iStatus      = OK;
                    }
                    break;
                }

                case AMC_ASDM_SUPPORTED_REPO_FPT:
                {
                    if( 0 < pxThis->pxSensorList[ xAsdmRepo ].ucNumFound )
                    {
                        int i = 0;
                        /* FPT primary header */
                        pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                       &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xFptRecord.xFptHdrPrimary,
                                       sizeof( ASDM_FPT_HEADER ) );
                        usByteCount += sizeof( ASDM_FPT_HEADER );

                        /* FPT primary partitions */
                        for( i = 0; i < pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xFptRecord.xFptHdrPrimary.ucNumEnteries;
                             i++ )
                        {
                            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xFptRecord.pxFptEntryPrimary[ i ],
                                           sizeof( ASDM_FPT_ENTRY ) );
                            usByteCount += sizeof( ASDM_FPT_ENTRY );
                        }

                        /* FPT secondary header */
                        pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                       &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xFptRecord.xFptHdrSecondary,
                                       sizeof( ASDM_FPT_HEADER ) );
                        usByteCount += sizeof( ASDM_FPT_HEADER );

                        /* FPT secondary partitions */
                        for( i = 0; i < pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xFptRecord.xFptHdrSecondary.ucNumEnteries;
                             i++ )
                        {
                            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xFptRecord.pxFptEntrySecondary[ i ],
                                           sizeof( ASDM_FPT_ENTRY ) );
                            usByteCount += sizeof( ASDM_FPT_ENTRY );
                        }
                    }
                    else
                    {
                        /* no FPT found, return OK to return empty SDR */
                        INC_ERROR_COUNTER( ASDM_ERRORS_AMI_SENSOR_REQUEST_EMPTY_SDR )
                        usByteCount += AMC_ASDM_EMPTY_SDR_SIZE;
                        iStatus      = OK;
                    }
                    break;
                }

                case AMC_ASDM_SUPPORTED_REPO_BOARD_INFO:
                {
                    if( 0 < pxThis->pxSensorList[ xAsdmRepo ].ucNumFound )
                    {
                        uint16_t usRespSizeBytes = 0;
                        iStatus = iPopulateAsdmSdrBoardInfoResponse( xRepo,
                                                                     &pucRespBuff[ usByteCount ],
                                                                     &usRespSizeBytes );
                        if( OK == iStatus )
                        {
                            usByteCount += usRespSizeBytes;
                        }
                    }
                    else
                    {
                        /* no board info found, return OK to return empty SDR */
                        INC_ERROR_COUNTER( ASDM_ERRORS_AMI_SENSOR_REQUEST_EMPTY_SDR )
                        usByteCount += AMC_ASDM_EMPTY_SDR_SIZE;
                        iStatus      = OK;
                    }
                    break;
                }

                default:
                {
                    iStatus = ERROR;
                    INC_ERROR_COUNTER( ASDM_ERRORS_AMI_UNSUPPORTED_REPO )
                    break;
                }
                }

                /* End of record */
                ucSize = sizeof( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pucAsdmEor );
                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pucAsdmEor,
                               sizeof( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pucAsdmEor ) );
                usByteCount += ucSize;

                /* Return the number bytes used in the response */
                *pusRespSizeBytes = usByteCount;

                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                {
                    INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_RELEASE_FAILED )
                    iStatus = ERROR;
                }
                else
                {
                    INC_STAT_COUNTER( ASDM_STATS_RELEASE_MUTEX )
                }
            }
            else
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_TAKE_FAILED )
                iStatus = ERROR;
            }
        }
    }
    return iStatus;
}

/**
 * @brief   Populate the get all sensors response back to the AMI proxy
 */
static int iPopulateAsdmGetAllSensorDataResponse( ASDM_REPOSITORY_TYPE xRepo,
                                                  uint8_t *pucRespBuff,
                                                  uint16_t *pusRespSizeBytes )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pucRespBuff ) &&
        ( NULL != pusRespSizeBytes ) )
    {
        INC_STAT_COUNTER( ASDM_STATS_ASDM_GET_ALL_SENSOR_API )
        AMC_ASDM_SUPPORTED_REPO xAsdmRepo = AMC_ASDM_SUPPORTED_REPO_MAX;

        /* Map the internal repo type from the AMI request */
        iStatus = iMapAsdmRepo( xRepo, &xAsdmRepo );

        if( OK == iStatus )
        {
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                      OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                uint16_t usByteCount   = 0;
                uint8_t  ucPayloadSize = 0;
                int      i             = 0;

                INC_STAT_COUNTER( ASDM_STATS_TAKE_MUTEX )

                /* SDR Completion code */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_CC ] = ASDM_SDR_COMPLETION_CODE_OPERATION_SUCCESS;
                usByteCount++;

                /* Repo Type */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_REPO_TYPE ] = xAsdmHeaderInfo[ xAsdmRepo ].ucRepoType;
                usByteCount++;

                /* Jump over the payload size to be populated at the end after sensors */
                usByteCount++;

                /* Sensor Values */
                for( i = 0; i < pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xHdr.ucTotalNumRecords; i++ )
                {
                    uint8_t ucSensorValueLen  = 0;
                    uint8_t ucSensorStatusLen = 0;

                    ucSensorValueLen = ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorValue.ucLength
                                         & ASDM_RECORD_FIELD_LENGTH_MASK );

                    ucSensorStatusLen = sizeof( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucSensorStatus );


                    /* Size of sensor Value + ( Snsr Val + Max Snsr Val + Snsr Avg) + sensor status */
                    ucPayloadSize += ( ( sizeof( ucSensorValueLen ) +
                                         ( SENSOR_RESPONSE_VALUES * ucSensorValueLen ) ) +
                                       ucSensorStatusLen );

                    /* Sensor Value Length */
                    pucRespBuff[ usByteCount++ ] = ucSensorValueLen;

                    /* Value */
                    pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                   &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorValue.ulValue,
                                   ucSensorValueLen );
                    usByteCount += ucSensorValueLen;

                    /* Max Value */
                    pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                   &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulMaxValue,
                                   ucSensorValueLen );
                    usByteCount += ucSensorValueLen;

                    /* Average Value */
                    pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                   &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulAverageValue,
                                   ucSensorValueLen );
                    usByteCount += ucSensorValueLen;

                    /* Status */
                    pucRespBuff[ usByteCount ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucSensorStatus;
                    usByteCount               += ucSensorStatusLen;
                }

                /* Payload size */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_SIZE ] = ucPayloadSize;

                /* Return the number bytes used in the response */
                *pusRespSizeBytes = usByteCount;

                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                {
                    INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_RELEASE_FAILED )
                    iStatus = ERROR;
                }
                else
                {
                    INC_STAT_COUNTER( ASDM_STATS_RELEASE_MUTEX )
                }
            }
            else
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_TAKE_FAILED )
                iStatus = ERROR;
            }
        }
    }
    return iStatus;
}

/**
 * @brief  Populate the get sdr size response back to the AMI proxy
 */
static int iPopulateAsdmGetSizeResponse( ASDM_REPOSITORY_TYPE xRepo,
                                         uint8_t *pucRespBuff,
                                         uint16_t *pusRespSizeBytes )
{
    int iStatus = ERROR;

    /*
     * Size of the SDR: Header, Sensor Records and End of Repo marker.
     */
    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pucRespBuff ) &&
        ( NULL != pusRespSizeBytes ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            uint16_t usSdrSize   = 0;
            uint16_t usByteCount = 0;

            INC_STAT_COUNTER( ASDM_STATS_TAKE_MUTEX )

            AMC_ASDM_SUPPORTED_REPO xAsdmRepo = AMC_ASDM_SUPPORTED_REPO_MAX;

            /* Map the internal repo type from the AMI request */
            iStatus = iMapAsdmRepo( xRepo, &xAsdmRepo );

            if( OK == iStatus )
            {
                /* SDR Completion code */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_CC ] = ASDM_SDR_COMPLETION_CODE_OPERATION_SUCCESS;
                usByteCount++;

                /* Repo Type */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_REPO_TYPE ] = xAsdmHeaderInfo[ xAsdmRepo ].ucRepoType;
                usByteCount++;

                /* Fill the Size of the SDR */
                usSdrSize = ( sizeof( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xHdr ) +
                              xAsdmHeaderInfo[ xAsdmRepo ].usTotalNumBytes +
                              sizeof( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pucAsdmEor ) );
                pvOSAL_MemCpy( &pucRespBuff[ ASDM_SDR_RESP_BYTE_SIZE ],
                               &usSdrSize,
                               sizeof( usSdrSize ) );
                usByteCount += sizeof( usSdrSize );

                /* Return the number bytes used in the response */
                *pusRespSizeBytes = usByteCount;

                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                {
                    INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_RELEASE_FAILED )
                    iStatus = ERROR;
                }
                else
                {
                    INC_STAT_COUNTER( ASDM_STATS_RELEASE_MUTEX )
                }
            }
        }
        else
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_TAKE_FAILED )
            iStatus = ERROR;
        }
    }

    return iStatus;
}

/**
 * @brief   Populate the get single sensor data response back to the AMI proxy
 */
static int iPopulateAsdmGetSingleSensorResponse( ASDM_REPOSITORY_TYPE xRepo,
                                                 uint8_t ucSensorId,
                                                 uint8_t *pucRespBuff,
                                                 uint16_t *pusRespSizeBytes )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pucRespBuff ) &&
        ( NULL != pusRespSizeBytes ) )
    {
        /* Return the instantaneous sensor data based on the input sensor Id */
        INC_STAT_COUNTER( ASDM_STATS_ASDM_GET_SINGLE_SENSOR_API )

        AMC_ASDM_SUPPORTED_REPO xAsdmRepo = AMC_ASDM_SUPPORTED_REPO_MAX;

        /* Map the internal repo type from the AMI request */
        iStatus = iMapAsdmRepo( xRepo, &xAsdmRepo );

        if( OK == iStatus )
        {
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                      OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                uint8_t  ucSensorValueLen  = 0;
                uint8_t  ucSensorStatusLen = 0;
                uint8_t  ucPayloadSize     = 0;
                uint16_t usByteCount       = 0;

                INC_STAT_COUNTER( ASDM_STATS_TAKE_MUTEX )

                /* SDR Completion code */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_CC ] = ASDM_SDR_COMPLETION_CODE_OPERATION_SUCCESS;
                usByteCount++;

                /* Repo Type */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_REPO_TYPE ] = xAsdmHeaderInfo[ xAsdmRepo ].ucRepoType;
                usByteCount++;

                /* Jump over the payload size to be populated at the end after sensors */
                usByteCount++;

                /* Sensor Value */
                ucSensorValueLen =
                    ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ ucSensorId ].xSensorName.ucLength
                      & ASDM_RECORD_FIELD_LENGTH_MASK );

                ucSensorStatusLen =
                    sizeof( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ ucSensorId ].ucSensorStatus );

                /* Size of sensor Value + ( Snsr Val + Max Snsr Val + Snsr Avg) + sensor status */
                ucPayloadSize += ( ( sizeof( ucSensorValueLen ) +
                                     ( SENSOR_RESPONSE_VALUES * ucSensorValueLen ) ) +
                                   ucSensorStatusLen );

                pucRespBuff[ usByteCount++ ] = ucSensorStatusLen;
                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ ucSensorId ].xSensorValue.ulValue,
                               ucSensorValueLen );
                usByteCount += ucSensorValueLen;
                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ ucSensorId ].ulMaxValue,
                               ucSensorValueLen );
                usByteCount += ucSensorValueLen;
                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ ucSensorId ].ulAverageValue,
                               ucSensorValueLen );
                usByteCount               += ucSensorValueLen;
                pucRespBuff[ usByteCount ] =
                    pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ ucSensorId ].ucSensorStatus,
                usByteCount += ucSensorStatusLen;

                /* Payload size */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_SIZE ] = ucPayloadSize;

                /* Return the number bytes used in the response */
                *pusRespSizeBytes = usByteCount;

                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                {
                    INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_RELEASE_FAILED )
                    iStatus = ERROR;
                }
                else
                {
                    INC_STAT_COUNTER( ASDM_STATS_RELEASE_MUTEX )
                }
            }
            else
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_TAKE_FAILED )
                iStatus = ERROR;
            }
        }
    }

    return ( iStatus );
}

/**
 * @brief   Calculate the total power using the data received from the ASC
 */
static int iCalculateTotalPower( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxThis->pxAscData ) &&
        ( NULL != pxThis->pxAsdmSdrInfo ) )
    {
        /* Loop around the list of power sensors and calculate the total power */
        uint8_t  ucTotalNumRecords = pxThis->pxSensorList[ AMC_ASDM_SUPPORTED_REPO_POWER ].ucNumFound;
        int      iSensorIdx        = 0;
        uint32_t ulTotalPower      = 0;

        /* Set initial suceess */
        iStatus = OK;

        for( iSensorIdx = 0; iSensorIdx < ucTotalNumRecords; iSensorIdx++ )
        {
            /* Pointer to the ASDM sensor record */
            ASDM_SDR_RECORD *pxSensorRecord = pxThis->pxAsdmSdrInfo[ AMC_ASDM_SUPPORTED_REPO_POWER ].pxSensorRecord;
            if( NULL != pxSensorRecord )
            {
                /* Check the ASC data if this sensor is part of the power calculation */
                int iAscDataIdx = pxThis->pxSensorList[ AMC_ASDM_SUPPORTED_REPO_POWER ].pucSensorIndex[ iSensorIdx ];
                if( TRUE == pxThis->pxAscData[ iAscDataIdx ].ucTotalPowerSensor )
                {
                    ulTotalPower += pxSensorRecord[ iSensorIdx ].xSensorValue.ulValue;
                }
            }
            else
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_ASDM_GET_SDR_FAILED )
                iStatus = ERROR;
                break;
            }
        }

        if( OK == iStatus )
        {
            /* Update the average & max values */
            pxThis->ulPowerCalcIterations++;
            if( ulTotalPower > pxThis->ulMaxPower )
            {
                pxThis->ulMaxPower = ulTotalPower;
            }
            pxThis->ulAveragePower = ( pxThis->ulAveragePower
                                       - ( pxThis->ulAveragePower / pxThis->ulPowerCalcIterations )
                                       + ( ulTotalPower / pxThis->ulPowerCalcIterations ) );


            /* Update the total power ASDM store with the calculated value */
            ASDM_SDR_RECORD *pxSensorRecord =
                pxThis->pxAsdmSdrInfo[ AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER ].pxSensorRecord;
            if( NULL != pxSensorRecord )
            {
                pxSensorRecord->ulAverageValue       = pxThis->ulAveragePower;
                pxSensorRecord->ulMaxValue           = pxThis->ulMaxPower;
                pxSensorRecord->xSensorValue.ulValue = ulTotalPower;
            }
            else
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_ASDM_GET_SDR_FAILED )
                iStatus = ERROR;
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Get the FPT data from the APC
 */
static int iGetFptData( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL == pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_PRIMARY ] ) &&
        ( NULL == pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_SECONDARY ] ) )
    {
        for( int i = APC_BOOT_DEVICE_PRIMARY; i < MAX_APC_BOOT_DEVICES; i++ )
        {
            /* Get the FPT header from the APC */
            iStatus = iAPC_GetFptHeader( ( APC_BOOT_DEVICES )i, &pxThis->pxFptHeader[ i ] );
            if( OK == iStatus )
            {
                INC_STAT_COUNTER( ASDM_STATS_GET_FPT_HEADER )

                pxThis->ppxFptPartitions[ i ] =
                    ( APC_PROXY_DRIVER_FPT_PARTITION * )pvOSAL_MemAlloc(
                        pxThis->pxFptHeader[ i ].ucNumEntries *
                        sizeof( APC_PROXY_DRIVER_FPT_PARTITION ) );

                if( NULL != pxThis->ppxFptPartitions[ i ] )
                {
                    int j = 0;

                    INC_STAT_COUNTER( ASDM_STATS_MALLOC )

                    for( j = 0; j < pxThis->pxFptHeader[ i ].ucNumEntries; j++ )
                    {
                        iStatus = iAPC_GetFptPartition( ( APC_BOOT_DEVICES )i, j, &pxThis->ppxFptPartitions[ i ][ j ] );
                        if( OK != iStatus )
                        {
                            INC_ERROR_COUNTER( ASDM_ERRORS_APC_PARTITION_INFO )
                            vOSAL_MemFree( ( void** )&pxThis->ppxFptPartitions[ i ] );
                            break;
                        }
                        INC_STAT_COUNTER( ASDM_STATS_GET_FPT_PARTITION )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER( ASDM_ERRORS_MALLOC_FAILED )
                }
            }
            else
            {
                /* on a failure, check the device type before returning status */
                if( APC_BOOT_DEVICE_PRIMARY == i )
                {
                    /* return Error, as primary FPT is required */
                    INC_ERROR_COUNTER( ASDM_ERRORS_APC_PARTITION_HEADER )
                    break;
                }
                else if( APC_BOOT_DEVICE_SECONDARY == i )
                {
                    /* ensure secondary FPT header empty */
                    pxThis->pxFptHeader[ i ].ulMagicNum      = 0;
                    pxThis->pxFptHeader[ i ].ucFptVersion    = 0;
                    pxThis->pxFptHeader[ i ].ucFptHeaderSize = 0;
                    pxThis->pxFptHeader[ i ].ucEntrySize     = 0;
                    pxThis->pxFptHeader[ i ].ucNumEntries    = 0;
                    /* return OK, as secondary FPT is optional */
                    iStatus = OK;
                }
            }

        }
    }

    return ( iStatus );
}

/**
 * @brief   Populate the FPT ASDM
 */
static int iPopulateAsdmFpt( uint16_t *pusByteCount )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( pusByteCount != NULL ) )
    {
        int      iRepoIndex     = AMC_ASDM_SUPPORTED_REPO_FPT;
        uint16_t usByteCount    = 0;
        uint16_t usAllocateSize = 0;

        /* Populate FPT Header (primary) */
        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrPrimary.ucFptVersion =
            pxThis->pxFptHeader[ APC_BOOT_DEVICE_PRIMARY ].ucFptVersion;
        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrPrimary.ucNumEnteries =
            pxThis->pxFptHeader[ APC_BOOT_DEVICE_PRIMARY ].ucNumEntries;
        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrPrimary.ucFptEntrySize =
            pxThis->pxFptHeader[ APC_BOOT_DEVICE_PRIMARY ].ucEntrySize;
        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrPrimary.ucFptHeaderSize =
            pxThis->pxFptHeader[ APC_BOOT_DEVICE_PRIMARY ].ucFptHeaderSize;
        /* Populate FPT Header (secondary) */
        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrSecondary.ucFptVersion =
            pxThis->pxFptHeader[ APC_BOOT_DEVICE_SECONDARY ].ucFptVersion;
        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrSecondary.ucNumEnteries =
            pxThis->pxFptHeader[ APC_BOOT_DEVICE_SECONDARY ].ucNumEntries;
        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrSecondary.ucFptEntrySize =
            pxThis->pxFptHeader[ APC_BOOT_DEVICE_SECONDARY ].ucEntrySize;
        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.xFptHdrSecondary.ucFptHeaderSize =
            pxThis->pxFptHeader[ APC_BOOT_DEVICE_SECONDARY ].ucFptHeaderSize;

        usByteCount += sizeof( ASDM_FPT_RECORD );

        /* Populate FPT partition information (primary) */
        usAllocateSize = sizeof( ASDM_FPT_ENTRY ) * pxThis->pxFptHeader[ APC_BOOT_DEVICE_PRIMARY ].ucNumEntries;

        pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary =
            ( ASDM_FPT_ENTRY * )pvOSAL_MemAlloc( usAllocateSize );

        if( ( NULL != pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary ) &&
            ( NULL != pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_PRIMARY ] ) )
        {
            int i = 0;

            INC_STAT_COUNTER( ASDM_STATS_MALLOC )

            for( i = 0; i < pxThis->pxFptHeader[ APC_BOOT_DEVICE_PRIMARY ].ucNumEntries; i++ )
            {
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary[ i ].ulType =
                    pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_PRIMARY ][ i ].ulPartitionType;
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary[ i ].ulBaseAddr =
                    pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_PRIMARY ][ i ].ulPartitionBaseAddr;
                pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary[ i ].ulPartitionSize =
                    pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_PRIMARY ][ i ].ulPartitionSize;
                usByteCount += sizeof( ASDM_FPT_ENTRY );
            }

            iStatus = OK;
        }
        else
        {
            vOSAL_MemFree( ( void** )&pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary );
            INC_ERROR_COUNTER( ASDM_ERRORS_MALLOC_FAILED )
        }

        /* Populate FPT partition information (secondary) */
        if( OK == iStatus )
        {
            iStatus        = ERROR;
            usAllocateSize = sizeof( ASDM_FPT_ENTRY ) * pxThis->pxFptHeader[ APC_BOOT_DEVICE_SECONDARY ].ucNumEntries;

            pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary =
                ( ASDM_FPT_ENTRY * )pvOSAL_MemAlloc( usAllocateSize );

            if( ( NULL != pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary ) &&
                ( NULL != pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_SECONDARY ] ) )
            {
                int i = 0;

                INC_STAT_COUNTER( ASDM_STATS_MALLOC )

                for( i = 0; i < pxThis->pxFptHeader[ APC_BOOT_DEVICE_SECONDARY ].ucNumEntries; i++ )
                {
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary[ i ].ulType =
                        pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_SECONDARY ][ i ].ulPartitionType;
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary[ i ].ulBaseAddr =
                        pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_SECONDARY ][ i ].ulPartitionBaseAddr;
                    pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary[ i ].ulPartitionSize =
                        pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_SECONDARY ][ i ].ulPartitionSize;
                    usByteCount += sizeof( ASDM_FPT_ENTRY );
                }

                iStatus = OK;
            }
            else
            {
                vOSAL_MemFree( ( void** )&pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary );
                INC_ERROR_COUNTER( ASDM_ERRORS_MALLOC_FAILED )

                /* return OK, as secondary FPT is optional */
                iStatus = OK;
            }

            *pusByteCount = usByteCount;
        }
    }

    return ( iStatus );
}

/**
 * @brief   Get the Board info data from the EEPROM driver
 */
static int iGetBoardInfoData( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL == pxThis->pxBoardInfo ) )
    {
        uint8_t pucField[ EEPROM_MAX_FIELD_SIZE ] =
        {
            0
        };
        uint8_t ucFieldLen = 0;

        pxThis->pxBoardInfo = ( ASDM_BOARD_INFO_RECORD * )pvOSAL_MemAlloc(
            sizeof( ASDM_BOARD_INFO_RECORD ) );

        if( NULL != pxThis->pxBoardInfo )
        {
            pvOSAL_MemSet( pxThis->pxBoardInfo, 0, sizeof( ASDM_BOARD_INFO_RECORD ) );

            /* EEPROM Version */
            iStatus = iEEPROM_GetEepromVersion( pucField, &ucFieldLen );
            if( OK == iStatus )
            {
                ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                pxThis->pxBoardInfo->xEepromVersion.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII;
                pxThis->pxBoardInfo->xEepromVersion.ucLength = ( ucFieldLen &
                                                                 ASDM_RECORD_FIELD_LENGTH_MASK );
                pvOSAL_MemCpy( pxThis->pxBoardInfo->xEepromVersion.pucBytesValue,
                               pucField,
                               ucFieldLen );
            }

            /* Product Name */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetProductName( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xProductName.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII;
                    pxThis->pxBoardInfo->xProductName.ucLength = ( ucFieldLen &
                                                                   ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xProductName.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* Board Revision */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetProductRevision( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xBoardRev.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII;
                    pxThis->pxBoardInfo->xBoardRev.ucLength = ( ucFieldLen &
                                                                ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xBoardRev.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* Board Serial */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetSerialNumber( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xBoardSerial.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII;
                    pxThis->pxBoardInfo->xBoardSerial.ucLength = ( ucFieldLen &
                                                                   ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xBoardSerial.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* MAC address count*/
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetMacAddressCount( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    pxThis->pxBoardInfo->xMacAddressCount.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_NUM;
                    pxThis->pxBoardInfo->xMacAddressCount.ucLength = ( sizeof( uint8_t ) &
                                                                       ASDM_RECORD_FIELD_LENGTH_MASK );
                    pxThis->pxBoardInfo->xMacAddressCount.ulValue = pucField[ 0 ];
                }
            }

            /* First MAC Address */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetFirstMacAddress( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xFirstMacAddress.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_BYTE_ARRAY;
                    pxThis->pxBoardInfo->xFirstMacAddress.ucLength = ( ucFieldLen &
                                                                       ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xFirstMacAddress.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* Active State */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetActiveState( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xActiveState.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII;
                    pxThis->pxBoardInfo->xActiveState.ucLength = ( ucFieldLen &
                                                                   ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xActiveState.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* Config Mode */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetConfigMode( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xConfigMode.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_BYTE_ARRAY;
                    pxThis->pxBoardInfo->xConfigMode.ucLength = ( ucFieldLen &
                                                                  ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xConfigMode.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* Manufacturing Date */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetManufacturingDate( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xManufacturingDate.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_BYTE_ARRAY;
                    pxThis->pxBoardInfo->xManufacturingDate.ucLength = ( ucFieldLen &
                                                                         ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xManufacturingDate.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* Part Number */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetPartNumber( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xPartNumber.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII;
                    pxThis->pxBoardInfo->xPartNumber.ucLength = ( ucFieldLen &
                                                                  ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xPartNumber.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* UUID */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetUuid( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xUuid.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_BYTE_ARRAY;
                    pxThis->pxBoardInfo->xUuid.ucLength = ( ucFieldLen &
                                                            ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xUuid.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* PCIe Id */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetPcieId( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xPcieId.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_BYTE_ARRAY;
                    pxThis->pxBoardInfo->xPcieId.ucLength = ( ucFieldLen &
                                                              ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xPcieId.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* Power mode */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetMaxPowerMode( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xMaxPowerMode.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_BYTE_ARRAY;
                    pxThis->pxBoardInfo->xMaxPowerMode.ucLength = ( ucFieldLen &
                                                                    ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xMaxPowerMode.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* Memory Size */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetMemorySize( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xMemorySize.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII;
                    pxThis->pxBoardInfo->xMemorySize.ucLength = ( ucFieldLen &
                                                                  ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xMemorySize.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* OEM id */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetOemId( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xOemId.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_BYTE_ARRAY;
                    pxThis->pxBoardInfo->xOemId.ucLength = ( ucFieldLen &
                                                             ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xOemId.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* Capability */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetCapability( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xCapability.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_BYTE_ARRAY;
                    pxThis->pxBoardInfo->xCapability.ucLength = ( ucFieldLen &
                                                                  ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xCapability.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }

            /* Manufacturing Part Number */
            if( OK == iStatus )
            {
                iStatus = iEEPROM_GetMfgPartNumber( pucField, &ucFieldLen );
                if( OK == iStatus )
                {
                    ucFieldLen = MIN( ucFieldLen, ( ASDM_RECORD_FIELD_BYTES_MAX - 1 ) );
                    pxThis->pxBoardInfo->xMfgPartNumber.ucType   = ASDM_RECORD_FIELD_TYPE_CODE_8_BIT_ASCII;
                    pxThis->pxBoardInfo->xMfgPartNumber.ucLength = ( ucFieldLen &
                                                                     ASDM_RECORD_FIELD_LENGTH_MASK );
                    pvOSAL_MemCpy( pxThis->pxBoardInfo->xMfgPartNumber.pucBytesValue,
                                   pucField,
                                   ucFieldLen );
                }
            }
        }
        else
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_MALLOC_FAILED )
        }
    }

    if( OK != iStatus )
    {
        INC_ERROR_COUNTER( ASDM_ERRORS_ASDM_POPULATE_BDINFO_FAILED )
    }

    return ( iStatus );
}

/**
 * @brief   Populate the Board Info ASDM
 */
static int iPopulateAsdmBoardInfo( uint16_t *pusByteCount )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxThis->pxBoardInfo ) &&
        ( NULL != pusByteCount ) )
    {
        int iRepoIndex = AMC_ASDM_SUPPORTED_REPO_BOARD_INFO;

        /* Use the already allocated table */
        pxThis->pxAsdmSdrInfo[ iRepoIndex ].pxBoardInfo = pxThis->pxBoardInfo;
        *pusByteCount = sizeof( ASDM_BOARD_INFO_RECORD );
        iStatus       = OK;
    }

    return ( iStatus );
}

/**
 * @brief   Populate the board info response into the buffer
 */
static int iPopulateAsdmSdrBoardInfoResponse( ASDM_REPOSITORY_TYPE xRepo,
                                              uint8_t *pucRespBuff,
                                              uint16_t *pusRespSizeBytes )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pucRespBuff ) &&
        ( NULL != pusRespSizeBytes ) )
    {
        uint16_t usByteCount = 0;

        AMC_ASDM_SUPPORTED_REPO xAsdmRepo = AMC_ASDM_SUPPORTED_REPO_MAX;

        /* Map the internal repo type from the AMI request */
        iStatus = iMapAsdmRepo( xRepo, &xAsdmRepo );

        if( OK == iStatus )
        {
            /* Eeprom */
            uint8_t ucFieldLen = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xEepromVersion.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xEepromVersion.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xEepromVersion.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* Product name */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xProductName.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xProductName.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xProductName.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* Board revision */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xBoardRev.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xBoardRev.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xBoardRev.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* Board serial */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xBoardSerial.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xBoardSerial.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xBoardSerial.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* MAC address */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMacAddressCount.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMacAddressCount.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMacAddressCount.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* First MAC address */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xFirstMacAddress.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xFirstMacAddress.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xFirstMacAddress.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* Active state */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xActiveState.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xActiveState.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xActiveState.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* Config mode */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xConfigMode.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xConfigMode.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xConfigMode.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* Manufacturing date */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xManufacturingDate.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xManufacturingDate.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xManufacturingDate.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* Part number */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xPartNumber.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xPartNumber.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xPartNumber.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* UUID */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xUuid.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xUuid.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xUuid.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* PCIe Id */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xPcieId.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xPcieId.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xPcieId.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* PowerMode */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMaxPowerMode.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMaxPowerMode.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMaxPowerMode.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* Memory Size */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMemorySize.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMemorySize.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMemorySize.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* OEM Id */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xOemId.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xOemId.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xOemId.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* Capability */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xCapability.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xCapability.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xCapability.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            /* Manufacturer Part Number */
            ucFieldLen                   = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMfgPartNumber.ucLength;
            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMfgPartNumber.ucType;
            pucRespBuff[ usByteCount++ ] = ucFieldLen;
            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxBoardInfo->xMfgPartNumber.pucBytesValue,
                           ucFieldLen );
            usByteCount += ucFieldLen;

            *pusRespSizeBytes = usByteCount;
            iStatus           = OK;
        }
    }

    return ( iStatus );
}

/**
 * @brief   Update all FPT data
 */
static int iRefreshFptData( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( ASDM_STATS_TAKE_MUTEX )

            pvOSAL_MemSet( &pxThis->pxFptHeader[ APC_BOOT_DEVICE_PRIMARY ],
                           0x00,
                           sizeof( pxThis->pxFptHeader[ APC_BOOT_DEVICE_PRIMARY ] ) );
            pvOSAL_MemSet( &pxThis->pxFptHeader[ APC_BOOT_DEVICE_SECONDARY ],
                           0x00,
                           sizeof( pxThis->pxFptHeader[ APC_BOOT_DEVICE_SECONDARY ] ) );

            if( NULL != pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_PRIMARY ] )
            {
                vOSAL_MemFree( ( void** )&pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_PRIMARY ] );
                INC_STAT_COUNTER( ASDM_STATS_FREE )
            }
            if( NULL != pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_SECONDARY ] )
            {
                vOSAL_MemFree( ( void** )&pxThis->ppxFptPartitions[ APC_BOOT_DEVICE_SECONDARY ] );
                INC_STAT_COUNTER( ASDM_STATS_FREE )
            }

            iStatus = iGetFptData();

            if( OK == iStatus )
            {
                /* Update ASDM */
                iStatus = iUpdateAsdmFpt();
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( ASDM_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_TAKE_FAILED )
            iStatus = ERROR;
        }
    }

    return ( iStatus );
}

/**
 * @brief   Repopulate ASDM FPT data
 */
static int iUpdateAsdmFpt( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int      iRepoIndex = AMC_ASDM_SUPPORTED_REPO_FPT;
        uint16_t usBytes    = ASDM_HEADER_DEFAULT_BYTES;

        /* Delete the existing entries */
        if( NULL != pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary )
        {
            vOSAL_MemFree( ( void** )&pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntryPrimary );
            INC_STAT_COUNTER( ASDM_STATS_FREE )
        }
        if( NULL != pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary )
        {
            vOSAL_MemFree( ( void** )&pxThis->pxAsdmSdrInfo[ iRepoIndex ].xFptRecord.pxFptEntrySecondary );
            INC_STAT_COUNTER( ASDM_STATS_FREE )
        }

        /* Repopulate data */
        if( OK == iPopulateAsdmFpt( &usBytes ) )
        {
            /* See `iInitAsdm` for this calculation */
            if( 0 != ( usBytes % TOTAL_NUM_BYTES_MULTIPLE ) )
            {
                uint8_t ucTmp = ( usBytes % TOTAL_NUM_BYTES_MULTIPLE );
                usBytes += ( TOTAL_NUM_BYTES_MULTIPLE - ucTmp );
            }

            pxThis->pxAsdmSdrInfo[ iRepoIndex ].xHdr.usTotalNumBytes =
                ( usBytes / TOTAL_NUM_BYTES_MULTIPLE );

            iStatus = OK;
        }
    }

    return iStatus;
}

/**
 * @brief   Populate the get all sensors response back to the RMI Handler
 */
static int iPopulateAsdmGetSdrResponseV2( ASDM_REPOSITORY_TYPE xRepo,
                                          uint8_t *pucRespBuff,
                                          uint16_t *pusRespSizeBytes )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pucRespBuff ) &&
        ( NULL != pusRespSizeBytes ) )
    {
        INC_STAT_COUNTER( ASDM_STATS_ASDM_GET_SDR_API )

        AMC_ASDM_SUPPORTED_REPO xAsdmRepo = AMC_ASDM_SUPPORTED_REPO_MAX;

        /* Map the internal repo type from the AMI request */
        iStatus = iMapAsdmRepo( xRepo, &xAsdmRepo );

        if( OK == iStatus )
        {
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                      OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                uint16_t usByteCount = 0;
                uint8_t  ucSize      = 0;
                int      i           = 0;

                INC_STAT_COUNTER( ASDM_STATS_TAKE_MUTEX )

                /* SDR Completion code */
                pucRespBuff[ usByteCount++ ] = ASDM_SDR_COMPLETION_CODE_OPERATION_SUCCESS;

                /* SDR Header */
                ucSize = sizeof( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xHdr );
                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xHdr,
                               ucSize );
                usByteCount += ucSize;

                switch( xAsdmRepo )
                {
                case AMC_ASDM_SUPPORTED_REPO_TEMP:
                case AMC_ASDM_SUPPORTED_REPO_VOLTAGE:
                case AMC_ASDM_SUPPORTED_REPO_CURRENT:
                case AMC_ASDM_SUPPORTED_REPO_POWER:
                case AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER:
                {
                    if( 0 < pxThis->pxSensorList[ xAsdmRepo ].ucNumFound )
                    {
                        /* Populate each SDR */
                        for( i = 0; i < pxThis->pxAsdmSdrInfo[ xAsdmRepo ].xHdr.ucTotalNumRecords; i++ )
                        {
                            uint8_t ucSensorValueLen   = 0;
                            uint8_t ucValueLen         = 0;
                            uint8_t ucBaseUnitValueLen = 0;
                            uint8_t ucType             = 0;
                            uint8_t ucTypeLenField     = 0;

                            /* Id */
                            pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucId;

                            /* Sensor Name */
                            ucSensorValueLen =
                                ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorName.ucLength
                                  & ASDM_RECORD_FIELD_LENGTH_MASK );
                            ucType = ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorName.ucType
                                       & ASDM_RECORD_FIELD_TYPE_MASK );
                            ucTypeLenField = ( ucSensorValueLen | ( ucType <<
                                                                    ASDM_RECORD_FIELD_TYPE_POS ) );
                            pucRespBuff[ usByteCount++ ] = ucTypeLenField;
                            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorName.
                                           pucBytesValue,
                                           ucSensorValueLen );
                            usByteCount += ucSensorValueLen;

                            /* Sensor Value */
                            ucValueLen = ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorValue.ucLength
                                           & ASDM_RECORD_FIELD_LENGTH_MASK );
                            ucType = ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorValue.ucType
                                       & ASDM_RECORD_FIELD_TYPE_MASK );
                            ucTypeLenField               = ( ucValueLen | ( ucType << ASDM_RECORD_FIELD_TYPE_POS ) );
                            pucRespBuff[ usByteCount++ ] = ucTypeLenField;
                            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorValue.ulValue,
                                           ucValueLen );
                            usByteCount += ucValueLen;

                            /* Base Unit */
                            ucBaseUnitValueLen =
                                ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorBaseUnit.ucLength
                                  & ASDM_RECORD_FIELD_LENGTH_MASK );
                            ucType = ( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorBaseUnit.ucType
                                       & ASDM_RECORD_FIELD_TYPE_MASK );
                            ucTypeLenField = ( ucBaseUnitValueLen | ( ucType <<
                                                                      ASDM_RECORD_FIELD_TYPE_POS ) );
                            pucRespBuff[ usByteCount++ ] = ucTypeLenField;
                            pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                           &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorBaseUnit.
                                           pucBytesValue,
                                           ucBaseUnitValueLen );
                            usByteCount += ucBaseUnitValueLen;

                            /* Unit Modifier*/
                            pucRespBuff[ usByteCount++ ] =
                                pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].cUnitModifier;

                            /* Threshold Support Byte */
                            pucRespBuff[ usByteCount++ ] =
                                pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask;

                            /* Lower Fatal Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_LOWER_FATAL_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulLowerFatalLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Lower Critical Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_LOWER_CRITICAL_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulLowerCritLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Lower Warning Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_LOWER_WARNING_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulLowerWarnLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Upper Fatal Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_UPPER_FATAL_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulUpperFatalLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Upper Critical Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_UPPER_CRITICAL_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulUpperCritLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Upper Warning Limit*/
                            if( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucThresholdSupportedBitMask &
                                ASDM_SDR_THRESHOLD_UPPER_WARNING_MASK )
                            {
                                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ulUpperWarnLimit,
                                               ucValueLen );
                                usByteCount += ucValueLen;
                            }

                            /* Sensor Status */
                            pucRespBuff[ usByteCount++ ] =
                                pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucSensorStatus;
                        }
                    }
                    else
                    {
                        /* no sensor data found, return OK to return empty SDS */
                        INC_ERROR_COUNTER( ASDM_ERRORS_AMI_SENSOR_REQUEST_EMPTY_SDR )
                        usByteCount += AMC_ASDM_EMPTY_SDR_SIZE;
                        iStatus      = OK;
                    }
                    break;
                }

                default:
                {
                    iStatus = ERROR;
                    INC_ERROR_COUNTER( ASDM_ERRORS_AMI_UNSUPPORTED_REPO )
                    break;
                }
                }

                /* End of record */
                ucSize = sizeof( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pucAsdmEor );
                pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                               &pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pucAsdmEor,
                               sizeof( pxThis->pxAsdmSdrInfo[ xAsdmRepo ].pucAsdmEor ) );
                usByteCount += ucSize;

                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                {
                    INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_RELEASE_FAILED )
                    iStatus = ERROR;
                }
                else
                {
                    INC_STAT_COUNTER( ASDM_STATS_RELEASE_MUTEX )
                }
            }
            else
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_TAKE_FAILED )
                iStatus = ERROR;
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Populate the get all sensors response back to the RMI Handler
 */
static int iPopulateAsdmGetAllSensorDataResponseV2( ASDM_REPOSITORY_TYPE xRepo,
                                                    uint8_t *pucRespBuff,
                                                    uint16_t *pusRespSizeBytes )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pucRespBuff ) &&
        ( NULL != pusRespSizeBytes ) )
    {
        INC_STAT_COUNTER( ASDM_STATS_ASDM_GET_ALL_SENSOR_API )
        AMC_ASDM_SUPPORTED_REPO xAsdmRepo = AMC_ASDM_SUPPORTED_REPO_MAX;

        /* Map the internal repo type from the AMI request */
        iStatus = iMapAsdmRepo( xRepo, &xAsdmRepo );

        if( OK == iStatus )
        {
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                      OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                uint16_t usByteCount   = 0;
                uint8_t  ucPayloadSize = 0;
                int      i             = 0;

                INC_STAT_COUNTER( ASDM_STATS_TAKE_MUTEX )

                /* SDR Completion code */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_CC ] = ASDM_SDR_COMPLETION_CODE_OPERATION_SUCCESS;
                usByteCount++;

                /* Repo Type */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_REPO_TYPE ] = xAsdmHeaderInfo[ xAsdmRepo ].ucRepoType;
                usByteCount++;

                /* Jump over the payload size to be populated at the end after sensors */
                usByteCount++;

                /* Sensor Values */
                for( i = 0; i < pxThis->pxAsdmSdsInfo[ xAsdmRepo ].xHdr.ucTotalNumRecords; i++ )
                {
                    uint8_t ucSensorValueLen  = 0;
                    uint8_t ucSensorStatusLen = 0;
                    uint8_t ucSensorTagLen    = 0;

                    /* Id */
                    pucRespBuff[ usByteCount++ ] = pxThis->pxAsdmSdsInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucId;

                    ucSensorValueLen = ( pxThis->pxAsdmSdsInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorValue.ucLength
                                         & ASDM_RECORD_FIELD_LENGTH_MASK );

                    /* Size of sensor Value + Snsr Val + sensor status */
                    ucPayloadSize += ( ( sizeof( ucSensorValueLen ) + ucSensorValueLen ) + ucSensorStatusLen );

                    /* Sensor Value Length */
                    pucRespBuff[ usByteCount++ ] = ucSensorValueLen;

                    /* Value */
                    pvOSAL_MemCpy( &pucRespBuff[ usByteCount ],
                                   &pxThis->pxAsdmSdsInfo[ xAsdmRepo ].pxSensorRecord[ i ].xSensorValue.ulValue,
                                   ucSensorValueLen );
                    usByteCount += ucSensorValueLen;

                    /* Status */
                    pucRespBuff[ usByteCount ] = pxThis->pxAsdmSdsInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucSensorStatus;
                    ucSensorStatusLen          =
                        sizeof( pxThis->pxAsdmSdsInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucSensorStatus );
                    usByteCount += ucSensorStatusLen;

                    /* Sensor Tag */
                    pucRespBuff[ usByteCount ] = pxThis->pxAsdmSdsInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucSensorTag;
                    ucSensorTagLen             =
                        sizeof( pxThis->pxAsdmSdsInfo[ xAsdmRepo ].pxSensorRecord[ i ].ucSensorTag );
                    usByteCount += ucSensorTagLen;
                }

                /* Payload size */
                pucRespBuff[ ASDM_SDR_RESP_BYTE_SIZE ] = ucPayloadSize;

                /* Return the number bytes used in the response */
                *pusRespSizeBytes = usByteCount;

                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                {
                    INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_RELEASE_FAILED )
                    iStatus = ERROR;
                }
                else
                {
                    INC_STAT_COUNTER( ASDM_STATS_RELEASE_MUTEX )
                }
            }
            else
            {
                INC_ERROR_COUNTER( ASDM_ERRORS_MUTEX_TAKE_FAILED )
                iStatus = ERROR;
            }
        }
    }

    return iStatus;
}

/**
 * @brief  Map the ASDM repo type to the SDS sensor tag
 */
static int iMapSensorTag( AMC_ASDM_SUPPORTED_REPO xAsdmRepo,
                          ASDM_SDS_SENSOR_TAG *pxSensorTag )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxSensorTag ) )
    {
        *pxSensorTag = ASDM_SDS_SENSOR_TAG_MAX;
        switch( xAsdmRepo )
        {
        case AMC_ASDM_SUPPORTED_REPO_TEMP:
        {
            *pxSensorTag = ASDM_SDS_SENSOR_TAG_BOARD_TEMP;
            iStatus      = OK;
            break;
        }

        case AMC_ASDM_SUPPORTED_REPO_VOLTAGE:
        {
            *pxSensorTag = ASDM_SDS_SENSOR_TAG_VOLTAGE;
            iStatus      = OK;
            break;
        }

        case AMC_ASDM_SUPPORTED_REPO_CURRENT:
        {
            *pxSensorTag = ASDM_SDS_SENSOR_TAG_CURRENT;
            iStatus      = OK;
            break;
        }

        case AMC_ASDM_SUPPORTED_REPO_POWER:
        case AMC_ASDM_SUPPORTED_REPO_TOTAL_POWER:
        {
            *pxSensorTag = ASDM_SDS_SENSOR_TAG_POWER;
            iStatus      = OK;
            break;
        }

        default:
        {
            INC_ERROR_COUNTER( ASDM_ERRORS_SENSOR_TAG_MAPPING )
            break;
        }
        }
    }

    return iStatus;
}
