#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# This code tests the network architecture proposed for the NTT.
# The idea is to check that the network works.
# It assumes that the NTT core (called butterfly unit, here BU) is a function with a list of
# R elements as input and a list of R elements as output.
# INTL_L different types of data are processed interleaved.
# After each NTT pass, a post-process is applied on the data.
# Note the post-process function depends on the pass.
# At the end of the first pass, the post-process is assumed to reduce the number of interleaved
# elements from INTL_L to GLWE_K+1.
# The second pass post-process is a point-wise operation.
# ==============================================================================================

import sys  # manage errors
import argparse  # parse input argument
from math import log, pow, ceil
import copy
import itertools  # product
from ntt_coord import *
from ntt_lib import *

# ==============================================================================
# Global variables
# ==============================================================================
VERBOSE = False
RD = 1
WR = 0

# ==============================================================================
# bu_core
# ==============================================================================
def bu_core(in_l, R, bu_coord):
    """
    Modelize a radix-R BU.
    Input
    - in_l : a list of R elements to processed
    - R : radix
    - bu_coord : Core identifier within the NTT process
    Output
    - out_l : a list of R elements.

    Here, instead of doing the NTT radix calculation, coordinate checks are done.
    This function generates the coordinates of a radix output.
    """
    # Check number of inputs
    if len(in_l) != R:
        sys.exit("ERROR> Wrong number of inputs")

    # Check input
    # - Belong to current BU
    # - Have same type
    ref_type_s = in_l[0].type_s
    for i, in_coord in enumerate(in_l):
        if not (NttCoord.belong_to(bu_coord, in_coord)):
            sys.exit(
                "ERROR> Point does not belong to the BU. point:{:s}, BU:{:s}".format(
                    str(in_coord), str(bu_coord)
                )
            )
        # Check point position
        if i != in_coord.get_point_position("in"):
            sys.exit(
                "ERROR> Wrong point position. exp={:d} seen={:d}, point:{:s}, BU:{:s}\
                     ".format(
                    i, in_coord.get_point_position("in"), str(in_coord), str(bu_coord)
                )
            )
        # Check type
        if in_coord.type_s != ref_type_s:
            sys.exit(
                "ERROR> Wrong type. exp={:s} seen={:d}, point:{:s}, BU:{:s}".format(
                    ref_type_s, in_coord
                ),
                str(in_coord),
                str(bu_coord),
            )

    # Generate output
    # keep input element type
    out_l = []
    for i in range(0, R):
        out_l.append(bu_coord.create_output(i, ref_type_s))

    return out_l


# ==============================================================================
# post_proc
# ==============================================================================
def post_proc(point_coord, R, S, GLWE_K_plus_1, stg_iter, ntt_bwd):
    """
    Modelize a post process on a point.
    Input:
    - point_coord : a point coordinate
    - R           : radix
    - S           : total number of stages
    - GLWE_K_plus_1 : Number of outputs per input when ntt_bwd == 0
    - stg_iter    : current stage iteration
    - ntt_bwd     : current type of NTT process
    Output:
    - When ntt_bwd = 0: a list of GLWE_K_plus_1 point coordinates
    - When ntt_bwd = 1: a list of 1 point coordinates

    Here, this function "rewinds" the coordinate to prepare it for the next process input.
    """
    if point_coord.stage != -1:
        sys.exit("ERROR> Not last stage output coordinate !")

    out_coord = copy.copy(point_coord)
    # Set stage
    out_coord.stage = S - 1
    # Reset coordinates
    out_coord.coord = reverse_order(out_coord.coord, R, S)

    if ntt_bwd == 0:
        out_nb = GLWE_K_plus_1
    else:
        out_nb = 1

    out_l = []

    if ntt_bwd == 0:
        for i in range(0, out_nb):
            out_l.append(copy.copy(out_coord))
            out_l[-1].type_s = point_coord.type_s | set(["INTT", "PP{:d}".format(i)])
            # remove 'NTT'
            try:
                out_l[-1].type_s.remove("NTT")
            except KeyError:
                sys.exit("ERROR> Wrong data type. Expected data from NTT.")
    else:
        out_l.append(out_coord)
        out_l[-1].type_s = point_coord.type_s | set(["DONE"])
        # Remove 'INTT'
        try:
            out_l[0].type_s.remove("INTT")
        except KeyError:
            sys.exit("ERROR> Wrong data type. Expected data from INTT.")
    return out_l


