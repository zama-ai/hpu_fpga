/**
 * Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains PLDM command enums, structures and functions
 *
 * @file pldm_commands.c
 *
 */


/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <unistd.h>

#include "pldm_processor.h"
#include "pldm_response.h"
#include "pldm_commands.h"
#include "pldm_pdr.h"
#include "util.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define MAX_PLDM_TYPE ( 6 )

#define POSSIBLE_MAX_PLDM_TYPE ( 8 * 8 )
#define POSSIBLE_MAX_PLDM_CMD  ( 8 * 32 )

#define TYPE0_VERSION_MAJOR  ( 0xF1 )                                          /* Single digit 1 */
#define TYPE0_VERSION_MINOR  ( 0xF1 )                                          /* Single digit 0 */
#define TYPE0_VERSION_UPDATE ( 0xF0 )                                          /* Single digit 0 */
#define TYPE0_VERSION_DRAFT  ( 0x00 )                                          /* Alpha field is not present */

#define TYPE2_VERSION_MAJOR  ( 0xF1 )                                          /* Single digit 1 */
#define TYPE2_VERSION_MINOR  ( 0xF2 )                                          /* Single digit 2 */
#define TYPE2_VERSION_UPDATE ( 0xF2 )                                          /* Single digit 0 */
#define TYPE2_VERSION_DRAFT  ( 0x00 )                                          /* Alpha field is not present */

#define TYPE5_VERSION_MAJOR  ( 0xF1 )                                          /* Single digit 1 */
#define TYPE5_VERSION_MINOR  ( 0xF0 )                                          /* Single digit 0 */
#define TYPE5_VERSION_UPDATE ( 0xF0 )                                          /* Single digit 0 */
#define TYPE5_VERSION_DRAFT  ( 0x00 )                                          /* Alpha field is not present */


/******************************************************************************/
/* Typedefs                                                                   */
/******************************************************************************/

/**
 * @struct  Pldm_command_list
 * @brief   PLDM command list variables
 */
typedef struct Pldm_command_list
{
    const PldmFunction       *funcList;
    const uint32_t           max_command_id;
    const uint32_t           version_id;
    uint8_t                  Pldm_Command_Supported[ 32 ];
    struct Pldm_command_list *next;                                            /* pointer to next command list for the same type but different version */

}Pldm_command_list;


/******************************************************************************/
/* Local Variables                                                            */
/******************************************************************************/

/*
 * ver32 encoding of the PLDM version
 * This array lists all the versions supported (regardless of which type)
 */
const static uint8_t Pldm_Versions[][ 4 ] =
{
    [ 0 ] = {
        TYPE0_VERSION_DRAFT, TYPE0_VERSION_UPDATE, TYPE0_VERSION_MINOR, TYPE0_VERSION_MAJOR
    },                                                                         //1.0.0
    [ 1 ] = {
        TYPE2_VERSION_DRAFT, TYPE2_VERSION_UPDATE, TYPE2_VERSION_MINOR, TYPE0_VERSION_MAJOR
    }                                                                          //1.2.0
};

/*
 * Supported PLDM type and command list
 * Initialize to 0 and will be built during the command_init
 */
static uint8_t Pldm_Type_Supported[ 8 ] =
{
    0
};

/*
 * Assuming non-defined entries will be NULL
 */
const static PldmFunction PldmType0_cmd[ MAX_PLDM_0_COMMAND ] =
{
    [ PLDM_CMD_SETTID ]     = pldm_cmd_SetTID,
    [ PLDM_CMD_GETTID ]     = pldm_cmd_GetTID,
    [ PLDM_CMD_GETVERSION ] = pldm_cmd_GetPLDMVersion,
    [ PLDM_CMD_GETTYPE ]    = pldm_cmd_GetPLDMType,
    [ PLDM_CMD_GETCOMMAND ] = pldm_cmd_GetPLDMCommand
};

/*
 * Assuming non-defined entries will be NULL
 */
const static PldmFunction PldmType2_cmd[ MAX_PLDM_2_COMMAND ] =
{
    [ PLDM_CMD_SET_NUMERIC_SENSOR_ENABLE ] = pldm_cmd_SetNumericSensorEnable,
    [ PLDM_CMD_GET_SENSOR_READING ]        = pldm_cmd_GetSensorReading,
    [ PLDM_CMD_GET_PDR_REPO_INFO ]         = pldm_cmd_GetPDRRepositoryInfo,
    [ PLDM_CMD_GET_PDR ]                   = pldm_cmd_GetPDR
};


static int PldmInitDone = 0;

