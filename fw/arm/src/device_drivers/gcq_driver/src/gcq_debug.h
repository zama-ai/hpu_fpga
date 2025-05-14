/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains definitions for the internal ring buffer implementation.
 *
 * @file gcq_debug.h
 *
 */

#ifndef _GCQ_DEBUG_H_
#define _GCQ_DEBUG_H_

#include <stdint.h>
#include <stdio.h>
#include "osal.h"

#ifndef GCQ_DEBUG_ENABLE
#define GCQ_DEBUG_ENABLE                        ( 0 )   /**< Debug logging disabled by default */
#endif
#if GCQ_DEBUG_ENABLE
#ifdef __KERNEL__
#define GCQ_DEBUG( x... )                       {  printk( "[GCQ Driver] " x ); }
#else
#define GCQ_DEBUG( x... )                       {  vOSAL_Printf( "[GCQ Driver] " x ); }
#endif
#else
#define GCQ_DEBUG( x... )                       ( void ) ( 0 )
#endif

#endif /* _GCQ_DEBUG_H_ */
