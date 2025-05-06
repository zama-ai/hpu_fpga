#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import sys  # manage errors
import argparse  # parse input argument
from math import log, pow, ceil
import copy

from ntt_lib import *


# ==============================================================================
# pseudo_reverse_order
# ==============================================================================
def pseudo_reverse_order(v, R, S, step):
    """
    For an index v in 0...R^S, if we decompose it in the R-base:
    v = v_0*R^0 + v_1*R^1 + ... v_(S-1)*R^(S-1)
    where v_j is in 0...R-1.
    The pseudo reverse order, at step s, of v in base R, for a number of stages S is:
    pseudo_reverse_order(v) = v_step*R^(S-1) + v_(step+1)*R^(S-2) +...+v_(S-1)*R^(step)+v_(step-1)*R^(step-1)+..+v_1*R^1+v_0*R^0

    R is a power of 2.

    step = 0 <=> reverse
    """
    r_width = int(log(R, 2))
    if pow(2, r_width) != R:
        sys.exit("ERROR> Radix R must be a power of 2")

    r_mask = (1 << r_width) - 1

    v_l = []
    res_l=[]
    tmp = v
    for i in range(S):
        v_l.append(tmp & r_mask)
        res_l.append(0)
        tmp = tmp >> r_width

    for i in range(step):
        res_l[i] = v_l[i]
    for i in range(step,S):
        res_l[i] = v_l[S-1-(i-step)]

    res = 0
    for i in range(S):
        res = (res << r_width) + res_l[S-1-i]

    return res

# ==============================================================================
# pseudo_inverse_order
# ==============================================================================
def pseudo_inverse_order(v, R, S, step):
    """
    For an index v in 0...R^S, if we decompose it in the R-base:
    v = v_0*R^0 + v_1*R^1 + ... v_(S-1)*R^(S-1)
    where v_j is in 0...R-1.
    The pseudo inverse order, at step s, of v in base R, for a number of stages S is:
    pseudo_inverse_order(v) = v_step*R^(S-1) + v_(step+1)*R^(S-2) +...+v_0*R^(step)+v_(S-1-step-1)*R^(step-1)+..+v_(S-2)*R^1+v_(S-1)*R^0

    R is a power of 2.

    step = 0 <=> inverse
    """
    r_width = int(log(R, 2))
    if pow(2, r_width) != R:
        sys.exit("ERROR> Radix R must be a power of 2")

    r_mask = (1 << r_width) - 1

    v_l = []
    res_l=[]
    tmp = v
    for i in range(S):
        v_l.append(tmp & r_mask)
        res_l.append(0)
        tmp = tmp >> r_width

    for i in range(step):
        res_l[i] = v_l[S-1-i]
    for i in range(step,S):
        res_l[i] = v_l[i-step]

    res = 0
    for i in range(S):
        res = (res << r_width) + res_l[S-1-i]

    return res

