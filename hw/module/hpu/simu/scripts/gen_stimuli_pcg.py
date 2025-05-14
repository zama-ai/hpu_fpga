#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# t = __import__("pbs_pbs_{:0d}".format(1))
# ----------------------------------------------------------------------------------------------
#  This script generate dummy input for the bench : tb_ntt_core_with_matrix_multiplication_pipeline
# ==============================================================================================

import os       # OS functions
import sys
import argparse # parse input argument
import random
import fcntl # Used for file-locking and mutual exclusion
from datetime import datetime
import glob # list filename
from math import log
import gen_stimuli as gen

#=====================================================
# Global variables
#=====================================================
PROJECT_DIR = os.getenv("PROJECT_DIR")

#=====================================================
# Parameters : default values
#=====================================================
BSK_SRV_NB          = 3
LWE_K               = 12
BSK_INST_BR_LOOP_NB = [4,4,4]
S                   = 11
PSI                 = 8
R                   = 2
GLWE_K_P1           = 2
PBS_L               = 1
OP_W                = 64
MOD_Q_W             = 64
BSK_COEF_NB         = PSI*R*GLWE_K_P1
BATCH_MAX_PBS       = 10
BATCH_MIN_PBS       = 1
BWD_PSI_DIV         = 1
BATCH_NB            = 2
LWE_ACS_W           = 16
GLWE_RAM_SUBWORD_COEF_NB=512//MOD_Q_W
DELTA               = 6

# TODO properly derived this values from other parameters
AXI4_W              = 512
AXI4_BSK_W          = 512

#=====================================================
# print hex
#=====================================================
def print_hex(l, w):
    '''
    l is a list containing n values of w bit width.
    w is the size in bits of each element of the list.
    This function output the string corresponding to the concatenation of these data.
    In hexa representation 1 character is 4 bits.
    '''

    w_remain  = w % 4;
    n_elt = 1;
    while (((n_elt * w_remain) % 4) != 0):
      n_elt = n_elt + 1
    char_nb = (w * n_elt) // 4


    # If we gather the values n_elt by n_elt, there is an entire number of characters.

    s = ""

    for i in range(0,len(l),n_elt):
        v = 0
        for j in range(0, n_elt):
            try:
                v = v + (l[i+j] << (j*w))
            except IndexError:
                # No more value
                None
        ss = ""
        for j in range(0, char_nb):
            ss = "{:01x}".format(v & 0xF) + ss
            v = v >> 4
        s = ss + s

    return s

