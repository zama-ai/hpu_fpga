#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# t = __import__("pbs_pbs_{:0d}".format(1))
# ----------------------------------------------------------------------------------------------
#  This script generate dummy input for the bench : tb_ntt_core_with_matrix_multiplication_pipeline
# ==============================================================================================

import os       # OS functions
import sys
import argparse # parse input argument
import random
import fcntl # Used for file-locking and mutual exclusion
from datetime import datetime
import glob # list filename
from math import log
import re
import gen_stimuli as gen
import gen_stimuli_pcg as gen_pcg

#=====================================================
# Global variables
#=====================================================
PROJECT_DIR = os.getenv("PROJECT_DIR")

#=====================================================
# Parameters : default values
#=====================================================
BSK_SRV_NB          = 3 # TODO remove deps from bsk network
LWE_K               = 29
BSK_INST_BR_LOOP_NB = [9,9,11]
S                   = 3
PSI                 = 8
R                   = 8
GLWE_K_P1           = 3
PBS_L               = 2
OP_W                = 32
MOD_Q_W             = 32
BATCH_MAX_PBS       = 10
BATCH_MIN_PBS       = 1
BWD_PSI_DIV         = 1
BATCH_NB            = 2
LWE_ACS_W           = 16
GLWE_RAM_SUBWORD_COEF_NB=512//MOD_Q_W
DELTA               = 6

