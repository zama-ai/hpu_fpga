/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the fal profile for the V80
 *
 * @file profile_fal.c
 *
 */

/*****************************************************************************/
/* Includes                                                                  */
/*****************************************************************************/

/* core libs */
#include "pll.h"

/* fal */
#include "fw_if_muxed_device.h"
#include "fw_if_gcq.h"
#include "fw_if_ospi.h"
#include "fw_if_emmc.h"
#include "fw_if_test.h"

/* device drivers */
#include "i2c.h"

/* proxy drivers*/
#include "apc_proxy_driver.h"
#include "ami_proxy_driver.h"

/* hardware definitions */
#include "profile_fal.h"
#include "profile_hal.h"
#include "profile_muxed_device.h"

/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define FAL_PROFILE_NAME      "PROFILE_FAL"
#define OSPI_PAGE_SIZE        ( 256 )
#define OSPI_RPU_BASE_ADDRESS ( 0x0 )
#define OSPI_RPU_LENGTH       ( 0x10000000 )                                   /* 2Gb (256MB) */
#define EMMC_RPU_BASE_ADDRESS ( 0x0 )
#define EMMC_RPU_LENGTH       ( ( uint64_t )HAL_EMMC_MAX_BLOCKS * ( uint64_t )HAL_EMMC_BLOCK_SIZE ) /* 64Gb */

#define FW_IF_SMBUS_UDID_LEN  ( 16 )

/* Enable SMBus PCIe link */
#define TCA6416AR_BIT_3                 ( 1 << 3 )
#define TCA6416AR_ADDRESS               ( 0x20 )
#define TCA6416AR_CONFIGURATION_0       ( 0x06 )
#define TCA6416AR_OUTPUT_PORT_0         ( 0x02 )
#define TCA6416AR_READ_BUFF_SIZE        ( 1 )
#define TCA6416AR_READ_BYTES_TO_RECEIVE ( 1 )
#define TCA6416AR_WRITE_BUFF_SIZE       ( 2 )


/*****************************************************************************/
/* Global variables                                                          */
/*****************************************************************************/

/* FAL objects */
FW_IF_CFG xGcqIf =
{
    0
};
FW_IF_CFG xOspiIf =
{
    0
};
FW_IF_CFG xEmmcIf =
{
    0
};
FW_IF_CFG xQsfpIf1 =
{
    0
};
FW_IF_CFG xQsfpIf2 =
{
    0
};
FW_IF_CFG xQsfpIf3 =
{
    0
};
FW_IF_CFG xQsfpIf4 =
{
    0
};
FW_IF_CFG xDimmIf =
{
    0
};
FW_IF_CFG xSMBusIf =
{
    0
};

FW_IF_CFG *pxEmmcIf  = &xEmmcIf;
FW_IF_CFG *pxOspiIf  = &xOspiIf;
FW_IF_CFG *pxSMBusIf = &xSMBusIf;

/*****************************************************************************/
/* Local variables                                                           */
/*****************************************************************************/

