/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the API for the Board Management Controller (BMC) proxy driver
 *
 * @file bmc_proxy_driver.h
 *
 */

#ifndef _BMC_PROXY_DRIVER_H_
#define _BMC_PROXY_DRIVER_H_


/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"
#include "evl.h"
#include "fw_if.h"
#include "pldm.h"
#include "pldm_pdr.h"

/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    BMC_PROXY_DRIVER_EVENTS
 * @brief   Events raised by this proxy driver
 */
typedef enum BMC_PROXY_DRIVER_EVENTS
{
    BMC_PROXY_DRIVER_E_MSG_ARRIVAL = 0,
    BMC_PROXY_DRIVER_E_GET_PDR,
    BMC_PROXY_DRIVER_E_GET_PDR_REPOSITORY_INFO,
    BMC_PROXY_DRIVER_E_GET_SENSOR_INFO,
    BMC_PROXY_DRIVER_E_ENABLE_SENSOR,
    BMC_PROXY_DRIVER_E_INVALID_REQUEST_RECVD,
    MAX_BMC_PROXY_DRIVER_EVENTS

} BMC_PROXY_DRIVER_EVENTS;

/**
 * @enum    BMC_PROXY_RESPONSE_RESULT
 * @brief   The response result
 */
typedef enum BMC_PROXY_RESULT
{
    BMC_PROXY_RESULT_SUCCESS = 0,
    BMC_PROXY_RESULT_FAILURE,
    MAX_BMC_PROXY_RESULT

} BMC_PROXY_RESULT;


/**
 * @enum    BMC_SENSOR_RESPONSE
 * @brief   The response
 */
typedef enum BMC_SENSOR_RESPONSE
{
    BMC_RESPONSE_OK = 0,
    BMC_RESPONSE_ERROR,
    MAX_BMC_SENSOR_RESPONSE

} BMC_SENSOR_RESPONSE;


/**
 * @enum    BMC_SET_NUMERIC_SENSOR_ENABLE_RESPONSE
 * @brief   The response
 */
typedef enum BMC_SET_NUMERIC_SENSOR_ENABLE_RESPONSE
{
    BMC_SENSOR_ENABLE_RESP_OK = 0,
    BMC_SENSOR_ENABLE_RESP_INVALID_SENSOR_ID,
    BMC_SENSOR_ENABLE_RESP_INVALID_SENSOR_OPERATIONAL_STATE,
    BMC_SENSOR_ENABLE_RESP_EVENT_GENERATION_NOT_SUPPORTED,
    BMC_SENSOR_ENABLE_RESP_NONE,
    MAX_BMC_SENSOR_ENABLE_RESP

} BMC_SET_NUMERIC_SENSOR_ENABLE_RESPONSE;

/**
 * @enum    BMC_GET_SENSOR_RESPONSE
 * @brief   The response
 */
typedef enum BMC_GET_SENSOR_RESPONSE
{
    BMC_GET_SENSOR_RESP_OK = 0,
    BMC_GET_SENSOR_RESP_INVALID_SENSOR_ID,
    BMC_GET_SENSOR_RESP_INVALID_SENSOR_OPERATIONAL_STATE,
    BMC_GET_SENSOR_RESP_REARM_UNAVAILABLE_IN_PRESENT_STATE,
    BMC_GET_SENSOR_RESP_NONE,
    MAX_BMC_GET_SENSOR_RESP

} BMC_GET_SENSOR_RESPONSE;

/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/**
 * @brief   Main initialisation point for the BMC Proxy Driver
 *
 * @param   ucProxyId   Unique ID for this Proxy driver
 * @param   pxFwIf      Handle to the Firmware Interface to use
 * @param   ulFwIfPort  Port to use on the Firmware Interface
 * @param   ulTaskPrio  Priority of the Proxy driver task (if RR disabled)
 * @param   ulTaskStack Stack size of the Proxy driver task
 * @param   pxPdrTemperatureSensors Pointer to Temperature PDR
 * @param   iTotalPdrTemperature Size of Temperature PDR
 * @param   pxPdrVoltageSensors Pointer to Voltage PDR
 * @param   iTotalPdrVoltage Size of Voltage PDR
 * @param   pxPdrCurrentSensors Pointer to Current PDR
 * @param   iTotalPdrCurrent Size of Current PDR
 * @param   pxPdrPowerSensors Pointer to Power PDR
 * @param   iTotalPdrPower Size of Power PDR
 * @param   pxPdrSensorNames Pointer to Sensor Names PDR
 * @param   iTotalPdrName Size of Sensor Names PDR
 * @param   pucUuid Pointer to UUID
 *
 * @return  OK          Proxy driver initialised correctly
 *          ERROR       Proxy driver not initialised, or was already initialised
 *
 * @note    Proxy drivers can have 0 or more firmware interfaces
 */
