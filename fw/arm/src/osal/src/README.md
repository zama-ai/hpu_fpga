# Operating System Abstraction Layer (OSAL)

Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
SPDX-License-Identifier: MIT

The OSAL allows the AMC to be ported to a different OS without requiring code changes in the AMC or its layers.

A common osal.h API is provided with a generic API. FreeRTOS and Linux implementations of this API are released with the AMC - however, a user can provide their own RTOS implementation if they prefer (e.g. osal_FreeRTOS.c can be replaced with a user-written osal_UCOS.c).
