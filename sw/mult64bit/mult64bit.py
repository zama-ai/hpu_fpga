# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import math 
import random
import numpy as np
from fractions import Fraction # For Toom-Cook Multiplication

# Global constant
goldilocks_prime = 2**64-2**32+1


def naive_64bmult(a, b):
    # Naive 64-bit Multiplication. 
    # Split into 16-bit chunks, and do naive crossproducts & additions
    a3 = (a >> 48) & (2**16-1)
    a2 = (a >> 32) & (2**16-1)
    a1 = (a >> 16) & (2**16-1)
    a0 = (a      ) & (2**16-1)
    b3 = (b >> 48) & (2**16-1)
    b2 = (b >> 32) & (2**16-1)
    b1 = (b >> 16) & (2**16-1)
    b0 = (b      ) & (2**16-1)

    p15 = a3*b3 # X^96
    p14 = a3*b2 # X^80
    p13 = a3*b1 # X^64
    p12 = a3*b0 # X^48

    p11 = a2*b3 # X^80
    p10 = a2*b2 # X^64
    p9 = a2*b1 # X^48
    p8 = a2*b0 # X^32

    p7 = a1*b3 # X^64
    p6 = a1*b2 # X^48
    p5 = a1*b1 # X^32
    p4 = a1*b0 # X^16

    p3 = a0*b3 # X^48
    p2 = a0*b2 # X^32
    p1 = a0*b1 # X^16
    p0 = a0*b0 # X^0

    c = p0 + ((p1+p4) << 16) + ((p2+p5+p8) << 32) + ((p3+p6+p9+p12) << 48) + ((p7+p10+p13) << 64) + ((p11+p14) << 80) + ((p15) << 96)
    return c

def lvl1karatsuba_64bmult(a, b):
    # Level-1 Karatsuba. 
    # Split into 32-bit chunks, multiply using Karatsuba
    a1 = (a >> 32) & (2**32-1)
    a0 = (a      ) & (2**32-1)
    b1 = (b >> 32) & (2**32-1)
    b0 = (b      ) & (2**32-1)

    z2 = a1*b1
    z0 = a0*b0
    z1 = (a1+a0)*(b1+b0)-z2-z0

    c = (z2 << 64) + (z1 << 32) + z0
    return c


def lvl2karatsuba_64bmult(a, b):
    # Level-2 Karatsuba. 
    # Split into 32-bit chunks, then in 16-bit chunks
    a1 = (a >> 32) & (2**32-1)
    a0 = (a      ) & (2**32-1)
    b1 = (b >> 32) & (2**32-1)
    b0 = (b      ) & (2**32-1)

    ## Create z2 with Karatsuba
    a1_1 = (a1 >> 16) & (2**16-1)
    a1_0 = (a1      ) & (2**16-1)
    b1_1 = (b1 >> 16) & (2**16-1)
    b1_0 = (b1      ) & (2**16-1)

    z2_2 = a1_1*b1_1
    z0_2 = a1_0*b1_0
    z1_2 = (a1_1+a1_0)*(b1_1+b1_0)-z2_2-z0_2
    z2 = (z2_2 << 32) + (z1_2 << 16) + z0_2

    ## Create z0 with Karatsuba
    a0_1 = (a0 >> 16) & (2**16-1)
    a0_0 = (a0      ) & (2**16-1)
    b0_1 = (b0 >> 16) & (2**16-1)
    b0_0 = (b0      ) & (2**16-1)

    z2_0 = a0_1*b0_1
    z0_0 = a0_0*b0_0
    z1_0 = (a0_1+a0_0)*(b0_1+b0_0)-z2_0-z0_0
    z0 = (z2_0 << 32) + (z1_0 << 16) + z0_0

    ## Create z1 with Karatsuba
    # (a1+a0)*(b1+b0)-z2-z0
    a10_1 = ((a1+a0) >> 16) & (2**17-1)
    a10_0 = ((a1+a0)      ) & (2**16-1)
    b10_1 = ((b1+b0) >> 16) & (2**17-1)
    b10_0 = ((b1+b0)      ) & (2**16-1)

    z2_1 = a10_1*b10_1
    z0_1 = a10_0*b10_0
    z1_1 = (a10_1+a10_0)*(b10_1+b10_0)-z2_1-z0_1
    z1 = (z2_1 << 32) + (z1_1 << 16) + z0_1

    z1 = z1-z2-z0

    c = (z2 << 64) + (z1 << 32) + z0
    return c


