/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains private definitions for the GCQ driver.
 *
 * @file gcq_internal.h
 *
 */

#ifndef _GCQ_INTERNAL_H_
#define _GCQ_INTERNAL_H_

#ifndef __KERNEL__
#include <stddef.h>
#include <assert.h>
#endif
#include "gcq.h"
#include "gcq_debug.h"
#include "gcq_regmap.h"
#include "gcq_hw.h"
#include "gcq_features.h"
#include "gcq_version.h"
#include "gcq_ring.h"


/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/

#define GCQ_TRUE                                        ( 1 )
#define GCQ_FALSE                                       ( 0 )

#define GCQ_VERSION                                     ( ( GIT_TAG_VER_MAJOR << 16 ) + GIT_TAG_VER_MINOR )
#define GET_GCQ_MAJOR( version )                        ( version >> 16 )
#define GET_GCQ_MINOR( version )                        ( version & 0xFFFF )

#define GCQ_ALLOC_MAGIC                                 ( 0x5847513F )
#define GCQ_MIN_NUM_SLOTS                               ( 2 )

#define CHECK_INSTANCE( f )                             ( NULL == f )
#define CHECK_NULL( f )                                 ( NULL == f )
#define CHECK_NOT_NULL( f )                             ( NULL != f )
#define CHECK_REG_IO_ACCESS( f )                        ( ( NULL == f->xGCQReadReg32 ) || \
                                                          ( NULL == f->xGCQWriteReg32 ) || \
                                                          ( NULL == f->xGCQReadMem32 ) || \
                                                          ( NULL == f->xGCQWriteMem32 ) )

#define GCQ_MODE_NAME_ENTRY( _s )                       [ GCQ_MODE_TYPE_ ## _s ] = #_s
static const char* const pcGCQModeStr[ ]            =   {  GCQ_MODE_NAME_ENTRY( CONSUMER_MODE ),
                                                           GCQ_MODE_NAME_ENTRY( PRODUCER_MODE ) };
#define GCQ_INTERRUPT_MODE_NAME_ENTRY( _s )             [ GCQ_INTERRUPT_MODE_ ## _s ] = #_s
static const char* const pcGCQInterruptModeStr[ ]   =   {  GCQ_INTERRUPT_MODE_NAME_ENTRY( POLLING ),
                                                           GCQ_INTERRUPT_MODE_NAME_ENTRY( TAIL_POINTER ),
                                                           GCQ_INTERRUPT_MODE_NAME_ENTRY( INTERRUPT_REG ) };


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct GCQ_RING_TYPE
 * 
 * @brief  Forward declaration of GCQ_RING_TYPE, used to model the ring buffer.
 * 
 */
struct GCQ_RING_TYPE;

/**
 * @struct  GCQ_TYPE
 * 
 * @brief   Instance of an GCQ_TYPE, used to model the GCQ IP Block.
 * 
 */
typedef struct GCQ_INSTANCE_TYPE
{
    uint32_t ulUpperFirewall;
    int      iInitialised;
    uint64_t ullBaseAddr;
    GCQ_MODE_TYPE xMode;
    GCQ_INTERRUPT_MODE_TYPE xIntMode;
    const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess;
    uint64_t ullRingAddr;
    uint32_t ulConsumerSlotSize;
    uint32_t ulProducerSlotSize;
    uint64_t ullGCQHeaderAddr;
    GCQ_FLAGS_TYPE xGCQFlags;
    #ifdef __KERNEL__
        struct GCQ_RING_TYPE xGCQSq; ____cacheline_aligned_in_smp
        struct GCQ_RING_TYPE xGCQCq; ____cacheline_aligned_in_smp
    #else
        struct GCQ_RING_TYPE xGCQSq;
        struct GCQ_RING_TYPE xGCQCq;
    #endif
    struct GCQ_RING_TYPE *pxGCQProducer;
    struct GCQ_RING_TYPE *pxGCQConsumer;
    uint32_t ulLowerFirewall;

} GCQ_INSTANCE_TYPE;


#endif /* _GCQ_INTERNAL_H_ */
