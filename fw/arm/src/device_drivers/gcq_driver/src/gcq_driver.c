/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the user API definitions for the GCQ driver.
 *
 * @file gcq_driver.c
 *
 */

#ifndef __KERNEL__
#include "util.h"
#include "osal.h"
#endif

#include "gcq_internal.h"


/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/

#define GCQ_INSTANCE_UPPER_FIREWALL     ( 0xBEEFCAFE )
#define GCQ_INSTANCE_LOWER_FIREWALL     ( 0xDEADFACE )

#define CHECK_ATTACHED( f )             ( ( GCQ_MODE_TYPE_CONSUMER_MODE == f->xMode ) && ( GCQ_FALSE == pxThis->ucConsumerAttached ) )
#define CHECK_FIREWALLS( f )            ( ( f->ulUpperFirewall != GCQ_INSTANCE_UPPER_FIREWALL ) && \
                                          ( f->ulLowerFirewall != GCQ_INSTANCE_LOWER_FIREWALL ) )

#define CHECK_32BIT_ALIGNMENT( x )      ( 0 == ( x & 0x3 ) )


/*****************************************************************************/
/* Enums                                                                     */
/*****************************************************************************/


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 *    @struct  GCQ_PRIVATE_DATA
 * 
 *    @brief   Structure to hold ths driver's private data
 *
 *    @note    Initialisation status is checked per instance.
 *
 */
typedef struct GCQ_PRIVATE_DATA
{
    uint32_t            ulUpperFirewall;
 
    uint8_t             ucConsumerAttached;
    uint8_t             ucInstancesAllocated;
    GCQ_INSTANCE_TYPE   xGCQInstances[ GCQ_MAX_INSTANCES ];
    
    uint32_t            ulLowerFirewall;

} GCQ_PRIVATE_DATA;


/*****************************************************************************/
/* Local Variables                                                           */
/*****************************************************************************/

static GCQ_PRIVATE_DATA xLocalData =
{
    GCQ_INSTANCE_UPPER_FIREWALL,     /* ulUpperFirewall */

    GCQ_FALSE,                       /* ucConsumerAttached */
    0,                               /* ucInstancesAllocated */
    { { 0 } },                       /* xGCQInstances */

    GCQ_INSTANCE_LOWER_FIREWALL      /* ulLowerFirewall */
};
static GCQ_PRIVATE_DATA *pxThis = &xLocalData;


/*****************************************************************************/
/* Private Functions                                                          */
/*****************************************************************************/

/**
 *
 * @brief   Calculate the number of slots that can be allocated based on
 *          the length of the ring and the SQ & CQ slot sizes
 *
 * @param   ullRingLen is the ring buffer length
 * @param   ulSQSlotSize is the SQ slot size
 * @param   ulCQSlotSize is the CQ slot size
 *
 * @return  the number of slots that can be allocated
 *
 */
static inline uint32_t prvulGCQAllocNumSlots( uint64_t ullRingLen,
                                              const uint32_t ulSQSlotSize,
                                              const uint32_t ulCQSlotSize )
{
    uint32_t ulTotalLen = 0;
    uint32_t ulNumSlots = 1;

    while( ulTotalLen <= ullRingLen )
    {
        /* Allocate an even number of slots starting at 2 */
        ulNumSlots <<= 1;

        /* The ring length is based on the ring header plus a number of SQ/CQ slots */
        ulTotalLen = prvulGCQRingLen( ulNumSlots, ulSQSlotSize, ulCQSlotSize );
    }

    return ( ulNumSlots >> 1 );
}

/**
 *
 * @brief   Fast forward both the producer & consumer
 *
 * @param   pxGCQInstance the gcq driver instance
 * @param   pxRing the sq or cq ring buffer
 *
 * @return  N/A
 * 
 */
static inline void prvvGCQFastForward( const GCQ_INSTANCE_TYPE *pxGCQInstance, struct GCQ_RING_TYPE *pxRing )
{
    gcq_assert( pxGCQInstance );
    gcq_assert( pxRing );

    prvvGCQRingReadProduced( pxGCQInstance->pxGCQIOAccess, pxGCQInstance->xGCQFlags, pxRing );
    prvvGCQRingReadConsumed( pxGCQInstance->pxGCQIOAccess, pxGCQInstance->xGCQFlags, pxRing );
}

