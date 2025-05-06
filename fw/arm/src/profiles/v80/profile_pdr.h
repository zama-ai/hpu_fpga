/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the PLDM PDR profile for the V80
 *
 * @file profile_pdr.h
 *
 */

#ifndef _PROFILE_PDR_H_
#define _PROFILE_PDR_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "util.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define TOTAL_PDR_TEMPERATURE          ( 6 )
#define TOTAL_PDR_VOLTAGE              ( 9 )
#define TOTAL_PDR_CURRENT              ( 8 )
#define TOTAL_PDR_POWER                ( 4 )
#define TOTAL_PDR_NUMERIC_ASCI_SENSORS ( TOTAL_PDR_TEMPERATURE + TOTAL_PDR_VOLTAGE + TOTAL_PDR_CURRENT + \
                                         TOTAL_PDR_POWER )

#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD ( 68 )
#define LOGICAL_PLDM_ENTITY_ADDIN_CARD  ( 32835 )

/* Macros to set bits for 'ucRangeFieldSupport' field in PDR */

#define NORMAL_MIN_MAX  ( 0x3 << 1 )
#define RATED_MIN_MAX   ( 0x3 << 3 )
#define HIGH_THRESHOLDS ( 0x5 << 3 )
#define LOW_THRESHOLDS  ( 0x5 << 4 )
#define NOMINAL_VALUE   ( 0x1 )

/* Macros to set bits for 'ucSupportedThresholds' field in PDR */

#define HAS_LOW_THRESHOLDS  ( 0x7 << 3 )
#define HAS_HIGH_THRESHOLDS ( 0x7 )

/* AMC Device ID Defines */

#define PCB_DEVICE_ID              ( 12 )
#define DEVICE_DEVICE_ID           ( 13 )
#define VR_VCCINT_DEVICE_ID        ( 14 )
#define QSFP_MODULE_0_DEVICE_ID    ( 15 )
#define QSFP_MODULE_1_DEVICE_ID    ( 16 )
#define QSFP_MODULE_2_DEVICE_ID    ( 17 )
#define QSFP_MODULE_3_DEVICE_ID    ( 18 )
#define DIMM_DEVICE_ID             ( 43 )
#define VR_1V2_VCC_HBM_DEVICE_ID   ( 20 )
#define VR_12V_AUX1_DEVICE_ID      ( 21 )
#define VR_12V_AUX2_DEVICE_ID      ( 22 )
#define VR_1V2_VCCO_DIMM_DEVICE_ID ( 23 )
#define VR_3V3_PEX_DEVICE_ID       ( 24 )
#define VR_12V_PEX_DEVICE_ID       ( 25 )
#define VR_3V3_QSFP_DEVICE_ID      ( 34 )
#define VR_1V5_VCCAUX_DEVICE_ID    ( 36 )
#define VR_1V2_GTXAVTT_DEVICE_ID   ( 38 )
#define VR_0V88_VCC_CPM5_DEVICE_ID ( 41 )

/* AMC Reading Channel Defines */

#define PCB_TEMPERATURE_READING_CHANNEL              ( 0 )
#define DEVICE_TEMPERATURE_READING_CHANNEL           ( 0 )
#define VR_VCCINT_TEMPERATURE_READING_CHANNEL        ( 0 )
#define VR_VCCINT_VOLTAGE_READING_CHANNEL            ( 1 )
#define VR_VCCINT_CURRENT_READING_CHANNEL            ( 2 )
#define VR_1V2_VCC_HBM_TEMPERATURE_READING_CHANNEL   ( 0 )
#define VR_1V2_VCC_HBM_VOLTAGE_READING_CHANNEL       ( 1 )
#define VR_1V2_VCC_HBM_CURRENT_READING_CHANNEL       ( 2 )
#define VR_12V_AUX1_VOLTAGE_READING_CHANNEL          ( 1 )
#define VR_12V_AUX1_CURRENT_READING_CHANNEL          ( 2 )
#define VR_12V_AUX1_POWER_READING_CHANNEL            ( 3 )
#define VR_12V_AUX2_VOLTAGE_READING_CHANNEL          ( 1 )
#define VR_12V_AUX2_CURRENT_READING_CHANNEL          ( 2 )
#define VR_12V_AUX2_POWER_READING_CHANNEL            ( 3 )
#define VR_3V3_PEX_VOLTAGE_READING_CHANNEL           ( 1 )
#define VR_3V3_PEX_CURRENT_READING_CHANNEL           ( 2 )
#define VR_3V3_PEX_POWER_READING_CHANNEL             ( 3 )
#define VR_12V_PEX_VOLTAGE_READING_CHANNEL           ( 1 )
#define VR_12V_PEX_CURRENT_READING_CHANNEL           ( 2 )
#define VR_12V_PEX_POWER_READING_CHANNEL             ( 3 )
#define VR_1V5_VCCAUX_VOLTAGE_READING_CHANNEL        ( 1 )
#define VR_1V2_GTXAVTT_TEMPERATURE_READING_CHANNEL   ( 0 )
#define VR_1V2_GTXAVTT_VOLTAGE_READING_CHANNEL       ( 1 )
#define VR_1V2_GTXAVTT_CURRENT_READING_CHANNEL       ( 2 )
#define VR_0V88_VCC_CPM5_TEMPERATURE_READING_CHANNEL ( 0 )
#define VR_0V88_VCC_CPM5_VOLTAGE_READING_CHANNEL     ( 1 )
#define VR_0V88_VCC_CPM5_CURRENT_READING_CHANNEL     ( 2 )

