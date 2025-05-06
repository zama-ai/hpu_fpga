/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the FW IF QSFP abstraction for AMC.
 *
 * @file fw_if_qsfp_amc.c
 *
 */

/*****************************************************************************/
/* Includes                                                                  */
/*****************************************************************************/

#include <stdio.h>
#include <string.h>

#include "util.h"
#include "fw_if_muxed_device.h"
#include "i2c.h"
#include "osal.h"
#include "profile_fal.h"

/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/

#define FW_IF_QSFP_NAME             "FW_IF_QSFP"
#define QSFP_UPPER_FIREWALL         ( 0xBEEFCAFE )
#define QSFP_LOWER_FIREWALL         ( 0xDEADFACE )

#define CHECK_DRIVER                if( FW_IF_FALSE == pxThis->iInitialised ) return FW_IF_ERRORS_DRIVER_NOT_INITIALISED
#define CHECK_FIREWALLS( f )        if( ( QSFP_UPPER_FIREWALL != f->upperFirewall ) &&        \
                                        ( QSFP_LOWER_FIREWALL != f->lowerFirewall ) &&        \
                                        ( QSFP_UPPER_FIREWALL != pxThis->ulUpperFirewall ) && \
                                        ( QSFP_LOWER_FIREWALL != pxThis->ulLowerFirewall ) ) return FW_IF_ERRORS_INVALID_HANDLE

#define CHECK_HDL( f )              if( NULL == f ) return FW_IF_ERRORS_INVALID_HANDLE
#define CHECK_CFG( f )              if( NULL == ( f )->cfg  ) return FW_IF_ERRORS_INVALID_CFG
#define CHECK_PROFILE( f )          if( NULL == ( f )->pvProfile ) return

/* Stat & Error definitions */
#define FW_IF_QSFP_STATS( DO )   \
    DO( FW_IF_QSFP_STATS_INIT_OVERALL_COMPLETE )         \
    DO( FW_IF_QSFP_STATS_INSTANCE_CREATE )               \
    DO( FW_IF_QSFP_STATS_I2C_SEND )                      \
    DO( FW_IF_QSFP_STATS_I2C_SEND_RECV )                 \
    DO( FW_IF_QSFP_STATS_MAX )

#define FW_IF_QSFP_ERRORS( DO )    \
    DO( FW_IF_QSFP_STATS_INSTANCE_CREATE_FAILED )        \
    DO( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )              \
    DO( FW_IF_QSFP_ERRORS_I2C_SEND_RECV_FAILED )         \
    DO( FW_IF_QSFP_ERRORS_VALIDATION_FAILED )            \
    DO( FW_IF_QSFP_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )             PLL_INF( FW_IF_QSFP_NAME, "%50s . . . . %d\r\n",          \
                                                     FW_IF_QSFP_STATS_STR[ x ],      \
                                                     pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x )            PLL_INF( FW_IF_QSFP_NAME, "%50s . . . . %d\r\n",          \
                                                     FW_IF_QSFP_ERRORS_STR[ x ],     \
                                                     pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )               { if( x < FW_IF_QSFP_STATS_MAX )pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x )              { if( x < FW_IF_QSFP_ERRORS_MAX )pxThis->pulErrorCounters[ x ]++; }


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    FW_IF_QSFP_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( FW_IF_QSFP_STATS, FW_IF_QSFP_STATS, FW_IF_QSFP_STATS_STR )

/**
 * @enum    FW_IF_QSFP_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( FW_IF_QSFP_ERRORS, FW_IF_QSFP_ERRORS, FW_IF_QSFP_ERRORS_STR )


/*****************************************************************************/
/* Structures                                                                */
/*****************************************************************************/

/**
 * @struct  FW_IF_QSFP_PRIVATE_DATA
 * @brief   Structure to hold this FAL's private data
 */
typedef struct FW_IF_QSFP_PRIVATE_DATA
{
    uint32_t                        ulUpperFirewall;

    FW_IF_MUXED_DEVICE_INIT_CFG     xLocalCfg;
    int                             iInitialised;
    uint32_t                        pulStatCounters[ FW_IF_QSFP_STATS_MAX ];
    uint32_t                        pulErrorCounters[ FW_IF_QSFP_ERRORS_MAX ];

    uint32_t                        ulLowerFirewall;

} FW_IF_QSFP_PRIVATE_DATA;


/*****************************************************************************/
/* local variables                                                           */
/*****************************************************************************/

static FW_IF_QSFP_PRIVATE_DATA xLocalData =
{
    QSFP_UPPER_FIREWALL,    /* ulUpperFirewall */
    { 0 },                  /* xLocalCfg       */
    FW_IF_FALSE,            /* iInitialised    */
    { 0 },                  /* pulStatCounters  */
    { 0 },                  /* pulErrorCounters */
    QSFP_LOWER_FIREWALL     /* ulLowerFirewall */
};
static FW_IF_QSFP_PRIVATE_DATA *pxThis = &xLocalData;


/*****************************************************************************/
/* Local Function declarations                                               */
/*****************************************************************************/

/**
 * @brief   Local function to check QSFP module presence,
 *          and set MODSEL line if detected.
 *
 * @param   pxCfg  Pointer to config options for QSFP interfaces
 *
 * @return  OK     QSFP present, and MODSEL line set
 *          ERROR  QSFP not present
 *
 */
