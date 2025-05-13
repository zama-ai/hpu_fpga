#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import sys  # manage errors
import argparse  # parse input argument
from math import log, pow, ceil
import copy

from ntt_lib import *

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


def reverse_order(v, R, S, step):
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
# reference
# ==============================================================================
def reference(ref_l, dest_l, ram_l):
    """
    Fill the lists with the reference values.
    For the last stage, the nodes are numbered in natural order.
    The BU are complete.
    """

    step = 0
    for stg in range(S):
        if (VERBOSE):
            print("# REF stg={:0d}".format(stg))

        ref_l.append([])
        dest_l.append([])
        ram_l.append([])

        #== Group characteristics
        group_size = R**(step + 2)
        group_nb   = (PSI*R) // group_size

        # init
        for p in range(PSI):
            ram_l[-1].append([])
            for r in range(R):
                ram_l[-1][-1].append([])
                for i in range(STG_ITER_NB):
                    ram_l[-1][-1][-1].append([])
                    ram_l[-1][-1][-1][-1] = {}

        for stg_iter in range(STG_ITER_NB):
            ref_l[-1].append([])
            dest_l[-1].append([])

            node_idx_0 = stg_iter * PSI
            node_id_0 = reverse_order(node_idx_0, R, S-1, step)

            if (VERBOSE):
                print("# stg_iter={:0d} node_id_0={:06b}".format(stg_iter, node_id_0))

            # init
            for p in range(PSI):
                dest_l[-1][-1].append([])
                for r in range(R):
                    dest_l[-1][-1][-1].append([])
                    dest_l[-1][-1][-1][-1].append([])

            for p in range(PSI):
                ref_l[-1][-1].append([])

                node_idx = stg_iter * PSI + p
                node_id = reverse_order(node_idx, R, S-1, step)

                for r in range(R):
                    ref_l[-1][-1][-1].append([])
                    next_node_id = node_id # current node gives the next node ID
                    next_p = next_node_id & PSI_MASK
                    next_stg_iter = next_node_id >> (PSI_W*R_W)
                    next_r = r

                    ref_l[-1][-1][-1][-1] = {}
                    ref_l[-1][-1][-1][-1]["next_p"] = next_p
                    ref_l[-1][-1][-1][-1]["next_r"] = next_r
                    ref_l[-1][-1][-1][-1]["next_stg_iter"] = next_stg_iter

                    d = {}
                    d["next_stg_iter"] = next_stg_iter
                    d["p"] = p
                    d["r"] = r
                    dest_l[-1][-1][next_p][next_r].append(d)

                    d2 = {}
                    d2["p"] = p
                    d2["r"] = r
                    d2["stg_iter"] = stg_iter
                    ram_l[-1][next_p][next_r][next_stg_iter] = d2

                    if (VERBOSE):
                        print("p={:2d} node_id={:06b} r={:1d} => next_node_id={:06b} next_p={:2d} next_r={:1d} next_stg_iter={:3d}".format(
                              p, node_id, r, next_node_id,next_p,next_r, next_stg_iter))

            if (VERBOSE):
                print("#--------")
                for next_p in range(PSI):
                    for next_r in range(R):
                        print("DEST: next_p={:2d} next_r={:1d} {:s}".format(
                                      next_p, next_r, str(dest_l[-1][-1][next_p][next_r])))
                print("#--------")
                for next_p in range(PSI):
                    for next_r in range(R):
                        print("RAM: next_p={:2d} next_r={:1d} {:s}".format(
                                      next_p, next_r, str(ram_l[-1][next_p][next_r])))


        #== Increase step
        step = step + 1
        if (step >= DELTA):
            step = 0;