static FW_IF_MUXED_DEVICE_CFG xQsfpCfg1 =
{
    FW_IF_DEVICE_QSFP,
    QSFP_POWER_IO_EXPANDER_I2C_ADDR,
    QSFP_1_REG_BIT_OFFSET,
    MUXED_DEVICE_MUX_1_ADDR,
    {
        MUXED_DEVICE_MUX_2_ADDR, MUXED_DEVICE_MUX_3_ADDR
    },
    MUXED_DEVICE_MUX_REG_BIT_1,
    MUXED_DEVICE_MUX_REG_BIT_2,
    QSFP_IO_EXPANDER_I2C_ADDR,
    QSFP_I2C_ADDR,
    FW_IF_MUXED_DEVICE_HW_LEVEL_MEMORY_MAP
};                                                                             /* QSFP 1 */
static FW_IF_MUXED_DEVICE_CFG xQsfpCfg2 =
{
    FW_IF_DEVICE_QSFP,
    QSFP_POWER_IO_EXPANDER_I2C_ADDR,
    QSFP_2_REG_BIT_OFFSET,
    MUXED_DEVICE_MUX_1_ADDR,
    {
        MUXED_DEVICE_MUX_2_ADDR, MUXED_DEVICE_MUX_3_ADDR
    },
    MUXED_DEVICE_MUX_REG_BIT_3,
    MUXED_DEVICE_MUX_REG_BIT_4,
    QSFP_IO_EXPANDER_I2C_ADDR,
    QSFP_I2C_ADDR,
    FW_IF_MUXED_DEVICE_HW_LEVEL_MEMORY_MAP
};                                                                             /* QSFP 2 */
static FW_IF_MUXED_DEVICE_CFG xQsfpCfg3 =
{
    FW_IF_DEVICE_QSFP,
    QSFP_POWER_IO_EXPANDER_I2C_ADDR,
    QSFP_3_REG_BIT_OFFSET,
    MUXED_DEVICE_MUX_2_ADDR,
    {
        MUXED_DEVICE_MUX_1_ADDR, MUXED_DEVICE_MUX_3_ADDR
    },
    MUXED_DEVICE_MUX_REG_BIT_1,
    MUXED_DEVICE_MUX_REG_BIT_2,
    QSFP_IO_EXPANDER_I2C_ADDR,
    QSFP_I2C_ADDR,
    FW_IF_MUXED_DEVICE_HW_LEVEL_MEMORY_MAP
};                                                                             /* QSFP 3 */
static FW_IF_MUXED_DEVICE_CFG xQsfpCfg4 =
{
    FW_IF_DEVICE_QSFP,
    QSFP_POWER_IO_EXPANDER_I2C_ADDR,
    QSFP_4_REG_BIT_OFFSET,
    MUXED_DEVICE_MUX_2_ADDR,
    {
        MUXED_DEVICE_MUX_1_ADDR, MUXED_DEVICE_MUX_3_ADDR
    },
    MUXED_DEVICE_MUX_REG_BIT_3,
    MUXED_DEVICE_MUX_REG_BIT_4,
    QSFP_IO_EXPANDER_I2C_ADDR,
    QSFP_I2C_ADDR,
    FW_IF_MUXED_DEVICE_HW_LEVEL_MEMORY_MAP
};                                                                             /* QSFP 4 */
static FW_IF_MUXED_DEVICE_CFG xDimmCfg =
{
    FW_IF_DEVICE_DIMM,
    0,
    0,
    MUXED_DEVICE_MUX_3_ADDR,
    {
        MUXED_DEVICE_MUX_1_ADDR, MUXED_DEVICE_MUX_2_ADDR
    },
    MUXED_DEVICE_MUX_REG_BIT_4,
    0,
    0,
    DIMM_I2C_ADDR,
    FW_IF_MUXED_DEVICE_HW_LEVEL_MEMORY_MAP
};                                                                             /* DIMM */
static FW_IF_GCQ_CFG xGcqCfg =
{
    ( uint64_t )HAL_BASE_LOGIC_GCQ_M2R_S01_AXI_BASEADDR,
    FW_IF_GCQ_MODE_PRODUCER,
    FW_IF_GCQ_INTERRUPT_MODE_NONE,
    ( uint64_t )HAL_RPU_RING_BUFFER_BASE,
    HAL_RPU_RING_BUFFER_LEN,
    AMI_PROXY_RESPONSE_SIZE,
    AMI_PROXY_REQUEST_SIZE,
    ""
};

static FW_IF_GCQ_INIT_CFG myGcqIf =
{
    NULL
};

static FW_IF_OSPI_CFG xOspiCfg =
{
    OSPI_RPU_BASE_ADDRESS,
    OSPI_RPU_LENGTH,
    TRUE,                                                                      /* Enable erase before write */
    FW_IF_OSPI_STATE_INIT
};

static FW_IF_EMMC_CFG xEmmcCfg =
{
    0,
    "EmmcCfg",
    EMMC_RPU_BASE_ADDRESS,
    EMMC_RPU_LENGTH,
    FW_IF_EMMC_STATE_ERROR
};

