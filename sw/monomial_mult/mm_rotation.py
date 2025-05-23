#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import sys  # manage errors
from math import log, pow
import argparse  # parse input argument

# ==============================================================================
# Global variables
# ==============================================================================
VERBOSE = False

# ==============================================================================
# pseudo_reverse_order
# ==============================================================================
def pseudo_reverse_order(v, R, S):
    """
    For an index v in 0...R^S, if we decompose it in the R-base:
    v = v_0*R^0 + v_1*R^1 + ... v_(S-1)*R^(S-1)
    where v_j is in 0...R-1.
    The pseudo reverse_order of v in base R, for a number of stages S is:
    pseudo_reverse_order(v) = v_0*R^(S-1) + v_1*R^(0) + v_2*R(1)... v_(S-1)*R^(S-2)

    R is a power of 2.
    """
    r_width = int(log(R, 2))
    if pow(2, r_width) != R:
        sys.exit("ERROR> Radix R must be a power of 2")

    mask = (1 << r_width) - 1

    v_0 = v & mask
    rev = (v >> r_width)
    rev = rev + v_0 * R**(S-1)
    return rev

# ==============================================================================
# get_r
# ==============================================================================
def get_r_psi_stgiter(v, R, PSI, STG_ITER_NB, order):
    """
    This function extracts the (r index, psi index, stg_iter) value from v.
    If v is a 'natural' (N) counter, v = {stg_iter,psi,r}.
    if v in a pseudo-reverse (PR) counter, v = {r,stg_iter,psi}.
    """

    r_width = int(log(R, 2))
    psi_width = int(log(PSI, 2))
    stg_iter_width = int(log(STG_ITER_NB, 2))
    if pow(2, r_width) != R:
        sys.exit("ERROR> The radix R must be a power of 2")
    if pow(2, psi_width) != PSI:
        sys.exit("ERROR> PSI must be a power of 2")
    if pow(2, stg_iter_width) != STG_ITER_NB:
        sys.exit("ERROR> STG_ITER_NB must be a power of 2")

    r_mask = (1 << r_width) - 1
    psi_mask = (1 << psi_width) - 1
    stg_iter_mask = (1 << stg_iter_width) - 1

    if (order == "N"):
        r = v
        psi = r >> r_width
        stg_iter = psi >> psi_width

    elif (order == "PR"):
        psi = v
        stg_iter = psi >> psi_width
        r = stg_iter >> stg_iter_width

    else:
        sys.exit("ERROR> Unrecognized order: {:s}".format(order))

    r = r & r_mask
    psi = psi & psi_mask
    stg_iter = stg_iter & stg_iter_mask

    return (r,psi,stg_iter)