# ==============================================================================
# Main
# ==============================================================================
if __name__ == "__main__":

    R = 2  # Radix
    PSI = 16  # Number of radix-R blocks used in parallel
    DELTA = 4
    S = 11  # R^S = N the number of coefficients to be processed by the NTT

    # ==============================================================================
    # Parse input arguments
    # ==============================================================================
    parser = argparse.ArgumentParser(
        description="Check the ping-pong structure of the NTT."
    )
    parser.add_argument(
        "-R",
        dest="radix",
        type=int,
        help="Radix value. Should be a power of 2.",
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
        "-D",
        dest="delta",
        type=int,
        help="Network depth",
        default=DELTA,
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
    DELTA = args.delta
    VERBOSE = args.verbose

    N = R**S
    STG_ITER_NB = (R**S)//(PSI*R)
    R_W = int(log(R, 2))
    # Number of digit to represent PSI in base R
    PSI_W = int(log(PSI, 2)) // R_W
    # Number of digit to represent STG_ITER_NB in base R
    STG_ITER_W = int(log(STG_ITER_NB, 2)) // R_W
    STG_ITER_MASK = (1 << STG_ITER_W*R_W) -1
    NODE_ID_MASK  = (1 << (S-1)*R_W) -1
    NODE_NB = N // R
    PSI_MASK = (1 << (PSI_W*R_W))-1


    #########################
    # Reference
    #########################
    # ref_l[stg][stg_iter][p][r] = {"next_p": ,
    #                             "next_r": ,
    #                             "next_stg_iter":}
    #
    # dest[stg][stg_iter][next_p][next_r] = {"p": ,
    #                                        "r": ,
    #                                        "next_stg_iter":}
    # ram_l[stg][next_p][next_r][next_stg_iter] = {"p":
    #                                            "r":,
    #                                            "stg_iter":}
    ref_l = []
    dest_l = []
    ram_l = []
    reference(ref_l, dest_l, ram_l)

    #########################
    # Process
    #########################
    delta = 0
    for stg in range(S):
        if (VERBOSE):
            print("#==============================")
            print("# stg={:0d} delta={:0d}".format(stg, delta))
            print("#==============================")

        # In BU unit
        group_size = R**(delta+2)
        group_nb = PSI // R**delta

        group_size = N
        group_nb   = (PSI*R) // group_size
        total_group_nb = N // group_size
        group_bu   = group_size // R # also = group_pos_occurrence
        group_bu_w =  int(log(group_bu,2))//R_W
        stg_iter_nb_per_group = STG_ITER_NB // total_group_nb
        max_stg_iter_nb_per_bu_pos = STG_ITER_NB // (PSI*R)
        next_delta = delta + 1
        pos_nb     = R

        if (VERBOSE):
            print("#==")
            print("# group_size={:0d} group_nb={:0d} group_bu={:0d} pos_nb={:0d} total_group_nb={:0d}".format(group_size, group_nb, group_bu, pos_nb, total_group_nb))
            print("# stg_iter_nb_per_group={:0d} max_stg_iter_nb_per_bu_pos={:0d}".format(stg_iter_nb_per_group,max_stg_iter_nb_per_bu_pos))
            print("#==")


        #== init buffer
        buf_l = []
        out_l = []
        # init
        for p in range(PSI):
            buf_l.append([])
            out_l.append([])
            for r in range(R):
                buf_l[-1].append([])
                out_l[-1].append([])
                for i in range(STG_ITER_NB):
                    buf_l[-1][-1].append([])
                    buf_l[-1][-1][-1] = {} # dict with p, r, stg_iter
                    out_l[-1][-1].append([])
                    out_l[-1][-1][-1] = {} # dict with p, r, stg_iter


        #====================
        #== Process
        #====================
        if (delta <= PSI_W*R_W):
            cons_nb = R**delta
            occ_nb = R**(PSI_W*R_W-delta)
            if ((PSI_W*R_W-delta) > STG_ITER_W*R_W):
                occ_nb = R**(STG_ITER_W*R_W)
        else:
            cons_nb = 1
            occ_nb = R**(delta - PSI_W*R_W)
            if (occ_nb > PSI):
                occ_nb = PSI

        if (delta < PSI_W*R_W):
            if (STG_ITER_W*R_W-(PSI_W*R_W-delta) > 0):
                iter_cons_nb = R**(STG_ITER_W*R_W-(PSI_W*R_W-delta))
            else:
                iter_cons_nb = 1
        else:
            if (delta - PSI_W*R_W > PSI_W*R_W):
                iter_cons_nb = R**(delta - 2*PSI_W*R_W)
            else:
                iter_cons_nb = 1


        set_nb = PSI//(cons_nb*occ_nb)
        if (set_nb == 0):
            set_nb = 1

        if (VERBOSE):
            print("#==")
            print("# cons_nb={:0d}".format(cons_nb))
            print("# occ_nb={:0d}".format(occ_nb))
            print("# set_nb={:0d}".format(set_nb))
            print("# iter_cons_nb={:0d}".format(iter_cons_nb))
            print("#==")

        set_w = int(log(set_nb,2))//R_W
        cons_w = int(log(cons_nb,2))//R_W

        #== Write
        for stg_iter in range(STG_ITER_NB):
            if (VERBOSE):
                print("## Proc WR stg_iter={:d}".format(stg_iter))
            # input
            in_l = []
            for p in range(PSI):
                node_idx = stg_iter*PSI+p
                node_id = reverse_order(node_idx, R, S-1, delta)
                next_node_id = node_id
                next_stg_iter_ofs = next_node_id >> (PSI_W*R_W)
                for r in range(R):
                    next_stg_iter = next_stg_iter_ofs;
                    in_l.append({"org":{"p" : p, "r" : r, "stg_iter" : stg_iter},
                                 "next_stg_iter":next_stg_iter})

            if (VERBOSE):
                print("#---------")
                for p in range(PSI):
                    for r in range(R):
                        print("wr_in_l[{:0d}][{:0d}] = {:s}".format(p,r,str(in_l[p*R+r])))

            # Dispatch BU
            wr_dispb_l = []
            for p in range(PSI):
                node_idx = p
                node_id = reverse_order(node_idx, R, S-1, delta)
                next_p_ofs = node_id & PSI_MASK
                occ_idx = p // cons_nb
                occ_id = reverse_order(occ_idx, R,int(log(occ_nb,2))//R_W, 0)
                next_p = (next_p_ofs+occ_id*cons_nb)%PSI
                if (VERBOSE):
                    print("# node_idx={:0d} node_id={:0d} next_p_ofs={:0d} occ_idx={:0d} occ_id={:0d} next_p={:0d}".format(node_idx, node_id, next_p_ofs,occ_idx, occ_id,next_p))
                for r in range(R):
                    wr_dispb_l.append(in_l[next_p*R+r])

            if (VERBOSE):
                print("#---------")
                for p in range(PSI):
                    for r in range(R):
                        print("wr_dispb_l[{:0d}][{:0d}] = {:s}".format(p,r,str(wr_dispb_l[p*R+r])))


            # Rot BU
            rot_idx = (stg_iter // iter_cons_nb) % (PSI // (set_nb*cons_nb))
            rot_id  = reverse_order(rot_idx, R,PSI_W-set_w-cons_w, 0)
            rot_bu_factor = (rot_id * cons_nb)%PSI
            wr_rotb_l = [wr_dispb_l[((p-rot_bu_factor)%PSI)*R+r] for p in range(PSI) for r in range(R)]
            if (VERBOSE):
                print("# wr_rot_bu_factor={:0d} rot_idx={:0d} rot_id={:0d}".format(rot_bu_factor,rot_idx, rot_id))
            if (VERBOSE):
                print("#---------")
                for p in range(PSI):
                    for r in range(R):
                        print("wr_rotb_l[{:0d}][{:0d}] = {:s}".format(p,r,str(wr_rotb_l[p*R+r])))

            for p in range(PSI):
                for r in range(R):
                    buf_l[p][r][wr_rotb_l[p*R+r]["next_stg_iter"]] = wr_rotb_l[p*R+r]

        #== Read
        for next_stg_iter in range(STG_ITER_NB):
            # read data
            rd_l = []
            for p in range(PSI):
                for r in range(R):
                    rd_l.append(buf_l[p][r][next_stg_iter])

            if (VERBOSE):
                print("## Proc RD next_stg_iter={:d}".format(next_stg_iter))

            if (VERBOSE):
                print("#---------")
                for p in range(PSI):
                    for r in range(R):
                        print("rd_in_l[{:0d}][{:0d}] = {:s}".format(p,r,str(rd_l[p*R+r])))


            # Rotate BU
            rot_bu_factor = (next_stg_iter//iter_cons_nb * cons_nb) % (PSI // set_nb)
            if (VERBOSE):
                print("# rd_rot_bu_factor={:0d}".format(rot_bu_factor))

            rd_l = [rd_l[(p+rot_bu_factor)%PSI * R + r] for p in range(PSI) for r in range(R)]

            if (VERBOSE):
                print("#---------")
                for p in range(PSI):
                    for r in range(R):
                        print("rd_rotb_l[{:0d}][{:0d}] = {:s}".format(p,r,str(rd_l[p*R+r])))

            for p in range(PSI):
                for r in range(R):
                    out_l[p][r][next_stg_iter] = rd_l[p*R+r]

        #====================
        #== Check
        #====================
        for stg_iter in range(STG_ITER_NB):
            error = 0
            for p in range(PSI):
                for r in range(R):
                    if (ram_l[stg][p][r][stg_iter] != out_l[p][r][stg_iter]["org"]):
                        print("ERROR> stg={:0d} stg_iter={:d} p={:0d} r={:0d} exp={:s} seen{:s}".format(stg,stg_iter,p,r,str(ram_l[stg][p][r][stg_iter]), str(out_l[p][r][stg_iter])))
                        error = 1
            if (error == 1):
                sys.exit("ERROR> Data mismatch at : stg={:0d} stg_iter={:d}".format(stg,stg_iter))





#            # Data order as at the output of the HW network
#            if (pos_nb > 1):
#                network_stage(in_l, R, PSI, group_size)
#
#            if (VERBOSE):
#                print("#---------")
#                for p in range(PSI):
#                    for r in range(R):
#                        print("wr_ntw_l[{:0d}][{:0d}] = {:s}".format(p,r,str(in_l[p*R+r])))
#
#
#            # Rot R
#            # To place according to pos_id
#            if (pos_nb == 1):
#                pos_id = ((stg_iter*PSI*R) // group_bu) % R
#                rot_r_factor = pos_id
#
#                if (VERBOSE):
#                    print("# wr_rot_r_factor={:0d}".format(rot_r_factor))
#                for p in range(PSI):
#                    in_l[p*R:(p+1)*R] = [in_l[p*R+(r-rot_r_factor)%R] for r in range(R)]
#
#            if (VERBOSE):
#                print("#---------")
#                for p in range(PSI):
#                    for r in range(R):
#                        print("wr_rotr_l[{:0d}][{:0d}] = {:s}".format(p,r,str(in_l[p*R+r])))
#
#
#            # Dispatch BU
#            if (pos_nb > 1):
#                # Interleave the groups
#                wr_dispb_l = []
#                tmp_l = [in_l[i*R +r]  for i in inc_stride(group_nb*group_bu, group_bu) for r in range(R)]
#                wr_dispb_l =  wr_dispb_l + tmp_l
#            else:
#                wr_dispb_l = in_l
#
#            # Dispatch according to the sets
#            wr_dispb_l = [wr_dispb_l[i*R*cons_nb +r]  for i in inc_stride(PSI//cons_nb, set_nb) for r in range(R*cons_nb)]
#
#            if (VERBOSE):
#                print("#---------")
#                for p in range(PSI):
#                    for r in range(R):
#                        print("wr_dispb_l[{:0d}][{:0d}] = {:s}".format(p,r,str(wr_dispb_l[p*R+r])))
#
#            # Rot BU
#            if (pos_nb > 1):
#                # To avoid writing collision
#                rot_bu_factor = ((stg_iter % group_bu) * cons_nb) % (PSI // set_nb)
#            else:
#                succ_iter = iter_cons_nb * R
#                rot_bu_factor = stg_iter // succ_iter
#
#            if (VERBOSE):
#                print("# wr_rot_bu_factor={:0d}".format(rot_bu_factor))
#            wr_rotb_l = [wr_dispb_l[((p-rot_bu_factor)%PSI)*R+r] for p in range(PSI) for r in range(R)]
#
#            if (VERBOSE):
#                print("#---------")
#                for p in range(PSI):
#                    for r in range(R):
#                        print("wr_rotb_l[{:0d}][{:0d}] = {:s}".format(p,r,str(wr_rotb_l[p*R+r])))
#
#            for p in range(PSI):
#                for r in range(R):
#                    buf_l[p][r][wr_rotb_l[p*R+r]["next_stg_iter"]] = wr_rotb_l[p*R+r]
#
#        #== Read
#        for next_stg_iter in range(STG_ITER_NB):
#            # read data
#            rd_l = []
#            for p in range(PSI):
#                for r in range(R):
#                    rd_l.append(buf_l[p][r][next_stg_iter])
#
#            if (VERBOSE):
#                print("## Proc RD next_stg_iter={:d}".format(next_stg_iter))
#
#            if (VERBOSE):
#                print("#---------")
#                for p in range(PSI):
#                    for r in range(R):
#                        print("rd_in_l[{:0d}][{:0d}] = {:s}".format(p,r,str(rd_l[p*R+r])))
#
#
#            # Rotate BU
#            if (pos_nb > 1):
#                rot_idx = (next_stg_iter // stg_iter_ofs)
#                rot_bu_factor = (rot_idx * cons_nb) % (PSI // set_nb)
#            else:
#                rot_bu_factor = (next_stg_iter // stg_iter_ofs) % (PSI//set_nb)
#
#            if (VERBOSE):
#                print("# rd_rot_bu_factor={:0d}".format(rot_bu_factor))
#
#            rd_l = [rd_l[(p+rot_bu_factor)%PSI * R + r] for p in range(PSI) for r in range(R)]
#
#            if (VERBOSE):
#                print("#---------")
#                for p in range(PSI):
#                    for r in range(R):
#                        print("rd_rotb_l[{:0d}][{:0d}] = {:s}".format(p,r,str(rd_l[p*R+r])))
#
#            # Rot R
#            if (pos_nb == 1):
#                rot_r_factor = (next_stg_iter // (STG_ITER_NB // R)) % R
#
#                if (VERBOSE):
#                    print("# rd_rot_r_factor={:0d}".format(rot_r_factor))
#                for p in range(PSI):
#                    rd_l[p*R:(p+1)*R] = [rd_l[p*R+(r+rot_r_factor)%R] for r in range(R)]
#
#            if (VERBOSE):
#                print("#---------")
#                for p in range(PSI):
#                    for r in range(R):
#                        print("rd_rotr_l[{:0d}][{:0d}] = {:s}".format(p,r,str(rd_l[p*R+r])))
#
#            for p in range(PSI):
#                for r in range(R):
#                    out_l[p][r][next_stg_iter] = rd_l[p*R+r]
#
#        #====================
#        #== Check
#        #====================
#        for stg_iter in range(STG_ITER_NB):
#            error = 0
#            for p in range(PSI):
#                for r in range(R):
#                    if (ram_l[stg][p][r][stg_iter] != out_l[p][r][stg_iter]["org"]):
#                        print("ERROR> stg={:0d} stg_iter={:d} p={:0d} r={:0d} exp={:s} seen{:s}".format(stg,stg_iter,p,r,str(ram_l[stg][p][r][stg_iter]), str(out_l[p][r][stg_iter])))
#                        error = 1
#            if (error == 1):
#                sys.exit("ERROR> Data mismatch at : stg={:0d} stg_iter={:d}".format(stg,stg_iter))

        #== Increase delta
        delta = delta + 1
        if (delta >= DELTA):
            delta = 0;
