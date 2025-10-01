#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  This script generates HPU parameters randomly.
#  Use this script to get coherent and supported parameters.
#
#  Some parameters could be given.
#  This module generates the basic parameters.
# ==============================================================================================

import argparse # parse input argument
import os       # OS functions
import sys      # manage errors
from pathlib import Path # Get current file path
import pprint
import datetime

import random
from constrainedrandom import RandObj, RandomizationError # For constrained random
from gen_tb_hpu_param_global import *

#=====================================================
# constraints
#=====================================================
def cstr_batch (batch_pbs,total_pbs):
    """
    Total number of pbs should be greater or equal to number of pbs per batch.
    """
    return total_pbs > batch_pbs

def cstr_pbs_level_div (bwd_psi_div, pbs_l, ntt_arch, psi):
    """
    PBS_L > 1 is only supported for unfold_pcg.
    If PBS_L > 1 and ntt_arch = wmm_unfold_pcg, the randomization on bwd_psi_div is possible, and psi/bwd_psi_div >= 2.
            Moreover, considering the SLR crossing is done with 4 channels, psi/bwd_psi_div >= 4,
    """
    if (ntt_arch == "NTT_CORE_ARCH_wmm_unfold_pcg"):
        return (bwd_psi_div <= pbs_l) and (psi/bwd_psi_div >= 4)
    else: # gf64
        return (bwd_psi_div == 1)

def cstr_level (b_w, l_nb, w):
    """
    Sum of the sizes of all the levels should fit inside the word.
    b_w * l_nb < w
    """
    return (b_w * l_nb) < w

def cstr_ksk_w (lbz, ksk_w):
    """
    lbz * ksk_w must fit inside a RAM word of 64 bits
    """
    return (lbz * ksk_w) <= RAM_W

