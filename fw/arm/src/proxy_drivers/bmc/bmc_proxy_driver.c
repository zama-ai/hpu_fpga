/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implementation for the Board Management Controller (BMC) proxy driver
 *
 * @file bmc_proxy_driver.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <string.h>
#include "util.h"
#include "pll.h"
#include "osal.h"
#include "bmc_proxy_driver.h"
#include "pldm.h"
#include "fw_if.h"
#include "profile_hal.h"
#include "pldm_response.h"
#include "pldm_pdr.h"
#include "pldm_sensors.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL ( 0xBABECAFE )
#define LOWER_FIREWALL ( 0xDEADFACE )

#define BMC_TASK_SLEEP_MS               ( 10 )
#define MAX_RX_DATA_SIZE                ( 256 )
#define BMC_TERMINUS_LOCATOR_VALUE_SIZE ( 17 )
#define BMC_TERMINUS_INSTANCE_1         ( 1 )

/* Stat & Error definitions */
#define BMC_PROXY_STATS( DO )                       \
        DO( BMC_PROXY_STATS_INIT_OVERALL_COMPLETE ) \
        DO( BMC_PROXY_STATS_CREATE_MUTEX )          \
        DO( BMC_PROXY_STATS_CREATE_SEMAPHORE )      \
        DO( BMC_PROXY_STATS_PEND_SEMAPHORE )        \
        DO( BMC_PROXY_STATS_POST_SEMAPHORE )        \
        DO( BMC_PROXY_STATS_TAKE_MUTEX )            \
        DO( BMC_PROXY_STATS_RELEASE_MUTEX )         \
        DO( BMC_PROXY_STATS_TASK_TIME_MS )          \
        DO( BMC_PROXY_STATS_STATUS_RETRIEVAL )      \
        DO( BMC_PROXY_STATS_GET_SENSOR_ID_REQUEST ) \
        DO( BMC_PROXY_STATS_MAX )

#define BMC_PROXY_ERRORS( DO )                        \
        DO( BMC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )   \
        DO( BMC_PROXY_ERRORS_MUTEX_TAKE_FAILED )      \
        DO( BMC_PROXY_ERRORS_CREATE_SEMAPHORE )       \
        DO( BMC_PROXY_ERRORS_PEND_SEMAPHORE )         \
        DO( BMC_PROXY_ERRORS_POST_SEMAPHORE )         \
        DO( BMC_PROXY_ERRORS_FW_IF_OPEN_FAILED )      \
        DO( BMC_PROXY_ERRORS_FW_IF_READ_FAILED )      \
        DO( BMC_PROXY_ERRORS_MEM_ALLOC_FAILED )       \
        DO( BMC_PROXY_ERRORS_VALIDATION_FAILED )      \
        DO( BMC_PROXY_INIT_MUTEX_CREATE_FAILED )      \
        DO( BMC_PROXY_INIT_TASK_CREATE_FAILED )       \
        DO( BMC_PROXY_VALIDATION_FAILED )             \
        DO( BMC_PROXY_UNSUPPORTED_OPCODE_RX )         \
        DO( BMC_PROXY_FW_IF_WRITE_FAILED )            \
        DO( BMC_PROXY_BIND_CB_FAILED )                \
        DO( BMC_PROXY_ERRORS_INIT_EVL_RECORD_FAILED ) \
        DO( BMC_PROXY_RAISE_EVENT_FAIL )              \
        DO( BMC_UNEXPECTED_SENSOR_ID )                \
        DO( BMC_UNEXPECTED_FLAG )                     \
        DO( BMC_PROXY_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )  PLL_INF( BMC_NAME,                 \
                                          "%50s . . . . %d\r\n",    \
                                          BMC_PROXY_STATS_STR[ x ], \
                                          pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x ) PLL_INF( BMC_NAME,                  \
                                          "%50s . . . . %d\r\n",     \
                                          BMC_PROXY_ERRORS_STR[ x ], \
                                          pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )             { if( x < BMC_PROXY_STATS_MAX ) pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x )            { if( x < BMC_PROXY_ERRORS_MAX ) pxThis->pulErrorCounters[ x ]++; }
#define INC_ERROR_COUNTER_WITH_STATE( x ) { pxThis->xState = MODULE_STATE_ERROR; INC_ERROR_COUNTER( x ) }
#define SET_STAT_COUNTER( x, y )          { if( x < BMC_PROXY_ERRORS_MAX ) pxThis->pulStatCounters[ x ] = y; }

#define BMC_UNREQUIRED_BYTES      ( 2 )
#define BMC_ADDRESS_LOCATION      ( 0 )
#define BMC_PAYLOAD_SIZE_LOCATION ( 1 )
#define BMC_PAYLOAD_LOCATION      ( 2 )



/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    BMC_MSG_TYPES
 * @brief   Enumeration of mbox message types for this proxy
 */
typedef enum BMC_MSG_TYPES
{
    MAX_BMC_MSG_TYPE = 0

} BMC_MSG_TYPES;

/**
 * @enum    BMC_CMD_OPCODE_REQ
 * @brief   Internal message opcode
 */
typedef enum BMC_CMD_OPCODE_REQ
{
    BMC_CMD_OPCODE_MSG_ARRIVED_REQ = 0,
    MAX_BMC_CMD_OPCODE

} BMC_CMD_OPCODE_REQ;

/**
 * @enum    BMC_CMD_STATE
 * @brief   Internal command state
 */
typedef enum BMC_CMD_STATE
{
    BMC_CMD_STATE_COMPLETED = 0,
    BMC_CMD_STATE_ABORTED,
    BMC_CMD_STATE_TIMEOUT,
    BMC_CMD_STATE_INVALID,
    BMC_CMD_STATE_CONFLICT_ID,
    MAX_BMC_CMD_STATE

} BMC_CMD_STATE;

/**
 * @enum    BMC_PROXY_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( BMC_PROXY_STATS, BMC_PROXY_STATS, BMC_PROXY_STATS_STR )

/**
 * @enum    BMC_PROXY_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( BMC_PROXY_ERRORS, BMC_PROXY_ERRORS, BMC_PROXY_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  BMC_PRIVATE_DATA
 * @brief   Structure to hold ths proxy driver's private data
 */
