#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Script used to create a ks_common_definition_pkg.sv file.
# ==============================================================================================

import os       # OS functions
import sys      # manage errors
import argparse # parse input argument
import pathlib  # Get current file path
import jinja2
import math

TEMPLATE_NAME = "hpu_part_definition_pkg.sv.j2"

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a module directory structure.")
    parser.add_argument('-head_s_nb',   dest='head_s_nb',  type=int, help="HEAD_S_NB", default=0)
    parser.add_argument('-head_use_pp', dest='head_use_pp',type=int, help="HEAD_USE_PP",default=0)
    parser.add_argument('-mid0_s_nb',   dest='mid0_s_nb',type=int, help="MID0_S_NB",default=5)
    parser.add_argument('-mid0_use_pp', dest='mid0_use_pp',type=int, help="MID0_USE_PP",default=0)
    parser.add_argument('-mid0_s_init', dest='mid0_s_init',type=int, help="MID0_S_INIT",default=9)
    parser.add_argument('-mid1_s_nb',   dest='mid1_s_nb',type=int, help="MID1_S_NB",default=10)
    parser.add_argument('-mid1_use_pp', dest='mid1_use_pp',type=int, help="MID1_USE_PP",default=1)
    parser.add_argument('-mid1_s_init', dest='mid1_s_init',type=int, help="MID1_S_INIT",default=4)
    parser.add_argument('-mid2_s_nb',   dest='mid2_s_nb',type=int, help="MID2_S_NB",default=5)
    parser.add_argument('-mid2_use_pp', dest='mid2_use_pp',type=int, help="MID2_USE_PP",default=0)
    parser.add_argument('-mid2_s_init', dest='mid2_s_init',type=int, help="MID2_S_INIT",default=14)
    parser.add_argument('-mid3_s_nb',   dest='mid3_s_nb',type=int, help="MID3_S_NB",default=0)
    parser.add_argument('-mid3_use_pp', dest='mid3_use_pp',type=int, help="MID3_USE_PP",default=0)
    parser.add_argument('-mid3_s_init', dest='mid3_s_init',type=int, help="MID3_S_INIT",default=0)

    parser.add_argument('-o',  dest='outfile',      type=str, help="Output filename.", required=True)
    parser.add_argument('-f',  dest='force',        help="Overwrite if file already exists", action="store_true", default=False)

    args = parser.parse_args()

#=====================================================
# Create files
#=====================================================
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)

    config = {"head_s_nb" : args.head_s_nb,
              "head_use_pp" : args.head_use_pp,
              "mid0_s_nb" : args.mid0_s_nb,
              "mid0_use_pp" : args.mid0_use_pp,
              "mid0_s_init" : args.mid0_s_init,
              "mid1_s_nb" : args.mid1_s_nb,
              "mid1_use_pp" : args.mid1_use_pp,
              "mid1_s_init" : args.mid1_s_init,
              "mid2_s_nb" : args.mid2_s_nb,
              "mid2_use_pp" : args.mid2_use_pp,
              "mid2_s_init" : args.mid2_s_init,
              "mid3_s_nb" : args.mid3_s_nb,
              "mid3_use_pp" : args.mid3_use_pp,
              "mid3_s_init" : args.mid3_s_init,}


    template = template_env.get_template(TEMPLATE_NAME)
    file_path = args.outfile
    if (os.path.exists(file_path) and not(args.force)):
        sys.exit("ERROR> File {:s} already exists".format(file_path))
    else:
        if (os.path.exists(file_path)):
            print("INFO> File {:s} already exists. Overwrite it.".format(file_path))
        with open(file_path, 'w') as fp:
            fp.write(template.render(config))

