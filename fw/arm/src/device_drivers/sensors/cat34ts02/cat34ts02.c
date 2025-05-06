/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implementation of CAT34TS02 sensor read
 * functions.
 *
 * @file cat34ts02.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "util.h"
#include "pll.h"

#include "cat34ts02.h"
#include "i2c.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL                          ( 0xBABECAFE )
#define LOWER_FIREWALL                          ( 0xDEADFACE )

#define CAT34TS02_NAME                          "CAT34TS02"

#define CAT34TS02_ERROR                         ( 1 )
#define CAT34TS02_WRITE_BUFFER_SIZE             ( 1 )
#define CAT34TS02_READ_BUFFER_SIZE              ( 2 )
#define CAT34TS02_WRITE_LENGTH                  ( 1 )
#define CAT34TS02_READ_LENGTH                   ( 2 )
#define CAT34TS02_BIT_SHIFT                     ( 8 )

#define CAT34TS02_TEMPERATURE_REGISTER          ( 0x05 )
#define CAT34TS02_TEMPERATURE_SIGN_BIT          ( 12 )
#define CAT34TS02_TEMP_NON_WHOLE_BITS           ( 4 )

#define CAT34TS02_STATS( DO )                  \
    DO( CAT34TS02_STATS_TEMPERATURE_READ )     \
    DO( CAT34TS02_STATS_MAX )

#define CAT34TS02_ERRORS( DO )                 \
    DO( CAT34TS02_ERRORS_TEMPERATURE_READ )    \
    DO( CAT34TS02_ERRORS_VALIDATION )          \
    DO( CAT34TS02_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )         PLL_INF( CAT34TS02_NAME, "%50s . . . . %d\r\n",    \
                                                 CAT34TS02_STATS_STR[ x ],                 \
                                                 pxThis->ulStats[ x ] )
#define PRINT_ERROR_COUNTER( x )        PLL_INF( CAT34TS02_NAME, "%50s . . . . %d\r\n",    \
                                                 CAT34TS02_ERRORS_STR[ x ],                \
                                                 pxThis->ulErrors[ x ] )

#define INC_STAT_COUNTER( x )           { if( x < CAT34TS02_STATS_MAX )pxThis->ulStats[ x ]++; }
#define INC_ERROR_COUNTER( x )          { if( x < CAT34TS02_ERRORS_MAX )pxThis->ulErrors[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    CAT34TS02_STATS
 * @brief   Enumeration of stats counters for this library
 */
UTIL_MAKE_ENUM_AND_STRINGS( CAT34TS02_STATS, CAT34TS02_STATS, CAT34TS02_STATS_STR )

/**
 * @enum    CAT34TS02_ERRORS
 * @brief   Enumeration of stats errors for this library
 */
UTIL_MAKE_ENUM_AND_STRINGS( CAT34TS02_ERRORS, CAT34TS02_ERRORS, CAT34TS02_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  CAT34TS02_PRIVATE_DATA
 * @brief   Private driver data
 */
typedef struct CAT34TS02_PRIVATE_DATA
{
    uint32_t    ulUpperFirewall;

    uint32_t    ulStats[ CAT34TS02_STATS_MAX ];
    uint32_t    ulErrors[ CAT34TS02_ERRORS_MAX ];

    uint32_t    ulLowerFirewall;

} CAT34TS02_PRIVATE_DATA;


/******************************************************************************/
/* Local variables                                                            */
/******************************************************************************/

static CAT34TS02_PRIVATE_DATA xPrivateData =
{
    UPPER_FIREWALL,     /* ulUpperFirewall */
    { 0 },              /* ulStats */
    { 0 },              /* ulErrors */
    LOWER_FIREWALL      /* ulLowerFirewall */
};

static CAT34TS02_PRIVATE_DATA *pxThis = &xPrivateData;


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/**
 * @brief   Read temperature using CAT34TS02 sensor
 */
int iCAT34TS02_ReadTemperature( uint8_t ucI2cNum, uint8_t ucSlaveAddr, uint8_t ucChannelNum, float *pfTemperatureValue )
{
    UNUSED( ucChannelNum );

    int      iStatus                                     = ERROR;
    uint16_t usTempHexVal                                = 0;
    uint8_t  pucWriteBuf[ CAT34TS02_WRITE_BUFFER_SIZE ]  = { 0 };
    uint8_t  pucReadBuf[ CAT34TS02_READ_BUFFER_SIZE ]    = { 0 };

    pucWriteBuf[ 0 ] = CAT34TS02_TEMPERATURE_REGISTER;

    if( NULL != pfTemperatureValue )
    {
        iStatus = iI2C_SendRecv( ucI2cNum, ucSlaveAddr, &pucWriteBuf[ 0 ], CAT34TS02_WRITE_LENGTH, &pucReadBuf[ 0 ], CAT34TS02_READ_LENGTH );

        if( OK == iStatus )
        {
            INC_STAT_COUNTER( CAT34TS02_STATS_TEMPERATURE_READ );

            uint16_t usNativeInt = 0;

            /* Arrange the bytes in  the correct order */
            usTempHexVal = pucReadBuf[ 1 ] | ( pucReadBuf[ 0 ] << CAT34TS02_BIT_SHIFT );

            /* Bit 12 (MSB) determines if the number is positive or negative */
            const int iNegative = ( ( usTempHexVal & ( 1 << CAT34TS02_TEMPERATURE_SIGN_BIT ) ) != 0 );

            usTempHexVal &= ( 0xFFF );

            /* If the value was negative we need to correct the MSB to reflect that
            and finally divide by 16 to change the temperature to a whole number */
            if( TRUE == iNegative )
            {
                usNativeInt = usTempHexVal | ~( ( 1 << CAT34TS02_TEMPERATURE_SIGN_BIT) - 1 );
                *pfTemperatureValue = ( uint16_t )( usNativeInt / ( 1 << CAT34TS02_TEMP_NON_WHOLE_BITS ) );
            }
            else
            {
                usNativeInt = usTempHexVal;
                *pfTemperatureValue = ( uint16_t )( usNativeInt / ( 1 << CAT34TS02_TEMP_NON_WHOLE_BITS ) );
            }
        }
        else
        {
            INC_ERROR_COUNTER( CAT34TS02_ERRORS_TEMPERATURE_READ );
        }
    }
    else
    {
        INC_ERROR_COUNTER( CAT34TS02_ERRORS_VALIDATION );
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iCAT34TS02_PrintStatistics( void )
{
     int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( CAT34TS02_NAME, "============================================================\n\r" );
        PLL_INF( CAT34TS02_NAME, "CAT34TS02 Statistics:\n\r" );
        for( i = 0; i < CAT34TS02_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( CAT34TS02_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( CAT34TS02_NAME, "CAT34TS02 Errors:\n\r" );
        for( i = 0; i < CAT34TS02_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( CAT34TS02_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( CAT34TS02_ERRORS_VALIDATION )
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iCAT34TS02_ClearStatistics( void )
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
        INC_ERROR_COUNTER( CAT34TS02_ERRORS_VALIDATION )
    }

    return iStatus;
}