typedef struct BMC_PRIVATE_DATA
{
    uint32_t                     ulUpperFirewall;

    int                          iInitialised;
    uint8_t                      ucMyId;

    FW_IF_CFG                    *pxFwIf;
    uint32_t                     ulFwIfPort;

    EVL_RECORD                   *pxEvlRecord;

    void                         *pvOsalMutexHdl;
    void                         *pvOsalMBoxHdl;
    void                         *pvOsalTaskHdl;
    void                         *pvOsalSemHdl;

    uint8_t                      pucRxData[ MAX_RX_DATA_SIZE ];
    uint32_t                     ulRxDataSize;
    uint8_t                      ucProcessRxData;

    uint8_t                      ucAwaitingSensorData;
    uint16_t                     usRequestedSensorId;
    uint8_t                      ucRequestedSensorOperationalState;
    uint8_t                      ucRequestedSensorEventMessageEnable;
    uint8_t                      ucSetNumericSensorEnableResponse;
    uint8_t                      ucGetNumericSensorResponse;
    uint8_t                      ucGetNumericSensorState;
    int16_t                      ssSensorInfo;

    PLDM_NUMERIC_SENSOR_PDR      *pxPdrTemperatureSensors;
    PLDM_NUMERIC_SENSOR_PDR      *pxPdrVoltageSensors;
    PLDM_NUMERIC_SENSOR_PDR      *pxPdrCurrentSensors;
    PLDM_NUMERIC_SENSOR_PDR      *pxPdrPowerSensors;
    PLDM_NUMERIC_SENSOR_NAME_PDR *pxPdrSensorNames;

    int                          iTotalPdrTemperature;
    int                          iTotalPdrVoltage;
    int                          iTotalPdrCurrent;
    int                          iTotalPdrPower;
    int                          iTotalPdrName;

    uint8_t                      pucUuid[ HAL_UUID_SIZE ];

    uint32_t                     pulStatCounters[ BMC_PROXY_STATS_MAX ];
    uint32_t                     pulErrorCounters[ BMC_PROXY_ERRORS_MAX ];

    MODULE_STATE                 xState;

    uint32_t                     ulLowerFirewall;

} BMC_PRIVATE_DATA;


/******************************************************************************/
/* Global Variables used in PLDM and MCTP code                                */
/******************************************************************************/

uint8_t ReqBuffer[ MAX_BUFFER_SIZE ] =
{
    0
};
uint8_t RespBuffer[ MAX_BUFFER_SIZE ] =
{
    0
};

TerminusPDRFormat_UID xPdrTerminusLocator[ TOTAL_PDR_COUNT_TERMINUS ] =
{
    {
        .PLDMTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .validity                         = ETerminusValidityValid,
        .TID                              = 0x0,
        .containerID                      = PLDM_CONTAINER_ID,
        .locator.terminusLocatorType      = ETerminusTypeUID,
        .locator.terminusLocatorValueSize = BMC_TERMINUS_LOCATOR_VALUE_SIZE,
        .locator.terminusInstance         = BMC_TERMINUS_INSTANCE_1,
        .locator.deviceUID                = {
            0
        }                                                                      /* This data is filled with UUID from EEPROM, in vPdrRepoInit() function */
    },
};


/******************************************************************************/
/* Local Variables                                                            */
/******************************************************************************/

static BMC_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                                                            /* ulUpperFirewall */
    FALSE,                                                                     /* iInitialised */
    0,                                                                         /* ucMyId */
    NULL,                                                                      /* pxFwIf */
    0,                                                                         /* ulFwIfPort */
    NULL,                                                                      /* pxEvlRecord */
    NULL,                                                                      /* pvOsalMutexHdl */
    NULL,                                                                      /* pvOsalMBoxHdl */
    NULL,                                                                      /* pvOsalTaskHdl */
    NULL,                                                                      /* pvOsalSemaphoreHdl */
    {
        0
    },                                                                         /* pucRxData */
    0,                                                                         /* ulRxDataSize */
    FALSE,                                                                     /* ucProcessRxData */
    FALSE,                                                                     /* ucAwaitingSensorData */
    0,                                                                         /* usRequestedSensorId */
    0,                                                                         /* ucRequestedSensorOperationalState */
    0,                                                                         /* ucRequestedSensorEventMessageEnable */
    BMC_SENSOR_ENABLE_RESP_NONE,                                               /* ucSetNumericSensorEnableResponse */
    BMC_GET_SENSOR_RESP_NONE,                                                  /* ucGetNumericSensorResponse */
    0,                                                                         /* ucGetNumericSensorState */
    0,                                                                         /* ssSensorInfo */

    NULL,                                                                      /* PLDM_NUMERIC_SENSOR_PDR *pxPdrTemperatureSensors */
    NULL,                                                                      /* PLDM_NUMERIC_SENSOR_PDR *pxPdrVoltageSensors */
    NULL,                                                                      /* PLDM_NUMERIC_SENSOR_PDR *pxPdrCurrentSensors */
    NULL,                                                                      /* PLDM_NUMERIC_SENSOR_PDR *pxPdrPowerSensors */
    NULL,                                                                      /* PLDM_NUMERIC_SENSOR_PDR *pxPdrSensorNames */
    0,                                                                         /* int iTotalPdrTemperature */
    0,                                                                         /* int iTotalPdrVoltage */
    0,                                                                         /* int iTotalPdrCurrent */
    0,                                                                         /* int iTotalPdrPower */
    0,                                                                         /* int iTotalPdrName */

    {
        0
    },                                                                         /* pucUuid */
    {
        0
    },                                                                         /* pulStatCounters */
    {
        0
    },                                                                         /* pulErrorCounters */
    MODULE_STATE_UNINITIALISED,                                                /* xState */
    LOWER_FIREWALL                                                             /* ulLowerFirewall */
};

static BMC_PRIVATE_DATA *pxThis = &xLocalData;

extern PDR_RepositoryInfo MSP432_PDR_Repository;

/******************************************************************************/
/* Local Function Declarations                                                */
/******************************************************************************/

/**
 * @brief   Check for incoming  message
 *
 */
static void vProcessRxMessage( void );

/**
 * @brief   Task declaration
 *
 * @param   pvArgs  Pointer to task args (unused)
 *
 * @return  N/A
 *
 */
static void vProxyDriverTask( void *pvArgs );

/**
 * @brief   Raise any BMC event
 *
 * @param   xBmcEventId   BMC Event
 * @return  OK            Event raised successfully
 *          ERROR         Event not raised successfully
 *
 */
static int iRaiseBmcEvent( BMC_PROXY_DRIVER_EVENTS xBmcEventId );

/**
 * @brief   Get the number of Temperature Sensor entries
 *
 * @return  Number of entries
 */
static int iGetNumTemperatureSensors( void );

