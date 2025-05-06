/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the API for the Alveo Management Interface (AMI) proxy driver
 *
 * @file ami_proxy_driver.h
 *
 */

#ifndef _AMI_PROXY_DRIVER_H_
#define _AMI_PROXY_DRIVER_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"
#include "evl.h"
#include "fw_if.h"
#include <stdbool.h>


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define AMI_PROXY_REQUEST_SIZE              ( 512 )
#define AMI_PROXY_RESPONSE_SIZE             ( 16 )


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    AMI_PROXY_DRIVER_EVENTS
 * @brief   Events raised by this proxy driver
 */
typedef enum AMI_PROXY_DRIVER_EVENTS
{
    AMI_PROXY_DRIVER_E_PDI_DOWNLOAD_START = 0,
    AMI_PROXY_DRIVER_E_PDI_COPY_START,
    AMI_PROXY_DRIVER_E_SENSOR_READ,
    AMI_PROXY_DRIVER_E_GET_IDENTITY,
    AMI_PROXY_DRIVER_E_BOOT_SELECT,
    AMI_PROXY_DRIVER_E_HEARTBEAT,
    AMI_PROXY_DRIVER_E_EEPROM_READ_WRITE,
    AMI_PROXY_DRIVER_E_MODULE_READ_WRITE,
    AMI_PROXY_DRIVER_E_DEBUG_VERBOSITY,
    AMI_PROXY_DRIVER_E_PEEK_POKE,
    AMI_PROXY_DRIVER_E_GET_UCORE_VERSION,

    MAX_AMI_PROXY_DRIVER_EVENTS

} AMI_PROXY_DRIVER_EVENTS;

/**
 * @enum    AMI_PROXY_CMD_SENSOR_REQUEST
 * @brief   Sensor request types
 */
typedef enum AMI_PROXY_CMD_SENSOR_REQUEST
{
    AMI_PROXY_CMD_SENSOR_REQUEST_GET_SIZE = 1,
    AMI_PROXY_CMD_SENSOR_REQUEST_GET_SDR,
    AMI_PROXY_CMD_SENSOR_REQUEST_GET_SINGLE_SDR,
    AMI_PROXY_CMD_SENSOR_REQUEST_ALL_SDR,

    MAX_AMI_PROXY_CMD_SENSOR_REQUEST

} AMI_PROXY_CMD_SENSOR_REQUEST;

/**
 * @enum    AMI_PROXY_CMD_SENSOR_REPO
 * @brief   Sensor repo request types
 */
typedef enum AMI_PROXY_CMD_SENSOR_REPO
{
    AMI_PROXY_CMD_SENSOR_REPO_GET_SIZE = 0,
    AMI_PROXY_CMD_SENSOR_REPO_BDINFO,
    AMI_PROXY_CMD_SENSOR_REPO_TEMP,
    AMI_PROXY_CMD_SENSOR_REPO_VOLTAGE,
    AMI_PROXY_CMD_SENSOR_REPO_CURRENT,
    AMI_PROXY_CMD_SENSOR_REPO_POWER,
    AMI_PROXY_CMD_SENSOR_REPO_TOTAL_POWER,
    AMI_PROXY_CMD_SENSOR_REPO_QSFP,
    AMI_PROXY_CMD_SENSOR_REPO_FPT,
    AMI_PROXY_CMD_SENSOR_REPO_ALL,

    MAX_AMI_PROXY_CMD_SENSOR_REPO

} AMI_PROXY_CMD_SENSOR_REPO;

/**
 * @enum    AMI_PROXY_CMD_RW_REQUEST
 * @brief   Request type for commands which accept read/write requests
 */
typedef enum AMI_PROXY_CMD_RW_REQUEST
{
    AMI_PROXY_CMD_RW_REQUEST_READ = 0,
    AMI_PROXY_CMD_RW_REQUEST_WRITE,

    MAX_AMI_PROXY_CMD_RW_REQUEST

} AMI_PROXY_CMD_RW_REQUEST;

/**
 * @enum    AMI_PROXY_RESPONSE_RESULT
 * @brief   The response result
 */
typedef enum AMI_PROXY_RESULT
{
    AMI_PROXY_RESULT_SUCCESS = 0,
    AMI_PROXY_RESULT_FAILURE,
    AMI_PROXY_RESULT_INVALID_VALUE,
    AMI_PROXY_RESULT_GET_REQUEST_FAILED,
    AMI_PROXY_RESULT_PROCESS_REQUEST_FAILED,
    AMI_PROXY_RESULT_ALREADY_IN_PROGRESS,
    AMI_PROXY_RESULT_INVALID_CONFIGURATION,

    MAX_AMI_PROXY_RESULT

} AMI_PROXY_RESULT;


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  AMI_PROXY_SENSOR_REQUEST
 * @brief   Sensor request
 */
