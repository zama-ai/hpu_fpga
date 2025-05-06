/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the PDR functions
 *
 * @file pldm_pdr.c
 *
 */


/******************************************************************************/
/* Includes                                                                    */
/******************************************************************************/

#include "unistd.h"
#include "pldm_pdr.h"
#include "util.h"
#include "pldm_sensors.h"
#include "eeprom.h"
#include "bmc_proxy_driver.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define PDR_HEADER_VERSION 0x1

#define DATATYPE_EDataTypeUInt8  uint8_t
#define DATATYPE_EDataTypeSInt8  int8_t
#define DATATYPE_EDataTypeUInt16 uint16_t
#define DATATYPE_EDataTypeSInt16 int16_t
#define DATATYPE_EDataTypeUInt32 uint32_t
#define DATATYPE_EDataTypeSInt32 int32_t
#define DATATYPE_EDataTypeReal32 real32_t

#define _DataType( x ) DATATYPE_ ## x

#define __DATE_ ( 0x18012024 )


/******************************************************************************/
/* Globals                                                                   */
/******************************************************************************/

PDR_RepositoryInfo MSP432_PDR_Repository =
{
    .repositoryState = ERepoStateFailed,                                       /* as repo is not intialized yet */
    /*intialization of repo related info in the init function */
};


/******************************************************************************/
/* Function definitions                                                       */
/******************************************************************************/

/**
 * @brief   Update the timestamp
 */
void vUpdateTimestamp( TimeStamp *time )
{
    time->Year                = 0;
    time->Month               = 0;
    time->Day                 = 0;
    time->Hours               = 8;
    time->Minutes             = 30;
    time->Seconds             = 15;
    time->uSeconds[ 0 ]       = time->uSeconds[ 1 ] = time->uSeconds[ 2 ] = 0;
    time->UTC_Offset          = 0;
    time->UTC_Time_Resolution = 0xF;                                           /* Value determined by Andrew */
}

/**
 * @brief   Count the empty space in the sensor name
 */
uint32_t sensor_name_empty_space( uint8_t *namePDR )
{
    int      i           = 0;
    uint16_t *name_utf16 = ( uint16_t * )namePDR;

    while( name_utf16[ i ] && i < MAX_NAME_SIZE )
    {
        i++;
    }

    /* To include null character in the end */
    i++;

    if( i == MAX_NAME_SIZE )
    {
        /* should never happend, it does happen, Assert here MAX_NAME_SIZE is not defined properly*/

        /*
         * while(1);
         */

        /*
         * Lets trim the string if we are not asserting.
         */
        name_utf16[ i - 1 ] = 0x0;
    }

    return 2 * ( MAX_NAME_SIZE - i );
}


/**
 * @brief   Update the TID
 */
void update_tid( uint8_t tid )
{
    PDR_RepositoryInfo    *repo;
    TerminusPDRFormat_UID *terminusPDR;

    /*
     * initialize repo if it is not already initialized.
     * Just sanity
     */
    vPdrRepoInit();

    repo        = &MSP432_PDR_Repository;
    terminusPDR = repo->PDRRecords[ PLDM_TERMINUS_HANDLE ];
    /*
     * Assuming the operation after this can be made async someday
     */
    repo->repositoryState = ERepoStateUpdateInprogress;
    terminusPDR->TID      = tid;
    terminusPDR->commonHeader.recordChangeNumber += 1;
    vUpdateTimestamp( &repo->updateTimestamp );
    repo->repositoryState = ERepoStateAvailable;
}

/**
 * @brief   Get the current PDR repository
 */
const PDR_RepositoryInfo *getPDRRepository( void )
{
    vPdrRepoInit();
    /* Sanity: Although called multiple times,
       it will be only initialized once (at the boot time) */

    return &MSP432_PDR_Repository;
}