/* PLDM Type 2 (DSP0248) Numeric Sensor ID Defines */

#define PCB_TEMPERATURE_SENSOR_ID              ( PCB_DEVICE_ID + ( PCB_TEMPERATURE_READING_CHANNEL << 8 ) )
#define DEVICE_TEMPERATURE_SENSOR_ID           ( DEVICE_DEVICE_ID + ( DEVICE_TEMPERATURE_READING_CHANNEL << 8 ) )
#define VR_VCCINT_TEMPERATURE_SENSOR_ID        ( VR_VCCINT_DEVICE_ID + ( VR_VCCINT_TEMPERATURE_READING_CHANNEL << 8 ) )
#define VR_VCCINT_VOLTAGE_SENSOR_ID            ( VR_VCCINT_DEVICE_ID + ( VR_VCCINT_VOLTAGE_READING_CHANNEL << 8 ) )
#define VR_VCCINT_CURRENT_SENSOR_ID            ( VR_VCCINT_DEVICE_ID + ( VR_VCCINT_CURRENT_READING_CHANNEL << 8 ) )
#define VR_1V2_VCC_HBM_TEMPERATURE_SENSOR_ID   ( VR_1V2_VCC_HBM_DEVICE_ID + \
                                                 ( VR_1V2_VCC_HBM_TEMPERATURE_READING_CHANNEL << 8 ) )
#define VR_1V2_VCC_HBM_VOLTAGE_SENSOR_ID       ( VR_1V2_VCC_HBM_DEVICE_ID + ( VR_1V2_VCC_HBM_VOLTAGE_READING_CHANNEL << \
                                                                              8 ) )
#define VR_1V2_VCC_HBM_CURRENT_SENSOR_ID       ( VR_1V2_VCC_HBM_DEVICE_ID + ( VR_1V2_VCC_HBM_CURRENT_READING_CHANNEL << \
                                                                              8 ) )
#define VR_12V_AUX1_VOLTAGE_SENSOR_ID          ( VR_12V_AUX1_DEVICE_ID + ( VR_12V_AUX1_VOLTAGE_READING_CHANNEL << 8 ) )
#define VR_12V_AUX1_CURRENT_SENSOR_ID          ( VR_12V_AUX1_DEVICE_ID + ( VR_12V_AUX1_CURRENT_READING_CHANNEL << 8 ) )
#define VR_12V_AUX1_POWER_SENSOR_ID            ( VR_12V_AUX1_DEVICE_ID + ( VR_12V_AUX1_POWER_READING_CHANNEL << 8 ) )
#define VR_12V_AUX2_VOLTAGE_SENSOR_ID          ( VR_12V_AUX2_DEVICE_ID + ( VR_12V_AUX2_VOLTAGE_READING_CHANNEL << 8 ) )
#define VR_12V_AUX2_CURRENT_SENSOR_ID          ( VR_12V_AUX2_DEVICE_ID + ( VR_12V_AUX2_CURRENT_READING_CHANNEL << 8 ) )
#define VR_12V_AUX2_POWER_SENSOR_ID            ( VR_12V_AUX2_DEVICE_ID + ( VR_12V_AUX2_POWER_READING_CHANNEL << 8 ) )
#define VR_3V3_PEX_VOLTAGE_SENSOR_ID           ( VR_3V3_PEX_DEVICE_ID + ( VR_3V3_PEX_VOLTAGE_READING_CHANNEL << 8 ) )
#define VR_3V3_PEX_CURRENT_SENSOR_ID           ( VR_3V3_PEX_DEVICE_ID + ( VR_3V3_PEX_CURRENT_READING_CHANNEL << 8 ) )
#define VR_3V3_PEX_POWER_SENSOR_ID             ( VR_3V3_PEX_DEVICE_ID + ( VR_3V3_PEX_POWER_READING_CHANNEL << 8 ) )
#define VR_12V_PEX_VOLTAGE_SENSOR_ID           ( VR_12V_PEX_DEVICE_ID + ( VR_12V_PEX_VOLTAGE_READING_CHANNEL << 8 ) )
#define VR_12V_PEX_CURRENT_SENSOR_ID           ( VR_12V_PEX_DEVICE_ID + ( VR_12V_PEX_CURRENT_READING_CHANNEL << 8 ) )
#define VR_12V_PEX_POWER_SENSOR_ID             ( VR_12V_PEX_DEVICE_ID + ( VR_12V_PEX_POWER_READING_CHANNEL << 8 ) )
#define VR_1V5_VCCAUX_VOLTAGE_SENSOR_ID        ( VR_1V5_VCCAUX_DEVICE_ID + ( VR_1V5_VCCAUX_VOLTAGE_READING_CHANNEL << \
                                                                             8 ) )
#define VR_1V2_GTXAVTT_TEMPERATURE_SENSOR_ID   ( VR_1V2_GTXAVTT_DEVICE_ID + \
                                                 ( VR_1V2_GTXAVTT_TEMPERATURE_READING_CHANNEL << 8 ) )
#define VR_1V2_GTXAVTT_VOLTAGE_SENSOR_ID       ( VR_1V2_GTXAVTT_DEVICE_ID + ( VR_1V2_GTXAVTT_VOLTAGE_READING_CHANNEL << \
                                                                              8 ) )