static int iQsfpModuleSelect( FW_IF_MUXED_DEVICE_CFG *pxCfg );

/**
 * @brief   Local function to unset MODSEL line in QSFP IO expander.
 *
 * @param   pxCfg  Pointer to config options for QSFP interfaces
 *
 * @return  OK     QSFP IO expander MODSEL line deselected
 *          ERROR  Unable to deselect MODSEL line
 *
 */
static int iQsfpModuleDeselect( FW_IF_MUXED_DEVICE_CFG *pxCfg );

/**
 * @brief   Local implementation of open specifically for QSFP device
 *
 * @param   pvFwIf  Pointer to the FW interface for the QSFP
 *
 * @return  FW_IF_ERRORS_NONE   Open was successful
 *          FW_IF_ERRORS        Open failed
 *
 */
static uint32_t ulOpenQsfpDevice( void *pvFwIf );

/**
 * @brief   Read DIMM Device
 *
 * @param   pvFwIf      Pointer to the FW interface for the QSFP
 * @param   ullSrcPort  DIMM Register to read
 * @param   pucData     Pointer to the data read
 * @param   pulSize     Size of the data to read
 * @param   ulTimeoutMs Timeout value
 *
 * @return  FW_IF_ERRORS_NONE   Read was successful
 *          FW_IF_ERRORS        Read failed
 *
 */
static uint32_t ulReadDimmDevice( void *pvFwIf, uint64_t ullSrcPort, uint8_t *pucData, uint32_t *pulSize, uint32_t ulTimeoutMs );

/**
 * @brief   Read QSFP Device
 *
 * @param   pvFwIf      Pointer to the FW interface for the QSFP
 * @param   ullSrcPort  QSFP Register to read
 * @param   pucData     Pointer to the data read
 * @param   pulSize     Size of the data to read
 * @param   ulTimeoutMs Timeout value
 *
 * @return  FW_IF_ERRORS_NONE   Read was successful
 *          FW_IF_ERRORS        Read failed
 *
 */
static uint32_t ulReadQsfpDevice( void *pvFwIf, uint64_t ullSrcPort, uint8_t *pucData, uint32_t *pulSize, uint32_t ulTimeoutMs );


/*****************************************************************************/
/* local functions                                                           */
/*****************************************************************************/

/**
 * @brief   Local implementation of open specifically for QSFP device
 */
