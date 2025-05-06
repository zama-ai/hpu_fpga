/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implementation of INA3221 sensor read
 * functions.
 *
 * @file ina3221.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "util.h"
#include "pll.h"

#include "ina3221.h"
#include "i2c.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL                      ( 0xBABECAFE )
#define LOWER_FIREWALL                      ( 0xDEADFACE )

#define INA3221_NAME                        "INA3221"

#define INA3221_CH1_NUMBER                  ( 0 )
#define INA3221_CH1_SHUNT_VOLTAGE           ( 0x01 )
#define INA3221_CH1_BUS_VOLTAGE             ( 0x02 )
#define INA3221_CH2_NUMBER                  ( 1 )
#define INA3221_CH2_SHUNT_VOLTAGE           ( 0x03 )
#define INA3221_CH2_BUS_VOLTAGE             ( 0x04 )
#define INA3221_CH3_NUMBER                  ( 2 )
#define INA3221_CH3_SHUNT_VOLTAGE           ( 0x05 )
#define INA3221_CH3_BUS_VOLTAGE             ( 0x06 )

#define INA3221_BUFFER_SIZE                 ( 8 )
#define INA3221_MSB_TO_HEX_BIT_SHIFT        ( 8 )
#define INA3221_VOLTAGE_BIT_SHIFT_MASK      ( 0x7 )
#define INA3221_VOLTAGE_BIT_SHIFT           ( 3 )
#define INA3221_VOLTAGE_SCALING_FACTOR      ( 0.00004 )
#define INA3221_VOLTAGE_SCALING_MULTIPLIER  ( 1000 )
#define INA3221_VOLTAGE_WRITE_LENGTH        ( 1 )
#define INA3221_VOLTAGE_READ_LENGTH         ( 2 )
#define INA3221_CURRENT_WRITE_LENGTH        ( 1 )
#define INA3221_CURRENT_READ_LENGTH         ( 2 )
#define INA3221_POWER_SCALING_FACTOR        ( 1000 )
#define INA3221_SHUNT_RESISTANCE_VALUE      ( 0.002 )
/* Multiply by this instead of dividing by INA3221_SHUNT_RESISTANCE_VALUE: 1/0.002 is 500 */
#define INA3221_1_OVER_SHUNT_RESISTANCE     ( 500 )

#define INA3221_STATS( DO )             \
    DO( INA3221_STATS_VOLTAGE_READ )    \
    DO( INA3221_STATS_CURRENT_READ )    \
    DO( INA3221_STATS_POWER_READ )      \
    DO( INA3221_STATS_MAX )

#define INA3221_ERRORS( DO )            \
    DO( INA3221_ERRORS_VOLTAGE_READ )   \
    DO( INA3221_ERRORS_CURRENT_READ )   \
    DO( INA3221_ERRORS_POWER_READ )     \
    DO( INA3221_ERRORS_VALIDATION )     \
    DO( INA3221_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )         PLL_INF( INA3221_NAME, "%50s . . . . %d\r\n",    \
                                                 INA3221_STATS_STR[ x ],                 \
                                                 pxThis->ulStats[ x ] )
#define PRINT_ERROR_COUNTER( x )        PLL_INF( INA3221_NAME, "%50s . . . . %d\r\n",    \
                                                 INA3221_ERRORS_STR[ x ],                \
                                                 pxThis->ulErrors[ x ] )

#define INC_STAT_COUNTER( x )           { if( x < INA3221_STATS_MAX )pxThis->ulStats[ x ]++; }
#define INC_ERROR_COUNTER( x )          { if( x < INA3221_ERRORS_MAX )pxThis->ulErrors[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    INA3221_STATS
 * @brief   Enumeration of stats counters for this library
 */
UTIL_MAKE_ENUM_AND_STRINGS( INA3221_STATS, INA3221_STATS, INA3221_STATS_STR )

/**
 * @enum    INA3221_ERRORS
 * @brief   Enumeration of stats errors for this library
 */