/**
 * @brief   Get the number of Voltage Sensor entries
 *
 * @return  Number of entries
 */
static int iGetNumVoltageSensors( void );

/**
 * @brief   Get the number of Current Sensor entries
 *
 * @return  Number of entries
 */
static int iGetNumCurrentSensors( void );

/**
 * @brief   Get the number of Power Sensor entries
 *
 * @return  Number of entries
 */
static int iGetNumPowerSensors( void );

/**
 * @brief   Get the number of Name Sensor entries
 *
 * @return  Number of entries
 */
static int iGetNumNameSensors( void );

/**
 * @brief   Get the value of a Sensor
 *
 * @param   usSensorId                  Sensor id
 * @param   pucCompletionCode           Pointer to the completion code
 * @param   pucSensorOperationalState   Pointer to the value of operational state
 * @param   pssReading                  Pointer to the sensor reading
 *
 * @return  OK or ERROR
 */
int iGetNumericSensorReading( uint16_t usSensorId,
                              uint8_t *pucCompletionCode,
                              uint8_t *pucSensorOperationalState,
                              int16_t *pssReading );

/**
 * @brief   Store the values of Sensor ID and RequestedSensorOperationalState in BMC context
 *
 * @param   usSensorId                          Sensor id
 * @param   ucRequestedSensorOperationalState   value of operational state
 * @param   pucResponseMessage                  pointer to the PLDM message response
 * @param   piResponseSize                      pointer to the PLDM response message size
 *
 * @return  OK or ERROR
 */
int iSetNumericSensorEnable( uint16_t usSensorId,
                             uint8_t ucRequestedSensorOperationalState,
                             uint8_t *pucResponseMessage,
                             int *piResponseSize );

/**
 * @brief   Test function to trigger message processing
 *
 * @param   pucData     Pointer to the data
 * @param   usDatasize  Size of data received
 */
void vEmulateReceivedMessage( uint8_t *pucData, uint16_t usDatasize );

/**
 * @brief   Allocate memory for a Numeric Sensor PDR and fill it
 *
 * @param   pxIncomingSensorPDR Pointer to the supplied Sensor PDR
 * @param   iTotalPdr           Size of the incoming PDR
 * @param   pxLocalSensorPDR    Pointer to the local Sensor PDR
 * @param   piLocalTotalPdr     Size of the local PDR
 *
 * @return  OK or ERROR
 */
static int iAllocateNumericSensorPDR( PLDM_NUMERIC_SENSOR_PDR *pxIncomingSensorPDR,
                                      int iTotalPdr,
                                      PLDM_NUMERIC_SENSOR_PDR **ppxLocalSensorPDR,
                                      int *piLocalTotalPdr );

/**
 * @brief   Start a Data Write
 *
 * @param   pucData     Pointer to the data
 * @param   usDatasize  Size of data received
 *
 * @return  OK or ERROR
 */
int iResponseDataWrite( uint8_t *pucData, uint16_t usDataSize );

/**
 * @brief   Get the UUID
 *
 * @param   pucUuid   pointer to UUID location
 *
 * @return  OK or ERROR
 */
int iGetUuid( uint8_t *pucUuid );

/**
 * @brief   Check that the Sensor Id is valid
 *
 * @param   usSensorId  Sensor id
 *
 * @return  OK if sensor is valid or ERROR if invalid
 */
static int iCheckSensorValid( uint16_t usSensorId );

/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/


