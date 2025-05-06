/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the API for the Alveo Sensor Control (ASC) proxy driver
 *
 * @file asc_proxy_driver.h
 *
 */

#ifndef _ASC_PROXY_DRIVER_H_
#define _ASC_PROXY_DRIVER_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"
#include "evl.h"
#include "fw_if.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define ASC_SENSOR_NAME_MAX ( 20 )

#define ASC_SENSOR_INVALID_VAL ( -1 )

#define ASC_SENSOR_I2C_BUS_NUM     ( 0 )
#define ASC_SENSOR_I2C_BUS_INVALID ( -1 )


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    ASC_PROXY_DRIVER_EVENTS
 * @brief   Events raised by this proxy driver
 */
typedef enum ASC_PROXY_DRIVER_EVENTS
{
    ASC_PROXY_DRIVER_E_SENSOR_UPDATE_COMPLETE = 0,
    ASC_PROXY_DRIVER_E_SENSOR_UNAVAILABLE,
    ASC_PROXY_DRIVER_E_SENSOR_COMMS_FAILURE,
    ASC_PROXY_DRIVER_E_SENSOR_WARNING,
    ASC_PROXY_DRIVER_E_SENSOR_CRITICAL,
    ASC_PROXY_DRIVER_E_SENSOR_FATAL,
    ASC_PROXY_DRIVER_E_SENSOR_LOWER_WARNING,
    ASC_PROXY_DRIVER_E_SENSOR_LOWER_CRITICAL,
    ASC_PROXY_DRIVER_E_SENSOR_LOWER_FATAL,
    ASC_PROXY_DRIVER_E_SENSOR_UPPER_WARNING,
    ASC_PROXY_DRIVER_E_SENSOR_UPPER_CRITICAL,
    ASC_PROXY_DRIVER_E_SENSOR_UPPER_FATAL,
    MAX_ASC_PROXY_DRIVER_EVENTS

} ASC_PROXY_DRIVER_EVENTS;

/**
 * @enum    ASC_PROXY_DRIVER_SENSOR_STATUS
 * @brief   Status of sensor
 */
typedef enum ASC_PROXY_DRIVER_SENSOR_STATUS
{
    ASC_PROXY_DRIVER_SENSOR_STATUS_NOT_PRESENT = 0,
    ASC_PROXY_DRIVER_SENSOR_STATUS_PRESENT_AND_VALID,
    ASC_PROXY_DRIVER_SENSOR_STATUS_DATA_NOT_AVAILABLE,
    ASC_PROXY_DRIVER_SENSOR_STATUS_NOT_AVAILABLE,
    MAX_ASC_PROXY_DRIVER_SENSOR_STATUS

} ASC_PROXY_DRIVER_SENSOR_STATUS;

/**
 * @enum    ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS
 * @brief   Operational status of sensor
 */
typedef enum ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS
{
    ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_ENABLED = 0,
    ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_DISABLED,
    ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS_UNAVAILABLE,
    MAX_ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS

} ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS;

/**
 * @enum   ASC_PROXY_DRIVER_SENSOR_UNIT_MOD
 * @brief  Base unit modifiers for sensor readings
 */
typedef enum ASC_PROXY_DRIVER_SENSOR_UNIT_MOD
{
    ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_MEGA = 0,
    ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_KILO,
    ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_NONE,
    ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_MILLI,
    ASC_PROXY_DRIVER_SENSOR_UNIT_MOD_MICRO,
    MAX_ASC_PROXY_DRIVER_SENSOR_UNIT_MOD

} ASC_PROXY_DRIVER_SENSOR_UNIT_MOD;

/**
 * @enum    ASC_PROXY_DRIVER_SENSOR_TYPE
 * @brief   Type of sensor
 */
typedef enum ASC_PROXY_DRIVER_SENSOR_TYPE
{
    ASC_PROXY_DRIVER_SENSOR_TYPE_TEMPERATURE = 0,
    ASC_PROXY_DRIVER_SENSOR_TYPE_VOLTAGE,
    ASC_PROXY_DRIVER_SENSOR_TYPE_CURRENT,
    ASC_PROXY_DRIVER_SENSOR_TYPE_POWER,
    MAX_ASC_PROXY_DRIVER_SENSOR_TYPE

} ASC_PROXY_DRIVER_SENSOR_TYPE;

/**
 * @enum    ASC_PROXY_DRIVER_SENSOR_BITFIELD
 * @brief   Bitfield of sensor types
 */
