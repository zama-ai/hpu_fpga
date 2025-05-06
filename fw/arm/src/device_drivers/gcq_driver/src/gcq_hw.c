/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains API definitions for HW accesses to GCQ IP.
 *
 * @file gcq_hw.c
 *
 */

#include "gcq_internal.h"


/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/

#define GCQ_HW_LOWER_32( val )   ( val & 0xffffffff )
#define GCQ_HW_UPPER_32( val )   ( ( val >> 32 ) & 0xffffffff )


/*****************************************************************************/
/* Public Functions                                                          */
/*****************************************************************************/

/**
 *
 * @brief    Initial GCQ IP block mode configuration
 *
 */
GCQ_ERRORS_TYPE xGCQHWInit( GCQ_MODE_TYPE xMode,
                            uint64_t ullBaseAddr,
                            uint64_t ullRingAddr,
                            const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess )
{
    if( CHECK_REG_IO_ACCESS( pxGCQIOAccess ) ) { return GCQ_ERRORS_INVALID_ARG; }

    {
        GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_NONE;
        uint32_t ulValue = 0;

        /*
         * The high/low memory address are meant to be used to store the base address of
         * where the ring buffer is located in memory, in the current HW implementation this
         * doesn't seen to be used, setting anyway as will maybe be required in the future.
         */
        switch( xMode )
        {
            case GCQ_MODE_TYPE_CONSUMER_MODE:
                /*
                 * In consumer mode we don't perform a soft reset and the HW is owned by the producer
                 */
                ulValue = FIELD_SET( GCQ_CONSUMER_CQ_QUEUE_MEM_ADDR_LOW, GCQ_HW_LOWER_32( ullRingAddr ) );
                pxGCQIOAccess->xGCQWriteReg32( ( ullBaseAddr + GCQ_CONSUMER_CQ_QUEUE_MEM_ADDR_LOW ), ulValue );
                ulValue = FIELD_SET( GCQ_CONSUMER_CQ_QUEUE_MEM_ADDR_HIGH, GCQ_HW_UPPER_32 ( ullRingAddr ) );
                pxGCQIOAccess->xGCQWriteReg32( ( ullBaseAddr + GCQ_CONSUMER_CQ_QUEUE_MEM_ADDR_HIGH ), ulValue );
                break;

            case GCQ_MODE_TYPE_PRODUCER_MODE:
                /*
                 * Performs a soft reset of all submission queue and completion queue registers.
                 * The reset field is self-clearing once set.
                 */
                ulValue = pxGCQIOAccess->xGCQReadReg32( ( ullBaseAddr + GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL ) );
                ulValue |= FIELD_SET( GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL_ENABLE_MASK, GCQ_INTERRUPT_CTRL_RESET );
                pxGCQIOAccess->xGCQWriteReg32( ( ullBaseAddr + GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL ), ulValue );
                ulValue = FIELD_SET( GCQ_PRODUCER_SQ_QUEUE_MEM_ADDR_LOW, GCQ_HW_LOWER_32 ( ullRingAddr ) );
                pxGCQIOAccess->xGCQWriteReg32( ( ullBaseAddr + GCQ_PRODUCER_SQ_QUEUE_MEM_ADDR_LOW ), ulValue );
                ulValue = FIELD_SET( GCQ_PRODUCER_SQ_QUEUE_MEM_ADDR_HIGH, GCQ_HW_UPPER_32 ( ullRingAddr ) );
                pxGCQIOAccess->xGCQWriteReg32( ( ullBaseAddr + GCQ_PRODUCER_SQ_QUEUE_MEM_ADDR_HIGH ), ulValue );
                break;

            default:
                xStatus = GCQ_ERRORS_INVALID_ARG;
                break;
        }

        if( GCQ_ERRORS_NONE == xStatus)
        {
            GCQ_DEBUG( "GCQ IP Block HW Init Complete: (%s) (0x%llx)\r\n", pcGCQModeStr[ xMode ], ullBaseAddr );
        }

        return ( xStatus );
    }
}

/**
 *
 * @brief    Configure the GCQ IP block interrupt mode
 *
 */
