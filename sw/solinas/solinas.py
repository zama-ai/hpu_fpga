#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# This code checks that the algorithm used in HW for the modular reduction with solinas type modulo
# is working.
# Note that the HW does not support any solinas value.
# This code helps determining if the modulo is supported by the HW or not.
#
# The HW supports Solinas with the following format:
# solinas 2 (SN=2): 2**MOD_W-2**E0+1
# solinas 3 (SN=3): 2**MOD_W-2**E0-2**E1+1
# We also assume that bit [MOD_W-1] of the modulo is not null.
#
# The reduction is composed of the following steps:
# - decompose input v according to MOD_M into SN+2 parts:
#     v[MOD_W-1:0]
#     d : part to be substracted
#     c[0..SN-1] : part to be multiplied by 2**Ei
# - reduce c[0..SN-1], by decomposing each term into c[i][s-1:0] and c[i][max:s]
#   where s = MOD_W-Ei
#   The "wrapping" corresponds to this step.
#   Each term d and c[i][s-1:0] are incremented by Sum(c[i][max]:s). Let's name them "'".
#   /!\ In HW this is done only once. For certain value of Modulo, this needs to be done several times,
#   since max > 2*s-1.
# - Do the sum:
#   solinas 2 : v[MOD_W-1:0]-d'+2**E0*c'[0]
#   solinas 3 : v[MOD_W-1:0]-d'+2**E0*c'[0]+2**E1*c'[1]
# - Do the final correction.
#   /!\ In HW, the correction only supports the following ranges:
#   solinas 2 : ]-2*MOD, 3*MOD[
#   solinas 3 : ]-2*MOD, 4*MOD[
# ==============================================================================================

import sys  # manage errors
import argparse  # parse input argument
from math import log, floor
import random

# ==============================================================================
# Global variables
# ==============================================================================
VERBOSE = False
MAX_POS_CORR_NB=2 # up to +2mod

# ==============================================================================
# Get exponents
# ==============================================================================
def get_exponent(m):
    '''
    Return a list containing the exponents of the Solinas Modulo.
    We assume that the 
    2^m0-2^m1-2^m2...+1
    '''
    l = []
    e = int(log(m,2))
    e = e+1 # because of the substraction of the other terms.
    l.append(e)
    v = (2**e+1) - m
    while (v > 0):
      e = int(log(v,2))
      l.append(e)
      v = v - 2**e
    return l

# ==============================================================================
# Get subpart
# ==============================================================================
def get_sub_part(v, lsb, msb):
   '''
   returns v[msb:lsb], where lsb and msb are the bit positions. (start with 0)
   '''
   nb_bits = msb - lsb + 1
   if (nb_bits < 0):
        sys.exit("ERROR> MSB and LSB seem to have been inversed.")
   mask = (1<<nb_bits)-1
   return (v >> lsb) & mask

# ==============================================================================
# Get position
# ==============================================================================
def get_position_core(e, POS_MAX, stride_l, pos_d):
    '''
    Recursive function to get the position.
    e : current position
    POS_MAX : maximum position (unreached)
    stride_l : list of strides to be considered.
    pos_d : dictionary, with the stride as key.
            Contains the result list which has to be completed.
    '''
    l = []
    for stride in stride_l:
        f = e + stride
        if (f < POS_MAX):
            l.append(f)
            for i in stride_l:
                pos_d[i].append(f)
    for f in l:
        get_position_core(f,POS_MAX,stride_l, pos_d)


def get_position(e_l, POS_MAX):
    '''
    Get the list of lsb positions that are wrapped, when doing the reduction.
    Find positions for a word that is up to e_l[0]*2+1 bits
    e_l : the exponents of the solinas modulo
    '''
    l = []
    e = e_l[0]
    l.append(e)
    
    pos_d = {}
    stride_l = []
    for i in range(1,len(e_l)):
        stride = e - e_l[i]
        stride_l.append(stride)
        pos_d[stride] = [e]
    
    get_position_core(e, POS_MAX, stride_l, pos_d)

    l = pos_d[stride_l[0]]
    for k in pos_d.keys():
      if (l != pos_d[k]):
        sys.exit("ERROR> Position list differs: "+str(l)+" [{:0d}]=".format(k)+str(pos_d[k]))
 
    return pos_d

