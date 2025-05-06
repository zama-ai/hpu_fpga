#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import sys  # manage errors
import argparse  # parse input argument
from math import log, pow, ceil
import copy

from ntt_lib import *

###############################################################################
# Default global variable
###############################################################################
VERBOSE = False

###############################################################################
# Reference
###############################################################################
def ref_network(data_l, cut_l, bwd, rdx_col_id):
    """
    Reorder data_l, which are the data at the output of rdx_col_id, as the network
    would do for the next radix column, according to cut_l, bwd.
    In FWD NTT rdx_col_id is numbered increasingly, in BWD NTT it is numbered
    decreasingly.
    """
    N = len(data_l)

    s_l = 0
    if (bwd):
        cid = len(cut_l)-1 - rdx_col_id
        for i in range(cid+2):
            s_l = s_l + cut_l[len(cut_l)-1-i]
        n_l = 2**s_l
        rdx_1 = 2**cut_l[rdx_col_id-1]
        rdx_0 = n_l // rdx_1
    else:
        for i in range(rdx_col_id, len(cut_l)):
            s_l = s_l + cut_l[i]
        n_l = 2**s_l
        rdx_0 = 2**cut_l[rdx_col_id]
        rdx_1 = n_l // rdx_0


    out_l = []
    for b in range(N//n_l): # For each working block
        for r1 in range(n_l//rdx_1): # For each radix 1 within the working block
            l = [data_l[b*n_l + i*(n_l//rdx_1) + r1] for i in range(rdx_1)]
            out_l = out_l + l

    return out_l


###############################################################################
# Network
###############################################################################
def network(data_l, cut_l, bwd, rdx_col_id, coef):
    """
    Reorder data_l, which are the data at the output of rdx_col_id, as the hw
    would do for the next radix column, according to cut_l, bwd, and coef :
    which is the number of coef of data_l seen at an instant (parallelism).
    In FWD NTT rdx_col_id is numbered increasingly, in BWD NTT it is numbered
    decreasingly.
    """
    N = len(data_l)

    s_l = 0
    if (bwd):
        cid = len(cut_l)-1 - rdx_col_id
        for i in range(cid+2):
            s_l = s_l + cut_l[len(cut_l)-1-i]
        n_l = 2**s_l
        rdx_1 = 2**cut_l[rdx_col_id-1]
        rdx_0 = n_l // rdx_1
    else:
        for i in range(rdx_col_id, len(cut_l)):
            s_l = s_l + cut_l[i]
        n_l = 2**s_l
        rdx_0 = 2**cut_l[rdx_col_id]
        rdx_1 = n_l // rdx_0


    # Number of rdx_0/rdx_1 block in the working block
    rdx_0_nb = n_l // rdx_0  # = rdx_1
    rdx_1_nb = n_l // rdx_1  # = rdx_0

    iter_nb   = N // coef

    # In the following, define some parameters, that will caracterize
    # the network.
    # cons_nb : number of consecutive elements per iteration
    # set_nb  : number of rdx1 written per iteration for 1 read iteration
    #           Is also the number of RDX1 visible in the coef window
    # pos_iter_nb : Number of iterations to write all the element of a
    #               given position
    # complete_rd_iter_nb : number of iterations to gather all the elements of a read iteration. (not necessarily consecutive)
    # rd_iter_nb : number of iterations to read an entire RDX1
    # target_rdx1_nb : number of RDX1 built at the same time during 1 iteration
    # target_rd_iter_nb  : number of rd iterations targeted with 1 iteration
    # pos : input position in RDX1 of the first element of the coef window.
    #

    if (rdx_1_nb >= coef): # Single position is present among the input coef
        cons_nb = 1
        do_interleave = False
        target_rdx1_nb = coef
    else : # rdx_1_nb < coef
        cons_nb = coef // rdx_1_nb
        do_interleave = True
        target_rdx1_nb = rdx_1_nb

    if (rdx_1 > coef): # Part of the RDX1 input are seen per iteration
        set_nb = 1
        rd_iter_nb = rdx_1 // coef
        do_dispatch = False
    else: # entire RDX1 are seen per iteration
        set_nb = coef // rdx_1
        rd_iter_nb = 1
        do_dispatch = True

    pos_iter_nb = rdx_1_nb // target_rdx1_nb
    disp_stride = set_nb
    complete_rd_iter_nb = coef // (cons_nb * set_nb)
    target_rd_iter_nb = target_rdx1_nb // set_nb


    if (VERBOSE):
        print("------------------------------------------")
        print(f"# n_l={n_l} rdx_0={rdx_0} rdx_1={rdx_1} rdx_1_nb={rdx_1_nb}")
        print(f"# do_interleave={do_interleave} do_dispatch={do_dispatch} disp_stride={disp_stride}")
        print(f"# cons_nb={cons_nb} set_nb={set_nb} pos_iter_nb={pos_iter_nb}")
        print(f"# rd_iter_nb={rd_iter_nb} complete_rd_iter_nb={complete_rd_iter_nb} target_rdx1_nb={target_rdx1_nb} target_rd_iter_nb={target_rd_iter_nb}")


    out_l = []
    if (n_l <= coef): # All coef of the working block are visible in the coef window.
                    # In hw we can do direct connection, without network
        if (VERBOSE):
            print("------------------------------------------")
            print(f">> Direct connection n_l={n_l} rdx_0={rdx_0} rdx_1={rdx_1}")

        for iter in range (iter_nb):
              for b in range(coef//n_l): # For each working block within coef window
                  for r1 in range(n_l//rdx_1): # For each radix 1 within the working block
                      l = [data_l[iter*coef + b*n_l + i*(n_l//rdx_1) + r1] for i in range(rdx_1)]
                      out_l = out_l + l


    else: # n_l > coef
        #Use a RAM to store the data
        ram = [[0 for _ in range(coef)] for _ in range (iter_nb)]


        for b in range(N//n_l): # For each working block
            w_iter_nb = n_l // coef
            add_b_ofs = b * w_iter_nb
            for w_iter in range(w_iter_nb): # for each iteration in this working blk
                d_l = data_l[b*n_l + (w_iter* coef) : b*n_l + (w_iter + 1)*coef] # current coef window
                pos = (w_iter * coef) // rdx_1_nb

                if (VERBOSE):
                    print("------------------------------------------")
                    print(f"#WB={b} w_iter={w_iter} n_l={n_l} pos_0={pos} rdx_0={rdx_0} rdx_1={rdx_1}")
                    print("#DATA = "+str(d_l))

                if (do_interleave):
                    intl_l = [d_l[x] for x in inc_stride(coef, rdx_1_nb, 1)]
                else:
                    intl_l = d_l

                if (VERBOSE):
                    print("#INTL = "+str(intl_l))

                if (do_dispatch):
                    dispatch_l = [intl_l[x] for x in inc_stride(coef, disp_stride, cons_nb)]
                else:
                    dispatch_l = intl_l

                if (VERBOSE):
                    print(f"#DISP[{disp_stride}] = "+str(dispatch_l))

                # rotation
                rot_factor = pos % coef
                rot_l = [dispatch_l[(x - rot_factor) % coef] for x in range(coef)]

                if (VERBOSE):
                    print("#ROT[{:0d}] = ".format(rot_factor)+str(rot_l))

                add_l = [ add_b_ofs + ( y*rd_iter_nb + (w_iter % pos_iter_nb)*(target_rd_iter_nb*rd_iter_nb) + (w_iter // (pos_iter_nb*complete_rd_iter_nb)))%w_iter_nb for x in range(set_nb) for y in range(target_rdx1_nb//set_nb) for z in range(cons_nb)]

                rot_add_l = [add_l[(x - rot_factor) % coef] for x in range(coef)]
                if (VERBOSE):
                    print("#ADD     = "+str(add_l))
                    print("#ROT_ADD = "+str(rot_add_l))

                # Write in RAM
                for i in range(coef):
                    if (ram[rot_add_l[i]][i] != 0):
                        sys.exit(f"ERROR> Overwrite RAM location @{rot_add_l[i]} pos={i} with value {rot_l[i]}")
                    ram[rot_add_l[i]][i] = rot_l[i]

                if (VERBOSE):
                    for i in range(b*w_iter_nb, (b+1)*w_iter_nb):
                        s = ""
                        for v in ram[i]:
                            s = s + "{:02d}, ".format(v)
                        print(f"RAM[{i}] = {s}")

            # read from RAM
            rd_mod = w_iter_nb
            for (w_iter,d_l) in enumerate(ram):
                if ((w_iter >= b*w_iter_nb) and (w_iter < (b+1)*w_iter_nb)):
                    ii = (w_iter%w_iter_nb)
                    rdx_1_id = (ii * coef) // rdx_1

                    if (rdx_1 > coef):
                        rot_factor = (rdx_1_id % (coef // cons_nb)) * cons_nb
                    else:
                        rot_factor = (rdx_1_id % set_nb) * rdx_1 + ((rdx_1_id//set_nb)%(rdx_1//cons_nb))*cons_nb

                    rot_d_l = [d_l[(x + rot_factor) % coef] for x in range(coef)]
                    if (VERBOSE):
                        print("#READ[{:0d}] ROT[{:0d}] = ".format(w_iter,rot_factor)+str(rot_d_l))

                    out_l = out_l + rot_d_l
                    if (VERBOSE):
                        print("++++++" + str(out_l))


    return out_l

###############################################################################
# Main
###############################################################################
if __name__ == "__main__":
# ==============================================================================
# Parse input arguments
# ==============================================================================
    parser = argparse.ArgumentParser(
        description="Compute the NTT with GF64 as prime."
    )
    parser.add_argument(
        "-N",
        dest="N",
        type=int,
        help="Polynomial size. Should be a power of 2.",
        default=256,
    )
    parser.add_argument(
        "-cut",
        dest="cut_l",
        type=int,
        action='append',
        help="NTT cut pattern. Given from input to output. The first one is the ngc",
        default=[],
    )
    parser.add_argument(
        "-coef",
        dest="coef",
        type=int,
        help="Number of coefficients that are processed in parallel. Should be a power of 2, and less than N.",
        default=0,
    )
    parser.add_argument(
        "-v",
        dest="verbose",
        help="Run in verbose mode.",
        action="store_true",
        default=False,
    )

    args = parser.parse_args()

    N = args.N
    COEF = args.coef
    cut_l = args.cut_l
    VERBOSE = args.verbose

    S = int(log(N,2))

# ==============================================================================
# Check input arguments
# ==============================================================================
    if (2**S != N):
        sys.exit(f"ERROR> N ({N}) Should be a power of 2")

    if (len(cut_l) == 0):
        cut_l.append(S)

    total_s = 0
    for i in cut_l:
        total_s = total_s + i

    if (total_s != S):
        sys.exit(f"ERROR> The given cut pattern {cut_l} does not fit N ({N})")

    if (COEF != 0 and 2**(int(log(COEF,2))) != COEF):
        sys.exit(f"ERROR> COEF ({COEF}) should be a power of 2")

    if (COEF != 0 and COEF < 2):
        sys.exit(f"ERROR> COEF ({COEF}) should be greater or equal to 2")

# ==============================================================================
# Build reference
# ==============================================================================
    in_data_l=[i for i in range(N)]

    # ref_l[bwd][cid]
    ref_l = []
    for i in range(2):
        bwd = (i==1)
        ref_l.append([])
        for cid in range(len(cut_l)-1):
            rdx_col_id = cid
            if (bwd):
                rdx_col_id = len(cut_l)-1 - cid
            ref_l[-1].append(ref_network(in_data_l, cut_l, bwd, rdx_col_id))

            #print(f"BWD={i} rdx_col_id={rdx_col_id}");
            #for v in out_l:
            #    print(v)

# ==============================================================================
# Build network
# ==============================================================================
    ntw_l = []
    for i in range(2):
        bwd = (i==1)
        ntw_l.append([])
        for cid in range(len(cut_l)-1):
            if (VERBOSE):
                print("##########################################")
                print(f"##### BWD={i} cid={cid}")
                print("##########################################")
            rdx_col_id = cid
            if (bwd):
                rdx_col_id = len(cut_l)-1 - cid
            ntw_l[-1].append(network(in_data_l, cut_l, bwd, rdx_col_id,COEF))

# ==============================================================================
# Check
# ==============================================================================
    match = True
    for i in range(2): # FWD / BWD
        for cid in range(len(cut_l)-1):
            if (VERBOSE):
                print(f"##### CHECK BWD={i} cid={cid}")
            for r,n in zip(ref_l[i][cid],ntw_l[i][cid]):
                if (VERBOSE):
                    print("ref=0x{:03x} ntw=0x{:03x}  => match={:b}".format(r,n,r==n))
                if (r != n):
                    match = False

    if not(match):
        sys.exit("ERROR> Data mismatch!")


