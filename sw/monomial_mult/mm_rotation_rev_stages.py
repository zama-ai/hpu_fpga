#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import sys  # manage errors
import copy
from math import log, pow
import argparse  # parse input argument

# ==============================================================================
# Global variables
# ==============================================================================
VERBOSE = False

# ==============================================================================
# reverse_order
# ==============================================================================
def reverse_order(v, R, S):
    """
    For an index v in 0...R^S, if we decompose it in the R-base:
    v = v_0*R^0 + v_1*R^1 + ... v_(S-1)*R^(S-1)
    where v_j is in 0...R-1.
    The reverse_order of v in base R, for a number of stages S is:
    reverse_order(v) = v_0*R^(S-1) + v_1*R^(S-2) + ... v_(S-1)*R^0

    R is a power of 2.
    """
    r_width = int(log(R, 2))
    if pow(2, r_width) != R:
        sys.exit("ERROR> In reverse_order function, the radix R must be a power of 2")

    mask = (1 << r_width) - 1
    rev = 0
    for i in range(0, S):
        rev = rev * R + (v & mask)
        v = v >> r_width
    return rev

# ==============================================================================
# get_permutation
# ==============================================================================
def get_permutation(S, N, PSI_W, R_W, rot, perm_lvl):
    """
    Build the permutation mask, for a given level, and rotation factor
    """
    mask_bit = perm_lvl+1
    perm_nb  = 2**perm_lvl

    mask   = (1 << mask_bit) - 1
    factor = ((rot % (N)) >> (S - (PSI_W+R_W))) & mask

    if (factor > perm_nb):
        factor = factor % perm_nb
        negate = 1
    else:
        negate = 0

    l = []
    for i in range(perm_nb):
        if (i < factor):
            l.append(1 ^ negate)
        else:
            l.append(0 ^ negate)

    # Reorder the bits in rev order.
    ll = []
    for i in range(perm_nb):
        ll.append(l[reverse_order(i, R, perm_lvl)])

    return ll

# ==============================================================================
# Main
# ==============================================================================
if __name__ == "__main__":
    # default values
    R = 2  # Radix
    PSI = 4  # Number of radix-R blocks used in parallel
    S = 5  # R^S = N the number of coefficients to be processed by the NTT

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
        help="Radix value. Should be 2.",
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

    # Compute the size of the parameters
    R_W = int(log(R, 2))
    PSI_W = int(log(PSI, 2))
    STG_ITER_W = int(log(STG_ITER_NB, 2))

    PERM_LVL_NB = int(log(R*PSI, 2))


    # Build initial lists
    ref_init_l = []
    for i in range(N):
        rev_i = reverse_order(i, R, S)
        ref_init_l.append(rev_i)


    # ram_init_l[stg_iter][psi][r]
    ram_init_l = []
    k = 0
    for stg_iter in range(STG_ITER_NB):
        ram_init_l.append([])
        for p in range(PSI*R):
            ram_init_l[-1].append(ref_init_l[k])
            k = k+1

    ### Compute for every rotation values
    for rot in range(2*N):
        if (VERBOSE):
            print("#==========================================")
            print("# rot={:0d}".format(rot))
            print("#==========================================")


        # Build reference
        ref_l = [(i+rot)%N for i in range(N)]
        ref_l = [ref_l[reverse_order(i, R, S)] for i in range(N)]
        ref_sign_l = [ -1 if (x+rot >= 32) and (x+rot < 64) else 1 for x in range(N)]
        ref_sign_l = [ref_sign_l[reverse_order(i, R, S)] for i in range(N)]

        print(f"REF SIGN : {ref_sign_l}")

        # Read
        result_l = []
        result_sign_l = []

        for stg_iter in range(STG_ITER_NB):
            id_0 = stg_iter * PSI * R
            rev_id_0 = reverse_order(id_0, R, S)
            rot_rev_id_0 = rev_id_0 + rot
            rot_add = reverse_order(rot_rev_id_0,R,S-PSI_W-R_W)

            read_l = copy.deepcopy(ram_init_l[rot_add])

            if (VERBOSE):
                print(f"STG_ITER[{stg_iter}] rot_rev_id_0={rot_rev_id_0} rot_add={rot_add}, {ram_init_l[stg_iter]} => {read_l}")


            # Sign
            sign_l = []
            for i in range(R*PSI):
                idd = id_0 + i
                rev_idd = reverse_order(idd, R, S)
                rot_rev_id = rev_idd + rot

                if (rot_rev_id >= 32 and rot_rev_id < 64):
                    sign_l.append(-1)
                else:
                    sign_l.append(1)


            # Compute permutation vector
            perm_l = []
            for perm_lvl in range(PERM_LVL_NB):
                perm_l.append(get_permutation(S, N, PSI_W, R_W, rot_rev_id_0, perm_lvl))

            if (VERBOSE):
                for perm_lvl in range(PERM_LVL_NB):
                    print(f"PERM LVL={perm_lvl} {perm_l[perm_lvl]}")

            # Do permutation
            for perm_lvl in range(PERM_LVL_NB-1,-1,-1):
                res_l = []
                for i in range(R*PSI):
                    res_l.append(-1)
                inc = PERM_LVL_NB - perm_lvl - 1
                inc = 2**inc
                l = perm_l[perm_lvl]
                for i in range(len(l)):
                    if (l[i] == 0):
                        for j in range(2*inc):
                            res_l[2*inc*i+j] = read_l[2*inc*i+j]
                    else:
                        for j in range(inc):
                            res_l[2*inc*i+j]     = read_l[2*inc*i+j+inc]
                            res_l[2*inc*i+j+inc] = read_l[2*inc*i+j]

                #read_l = copy.deepcopy(res_l)
                read_l = res_l
                if (VERBOSE):
                    print(f"-> after perm{perm_lvl} {read_l}")

            result_l.append(read_l)
            result_sign_l.append(sign_l)

        # Check result
        flat_result_l = [ x for xs in result_l for x in xs ]
        flat_result_sign_l = [x for xs in result_sign_l for x in xs]
        for i,(a,b) in enumerate(zip(ref_l,flat_result_l)):
            if (a!=b):
                print(f"> ERROR: mismatch pos={i} exp={a} seen={b}")
                break
        for i,(a,b) in enumerate(zip(ref_sign_l,flat_result_sign_l)):
            if (a!=b):
                print(f"> ERROR: SIGN mismatch pos={i} exp={a} seen={b}")
                break