def toomcook4_64bmult(a, b):
    # Toom-Cook 4-way Multiplier.
    # Algorithm from: https://en.wikipedia.org/wiki/Toom%E2%80%93Cook_multiplication
    # Split inputs into 16-bit chunks
    u3 = (a >> 48) & (2**16-1)
    u2 = (a >> 32) & (2**16-1)
    u1 = (a >> 16) & (2**16-1)
    u0 = (a      ) & (2**16-1)
    v3 = (b >> 48) & (2**16-1)
    v2 = (b >> 32) & (2**16-1)
    v1 = (b >> 16) & (2**16-1)
    v0 = (b      ) & (2**16-1)

    # Expected number of multipliers is d = 2k-1 = 7
    d = 7
    

    ## P and Q matrices from evaluation points
    P = np.matrix([[1, 0, 0, 0], [1, 1, 1, 1], [1, -1, 1, -1], [1, 2, 4, 8], [1, -2, 4, -8], [1, -3, 9, -27], [0, 0, 0, 1]])
    Q = np.matrix([[1, 0, 0, 0], [1, 1, 1, 1], [1, -1, 1, -1], [1, 2, 4, 8], [1, -2, 4, -8], [1, -3, 9, -27], [0, 0, 0, 1]])

    ## Evaluation
    p_vec = P*np.matrix([[u0], [u1], [u2], [u3]])
    q_vec = Q*np.matrix([[v0], [v1], [v2], [v3]])

    r_vec = np.zeros((d, 1))
    
    ## Pointwise multiplications
    for i in range(d):
        r_vec[i][0] = p_vec[i]*q_vec[i]

    R = np.matrix([[1, 0, 0, 0, 0, 0, 0], [1, 1, 1, 1, 1, 1, 1], [1, -1, 1, -1, 1, -1, 1], [1, 2, 4, 8, 16, 32, 64], [1, -2, 4, -8, 16, -32, 64], [1, -3, 9, -27, 81, -243, 729], [0, 0, 0, 0, 0, 0, 1]])
    R_inv_int = np.linalg.inv(R) # intermediate values
    R_inv = np.zeros((d, d)) # contains fractions instead of floats

    for i in range(d):
        for j in range(d): 
            res = Fraction(R_inv_int[i, j].item()).limit_denominator(100000)
            R_inv[i, j] = res.numerator/res.denominator

    ## Check if R and R_inv are ok                     
    #print(np.round(R*R_inv))

    r = np.matmul(R_inv, r_vec)
    
    ## Reconstruct
    c = (round(r[6].item()) << 96) + (round(r[5].item()) << 80) + (round(r[4].item()) << 64) + (round(r[3].item()) << 48) + (round(r[2].item()) << 32) + (round(r[1].item()) << 16) + round(r[0].item())
    return c