static uint32_t ulOpenQsfpDevice( void *pvFwIf )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );
    CHECK_DRIVER;

    FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )pxThisIf->cfg;
    uint8_t ucConfigRegValue = 0;
    uint8_t ucInputPortRegValue = 0;
    uint8_t ucOutputPortRegValue = 0;
    uint8_t pucReadBuf[ FAL_QSFP_READ_DEFAULT_SIZE ] = { 0 };
    uint8_t pucWriteBuff[ FAL_QSFP_WRITE_DEFAULT_SIZE ] = { 0 };

    /*
    * Setting power for each QSFP is a many step process
    *
    * 1) The correct bit in Power IO expander configuration register must be set to 0
    * to set the QSFP I/O port as an output
    *
    * 2) The correct bit in Power IO expander output port register must be set to 1
    * to set power for the respective QSFP
    *
    * 3) Power to the QSFPs can be verified with Power IO expander input port register
    * bits 4-7.
    *
    * 4) There are 2 muxes controlling 4 QSFPs. Set the other mux to 0 to ensure the
    * IO Expanders and QSFPs it controls are deselected.
    *
    * 5) Set MUX control register output to correct IO expander
    *
    * 6) Write to the IO expander output port to ensure MODSEL_L is set high
    *
    * 7) Write to the IO expander config port to configure the MODSEL_L pin as an output
    *
    * See TCA6408A I/O Expander whitepaper page 26 for register descriptions
    */

    /*
    * Step 1: Set I/O pin as output using configuration register
    * (At power on, all I/O pins are configured as inputs)
    */

    /* read current config reg value */
    pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_CONFIGURATION_REG;
    ulStatus = FW_IF_ERRORS_OPEN; /* set status before each I2C call */

    if( ERROR != iI2C_SendRecv( pxThis->xLocalCfg.ulI2CBusNum,
                                pxCfg->ucPowerIoExpanderAddr,
                                pucWriteBuff,
                                1,
                                pucReadBuf,
                                1 ) )
    {
        INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND_RECV )
        ulStatus = FW_IF_ERRORS_NONE;
    }
    else
    {
        INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_RECV_FAILED )
    }

    if( FW_IF_ERRORS_NONE == ulStatus )
    {
        ulStatus = FW_IF_ERRORS_OPEN;
        ucConfigRegValue = ( pucReadBuf[ 0 ] ) & ( ~pxCfg->ucPowerIoExpanderRegBit );

        /* write new config reg value */
        pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_CONFIGURATION_REG;
        pucWriteBuff[ 1 ] = ucConfigRegValue;

        if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucPowerIoExpanderAddr, pucWriteBuff, 2 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            ulStatus = FW_IF_ERRORS_NONE;
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
        }
    }

    /*
    * Step 2: Set I/O pin output value, using output port register.
    */
    if( FW_IF_ERRORS_NONE == ulStatus )
    {
        ulStatus = FW_IF_ERRORS_OPEN;

        /* read current output port reg value */
        pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_OUTPUT_PORT_REG;
        pucReadBuf[ 0 ] = 0;

        if( ERROR != iI2C_SendRecv( pxThis->xLocalCfg.ulI2CBusNum,
                                    pxCfg->ucPowerIoExpanderAddr,
                                    pucWriteBuff,
                                    1,
                                    pucReadBuf,
                                    1 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND_RECV )
            ulStatus = FW_IF_ERRORS_NONE;
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_RECV_FAILED )
        }
    }

    if( FW_IF_ERRORS_NONE == ulStatus )
    {
        ulStatus = FW_IF_ERRORS_OPEN;

        ucOutputPortRegValue = ( pucReadBuf[ 0 ] ) | ( pxCfg->ucPowerIoExpanderRegBit );

        /* write new output port reg value */
        pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_OUTPUT_PORT_REG;
        pucWriteBuff[ 1 ] = ucOutputPortRegValue;

        if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucPowerIoExpanderAddr, pucWriteBuff, 2 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            ulStatus = FW_IF_ERRORS_NONE;
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
        }
    }

    /* pause before checking QSFP power logic level */
    iOSAL_Task_SleepMs( FAL_QSFP_PROCESS_TIME_MS );

    /*
    * Step 3: Read Power IO Expander input port register
    * bits 4-7 to ensure power is on
    */
    if( FW_IF_ERRORS_NONE == ulStatus )
    {
        ulStatus = FW_IF_ERRORS_OPEN;

        /* read current input port reg value */
        pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_INPUT_PORT_REG;
        pucReadBuf[ 0 ] = 0;

        if( ERROR != iI2C_SendRecv( pxThis->xLocalCfg.ulI2CBusNum,
                                    pxCfg->ucPowerIoExpanderAddr,
                                    pucWriteBuff,
                                    1,
                                    pucReadBuf,
                                    1 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND_RECV )
            /* check input port reg bits */
            ucInputPortRegValue = ( pucReadBuf[ 0 ] ) >> FAL_QSFP_POWER_IO_EXPANDER_NUM_INPUTS;

            if( 0 != ( ucInputPortRegValue & pxCfg->ucPowerIoExpanderRegBit ) )
            {
                /* Power IO Expander bits 4-7 set correctly. QSFP power successfully set. */
                ulStatus = FW_IF_ERRORS_NONE;
            }
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_RECV_FAILED )
        }
    }

    /*
    * Step 4: Set Other IO Expander config reg
    */
    if( FW_IF_ERRORS_NONE == ulStatus )
    {
        ulStatus = FW_IF_ERRORS_OPEN;

        pucWriteBuff[ 0 ] = FAL_QSFP_MUX_IO_EXPANDER_DESELECTED;

        /* Ensure other MUX control register output is set to no IO Expander */
        if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->pucUnselectedMuxAddr[ FW_IF_MUX_ADDRESS_0 ], pucWriteBuff, 1 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            ulStatus = FW_IF_ERRORS_NONE;
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
        }
    }

    if( FW_IF_ERRORS_NONE == ulStatus )
    {
        ulStatus = FW_IF_ERRORS_OPEN;

        pucWriteBuff[ 0 ] = FAL_QSFP_MUX_IO_EXPANDER_DESELECTED;

        /* Ensure other MUX control register output is set to no IO Expander */
        if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->pucUnselectedMuxAddr[ FW_IF_MUX_ADDRESS_1 ], pucWriteBuff, 1 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            ulStatus = FW_IF_ERRORS_NONE;
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
        }
    }

    /*
    * Step 5: Point the MUX at the Correct IO Expander
    */
    if( FW_IF_ERRORS_NONE == ulStatus )
    {
        ulStatus = FW_IF_ERRORS_OPEN;
        /* Point the MUX at the IO Expander */
        pucWriteBuff[ 0 ] = pxCfg->ulMuxRegBitIoExpander;

        /* set MUX control register output to correct IO expander */
        if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucSelectedMuxAddr, pucWriteBuff, 1 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            ulStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
        }
    }

    /*
    * Step 6: Ensure MODSEL_L pin is high before we configure it as an output
    */
    if( FW_IF_ERRORS_NONE == ulStatus )
    {
        ulStatus = FW_IF_ERRORS_OPEN;

        /* set IO expander outputs high */
        pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_OUTPUT_PORT_REG;
        pucWriteBuff[ 1 ] = FAL_QSFP_ALL_OUTPUTS_HIGH ;

        if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucIoExpanderAddr, pucWriteBuff, 2 ) )
        {
            /* Ready to read from QSFP */
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            ulStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
        }
    }

    /*
    * Step 7: Set the IO Expander config register to configure
    * MODSEL_L_ line of the IO expander as an output
    */
    if( FW_IF_ERRORS_NONE == ulStatus )
    {
        ulStatus = FW_IF_ERRORS_OPEN;

        /* On the config register set module select line of the IO expander as an output.
        Config register is input by default */
        /* TODO - We may need to set other lines as outputs also eg. RESET_L, LPMODE */
        pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_CONFIGURATION_REG;
        pucWriteBuff[ 1 ] = FAL_QSFP_MODSELL_L_SET_LOW;

        if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucIoExpanderAddr, pucWriteBuff, 2 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            ulStatus = FW_IF_ERRORS_NONE;
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
        }
    }

    /* Delay to ensure QSFP is ready to be accessed */
    if( FW_IF_ERRORS_NONE == ulStatus )
    {
        /* Delay to allow QSFP a setup time after MODSEL is set */
        if( OSAL_ERRORS_NONE != iOSAL_Task_SleepMs( FAL_QSFP_PROCESS_TIME_MS ) )
        {
            ulStatus = FW_IF_ERRORS_OPEN;
        }
    }

    return ulStatus;
}

