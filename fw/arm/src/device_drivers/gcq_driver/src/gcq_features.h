/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains definitions for extended driver features.
 *
 * @file gcq_features.h
 *
 */

#ifndef _GCQ_FEATURES_H_
#define _GCQ_FEATURES_H_


/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/

#define GCQ_FEATURES_IS_IN_MEM_PTR( flags )              ( ( flags & GCQ_FLAGS_TYPE_IN_MEM_PTR_ENABLE ) != 0 )
#define GCQ_FEATURES_NEED_DOUBLE_MEM_READ( flags )       ( ( flags & GCQ_FLAGS_TYPE_DOUBLE_READ_ENABLE ) != 0 )
#define GCQ_FEATURES_DOUBLE_MEM_READ_RETRY_COUNT         ( 1000 )


/******************************************************************************/
/* Function Declarations                                                      */
/******************************************************************************/

/**
 *
 * @brief    Currently, this is only used as a workaround for the BRAM read/write
 *           collision HW issue on MB ERT, which will cause ERT to read incorrect value
 *           from CQ. We only trust the value until we read twice and got the same value.
 *
 * @param    pxGCQIOAccess is the bound in memory/register access functions
 * @param    ullAddr is the address to read
 *
 * @return   The value read after its been validated by reading more than once
 *
 * @note     Only used for memory accesses, not register
 *
 */
uint32_t ulGCQFeaturesHandleDoubleRead32( const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess, uint64_t ullAddr );


#endif /* _GCQ_FEATURES_H_ */