GCQ_ERRORS_TYPE xGCQHWConfigureInterruptMode( GCQ_MODE_TYPE xMode,
                                              GCQ_INTERRUPT_MODE_TYPE xIntMode,
                                              uint64_t ullBaseAddr,
                                              const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess )
{
    if( CHECK_REG_IO_ACCESS( pxGCQIOAccess ) ) { return GCQ_ERRORS_INVALID_ARG; }

    {
        GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_NONE;
        uint32_t ulValue = 0;
        uint64_t ullReg = 0;

        switch( xMode )
        {
            case GCQ_MODE_TYPE_CONSUMER_MODE:
            {
                ullReg = ( ullBaseAddr + GCQ_CONSUMER_CQ_RESET_INTERRUPT_CTRL );
                switch( xIntMode )
                {
                    case GCQ_INTERRUPT_MODE_POLLING:
                        /* In polling mode we disable interrups */
                        ulValue = FIELD_SET( GCQ_CONSUMER_CQ_RESET_INTERRUPT_CTRL_ENABLE_MASK, GCQ_INTERRUPT_CTRL_DISABLE );
                        break;
                    case GCQ_INTERRUPT_MODE_TAIL_POINTER:
                        ulValue = FIELD_SET( GCQ_CONSUMER_CQ_RESET_INTERRUPT_CTRL_ENABLE_MASK, GCQ_INTERRUPT_CTRL_ENABLE ) |
                                  FIELD_SET( GCQ_CONSUMER_CQ_RESET_INTERRUPT_CTRL_TYPE_MASK, GCQ_INTERRUPT_CTRL_TYPE_TAIL_POINTER_WRITE );
                        break;
                    case GCQ_INTERRUPT_MODE_INTERRUPT_REG:
                        ulValue = FIELD_SET( GCQ_CONSUMER_CQ_RESET_INTERRUPT_CTRL_ENABLE_MASK, GCQ_INTERRUPT_CTRL_ENABLE ) |
                                  FIELD_SET( GCQ_CONSUMER_CQ_RESET_INTERRUPT_CTRL_TYPE_MASK, GCQ_INTERRUPT_CTRL_TYPE_INTE_REG_WRITE );
                        break;
                    default:
                        xStatus = GCQ_ERRORS_INVALID_ARG;
                        break;
                }
            }
            break;

            case GCQ_MODE_TYPE_PRODUCER_MODE:
            {
                ullReg = ( ullBaseAddr + GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL );
                switch( xIntMode )
                {
                    case GCQ_INTERRUPT_MODE_POLLING:
                        /* In polling mode we disable interrups */
                        ulValue = FIELD_SET( GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL_ENABLE_MASK, GCQ_INTERRUPT_CTRL_DISABLE );
                        break;
                    case GCQ_INTERRUPT_MODE_TAIL_POINTER:
                        ulValue = FIELD_SET( GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL_ENABLE_MASK, GCQ_INTERRUPT_CTRL_ENABLE ) |
                                  FIELD_SET( GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL_TYPE_MASK, GCQ_INTERRUPT_CTRL_TYPE_TAIL_POINTER_WRITE );
                        break;
                    case GCQ_INTERRUPT_MODE_INTERRUPT_REG:
                        ulValue = FIELD_SET( GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL_ENABLE_MASK, GCQ_INTERRUPT_CTRL_ENABLE ) |
                                  FIELD_SET( GCQ_PRODUCER_SQ_RESET_INTERRUPT_CTRL_TYPE_MASK, GCQ_INTERRUPT_CTRL_TYPE_INTE_REG_WRITE );
                        break;
                    default:
                        xStatus = GCQ_ERRORS_INVALID_ARG;
                        break;
                }
            }
            break;

            default:
                xStatus = GCQ_ERRORS_INVALID_ARG;
                break;
        }

        if( GCQ_ERRORS_NONE == xStatus )
        {
            pxGCQIOAccess->xGCQWriteReg32( ullReg, ulValue );
            GCQ_DEBUG( "Interrupt Mode Type Configured: (%s)\r\n", pcGCQInterruptModeStr[ xIntMode ] );
        }

        return ( xStatus );
    }
}

/**
 *
 * @brief   Trigger an interrupt, used for interrupt reg mode only
 *
 */
GCQ_ERRORS_TYPE xGCQHWTriggerInterrupt( GCQ_MODE_TYPE xMode,
                                        uint64_t ullBaseAddr,
                                        const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess )
{
    if( CHECK_REG_IO_ACCESS( pxGCQIOAccess ) ) { return GCQ_ERRORS_INVALID_ARG; }

    {
        GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_NONE;
        uint32_t ulValue = 0;
        uint64_t ullReg = 0;

        switch( xMode )
        {
            case GCQ_MODE_TYPE_CONSUMER_MODE:
                ullReg = ( ullBaseAddr + GCQ_CONSUMER_CQ_INTERRUPT_REG );
                ulValue = FIELD_SET( GCQ_CONSUMER_CQ_INTERRUPT_REG_INT_REG_MASK, GCQ_INTERRUPT_REG_INT_REG_TRIGGER ) ;
                break;
            case GCQ_MODE_TYPE_PRODUCER_MODE:
                ullReg = ( ullBaseAddr + GCQ_PRODUCER_SQ_INTERRUPT_REG );
                ulValue = FIELD_SET( GCQ_PRODUCER_SQ_INTERRUPT_REG_INT_REG_MASK, GCQ_INTERRUPT_REG_INT_REG_TRIGGER ) ;
                break;
            default:
                xStatus = GCQ_ERRORS_INVALID_ARG;
                break;
        }

        if( GCQ_ERRORS_NONE == xStatus )
        {
            pxGCQIOAccess->xGCQWriteReg32( ullReg, ulValue );
            GCQ_DEBUG( "Trigger Interrupt [%s]\r\n", pcGCQModeStr[ xMode ] );
        }

        return ( xStatus );
    }
}

/**
 * @brief   Check the interrupt status, used for interrupt reg mode only
 *
 */
GCQ_ERRORS_TYPE xGCQHWClearInterrupt( GCQ_MODE_TYPE xMode,
                                      uint64_t ullBaseAddr,
                                      const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess )
{
    if( CHECK_REG_IO_ACCESS( pxGCQIOAccess ) ) { return GCQ_ERRORS_INVALID_ARG; }

    {
        GCQ_ERRORS_TYPE xStatus = GCQ_ERRORS_NONE;
        uint64_t ullReg = 0;

        switch( xMode )
        {
            case GCQ_MODE_TYPE_CONSUMER_MODE:
                ullReg = ( ullBaseAddr + GCQ_CONSUMER_CQ_INTERRUPT_REG );
                break;
            case GCQ_MODE_TYPE_PRODUCER_MODE:
                ullReg = ( ullBaseAddr + GCQ_PRODUCER_SQ_INTERRUPT_REG );
                break;
            default:
                xStatus = GCQ_ERRORS_INVALID_ARG;
                break;
        }

        if( GCQ_ERRORS_NONE == xStatus )
        {
            /* Reading this register clears the completion queue interrupt if asserted */
            pxGCQIOAccess->xGCQReadReg32( ullReg );
            GCQ_DEBUG( "Interrupt Cleared [%s]\r\n", pcGCQModeStr[ xMode ] );
        }

        return ( xStatus );
    }
}