/**
 * @brief   Local implementation of FW_IF_open
 */
static uint32_t ulQsfpOpen( void *pvFwIf )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );
    CHECK_DRIVER;

    FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )pxThisIf->cfg;

    switch( pxCfg->xDevice )
    {
        case FW_IF_DEVICE_QSFP:
            ulStatus = ulOpenQsfpDevice( pvFwIf );
            break;

        case FW_IF_DEVICE_DIMM:
            /* DIMM  - No need to do anything on open */
            break;

        default:
            break;
    }

    return ulStatus;
}


/**
 * @brief   Local implementation of FW_IF_close
 */
static uint32_t ulQsfpClose( void *pvFwIf )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );
    CHECK_DRIVER;

    FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )pxThisIf->cfg;
    uint8_t ucOutputPortRegValue = 0;
    uint8_t pucReadBuf[ FAL_QSFP_READ_DEFAULT_SIZE ] = { 0 };
    uint8_t pucWriteBuff[ FAL_QSFP_WRITE_DEFAULT_SIZE ] = { 0 };

    switch( pxCfg->xDevice )
    {
        case FW_IF_DEVICE_QSFP:
        {
            /*
            * Set I/O pin output value to 0 to disable power,
            * using output port register.
            */
            ulStatus = FW_IF_ERRORS_CLOSE; /* set status before each I2C call */
            pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_OUTPUT_PORT_REG; /* read current output port reg value */

            if( ERROR != iI2C_SendRecv( pxThis->xLocalCfg.ulI2CBusNum,
                                        pxCfg->ucPowerIoExpanderAddr,
                                        pucWriteBuff,
                                        1,
                                        pucReadBuf,
                                        1 ) )
            {
                INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND_RECV )
                ulStatus = FW_IF_ERRORS_NONE;
            }
            else
            {
                INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_RECV_FAILED )
            }

            if( FW_IF_ERRORS_NONE == ulStatus )
            {
                ulStatus = FW_IF_ERRORS_CLOSE;

                ucOutputPortRegValue = ( pucReadBuf[ 0 ] ) & ( ~pxCfg->ucPowerIoExpanderRegBit );

                /* write new output port reg value */
                pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_OUTPUT_PORT_REG;
                pucWriteBuff[ 1 ] = ucOutputPortRegValue;

                if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucPowerIoExpanderAddr, pucWriteBuff, 2 ) )
                {
                    INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
                    ulStatus = FW_IF_ERRORS_NONE;
                }
                else
                {
                    INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
                }
            }
            break;
        }

        case FW_IF_DEVICE_DIMM:
            /* DIMM  - No need to do anything on close */
            break;

        default:
            break;
    }

    return ulStatus;
}

/**
 * @brief   Local implementation of FW_IF_write
 */