#define VR_1V2_GTXAVTT_CURRENT_SENSOR_ID       ( VR_1V2_GTXAVTT_DEVICE_ID + ( VR_1V2_GTXAVTT_CURRENT_READING_CHANNEL << \
                                                                              8 ) )
#define VR_0V88_VCC_CPM5_TEMPERATURE_SENSOR_ID ( VR_0V88_VCC_CPM5_DEVICE_ID + \
                                                 ( VR_0V88_VCC_CPM5_TEMPERATURE_READING_CHANNEL << 8 ) )
#define VR_0V88_VCC_CPM5_VOLTAGE_SENSOR_ID     ( VR_0V88_VCC_CPM5_DEVICE_ID + \
                                                 ( VR_0V88_VCC_CPM5_VOLTAGE_READING_CHANNEL << 8 ) )
#define VR_0V88_VCC_CPM5_CURRENT_SENSOR_ID     ( VR_0V88_VCC_CPM5_DEVICE_ID + \
                                                 ( VR_0V88_VCC_CPM5_CURRENT_READING_CHANNEL << 8 ) )


/* PLDM Type 2 (DSP2061&DSP0241) Entity Type and Number */

#define LOGICAL_PLDM_ENTITY_ADDIN_CARD_1_DEVICE_TEMPERATURE             ( 1 )
#define LOGICAL_PLDM_ENTITY_ADDIN_CARD_2_VR_12V_AUX1_CURRENT            ( 2 )
#define LOGICAL_PLDM_ENTITY_ADDIN_CARD_3_VR_12V_AUX1_POWER              ( 3 )
#define LOGICAL_PLDM_ENTITY_ADDIN_CARD_4_VR_1V5_VCCAUX_VOLTAGE          ( 4 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_1_PCB_TEMPERATURE               ( 1 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_2_VR_VCCINT_TEMPERATURE         ( 2 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_3_VR_VCCINT_VOLTAGE             ( 3 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_4_VR_VCCINT_CURRENT             ( 4 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_10_VR_1V2_VCC_HBM_TEMPERATURE   ( 10 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_11_VR_1V2_VCC_HBM_VOLTAGE       ( 11 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_12_VR_1V2_VCC_HBM_CURRENT       ( 12 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_13_VR_12V_AUX1_VOLTAGE          ( 13 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_14_VR_12V_AUX2_VOLTAGE          ( 14 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_15_VR_12V_AUX2_CURRENT          ( 15 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_16_VR_12V_AUX2_POWER            ( 16 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_20_VR_3V3_PEX_VOLTAGE           ( 20 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_21_VR_3V3_PEX_CURRENT           ( 21 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_22_VR_3V3_PEX_POWER             ( 22 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_23_VR_12V_PEX_VOLTAGE           ( 23 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_24_VR_12V_PEX_CURRENT           ( 24 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_25_VR_12V_PEX_POWER             ( 25 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_29_VR_1V2_GTXAVTT_TEMPERATURE   ( 29 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_30_VR_1V2_GTXAVTT_VOLTAGE       ( 30 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_31_VR_1V2_GTXAVTT_CURRENT       ( 31 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_32_VR_0V88_VCC_CPM5_TEMPERATURE ( 32 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_33_VR_0V88_VCC_CPM5_VOLTAGE     ( 33 )
#define PHYSICAL_PLDM_ENTITY_ADDIN_CARD_34_VR_0V88_VCC_CPM5_CURRENT     ( 34 )

/* PCB Temperature PDR Defines */

#define PCB_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )
#define PCB_TEMPERATURE_NORMAL_MAX      ( 79 )
#define PCB_TEMPERATURE_WARNING_HIGH    ( 80 )
#define PCB_TEMPERATURE_CRITICAL_HIGH   ( 85 )
#define PCB_TEMPERATURE_FATAL_HIGH      ( 95 )

/* Device Temperature PDR Defines */

#define DEVICE_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )
#define DEVICE_TEMPERATURE_NORMAL_MAX      ( 91 )
#define DEVICE_TEMPERATURE_WARNING_HIGH    ( 92 )
#define DEVICE_TEMPERATURE_CRITICAL_HIGH   ( 100 )
#define DEVICE_TEMPERATURE_FATAL_HIGH      ( 105 )

/* VR_VCCINT Temperature PDR Defines */

#define VR_VCCINT_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )
#define VR_VCCINT_TEMPERATURE_NORMAL_MAX      ( 99 )
#define VR_VCCINT_TEMPERATURE_WARNING_HIGH    ( 100 )
#define VR_VCCINT_TEMPERATURE_CRITICAL_HIGH   ( 110 )
#define VR_VCCINT_TEMPERATURE_FATAL_HIGH      ( 125 )

/* VR_VCCINT Voltage PDR Defines */

#define VR_VCCINT_VOLTAGE_UPDATE_INTERVAL ( 1.0 )

/* VR_VCCINT Current PDR Defines */

#define VR_VCCINT_CURRENT_UPDATE_INTERVAL ( 1.0 )

/* QSFP Module 0 Temperature PDR Defines */

#define QSFP_MODULE_0_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )
#define QSFP_MODULE_0_TEMPERATURE_NORMAL_MAX      ( 79 )
#define QSFP_MODULE_0_TEMPERATURE_WARNING_HIGH    ( 80 )
#define QSFP_MODULE_0_TEMPERATURE_CRITICAL_HIGH   ( 85 )
#define QSFP_MODULE_0_TEMPERATURE_FATAL_HIGH      ( 95 )

/* QSFP Module 1 Temperature PDR Defines */

