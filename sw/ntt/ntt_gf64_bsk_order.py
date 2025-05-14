#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# BSK polynomials are order in natural order.
# For each polynomial of BSK do the following re-ordering.
# cut_l is the way the NTT is split into radix.

def bsk_order (cut_l):
    """
    Compute bsk output order for current working block size.
    Extend to all the working blocks.
    """

    if (len(cut_l) == 1):
        n_l = 2**cut_l[0]

        return [i for i in range(n_l)]

    else:
        s_l = 0;
        for c in (cut_l):
          s_l = s_l + c

        # Current WB size
        n_l = 2**s_l

        r0 = 2**cut_l[0]
        r1 = 2**(s_l-cut_l[0])

        r1_nb = n_l // r1

        l1 = bsk_order(cut_l[1:])

        return [r0*idx+j for j in range(r1_nb) for idx in l1]