# ==============================================================================
# pass_dispatch_rot_div
# ==============================================================================
def dispatch_rot_shift(R, S, PSI):
    """
    # We notice that, if we name last_stg_bu_id, the ID of the BU in the last stage,
    # all its output are destinated to a single dest_stg_bu_id = reverse_order(last_stg_bu_id,R,S-1).
    # By definition : dest_stg_bu_id = {dest_stg_iter[stg_iter_w-1:0], dest_cl_bu_id[psi_w-1:0]}
    #
    # During the last stage, it occurs that within a stage iterations several BU have their
    # output destinated to the same destination BU, and so the same RAM.
    # Therefore a rotation on BU basis has to be done, so that the writing can be done in a
    # single clock.
    #
    # This function is used in the last write stage, or in the first read stage.
    # It computes the shift value to be applied on the following index : dest_stg_bu_id,
    # in order to retrieve the MSBs. These MSBs are the rotation factor value to applied.
    # The index is the following index :
    # (where in [] are the bits)
    # This index has r_w * (S-1) bits.
    #
    # The number of MSB bits that defines the rotation faction depends on the size
    # of PSI.
    #
    # It also computes an increment inc to complete the rotation factor. Indeed,
    # it could occur that that several contiguous next stage BU inputs are present in the
    # stage iteration. In this case, the spatial dispersion has to take this into account.
    """
    # Number of bits of ...
    # Number of bits of R
    r_w = int(log(R, 2))
    # Number of bits of PSI
    psi_w = int(log(PSI, 2))
    # Number of bits of psi_w rounded to an entire number of r_w bits
    psi_w_round_up = (psi_w + r_w - 1) // r_w * r_w

    # In the index some bits expressed the next_cl_bu_id. Somes bits corresponding to the current
    # cl_bu_id toggles.
    # Look if these bits overlap.
    overlap = r_w * (S - 1) - 2 * psi_w_round_up

    if overlap >= 0:
        # No overlap
        # Target only 1 destination BU.
        # During a stage iteration, every next stage iteration inputs for this destination BU
        # are available.
        rot_shift = r_w * (S - 1) - psi_w_round_up
    else:  # (overlap < 0)
        # Some digits are overlapping
        rot_shift = psi_w_round_up

    if psi_w_round_up == r_w * (S - 1):
        # There are consecutive next stage cluster BU inputs among the current stage iteration output.
        inc = int(2 ** (psi_w % r_w))
    else:
        inc = 0

    if VERBOSE:
        print(
            "DEBUG> last_stage rot: overlap={:d} shift={:d} inc = {:d}".format(
                overlap, rot_shift, inc
            )
        )

    return (rot_shift, inc)


# ==============================================================================
# ram_access_parity
# ==============================================================================
def ram_access_parity(S, stg, ntt_bwd, rwb):
    """
    Gives the parity of the RAM: where to access, according to current stage, pass, and
    direction :"rd" or "wr".
    Input:
    - S         : total number of stages
    - stg       : current stage
    - ntt_bwd   : current type of NTT process
    - rwb       : (1) read, (0) write
    """

    if rwb == 1:  # Read
        offset = 1
    else:  # Write
        offset = 0

    if ntt_bwd == 0:
        parity = (stg + offset) % 2
    else:  # During the last stage of previous pass, the data have been written in 0
        # Therefore, this fix the reading parity for the 2nd pass
        parity = (S - 1 - stg + 1 + offset) % 2

    return parity


