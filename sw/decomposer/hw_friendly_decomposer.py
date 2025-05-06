# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import sys
import math
import random

def org_decomposer(k,b,n):
    max = int(math.pow(b,n))
    max_half_f = math.floor(max/2)
    max_half_c = math.ceil(max/2)
    half_f = math.floor(b/2)
    half_c = math.ceil(b/2)
    if (k >= max):
        sys.exit("ERROR> k is greater than b^n : k={:d}, b={:d}, n={:d}".format(k,b,n))
    
    if (k > max_half_f) or ((k == max_half_c) and (random.randrange(2) == 0)):
        k = k - max

    r = [] 
    while (k != 0):
        ki = k % b
        k = int((k-ki)/b)
        if (ki > half_f or ((ki == half_c) and ((k % b) >= half_f))):
            ki = ki - b
            k = k + 1
        r.append(ki)
    
    for i in range(len(r),n):
        r.append(0)
    return r

# H: b is a power of 2
def jj_decomposer(k,b,n):
    max = math.pow(b,n)
    if (k >= max):
        sys.exit("ERROR> k is greater than b^n : k={:d}, b={:d}, n={:d}".format(k,b,n))

    b_w = int(math.log(b,2))
    mask = (1 << b_w) -1
    half_mask = 1 << (b_w-1)     
    sign_mask = 1 << b_w
    core_mask = mask >> 1


    # Here b should be a power of 2
    if (math.pow(2,b_w) != b):
        sys.exit("ERROR> b should be a power of 2: {:d}".format(b))

    #decompose k in base b
    k_a = []
    for i in range (0,n):
        k_a.append(k & mask)
        k = k >> b_w

    carry = 0        
    for i in range (0,n):
        k_a[i] = (k_a[i] + carry)
        try:
            if (((k_a[i] & sign_mask)!= 0) # propagate a carry, if current digit is already negative
                or (((k_a[i] & half_mask)!= 0) and ((k_a[i] & core_mask)!= 0 or (k_a[i+1] & half_mask)!= 0))):
                # propagate a carry if the digit is > b/2.
                # In the case = b/2, propagate only if a propagation analysis is done on the next stage. 
                carry = 1
                k_a[i] = k_a[i] ^ sign_mask # inverse sign
            else:
                # Do not propagate: keep positive value (set sign bit to 0)
                carry = 0
                k_a[i] = k_a[i] & mask
        except IndexError: # last digit
            carry = 0

    return k_a

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

for base_w in range (1, 5):
    base = int(math.pow(2,base_w))
    print(">>>> Processing base={:d}".format(base))
    for digit_nb in range(1,6):
        print("++++ Processing digit_nb={:d}".format(digit_nb))
        for k in range (0,int(math.pow(base, digit_nb))):
            a = org_decomposer(k,base,digit_nb)
            b = into_int(jj_decomposer(k,base,digit_nb),base)
            r_a = reconstruction(a, base, digit_nb)
            r_b = reconstruction(b, base, digit_nb)
            w_a = weight(a)
            w_b = weight(b)
            if not((a[:-1] == b[:-1]) and (r_a == r_b) and (r_a == k) and (w_a == w_b)):
                sys.exit("ERROR> org={:s} jj={:s} rec(org)={:d} rec(jj)={:d} weight(org)={:d} weight(jj)={:d} with base={:d} digit_nb={:d} k={:d}".format(str(a), str(b), r_a, r_b, w_a, w_b, base,digit_nb,k))
                
