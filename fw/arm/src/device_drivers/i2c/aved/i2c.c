/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the user API definitions for the I2C driver.
 *
 * @file i2c.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include "xiicps.h"

#include "util.h"
#include "pll.h"
#include "osal.h"

#include "i2c.h"
#include "profile_hal.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/
#define UPPER_FIREWALL ( 0xBABECAFE )
#define LOWER_FIREWALL ( 0xDEADFACE )

#define I2C_NAME "I2C"

/* Verbose data log - disabled by default */
//#define I2C_DEBUG_DATA_LOG_ENABLE
#define I2C_LOG_STRING_LENGTH       ( 105 )
#define I2C_LOG_DEPTH               ( 100 )
#define I2C_DEBUG_DATA_LOG_BUFF_MAX ( 60 )
#define I2C_DEBUG_CHAR_PER_VALUE    ( 5 )

#define I2C_DEBUG_DATA_READ  ( 0 )
#define I2C_DEBUG_DATA_WRITE ( 1 )

#define I2C_WAIT_TIMEOUT_MS  ( 100 )
#define I2C_RESET_TIMEOUT_MS ( 100 )

/* Stat & Error definitions */
#define I2C_STATS( DO )                   \
        DO( I2C_STATS_INIT_COMPLETED )    \
        DO( I2C_STATS_SEND_COMPLETED )    \
        DO( I2C_STATS_RECEIVE_COMPLETED ) \
        DO( I2C_STATS_CREATE_TIMER )      \
        DO( I2C_STATS_CREATE_MUTEX )      \
        DO( I2C_STATS_TAKE_MUTEX )        \
        DO( I2C_STATS_RELEASE_MUTEX )     \
        DO( I2C_STATS_REINIT_SUCCESSFUL ) \
        DO( I2C_STATS_MAX )