# ==============================================================================
# Check modulo supported
# ==============================================================================
def check_modulo_supported(MOD, POS_MAX, MOD_W):
    '''
    Check if current modulo is supported with the HW architecture.
    For this the intermediate values (called d and b inthe code)
    must not exceed a given size.
    '''
    if (MOD < 2**(MOD_W-1)):
        print("Modulo bit [MOD_W-1] should be not null!")
        return False

    exp_l = get_exponent(MOD)
    MAX_NEG_CORR_NB = len(exp_l)

    if (MOD <= (MAX_NEG_CORR_NB*(MOD-2**MOD_W))+1):
        print("HW arch number of negative correction won't be enough.")
        return False

    pos_d = get_position(exp_l, POS_MAX)
    stride_l = list(pos_d.keys())
    # Check that b does not overflow
    # The HW is designed to support that b is wrapped once. Therefore, the result of b
    # must be in [0,2**(2*stride)-1]
    # Moreover the HW has also some limitation on the final correction. Check that
    # b wrapped does not overflow.
    MAX_NEG_CORR_NB = len(exp_l)

    d_max = 0
    b_wrap = {}
    b_max = {}
    for s in stride_l:


        b_max[s] = 0
        for p in pos_d[s]:
            # Retreive the number of bits of each contribution.
            b = s
            if (p+s > POS_MAX):
                b = POS_MAX - p
            b_max[s] = b_max[s] + 2**b-1
        # b_max should not be greater than 2**(2*s)-1 to be supported by the HW.
        # Indeed a single wrap stage won't be enough
        if (b_max[s] >= 2**(2*s)):
            print("HW arch does not support this modulo for stride {:0d}".format(s))
            return False
        b_wrap[s] = b_max[s] % 2**s
        if ((b_max[s] >> s) > 0):
          b_wrap[s] = ((b_max[s]>> s)-1) + (2**s-1) # worst case
        d_max = d_max + b_max[s] >> s

    # check b_wrap max value
    for s in stride_l:
        # Approximate computation of the bound
        # We want : (Solinas 3)
        # v[MOD_W-1:0] + 2**e0*A + 2**e1*B < 4*MOD
        # Maximize its value:
        # 2**MOD_W-1 + 2**e0*A + 2**e1*B_max < 4*MOD
        # A < (A*MOD-2**MOD_W+1-2**e1*B_max)/2**e0
        # A < bound
        b_bound = 0
        for ss in stride_l:
            if (ss != s):
                b_bound = b_bound + b_wrap[ss]*2**(MOD_W-ss)
            b_bound = floor((((MAX_NEG_CORR_NB+1)*MOD - 2**MOD_W + 1) - b_bound) / 2**(MOD_W-s))
        if (b_wrap[s] > b_bound):
            print("HW arch MAY not support this modulo for stride {:0d}, wrap result is too big b_max=0x{:0x} -> b_wrap=0x{:0x} > 0x{:0x}".format(s, b_max[s], b_wrap[s], b_bound))
            return False

    # Check that d does not overflow
    s = MOD_W
    for p in pos_d[stride_l[0]]:
        b = MOD_W
        if (p+s > POS_MAX):
            b = POS_MAX - p
        d_max = d_max + 2**b-1

    # d_max should not be greater than 2*MOD to be supported by the HW
    if (d_max >= MAX_POS_CORR_NB*MOD):
        print("HW arch does not support this modulo, since d overflows 0x{:0x}".format(d_max))
        return False


    return True

