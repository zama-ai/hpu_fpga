/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the profile debug menu for the V80
 *
 * @file profile_debug_menu.h
 *
 */

/*****************************************************************************/
/* Includes                                                                  */
/*****************************************************************************/

#include "profile_debug_menu.h"
#include "profile_muxed_device.h"
#include "profile_hal.h"
#include "profile_fal.h"
#include "dal.h"

/******************************************************************************/
/* Public Function Implementations                                            */
/******************************************************************************/

/**
 * @brief   Initialise Debug Menu
 */
void vDebugMenu_Initialise( )
{
    /* top level directories */
    static DAL_HDL pxDeviceDrivers   = NULL;
    static DAL_HDL pxCoreLibsTop     = NULL;
    static DAL_HDL pxProxyDriversTop = NULL;
    static DAL_HDL pxAppsTop         = NULL;

    /* osal */
    vOSAL_DebugInit();

    /* device drivers */
    pxDeviceDrivers = pxDAL_NewDirectory( "device_drivers" );

    vINA3221_DebugInit( pxDeviceDrivers );
    vISL68221_DebugInit( pxDeviceDrivers );
    vCAT34TS02_DebugInit( pxDeviceDrivers );
    vSYS_MON_DebugInit( pxDeviceDrivers );
    vEeprom_DebugInit( pxDeviceDrivers );
    vOSPI_DebugInit( pxDeviceDrivers );
    vI2C_DebugInit( pxDeviceDrivers );
#if ( 0 != HAL_EMMC_FEATURE )
    vEMMC_DebugInit( pxDeviceDrivers );
#endif
    /* core libraries */
    pxCoreLibsTop = pxDAL_NewDirectory( "core_libs" );

    vPLL_DebugInit( pxCoreLibsTop );
    vDAL_DebugInit( pxCoreLibsTop );
    vEVL_DebugInit( pxCoreLibsTop );

    vFAL_DebugInitialise();

    /* proxy drivers */
    pxProxyDriversTop = pxDAL_NewDirectory( "proxy_drivers" );

    vAMI_DebugInit( pxProxyDriversTop );
    vAPC_DebugInit( pxProxyDriversTop );
    vASC_DebugInit( pxProxyDriversTop );
    if( 0 != MAX_NUM_EXTERNAL_DEVICES_AVAILABLE )
    {
        vAXC_DebugInit( pxProxyDriversTop );
    }
    vBMC_DebugInit( pxProxyDriversTop );

    /* apps */
    pxAppsTop = pxDAL_NewDirectory( "apps" );

    vASDM_DebugInit( pxAppsTop );
    vIN_BAND_TELEMETRY_DebugInit( pxAppsTop, HAL_RPU_SHARED_MEMORY_BASE_ADDR );
    vOUT_OF_BAND_TELEMETRY_DebugInit( pxAppsTop );
    vBIM_DebugInit( pxAppsTop );
}
