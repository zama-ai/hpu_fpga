#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  This script checks the algorithm used for the rotation by and sample extract, on
#  data stored in reverse order.
# ==============================================================================================

import os       # OS functions
import sys
import argparse # parse input argument
from math import log

# ==============================================================================
# reverse_order
# ==============================================================================
def reverse_order_core(v_l, R, S, step):
    """
    For an input v with v_i as digit in R base,
    the reverse of v at step "step" is :
    digits 0 .. step-1:
      rev_v[step-1:0] = reverse_order(v[step-1:0],R,step,0)
    digit step .. S-1
      rev_v[S-1:step] = reverse_order(v[S-1:step],R,S-step,0)

    step = 0 <=> reverse
    """
    res_l=[]
    for i in range(S):
        res_l.append(0)

    if (step == 0):
        res_l = [v_l[S-1-i] for i in range(S)]
    else:
        res_l[0:step] = reverse_order_core(v_l[0:step], R, step, 0)
        res_l[step:S] = reverse_order_core(v_l[step:S], R, S-step, 0)

    return res_l


def reverse_order(v, R, S, step=0):
    """
    For an input v with v_i as digit in R base,
    the reverse of v at step "step" is :
    digits 0 .. step-1:
      rev_v[step-1:0] = reverse_order(v[step-1:0],R,step,0)
    digit step .. S-1
      rev_v[S-1:step] = reverse_order(v[S-1:step],R,S-step,0)

    step = 0 <=> reverse
    """
    r_width = int(log(R, 2))
    if pow(2, r_width) != R:
        sys.exit("ERROR> Radix R must be a power of 2")

    r_mask = (1 << r_width) - 1

    # put v digits into a list
    v_l = []
    res_l=[]
    tmp = v
    for i in range(S):
        v_l.append(tmp & r_mask)
        res_l.append(0)
        tmp = tmp >> r_width

    res_l = reverse_order_core(v_l,R,S,step)

    res = 0
    for i in range(S):
        res = (res << r_width) + res_l[S-1-i]

    return res

# ==============================================================================
# inv_sign
# ==============================================================================
def inv_sign (v, inv=1):
    """
    v is a couple (sign, value).
    The inversion concerns the sign.
    """
    return (inv^v[0],v[1])

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
if __name__ == '__main__':
#=====================================================
# Default
#=====================================================
    R = 2
    PSI = 8
    S = 7

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Check mmacc sample extract.")
    parser.add_argument('-R',  dest='radix',   type=int, help="Radix. (Only value 2 has been verified)",
                               default=R)
    parser.add_argument('-P',  dest='psi',     type=int, help="PSI.",
                               default=PSI)
    parser.add_argument('-S',  dest='stage',   type=int, help="Number of NTT stages.",
                               default=S)
    parser.add_argument("-v",  dest="verbose", help="Run in verbose mode.", action="store_true",
                               default=False)


    args = parser.parse_args()

    VERBOSE = args.verbose
    R = args.radix
    PSI = args.psi
    S = args.stage

    # Deduced parameters
    N = R ** S
    STG_ITER_NB = N // (R*PSI)
    C_W = int(log(R*PSI,R))
    R_W = int(log(R, 2))
    PSI_W = int(log(PSI, 2))

#=====================================================
# Input
#=====================================================
    in_nat = []
    in_rev = []
    ram_rev = []

    for i in range(N):
        in_nat.append((0,i));
        in_rev.append((0,reverse_order(i, R, S)))

    for i in range(STG_ITER_NB):
        ram_rev.append(in_rev[i*R*PSI:(i+1)*R*PSI])