# ==============================================================================
# compute modulo
# ==============================================================================
def compute_modulo(v, MOD,POS_MAX, e_l, pos_d):
    '''
    Compute the modulo value of v, as the HW would do it.
    '''
    mod_w = e_l[0]
    v_0 = get_sub_part(v,0, mod_w-1)
    d = 0
    v_msb = get_sub_part(v, 2*mod_w, 2*mod_w)
    stride_l = list(pos_d.keys())
    
    for p in pos_d[stride_l[0]]:
        a = mod_w
        if (p+a > POS_MAX):
            a = POS_MAX - p
        d = d + get_sub_part(v, p, p+a-1)
    d = d - v_msb
    if (VERBOSE):
        print("v=0x{:0x} d=0x{:0x}".format(v, d))

    b = {}
    compl = 0 # complement to be added due to the wrap

    MAX_NEG_CORR_NB = len(exp_l)
    b_bound = int(((MAX_NEG_CORR_NB+1)*MOD - 2**MOD_W + 1)/(MAX_NEG_CORR_NB-1))

    for s in stride_l:
        b[s] = 0
        for p in pos_d[s]:
            a = s
            if (p+a > POS_MAX):
                a = POS_MAX - p
            b[s] = b[s] + get_sub_part(v, p, p+a-1)
        b[s] = b[s] - v_msb
        if (VERBOSE):
            print("v=0x{:0x} b[{:0d}]=0x{:0x}".format(v, s, b[s]))

        if (b[s] < 0):
            sys.exit("ERROR> b[{:0d}] is negative! ({:d})".format(s, b[s]))

        try:
            if (int(log(b[s],2)) > 2*s):
                sys.exit("ERROR> Unsupported stride : overflow b[{:0d}]=0x{:0x} v=0x{:0x}! ({:d})".format(s, b[s], v))
        except ValueError:
            if (b[s] != 0):
                raise ValueError

        compl = compl + get_sub_part(b[s], s, 2*s-1)
        b[s] = get_sub_part(b[s], 0, s-1)

    for s in stride_l:
        b[s] = b[s] + compl
        if (VERBOSE):
            print("v=0x{:0x} b'[{:0d}]=0x{:0x}".format(v, s, b[s]))
        
    d = d + compl
    if (VERBOSE):
        print("v=0x{:0x} d'=0x{:0x}".format(v, d))
    if (d >= MAX_POS_CORR_NB*MOD):
        sys.exit("ERROR> Unsupported : d overflow! v=0x{:0x} d=0x{:0x} MAX_POS_CORR_NB*MOD=0x{:0x}".format(v, d, MAX_POS_CORR_NB*MOD))


    r = v_0
    for s in stride_l:
        exp = mod_w - s
        r = r + (2**exp)*b[s]
    r = r - d

    # Correction
    # Check range
    MAX_NEG_CORR_NB = len(e_l)
    if (r <= -MAX_POS_CORR_NB*MOD or r >= (MAX_NEG_CORR_NB+1) * MOD):
        sys.exit("ERROR> Result overflow! range]0x{:0x}, 0x{:0x}[ v=0x{:0x} seen=0x{:0x}".format( -MAX_POS_CORR_NB*MOD, (MAX_NEG_CORR_NB+1) * MOD, v, r))

# Do not do the following codes, since it needs to much adders.
# Keep it for explanation of what follows.
#    # Negative value - positive correction
#    r_corr = r;
#    for c in range(MAX_POS_CORR_NB):
#        if (r_corr < 0):
#            r_corr = r_corr + MOD
#    # Positive
#    for c in range(MAX_NEG_CORR_NB):
#        if (r_corr >= MOD):
#            r_corr = r_corr - MOD

    r_corr = r
    if (r < 0):
      r_corr = r + MAX_POS_CORR_NB*MOD
    elif (r >= 2**MOD_W):
      r_corr = r - (MAX_NEG_CORR_NB-1)*MOD

    # Now r_corr must be in ]-MOD, 2*MOD[
    if (r_corr < 0):
      r_corr = r_corr + MOD
    elif (r_corr >= MOD):
      r_corr = r_corr - MOD

    if not(r_corr >= 0 and r_corr < MOD):
        sys.exit("ERROR> Result after correction overflow! range]0x{:0x}, 0x{:0x}[ v=0x{:0x} r=0x{:0x} r_corr=0x{:0x}".format(
                    -MAX_POS_CORR_NB*MOD, (MAX_POS_CORR_NB+1) * MOD, v, r, r_corr))

    return r_corr