typedef struct AMI_PROXY_SENSOR_REQUEST
{
    AMI_PROXY_CMD_SENSOR_REQUEST xRequest;
    AMI_PROXY_CMD_SENSOR_REPO xRepo;
    uint32_t ulSensorId;
    uint32_t ulLength;
    uint64_t ullAddress;

} AMI_PROXY_SENSOR_REQUEST;

/**
 * @struct  AMI_PROXY_PDI_DOWNLOAD_REQUEST
 * @brief   PDI download request
 */
typedef struct AMI_PROXY_PDI_DOWNLOAD_REQUEST
{
    int      iBootDevice;
    int      iUpdateFpt;
    int      iLastPacket;
    uint64_t ullAddress;
    uint32_t ulLength;
    uint32_t ulPartitionSel;
    uint16_t usPacketNum; 
    uint16_t usPacketSize;

} AMI_PROXY_PDI_DOWNLOAD_REQUEST;

/**
 * @struct  AMI_PROXY_PDI_COPY_REQUEST
 * @brief   PDI copy request
 */
typedef struct AMI_PROXY_PDI_COPY_REQUEST
{
    uint64_t ullAddress;
    uint32_t ulMaxLength;
    uint32_t ulSrcDevice;
    uint32_t ulSrcPartition;
    uint32_t ulDestDevice;
    uint32_t ulDestPartition;

} AMI_PROXY_PDI_COPY_REQUEST;

/**
 * @struct  AMI_PROXY_BOOT_SELECT_REQUEST
 * @brief   Boot select request
 */
typedef struct AMI_PROXY_BOOT_SELECT_REQUEST
{
    uint32_t ulPartitionSel;

} AMI_PROXY_BOOT_SELECT_REQUEST;

/**
 * @struct  AMI_PROXY_EEPROM_RW_REQUEST
 * @brief   Read from or write to the eeprom
 */
typedef struct AMI_PROXY_EEPROM_RW_REQUEST
{
    AMI_PROXY_CMD_RW_REQUEST xRequest;
    uint64_t ullAddress;
    uint32_t ulLength;
    uint32_t ulOffset;

} AMI_PROXY_EEPROM_RW_REQUEST;

typedef struct AMI_PROXY_PEEK_POKE_REQUEST
{
    AMI_PROXY_CMD_RW_REQUEST xRequest;
    uint64_t ullAddress;
    uint32_t ulLength;
    uint32_t ulOffset;

} AMI_PROXY_PEEK_POKE_REQUEST;

/**
 * @struct  AMI_PROXY_MODULE_RW_REQUEST
 * @brief   Read from or write to a QSFP module
 */
typedef struct AMI_PROXY_MODULE_RW_REQUEST
{
    AMI_PROXY_CMD_RW_REQUEST xRequest;
    uint64_t ullAddress;
    uint8_t  ucExDeviceId;
    uint8_t  ucPage;
    uint8_t  ucByteOffset;
    uint8_t  ucLength;

} AMI_PROXY_MODULE_RW_REQUEST;

/**
 * @struct  AMI_PROXY_IDENTITY_RESPONSE
 * @brief   Identity reponse
 */
typedef struct AMI_PROXY_IDENTITY_RESPONSE
{
    uint8_t  ucVerMajor;        /* major version number */
    uint8_t  ucVerMinor;        /* minor version number */
    uint8_t  ucVerPatch;        /* patch number */
    uint8_t  ucLocalChanges;    /* 0 for no changes, 1 for changes */
    uint16_t usDevCommits;      /* number of commits since the version tag */
    
    uint8_t  ucLinkVerMajor;    /* major version number of the comms link */
    uint8_t  ucLinkVerMinor;    /* minor version number of the comms link */

} AMI_PROXY_IDENTITY_RESPONSE;

/**
 * @struct  AMI_PROXY_HEARTBEAT_RESPONSE
 * @brief   Heartbeat response
 */
typedef struct AMI_PROXY_HEARTBEAT_RESPONSE
{
    uint8_t ucHeartbeatCount;   /* return the value sent in the request */

} AMI_PROXY_HEARTBEAT_RESPONSE;

/******************************************************************************/
/* Function declarations                                                      */
/******************************************************************************/

/* Init Functions *************************************************************/