static uint32_t ulQsfpWrite( void *pvFwIf, uint64_t ullDstPort, uint8_t *pucData, uint32_t ulSize, uint32_t ulTimeoutMs )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );
    CHECK_DRIVER;

    if( ( NULL != pucData ) &&
        ( FAL_QSFP_MAX_DATA >= ulSize ) )
    {
        FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )pxThisIf->cfg;
        uint8_t pucWriteBuff[ FAL_QSFP_WRITE_DEFAULT_SIZE ] = { 0 };

        switch( pxCfg->xDevice )
        {
            case FW_IF_DEVICE_QSFP:
            {
                /*
                * Step 1: Check QSFP module is present
                */
                if( OK == iQsfpModuleSelect( pxCfg ) )
                {
                    /*
                    * Step 2: Read IO Expander control lines / Read QSFP memory map registers
                    * (based on config)
                    */
                    switch( pxCfg->xHwLevel )
                    {
                        case FW_IF_MUXED_DEVICE_HW_LEVEL_MEMORY_MAP:
                        {
                            ulStatus = FW_IF_ERRORS_WRITE;

                            /* delay before writing qsfp registers  */
                            iOSAL_Task_SleepTicks( FAL_QSFP_PROCESS_TIME_TICKS );

                            /* write QSFP memory map registers */
                            uint8_t *pucQsfpWriteBuff = pvOSAL_MemAlloc( ( ulSize+1 ) * sizeof( uint8_t ) );

                            if( NULL != pucQsfpWriteBuff )
                            {
                                pucQsfpWriteBuff[ 0 ] = ullDstPort;
                                pvOSAL_MemCpy( &pucQsfpWriteBuff[ 1 ], pucData, ulSize );

                                if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucDeviceI2cAddr, pucQsfpWriteBuff, ulSize+1 ) )
                                {
                                    INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
                                    ulStatus = FW_IF_ERRORS_NONE;
                                }
                                else
                                {
                                    INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
                                }

                                vOSAL_MemFree( ( void** )&pucQsfpWriteBuff );
                            }
                            break;
                        }

                        case FW_IF_MUXED_DEVICE_HW_LEVEL_IO_EXPANDER:
                        {
                            ulStatus = FW_IF_ERRORS_WRITE;

                            /* write IO expander control lines */
                            pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_OUTPUT_PORT_REG;
                            pucWriteBuff[ 1 ] = *pucData;

                            if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucIoExpanderAddr, pucWriteBuff, 2 ) )
                            {
                                INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
                                ulStatus = FW_IF_ERRORS_NONE;
                            }
                            else
                            {
                                INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
                            }

                            break;
                        }

                        default:
                        {
                            /* unsupported HW level */
                            ulStatus = FW_IF_ERRORS_INVALID_CFG;
                            break;
                        }
                    }

                    /*
                    * Step 3: Re-set selections for future APIs
                    */
                    if( OK != iQsfpModuleDeselect( pxCfg ) )
                    {
                        ulStatus = FW_IF_ERRORS_WRITE;
                    }
                }
                else
                {
                    /* QSFP module not present */
                    ulStatus = FW_IF_ERRORS_WRITE;
                }

                /* disable the MUX */
                pucWriteBuff[ 0 ] = 0;

                if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucSelectedMuxAddr, pucWriteBuff, 1 ) )
                {
                    INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
                }
                else
                {
                    /* unable to disable the MUX */
                    INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
                    ulStatus = FW_IF_ERRORS_WRITE;
                }
                break;
            }


            case FW_IF_DEVICE_DIMM:
                /* DIMM  - No need to do anything on write */
                break;

            default:
                break;
        }
    }
    else
    {
        ulStatus = FW_IF_ERRORS_PARAMS;
    }

    return ulStatus;
}

/**
 * @brief   Read DIMM Device
 */
static uint32_t ulReadDimmDevice( void *pvFwIf, uint64_t ullSrcPort, uint8_t *pucData, uint32_t *pulSize, uint32_t ulTimeoutMs )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );
    CHECK_DRIVER;

    if( ( NULL != pucData ) &&
        ( NULL != pulSize ) &&
        ( FAL_QSFP_MAX_DATA >= *pulSize ) )
    {
        FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )pxThisIf->cfg;
        uint8_t pucWriteBuff[ FAL_QSFP_WRITE_DEFAULT_SIZE ] = { 0 };

        pucWriteBuff[ 0 ] = FAL_QSFP_MUX_IO_EXPANDER_DESELECTED;

        /* Ensure 2nd MUX control register output is set to no IO Expander */
        if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->pucUnselectedMuxAddr[ FW_IF_MUX_ADDRESS_0 ], pucWriteBuff, 1 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
                ulStatus = FW_IF_ERRORS_READ;
        }

        /* Ensure 3rd MUX control register output is set to no IO Expander */
        if( FW_IF_ERRORS_NONE == ulStatus )
        {
            if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->pucUnselectedMuxAddr[ FW_IF_MUX_ADDRESS_1 ], pucWriteBuff, 1 ) )
            {
                INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            }
            else
            {
                INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
                    ulStatus = FW_IF_ERRORS_READ;
            }
        }

        /* Ensure DIMM MUX is set to correct Expander */
        if( FW_IF_ERRORS_NONE == ulStatus )
        {
            pucWriteBuff[ 0 ] = pxCfg->ulMuxRegBitIoExpander;
            if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucSelectedMuxAddr, pucWriteBuff, 1 ) )
            {
                INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            }
            else
            {
                INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
                    ulStatus = FW_IF_ERRORS_READ;
            }
        }

        if( FW_IF_ERRORS_NONE == ulStatus )
        {
            /* read DIMM register */
            pucWriteBuff[ 0 ] = ( uint8_t )ullSrcPort;
            if( ERROR != iI2C_SendRecv( pxThis->xLocalCfg.ulI2CBusNum,
                                        pxCfg->ucDeviceI2cAddr,
                                        pucWriteBuff,
                                        1,
                                        pucData,
                                        *pulSize ) )
            {
                INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND_RECV )
            }
            else
            {
                INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_RECV_FAILED )
                ulStatus = FW_IF_ERRORS_READ;
            }
        }
    }
    return ulStatus;
}

/**
 * @brief   Read QSFP Device
 */