Pldm_command_list type0_cmd_list =
{
    PldmType0_cmd,  MAX_PLDM_0_COMMAND, 0, {
        0
    }, NULL
};
Pldm_command_list type2_cmd_list =
{
    PldmType2_cmd,  MAX_PLDM_2_COMMAND, 1, {
        0
    }, NULL
};

/*
 * Assuming non-defined entries will be NULL
 */
Pldm_command_list *pldm_type_cmd[ MAX_PLDM_TYPE ] =
{
    [ 0 ] = &type0_cmd_list,
    [ 2 ] = &type2_cmd_list
};


/******************************************************************************/
/* Function defintions                                                        */
/******************************************************************************/

/**
 * @brief   Initialise the PLDM commnand list
 */
int pldm_command_init( void )
{
    int type_index = 0;
    int cmd_index  = 0;

    /*
     * Build the PLDM type and command supported parameters
     */
    if( PldmInitDone == 1 )
    {
        /*todo: Flag a warning */
        return 0;
    }

    /*
     * Do the PDR initiliazations
     */
    vPdrRepoInit();

    if( !CHECK_RANGE( MAX_PLDM_TYPE, 0, POSSIBLE_MAX_PLDM_TYPE ) )
    {
        /*
         * todo: Flag a warning
         * Assert, max pldm type cannot be more than possible max
         */
    }

    for(type_index = 0; type_index < MAX_PLDM_TYPE; type_index++)
    {
        Pldm_command_list *current_cmd_list = pldm_type_cmd[ type_index ];
        if( current_cmd_list != NULL )
        {
            Pldm_Type_Supported[ type_index / 8 ] |= ( 1 << ( type_index % 8 ) );
            for( ; current_cmd_list != NULL; current_cmd_list = current_cmd_list->next)
            {
                if( !CHECK_RANGE( ( int )current_cmd_list->max_command_id, 0, POSSIBLE_MAX_PLDM_CMD ) )
                {
                    /*
                     * Assert, max pldm cmd id cannot be more than possible max
                     */
                }

                for(cmd_index = 0; cmd_index < current_cmd_list->max_command_id; cmd_index++)
                {
                    if( current_cmd_list->funcList[ cmd_index ] )
                        current_cmd_list->Pldm_Command_Supported[ cmd_index / 8 ] |= ( 1 << ( cmd_index % 8 ) );
                }
            }
        }
    }

    PldmInitDone = 1;

    return 0;
}

/**
 * @brief   Get the PLDM Version ID
 */
static int get_pldm_version_id( const uint8_t *version )
{
    int id;
    int total_supported_ver = ARRAY_LEN( Pldm_Versions );

    for(id = 0; id < total_supported_ver; id++ )
    {
        int i = 0;
        for(i = 0; i < 4; i++)
        {
            if( version[ i ] != Pldm_Versions[ id ][ i ] )
            {
                break;
            }
        }
        if( i == 4 )
        {
            return id;
        }
    }
    return -1;                                                                 /*not supported version */
}

/**
 * @brief   Is the PLDM Type supported
 */
int IsPldmTypeSupported( const uint8_t type )
{
    if( !CHECK_RANGE( ( int )type, 0, MAX_PLDM_TYPE ) )
    {
        /*
         * todo: Flag error/warning
         */
        return 0;
    }

    if( pldm_type_cmd[ type ] == 0 )
    {
        /*
         * pldm type not supported
         */
        return 0;
    }

    /*
     * Type is supported
     */
    return 1;
}


/**
 * @brief   Get the PLDM function for the type
 */
int get_pldm_func( uint8_t pldm_type, uint8_t pldm_cmd, PldmFunction *func )
{
    Pldm_command_list *current_cmd_list = NULL;

    *func = NULL;

    if( !IsPldmTypeSupported( pldm_type ) )
    {
        /*
         * not supported pldm_type
         */
        return RESP_PLDM_ERROR_PLDM_TYPE_INV;
    }

    for(current_cmd_list = pldm_type_cmd[ pldm_type ]; current_cmd_list != NULL;
        current_cmd_list = current_cmd_list->next )
    {
        if( !CHECK_RANGE( ( int )pldm_cmd, 0x1, current_cmd_list->max_command_id ) )
        {
            /*
             * Not in this list
             */
            continue;
        }

        if( current_cmd_list->funcList[ pldm_cmd ] != NULL )
        {
            *func = current_cmd_list->funcList[ pldm_cmd ];
            return RESP_PLDM_SUCCESS;                                          // success
        }
    }

    /*
     * Not supported PLDM command
     */
    return RESP_PLDM_ERROR_PLDM_CMD_NS;
}