# ==============================================================================
# Main
# ==============================================================================
if __name__ == "__main__":

    # ==============================================================================
    # Parse input arguments
    # ==============================================================================
    parser = argparse.ArgumentParser(
        description="Check the ping-pong structure of the NTT."
    )
    parser.add_argument(
        "-w",
        dest="mod_w",
        type=int,
        help="Modulo width",
        default=32,
    )
    parser.add_argument(
        "-m",
        dest="modulo",
        type=int,
        help="Modulo. Must be of Solinas type (2^m0-2^m1-2^m2...+1).",
        default=2**32-2**17-2**13+1,
    )
    parser.add_argument(
        "-p",
        dest="pos_max",
        type=int,
        help="Operand width. Support up to 2*MOD_W+1",
        default=-1,
    )
    parser.add_argument(
        "-v",
        dest="verbose",
        help="Verbose mode",
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "-d",
        dest="data",
        help="Data to reduce. If not given, compute all the values from 2*POS_MAX-1.",
        type=int,
        default="0",
    )
    parser.add_argument(
        "-f",
        dest="find",
        help="Find the supported solinas for the mod_w given in argument of -f.",
        type=int,
        default=0,
    )
    parser.add_argument(
        "-a",
        dest="reduce_all",
        help="Does the computation for all the values in [2**POS_MAX-1,0]. -a and -d are exclusive.",
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "-b",
        dest="bypass_check",
        help="Bypass the check",
        action="store_true",
        default=False,
    )

    args = parser.parse_args()

    VERBOSE = args.verbose

    # ==============================================================================
    # Find
    # ==============================================================================
    if (args.find > 0):
        MOD_W = args.find
        POS_MAX = args.pos_max
        if (POS_MAX < 0): #Retreive default value
            POS_MAX = 2*MOD_W + 1
        if (POS_MAX > 2*MOD_W + 1):
            sys.exit("ERROR> Unsupported POS_MAX. Must be in [0, {:0d}]".format(2*MOD_W + 1))

        if (VERBOSE):
            print("#######################################################")
            print("Find value Solinas values for:")
            print("MOD_W={:0d}".format(MOD_W))
            print("POS_MAX={:0d}.".format(POS_MAX))
            print("#######################################################")

        print(">>>>> Solinas 2 >>>>>")
        for i in range(1,MOD_W-1):
              MOD=2**MOD_W-2**i+1
              exp_l = get_exponent(MOD)
              pos_d = get_position(exp_l, POS_MAX)
              ok = check_modulo_supported(MOD, POS_MAX, MOD_W)
              if (ok==False):
                  print("UNSUPPORTED: exp_l={:s}".format(str(exp_l)))

        print(">>>>> Solinas 3 >>>>>")
        for i in range(2,MOD_W-1):
            for j in range(1,i-1):
                MOD=2**MOD_W-2**i-2**j+1
                exp_l = get_exponent(MOD)
                pos_d = get_position(exp_l, POS_MAX)
                ok = check_modulo_supported(MOD, POS_MAX, MOD_W)
                if (ok==False):
                    print("UNSUPPORTED: exp_l={:s}".format(str(exp_l)))


    # ==============================================================================
    # Compute
    # ==============================================================================
    if (args.data != 0 and args.reduce_all):
        sys.exit("ERROR> Compute for a single data, and compute for all the values are exclusive.")
    elif (args.data != 0 or args.reduce_all):
        MOD_W = args.mod_w
        POS_MAX = args.pos_max
        if (POS_MAX < 0): #Retreive default value
            POS_MAX = 2*MOD_W + 1
        if (POS_MAX > 2*MOD_W + 1):
            sys.exit("ERROR> Unsupported POS_MAX. Must be in [0, {:0d}]".format(2*MOD_W + 1))

        # Get the modulo
        MOD   = args.modulo
        exp_l = get_exponent(MOD)
        # We only support Solinas 2 and 3 for the moment.
        if not(len(exp_l)==2 or len(exp_l)==3):
            sys.exit("ERROR> Unsupported Solinas modulo. The number of exponents does not correspond to the ones supported : 2 or 3. mod=0x{:0x} ".format(MOD)
                    +str(exp_l))
        pos_d = get_position(exp_l, POS_MAX)

        if (VERBOSE):
            print("#######################################################")
            print("Compute value for :")
            print("MOD_W={:0d}".format(MOD_W))
            print("MOD=0x{0:x}".format(MOD))
            print("exp_l="+str(exp_l))
            print("pos_d="+str(pos_d))
            print("#######################################################")

        ok = check_modulo_supported(MOD, POS_MAX, MOD_W)

        if not(args.bypass_check):
            if not(ok):
                sys.exit("ERROR> HW does not support this modulo 0x{:0x}".format(MOD))
       
        if (args.data == 0):
            msb_max = 2**POS_MAX-1 >> MOD_W
            msb_min = -1

            i = 0;
            for msb in range(msb_max, -1, -1):
                # Reduce the number of computing, in order to test more values.
                # In the computation, 
                for step in range(4):
                    if (step == 0):
                        v = 0
                    elif (step == 1):
                        v = 2**MOD_W-1
                    elif (step == 2):
                        v = random.randrange(1,2**(MOD_W-1))
                    elif (step == 3):
                        v = random.randrange(2**(MOD_W-1),2**MOD_W-1)
                    v = v + msb * 2**MOD_W;
                    r = compute_modulo(v, MOD, POS_MAX, exp_l, pos_d)
                    ref = v % MOD
                    if (r != ref):
                        sys.exit("ERROR> Reduction mismatch: v=0x{:0x} exp=0x{:0x} seen=0x{:0x}".format( v, ref, r))
                    if (i%100000==0):
                        print("0x{:09x}... OK".format(msb))
                    i=i+1
            print("All #{:d} OK".format(i))

        else:
            v = args.data
            if (VERBOSE):
                print("data=0x"+hex(args.data))
            if (v > 2**POS_MAX-1):
                sys.exit("ERROR> Unsupported data 0x{:0x} to reduced. Must be in [1,2**{:0d}-1]".format(v,POS_MAX))
            
            r = compute_modulo(v, MOD, POS_MAX, exp_l, pos_d)
            ref = v % MOD
            if (r != ref):
                sys.exit("ERROR> Reduction mismatch: v=0x{:0x} exp=0x{:0x} seen=0x{:0x}".format( v, ref, r))
            print("OK")