def supranational_64bmult(a, b):
    # Supranational Multiplier. 
    # Algorithm from: https://github.com/supranational/zprize-fpga-ntt/blob/main/rtl/dsp48e2/mul64x64.sv
    # Split inputs
    a2 = (a >> 52) & (2**26-1)
    a1 = (a >> 26) & (2**26-1)
    a0 = (a      ) & (2**26-1)

    b3 = (b >> 51) & (2**17-1)
    b2 = (b >> 34) & (2**17-1)
    b1 = (b >> 17) & (2**17-1)
    b0 = (b      ) & (2**17-1)

    ## Test reconstruction 
    #a_rec = (a2 << 52) | (a1 << 26) | (a0 << 0)
    #b_rec = (b3 << 51) | (b2 << 34) | (b1 << 17) | (b0 << 0)
    #print("Reconstruction of a ok? ", a_rec==a)
    #print("Reconstruction of b ok? ", b_rec==b)
    #print()

    ## Functionality of the 12 DSPs 
    dsp_00 = a0*b0                   # Contributions in x^0
    dsp_01 = a0*b1 + (dsp_00 >> 17)  # Contributions in x^17
    dsp_02 = a0*b2 + (dsp_01 >> 17)  # Contributions in x^34
    dsp_03 = a0*b3 + (dsp_02 >> 17)  # Contributions in x^51

    dsp_10 = a1*b0 + ((dsp_02 & 2**9-1) << 8) + ((dsp_01 >> 9) & 2**8-1)
    dsp_11 = a1*b1 + ((dsp_03 & 2**9-1) << 8) + ((dsp_02 >> 9) & 2**8-1) + (dsp_10 >> 17)
    dsp_12 = a1*b2 + ((dsp_03 >> 9) & 2**39-1) + (dsp_11 >> 17)
    dsp_13 = a1*b3 + (dsp_12 >> 17)

    dsp_20 = a2*b0 + (((dsp_12 & 2**9-1) << 8) + ((dsp_11 >> 9) & 2**8-1))
    dsp_21 = a2*b1 + ((dsp_13 & 2**9-1) << 8) + ((dsp_12 >> 9) & 2**8-1) + (dsp_20 >> 17)
    dsp_22 = a2*b2 + ((dsp_13 >> 9) & 2**39-1) + (dsp_21 >> 17)
    dsp_23 = a2*b3 + (dsp_22 >> 17)

    ## Reconstruct output
    dsp_res = dsp_00 & 2**17-1
    dsp_res = dsp_res | ((dsp_01 & 2**9-1) << 17)
    dsp_res = dsp_res | ((dsp_10 & 2**17-1) << 26)
    dsp_res = dsp_res | ((dsp_11 & 2**9-1) << 43)
    dsp_res = dsp_res | ((dsp_20 & 2**17-1) << 52)
    dsp_res = dsp_res | ((dsp_21 & 2**17-1) << 69)
    dsp_res = dsp_res | ((dsp_22 & 2**17-1) << 86)
    dsp_res = dsp_res | ((dsp_22 & 2**17-1) << 86)

    dsp_res = dsp_res | (dsp_23 << 103)
    return dsp_res


def mod_red(a):
    # Modular reduction for modular multiplication with Golidlocks prime as modulus
    # Algorithm from: https://www.craig-wood.com/nick/armprime/math/
    
    ## Split input: x3 * 2^96 + x2 * 2^64 + x1 * 2^32 + x0 mod p
    x3 = a >> 96
    x2 = (a >> 64) & (2**32-1)
    x1 = (a >> 32) & (2**32-1)
    x0 = a & (2**32-1)
    
    ## Check that reconstruction is ok 
    recons = x3*2**96 + x2*2**64 + x1*2**32 + x0
    if (recons != a):
        print("ERROR - Recons NOT OK")
    
    ## Calculate modular reduction
    a_mod = x2*2**64+x1*2**32+(x0-x3)
    y2 = (a_mod >> 64) & (2**32-1)
    y1 = (a_mod >> 32) & (2**32-1)
    y0 = a_mod & (2**32-1)
    a_mod = y2*2**64 + y1*2**32 + y0
    a_mod = (y1+y2)*2**32 + (y0-y2)

    ## Final correction    
    if a_mod >= goldilocks_prime:
        a_mod = a_mod-goldilocks_prime
    
    return a_mod

