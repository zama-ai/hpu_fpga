# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Description  : generate rom script
# ----------------------------------------------------------------------------------------------
#
#  Generate the roms according to the design parameters PSI, R, S, S_INIT, S_DEC
#  The script generate the "twiddle" list in order according to the testbench definition.
#
# ----------------------------------------------------------------------------------------------
# Libraries
# ==============================================================================================

import os, sys, stat  # OS functions
import sys
import argparse  # parse input argument
import math


## ---------------------------------------------------------------------------------------------- ##
# Directories and path
PROJECT_DIR = os.getenv("PROJECT_DIR")
FILE_NAME = "data"
FILE_SUFFIX = ".mem"
## ---------------------------------------------------------------------------------------------- ##

## ============================================================================================== ##
# Main
## ============================================================================================== ##

if __name__ == '__main__':
    # Argument parser
    parser = argparse.ArgumentParser(description="script for data twiddle generation")
    parser.add_argument("-P",  type=int, help="Parameter PSI", default=8)
    parser.add_argument("-R",  type=int, help="Parameter R", default=8)
    parser.add_argument("-S",  type=int, help="Parameter S", default=3)
    parser.add_argument("-si", type=int, help="Parameter S_INIT", default=2)
    parser.add_argument("-sd", type=int, help="Parameter S_DEC", default=1)
    parser.add_argument("-o",  type=str, help="Output directory")

    args = parser.parse_args()

    ## ========================================================================================== ##
    # PARAMETER definition
    S_INIT = args.si
    S_DEC = args.sd
    R = args.R
    PSI = args.P
    S = args.S
    OUTPUT_DIR = args.o
    GEN_DIR = os.path.join(OUTPUT_DIR) 
    STG_ITER_NB = int((R ** (S-1)) / PSI)

    DO_LOOPBACK  = 1
    if (S_DEC == 0):
        DO_LOOPBACK = 0

    NTT_BWD_INIT = 0
    NTT_BWD_NB   = 2

    if not(DO_LOOPBACK):
        NTT_BWD_NB = 1

    S_DEC_L      = S_DEC % S
    S_INIT_L     = S_INIT
    if (S_INIT >= S):
        S_INIT_L     = S_INIT - S
        NTT_BWD_INIT = 1

    if R >= 4:
        RD_NB = 2
    else:
        RD_NB = 1

    if R==1:
        R_W = 1
    else:
        R_W = math.ceil(math.log2(R))

    if PSI==1:
        PSI_W = 1
    else:
        PSI_W = math.ceil(math.log2(PSI))

    if S==1:
        STG_W = 1
    else:
        STG_W = math.ceil(math.log2(S))

    if (STG_ITER_NB == 1) :
        STG_ITER_W = 1
    else :
        STG_ITER_W = math.ceil(math.log2(STG_ITER_NB))

    ## ========================================================================================== ##
    stg = 0
    data = []

    for i in range(0, NTT_BWD_NB):
        ntt_bwd = (NTT_BWD_INIT + i)%2
        if ntt_bwd != NTT_BWD_INIT:
            s_init = (stg - S_DEC + S) 
        else:
            s_init = S_INIT_L
        if (S_DEC_L == 0):
            stg_nb = 1
        else:
            stg_nb = 1 + s_init // S_DEC_L
        for s in range(0, stg_nb):
            stg = s_init - s*S_DEC_L
            for stg_iter in range(0, STG_ITER_NB):
                for n in range(0, RD_NB):
                    d = []
                    for p in range(0, PSI):
                        for r in range(0, R // (RD_NB * 2)):
                            for i in range(0, 2):
                                d.append(
                                    n * RD_NB + r * (RD_NB * 2) + i +
                                    p         * (2 ** (R_W)) +
                                    stg_iter  * (2 ** (R_W + PSI_W)) +
                                    stg       * (2 ** (R_W + PSI_W  + STG_ITER_W)) +
                                    ntt_bwd   * (2 ** (R_W + PSI_W  + STG_ITER_W + STG_W))
                                )
                    data.append(d)

    listFile = []
    for i in data:
        for item in i:
            listFile.append(item)

    u = []
    RL = R // (RD_NB * 2)

    for p in range(0,PSI):
        u.append([])
        for r in range(0,RL):
            u[-1].append(open(os.path.join(GEN_DIR, "data_" + str(p) + "_" + str(r) + FILE_SUFFIX), 'w'))

    p = 0
    r = 0
    for j in range(0, len(listFile), 2):
        #print(p, r, j, len(listFile))
        u[p][r].write("{:0x}\n".format(listFile[j]))
        u[p][r].write("{:0x}\n".format(listFile[j+1]))
        r = r + 1
        if RL == r : 
            r = 0
            p = p + 1
            if (p == PSI) :
                p = 0

    for p in range(0,PSI):
        for r in range(0,RL):
            u[p][r].close()
