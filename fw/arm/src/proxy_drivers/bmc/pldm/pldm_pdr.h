/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains PLDM PDR enums, structures and functions
 *
 * @file pldm_pdr.h
 *
 */

#ifndef PLDM_PDR_H_
#define PLDM_PDR_H_


/******************************************************************************/
/* Includes                                                                    */
/******************************************************************************/

#include "standard.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define PDR_HEADER_VERSION 0x1

#define PLDM_ENTITY_ADDIN_CARD ( 68 )
#define PDR_PARAM_NONE         ( 0 )
#define EFFECTER_MAX_VALUE     ( 1 )
#define EFFECTER_MIN_VALUE     ( 0 )
#define MILLISECOND( x ) ( ( float )x / 1000 )
#define UNITS_IN_MILLI ( -3 )

/* Macros to set bits for 'rangeFieldSupport' field in PDR */
#define NORMAL_MIN_MAX  ( 0x3 << 1 )
#define RATED_MIN_MAX   ( 0x3 << 3 )
#define HIGH_THRESHOLDS ( 0x5 << 3 )
#define LOW_THRESHOLDS  ( 0x5 << 4 )
#define NOMINAL_VALUE   ( 0x1 )
/* Macros to set bits for 'supportedThresholds' field in PDR */
#define HAS_LOW_THRESHOLDS  ( 0x7 << 3 )
#define HAS_HIGH_THRESHOLDS ( 0x7 )

#define CONTAINER_ENTITY_CONTAINER_ID 1
#define CONTAINED_ENTITY_CONTAINER_ID 1000

#define PLDM_ENTITY_ACCELERATOR_PROCESSOR 149                                  // (DSP2061)

#define TOTAL_PDR_COUNT_TERMINUS ( 1 )

#define TOTAL_PDR_COUNT_STATE_SENSORS ( 0 )
#define TOTAL_PDR_COUNT_NAME          ( 38 )                                   //TOTAL_PDR_NUMERIC_ASCI_SENSORS

#define TOTAL_PDR_COUNT_NUMERIC_EFFECTER ( 5 )
#define TOTAL_PDR_COUNT_EFFECTER_NAME    TOTAL_PDR_COUNT_NUMERIC_EFFECTER

#define TOTAL_PDR_COUNT (              \
            TOTAL_PDR_COUNT_TERMINUS + \
            ( TOTAL_PDR_COUNT_NAME * 2 ) )

#define MAX_NAME_SIZE 32

#define PLDM_TIME_STAMP_YEAR_MASK  ( 0xFFFF )
#define PLDM_TIME_STAMP_MONTH_MASK ( 0x00FF )
#define PLDM_TIME_STAMP_DAY_MASK   ( 0x00FF )


/******************************************************************************/
/* Typedefs                                                                      */
/******************************************************************************/

typedef uint8_t enum8_t;
typedef uint8_t bool8_t;
typedef float real32_t;
typedef uint8_t bitfield8_t;
typedef uint16_t bitfield16_t;
typedef uint32_t bitfield32_t;

/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    RepoState
 * @brief   PDR Repo States
 */
enum RepoState
{
    ERepoStateAvailable,
    ERepoStateUpdateInprogress,
    ERepoStateFailed

};

/**
 * @enum    InitStatus
 * @brief   Init status types
 */
enum InitStatus
{
    eNoInit,
    eUseInitPDR,
    eEnable,
    eDisable

};

/**
 * @enum    BaseUnit
 * @brief   BaseUnit enumeration values
 */
enum BaseUnit
{
    eNoUnit   = 00,
    eDegreesC = 02,
    eVolts    = 05,
    eAmps     = 06,
    eWatts    = 07,
    eHertz    = 20,
    eCounts   = 67

};

/**
 * @enum    RateUnit
 * @brief   RateUnit enumeration values
 */
enum RateUnit
{
    eNone,
    ePerMicroSecond,
    ePerMilliSecond,
    ePerSecond,
    ePerMinute,
    ePerHour,
    ePerDay,
    ePerWeek,
    ePerMonth,
    ePerYear

};

/**
 * @enum    PDRTypes
 * @brief   PDR Type enumeration values
 */
enum PDRTypes
{
    EPDRTypeTerminusLocator = 0x1,
    EPDRTypeNumericSensor,
    EPDRTypeNumericSensorInit,
    EPDRTypeStateSensor,
    EPDRTypeStateSensorInit,
    EPDRTypeSensorAuxNames,
    EPDRTypeOEMUnit,
    EPDRTypeOEMStateSet,
    EPDRTypeNumericEffecter,
    EPDRTypeNumericEffecterInit,
    EPDRTypeStateEffecter,
    EPDRTypeStateEffecterInit,
    EPDRTypeEffecterAuxNames,
    EPDRTypeEntityAssociation = 0x0f

};