static FW_IF_OSPI_INIT_CFG myOspiIf =
{
    HAL_OSPI_0_DEVICE_ID,
    OSPI_PAGE_SIZE
};

static FW_IF_EMMC_INIT_CFG myEmmcIf =
{
    "EmmcIfCfg",
    HAL_EMMC_DEVICE_ID
};

static FW_IF_MUXED_DEVICE_INIT_CFG myQsfpIf =
{
    "QsfpIfCfg",
    HAL_I2C_BUS_1_DEVICE_ID
};

/******************************************************************************/
/* Private Function declarations                                              */
/******************************************************************************/

/**
 * @brief   Read from Tca6416a register via i2c.
 *
 * @param   ucI2cNum         I2c Bus Number
 * @param   ucSlaveAddr      I2c Slave Addr
 * @param   ucRegister       I2c Slave register
 * @param   pucRegisterValue Pointer to register value
 *
 * @return  OK               Register value read successfully
 *          ERROR            Error reading register value
 *
 */
static uint8_t ucTca6416aRegisterRead( uint8_t ucI2cNum,
                                       uint8_t ucSlaveAddr,
                                       uint8_t ucRegister,
                                       uint8_t *pucRegisterValue );

/**
 * @brief   Write to Tca6416a register via i2c.
 *
 * @param   ucI2cNum         I2c Bus Number
 * @param   ucSlaveAddr      I2c Slave Addr
 * @param   ucRegister       I2c Slave register
 * @param   ucRegisterValue  Register value to write
 *
 * @return  OK               Register value written successfully
 *          ERROR            Error writting register value
 *
 */
static uint8_t ucTca6416aRegisterWrite( uint8_t ucI2cNum,
                                        uint8_t ucSlaveAddr,
                                        uint8_t ucRegister,
                                        uint8_t ucRegisterValue );

/**
 * @brief   Enable SMBus PCIe Link.
 *
 * @return  OK               SMBus PCIe Link enabled successfully
 *          ERROR            Error enabling SMBus PCIe Link
 *
 */
static uint8_t ucEnableSMBusPcieLink( void );


/******************************************************************************/
/* Private Function implementations                                           */
/******************************************************************************/

/**
 * @brief   Read from Tca6416a register via i2c.
 */
uint8_t ucTca6416aRegisterRead( uint8_t ucI2cNum, uint8_t ucSlaveAddr, uint8_t ucRegister, uint8_t *pucRegisterValue )
{
    uint8_t ucStatus = ERROR;
    uint8_t pucSendData[ TCA6416AR_READ_BUFF_SIZE ] =
    {
        0
    };

    if( NULL != pucRegisterValue )
    {
        pucSendData[ 0 ] = ucRegister;

        ucStatus = iI2C_SendRecv( ucI2cNum,
                                  ucSlaveAddr,
                                  pucSendData,
                                  TCA6416AR_READ_BUFF_SIZE,
                                  pucRegisterValue,
                                  TCA6416AR_READ_BYTES_TO_RECEIVE );
    }

    return ucStatus;
}

/**
 * @brief   Write to Tca6416a register via i2c.
 */
uint8_t ucTca6416aRegisterWrite( uint8_t ucI2cNum, uint8_t ucSlaveAddr, uint8_t ucRegister, uint8_t ucRegisterValue )
{
    uint8_t ucStatus = ERROR;
    uint8_t pucSendData[ TCA6416AR_WRITE_BUFF_SIZE ] =
    {
        0
    };

    pucSendData[ 0 ] = ucRegister;
    pucSendData[ 1 ] = ucRegisterValue;

    ucStatus = iI2C_Send( ucI2cNum, ucSlaveAddr, pucSendData, TCA6416AR_WRITE_BUFF_SIZE );

    return ucStatus;
}

/**
 * @brief   Enable SMBus PCIe Link.
 */