/**
 * @brief   Main initialisation point for the AMI Proxy Driver
 *
 * @param   ucProxyId   Unique ID for this Proxy driver
 * @param   pxFwIf      Handle to the Firmware Interface to use
 * @param   ulFwIfPort  Port to use on the Firmware Interface
 * @param   ulTaskPrio  Priority of the Proxy driver task (if RR disabled)
 * @param   ulTaskStack Stack size of the Proxy driver task
 *
 * @return  OK          Proxy driver initialised correctly
 *          ERROR       Proxy driver not initialised, or was already initialised
 *
 * @note    Proxy drivers can have 0 or more firmware interfaces
 */
int iAMI_Initialise( uint8_t ucProxyId, FW_IF_CFG *pxFwIf, uint32_t ulFwIfPort,
                     uint32_t ulTaskPrio, uint32_t ulTaskStack );

/**
 * @brief   Bind into this proxy driver
 *
 * @param   pxCallback  Callback to bind into the proxy driver
 *
 * @return  OK          Callback successfully bound
 *          ERROR       Callback not bound
 */
int iAMI_BindCallback( EVL_CALLBACK *pxCallback );


/* Set Functions **************************************************************/

/**
 * @brief   Set the response after the PDI download has completed
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 * @param   xResult     The result of the pdi download request
 *
 * @return  OK          Data passed to proxy driver successfully
 *          ERROR       Data not passed successfully
 */
int iAMI_SetPdiDownloadCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult );

/**
 * @brief   Set the response after the PDI copy has completed
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 * @param   xResult     The result of the pdi copy request
 *
 * @return  OK          Data passed to proxy driver successfully
 *          ERROR       Data not passed successfully
 */
int iAMI_SetPdiCopyCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult );

/**
 * @brief   Set the response after the sensor request has completed
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 * @param   xResult     The result of the sensor request
 *
 * @return  OK          Data passed to proxy driver successfully
 *          ERROR       Data not passed successfully
 */
int iAMI_SetSensorCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult );

/**
 * @brief   Set the identity response
 *
 * @param   pxSignal                Current event occurance (used for tracking)
 * @param   xResult                 The result of the identity request
 * @param   pxIdentityResponse      The structure containing the version information
 *
 * @return  OK                      Data passed to proxy driver successfully
 *          ERROR                   Data not passed successfully
 */
int iAMI_SetIdentityResponse( EVL_SIGNAL *pxSignal,
                              AMI_PROXY_RESULT xResult,
                              AMI_PROXY_IDENTITY_RESPONSE *pxIdentityResponse );

/**
 * @brief   Set the response after the Boot select has completed
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 * @param   xResult     The result of the boot select request
 *
 * @return  OK          Data passed to proxy driver successfully
 *          ERROR       Data not passed successfully
 */
int iAMI_SetBootSelectCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult );

/**
 * @brief   Set the response after the EEPROM read/write has completed
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 * @param   xResult     The result of the EEPROM rd/wr request
 *
 * @return  OK          Data passed to proxy driver successfully
 *          ERROR       Data not passed successfully
 */
int iAMI_SetEepromReadWriteCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult );

/**
 * @brief   Set the response after the peek/poke has completed
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 * @param   xResult     The result of the rd/wr request in registers
 *
 * @return  OK          Data passed to proxy driver successfully
 *          ERROR       Data not passed successfully
 */
int iAMI_SetPeekPokeReadWriteCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult );

/**
 * @brief   Set the response after get ucore version has completed
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 * @param   xResult     The result of the rd/wr request in registers
 *
 * @return  OK          Data passed to proxy driver successfully
 *          ERROR       Data not passed successfully
 */
int iAMI_SetUcoreVersionCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult );

/**
 * @brief   Set the response after the module read/write has completed
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 * @param   xResult     The result of the module rd/wr request
 *
 * @return  OK          Data passed to proxy driver successfully
 *          ERROR       Data not passed successfully
 */
int iAMI_SetModuleReadWriteCompleteResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult );

/**
 * @brief   Set the response after the debug verbosity request has completed
 *
 * @param   pxSignal    Current event occurance (used for tracking)
 * @param   xResult     The result of the debug verbosity request
 *
 * @return  OK          Data passed to proxy driver successfully
 *          ERROR       Data not passed successfully
 */
int iAMI_SetDebugVerbosityResponse( EVL_SIGNAL *pxSignal, AMI_PROXY_RESULT xResult );

/* Get Functions **************************************************************/