# ==============================================================================
# Main
# ==============================================================================
if __name__ == "__main__":
    # default values
    R = 8  # Radix
    PSI = 8  # Number of radix-R blocks used in parallel
    S = 3  # R^S = N the number of coefficients to be processed by the NTT

    # ==============================================================================
    # Parse input arguments
    # ==============================================================================
    parser = argparse.ArgumentParser(
        description="Check the monomult."
    )
    parser.add_argument(
        "-R",
        dest="radix",
        type=int,
        help="Radix value. Should be a power of 2.",
        default=R,
    )
    parser.add_argument(
        "-P",
        dest="parallel_nb",
        type=int,
        help="Number of radix blocks that work in parallel",
        default=PSI,
    )
    parser.add_argument(
        "-S",
        dest="stg_nb",
        type=int,
        help="Total number of stages. Note that R^S = N the number of coefficients of the NTT",
        default=S,
    )
    parser.add_argument(
        "-v",
        dest="verbose",
        help="Run in verbose mode.",
        action="store_true",
        default=False,
    )


    args = parser.parse_args()

    R = args.radix
    PSI = args.parallel_nb
    S = args.stg_nb
    VERBOSE = args.verbose

    N = R**S
    STG_ITER_NB = N // (PSI*R)

    ### Compute for every rotation values
    for rot in range(2*N):
        if (VERBOSE):
            print("#==========================================")
            print("# rot={:0d}".format(rot))
            print("#==========================================")

        # initialize
        proc_l = []
        read_l = []
        for stg_iter in range(STG_ITER_NB):
            proc_l.append([])
            read_l.append([])
            for p in range(PSI):
                proc_l[-1].append([])
                read_l[-1].append([])
                for r in range(R):
                    proc_l[-1][-1].append([])
                    read_l[-1][-1].append([])

        ref_d = {}
        for v in range(N):
            # Find the rotated of i
            v_rot = v + rot
            sign = 0
            if (v_rot >= N and v_rot < 2*N):
                sign = 1
            v_rot = v_rot % N
            ref_d[v] = {}
            ref_d[v]['rot'] = v_rot
            ref_d[v]['sign'] = sign
            ref_d[v]['add'] = list(get_r_psi_stgiter(v, R, PSI, STG_ITER_NB, "PR"))
            ref_d[v]['rot_add'] = list(get_r_psi_stgiter(v_rot, R, PSI, STG_ITER_NB, "PR"))

            r = ref_d[v]['add'][0]
            psi = ref_d[v]['add'][1]
            stg_iter = ref_d[v]['add'][2]
            rot_r = ref_d[v]['rot_add'][0]
            rot_psi = ref_d[v]['rot_add'][1]
            rot_stg_iter = ref_d[v]['rot_add'][2]

            proc_l[stg_iter][psi][r] = {}
            proc_l[stg_iter][psi][r]['v'] = v
            proc_l[stg_iter][psi][r]['v_rot'] = v_rot
            proc_l[stg_iter][psi][r]['rot_r'] = rot_r
            proc_l[stg_iter][psi][r]['rot_psi'] = rot_psi
            proc_l[stg_iter][psi][r]['rot_stg_iter'] = rot_stg_iter
            proc_l[stg_iter][psi][r]['sign'] = sign

            read_l[stg_iter][rot_psi][rot_r] = {}
            read_l[stg_iter][rot_psi][rot_r]['v'] = v
            read_l[stg_iter][rot_psi][rot_r]['r'] = r
            read_l[stg_iter][rot_psi][rot_r]['psi'] = psi
            read_l[stg_iter][rot_psi][rot_r]['rot_stg_iter'] = rot_stg_iter
            read_l[stg_iter][rot_psi][rot_r]['sign'] = sign



        for stg_iter in range(STG_ITER_NB):
            if (VERBOSE):
                print("### stg_iter={:0d}".format(stg_iter))
                for p in range(PSI):
                    for r in range(R):
                        print("REF PROC : p={:2d} r={:2d} => {:s}".format(p,r,str(proc_l[stg_iter][p][r])))
                print("# read")
                for p in range(PSI):
                    for r in range(R):
                        print("REF READ : p={:2d} r={:2d} => {:s}".format(p,r,str(read_l[stg_iter][p][r])))


            # Process
            v_n_0 = stg_iter*(PSI*R)
            v_pr_0 = pseudo_reverse_order(v_n_0,R,S)
            v_rot_0 = (v_pr_0 + rot)% N

            (rot_r_0,rot_p_0,rot_stg_iter_0) = get_r_psi_stgiter(v_rot_0, R, PSI, STG_ITER_NB, "PR")

            res_l = []
            for p in range(PSI):
                res_l.append([])
                for r in range(R):
                    if (p >= rot_p_0):
                        rot_stg_iter = rot_stg_iter_0
                    else: # p < rot_p_0 # wrap
                        rot_stg_iter = (rot_stg_iter_0 + 1) % STG_ITER_NB
                    res_l[-1].append([r,p,rot_stg_iter])

#            if (VERBOSE):
#                print("# PROC : Read access per R*PSI")
#                for p in range(PSI):
#                    for r in range(R):
#                        print("rot_r={:3d} rot_p={:2d} rot_stg_iter={:4d}".format(r,p,res_l[p][r][2]))

            # reorder
            # rotation + sign
            sign_l = [] # sign to be applied once reordered
            # rotation on PSI block level
            reorder_l = [res_l[(i+rot_p_0) % PSI] for i in range(0, PSI)]
            for p in range(PSI):
                sign_l.append([])
                # rotation among R
                v_n  = p*R + stg_iter*(PSI*R) # Of the first coef of the block
                v_pr = pseudo_reverse_order(v_n,R,S)

                v_rot = (v_pr + rot)
                sign = 0
                if (v_rot >= N and v_rot < 2*N):
                    sign = 1
                v_rot = v_rot % N

                (rot_r,rot_p,rot_stg_iter) = get_r_psi_stgiter(v_rot, R, PSI, STG_ITER_NB, "PR")

                reorder_l[p] = [reorder_l[p][(i+rot_r)%R] for i in range(0, R)]

                v = sign*R + rot_r
                for r in range(R):
                    v_tmp = v + r
                    sign_tmp = 0
                    if (v_tmp >= R and v_tmp < 2*R):
                        sign_tmp = 1
                    sign_l[-1].append(sign_tmp)

            ### Compare
            for p in range(PSI):
                for r in range(R):
                    if (res_l[p][r] != [r,p,read_l[stg_iter][p][r]['rot_stg_iter']]):
                        sys.exit("ERROR> Read : rot={:d} stg_iter={:d} p={:d} r={:d} exp={:d} seen={:d}".format(rot, stg_iter, p,r,ref_l[p][r],read_l[stg_iter][p][r]['rot_stg_iter']))
                    if (reorder_l[p][r] != [proc_l[stg_iter][p][r]['rot_r'],proc_l[stg_iter][p][r]['rot_psi'],proc_l[stg_iter][p][r]['rot_stg_iter']]):
                        sys.exit("ERROR> Reorder : rot={:d} stg_iter={:d} p={:d} r={:d} exp={:s} seen={:s}".format(rot, stg_iter, p,r,str(proc_l[stg_iter][p][r]),reorder_l[p][r]))
                    if (sign_l[p][r] != proc_l[stg_iter][p][r]['sign']):
                        sys.exit("ERROR> Sign: rot={:d} stg_iter={:d} p={:d} r={:d} exp={:d} seen={:d}".format(rot, stg_iter, p,r,proc_l[stg_iter][p][r]['sign'],sign_l[p][r]))