/**
 * @brief   Get PLDM Type Support
 */
int getPldmTypeSupport( uint8_t *typeSupported )
{
    int i;

    if( PldmInitDone == 0 )
    {
        /*
         * todo: Shouldn't be here. Flag warning
         */
        ( void )pldm_command_init();
    }

    for(i = 0; i < POSSIBLE_MAX_PLDM_TYPE / 8 ; i++)
    {
        typeSupported[ i ] = Pldm_Type_Supported[ i ];
    }

    return POSSIBLE_MAX_PLDM_TYPE / 8;
}

/**
 * @brief   Check if PLDM Version is supported
 */
int IsPldmVersionSupported( const uint8_t type, const uint8_t *ver )
{
    int               version_id        = 0;
    Pldm_command_list *current_cmd_list = NULL;

    if( !IsPldmTypeSupported( type ) )
    {
        /*
         * not supported pldm_type
         * todo: flag pldm type not supported
         */
        return 0;
    }

    version_id = get_pldm_version_id( ver );

    if( version_id == -1 )
    {
        /*
         * no such version supported
         */
        return 0;
    }

    for(current_cmd_list = pldm_type_cmd[ type ]; current_cmd_list; current_cmd_list = current_cmd_list->next )
    {
        if( current_cmd_list->version_id == version_id )
        {
            /* Version supported */
            return 1;
        }
    }

    /*
     * The version is not supported
     */
    return 0;
}

/**
 * @brief   Check if PLDM Version is supported
 */
int getPldmVersionSupport( const uint8_t type,
                           uint8_t *ver,
                           const uint32_t start_version,
                           const uint32_t num_version,
                           int *moreAvailable )
{
    int               i                 = 0;
    int               ret_size          = 0;
    Pldm_command_list *current_cmd_list = NULL;

    *moreAvailable = 0;

    if( !IsPldmTypeSupported( type ) )
    {
        /*
         * todo: Flag error/warning
         */
        return 0;
    }

    current_cmd_list = pldm_type_cmd[ type ];

    for(i = 0; i < start_version; i++)
    {
        /*
         * Skip previously reported versions
         */
        if( current_cmd_list )
        {
            current_cmd_list = current_cmd_list->next;
        }
        else
        {
            /*
             * Should never be here
             */
            return 0;
        }

    }

    for(i = 0; i < num_version; i++, current_cmd_list = current_cmd_list->next)
    {
        if( current_cmd_list )
        {
            int j;
            for(j = 0; j < 4; j++)
            {
                ver[ ret_size++ ] = Pldm_Versions[ current_cmd_list->version_id ][ j ];
            }
        }
        else
        {
            /* no further node available */
            *moreAvailable = 0;
            return ret_size;
        }
    }
    /*
     * todo: Assert i == num_version
     */
    if( current_cmd_list )
        *moreAvailable = 1;

    return ret_size;
}

/**
 * @brief   Check if PLDM Command is supported
 */
int getPldmCmdSupport( const uint8_t type, const uint8_t *ver, uint8_t *cmdSupported )
{
    Pldm_command_list *current_cmd_list = NULL;
    int               ret_size          = 0;
    int               version_id        = 0;

    /*
     * Todo: check if error codes can be communicated back instead of just 0
     */
    if( PldmInitDone == 0 )
    {
        /*
         * todo: Shouldn't be here. Flag warning
         */
        ( void )pldm_command_init();
    }

    if( !IsPldmTypeSupported( type ) )
    {
        /*
         * not supported pldm_type
         * todo: flag pldm type not supported
         * This checks should be done by the caller
         */
        return 0;
    }

    version_id = get_pldm_version_id( ver );

    if( version_id == -1 )
    {
        /*
         * no such version supported
         * This checks should be done by the caller
         */
        return 0;
    }

    for(current_cmd_list = pldm_type_cmd[ type ]; current_cmd_list; current_cmd_list = current_cmd_list->next )
    {
        if( current_cmd_list->version_id == version_id )
        {
            /* Version supported */
            break;
        }
    }

    if( current_cmd_list )
    {
        int i;
        for(i = 0; i < POSSIBLE_MAX_PLDM_CMD / 8 ; i++)
        {
            cmdSupported[ ret_size++ ] = current_cmd_list->Pldm_Command_Supported[ i ];
        }
    }
    else
    {
        /*
         * Should never be here.
         * Non supported versions will be caught earlier.
         */
    }

    return ret_size;
}