uint8_t ucEnableSMBusPcieLink( void )
{
    uint8_t ucStatus        = ERROR;
    uint8_t ucI2cNum        = HAL_I2C_BUS_0_DEVICE_ID;
    uint8_t ucRegisterValue = 0;

    /* Read Configuration 0 Register - Command Byte 06 */
    ucStatus = ucTca6416aRegisterRead( ucI2cNum, TCA6416AR_ADDRESS, TCA6416AR_CONFIGURATION_0, &ucRegisterValue );

    if( OK == ucStatus )
    {
        /* Write Configuration 0 Register setting bit 3 to 0 - Command Byte 06 */
        ucRegisterValue = ( ucRegisterValue & ~( TCA6416AR_BIT_3 ) );
        ucStatus        = ucTca6416aRegisterWrite( ucI2cNum,
                                                   TCA6416AR_ADDRESS,
                                                   TCA6416AR_CONFIGURATION_0,
                                                   ucRegisterValue );

        if( OK == ucStatus )
        {
            /* Read Output 0 Register - Command Byte 02 */
            ucStatus = ucTca6416aRegisterRead( ucI2cNum, TCA6416AR_ADDRESS, TCA6416AR_OUTPUT_PORT_0, &ucRegisterValue );

            if( OK == ucStatus )
            {
                /* Write Output 0 Register setting bit 3 to 1 - Command Byte 02 */
                ucRegisterValue = ( ucRegisterValue | ( TCA6416AR_BIT_3 ) );
                ucStatus        = ucTca6416aRegisterWrite( ucI2cNum,
                                                           TCA6416AR_ADDRESS,
                                                           TCA6416AR_OUTPUT_PORT_0,
                                                           ucRegisterValue );
            }
        }
    }

    return ucStatus;
}


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/**
 * @brief   Initialise FAL layer
 */