# ==============================================================================
# ram_read
# ==============================================================================
def ram_read(RAM, R, S, PSI, stg, stg_iter, intl_idx, ntt_bwd):
    """
    Input:
    - RAM       : list where to read
    - R         : radix
    - S         : total number of stages
    - PSI       : number of BU that process in parallel
    - stg       : current stage
    - stg_iter  : current stage iteration
    - intl_idx  : current data type
    - ntt_bwd   : current type of NTT process
    Outputs a list of PSI*R elements, that corresponds to the input of the BU-cluster.
    RAM[<cl_bu_id>][<ram_id> 0..R-1][<parity> 0,1][<level>][<address>]

    If the current stage is the first one, that means that the current pass follows a previous one.
    Therefore some data rotation on core basis is needed to retrieve the data.
    """

    # if (VERBOSE):
    #    print("DEBUG> RD : RAM : {:s}".format(str(RAM)))
    stg_bu_nb = int(pow(R, S - 1))
    wr_in_nb = (PSI * R + (stg_bu_nb - 1)) // stg_bu_nb

    in_l = []
    rd_parity = ram_access_parity(S, stg, ntt_bwd, RD)

    # Rotation
    for cl_bu_id in range(0, PSI):
        l = []
        for i in range(0, R):
            l.append(RAM[cl_bu_id][i][rd_parity][intl_idx][stg_iter])
        if stg != S - 1:  # Not first stage
            # Rotation on data basis within each BU input elements
            # Rotate back
            l = [l[(stg_iter * wr_in_nb + i) % R] for i in range(0, R)]
            if VERBOSE:
                print(
                    "DEBUG> RD (stg_iter:{:d}, cl_bu_id:{:d}) [0]={:d}".format(
                        stg_iter, cl_bu_id, (stg_iter * wr_in_nb) % R
                    )
                )
        in_l = in_l + l

    # Dispatch
    if stg == S - 1:  # First stage
        psi_w = int(log(PSI, 2))
        idx = stg_iter << psi_w
        (rot_shift, inc) = dispatch_rot_shift(R, S, PSI)
        rot_factor = ((idx >> rot_shift) + stg_iter * inc) % PSI
        in_l = [
            in_l[(rot_factor + cl_bu_id) % PSI * R + i]
            for cl_bu_id, i in itertools.product(range(0, PSI), range(0, R))
        ]

    return in_l


