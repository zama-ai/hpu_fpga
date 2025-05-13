#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  This script generates HPU parameters randomly.
#  Use this script to get coherent and supported parameters.
#
#  Some parameters could be given.
#  This module generates parameters depending on basic ones.
# ==============================================================================================

import argparse # parse input argument
import os       # OS functions
import sys      # manage errors
from pathlib import Path # Get current file path
import pprint
import datetime

from gen_tb_hpu_param_global import *

import random
from constrainedrandom import RandObj, RandomizationError # For constrained random

#==================================================================================================
# Constraints
#==================================================================================================
def cstr_lwe_k (lwe_k):
    """
    LWE_K should not be too small, to avoid unsupported corner cases in the design
    """
    return ((lwe_k // args.lbx) >= MIN_BCOL) and ((args.s > 9) or (lwe_k >= MIN_LWE_K))


def cstr_bsk_pc (bsk_pc):
    """
    Number of coef presented by each PC should divide R*PSI
    Total number of coefficients sent should match N. (no croppping done)
    per cut (#cut = #pc)
    """
    bsk_w = args.mod_ntt_w
    if ((bsk_w) > 32):
        bsk_acs_w = 64
    else:
        bsk_acs_w = 32
    pc_coef = AXI_W // bsk_acs_w
    return ((bsk_pc == 1)
            or ((bsk_pc <= (args.r*args.psi))
                and ((args.r**args.s) % (bsk_pc * pc_coef) == 0)))

def cstr_ksk_pc (ksk_pc):
    """
    Number of coef presented by each PC should divide LBY
    Total number of coefficients sent should match BLWE_K. (no croppping done)
    per cut (#cut = #pc)
    """
    blwe_k = (args.r**args.s) * args.glwe_k
    if ((args.lbz * args.mod_ksk_w) > 32):
        ksk_acs_w = 64
    else:
        ksk_acs_w = 32
    pc_coef = AXI_W // ksk_acs_w
    return ( (ksk_pc == 1)
             or ((ksk_pc <= args.lby)
                  and (blwe_k % (ksk_pc * pc_coef) == 0)))

def cstr_pem_pc (pem_pc):
    """
    The number of PC should not exceed the number of sequences of the regfile
    """
    return (pem_pc <= args.regf_seq)

def cstr_run (lwe_k):
    """
    To avoid too long simulations, artificially limit value of k
    """
    if (args.s > 9):
        return (lwe_k < MAX_LWE_K)
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
    parser.add_argument('-A', dest='ntt_arch',     type=str, help="NTT architecture", choices=['NTT_CORE_ARCH_wmm_unfold_pcg','NTT_CORE_ARCH_gf64'], default='NTT_CORE_ARCH_gf64')
    parser.add_argument('-R', dest='r',            type=int, help="R: radix. (Supports only 2)",                     default=2)
    parser.add_argument('-P', dest='psi',          type=int, help="PSI: Number of butterflies.",                     default=8)
    parser.add_argument('-S', dest='s',            type=int, help="2**S: Number of coefficients in a polynomial.",   default=11)
    parser.add_argument('-g', dest='glwe_k',       type=int, help="GLWE_K",                                          default=1)
    parser.add_argument('-V', dest='mod_ksk_w',    type=int, help="MOD_KSK_W.",                                      default=21)
    parser.add_argument('-w', dest='mod_ntt_w',    type=int, help="MOD_NTT_W: Modulo width.",                        default=64)
    parser.add_argument('-c', dest='batch_pbs_nb', type=int, help="BATCH_PBS_NB: Maximum number of pbs per batch.",  default=16)
    parser.add_argument('-H', dest='total_pbs_nb', type=int, help="TOTAL_PBS_NB: Maximum number of pbs stored."   ,  default=32)
    parser.add_argument('-e', dest='bwd_psi_div',  type=int, help="BWD_PSI_DIV.",                                    default=1)
    parser.add_argument('-l', dest='pbs_l',        type=int, help="PBS_L.",                                          default=1)
    parser.add_argument('-b', dest='pbs_b_w',      type=int, help="PBS_B_W.",                                        default=25)
    parser.add_argument('-L', dest='ksk_l',        type=int, help="KSK_L.",                                          default=8)
    parser.add_argument('-B', dest='ksk_b_w',      type=int, help="KSK_B_W.",                                        default=2)
    parser.add_argument('-X', dest='lbx',          type=int, help="LBX.",                                            default=2)
    parser.add_argument('-Y', dest='lby',          type=int, help="LBY.",                                            default=16)
    parser.add_argument('-Z', dest='lbz',          type=int, help="LBZ.",                                            default=2)
    parser.add_argument('-i', dest='regf_reg_nb',  type=int, help="REGF_REG_NB.",                                    default=64)
    parser.add_argument('-j', dest='regf_coef_nb', type=int, help="REGF_COEF_NB.",                                   default=32)
    parser.add_argument('-k', dest='regf_seq',     type=int, help="REGF_SEQ.",                                       default=4)
    parser.add_argument('-D', dest='axi_w',        type=int, help="AXI4_DATA_W: Axi4 bus data width.",               default=512)
    parser.add_argument('-FPGA', dest='fpga',      type=str, help="FPGA type",              choices=['v80'],         default="v80")
    parser.add_argument('-out_bash',               type=str, help="Output in bash format.", required=True)
    parser.add_argument('-s', dest='seed',         type=int, help="Seed.",                                           default=int(datetime.datetime.utcnow().timestamp()))
    parser.add_argument('-v', dest='verbose',                help="Run in verbose mode.", action="store_true",       default=False)

    args = parser.parse_args()

    AXI_W = args.axi_w
    FPGA  = args.fpga

    if (FPGA == 'v80'):
        BSK_PC_MAX = 16
        KSK_PC_MAX = 16
        PEM_PC_MAX = 2
    else:
        sys.exit(f"ERROR> Unsupported FPGA {{FPGA}}.")

#=====================================================
# Set global seed
#=====================================================
    random.seed(args.seed)

#=====================================================
# Random variables
#=====================================================
    # Create randomizable object
    r1 = RandObj(max_iterations=MAX_ITER)

    r1.add_rand_var("BSK_PC"        , fn=rand_power_of, args=(2,1,BSK_PC_MAX), order=0)
    r1.add_rand_var("KSK_PC"        , fn=rand_power_of, args=(2,1,KSK_PC_MAX), order=0)
    r1.add_rand_var("LWE_K"         , domain=range(28,45+1), order=0)
    r1.add_rand_var("PEM_PC"        , domain=range(1,PEM_PC_MAX+1), order=0)

#=====================================================
# Constraints
#=====================================================
#---------------
# r1
#---------------
    r1.add_constraint(cstr_lwe_k, ('LWE_K'))
    r1.add_constraint(cstr_bsk_pc, ('BSK_PC'))
    r1.add_constraint(cstr_ksk_pc, ('KSK_PC'))
    r1.add_constraint(cstr_pem_pc, ('PEM_PC'))
    r1.add_constraint(cstr_run, ('LWE_K'))

#=====================================================
# Randomize
#=====================================================
    try:
        r1.randomize()
    except RandomizationError:
        sys.exit(f"ERROR> No solution found for r1 after {MAX_ITER} iterations.")

    extra_d = {
        "BSK_CUT_NB" : r1.BSK_PC,
        "KSK_CUT_NB" : r1.KSK_PC,
    }

#=====================================================
# Print
#=====================================================
    # Bash file
    bfile_path = Path(args.out_bash)
    with open(bfile_path, 'w') as b_fp:
        for (k,v) in r1.get_results().items():
          b_fp.write(f"{k}={v}\n")
        for (k,v) in extra_d.items():
          b_fp.write(f"{k}={v}\n")