#=====================================================
# Reshape a list of value in 2D list.
# Used to easily packed small-word in bigger one
#=====================================================
def reshape_w(TO_W, FROM_W, values):
    assert FROM_W < TO_W, "ERR: Only upscaling in supported"
    assert 0 == (TO_W%FROM_W), "ERR: Only aligned reshaping in supported"

    from itertools import islice
    pack_w = TO_W // FROM_W
    shape_2d = [pack_w for _ in range(len(values)//pack_w)]
    if (0 != (len(values)%pack_w)): # Finish with incomplete word
        shape_2d.append(len(values)%pack_w)

    val_iter = iter(values)
    return [list(islice(val_iter, i)) for i in shape_2d]

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
# inv_pseudo_reverse_order
# ==============================================================================
def inv_pseudo_reverse_order(v, R, S, step):
    """
    For an index v in 0...R^S, if we decompose it in the R-base:
    v = v_0*R^0 + v_1*R^1 + ... v_(S-1)*R^(S-1)
    where v_j is in 0...R-1.
    The inv_pseudo reverse order, at step s, of v in base R, for a number of stages S is:
    inv_pseudo_reverse_order(v) = v_(step)*R^(S-1)+..+v_1*R^(S-(step+1)+1)+v_0*R^(S-(step+1))+v(step+1)*R^(S-1-(step+1))+..+v(S-2)*R^1+v(S-1)*R^0

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

    for i in range(step+1):
        res_l[S-(step+1)+i] = v_l[i]
    for i in range(step+1,S):
        res_l[i-(step+1)] = v_l[S-1-(i-(step+1))]
    res = 0
    for i in range(S):
        res = (res << r_width) + res_l[S-1-i]

    return res

#=====================================================
# get_id
#=====================================================
def get_pos_id(R,S,pos_idx,delta_idx):
    '''
    For a given position idx (in 0..N-1), at stage stg, at processing step delta_idx,
    find the corresponding id.
    Consider the input of the node.
    '''
    node_idx = pos_idx // R
    r_idx = pos_idx % R

    rev_idx = pseudo_reverse_order(node_idx, R, S-1, delta_idx)

    res_idx = rev_idx * R + r_idx
    #print("idx={:0d} rev_idx={:0d} res_idx={:0d}".format(idx,rev_idx, res_idx))

    return res_idx

def get_node_id(R,S,node_idx,delta_idx):
    '''
    For a given position idx (in 0..N-1), at stage stg, at processing step delta_idx,
    find the corresponding id.
    Consider the input of the node.
    '''
    rev_idx = pseudo_reverse_order(node_idx, R, S, delta_idx)

    return rev_idx
#=====================================================
# Generate ntt wmm stimulus -> unscrambled on axi4 width
#=====================================================
def generate_axi4_bsk(AXI4_W, OP_W, tvec_bsk_l,LS_DELTA_IDX, WORK_DIR, filename_prefix="bsk_axi4"):
    '''
    Generate the input writing BSK in DDR
    tvec_bsk_l : contains the BSK
            tvec_bsk_l[br_loop][PBS_L][GLWE_K_P1][GLWE_K_P1][N (rev)]
    Warning : the levels are in inverse order in the tvec.
    '''
    # bsk_if in RTL write in bsk_manager with g_idx as outerloop:
    # -> Write all stg_iter, l_idx, p,r for a given g_idx then incr g_idx.
    # In the following, we order the bsk key accordingly.
    # NB: This &| the rtl should (or not kind of one time task...) be rework based on the bsk ordering in SW.
    bsk_l = []
    for br_loop in range(0, LWE_K):
      for glwe_idx in range(0,GLWE_K_P1):
        for stg_iter in range(0,STG_ITER_NB):
          for g_idx in range(0,GLWE_K_P1):
            for l_idx in range(PBS_L-1, -1, -1): # Inverse order
              for p in range(0,PSI):
                for r in range(0,R):
                  c_idx = stg_iter*(PSI*R)+p*R+r
                  c_id = get_pos_id(R,S,c_idx,LS_DELTA_IDX)
                  bsk_l.append(tvec_bsk_l[br_loop][l_idx][g_idx][glwe_idx][c_id])

    # Reshape to have 2D list based on word width
    bsk_l = reshape_w(AXI4_W, OP_W, bsk_l)

    # Print
    with open(os.path.join(WORK_DIR,"{:s}.dat".format(filename_prefix)), 'w') as f:
        for l in bsk_l:
            d = print_hex(l, OP_W)
            f.write(d + "\n")

def generate_axi4_lwe(AXI4_W, OP_W, batch_pbs_l, batch_id, tvec_data, WORK_DIR, filename_prefix="lwe"):
    '''
    Generate the ciphertext in LWE form without the "b" coefficient.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['input_lwe_2N']
    '''

    gen.generate_axi4_lwe(AXI4_W, OP_W, batch_pbs_l, batch_id, tvec_data, WORK_DIR, filename_prefix)

def generate_axi4_glwe_input(AXI4_W, OP_W, batch_pbs_l, batch_id, tvec_data, WORK_DIR, filename_prefix="glwe_in"):
    '''
    Generate the ciphertext in LWE form without the "b" coefficient.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['lut_glwe']
    '''

    # Flatten nested list
    from itertools import chain

    with open(os.path.join(WORK_DIR,"{:s}_batch{:d}.dat".format(filename_prefix, batch_id)), 'w') as f:
        for pbs_id in batch_pbs_l[batch_id]:
            glwe_l = []
            for l in (tvec_data[pbs_id].pbs['br_loop'][0]['ct0']):
              for c_idx in range(len(l)):
                c_id = get_pos_id(R,S,c_idx,0)
                glwe_l.append(l[c_id])

            #glwe_l = list(chain.from_iterable(tvec_data[pbs_id].pbs['br_loop'][0]['ct0']))
            while (type(glwe_l[0]) == type([])):
                glwe_l = list(chain.from_iterable(glwe_l))

            glwe_l = reshape_w(AXI4_W, OP_W, glwe_l)

            f.write("# pbs_id={:0d}\n".format(pbs_id))
            for l in glwe_l:
                d = print_hex(l, OP_W)
                f.write(d + "\n")

def generate_axi4_glwe_output(AXI4_W, OP_W, batch_pbs_l, batch_id, tvec_data, WORK_DIR, filename_prefix="glwe_out"):
    '''
    Generate the ciphertext in LWE form without the "b" coefficient.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['lut_glwe']
    '''

    # Flatten nested list
    from itertools import chain

    with open(os.path.join(WORK_DIR,"{:s}_batch{:d}.dat".format(filename_prefix, batch_id)), 'w') as f:
        for pbs_id in batch_pbs_l[batch_id]:
            glwe_raw =[d['ct0 + pp_mod_q'] for d in tvec_data[pbs_id].pbs['br_loop'][-1]['pp']]
            glwe_l = []
            for l in (glwe_raw):
              for c_idx in range(len(l)):
                c_id = get_pos_id(R,S,c_idx,0)
                glwe_l.append(l[c_id])

            #glwe_l = list(chain.from_iterable(glwe_raw))
            while (type(glwe_l[0]) == type([])):
                glwe_l = list(chain.from_iterable(glwe_l))

            glwe_l = reshape_w(AXI4_W, OP_W, glwe_l)

            f.write("# pbs_id={:0d}\n".format(pbs_id))
            for l in glwe_l:
                d = print_hex(l, OP_W)
                f.write(d + "\n")

def generate_batch_info(batch_pbs_l, WORK_DIR, filename_prefix="batch_info"):
    '''
    Generate the list of batch size.
    run_edalize seems to don't support array in -P options
    '''
    gen.generate_batch_info(batch_pbs_l, WORK_DIR, filename_prefix)

#=====================================================
# Generate BSK
#=====================================================
def generate_bsk (R,PSI,OP_W,STG_ITER_NB,tvec_bsk_l,BSK_COEF_NB,BSK_INST_BR_LOOP_NB,LS_DELTA_IDX,WORK_DIR,filename_prefix="bsk"):
    '''
    Generate the input for write BSK path
    tvec_bsk_l : contains the BSK
            tvec_bsk_l[br_loop][PBS_L][GLWE_K_P1][GLWE_K_P1][N (rev)]
    Warning : the levels are in inverse order in the tvec.
    '''
    bsk_l = []
    br_loop_ofs = 0
    for srv in range(0,BSK_SRV_NB):
        bsk_l.append([])
        for br_loop in range(br_loop_ofs, br_loop_ofs + BSK_INST_BR_LOOP_NB[srv]):
            for stg_iter in range(0,STG_ITER_NB):
                for g_idx in range(0,GLWE_K_P1):
                    for l_idx in range(PBS_L-1, -1, -1): # Inverse order
                        for p in range(0,PSI):
                            for r in range(0,R):
                                for glwe_idx in range(0,GLWE_K_P1):
                                    val = (p*(R*GLWE_K_P1) + r*GLWE_K_P1 + glwe_idx)
                                    coef_id = val % BSK_COEF_NB
                                    if (coef_id == 0) :
                                        wr_data_l = [0]*BSK_COEF_NB
                                    c_idx = stg_iter*(PSI*R)+p*R+r
                                    c_id = get_pos_id(R,S,c_idx,LS_DELTA_IDX)
                                    wr_data_l[coef_id] = tvec_bsk_l[br_loop][l_idx][g_idx][glwe_idx][c_id]
                                    if (coef_id == BSK_COEF_NB-1) :
                                        bsk_l[-1].append(wr_data_l)

        br_loop_ofs = br_loop_ofs + BSK_INST_BR_LOOP_NB[srv]


    # Print
    for i in range(0,BSK_SRV_NB) :
        with open(os.path.join(WORK_DIR,"{:s}_{:0d}.dat".format(filename_prefix,i)), 'w') as f:
            for l in bsk_l[i]:
                d = print_hex(l, OP_W)
                f.write(d + "\n")


#=====================================================
# Generate twiddle intt final
#=====================================================
def generate_twd_ifnl(R,S,PSI,OP_W,STG_ITER_NB,tvec_twd_ifnl_l,LS_DELTA_IDX,WORK_DIR,filename_prefix="twd_ifnl"):
    '''
    Generate the input for the INTT final stage twiddles.
    tvec_twd_ifnl_l : contains the twiddle intt final
        tvec_twd_ifnl_l[PSI*STG_ITER_NB][R rev]
    '''
    twd_ifnl_l = []
    for stg_iter in range(0,STG_ITER_NB) :
        for p in range (0, PSI):
            c_idx = stg_iter*PSI+p
            c_id = get_node_id(R,S-1,c_idx,LS_DELTA_IDX)
            for r in range(0,R):
                twd_ifnl_l = twd_ifnl_l + [tvec_twd_ifnl_l[c_id][r]]
                #print("twd_ifnl_l > delta_idx={:0d} stg_iter={:0d} p={:0d} r={:0d} c_idx={:0d} c_id={:0d}".format(LS_DELTA_IDX,stg_iter,p,r,c_idx,c_id))

    # Print
    # There are 2 readings per ROM. So there is a total of PSI*R/2 ROMs.
    for p in range(0, PSI):
        for r in range(0,R//2):
            with open(os.path.join(WORK_DIR,"{:s}_{:0d}_{:0d}.mem".format(filename_prefix, p,r)), 'w') as f:
                for i in range(p*R+r*2,len(twd_ifnl_l),PSI*R):
                    for j in range(2):
                        d = print_hex([twd_ifnl_l[i+j]], OP_W)
                        f.write(d + "\n")

#=====================================================
# Generate twiddle phi RU
#=====================================================
def generate_twd_phru_compact(R,S,PSI,OP_W,STG_ITER_NB, tvec_fwd_twd_phru_l,tvec_bwd_twd_phru_l,LPB_NB, RS_DELTA_IDX, LS_DELTA_IDX, DELTA, TWD_PHRU_RD_NB,WORK_DIR,filename_prefix="twd_phru"):
    '''
    Generate the input for the INTT PHI root of unity.
    tvec_fwd/bwd_twd_phru_l[S][N/R][R]
    In tvec the stage are numbered this way : stg=0 : first stage.
    In the RTL stage are numbered this way : stg=0 : last stage
    '''
    tvec_twd_phru_l = []
    tvec_twd_phru_l.append(tvec_fwd_twd_phru_l)
    tvec_twd_phru_l.append(tvec_bwd_twd_phru_l)

    RD_NB = TWD_PHRU_RD_NB*2
    r_tmp = R//RD_NB

    # twd_phru_l[delta][2*LPB_NB*N]
    twd_phru_l = []
    for d in range(DELTA):
        stg = d
        twd_phru_l.append([])
        for ntt_bwd in range (2) :
            stg = d
            for lpb in range (LPB_NB) :
                if ((lpb < LPB_NB-1 and d <= RS_DELTA_IDX) or (lpb == LPB_NB-1 and d <= LS_DELTA_IDX)):
                    #print("delta={:0d} ntt_bwd={:0d} lpb={:0d} stg={:0d}".format(d,ntt_bwd, lpb, stg))
                    for stg_iter in range(STG_ITER_NB) :
                        for p in range(PSI) :
                            c_idx = stg_iter*PSI+p
                            c_id = get_node_id(R,S-1,c_idx,d)
                            for r in range(R) :
                                twd_phru_l[-1] = twd_phru_l[-1] + [tvec_twd_phru_l[ntt_bwd][stg][c_id][r]]
                                #print("twd_phru_l > delta_idx={:0d} ntt_bwd={:0d} lpb={:0d} stg={:0d} stg_iter={:0d} p={:0d} r={:0d} c_idx={:0d} c_id={:0d}".format(d,ntt_bwd,lpb, stg,stg_iter,p,r,c_idx,c_id))
                stg = stg + DELTA

    # Print
    # There are RD_NB readings per ROM. So there is a total of PSI*R/RD_NB ROMs.
    for d_idx in range(DELTA) :
        for p in range(0, PSI):
            for r in range(0,R//RD_NB):
                with open(os.path.join(WORK_DIR,"{:s}_D{:0d}_{:0d}_{:0d}.mem".format(filename_prefix,d_idx,p,r)), 'w') as f:
                    for i in range(p*R+r*RD_NB,len(twd_phru_l[d_idx]),PSI*R):
                        for j in range(RD_NB):
                            d = print_hex([twd_phru_l[d_idx][i+j]], OP_W)
                            f.write(d + "\n")


def generate_twd_phru_unfold(R,S,PSI,BWD_PSI,OP_W,STG_ITER_NB,BWD_STG_ITER_NB,tvec_fwd_twd_phru_l,tvec_bwd_twd_phru_l, LS_DELTA, DELTA, CLBU_NB, TWD_PHRU_RD_NB,WORK_DIR,filename_prefix="twd_phru"):
    '''
    Generate the input for the INTT PHI root of unity.
    tvec_fwd/bwd_twd_phru_l[S][N/R][R]
    In tvec the stage are numbered this way : stg=0 : first stage.
    In the RTL stage are numbered this way : stg=0 : last stage
    '''
    RD_NB = TWD_PHRU_RD_NB*2
    r_tmp = R//RD_NB

    # twd_phru_fwd_l[delta][LPB_NB*N]
    twd_phru_fwd_l = []
    for clbu in range(CLBU_NB):
        twd_phru_fwd_l.append([])
        delta = DELTA
        if (clbu == CLBU_NB-1):
            delta = LS_DELTA
        for d in range(delta):
            stg = clbu*DELTA + d
            twd_phru_fwd_l[-1].append([])
            for stg_iter in range(STG_ITER_NB) :
                for p in range(PSI) :
                    c_idx = stg_iter*PSI+p
                    c_id = get_node_id(R,S-1,c_idx,d)
                    for r in range(R) :
                        twd_phru_fwd_l[-1][-1] = twd_phru_fwd_l[-1][-1] + [tvec_fwd_twd_phru_l[stg][c_id][r]]
                        #print("twd_phru_fwd_l > delta_idx={:0d} lpb={:0d} stg={:0d} stg_iter={:0d} p={:0d} r={:0d} c_idx={:0d} c_id={:0d}".format(d,lpb, stg,stg_iter,p,r,c_idx,c_id))

    # twd_phru_bwd_l[delta][LPB_NB*N]
    twd_phru_bwd_l = []
    for clbu in range(CLBU_NB):
        twd_phru_bwd_l.append([])
        delta = DELTA
        if (clbu == CLBU_NB-1):
            delta = LS_DELTA
        for d in range(delta):
            stg = clbu*DELTA + d
            twd_phru_bwd_l[-1].append([])
            for stg_iter in range(BWD_STG_ITER_NB) :
                for p in range(BWD_PSI) :
                    c_idx = stg_iter*BWD_PSI+p
                    c_id = get_node_id(R,S-1,c_idx,d)
                    for r in range(R) :
                        twd_phru_bwd_l[-1][-1] = twd_phru_bwd_l[-1][-1] + [tvec_bwd_twd_phru_l[stg][c_id][r]]
                        #print("twd_phru_bwd_l > delta_idx={:0d} lpb={:0d} stg={:0d} stg_iter={:0d} p={:0d} r={:0d} c_idx={:0d} c_id={:0d}".format(d,lpb, stg,stg_iter,p,r,c_idx,c_id))

    # Print
    # There are RD_NB readings per ROM. So there is a total of PSI*R/RD_NB ROMs.
    for clbu in range(CLBU_NB):
        delta = DELTA
        if (clbu == CLBU_NB-1):
            delta = LS_DELTA
        for d_idx in range(delta) :
            for p in range(0, PSI):
                for r in range(0,R//RD_NB):
                    with open(os.path.join(WORK_DIR,"{:s}_C{:0d}_D{:0d}_fwd_{:0d}_{:0d}.mem".format(filename_prefix,clbu,d_idx,p,r)), 'w') as f:
                        for i in range(p*R+r*RD_NB,len(twd_phru_fwd_l[clbu][d_idx]),PSI*R):
                            for j in range(RD_NB):
                                d = print_hex([twd_phru_fwd_l[clbu][d_idx][i+j]], OP_W)
                                f.write(d + "\n")

    for clbu in range(CLBU_NB):
        delta = DELTA
        if (clbu == CLBU_NB-1):
            delta = LS_DELTA
        for d_idx in range(delta) :
            for p in range(0, BWD_PSI):
                for r in range(0,R//RD_NB):
                    with open(os.path.join(WORK_DIR,"{:s}_C{:0d}_D{:0d}_bwd_{:0d}_{:0d}.mem".format(filename_prefix,clbu,d_idx,p,r)), 'w') as f:
                        for i in range(p*R+r*RD_NB,len(twd_phru_bwd_l[clbu][d_idx]),BWD_PSI*R):
                            for j in range(RD_NB):
                                d = print_hex([twd_phru_bwd_l[clbu][d_idx][i+j]], OP_W)
                                f.write(d + "\n")


#=====================================================
# Generate twiddle omg ru r pow
#=====================================================
def generate_twd_omg_ru_r_pow(OP_W,tvec_fwd_twd_omg_ru_r_l,tvec_bwd_twd_omg_ru_r_l,WORK_DIR,filename_prefix="twd_omg_ru_r_pow"):
    '''
    Generate the input for the powers of twiddle omega root of unity.
    tvec_fwd_twd_omg_ru_r_l[i] = omg ^ i
    tvec_bwd_twd_omg_ru_r_l[i] = omg ^ -i
    '''
    tvec_twd_omg_ru_r_l = []
    tvec_twd_omg_ru_r_l.append(tvec_fwd_twd_omg_ru_r_l)
    tvec_twd_omg_ru_r_l.append(tvec_bwd_twd_omg_ru_r_l)

    twd_omg_ru_l = tvec_twd_omg_ru_r_l

    # Print
    with open(os.path.join(WORK_DIR,"{:s}.dat".format(filename_prefix)), 'w') as f:
        for l in twd_omg_ru_l:
            d = print_hex(l, OP_W)
            f.write(d + "\n")


#=====================================================
# Generate GRAM input
#=====================================================
def generate_gram_input(STG_ITER_NB,GLWE_K_P1,MOD_Q_W,GLWE_RAM_SUBWORD_COEF_NB,GLWE_RAM_SUBWORD_NB,batch_pbs_l,batch_id,tvec_data,WORK_DIR,filename_prefix="gram_in"):
    '''
    Generate the initial content of the GRAM.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['br_loop'][bl]['ct0'][GLWE_K_P1][N]
    '''
    if (batch_id == 0):
       write_option = 'w'
    else:
       write_option = 'a'

    with open(os.path.join(WORK_DIR,"{:s}.dat".format(filename_prefix)), write_option) as f:
        for pbs_id in batch_pbs_l[batch_id]:
            f.write("# pbs_id={:0d}\n".format(pbs_id))
            for g in range(GLWE_K_P1):
                for stg_iter in range(STG_ITER_NB):
                    for s in range(GLWE_RAM_SUBWORD_NB):
                        l = []
                        for c in range(GLWE_RAM_SUBWORD_COEF_NB):
                            c_idx = stg_iter*GLWE_RAM_SUBWORD_COEF_NB*GLWE_RAM_SUBWORD_NB + s*GLWE_RAM_SUBWORD_COEF_NB + c
                            c_id = get_pos_id(R,S,c_idx,0)
                            l.append(tvec_data[pbs_id].pbs['br_loop'][0]['ct0'][g][c_id])
                        d = print_hex(l, MOD_Q_W)
                        f.write(d + "\n")


#=====================================================
# Generate GRAM output
#=====================================================
def generate_gram_output(STG_ITER_NB,GLWE_K_P1,MOD_Q_W,GLWE_RAM_SUBWORD_COEF_NB,GLWE_RAM_SUBWORD_NB,batch_pbs_l,batch_id,br_loop_nb,tvec_data,WORK_DIR,filename_prefix="gram_out"):
    '''
    Generate the initial content of the GRAM.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['br_loop'][bl]['pp'][GLWE_K_P1]['ct0 + pp_mod_q'][N]
    '''

    if (batch_id == 0):
       write_option = 'w'
    else:
       write_option = 'a'

    with open(os.path.join(WORK_DIR,"{:s}.dat".format(filename_prefix)), write_option) as f:
        for pbs_id in batch_pbs_l[batch_id]:
            f.write("# pbs_id={:0d}\n".format(pbs_id))
            for g in range(GLWE_K_P1):
                for stg_iter in range(STG_ITER_NB):
                    for s in range(GLWE_RAM_SUBWORD_NB):
                        l = []
                        for c in range(GLWE_RAM_SUBWORD_COEF_NB):
                            c_idx = stg_iter*GLWE_RAM_SUBWORD_COEF_NB*GLWE_RAM_SUBWORD_NB + s*GLWE_RAM_SUBWORD_COEF_NB + c
                            c_id = get_pos_id(R,S,c_idx,0)
                            l.append(tvec_data[pbs_id].pbs['br_loop'][br_loop_nb-1]['pp'][g]['ct0 + pp_mod_q'][c_id])
                        d = print_hex(l, MOD_Q_W)
                        f.write(d + "\n")


#=====================================================
# Generate LRAM
#=====================================================
def generate_lram(LWE_K,LWE_ACS_W, batch_pbs_l,batch_id,tvec_data,WORK_DIR,filename_prefix="lram"):
    '''
    Generate the ciphertext in LWE form without the "b" coefficient.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['input_lwe_2N'][LWE_K]
    '''

    gen.generate_lram(LWE_K,LWE_ACS_W, batch_pbs_l,batch_id,tvec_data,WORK_DIR,filename_prefix)

#=====================================================
# Generate LWE
#=====================================================
def generate_lwe(LWE_K,LWE_ACS_W,batch_pbs_l,batch_id,tvec_data,WORK_DIR,filename_prefix="lwe_in"):
    '''
    Generate the ciphertext in LWE form with the "b" coefficient.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['input_lwe_2N'][LWE_K+1]
    Assumption: Batches are process in order.
    '''

    gen.generate_lwe(LWE_K,LWE_ACS_W,batch_pbs_l,batch_id,tvec_data,WORK_DIR,filename_prefix)

#=====================================================
# Generate monomult rotation
#=====================================================
def generate_monomult_rotation(R,S,PSI,STG_ITER_NB,GLWE_K_P1,MOD_Q_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data,WORK_DIR,filename_prefix="monomult_rot"):
    '''
    Generate the rotated data read from GRAM.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['br_loop'][bl]['ct1'][GLWE_K_P1][N]
    '''
    # tvec_in_data_l[pbs_id][stg_iter][GLWE_K_P1][R*PSI]
    tvec_in_data_l = []

    for pbs_id in batch_pbs_l[batch_id]:
        tvec_in_data_l.append([])
        for stg_iter in range(STG_ITER_NB):
            tvec_in_data_l[-1].append([])
            for g in range(GLWE_K_P1):
                tvec_in_data_l[-1][-1].append([])
                for p in range(PSI):
                    for r in range(R):
                        c_idx = stg_iter*PSI*R+p*R+r
                        c_id = get_pos_id(R,S,c_idx,0)
                        tvec_in_data_l[-1][-1][-1].append(tvec_data[pbs_id].pbs['br_loop'][br_loop_l[pbs_id]]['ct1'][g][c_id])


    ### Print
    if (batch_iter == 0):
       write_option = 'w'
    else:
       write_option = 'a'

    ## monomult -> rot
    with open(os.path.join(WORK_DIR,"{:s}.dat".format(filename_prefix)), write_option) as f:
        f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]),br_loop_l[batch_pbs_l[batch_id][0]]))
        for pbs_id, pbs_l in enumerate(tvec_in_data_l):
            f.write("# pbs_id={:0d}\n".format(pbs_id))
            for stg_iter_l in pbs_l:
                for lvl_l in stg_iter_l:
                    d = print_hex(lvl_l, MOD_Q_W)
                    f.write(d + "\n")


#=====================================================
# Generate monomult accumulation
#=====================================================
def generate_monomult_accumulation(R,S,PSI,STG_ITER_NB,GLWE_K_P1,MOD_Q_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data,WORK_DIR,filename_prefix="monomult_acc"):
    '''
    Generate the accumulated data write into GRAM.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['br_loop'][bl]['pp'][GLWE_K_P1]['ct0 + pp_mod_q'][N]
    '''
    # tvec_in_data_l[pbs_id][stg_iter][GLWE_K_P1][R*PSI]
    tvec_in_data_l = []
    for pbs_id in batch_pbs_l[batch_id]:
        tvec_in_data_l.append([])
        for stg_iter in range(STG_ITER_NB):
            tvec_in_data_l[-1].append([])
            for g in range(GLWE_K_P1):
                tvec_in_data_l[-1][-1].append([])
                for p in range(PSI):
                    for r in range(R):
                        c_idx = stg_iter*PSI*R+p*R+r
                        c_id = get_pos_id(R,S,c_idx,0)
                        tvec_in_data_l[-1][-1][-1].append(tvec_data[pbs_id].pbs['br_loop'][br_loop_l[pbs_id]]['pp'][g]['ct0 + pp_mod_q'][c_id])


    ### Print
    if (batch_iter == 0):
       write_option = 'w'
    else:
       write_option = 'a'

    ## monomult -> acc
    with open(os.path.join(WORK_DIR,"{:s}.dat".format(filename_prefix)), write_option) as f:
        f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]),br_loop_l[batch_pbs_l[batch_id][0]]))
        for pbs_id, pbs_l in enumerate(tvec_in_data_l):
            f.write("# pbs_id={:0d}\n".format(pbs_id))
            for stg_iter_l in pbs_l:
                for lvl_l in stg_iter_l:
                    d = print_hex(lvl_l, MOD_Q_W)
                    f.write(d + "\n")


#=====================================================
# Generate decomposer input
#=====================================================
def generate_monomult_decomp(R,S,PSI,STG_ITER_NB,PBS_L,GLWE_K_P1,MOD_Q_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data,WORK_DIR,filename_prefix="monomult_decomp"):
    '''
    Generate the decomposer input.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['br_loop'][bl]['ct10'][GLWE_K_P1][N]
    '''
    # tvec_in_data_l[pbs_id][stg_iter][GLWE_K_P1][R*PSI]
    tvec_in_data_l = []

    for pbs_id in batch_pbs_l[batch_id]:
        tvec_in_data_l.append([])
        for stg_iter in range(STG_ITER_NB):
            tvec_in_data_l[-1].append([])
            for g in range(GLWE_K_P1):
                tvec_in_data_l[-1][-1].append([])
                for p in range(PSI):
                    for r in range(R):
                        c_idx = stg_iter*PSI*R+p*R+r
                        c_id = get_pos_id(R,S,c_idx,0)
                        tvec_in_data_l[-1][-1][-1].append(tvec_data[pbs_id].pbs['br_loop'][br_loop_l[pbs_id]]['ct10'][g][c_id])


    ### Print
    if (batch_iter == 0):
       write_option = 'w'
    else:
       write_option = 'a'

    with open(os.path.join(WORK_DIR,"{:s}.dat".format(filename_prefix)), write_option) as f:
        f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]),br_loop_l[batch_pbs_l[batch_id][0]]))
        for pbs_id, pbs_l in enumerate(tvec_in_data_l):
            f.write("# pbs_id={:0d}\n".format(pbs_id))
            for stg_iter_l in pbs_l:
                for lvl_l in stg_iter_l:
                    coef_nb = (N + (STG_ITER_NB * PBS_L-1)) // (STG_ITER_NB * PBS_L)  # Number of coefficients per chunk
                    for chk in range(PBS_L):
                        # If coef_nb * STG_ITER_NB * PBS_L != N, the last chunk is not complete.
                        # The significant bits are in LSB
                        while (len(lvl_l[chk*coef_nb:(chk+1)*coef_nb]) < coef_nb):
                            lvl_l.append(0)
                        d = print_hex(lvl_l[chk*coef_nb:(chk+1)*coef_nb], MOD_Q_W)
                        f.write(d + "\n")

#=====================================================
# Generate NTT input
#=====================================================
def generate_ntt_input(R,S,PSI,BWD_PSI,STG_ITER_NB,BWD_STG_ITER_NB,PBS_L,GLWE_K_P1, OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data,WORK_DIR,filename_prefix="decomp_ntt"):
    '''
    Generate the NTT input data.
    tvec_data has the following format:
    fwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['extp_bl'][PBS_L][GLWE_K_P1]['ntt'][stg]['in'][PSI*STG_ITER_NB][R]
    bwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['pp'][GLWE_K_P1]['ntt'][stg]['in'][PSI*STG_ITER_NB][R]
    In tvec stg=0 : first stage.
    In RTL stg=0 : last stage
    '''
    # tvec_stg_data_l[pbs_id][stg_iter][level][R*PSI]
    tvec_stg_data_l = []

    for pbs_id in batch_pbs_l[batch_id]:
        tvec_stg_data_l.append([])
        for stg_iter in range(STG_ITER_NB):
            tvec_stg_data_l[-1].append([])
            for g in range(GLWE_K_P1):
                for l in range(PBS_L):
                    tvec_stg_data_l[-1][-1].append([])
                    for p in range(PSI):
                        for r in range(R):
                            c_idx = stg_iter*PSI+p
                            c_id = get_node_id(R,S-1,c_idx,0)
                            tvec_stg_data_l[-1][-1][-1].append(tvec_data[pbs_id].pbs['br_loop'][br_loop_l[pbs_id]]['extp_bl'][l][g]['ntt'][0]['in'][c_id][r])

    ### Print
    if (batch_iter == 0):
        write_option = 'w'
    else:
        write_option = 'a'

    with open(os.path.join(WORK_DIR,"{:s}.dat".format(filename_prefix)), write_option) as f:
        f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]),br_loop_l[batch_pbs_l[batch_id][0]]))
        for pbs_id, pbs_l in enumerate(tvec_stg_data_l):
            f.write("# pbs_id={:0d}\n".format(pbs_id))
            for stg_iter_l in pbs_l:
                for lvl_l in stg_iter_l:
                    d = print_hex(lvl_l, OP_W)
                    f.write(d + "\n")

#=====================================================
# Generate NTT stage input
#=====================================================
def generate_ntt_stage_input_core(R,S,PSI,BWD_PSI,STG_ITER_NB,BWD_STG_ITER_NB,PBS_L,GLWE_K_P1,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data,filename_prefix="decomp_ntt"):
    '''
    Generate the list necessary for the generation of the data input for each NTT stage stg.
    tvec_data has the following format:
    fwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['extp_bl'][PBS_L][GLWE_K_P1]['ntt'][stg]['in'][PSI*STG_ITER_NB][R]
    bwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['pp'][GLWE_K_P1]['ntt'][stg]['in'][PSI*STG_ITER_NB][R]
    In tvec stg=0 : first stage.
    In RTL stg=0 : last stage
    '''
    # tvec_stg_data_l[fwd/bwd][stg_sw][pbs_id][level][N]
    tvec_stg_data_l = []
    tvec_fwd_stg_data_l = []
    tvec_bwd_stg_data_l = []

    # Forward
    for stg in range(S):
        tvec_fwd_stg_data_l.append([])
        for pbs_id in batch_pbs_l[batch_id]:
            tvec_fwd_stg_data_l[-1].append([])
            for g in range(GLWE_K_P1):
                for l in range(PBS_L):
                    tvec_fwd_stg_data_l[-1][-1].append([])
                    for stg_iter in range(STG_ITER_NB):
                        for p in range(PSI):
                            for r in range(R):
                                tvec_fwd_stg_data_l[-1][-1][-1].append(tvec_data[pbs_id].pbs['br_loop'][br_loop_l[pbs_id]]['extp_bl'][l][g]['ntt'][stg]['in'][stg_iter*PSI+p][r])

    # Backward
    for stg in range(S):
        tvec_bwd_stg_data_l.append([])
        for pbs_id in batch_pbs_l[batch_id]:
            tvec_bwd_stg_data_l[-1].append([])
            for g in range(GLWE_K_P1):
                tvec_bwd_stg_data_l[-1][-1].append([])
                for stg_iter in range(STG_ITER_NB):
                    for p in range(PSI):
                        for r in range(R):
                            tvec_bwd_stg_data_l[-1][-1][-1].append(tvec_data[pbs_id].pbs['br_loop'][br_loop_l[pbs_id]]['pp'][g]['ntt'][stg]['in'][stg_iter*BWD_PSI+p][r])


    # Organize forward and backward per br_loop
    tvec_stg_data_l.append(tvec_fwd_stg_data_l)
    tvec_stg_data_l.append(tvec_bwd_stg_data_l)

    return tvec_stg_data_l


def generate_ntt_stage_input_compact(R,S,PSI,STG_ITER_NB,PBS_L,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data,LPB_NB, RS_DELTA_IDX, LS_DELTA_IDX, DELTA,WORK_DIR,filename_prefix="ntt_clbu_in"):
    '''
    Generate the data input for stage stg.
    tvec_data has the following format:
    fwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['extp_bl'][PBS_L][GLWE_K_P1]['ntt'][stg]['in'][PSI*STG_ITER_NB][R]
    bwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['pp'][GLWE_K_P1]['ntt'][stg]['in'][PSI*STG_ITER_NB][R]
    In tvec stg=0 : first stage.
    In RTL stg=0 : last stage
    '''
    # tvec_stg_data_l[fwd/bwd][stg_sw][pbs_id][level][N]
    tvec_stg_data_l = generate_ntt_stage_input_core(R,S,PSI,PSI,STG_ITER_NB,STG_ITER_NB,PBS_L,GLWE_K_P1,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data)

    ## CLBU input
    # tvec_delta_data_l[delta][fwd/bwd][lpb][pbs_id][stg_iter][level][PSI*R]
    tvec_delta_data_l = []
    for delta_idx in range(DELTA):
        tvec_delta_data_l.append([])
        for ntt_bwd in range (2) :
            stg = delta_idx
            lvl_nb = GLWE_K_P1 * PBS_L
            if (ntt_bwd == 1):
                lvl_nb = GLWE_K_P1
            tvec_delta_data_l[-1].append([])
            for lpb in range (LPB_NB) :
                if ((lpb < LPB_NB-1 and delta_idx <= RS_DELTA_IDX) or (lpb == LPB_NB-1 and delta_idx <= LS_DELTA_IDX)):
                    #print("delta={:0d} ntt_bwd={:0d} lpb={:0d} stg={:0d}".format(delta_idx,ntt_bwd, lpb, stg))
                    tvec_delta_data_l[-1][-1].append([])
                    for pbs_id, pbs_l in enumerate(tvec_stg_data_l[ntt_bwd][stg]):
                        tvec_delta_data_l[-1][-1][-1].append([])
                        for stg_iter in range(STG_ITER_NB) :
                            tvec_delta_data_l[-1][-1][-1][-1].append([])
                            for lvl in range(lvl_nb) :
                                tvec_delta_data_l[-1][-1][-1][-1][-1].append([])
                                for p in range(PSI) :
                                    for r in range(R) :
                                        c_idx = stg_iter*(PSI*R)+p*R+r
                                        c_id = get_pos_id(R,S,c_idx,delta_idx)
                                        #print("delta_idx={:0d} c_idx={:0d} c_id={:0d}".format(delta_idx,c_idx,c_id))
                                        tvec_delta_data_l[-1][-1][-1][-1][-1][-1].append(pbs_l[lvl][c_id])
                stg = stg + RS_DELTA



    ### Print
    if (batch_iter == 0):
        write_option = 'w'
    else:
        write_option = 'a'

    for delta_idx in range(DELTA):
        with open(os.path.join(WORK_DIR,"{:s}_D{:0d}.dat".format(filename_prefix,delta_idx)), write_option) as f:
            f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]), br_loop_l[batch_pbs_l[batch_id][0]]))
            for ntt_bwd, ntt_l in enumerate(tvec_delta_data_l[delta_idx]):
                stg = delta_idx
                f.write("# ntt_bwd={:0d}\n".format(ntt_bwd))
                for lpb, lpb_l in enumerate(ntt_l):
                    f.write("# lpb={:0d} stg={:0d}\n".format(lpb, S-1-stg)) # in RTL numbering
                    for pbs_id, pbs_l in enumerate(lpb_l):
                        f.write("# pbs_id={:0d}\n".format(pbs_id))
                        for stg_iter, stg_iter_l in enumerate(pbs_l):
                            f.write("# stg_iter={:0d}\n".format(stg_iter))
                            for lvl, lvl_l in enumerate(stg_iter_l):
                              d = print_hex(lvl_l, OP_W)
                              f.write(d + "\n")
                    stg = stg + RS_DELTA


def generate_ntt_stage_input_unfold(R,S,PSI,BWD_PSI,STG_ITER_NB,BWD_STG_ITER_NB,PBS_L,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data, LS_DELTA_IDX, DELTA,CLBU_NB, WORK_DIR,filename_prefix="ntt_clbu_in"):
    '''
    Generate the data input for stage stg.
    tvec_data has the following format:
    fwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['extp_bl'][PBS_L][GLWE_K_P1]['ntt'][stg]['in'][PSI*STG_ITER_NB][R]
    bwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['pp'][GLWE_K_P1]['ntt'][stg]['in'][PSI*STG_ITER_NB][R]
    In tvec stg=0 : first stage.
    In RTL stg=0 : last stage
    '''
    # tvec_stg_data_l[fwd/bwd][stg_sw][pbs_id][level][N]
    tvec_stg_data_l = generate_ntt_stage_input_core(R,S,PSI,PSI,STG_ITER_NB,STG_ITER_NB,PBS_L,GLWE_K_P1,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data)

    ## CLBU input
    # tvec_delta_data_l[clbu][delta][fwd/bwd][pbs_id][stg_iter][level][PSI*R]
    tvec_delta_data_l = []
    for clbu in range(CLBU_NB):
        delta = DELTA
        if (clbu == CLBU_NB-1):
            delta = LS_DELTA
        tvec_delta_data_l.append([])
        for delta_idx in range(delta):
            stg = clbu*DELTA + delta_idx
            tvec_delta_data_l[-1].append([])
            for ntt_bwd in range (2) :
                lvl_nb = GLWE_K_P1 * PBS_L
                psi = PSI
                stg_iter_nb = STG_ITER_NB
                if (ntt_bwd == 1):
                    lvl_nb = GLWE_K_P1
                    psi = BWD_PSI
                    stg_iter_nb = BWD_STG_ITER_NB
                tvec_delta_data_l[-1][-1].append([])
                #print("delta={:0d} ntt_bwd={:0d} lpb={:0d} stg={:0d}".format(delta_idx,ntt_bwd, lpb, stg))
                for pbs_id, pbs_l in enumerate(tvec_stg_data_l[ntt_bwd][stg]):
                    tvec_delta_data_l[-1][-1][-1].append([])
                    for stg_iter in range(stg_iter_nb) :
                        tvec_delta_data_l[-1][-1][-1][-1].append([])
                        for lvl in range(lvl_nb) :
                            tvec_delta_data_l[-1][-1][-1][-1][-1].append([])
                            for p in range(psi) :
                                for r in range(R) :
                                    c_idx = stg_iter*(psi*R)+p*R+r
                                    c_id = get_pos_id(R,S,c_idx,delta_idx)
                                    #print("delta_idx={:0d} c_idx={:0d} c_id={:0d}".format(delta_idx,c_idx,c_id))
                                    tvec_delta_data_l[-1][-1][-1][-1][-1][-1].append(pbs_l[lvl][c_id])


    ### Print
    if (batch_iter == 0):
        write_option = 'w'
    else:
        write_option = 'a'

    for clbu in range(CLBU_NB):
        delta = DELTA
        if (clbu == CLBU_NB-1):
            delta = LS_DELTA
        for delta_idx in range(delta):
            stg = clbu*DELTA + delta_idx
            with open(os.path.join(WORK_DIR,"{:s}_C{:0d}_D{:0d}_fwd.dat".format(filename_prefix,clbu,delta_idx)), write_option) as f:
                f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]), br_loop_l[batch_pbs_l[batch_id][0]]))
                ntt_bwd = 0
                f.write("# ntt_bwd={:0d}\n".format(ntt_bwd))
                f.write("# stg={:0d}\n".format(S-1-stg)) # in RTL numbering
                for pbs_id, pbs_l in enumerate(tvec_delta_data_l[clbu][delta_idx][ntt_bwd]):
                    f.write("# pbs_id={:0d}\n".format(pbs_id))
                    for stg_iter, stg_iter_l in enumerate(pbs_l):
                        f.write("# stg_iter={:0d}\n".format(stg_iter))
                        for lvl, lvl_l in enumerate(stg_iter_l):
                          d = print_hex(lvl_l, OP_W)
                          f.write(d + "\n")

            with open(os.path.join(WORK_DIR,"{:s}_C{:0d}_D{:0d}_bwd.dat".format(filename_prefix,clbu,delta_idx)), write_option) as f:
                f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]), br_loop_l[batch_pbs_l[batch_id][0]]))
                ntt_bwd = 1
                f.write("# ntt_bwd={:0d}\n".format(ntt_bwd))
                f.write("# stg={:0d}\n".format(S-1-stg)) # in RTL numbering
                for pbs_id, pbs_l in enumerate(tvec_delta_data_l[clbu][delta_idx][ntt_bwd]):
                    f.write("# pbs_id={:0d}\n".format(pbs_id))
                    for stg_iter, stg_iter_l in enumerate(pbs_l):
                        f.write("# stg_iter={:0d}\n".format(stg_iter))
                        for lvl, lvl_l in enumerate(stg_iter_l):
                          d = print_hex(lvl_l, OP_W)
                          f.write(d + "\n")


#=====================================================
# Generate NTT stage output
#=====================================================
def generate_ntt_stage_output_core(R,S,PSI,BWD_PSI,STG_ITER_NB,BWD_STG_ITER_NB,PBS_L,GLWE_K_P1,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data):
    '''
    Parse the test vector to build the list necessary for the generation of the clbu
    output for stage stg.
    tvec_data has the following format:
    fwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['extp_bl'][PBS_L][GLWE_K_P1]['ntt'][stg]['bu'][PSI*STG_ITER_NB][R]
    bwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['pp'][GLWE_K_P1]['ntt'][stg]['bu'][PSI*STG_ITER_NB][R]
    In tvec stg=0 : first stage.
    In RTL stg=0 : last stage
    '''
    # tvec_stg_data_l[fwd/bwd][stgB][pbs_id][stg_iter][level][R*PSI]
    tvec_stg_data_l = []

    tvec_fwd_stg_data_l = []
    tvec_bwd_stg_data_l = []

    # Forward
    for stg in range(S):
        tvec_fwd_stg_data_l.append([])
        for pbs_id in batch_pbs_l[batch_id]:
            tvec_fwd_stg_data_l[-1].append([])
            for g in range(GLWE_K_P1):
                for l in range(PBS_L):
                    tvec_fwd_stg_data_l[-1][-1].append([])
                    for stg_iter in range(STG_ITER_NB):
                        for p in range(PSI):
                            for r in range(R):
                                tvec_fwd_stg_data_l[-1][-1][-1].append(tvec_data[pbs_id].pbs['br_loop'][br_loop_l[pbs_id]]['extp_bl'][l][g]['ntt'][stg]['bu'][stg_iter*PSI+p][r])

    # Backward
    for stg in range(S):
        tvec_bwd_stg_data_l.append([])
        for pbs_id in batch_pbs_l[batch_id]:
            tvec_bwd_stg_data_l[-1].append([])
            for g in range(GLWE_K_P1):
                tvec_bwd_stg_data_l[-1][-1].append([])
                for stg_iter in range(STG_ITER_NB):
                    for p in range(PSI):
                        for r in range(R):
                            tvec_bwd_stg_data_l[-1][-1][-1].append(tvec_data[pbs_id].pbs['br_loop'][br_loop_l[pbs_id]]['pp'][g]['ntt'][stg]['bu'][stg_iter*BWD_PSI+p][r])


    # Organize forward and backward per br_loop
    tvec_stg_data_l.append(tvec_fwd_stg_data_l)
    tvec_stg_data_l.append(tvec_bwd_stg_data_l)

    return tvec_stg_data_l

def generate_ntt_stage_output_compact(R,S,PSI,STG_ITER_NB,PBS_L,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data,LPB_NB, RS_DELTA_IDX, LS_DELTA_IDX, DELTA,WORK_DIR,filename_prefix="ntt_clbu_out"):
    '''
    Generate the clbu output for stage stg.
    tvec_data has the following format:
    fwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['extp_bl'][PBS_L][GLWE_K_P1]['ntt'][stg]['bu'][PSI*STG_ITER_NB][R]
    bwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['pp'][GLWE_K_P1]['ntt'][stg]['bu'][PSI*STG_ITER_NB][R]
    In tvec stg=0 : first stage.
    '''
    # tvec_delta_data_l[delta][fwd/bwd][lpb][pbs_id][stg_iter][level][PSI*R]
    tvec_stg_data_l = generate_ntt_stage_output_core(R,S,PSI,PSI,STG_ITER_NB,STG_ITER_NB,PBS_L,GLWE_K_P1,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data)

    ## CLBU input
    # tvec_delta_data_l[delta][fwd/bwd][lpb][pbs_id][stg_iter][level][PSI*R]
    tvec_delta_data_l = []
    for delta_idx in range(DELTA):
        stg = delta_idx
        tvec_delta_data_l.append([])
        for ntt_bwd in range (2) :
            stg = delta_idx
            lvl_nb = GLWE_K_P1 * PBS_L
            if (ntt_bwd == 1):
                lvl_nb = GLWE_K_P1
            tvec_delta_data_l[-1].append([])
            for lpb in range (LPB_NB) :
                if ((lpb < LPB_NB-1 and delta_idx <= RS_DELTA_IDX) or (lpb == LPB_NB-1 and delta_idx <= LS_DELTA_IDX)):
                    #print("delta={:0d} ntt_bwd={:0d} lpb={:0d} stg={:0d}".format(delta_idx,ntt_bwd, lpb, stg))
                    tvec_delta_data_l[-1][-1].append([])
                    for pbs_id, pbs_l in enumerate(tvec_stg_data_l[ntt_bwd][stg]):
                        tvec_delta_data_l[-1][-1][-1].append([])
                        for stg_iter in range(STG_ITER_NB) :
                            tvec_delta_data_l[-1][-1][-1][-1].append([])
                            for lvl in range(lvl_nb) :
                                tvec_delta_data_l[-1][-1][-1][-1][-1].append([])
                                for p in range(PSI) :
                                    for r in range(R) :
                                        c_idx = stg_iter*(PSI*R)+p*R+r
                                        c_id = get_pos_id(R,S,c_idx,delta_idx)
                                        tvec_delta_data_l[-1][-1][-1][-1][-1][-1].append(pbs_l[lvl][c_id])
                stg = stg + RS_DELTA



    ### Print
    if (batch_iter == 0):
        write_option = 'w'
    else:
        write_option = 'a'

    for delta_idx in range(DELTA):
        with open(os.path.join(WORK_DIR,"{:s}_D{:0d}.dat".format(filename_prefix,delta_idx)), write_option) as f:
            f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]), br_loop_l[batch_pbs_l[batch_id][0]]))
            for ntt_bwd, ntt_l in enumerate(tvec_delta_data_l[delta_idx]):
                stg = delta_idx
                f.write("# ntt_bwd={:0d}\n".format(ntt_bwd))
                for lpb, lpb_l in enumerate(ntt_l):
                    f.write("# lpb={:0d} stg={:0d}\n".format(lpb, S-1-stg)) # in RTL numbering
                    for pbs_id, pbs_l in enumerate(lpb_l):
                        f.write("# pbs_id={:0d}\n".format(pbs_id))
                        for stg_iter, stg_iter_l in enumerate(pbs_l):
                            f.write("# stg_iter={:0d}\n".format(stg_iter))
                            for lvl, lvl_l in enumerate(stg_iter_l):
                              d = print_hex(lvl_l, OP_W)
                              f.write(d + "\n")
                    stg = stg + RS_DELTA


def generate_ntt_stage_output_unfold(R,S,PSI,BWD_PSI,STG_ITER_NB,BWD_STG_ITER_NB,PBS_L,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data, LS_DELTA_IDX, DELTA,CLBU_NB, WORK_DIR,filename_prefix="ntt_clbu_out"):
    '''
    Generate the data input for stage stg.
    tvec_data has the following format:
    fwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['extp_bl'][PBS_L][GLWE_K_P1]['ntt'][stg]['in'][PSI*STG_ITER_NB][R]
    bwd:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['pp'][GLWE_K_P1]['ntt'][stg]['in'][PSI*STG_ITER_NB][R]
    In tvec stg=0 : first stage.
    In RTL stg=0 : last stage
    '''
    # tvec_stg_data_l[fwd/bwd][stg_sw][pbs_id][level][N]
    tvec_stg_data_l = generate_ntt_stage_output_core(R,S,PSI,PSI,STG_ITER_NB,STG_ITER_NB,PBS_L,GLWE_K_P1,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data)

    ## CLBU input
    # tvec_delta_data_l[clbu][delta][fwd/bwd][pbs_id][stg_iter][level][PSI*R]
    tvec_delta_data_l = []
    for clbu in range(CLBU_NB):
        delta = DELTA
        if (clbu == CLBU_NB-1):
            delta = LS_DELTA
        tvec_delta_data_l.append([])
        for delta_idx in range(delta):
            stg = clbu*DELTA + delta_idx
            tvec_delta_data_l[-1].append([])
            for ntt_bwd in range (2) :
                lvl_nb = GLWE_K_P1 * PBS_L
                psi = PSI
                stg_iter_nb = STG_ITER_NB
                if (ntt_bwd == 1):
                    lvl_nb = GLWE_K_P1
                    psi = BWD_PSI
                    stg_iter_nb = BWD_STG_ITER_NB
                tvec_delta_data_l[-1][-1].append([])
                #print("delta={:0d} ntt_bwd={:0d} lpb={:0d} stg={:0d}".format(delta_idx,ntt_bwd, lpb, stg))
                for pbs_id, pbs_l in enumerate(tvec_stg_data_l[ntt_bwd][stg]):
                    tvec_delta_data_l[-1][-1][-1].append([])
                    for stg_iter in range(stg_iter_nb) :
                        tvec_delta_data_l[-1][-1][-1][-1].append([])
                        for lvl in range(lvl_nb) :
                            tvec_delta_data_l[-1][-1][-1][-1][-1].append([])
                            for p in range(psi) :
                                for r in range(R) :
                                    c_idx = stg_iter*(psi*R)+p*R+r
                                    c_id = get_pos_id(R,S,c_idx,delta_idx)
                                    #print("delta_idx={:0d} c_idx={:0d} c_id={:0d}".format(delta_idx,c_idx,c_id))
                                    tvec_delta_data_l[-1][-1][-1][-1][-1][-1].append(pbs_l[lvl][c_id])


    ### Print
    if (batch_iter == 0):
        write_option = 'w'
    else:
        write_option = 'a'

    for clbu in range(CLBU_NB):
        delta = DELTA
        if (clbu == CLBU_NB-1):
            delta = LS_DELTA
        for delta_idx in range(delta):
            stg = clbu*DELTA + delta_idx
            with open(os.path.join(WORK_DIR,"{:s}_C{:0d}_D{:0d}_fwd.dat".format(filename_prefix,clbu,delta_idx)), write_option) as f:
                f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]), br_loop_l[batch_pbs_l[batch_id][0]]))
                ntt_bwd = 0
                f.write("# ntt_bwd={:0d}\n".format(ntt_bwd))
                f.write("# stg={:0d}\n".format(S-1-stg)) # in RTL numbering
                for pbs_id, pbs_l in enumerate(tvec_delta_data_l[clbu][delta_idx][ntt_bwd]):
                    f.write("# pbs_id={:0d}\n".format(pbs_id))
                    for stg_iter, stg_iter_l in enumerate(pbs_l):
                        f.write("# stg_iter={:0d}\n".format(stg_iter))
                        for lvl, lvl_l in enumerate(stg_iter_l):
                          d = print_hex(lvl_l, OP_W)
                          f.write(d + "\n")

            with open(os.path.join(WORK_DIR,"{:s}_C{:0d}_D{:0d}_bwd.dat".format(filename_prefix,clbu,delta_idx)), write_option) as f:
                f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]), br_loop_l[batch_pbs_l[batch_id][0]]))
                ntt_bwd = 1
                f.write("# ntt_bwd={:0d}\n".format(ntt_bwd))
                f.write("# stg={:0d}\n".format(S-1-stg)) # in RTL numbering
                for pbs_id, pbs_l in enumerate(tvec_delta_data_l[clbu][delta_idx][ntt_bwd]):
                    f.write("# pbs_id={:0d}\n".format(pbs_id))
                    for stg_iter, stg_iter_l in enumerate(pbs_l):
                        f.write("# stg_iter={:0d}\n".format(stg_iter))
                        for lvl, lvl_l in enumerate(stg_iter_l):
                          d = print_hex(lvl_l, OP_W)
                          f.write(d + "\n")

#=====================================================
# Generate NTT output
#=====================================================
def generate_ntt_acc (R,S,PSI,STG_ITER_NB,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tvec_data,WORK_DIR,with_modswitch,filename_prefix="ntt_acc"):
    '''
    Generate the NTT core output.
    tvec_data has the following format:
    tvec_data[pbs_id].pbs['br_loop'][br_loop]['pp'][GLWE_K_P1]['pp_mod_p'][N]

    pbs_nb_l : list of the number of pbs per batch.
    batch_order_l : batch_id order to process
    '''
    # tvec_stg_data_l[pbs_id][stg_iter][level][R*PSI]
    tvec_stg_data_l = []

    if (with_modswitch):
        key = 'pp_mod_q'
    else:
        key = 'pp_mod_p'


    for pbs_id in batch_pbs_l[batch_id]:
        tvec_stg_data_l.append([])
        for stg_iter in range(STG_ITER_NB):
            tvec_stg_data_l[-1].append([])
            for g in range(GLWE_K_P1):
                tvec_stg_data_l[-1][-1].append([])
                for p in range(PSI):
                    for r in range(R):
                        c_idx = stg_iter*(PSI*R)+p*R+r
                        c_id = get_pos_id(R,S,c_idx,0)
                        tvec_stg_data_l[-1][-1][-1].append(tvec_data[pbs_id].pbs['br_loop'][br_loop_l[pbs_id]]['pp'][g][key][c_id])

    # Print
    if (batch_iter == 0):
        write_option = 'w'
    else:
        write_option = 'a'

    with open(os.path.join(WORK_DIR,"{:s}.dat".format(filename_prefix)), write_option) as f:
        f.write("# batch_id={:0d} pbs_l={:s} br_loop={:0d}\n".format(batch_id, str(batch_pbs_l[batch_id]),br_loop_l[batch_pbs_l[batch_id][0]]))
        for pbs_id, pbs_l in enumerate(tvec_stg_data_l):
            f.write("# pbs_id={:0d}\n".format(pbs_id))
            for stg_iter_l in pbs_l:
                for lvl_l in stg_iter_l:
                    d = print_hex(lvl_l, OP_W)
                    f.write(d + "\n")


#=====================================================
# Generate batch_cmd
#=====================================================
def generate_batch_cmd(pbs_nb, br_loop, batch_iter,WORK_DIR,filename_prefix="batch_cmd"):
    '''
    Generate the batch command
    '''
    if (batch_iter == 0):
        write_option = 'w'
    else:
        write_option = 'a'
    with open(os.path.join(WORK_DIR,"{:s}.dat".format(filename_prefix)), write_option) as f:
        if (batch_iter == 0):
            f.write("# [31:0] pbs_nb, [63:32] br_loop\n")
        d = print_hex([pbs_nb, br_loop], 32) # Use 32 bits for each field
        f.write(d + "\n")


#=====================================================
# Generate info
#=====================================================
def generate_info(seed, batch_order_l,br_loop_nb,total_pbs_nb,pbs_nb_l,WORK_DIR,filename_prefix="info"):
    '''
    Generate the file containing this stimuli information.
    '''

    with open(os.path.join(WORK_DIR,"{:s}.txt".format(filename_prefix)), 'w') as f:
        f.write("SEED={:0d}\n".format(seed))
        f.write("SIMU_BATCH_NB={:0d}\n".format(len(batch_order_l)))
        f.write("WHOLE_BATCH_NB={:0d}\n".format(len(pbs_nb_l)))
        f.write("TOTAL_PBS_NB={:0d}\n".format(total_pbs_nb))
        f.write("BR_LOOP_NB={:0d}\n".format(br_loop_nb))

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Generate stimuli for ntt wmm.")
    parser.add_argument('-o',  dest='work_dir',              type=str, help="Working directory.",
                               required=True)
    parser.add_argument('-i',  dest='tv_dir',                type=str, help="Input test_vectors.py directory.",
                               required=True)
    parser.add_argument('-z',  dest='skip_stim_l',           type=str, help="Skipped stimuli. Default : []",
                               default = [], choices=['bsk','twd_ifnl','twd_phru','twd_omg','ntt_data','info','mmacc_data', 'axi4'] , action='append')
    parser.add_argument('-R',  dest='radix',                 type=int, help="Radix.",
                               default=R)
    parser.add_argument('-P',  dest='psi',                   type=int, help="PSI.",
                               default=PSI)
    parser.add_argument('-S',  dest='stage',                 type=int, help="Number of NTT stages.",
                               default=S)
    parser.add_argument('-l',  dest='pbs_l',                 type=int, help="PBS_L: Number of decomposed levels",
                               default=PBS_L)
    parser.add_argument('-K',  dest='lwe_k',                 type=int, help="LWE_K: Ciphertext number of coef",
                               default=LWE_K)
    parser.add_argument('-g',  dest="glwe_k",                type=int, help="GLWE_K: Number of polynomials",
                               default=GLWE_K_P1-1)
    parser.add_argument('-w',  dest='op_w',                  type=int, help="NTT Operand width.",
                               default=OP_W)
    parser.add_argument('-W',  dest='mod_q_w',               type=int, help="Operand width.",
                               default=OP_W)
    parser.add_argument('-a',  dest='bsk_coef_nb',           type=int, help="BSK server number of coefficients.",
                               default=BSK_COEF_NB)
    parser.add_argument('-bs', dest='bsk_srv_nb',            type=int, help="Number of BSK servers",
                               default=BSK_SRV_NB)
    parser.add_argument('-bn', dest='bsk_inst_br_loop_nb_l', type=int, help="Number of br_loop per BSK server. Append the value for each server, starting with server #0.",
                               default=[], action='append')
    parser.add_argument('-dM', dest='batch_max_pbs',         type=int, help="Max number of PBS per batch",
                               default=BATCH_MAX_PBS)
    parser.add_argument('-dm', dest='batch_min_pbs',         type=int, help="Min number of PBS per batch",
                               default=BATCH_MIN_PBS)
    parser.add_argument('-e',  dest='bwd_psi_div',           type=int, help="PSI divider for Backward path. Set to 1 if not an NTT unfold architecture.",
                               default=BWD_PSI_DIV)
    parser.add_argument('-A',  dest='ntt_core_wmm_arch',     type=str, help="NTT core wmm architecture",
                               default='NTT_CORE_ARCH_wmm_compact_pcg', choices=['NTT_CORE_ARCH_wmm_compact_pcg', 'NTT_CORE_ARCH_wmm_pipeline_pcg', 'NTT_CORE_ARCH_wmm_unfold_pcg'])
    parser.add_argument('-s',  dest='seed',                  type=int, help="Seed",
                               default=None)
    parser.add_argument('-u',  dest='use_ordered_batch',     help="Process PBS/batch in order. Default : disorder",
                               default=False, action="store_true")
    parser.add_argument('-B',  dest='batch_nb',              type=int, help="BATCH_NB: Number of interleved batches. Default : 2",
                               default=BATCH_NB)
    parser.add_argument('-lw', dest='lwe_acs_w',             type=int, help="LWE_ACS_W: LWE transfer size.",
                               default=LWE_ACS_W)
    parser.add_argument('-delta', dest='delta',              type=int, help="DELTA: PCG CLBU delta parameter.",
                               default=DELTA)
    parser.add_argument('-v',  dest='verbose',                help="Run in verbose mode.",
                               default=False, action="store_true")

    args = parser.parse_args()

    SEED = args.seed
    if (SEED == None):
      SEED = random.randrange(sys.maxsize)
    random.seed(args.seed)

    VERBOSE = args.verbose
    USE_ORDERED_BATCH = args.use_ordered_batch
    BATCH_NB = args.batch_nb
    WORK_DIR = args.work_dir
    TV_DIR = args.tv_dir
    NTT_CORE_WMM_ARCH = args.ntt_core_wmm_arch
    R = args.radix
    PSI = args.psi
    S = args.stage
    OP_W = args.op_w
    MOD_Q_W = args.mod_q_w
    PBS_L = args.pbs_l
    LWE_K = args.lwe_k
    GLWE_K_P1 = args.glwe_k + 1
    BSK_SRV_NB = args.bsk_srv_nb
    BSK_COEF_NB = args.bsk_coef_nb
    BATCH_MAX_PBS = args.batch_max_pbs
    BATCH_MIN_PBS = args.batch_min_pbs
    BWD_PSI_DIV = args.bwd_psi_div
    LWE_ACS_W = args.lwe_acs_w
    if (MOD_Q_W > 32):
      GLWE_ACS_W     = 64;
      BLWE_ACS_W     = 64;
    else:
      GLWE_ACS_W     = 32;
      BLWE_ACS_W     = 32;
    DELTA = args.delta

    # Deduce the used parameters
    GLWE_RAM_SUBWORD_COEF_NB = AXI4_W // GLWE_ACS_W
    if (GLWE_RAM_SUBWORD_COEF_NB > PSI*R):
      GLWE_RAM_SUBWORD_COEF_NB = PSI*R
      #AXI4_W = GLWE_RAM_SUBWORD_COEF_NB * MOD_Q_W

    GLWE_RAM_SUBWORD_NB = (PSI*R) // GLWE_RAM_SUBWORD_COEF_NB
    BWD_PSI = PSI // BWD_PSI_DIV
    if (len(args.bsk_inst_br_loop_nb_l) != 0):
        BSK_INST_BR_LOOP_NB = args.bsk_inst_br_loop_nb_l
    else:
        BSK_INST_BR_LOOP_NB = []
        remain = LWE_K
        for i in range(BSK_SRV_NB):
            if (i==BSK_SRV_NB-1):
                BSK_INST_BR_LOOP_NB.append(remain)
            else:
                BSK_INST_BR_LOOP_NB.append(LWE_K // BSK_SRV_NB)
            remain = remain - (LWE_K // BSK_SRV_NB)

    N              = R**S
    STG_ITER_NB    = N // (R*PSI)
    BWD_STG_ITER_NB= N // (R*BWD_PSI)
    INTL_L         = PBS_L * GLWE_K_P1
    LWE_COEF_W     = int(log(2*N,2))
    TWD_PHRU_RD_NB = 2
    if (R < 4):
        TWD_PHRU_RD_NB      = 1
    TWD_PHRU_RD_PER_RAM = (TWD_PHRU_RD_NB * 2)

    RS_DELTA = DELTA
    LS_DELTA = S % DELTA
    if (LS_DELTA == 0):
      LS_DELTA = DELTA

    RS_DELTA_IDX = RS_DELTA - 1
    LS_DELTA_IDX = LS_DELTA - 1

    if (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_compact_pcg'):
        LPB_NB = (S+DELTA-1)//DELTA
        CLBU_NB = 1
    else:
        LPB_NB = 1
        CLBU_NB = (S+DELTA-1)//DELTA

    # Check BWD_PSI_DIV
    if (NTT_CORE_WMM_ARCH != 'NTT_CORE_ARCH_wmm_unfold_pcg' and BWD_PSI_DIV != 1):
        sys.exit("ERROR> BWD_PSI_DIV must be set to 1 for architecture different from NTT_CORE_ARCH_wmm_unfold_pcg. BWD_PSI_DIV={:0d}".format(BWD_PSI_DIV))

    # Check number of PBS per batch
    if (BATCH_MAX_PBS < BATCH_MIN_PBS):
        sys.exit("ERROR> BATCH_MAX_PBS ({:0d}) must be greater or equal to BATCH_MIN_PBS ({:0d})".format(BATCH_MAX_PBS,BATCH_MIN_PBS))

    # Check LPB_NB and DELTAs
    if (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_compact_pcg'):
        if (((LPB_NB-1) * RS_DELTA + LS_DELTA) != S):
            sys.exit("ERROR> LPB_NB ({:0d}), RS_DELTA({:0d}) and LS_DELTA({:0d}) are incoherent.".format(LPB_NB,RS_DELTA,LS_DELTA))

#=====================================================
# Take system-wide lock
# Prevent multiple instance of this RAM-hungry script to run in //
# => Use a mutex in the filesystem to serialize them
#=====================================================
    import os
    lock_f = open(f'/var/lock/{os.environ["USER"]}_zama_ci_gen_stimuli_mutex', 'a')
    fcntl.lockf(lock_f, fcntl.LOCK_EX)
    lock_f.write(f'{os.getpid()} @{datetime.today()}\n')

#=====================================================
# Test vectors
#=====================================================
    # Import test vector directory
    sys.path.append(TV_DIR)

    total_pbs_nb = len(glob.glob(os.path.join(TV_DIR,'test_vectors_pbs_*.py')))

    #import test_vectors as tv
    import test_vectors_params as tv_param
    # import the first pbs as tv_pbs[0]
    tv_pbs=[]
    for i in range(total_pbs_nb):
        tv_pbs.append(0) # place holder

    tv_pbs[0] = __import__("test_vectors_pbs_{:0d}".format(0))

#=====================================================
# List of generated stimuli
#=====================================================
    # By default run all stimuli
    run_stim_l = ['bsk','twd_ifnl','twd_phru','twd_omg','ntt_data','info','mmacc_data', 'axi4']
    run_stim_l = list(set(run_stim_l) - set(args.skip_stim_l))

#=====================================================
# Output
#=====================================================
    # bsk_ntt[br_loop][PBS_L][GLWE_K_P1][GLWE_K_P1][N (rev)]
    br_loop_nb = len(tv_param.bsk_ntt)

    # Create batches
    # pbs_nb_l : for each batch [i], gives the number of pbs it contains
    pbs_nb_l = []
    pbs_cnt = total_pbs_nb
    while (pbs_cnt > 0):
        try:
            pbs_nb = random.randrange(BATCH_MIN_PBS, min([pbs_cnt, BATCH_MAX_PBS])+1)
        except ValueError:
            pbs_nb = pbs_cnt
        pbs_nb_l.append(pbs_nb)
        pbs_cnt = pbs_cnt - pbs_nb

    all_batch_nb = len(pbs_nb_l)

    # batch_order_l gives the order in which the batches are processes.
    # Note that each batch is processed br_loop_nb times.
    batch_order_l = []
    if (USE_ORDERED_BATCH):
        for i in range(0, all_batch_nb, BATCH_NB):
            # Interleaved "cnt" batches
            cnt = BATCH_NB;
            if (i + BATCH_NB > all_batch_nb):
                cnt = all_batch_nb - i;
            for b in range(br_loop_nb):
                for n in range(cnt):
                    batch_order_l.append(i + n)
    else:
        # Build a list to do random on it
        choice_batch_l = []
        for i in range(all_batch_nb):
            choice_batch_l = choice_batch_l + [i]*br_loop_nb

        while (len(choice_batch_l)>0):
            batch_id = random.choice(choice_batch_l)
            batch_order_l.append(batch_id)
            # remove it from the list
            choice_batch_l.remove(batch_id)

    if (VERBOSE):
        print("INFO> pbs_nb_l=%{:s}".format(str(pbs_nb_l)))
        print("INFO> batch_order_l=%{:s}".format(str(batch_order_l)))

    # Generate top-lvl files
    # Bsk ordered based on bsk_if requirements
    if ('axi4' in run_stim_l):
        generate_axi4_bsk(AXI4_BSK_W, OP_W, tv_param.bsk_ntt,LS_DELTA_IDX,WORK_DIR)

    # Generate files
    if ('bsk' in run_stim_l):
        generate_bsk(R,PSI,OP_W,STG_ITER_NB,tv_param.bsk_ntt,BSK_COEF_NB,BSK_INST_BR_LOOP_NB,LS_DELTA_IDX,WORK_DIR)
    if ('twd_ifnl' in run_stim_l):
        generate_twd_ifnl(R,S,BWD_PSI,OP_W,BWD_STG_ITER_NB,tv_param.ntt_fm_factors,LS_DELTA_IDX,WORK_DIR)
    if ('twd_phru' in run_stim_l):
        if (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_compact_pcg'):
            generate_twd_phru_compact(R,S,PSI,OP_W,STG_ITER_NB,tv_param.ntt_fwd_twiddles, tv_param.ntt_bwd_twiddles,LPB_NB, RS_DELTA_IDX, LS_DELTA_IDX, DELTA,TWD_PHRU_RD_NB,WORK_DIR)
#        elif (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_pipeline_pcg'):
#            generate_twd_phru_pipeline(R,S,PSI,OP_W,STG_ITER_NB,tv_param.ntt_fwd_twiddles, tv_param.ntt_bwd_twiddles,WORK_DIR)
        elif (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_unfold_pcg'):
            generate_twd_phru_unfold(R,S,PSI,BWD_PSI,OP_W,STG_ITER_NB,BWD_STG_ITER_NB,tv_param.ntt_fwd_twiddles, tv_param.ntt_bwd_twiddles,LS_DELTA, DELTA, CLBU_NB,TWD_PHRU_RD_NB,WORK_DIR)
        else:
            sys.exit("ERROR> Unupported NTT_CORE_WMM_ARCH : {:s}".format(NTT_CORE_WMM_ARCH))
    if ('twd_omg' in run_stim_l):
        generate_twd_omg_ru_r_pow(OP_W,
          tv_pbs[0].pbs['br_loop'][0]['extp_bl'][0][0]['ntt']['powof_omega_ru'],
          tv_pbs[0].pbs['br_loop'][0]['pp'][0]['ntt']['powof_omega_ru'],WORK_DIR)
    if ('info' in run_stim_l):
        generate_info(SEED, batch_order_l,br_loop_nb,total_pbs_nb,pbs_nb_l,WORK_DIR)

    # For each pbs keep track of the current br_loop
    br_loop_l = [ 0 for i in range(total_pbs_nb)]
    # for each batch list the pbs_id that it contains
    batch_pbs_l = []
    pbs_ofs = 0;
    for b in range(all_batch_nb):
        batch_pbs_l.append([])
        for i in range(pbs_nb_l[b]):
            batch_pbs_l[-1].append(pbs_ofs + i)
        pbs_ofs = pbs_ofs + pbs_nb_l[b]


    # For each batch
    # Assumption : batches are processed in order
    for batch_id in range(all_batch_nb):
        for i in batch_pbs_l[batch_id]:
            if (tv_pbs[i] == 0):
                tv_pbs[i] = __import__("test_vectors_pbs_{:0d}".format(i))

        # Generate top-lvl files
        # Top level stimulus are dump unscrambled. Scrambling is done by the bsk_if
        if ('axi4' in run_stim_l):
            generate_axi4_glwe_input(AXI4_W, GLWE_ACS_W, batch_pbs_l, batch_id, tv_pbs,WORK_DIR)
            generate_axi4_glwe_output(AXI4_W,BLWE_ACS_W, batch_pbs_l, batch_id, tv_pbs,WORK_DIR)
            generate_axi4_lwe (AXI4_W, LWE_ACS_W, batch_pbs_l, batch_id, tv_pbs, WORK_DIR)
            generate_batch_info(batch_pbs_l, WORK_DIR)

        if ('mmacc_data' in run_stim_l):
            generate_lram(LWE_K,LWE_COEF_W,batch_pbs_l,batch_id,tv_pbs,WORK_DIR)
            generate_lwe(LWE_K,LWE_ACS_W,batch_pbs_l,batch_id,tv_pbs,WORK_DIR)
            generate_gram_input(STG_ITER_NB,GLWE_K_P1,MOD_Q_W,GLWE_RAM_SUBWORD_COEF_NB,GLWE_RAM_SUBWORD_NB,batch_pbs_l,batch_id,tv_pbs,WORK_DIR)
            generate_gram_output(STG_ITER_NB,GLWE_K_P1,MOD_Q_W,GLWE_RAM_SUBWORD_COEF_NB,GLWE_RAM_SUBWORD_NB,batch_pbs_l,batch_id,br_loop_nb,tv_pbs,WORK_DIR)

    # For each processed batch
    for batch_iter in range(len(batch_order_l)):
        batch_id = batch_order_l[batch_iter]
        for i in batch_pbs_l[batch_id]:
            if (tv_pbs[i] == 0):
                tv_pbs[i] = __import__("test_vectors_pbs_{:0d}".format(i))

        if ('mmacc_data' in run_stim_l) or ('ntt_data' in run_stim_l):
            generate_batch_cmd(pbs_nb_l[batch_id],br_loop_l[batch_pbs_l[batch_id][0]],batch_iter,WORK_DIR)
            generate_ntt_input(R,S,PSI,BWD_PSI,STG_ITER_NB,BWD_STG_ITER_NB,PBS_L,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,WORK_DIR)
            generate_ntt_acc (R,S,PSI,STG_ITER_NB,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,WORK_DIR,0,"ntt_acc")
        if ('mmacc_data' in run_stim_l):
            generate_ntt_acc (R,S,PSI,STG_ITER_NB,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,WORK_DIR,1,"ntt_acc_modswitch")
            generate_monomult_decomp(R,S,PSI,STG_ITER_NB,PBS_L,GLWE_K_P1,MOD_Q_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,WORK_DIR)
            generate_monomult_rotation(R,S,PSI,STG_ITER_NB,GLWE_K_P1,MOD_Q_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,WORK_DIR)
            generate_monomult_accumulation(R,S,PSI,STG_ITER_NB,GLWE_K_P1,MOD_Q_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,WORK_DIR)
        if ('ntt_data' in run_stim_l):
            if (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_compact_pcg'):
                generate_ntt_stage_input_compact(R,S,PSI,STG_ITER_NB,PBS_L,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,LPB_NB, RS_DELTA_IDX, LS_DELTA_IDX, DELTA,WORK_DIR)
                generate_ntt_stage_output_compact(R,S,PSI,STG_ITER_NB,PBS_L,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,LPB_NB, RS_DELTA_IDX, LS_DELTA_IDX, DELTA,WORK_DIR)
#            elif (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_pipeline_pcg'):
#                generate_ntt_stage_input_pipeline(R,S,PSI,STG_ITER_NB,PBS_L,GLWE_K_P1,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,WORK_DIR)
#                generate_ntt_stage_output_pipeline(R,S,PSI,STG_ITER_NB,PBS_L,GLWE_K_P1,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,WORK_DIR)
            elif (NTT_CORE_WMM_ARCH == 'NTT_CORE_ARCH_wmm_unfold_pcg'):
                generate_ntt_stage_input_unfold(R,S,PSI,BWD_PSI,STG_ITER_NB,BWD_STG_ITER_NB,PBS_L,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,LS_DELTA_IDX, DELTA,CLBU_NB,WORK_DIR)
                generate_ntt_stage_output_unfold(R,S,PSI,BWD_PSI,STG_ITER_NB,BWD_STG_ITER_NB,PBS_L,GLWE_K_P1,OP_W,batch_pbs_l,br_loop_l,batch_iter,batch_id,tv_pbs,LS_DELTA_IDX, DELTA,CLBU_NB,WORK_DIR)
            else:
                sys.exit("ERROR> Unupported NTT_CORE_WMM_ARCH : {:s}".format(NTT_CORE_WMM_ARCH))

        for pbs_id in batch_pbs_l[batch_id]:
            # increment the br_loop of the concerned PBS
            br_loop_l[pbs_id] = br_loop_l[pbs_id] + 1

#=====================================================
# Release system-wide-lock
#=====================================================
    fcntl.lockf(lock_f, fcntl.LOCK_UN)
