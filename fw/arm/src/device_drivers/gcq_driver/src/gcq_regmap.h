/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains register definitions and macros to
 * access fields.
 *
 * @file gcq_regmap.h
 *
 */

#ifndef _GCQ_REGMAP_H_
#define _GCQ_REGMAP_H_


/*****************************************************************************/
/* Static Function Declarations                                              */
/*****************************************************************************/

/**
 * @brief Function to return the position of the first (least significant) bit
 *        set. This would be the equivalent of __builtin_ffsll in gcc.
 */
static inline uint32_t prvulGetTrailingZeros( uint64_t ullValue )
{
    uint32_t ulPos = 0;

    if( ullValue > 0 )
    {
        if( 0 == ( ullValue & 0xffffffff ) )
        {
            ulPos += 32;
            ullValue >>= 32;
        }

        if( 0 == ( ullValue & 0xffff ) )
        {
            ulPos += 16;
            ullValue >>= 16;
        }

        if( 0 == ( ullValue & 0xff ) )
        {
            ulPos += 8;
            ullValue >>= 8;
        }

        if( 0 == ( ullValue & 0xf ) )
        {
            ulPos += 4;
            ullValue >>= 4;
        }

        if( 0 == ( ullValue & 0x3 ) )
        {
            ulPos += 2;
            ullValue >>= 2;
        }

        if( 0 == ( ullValue & 0x1 ) )
        {
            ulPos += 1;
        }
    }

    return ulPos;
}


/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/

#define BITS_PER_U32                                            ( 32 )
#ifndef __KERNEL__
#define BIT( n )                                                ( 1ul << ( n ) )    /* BIT a macro already defined in include/linux/bitops.h */
#endif
#define BITS( h, l )                                            ( ( UINT32_MAX - ( 1U << (l) ) + 1 ) & \
                                                                ( UINT32_MAX >> ( BITS_PER_U32 - 1 - ( h ) ) ) )
#define FIELD_SHIFT( mask )                                     ( prvulGetTrailingZeros( mask ) )
#define FIELD_SET( mask, val )                                  ( ( ( val ) << FIELD_SHIFT( mask ) ) & ( mask ) )
#define FIELD_GET( mask, reg )                                  ( ( ( reg ) & ( mask ) ) >> FIELD_SHIFT( mask ) )

#define GCQ_INTERRUPT_CTRL_DISABLE                              ( 0x0 )
#define GCQ_INTERRUPT_CTRL_ENABLE                               ( 0x1 )

#define GCQ_INTERRUPT_CTRL_TYPE_TAIL_POINTER_WRITE              ( 0x0 )
#define GCQ_INTERRUPT_CTRL_TYPE_INTE_REG_WRITE                  ( 0x1 )

#define GCQ_INTERRUPT_CTRL_RESET                                ( 0x1 )

#define GCQ_INTERRUPT_REG_INT_REG_TRIGGER                       ( 0x1 )
#define GCQ_INTERRUPT_REG_INT_REG_ASSERTED                      ( 0x1 )


/**
 * Producer AXI Register Space
 */
#define GCQ_PRODUCER_SQ_TAIL_POINTER                             ( 0x0000 )
#define GCQ_PRODUCER_SQ_TAIL_POINTER_MASK                        BITS( 31, 0 )      /* RW */

#define GCQ_PRODUCER_SQ_INTERRUPT_REG                            ( 0x0004 )
#define GCQ_PRODUCER_SQ_INTERRUPT_REG_INT_REG_MASK               BIT( 0 )           /* WO */
#define GCQ_PRODUCER_SQ_INTERRUPT_REG_INT_STATUS_MASK            BIT( 1 )           /* RO */

#define GCQ_PRODUCER_SQ_QUEUE_MEM_ADDR_LOW                       ( 0x0008 )
#define GCQ_PRODUCER_SQ_QUEUE_MEM_ADDR_LOW_MASK                  BITS( 31, 0 )      /* RW */

#define GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL                     ( 0x000C )
#define GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL_ENABLE_MASK         BIT( 0 )           /* RW */
#define GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL_TYPE_MASK           BIT( 1 )           /* RW */
#define GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL_RESET_MASK          BIT( 31 )          /* WO */

#define GCQ_PRODUCER_SQ_QUEUE_MEM_ADDR_HIGH                      ( 0x0010 )
#define GCQ_PRODUCER_SQ_QUEUE_MEM_ADDR_HIGH_MASK                 BITS( 31, 0 )      /* RW */