/**
 *
 * @brief   Check if the producer has any more free slots
 *
 * @param   pxGCQInstance the gcq driver instance
 * @param   pxRing the sq or cq ring buffer
 *
 * @return  returns true if can produce
 * 
 */
static inline uint32_t prvucGCQCanProduce( const GCQ_INSTANCE_TYPE *pxGCQInstance, struct GCQ_RING_TYPE *pxRing )
{
    uint32_t ulStatus = GCQ_FALSE;

    if( ( GCQ_FALSE == CHECK_NULL( pxGCQInstance ) ) || 
        ( GCQ_FALSE == CHECK_NULL( pxRing ) ) )
    {
        if( GCQ_FALSE == likely( prvucGCQRingIsFull( pxRing ) ) )
        {
            ulStatus = GCQ_TRUE;
        }
        else
        {
            prvvGCQRingReadConsumed( pxGCQInstance->pxGCQIOAccess, pxGCQInstance->xGCQFlags, pxRing );
            ulStatus = ( GCQ_FALSE == prvucGCQRingIsFull( pxRing ) );
        }
    }

    return ( ulStatus );
}

/**
 *
 * @brief   Check if the consumer has data that can be consumed
 *
 * @param   pxGCQInstance the gcq driver instance
 * @param   pxRing the sq or cq ring buffer
 *
 * @return  returns GCQ_TRUE if data can be consumed
 *
 */
static inline uint32_t prvucGCQCanConsume( const GCQ_INSTANCE_TYPE *pxGCQInstance, struct GCQ_RING_TYPE *pxRing )
{
    uint32_t ulStatus = GCQ_FALSE;

    if( ( GCQ_FALSE == CHECK_NULL( pxGCQInstance ) ) || 
        ( GCQ_FALSE == CHECK_NULL( pxRing ) ) )
    {
        /* Check for errors */
        uint32_t ulSqTailPointer = pxGCQInstance->pxGCQIOAccess->xGCQReadReg32(
            pxGCQInstance->ullBaseAddr + GCQ_PRODUCER_SQ_TAIL_POINTER
        );

        uint32_t ulCqTailPointer = pxGCQInstance->pxGCQIOAccess->xGCQReadReg32(
            pxGCQInstance->ullBaseAddr + GCQ_PRODUCER_CQ_TAIL_POINTER
        );

        if ( unlikely( ( ( uint32_t )-1 == ulSqTailPointer ) && ( ( uint32_t )-1 == ulCqTailPointer ) ) )
        {
            ulStatus = GCQ_FALSE;
        }
        else if( GCQ_FALSE == likely( prvucGCQRingIsEmpty( pxRing ) ) )
        {
            ulStatus = GCQ_TRUE;
        }
        else
        {
            prvvGCQRingReadProduced( pxGCQInstance->pxGCQIOAccess, pxGCQInstance->xGCQFlags, pxRing );
            ulStatus = ( GCQ_FALSE == prvucGCQRingIsEmpty( pxRing ) );
        }
    }

    return ( ulStatus );
}

/**
 *
 * @brief   Set consumed to be the same as produced to ignore any existing
 *          commands.
 *
 * @param   pxGCQInstance the gcq driver instance
 * @param   pxRing the sq or cq ring buffer
 *
 * @return  N/A
 *
 */
static inline void prvvGCQSoftReset( const GCQ_INSTANCE_TYPE *pxGCQInstance, struct GCQ_RING_TYPE *pxRing )
{
    gcq_assert( pxGCQInstance );
    gcq_assert( pxRing );

    prvvGCQRingReadProduced( pxGCQInstance->pxGCQIOAccess, pxGCQInstance->xGCQFlags, pxRing );
    pxRing->ulRingConsumed = pxRing->ulRingProduced;
    prvvGCQRingWriteConsumed( pxGCQInstance->pxGCQIOAccess, pxGCQInstance->xGCQFlags, pxRing );
}

/**
 *
 * @brief   Attempt to add data into the producer, can fail if no more
 *          free slots
 *
 * @param   pxGCQInstance the gcq driver instance
 * @param   ullSlotAddr is the slot address
 *
 * @return  returns GCQ_TRUE if produced else error
 *
 */