def cstr_ks (ks_l, lbx, lby, lbz, r, s, glwe_k, ksk_w, ntt_w, batch_pbs_nb):
    """
    Check that there is enough time to empty the KS output pipe
    """
    q_w                   = ntt_w
    ks_lg_nb              = (ks_l + lbz-1) // lbz;
    blwe_k                = (r ** s) * glwe_k
    ks_block_line_nb      = (blwe_k + lby-1) // lby;
    column_proc_cycle_min = ks_block_line_nb * ks_lg_nb
    read_pipe_cycle_max   = lbx * batch_pbs_nb

    if ((lbz * ksk_w) > 32):
        ksk_acs_w = 64
    else:
        ksk_acs_w = 32
    ksk_coef_per_axi4_word  = AXI_W/ksk_acs_w

    if (q_w > 32):
        blwe_acs_w = 64
    else:
        blwe_acs_w = 32
    if (lby < (AXI_W // blwe_acs_w)):
        blwe_subw_coef_nb = lby
    else:
        blwe_subw_coef_nb = (AXI_W // blwe_acs_w)
    blwe_subw_nb = lby // blwe_subw_coef_nb


    return (
            (column_proc_cycle_min >= read_pipe_cycle_max)
            and (blwe_subw_nb*blwe_subw_coef_nb == lby)
            and  ((lby <= ksk_coef_per_axi4_word) or ((lby // ksk_coef_per_axi4_word)*ksk_coef_per_axi4_word == lby))
            and  ((lby >= ksk_coef_per_axi4_word) or (ksk_coef_per_axi4_word//lby)*lby == ksk_coef_per_axi4_word ))

def cstr_regf_seq (regf_seq, regf_coef):
    """
    Checks that :
    * regf_seq divides regf_coef
    * Number of coef per seq >=2
    """
    return ((regf_coef % regf_seq) == 0) and ((regf_coef // regf_seq) > 1)

def cstr_regf_lby (regf_seq, regf_coef, lby):
    """
    if regf_coef > lby
      we should have : regf_coef%lby == 0
      and            : regf_coef/regf_seq <= lby
    else
      we should have : lby%regf_coef == 0

    """
    if (regf_coef > lby):
        return ((regf_coef % lby) == 0) and (regf_coef/regf_seq <= lby)
    elif (regf_coef < lby):
        return (lby % regf_coef) == 0
    else:
        return True

def cstr_mmacc_infifo (r, s, psi, glwe_k):
    """
    MMACC infifo is composed of 1 BRAM depth, to avoid using to many BRAMs.
    Therefore the parameters must fulfill the constraint that this
    RAM cannot overflow.
    Actually, for the system to work, this RAM should be able to store at
    least MIN_INFIFO_CT_NB entire ciphertext.
    """
    n = r ** s
    coef = r * psi
    return ((BRAM_DEPTH / ((n * (glwe_k+1)) // coef)) >= MIN_INFIFO_CT_NB)

def cstr_run5 (s, glwe_k):
    """
    To avoid too long simulations, artificially limit value of k
    """
    if (s > 9):
        return (glwe_k < 3)
    else:
        return True

def cstr_run4 (r, psi, pbs_l, lby, lbz, ks_l):
    """
    To avoid too long simulations, artificially balance BR and KS size
    """
    v = (r*psi) / pbs_l
    w = (lby * lbz) / ks_l
    if (v > w):
        return (v/w < 8)
    else:
        return (w/v < 8)

def cstr_gram_arb (r,psi,s):
    """
    For the GRAM arbiter to work correctly, there should be an overlap between the 1rst and the
    2nd arbitration for feed and acc.
    This could be simplify by STG_ITER_NB >= 4
    """
    stg_iter_nb = 2**s // (r * psi)
    return stg_iter_nb >= 4

def cstr_mod_ntt_w_arch (mod_ntt_w, ntt_arch):
    """
    NTT_CORE_ARCH_gf64 only supports goldilocks
    """
    return (ntt_arch != "NTT_CORE_ARCH_gf64") or (mod_ntt_w == 64)

#==================================================================================================
# Main
#==================================================================================================
MAX_ITER=20
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Generate HPU parameters")
    parser.add_argument('-A', dest='ntt_arch',     type=str, help="NTT architecture", choices=['NTT_CORE_ARCH_gf64','NTT_CORE_ARCH_wmm_unfold_pcg'], default=None)
    parser.add_argument('-R', dest='r',            type=int, help="R: radix. (Supports only 2)",                     default=2)
    parser.add_argument('-P', dest='psi',          type=int, help="PSI: Number of butterflies.",                     default=-1)
    parser.add_argument('-S', dest='stage_nb',     type=int, help="2**S: Number of coefficients in a polynomial.",   default=-1)
    parser.add_argument('-g', dest='glwe_k',       type=int, help="GLWE_K",                                          default=-1)
    parser.add_argument('-V', dest='mod_ksk_w',    type=int, help="MOD_KSK_W.",                                      default=-1)
    parser.add_argument('-w', dest='mod_ntt_w',    type=int, help="MOD_NTT_W: Modulo width.",                        default=-1)
    parser.add_argument('-D', dest='axi_w',        type=int, help="AXI4_DATA_W: Axi4 bus data width.",               default=512)
    parser.add_argument('-d', dest='use_mean_comp',type=int, help="USE_MEAN_COMP.",                                  default=-1)
    parser.add_argument('-out_bash',               type=str, help="Output in bash format.", required=True)
    parser.add_argument('-s', dest='seed',         type=int, help="Seed.",                                           default=int(datetime.datetime.utcnow().timestamp()))
    parser.add_argument('-v', dest='verbose',                help="Run in verbose mode.", action="store_true",       default=False)

    args = parser.parse_args()

    AXI_W = args.axi_w

#=====================================================
# Set global seed
#=====================================================
    random.seed(args.seed)

#=====================================================
# Random variables
#=====================================================

    # Create randomizable object
    r1 = RandObj(max_iterations=MAX_ITER)
    r3 = RandObj(max_iterations=MAX_ITER)

    r1.add_rand_var("R"             , fn=rand_power_of, args=(2,set_val(args.r,2),set_val(args.r,2)), order=0)
    r1.add_rand_var("S"             , domain=range(set_val(args.stage_nb,7),set_val(args.stage_nb,11)+1), order=0)
    r1.add_rand_var("PSI"           , fn=rand_power_of, args=(2,set_val(args.psi,4),set_val(args.psi,64)), order=0)
    r1.add_rand_var("NTT_ARCH"      , domain=set_list(args.ntt_arch,['NTT_CORE_ARCH_wmm_unfold_pcg','NTT_CORE_ARCH_gf64']), order=0)
    r1.add_rand_var("MOD_NTT_W"     , domain=range(set_val(args.mod_ntt_w,32),set_val(args.mod_ntt_w,64)+1), order=0)
    r1.add_rand_var("GLWE_K"        , domain=range(set_val(args.glwe_k,1),set_val(args.glwe_k,3)+1), order=1)
    r1.add_rand_var("MOD_KSK_W"     , domain=range(set_val(args.mod_ksk_w,16),set_val(args.mod_ksk_w,32)+1), order=1)
    r1.add_rand_var("BATCH_PBS_NB"  , fn=rand_mult_by, args=(4,4,32), order=1)
    r1.add_rand_var("TOTAL_PBS_NB"  , fn=rand_mult_by, args=(4,8,64), order=1)
    r1.add_rand_var("PBS_L"         , domain=range(1,3+1), order=1)
    r1.add_rand_var("BWD_PSI_DIV"   , domain=range(1,2+1), order=1)
    r1.add_rand_var("PBS_B_W"       , domain=range(2,48+1), order=1)
    r1.add_rand_var("KS_L"          , domain=range(1,10+1), order=1)
    r1.add_rand_var("KS_B_W"        , domain=range(2,5+1), order=1)
    r1.add_rand_var("LBX"           , domain=range(1,4+1), order=1)
    r1.add_rand_var("LBY"           , fn=rand_power_of, args=(2,2,128), order=1)
    r1.add_rand_var("LBZ"           , domain=range(1,4+1), order=1)
    r1.add_rand_var("REGF_COEF_NB"  , fn=rand_power_of, args=(2,4,64), order=1)
    r1.add_rand_var("REGF_SEQ"      , fn=rand_power_of, args=(2,1,8), order=1)
    r1.add_rand_var("USE_MEAN_COMP" , domain=range(set_val(args.use_mean_comp,0),set_val(args.use_mean_comp,1)+1), order=0)

    r3.add_rand_var("USE_BPIP"      , domain={0: 1,1: 4}) # To keep some runs with IPIP (20%)
    r3.add_rand_var("RAM_LATENCY"   , domain=range(1,3+1))


#=====================================================
# Constraints
#=====================================================
#---------------
# r1
#---------------
    r1.add_constraint(cstr_r_psi_s, ('R','PSI','S'))
    r1.add_constraint(cstr_gt,('MOD_NTT_W','MOD_KSK_W'))
    r1.add_constraint(cstr_batch,('BATCH_PBS_NB','TOTAL_PBS_NB'))
    r1.add_constraint(cstr_pbs_level_div, ('BWD_PSI_DIV', 'PBS_L', 'NTT_ARCH', 'PSI'))
    r1.add_constraint(cstr_level, ('PBS_B_W','PBS_L','MOD_NTT_W'))
    r1.add_constraint(cstr_level, ('KS_B_W','KS_L','MOD_KSK_W'))
    r1.add_constraint(cstr_ks, ('KS_L', 'LBX', 'LBY', 'LBZ', 'R', 'S', 'GLWE_K', 'MOD_KSK_W', 'MOD_NTT_W','BATCH_PBS_NB'))
    r1.add_constraint(cstr_ksk_w, ('LBZ', 'MOD_KSK_W'))
    r1.add_constraint(cstr_regf_seq, ('REGF_SEQ', 'REGF_COEF_NB'))
    r1.add_constraint(cstr_regf_lby, ('REGF_SEQ', 'REGF_COEF_NB', 'LBY'))
    r1.add_constraint(cstr_mmacc_infifo,('R', 'S', 'PSI', 'GLWE_K'))
    r1.add_constraint(cstr_run4, ('R', 'PSI', 'PBS_L', 'LBY', 'LBZ', 'KS_L'))
    r1.add_constraint(cstr_run5, ('S', 'GLWE_K'))
    r1.add_constraint(cstr_gram_arb, ('R','PSI','S'))
    r1.add_constraint(cstr_mod_ntt_w_arch, ('MOD_NTT_W', 'NTT_ARCH'))

#=====================================================
# Randomize
#=====================================================
    try:
        r1.randomize()
    except RandomizationError:
        sys.exit(f"ERROR> No solution found for r1 after {MAX_ITER} iterations.")

    try:
        r3.randomize()
    except RandomizationError:
        sys.exit(f"ERROR> No solution found for r3 after {MAX_ITER} iterations.")

    extra_d = {
        "REGF_REG_NB" : max(2* r1.REGF_COEF_NB,MIN_REGF_REG),
        "MOD_Q_W" : r1.MOD_NTT_W,
    }

#=====================================================
# Print
#=====================================================
    # Bash file
    bfile_path = Path(args.out_bash)
    with open(bfile_path, 'w') as b_fp:
        b_fp.write(f"AXI_W={AXI_W}\n")
        for (k,v) in r1.get_results().items():
          b_fp.write(f"{k}={v}\n")
        for (k,v) in r3.get_results().items():
          b_fp.write(f"{k}={v}\n")
        for (k,v) in extra_d.items():
          b_fp.write(f"{k}={v}\n")