static uint32_t ulReadQsfpDevice( void *pvFwIf, uint64_t ullSrcPort, uint8_t *pucData, uint32_t *pulSize, uint32_t ulTimeoutMs )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );
    CHECK_DRIVER;

    if( ( NULL != pucData ) &&
        ( NULL != pulSize ) &&
        ( FAL_QSFP_MAX_DATA >= *pulSize ) )
    {
        FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )pxThisIf->cfg;
        uint8_t pucWriteBuff[ FAL_QSFP_WRITE_DEFAULT_SIZE ] = { 0 };

        /*
        * Step 1: Check QSFP module is present
        */
        if( OK == iQsfpModuleSelect( pxCfg ) )
        {
            /*
            * Step 2: Read IO Expander control lines / Read QSFP memory map registers
            * (based on config)
            */
            switch( pxCfg->xHwLevel )
            {
                case FW_IF_MUXED_DEVICE_HW_LEVEL_MEMORY_MAP:
                {
                    /* read QSFP memory map registers */
                    pucWriteBuff[ 0 ] = ( uint8_t )ullSrcPort;

                    if( ERROR != iI2C_SendRecv( pxThis->xLocalCfg.ulI2CBusNum,
                                                pxCfg->ucDeviceI2cAddr,
                                                pucWriteBuff,
                                                1,
                                                pucData,
                                                *pulSize ) )
                    {
                        INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND_RECV )
                    }
                    else
                    {
                        INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_RECV_FAILED )
                        ulStatus = FW_IF_ERRORS_READ;
                    }

                    break;
                }

                case FW_IF_MUXED_DEVICE_HW_LEVEL_IO_EXPANDER:
                {
                    /* read IO expander control lines */
                    pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_INPUT_PORT_REG;
                    *pulSize = 1; /* update read size to 1 byte */

                    if( ERROR != iI2C_SendRecv( pxThis->xLocalCfg.ulI2CBusNum,
                                                pxCfg->ucIoExpanderAddr,
                                                pucWriteBuff,
                                                1,
                                                pucData,
                                                *pulSize ) )
                    {
                        INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND_RECV )
                    }
                    else
                    {
                        INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_RECV_FAILED )
                        ulStatus = FW_IF_ERRORS_READ;
                    }

                    break;
                }

                default:
                {
                    /* unsupported HW level */
                    ulStatus = FW_IF_ERRORS_INVALID_CFG;
                    break;
                }
            }

            /*
            * Step 3: Re-set selections for future APIs
            */
            if( OK != iQsfpModuleDeselect( pxCfg ) )
            {
                ulStatus = FW_IF_ERRORS_READ;
            }
        }
        else
        {
            /* QSFP module not present */
            ulStatus = FW_IF_ERRORS_READ;
        }

    }
    return ulStatus;
}

/**
 * @brief   Local implementation of FW_IF_read
 */
static uint32_t ulQsfpRead( void *pvFwIf, uint64_t ullSrcPort, uint8_t *pucData, uint32_t *pulSize, uint32_t ulTimeoutMs )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );
    CHECK_DRIVER;

    if( ( NULL != pucData ) &&
        ( NULL != pulSize ) &&
        ( FAL_QSFP_MAX_DATA >= *pulSize ) )
    {
        FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )pxThisIf->cfg;

        switch( pxCfg->xDevice )
        {
            case FW_IF_DEVICE_QSFP:
                ulStatus = ulReadQsfpDevice( pvFwIf, ullSrcPort, pucData, pulSize, ulTimeoutMs );
                break;

            case FW_IF_DEVICE_DIMM:
                ulStatus = ulReadDimmDevice( pvFwIf, ullSrcPort, pucData, pulSize, ulTimeoutMs );
                break;

            default:
                break;
        }
    }
    else
    {
        ulStatus = FW_IF_ERRORS_PARAMS;
    }

    return ulStatus;
}

/**
 * @brief   Local implementation of FW_IF_ioctrl
 */
static uint32_t ulQsfpIoctrl( void *pvFwIf, uint32_t ulOption, void *pvValue )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );
    CHECK_DRIVER;

    FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )pxThisIf->cfg;

    switch( ulOption )
    {
        case FW_IF_COMMON_IOCTRL_FLUSH_TX:
        case FW_IF_COMMON_IOCTRL_FLUSH_RX:
        case FW_IF_COMMON_IOCTRL_GET_RX_MODE:
            /*
             * Handle common IOCTL's.
             */
            break;

        case FW_IF_MUXED_DEVICE_IOCTL_SET_IO_EXPANDER:
        {
            pxCfg->xHwLevel = FW_IF_MUXED_DEVICE_HW_LEVEL_IO_EXPANDER;
            break;
        }

        case FW_IF_MUXED_DEVICE_IOCTL_SET_MEMORY_MAP:
        {
            pxCfg->xHwLevel = FW_IF_MUXED_DEVICE_HW_LEVEL_MEMORY_MAP;
            break;
        }

        default:
        {
            ulStatus = FW_IF_ERRORS_UNRECOGNISED_OPTION;
            PLL_ERR( FW_IF_QSFP_NAME, "QSFP IOCTL - Unrecognised option\r\n" );
            break;
        }
    }

    return ulStatus;
}

/**
 * @brief   Local implementation of FW_IF_bindCallback
 */