static inline GCQ_ERRORS_TYPE prvxGCQProduce( GCQ_INSTANCE_TYPE *pxGCQInstance, uint64_t *ullSlotAddr )
{
    GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_NONE;

    if( ( CHECK_NULL( pxGCQInstance ) ) || 
        ( CHECK_NULL( ullSlotAddr ) ) )
    {
        xStatus = GCQ_ERRORS_INVALID_ARG;
    }

    if( GCQ_ERRORS_NONE == xStatus)
    {
        struct GCQ_RING_TYPE *pxRing = NULL;

        /* Bind into the correct ring buffer */
        pxRing = pxGCQInstance->pxGCQProducer;

        /* Check if there is a free slot */
        if( GCQ_TRUE == likely( prvucGCQCanProduce( pxGCQInstance, pxRing ) ) )
        {
            *ullSlotAddr = prvullGCQRingGetSlotPtrProduced( pxRing );
            pxRing->ulRingProduced++;
        }
        else
        {
            xStatus = GCQ_ERRORS_PRODUCER_NO_FREE_SLOTS;
        }
    }

    return xStatus;
}


/**
 *
 * @brief   Attempt to consume data from the consumer, can fail is no data
 *          is available to read
 *
 * @param   pxGCQInstance the gcq driver instance
 * @param   ullSlotAddr is the slot address
 *
 * @return  returns GCQ_TRUE if consumed else error
 *
 */
static inline GCQ_ERRORS_TYPE prvxGCQConsume( GCQ_INSTANCE_TYPE *pxGCQInstance, uint64_t *ullSlotAddr )
{
    GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_NONE;

    if( ( CHECK_NULL( pxGCQInstance ) ) || 
        ( CHECK_NULL( ullSlotAddr ) ) )
    {
        xStatus = GCQ_ERRORS_INVALID_ARG;
    }

    if( GCQ_ERRORS_NONE == xStatus )
    {
        struct GCQ_RING_TYPE *pxRing = NULL;

        /* Bind into the correct ring */
        pxRing = pxGCQInstance->pxGCQConsumer;

        if( GCQ_TRUE == likely( prvucGCQCanConsume( pxGCQInstance, pxRing ) ) )
        {
            *ullSlotAddr = prvullGCQRingGetSlotPtrConsumed( pxRing );
            pxRing->ulRingConsumed++;
        }
        else
        {
            xStatus = GCQ_ERRORS_CONSUMER_NO_DATA_RECEIVED;
        } 
    }

    return xStatus;
}

/**
 *
 * @brief   Attempt to find an uninitialized GCQ instance
 *
 * @param   ppxGCQInstance variable to store the gcq driver instance
 *
 * @return  returns GCQ_ERRORS_NONE if instance found, error otherwise
 *
 */
static inline GCQ_ERRORS_TYPE prviGCQFindNextFreeInstance( struct GCQ_INSTANCE_TYPE **ppxGCQInstance )
{
    GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_NO_FREE_INSTANCES;

    if( CHECK_NULL( ppxGCQInstance ) || CHECK_NOT_NULL( *ppxGCQInstance ) ) 
    {
        xStatus = GCQ_ERRORS_INVALID_ARG;
    }
    else if( pxThis->ucInstancesAllocated < GCQ_MAX_INSTANCES )
    {
        int iIndex = 0;
        for( iIndex = 0; iIndex < GCQ_MAX_INSTANCES; iIndex++ )
        {
            if( GCQ_FALSE == pxThis->xGCQInstances[ iIndex ].iInitialised )
            {
                *ppxGCQInstance = &pxThis->xGCQInstances[ iIndex ];
                xStatus = GCQ_ERRORS_NONE;
                break;
            }
        }
    }

    return xStatus;
}

/*****************************************************************************/
/* Public Functions                                                          */
/*****************************************************************************/

/**
 *
 * @brief    Initialise the GCQ standalone driver
 *
 */
