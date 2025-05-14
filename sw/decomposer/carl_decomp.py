#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import sys  # manage errors
import argparse  # parse input argument
from math import log, pow, floor, ceil
import random

#============================================
# This code describes the decomposition proposed by Carl
#============================================

# ==============================================================================
# Original decompose
# ==============================================================================

def decompose(input,base,level,q):
    if input > (q // 2):
        # If we do not want to decompose negative values then we can alternatively
        # define input = q - input and then negate each of the digits of the output
        # Negation is with respect to the modulus q, so we can replace digit by
        # q - digit
        input -= q
    # If we use the Goldilocks' prime pot = 2^64
    pot = 2 ** ceil(log(q,2))
    smallest_representable = pot // (base ** level)
    # !!! The following "round" operation should be symmetric about zero !!!
    # i.e. round(-x) = -round(x)
    # Here round(-1/2) = -1 = -round(1/2)
    # Rounding towards zero would also be acceptable.
    state = round(input/smallest_representable)
    digits = []
    for i in range(level):
        res = state % base
        state = (state - res) // base
        carry = 0
        if (res > base // 2) or ((res == base // 2) and ((state % base) >= base // 2)):
            carry += 1
            state += carry
            # If we do not want to have negative digits we can instead
            # define res = res + (q - base)
            res -= base
        digits.append(res)
    digits.reverse()
    return digits

#Decomposition with base a power of two
def decompose_pos(input,base,level,q):
    negate_digits = False
    if input > floor(q/2):
        # input remains non-negative
        input = q - input
        negate_digits = True
    pot = 2**ceil(log(q,2))
    smallest_representable = pot//(base**level)
    # This round is deterministic, if half way between two integers
    # always choose to either round up, or always round down
    state = input//smallest_representable
    rnd = (input//(smallest_representable//2))%2
    state = state + rnd

    print("+++++++ input 0x{:08x}".format(input))
    print("+++++++ state 0x{:08x}".format(state))
    digits = []
    for i in range(level):
        res = state % base
        state = (state - res) // base
        carry = 0
        if (res > base // 2) or ((res == base // 2) and ((state % base) >= base // 2)):
            carry += 1
            state += carry
            res -= base
        digits.append(res)
    digits.reverse()
    if negate_digits:
        for i in range(level):
            digits[i] *= -1
    return digits


def jj_decomposer(k,base,level,q):

    b_w = ceil(log(base,2))
    q_w = ceil(log(q,2))
    mask = (1 << b_w) -1
    half_mask = 1 << (b_w-1)
    sign_mask = 1 << b_w
    core_mask = mask >> 1
    trash_bit = (q_w - level * b_w)

    half_q = q // 2

    # Here base should be a power of 2
    if (2**b_w != base):
        sys.exit("ERROR> base should be a power of 2: {:d}".format(b))

    do_final_inverse = 0

    if (k > half_q):
        k = q - k
        do_final_inverse = 1

    # Closest representation
    closest_k = (k >> trash_bit) + ((k >> (trash_bit - 1)) % 2)

    print("------- input 0x{:08x}".format(k))
    print("------- state 0x{:08x} {:0d}".format(closest_k,((k >> (trash_bit - 1)))))

    #print(">> v=0x{:08x} closest=0x{:0x} trash_bit={:0d} do_final_inverse={:0d} q_w={:0d} level={:0d} b_w={:0d}".format(k, closest_k, trash_bit, do_final_inverse, q_w, level, b_w))

    #decompose k in base base
    digit_l = []
    for i in range (0,level):
        digit_l.append(closest_k & mask)
        closest_k = closest_k >> b_w

    carry = 0
    for i in range (0,level):
        digit_l[i] = (digit_l[i] + carry)
        try:
            if (((digit_l[i] & sign_mask)!= 0) # propagate a carry, if current digit is already negative
                or (((digit_l[i] & half_mask)!= 0) and ((digit_l[i] & core_mask)!= 0 or (digit_l[i+1] & half_mask)!= 0))):
                # propagate a carry if the digit is > base/2.
                # In the case = base/2, propagate only if a propagation analysis is done on the next stage.
                carry = 1
                digit_l[i] = digit_l[i] ^ sign_mask # inverse sign
            else:
                # Do not propagate: keep positive value (set sign bit to 0)
                carry = 0
                digit_l[i] = digit_l[i] & mask
        except IndexError: # last digit
            carry = 0

    if (do_final_inverse):
        for i in range (0,level):
            digit_l[i] = ~digit_l[i] + 1
            digit_l[i] = digit_l[i] & (sign_mask|mask)
    digit_l.reverse()
    return digit_l






# ==============================================================================
# Main
# ==============================================================================
if __name__ == "__main__":
    w = 32
    b_w = 8
    lvl_nb = 3

    q = int(2**w-2**(w/2)+1)
    b = 2**b_w

    b_mask = (1 << (b_w+1)) - 1
    core_mask = (1 << b_w) - 1
    sign_mask = 1 << (b_w+1)

    # Check q must be odd
    if (q % 2 != 1):
        sys.exit("ERROR> q must be odd");

    print("w  = {:0d}".format(w))
    print("b_w= {:0d}".format(b_w))
    print("q  = 0x{:08x}".format(q))
    print("q/2= 0x{:08x}".format(floor(q/2)))

    random.seed(5)

    for i in range(10000):
        v = random.randrange(1,q)
        digit_l = decompose_pos(v,b,lvl_nb,q)
        jj_digit_l = jj_decomposer(v,b,lvl_nb,q)

        match_l=[]
        match_all = True
        diff=0

        for l,m in zip(digit_l, jj_digit_l):
            if ((l & b_mask) == m):
                match_l.append(1)
            else:
                match_l.append(0)
                match_all = False
                if ((l & sign_mask) == (m & sign_mask)):
                    diff_tmp = abs((l & b_mask) - m)
                else:
                    diff_tmp = ((l & b_mask) - m) & b_mask
                    if (diff_tmp & sign_mask):
                        diff_tmp = (~diff_tmp + 1) & core_mask
                if (diff_tmp > diff):
                    diff = diff_tmp

        s = ""
        s="v=0x{:08x} lvl=[".format(v)
        for l in digit_l:
            s=s+"0x{:02x},".format(l & b_mask)
        s=s+"] "
        s=s+"jjlvl=[".format(v)
        for l in jj_digit_l:
            s=s+"0x{:02x},".format(l & b_mask)
        s=s+"] "
        s=s+"match="+str(match_l)

        if not(match_all):
            print(s)
            print(">>> Mismatch diff = {:0d}!".format(diff))
            #break