#define QSFP_MODULE_1_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )
#define QSFP_MODULE_1_TEMPERATURE_NORMAL_MAX      ( 79 )
#define QSFP_MODULE_1_TEMPERATURE_WARNING_HIGH    ( 80 )
#define QSFP_MODULE_1_TEMPERATURE_CRITICAL_HIGH   ( 85 )
#define QSFP_MODULE_1_TEMPERATURE_FATAL_HIGH      ( 95 )

/* QSFP Module 2 Temperature PDR Defines */

#define QSFP_MODULE_2_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )
#define QSFP_MODULE_2_TEMPERATURE_NORMAL_MAX      ( 79 )
#define QSFP_MODULE_2_TEMPERATURE_WARNING_HIGH    ( 80 )
#define QSFP_MODULE_2_TEMPERATURE_CRITICAL_HIGH   ( 85 )
#define QSFP_MODULE_2_TEMPERATURE_FATAL_HIGH      ( 95 )

/* QSFP Module 3 Temperature PDR Defines */

#define QSFP_MODULE_3_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )
#define QSFP_MODULE_3_TEMPERATURE_NORMAL_MAX      ( 79 )
#define QSFP_MODULE_3_TEMPERATURE_WARNING_HIGH    ( 80 )
#define QSFP_MODULE_3_TEMPERATURE_CRITICAL_HIGH   ( 85 )
#define QSFP_MODULE_3_TEMPERATURE_FATAL_HIGH      ( 95 )

/* DIMM Temperature PDR Defines */

#define DIMM_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )

/* VR_1V2_VCC_HBM Temperature PDR Defines */

#define VR_1V2_VCC_HBM_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )

/* VR_1V2_VCC_HBM Voltage PDR Defines */

#define VR_1V2_VCC_HBM_VOLTAGE_UPDATE_INTERVAL ( 1.0 )

/* VR_1V2_VCC_HBM Current PDR Defines */

#define VR_1V2_VCC_HBM_CURRENT_UPDATE_INTERVAL ( 1.0 )

/* VR_12V_AUX1 Voltage PDR Defines */

#define VR_12V_AUX1_VOLTAGE_UPDATE_INTERVAL ( 1.0 )

/* VR_12V_AUX1 Current PDR Defines */

#define VR_12V_AUX1_CURRENT_UPDATE_INTERVAL ( 1.0 )
#define VR_12V_AUX1_CURRENT_NORMAL_MAX      ( 12499 )
#define VR_12V_AUX1_CURRENT_WARNING_HIGH    ( 12500 )
#define VR_12V_AUX1_CURRENT_CRITICAL_HIGH   ( 12750 )
#define VR_12V_AUX1_CURRENT_FATAL_HIGH      ( 12751 )

/* VR_12V_AUX1 Power PDR Defines */

#define VR_12V_AUX1_POWER_UPDATE_INTERVAL ( 1.0 )

/* VR_12V_AUX2 Voltage PDR Defines */

#define VR_12V_AUX2_VOLTAGE_UPDATE_INTERVAL ( 1.0 )

/* VR_12V_AUX2 Current PDR Defines */

#define VR_12V_AUX2_CURRENT_UPDATE_INTERVAL ( 1.0 )
#define VR_12V_AUX2_CURRENT_NORMAL_MAX      ( 12499 )
#define VR_12V_AUX2_CURRENT_WARNING_HIGH    ( 12500 )
#define VR_12V_AUX2_CURRENT_CRITICAL_HIGH   ( 12750 )
#define VR_12V_AUX2_CURRENT_FATAL_HIGH      ( 12751 )

/* VR_12V_AUX2 Power PDR Defines */

#define VR_12V_AUX2_POWER_UPDATE_INTERVAL ( 1.0 )

/* VR_3V3_PEX Voltage PDR Defines */

#define VR_3V3_PEX_VOLTAGE_UPDATE_INTERVAL ( 1.0 )

/* VR_3V3_PEX Current PDR Defines */

#define VR_3V3_PEX_CURRENT_UPDATE_INTERVAL ( 1.0 )
#define VR_3V3_PEX_CURRENT_NORMAL_MAX      ( 2999 )
#define VR_3V3_PEX_CURRENT_WARNING_HIGH    ( 3000 )
#define VR_3V3_PEX_CURRENT_CRITICAL_HIGH   ( 3150 )
#define VR_3V3_PEX_CURRENT_FATAL_HIGH      ( 3151 )

/* VR_3V3_PEX Power PDR Defines */

#define VR_3V3_PEX_POWER_UPDATE_INTERVAL ( 1.0 )

/* VR_12V_PEX Voltage PDR Defines */

#define VR_12V_PEX_VOLTAGE_UPDATE_INTERVAL ( 1.0 )

/* VR_12V_PEX Current PDR Defines */

#define VR_12V_PEX_CURRENT_UPDATE_INTERVAL ( 1.0 )
#define VR_12V_PEX_CURRENT_NORMAL_MAX      ( 5499 )
#define VR_12V_PEX_CURRENT_WARNING_HIGH    ( 5500 )
#define VR_12V_PEX_CURRENT_CRITICAL_HIGH   ( 5750 )
#define VR_12V_PEX_CURRENT_FATAL_HIGH      ( 5751 )

/* VR_12V_PEX Power PDR Defines */

#define VR_12V_PEX_POWER_UPDATE_INTERVAL ( 1.0 )

/* VR_1V5_VCCAUX Voltage PDR Defines */