UTIL_MAKE_ENUM_AND_STRINGS( INA3221_ERRORS, INA3221_ERRORS, INA3221_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  INA3221_PRIVATE_DATA
 * @brief   Private driver data
 */
typedef struct INA3221_PRIVATE_DATA
{
    uint32_t    ulUpperFirewall;

    uint32_t    ulStats[ INA3221_STATS_MAX ];
    uint32_t    ulErrors[ INA3221_ERRORS_MAX ];

    uint32_t    ulLowerFirewall;

} INA3221_PRIVATE_DATA;


/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

static INA3221_PRIVATE_DATA xPrivateData =
{
    UPPER_FIREWALL,     /* ulUpperFirewall */
    { 0 },              /* ulStats */
    { 0 },              /* ulErrors */
    LOWER_FIREWALL      /* ulLowerFirewall */
};

static INA3221_PRIVATE_DATA *pxThis = &xPrivateData;


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/**
 * @brief   Read voltage using INA3221 sensor
 */
int iINA3221_ReadVoltage( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucChannelNum, float *pfVoltageInMV )
{
    int      iStatus                             = ERROR;
    uint8_t  pucWriteBuf[ INA3221_BUFFER_SIZE ]  = { 0 };
    uint8_t  pucReadBuf[ INA3221_BUFFER_SIZE ]   = { 0 };
    uint16_t usReadData                          = 0;

    if( NULL != pfVoltageInMV )
    {
        switch( ucChannelNum )
        {
        case INA3221_CH1_NUMBER:
            pucWriteBuf[ 0 ] = INA3221_CH1_BUS_VOLTAGE;
            iStatus = OK;
            break;
        case INA3221_CH2_NUMBER:
            pucWriteBuf[ 0 ] = INA3221_CH2_BUS_VOLTAGE;
            iStatus = OK;
            break;
        case INA3221_CH3_NUMBER:
            pucWriteBuf[ 0 ] = INA3221_CH3_BUS_VOLTAGE;
            iStatus = OK;
            break;
        default:
            break;
        }

        if( OK == iStatus )
        {
            iStatus = iI2C_SendRecv( ucBusNum, ucSlaveAddr, ( uint8_t* ) pucWriteBuf, INA3221_VOLTAGE_WRITE_LENGTH, ( uint8_t* ) pucReadBuf, INA3221_VOLTAGE_READ_LENGTH );
        }

        if( OK == iStatus )
        {
            INC_STAT_COUNTER( INA3221_STATS_VOLTAGE_READ );

            pucReadBuf[ 1 ] = pucReadBuf[ 1 ] & ~INA3221_VOLTAGE_BIT_SHIFT_MASK;
            usReadData= ( ( uint16_t ) pucReadBuf[ 1 ] ) | ( ( uint16_t ) pucReadBuf[ 0 ] << INA3221_MSB_TO_HEX_BIT_SHIFT );
            *pfVoltageInMV = ( ( float ) usReadData );
        }
        else
        {
            INC_ERROR_COUNTER( INA3221_ERRORS_VOLTAGE_READ );
        }
    }
    else
    {
        INC_ERROR_COUNTER( INA3221_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Read current using INA3221 sensor
 */
int iINA3221_ReadCurrent( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucChannelNum, float *pfCurrentInmA )
{
    int      iStatus                             = ERROR;
    uint8_t  pucWriteBuf[ INA3221_BUFFER_SIZE ]  = { 0 };
    uint8_t  pucReadBuf[ INA3221_BUFFER_SIZE ]   = { 0 };
    uint16_t usReadData                          = 0;

    if( NULL != pfCurrentInmA )
    {
        switch( ucChannelNum )
        {
        case INA3221_CH1_NUMBER:
            pucWriteBuf[ 0 ] = INA3221_CH1_SHUNT_VOLTAGE;
            iStatus = OK;
            break;
        case INA3221_CH2_NUMBER:
            pucWriteBuf[ 0 ] = INA3221_CH2_SHUNT_VOLTAGE;
            iStatus = OK;
            break;
        case INA3221_CH3_NUMBER:
            pucWriteBuf[ 0 ] = INA3221_CH3_SHUNT_VOLTAGE;
            iStatus = OK;
            break;
        default:
            break;
        }

        if( OK == iStatus )
        {
            iStatus = iI2C_SendRecv( ucBusNum, ucSlaveAddr, ( uint8_t* ) pucWriteBuf, INA3221_CURRENT_WRITE_LENGTH, ( uint8_t* ) pucReadBuf, INA3221_CURRENT_READ_LENGTH );
        }

        if( OK == iStatus )
        {
            INC_STAT_COUNTER( INA3221_STATS_CURRENT_READ );

            pucReadBuf[ 1 ] = pucReadBuf[ 1 ] & ~INA3221_VOLTAGE_BIT_SHIFT_MASK;
            usReadData = ( ( uint16_t ) pucReadBuf[ 1 ] ) | ( ( uint16_t ) pucReadBuf[ 0 ] << INA3221_MSB_TO_HEX_BIT_SHIFT );

            float fShuntVolt = ( float ) ( usReadData >> INA3221_VOLTAGE_BIT_SHIFT );
            fShuntVolt *= ( float ) INA3221_VOLTAGE_SCALING_FACTOR;
            fShuntVolt *= INA3221_VOLTAGE_SCALING_MULTIPLIER;

            *pfCurrentInmA = fShuntVolt * INA3221_1_OVER_SHUNT_RESISTANCE ;
        }
        else
        {
            INC_ERROR_COUNTER( INA3221_ERRORS_CURRENT_READ );
        }
    }
    else
    {
        INC_ERROR_COUNTER( INA3221_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Calculate power using INA3221 voltage and current reads
 */
int iINA3221_ReadPower( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucChannelNum, float *pfPowerInmW )
{
    int   iStatus       = ERROR;
    float fCurrentInmA  = 0.0;
    float fVoltageInmV  = 0.0;

    if( NULL != pfPowerInmW )
    {
        if( OK == ( iStatus = iINA3221_ReadCurrent( ucBusNum, ucSlaveAddr, ucChannelNum, &fCurrentInmA ) ) )
        {
            if( OK == ( iStatus = iINA3221_ReadVoltage( ucBusNum, ucSlaveAddr, ucChannelNum, &fVoltageInmV ) ) )
            {
                *pfPowerInmW = ( float ) ( ( ( double ) fVoltageInmV * ( double ) fCurrentInmA ) / INA3221_POWER_SCALING_FACTOR );
            }
        }

        if( OK == iStatus )
        {
            INC_STAT_COUNTER( INA3221_STATS_POWER_READ );
        }
        else
        {
            INC_ERROR_COUNTER( INA3221_ERRORS_POWER_READ );
        }
    }
    else
    {
        INC_ERROR_COUNTER( INA3221_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iINA3221_PrintStatistics( void )
{
     int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( INA3221_NAME, "============================================================\n\r" );
        PLL_INF( INA3221_NAME, "INA3221 Statistics:\n\r" );
        for( i = 0; i < INA3221_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( INA3221_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( INA3221_NAME, "INA3221 Errors:\n\r" );
        for( i = 0; i < INA3221_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( INA3221_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( INA3221_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iINA3221_ClearStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        pvOSAL_MemSet( pxThis->ulStats, 0, sizeof( pxThis->ulStats ) );
        pvOSAL_MemSet( pxThis->ulErrors, 0, sizeof( pxThis->ulErrors ) );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( INA3221_ERRORS_VALIDATION )
    }

    return iStatus;
}