static uint32_t ulQsfpBindCallback( void *pvFwIf, FW_IF_callback *pxNewFunc )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    FW_IF_CFG *pxThisIf = ( FW_IF_CFG* )pvFwIf;
    CHECK_HDL( pxThisIf );
    CHECK_CFG( pxThisIf );
    CHECK_FIREWALLS( pxThisIf );
    CHECK_DRIVER;

    if( NULL != pxNewFunc )
    {
        FW_IF_MUXED_DEVICE_CFG *pxCfg = ( FW_IF_MUXED_DEVICE_CFG* )pxThisIf->cfg;

        /*
         * Binds in callback provided to the FW_IF.
         * Callback will be invoked when driver event occurs.
         */
        pxThisIf->raiseEvent = pxNewFunc;
        PLL_DBG( FW_IF_QSFP_NAME, "QSFP FW_IF_bindCallback (qsfp address 0x%02X) \r\n",
               ( unsigned int )pxCfg->ucDeviceI2cAddr );
    }
    else
    {
        ulStatus = FW_IF_ERRORS_PARAMS;
    }

    return ulStatus;
}

/**
 * @brief   Local function to check QSFP module presence,
 *          and set MODSEL line if detected.
 */
static int iQsfpModuleSelect( FW_IF_MUXED_DEVICE_CFG *pxCfg )
{
    int iStatus = ERROR;

    if( NULL != pxCfg )
    {
        uint8_t ucInputPortRegValue = 0;
        uint8_t pucReadBuf[ FAL_QSFP_READ_DEFAULT_SIZE ] = { 0 };
        uint8_t pucWriteBuff[ FAL_QSFP_WRITE_DEFAULT_SIZE ] = { 0 };

        pucWriteBuff[ 0 ] = FAL_QSFP_MUX_IO_EXPANDER_DESELECTED;

        /* Ensure 2nd MUX control register output is set to no IO Expander */
        if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->pucUnselectedMuxAddr[ FW_IF_MUX_ADDRESS_0 ], pucWriteBuff, 1 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
        }

        /* Ensure 3rd MUX control register output is set to no IO Expander */
        if( OK == iStatus )
        {
            if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->pucUnselectedMuxAddr[ FW_IF_MUX_ADDRESS_1 ], pucWriteBuff, 1 ) )
            {
                INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
            }
        }

        if( OK == iStatus )
        {
            iStatus = ERROR;
            /* We should be able to set both the IO Expander and the QSFP on the MUX */
            pucWriteBuff[ 0 ] = pxCfg->ulMuxRegBitIoExpander | pxCfg->ulMuxRegBit;

            /* set MUX control register output to correct IO expander */
            if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucSelectedMuxAddr, pucWriteBuff, 1 ) )
            {
                INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
            }
        }

        if( OK == iStatus )
        {
            iStatus = ERROR;

            /* Read MODPRES line of IO Expander to determine if QSFP is present */
            pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_INPUT_PORT_REG;

            if( ERROR != iI2C_SendRecv( pxThis->xLocalCfg.ulI2CBusNum,
                                        pxCfg->ucIoExpanderAddr,
                                        pucWriteBuff,
                                        1,
                                        pucReadBuf,
                                        1 ) )
            {
                INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND_RECV )
                ucInputPortRegValue = pucReadBuf[ 0 ];
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_RECV_FAILED )
            }
        }

        if( OK == iStatus )
        {
            iStatus = ERROR;

            /* Check if QSFP is present */
            if( 0 == ( ucInputPortRegValue & FAL_QSFP_MODPRES_L_BIT_MASK ) )
            {
                /* If QSFP module is present check if MODSEL_L is already selected */
                if( 0 != ( ucInputPortRegValue & FAL_QSFP_MODSEL_L_BIT_MASK ) )
                {
                    /* MODSEL_L wasn't yet set so set it 0 */
                    pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_OUTPUT_PORT_REG;
                    pucWriteBuff[ 1 ] = ( ucInputPortRegValue & FAL_QSFP_MODSELL_L_SET_LOW );
                    if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucIoExpanderAddr, pucWriteBuff, 2 ) )
                    {
                        /* Ready to read from QSFP */
                        INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
                        iStatus = OK;
                    }
                    else
                    {
                        INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
                    }

                    /* Delay to allow QSFP a setup time after MODSEL is set */
                    if( OSAL_ERRORS_NONE != iOSAL_Task_SleepMs( FAL_QSFP_PROCESS_TIME_MS ) )
                    {
                        iStatus = ERROR;
                    }
                }
                else
                {
                    iStatus = OK;
                }
            }
            else
            {
                /* QSFP is not present. Check if MODSEL was already selected and if so unset it */
                if( 0 == ( ucInputPortRegValue & FAL_QSFP_MODSEL_L_BIT_MASK ) )
                {
                    /* set MODSEL to 1 */
                    pucWriteBuff[ 0 ] = FAL_QSFP_IO_EXPANDER_OUTPUT_PORT_REG;
                    pucWriteBuff[ 1 ] = ( ucInputPortRegValue | ~FAL_QSFP_MODSELL_L_SET_LOW );

                    if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucIoExpanderAddr, pucWriteBuff, 2 ) )
                    {
                        INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
                        /* Leave iStatus as ERROR to stop access to QSFP */
                    }
                    else
                    {
                        INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
                    }
                }
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Local function to unset MODSEL line in QSFP IO expander.
 */
