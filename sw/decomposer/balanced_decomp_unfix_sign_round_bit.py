# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import sys
import math
import random

VERBOSE=0

# Original code from Carl
# Balanced decomposition with unfixed sign and rounding bit
def org_decompose(val,base,level,q):
    if (VERBOSE):
        print(f"INFO> org_decompose({val},{base},{level},{q})")
    y = (val * 2 * base**level) // q
    bit = y % 2
    state = (y + 1) // 2

    if (VERBOSE):
        print(f"INFO> closest_rep={state}")

    if state > base**level/2 or (state == base**level/2 and bit == 1):
        state = state - base**level    # Careful how this is done as it will be negative!
    
    if (VERBOSE):
        print("INFO> state={:d}=0x{:x}".format(state,state))

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
    #digits.reverse()
    return digits

# HW implementation
def hw_decompose(val,b,level,q):
    if (VERBOSE):
        print(f"INFO> hw_decompose({val},{base},{level},{q})")

    b_w = int(math.log(b,2))
    q_w = int(math.log(q,2))
    mask = (1 << b_w)-1
    all_mask = (1 << (b_w*level))-1
    half_mask = 1 << (b_w-1)
    sign_mask = 1 << b_w
    core_mask = mask >> 1
    closest_rep_msb_mask = 1 << (b_w*level - 1)
    closest_rep_lsb_mask = (1 << (b_w*level - 1))-1

    # Here b should be a power of 2
    if (math.pow(2,b_w) != b):
        sys.exit("ERROR> base should be a power of 2: {:d}".format(b))
    # val should be less than q
    if (val > q):
        sys.exit(f"ERROR> val ({val}) is greater than q ({q})");

    closest_rep = val >> (q_w - b_w * level) # keep b_w * level msb
    round_bit = (val >> (q_w - b_w * level - 1)) % 2 # 1rst bit of fractional part
    closest_rep = closest_rep + round_bit

    last_sign = 0
    if (((closest_rep & closest_rep_msb_mask) != 0)
        and (((closest_rep & closest_rep_lsb_mask) != 0) or (round_bit != 0))):
        last_sign = 1


    if (VERBOSE):
        print(f"INFO> closest_rep={closest_rep} round_bit={round_bit} last_sign={last_sign}")

    #decompose k in base b
    v_a = []
    for i in range (0,level):
        v_a.append(closest_rep & mask)
        closest_rep = closest_rep >> b_w

    # Add last element for the last coef
    v_a.append(last_sign * mask)

    carry = 0
    for i in range (0,level):
        v_a[i] = (v_a[i] + carry)
        if (((v_a[i] & sign_mask)!= 0) # propagate a carry, if current digit is already negative
            or (((v_a[i] & half_mask)!= 0) and ((v_a[i] & core_mask)!= 0 or (v_a[i+1] & half_mask)!= 0))):
            # propagate a carry if the digit is > b/2.
            # In the case = b/2, propagate only if a propagation analysis is done on the next stage.
            carry = 1
            v_a[i] = v_a[i] ^ sign_mask # inverse sign
        else:
            # Do not propagate: keep positive value (set sign bit to 0)
            carry = 0
            v_a[i] = v_a[i] & mask

    #remove the additional value
    v_a = v_a[:-1]
    return v_a

####################################################
# Utils
####################################################

def into_int(k_a,b):
    b_w = int(math.log(b,2))
    mask = (1 << b_w) -1
    sign_mask = (1 << b_w)

    r = []
    for ki in k_a:
        if ((ki & sign_mask) != 0):
            v = (~ki + 1) & mask
            r.append(-v)
        else:
            r.append(ki)
    return r

def reconstruction(a,b,n):
    r = 0
    for i in a[::-1]:
      r = r*b + i

    max = int(math.pow(b,n))

    while (r < 0):
        r = r + max
    return r

def weight(a):
    r = 0
    for i in a:
        r = r + i*i

    return r

####################################################
# Verify result
####################################################

for base_w in range (1, 6):
    base = int(math.pow(2,base_w))
    print(">>>> Processing base={:d}".format(base))
    for digit_nb in range(1,6):
        print("++++ Processing digit_nb={:d}".format(digit_nb))
        q = int(2*math.pow(base,digit_nb))
        for k in range (0,q):
            a = org_decompose(k,base,digit_nb,q)
            b = into_int(hw_decompose(k,base,digit_nb,q),base)
            r_a = reconstruction(a, base, digit_nb)
            r_b = reconstruction(b, base, digit_nb)
            w_a = weight(a)
            w_b = weight(b)
            if not((a == b) and (r_a == r_b) and (w_a == w_b)):
                sys.exit("ERROR> base={:d} digit_nb={:d} q={:d} k={:d} : org={:s} hw={:s} rec(org)={:d} rec(hw)={:d} weight(org)={:d} weight(hw)={:d}".format(base,digit_nb,q,k, str(a), str(b), r_a, r_b, w_a, w_b))


