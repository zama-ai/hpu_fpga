/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the printing profile for the AVED v80 platform
 *
 * @file profile_print.h
 *
 */

#ifndef _PROFILE_PRINT_H_
#define _PROFILE_PRINT_H_

#include "xil_printf.h"

#ifndef PRINT
#define PRINT( ... ) ( xil_printf( __VA_ARGS__ ) )
#endif

#endif
