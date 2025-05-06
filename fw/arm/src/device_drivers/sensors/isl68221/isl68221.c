/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implementation of ISL68221 sensor read
 * functions.
 *
 * @file isl68221.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "util.h"
#include "pll.h"

#include "isl68221.h"
#include "i2c.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL                          ( 0xBABECAFE )
#define LOWER_FIREWALL                          ( 0xDEADFACE )

#define ISL68221_NAME                           "ISL68221"

#define ISL68221_ERROR                          ( 1 )
#define ISL68221_BUFFER_SIZE                    ( 8 )
#define ISL68221_WRITE_SIZE                     ( 2 )
#define ISL68221_WRITE_LENGTH                   ( 1 )
#define ISL68221_READ_LENGTH                    ( 2 )
#define ISL68221_BIT_SHIFT                      ( 8 )

#define ISL68221_CURRENT_SCALING_FACTOR         ( 10 )

#define ISL68221_PAGE_REGISTER                  ( 0x00 )

#define ISL68221_SELECT_PAGE_RAIL_0             ( 0x00 )
#define ISL68221_SELECT_PAGE_RAIL_1             ( 0x01 )
#define ISL68221_SELECT_PAGE_RAIL_2             ( 0x02 )

#define ISL68221_OUTPUT_VOLTAGE_REGISTER        ( 0x8B )
#define ISL68221_OUTPUT_CURRENT_REGISTER        ( 0x8C )
#define ISL68221_READ_TEMP_HOTTEST_POWER_STAGE  ( 0x8D )
#define ISL68221_READ_TEMP_CONTROLLER           ( 0x8E )
#define ISL68221_READ_TEMP_PIN                  ( 0x8F )

#define ISL68221_STATS( DO )                  \
    DO( ISL68221_STATS_REGISTER_WRITE )       \
    DO( ISL68221_STATS_REGISTER_READ  )       \
    DO( ISL68221_STATS_VOLTAGE_READ )         \
    DO( ISL68221_STATS_CURRENT_READ )         \
    DO( ISL68221_STATS_TEMPERATURE_READ )     \
    DO( ISL68221_STATS_MAX )

#define ISL68221_ERRORS( DO )                 \
    DO( ISL68221_ERRORS_REGISTER_WRITE )      \
    DO( ISL68221_ERRORS_REGISTER_READ  )      \
    DO( ISL68221_ERRORS_VOLTAGE_READ )        \
    DO( ISL68221_ERRORS_CURRENT_READ )        \
    DO( ISL68221_ERRORS_TEMPERATURE_READ )    \
    DO( ISL68221_ERRORS_VALIDATION )          \
    DO( ISL68221_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )         PLL_INF( ISL68221_NAME, "%50s . . . . %d\r\n",    \
                                                 ISL68221_STATS_STR[ x ],                 \
                                                 pxThis->ulStats[ x ] )
#define PRINT_ERROR_COUNTER( x )        PLL_INF( ISL68221_NAME, "%50s . . . . %d\r\n",    \
                                                 ISL68221_ERRORS_STR[ x ],                \
                                                 pxThis->ulErrors[ x ] )

#define INC_STAT_COUNTER( x )           { if( x < ISL68221_STATS_MAX )pxThis->ulStats[ x ]++; }
#define INC_ERROR_COUNTER( x )          { if( x < ISL68221_ERRORS_MAX )pxThis->ulErrors[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    ISL68221_STATS
 * @brief   Enumeration of stats counters for this library
 */
UTIL_MAKE_ENUM_AND_STRINGS( ISL68221_STATS, ISL68221_STATS, ISL68221_STATS_STR )

/**
 * @enum    ISL68221_ERRORS
 * @brief   Enumeration of stats errors for this library
 */
