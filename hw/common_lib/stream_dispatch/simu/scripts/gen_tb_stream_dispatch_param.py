#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  This script generates stream_dispatch parameters randomly.
#  Use this script to get coherent and supported parameters.
# ==============================================================================================

import argparse # parse input argument
import os       # OS functions
import sys      # manage errors
from pathlib import Path # Get current file path
import pprint
import datetime

import random
from constrainedrandom import RandObj, RandomizationError # For constrained random

#==================================================================================================
# Constraints
#==================================================================================================
def cstr_out_disp (out_coef, disp_coef):
    """
    The number of coefficients to be dispatched per output port should greater of equal
    to the output port size in coef unit.
    out_coef should divide disp_coef.
    """
    return (disp_coef >= out_coef) and ((disp_coef % out_coef) == 0)

def cstr_in_disp (in_coef, disp_coef):
    """
    if (in_coef < disp_coef) in_coef should divide disp_coef.
    if (in_coef > disp_coef) disp_coef should divide in_coef.
    """
    if (in_coef < disp_coef):
        return ((disp_coef % in_coef) == 0)
    elif (in_coef > disp_coef):
        return ((in_coef % disp_coef) == 0)
    else:
        return True

def cstr_in_out (in_coef, out_coef, disp_coef):
    """
    if (in_coef < disp_coef) in_coef should divide or be a multiple of out_coef.
    """
    if (in_coef < disp_coef):
        if (in_coef < out_coef):
            return ((out_coef % in_coef) == 0)
        elif (in_coef > out_coef):
            return ((in_coef % out_coef) == 0)
        else :
            return True
    else:
        return True

def cstr_out_nb (out_nb, in_coef, disp_coef):
    """
    if (disp_coef < in_coef) the number of output addressed must divide, or be a multiple of out_nb.
    """
    if (disp_coef < in_coef):
        if (in_coef <= disp_coef):
            dest_nb = 1
        elif (in_coef > disp_coef):
            dest_nb = in_coef // disp_coef

        if (out_nb < dest_nb):
            return ((dest_nb % out_nb) == 0)
        elif (out_nb > dest_nb):
            return ((out_nb % dest_nb) == 0)
        else:
            return True
    else:
        return True

#==================================================================================================
# Main
#==================================================================================================
MAX_ITER=20
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Generate HPU parameters")
    parser.add_argument('-out_bash',               type=str, help="Output in bash format.", required=True)
    parser.add_argument('-s', dest='seed',         type=int, help="Seed.",                                           default=int(datetime.datetime.utcnow().timestamp()))
    parser.add_argument('-v', dest='verbose',                help="Run in verbose mode.", action="store_true",       default=False)

    args = parser.parse_args()


#=====================================================
# Set global seed
#=====================================================
    random.seed(args.seed)

#=====================================================
# Random variables
#=====================================================
    # Create randomizable object
    r1 = RandObj(max_iterations=MAX_ITER)

    r1.add_rand_var("IN_COEF"   , domain=range(1,64+1), order=0)
    r1.add_rand_var("OUT_COEF"  , domain=range(1,64+1), order=0)
    r1.add_rand_var("DISP_COEF" , domain=range(1,64+1), order=0)
    r1.add_rand_var("OUT_NB"    , domain=range(1,16+1), order=0)

#=====================================================
# Constraints
#=====================================================
#---------------
# r1
#---------------
    r1.add_constraint(cstr_out_disp, ('OUT_COEF', 'DISP_COEF'))
    r1.add_constraint(cstr_in_disp, ('IN_COEF', 'DISP_COEF'))
    r1.add_constraint(cstr_out_nb, ('OUT_NB', 'IN_COEF', 'DISP_COEF'))
    r1.add_constraint(cstr_in_out, ('IN_COEF', 'OUT_COEF', 'DISP_COEF'))

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