#define I2C_ERRORS( DO )                                      \
        DO( I2C_ERRORS_VALIDATION_FAILED )                    \
        DO( I2C_ERRORS_XIIC_PS_CONFIG_FAILED )                \
        DO( I2C_ERRORS_XIIC_PS_SET_CLK_FAILED )               \
        DO( I2C_ERRORS_XIIC_PS_MASTER_SEND_POLLED_FAILED )    \
        DO( I2C_ERRORS_XIIC_PS_MASTER_RECEIVE_POLLED_FAILED ) \
        DO( I2C_ERRORS_XIIC_PS_SET_OPTIONS_FAILED )           \
        DO( I2C_ERRORS_XIIC_PS_CLEAR_OPTIONS_FAILED )         \
        DO( I2C_ERRORS_TIMER_CREATE_FAILED )                  \
        DO( I2C_ERRORS_TIMER_START_FAILED )                   \
        DO( I2C_ERRORS_TIMER_STOP_FAILED )                    \
        DO( I2C_ERRORS_MUTEX_CREATE_FAILED )                  \
        DO( I2C_ERRORS_MUTEX_RELEASE_FAILED )                 \
        DO( I2C_ERRORS_MUTEX_TAKE_FAILED )                    \
        DO( I2C_ERRORS_WAIT_FOR_BUS_IDLE_FAILED )             \
        DO( I2C_ERRORS_WAIT_FOR_BUS_IDLE_TIMED_OUT )          \
        DO( I2C_ERRORS_REINIT_FAILED )                        \
        DO( I2C_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )  PLL_INF( I2C_NAME,              \
                                          "%50s . . . . %d\r\n", \
                                          I2C_STATS_STR[ x ],    \
                                          pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x ) PLL_INF( I2C_NAME,              \
                                          "%50s . . . . %d\r\n", \
                                          I2C_ERRORS_STR[ x ],   \
                                          pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )  { if( x < I2C_STATS_MAX ) pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x ) { if( x < I2C_ERRORS_MAX ) pxThis->pulErrorCounters[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    I2C_STATS
 * @brief   Enumeration of stats counters for this driver
 */
UTIL_MAKE_ENUM_AND_STRINGS( I2C_STATS, I2C_STATS, I2C_STATS_STR )

/**
 * @enum    I2C_ERRORS
 * @brief   Enumeration of stats errors for this driver
 */
UTIL_MAKE_ENUM_AND_STRINGS( I2C_ERRORS, I2C_ERRORS, I2C_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  I2C_LOG
 * @brief   Structure to hold a log string
 */
typedef struct I2C_LOG
{
    char cLogEntry[ I2C_LOG_STRING_LENGTH ];

} I2C_LOG;

/**
 * @struct  I2C_PROFILE
 * @brief   Structure to hold the instance, timer & mutex pointers
 */
typedef struct I2C_PROFILE
{
    XIicPs  xIicInstance;

    void    *pvTimerHandle;
    int     iAbortBusWait;
    void    *pvOsalMutexHdl;

    I2C_LOG xCircularLog[ I2C_LOG_DEPTH ];
    int     iLogIndex;
    int     iI2cEnabled;

} I2C_PROFILE;

/**
 * @struct  I2C_PRIVATE_DATA
 * @brief   Structure to hold ths driver's private data
 */
typedef struct I2C_PRIVATE_DATA
{
    uint32_t     ulUpperFirewall;

    int          iInitialised;

    I2C_PROFILE  xIicProfile[ I2C_NUM_INSTANCES ];

    uint16_t     usBusIdleWaitMs;
    I2C_CFG_TYPE pxI2cCfg[ I2C_NUM_INSTANCES ];

    uint32_t     pulStatCounters[ I2C_STATS_MAX ];
    uint32_t     pulErrorCounters[ I2C_ERRORS_MAX ];

    uint32_t     ulLowerFirewall;

} I2C_PRIVATE_DATA;


/******************************************************************************/
/* Local Variables                                                            */
/******************************************************************************/

static I2C_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                                                            /* ulUpperFirewall */
    FALSE,                                                                     /* iInitialised */
    { { { {
              0
          } } } },                                                             /* xIicProfile */
    0,                                                                         /* usBusIdleWaitMs */
    { {
          0
      } },                                                                     /* *pxI2cCfg */
    {
        0
    },                                                                         /* pulStatCounters */
    {
        0
    },                                                                         /* pulErrorCounters */
    LOWER_FIREWALL                                                             /* ulLowerFirewall */
};
static I2C_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Private Function declarations                                              */
/******************************************************************************/

/**
 * @brief   Debug function to log transactions to a circular log
 *
 * @param   ucReadWrite         a read or a write
 * @param   ucDeviceId          the device id
 * @param   ucAddr              is the address of the slave we are receiving from
 * @param   pucDataBuff         is the pointer to the receive buffer
 * @param   ulLength            is the number of bytes to be received
 *
 * @return  N/A
 */
static void vLogI2cTransaction( uint8_t ucReadWrite,
                                uint8_t ucDeviceId,
                                uint8_t ucAddr,
                                uint8_t *pucDataBuff,
                                uint32_t ulLength );

/**
 * @brief   Debug function to dump out transactions
 *
 * @param   ucReadWrite         a read or a write
 * @param   ucDeviceId          the device id
 * @param   ucAddr              is the address of the slave we are receiving from
 * @param   pucDataBuff         is the pointer to the receive buffer
 * @param   ulLength            is the number of bytes to be received
 *
 * @return  N/A
 */
#ifdef I2C_DEBUG_DATA_LOG_ENABLE
static void vDumpI2cTransaction( uint8_t ucReadWrite,
                                 uint8_t ucDeviceId,
                                 uint8_t ucAddr,
                                 uint8_t *pucDataBuff,
                                 uint32_t ulLength );
#endif

/**
 * @brief   Callback invoked whenever the bus idle has timeout out
 *
 * @param   pvTimerHandle       Pointer to OS Timer Handle.
 *
 * @return  N/A
 */
static void vTimerBusIdleTimeoutCb( void *pvTimerHandle );

/**
 * @brief  Wait until bus is idle before starting another transfer
 *
 * @param   ucDeviceId          the device id
 * *
 * @return  OK                  Bus idle within specified time
 *          ERROR               Timed out waiting for bus to be idle
 */
static int iWaitForBusIdle( uint8_t ucDeviceId );


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/**
 * @brief   Re-initialise the I2C driver.
 */
int iI2C_ReInit( uint8_t ucDeviceId )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( I2C_NUM_INSTANCES > ucDeviceId ) )
    {
        int iI2cStatus = XST_FAILURE;

        I2C_PROFILE *pxIicProfile  = &( pxThis->xIicProfile[ ucDeviceId ] );
        XIicPs      *pxIicInstance = &( pxThis->xIicProfile[ ucDeviceId ].xIicInstance );

        /*
         * Initial clk value set and used to test if Fscl input is out of range
         */
        XIicPs_Config xEngineCfg =
        {
            .DeviceId     = pxThis->pxI2cCfg[ ucDeviceId ].ucDeviceId,
            .BaseAddress  = pxThis->pxI2cCfg[ ucDeviceId ].ullBaseAddress,
            .InputClockHz = HAL_I2C_DEFAULT_SCLK_RATE
        };

        pxIicInstance->IsReady = TRUE;
        iI2cStatus             = XIicPs_CfgInitialize( pxIicInstance,
                                                       &xEngineCfg,
                                                       pxThis->pxI2cCfg[ ucDeviceId ].ullBaseAddress );

        if( XST_SUCCESS == iI2cStatus )
        {
            iI2cStatus = XIicPs_SetSClk( pxIicInstance, pxThis->pxI2cCfg[ ucDeviceId ].ulInputClockHz );
            if( XST_SUCCESS == iI2cStatus )
            {
                iStatus                   = OK;
                pxIicProfile->iI2cEnabled = TRUE;
            }
            else
            {
                PLL_ERR( I2C_NAME, "Error XIicPs_SetSClk() failed: %d\r\n", iI2cStatus );
                INC_ERROR_COUNTER( I2C_ERRORS_XIIC_PS_SET_CLK_FAILED )
            }
        }
        else
        {
            PLL_ERR( I2C_NAME, "Error XIicPs_CfgInitialize() failed: %d\r\n", iI2cStatus );
            INC_ERROR_COUNTER( I2C_ERRORS_XIIC_PS_CONFIG_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( I2C_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Initializes the I2C driver.
 */
int iI2C_Init( I2C_CFG_TYPE *pxI2cCfg, uint16_t usBusIdleWaitMs )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) &&
        ( NULL != pxI2cCfg ) )
    {
        int iI2cStatus = XST_FAILURE;
        int i          = 0;

        /* Store the init values */
        pvOSAL_MemCpy( pxThis->pxI2cCfg, pxI2cCfg, ( sizeof( pxThis->pxI2cCfg ) ) );

        for( i = 0; i < I2C_NUM_INSTANCES; i++ )
        {
            pxThis->xIicProfile[ i ].iLogIndex   = 0;
            pxThis->xIicProfile[ i ].iI2cEnabled = TRUE;
            /* Revert to error at start of loop */
            iStatus = ERROR;

            I2C_PROFILE *pxIicProfile  = &( pxThis->xIicProfile[ i ] );
            XIicPs      *pxIicInstance = &( pxThis->xIicProfile[ i ].xIicInstance );

            if( TRUE == pxI2cCfg[ i ].ucHwResetDuringInit )
            {
                /* Toggle the reset line for the HW devices connected to this I2C Bus
                   This is a LPD_MIO output register */
                uint32_t ulRegisterValue    = 0;
                uint32_t ulNewRegisterValue = 0;

                /* Read the current value of the register */
                ulRegisterValue    = HAL_IO_READ32( pxI2cCfg[ i ].ulHwResetAddress );
                ulNewRegisterValue = ulRegisterValue & ~( pxI2cCfg[ i ].ulHwResetMask );

                /* Set the output bit of the register low */
                HAL_IO_WRITE32_NO_FLUSH( ulNewRegisterValue,  pxI2cCfg[ i ].ulHwResetAddress );
                iOSAL_Task_SleepMs( I2C_RESET_TIMEOUT_MS );

                /* Set the output bit of the register high again */
                HAL_IO_WRITE32_NO_FLUSH( ulRegisterValue, pxI2cCfg[ i ].ulHwResetAddress );
                iOSAL_Task_SleepMs( I2C_RESET_TIMEOUT_MS );
            }

            /*
             * Writing to the reset register on the QSFP bus causes issues if there are no
             * QSFPs present whereby the device is placed in a broken state after performing
             * a hot reset from the host - this can only be recovered with a PDU power cycle.
             */
            if( TRUE == pxI2cCfg[ i ].ucResetDuringInit )
            {
                /* Toggle the I2C resets */
                XIicPs_WriteReg( HAL_I2C_SW_RESET_BASEADDR, pxThis->pxI2cCfg[ i ].ulSwResetOffset, 1 );
                iOSAL_Task_SleepMs( I2C_RESET_TIMEOUT_MS );
                XIicPs_WriteReg( HAL_I2C_SW_RESET_BASEADDR, pxThis->pxI2cCfg[ i ].ulSwResetOffset, 0 );
                iOSAL_Task_SleepMs( I2C_RESET_TIMEOUT_MS );
            }

            /*
             * Initial clk value set and used to test if Fscl input is out of range
             */
            XIicPs_Config xEngineCfg =
            {
                .DeviceId     = pxI2cCfg[ i ].ucDeviceId,
                .BaseAddress  = pxI2cCfg[ i ].ullBaseAddress,
                .InputClockHz = HAL_I2C_DEFAULT_SCLK_RATE
            };

            pxIicInstance->IsReady = TRUE;
            iI2cStatus             = XIicPs_CfgInitialize( pxIicInstance,
                                                           &xEngineCfg,
                                                           pxI2cCfg[ i ].ullBaseAddress );

            if( XST_SUCCESS == iI2cStatus )
            {
                iI2cStatus = XIicPs_SetSClk( pxIicInstance, pxI2cCfg[ i ].ulInputClockHz );
                if( XST_SUCCESS == iI2cStatus )
                {
                    PLL_LOG( I2C_NAME,
                             "Device Configured: %d 0x%llx %d\r\n",
                             pxI2cCfg[ i ].ucDeviceId,
                             pxI2cCfg[ i ].ullBaseAddress,
                             pxI2cCfg[ i ].ulInputClockHz );
                    iStatus = OK;
                }
                else
                {
                    PLL_ERR( I2C_NAME, "Error XIicPs_SetSClk() failed: %d\r\n", iI2cStatus );
                    INC_ERROR_COUNTER( I2C_ERRORS_XIIC_PS_SET_CLK_FAILED )
                }
            }
            else
            {
                PLL_ERR( I2C_NAME, "Error XIicPs_CfgInitialize() failed: %d\r\n", iI2cStatus );
                INC_ERROR_COUNTER( I2C_ERRORS_XIIC_PS_CONFIG_FAILED )
            }


            if( OK == iStatus )
            {
                if( OSAL_ERRORS_NONE != iOSAL_Timer_Create( &( pxIicProfile->pvTimerHandle ),
                                                            OSAL_TIMER_CONFIG_ONE_SHOT,
                                                            vTimerBusIdleTimeoutCb,
                                                            "I2C_Bus_Idle" ) )
                {
                    PLL_ERR( I2C_NAME, "Error XIicPs_CfgInitialize() failed: %d\r\n", iI2cStatus );
                    INC_ERROR_COUNTER( I2C_ERRORS_TIMER_CREATE_FAILED )
                    iStatus = ERROR;
                }
                else
                {
                    pxThis->usBusIdleWaitMs = usBusIdleWaitMs;
                    INC_STAT_COUNTER( I2C_STATS_CREATE_TIMER )
                }
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &( pxIicProfile->pvOsalMutexHdl ),
                                                        "i2c mutex" ) )
            {
                PLL_ERR( I2C_NAME, "Error initialising mutex\r\n" );
                INC_ERROR_COUNTER( I2C_ERRORS_MUTEX_CREATE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( I2C_STATS_CREATE_MUTEX )
            }

            if( OK == iStatus )
            {
                pxThis->iInitialised = TRUE;
                INC_STAT_COUNTER( I2C_STATS_INIT_COMPLETED )
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( I2C_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   This function sends data from the I2C device into a specified buffer.
 */
int iI2C_Send( uint8_t ucDeviceId,
               uint8_t ucAddr,
               uint8_t *pucDataBuff,
               uint32_t ulLength )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucDataBuff ) &&
        ( ucDeviceId < I2C_NUM_INSTANCES ) )
    {
        I2C_PROFILE *pxIicProfile      = &( pxThis->xIicProfile[ ucDeviceId ] );
        XIicPs      *pxIicInstance     = &( pxThis->xIicProfile[ ucDeviceId ].xIicInstance );
        int         iI2cStatus         = XST_FAILURE;
        int         iWaitBusIdleStatus = ERROR;
        int         iReInitStatus      = OK;
        uint8_t     ucTryCount         = 0;

        while( ( ( XST_SUCCESS != iI2cStatus ) ||
                 ( OK != iWaitBusIdleStatus ) ||
                 ( OK != iReInitStatus ) ) &&
               ( ucTryCount < pxThis->pxI2cCfg[ ucDeviceId ].ucReTryCount ) )
        {
            if( TRUE == pxIicProfile->iI2cEnabled )
            {
                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxIicProfile->pvOsalMutexHdl,
                                                          I2C_WAIT_TIMEOUT_MS ) )
                {
                    iI2cStatus = XST_FAILURE;
                    INC_STAT_COUNTER( I2C_STATS_TAKE_MUTEX )

                    vLogI2cTransaction( I2C_DEBUG_DATA_WRITE,
                                        ucDeviceId,
                                        ucAddr,
                                        pucDataBuff,
                                        ulLength );

    #ifdef I2C_DEBUG_DATA_LOG_ENABLE
                    vDumpI2cTransaction( I2C_DEBUG_DATA_WRITE,
                                         ucDeviceId,
                                         ucAddr,
                                         pucDataBuff,
                                         ulLength );
    #endif

                    /*
                     * Wait until bus is idle to start another transfer.
                     */
                    iWaitBusIdleStatus = iWaitForBusIdle( ucDeviceId );

                    if( OK == iWaitBusIdleStatus )
                    {
                        iI2cStatus = XIicPs_MasterSendPolled( pxIicInstance,
                                                              pucDataBuff,
                                                              ulLength,
                                                              ucAddr );

                        if( XST_SUCCESS == iI2cStatus )
                        {
                            iStatus = OK;
                            INC_STAT_COUNTER( I2C_STATS_SEND_COMPLETED )
                        }
                        else
                        {
                            I2C_PROFILE *pxProfile = &pxThis->xIicProfile[ ucDeviceId ];
                            pxProfile->iI2cEnabled = FALSE;
                            PLL_ERR( I2C_NAME, "Error XIicPs_MasterSendPolled() failed: %d\r\n", iI2cStatus );
                            INC_ERROR_COUNTER( I2C_ERRORS_XIIC_PS_MASTER_SEND_POLLED_FAILED )

                            /* Attempt to recover the i2c if it fails */
                            iReInitStatus = iI2C_ReInit( ucDeviceId );
                            if( OK ==  iReInitStatus )
                            {
                                INC_STAT_COUNTER( I2C_STATS_REINIT_SUCCESSFUL )
                            }
                            else
                            {
                                INC_ERROR_COUNTER( I2C_ERRORS_REINIT_FAILED )
                            }
                        }
                    }
                    else
                    {
                        /* Attempt to recover the i2c if bus is busy */
                        iReInitStatus = iI2C_ReInit( ucDeviceId );
                        if( OK ==  iReInitStatus )
                        {
                            INC_STAT_COUNTER( I2C_STATS_REINIT_SUCCESSFUL )
                        }
                        else
                        {
                            INC_ERROR_COUNTER( I2C_ERRORS_REINIT_FAILED )
                        }

                        INC_ERROR_COUNTER( I2C_ERRORS_WAIT_FOR_BUS_IDLE_FAILED )
                    }

                    if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxIicProfile->pvOsalMutexHdl ) )
                    {
                        INC_ERROR_COUNTER( I2C_ERRORS_MUTEX_RELEASE_FAILED )
                        iStatus = ERROR;
                    }
                    else
                    {
                        INC_STAT_COUNTER( I2C_STATS_RELEASE_MUTEX )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER( I2C_ERRORS_MUTEX_TAKE_FAILED )
                }
            }
            ucTryCount++;
        }
    }
    else
    {
        INC_ERROR_COUNTER( I2C_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   This function reads data from the I2C device into a specified buffer.
 */
int iI2C_Recv( uint8_t ucDeviceId,
               uint8_t ucAddr,
               uint8_t *pucDataBuff,
               uint32_t ulLength )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucDataBuff ) &&
        ( ucDeviceId < I2C_NUM_INSTANCES ) )
    {
        I2C_PROFILE *pxIicProfile      = &( pxThis->xIicProfile[ ucDeviceId ] );
        XIicPs      *pxIicInstance     = &( pxThis->xIicProfile[ ucDeviceId ].xIicInstance );
        int         iI2cStatus         = XST_FAILURE;
        int         iWaitBusIdleStatus = ERROR;
        int         iReInitStatus      = OK;
        uint8_t     ucTryCount         = 0;

        while( ( ( XST_SUCCESS != iI2cStatus ) ||
                 ( OK != iWaitBusIdleStatus ) ||
                 ( OK != iReInitStatus ) ) &&
               ( ucTryCount < pxThis->pxI2cCfg[ ucDeviceId ].ucReTryCount ) )
        {
            if( TRUE == pxIicProfile->iI2cEnabled )
            {
                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxIicProfile->pvOsalMutexHdl,
                                                          I2C_WAIT_TIMEOUT_MS ) )
                {
                    iI2cStatus = XST_FAILURE;
                    INC_STAT_COUNTER( I2C_STATS_TAKE_MUTEX )

                    /*
                     * Wait until bus is idle to start another transfer.
                     */
                    iWaitBusIdleStatus = iWaitForBusIdle( ucDeviceId );

                    if( OK == iWaitBusIdleStatus )
                    {
                        iI2cStatus = XIicPs_MasterRecvPolled( pxIicInstance,
                                                              pucDataBuff,
                                                              ulLength,
                                                              ucAddr );
                        if( XST_SUCCESS == iI2cStatus )
                        {
                            /*
                             * Receive Data.
                             */
                            vLogI2cTransaction( I2C_DEBUG_DATA_WRITE,
                                                ucDeviceId,
                                                ucAddr,
                                                pucDataBuff,
                                                ulLength );

    #ifdef I2C_DEBUG_DATA_LOG_ENABLE
                            vDumpI2cTransaction( I2C_DEBUG_DATA_READ,
                                                 ucDeviceId,
                                                 ucAddr,
                                                 pucDataBuff,
                                                 ulLength );
    #endif

                            INC_STAT_COUNTER( I2C_STATS_RECEIVE_COMPLETED )
                            iStatus = OK;
                        }
                        else
                        {
                            I2C_PROFILE *pxProfile = &pxThis->xIicProfile[ ucDeviceId ];
                            pxProfile->iI2cEnabled = FALSE;
                            PLL_ERR( I2C_NAME, "Error XIicPs_MasterRecvPolled( ) failed: %d\r\n", iI2cStatus );
                            INC_ERROR_COUNTER( I2C_ERRORS_XIIC_PS_MASTER_RECEIVE_POLLED_FAILED )

                            /* Attempt to recover the i2c if it fails */
                            iReInitStatus = iI2C_ReInit( ucDeviceId );
                            if( OK == iReInitStatus )
                            {
                                INC_STAT_COUNTER( I2C_STATS_REINIT_SUCCESSFUL )
                            }
                            else
                            {
                                INC_ERROR_COUNTER( I2C_ERRORS_REINIT_FAILED )
                            }
                        }
                    }
                    else
                    {
                        /* Attempt to recover the i2c if bus is busy */
                        iReInitStatus = iI2C_ReInit( ucDeviceId );
                        if( OK ==  iReInitStatus )
                        {
                            INC_STAT_COUNTER( I2C_STATS_REINIT_SUCCESSFUL )
                        }
                        else
                        {
                            INC_ERROR_COUNTER( I2C_ERRORS_REINIT_FAILED )
                        }

                        INC_ERROR_COUNTER( I2C_ERRORS_WAIT_FOR_BUS_IDLE_FAILED )
                    }

                    if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxIicProfile->pvOsalMutexHdl ) )
                    {
                        INC_ERROR_COUNTER( I2C_ERRORS_MUTEX_RELEASE_FAILED )
                        iStatus = ERROR;
                    }
                    else
                    {
                        INC_STAT_COUNTER( I2C_STATS_RELEASE_MUTEX )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER( I2C_ERRORS_MUTEX_TAKE_FAILED )
                }
                ucTryCount++;
            }

        }
    }
    else
    {
        INC_ERROR_COUNTER( I2C_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   This function sends data from the I2C device and waits for a response coming back.
 */
int iI2C_SendRecv( uint8_t ucDeviceId,
                   uint8_t ucWriteReadAddr,
                   uint8_t *pucWriteDataBuff,
                   uint32_t ulWriteLength,
                   uint8_t *pucReadDataBuff,
                   uint32_t ulReadLength )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucWriteDataBuff ) &&
        ( NULL != pucReadDataBuff ) &&
        ( ucDeviceId < I2C_NUM_INSTANCES ) )
    {
        I2C_PROFILE *pxIicProfile      = &( pxThis->xIicProfile[ ucDeviceId ] );
        XIicPs      *pxIicInstance     = &( pxThis->xIicProfile[ ucDeviceId ].xIicInstance );
        int         iI2cStatus         = XST_FAILURE;
        int         iWaitBusIdleStatus = ERROR;
        int         iReInitStatus      = OK;
        uint8_t     ucTryCount         = 0;

        while( ( ( XST_SUCCESS != iI2cStatus ) ||
                 ( OK != iWaitBusIdleStatus ) ||
                 ( OK != iReInitStatus ) ) &&
               ( ucTryCount < pxThis->pxI2cCfg[ ucDeviceId ].ucReTryCount ) )
        {
            if( TRUE == pxIicProfile->iI2cEnabled )
            {
                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxIicProfile->pvOsalMutexHdl, I2C_WAIT_TIMEOUT_MS ) )
                {
                    INC_STAT_COUNTER( I2C_STATS_TAKE_MUTEX )
                    /*
                     * Enable repeated start option.
                     * This call will give an indication to the driver.
                     * The hold bit is actually set before beginning the following transfer
                     */
                    iI2cStatus = XIicPs_SetOptions( pxIicInstance, XIICPS_REP_START_OPTION );

                    if( XST_SUCCESS == iI2cStatus )
                    {
                        /*
                         * Send the Data.
                         */
                        vLogI2cTransaction( I2C_DEBUG_DATA_WRITE,
                                            ucDeviceId,
                                            ucWriteReadAddr,
                                            pucWriteDataBuff,
                                            ulWriteLength );

    #ifdef I2C_DEBUG_DATA_LOG_ENABLE
                        vDumpI2cTransaction( I2C_DEBUG_DATA_WRITE,
                                             ucDeviceId,
                                             ucWriteReadAddr,
                                             pucWriteDataBuff,
                                             ulWriteLength );
    #endif

                        /*
                         * Wait until bus is idle to start another transfer.
                         */
                        iWaitBusIdleStatus = iWaitForBusIdle( ucDeviceId );

                        if( OK == iWaitBusIdleStatus )
                        {
                            iI2cStatus = XIicPs_MasterSendPolled( pxIicInstance,
                                                                  pucWriteDataBuff,
                                                                  ulWriteLength,
                                                                  ucWriteReadAddr );

                            if( XST_SUCCESS == iI2cStatus )
                            {
                                /*
                                 * Disable repeated start option.
                                 * This call will give an indication to the driver.
                                 * The hold bit is actually reset when the following transfer ends.
                                 */
                                INC_STAT_COUNTER( I2C_STATS_SEND_COMPLETED )

                                iI2cStatus = XIicPs_ClearOptions( pxIicInstance, XIICPS_REP_START_OPTION );

                                if( XST_SUCCESS == iI2cStatus )
                                {
                                    /*
                                     * Receive the Data.
                                     */
                                    iI2cStatus = XIicPs_MasterRecvPolled( pxIicInstance,
                                                                          pucReadDataBuff,
                                                                          ulReadLength,
                                                                          ucWriteReadAddr );
                                    if( XST_SUCCESS == iI2cStatus )
                                    {
                                        /*
                                         * Wait until bus is idle to start another transfer.
                                         */
                                        iWaitBusIdleStatus = iWaitForBusIdle( ucDeviceId );

                                        if( OK == iWaitBusIdleStatus )
                                        {
                                            vLogI2cTransaction( I2C_DEBUG_DATA_READ,
                                                                ucDeviceId,
                                                                ucWriteReadAddr,
                                                                pucReadDataBuff,
                                                                ulReadLength );
        #ifdef I2C_DEBUG_DATA_LOG_ENABLE
                                            vDumpI2cTransaction( I2C_DEBUG_DATA_READ,
                                                                 ucDeviceId,
                                                                 ucWriteReadAddr,
                                                                 pucReadDataBuff,
                                                                 ulReadLength );
        #endif
                                            INC_STAT_COUNTER( I2C_STATS_RECEIVE_COMPLETED )
                                            iStatus = OK;
                                        }
                                        else
                                        {
                                            /* Attempt to recover the i2c if bus is busy */
                                            iReInitStatus = iI2C_ReInit( ucDeviceId );
                                            if( OK ==  iReInitStatus )
                                            {
                                                INC_STAT_COUNTER( I2C_STATS_REINIT_SUCCESSFUL )
                                            }
                                            else
                                            {
                                                INC_ERROR_COUNTER( I2C_ERRORS_REINIT_FAILED )
                                            }

                                            INC_ERROR_COUNTER( I2C_ERRORS_WAIT_FOR_BUS_IDLE_FAILED )
                                        }
                                    }
                                    else
                                    {
                                        I2C_PROFILE *pxProfile = &pxThis->xIicProfile[ ucDeviceId ];
                                        pxProfile->iI2cEnabled = FALSE;
                                        PLL_ERR( I2C_NAME,
                                                 "Error XIicPs_MasterRecvPolled() failed: %d\r\n",
                                                 iI2cStatus );
                                        INC_ERROR_COUNTER( I2C_ERRORS_XIIC_PS_MASTER_RECEIVE_POLLED_FAILED )

                                        /* Attempt to recover the i2c if it fails */
                                        iReInitStatus = iI2C_ReInit( ucDeviceId );
                                        if( OK == iReInitStatus )
                                        {
                                            INC_STAT_COUNTER( I2C_STATS_REINIT_SUCCESSFUL )
                                        }
                                        else
                                        {
                                            INC_ERROR_COUNTER( I2C_ERRORS_REINIT_FAILED )
                                        }
                                    }
                                }
                                else
                                {
                                    PLL_ERR( I2C_NAME, "Error XIicPs_ClearOptions() failed: %d\r\n", iI2cStatus );
                                    INC_ERROR_COUNTER( I2C_ERRORS_XIIC_PS_CLEAR_OPTIONS_FAILED )
                                }
                            }
                            else
                            {
                                I2C_PROFILE *pxProfile = &pxThis->xIicProfile[ ucDeviceId ];
                                pxProfile->iI2cEnabled = FALSE;
                                PLL_ERR( I2C_NAME, "Error XIicPs_MasterSendPolled() failed: %d\r\n", iI2cStatus );
                                INC_ERROR_COUNTER( I2C_ERRORS_XIIC_PS_MASTER_SEND_POLLED_FAILED )

                                /* Attempt to recover the i2c if it fails */
                                iReInitStatus = iI2C_ReInit( ucDeviceId );
                                if( OK == iReInitStatus )
                                {
                                    INC_STAT_COUNTER( I2C_STATS_REINIT_SUCCESSFUL )
                                }
                                else
                                {
                                    INC_ERROR_COUNTER( I2C_ERRORS_REINIT_FAILED )
                                }
                            }
                        }
                        else
                        {
                            /* Attempt to recover the i2c if bus is busy */
                            iReInitStatus = iI2C_ReInit( ucDeviceId );
                            if( OK ==  iReInitStatus )
                            {
                                INC_STAT_COUNTER( I2C_STATS_REINIT_SUCCESSFUL )
                            }
                            else
                            {
                                INC_ERROR_COUNTER( I2C_ERRORS_REINIT_FAILED )
                            }

                            INC_ERROR_COUNTER( I2C_ERRORS_WAIT_FOR_BUS_IDLE_FAILED )
                        }
                    }
                    else
                    {
                        PLL_ERR( I2C_NAME, "Error XIicPs_ClearOptions() failed: %d\r\n", iI2cStatus );
                        INC_ERROR_COUNTER( I2C_ERRORS_XIIC_PS_SET_OPTIONS_FAILED )
                    }

                    if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxIicProfile->pvOsalMutexHdl ) )
                    {
                        INC_ERROR_COUNTER( I2C_ERRORS_MUTEX_RELEASE_FAILED )
                        iStatus = ERROR;
                    }
                    else
                    {
                        INC_STAT_COUNTER( I2C_STATS_RELEASE_MUTEX )
                    }
                }
                else
                {
                    INC_ERROR_COUNTER( I2C_ERRORS_MUTEX_TAKE_FAILED )
                }
            }
            ucTryCount++;
        }
    }
    else
    {
        INC_ERROR_COUNTER( I2C_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Print all the stats gathered by the driver
 */
int iI2C_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( I2C_NAME, "============================================================\n\r" );
        PLL_INF( I2C_NAME, "I2C Statistics:\n\r" );
        for( i = 0; i < I2C_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( I2C_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( I2C_NAME, "I2C Errors:\n\r" );
        for( i = 0; i < I2C_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( I2C_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( I2C_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Clear all the stats in the driver
 */
int iI2C_ClearStatistics( void )
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
        INC_ERROR_COUNTER( I2C_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Print the circular log
 */
int iI2C_PrintLog( int iDevice )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        int i = 0;

        I2C_PROFILE *pxProfile = &pxThis->xIicProfile[ iDevice ];
        for( i = 0; i < I2C_LOG_DEPTH; i++ )
        {
            if( i == ( pxProfile->iLogIndex - 1 ) )
            {
                PLL_INF( I2C_NAME, "%2d* %s", i, pxProfile->xCircularLog[ i ].cLogEntry );
            }
            else
            {
                PLL_INF( I2C_NAME, "%2d  %s", i, pxProfile->xCircularLog[ i ].cLogEntry );
            }
        }
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( I2C_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/******************************************************************************/
/* Private Function implementation                                            */
/******************************************************************************/

/**
 * @brief   Debug function to dump out I2C read or write buffer
 */
#ifdef I2C_DEBUG_DATA_LOG_ENABLE
static void vDumpI2cTransaction( uint8_t ucReadWrite,
                                 uint8_t ucDeviceId,
                                 uint8_t ucAddr,
                                 uint8_t *pucDataBuff,
                                 uint32_t ulLength )
{
    int  i = 0;
    char cTempBuff[ I2C_DEBUG_DATA_LOG_BUFF_MAX ] =
    {
        0
    };
    char    *pcTempBuff  = cTempBuff;
    uint8_t ucMaxStrBuff = I2C_DEBUG_DATA_LOG_BUFF_MAX / I2C_DEBUG_CHAR_PER_VALUE;

    if( ulLength > ucMaxStrBuff )
    {
        ulLength = ucMaxStrBuff;
        PLL_ERR( I2C_NAME, "Error: Limiting output to fit within buffer\r\n" );
    }

    if( ucReadWrite <= I2C_DEBUG_DATA_WRITE )
    {
        for( i = 0; i < ulLength; i++ )
        {
            sprintf( pcTempBuff, "0x%02x ", pucDataBuff[ i ] );
            pcTempBuff += I2C_DEBUG_CHAR_PER_VALUE;
        }
        cTempBuff[ strlen( cTempBuff ) - 1 ] = '\0';

        if( I2C_DEBUG_DATA_WRITE == ucReadWrite )
        {
            PLL_DBG( I2C_NAME, "[Write] Addr:0x%x Len:%d [%s]\r\n", ucAddr, ulLength, cTempBuff );
        }
        else
        {
            PLL_DBG( I2C_NAME, "[Read] Addr:0x%x Len:%d [%s]\r\n", ucAddr, ulLength, cTempBuff );
        }
    }
    else
    {
        PLL_ERR( I2C_NAME, "Error: Invalid transaction type" );
    }
}
#endif

/**
 * @brief   Debug function to log I2C read or write to a circular buffer
 */
static void vLogI2cTransaction( uint8_t ucReadWrite,
                                uint8_t ucDeviceId,
                                uint8_t ucAddr,
                                uint8_t *pucDataBuff,
                                uint32_t ulLength )
{
    int  i = 0;
    char cTempBuff[ I2C_DEBUG_DATA_LOG_BUFF_MAX ] =
    {
        0
    };
    char     *pcTempBuff     = cTempBuff;
    uint8_t  ucMaxStrBuff    = I2C_DEBUG_DATA_LOG_BUFF_MAX / I2C_DEBUG_CHAR_PER_VALUE;
    uint32_t ulIntrStatusReg = 0;

    I2C_PROFILE *pxProfile = &pxThis->xIicProfile[ ucDeviceId ];

    if( TRUE == pxProfile->iI2cEnabled )
    {
        char *pcLogEntry = pxProfile->xCircularLog [ pxProfile->iLogIndex ].cLogEntry;
        if( ulLength > ucMaxStrBuff )
        {
            ulLength = ucMaxStrBuff;
            snprintf( pcLogEntry, I2C_LOG_STRING_LENGTH, "Error: Limiting output to fit within buffer\r\n" );
        }

        ulIntrStatusReg = HAL_IO_READ32( pxProfile->xIicInstance.Config.BaseAddress + XIICPS_ISR_OFFSET );

        if( ucReadWrite <= I2C_DEBUG_DATA_WRITE )
        {
            for( i = 0; i < ulLength; i++ )
            {
                /* Note the last character will be NULL */
                sprintf( pcTempBuff, "0x%02x", pucDataBuff[ i ] );

                pcTempBuff += I2C_DEBUG_CHAR_PER_VALUE - 1;

                /* If this is not the last value, replace the NULL with a space */
                if( ( ulLength - 1 ) != i )
                {
                    *pcTempBuff = ' ';
                }

                pcTempBuff++;
            }

            if( I2C_DEBUG_DATA_WRITE == ucReadWrite )
            {
                snprintf( pcLogEntry,
                          I2C_LOG_STRING_LENGTH,
                          "[Write] Addr:0x%x Len:%d ISR:0x%04lx [%s]\r\n",
                          ucAddr,
                          ( int )ulLength,
                          ulIntrStatusReg,
                          cTempBuff );
            }
            else
            {
                snprintf( pcLogEntry,
                          I2C_LOG_STRING_LENGTH,
                          "[Read] Addr:0x%x Len:%d ISR:0x%04lx [%s]\r\n",
                          ucAddr,
                          ( int )ulLength,
                          ulIntrStatusReg,
                          cTempBuff );
            }
        }
        else
        {
            snprintf( pcLogEntry, I2C_LOG_STRING_LENGTH, "Error: Invalid transaction type\r\n" );
        }

        pxProfile->iLogIndex++;
        if( I2C_LOG_DEPTH == pxProfile->iLogIndex )
        {
            pxProfile->iLogIndex = 0;
        }
    }

}

/**
 * @brief   Callback invoked whenever the bus idle check has taken too long
 */
static void vTimerBusIdleTimeoutCb( void *pvTimerHandle )
{
    int i = 0;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pvTimerHandle ) )
    {
        for( i = 0; i < I2C_NUM_INSTANCES; i++ )
        {
            if( pxThis->xIicProfile[ i ].pvTimerHandle == pvTimerHandle )
            {
                pxThis->xIicProfile[ i ].iAbortBusWait = TRUE;
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( I2C_ERRORS_VALIDATION_FAILED )
    }
}

/**
 * @brief   Wait until bus is idle before starting another transfer
 */
static int iWaitForBusIdle( uint8_t ucDeviceId )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        I2C_PROFILE *pxIicProfile  = &( pxThis->xIicProfile[ ucDeviceId ] );
        XIicPs      *pxIicInstance = &( pxThis->xIicProfile[ ucDeviceId ].xIicInstance );

        /* Clear the flag before starting the timer */
        pxIicProfile->iAbortBusWait = FALSE;

        /* Start timer checking for bus idle timeout */
        if( OSAL_ERRORS_NONE != iOSAL_Timer_Start( pxIicProfile->pvTimerHandle, pxThis->usBusIdleWaitMs ) )
        {
            INC_ERROR_COUNTER( I2C_ERRORS_TIMER_START_FAILED )
        }
        else
        {
            while( XIicPs_BusIsBusy( pxIicInstance ) )
            {
                if( TRUE == pxIicProfile->iAbortBusWait )
                {
                    /* check for abort and break out of busy wait */
                    break;
                }
            }

            if( FALSE == pxIicProfile->iAbortBusWait )
            {
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( I2C_ERRORS_WAIT_FOR_BUS_IDLE_TIMED_OUT )
            }

            /* Stop timer */
            if( OSAL_ERRORS_NONE != iOSAL_Timer_Stop( pxIicProfile->pvTimerHandle ) )
            {
                INC_ERROR_COUNTER( I2C_ERRORS_TIMER_STOP_FAILED )
                iStatus = ERROR;
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( I2C_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}