# ==============================================================================
# network
# ==============================================================================
def network_whole_group(l, R, PSI, group_size, use_bu):
    """
    l is a list containing the output of the BUs : R*PSI elements
    This function reoders the data for the next stage.
    """

    # group_size is a power of R
    size_w = int(log(group_size, R))
    if (R**size_w != group_size):
        sys.exit("ERROR> network group_size ({:0d}) should be a power of R ({:0d}".format(group_size,R))
    if (group_size > (R*PSI)):
        sys.exit("ERROR> group_size {:0d} is greater than the size of l ({:0d}).".format(group_size, R*PSI))
    if (len(l) != R*PSI):
        sys.exit("ERROR> Wrong l size {:0d}. Should be R*PSI {:0d}x{:0d}".format(len(l),R,PSI))

    part_size = group_size // R**2

    if (use_bu):
      if (group_size >= R**3):
          cond0 = True
      else:
          cond0 = False

      if (part_size > R):
          cond1 = True
      else:
          cond1 = False
    else:
      if (group_size >= R**2):
          cond0 = True
      else:
          cond0 = False

      if (part_size > 1):
          cond1 = True
      else:
          cond1 = False

    if (cond0):
        group_cnt = (R*PSI) // group_size

        for k in range(group_cnt):
            ll = copy.deepcopy(l[k*group_size:(k+1)*group_size])
            for i in range(R**2):
                # TODO : do this for R!=2
                if (i==0 or i==3):
                    l[k*group_size+i*part_size:k*group_size+(i+1)*part_size] = ll[i*part_size:(i+1)*part_size]
                else:
                    ii = 1
                    if (i == 1):
                        ii = 2
                    l[k*group_size+i*part_size:k*group_size+(i+1)*part_size] = ll[ii*part_size:(ii+1)*part_size]

        # recursion
        network_whole_group(l, R, PSI, group_size//R,use_bu)

        if (cond1):
            for k in range(group_cnt):
                ll = copy.deepcopy(l[k*group_size:(k+1)*group_size])
                for i in range(R**2):
                    # TODO : do this for R!=2
                    if (i==0 or i==3):
                        l[k*group_size+i*part_size:k*group_size+(i+1)*part_size] = ll[i*part_size:(i+1)*part_size]
                    else:
                        ii = 1
                        if (i == 1):
                            ii = 2
                        l[k*group_size+i*part_size:k*group_size+(i+1)*part_size] = ll[ii*part_size:(ii+1)*part_size]


def network_part_group(l, R, PSI,group_size):
    """
    l is a list containing the output of the BUs.
    This function reoders the data for the next stage.
    len(l) < group_size
    """

    # group_size is a power of R
    size_w = int(log(group_size, R))
    if (R**size_w != group_size):
        sys.exit("ERROR> network group_size ({:0d}) should be a power of R ({:0d}".format(group_size,R))
    if (group_size < R*PSI):
        sys.exit("ERROR> group_size {:0d} is less or equal to the size of l ({:0d}).".format(group_size, R*PSI))
    if (len(l) != R*PSI):
        sys.exit("ERROR> Wrong l size {:0d}. Should be R*PSI {:0d}x{:0d}".format(len(l),R,PSI))

    # Do nothing
    

# ==============================================================================
# reference
# ==============================================================================
def reference(ref_l, dest_l, ram_l):
    """
    Fill the lists with the reference values.
    """

    step = 0
    for stg in range(S-1): 
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
            node_id_0 = pseudo_reverse_order(node_idx_0, R, S-1, step)
            
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
                node_id = pseudo_reverse_order(node_idx, R, S-1, step)

                next_node_id_0 = (node_id << R_W) & NODE_ID_MASK
                for r in range(R):
                    ref_l[-1][-1][-1].append([])
                    next_node_id = next_node_id_0 | r
                    next_r = ((node_idx * R + r) % group_size) // (group_size//R)
                    next_p = next_node_id >> (STG_ITER_W * R_W)
                    next_stg_iter = next_node_id & STG_ITER_MASK
                    next_stg_iter = pseudo_reverse_order(next_stg_iter, R, STG_ITER_W, 0)

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
                        #rev_p = pseudo_reverse_order(next_p, R, PSI_W, 0)
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
    for stg in range(S-1):
        if (VERBOSE):
            print("#==============================")
            print("# stg={:0d} delta={:0d}".format(stg, delta))
            print("#==============================")

        #== Current delta characteristics
        group_size = R**(delta + 2)
        group_nb   = (PSI*R) // group_size
        total_group_nb = N // group_size
        group_bu   = group_size // R # also = group_pos_occurence
        stg_iter_nb_per_group = STG_ITER_NB // total_group_nb
        stg_iter_nb_per_bu_pos = STG_ITER_NB // (PSI*R)
        next_delta = delta + 1
        pos_nb     = R
        if (group_nb == 0):
            pos_nb = (PSI*R) // group_bu
            if (pos_nb == 0):
                pos_nb = 1 # at least 1 position


        if (VERBOSE):
            print("#==")
            print("# group_size={:0d} group_nb={:0d} group_bu={:0d} pos_nb={:0d} total_group_nb={:0d}".format(group_size, group_nb, group_bu, pos_nb, total_group_nb))
            print("# stg_iter_nb_per_group={:0d} stg_iter_nb_per_bu_pos={:0d}".format(stg_iter_nb_per_group,stg_iter_nb_per_bu_pos))
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
        #== Write
        for stg_iter in range(STG_ITER_NB):
            if (VERBOSE):
                print("## Proc WR stg_iter={:d}".format(stg_iter))
            # input
            in_l = []
            for p in range(PSI):
                node_idx = stg_iter*PSI+p
                node_id = pseudo_reverse_order(node_idx, R, S-1, delta)
                next_node_id = (node_id << R_W) & NODE_ID_MASK
                next_stg_iter_ofs = next_node_id & STG_ITER_MASK
                for r in range(R):
                    next_stg_iter_tmp = next_stg_iter_ofs | r;
                    next_stg_iter     = pseudo_reverse_order(next_stg_iter_tmp, R, STG_ITER_W, 0)
                    in_l.append({"org":{"p" : p, "r" : r, "stg_iter" : stg_iter},
                                 "next_stg_iter":next_stg_iter})

            if (pos_nb > 1):
                network_whole_group(in_l, R, PSI, group_size,False)
            else:
                network_part_group(in_l, R, PSI, group_size)
                network_whole_group(in_l, R, PSI, PSI*R,False)

            if (VERBOSE):
                print("#---------")
                for p in range(PSI):
                    for r in range(R):
                        print("wr_ntw_l[{:0d}][{:0d}] = {:s}".format(p,r,str(in_l[p*R+r])))
            
            # Rot R
            # To place according to pos_id
            if (pos_nb == 1):
                pos_id = ((stg_iter*PSI*R) // group_bu) % R
                if ((stg_iter_nb_per_group > PSI*R) and (stg_iter_nb_per_group > stg_iter_nb_per_bu_pos*R)): # consecutive BU are generated + overflow
                    cons_nb = stg_iter_nb_per_group // (stg_iter_nb_per_bu_pos*R)
                    pos_id = (stg_iter // (stg_iter_nb_per_bu_pos * cons_nb)) % R
                    print("# cons_nb={:0d}".format(cons_nb))
                rot_r_factor = pos_id
                #iter_ofs = (group_size // R) // (R*PSI)
                #rot_r_factor = (stg_iter // iter_ofs) % R

                if (VERBOSE):
                    print("# wr_rot_r_factor={:0d}".format(rot_r_factor))
                for p in range(PSI):
                    in_l[p*R:(p+1)*R] = [in_l[p*R+(r-rot_r_factor)%R] for r in range(R)]
                
            if (VERBOSE):
                print("#---------")
                for p in range(PSI):
                    for r in range(R):
                        print("wr_rotr_l[{:0d}][{:0d}] = {:s}".format(p,r,str(in_l[p*R+r])))


            # Rot BU
            # to place the first BU at the correct location
            if (pos_nb == 1):
                pos_iter_nb = group_size // (PSI*R)
                rot_bu_factor = stg_iter // pos_iter_nb
                rot_bu_factor = pseudo_reverse_order(rot_bu_factor,R,PSI_W,0)
                if ((stg_iter_nb_per_group > PSI*R) and (stg_iter_nb_per_group > stg_iter_nb_per_bu_pos*R)): # consecutive BU are generated + overflow
                    cons_nb = stg_iter_nb_per_group // (stg_iter_nb_per_bu_pos*R)
                    iter_pos_id = stg_iter // stg_iter_nb_per_bu_pos
                    rot_bu_factor = iter_pos_id % cons_nb + (iter_pos_id // (cons_nb*R)) * cons_nb
                    print("# cons_nb={:0d} iter_pos_id={:0d}".format(cons_nb,iter_pos_id))
            else :
                pos_iter_nb = PSI // group_bu
                rot_bu_factor = (stg_iter * pos_iter_nb)%PSI
                rot_bu_factor = pseudo_reverse_order(rot_bu_factor,R,PSI_W,0)
            
            if (VERBOSE):
                print("# wr_rot_bu_factor={:0d}".format(rot_bu_factor))
            in_l = [in_l[((p-rot_bu_factor)%PSI)*R+r] for p in range(PSI) for r in range(R)]

            if (VERBOSE):
                print("#---------")
                for p in range(PSI):
                    for r in range(R):
                        print("wr_rotb_l[{:0d}][{:0d}] = {:s}".format(p,r,str(in_l[p*R+r])))

            for p in range(PSI):
                for r in range(R):
                    buf_l[p][r][in_l[p*R+r]["next_stg_iter"]] = in_l[p*R+r]

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
            # Rot BU
            if (pos_nb > 1):
                stg_iter_ofs = (N // group_size) // PSI
                rot_bu_factor = next_stg_iter // stg_iter_ofs
                print("# stg_iter_ofs={:0d} rot_bu_factor={:0d}".format(stg_iter_ofs,rot_bu_factor))
            else:
                stg_iter_ofs  = ((N // (PSI*R)) // PSI)
                rot_bu_factor = next_stg_iter // stg_iter_ofs
                
                print("# stg_iter_ofs={:0d} rot_bu_factor={:0d}".format(stg_iter_ofs,rot_bu_factor))
            rd_l = [rd_l[(p+rot_bu_factor)%PSI * R + r] for p in range(PSI) for r in range(R)]

            if (VERBOSE):
                print("#---------")
                for p in range(PSI):
                    for r in range(R):
                        print("rd_rotb_l[{:0d}][{:0d}] = {:s}".format(p,r,str(rd_l[p*R+r])))

            # Rot R
            if (pos_nb == 1):
                iter_ofs = ((N // (PSI*R*R)) // PSI)
                if (iter_ofs == 0): # TOREVIEW
                    iter_ofs = 1
                print(">>>"+str(iter_ofs))
                rot_r_factor = (next_stg_iter // iter_ofs) % R

                for p in range(PSI):
                    rd_l[p*R:(p+1)*R] = [rd_l[p*R+(r+rot_r_factor)%R] for r in range(R)]

            if (VERBOSE):
                print("#---------")
                for p in range(PSI):
                    for r in range(R):
                        print("rd_rotr_l[{:0d}][{:0d}] = {:s}".format(p,r,str(rd_l[p*R+r])))
 
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

        #== Increase delta
        delta = delta + 1
        if (delta >= DELTA):
            delta = 0;