typedef enum ASC_PROXY_DRIVER_SENSOR_BITFIELD
{
    ASC_PROXY_DRIVER_SENSOR_BITFIELD_TEMPERATURE = ( 1 << 0 ),
    ASC_PROXY_DRIVER_SENSOR_BITFIELD_VOLTAGE     = ( 1 << 1 ),
    ASC_PROXY_DRIVER_SENSOR_BITFIELD_CURRENT     = ( 1 << 2 ),
    ASC_PROXY_DRIVER_SENSOR_BITFIELD_POWER       = ( 1 << 3 ),
    MAX_ASC_PROXY_DRIVER_SENSOR_BITFIELD

} ASC_PROXY_DRIVER_SENSOR_BITFIELD;

/**
 * @enum    ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS
 * @brief   Bitfield of sensor types
 */
typedef enum ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS
{
    ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS_HEALTHY = 0,
    ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS_WARNING,
    ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS_CRITICAL,
    ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS_FATAL,
    MAX_ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS

} ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS;


/******************************************************************************/
/* Typedefs                                                                   */
/******************************************************************************/

/**
 * @typedef  ASC_PROXY_DRIVER_READ_SENSOR_FUNC
 * @brief    Function definition for sensor-reading APIs
 */
typedef int ( ASC_PROXY_DRIVER_READ_SENSOR_FUNC ) ( uint8_t ucBusNum,
                                                    uint8_t ucSlaveAddr,
                                                    uint8_t ucChannelNum,
                                                    float *pfValue );

/**
 * @typedef  ASC_PROXY_DRIVER_ENABLE_SENSOR_FUNC
 *
 * @brief    Function definition for checking if sensor is enabled or disabled
 *
 * @return   TRUE if sensor is enabled or FALSE if sensor is disabled
 */
typedef int ( ASC_PROXY_DRIVER_ENABLE_SENSOR_FUNC ) ( void );


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  ASC_PROXY_DRIVER_SENSOR_READINGS
 * @brief   Sensor data readings
 */
typedef struct ASC_PROXY_DRIVER_SENSOR_READINGS
{
    uint32_t                                   ulSensorValue;

    const uint32_t                             ulLowerWarningLimit;
    const uint32_t                             ulLowerCriticalLimit;
    const uint32_t                             ulLowerFatalLimit;
    const uint32_t                             ulUpperWarningLimit;
    const uint32_t                             ulUpperCriticalLimit;
    const uint32_t                             ulUpperFatalLimit;
    uint32_t                                   ulAverageSensorValue;
    uint32_t                                   ulMaxSensorValue;

    ASC_PROXY_DRIVER_SENSOR_STATUS             xSensorStatus;
    ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS xSensorOperationalStatus;
    ASC_PROXY_DRIVER_SENSOR_UNIT_MOD           xSensorUnitModifier;

} ASC_PROXY_DRIVER_SENSOR_READINGS;

/**
 * @struct  ASC_PROXY_DRIVER_SENSOR_DATA
 * @brief   Sensor data
 */
typedef struct ASC_PROXY_DRIVER_SENSOR_DATA
{
    const char                               pcSensorName[ ASC_SENSOR_NAME_MAX ];

    const uint8_t                            ucSensorId;
    const uint8_t                            ucSensorType;
    const uint8_t                            ucTotalPowerSensor;
    const uint8_t                            ucSensorAddress;
    const uint8_t                            ucChannelNumber[ MAX_ASC_PROXY_DRIVER_SENSOR_TYPE ];

    ASC_PROXY_DRIVER_ENABLE_SENSOR_FUNC      *pxSensorEnabled;

    ASC_PROXY_DRIVER_READ_SENSOR_FUNC        *ppxReadSensorFunc[ MAX_ASC_PROXY_DRIVER_SENSOR_TYPE ];

    ASC_PROXY_DRIVER_SENSOR_READINGS         pxReadings[ MAX_ASC_PROXY_DRIVER_SENSOR_TYPE ];

    ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS ulThresholdStatus;

} ASC_PROXY_DRIVER_SENSOR_DATA;


/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/* Init functions *************************************************************/

/**
 * @brief   Main initialisation point for the ASC Proxy Driver
 *
 * @param   ucProxyId      Unique ID for this Proxy driver
 * @param   ulTaskPrio     Priority of the Proxy driver task (if RR disabled)
 * @param   ulTaskStack    Stack size of the Proxy driver task
 * @param   pxSensorData   Array of sensor data
 * @param   ucNumSensors   Number of sensors to monitor
 *
 * @return  OK          Proxy driver initialised correctly
 *          ERROR       Proxy driver not initialised, or was already initialised
 *
 * @note   Proxy drivers can have 0 or more firmware interfaces
 */
int iASC_Initialise( uint8_t ucProxyId,
                     uint32_t ulTaskPrio,
                     uint32_t ulTaskStack,
                     ASC_PROXY_DRIVER_SENSOR_DATA *pxSensorData,
                     uint8_t ucNumSensors );