/**
 * @brief   Main initialisation point for the BMC Proxy Driver
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
                     uint8_t *pucUuid )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) &&
        ( NULL != pxFwIf ) &&
        ( NULL != pxPdrTemperatureSensors ) &&
        ( NULL != pxPdrVoltageSensors ) &&
        ( NULL != pxPdrCurrentSensors ) &&
        ( NULL != pxPdrPowerSensors ) &&
        ( NULL != pxPdrSensorNames ) &&
        ( NULL != pucUuid ) )
    {
        /* Store parameters locally */
        pxThis->ucMyId     = ucProxyId;
        pxThis->pxFwIf     = pxFwIf;
        pxThis->ulFwIfPort = ulFwIfPort;                                       /* The  Address */

        /* initalise evl record*/
        if( OK != iEVL_CreateRecord( &pxThis->pxEvlRecord ) )
        {
            PLL_ERR( BMC_NAME, "Error initialising EVL_RECORD\r\n" );
            INC_ERROR_COUNTER_WITH_STATE( BMC_PROXY_ERRORS_INIT_EVL_RECORD_FAILED );
        }
        else if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvOsalMutexHdl,
                                                         "bmc_proxy mutex" ) )
        {
            PLL_ERR( BMC_NAME, "Error initialising mutex\r\n" );
            INC_ERROR_COUNTER_WITH_STATE( BMC_PROXY_INIT_MUTEX_CREATE_FAILED )
        }
        else if( OSAL_ERRORS_NONE != iOSAL_Semaphore_Create( &pxThis->pvOsalSemHdl,
                                                             1,
                                                             1,
                                                             "BMC_Semaphore" ) )
        {
            PLL_ERR( BMC_NAME, "Error initialising semaphore\r\n" );
            INC_ERROR_COUNTER( BMC_PROXY_ERRORS_CREATE_SEMAPHORE )
        }
        else if( OSAL_ERRORS_NONE != iOSAL_Task_Create( &pxThis->pvOsalTaskHdl,
                                                        vProxyDriverTask,
                                                        ulTaskStack,
                                                        NULL,
                                                        ulTaskPrio,
                                                        "bmc_proxy task" ) )
        {
            PLL_ERR( BMC_NAME, "Error initialising task\r\n" );
            INC_ERROR_COUNTER_WITH_STATE( BMC_PROXY_INIT_TASK_CREATE_FAILED )
        }
        else
        {
            /* Get UUID */
            pvOSAL_MemCpy( pxThis->pucUuid, pucUuid, HAL_UUID_SIZE );


            /* Temperature PDR */
            iStatus = iAllocateNumericSensorPDR( pxPdrTemperatureSensors,
                                                 iTotalPdrTemperature,
                                                 &pxThis->pxPdrTemperatureSensors,
                                                 &pxThis->iTotalPdrTemperature );

            if( OK == iStatus )
            {
                /* Voltage PDR */
                iStatus = iAllocateNumericSensorPDR( pxPdrVoltageSensors,
                                                     iTotalPdrVoltage,
                                                     &pxThis->pxPdrVoltageSensors,
                                                     &pxThis->iTotalPdrVoltage );
            }

            if( OK == iStatus )
            {
                /* Current PDR */
                iStatus = iAllocateNumericSensorPDR( pxPdrCurrentSensors,
                                                     iTotalPdrCurrent,
                                                     &pxThis->pxPdrCurrentSensors,
                                                     &pxThis->iTotalPdrCurrent );
            }

            if( OK == iStatus )
            {
                /* Power PDR */
                iStatus = iAllocateNumericSensorPDR( pxPdrPowerSensors,
                                                     iTotalPdrPower,
                                                     &pxThis->pxPdrPowerSensors,
                                                     &pxThis->iTotalPdrPower );
            }

            if( OK == iStatus )
            {
                /* Names PDR */
                pxThis->pxPdrSensorNames =
                    ( PLDM_NUMERIC_SENSOR_NAME_PDR * )pvOSAL_MemAlloc( sizeof ( PLDM_NUMERIC_SENSOR_NAME_PDR ) *
                                                                       iTotalPdrName );
                if( NULL != pxThis->pxPdrSensorNames )
                {
                    pvOSAL_MemCpy( pxThis->pxPdrSensorNames,
                                   pxPdrSensorNames,
                                   sizeof( PLDM_NUMERIC_SENSOR_NAME_PDR ) * iTotalPdrName );
                    pxThis->iTotalPdrName = iTotalPdrName;
                }
                else
                {
                    iStatus = ERROR;
                    PLL_ERR( BMC_NAME, "pvOSAL_MemAlloc failed\r\n" );
                    INC_ERROR_COUNTER_WITH_STATE( BMC_PROXY_ERRORS_MEM_ALLOC_FAILED )
                }
            }

            if( OK == iStatus )
            {
                /* Now open the FW_IF to receive data */
                if( FW_IF_ERRORS_NONE != pxThis->pxFwIf->open( pxThis->pxFwIf ) )
                {
                    PLL_ERR( BMC_NAME, "Error opening FW_IF\r\n" );
                    INC_ERROR_COUNTER_WITH_STATE( BMC_PROXY_ERRORS_FW_IF_OPEN_FAILED )
                }
                else
                {
                    pxThis->iInitialised = TRUE;
                    pxThis->xState       = MODULE_STATE_OK;
                    iStatus              = OK;

                    /* Initialise anything required in MCTP or PLDM */
                    ( void ) pldm_command_init();

                    INC_STAT_COUNTER( BMC_PROXY_STATS_CREATE_MUTEX )
                    INC_STAT_COUNTER( BMC_PROXY_STATS_CREATE_SEMAPHORE )
                    INC_STAT_COUNTER( BMC_PROXY_STATS_INIT_OVERALL_COMPLETE )
                }
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( BMC_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Bind into this proxy driver
 */
int iBMC_BindCallback( EVL_CALLBACK *pxCallback )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxCallback ) &&
        ( NULL != pxThis->pxEvlRecord ) )
    {
        iStatus = iEVL_BindCallback( pxThis->pxEvlRecord, pxCallback );
        if( ERROR == iStatus )
        {
            INC_ERROR_COUNTER_WITH_STATE( BMC_PROXY_BIND_CB_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( BMC_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}


/* Set Functions **************************************************************/

/**
 * @brief   Response to a Sensor Info request
 */
int iBMC_SendResponseForGetSensor( EVL_SIGNAL *pxSignal,
                                   uint16_t usSensorId,
                                   int16_t ssSensorInfo,
                                   uint8_t ucSensorState,
                                   BMC_GET_SENSOR_RESPONSE xSensorResponse )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        if( TRUE == pxThis->ucAwaitingSensorData )
        {
            if( pxThis->usRequestedSensorId == usSensorId )
            {
                pxThis->ssSensorInfo = ssSensorInfo;

                if( eSensorOpStateEnabled == ucSensorState )
                {
                    pxThis->ucGetNumericSensorResponse = ucSensorState;
                }
                else
                {
                    pxThis->ucGetNumericSensorResponse = 0;
                }
                pxThis->ucRequestedSensorOperationalState = ucSensorState;
                pxThis->ucGetNumericSensorResponse        = xSensorResponse;
                iStatus = OK;
            }
            else
            {
                pxThis->ucGetNumericSensorResponse = BMC_GET_SENSOR_RESP_NONE;
                INC_ERROR_COUNTER( BMC_UNEXPECTED_SENSOR_ID )
            }
            pxThis->ucAwaitingSensorData = FALSE;
        }
        else
        {
            INC_ERROR_COUNTER( BMC_UNEXPECTED_FLAG )
        }
    }
    else
    {
        INC_ERROR_COUNTER( BMC_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Response to an enable sensor request
 *
 */
int iBMC_SetResponse( EVL_SIGNAL *pxSignal, uint16_t usSensorId, BMC_SENSOR_RESPONSE xBmcResponse )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        if( TRUE == pxThis->ucAwaitingSensorData )
        {
            if( pxThis->usRequestedSensorId == usSensorId )
            {
                pxThis->ucSetNumericSensorEnableResponse = xBmcResponse;
                iStatus = OK;
            }
            else
            {
                pxThis->ucSetNumericSensorEnableResponse = BMC_SENSOR_ENABLE_RESP_NONE;
                INC_ERROR_COUNTER( BMC_UNEXPECTED_SENSOR_ID )
            }
            pxThis->ucAwaitingSensorData = FALSE;
        }
        else
        {
            INC_ERROR_COUNTER( BMC_UNEXPECTED_FLAG )
        }
    }
    else
    {
        INC_ERROR_COUNTER( BMC_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/* Get Functions **************************************************************/

/**
 * @brief   Display the current stats/errors
 */
int iBMC_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( BMC_NAME, "============================================================\n\r" );
        PLL_INF( BMC_NAME, "BMC Proxy Statistics:\n\r" );
        for( i = 0; i < BMC_PROXY_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( BMC_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( BMC_NAME, "BMC Proxy Errors:\n\r" );
        for( i = 0; i < BMC_PROXY_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );

        }
        PLL_INF( BMC_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( BMC_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iBMC_ClearStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        pvOSAL_MemSet( pxThis->pulStatCounters, 0, sizeof( pxThis->pulStatCounters ) );
        pvOSAL_MemSet( pxThis->pulErrorCounters, 0, sizeof( pxThis->pulErrorCounters ) );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( BMC_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Get the Id of the sensor to read
 *
 * @return  OK or ERROR
 */
int iBMC_GetSensorIdRequest( EVL_SIGNAL *pxSignal, int16_t *pssSensorId, uint8_t *pucOperationalState )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxSignal ) &&
        ( NULL != pssSensorId ) &&
        ( NULL != pucOperationalState ) )
    {
        INC_STAT_COUNTER( BMC_PROXY_STATS_GET_SENSOR_ID_REQUEST )

        * pssSensorId        = pxThis->usRequestedSensorId;
        *pucOperationalState = pxThis->ucRequestedSensorOperationalState;
        iStatus              = OK;

    }
    else
    {
        INC_ERROR_COUNTER( BMC_PROXY_VALIDATION_FAILED )
    }

    return iStatus;
}


/******************************************************************************/
/* Local Function Implementations                                             */
/******************************************************************************/

/**
 * @brief   Check that the sensor id is valid
 */
static int iCheckSensorValid( uint16_t usSensorId )
{
    int iStatus     = ERROR;
    int iNumSensors = 0;
    int i           = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        /*
         * Check the Temperature sensors PDR
         */
        iNumSensors = iGetNumTemperatureSensors();
        for( i = 0; i < iNumSensors ; i++ )
        {
            if( pxThis->pxPdrTemperatureSensors[ i ].usSensorId  == usSensorId )
            {
                iStatus = OK;
                break;
            }
        }

        if( OK != iStatus )
        {
            /*
             * Check the Voltage sensors PDR
             */
            iNumSensors = iGetNumVoltageSensors();
            for( i = 0; i < iNumSensors; i++ )
            {
                if( pxThis->pxPdrVoltageSensors[ i ].usSensorId  == usSensorId )
                {
                    iStatus = OK;
                    break;
                }
            }
        }

        if( OK != iStatus )
        {
            /*
             * Check the Current sensors PDR
             */
            iNumSensors = iGetNumCurrentSensors();
            for( i = 0; i < iNumSensors; i++ )
            {
                if( pxThis->pxPdrCurrentSensors[ i ].usSensorId  == usSensorId )
                {
                    iStatus = OK;
                    break;
                }
            }
        }

        if( OK != iStatus )
        {
            /*
             * Check the Power PDR
             */
            iNumSensors = iGetNumPowerSensors();
            for( i = 0; i < iNumSensors; i++ )
            {
                if( pxThis->pxPdrPowerSensors[ i ].usSensorId  == usSensorId )
                {
                    iStatus = OK;
                    break;
                }
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Allocate memory for a Numeric Sensor PDR and fill it
 */
static int iAllocateNumericSensorPDR( PLDM_NUMERIC_SENSOR_PDR *pxIncomingSensorPDR,
                                      int iTotalPdr,
                                      PLDM_NUMERIC_SENSOR_PDR **ppxLocalSensorPDR,
                                      int *piLocalTotalPdr )
{
    int iStatus = OK;

    if( ( NULL != pxIncomingSensorPDR ) &&
        ( NULL != ppxLocalSensorPDR ) )
    {
        *ppxLocalSensorPDR =
            ( PLDM_NUMERIC_SENSOR_PDR * )pvOSAL_MemAlloc( sizeof ( PLDM_NUMERIC_SENSOR_PDR ) *
                                                          iTotalPdr );
        if( NULL != *ppxLocalSensorPDR )
        {
            pvOSAL_MemCpy( *ppxLocalSensorPDR,
                           pxIncomingSensorPDR,
                           sizeof( PLDM_NUMERIC_SENSOR_PDR ) * iTotalPdr );
            *piLocalTotalPdr = iTotalPdr;
        }
        else
        {
            iStatus = ERROR;
            PLL_ERR( BMC_NAME, "pvOSAL_MemAlloc failed\r\n" );
            INC_ERROR_COUNTER_WITH_STATE( BMC_PROXY_ERRORS_MEM_ALLOC_FAILED )
        }
    }

    return iStatus;
}

/**
 * @brief   Task to handle incoming requests and handle responses being sent
 *          out the message queue.
 */
static void vProxyDriverTask( void *pvArgs )
{
    uint32_t ulStartMs = 0;

    FOREVER
    {
        ulStartMs = ulOSAL_GetUptimeMs();

        if( FW_IF_ERRORS_NONE != pxThis->pxFwIf->read( pxThis->pxFwIf,
                                                       0,
                                                       pxThis->pucRxData,
                                                       &( pxThis->ulRxDataSize ),
                                                       0 ) )
        {
            INC_ERROR_COUNTER_WITH_STATE( BMC_PROXY_ERRORS_FW_IF_READ_FAILED )
        }
        else
        {
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                      OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                INC_STAT_COUNTER( BMC_PROXY_STATS_TAKE_MUTEX )

                /* Reset any variables that may be used */
                pxThis->ucAwaitingSensorData                = FALSE;
                pxThis->usRequestedSensorId                 = 0;
                pxThis->ucRequestedSensorOperationalState   = 0;
                pxThis->ucRequestedSensorEventMessageEnable = 0;
                pxThis->ucSetNumericSensorEnableResponse    = 0;
                pxThis->ucGetNumericSensorResponse          = 0;
                pxThis->ucGetNumericSensorState             = 0;
                pxThis->ssSensorInfo = 0;

                pxThis->ucProcessRxData = TRUE;

                if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
                {
                    INC_ERROR_COUNTER( BMC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                }
                else
                {
                    INC_STAT_COUNTER( BMC_PROXY_STATS_RELEASE_MUTEX )
                }
            }
            else
            {
                INC_ERROR_COUNTER( BMC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
            }
        }

        if( TRUE == pxThis->ucProcessRxData )
        {
            /* We have received a message so work on it */
            vProcessRxMessage();

        }

        pxThis->pulStatCounters[ BMC_PROXY_STATS_TASK_TIME_MS ] = UTIL_ELAPSED_TIME_MS( ulStartMs )
    }
}

/**
 * @brief   Check for incoming  message
 *
 */
static void vProcessRxMessage( void )
{
    int      iStatus                 = ERROR;
    uint32_t ulRequestMessageTimeMs  = ulOSAL_GetUptimeMs();
    uint32_t ulResponseMessageTimeMs = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( BMC_PROXY_STATS_TAKE_MUTEX )

            /* raise event that  message arrived to anyone interested */
            EVL_SIGNAL xNewSignal =
            {
                pxThis->ucMyId,
                BMC_PROXY_DRIVER_E_MSG_ARRIVAL,
                0,
                0
            };
            xNewSignal.ucEventType = BMC_PROXY_DRIVER_E_MSG_ARRIVAL;
            iStatus                = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );

            if( ERROR == iStatus )
            {
                PLL_ERR( BMC_NAME,
                         "Error attempting to raise event 0x%x\r\n",
                         BMC_PROXY_DRIVER_E_MSG_ARRIVAL );
                INC_ERROR_COUNTER( BMC_PROXY_RAISE_EVENT_FAIL )
            }
            else
            {
                int iMessageDataSize = ERROR;

                ( void )pvOSAL_MemSet( ReqBuffer, 0, MAX_BUFFER_SIZE );
                ( void )pvOSAL_MemSet( RespBuffer, 0, MAX_BUFFER_SIZE );

                iMessageDataSize = pxThis->ulRxDataSize;

                /* Leave 2 spaces at the beginning of request buffer for dest_slave_addr and size */
                ReqBuffer[ BMC_PAYLOAD_SIZE_LOCATION ] = pxThis->ulRxDataSize;
                ( void )pvOSAL_MemCpy( ReqBuffer + BMC_PAYLOAD_LOCATION, pxThis->pucRxData, pxThis->ulRxDataSize );

                if( 0 < iMessageDataSize )
                {
                    /* Call into existing PLDM / MCTP Code process_OoB_request
                       We add on 2 bytes since the message is missing bytes that existing
                       i2c message would have */
                    process_pmci_request( iMessageDataSize + BMC_PAYLOAD_LOCATION );

                    ulResponseMessageTimeMs = ulOSAL_GetUptimeMs();
                    PLL_DBG( BMC_NAME,
                             "Message processing took %d mS\r\n",
                             ( ulResponseMessageTimeMs - ulRequestMessageTimeMs ) );
                }
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER( BMC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
            }
            else
            {
                INC_STAT_COUNTER( BMC_PROXY_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER( BMC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }

        /* Clear the flag */
        pxThis->ucProcessRxData = FALSE;
    }
}

/**
 * @brief   Raise a BMC event
 *
 * @return  OK or ERROR
 */
static int iRaiseBmcEvent( BMC_PROXY_DRIVER_EVENTS xBmcEventId )
{
    int iStatus = ERROR;

    EVL_SIGNAL xNewSignal =
    {
        pxThis->ucMyId,
        xBmcEventId,
        0,
        0
    };

    if( ( BMC_PROXY_DRIVER_E_GET_SENSOR_INFO == xBmcEventId ) ||
        ( BMC_PROXY_DRIVER_E_ENABLE_SENSOR == xBmcEventId ) )
    {
        pxThis->ucAwaitingSensorData = TRUE;
    }

    xNewSignal.ucEventType = xBmcEventId;
    iStatus                = iEVL_RaiseEvent( pxThis->pxEvlRecord, &xNewSignal );
    if( ERROR == iStatus )
    {
        PLL_ERR( BMC_NAME,
                 "Error attempting to raise event 0x%x\r\n",
                 BMC_PROXY_DRIVER_E_MSG_ARRIVAL );
        INC_ERROR_COUNTER( BMC_PROXY_RAISE_EVENT_FAIL )
    }

    return iStatus;
}


/**
 * @brief   Set the enable for a Sensor
 *
 * @return  OK or ERROR
 */
int iSetNumericSensorEnable( uint16_t usSensorId,
                             uint8_t ucSensorOperationalState,
                             uint8_t *pucResponseMessage,
                             int *piResponseSize )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucResponseMessage ) &&
        ( NULL != piResponseSize ) )
    {
        pxThis->usRequestedSensorId               = usSensorId;
        pxThis->ucRequestedSensorOperationalState = ucSensorOperationalState;

        if( OK == iCheckSensorValid( usSensorId ) )
        {
            if( OK == iRaiseBmcEvent( BMC_PROXY_DRIVER_E_ENABLE_SENSOR ) )
            {
                iStatus = OK;

                /* OoB applicatiion will respond */
                /* Now check the response */
                switch( pxThis->ucSetNumericSensorEnableResponse )
                {
                case BMC_SENSOR_ENABLE_RESP_OK:
                {
                    pucResponseMessage[ ( *piResponseSize )++ ] = RESP_PLDM_SUCCESS;
                    break;
                }

                case BMC_SENSOR_ENABLE_RESP_INVALID_SENSOR_ID:
                {
                    pucResponseMessage[ ( *piResponseSize )++ ] = RESP_INVALID_SENSOR_ID;
                    break;
                }

                case BMC_SENSOR_ENABLE_RESP_INVALID_SENSOR_OPERATIONAL_STATE:
                {
                    pucResponseMessage[ ( *piResponseSize )++ ] = RESP_INVALID_SENSOR_OPERATIONAL_STATE;
                    break;
                }

                case BMC_SENSOR_ENABLE_RESP_EVENT_GENERATION_NOT_SUPPORTED:
                {
                    pucResponseMessage[ ( *piResponseSize )++ ] = RESP_EVENT_GENERATION_NOT_SUPPORTED;
                    break;
                }

                default:
                {
                    pucResponseMessage[ ( *piResponseSize )++ ] = RESP_PLDM_ERROR_GENERIC;
                    break;
                }
                }

            }
            else
            {
                pucResponseMessage[ ( *piResponseSize )++ ] = RESP_PLDM_ERROR_GENERIC;
            }
        }
        else
        {
            pucResponseMessage[ ( *piResponseSize )++ ] = RESP_INVALID_SENSOR_ID;
        }
    }

    return iStatus;
}

/**
 * @brief   Get the value of a Sensor
 *
 * @return  OK or ERROR
 */
int iGetNumericSensorReading( uint16_t usSensorId,
                              uint8_t *pucCompletionCode,
                              uint8_t *pucSensorOperationalState,
                              int16_t *pssReading )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucCompletionCode ) &&
        ( NULL != pucSensorOperationalState ) &&
        ( NULL != pssReading ) )
    {
        pxThis->usRequestedSensorId = usSensorId;

        if( OK == iCheckSensorValid( usSensorId ) )
        {
            if( OK == iRaiseBmcEvent( BMC_PROXY_DRIVER_E_GET_SENSOR_INFO ) )
            {
                iStatus = OK;

                /* OoB applicatiion will respond */
                /* Now check the response */
                switch( pxThis->ucGetNumericSensorResponse )
                {
                case BMC_GET_SENSOR_RESP_OK:
                {
                    *pucCompletionCode         = RESP_PLDM_SUCCESS;
                    *pucSensorOperationalState = pxThis->ucRequestedSensorOperationalState;
                    *pssReading                = pxThis->ssSensorInfo;
                    break;
                }

                case BMC_GET_SENSOR_RESP_INVALID_SENSOR_ID:
                {
                    *pucCompletionCode = RESP_INVALID_SENSOR_ID;
                    break;
                }

                case BMC_GET_SENSOR_RESP_INVALID_SENSOR_OPERATIONAL_STATE:
                {
                    *pucCompletionCode = RESP_INVALID_SENSOR_OPERATIONAL_STATE;
                    break;
                }

                case BMC_GET_SENSOR_RESP_REARM_UNAVAILABLE_IN_PRESENT_STATE:
                {
                    *pucCompletionCode = RESP_REARM_UNAVAILABLE_IN_PRESENT_STATE;
                    break;
                }

                default:
                {
                    *pucCompletionCode = RESP_PLDM_ERROR_GENERIC;
                    break;
                }
                }
            }
            else
            {
                *pucCompletionCode = RESP_PLDM_ERROR_GENERIC;
            }
        }
        else
        {
            *pucCompletionCode = RESP_INVALID_SENSOR_ID;
        }
    }

    return iStatus;
}

/**
 * @brief   Get the number of Temperature Sensor entries
 *
 * @return  Number of entries
 */
int iGetNumTemperatureSensors( void )
{
    int iNumber = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        iNumber = pxThis->iTotalPdrTemperature;
    }

    return iNumber;
}

/**
 * @brief   Get the number of Voltage Sensor entries
 *
 * @return  Number of entries
 */
int iGetNumVoltageSensors( void )
{
    int iNumber = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        iNumber = pxThis->iTotalPdrVoltage;
    }

    return iNumber;
}

/**
 * @brief   Get the number of Current Sensor entries
 *
 * @return  Number of entries
 */
int iGetNumCurrentSensors( void )
{
    int iNumber = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        iNumber = pxThis->iTotalPdrCurrent;
    }

    return iNumber;
}

/**
 * @brief   Get the number of Power Sensor entries
 *
 * @return  Number of entries
 */
int iGetNumPowerSensors( void )
{
    int iNumber = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        iNumber = pxThis->iTotalPdrPower;
    }

    return iNumber;
}

/**
 * @brief   Get the number of Name Sensor entries
 *
 * @return  Number of entries
 */
int iGetNumNameSensors( void )
{
    int iNumber = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        iNumber = pxThis->iTotalPdrName;
    }

    return iNumber;
}

/**
 * @brief   Populate the PDR Repo
 */
void vPdrRepoInit( void )
{
    static int         iIsRepoInitialized = 0;
    PDR_RepositoryInfo *pxRepo            =
    {
        0
    };
    int             i             = 0;
    int             iRecordHandle = 0;
    CommonPDRFormat *pxHeader     =
    {
        0
    };
    int iCurrRecordSize = 0;
    int iNumSensors     = 0;

    if( iIsRepoInitialized )
    {
        return;
    }

    iIsRepoInitialized = 1;

    pxRepo                            = &MSP432_PDR_Repository;
    pxRepo->repositoryState           = ERepoStateAvailable;
    pxRepo->recordCount               = 0;
    pxRepo->repositorySize            = 0;
    pxRepo->largestRecordSize         = 0;
    pxRepo->dataTransferHandleTimeout = 0;

    vUpdateTimestamp( &pxRepo->updateTimestamp );
    pxRepo->updateTimestamp.UTC_Time_Resolution = 0xF;
    pxRepo->OEMUpdateTimestamp                  = pxRepo->updateTimestamp;

    /*
     * Update the terminus PDRs
     */
    for( i = 0; i < TOTAL_PDR_COUNT_TERMINUS; i++ )
    {
        pvOSAL_MemCpy( &xPdrTerminusLocator[ i ].locator.deviceUID[ 0 ], pxThis->pucUuid, HAL_UUID_SIZE );
        pxHeader                     = pxRepo->PDRRecords[ iRecordHandle ] = xPdrTerminusLocator + i;
        pxHeader->recordHandle       = iRecordHandle;
        pxHeader->PDRHeaderVersion   = PDR_HEADER_VERSION;
        pxHeader->PDRType            = EPDRTypeTerminusLocator;
        pxHeader->recordChangeNumber = 0;                                      /* gets updated if the record is updated */
        iCurrRecordSize              = sizeof( xPdrTerminusLocator[ i ] );
        pxHeader->dataLength         = iCurrRecordSize - sizeof( CommonPDRFormat );

        /*
         * Update repo info
         */
        iRecordHandle++;
        pxRepo->recordCount++;
        pxRepo->repositorySize   += iCurrRecordSize;
        pxRepo->largestRecordSize = MAX( pxRepo->largestRecordSize, iCurrRecordSize );
    }

    /*
     * Update the Temperature sensors PDR
     */
    iNumSensors = iGetNumTemperatureSensors();
    for( i = 0; i < iNumSensors ; i++ )
    {
        pxHeader                     = pxRepo->PDRRecords[ iRecordHandle ] = pxThis->pxPdrTemperatureSensors + i;
        pxHeader->recordHandle       = iRecordHandle;
        pxHeader->PDRHeaderVersion   = PDR_HEADER_VERSION;
        pxHeader->PDRType            = EPDRTypeNumericSensor;
        pxHeader->recordChangeNumber = 0;                                      /* gets updated if the record is updated */
        iCurrRecordSize              = sizeof( pxThis->pxPdrTemperatureSensors[ i ] );
        pxHeader->dataLength         = iCurrRecordSize - sizeof( CommonPDRFormat );

        /*
         * Update repo info
         */
        iRecordHandle++;
        pxRepo->recordCount++;
        pxRepo->repositorySize   += iCurrRecordSize;
        pxRepo->largestRecordSize = MAX( pxRepo->largestRecordSize, iCurrRecordSize );
    }

    /*
     * Update the Voltage sensors PDR
     */
    iNumSensors = iGetNumVoltageSensors();
    for( i = 0; i < iNumSensors; i++ )
    {
        pxHeader                     = pxRepo->PDRRecords[ iRecordHandle ] = pxThis->pxPdrVoltageSensors + i;
        pxHeader->recordHandle       = iRecordHandle;
        pxHeader->PDRHeaderVersion   = PDR_HEADER_VERSION;
        pxHeader->PDRType            = EPDRTypeNumericSensor;
        pxHeader->recordChangeNumber = 0;                                      /* gets updated if the record is updated */
        iCurrRecordSize              = sizeof( pxThis->pxPdrVoltageSensors[ i ] );
        pxHeader->dataLength         = iCurrRecordSize - sizeof( CommonPDRFormat );

        /*
         * Update repo info
         */
        iRecordHandle++;
        pxRepo->recordCount++;
        pxRepo->repositorySize   += iCurrRecordSize;
        pxRepo->largestRecordSize = MAX( pxRepo->largestRecordSize, iCurrRecordSize );
    }

    /*
     * Update the Current sensors PDR
     */
    iNumSensors = iGetNumCurrentSensors();
    for( i = 0; i < iNumSensors; i++ )
    {
        pxHeader                     = pxRepo->PDRRecords[ iRecordHandle ] = pxThis->pxPdrCurrentSensors + i;
        pxHeader->recordHandle       = iRecordHandle;
        pxHeader->PDRHeaderVersion   = PDR_HEADER_VERSION;
        pxHeader->PDRType            = EPDRTypeNumericSensor;
        pxHeader->recordChangeNumber = 0;                                      /* gets updated if the record is updated */
        iCurrRecordSize              = sizeof( pxThis->pxPdrCurrentSensors[ i ] );
        pxHeader->dataLength         = iCurrRecordSize - sizeof( CommonPDRFormat );

        /*
         * Update repo info
         */
        iRecordHandle++;
        pxRepo->recordCount++;
        pxRepo->repositorySize   += iCurrRecordSize;
        pxRepo->largestRecordSize = MAX( pxRepo->largestRecordSize, iCurrRecordSize );
    }

    /*
     * Update the Power PDR
     */
    iNumSensors = iGetNumPowerSensors();
    for( i = 0; i < iNumSensors; i++ )
    {
        pxHeader                     = pxRepo->PDRRecords[ iRecordHandle ] = pxThis->pxPdrPowerSensors + i;
        pxHeader->recordHandle       = iRecordHandle;
        pxHeader->PDRHeaderVersion   = PDR_HEADER_VERSION;
        pxHeader->PDRType            = EPDRTypeNumericSensor;
        pxHeader->recordChangeNumber = 0;                                      /* gets updated if the record is updated */
        iCurrRecordSize              = sizeof( pxThis->pxPdrPowerSensors[ i ] );
        pxHeader->dataLength         = iCurrRecordSize - sizeof( CommonPDRFormat );

        /*
         * Update repo info
         */
        iRecordHandle++;
        pxRepo->recordCount++;
        pxRepo->repositorySize   += iCurrRecordSize;
        pxRepo->largestRecordSize = MAX( pxRepo->largestRecordSize, iCurrRecordSize );
    }

    /*
     * Update the Names PDR
     */
    iNumSensors = iGetNumNameSensors();
    for( i = 0; i < iNumSensors; i++ )
    {
        pxHeader                     = pxRepo->PDRRecords[ iRecordHandle ] = pxThis->pxPdrSensorNames + i;
        pxHeader->recordHandle       = iRecordHandle;
        pxHeader->PDRHeaderVersion   = PDR_HEADER_VERSION;
        pxHeader->PDRType            = EPDRTypeSensorAuxNames;
        pxHeader->recordChangeNumber = 0;                                      /* gets updated if the record is updated */
        iCurrRecordSize              = sizeof( pxThis->pxPdrSensorNames[ i ] ) -
                                       sensor_name_empty_space( pxThis->pxPdrSensorNames[ i ].ucSensorNameBe16 );
        pxHeader->dataLength = iCurrRecordSize - sizeof( CommonPDRFormat );

        /*
         * Update repo info
         */
        iRecordHandle++;
        pxRepo->recordCount++;
        pxRepo->repositorySize   += iCurrRecordSize;
        pxRepo->largestRecordSize = MAX( pxRepo->largestRecordSize, iCurrRecordSize );

    }
}

/**
 * @brief   Test function to trigger message processing
 */
void vEmulateReceivedMessage( uint8_t *pucData, uint16_t usDatasize )
{
    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucData ) )
    {
        pvOSAL_MemCpy( pxThis->pucRxData, pucData, usDatasize );
        pxThis->ulRxDataSize    = usDatasize;
        pxThis->ucProcessRxData = TRUE;
    }
}

