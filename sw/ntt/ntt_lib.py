#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# NTT common functions
# ==============================================================================================

import sys  # manage errors
from math import log, pow

# ==============================================================================
# reverse_order
# ==============================================================================
def reverse_order(v, R, S):
    """
    For an index v in 0...R^S, if we decompose it in the R-base:
    v = v_0*R^0 + v_1*R^1 + ... v_(S-1)*R^(S-1)
    where v_j is in 0...R-1.
    The reverse_order of v in base R, for a number of stages S is:
    reverse_order(v) = v_0*R^(S-1) + v_1*R^(S-2) + ... v_(S-1)*R^0

    R is a power of 2.
    """
    r_width = int(log(R, 2))
    if pow(2, r_width) != R:
        sys.exit("ERROR> In reverse_order function, the radix R must be a power of 2")

    mask = (1 << r_width) - 1
    rev = 0
    for i in range(0, S):
        rev = rev * R + (v & mask)
        v = v >> r_width
    return rev


# ==============================================================================
# inc_stride
# ==============================================================================
def inc_stride(n, stride,cons=1):
    """
    Outputs a list of number in range [0...n-1] from 0, with an increment of stride.
    Once the max reached, restart at value 1, etc...
    If cons > 1, each element is composed of "cons" numbers.
    """
    l = []
    for offset in range(stride):
        for i in range(n // (stride*cons)):
            for c in range(cons):
                l.append(offset*cons + c + i * stride*cons)
    return l
