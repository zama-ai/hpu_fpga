#!/usr/bin/env sage
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# This code generates the twiddles in the order necessary for the NTT network.
# ==============================================================================================

from sage.all import *
import os
import sys  # manage errors
import argparse  # parse input argument
from ntt_lib import *

# ==============================================================================
# Global variables
# ==============================================================================
VERBOSE = False

# ==============================================================================
# power_exists
# ==============================================================================
def power_exists(v, N, mod_m, val):
    """
    Return a boolean indicating if there exists a power p < N such that
    (v ^ p) % mod_m == val
    """
    found = False
    j = 1  # counts the number of loop iteration
    p = 1  # store the power
    while j < N:
        p = mod((p * v),mod_m)  # v ^ j % mod_m
        if p == val:
            found = True
            break
        j = j + 1

    return found

# ==============================================================================
# generate_modulo
# ==============================================================================
def generate_mersenne_modulo(N, MOD_W):
    """
    Find a pseudo-Mersenne Prime that satisfies p = 1 mod 2*N.
    """
    pp = (2 ^ MOD_W - c for c in range(0, 2 ^ (MOD_W // 2)))
    pseudo_mersenne = (q for q in pp if is_prime(q))
    ntt_modulo = (m for m in pseudo_mersenne if m % (2 * N) == 1)

    return next(ntt_modulo)

def generate_solinas2_modulo(N, MOD_W):
    """
    Find a Solinas Prime that satisfies p = 1 mod 2*N.
    With the form:
    2^MOD_W-2^E0+1
    """
    pp = (2 ^ MOD_W - 2 ^ c + 1 for c in range(1, MOD_W-1))
    solinas = (q for q in pp if is_prime(q))
    ntt_modulo = (m for m in solinas if m % (2 * N) == 1)

    return next(ntt_modulo)

def generate_solinas3_modulo(N, MOD_W):
    """
    Find a Solinas Prime that satisfies p = 1 mod 2*N.
    With the form:
    2^MOD_W-2^E0-2^E1+1
    """
    pp = (2 ^ MOD_W - 2 ^ c - 2 ^ d + 1 for c in range(2, MOD_W-1) for d in range(1,c))
    solinas = (q for q in pp if is_prime(q))
    ntt_modulo = (m for m in solinas if m % (2 * N) == 1)

    return next(ntt_modulo)

def generate_modulo(N, MOD_W, MOD_TYPE):
    if (MOD_TYPE == "mersenne"):
        return generate_mersenne_modulo(N, MOD_W)
    elif (MOD_TYPE == "solinas2"):
        return generate_solinas2_modulo(N, MOD_W)
    elif (MOD_TYPE == "solinas3"):
        return generate_solinas3_modulo(N, MOD_W)
    else:
        sys.exit("ERROR> Unsupported modulo type {:s}".format(MOD_TYPE))

# ==============================================================================
# generate_root_unity
# ==============================================================================
def generate_root_unity(N, mod_m):
    """
    Find the Nth root of unity : omega_ru_n.
    Input:
    - N         : root unity
    - mod_m     : modulo
    Output a Nth root of unity
    """
    ZZ_mod_m = (x for x in IntegerRange(mod_m))
    pow_N_equals_1 = (x for x in ZZ_mod_m if (power_mod(x, N, mod_m) == 1))
    ru_N = (x for x in pow_N_equals_1 if not (power_exists(x, N, mod_m, 1)))
    ru_N_gcd = (x for x in ru_N if (gcd(x,mod_m) == 1))

    try:
        omega_ru_n = next(ru_N_gcd)
    except StopIteration:
        sys.exit("ERROR> Nth root of unity not found")

    return omega_ru_n


# ==============================================================================
# generate_root_unity_r
# ==============================================================================
def generate_root_unity_r(R, mod_m, omega_ru_n, S):
    """
    Find the Rth root of unity : omega_ru_r.
    Input:
    - R         : radix
    - mod_m     : modulo
    - omega_ru_n: omega Nth root of unity
    - S         : number of stage
    Output the Rth root of unity linked to omega_ru_n
    """

    return power_mod(omega_ru_n,R^(S-1), mod_m)

# ==============================================================================
# generate_twiddles
# ==============================================================================
def generate_twiddles(
    R, S, PSI, stg, stg_iter, bwd_ntt, mod_ntt, phi_ru_2n, omega_ru_n_inv
):
    """
    Generate twiddle factors for the pointwise multiplication within a BU.
    Input:
    - R         : radix
    - S         : total number of stages
    - PSI       : number of BU that process in parallel
    - stg       : current stage
    - stg_iter  : current stage iteration
    - bwd_ntt   : current type of NTT process
    - mod_ntt   : modulo used in NTT
    - phi_ru_2n : 2Nth root of unity (used when bwd_ntt = 0)
    - omega_ru_n_inv : Inverse of the Nth root of unity (used when bwd_ntt = 1)
    Output:
    - A list of PSI*R twiddle values for stage stg, iteration stg_iter.
    """
    out_l = []
    r_width = int(log(R, 2))

    digit_nb = (S - 1) - stg  # Number of digits to take into account
    mask = (1 << r_width * digit_nb) - 1
    stride = R ^ stg

    stg_bu_id_0 = stg_iter * PSI

    if bwd_ntt == 0:
        ru = phi_ru_2n
    else:
        ru = omega_ru_n_inv

    ru_pow_stride = power_mod(ru, stride, mod_ntt)

    for cl_bu_id in range(0, PSI):
        stg_bu_id = stg_bu_id_0 + cl_bu_id
        k = stg_bu_id & mask
        k_rev = reverse_order(k, R, digit_nb)

        if bwd_ntt == 0:
            exp = 2 * k_rev + 1
        else:
            exp = k_rev

        for i in range(0, R):
            out_l.append(power_mod(ru_pow_stride, i * exp, mod_ntt))

    return out_l


# ==============================================================================
# generate_final_factor
# ==============================================================================
def generate_final_factor(R, S, PSI, stg_iter, mod_ntt, n_inv, phi_ru_2n_inv):
    """
    Generate a list containing the final factors for stage iteration stg_iter.
    Input:
    - R         : radix
    - S         : total number of stages
    - PSI       : number of BU that process in parallel
    - stg_iter  : current stage iteration
    - mod_ntt   : modulo used in NTT
    - n_inv     : inverse of N
    - phi_ru_2n_inv : inverse of the 2Nth root of unity
    """
    offset = stg_iter * PSI * R
    out_l = []

    for cl_bu_id in IntegerRange(0, PSI):
        for i in IntegerRange(0, R):
            pos = stg_iter * PSI * R + cl_bu_id * R + i
            rev = reverse_order(pos, R, S)
            factor = power_mod(phi_ru_2n_inv, rev, mod_ntt)
            factor = (factor * n_inv) % mod_ntt
            out_l.append(factor)
    return out_l


# ==============================================================================
# Main
# ==============================================================================
if __name__ == "__main__" and "__file__" in globals():
    R = 8  # Radix
    PSI = 2  # Number of radix-R blocks used in parallel
    S = 3  # R^S = N the number of coefficients to be processed by the NTT
    OMEGA_RU_N = -1
    PHI_RU_2N = -1

    # ==============================================================================
    # Parse input arguments
    # ==============================================================================
    parser = argparse.ArgumentParser(description="Generate the NTT twiddles.")
    parser.add_argument(
        "-R",
        dest="radix",
        type=int,
        help="Radix value. Should be a power of 2. Default value : {:d}".format(R),
        default=R,
    )
    parser.add_argument(
        "-P",
        dest="parallel_nb",
        type=int,
        help="Number of radix blocks that work in parallel. Default value : {:d}".format(
            PSI
        ),
        default=PSI,
    )
    parser.add_argument(
        "-S",
        dest="stg_nb",
        type=int,
        help="Total number of stages. Note that R^S = N the number of coefficients of the NTT.\
            Default value : {:d}".format(
            S
        ),
        default=S,
    )
    parser.add_argument(
        "-m",
        dest="modulo",
        type=int,
        help="NTT modulo. If not given, choose the first pseudo Mersenne prime that satisfies\
            prime = 1 mod 2*N",
        default=-1,
    )
    parser.add_argument(
        "-o",
        dest="omega_ru_n",
        type=int,
        help="Nth root of unity. If not given, compute one.",
        default=-1,
    )
    parser.add_argument(
        "-q",
        dest="omega_ru_r",
        type=int,
        help="Rth root of unity. If not given, compute one.",
        default=-1,
    )
    parser.add_argument(
        "-d",
        dest="display",
        type=str,
        help="Output display order. Process order follows the processing twiddle consumption. Ram\
            order is the storage in RAM. Default : process",
        choices=["process", "ram"],
        default="process",
    )
    parser.add_argument(
        "-w",
        dest="mod_w",
        type=int,
        help="Modulo width",
        default=32
    )
    parser.add_argument(
        "-t",
        dest="mod_type",
        type=str,
        help="Modulo type",
        choices=["mersenne", "solinas2", "solinas3"],
        default="mersenne"
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
    N = R ^ S
    VERBOSE = args.verbose
    MOD_W = args.mod_w
    MOD_TYPE = args.mod_type

    # Check parameters
    if pow(2, int(log(R, 2))) != R:
        sys.exit("ERROR> R must be a power of 2")
    if S < 2:
        sys.exit("ERROR> S must be > 1 (S=1, no network needed)")

    # ==============================================================================
    # Generate modulo
    # ==============================================================================
    if args.modulo == -1:
        if VERBOSE:
            print("DEBUG> Generate NTT modulo.")
        MOD_NTT = generate_modulo(N, MOD_W, MOD_TYPE)
    else:
        MOD_NTT = args.modulo
        # Check modulo
        OK = is_prime(MOD_NTT) and (MOD_NTT >> (MOD_W-1) == 1)
        if not(OK):
            sys.exit("ERROR> Given MOD_NTT does not satisfy the requirements.")

    if VERBOSE:
        print("DEBUG> Using NTT modulo : {:d} (=0x{:x})".format(MOD_NTT, MOD_NTT))

    # ==============================================================================
    # Generate omega and phi
    # ==============================================================================
    if args.omega_ru_n == -1:
        if VERBOSE:
            print("DEBUG> Generate OMEGA_RU_N.")

        OMEGA_RU_N = generate_root_unity(N, MOD_NTT)
    else:
        OMEGA_RU_N = args.omega_ru_n
        # Check that it is a Nth root of unity
        if (power_mod(OMEGA_RU_N, N, MOD_NTT) != 1) or (
            power_exists(OMEGA_RU_N, N, MOD_NTT, 1)
        ):
            sys.exit("ERROR> {:d} is not a Nth root of unity.".format(OMEGA_RU_N))

    if VERBOSE:
        print("DEBUG> Using OMEGA_RU_N : {:d} (=0x{:x})".format(OMEGA_RU_N, OMEGA_RU_N))

    # Compute phi
    PHI_RU_2N = Integer(mod(OMEGA_RU_N, MOD_NTT).sqrt())

    # Compute the inverses
    OMEGA_RU_N_INV = inverse_mod(OMEGA_RU_N, MOD_NTT)
    PHI_RU_2N_INV = inverse_mod(PHI_RU_2N, MOD_NTT)

    # ==============================================================================
    # Compute inverse of N
    # ==============================================================================
    N_INV = inverse_mod(N, MOD_NTT)

    # ==============================================================================
    # Generate twiddles
    # ==============================================================================
    # twiddle_l[bwd_ntt][stg][stg_iter][PSI*R]
    twiddle_l = []
    for bwd_ntt in IntegerRange(0, 2):
        twiddle_l.append([])
        for stg in IntegerRange(0, S):
            twiddle_l[-1].append([])
            for stg_iter in IntegerRange(0, N // (PSI * R)):
                twiddle_l[-1][-1].append(
                    generate_twiddles(
                        R,
                        S,
                        PSI,
                        stg,
                        stg_iter,
                        bwd_ntt,
                        MOD_NTT,
                        PHI_RU_2N,
                        OMEGA_RU_N_INV,
                    )
                )

    # ==============================================================================
    # Generate omega_ru_r and multiples
    # ==============================================================================
    if args.omega_ru_r == -1:
        if VERBOSE:
            print("DEBUG> Generate OMEGA_RU_R.")
        OMEGA_RU_R = generate_root_unity_r(R, MOD_NTT, OMEGA_RU_N, S)
    else:
        OMEGA_RU_R = args.omega_ru_r
        # Check that is a Rth root of unity
        if (power_mod(OMEGA_RU_R, R, MOD_NTT) != 1) or (
            power_exists(OMEGA_RU_R, R, MOD_NTT, 1)
        ):
            sys.exit("ERROR> {:d} is not a Rth root of unity.".format(OMEGA_RU_R))

    if VERBOSE:
        print("DEBUG> Using OMEGA_RU_R : {:d} (=0x{:x})".format(OMEGA_RU_R, OMEGA_RU_R))

    omega_ru_r_l = []
    omega_ru_r_inv_l = []
    omega_ru_r_l.append(1)
    omega_ru_r_inv_l.append(1)
    for i in IntegerRange(1, R // 2):
        omega_ru_r_l.append((omega_ru_r_l[-1] * OMEGA_RU_R) % MOD_NTT)
        omega_ru_r_inv_l.append(inverse_mod(omega_ru_r_l[-1], MOD_NTT))

    # ==============================================================================
    # Final point-wise multiplication factor
    # ==============================================================================
    final_mult_factor_l = []
    for stg_iter in IntegerRange(0, N // (PSI * R)):
        final_mult_factor_l.append(
            generate_final_factor(R, S, PSI, stg_iter, MOD_NTT, N_INV, PHI_RU_2N_INV)
        )

    # ==============================================================================
    # Print
    # ==============================================================================
    display = """
N = {N}
R = {R}
S = {S}
PSI = {PSI}
N_INV = {N_INV}
MOD_NTT = {MOD_NTT}
OMEGA_RU_N = {OMEGA_RU_N}
PHI_RU_2N = {PHI_RU_2N}
OMEGA_RU_N_INV = {OMEGA_RU_N_INV}
PHI_RU_2N_INV = {PHI_RU_2N_INV}
""".format(
        N=N,
        R=R,
        S=S,
        PSI=PSI,
        N_INV=N_INV,
        MOD_NTT=MOD_NTT,
        OMEGA_RU_N=OMEGA_RU_N,
        PHI_RU_2N=PHI_RU_2N,
        OMEGA_RU_N_INV=OMEGA_RU_N_INV,
        PHI_RU_2N_INV=PHI_RU_2N_INV,
    )

    # Print matrix coefficients
    display = display + "[[\n"
    for i, c in enumerate(omega_ru_r_l):
        display = display + "0x{:09x}, # omega_ru_r^{:d}\n".format(c, i)
    display = display + "],[\n"
    for i, c in enumerate(omega_ru_r_inv_l):
        display = display + "0x{:09x}, # omega_ru_r^(-{:d})\n".format(c, i)
    display = display + "]]\n"

    # Print final factors
    display = display + "#- final factor --------------------\n"
    display = display + "[\n"
    for stg_iter in IntegerRange(0, N // (PSI * R)):
        display = display + "[\n"
        display = display + "#-- stg_iter = {:d}\n".format(stg_iter)
        for cl_bu_id in IntegerRange(0, PSI):
            display = display + "#--- cl_bu_id = {:d}\n".format(cl_bu_id)
            for i in IntegerRange(0, R):
                display = display + "0x{:09x}, ".format(
                    final_mult_factor_l[stg_iter][cl_bu_id * R + i]
                )
            display = display + "\n"
        display = display + "],\n"
    display = display + "]\n"

    # Print point wise multipliers
    display = display + "#- twiddles --------------------\n"
    if args.display == "process":
        display = display + "[\n"
        for bwd_ntt in IntegerRange(0, 2):
            display = display + "[\n"
            display = display + "#-- bwd_ntt = {:d}\n".format(bwd_ntt)
            for stg in IntegerRange(0, S):
                display = display + "[\n"
                display = display + "#--- stg = {:d}\n".format(stg)
                for stg_iter in IntegerRange(0, N // (PSI * R)):
                    display = display + "[\n"
                    display = display + "#---- stg_iter = {:d}\n".format(stg_iter)
                    for cl_bu_id in IntegerRange(0, PSI):
                        for i in IntegerRange(0, R):
                            display = display + "0x{:09x}, ".format(
                                twiddle_l[bwd_ntt][stg][stg_iter][cl_bu_id * R + i]
                            )
                        display = display + "\n"
                    display = display + "],\n"
                display = display + "],\n"
            display = display + "],\n"
        display = display + "]\n"

    elif args.display == "ram":
        for cl_bu_id in IntegerRange(0, PSI):
            display = display + "#-- cl_bu_id = {:d}\n".format(cl_bu_id)
            for i in IntegerRange(0, R):
                display = display + "#---[{:d}]\n".format(i)
                for bwd_ntt in IntegerRange(0, 2):
                    display = display + "#---- bwd_ntt = {:d}\n".format(bwd_ntt)
                    for stg in IntegerRange(0, S):
                        display = display + "#----- stg = {:d}\n".format(stg)
                        for stg_iter in IntegerRange(0, N // (PSI * R)):
                            display = display + "{:d}\n".format(
                                twiddle_l[bwd_ntt][stg][stg_iter][cl_bu_id * R + i]
                            )

    else:
        sys.exit("ERROR> Unsupported display format")

    print(display)
