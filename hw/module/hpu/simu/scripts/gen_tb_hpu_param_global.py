#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  This script generates HPU parameters randomly.
#  Use this script to get coherent and supported parameters.
#
#  This file contains shared constants and functions.
# ==============================================================================================

import random
import math

#=====================================================
# global var
#=====================================================
GRAM_NB = 4
RAM_W = 64
MIN_BCOL = 6
MIN_LWE_K = 30 # For small S
MAX_LWE_K = 40 # For big S
MIN_REGF_REG = 16
BRAM_DEPTH = 1024
MIN_INFIFO_CT_NB = 3
MAX_NGC_RDX = 5
MAX_CYC_RDX = 6

#=====================================================
# functions
#=====================================================
def cstr_divisible (x, y):
    """
    Checks that x divides y
    """
    return (y % x) == 0

def cstr_r_psi_s (r,p,s):
    """
    Checks that:
    * R*PSI divides R**S
    * R*PSI < R**S
    """
    return (((r**s) % (r*p)) == 0) and ((r**s) > (r*p)) and (p >= 4)

def cstr_gt (a,b):
    """
    Checks that a > b
    """
    return a > b

#=====================================================
# set_val
#=====================================================
def set_val (arg_val, val):
    """
    Set value according to what user sets in the arguments.
    If the user argument is -1 => random is required. Therefore, use val.
    Else use value given by user.
    """
    if (arg_val == -1):
        return val
    else:
        return arg_val

#=====================================================
# set_list
#=====================================================
def set_list (arg_val, l):
    """
    Set list according to what user sets in the arguments.
    If the user argument is None => random is required. Therefore, use l.
    Else use value given by user.
    """
    if (arg_val == None):
        return l
    else:
        return [arg_val]

#=====================================================
# rand_power_of
#=====================================================
def rand_power_of(p, min_v, max_v):
    """
    Randomize a value that is a power of p, within the range
    [min, max]
    """
    log_min = math.ceil(math.log(min_v,p))
    log_max = math.floor(math.log(max_v,p))
    val = random.randrange(log_min,log_max+1)
    return p ** val

#=====================================================
# rand_mult_by
#=====================================================
def rand_mult_by(f, min_v, max_v):
    """
    Randomize a value that is a multiple of f, within the range
    [min, max]
    """
    div_min = math.ceil(min_v / f)
    div_max = math.floor(max_v / f)
    val = random.randrange(div_min,div_max+1)
    return val * f

#=====================================================
# is_ntt_wmm
#=====================================================
def is_ntt_wmm(ntt_arch):
    """
    Return true, if the ntt_arch is of type wmm
    """
    return (ntt_arch == "NTT_CORE_ARCH_wmm_unfold_pcg" ) or (ntt_arch == "NTT_CORE_ARCH_wmm_compact_pcg" )