/**
 * @enum    TerminusValidity
 * @brief   Terminus Validity enumeration values
 */
enum TerminusValidity
{
    ETerminusValidityNotValid,
    ETerminusValidityValid

};

/**
 * @enum    TerminusType
 * @brief   Terminus Type enumeration values
 */
enum TerminusType
{
    ETerminusTypeUID,
    ETerminusTypeMCTP_EID,
    ETerminusTypeSMBusRelative,
    ETerminusTypeSystemSoftware

};


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  TimeStamp
 * @brief   Structure to the timestamp
 */
typedef struct TimeStamp
{
    int16_t  UTC_Offset;                                                       /* UTC offset in minutes as sint16 */
    uint8_t  uSeconds[ 3 ];                                                    /* microsecond within the second as a 24-bit binary signed integer (starting with 0)
                                                                                  represent here in 3 bytes unsigned integer, so convert before storing */
    uint8_t  Seconds;
    uint8_t  Minutes;
    uint8_t  Hours;
    uint8_t  Day;
    uint8_t  Month;
    uint16_t Year;
    uint8_t  UTC_Time_Resolution;                                              /*
                                                                                   [ 7:4 ] UTC resolution = enum4 {UTCunspecified, minute, 10minute, hour }
                                                                                   [ 3:0 ] Time resolution = enum4 { microsecond, 10microsecond, 100microsecond,
                                                                                   millisecond, 10millisecond, 100millisecond, second, 10second, minute, 10minute,
                                                                                   hour, day, month, year }
                                                                                */

}__attribute__ ( ( __packed__ ) ) TimeStamp;

/**
 * @struct  PDR_RespositoryInfo
 * @brief   Structure to complete PDR repository
 */
typedef struct PDR_RespositoryInfo
{
    enum8_t   repositoryState;
    TimeStamp updateTimestamp;
    TimeStamp OEMUpdateTimestamp;
    uint32_t  recordCount;
    uint32_t  repositorySize;
    uint32_t  largestRecordSize;
    uint8_t   dataTransferHandleTimeout;
    void      *PDRRecords[ TOTAL_PDR_COUNT ];

}PDR_RepositoryInfo;

/**
 * @struct  CommonPDRFormat
 * @brief   Structure to hold common PDR format
 */
typedef struct CommonPDRFormat
{
    uint32_t recordHandle;
    uint8_t  PDRHeaderVersion;
    uint8_t  PDRType;
    uint16_t recordChangeNumber;
    uint16_t dataLength;

}__attribute__ ( ( __packed__ ) ) CommonPDRFormat;

/**
 * @struct  TerminusLocatorFormat_UID
 * @brief   Structure to hold Terminus Locator format
 */
typedef struct TerminusLocatorFormat_UID
{
    const enum8_t terminusLocatorType;                                         /* type will be UID for this structure */
    const enum8_t terminusLocatorValueSize;                                    /* This will be 1+16 bytes = 17bytes for UID type*/
    uint8_t       terminusInstance;
    uint8_t       deviceUID[ 16 ];

}__attribute__ ( ( __packed__ ) ) TerminusLocatorFormat_UID;

/**
 * @struct  TerminusPDRFormat_UID
 * @brief   Structure to hold Terminus PDR format
 */
typedef struct TerminusPDRFormat_UID
{
    CommonPDRFormat           commonHeader;
    uint16_t                  PLDMTerminusHandle;
    enum8_t                   validity;
    uint8_t                   TID;
    uint16_t                  containerID;
    TerminusLocatorFormat_UID locator;

}__attribute__ ( ( __packed__ ) ) TerminusPDRFormat_UID;


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Initialise the PDR repository
 */
void vPdrRepoInit( void );

/**
 * @brief   Update the TID in the PDR repository
 *
 * @param   tid     The TID to use
 */
void update_tid( uint8_t tid );

/**
 * @brief   Get the PDR repository
 *
 * @return  The location of the PDR repository
 */
const PDR_RepositoryInfo *getPDRRepository( void );

/**
 * @brief   Update the timestamp
 *
 * @param   time Pointer to timestamp
 */
void vUpdateTimestamp( TimeStamp *time );

/**
 * @brief   Count the empty space in the sensor name
 *
 * @param   namePDR Pointer to the sensor name
 *
 * @return  The count
 */
uint32_t sensor_name_empty_space( uint8_t *namePDR );

#endif /* PLDM_PDR_H_ */