#define VR_1V5_VCCAUX_VOLTAGE_UPDATE_INTERVAL ( 1.0 )

/* VR_1V2_GTXAVTT Temperature PDR Defines */

#define VR_1V2_GTXAVTT_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )

/* VR_1V2_GTXAVTT Voltage PDR Defines */

#define VR_1V2_GTXAVTT_VOLTAGE_UPDATE_INTERVAL ( 1.0 )

/* VR_1V2_GTXAVTT Current PDR Defines */

#define VR_1V2_GTXAVTT_CURRENT_UPDATE_INTERVAL ( 1.0 )

/* VR_0V88_VCC_CPM5 Temperature PDR Defines */

#define VR_0V88_VCC_CPM5_TEMPERATURE_UPDATE_INTERVAL ( 1.0 )

/* VR_0V88_VCC_CPM5 Voltage PDR Defines */

#define VR_0V88_VCC_CPM5_VOLTAGE_UPDATE_INTERVAL ( 1.0 )

/* VR_0V88_VCC_CPM5 Current PDR Defines */

#define VR_0V88_VCC_CPM5_CURRENT_UPDATE_INTERVAL ( 1.0 )


/******************************************************************************/
/* Public data                                                                */
/******************************************************************************/

PLDM_NUMERIC_SENSOR_PDR pxPdrTemperatureSensors[ TOTAL_PDR_TEMPERATURE ] =
{
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = PCB_TEMPERATURE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_1_PCB_TEMPERATURE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_DEGREES_C,
        .cUnitModifier                      = PDR_PARAM_NONE,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = HAS_HIGH_THRESHOLDS,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = PCB_TEMPERATURE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = ( NORMAL_MIN_MAX | HIGH_THRESHOLDS ),
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PCB_TEMPERATURE_NORMAL_MAX,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PCB_TEMPERATURE_WARNING_HIGH,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PCB_TEMPERATURE_CRITICAL_HIGH,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PCB_TEMPERATURE_FATAL_HIGH,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = DEVICE_TEMPERATURE_SENSOR_ID,
        .usEntityType                       = LOGICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = LOGICAL_PLDM_ENTITY_ADDIN_CARD_1_DEVICE_TEMPERATURE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_DEGREES_C,
        .cUnitModifier                      = PDR_PARAM_NONE,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = HAS_HIGH_THRESHOLDS,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = DEVICE_TEMPERATURE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = ( NORMAL_MIN_MAX | HIGH_THRESHOLDS ),
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = DEVICE_TEMPERATURE_NORMAL_MAX,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = DEVICE_TEMPERATURE_WARNING_HIGH,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = DEVICE_TEMPERATURE_CRITICAL_HIGH,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = DEVICE_TEMPERATURE_FATAL_HIGH,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_VCCINT_TEMPERATURE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_2_VR_VCCINT_TEMPERATURE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_DEGREES_C,
        .cUnitModifier                      = PDR_PARAM_NONE,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = HAS_HIGH_THRESHOLDS,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_VCCINT_TEMPERATURE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = ( NORMAL_MIN_MAX | HIGH_THRESHOLDS ),
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = VR_VCCINT_TEMPERATURE_NORMAL_MAX,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = VR_VCCINT_TEMPERATURE_WARNING_HIGH,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = VR_VCCINT_TEMPERATURE_CRITICAL_HIGH,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = VR_VCCINT_TEMPERATURE_FATAL_HIGH,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_1V2_VCC_HBM_TEMPERATURE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_10_VR_1V2_VCC_HBM_TEMPERATURE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_DEGREES_C,
        .cUnitModifier                      = PDR_PARAM_NONE,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_1V2_VCC_HBM_TEMPERATURE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_1V2_GTXAVTT_TEMPERATURE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_29_VR_1V2_GTXAVTT_TEMPERATURE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_DEGREES_C,
        .cUnitModifier                      = PDR_PARAM_NONE,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_1V2_GTXAVTT_TEMPERATURE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_0V88_VCC_CPM5_TEMPERATURE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_32_VR_0V88_VCC_CPM5_TEMPERATURE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_DEGREES_C,
        .cUnitModifier                      = PDR_PARAM_NONE,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_0V88_VCC_CPM5_TEMPERATURE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    }
};

PLDM_NUMERIC_SENSOR_PDR pxPdrVoltageSensors[ TOTAL_PDR_VOLTAGE ] =
{
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_VCCINT_VOLTAGE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_3_VR_VCCINT_VOLTAGE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_VOLTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_VCCINT_VOLTAGE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_1V2_VCC_HBM_VOLTAGE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_11_VR_1V2_VCC_HBM_VOLTAGE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_VOLTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_1V2_VCC_HBM_VOLTAGE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_12V_AUX1_VOLTAGE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_13_VR_12V_AUX1_VOLTAGE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_VOLTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_12V_AUX1_VOLTAGE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_12V_AUX2_VOLTAGE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_14_VR_12V_AUX2_VOLTAGE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_VOLTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_12V_AUX2_VOLTAGE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_3V3_PEX_VOLTAGE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_20_VR_3V3_PEX_VOLTAGE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_VOLTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_3V3_PEX_VOLTAGE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE,
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_12V_PEX_VOLTAGE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_23_VR_12V_PEX_VOLTAGE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_VOLTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_12V_PEX_VOLTAGE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE,
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_1V5_VCCAUX_VOLTAGE_SENSOR_ID,
        .usEntityType                       = LOGICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = LOGICAL_PLDM_ENTITY_ADDIN_CARD_4_VR_1V5_VCCAUX_VOLTAGE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_VOLTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_1V5_VCCAUX_VOLTAGE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE,
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_1V2_GTXAVTT_VOLTAGE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_30_VR_1V2_GTXAVTT_VOLTAGE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_VOLTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_1V2_GTXAVTT_VOLTAGE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE,
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_0V88_VCC_CPM5_VOLTAGE_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_33_VR_0V88_VCC_CPM5_VOLTAGE,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_VOLTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_0V88_VCC_CPM5_VOLTAGE_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE,
    }
};

