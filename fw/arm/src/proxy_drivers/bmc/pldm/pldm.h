/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains PLDM enums, structures and functions
 *
 * @file pldm.h
 *
 */

#ifndef PLDM_COMMANDS_H_
#define PLDM_COMMANDS_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define MAX_BUFFER_SIZE ( 255 )

#define BMC_PROXY_REQUEST_SIZE  ( 512 )
#define BMC_PROXY_RESPONSE_SIZE ( 16 )
#define BMC_NAME                "BMC"

#define PLDM_TERMINUS_HANDLE ( 0x0 )
#define PLDM_CONTAINER_ID    ( 0x7F7F )
#define PLDM_ENTITY_TYPE     ( 0x51 )

#define PDR_MAX_NAME_SIZE           ( 32 )
#define PDR_SENSOR_NAME_SIZE        ( PDR_MAX_NAME_SIZE * 2 )
#define PDR_LANGUAGE_TAG_SIZE       ( 6 )                                      /* "en-US" including NULL char */
#define PDR_SENSOR_NAME_STRING_SIZE ( 1 )


/******************************************************************************/
/* Externs                                                                    */
/******************************************************************************/

extern uint8_t ReqBuffer[ MAX_BUFFER_SIZE ];
extern uint8_t RespBuffer[ MAX_BUFFER_SIZE ];


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    DataType
 * @brief   Enumeration of data type values
 */
enum DataType
{
    EDataTypeUInt8,
    EDataTypeSInt8,
    EDataTypeUInt16,
    EDataTypeSInt16,
    EDataTypeUInt32,
    EDataTypeSInt32,
    EDataTypeReal32

};

/**
 * @enum    PLDM_DATA_SIZE_FORMAT
 * @brief   Enumeration of PLDM PDR data sizes.
 */
typedef enum PLDM_DATA_SIZE_FORMAT
{
    PLDM_DATA_SIZE_FORMAT_UINT8_T  = 0x1,
    PLDM_DATA_SIZE_FORMAT_SINT8_T  = 0x1,
    PLDM_DATA_SIZE_FORMAT_UINT16_T = 0x2,
    PLDM_DATA_SIZE_FORMAT_SINT16_T = 0x2,
    PLDM_DATA_SIZE_FORMAT_UINT32_T = 0x4,
    PLDM_DATA_SIZE_FORMAT_SINT32_T = 0x4,
    MAX_PLDM_DATA_SIZE_FORMAT

} PLDM_DATA_SIZE_FORMAT;

/**
 * @enum    PLDM_SUPPORTED_THRESHOLDS_BITFIELD
 * @brief   Bitfield representing the supported thresholds in PLDM
 */
typedef enum PLDM_SUPPORTED_THRESHOLDS_BITFIELD
{
    PLDM_SUPPORTED_THRESHOLDS_BITFIELD_UPPER_THRESHOLD_WARNING  = ( 1 << 0 ),
    PLDM_SUPPORTED_THRESHOLDS_BITFIELD_UPPER_THRESHOLD_CRITICAL = ( 1 << 1 ),
    PLDM_SUPPORTED_THRESHOLDS_BITFIELD_UPPER_THRESHOLD_FATAL    = ( 1 << 2 ),
    PLDM_SUPPORTED_THRESHOLDS_BITFIELD_LOWER_THRESHOLD_WARNING  = ( 1 << 3 ),
    PLDM_SUPPORTED_THRESHOLDS_BITFIELD_LOWER_THRESHOLD_CRITICAL = ( 1 << 4 ),
    PLDM_SUPPORTED_THRESHOLDS_BITFIELD_LOWER_THRESHOLD_FATAL    = ( 1 << 5 ),
    MAX_PLDM_SUPPORTED_THRESHOLDS_BITFIELD

} PLDM_SUPPORTED_THRESHOLDS_BITFIELD;

/**
 * @enum    PLDM_PDR_INIT_STATUS
 * @brief   Init status for the numeric sensor PDRs
 */
typedef enum PLDM_PDR_INIT_STATUS
{
    PLDM_PDR_INIT_STATUS_NO_INIT = 0x0,
    PLDM_PDR_INIT_STATUS_USE_INIT_PDR,
    PLDM_PDR_INIT_STATUS_ENABLE,
    PLDM_PDR_INIT_STATUS_DISABLE,
    MAX_LDM_PDR_INIT_STATUS

} PLDM_PDR_INIT_STATUS;

/**
 * @enum    PLDM_PDR_BASE_UNIT
 * @brief   Base unit for the numeric sensor PDR readings
 */
typedef enum PLDM_PDR_BASE_UNIT
{
    PLDM_PDR_BASE_UNIT_NO_UNIT   = 0x0,
    PLDM_PDR_BASE_UNIT_DEGREES_C = 0x2,
    PLDM_PDR_BASE_UNIT_VOLTS     = 0x5,
    PLDM_PDR_BASE_UNIT_AMPS      = 0x6,
    PLDM_PDR_BASE_UNIT_WATTS     = 0x7,
    PLDM_PDR_BASE_UNIT_HERTZ     = 0x14,
    PLDM_PDR_BASE_UNIT_COUNTS    = 0x43,
    MAX_PLDM_PDR_BASE_UNIT

} PLDM_PDR_BASE_UNIT;

/**
 * @enum    PLDM_PDR_RATE_UNIT
 * @brief   Numeric sensor PDR reading frequencies
 */
