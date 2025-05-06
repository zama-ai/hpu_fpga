#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  This script generates HPU parameters randomly.
#  Use this script to get coherent and supported parameters.
#
#  Some parameters could be given.
#  This module generates parameters for the radix cut. They depend on the basic ones.
# ==============================================================================================

import argparse # parse input argument
import os       # OS functions
import sys      # manage errors
from pathlib import Path # Get current file path
import pprint
import datetime

from gen_tb_hpu_param_global import *

import random
from constrainedrandom import RandObj, RandomizationError # For contrained random

#==================================================================================================
# Constraints
#==================================================================================================
def cstr_rdx_cut_nb(rdx_cut_nb):
    """
    The number of cuts has the following constraints:
    if wmm arch:
        rdx_cut_nb = 2
    """
    if (is_ntt_wmm(args.ntt_arch)):
        return (rdx_cut_nb == 2)
    else:
        return True

def cstr_rdx_cut_0(rdx_cut_0,rdx_cut_nb):
    """
      if rdx_cut_nb == 1 (only possible in ARCH_gf64)
        rdx_cut_0 = s
      else
        rdx_cut_0 must not be too big, so that the other cuts could exist

      Note that in ARCH_gf64, the first cut, is the negacyclic one.
      Only up to MAX_NGC_RDX is supported.
    """
    if (is_ntt_wmm(args.ntt_arch)):
        size_cond = rdx_cut_0 >= ((args.s+1)//2)
    else:
        size_cond = (args.r*args.psi >= 2**rdx_cut_0) and (rdx_cut_0 <= MAX_NGC_RDX)

    if (rdx_cut_nb == 1):
        return (rdx_cut_0==args.s) and size_cond
    else:
        return (rdx_cut_0 > 0) and (rdx_cut_0 <= (args.s-(rdx_cut_nb-1))) and size_cond

def cstr_rdx_cut_1(rdx_cut_0,rdx_cut_1,rdx_cut_nb):
    """
      if rdx_cut_nb == 2
        SUM(rdx_cut_<i>) = s
      else
        rdx_cut_1 must not be too big, so that the other cuts could exist
    """
    if (is_ntt_wmm(args.ntt_arch)):
        size_cond = (rdx_cut_1 <= rdx_cut_0)
    else:
        size_cond = (args.r*args.psi >= 2**rdx_cut_1) and (rdx_cut_1 <= MAX_CYC_RDX)

    if (rdx_cut_nb < 2):
        return (rdx_cut_1==0)
    elif (rdx_cut_nb == 2):
        return (rdx_cut_1 > 0) and ((rdx_cut_0+rdx_cut_1) == args.s) and size_cond
    else:
        return (rdx_cut_1 > 0) and ((rdx_cut_0+rdx_cut_1) <= args.s-(rdx_cut_nb-2)) and size_cond

def cstr_rdx_cut_2(rdx_cut_0,rdx_cut_1,rdx_cut_2,rdx_cut_nb):
    """
      if rdx_cut_nb == 3
        SUM(rdx_cut_<i>) = s
      else
        rdx_cut_2 must not be too big, so that the other cuts could exist
    """
    size_cond = True
    if not(is_ntt_wmm(args.ntt_arch)):
        size_cond = (args.r*args.psi >= 2**rdx_cut_2) and (rdx_cut_2 <= MAX_CYC_RDX)

    if (rdx_cut_nb < 3):
        return (rdx_cut_2==0)
    elif (rdx_cut_nb == 3):
        return (rdx_cut_2 > 0) and ((rdx_cut_0+rdx_cut_1+rdx_cut_2) == args.s) and size_cond
    else:
        return (rdx_cut_2 > 0) and ((rdx_cut_0+rdx_cut_1+rdx_cut_2) <= args.s-(rdx_cut_nb-3)) and size_cond

def cstr_rdx_cut_3(rdx_cut_0,rdx_cut_1,rdx_cut_2,rdx_cut_3,rdx_cut_nb):
    """
      if rdx_cut_nb == 4
        SUM(rdx_cut_<i>) = s
      else
        rdx_cut_3 must not be too big, so that the other cuts could exist
    """
    size_cond = True
    if not(is_ntt_wmm(args.ntt_arch)):
        size_cond = (args.r*args.psi >= 2**rdx_cut_3) and (rdx_cut_3 <= MAX_CYC_RDX)

    if (rdx_cut_nb < 4):
        return (rdx_cut_3==0)
    elif (rdx_cut_nb == 4):
        return (rdx_cut_3 > 0) and ((rdx_cut_0+rdx_cut_1+rdx_cut_2+rdx_cut_3) == args.s) and size_cond
    else:
        return (rdx_cut_3 > 0) and ((rdx_cut_0+rdx_cut_1+rdx_cut_2+rdx_cut_3) <= args.s-(rdx_cut_nb-4)) and size_cond

#==================================================================================================
# Main
#==================================================================================================
MAX_ITER=50
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Generate HPU parameters")
    parser.add_argument('-A', dest='ntt_arch',     type=str, help="NTT architecture", choices=['NTT_CORE_ARCH_wmm_unfold_pcg','NTT_CORE_ARCH_gf64'], default='NTT_CORE_ARCH_gf64')
    parser.add_argument('-R', dest='r',            type=int, help="R: radix. (Supports only 2)",                     default=2)
    parser.add_argument('-P', dest='psi',          type=int, help="PSI: Number of butterflies.",                     default=8)
    parser.add_argument('-S', dest='s',            type=int, help="2**S: Number of coefficients in a polynomial.",   default=11)
    parser.add_argument('-J', dest="cut_l",        type=int, action='append', help="NTT cut pattern. Given from input to output. The first one is the ngc",default=[])
    parser.add_argument('-out_bash',               type=str, help="Output in bash format.", required=True)
    parser.add_argument('-s', dest='seed',         type=int, help="Seed.",                                           default=int(datetime.datetime.utcnow().timestamp()))
    parser.add_argument('-v', dest='verbose',                help="Run in verbose mode.", action="store_true",       default=False)

    args = parser.parse_args()

    # cut_l - set default values
    cut_l_length = len(args.cut_l)
    if (cut_l_length == 0):
        cut_l_length = -1

    if (len(args.cut_l) > 4):
        sys.exit("ERROR> Does not support more than 4 NTT radix cuts");
    else:
        for i in range(len(args.cut_l), 4):
            args.cut_l.append(-1)

#=====================================================
# Set global seed
#=====================================================
    random.seed(args.seed)

#=====================================================
# Random variables
#=====================================================
    # Create randomizable object
    r1 = RandObj(max_iterations=MAX_ITER)

    r1.add_rand_var("RDX_CUT_NB"    , domain=range(set_val(cut_l_length,1),set_val(cut_l_length,4)+1), order=0)
    r1.add_rand_var("RDX_CUT_0"     , domain=range(set_val(args.cut_l[0],2),set_val(args.cut_l[0],8)+1), order=1)
    r1.add_rand_var("RDX_CUT_1"     , domain=range(set_val(args.cut_l[1],0),set_val(args.cut_l[1],8)+1), order=2)
    r1.add_rand_var("RDX_CUT_2"     , domain=range(set_val(args.cut_l[2],0),set_val(args.cut_l[2],3)+1), order=3)
    r1.add_rand_var("RDX_CUT_3"     , domain=range(set_val(args.cut_l[3],0),set_val(args.cut_l[3],3)+1), order=4)

#=====================================================
# Constraints
#=====================================================
#---------------
# r1
#---------------
    r1.add_constraint(cstr_rdx_cut_nb,('RDX_CUT_NB'))
    r1.add_constraint(cstr_rdx_cut_0,('RDX_CUT_0','RDX_CUT_NB'))
    r1.add_constraint(cstr_rdx_cut_1,('RDX_CUT_0','RDX_CUT_1','RDX_CUT_NB'))
    r1.add_constraint(cstr_rdx_cut_2,('RDX_CUT_0','RDX_CUT_1','RDX_CUT_2','RDX_CUT_NB'))
    r1.add_constraint(cstr_rdx_cut_3,('RDX_CUT_0','RDX_CUT_1','RDX_CUT_2','RDX_CUT_3','RDX_CUT_NB'))

#=====================================================
# Randomize
#=====================================================
    try:
        r1.randomize()
    except RandomizationError:
        sys.exit(f"ERROR> No solution found for r1 after {MAX_ITER} iterations.")

#=====================================================
# Print
#=====================================================
    # Bash file
    bfile_path = Path(args.out_bash)
    with open(bfile_path, 'w') as b_fp:
        for (k,v) in r1.get_results().items():
          b_fp.write(f"{k}={v}\n")