def ulvetanna_modmul(a, b):
    # Modular Multiplication with Golidlocks prime as modulus
    # Optimisations are from the Ulvetanna blogpost: https://www.ulvetanna.io/news/fpga-architecture-for-goldilocks-ntt
    # Split inputs
    a1 = (a >> 32) & (2**32-1)
    a0 = (a      ) & (2**32-1)
    b1 = (b >> 32) & (2**32-1)
    b0 = (b      ) & (2**32-1)

    ## Calculate 98-bit intermediate value
    c = (a0*b0-a1*b1) + (((a0+a1)*(b0+b1)-a0*b0) << 32)

    ## Reduce 98-bit value to 64-bit output
    c3 = (c >> 96) & (2**2-1)
    c2 = (c >> 64) & (2**32-1)
    c1 = (c >> 32) & (2**32-1)
    c0 = (c >> 0) & (2**32-1)

    c = ((c1+c2) << 32) + c0 - c2 - c3

    ## Final correction
    if c >= goldilocks_prime: 
        c = c-goldilocks_prime

    return c

def ulvetanna_modred(a):
    # Modular Reduction with Golidlocks prime as modulus
    # Optimisations are from the Ulvetanna blogpost: https://www.ulvetanna.io/news/fpga-architecture-for-goldilocks-ntt
    # This function checks whether the modred can reduce inputs with more than 98-bits
    c3 = (a >> 96) & (2**32-1)
    c2 = (a >> 64) & (2**32-1)
    c1 = (a >> 32) & (2**32-1)
    c0 = (a >> 0) & (2**32-1)

    c = ((c1+c2) << 32) + c0 - c2 - c3

    ## Final correction
    if c >= goldilocks_prime: 
        c = c-goldilocks_prime

    return c


def main():
    nr_of_iterations = 2000

    print("Test 64x64-bit Arithmetic Multiplications")
    for i in range(nr_of_iterations):
        op_a = random.getrandbits(64) % goldilocks_prime
        op_b = random.getrandbits(64) % goldilocks_prime
        c_ref = op_a*op_b
        c_naive = naive_64bmult(op_a, op_b)
        c_lvl1karatsuba = lvl1karatsuba_64bmult(op_a, op_b)
        c_lvl2karatsuba = lvl2karatsuba_64bmult(op_a, op_b)
        c_toomcook = toomcook4_64bmult(op_a, op_b)
        c_supranational = supranational_64bmult(op_a, op_b)

        if (c_ref!=c_naive | c_ref!=c_lvl1karatsuba | c_ref!=c_lvl2karatsuba | c_ref!=c_toomcook | c_ref!=c_supranational):
            print("64-bit Multiplication with Naive Mult OK?          ", c_ref==c_naive)
            print("64-bit Multiplication with lvl1 Karatsuba Mult OK? ", c_ref==c_lvl1karatsuba)
            print("64-bit Multiplication with lvl2 Karatsuba Mult OK? ", c_ref==c_lvl2karatsuba)
            print("64-bit Multiplication with Toom-Cook Mult OK?      ", c_ref==c_toomcook)
            print("64-bit Multiplication with Supranational Mult OK?  ", c_ref==c_supranational)


    print("Test Modular Multiplications with Goldilocks prime modulus: ", goldilocks_prime)
    for i in range(nr_of_iterations):
        op_a = random.getrandbits(64) % goldilocks_prime
        op_b = random.getrandbits(64) % goldilocks_prime
        c_ref = mod_red(op_a*op_b)
        c_ulvetanna = ulvetanna_modmul(op_a, op_b)
        if (c_ref!=c_ulvetanna):
            print("64-bit Modular Multiplication with Ulvetanna Mod Mult OK?  ", c_ref==c_ulvetanna)

    # Check compatibility of modular reduction with sum of products
    print("Test Ulvetanna Modular Reduction with Goldilocks prime modulus and inputs with more than 98 bits")
    for i in range(nr_of_iterations):
        op_a = random.getrandbits(64) % goldilocks_prime
        op_b = random.getrandbits(64) % goldilocks_prime
        c_ref = op_a*op_b
        c_mod = mod_red(c_ref)
        c_ulvetanna = ulvetanna_modred(c_ref)
        if (c_mod!=c_ulvetanna):
            print("128-bit Goldilocks Modular Reduction with Ulvetanna Mod Red OK?  ", c_mod==c_ulvetanna)


if __name__ == '__main__':
    main()