/**
 * @brief   Get the PDI download request
 *
 * @param   pxSignal                Current event occurance (used for tracking)
 * @param   pxDownloadRequest       Pointer to download pdi structure
 *
 * @return  OK                      Data retrieved from proxy driver successfully
 *          ERROR                   Data not retrieved successfully
 */
int iAMI_GetPdiDownloadRequest( EVL_SIGNAL *pxSignal,
                                AMI_PROXY_PDI_DOWNLOAD_REQUEST *pxDownloadRequest );

/**
 * @brief   Get the PDI copy request
 *
 * @param   pxSignal                Current event occurance (used for tracking)
 * @param   pxCopyRequest           Pointer to copy pdi structure
 *
 * @return  OK                      Data retrieved from proxy driver successfully
 *          ERROR                   Data not retrieved successfully
 */
int iAMI_GetPdiCopyRequest( EVL_SIGNAL *pxSignal,
                            AMI_PROXY_PDI_COPY_REQUEST *pxCopyRequest );
/**
 * @brief   Get the Sensor request
 *
 * @param   pxSignal                Current event occurance (used for tracking)
 * @param   pxSensorRequest         Pointer sensor request structure
 *
 * @return  OK                      Data retrieved from proxy driver successfully
 *          ERROR                   Data not retrieved successfully
 *
 */
int iAMI_GetSensorRequest( EVL_SIGNAL *pxSignal, AMI_PROXY_SENSOR_REQUEST *pxSensorRequest );

/**
 * @brief   Get the Boot Select request
 *
 * @param   pxSignal                Current event occurance (used for tracking)
 * @param   pxBootSelectRequest     Pointer boot select request structure
 *
 * @return  OK                      Data retrieved from proxy driver successfully
 *          ERROR                   Data not retrieved successfully
 *
 */
int iAMI_GetBootSelectRequest( EVL_SIGNAL *pxSignal, AMI_PROXY_BOOT_SELECT_REQUEST *pxBootSelectRequest );

/**
 * @brief   Get the eeprom read write request
 *
 * @param   pxSignal                    Current event occurance (used for tracking)
 * @param   pxEepromReadWriteRequest    Pointer sensor request structure
 *
 * @return  OK                          Data retrieved from proxy driver successfully
 *          ERROR                       Data not retrieved successfully
 *
 */
int iAMI_GetEepromReadWriteRequest( EVL_SIGNAL *pxSignal,
                                    AMI_PROXY_EEPROM_RW_REQUEST *pxEepromReadWriteRequest );

/**
 * @brief   Get the HPU register read write request
 *
 * @param   pxSignal                    Current event occurance (used for tracking)
 * @param   pxEepromReadWriteRequest    Pointer sensor request structure
 *
 * @return  OK                          Data retrieved from proxy driver successfully
 *          ERROR                       Data not retrieved successfully
 *
 */
int iAMI_GetPeekPokeRequest( EVL_SIGNAL *pxSignal,
                             AMI_PROXY_PEEK_POKE_REQUEST *pxPeekPokeRequest );

/**
 * @brief   Get the module read write request
 *
 * @param   pxSignal                    Current event occurance (used for tracking)
 * @param   pxModuleReadWriteRequest    Pointer sensor request structure
 *
 * @return  OK                          Data retrieved from proxy driver successfully
 *          ERROR                       Data not retrieved successfully
 *
 */
int iAMI_GetModuleReadWriteRequest( EVL_SIGNAL *pxSignal,
                                    AMI_PROXY_MODULE_RW_REQUEST *pxModuleReadWriteRequest );

/**
 * @brief   Get the debug verbosity request
 *
 * @param   pxSignal                    Current event occurance (used for tracking)
 * @param   pucDebugVerbosityRequest    Pointer to store requested debug verbosity
 *
 * @return  OK                          Data retrieved from proxy driver successfully
 *          ERROR                       Data not retrieved successfully
 *
 */
int iAMI_GetDebugVerbosityRequest( EVL_SIGNAL *pxSignal,
                                   uint8_t *pucDebugVerbosityRequest );

/**
 * @brief   Print all the stats gathered by the application
 *
 * @return  OK          Stats retrieved from proxy driver successfully
 *          ERROR       Stats not retrieved successfully
 * 
 */
int iAMI_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the application
 *
 * @return  OK          Stats cleared successfully
 *          ERROR       Stats not cleared successfully
 * 
 */
int iAMI_ClearStatistics( void );

/**
 * @brief   Gets the current state of the proxy driver
 *
 * @param   pxState         Pointer to the state
 *
 * @return  OK              If successful
 *          ERROR           If not successful
 */
int iAMI_GetState( MODULE_STATE *pxState );

#endif