#=====================================================
# Check for each rotation factor value
#=====================================================
    if (VERBOSE):
        print(">>> R={:0d} PSI={:0d} S={:0d}".format(R,PSI,S))

    for rot_factor in range(0,2*N):
    #for rot_factor in [12]:
        if (VERBOSE):
            print(">>> ==================================")
            print(">>> ROT = {:0d}".format(rot_factor))
            print(">>> ==================================")

    #-----------------------------------------------------
    # Build reference
    #-----------------------------------------------------
        ref_rot = []
        # Rotation
        for i in range(N):
            id = i+rot_factor
            inv = 0
            if (id >= N and id < 2*N):
                inv = 1
            ref_rot.append(inv_sign(in_nat[id % N],inv))
        ref_sxt = [ref_rot[0]] + [inv_sign(ref_rot[i]) for i in range(N-1,0,-1)]
        ref_rev = [ref_sxt[reverse_order(i, R, S)] for i in range(N)]

    #-----------------------------------------------------
    # Build compute
    #-----------------------------------------------------
        # address in RAM where to read
        add_l = []
        # Result
        res_l = []
        for stg in range (STG_ITER_NB):
            dec = reverse_order(stg*R*PSI,R,S) # rev_id_0
            id_0 = (rot_factor - dec) % N
            id_0_rev = reverse_order(id_0,R,S)
            add = id_0_rev // (R*PSI)
            add_l.append(add)
            if (VERBOSE):
              print("STG_ITER {:0d}: Add = 0x{:0x}".format(stg,add))

            # indices available at this address
            id_l = []
            for j in range(R*PSI):
                id = reverse_order(add * (R*PSI) + j, R,S)
                id_l.append(id)

                # Check
                #if (ram_rev[add][j][1] != id):
                #    sys.exit("> ERROR: Mismatch : @={:d} seen={:s} exp={:s}".format(add, str(id_l), str(ram_rev[add])))

            # Sign
            sign_l=[]
            sign_0 = 0
            if (rot_factor >= N and rot_factor < 2*N):
                sign_0 = sign_0 ^ 1
            for c in id_l:
                if c > (rot_factor % N):
                    sign = sign_0 ^ 1
                    sign_l.append(sign)
                else:
                    sign_l.append(sign_0)


            # Permutation
            # There are $clogR(R*PSI)=C_W levels of permutation.
            # Each permutation is a permutation of R elements.
            # At level <i> there are R^<i> permutations (i starts at 0).
            # /!\ tested for R=2 only
            perm_l = []
            id_l = [id_0]
            for p in range(C_W):
                #print(id_l)
                l = []
                i_l = []
                for j,c in enumerate(id_l):
                    #if (VERBOSE):
                    #    print("[{:d}] C : {:d}".format(j,c))
                    c_rev = reverse_order(c,R,S)
                    perm = (c_rev >> (C_W - 1 - p)) & 1
                    l.append(perm)
                    #new_id = (c - (N//((R*PSI)//R**p))) % N
                    new_id2 = (c - ((R**p)<<(S-C_W))) % N

                    i_l.append(c)
                    i_l.append(new_id2)
                id_l = i_l
                perm_l.append(l)

            # Simpler way to compute permutation lists
            perm_2_l = []
            for p in range(C_W):
                perm_depth = 2**p
                rot_f = id_0 + (perm_depth + 1)*STG_ITER_NB
                #print(f"perm_lvl={p} perm_depth={perm_depth} rot={rot_factor} rot_f={rot_f}")
                perm_2_l.append(get_permutation(S, N, PSI_W, R_W, rot_f, p))
                if (VERBOSE):
                  print(f"PERM_LVL {p} id_0={id_0} rot_f={rot_f} {perm_2_l[-1]}")


            for p in range(C_W):
                for i,(a,b) in enumerate(zip(perm_l[p],perm_2_l[p])):
                    if (a!=b):
                        print(f"MISMATCH perm_lvl={p} pos={i} {perm_l[p]} {perm_2_l[p]}")
                        sys.exit()


            # Build data
            d_l = []
            for j in range(R*PSI):
                d = inv_sign(ram_rev[add][j], sign_l[j])
                d_l.append(d)
            if (VERBOSE):
                #print(d_l)
                print("PERM : {:s}".format(str(perm_l)))

            elt_nb = R*PSI
            for p_l in perm_l:
                l = []
                for lvl, p in enumerate(p_l):
                    if (p == 1):
                        l.extend(d_l[lvl*elt_nb+elt_nb//R:(lvl+1)*elt_nb])
                        l.extend(d_l[lvl*elt_nb:lvl*elt_nb+elt_nb//R])
                    else:
                        l.extend(d_l[lvl*elt_nb:lvl*elt_nb+elt_nb//R])
                        l.extend(d_l[lvl*elt_nb+elt_nb//R:(lvl+1)*elt_nb])
                d_l = l
                elt_nb = elt_nb // R # For next iteration

            res_l.extend(d_l)


    #-----------------------------------------------------
    # Check
    #-----------------------------------------------------
        if (VERBOSE):
            print(">>> ROT = {:0d}".format(rot_factor))
            print("   --REF--")
            print(ref_sxt)
            for i in range(STG_ITER_NB):
                a = reverse_order(ref_rev[i*R*PSI][1],R,S) // (R*PSI)
                print("@{:2} {:s}".format(a,str(ref_rev[i*R*PSI:(i+1)*R*PSI])))
                if (a != add_l[i]):
                    sys.exit("> MISMATCH : seen={:2d} exp={:2}".format(a,add_l[i]))

        # Check address
        for i in range(STG_ITER_NB):
                a = reverse_order(ref_rev[i*R*PSI][1],R,S) // (R*PSI)
                if (a != add_l[i]):
                    sys.exit("> MISMATCH ADD : ROT={:d} seen={:2d} exp={:2}".format(rot_factor,a,add_l[i]))

        # Check sign
        for c in ref_rev:
            sign = 0
            if c[1] > (rot_factor % N):
                sign = 1

            if (rot_factor >= N and rot_factor < 2*N):
                sign = sign ^ 1
            if (sign != c[0]):
                sys.exit("> MISMATCH SIGN: ROT={:d} seen={:2d} exp={:2} {:s}".format(rot_factor,c[0],sign, str(c)))

        # Check result
        for i,c in enumerate(ref_rev):
            if (c != res_l[i]):
                sys.exit("> MISMATCH DATA: ROT={:d} seen={:s} exp={:s}.\n REF={:s}\n RES={:s}".format(rot_factor,str(res_l[i]),str(c),str(ref_rev),str(res_l)))