int iFAL_Initialise( uint64_t *pullAmcInitStatus )
{
    int     iStatus                         = OK;
    int     iMuxedDeviceStatus              = OK;
    uint8_t ucUuidSize                      = 0;
    uint8_t pucUuid[ FW_IF_SMBUS_UDID_LEN ] =
    {
        0
    };

    if( NULL != pullAmcInitStatus )
    {
        if( AMC_CFG_I2C_INITIALISED == ( *pullAmcInitStatus & AMC_CFG_I2C_INITIALISED ) )
        {
            /* Enable SMBus PCIe link */
            if( OK == ucEnableSMBusPcieLink() )
            {
                PLL_LOG( FAL_PROFILE_NAME, "PCIe SMBus link enabled\n\r" );
                *pullAmcInitStatus |= AMC_CFG_SMBUS_PCIE_LINK_INITIALISED;
            }
            else
            {
                PLL_ERR( FAL_PROFILE_NAME, "Error enabling PCIe SMBus link \n\r" );
                iStatus = ERROR;
            }
        }

        /* Init the Muxed Device FAL */
        if( AMC_CFG_I2C_INITIALISED == ( *pullAmcInitStatus & AMC_CFG_I2C_INITIALISED ) )
        {
            if( 0 != MAX_NUM_EXTERNAL_DEVICES_AVAILABLE )
            {
                if( FW_IF_ERRORS_NONE == ulFW_IF_MUXED_DEVICE_Init( &myQsfpIf ) )
                {
                    PLL_DBG( FAL_PROFILE_NAME, "Muxed Device FAL initialised OK\r\n" );
                    *pullAmcInitStatus |= AMC_CFG_MUXED_DEVICE_FAL_INITIALISED;
                }
                else
                {
                    PLL_ERR( FAL_PROFILE_NAME, "Error initialising Muxed Device FAL\r\n" );
                    iStatus = ERROR;
                }
            }
            else
            {
                *pullAmcInitStatus |= AMC_CFG_MUXED_DEVICE_FAL_INITIALISED;
            }
        }

        /* Init the GCQ FAL */
        PLL_LOG( FAL_PROFILE_NAME, "GCQ service: starting\r\n" );
        if( FW_IF_ERRORS_NONE == ulFW_IF_GCQ_Init( &myGcqIf ) )
        {
            PLL_DBG( FAL_PROFILE_NAME, "GCQ FAL initialised OK\r\n" );
            PLL_LOG( FAL_PROFILE_NAME, "GCQ service: ready\r\n" );
            *pullAmcInitStatus |= AMC_CFG_GCQ_FAL_INITIALISED;
        }
        else
        {
            PLL_ERR( FAL_PROFILE_NAME, "Error initialising GCQ FAL\r\n" );
            PLL_LOG( FAL_PROFILE_NAME, "GCQ service: error initialising\r\n" );
            iStatus = ERROR;
        }

        /* Init the OPSI FAL */
        PLL_LOG( FAL_PROFILE_NAME, "OSPI driver: starting\r\n" );
        if( FW_IF_ERRORS_NONE == ulFW_IF_OSPI_Init( &myOspiIf ) )
        {
            PLL_DBG( FAL_PROFILE_NAME, "OSPI FAL initialised OK\r\n" );
            PLL_LOG( FAL_PROFILE_NAME, "OSPI driver: ready\r\n" );
            *pullAmcInitStatus |= AMC_CFG_OSPI_FAL_INITIALISED;
        }
        else
        {
            PLL_ERR( FAL_PROFILE_NAME, "Error initialising OSPI FAL\r\n" );
            PLL_LOG( FAL_PROFILE_NAME, "OSPI driver: error initialising\r\n" );
            iStatus = ERROR;
        }

        /* Init the eMMC FAL */
        if( FW_IF_ERRORS_NONE == ulFW_IF_EMMC_Init( &myEmmcIf ) )
        {
            PLL_DBG( FAL_PROFILE_NAME, "eMMC FAL initialised OK\r\n" );
            *pullAmcInitStatus |= AMC_CFG_EMMC_FAL_INITIALISED;
        }
        else
        {
            PLL_ERR( FAL_PROFILE_NAME, "Error initialising eMMC FAL\r\n" );
            iStatus = ERROR;
        }

        if( AMC_CFG_MUXED_DEVICE_FAL_INITIALISED == ( *pullAmcInitStatus & AMC_CFG_MUXED_DEVICE_FAL_INITIALISED ) )
        {
            if( 0 != MAX_NUM_EXTERNAL_DEVICES_AVAILABLE )
            {
                if( FW_IF_ERRORS_NONE == ulFW_IF_MUXED_DEVICE_Create( &xQsfpIf1, &xQsfpCfg1 ) )
                {
                    PLL_DBG( FAL_PROFILE_NAME, "ulFW_IF_MUXED_DEVICE_Create created OK\r\n" );
                }
                else
                {
                    PLL_ERR( FAL_PROFILE_NAME, "Error creating QSFP FAL handle\r\n" );
                    iStatus            = ERROR;
                    iMuxedDeviceStatus = ERROR;
                }

                if( FW_IF_ERRORS_NONE == ulFW_IF_MUXED_DEVICE_Create( &xQsfpIf2, &xQsfpCfg2 ) )
                {
                    PLL_DBG( FAL_PROFILE_NAME, "ulFW_IF_MUXED_DEVICE_Create created OK\r\n" );
                }
                else
                {
                    PLL_ERR( FAL_PROFILE_NAME, "Error creating QSFP FAL handle\r\n" );
                    iStatus            = ERROR;
                    iMuxedDeviceStatus = ERROR;
                }

                if( FW_IF_ERRORS_NONE == ulFW_IF_MUXED_DEVICE_Create( &xQsfpIf3, &xQsfpCfg3 ) )
                {
                    PLL_DBG( FAL_PROFILE_NAME, "ulFW_IF_MUXED_DEVICE_Create created OK\r\n" );
                }
                else
                {
                    PLL_ERR( FAL_PROFILE_NAME, "Error creating QSFP FAL handle\r\n" );
                    iStatus            = ERROR;
                    iMuxedDeviceStatus = ERROR;
                }

                if( FW_IF_ERRORS_NONE == ulFW_IF_MUXED_DEVICE_Create( &xQsfpIf4, &xQsfpCfg4 ) )
                {
                    PLL_DBG( FAL_PROFILE_NAME, "ulFW_IF_MUXED_DEVICE_Create created OK\r\n" );
                }
                else
                {
                    PLL_ERR( FAL_PROFILE_NAME, "Error creating QSFP FAL handle\r\n" );
                    iStatus            = ERROR;
                    iMuxedDeviceStatus = ERROR;
                }

                if( FW_IF_ERRORS_NONE == ulFW_IF_MUXED_DEVICE_Create( &xDimmIf, &xDimmCfg ) )
                {
                    PLL_DBG( FAL_PROFILE_NAME, "ulFW_IF_MUXED_DEVICE_Create created OK\r\n" );
                }
                else
                {
                    PLL_ERR( FAL_PROFILE_NAME, "Error creating DIMM FAL handle\r\n" );
                    iStatus            = ERROR;
                    iMuxedDeviceStatus = ERROR;
                }

                if( OK == iMuxedDeviceStatus )
                {
                    *pullAmcInitStatus |= AMC_CFG_MUXED_DEVICE_FAL_CREATED;
                }
            }
            else
            {
                *pullAmcInitStatus |= AMC_CFG_MUXED_DEVICE_FAL_CREATED;
            }
        }

        /* Create instance of the GCQ based on the global configuration */
        if( AMC_CFG_GCQ_FAL_INITIALISED == ( *pullAmcInitStatus & AMC_CFG_GCQ_FAL_INITIALISED ) )
        {
            if( FW_IF_ERRORS_NONE == ulFW_IF_GCQ_Create( &xGcqIf, &xGcqCfg ) )
            {
                PLL_DBG( FAL_PROFILE_NAME, "GCQ created OK\r\n" );
                *pullAmcInitStatus |= AMC_CFG_GCQ_FAL_CREATED;
            }
            else
            {
                PLL_ERR( FAL_PROFILE_NAME, "Error creating GCQ\r\n" );
                iStatus = ERROR;
            }
        }

        /* Create instance of the OSPI based on the global configuration */
        if( AMC_CFG_OSPI_FAL_INITIALISED == ( *pullAmcInitStatus & AMC_CFG_OSPI_FAL_INITIALISED ) )
        {
            if( FW_IF_ERRORS_NONE == ulFW_IF_OSPI_Create( &xOspiIf, &xOspiCfg ) )
            {
                PLL_DBG( FAL_PROFILE_NAME, "OSPI created OK\r\n" );
                *pullAmcInitStatus |= AMC_CFG_OSPI_FAL_CREATED;
            }
            else
            {
                PLL_ERR( FAL_PROFILE_NAME, "Error creating OSPI\r\n" );
                iStatus = ERROR;
            }
        }

        /* Create instance of the eMMC based on the global configuration */
        if( AMC_CFG_EMMC_FAL_INITIALISED == ( *pullAmcInitStatus & AMC_CFG_EMMC_FAL_INITIALISED ) )
        {
            if( FW_IF_ERRORS_NONE == ulFW_IF_EMMC_Create( &xEmmcIf, &xEmmcCfg ) )
            {
                PLL_DBG( FAL_PROFILE_NAME, "eMMC created OK\r\n" );
                *pullAmcInitStatus |= AMC_CFG_EMMC_FAL_CREATED;
            }
            else
            {
                PLL_ERR( FAL_PROFILE_NAME, "Error creating eMMC\r\n" );
                iStatus = ERROR;
            }
        }

        /* Get UUID */
        if( AMC_CFG_EEPROM_INITIALISED == ( *pullAmcInitStatus & AMC_CFG_EEPROM_INITIALISED ) )
        {
            /* If EEPROM is ok use the UUID from it */
            if( OK == iEEPROM_GetUuid( pucUuid, &ucUuidSize ) )
            {
                if( FW_IF_SMBUS_UDID_LEN != ucUuidSize )
                {
                    PLL_ERR( FAL_PROFILE_NAME, "Error UUID size incorrect\n\r" );
                    iStatus = ERROR;
                }
            }
            else
            {
                PLL_ERR( FAL_PROFILE_NAME, "Error getting UUID\r\n" );
                iStatus = ERROR;
            }
        }
    }
    else
    {
        iStatus = ERROR;
    }

    return iStatus;

}