UTIL_MAKE_ENUM_AND_STRINGS( ISL68221_ERRORS, ISL68221_ERRORS, ISL68221_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  ISL68221_PRIVATE_DATA
 * @brief   Private driver data
 */
typedef struct ISL68221_PRIVATE_DATA
{
    uint32_t    ulUpperFirewall;

    uint32_t    ulStats[ ISL68221_STATS_MAX ];
    uint32_t    ulErrors[ ISL68221_ERRORS_MAX ];

    uint32_t    ulLowerFirewall;

} ISL68221_PRIVATE_DATA;


/******************************************************************************/
/* Private Function declaratations                                            */
/******************************************************************************/

/**
 * @brief   Send data to ISL68221 sensor
 *
 * @param   ucI2cNum            I2C number
 * @param   ucSlaveAddr         I2C slave address
 * @param   ucRegisterAddress   Register's address
 * @param   pucRegisterContent  Pointer to register's content
 *
 * @return  OK                  Register written successfully
 *          ERROR               Register not written successfully
 *
 */
static int iWriteRegister( uint8_t ucI2cNum, uint8_t ucSlaveAddr, uint8_t ucRegisterAddress, uint8_t *pucRegisterContent );

/**
 * @brief   Read data from ISL68221 sensor
 *
 * @param   ucI2cNum            I2C number
 * @param   ucSlaveAddr         I2C slave address
 * @param   ucRegisterAddress   Register's address
 * @param   pucRegisterContent  Pointer to register's content
 *
 * @return  OK                  Register read successfully
 *          ERROR               Register not read successfully
 *
 */
static int iReadRegister( uint8_t ucI2cNum, uint8_t ucSlaveAddr, uint8_t ucRegisterAddress, uint8_t *pucRegisterContent );


/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

static ISL68221_PRIVATE_DATA xPrivateData =
{
    UPPER_FIREWALL,     /* ulUpperFirewall */
    { 0 },              /* ulStats */
    { 0 },              /* ulErrors */
    LOWER_FIREWALL      /* ulLowerFirewall */
};

static ISL68221_PRIVATE_DATA *pxThis = &xPrivateData;


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/**
 * @brief   Read voltage using ISL68221 sensor
 */
int iISL68221_ReadVoltage( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucPageNum, float *pfVoltageInMV )
{
    int      iStatus                              = ERROR;
    uint8_t  pucWriteBuf[ ISL68221_BUFFER_SIZE ]  = { 0 };
    uint8_t  pucReadBuf[ ISL68221_BUFFER_SIZE ]   = { 0 };
    uint16_t usReadData                           = 0;

    if( ( NULL != pfVoltageInMV ) && ( MAX_ISL68221_SENSOR_PAGE >ucPageNum ) )
    {
        switch( ucPageNum )
        {
            case ISL68221_SENSOR_PAGE_0:
                pucWriteBuf[ 0 ] = ISL68221_SELECT_PAGE_RAIL_0;
                iStatus = OK;
                break;
            case ISL68221_SENSOR_PAGE_1:
                pucWriteBuf[ 0 ] = ISL68221_SELECT_PAGE_RAIL_1;
                iStatus = OK;
                break;
            case ISL68221_SENSOR_PAGE_2:
                pucWriteBuf[ 0 ] = ISL68221_SELECT_PAGE_RAIL_2;
                iStatus = OK;
                break;
            default:
                break;
        }

        if( OK == iStatus )
        {
            iStatus = iWriteRegister( ucBusNum, ucSlaveAddr, ISL68221_PAGE_REGISTER, ( uint8_t* ) pucWriteBuf );
        }

        if( OK == iStatus )
        {
            iStatus = iReadRegister( ucBusNum, ucSlaveAddr, ISL68221_OUTPUT_VOLTAGE_REGISTER, ( uint8_t* ) pucReadBuf );
        }

        if( OK == iStatus )
        {
            INC_STAT_COUNTER( ISL68221_STATS_VOLTAGE_READ )

            usReadData = ( pucReadBuf[ 1 ] << ISL68221_BIT_SHIFT ) | pucReadBuf[ 0 ];
            *pfVoltageInMV = ( ( float ) usReadData );
        }
        else
        {
            INC_ERROR_COUNTER( ISL68221_ERRORS_VOLTAGE_READ )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ISL68221_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Read current using ISL68221 sensor
 */
int iISL68221_ReadCurrent( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucPageNum, float *pfCurrentInA )
{
    int      iStatus                              = ERROR;
    uint8_t  pucWriteBuf[ ISL68221_BUFFER_SIZE ]  = { 0 };
    uint8_t  pucReadBuf[ ISL68221_BUFFER_SIZE ]   = { 0 };
    uint16_t usReadData                           = 0;

    if( ( NULL != pfCurrentInA ) && ( MAX_ISL68221_SENSOR_PAGE > ucPageNum ) )
    {
        switch( ucPageNum )
        {
            case ISL68221_SENSOR_PAGE_0:
                pucWriteBuf[ 0 ] = ISL68221_SELECT_PAGE_RAIL_0;
                iStatus = OK;
                break;
            case ISL68221_SENSOR_PAGE_1:
                pucWriteBuf[ 0 ] = ISL68221_SELECT_PAGE_RAIL_1;
                iStatus = OK;
                break;
            case ISL68221_SENSOR_PAGE_2:
                pucWriteBuf[ 0 ] = ISL68221_SELECT_PAGE_RAIL_2;
                iStatus = OK;
                break;
            default:
                break;
        }

        if( OK == iStatus )
        {
            iStatus = iWriteRegister( ucBusNum, ucSlaveAddr, ISL68221_PAGE_REGISTER, ( uint8_t* ) pucWriteBuf );
        }

        if( OK == iStatus )
        {
            iStatus = iReadRegister( ucBusNum, ucSlaveAddr, ISL68221_OUTPUT_CURRENT_REGISTER, ( uint8_t* ) pucReadBuf );
        }

        if( OK == iStatus )
        {
            INC_STAT_COUNTER( ISL68221_STATS_CURRENT_READ )

            usReadData = ( pucReadBuf[ 1 ] << ISL68221_BIT_SHIFT ) | pucReadBuf[ 0 ];
            *pfCurrentInA = ( ( float ) usReadData ) / ISL68221_CURRENT_SCALING_FACTOR;
        }
        else
        {
            INC_ERROR_COUNTER( ISL68221_ERRORS_CURRENT_READ )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ISL68221_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Read temperature using ISL68221 sensor
 */
int iISL68221_ReadTemperature( uint8_t ucBusNum, uint8_t ucSlaveAddr, uint8_t ucPageNum, float *pfTemperature )
{
    int      iStatus                              = ERROR;
    uint8_t  pucWriteBuf[ ISL68221_BUFFER_SIZE ]  = { 0 };
    uint8_t  pucReadBuf[ ISL68221_BUFFER_SIZE ]   = { 0 };
    uint16_t usReadData                           = 0;

    if( ( NULL != pfTemperature ) && ( MAX_ISL68221_SENSOR_PAGE > ucPageNum ) )
    {
        switch( ucPageNum )
        {
            case ISL68221_SENSOR_PAGE_0:
                pucWriteBuf[ 0 ] = ISL68221_SELECT_PAGE_RAIL_0;
                iStatus = OK;
                break;
            case ISL68221_SENSOR_PAGE_1:
                pucWriteBuf[ 0 ] = ISL68221_SELECT_PAGE_RAIL_1;
                iStatus = OK;
                break;
            case ISL68221_SENSOR_PAGE_2:
                pucWriteBuf[ 0 ] = ISL68221_SELECT_PAGE_RAIL_2;
                iStatus = OK;
                break;
            default:
                break;
        }

        if( OK == iStatus )
        {
            iStatus = iWriteRegister( ucBusNum, ucSlaveAddr, ISL68221_PAGE_REGISTER, ( uint8_t* ) pucWriteBuf );
        }

        if( OK == iStatus )
        {
            iStatus = iReadRegister(ucBusNum, ucSlaveAddr, ISL68221_READ_TEMP_HOTTEST_POWER_STAGE, ( uint8_t* ) pucReadBuf );
        }

        if( OK == iStatus )
        {
            INC_STAT_COUNTER( ISL68221_STATS_TEMPERATURE_READ )

            usReadData = ( pucReadBuf[ 1 ] << ISL68221_BIT_SHIFT ) | pucReadBuf[ 0 ];
            *pfTemperature = ( ( float ) usReadData );
        }
        else
        {
            INC_ERROR_COUNTER( ISL68221_ERRORS_TEMPERATURE_READ )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ISL68221_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iISL68221_PrintStatistics( void )
{
     int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( ISL68221_NAME, "============================================================\n\r" );
        PLL_INF( ISL68221_NAME, "ISL68221 Statistics:\n\r" );
        for( i = 0; i < ISL68221_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( ISL68221_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( ISL68221_NAME, "ISL68221 Errors:\n\r" );
        for( i = 0; i < ISL68221_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( ISL68221_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( ISL68221_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iISL68221_ClearStatistics( void )
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
        INC_ERROR_COUNTER( ISL68221_ERRORS_VALIDATION )
    }

    return iStatus;
}


/******************************************************************************/
/* Private Function implementations                                           */
/******************************************************************************/

/**
 * @brief   Send data to ISL68221 sensor
 */
static int iWriteRegister( uint8_t ucI2cNum, uint8_t ucSlaveAddr, uint8_t ucRegisterAddress, uint8_t *pucRegisterContent )
{
    int     iStatus                              = ERROR;
    uint8_t pucWriteData[ ISL68221_WRITE_SIZE ]  = { 0 };

    if( NULL != pucRegisterContent )
    {
        pucWriteData[ 0 ] = ucRegisterAddress;
        pucWriteData[ 1 ] = *pucRegisterContent;

        if( OK == iI2C_Send( ucI2cNum, ucSlaveAddr, pucWriteData, ISL68221_READ_LENGTH ) )
        {
            INC_STAT_COUNTER( ISL68221_STATS_REGISTER_WRITE );
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER( ISL68221_ERRORS_REGISTER_WRITE )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ISL68221_ERRORS_VALIDATION )
    }

    return( iStatus );
}

/**
 * @brief   Read data from ISL68221 sensor
 */
static int iReadRegister( uint8_t ucI2cNum, uint8_t ucSlaveAddr, uint8_t ucRegisterAddress, uint8_t *pucRegisterContent )
{
    int iStatus = ERROR;

    if( NULL != pucRegisterContent )
    {
        if( OK == iI2C_SendRecv( ucI2cNum, ucSlaveAddr, &ucRegisterAddress, ISL68221_WRITE_LENGTH, pucRegisterContent, ISL68221_READ_LENGTH ) )
        {
            INC_STAT_COUNTER( ISL68221_STATS_REGISTER_READ );
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER( ISL68221_ERRORS_REGISTER_READ )
        }
    }
    else
    {
        INC_ERROR_COUNTER( ISL68221_ERRORS_VALIDATION )
    }

    return( iStatus );
}