PLDM_NUMERIC_SENSOR_PDR pxPdrCurrentSensors[ TOTAL_PDR_CURRENT ] =
{
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_VCCINT_CURRENT_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_4_VR_VCCINT_CURRENT,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_AMPS,
        .cUnitModifier                      = PDR_PARAM_NONE,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_VCCINT_CURRENT_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_1V2_VCC_HBM_CURRENT_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_12_VR_1V2_VCC_HBM_CURRENT,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_AMPS,
        .cUnitModifier                      = PDR_PARAM_NONE,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_1V2_VCC_HBM_CURRENT_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_12V_AUX1_CURRENT_SENSOR_ID,
        .usEntityType                       = LOGICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = LOGICAL_PLDM_ENTITY_ADDIN_CARD_2_VR_12V_AUX1_CURRENT,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_AMPS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = HAS_HIGH_THRESHOLDS,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_12V_AUX1_CURRENT_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = ( NORMAL_MIN_MAX | HIGH_THRESHOLDS ),
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = VR_12V_AUX1_CURRENT_NORMAL_MAX,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = VR_12V_AUX1_CURRENT_WARNING_HIGH,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = VR_12V_AUX1_CURRENT_CRITICAL_HIGH,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = VR_12V_AUX1_CURRENT_FATAL_HIGH,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_12V_AUX2_CURRENT_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_15_VR_12V_AUX2_CURRENT,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_AMPS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = HAS_HIGH_THRESHOLDS,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_12V_AUX2_CURRENT_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = ( NORMAL_MIN_MAX | HIGH_THRESHOLDS ),
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = VR_12V_AUX2_CURRENT_NORMAL_MAX,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = VR_12V_AUX2_CURRENT_WARNING_HIGH,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = VR_12V_AUX2_CURRENT_CRITICAL_HIGH,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = VR_12V_AUX2_CURRENT_FATAL_HIGH,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_3V3_PEX_CURRENT_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_21_VR_3V3_PEX_CURRENT,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_AMPS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = HAS_HIGH_THRESHOLDS,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_3V3_PEX_CURRENT_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = ( NORMAL_MIN_MAX | HIGH_THRESHOLDS ),
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = VR_3V3_PEX_CURRENT_NORMAL_MAX,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = VR_3V3_PEX_CURRENT_WARNING_HIGH,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = VR_3V3_PEX_CURRENT_CRITICAL_HIGH,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = VR_3V3_PEX_CURRENT_FATAL_HIGH,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_12V_PEX_CURRENT_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_24_VR_12V_PEX_CURRENT,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_AMPS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = HAS_HIGH_THRESHOLDS,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_12V_PEX_CURRENT_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = ( NORMAL_MIN_MAX | HIGH_THRESHOLDS ),
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = VR_12V_PEX_CURRENT_NORMAL_MAX,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = VR_12V_PEX_CURRENT_WARNING_HIGH,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = VR_12V_PEX_CURRENT_CRITICAL_HIGH,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = VR_12V_PEX_CURRENT_FATAL_HIGH,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_1V2_GTXAVTT_CURRENT_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_31_VR_1V2_GTXAVTT_CURRENT,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_AMPS,
        .cUnitModifier                      = PDR_PARAM_NONE,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_1V2_GTXAVTT_CURRENT_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_0V88_VCC_CPM5_CURRENT_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_34_VR_0V88_VCC_CPM5_CURRENT,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_AMPS,
        .cUnitModifier                      = PDR_PARAM_NONE,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_0V88_VCC_CPM5_CURRENT_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    }
};