typedef enum PLDM_PDR_RATE_UNIT
{
    PLDM_PDR_RATE_UNIT_NONE = 0x0,
    PLDM_PDR_RATE_UNIT_PER_MICRO_SECOND,
    PLDM_PDR_RATE_UNIT_PER_MILLI_SECOND,
    PLDM_PDR_RATE_UNIT_PER_SECOND,
    PLDM_PDR_RATE_UNIT_PER_MINUTE,
    PLDM_PDR_RATE_UNIT_PER_HOUR,
    PLDM_PDR_RATE_UNIT_PER_DAY,
    PLDM_PDR_RATE_UNIT_PER_WEEK,
    PLDM_PDR_RATE_UNIT_PER_MONTH,
    PLDM_PDR_RATE_UNIT_PER_YEAR,
    MAX_PLDM_PDR_RATE_UNIT

} PLDM_PDR_RATE_UNIT;


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct    PLDM_COMMON_HEADER_PDR
 * @brief   Common header used by PLDM PDRs
 */
typedef struct PLDM_COMMON_HEADER_PDR
{
    uint32_t ulRecordHandle;
    uint8_t  ucPdrHeaderVersion;
    uint8_t  ucPdrType;
    uint16_t usRecordChangeNumber;
    uint16_t usDataLength;

} __attribute__ ( ( __packed__ ) ) PLDM_COMMON_HEADER_PDR;

/**
 * @struct    PLDM_NUMERIC_SENSOR_RANGE_FORMAT
 * @brief   Numeric sensor PDR threshold ranges
 */
typedef struct PLDM_NUMERIC_SENSOR_RANGE_FORMAT
{
    const uint8_t ucRangeFieldFormat;
    uint8_t       ucRangeFieldSupport;
    int16_t       sNominalValue;
    int16_t       sNormalMax;
    int16_t       sNormalMin;
    int16_t       sWarningHigh;
    int16_t       sWarningLow;
    int16_t       sCriticalHigh;
    int16_t       sCriticalLow;
    int16_t       sFatalHigh;
    int16_t       sFatalLow;

} __attribute__ ( ( __packed__ ) ) PLDM_NUMERIC_SENSOR_RANGE_FORMAT;

/**
 * @struct    PLDM_NUMERIC_SENSOR_PDR
 * @brief   The numeric sensor PDR format
 */
typedef struct PLDM_NUMERIC_SENSOR_PDR
{
    PLDM_COMMON_HEADER_PDR           xCommonPdrHeader;
    uint16_t                         usPldmTerminusHandle;
    uint16_t                         usSensorId;
    uint16_t                         usEntityType;
    uint16_t                         usEntityInstanceNumber;
    uint16_t                         usContainerId;
    uint8_t                          ucSensorInit;
    uint8_t                          ucSensorAuxiliaryNamesPdr;
    uint8_t                          ucBaseUnit;
    int8_t                           cUnitModifier;
    uint8_t                          ucRateUnit;
    uint8_t                          ucBaseOemUnitHandle;
    uint8_t                          ucAuxUnit;
    int8_t                           cAuxUnitModifier;
    uint8_t                          ucAuxRateUnit;
    uint8_t                          ucRel;
    uint8_t                          ucAuxOemUnitHandle;
    uint8_t                          ucIsLinear;
    const uint8_t                    ucSensorDataSize;
    float                            fResolution;
    float                            fOffset;
    uint16_t                         usAccuracy;
    uint8_t                          ucPlusTolerance;
    uint8_t                          ucMinusTolerance;
    int16_t                          sHysteresis;
    uint8_t                          ucSupportedThresholds;
    uint8_t                          ucThresholdAndHysteresisVolatility;
    float                            fStateTransitionInterval;
    float                            fUpdateInterval;
    int16_t                          sMaxReadable;
    int16_t                          sMinReadable;
    PLDM_NUMERIC_SENSOR_RANGE_FORMAT xRange;

} __attribute__ ( ( __packed__ ) ) PLDM_NUMERIC_SENSOR_PDR;

/**
 * @struct    PLDM_NUMERIC_SENSOR_NAME_PDR
 * @brief   The numeric sensor names PDR format
 */
typedef struct PLDM_NUMERIC_SENSOR_NAME_PDR
{
    PLDM_COMMON_HEADER_PDR xCommonHeader;
    uint16_t               usPldmTerminusHandle;
    uint16_t               usSensorId;
    uint8_t                ucSensorCount;
    uint8_t                ucNameStringCount[ PDR_SENSOR_NAME_STRING_SIZE ];
    uint8_t                ucNameLanguageTag[ PDR_LANGUAGE_TAG_SIZE ];
    uint8_t                ucSensorNameBe16[ PDR_SENSOR_NAME_SIZE ];

} __attribute__ ( ( __packed__ ) ) PLDM_NUMERIC_SENSOR_NAME_PDR;


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Get a CRC 32 for supplied data
 *
 * @param   data    Pointer to the data
 * @param   size    Size of the data
 *
 * @return  32-bit CRC
 *
 */
uint32_t ulGetCrc32( const uint8_t data[], size_t size );

/**
 * @brief   Get a CRC 8 for supplied data
 *
 * @param   data    Pointer to the data
 * @param   size    Size of the data
 *
 * @return  8-bit CRC
 *
 */
uint8_t ucGetCrc8( const uint8_t data[], size_t size );

/**
 * @brief   Build the PLDM command table
 *
 * @return  0 on success
 */
int pldm_command_init( void );

/**
 * @brief   Process a PLDM message
 *
 * @param   ReqBuff     Pointer to the request message
 * @param   RespBuff    Pointer to the response message
 * @param   request_pkt Request or response
 *
 * @return  Size of the response
 */
int process_pldm_request( void *ReqBuff, void *RespBuff, int request_pkt );

/**
 * @brief   Process a received message
 *
 * @param   i2cSlaveReadCount    The size of the data to process
 *
 */
void process_pmci_request( int i2cSlaveReadCount );

#endif /* PLDM_COMMANDS_H_ */
