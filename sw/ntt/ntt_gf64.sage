#!/usr/bin/env sage
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# This script is the NTT / INTT model of the HW implementation for goldilocks64
# used as prime.
# The twiddles and phi necessary for the computation are computed.
# A check is also done, to verify the chosen implementation.
#
# The HW needs to do a negacyclic NTT, a polynomial multiplication, followed
# by an INTT to get back to the initial domain.
# Polynomial coefficients are ordered in reverse order at the input.
# The output polynomial should also have the same order.
# ==============================================================================================

import numpy as np
import math
import copy
import sys  # manage errors
import os
import argparse  # parse input argument
import pathlib  # Get current file path
import jinja2
import ntt_gf64_network as ntw

###############################################################################
# Constant
###############################################################################
# We use Goldilocks_64 as prime
Q = 2^64 - 2^32 + 1
# Work in the Z_MODNTT field
ZQ = GF(Q)

# This prime has multiple properties.
# The one used here is that its 64th root of unity is a power of 2.
# Therefore the powers of OMG_64 are HW friendly, since powers of 2.
OMG_64 = 2^3
LOG_OMG_64 = int(math.log(OMG_64))

# The following value is the 2^32th root of unity in Z_MODNTT. It is used to compute the
# phis.
OMG_2_32 = ZQ(16334397945464290598)

# The cyclic NTT of size N uses OMG_N coefficients. Therefore we can build cyclic NTT with friendly
# omegas, up to N=64.
# The negacyclic NTT of size N uses OMG_2N coefficients. Therefore we can build negacyclic NTT with
# friendly omegas, up to N=32.
CYC_MAX_R = 64
NGC_MAX_R = 32
LOG_CYC_MAX_R = int(math.log(CYC_MAX_R,2))
LOG_NGC_MAX_R = int(math.log(NGC_MAX_R,2))

N_MAX=2048 # Max radix handled for the rtl generation
N_MIN=4

###############################################################################
# Global variables
###############################################################################
VERBOSE = False

###############################################################################
# Functions
###############################################################################

#==============================================================================
# power_of_rou
#==============================================================================
def power_of_rou(root, power):
    """
    power_of_rou computes the root-th root of unity in ZQ to the power k.
    """
    if (root > 2^32):
        sys.exit(f"ERROR> Cannot compute the root of unity greater than 2^32: {root}")
    return ZQ(OMG_2_32^(power*2^32/root))

#==============================================================================
# reverse_order
#==============================================================================
def reverse_order(v, S):
    """
    For an index v, decomposed in base 2, with S terms :
    v = v_0*2^0 + v_1*2^1 + ... v_(S-1)*2^(S-1)

    The reverse order is given by:
    rev = v_0*2^(S-1) + v_1*2^(S-2) + ... v_(S-1)*2^0
    """
    if (v >= 2^S):
        sys.exit(f"ERROR> The index:{v} to be reversed is greater than the given size S:{S}")

    v_l = []
    for i in range(S):
        v_l.append((v >> i)%2)

    res = 0
    for b in v_l:
        res = (res << 1) + b

    return res

#==============================================================================
# convert_power_2
#==============================================================================
def convert_power_2(twd_l):
    """
    Input: list of OMG_64 powers
    Output :
      * list of powers of 2
      * list of associated sign
    """

    pow_2_l = []
    sign_l  = []

    for s_l in twd_l:
        pow_2_l.append([])
        sign_l.append([])
        for p in s_l:
            v = p * 3
            sign = 1
            if (v >= 96):
                sign = -1
                v = v - 96
            pow_2_l[-1].append(v)
            sign_l[-1].append(sign)

    return (sign_l, pow_2_l)

