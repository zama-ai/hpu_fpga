/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains the function declarations for accessing the
 * manufacturing eeprom.
 *
 * @file eeprom.h
 *
 */

#ifndef _EEPROM_H_
#define _EEPROM_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define EEPROM_MAX_FIELD_SIZE   ( 40 )
#define EEPROM_MAX_DATA_SIZE    ( 255 )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  EEPROM_CFG_TYPE
 * @brief   The EEPROM device configuration
 */
typedef struct EEPROM_CFG
{
    uint8_t ucEepromI2cBus;             /* I2C Bus number of the device*/
    uint8_t ucEepromSlaveAddress;       /* I2C Slave address of the device */
    uint8_t ucEepromAddressSize;        /* The number of bytes in the EEPROM register address */
    uint8_t ucEepromPageSize;           /* Eeprom page size */
    uint8_t ucEepromNumPages;           /* The number of page in Eeprom */
    uint8_t ucEepromDeviceIdAddress;    /* I2C Slave address for reaching the device id register */
    uint8_t ucEepromDeviceIdRegister;   /* Device ID register */
    uint16_t usEepromDeviceId;          /* The device id of eeprom */

} EEPROM_CFG;

/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    EEPROM_VERSION
 * @brief   enumeration for all the supported EEPROM versions
 */
typedef enum EEPROM_VERSION
{
    EEPROM_VERSION_3_0 = 30,
    EEPROM_VERSION_3_1,
    EEPROM_VERSION_4_0 = 40,

    EEPROM_VERSION_MAX

} EEPROM_VERSION;


/******************************************************************************/
/* Driver External APIs                                                       */
/******************************************************************************/

/**
 * @brief   Initialises the EEPROM driver.
 *
 * @param   xEepromVersion                The expected EEPROM Version for this product
 * @param   pxEepromCfg                   The pointer of EEPROM configuration struct
 *
 * @return  OK if successful, else ERROR.
 */
int iEEPROM_Initialise( EEPROM_VERSION xEepromVersion, EEPROM_CFG *pxEepromCfg );

/**
 * @brief   Read the EEPROM Version
 *
 * @param   pucField       Pointer to store the EEPROM Version in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 * 
 * @return  OK             EEPROM Version read successfully
 *          ERROR          EEPROM Version not read successfully
 * 
 */