#define GCQ_PRODUCER_CQ_TAIL_POINTER                             ( 0x0100 )
#define GCQ_PRODUCER_CQ_TAIL_POINTER_MASK                        BITS( 31, 0 )      /* RO */

#define GCQ_PRODUCER_CQ_INTERRUPT_STATUS                         ( 0x0104 )
#define GCQ_PRODUCER_CQ_INTERRUPT_REG_INT_STATUS_MASK            BIT( 0 )           /* RO */

#define GCQ_PRODUCER_CQ_QUEUE_MEM_ADDR_LOW                       ( 0x0108 )
#define GCQ_PRODUCER_CQ_QUEUE_MEM_ADDR_LOW_MASK                  BITS( 31, 0 )      /* RO */

#define GCQ_PRODUCER_CQ_RESET_INTERRUPT_CTRL                     ( 0x010C )
#define GCQ_PRODUCER_CQ_RESET_INTERRUPT_CTRL_ENABLE_MASK         BIT( 0 )           /* RO */
#define GCQ_PRODUCER_CQ_RESET_INTERRUPT_CTRL_TYPE_MASK           BIT( 1 )           /* RO */

#define GCQ_PRODUCER_CQ_QUEUE_MEM_ADDR_HIGH                      ( 0x0110 )
#define GCQ_PRODUCER_CQ_QUEUE_MEM_ADDR_HIGH_MASK                 BITS( 31, 0 )

/**
 * Consumer  AXI Register Space
 */
#define GCQ_CONSUMER_CQ_TAIL_POINTER                             ( 0x0000 )
#define GCQ_CONSUMER_CQ_TAIL_POINTER_MASK                        BITS( 31, 0 )       /* RW */

#define GCQ_CONSUMER_CQ_INTERRUPT_REG                            ( 0x0004 )
#define GCQ_CONSUMER_CQ_INTERRUPT_REG_INT_REG_MASK               BIT( 0 )            /* WO */
#define GCQ_CONSUMER_CQ_INTERRUPT_REG_INT_STATUS_MASK            BIT( 1 )            /* RO */

#define GCQ_CONSUMER_CQ_QUEUE_MEM_ADDR_LOW                       ( 0x0008 )
#define GCQ_CONSUMER_CQ_QUEUE_MEM_ADDR_LOW_MASK                  BITS( 31, 0 )       /* RW */

#define GCQ_CONSUMER_CQ_RESET_INTERRUPT_CTRL                     ( 0x000C )
#define GCQ_CONSUMER_CQ_RESET_INTERRUPT_CTRL_ENABLE_MASK         BIT( 0 )            /* RW */
#define GCQ_CONSUMER_CQ_RESET_INTERRUPT_CTRL_TYPE_MASK           BIT( 1 )            /* RW */
#define GCQ_CONSUMER_CQ_RESET_INTERRUPT_CTRL_RESET_MASK          BIT( 31 )           /* WO */

#define GCQ_CONSUMER_CQ_QUEUE_MEM_ADDR_HIGH                      ( 0x0010 )
#define GCQ_CONSUMER_CQ_QUEUE_MEM_ADDR_HIGH_MASK                 BITS( 31, 0 )       /* RW */

#define GCQ_CONSUMER_SQ_TAIL_POINTER                             ( 0x0100 )
#define GCQ_CONSUMER_SQ_TAIL_POINTER_MASK                        BITS( 31, 0 )       /* RO */

#define GCQ_CONSUMER_SQ_INTERRUPT_REG                            ( 0x0104 )
#define GCQ_CONSUMER_SQ_INTERRUPT_REG_INT_STATUS_MASK            BIT( 0 )            /* RO */

#define GCQ_CONSUMER_SQ_QUEUE_MEM_ADDR_LOW                       ( 0x0108 )
#define GCQ_CONSUMER_SQ_QUEUE_MEM_ADDR_LOW_MASK                  BITS( 31, 0 )       /* RO */

#define GCQ_CONSUMER_SQ_RESET_INTERRUPT_CTRL                     ( 0x010C )
#define GCQ_CONSUMER_SQ_RESET_INTERRUPT_CTRL_ENABLE_MASK         BIT( 0 )            /* RO */
#define GCQ_CONSUMER_SQ_RESET_INTERRUPT_CTRL_TYPE_MASK           BIT( 1 )            /* RO */

#define GCQ_CONSUMER_SQ_QUEUE_MEM_ADDR_HIGH                      ( 0x0110 )
#define GCQ_CONSUMER_SQ_QUEUE_MEM_ADDR_HIGH_MASK                 BITS( 31, 0 )       /* RO */


#endif /* _GCQ_REGMAP_H_ */