GCQ_ERRORS_TYPE xGCQInit( struct GCQ_INSTANCE_TYPE **ppxGCQInstance,
                          const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess,
                          GCQ_MODE_TYPE xMode,
                          GCQ_INTERRUPT_MODE_TYPE xIntMode,
                          GCQ_FLAGS_TYPE xflags,
                          uint64_t ullBaseAddr,
                          uint64_t ullRingAddr,
                          uint64_t ullRingLen,
                          uint32_t ulSQSlotSize,
                          uint32_t ulCQSlotSize )
{
    GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_INVALID_ARG;

    struct GCQ_HEADER_TYPE xGCQHeader = { };
    uint32_t ullNumSlots = 0;

    if( ( GCQ_INSTANCE_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( GCQ_INSTANCE_LOWER_FIREWALL == pxThis->ulLowerFirewall ) ) 
    {
        xStatus = GCQ_ERRORS_NONE;

        if( CHECK_NOT_NULL( *ppxGCQInstance ) ) 
        {
            xStatus = GCQ_ERRORS_INVALID_ARG;
        }

        if( CHECK_REG_IO_ACCESS( pxGCQIOAccess ) ) 
        {
            xStatus = GCQ_ERRORS_INVALID_ARG;
        }

        /* Find the next free instance */
        if( GCQ_ERRORS_NONE == xStatus )
        {
            xStatus = prviGCQFindNextFreeInstance( ppxGCQInstance );
        }

        /* Slot Validation */
        if( GCQ_ERRORS_NONE == xStatus )
        {
            if( ( ulSQSlotSize % sizeof( uint32_t ) ) ||
                ( ulCQSlotSize % sizeof( uint32_t ) ) )
            {
                GCQ_DEBUG( "Error: Invalid SQ/CQ slot size specified, needs to be 32-bit aligned!\r\n" );
                xStatus = GCQ_ERRORS_INVALID_SLOT_SIZE;
            }
            else if( ( 0 == ulSQSlotSize ) ||
                     ( 0 == ulCQSlotSize ) )
            {
                GCQ_DEBUG( "Error: Invalid SQ/CQ slot size specified, zero is not a valid value\r\n" );
                xStatus = GCQ_ERRORS_INVALID_SLOT_SIZE;
            }


            if( GCQ_ERRORS_NONE == xStatus )
            {
                ullNumSlots = prvulGCQAllocNumSlots( ullRingLen, ulSQSlotSize, ulCQSlotSize );
                if( ullNumSlots < GCQ_MIN_NUM_SLOTS )
                {
                    GCQ_DEBUG( "Error: Number of slots calculated less than minimum supported value of %d\r\n", GCQ_MIN_NUM_SLOTS );
                    xStatus = GCQ_ERRORS_INVALID_NUM_SLOTS;
                }
            }
        }

        /* Populate the Instance data */
        if( GCQ_ERRORS_NONE == xStatus )
        {
            uint64_t ullCQProduced = 0;
            uint64_t ullSQProduced = 0;

            /* Init IP block and configure interrupt mode */
            xGCQHWInit(xMode, ullBaseAddr, ullRingAddr, pxGCQIOAccess );
            xGCQHWConfigureInterruptMode( xMode, xIntMode, ullBaseAddr, pxGCQIOAccess );

            if( GCQ_MODE_TYPE_PRODUCER_MODE == xMode )
            {
                ( *ppxGCQInstance )->ulProducerSlotSize = ulCQSlotSize;
                ( *ppxGCQInstance )->ulConsumerSlotSize = ulSQSlotSize;
                /* In producer mode we produce onto the CQ and consume from the SQ */
                ( *ppxGCQInstance )->pxGCQProducer = &( *ppxGCQInstance )->xGCQCq;
                ( *ppxGCQInstance )->pxGCQConsumer = &( *ppxGCQInstance )->xGCQSq;
                /* Set the producer address based on producer AXI register map */
                ullCQProduced = ( ullBaseAddr + GCQ_PRODUCER_SQ_TAIL_POINTER );
                ullSQProduced = ( ullBaseAddr + GCQ_PRODUCER_CQ_TAIL_POINTER );
            }
            else
            {
                ( *ppxGCQInstance )->ulProducerSlotSize = ulSQSlotSize;
                ( *ppxGCQInstance )->ulConsumerSlotSize = ulCQSlotSize;
                /* In consumer mode we produce onto the SQ and consume from the CQ */
                ( *ppxGCQInstance )->pxGCQProducer = &( *ppxGCQInstance )->xGCQSq;
                ( *ppxGCQInstance )->pxGCQConsumer = &( *ppxGCQInstance )->xGCQCq;
                /* Set the producer address based on consumer AXI register map */
                ullCQProduced = ( ullBaseAddr + GCQ_CONSUMER_SQ_TAIL_POINTER );
                ullSQProduced = ( ullBaseAddr + GCQ_CONSUMER_CQ_TAIL_POINTER );
            }

            /* Check if memory pointers are being used and override */
            if( GCQ_FEATURES_IS_IN_MEM_PTR( xflags ) )
            {
                /* Passed-in SQ/CQ producer pointer will be ignored. */
                ullSQProduced = ullRingAddr + offsetof( struct GCQ_HEADER_TYPE, ulHdrSQProduced );
                ullCQProduced = ullRingAddr + offsetof( struct GCQ_HEADER_TYPE, ulHdrCQProduced );
            }

            /* Init SQ & CQ rings */
            GCQ_DEBUG( "GCQ Init Ring SQ\r\n" );
            prvvGCQInitRing( *ppxGCQInstance,
                                &( *ppxGCQInstance )->xGCQSq,
                                ullSQProduced,
                                ullRingAddr + offsetof( struct GCQ_HEADER_TYPE, ulHdrSQConsumed ),
                                ullRingAddr + sizeof( struct GCQ_HEADER_TYPE ),
                                ullNumSlots,
                                ulSQSlotSize);
            GCQ_DEBUG( "GCQ Init Ring CQ\r\n" );
            prvvGCQInitRing( *ppxGCQInstance,
                                &( *ppxGCQInstance )->xGCQCq,
                                ullCQProduced,
                                ullRingAddr + offsetof( struct GCQ_HEADER_TYPE, ulHdrCQConsumed ),
                                ullRingAddr + sizeof( struct GCQ_HEADER_TYPE ) + ullNumSlots * ulSQSlotSize,
                                ullNumSlots,
                                ulCQSlotSize );

            ( *ppxGCQInstance )->iInitialised = GCQ_FALSE;
            ( *ppxGCQInstance )->xMode = xMode;
            ( *ppxGCQInstance )->xIntMode = xIntMode;
            ( *ppxGCQInstance )->xGCQFlags = xflags;
            ( *ppxGCQInstance )->ullGCQHeaderAddr = ullRingAddr;
            ( *ppxGCQInstance )->ullBaseAddr = ullBaseAddr;
            ( *ppxGCQInstance )->ullRingAddr = ullRingAddr;
            ( *ppxGCQInstance )->pxGCQIOAccess = pxGCQIOAccess;
            ( *ppxGCQInstance )->ulUpperFirewall = GCQ_INSTANCE_UPPER_FIREWALL;
            ( *ppxGCQInstance )->ulLowerFirewall = GCQ_INSTANCE_LOWER_FIREWALL;

            /* If producer mode then populate the header onto the ring */
            if( GCQ_MODE_TYPE_PRODUCER_MODE == xMode )
            {
                xGCQHeader.ulHdrMagic = 0;
                xGCQHeader.ulHdrVersion = GCQ_VERSION;
                xGCQHeader.ulHdrSlotNum = ullNumSlots;
                xGCQHeader.ulHdrSQOffset = ( ( *ppxGCQInstance )->xGCQSq.ullRingSlotAddr - ullRingAddr );
                xGCQHeader.ulHdrSQSlotSize = ulSQSlotSize;
                xGCQHeader.ulHdrCQOffset = ( ( *ppxGCQInstance )->xGCQCq.ullRingSlotAddr - ullRingAddr );
                xGCQHeader.ulHdrSQConsumed = 0;
                xGCQHeader.ulHdrCQConsumed = 0;

                /* Write the header to the ring buffer */
                prvvGCQCopyToRing( pxGCQIOAccess, ( uint8_t* )&xGCQHeader, ullRingAddr, sizeof( struct GCQ_HEADER_TYPE ) );
                prvvGCQSoftReset( ( *ppxGCQInstance ), &( *ppxGCQInstance )->xGCQSq );
                prvvGCQSoftReset( ( *ppxGCQInstance ), &( *ppxGCQInstance )->xGCQCq );

                /* Write the magic number to confirm the header is fully initialized */
                xGCQHeader.ulHdrMagic = GCQ_ALLOC_MAGIC;
                prvvGCQCopyToRing( pxGCQIOAccess, ( uint8_t* )&xGCQHeader, ullRingAddr, sizeof( uint32_t ) );
            }

            /* Set flag to show initialisation complete */
            ( *ppxGCQInstance )->iInitialised = GCQ_TRUE;
            pxThis->ucInstancesAllocated++;
        }
    }

    return xStatus;
}

/**
 *
 * @brief    De-initialise a GCQ driver instance
 *
 */
GCQ_ERRORS_TYPE xGCQDeinit( struct GCQ_INSTANCE_TYPE *pxGCQInstance )
{
    GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_INVALID_ARG;

    if( ( GCQ_INSTANCE_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( GCQ_INSTANCE_LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        xStatus = GCQ_ERRORS_NONE;

        if( ( CHECK_INSTANCE( pxGCQInstance ) ) || ( GCQ_FALSE == pxGCQInstance->iInitialised ) ) 
        {
            xStatus = GCQ_ERRORS_INVALID_INSTANCE; 
        }
        else
        {
            pxGCQInstance->iInitialised = GCQ_FALSE;
            pxThis->ucInstancesAllocated--;
        }
    }

    return xStatus;
}

/**
 *
 * @brief    Attempt to attach to the consumer, needs to be called before
 *           data can be consumed.
 *
 */
GCQ_ERRORS_TYPE xGCQAttachConsumer( struct GCQ_INSTANCE_TYPE *pxGCQInstance )
{
    GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_INVALID_ARG;

    struct GCQ_HEADER_TYPE xGCQHeader = { };

    if( ( GCQ_INSTANCE_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( GCQ_INSTANCE_LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        xStatus = GCQ_ERRORS_NONE;

        if( ( CHECK_INSTANCE( pxGCQInstance ) ) || ( GCQ_FALSE == pxGCQInstance->iInitialised ) ) 
        {
            xStatus = GCQ_ERRORS_INVALID_INSTANCE; 
        }

        if( GCQ_ERRORS_NONE == xStatus )
        {
            /* Copy header from the ring buffer */
            prvvGCQCopyFromRing( pxGCQInstance->pxGCQIOAccess, ( uint8_t* )&xGCQHeader, pxGCQInstance->ullRingAddr, sizeof( uint32_t ) );

            /* Magic number must show up to confirm the header is fully initialized */
            if( xGCQHeader.ulHdrMagic != GCQ_ALLOC_MAGIC )
            {
                xStatus = GCQ_ERRORS_CONSUMER_NOT_AVAILABLE;
            }
        }

        /* Check the version within the header is as expected */
        if( GCQ_ERRORS_NONE == xStatus )
        {
            prvvGCQCopyFromRing( pxGCQInstance->pxGCQIOAccess, ( uint8_t* )&xGCQHeader, pxGCQInstance->ullRingAddr, sizeof( struct GCQ_HEADER_TYPE ) );
            
            if( GIT_TAG_VER_MAJOR != GET_GCQ_MAJOR( xGCQHeader.ulHdrVersion ) )
            {
                GCQ_DEBUG( "Error: Unexpected version:0x%lx in magic header!\r\n", xGCQHeader.ulHdrVersion );
                xStatus = GCQ_ERRORS_INVALID_VERSION;
            }
            else
            {
                GCQ_DEBUG( "Version: 0x%lx 0x%lx\n", GET_GCQ_MAJOR( xGCQHeader.ulHdrVersion ), GET_GCQ_MINOR( xGCQHeader.ulHdrVersion ) );
            }
        }

        /* Validate the number of slots matches */
        if( GCQ_ERRORS_NONE == xStatus )
        {
            uint32_t ullHdrNumSlots = xGCQHeader.ulHdrSlotNum;
            uint32_t ullNumSlots = pxGCQInstance->xGCQSq.ulRingSlotNum;
            
            if( ullNumSlots != ullHdrNumSlots )
            {
                GCQ_DEBUG( "Error: Invalid number of slots:%ld found in magic header, expecting: %ld!!\r\n", ullHdrNumSlots, ullNumSlots );
                xStatus = GCQ_ERRORS_INVALID_NUM_SLOTS;
            }
        }

        /* Validate the slot size matches */
        if( GCQ_ERRORS_NONE == xStatus )
        {
            uint32_t ulHdrSlotSize = xGCQHeader.ulHdrSQSlotSize;
            uint32_t ulRingSlotSize = pxGCQInstance->xGCQSq.ulRingSlotSize;
            if( ulRingSlotSize != ulHdrSlotSize )
            {
                GCQ_DEBUG( "Error: Invalid slot size:%ld found in magic header, expecting: %ld!\r\n", ulHdrSlotSize, ulRingSlotSize );
                xStatus = GCQ_ERRORS_INVALID_SLOT_SIZE;
            }
        }

        if( GCQ_ERRORS_NONE == xStatus )
        {
            prvvGCQFastForward( pxGCQInstance, &pxGCQInstance->xGCQSq );
            prvvGCQFastForward( pxGCQInstance, &pxGCQInstance->xGCQCq );

            /* Set flag to show now attached */
            pxThis->ucConsumerAttached = GCQ_TRUE;
        }
    }

    return xStatus;
}

/**
 * 
 * @brief    Function to consume data from the ring buffer
 * 
 */
GCQ_ERRORS_TYPE xGCQConsumeData( struct GCQ_INSTANCE_TYPE *pxGCQInstance, uint8_t *pucData, uint32_t ulDataLen )
{
    GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_INVALID_ARG;

    uint64_t ullSlotAddr = 0;

    if( ( GCQ_INSTANCE_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( GCQ_INSTANCE_LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        xStatus = GCQ_ERRORS_NONE;

        if( ( CHECK_INSTANCE( pxGCQInstance ) ) || ( GCQ_FALSE == pxGCQInstance->iInitialised ) ) 
        {
            xStatus = GCQ_ERRORS_INVALID_INSTANCE; 
        }

        if( CHECK_ATTACHED( pxGCQInstance ) ) 
        { 
            xStatus = GCQ_ERRORS_CONSUMER_NOT_ATTACHED; 
        }

        if( CHECK_NULL( pucData ) ) 
        { 
            xStatus = GCQ_ERRORS_INVALID_ARG; 
        }

        if ( !CHECK_32BIT_ALIGNMENT( ulDataLen ) ) 
        { 
            GCQ_DEBUG( " Error: length 0x%lx is not 32bit aligned\r\n", ulDataLen );
            xStatus = GCQ_ERRORS_INVALID_ARG; 
        }

        if( ulDataLen > pxGCQInstance->ulConsumerSlotSize )
        {
            GCQ_DEBUG( " Error: length 0x%lx specified is larger than slot configured\r\n", ulDataLen );
            xStatus = GCQ_ERRORS_INVALID_ARG;
        }

        if( GCQ_ERRORS_NONE == xStatus )
        {
            /* Attempt to consume data if any is available */
            xStatus = prvxGCQConsume( pxGCQInstance, &ullSlotAddr );
        }

        if( GCQ_ERRORS_NONE == xStatus )
        {
            int offset;
            GCQ_DEBUG( "Read data from slot addr:0x%llx len:%ld\r\n", ullSlotAddr, ulDataLen );

            /* Process the data & populate the return buffer */
            for( offset = 0; offset < ulDataLen; offset += 4 )
            {
                *( uint32_t *)( pucData + offset ) = pxGCQInstance->pxGCQIOAccess->xGCQReadMem32( ullSlotAddr + offset );
                GCQ_DEBUG( "Read addr:0x%llx val:0x%lx\r\n", ullSlotAddr + offset, *( uint32_t* )( pucData + offset ) );
            }

            /* Notify the peer the data has been consumed */
            prvvGCQRingWriteConsumed( pxGCQInstance->pxGCQIOAccess, pxGCQInstance->xGCQFlags, pxGCQInstance->pxGCQConsumer );


            if( ( GCQ_INTERRUPT_MODE_INTERRUPT_REG == pxGCQInstance->xIntMode ) )
            {
                /* Once triggered the interrupt is cleared by reading the interrupt status field */
                xStatus = xGCQHWClearInterrupt( pxGCQInstance->xMode,
                                                pxGCQInstance->ullBaseAddr,
                                                pxGCQInstance->pxGCQIOAccess );
            }
        }
    }

    return xStatus;
}


/**
 *
 * @brief    Function to provide data and populate the ring buffer
 * 
 */
GCQ_ERRORS_TYPE xGCQProduceData( struct GCQ_INSTANCE_TYPE *pxGCQInstance, uint8_t * pucData, uint32_t ulDataLen )
{
    GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_INVALID_ARG;

    uint64_t ullSlotAddr = 0;

    if( ( GCQ_INSTANCE_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( GCQ_INSTANCE_LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        xStatus = GCQ_ERRORS_NONE;

        if( ( CHECK_INSTANCE( pxGCQInstance ) ) || ( GCQ_FALSE == pxGCQInstance->iInitialised ) ) 
        {
            xStatus = GCQ_ERRORS_INVALID_INSTANCE; 
        }
        
        if( CHECK_NULL( pucData ) ) 
        {
            xStatus = GCQ_ERRORS_INVALID_ARG; 
        }
        
        if( !CHECK_32BIT_ALIGNMENT( ulDataLen ) ) 
        {
            GCQ_DEBUG( " Error: length 0x%lx is not 32bit aligned\r\n", ulDataLen );
            xStatus = GCQ_ERRORS_INVALID_ARG; 
        }

        if( ulDataLen > pxGCQInstance->ulProducerSlotSize )
        {
            GCQ_DEBUG( " Error: length 0x%lx specified is larger than slot configured\r\n", ulDataLen );
            xStatus = GCQ_ERRORS_INVALID_ARG;
        }

        if( GCQ_ERRORS_NONE == xStatus )
        {
            xStatus = prvxGCQProduce( pxGCQInstance, &ullSlotAddr );
        }

        if( GCQ_ERRORS_NONE == xStatus )
        {
            int offset = 0;
            GCQ_DEBUG( "Write data to slot addr:0x%llx len:%ld\r\n", ullSlotAddr, ulDataLen );

            for( offset = 0; offset < ulDataLen; offset += 4 )
            {
                pxGCQInstance->pxGCQIOAccess->xGCQWriteMem32( ullSlotAddr + offset, *( uint32_t * )( pucData + offset ) );
                GCQ_DEBUG( "Write addr:0x%llx val:0x%lx\r\n", ullSlotAddr + offset, *( uint32_t * )( pucData + offset ) );
            }

            prvvGCQRingWriteProduced( pxGCQInstance->pxGCQIOAccess, pxGCQInstance->xGCQFlags, pxGCQInstance->pxGCQProducer );

            if( GCQ_INTERRUPT_MODE_INTERRUPT_REG == pxGCQInstance->xIntMode )
            {
                xStatus = xGCQHWTriggerInterrupt( pxGCQInstance->xMode,
                                                pxGCQInstance->ullBaseAddr,
                                                pxGCQInstance->pxGCQIOAccess );
                
                if( GCQ_ERRORS_NONE != xStatus )
                {
                    GCQ_DEBUG( "Error: Interrupt trigger failed with status: %d\r\n", xStatus );
                }
            }
        }
        else
        {
            GCQ_DEBUG( "Error: Failed to add data into slot: %d\r\n", xStatus );
        }
    }

    return xStatus;
}

/**
 *
 * @brief    Sets this modules version information
 * 
 */
int iGCQGetVersion( GCQ_VERSION_TYPE *pxVersion )
{
    int iStatus = GCQ_ERRORS_INVALID_ARG;

    if( ( GCQ_INSTANCE_UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( GCQ_INSTANCE_LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxVersion ) )
    {

        pxVersion->ucVerMajor   = GIT_TAG_VER_MAJOR;
        pxVersion->ucVerMinor   = GIT_TAG_VER_MINOR;
        pxVersion->ucVerPatch   = GIT_TAG_VER_PATCH;
        pxVersion->ucDevCommits = GIT_TAG_VER_DEV_COMMITS;

        iStatus = GCQ_ERRORS_NONE;
    }

    return iStatus;
}