# TODO properly derived this values from other parameters
AXI4_W              = 512
AXI4_BSK_W          = 512

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Generate twiddle for top.")
    parser.add_argument('-o',  dest='work_dir',              type=str, help="Working directory.",
                               required=True)
    parser.add_argument('-i',  dest='tv_dir',                type=str, help="Input test_vectors.py directory.",
                               required=True)
    parser.add_argument('-R',  dest='radix',                 type=int, help="Radix.",
                               default=R)
    parser.add_argument('-P',  dest='psi',                   type=int, help="PSI.",
                               default=PSI)
    parser.add_argument('-S',  dest='stage',                 type=int, help="Number of NTT stages.",
                               default=S)
    parser.add_argument('-l',  dest='pbs_l',                 type=int, help="PBS_L: Number of decomposed levels",
                               default=PBS_L)
    parser.add_argument('-K',  dest='lwe_k',                 type=int, help="LWE_K: Ciphertext number of coef",
                               default=LWE_K)
    parser.add_argument('-g',  dest="glwe_k",                type=int, help="GLWE_K: Number of polynomials",
                               default=GLWE_K_P1-1)
    parser.add_argument('-w',  dest='op_w',                  type=int, help="NTT Operand width.",
                               default=OP_W)
    parser.add_argument('-W',  dest='mod_q_w',               type=int, help="Operand width.",
                               default=OP_W)
    parser.add_argument('-bs', dest='bsk_srv_nb',            type=int, help="Number of BSK servers",
                               default=BSK_SRV_NB)
    parser.add_argument('-bn', dest='bsk_inst_br_loop_nb_l', type=int, help="Number of br_loop per BSK server. Append the value for each server, starting with server #0.",
                               default=[], action='append')
    parser.add_argument('-dM', dest='batch_max_pbs',         type=int, help="Max number of PBS per batch",
                               default=BATCH_MAX_PBS)
    parser.add_argument('-dm', dest='batch_min_pbs',         type=int, help="Min number of PBS per batch",
                               default=BATCH_MIN_PBS)
    parser.add_argument('-e',  dest='bwd_psi_div',           type=int, help="PSI divider for Backward path. Set to 1 if not an NTT unfold architecture.",
                               default=BWD_PSI_DIV)
    parser.add_argument('-A',  dest='ntt_core_wmm_arch',     type=str, help="NTT core wmm architecture",
                               default='NTT_CORE_ARCH_wmm_compact_pcg', choices=['NTT_CORE_ARCH_wmm_compact_pcg', 'NTT_CORE_ARCH_wmm_pipeline_pcg', 'NTT_CORE_ARCH_wmm_unfold_pcg', 'NTT_CORE_ARCH_wmm_compact', 'NTT_CORE_ARCH_wmm_pipeline', 'NTT_CORE_ARCH_wmm_unfold'])
    parser.add_argument('-s',  dest='seed',                  type=int, help="Seed",
                               default=None)
    parser.add_argument('-u',  dest='use_ordered_batch',     help="Process PBS/batch in order. Default : disorder",
                               default=False, action="store_true")
    parser.add_argument('-B',  dest='batch_nb',              type=int, help="BATCH_NB: Number of interleved batches. Default : 2",
                               default=BATCH_NB)
    parser.add_argument('-lw', dest='lwe_acs_w',             type=int, help="LWE_ACS_W: LWE transfer size.",
                               default=LWE_ACS_W)
    parser.add_argument('-delta', dest='delta',              type=int, help="DELTA: PCG CLBU delta parameter.",
                               default=DELTA)
    parser.add_argument('-v',  dest='verbose',                help="Run in verbose mode.",
                               default=False, action="store_true")

    args = parser.parse_args()

    SEED = args.seed
    if (SEED == None):
      SEED = random.randrange(sys.maxsize)
    random.seed(args.seed)

    VERBOSE = args.verbose
    USE_ORDERED_BATCH = args.use_ordered_batch
    BATCH_NB = args.batch_nb
    WORK_DIR = args.work_dir
    TV_DIR = args.tv_dir
    NTT_CORE_WMM_ARCH = args.ntt_core_wmm_arch
    R = args.radix
    PSI = args.psi
    S = args.stage
    OP_W = args.op_w
    MOD_Q_W = args.mod_q_w
    PBS_L = args.pbs_l
    LWE_K = args.lwe_k
    GLWE_K_P1 = args.glwe_k + 1
    BSK_SRV_NB = args.bsk_srv_nb
    BATCH_MAX_PBS = args.batch_max_pbs
    BATCH_MIN_PBS = args.batch_min_pbs
    BWD_PSI_DIV = args.bwd_psi_div
    LWE_ACS_W = args.lwe_acs_w
    if (MOD_Q_W > 32):
      GLWE_ACS_W     = 64;
      BLWE_ACS_W     = 64;
    else:
      GLWE_ACS_W     = 32;
      BLWE_ACS_W     = 32;
    DELTA = args.delta


    # Deduce the used parameters
    GLWE_RAM_SUBWORD_COEF_NB = AXI4_W // GLWE_ACS_W
    if (GLWE_RAM_SUBWORD_COEF_NB > PSI*R):
      GLWE_RAM_SUBWORD_COEF_NB = PSI*R
      #AXI4_W = GLWE_RAM_SUBWORD_COEF_NB * MOD_Q_W
    GLWE_RAM_SUBWORD_NB = (PSI*R) // GLWE_RAM_SUBWORD_COEF_NB
    BWD_PSI = PSI // BWD_PSI_DIV
    if (len(args.bsk_inst_br_loop_nb_l) != 0):
        BSK_INST_BR_LOOP_NB = args.bsk_inst_br_loop_nb_l
    else:
        BSK_INST_BR_LOOP_NB = []
        remain = LWE_K
        for i in range(BSK_SRV_NB):
            if (i==BSK_SRV_NB-1):
                BSK_INST_BR_LOOP_NB.append(remain)
            else:
                BSK_INST_BR_LOOP_NB.append(LWE_K // BSK_SRV_NB)
            remain = remain - (LWE_K // BSK_SRV_NB)

    N              = R**S
    STG_ITER_NB    = N // (R*PSI)
    BWD_STG_ITER_NB= N // (R*BWD_PSI)
    INTL_L         = PBS_L * GLWE_K_P1
    LWE_COEF_W     = int(log(2*N,2))
    if (MOD_Q_W > 32):
      GLWE_ACS_W     = 64;
      BLWE_ACS_W     = 64;
    else:
      GLWE_ACS_W     = 32;
      BLWE_ACS_W     = 32;
    TWD_PHRU_RD_NB = 2
    if (R < 4):
        TWD_PHRU_RD_NB      = 1
    TWD_PHRU_RD_PER_RAM = (TWD_PHRU_RD_NB * 2)

    RS_DELTA = DELTA
    LS_DELTA = S % DELTA
    if (LS_DELTA == 0):
      LS_DELTA = DELTA

    RS_DELTA_IDX = RS_DELTA - 1
    LS_DELTA_IDX = LS_DELTA - 1

    if (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_compact_pcg'):
        LPB_NB = (S+DELTA-1)//DELTA
        CLBU_NB = 1
    else:
        LPB_NB = 1
        CLBU_NB = (S+DELTA-1)//DELTA

    USE_PCG = 0
    if (re.match('.*_pcg$',NTT_CORE_WMM_ARCH)):
        USE_PCG = 1

    # Check BWD_PSI_DIV
    if (NTT_CORE_WMM_ARCH != 'NTT_CORE_ARCH_wmm_unfold' and NTT_CORE_WMM_ARCH != 'NTT_CORE_ARCH_wmm_unfold_pcg'  and BWD_PSI_DIV != 1):
        sys.exit("ERROR> BWD_PSI_DIV must be set to 1 for architecture different from NTT_CORE_ARCH_wmm_unfold. BWD_PSI_DIV={:0d}".format(BWD_PSI_DIV))

    # Check number of PBS per batch
    if (BATCH_MAX_PBS < BATCH_MIN_PBS):
        sys.exit("ERROR> BATCH_MAX_PBS ({:0d}) must be greater or equal to BATCH_MIN_PBS ({:0d})".format(BATCH_MAX_PBS,BATCH_MIN_PBS))

    # Check LPB_NB and DELTAs
    if (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_compact_pcg'):
        if (((LPB_NB-1) * RS_DELTA + LS_DELTA) != S):
            sys.exit("ERROR> LPB_NB ({:0d}), RS_DELTA({:0d}) and LS_DELTA({:0d}) are incoherent.".format(LPB_NB,RS_DELTA,LS_DELTA))

#=====================================================
# Take system-wide lock
# Prevent multiple instance of this RAM-hungry script to run in //
# => Use a mutex in the filesystem to serialize them
#=====================================================
    import os
    lock_f = open(f'/var/lock/{os.environ["USER"]}_zama_ci_gen_stimuli_mutex', 'a')
    fcntl.lockf(lock_f, fcntl.LOCK_EX)
    lock_f.write(f'{os.getpid()} @{datetime.today()}\n')

#=====================================================
# Test vectors
#=====================================================
    # Import test vector directory
    sys.path.append(TV_DIR)
    import twd_fwd_bwd as twd

#=====================================================
# Output
#=====================================================
    # Generate twiddle intt final files
    if (USE_PCG):
        gen_pcg.generate_twd_ifnl(R,S,BWD_PSI,OP_W,BWD_STG_ITER_NB,twd.ntt_fm_factors,LS_DELTA_IDX,WORK_DIR)
    else:
        gen.generate_twd_ifnl(R,S,BWD_PSI,OP_W,BWD_STG_ITER_NB,twd.ntt_fm_factors,WORK_DIR)

    # Generate twiddle phi ru files
    if (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_compact'):
        gen.generate_twd_phru_compact(R,S,PSI,OP_W,STG_ITER_NB,twd.ntt_fwd_twiddles, twd.ntt_bwd_twiddles,TWD_PHRU_RD_NB,WORK_DIR)
    elif (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_pipeline'):
        gen.generate_twd_phru_pipeline(R,S,PSI,OP_W,STG_ITER_NB,twd.ntt_fwd_twiddles, twd.ntt_bwd_twiddles,TWD_PHRU_RD_NB,WORK_DIR)
    elif (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_unfold'):
        gen.generate_twd_phru_unfold(R,S,PSI,BWD_PSI,OP_W,STG_ITER_NB,BWD_STG_ITER_NB,twd.ntt_fwd_twiddles, twd.ntt_bwd_twiddles,TWD_PHRU_RD_NB,WORK_DIR)
    elif (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_compact_pcg'):
        gen_pcg.generate_twd_phru_compact(R,S,PSI,OP_W,STG_ITER_NB,twd.ntt_fwd_twiddles, twd.ntt_bwd_twiddles,LPB_NB, RS_DELTA_IDX, LS_DELTA_IDX, DELTA,TWD_PHRU_RD_NB,WORK_DIR)
    elif (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_unfold_pcg'):
        gen_pcg.generate_twd_phru_unfold(R,S,PSI,BWD_PSI,OP_W,STG_ITER_NB,BWD_STG_ITER_NB,twd.ntt_fwd_twiddles, twd.ntt_bwd_twiddles,LS_DELTA, DELTA, CLBU_NB,TWD_PHRU_RD_NB,WORK_DIR)
    else:
        sys.exit("ERROR> Unupported NTT_CORE_WMM_ARCH : {:s}".format(NTT_CORE_WMM_ARCH))

#=====================================================
# Release system-wide-lock
#=====================================================
    fcntl.lockf(lock_f, fcntl.LOCK_UN)
