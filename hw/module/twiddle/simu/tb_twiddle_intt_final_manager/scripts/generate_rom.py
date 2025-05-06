# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Description  : generate rom script
# ----------------------------------------------------------------------------------------------
#
#  Generate the roms according to the design parameters PSI, R, S
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
    parser.add_argument("-o",  type=str, help="Output directory")

    args = parser.parse_args()

    ## ========================================================================================== ##
    # PARAMETER definition
    R = args.R
    PSI = args.P
    S = args.S
    GEN_DIR = args.o
    STG_ITER_NB = int((R ** (S-1)) / PSI)
    RD_NB = 2

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
    # ------------------------------------------------------------------------------------------- ##
    # Building pre-process
    # ------------------------------------------------------------------------------------------- ##
    stg = 0
    listFile = []

    for stg_iter in range(0, STG_ITER_NB):
        for i in range(0, R*PSI):
            listFile.append(
                i +
                stg_iter * (2 ** (R_W + PSI_W))
            )

    u = []
    RL = R // RD_NB

    for p in range(0, PSI):
        u.append([])
        for r in range(0, RL):
            u[-1].append(open(os.path.join(GEN_DIR, "data_" + str(p) + "_" + str(r) + FILE_SUFFIX), 'w'))

    p = 0
    r = 0
    for j in range(0, len(listFile), 2):
        u[p][r].write("{:0x}\n".format(listFile[j]))
        u[p][r].write("{:0x}\n".format(listFile[j+1]))
        r = r + 1
        if RL == r :
            r = 0
            p = p + 1
            if (p == PSI) :
                p = 0
#    for p in range(0, PSI):
#        for r in range(0,R//2):
#            for j in range(p*R+r*2,len(listFile),PSI*R):
#                u[p][r].write("{:0x}\n".format(listFile[j]))
#                u[p][r].write("{:0x}\n".format(listFile[j+1]))

    for p in range(0, PSI):
        for r in range(0, RL):
            u[p][r].close()