/**
 * @brief   Call FW_IF to send data
 *
 * @return  OK or ERROR
 */
int iResponseDataWrite( uint8_t *pucData, uint16_t usDataSize )
{
    int iStatus = ERROR;
    int i       = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucData ) )
    {
        if( FW_IF_ERRORS_NONE == pxThis->pxFwIf->write( pxThis->pxFwIf,
                                                        ( uint64_t )pucData[ BMC_ADDRESS_LOCATION ],
                                                        &pucData[ BMC_PAYLOAD_LOCATION ],
                                                        ( usDataSize - BMC_UNREQUIRED_BYTES ),
                                                        0 ) )
        {
            iStatus = usDataSize;
        }

        PLL_DBG( BMC_NAME,
                 "\n\r Payload Size %d Destination 0x%x\n\r",
                 ( usDataSize - BMC_UNREQUIRED_BYTES ),
                 pucData[ 0 ] );

        for( i = BMC_PAYLOAD_LOCATION; i < usDataSize; i++ )
        {
            vPLL_Output( PLL_OUTPUT_LEVEL_DEBUG, "%02x ", pucData[ i ] );
        }
        vPLL_Output( PLL_OUTPUT_LEVEL_DEBUG, "\n\r" );
    }

    return iStatus;
}

/**
 * @brief   Get the UUID
 *
 * @return  UUID Size
 */
int iGetUuid( uint8_t *pucUuid )
{
    int iStatus = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucUuid ) )
    {
        pvOSAL_MemCpy( pucUuid, pxThis->pucUuid, HAL_UUID_SIZE );
        iStatus = HAL_UUID_SIZE;
    }

    return iStatus;
}

/**
 * @brief   Gets the current state of the proxy
 */
int iBMC_GetState( MODULE_STATE *pxState )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxState ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl, OSAL_TIMEOUT_TASK_WAIT_MS ) )
        {
            INC_STAT_COUNTER( BMC_PROXY_STATS_TAKE_MUTEX );
            *pxState = pxThis->xState;

            INC_STAT_COUNTER( BMC_PROXY_STATS_STATUS_RETRIEVAL );

            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_STAT_COUNTER( BMC_PROXY_STATS_RELEASE_MUTEX )
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER_WITH_STATE( BMC_PROXY_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
        }
        else
        {
            INC_ERROR_COUNTER_WITH_STATE( BMC_PROXY_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( BMC_PROXY_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}