# ==============================================================================
# ram_write
# ==============================================================================
def ram_write(out_l, RAM, R, S, PSI, stg, stg_iter, intl_idx, ntt_bwd):
    """
    Input:
    - out_l     : list of data to be written
    - R         : radix
    - S         : total number of stages
    - PSI       : number of radix cores that process in parallel
    - stg       : current stage
    - stg_iter  : current stage iteration
    - intl_idx  : current data source
    - ntt_bwd   : current type of NTT process
    Writes the PSI*R elements from out_l, that corresponds to the outputs of the BU-cluster.
    RAM[<cl_bu_id>][<ram_id> 0..R-1][<parity> 0,1][<level>][<address>]

    During the last stage the writing order is different. We prepare the data for the
    next process reading, i.e. reorder as the input order, up to one core-rotation.

    A stage contains R^(S-1) BU operations.
    During 1 stage iteration (stg_iter), PSI cores are working in parallel.
    if stage is not the last stage (stg!= 0):
      Stage-BUs with ID from b*R^(S-2) to (b+1)*R^(S-2)-1 are all outputting next stage input
      position <b>.
      Within this set of R^(S-2) * R outputs, output <i> is targetting stage-BU #<i>.

      Therefore at stage iteration stg_iter, we are computing the next stage input position:
      (stg_iter * PSI)/(R^(S-2)).
      The outputs are destinated to the next stage BU (PSI*R), ID starting at :
      ((stg_iter * PSI * R) % (R^(S-2))).
      The outputs are destinated to the next stage iterations starting at :
      ((stg_iter * PSI * R) % (R^(S-2))) / PSI.
      Considering the RAM organization, a rotation on data basis, for a spatial dispatch over the
      RAMs is necessary to enable the writing of all the data at once. (Note that a rotation
      "back" will be done at the reading.
      The dispatch is used to ease the connection to the RAMs.
    if stage is the last one (stg_iter==0): We have to reorder such that 2 NTT processing
      can be chained.
      The output data of the last iteration are ordered in reverse order :
      reverse_order(stg_iter*PSI*R+cl_bu_id*R+i,R,S).
      Note that the output of a single BU are already in the correct order for the input of the
      next pass.
      This means that the reorder has to be done on BU level.
      Let's name psi such as : psi = ceil(log(PSI,R))
      * For psi < S/2: all the outputs are destinated to the same processing BU.
        Considering the RAM organization, a rotation on a BU basis is necessary, for the spatial
        repartition.
        A backward rotation on BU level will be done while reading.
      * For PSI >= S/2: Several destination BU ID are concerned.
    """
    stg_bu_nb = int(pow(R, S - 1))
    wr_in_nb = (PSI * R + (stg_bu_nb - 1)) // stg_bu_nb
    stg_iter_nb = stg_bu_nb // PSI

    ### Dispatch
    if stg > 0:  # Not last stage
        # Dispatch the output. Order in cluster BU basis.
        dispatch_l = [out_l[i] for i in inc_stride(R * PSI, PSI)]
        # If several input positions are produced within a stage iteration,
        # interleave the positions.
        if stg_bu_nb < (PSI * R):
            d_l = []
            for cl_bu_id in range(0, PSI):
                d_l = d_l + [
                    dispatch_l[cl_bu_id * R + i] for i in inc_stride(R, stg_iter_nb)
                ]
            dispatch_l = d_l

        if VERBOSE:
            print("DEBUG> WR Dispatch:")
            for cc in dispatch_l:
                print("\t{:s}".format(str(cc)))

    else:  # Last stage
        # All BUs output for the same cl_bu_id in next stage.
        # Therefore we need to distribute them spatially in the PSI RAMs, according to the
        # stage iteration value.
        # stg_bu_id of the first cluster-BU of the cluster.
        stg_bu_id_0 = stg_iter * PSI
        (rot_shift, inc) = dispatch_rot_shift(R, S, PSI)

        next_stg_iter_l = []
        rot_factor_l = []
        ram_cl_bu_id_l = []
        for cl_bu_id in range(0, PSI):  # Compute RAM ID and address
            rev_idx = reverse_order(stg_bu_id_0 + cl_bu_id, R, S - 1)

            next_stg_iter, next_cl_bu_id = divmod(rev_idx, PSI)

            rot_factor = ((rev_idx >> rot_shift) + next_stg_iter * inc) % PSI
            ram_cl_bu_id = (next_cl_bu_id + rot_factor) % PSI
            if VERBOSE:
                print(
                    "DEBUG> WR - last_stage : cl_bu_id={:2d} rev(cl_bu_id_0+cl_bu_id)={:4d} next_stg_iter={:2d} next_cl_bu_id={:3d} rot={:2d} ram_cl_bu_id={:2d}".format(
                        cl_bu_id,
                        rev_idx,
                        next_stg_iter,
                        next_cl_bu_id,
                        rot_factor,
                        ram_cl_bu_id,
                    )
                )

            next_stg_iter_l.append(next_stg_iter)
            rot_factor_l.append(rot_factor)
            ram_cl_bu_id_l.append(ram_cl_bu_id)

        # Check that all destination core IDs are different. If not, this means writing conflict.
        s = set(ram_cl_bu_id_l)
        if len(s) != PSI:
            sys.exit("ERROR> Write conflict in same cl_bu_id RAM")

        # Rotate data and addresses on BU basis
        rot_ll = []
        add_l = [-1] * PSI

        for cl_bu_id in range(0, PSI):
            rot_ll.append([])
            for i in range(0, R):
                rot_ll[-1].append(-1)  # Initialize

        for cl_bu_id in range(0, PSI):
            rot_ll[ram_cl_bu_id_l[cl_bu_id]] = out_l[
                cl_bu_id * R : cl_bu_id * R + R
            ]
            add_l[ram_cl_bu_id_l[cl_bu_id]] = next_stg_iter_l[cl_bu_id]
        add_ll = []
        for cl_bu_id in range(0, PSI):
            add_ll.append([add_l[cl_bu_id]] * R)

    ### Data rotation
    if stg > 0:  # Not last stage
        add_ll = []
        rot_ll = []
        next_bu_in_idx_0 = int((stg_iter * PSI) / int(pow(R, (S - 2))))
        next_stg_bu_id_0 = (stg_iter * PSI * R) % int(pow(R, (S - 1)))
        next_stg_iter_0 = int(next_stg_bu_id_0 / PSI)

        if VERBOSE:
            print(
                "DEBUG> WR : next_stg_bu_id_0:{:d}, next_bu_in_idx_0:{:d}".format(
                    next_stg_bu_id_0, next_bu_in_idx_0
                )
            )

        # Rotate address
        add_l = []
        for i in range(0, R):
            add_l.append(next_stg_iter_0 + i // wr_in_nb)
        add_l = [add_l[((i + R - next_bu_in_idx_0) % R)] for i in range(0, R)]

        for cl_bu_id in range(0, PSI):
            add_ll.append(add_l)

        for cl_bu_id in range(0, PSI):
            # Do the rotation on data basis
            # Rotate the output to write in the correct RAM : rotate to the MSB by next_bu_in_idx_0 positions.
            rot_l = [
                dispatch_l[(cl_bu_id * R) + ((i + R - next_bu_in_idx_0) % R)]
                for i in range(0, R)
            ]
            if VERBOSE:
                print(
                    "DEBUG> WR : rot(cl_bu_id:{:d}) wr_in_nb={:d} next_bu_in_idx_0={:d} [0]=({:d}+{:d})".format(
                        cl_bu_id,
                        wr_in_nb,
                        next_bu_in_idx_0,
                        (cl_bu_id * R),
                        ((R - next_bu_in_idx_0) % R),
                    )
                )

            rot_ll.append(rot_l)
    else:  # Last stage
        # Do nothing
        None

    # Write in RAM
    wr_parity = ram_access_parity(S, stg, ntt_bwd, WR)
    for cl_bu_id in range(0, PSI):
        for i, d in enumerate(rot_ll[cl_bu_id]):
            if VERBOSE:
                print(
                    "DEBUG> WR cl_bu_id={:d} i={:d} parity={:d} intl_idx={:d} add={:d} : {:s}".format(
                        cl_bu_id, i, wr_parity, intl_idx, add_ll[cl_bu_id][i], str(d)
                    )
                )
            RAM[cl_bu_id][i][wr_parity][intl_idx][add_ll[cl_bu_id][i]] = d


# ==============================================================================
# ntt_network
# ==============================================================================
def ntt_network(
    RAM, R, S, PSI, GLWE_K_plus_1, PBS_L, ntt_bwd, in0_l, ntt_core, post_proc
):
    """
    Modelize the NTT network.
    Inputs:
    - RAM[<cl_bu_id>][<ram_id> 0..R-1][<parity> 0,1][<level>][<address>] : where intermediate
    data are stored
    - R             : Radix
    - S             : Total number of stages
    - PSI           : Number of BU that work in parallel
    - GLWE_K_plus_1 : Number of interleaved GLWE polynomials
    - PBS_L         : Number of interleaved decomposition levels
    - ntt_bwd       : current type of NTT process
    - in0_l         : GLWE_K_plus_1 * PBS_L *  R^S elements to process.
                      in0_l[GLWE_K+1][PBS_L][R^S]
    - ntt_core      : NTT core function with this format, ntt_core(in_l, R, block_coord)
      where in_l is a list of R elements (see bu_core)
    - post_proc     : post process with this format :
      post_proc(point_coord, R, S, GLWE_K_plus_1, stg_iter, ntt_bwd)
    Output:
    - a list of R^S elements
    """

    COEF_NB = int(pow(R, S))
    INTL_LVL = GLWE_K_plus_1 * PBS_L
    if ntt_bwd == 0:
        MAX_PBS_L = PBS_L
    else:
        MAX_PBS_L = 1

    for stg in range(S - 1, -1, -1):  # For each stage. Stages are reverse numbered.
        if VERBOSE:
            print(
                "DEBUG>============ Pass {:d}, Stage {:d} ================".format(
                    ntt_bwd, stg
                )
            )

        s_out_l = []
        for lvl in range(0, INTL_LVL):
            s_out_l.append([])

        for stg_iter in range(0, COEF_NB // (R * PSI)):
            PPROC_REG = []
            for g in range(0, GLWE_K_plus_1):
                PPROC_REG.append([])
                for i in range(0, R * PSI):
                    PPROC_REG[-1].append(0)  # Initialized to 0
            if VERBOSE:
                print("DEBUG>++++ Stage iteration {:d} ++++".format(stg_iter))
            for glwe_idx in range(0, GLWE_K_plus_1):
                for dec_lvl in range(0, MAX_PBS_L):
                    if VERBOSE:
                        print(
                            "DEBUG>-- glwe_id {:d} dec_lvl {:d}--".format(
                                glwe_idx, dec_lvl
                            )
                        )
                    out_l = []
                    lvl = glwe_idx * PBS_L + dec_lvl

                    if (stg == S - 1) and (ntt_bwd == 0):
                        in_l = in0_l[glwe_idx][dec_lvl][
                            stg_iter * R * PSI : stg_iter * R * PSI + R * PSI
                        ]
                    else:
                        in_l = ram_read(RAM, R, S, PSI, stg, stg_iter, lvl, ntt_bwd)

                    for cl_bu_id in range(0, PSI):
                        out_l = out_l + ntt_core(
                            in_l[cl_bu_id * R : cl_bu_id * R + R],
                            R,
                            NttCoord(stg, S - 1, stg_iter * PSI + cl_bu_id, R),
                        )
                        if VERBOSE:
                            print("DEBUG> in{:d}  :".format(stg_iter * PSI + cl_bu_id))
                            for cc in in_l[cl_bu_id * R : cl_bu_id * R + R]:
                                print("\t{:s}".format(str(cc)))
                            print("DEBUG> out{:d} :".format(stg_iter * PSI + cl_bu_id))
                            for cc in out_l[-R:]:
                                print("\t{:s}".format(str(cc)))

                    s_out_l[lvl] = s_out_l[lvl] + out_l

                    # Post-process
                    if stg == 0:  # Last stage
                        for i in range(0, R * PSI):
                            pp_l = post_proc(
                                out_l[i], R, S, GLWE_K_plus_1, stg_iter, ntt_bwd
                            )

                            if ntt_bwd == 0:  # Accumulate
                                for g, c in enumerate(pp_l):
                                    try:
                                        PPROC_REG[g][i] = PPROC_REG[g][i] + c
                                    except TypeError:
                                        PPROC_REG[g][i] = c
                            else:
                                out_l[i] = pp_l[0]
                    # Write in RAM
                    if not (stg == 0 and ntt_bwd == 0):
                        ram_write(out_l, RAM, R, S, PSI, stg, stg_iter, lvl, ntt_bwd)

            # Write in RAM once all interleaved levels have been received.
            if stg == 0 and ntt_bwd == 0:
                for g in range(0, GLWE_K_plus_1):
                    ram_write(PPROC_REG[g], RAM, R, S, PSI, stg, stg_iter, g, ntt_bwd)

    return s_out_l


# ==============================================================================
# Main
# ==============================================================================
if __name__ == "__main__":

    R = 8  # Radix
    PSI = 2  # Number of radix-R blocks used in parallel
    S = 3  # R^S = N the number of coefficients to be processed by the NTT
    PBS_L = 2  # Total number of decomposition levels
    GLWE_K_plus_1 = 3  # Number of polynomials in GLWE + 1

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
        "-l", dest="level_nb", type=int, help="Total number of levels", default=PBS_L
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
        "-g",
        dest="poly_nb",
        type=int,
        help="Number of polynomials",
        default=GLWE_K_plus_1,
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
    PBS_L = args.level_nb
    GLWE_K_plus_1 = args.poly_nb
    VERBOSE = args.verbose

    # Check parameters
    if pow(2, int(log(R, 2))) != R:
        sys.exit("ERROR> R must be a power of 2")
    if S < 2:
        sys.exit("ERROR> S must be > 1 (S=1, no network needed)")
    if (int(pow(R, S - 1)) % PSI) != 0:
        sys.exit("ERROR> Only supports PSI that divides R^(S-1)")
    # if log(PSI, R) >= S / 2:
    #    sys.exit("ERROR> Only supports PSI < R^(S/2) (TODO)")
    # ==============================================================================
    # RAMs for intermediate values
    # ==============================================================================
    # RAM[<cl_bu_id>][<ram_id> 0..R-1][<parity> 0,1][<level>][<address>]
    COEF_NB = int(pow(R, S))
    BU_NB = COEF_NB // R
    STG_ITER_NB = BU_NB // PSI
    RAM = []
    for p in range(0, PSI):  # parallel index
        RAM.append([])
        for i in range(0, R):  # input coefficients
            RAM[-1].append([])
            for i in range(0, 2):  # parity for the ping-pong
                RAM[-1][-1].append([])
                for l in range(0, PBS_L * GLWE_K_plus_1):  # level
                    RAM[-1][-1][-1].append([])
                    for add in range(0, STG_ITER_NB):
                        RAM[-1][-1][-1][-1].append(-1)  # Initilalize with -1 for debug

    # ==============================================================================
    # Build input
    # ==============================================================================
    in0_l = []
    for glwe_idx in range(0, GLWE_K_plus_1):
        in0_l.append([])
        for dec_lvl in range(0, PBS_L):
            in0_l[-1].append([])
            for i in inc_stride(COEF_NB, COEF_NB // R):
                in0_l[-1][-1].append(
                    NttCoord(
                        stage=S - 1,
                        length=S,
                        coord=i,
                        base=R,
                        type_s=set(
                            ["NTT", "D{:d}".format(dec_lvl), "P{:d}".format(glwe_idx)]
                        ),
                    )
                )
    # if VERBOSE:
    #    print("DEBUG> in0_l:\n")
    #    for ii_l in in0_l:
    #        for ii in ii_l:
    #            print("\t{:s}".format(str(ii)))

    for ntt_bwd in range(0, 2):  # First pass for NTT, second pass for INTT
        if ntt_bwd == 0:
            pbs_l = PBS_L
        else:
            pbs_l = 1

        MAX_LVL = pbs_l * GLWE_K_plus_1
        # ==============================================================================
        # Network
        # ==============================================================================
        s_out_l = ntt_network(
            RAM, R, S, PSI, GLWE_K_plus_1, pbs_l, ntt_bwd, in0_l, bu_core, post_proc
        )

        # ==============================================================================
        # Print RAM content for next process
        # ==============================================================================
        if VERBOSE:
            ram_parity = ram_access_parity(S, 0, ntt_bwd, WR)
            for lvl in range(0, MAX_LVL):
                print(
                    "DEBUG>============ Pass {:d} : Level{:d} RAM  ================".format(
                        ntt_bwd, lvl
                    )
                )
                for stg_iter in range(0, STG_ITER_NB):
                    print("DEBUG>+++ stg_iter{:d} RAM +++".format(stg_iter, lvl))
                    for p in range(0, PSI):
                        for coord in range(0, R):
                            print(str(RAM[p][coord][ram_parity][lvl][stg_iter]))

        # ==============================================================================
        # Check output
        # ==============================================================================
        # s_out_l contains the output of the last stage
        for lvl in range(0, MAX_LVL):
            if VERBOSE:
                print(
                    "DEBUG>============ Pass {:d} : Level{:d} Output  ================".format(
                        ntt_bwd, lvl
                    )
                )
            for i, c in enumerate(s_out_l[lvl]):
                if VERBOSE:
                    print("DEBUG> out_l:{:s}".format(str(c)))
                if c.coord != i:
                    sys.exit(
                        "ERROR> Output mismatches (lvl:{:d}). i={:d} exp={:d} seen={:d}".format(
                            lvl, i, reverse_order(i, R, S), c.coord
                        )
                    )
                if ntt_bwd == 1:
                    if not ("INTT" in c.type_s):
                        sys.exit(
                            "ERROR> Final output data before post-process does not contain type 'INTT'. {:s}".format(
                                str(c)
                            )
                        )
                    if not ("PP{:d}".format(lvl) in c.type_s):
                        sys.exit(
                            "ERROR> Final output data before post-process does not have the correct PP<id>. lvl={:d} {:s}".format(
                                lvl, str(c)
                            )
                        )
                    for l in range(0, PBS_L):
                        if not ("D{:d}".format(l) in c.type_s):
                            sys.exit(
                                "ERROR> Final output data before post-process does not have all the D<id>. {:s}".format(
                                    str(c)
                                )
                            )
                    for l in range(0, GLWE_K_plus_1):
                        if not ("P{:d}".format(l) in c.type_s):
                            sys.exit(
                                "ERROR> Final output data before post-process does not have all the P<id>. {:s}".format(
                                    str(c)
                                )
                            )

    # ==============================================================================
    # Final read from RAM + check
    # ==============================================================================
    if VERBOSE:
        print("DEBUG>============ Final output  ================")
    next_in_l = []
    for glwe_idx in range(0, GLWE_K_plus_1):
        next_in_l.append([])
    for stg_iter in range(0, STG_ITER_NB):
        for glwe_idx in range(0, GLWE_K_plus_1):
            next_in_l[glwe_idx] = next_in_l[glwe_idx] + ram_read(
                RAM, R, S, PSI, S - 1, stg_iter, glwe_idx, 0
            )

    for glwe_idx in range(0, GLWE_K_plus_1):
        if VERBOSE:
            print("DEBUG>-- glwe_id {:d}--".format(glwe_idx))
        for i, pos in enumerate(inc_stride(COEF_NB, COEF_NB // R)):
            if next_in_l[glwe_idx][i].coord != pos:
                sys.exit(
                    "ERROR> Final RAM output order. exp={:d} seen={:d}".format(
                        pos, next_in_l[glwe_idx][i].coord
                    )
                )
            if not ("DONE" in next_in_l[glwe_idx][i].type_s):
                sys.exit(
                    "ERROR> Final RAM output does not contain type 'DONE'. {:s}".format(
                        str(next_in_l[glwe_idx][i])
                    )
                )
            if VERBOSE:
                print("DEBUG> [{:3d}] {:s}".format(i, str(next_in_l[glwe_idx][i])))

    print("SUCCEED!")
