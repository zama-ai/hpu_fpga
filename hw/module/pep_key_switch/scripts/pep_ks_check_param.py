#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import sys
import argparse # parse input argument

#==================================================================================================
# This script checks if the LBX LBY and LBZ parameters are supported.
#==================================================================================================


#=====================================================
# Main
#=====================================================
if __name__ == '__main__':
    # Default values
    BATCH_PBS_NB=8
    R=2
    S=11
    GLWE_K=1
    AXI_W=512
    KSK_W=21
    Q_W=64
#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Check LBX, LBY, LBZ")
    parser.add_argument('-dM', dest='batch_pbs_nb',  type=int, help="Max number of PBS per batch",
                               default=BATCH_PBS_NB)
    parser.add_argument('-R',  dest='radix',          type=int, help="Radix.",
                               default=R)
    parser.add_argument('-S', dest='stage',           type=int, help="Number of NTT stages.",
                               default=S)
    parser.add_argument('-g',  dest="glwe_k",         type=int, help="GLWE_K: Number of polynomials",
                               default=GLWE_K)
    parser.add_argument('-L', dest='ks_l',        type=int, help="Number key_switch levels",
                               required=True)
    parser.add_argument('-X', dest='lbx',         type=int, help="Number of columns processed in parallel in the key_switch",
                               required=True)
    parser.add_argument('-Y', dest='lby',         type=int, help="Number of lines processed in parallel in the key_switch",
                               required=True)
    parser.add_argument('-Z', dest='lbz',         type=int, help="Number of levels processed in parallel in the key_switch",
                               required=True)
    parser.add_argument('-A', dest='axi_w',       type=int, help="AXI4 bus width",
                               default=AXI_W)
    parser.add_argument('-V', dest='ksk_w',       type=int, help="KSK width",
                               default=KSK_W)
    parser.add_argument('-W', dest='q_w',         type=int, help="Ciphertext coef width",
                               default=Q_W)
    parser.add_argument('-v',  dest='verbose',              help="Run in verbose mode.",
                               default=False, action="store_true")

    args = parser.parse_args()

    VERBOSE = args.verbose
    BATCH_PBS_NB = args.batch_pbs_nb
    R = args.radix
    S = args.stage
    GLWE_K = args.glwe_k
    KS_L = args.ks_l
    LBX = args.lbx
    LBY = args.lby
    LBZ = args.lbz
    KSK_W = args.ksk_w
    AXI_W = args.axi_w
    Q_W = args.q_w

#=====================================================
# Intermediate values
#=====================================================

    KS_LG_NB = (KS_L + LBZ-1) // LBZ;
    BLWE_K = (R ** S) * GLWE_K
    KS_BLOCK_LINE_NB = (BLWE_K + LBY-1) // LBY;
    COLUMN_PROC_CYCLE_MIN = KS_BLOCK_LINE_NB * KS_LG_NB;
    READ_PIPE_CYCLE_MAX   = LBX * BATCH_PBS_NB;
    if ((LBZ * KSK_W) > 32):
        KSK_ACS_W = 64
    else:
        KSK_ACS_W = 32
    KSK_COEF_PER_AXI4_WORD  = AXI_W/KSK_ACS_W

    if (Q_W > 32):
        BLWE_ACS_W = 64
    else:
        BLWE_ACS_W = 32
    if (LBY < (AXI_W // BLWE_ACS_W)):
        BLWE_SUBW_COEF_NB = LBY
    else:
        BLWE_SUBW_COEF_NB = (AXI_W // BLWE_ACS_W)
    BLWE_SUBW_NB = LBY // BLWE_SUBW_COEF_NB

#=====================================================
# Check
#=====================================================
    if (VERBOSE):
      print("INFO> KS_LG_NB={:0d}".format(KS_LG_NB))
      print("INFO> KS_BLOCK_LINE_NB={:0d}".format(KS_BLOCK_LINE_NB))
      print("INFO> BATCH_PBS_NB={:0d}".format(BATCH_PBS_NB))
      print("INFO> LBX={:0d}".format(LBX))
      print("INFO> READ_PIPE_CYCLE_MAX={:0d}".format(READ_PIPE_CYCLE_MAX))

    # From KS process
    if (COLUMN_PROC_CYCLE_MIN < READ_PIPE_CYCLE_MAX):
        if (VERBOSE):
            print("ERROR> Unsupported LBX, LBY, LBZ. Not enough time to empty the KS output pipe.")
        sys.exit(1)
    if (BLWE_SUBW_NB*BLWE_SUBW_COEF_NB != LBY):
        if (VERBOSE):
            print("ERROR> Unsupported LBY value. Should have: BLWE_SUBW_NB(%0d)*BLWE_SUBW_COEF_NB(%0d) == LBY(%0d)", BLWE_SUBW_NB,BLWE_SUBW_COEF_NB,LBY)
        sys.exit(1)
    # From ksk_if
    if ((LBY > KSK_COEF_PER_AXI4_WORD) and ((LBY // KSK_COEF_PER_AXI4_WORD)*KSK_COEF_PER_AXI4_WORD != LBY)):
        if (VERBOSE):
            print("ERROR> Unsupported : LBY {:0d} should be a multiple of KSK_COEF_PER_AXI4_WORD {:0d}",LBY,KSK_COEF_PER_AXI4_WORD)
        sys.exit(1)
    if ((LBY < KSK_COEF_PER_AXI4_WORD) and (KSK_COEF_PER_AXI4_WORD//LBY)*LBY != KSK_COEF_PER_AXI4_WORD ):
        if (VERBOSE):
            print("ERROR> Unsupported : LBY {:0d} should divide KSK_COEF_PER_AXI4_WORD {:0d}",LBY,KSK_COEF_PER_AXI4_WORD)
        sys.exit(1)
