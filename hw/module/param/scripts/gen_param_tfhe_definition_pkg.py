#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Script used to create a pbs_definition_pkg.sv file.
# ==============================================================================================

import os       # OS functions
import sys      # manage errors
import argparse # parse input argument
import pathlib  # Get current file path
import jinja2
import math

TEMPLATE_NAME = "param_tfhe_definition_pkg.sv.j2"

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a module directory structure.")
    parser.add_argument('-N',       dest='poly_coef_nb', type=int, help="N: Number of coefficients in a polynomial.", default=512)
    parser.add_argument('-g',       dest='glwe_k',       type=int, help="GLWE_K", default=2)
    parser.add_argument('-l',       dest='pbs_l',        type=int, help="PBS_L: Number of decomposed levels for BR", default=2)
    parser.add_argument('-b',       dest='pbs_b_w',      type=int, help="PBS_B_W: Decomposition base width for BR", default=8)
    parser.add_argument('-L',       dest='ks_l',         type=int, help="KS_L: Number of decomposed levels for KS", default=5)
    parser.add_argument('-B',       dest='ks_b_w',       type=int, help="KS_B_W: Decomposition base width for KS", default=3)
    parser.add_argument('-K',       dest='lwe_k',        type=int, help="LWE_K: Number of blind rotation loop iteration", default=586)
    parser.add_argument('-q',       dest='mod_q',        type=str, help="MOD_Q.", default="2**32")
    parser.add_argument('-W',       dest='mod_q_w',      type=int, help="MOD_Q_W.", default=32)
    parser.add_argument('-r',       dest='mod_ksk',      type=str, help="MOD_KSK.", default="2**32")
    parser.add_argument('-V',       dest='mod_ksk_w',    type=int, help="MOD_KSK_W.", default=32)
    parser.add_argument('-Q',       dest='payload_bit',  type=int, help="PAYLOAD_BIT.", default=4)
    parser.add_argument('-D',       dest='padding_bit',  type=int, help="PADDING_BIT.", default=1)
    parser.add_argument('-d',       dest='use_mean_comp',type=int, help="USE_MEAN_COMP.", default=1)
    parser.add_argument('-n',       dest='name',         type=str, help="APPLICATION_NAME.", default="APPLICATION_NAME_SIMU")
    parser.add_argument('-o',       dest='outfile',      type=str, help="Output filename.", required=True)
    parser.add_argument('-f',       dest='force',        help="Overwrite if file already exists", action="store_true", default=False)

    args = parser.parse_args()

#=====================================================
# Create files
#=====================================================
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)

    config = {"poly_coef_nb" : args.poly_coef_nb,
              "glwe_k"       : args.glwe_k,
              "pbs_l"        : args.pbs_l,
              "pbs_b_w"      : args.pbs_b_w,
              "ks_l"         : args.ks_l,
              "ks_b_w"       : args.ks_b_w,
              "lwe_k"        : args.lwe_k,
              "mod_q"        : args.mod_q,
              "mod_q_w"      : args.mod_q_w,
              "mod_ksk"      : args.mod_ksk,
              "mod_ksk_w"    : args.mod_ksk_w,
              "payload_bit"  : args.payload_bit,
              "padding_bit"  : args.padding_bit,
              "use_mean_comp": args.use_mean_comp,
              "name"         : args.name}


    template = template_env.get_template(TEMPLATE_NAME)
    file_path = args.outfile
    if (os.path.exists(file_path) and not(args.force)):
        sys.exit("ERROR> File {:s} already exists".format(file_path))
    else:
        if (os.path.exists(file_path)):
            print("INFO> File {:s} already exists. Overwrite it.".format(file_path))
        with open(file_path, 'w') as fp:
            fp.write(template.render(config))

