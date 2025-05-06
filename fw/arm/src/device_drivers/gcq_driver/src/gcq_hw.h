/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains API definitions for HW accesses to GCQ IP.
 *
 * @file gcq_hw.h
 *
 */

#ifndef _GCQ_HW_H_
#define _GCQ_HW_H_


/******************************************************************************/
/* Function Declarations                                                      */
/******************************************************************************/

/**
 *
 * @brief    Initial GCQ IP block mode configuration
 *
 * @param    xMode is the supported mode, consumer or producer
 * @param    ullBaseAddr is the base address of the GCQ IP block
 * @param    ullRingAddr the queue memory base address
 * @param    pxGCQIOAccess is the bound in memory/register access functions
 *
 * @return   See GCQ_ERRORS_TYPE for possible return values
 * 
 */
GCQ_ERRORS_TYPE xGCQHWInit( GCQ_MODE_TYPE xMode,
                            uint64_t ullBaseAddr,
                            uint64_t ullRingAddr,
                            const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess );

/**
 *
 * @brief    Configure the GCQ IP block interrupt mode
 *
 * @param    xMode is the supported mode, consumer or producer
 * @param    xIntMode is the supported interrupt mode
 * @param    ullBaseAddr is the base address of the GCQ IP block
 * @param    pxGCQIOAccess is the bound in memory/register access functions
 *
 * @return   See GCQ_ERRORS_TYPE for possible return values
 * 
 */
GCQ_ERRORS_TYPE xGCQHWConfigureInterruptMode( GCQ_MODE_TYPE xMode,
                                              GCQ_INTERRUPT_MODE_TYPE xIntMode,
                                              uint64_t ullBaseAddr,
                                              const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess );

/**
 *
 * @brief    Trigger an interrupt via the interrupt register
 *
 * @param    xMode is the supported mode, consumer or producer
 * @param    ullBaseAddr is the base address of the GCQ IP block
 * @param    pxGCQIOAccess is the bound in memory/register access functions
 *
 * @return   See GCQ_ERRORS_TYPE for possible return values
 * 
 */
GCQ_ERRORS_TYPE xGCQHWTriggerInterrupt( GCQ_MODE_TYPE xMode,
                                        uint64_t ullBaseAddr,
                                        const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess );

/**
 *
 * @brief    Clear the interrupt via the interrupt status register
 *
 * @param    xMode is the supported mode, consumer or producer
 * @param    ullBaseAddr is the base address of the GCQ IP block
 * @param    pxGCQIOAccess is the bound in memory/register access functions
 *
 * @return   See GCQ_ERRORS_TYPE for possible return values
 * 
 */
GCQ_ERRORS_TYPE xGCQHWClearInterrupt( GCQ_MODE_TYPE xMode,
                                      uint64_t ullBaseAddr,
                                      const GCQ_IO_ACCESS_TYPE *pxGCQIOAccess );

#endif /* _GCQ_HW_H_ */
