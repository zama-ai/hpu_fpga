/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains API definitions for GCQ feature flags.
 *
 * @file gcq_features.c
 *
 */

#include "gcq_internal.h"


/*****************************************************************************/
/* Public Functions                                                          */
/*****************************************************************************/

/**
 *
 * @brief    Currently, this is only used as a workaround for the BRAM read/write
 *           collision HW issue on MB ERT, which will cause ERT to read incorrect value
 *           from CQ. We only trust the value until we read twice and got the same value.
 *
 */
uint32_t ulGCQFeaturesHandleDoubleRead32( const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess, uint64_t ullAddr )
{
    gcq_assert( pxGCQIOAccess );
    {
        uint32_t ulValue[ 2 ] = { 0 };
        int i = 0;

        /* Taken directly from previous implementation */
        ulValue[ 1 ] = pxGCQIOAccess->xGCQReadMem32( ullAddr );
        ulValue[ 0 ] = ( ulValue[ 1 ] - 1 );
        while( ulValue[ 0 ] != ulValue[ 1 ] )
        {
            ulValue[ i++ & 0x1 ] = pxGCQIOAccess->xGCQReadMem32( ullAddr );

            if( GCQ_FEATURES_DOUBLE_MEM_READ_RETRY_COUNT < i ) 
            {
                gcq_assert( 0 );
                break;
            }
        }

        return ( ulValue[ 0 ] );
    }
}