int iEEPROM_GetEepromVersion( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Product Name
 *
 * @param   pucField       Pointer to store the Product Name in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 * 
 * @return  OK             Product Name read successfully
 *          ERROR          Product Name not read successfully
 * 
 */
int iEEPROM_GetProductName( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Product Revision
 *
 * @param   pucField       Pointer to store the Product Revision in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 * 
 * @return  OK             Product Revision read successfully
 *          ERROR          Product Revision not read successfully
 * 
 */
int iEEPROM_GetProductRevision( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the board serial number
 *
 * @param   pucField       Pointer to store the Serial number in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             Serial number read successfully
 *          ERROR          Serial number not read successfully
 * 
 */
int iEEPROM_GetSerialNumber( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the number of MAC addresses
 *
 * @param   pucField       Pointer to store the MAC address count in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             MAC address count read successfully
 *          ERROR          MAC address count not read successfully
 * 
 */
int iEEPROM_GetMacAddressCount( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the First MAC Address
 *
 * @param   pucField       Pointer to store the First MAC Address in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             First MAC Address read successfully
 *          ERROR          First MAC Address not read successfully
 * 
 */
int iEEPROM_GetFirstMacAddress( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Active/Passive state 
 *
 * @param   pucField       Pointer to store the Active/Passive State in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             Active/Passive State read successfully
 *          ERROR          Active/Passive State not read successfully
 * 
 */
int iEEPROM_GetActiveState( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Config Mode
 *
 * @param   pucField       Pointer to store the Config Mode in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             Config Mode read successfully
 *          ERROR          Config Mode not read successfully
 * 
 */
int iEEPROM_GetConfigMode( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Manufacturing Date
 *
 * @param   pucField       Pointer to store the Manufacturing Date in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             Manufacturing Date read successfully
 *          ERROR          Manufacturing Date not read successfully
 * 
 */
int iEEPROM_GetManufacturingDate( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Part Number
 *
 * @param   pucField       Pointer to store the Part Number in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             Part Number read successfully
 *          ERROR          Part Number not read successfully
 * 
 */
int iEEPROM_GetPartNumber( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Manufacturer Part Number
 *
 * @param   pucField       Pointer to store the Part Number in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             Part Number read successfully
 *          ERROR          Part Number not read successfully
 *
 */
int iEEPROM_GetMfgPartNumber( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the UUID
 *
 * @param   pucField       Pointer to store the UUID in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             UUID read successfully
 *          ERROR          UUID not read successfully
 * 
 */
int iEEPROM_GetUuid( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the PCIe ID
 *
 * @param   pucField       Pointer to store the PCIe ID in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             PCIe ID read successfully
 *          ERROR          PCIe ID not read successfully
 * 
 */
int iEEPROM_GetPcieId( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Max Power Mode
 *
 * @param   pucField       Pointer to store the Max Power in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             Max Power Mode read successfully
 *          ERROR          Max Power Mode not read successfully
 * 
 */
int iEEPROM_GetMaxPowerMode( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Memory Size
 *
 * @param   pucField       Pointer to store the Memory Size in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             Memory Size read successfully
 *          ERROR          Memory Size not read successfully
 * 
 */
int iEEPROM_GetMemorySize( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the OEM ID
 *
 * @param   pucField       Pointer to store the OEM ID in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             OEM ID read successfully
 *          ERROR          OEM ID not read successfully
 * 
 */
int iEEPROM_GetOemId( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Capability
 *
 * @param   pucField       Pointer to store the Capability in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 * 
 * @return  OK             Capability read successfully
 *          ERROR          Capability not read successfully
 * 
 */
int iEEPROM_GetCapability( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read the Config Mode
 *
 * @param   pucField       Pointer to store the Config Mode in
 * @param   pucSizeBytes   The number of bytes used to store the returned value
 *
 * @return  OK             Config Mode read successfully
 *          ERROR          Config Mode not read successfully
 * 
 */
int iEEPROM_GetConfigMode( uint8_t *pucField, uint8_t *pucSizeBytes );

/**
 * @brief   Read raw data
 *
 * @param   pucData        Buffer to store the raw data in
 * @param   ucSizeBytes    The number of bytes allocated to the buffer
 * @param   ucEepromAddr   Address in EEPROM to read data from
 *
 * @return  OK             Data read successfully
 *          ERROR          Data not read successfully
 *
 */
int iEEPROM_ReadRawValue( uint8_t *pucData, uint8_t ucSizeBytes, uint8_t ucEepromAddr );

/**
 * @brief   Write raw data
 *
 * @param   pucData        Buffer of raw data to write
 * @param   ucSizeBytes    The number of bytes to write from the buffer
 * @param   ucEepromAddr   Address in EEPROM to write data to
 *
 * @return  OK             Data written successfully
 *          ERROR          Data not written successfully
 *
 */
int iEEPROM_WriteRawValue( uint8_t *pucData, uint8_t ucSizeBytes, uint8_t ucEepromAddr );

/**
 * @brief   Print all the stats gathered by the eeprom driver
 *
 * @return  OK                  Stats retrieved from driver successfully
 *          ERROR               Stats not retrieved successfully
 * 
 */
int iEEPROM_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the eeprom driver
 *
 * @return  OK                  Stats cleared successfully
 *          ERROR               Stats not cleared successfully
 * 
 */
int iEEPROM_ClearStatistics( void );

/**
 * @brief   Display all the EEPROM fields
 *
 * @return  OK                  Stats cleared successfully
 *          ERROR               Stats not cleared successfully
 * 
 */
int iEEPROM_DisplayEepromValues( void );

#endif