int iBMC_Initialise( uint8_t ucProxyId,
                     FW_IF_CFG *pxFwIf,
                     uint32_t ulFwIfPort,
                     uint32_t ulTaskPrio,
                     uint32_t ulTaskStack,
                     PLDM_NUMERIC_SENSOR_PDR *pxPdrTemperatureSensors,
                     int iTotalPdrTemperature,
                     PLDM_NUMERIC_SENSOR_PDR *pxPdrVoltageSensors,
                     int iTotalPdrVoltage,
                     PLDM_NUMERIC_SENSOR_PDR *pxPdrCurrentSensors,
                     int iTotalPdrCurrent,
                     PLDM_NUMERIC_SENSOR_PDR *pxPdrPowerSensors,
                     int iTotalPdrPower,
                     PLDM_NUMERIC_SENSOR_NAME_PDR *pxPdrSensorNames,
                     int iTotalPdrName,
                     uint8_t *pucUuid );

/**
 * @brief   Bind into this proxy driver
 *
 * @param   pxCallback  Callback to bind into the proxy driver
 *
 * @return  OK          Callback successfully bound
 *          ERROR       Callback not bound
 */
int iBMC_BindCallback( EVL_CALLBACK *pxCallback );

/**
 * @brief   Response to a Sensor Info request
 *
 * @param   pxSignal        Current event occurence (used for tracking)
 * @param   usSensorId      Sensor Id
 * @param   ssSensorInfo    Sensor Value
 * @param   ucSensorState   Sensor Operational State
 * @param   xSensorResponse The response to the sensor query, OK, Invalid ID etc
 *
 * @return  OK          Command was successful
 *          ERROR       Command failed
 */
int iBMC_SendResponseForGetSensor( EVL_SIGNAL *pxSignal,
                                   uint16_t usSensorId,
                                   int16_t ssSensorInfo,
                                   uint8_t ucSensorState,
                                   BMC_GET_SENSOR_RESPONSE xSensorResponse );
/**
 * @brief   Response to an enable sensor request
 *
 * @param   pxSignal      Current event occurence (used for tracking)
 * @param   xBmcResponse  Enable sensor response
 *
 * @return  OK          Command was successful
 *          ERROR       Command failed
 */
int iBMC_SetResponse( EVL_SIGNAL *pxSignal, uint16_t usSensorId, BMC_SENSOR_RESPONSE xBmcResponse );

/**
 * @brief   Print all the stats gathered by the application
 *
 * @return  OK          Stats retrieved from proxy driver successfully
 *          ERROR       Stats not retrieved successfully
 *
 */
int iBMC_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the application
 *
 * @return  OK          Stats cleared successfully
 *          ERROR       Stats not cleared successfully
 *
 */
int iBMC_ClearStatistics( void );

/**
 * @brief   Function called after certain events are raised to get the sensor id
 *
 * @param   pxSignal            pointer to signal raised
 * @param   pusSensorId         pointer to sensor id
 * @param   pucOperationalState pointer to the new state (if required)
 *
 * @return  OK or ERROR
 */
int iBMC_GetSensorIdRequest( EVL_SIGNAL *pxSignal, int16_t *pssSensorId, uint8_t *pucOperationalState );

/**
 * @brief   Gets the current state of the proxy driver
 *
 * @param   pxState         Pointer to the state
 *
 * @return  OK              If successful
 *          ERROR           If not successful
 */
int iBMC_GetState( MODULE_STATE *pxState );

#endif