/**
 * @brief   Bind into this proxy driver
 *
 * @param   pxCallback  Callback to bind into the proxy driver
 *
 * @return  OK          Callback successfully bound
 *          ERROR       Callback not bound
 *
 */
int iASC_BindCallback( EVL_CALLBACK *pxCallback );


/* Set functions **************************************************************/

/**
 * @brief   Reset current, average, max and status values for all sensors
 *
 * @return  OK          Data reset successfully
 *          ERROR       Data not reset successfully
 *
 */
int iASC_ResetAllSensorData( void );

/**
 * @brief   Reset current, average, max and status values for a single sensor by ID
 *
 * @param   ucId        Sensor ID
 *
 * @return  OK          Data reset successfully
 *          ERROR       Data not reset successfully
 *
 */
int iASC_ResetSingleSensorDataById( uint8_t ucId );

/**
 * @brief   Reset current, average, max and status values for a single sensor by name
 *
 * @param   pcName      Sensor Name
 *
 * @return  OK          Data reset successfully
 *          ERROR       Data not reset successfully
 *
 */
int iASC_ResetSingleSensorDataByName( const char *pcName );

/* Get functions **************************************************************/

/**
 * @brief   Get all sensor data
 *
 * @param   pxData         Pointer to data to get
 * @param   pucNumSensors  Pointer to the number of sensors monitored
 *                         Orignally passed in as the maximum number of sensors that can be monitored but will then be
 *                         updated to the actual number of sensors that are monitored
 *
 * @return  OK             Data retrieved successfully
 *          ERROR          Data not retrieved successfully
 *
 */
int iASC_GetAllSensorData( ASC_PROXY_DRIVER_SENSOR_DATA *pxData, uint8_t *pucNumSensors );

/**
 * @brief   Get single sensor data by ID
 *
 * @param   ucId        Sensor ID
 * @param   pxData      Pointer to data to get
 *
 * @return  OK          Data retrieved successfully
 *          ERROR       Data not retrieved successfully
 *
 */
int iASC_GetSingleSensorDataById( uint8_t ucId, ASC_PROXY_DRIVER_SENSOR_DATA *pxData );

/**
 * @brief   Get single sensor data by name
 *
 * @param   pcName      Sensor Name
 * @param   pxData      Pointer to data to get
 *
 * @return  OK          Data retrieved successfully
 *          ERROR       Data not retrieved successfully
 *
 */
int iASC_GetSingleSensorDataByName( const char *pcName, ASC_PROXY_DRIVER_SENSOR_DATA *pxData );

/**
 * @brief   Sets the threshold status of a single sensor
 *
 * @param   ucId        Sensor ID
 * @param   xStatus     New threshold status
 *
 * @return  OK          Status set successfully
 *          ERROR       Satus not set
 *
 */
int iASC_SetSingleSensorThresholdStatusById( uint8_t ucId, ASC_PROXY_DRIVER_SENSOR_THRESHOLD_STATUS xStatus );

/**
 * @brief   Set single sensor operational state by ID
 *
 * @param   ucId                Sensor ID
 * @param   ucSensorType        The sensor type
 * @param   ucOperationalState  The operational state to set
 *
 * @return  OK          operational state set successfully
 *          ERROR       operational state not set
 */
int iASC_SetSingleSensorOperationalStateById( uint8_t ucId,
                                              uint8_t ucSensorType,
                                              ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS ucOperationalState );

/**
 * @brief   Get single sensor operational state by ID
 *
 * @param   ucId                Sensor ID
 * @param   ucSensorType        The sensor type
 * @param   pucOperationalState Pointer to the operational state read
 *
 * @return  OK          operational state read successfully
 *          ERROR       operational state not read
 */
int iASC_GetSingleSensorOperationalStateById( uint8_t ucId,
                                              uint8_t ucSensorType,
                                              ASC_PROXY_DRIVER_SENSOR_OPERATIONAL_STATUS *pucOperationalState );

/**
 * @brief   Print all of the stats gathered by the application
 *
 * @return  OK          Stats retrieved from proxy driver successfully
 *          ERROR       Stats not retrieved successfully
 *
 */
int iASC_PrintStatistics( void );

/**
 * @brief   Clear all of the stats in the application
 *
 * @return  OK          Stats cleared successfully
 *          ERROR       Stats not cleared successfully
 *
 */
int iASC_ClearStatistics( void );

/**
 * @brief   Gets the current state of the proxy driver
 *
 * @param   pxState         Pointer to the state
 *
 * @return  OK              If successful
 *          ERROR           If not successful
 */
int iASC_GetState( MODULE_STATE *pxState );

#endif