#==============================================================================
# ntt_phi
#==============================================================================
def ntt_phi_core(R,cut_start,cut_end,bwd,ngc):
    """
    This function generates the PHI that are used between the radix NTT:
    The PHI are given in 3 lists:
    * phi_l contains the PHI values in ZQ -> always available
    * pow2_l contains the corresponding power of 2 of phi_l when it exists.
      This means, that this list is not valid for ngc, nor radix greater than 64.
    * sign_l contains the sign of the coefficients, when expressed in power of 2.
    The first column contains radix of size 2^cut_start, and the second
    2^cut_end.
    In forward NTT, the PHI are generated after the network,
    for the input of the 2nd column.
    In backward NTT, the PHI are also generated after the network
    for the input of the 2nd column.
    """
    STG = int(log(R,2))

    if (STG != cut_end + cut_start):
        sys.exit(f"ERROR> ntt_phi_core : the cuts ({cut_start}+{cut_end}) must be equal to the size log(R) ({STG})")

    phi_l = []
    pow2_l = []
    sign_l = []
    # Tip : Inverse the 2 for_loop l and a, if we want the output of the first column,
    # instead of the input of the second
    if (bwd):
        for l in range(2^cut_start):
            ll = reverse_order(l,cut_start)
            for a in range(2^cut_end):
                aa = a
                v = power_of_rou(R,-aa*ll)
                # The power of 2 is only used when not ngc
                e = ((R - aa*ll) * 64 // R) # omg_64 power
                s = (-1) ^ (e // 32)
                e = 3 * (e % 32)

                if (ngc):
                    v = ZQ(v*power_of_rou(2*R,-ll)*1/R)
                phi_l.append(v)
                pow2_l.append(e)
                sign_l.append(s)

    else: # fwd
        for l in range(2^cut_start):
            ll = l
            for a in range(2^cut_end):
                aa = reverse_order(a,cut_end)
                v = power_of_rou(R,aa*ll)
                e = 3*(aa*ll * 64 // R) # Power of 2 : Only used in not ngc
                if (ngc):
                    v = ZQ(v*power_of_rou(2*R,aa))
                phi_l.append(v)
                pow2_l.append(e)
                sign_l.append(1)

    return (sign_l, pow2_l, phi_l)

def ntt_phi(cut_l,bwd):
    """
    This function computes the phi for a list of cuts.
    The PHI are given in 3 lists:
    * phi_l contains the PHI values in ZQ -> always available
    * pow2_l contains the corresponding power of 2 of phi_l when it exists.
      This means, that this list is not valid for ngc, nor radix greater than 64.
    * sign_l contains the sign of the coefficients, when expressed in power of 2.
    """
    S = 0
    for c in cut_l:
        S = S + c

    phi_l = []
    pow2_l = []
    sign_l = []
    pow
    for i in range(len(cut_l)-1):
        phi_l.append([])
        pow2_l.append([])
        sign_l.append([])

        # compute remaining stages after current one.
        cut_acc = 0
        for c in cut_l[i+1:]:
            cut_acc = cut_acc + c

        STG = cut_acc + cut_l[i]
        R = 2^STG

        if (bwd):
            (s_l,e_l,p_l) = ntt_phi_core(R,cut_acc,cut_l[i],bwd,i==0)
        else: # fwd
            (s_l, e_l,p_l) = ntt_phi_core(R,cut_l[i],cut_acc,bwd,i==0)

        phi_l[-1] = (N//R) * p_l
        pow2_l[-1]= (N//R) * e_l
        sign_l[-1]= (N//R) * s_l

    if (bwd):
        phi_l.reverse()
        pow2_l.reverse()
        sign_l.reverse()

    return (sign_l,pow2_l,phi_l)

#==============================================================================
# ntt_twd
#==============================================================================
def ntt_twd(R,bwd,ngc):
    """
    Compute omegas for radixR NTT cyclic/negacyclic butterflies.
    The butterfly is in Rev/Nat order for forward NTT.
    The butterfly is in Nat/Rev order for backward NTT.
    The output list : [stage][index].
    """

    omg_64_power_l = []

    for s in range(int(log(R,2))):
        omg_64_power_l.append([])
        gp = 2^(s+1)
        for i in range(R):
            if ((i % gp) < gp//2):
                omg_64_power_l[-1].append(0)
            else:
                if not(ngc):
                    v = (i%(gp//2)) * 64//gp
                else:
                    v = (1+2*(i % (gp//2))) * 64//(2*gp)
                # If bwd use the opposite exponent
                if bwd:
                    v = 64 - v
                omg_64_power_l[-1].append(v)

    # For backward NTT, reverse the stage order
    if bwd:
        omg_64_power_l.reverse()

    return omg_64_power_l

#==============================================================================
# ntt_radix
#==============================================================================
def ntt_radix(R,p,ngc,omg_64_power_l,pow_2_l,sign_l):
    """
    Compute a Rev/Nat NTT on the input polynomial p.
    p coefficients are already ordered in reverse order.
    This function only supports : size(p) = R.
    The used algorithm is the one implemented in HW.
    """

    if (len(p) != R):
        sys.exit(f"ERROR> ntt_radix : polynomial (size={len(p)}) is not of size R ({R})")

    if (ngc and (R > 32)):
        sys.exit(f"ERROR> ngc max size is 32. Here R={R}")

    #omg_64_power_l = ntt_twd(R,False,ngc)
    #(sign_l,pow_2_l) = convert_power_2(omg_64_power_l)

    # Cooley Tukey
    interm_l = copy.deepcopy(p)
    for s in range(int(log(R,2))):
        gp = 2^(s+1)
        if (VERBOSE):
            print(f"> NTT s={s}, gp={gp} : {interm_l}")
        for r in range(R//gp): # for each group of gp elements
            add_l = []
            sub_l = []
            for i in range(gp//2):
                idx1 = r * gp + i
                idx2 = idx1 + gp//2
                if (VERBOSE):
                    print(f">> idx1={idx1}")
                    print(f">> idx2={idx2}")
                a = interm_l[idx1]
                b = ZQ(sign_l[s][idx2] * (interm_l[idx2] << pow_2_l[s][idx2]))
                add_l.append(ZQ(a+b))
                sub_l.append(ZQ(a-b))
            for i,v in enumerate(add_l):
                interm_l[r*gp+i] = v
            for i,v in enumerate(sub_l):
                interm_l[r*gp+gp//2+i] = v

    return interm_l

#==============================================================================
# intt_radix
#==============================================================================
def intt_radix(R,p,ngc,omg_64_power_l,pow_2_l,sign_l):
    """
    Compute a Nat/Rev cyclic INTT on the input polynomial p.
    p coefficients are already ordered in natural order.
    This function only supports : size(p) = R.
    The used algorithm is the one implemented in HW.
    !! The factor 1/N is not taken into account here.
    """

    if (len(p) != R):
        sys.exit(f"ERROR> intt_radix : polynomial (size={len(p)}) is not of size R ({R})")

    if (ngc and (R > 32)):
        sys.exit(f"ERROR> ngc max size is 32. Here R={R}")

    #omg_64_power_l = ntt_twd(R,True,ngc)
    #(sign_l,pow_2_l) = convert_power_2(omg_64_power_l)

    # Gentleman-Sande
    interm_l = copy.deepcopy(p)
    for s in range(int(log(R,2))):
        gp = 2^(int(log(R,2))-s) # Number of elements per group
        if (VERBOSE):
            print(f"> INTT s={s}, gp={gp} : {interm_l}")
        for r in range(R//gp): # for each group of gp elements
            add_l = []
            sub_l = []
            for i in range(gp//2):
                idx1 = r * gp + i
                idx2 = idx1 + gp//2
                if (VERBOSE):
                    print(f">> idx1={idx1}")
                    print(f">> idx2={idx2}")
                a = ZQ(interm_l[idx1] + interm_l[idx2])
                b = ZQ(interm_l[idx1] - interm_l[idx2])
                b = ZQ(sign_l[s][idx2] * (b << pow_2_l[s][idx2]))
                add_l.append(ZQ(a))
                sub_l.append(ZQ(b))
            for i,v in enumerate(add_l):
                interm_l[r*gp+i] = v
            for i,v in enumerate(sub_l):
                interm_l[r*gp+gp//2+i] = v

    return interm_l

#==============================================================================
# ntt
#==============================================================================
def ntt(N,p,cut_l,coef,fwd_omg_64_power_l,fwd_twd_pow_2_l,fwd_twd_sign_l,fwd_phi_sign_l,fwd_phi_pow_2_l,fwd_phi_l):
    """
    Compute a Rev/Nat NTT on the input polynomial p.
    p coefficients are already ordered in reverse order.
    The used algorithm is the one implemented in HW.
    """
    out_l = []

    for i,c in enumerate(cut_l):
        R = 2^c
        bu_nb = N // R
        ngc = (i == 0)
        rdx_col_id = i

        if (VERBOSE):
            print(f"-------NTT  cut#{i} : cut_sz={c}")

        if (i==0):
            in_l = p
        else:
            # need to reorder and multiply by phi.
            # Define a block, as the set containing previous cut, and all the following ones.
            # Define a sub-block, as the set contain the current cut and all the following ones.
            # Distribute within this block, according to the sub-blocks.
            # All first coef of each sub-block, then all 2nd coef, then third etc
            ss = 0
            for cc in cut_l[i:]:
                ss = ss + cc
            s = ss + cut_l[i-1]
            blk_R = 2^s
            sblk_R = 2^ss
            blk_nb = N // blk_R
            sblk_in_blk = blk_R // sblk_R

            if (VERBOSE):
                print(f"-------------> blk {blk_R} : sblk {sblk_R}")

            if (VERBOSE):
                for pos,v in enumerate(out_l[-1]):
                    print("IN_STG[{:0d}] : [{:0d}] 0x{:016x}".format(i,pos,int(v)))

            # network
            #in_l = [out_l[-1][x*blk_R+z*sblk_in_blk+y] for x in range(blk_nb) for y in range (sblk_in_blk) for z in range(sblk_R)]
            try:
                in_l = ntw.network(out_l[-1], cut_l, False, rdx_col_id-1, coef) # call with index of the previous radix col
            except SystemExit as e:
                sys.exit(f"> ERROR: in NTT : {e}")

            if (VERBOSE):
                for pos,v in enumerate(in_l):
                    print("NTW_STG[{:0d}] : [{:0d}] 0x{:016x}".format(i,pos,int(v)))

            #for x in range(blk_nb):
            #    for y in range (sblk_in_blk):
            #        for z in range(sblk_R):
            #            print(x*blk_R+z*sblk_in_blk+y)
            if ((i == 1) or (blk_R > 64)): # Apply ngc phi or if the block needs phi that are not friendly
                in_l = [ZQ(in_l[x] * fwd_phi_l[i-1][x]) for x in range(N)]
                if (VERBOSE):
                    for pos,v in enumerate(in_l):
                        print("PHI_STG[{:0d}] mult : [{:0d}] 0x{:016x}".format(i,pos,int(fwd_phi_l[i-1][pos])))
            else: # friendly phi
                in_l = [ZQ((in_l[x] << fwd_phi_pow_2_l[i-1][x]) * fwd_phi_sign_l[i-1][x]) for x in range(N)]
                for pos,v in enumerate(in_l):
                    print("PHI_STG[{:0d}] shift : [{:0d}] 0x{:04x} *{:0d}".format(i,pos,fwd_phi_pow_2_l[i-1][pos],fwd_phi_sign_l[i-1][pos]))


            if (VERBOSE):
                for pos,v in enumerate(in_l):
                    print("PHI_STG[{:0d}] : [{:0d}] 0x{:016x}".format(i,pos,int(v)))


        # Apply NTT radix
        out_l.append([])
        for j in range(bu_nb):
            l = ntt_radix(R,in_l[j*R:(j+1)*R],ngc,fwd_omg_64_power_l[i],fwd_twd_pow_2_l[i],fwd_twd_sign_l[i])
            out_l[-1] = out_l[-1] + l

    return out_l

#==============================================================================
# intt
#==============================================================================
def intt(N,p,cut_l,coef,bwd_omg_64_power_l,bwd_twd_pow_2_l,bwd_twd_sign_l,bwd_phi_sign_l,bwd_phi_pow_2_l,bwd_phi_l):
    """
    Compute a (pseudo)Nat/rev INTT on the input polynomial p.
    p coefficients are already ordered in pseudo natural order.
    The used algorithm is the one implemented in HW.
    """
    out_l = []

    rev_cut_l=cut_l[::-1]

    for i,c in enumerate(rev_cut_l): # the cut are in the reverse order
        R = 2^c
        bu_nb = N // R
        ngc = (i == (len(cut_l)-1))
        rdx_col_id = (len(cut_l)-1) - i

        if (VERBOSE):
            print(f"-------INTT  {i} : {c}")

        if (i == 0):
            in_l = p
        else:
            # need to reorder and multiply by phi
            # Define a block, as the set containing previous cut, and all the following ones.
            # Define a sub-block, as the set contain the current cut and all the following ones.
            # Distribute within this block, according to the sub-blocks.
            # All first coef of each sub-block, then all 2nd coef, then third etc
            s = 0
            for cc in rev_cut_l[0:i+1]:
                s = s + cc
            blk_R = 2^s
            sblk_R = R
            blk_nb = N // blk_R
            sblk_in_blk = blk_R // sblk_R

            if (VERBOSE):
                print(f"-------------> blk {blk_R} : sblk (c) {R}")

            #network
            #in_l = [out_l[-1][x*blk_R+z*sblk_in_blk+y] for x in range(blk_nb) for y in range (sblk_in_blk) for z in range(sblk_R)]
            try:
                in_l = ntw.network(out_l[-1], cut_l, True, rdx_col_id+1, coef) # call with index of the previous radix col
            except SystemExit as e:
                sys.exit(f"> ERROR: in NTT : {e}")

            #for x in range(blk_nb):
            #    for y in range (sblk_in_blk):
            #        for z in range(sblk_R):
            #            print(x*blk_R+z*sblk_in_blk+y)
            if (ngc or (blk_R > 64)): # Apply ngc phi or if the block needs phi that are not friendly
                in_l = [ZQ(in_l[x] * bwd_phi_l[i-1][x]) for x in range(N)]
            else:   # friendly phi
                in_l = [ZQ((in_l[x] << bwd_phi_pow_2_l[i-1][x]) * bwd_phi_sign_l[i-1][x]) for x in range(N)]

       # Apply INTT radix
        out_l.append([])
        for j in range(bu_nb):
            l = intt_radix(R,in_l[j*R:(j+1)*R],ngc,bwd_omg_64_power_l[i],bwd_twd_pow_2_l[i],bwd_twd_sign_l[i])
            out_l[-1] = out_l[-1] + l

    return out_l

#==============================================================================
# test_convolution
#==============================================================================
def test_convolution(cut_l, coef,
                    fwd_omg_64_power_l, fwd_twd_sign_l, fwd_twd_pow_2_l, fwd_phi_l, fwd_phi_pow_2_l, fwd_phi_sign_l,
                    bwd_omg_64_power_l, bwd_twd_sign_l, bwd_twd_pow_2_l, bwd_phi_l, bwd_phi_pow_2_l, bwd_phi_sign_l):
    """
    Test the NTT/INTT functions.
    Draw 3 random polynomials of size N in Z_Q[X] / X^N+1
    Do the following operation:
    p * q * r

    Return a boolean, indicating if the HW algo matches the straight computing.
    """

    S = 0
    for i in cut_l:
        S = S + i

    N = 2^S

    # Random polynomials
    p = vector(ZQ,[ZZ.random_element(0,Q,"uniform") for _ in range(N)])
    q = vector(ZQ,[ZZ.random_element(0,Q,"uniform") for _ in range(N)])
    r = vector(ZQ,[ZZ.random_element(0,Q,"uniform") for _ in range(N)])
    rev_p = [p[reverse_order(i, S)] for i in range(N)]
    rev_q = [q[reverse_order(i, S)] for i in range(N)]
    rev_r = [r[reverse_order(i, S)] for i in range(N)]


    if (VERBOSE):
        print(f"p={p}")
        print(f"rev_p={rev_p}")
        print(f"q={q}")
        print(f"rev_q={rev_q}")

    # Computing the witness convolution
    Rn = PolynomialRing(ZQ, 'x').quotient(x^(N) + 1, 'X')
    witness = Rn(p.list()) * Rn(q.list()) * Rn(r.list())

    #== Computing polymul with HW algo
    # NTT
    ntt_p_l = ntt(N,rev_p,cut_l,coef,fwd_omg_64_power_l,fwd_twd_pow_2_l,fwd_twd_sign_l,fwd_phi_sign_l,fwd_phi_pow_2_l,fwd_phi_l)
    ntt_q_l = ntt(N,rev_q,cut_l,coef,fwd_omg_64_power_l,fwd_twd_pow_2_l,fwd_twd_sign_l,fwd_phi_sign_l,fwd_phi_pow_2_l,fwd_phi_l)
    ntt_r_l = ntt(N,rev_r,cut_l,coef,fwd_omg_64_power_l,fwd_twd_pow_2_l,fwd_twd_sign_l,fwd_phi_sign_l,fwd_phi_pow_2_l,fwd_phi_l)

    # point-wise mult p*q
    ntt_pq = [ZQ(ntt_p_l[-1][i] * ntt_q_l[-1][i]) for i in range(N)]
    # point-wise mult (p*q)*r
    ntt_pqr = [ZQ(ntt_pq[i] * ntt_r_l[-1][i]) for i in range(N)]

    intt_pqr_l = intt(N,ntt_pqr,cut_l,coef,bwd_omg_64_power_l,bwd_twd_pow_2_l,bwd_twd_sign_l,bwd_phi_sign_l,bwd_phi_pow_2_l,bwd_phi_l)

    pqr = [intt_pqr_l[-1][reverse_order(i,S)] for i in range(N)]

    test = (list(witness) == list(pqr))

    if (VERBOSE):
        print(f"ntt_p={ntt_p_l}")
        print(f"ntt_p={ntt_q_l}")
        print(f"ntt_pq={ntt_pq}")
        print(f"ntt_pqr={ntt_pq}")
        print(f"intt_pqr={intt_pqr_l}")
        print(f"pqr={pqr}")
        print(f"witness={witness}")

    return test

#==============================================================================
# debug_rtl
#==============================================================================
def debug_rtl(cut_l, coef,
                    fwd_omg_64_power_l, fwd_twd_sign_l, fwd_twd_pow_2_l, fwd_phi_l, fwd_phi_pow_2_l, fwd_phi_sign_l,
                    bwd_omg_64_power_l, bwd_twd_sign_l, bwd_twd_pow_2_l, bwd_phi_l, bwd_phi_pow_2_l, bwd_phi_sign_l):
    """
    Generate reference stimuli for RTL
    """

    S = 0
    for i in cut_l:
        S = S + i

    N = 2^S

    # Polynomial with known values
    p =  [ZQ(i) for i in range(N)]

    ntt_p_l = ntt(N,p,cut_l,coef,fwd_omg_64_power_l,fwd_twd_pow_2_l,fwd_twd_sign_l,fwd_phi_sign_l,fwd_phi_pow_2_l,fwd_phi_l)
    intt_p_l = intt(N,ntt_p_l[-1],cut_l,coef,bwd_omg_64_power_l,bwd_twd_pow_2_l,bwd_twd_sign_l,bwd_phi_sign_l,bwd_phi_pow_2_l,bwd_phi_l)

    print("# NTT")
    for stg,ntt_l in enumerate(ntt_p_l):
      print(f"# RDX_STG={stg}")
      for i,v in enumerate(ntt_l):
        print("[{:0d}] 0x{:016x}".format(i,int(v)))

    print("# INTT")
    for stg,ntt_l in enumerate(intt_p_l):
      print(f"# RDX_STG={stg}")
      for i,v in enumerate(ntt_l):
        print("[{:0d}] 0x{:016x}".format(i,int(v)))

#==============================================================================
# gen_all_phi
#==============================================================================
def gen_all_phi_core(n_l,bwd,with_div):
    """
    Generate a string containing all the powers of w2n_l.
    RTL array with [w2N power (0 to 2*n_l-1)][63:0]
    """

    factor = ZQ(1)
    if (bwd and with_div):
      factor = ZQ(1/n_l)

    phi_l=[]
    for p in range(0,2*n_l): # power of w2N
        if (bwd):
            w = power_of_rou(2*n_l,-p) * factor
        else:
            w = power_of_rou(2*n_l,p)
        phi_l.append(w)

    pretty_p = ""
    for i,w in enumerate(phi_l):
        pretty_w = "64'h{:016x}".format(int(w))
        if (i != 0):
            pretty_w = pretty_w + ","
        if (i%4 == 0):
            pretty_w = pretty_w + "\n"
        pretty_p = pretty_w + pretty_p
    pretty_p = "{\n"+pretty_p+"}"
    
    return pretty_p



def gen_all_phi(cur_workdir):
    """
    Generate a string containing all the phis that are needed for the RTL.
    RTL array with [wN power (0 to N_MAX-1)][w2N power (0 to N_MAX/2-1)][63:0]
    Note that cyclic are obtained with w2N power = 0
    """
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)
    template        = template_env.get_template("ntt_core_gf64_phi_phi_pkg.sv.j2")

    S_MAX = int(log(N_MAX,2))
    S_MIN = int(log(N_MIN,2))

    fwd_l = []
    bwd_l = []
    bwd_wdiv_l = []
    for i in range(S_MIN,S_MAX+1):
        n_l = 2^i
        fwd_l.append(gen_all_phi_core(n_l,False,False))
        bwd_l.append(gen_all_phi_core(n_l,True,False))
        bwd_wdiv_l.append(gen_all_phi_core(n_l,True,True))

    config = {"NTT_GF64_FWD_N4_PHI_L"    : fwd_l[0],
              "NTT_GF64_FWD_N8_PHI_L"    : fwd_l[1],
              "NTT_GF64_FWD_N16_PHI_L"   : fwd_l[2],
              "NTT_GF64_FWD_N32_PHI_L"   : fwd_l[3],
              "NTT_GF64_FWD_N64_PHI_L"   : fwd_l[4],
              "NTT_GF64_FWD_N128_PHI_L"  : fwd_l[5],
              "NTT_GF64_FWD_N256_PHI_L"  : fwd_l[6],
              "NTT_GF64_FWD_N512_PHI_L"  : fwd_l[7],
              "NTT_GF64_FWD_N1024_PHI_L" : fwd_l[8],
              "NTT_GF64_FWD_N2048_PHI_L" : fwd_l[9],
              "NTT_GF64_BWD_N4_PHI_L"    : bwd_l[0],
              "NTT_GF64_BWD_N8_PHI_L"    : bwd_l[1],
              "NTT_GF64_BWD_N16_PHI_L"   : bwd_l[2],
              "NTT_GF64_BWD_N32_PHI_L"   : bwd_l[3],
              "NTT_GF64_BWD_N64_PHI_L"   : bwd_l[4],
              "NTT_GF64_BWD_N128_PHI_L"  : bwd_l[5],
              "NTT_GF64_BWD_N256_PHI_L"  : bwd_l[6],
              "NTT_GF64_BWD_N512_PHI_L"  : bwd_l[7],
              "NTT_GF64_BWD_N1024_PHI_L" : bwd_l[8],
              "NTT_GF64_BWD_N2048_PHI_L" : bwd_l[9],
              "NTT_GF64_BWD_WDIV_N4_PHI_L"    : bwd_wdiv_l[0],
              "NTT_GF64_BWD_WDIV_N8_PHI_L"    : bwd_wdiv_l[1],
              "NTT_GF64_BWD_WDIV_N16_PHI_L"   : bwd_wdiv_l[2],
              "NTT_GF64_BWD_WDIV_N32_PHI_L"   : bwd_wdiv_l[3],
              "NTT_GF64_BWD_WDIV_N64_PHI_L"   : bwd_wdiv_l[4],
              "NTT_GF64_BWD_WDIV_N128_PHI_L"  : bwd_wdiv_l[5],
              "NTT_GF64_BWD_WDIV_N256_PHI_L"  : bwd_wdiv_l[6],
              "NTT_GF64_BWD_WDIV_N512_PHI_L"  : bwd_wdiv_l[7],
              "NTT_GF64_BWD_WDIV_N1024_PHI_L" : bwd_wdiv_l[8],
              "NTT_GF64_BWD_WDIV_N2048_PHI_L" : bwd_wdiv_l[9]
              }

    with open(os.path.join(cur_workdir, "ntt_core_gf64_phi_phi_pkg.sv"), "w") as fp:
        fp.write(template.render(config))

#==============================================================================
# gen_phi_rom
#==============================================================================
def gen_phi_rom (cut_l, COEF, fwd_phi_l, bwd_phi_l, cur_workdir):
    """
    Create ROM files for ngc phi fwd NTT, and bwd NTT.
    Files are named twd_phi_<fwd/bwd>_N<N>_<psi>
    """

    s = 0
    for j in (cut_l[0:]):
        s = s + j

    N_L = 2^s

    if (N_L > NGC_MAX_R):

        iter_nb = N_L // COEF

        #---------------
        # fwd
        #---------------
        phi_l = fwd_phi_l[0]

        for psi in range(COEF//2):
            # reorder
            l = [phi_l[i*COEF+psi*2+r] for i in range(iter_nb) for r in range(2)]

            # print
            with open(os.path.join(cur_workdir, f"twd_phi_fwd_N{N_L}_{psi}.mem"),"w") as f:
                for phi in l:
                    f.write("{:016x}\n".format(int(phi)))

        #---------------
        # bwd
        #---------------
        phi_l = bwd_phi_l[-1]

        for psi in range(COEF//2):
            # reorder
            l = [phi_l[i*COEF+psi*2+r] for i in range(iter_nb) for r in range(2)]

            # print
            with open(os.path.join(cur_workdir, f"twd_phi_bwd_N{N_L}_{psi}.mem"),"w") as f:
                for phi in l:
                    f.write("{:016x}\n".format(int(phi)))

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
        "-J",
        dest="cut_l",
        type=int,
        action='append',
        help="NTT cut pattern. Given from input to output. The first one is the ngc",
        default=[],
    )
    parser.add_argument(
        "-t",
        dest="test_nb",
        type=int,
        help="Number of convolution tests. Set to 0 for none. Default 1",
        default=0,
    )
    parser.add_argument(
        "-p",
        dest="print",
        action='store_true',
        help="Print twiddles and phis",
        default=False,
    )
    parser.add_argument(
        "-gen_phi",
        dest="gen_phi",
        action='store_true',
        help="Print RTL package containing phis, from N=4 to N=2048",
        default=False,
    )
    parser.add_argument(
        "-gen_rom",
        dest="gen_rom",
        action='store_true',
        help="Print the ROMs content for ngc. The number of coefficients that are processed in parallel must be given. Should be a power of 2, and less than N.",
        default=False,
    )
    parser.add_argument(
        "-coef",
        dest="coef",
        type=int,
        help="The number of coefficients that are processed in parallel must be given. Should be a power of 2, and less than N.",
        default=2,
    )
    parser.add_argument(
        "-dbg",
        dest="dbg",
        action='store_true',
        help="Generate stimuli for RTL debug",
        default=False,
    )
    parser.add_argument(
        "-dir",
        dest="dir",
        type=str,
        help="Generated file directory. Default : current directory",
        default=os.getcwd(),
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
    test_nb = args.test_nb
    do_print = args.print
    do_gen_phi = args.gen_phi
    do_gen_rom = args.gen_rom
    dbg = args.dbg
    workdir = os.path.abspath(args.dir)
    VERBOSE = args.verbose

    S = int(log(N,2))

# ==============================================================================
# Check input arguments
# ==============================================================================
    if (2^S != N):
        sys.exit(f"ERROR> N ({N}) Should be a power of 2")

    if (len(cut_l) == 0):
        cut_l.append(S)

    total_s = 0
    for i in cut_l:
        total_s = total_s + i

    if (total_s != S):
        sys.exit(f"ERROR> The given cut pattern {cut_l} does not fit N ({N})")

    if (COEF != 0 and 2^(int(log(COEF,2))) != COEF):
        sys.exit(f"ERROR> COEF ({COEF}) should be a power of 2")

    if (COEF != 0 and COEF < 2):
        sys.exit(f"ERROR> COEF ({COEF}) should be greater or equal to 2")

# ==============================================================================
# Generate twiddles and Phi
# ==============================================================================
    # In processing stage order.
    fwd_omg_64_power_l = []
    fwd_twd_sign_l     = []
    fwd_twd_pow_2_l    = []

    bwd_omg_64_power_l = []
    bwd_twd_sign_l     = []
    bwd_twd_pow_2_l    = []

    for i,c in enumerate(cut_l):
        omg_64_power_l = ntt_twd(2^c,False,i==0)
        (sign_l,pow_2_l) = convert_power_2(omg_64_power_l)

        fwd_omg_64_power_l.append(omg_64_power_l)
        fwd_twd_sign_l.append(sign_l)
        fwd_twd_pow_2_l.append(pow_2_l)

        omg_64_power_l = ntt_twd(2^c,True,i==0)
        (sign_l,pow_2_l) = convert_power_2(omg_64_power_l)

        bwd_omg_64_power_l.append(omg_64_power_l)
        bwd_twd_sign_l.append(sign_l)
        bwd_twd_pow_2_l.append(pow_2_l)

    bwd_omg_64_power_l.reverse()
    bwd_twd_sign_l.reverse()
    bwd_twd_pow_2_l.reverse()

    (fwd_phi_sign_l,fwd_phi_pow_2_l,fwd_phi_l) = ntt_phi(cut_l,False)
    (bwd_phi_sign_l,bwd_phi_pow_2_l,bwd_phi_l) = ntt_phi(cut_l,True)

# ==============================================================================
# Convolution test
# ==============================================================================
    for i in range(test_nb):
        test = test_convolution(cut_l, COEF,
                                fwd_omg_64_power_l, fwd_twd_sign_l, fwd_twd_pow_2_l, fwd_phi_l, fwd_phi_pow_2_l, fwd_phi_sign_l,
                                bwd_omg_64_power_l, bwd_twd_sign_l, bwd_twd_pow_2_l, bwd_phi_l, bwd_phi_pow_2_l, bwd_phi_sign_l)
        if (test == False):
            sys.exit(f"ERROR > Test mismatch at iteration {i}")

# ==============================================================================
# Generate lists for RTL
# ==============================================================================
    if (do_gen_rom or do_gen_phi):
        #-------------------------------
        # Gen phi list
        #-------------------------------
        if (do_gen_phi):
            gen_all_phi(workdir)

        #-------------------------------
        # Gen ROM input
        #-------------------------------
        if (do_gen_rom):
            gen_phi_rom (cut_l, COEF, fwd_phi_l, bwd_phi_l, workdir)

# ==============================================================================
# Generate RTL debug stimuli
# ==============================================================================
    if (dbg):
        debug_rtl(cut_l, COEF,
                  fwd_omg_64_power_l, fwd_twd_sign_l, fwd_twd_pow_2_l, fwd_phi_l, fwd_phi_pow_2_l, fwd_phi_sign_l,
                  bwd_omg_64_power_l, bwd_twd_sign_l, bwd_twd_pow_2_l, bwd_phi_l, bwd_phi_pow_2_l, bwd_phi_sign_l)

# ==============================================================================
# Print
# ==============================================================================
    if (do_print):
        print("#==============================================================================")
        print("# NTT")
        print("#==============================================================================")
        for i,c in enumerate(cut_l):
            print("#------------------------------------------------------------------------------")
            if (i==0):
                print(f"# NTT ngc R={2^c}")
            else:
                print(f"# NTT cyc R={2^c}")
            print("#------------------------------------------------------------------------------")
            omg_64_power_l = fwd_omg_64_power_l[i]
            pow_2_l = fwd_twd_pow_2_l[i]
            sign_l = fwd_twd_sign_l[i]
            for s, o_l in enumerate(omg_64_power_l):
                print(f"# Stage {s}")
                for j,p_l in enumerate(o_l):
                    print("omg_pw={:02d}, pow2={:02d}, sign={:01d}".format(p_l, pow_2_l[s][j], sign_l[s][j]))


        print("#------------------------------------------------------------------------------")
        print("# FWD Phi")
        print("#------------------------------------------------------------------------------")
        for j in range(len(fwd_phi_l)):
            cut_acc = 0
            for c in cut_l[j+1:]:
                cut_acc = cut_acc + c
            R = cut_acc + cut_l[j]

            if (j==0):
                print("# ncg phi")
            else:# compute remaining stages after current one.
                print(f"# phi R={R} -> {cut_l[j]} : {cut_acc}")

            for k,p in enumerate(zip(fwd_phi_l[j],fwd_phi_pow_2_l[j],fwd_phi_sign_l[j])):
                if (k < 2^R):
                    if (j > 0): # not ngc
                        print("phi=0x{:016x}, pow2={:03d}, sign={:0d}".format(int(p[0]), p[1], p[2]))
                    else:
                        print("phi=0x{:016x}".format(int(p[0])))


        print("#==============================================================================")
        print("# INTT")
        print("#==============================================================================")
        for i,c in enumerate(cut_l[::-1]): # reverse cut_l
            print("#------------------------------------------------------------------------------")
            if (i==(len(cut_l)-1)):
                print(f"# INTT ngc R={2^c}")
            else:
                print(f"# INTT cyc R={2^c}")
            print("#------------------------------------------------------------------------------")
            omg_64_power_l = bwd_omg_64_power_l[i]
            pow_2_l = bwd_twd_pow_2_l[i]
            sign_l = bwd_twd_sign_l[i]
            for s, o_l in enumerate(omg_64_power_l):
                print(f"# Stage {s}")
                for j,p_l in enumerate(o_l):
                    print("omg_pw={:02d}, pow2={:02d}, sign={:01d}".format(p_l, pow_2_l[s][j], sign_l[s][j]))

        print("#------------------------------------------------------------------------------")
        print("# BWD Phi")
        print("#------------------------------------------------------------------------------")
        rev_cut_l = cut_l[::-1]
        for j in range(len(bwd_phi_l)):
            cut_acc = 0
            for c in rev_cut_l[j+1:-1]: # do not count last one, which is ngc
                cut_acc = cut_acc + c
            R = cut_acc + rev_cut_l[j]

            if (j==(len(bwd_phi_l)-1)):
                print("# ncg phi")
                R = N
            else:# compute remaining stages after current one.
                print(f"# phi R={R} -> {rev_cut_l[j]} : {cut_acc}")

            for k,p in enumerate(zip(bwd_phi_l[j],bwd_phi_pow_2_l[j],bwd_phi_sign_l[j])):
                if (k < 2^R):
                    if (j < (len(bwd_phi_l)-1)): # not ngc
                        print("phi=0x{:016x}, pow2={:03d}, sign={:01d}".format(int(p[0]), p[1], p[2]))
                    else:
                        print("phi=0x{:016x}".format(int(p[0])))