PLDM_NUMERIC_SENSOR_PDR pxPdrPowerSensors[ TOTAL_PDR_POWER ] =
{
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_12V_AUX1_POWER_SENSOR_ID,
        .usEntityType                       = LOGICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = LOGICAL_PLDM_ENTITY_ADDIN_CARD_3_VR_12V_AUX1_POWER,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_WATTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_12V_AUX1_POWER_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_12V_AUX2_POWER_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_16_VR_12V_AUX2_POWER,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_WATTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_12V_AUX2_POWER_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_3V3_PEX_POWER_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_22_VR_3V3_PEX_POWER,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_WATTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_3V3_PEX_POWER_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    },
    {
        .ucSensorDataSize                   = EDataTypeSInt16,
        .xRange.ucRangeFieldFormat          = EDataTypeSInt16,
        .usPldmTerminusHandle               = PLDM_TERMINUS_HANDLE,
        .usSensorId                         = VR_12V_PEX_POWER_SENSOR_ID,
        .usEntityType                       = PHYSICAL_PLDM_ENTITY_ADDIN_CARD,
        .usEntityInstanceNumber             = PHYSICAL_PLDM_ENTITY_ADDIN_CARD_25_VR_12V_PEX_POWER,
        .usContainerId                      = CONTAINED_ENTITY_CONTAINER_ID,
        .ucSensorInit                       = PLDM_PDR_INIT_STATUS_NO_INIT,
        .ucSensorAuxiliaryNamesPdr          = TRUE,
        .ucBaseUnit                         = PLDM_PDR_BASE_UNIT_WATTS,
        .cUnitModifier                      = UNITS_IN_MILLI,
        .ucRateUnit                         = PLDM_PDR_RATE_UNIT_NONE,
        .ucBaseOemUnitHandle                = PDR_PARAM_NONE,
        .ucAuxUnit                          = PLDM_PDR_RATE_UNIT_NONE,
        .cAuxUnitModifier                   = PDR_PARAM_NONE,
        .ucAuxRateUnit                      = PLDM_PDR_RATE_UNIT_NONE,
        .ucRel                              = PDR_PARAM_NONE,
        .ucAuxOemUnitHandle                 = PDR_PARAM_NONE,
        .ucIsLinear                         = TRUE,
        .fResolution                        = PDR_PARAM_NONE,
        .fOffset                            = PDR_PARAM_NONE,
        .usAccuracy                         = PDR_PARAM_NONE,
        .ucPlusTolerance                    = PDR_PARAM_NONE,
        .ucMinusTolerance                   = PDR_PARAM_NONE,
        .sHysteresis                        = PDR_PARAM_NONE,
        .ucSupportedThresholds              = PDR_PARAM_NONE,
        .ucThresholdAndHysteresisVolatility = PDR_PARAM_NONE,
        .fStateTransitionInterval           = PDR_PARAM_NONE,
        .fUpdateInterval                    = VR_12V_PEX_POWER_UPDATE_INTERVAL,
        .sMaxReadable                       = PDR_PARAM_NONE,
        .sMinReadable                       = PDR_PARAM_NONE,
        .xRange.ucRangeFieldSupport         = PDR_PARAM_NONE,
        .xRange.sNominalValue               = PDR_PARAM_NONE,
        .xRange.sNormalMax                  = PDR_PARAM_NONE,
        .xRange.sNormalMin                  = PDR_PARAM_NONE,
        .xRange.sWarningHigh                = PDR_PARAM_NONE,
        .xRange.sWarningLow                 = PDR_PARAM_NONE,
        .xRange.sCriticalHigh               = PDR_PARAM_NONE,
        .xRange.sCriticalLow                = PDR_PARAM_NONE,
        .xRange.sFatalHigh                  = PDR_PARAM_NONE,
        .xRange.sFatalLow                   = PDR_PARAM_NONE
    }
};

/* Numeric sensor names PDRs */