static int iQsfpModuleDeselect( FW_IF_MUXED_DEVICE_CFG *pxCfg )
{
    int iStatus = ERROR;

    if( NULL != pxCfg )
    {
        uint8_t pucWriteBuff[ FAL_QSFP_WRITE_DEFAULT_SIZE ] = { 0 };

        pucWriteBuff[ 0 ] = pxCfg->ulMuxRegBitIoExpander;

        /* set MUX control register output to correct IO expander */
        if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucSelectedMuxAddr, pucWriteBuff, 1 ) )
        {
            INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
            iStatus = OK;
        }
        else
        {
            INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
        }

        if( OK == iStatus )
        {
            iStatus = ERROR;
            /* Finally set the MUX control register output to deselect the IO Expander */
            pucWriteBuff[ 0 ] = FAL_QSFP_MUX_IO_EXPANDER_DESELECTED;
            if( ERROR != iI2C_Send( pxThis->xLocalCfg.ulI2CBusNum, pxCfg->ucSelectedMuxAddr, pucWriteBuff, 1 ) )
            {
                INC_STAT_COUNTER( FW_IF_QSFP_STATS_I2C_SEND )
                iStatus = OK;
            }
            else
            {
                INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_I2C_SEND_FAILED )
            }
        }
    }

    return iStatus;
}

/*****************************************************************************/
/* public functions                                                          */
/*****************************************************************************/

/**
 * @brief   initialisation function for QSFP interfaces (generic across all QSFP interfaces)
 */
uint32_t ulFW_IF_MUXED_DEVICE_Init( FW_IF_MUXED_DEVICE_INIT_CFG *pxInitCfg )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    if( FW_IF_FALSE != pxThis->iInitialised )
    {
        ulStatus = FW_IF_ERRORS_DRIVER_IN_USE;
    }
    else if ( NULL == pxInitCfg )
    {
        ulStatus = FW_IF_ERRORS_PARAMS;
    }
    else
    {
        /*
         * Initilise config data shared between all QSFPs.
         */
        pvOSAL_MemCpy( &pxThis->xLocalCfg, pxInitCfg, sizeof( FW_IF_MUXED_DEVICE_INIT_CFG ) );
        pxThis->iInitialised = FW_IF_TRUE;
        INC_STAT_COUNTER( FW_IF_QSFP_STATS_INIT_OVERALL_COMPLETE )
    }

    return ulStatus;
}

/**
 * @brief   creates an instance of the QSFP interface
 */
uint32_t ulFW_IF_MUXED_DEVICE_Create( FW_IF_CFG *pxFwIf, FW_IF_MUXED_DEVICE_CFG *pxQsfpCfg )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    CHECK_DRIVER;

    if( ( NULL != pxFwIf ) && ( NULL != pxQsfpCfg ) )
    {
        FW_IF_CFG xLocalIf =
        {
            .upperFirewall  = QSFP_UPPER_FIREWALL,
            .open           = &ulQsfpOpen,
            .close          = &ulQsfpClose,
            .write          = &ulQsfpWrite,
            .read           = &ulQsfpRead,
            .ioctrl         = &ulQsfpIoctrl,
            .bindCallback   = &ulQsfpBindCallback,
            .cfg            = ( void* )pxQsfpCfg,
            .lowerFirewall  = QSFP_LOWER_FIREWALL
        };

        pvOSAL_MemCpy( pxFwIf, &xLocalIf, sizeof( FW_IF_CFG ) );
        INC_STAT_COUNTER( FW_IF_QSFP_STATS_INSTANCE_CREATE );
    }
    else
    {
        INC_ERROR_COUNTER( FW_IF_QSFP_STATS_INSTANCE_CREATE_FAILED )
        ulStatus = FW_IF_ERRORS_PARAMS;
    }

    return ulStatus;
}

/**
 * @brief   Print all the stats gathered by the application
 */
uint32_t ulFW_IF_MUXED_DEVICE_PrintStatistics( void )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    if( FW_IF_TRUE == pxThis->iInitialised )
    {
        int i = 0;
        PLL_INF( FW_IF_QSFP_NAME, "============================================================\n\r" );
        PLL_INF( FW_IF_QSFP_NAME, "FWIF QSFP Statistics:\n\r" );
        for( i = 0; i < FW_IF_QSFP_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( FW_IF_QSFP_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( FW_IF_QSFP_NAME, "FWIF QSFP Errors:\n\r" );
        for( i = 0; i < FW_IF_QSFP_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( FW_IF_QSFP_NAME, "============================================================\n\r" );
    }
    else
    {
        INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_VALIDATION_FAILED )
        ulStatus = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
    }

    return ulStatus;
}

/**
 * @brief   Clear all the stats in the application
 */
uint32_t ulFW_IF_MUXED_DEVICE_ClearStatistics( void )
{
    uint32_t ulStatus = FW_IF_ERRORS_NONE;

    if( FW_IF_TRUE == pxThis->iInitialised )
    {
        pvOSAL_MemSet( pxThis->pulStatCounters, 0, sizeof( pxThis->pulStatCounters ) );
        pvOSAL_MemSet( pxThis->pulErrorCounters, 0, sizeof( pxThis->pulErrorCounters ) );
    }
    else
    {
        INC_ERROR_COUNTER( FW_IF_QSFP_ERRORS_VALIDATION_FAILED )
        ulStatus = FW_IF_ERRORS_DRIVER_NOT_INITIALISED;
    }

    return ulStatus;
}