PLDM_NUMERIC_SENSOR_NAME_PDR pxPdrSensorNames[ TOTAL_PDR_NUMERIC_ASCI_SENSORS ] =
{
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = PCB_TEMPERATURE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 80, 0, 67, 0, 66, 0, 32, 0, 84, 0, 101, 0, 109, 0, 112, 0, 101, 0, 114, 0, 97, 0, 116, 0, 117, 0, 114, 0,
          101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = DEVICE_TEMPERATURE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 68, 0, 101, 0, 118, 0, 105, 0, 99, 0, 101, 0, 32, 0, 84, 0, 101, 0, 109, 0, 112, 0, 101, 0, 114, 0, 97, 0,
          116, 0, 117, 0, 114, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_VCCINT_TEMPERATURE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 86, 0, 67, 0, 67, 0, 73, 0, 78, 0, 84, 0, 32, 0, 84, 0, 101, 0, 109, 0, 112, 0, 101,
          0, 114, 0, 97, 0, 116, 0, 117, 0, 114, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_VCCINT_VOLTAGE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 86, 0, 67, 0, 67, 0, 73, 0, 78, 0, 84, 0, 32, 0, 86, 0, 111, 0, 108, 0, 116, 0, 97, 0,
          103, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_VCCINT_CURRENT_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 86, 0, 67, 0, 67, 0, 73, 0, 78, 0, 84, 0, 32, 0, 67, 0, 117, 0, 114, 0, 114, 0, 101,
          0, 110, 0, 116, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_1V2_VCC_HBM_TEMPERATURE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 86, 0, 50, 0, 95, 0, 86, 0, 67, 0, 67, 0, 95, 0, 72, 0, 66, 0, 77, 0, 32, 0,
          84, 0, 101, 0, 109, 0, 112, 0, 101, 0, 114, 0, 97, 0, 116, 0, 117, 0, 114, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_1V2_VCC_HBM_VOLTAGE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 86, 0, 50, 0, 95, 0, 86, 0, 67, 0, 67, 0, 95, 0, 72, 0, 66, 0, 77, 0, 32, 0,
          86, 0, 111, 0, 108, 0, 116, 0, 97, 0, 103, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_1V2_VCC_HBM_CURRENT_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 86, 0, 50, 0, 95, 0, 86, 0, 67, 0, 67, 0, 95, 0, 72, 0, 66, 0, 77, 0, 32, 0,
          67, 0, 117, 0, 114, 0, 114, 0, 101, 0, 110, 0, 116, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_12V_AUX1_VOLTAGE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 50, 0, 86, 0, 95, 0, 65, 0, 85, 0, 88, 0, 49, 0, 32, 0, 86, 0, 111, 0, 108, 0,
          116, 0, 97, 0, 103, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_12V_AUX1_CURRENT_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 50, 0, 86, 0, 95, 0, 65, 0, 85, 0, 88, 0, 49, 0, 32, 0, 67, 0, 117, 0, 114, 0,
          114, 0, 101, 0, 110, 0, 116, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_12V_AUX1_POWER_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 50, 0, 86, 0, 95, 0, 65, 0, 85, 0, 88, 0, 49, 0, 32, 0, 80, 0, 111, 0, 119, 0,
          101, 0, 114, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_12V_AUX2_VOLTAGE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 50, 0, 86, 0, 95, 0, 65, 0, 85, 0, 88, 0, 50, 0, 32, 0, 86, 0, 111, 0, 108, 0,
          116, 0, 97, 0, 103, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_12V_AUX2_CURRENT_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 50, 0, 86, 0, 95, 0, 65, 0, 85, 0, 88, 0, 50, 0, 32, 0, 67, 0, 117, 0, 114, 0,
          114, 0, 101, 0, 110, 0, 116, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_12V_AUX2_POWER_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 50, 0, 86, 0, 95, 0, 65, 0, 85, 0, 88, 0, 50, 0, 32, 0, 80, 0, 111, 0, 119, 0,
          101, 0, 114, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_3V3_PEX_VOLTAGE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 51, 0, 86, 0, 51, 0, 95, 0, 80, 0, 69, 0, 88, 0, 32, 0, 86, 0, 111, 0, 108, 0, 116, 0,
          97, 0, 103, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_3V3_PEX_CURRENT_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 51, 0, 86, 0, 51, 0, 95, 0, 80, 0, 69, 0, 88, 0, 32, 0, 67, 0, 117, 0, 114, 0, 114, 0,
          101, 0, 110, 0, 116, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_3V3_PEX_POWER_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 51, 0, 86, 0, 51, 0, 95, 0, 80, 0, 69, 0, 88, 0, 32, 0, 80, 0, 111, 0, 119, 0, 101, 0,
          114, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_12V_PEX_VOLTAGE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 50, 0, 86, 0, 95, 0, 80, 0, 69, 0, 88, 0, 32, 0, 86, 0, 111, 0, 108, 0, 116, 0,
          97, 0, 103, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_12V_PEX_CURRENT_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 50, 0, 86, 0, 95, 0, 80, 0, 69, 0, 88, 0, 32, 0, 67, 0, 117, 0, 114, 0, 114, 0,
          101, 0, 110, 0, 116, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_12V_PEX_POWER_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 50, 0, 86, 0, 95, 0, 80, 0, 69, 0, 88, 0, 32, 0, 80, 0, 111, 0, 119, 0, 101, 0,
          114, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_1V5_VCCAUX_VOLTAGE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 86, 0, 53, 0, 95, 0, 86, 0, 67, 0, 67, 0, 65, 0, 85, 0, 88, 0, 32, 0, 86, 0,
          111, 0, 108, 0, 116, 0, 97, 0, 103, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_1V2_GTXAVTT_TEMPERATURE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 86, 0, 50, 0, 95, 0, 71, 0, 84, 0, 88, 0, 65, 0, 86, 0, 84, 0, 84, 0, 32, 0,
          84, 0, 101, 0, 109, 0, 112, 0, 101, 0, 114, 0, 97, 0, 116, 0, 117, 0, 114, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_1V2_GTXAVTT_VOLTAGE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 86, 0, 50, 0, 95, 0, 71, 0, 84, 0, 88, 0, 65, 0, 86, 0, 84, 0, 84, 0, 32, 0,
          86, 0, 111, 0, 108, 0, 116, 0, 97, 0, 103, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_1V2_GTXAVTT_CURRENT_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 49, 0, 86, 0, 50, 0, 95, 0, 71, 0, 84, 0, 88, 0, 65, 0, 86, 0, 84, 0, 84, 0, 32, 0,
          67, 0, 117, 0, 114, 0, 114, 0, 101, 0, 110, 0, 116, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_0V88_VCC_CPM5_TEMPERATURE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 48, 0, 86, 0, 56, 0, 56, 0, 95, 0, 86, 0, 67, 0, 67, 0, 95, 0, 67, 0, 80, 0, 77, 0,
          53, 0, 32, 0, 84, 0, 101, 0, 109, 0, 112, 0, 101, 0, 114, 0, 97, 0, 116, 0, 117, 0, 114, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_0V88_VCC_CPM5_VOLTAGE_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 48, 0, 86, 0, 56, 0, 56, 0, 95, 0, 86, 0, 67, 0, 67, 0, 95, 0, 67, 0, 80, 0, 77, 0,
          53, 0, 32, 0, 86, 0, 111, 0, 108, 0, 116, 0, 97, 0, 103, 0, 101, 0, 0 }

    },
    {
        .usPldmTerminusHandle = PLDM_TERMINUS_HANDLE,
        .usSensorId           = VR_0V88_VCC_CPM5_CURRENT_SENSOR_ID,
        .ucSensorCount        = 1,
        .ucNameStringCount    =
        { 1 },
        .ucNameLanguageTag =
        { 117, 115, 45, 101, 110, 0 },
        .ucSensorNameBe16 =
        { 0, 86, 0, 82, 0, 95, 0, 48, 0, 86, 0, 56, 0, 56, 0, 95, 0, 86, 0, 67, 0, 67, 0, 95, 0, 67, 0, 80, 0, 77, 0,
          53, 0, 32, 0, 67, 0, 117, 0, 114, 0, 114, 0, 101, 0, 110, 0, 116, 0, 0 }

    }
};

#endif
