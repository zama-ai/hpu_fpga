#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Script used to create a param_ntt_definition_pkg.sv file.
# ==============================================================================================

import os       # OS functions
import sys      # manage errors
import argparse # parse input argument
import pathlib  # Get current file path
import jinja2

TEMPLATE_NAME = "param_ntt_definition_pkg.sv.j2"

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a module directory structure.")
    parser.add_argument('-w', dest='mod_w',        type=int, help="MOD_NTT_W: Modulo width.", default=32)
    parser.add_argument('-m', dest='mod_ntt',      type=str, help="MOD_NTT", default="2**32-2*17-2**13+1")
    parser.add_argument('-t', dest='mod_type',     type=str, help="MOD_NTT_TYPE: modulo type", default="SOLINAS3")
    parser.add_argument('-T', dest='mod_inv_type', type=str, help="MOD_NTT_INV_TYPE: modulo inverse type", default="<MOD_NTT_TYPE>_INV")
    parser.add_argument('-n', dest='mod_ntt_name', type=str, help="MOD_NTT_NAME: modulo inverse type", default="MOD_NTT_NAME_SIMU")
    parser.add_argument('-N', dest='mod_ntt_name_s', type=str, help="MOD_NTT_NAME_S: modulo inverse type", default="MOD_NTT_NAME_SIMU_S")
    parser.add_argument('-o', dest='outfile',      type=str, help="Output filename.", required=True)
    parser.add_argument('-f', dest='force',        help="Overwrite if file already exists", action="store_true", default=False)

    args = parser.parse_args()

    if (args.mod_inv_type == "<MOD_NTT_TYPE>_INV"):
        MOD_NTT_INV_TYPE = "{:s}_INV".format(args.mod_type)
    else:
        MOD_NTT_INV_TYPE = args.mod_inv_type

#=====================================================
# Create files
#=====================================================
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)

    config = {"mod_w"     : args.mod_w,
              "mod_ntt"   : args.mod_ntt,
              "mod_type"  : args.mod_type,
              "mod_inv_type"   : MOD_NTT_INV_TYPE,
              "mod_ntt_name"   : args.mod_ntt_name,
              "mod_ntt_name_s" : args.mod_ntt_name_s}


    template = template_env.get_template(TEMPLATE_NAME)
    file_path = args.outfile
    if (os.path.exists(file_path) and not(args.force)):
        sys.exit("ERROR> File {:s} already exists".format(file_path))
    else:
        if (os.path.exists(file_path)):
            print("INFO> File {:s} already exists. Overwrite it.".format(file_path))
        with open(file_path, 'w') as fp:
            fp.write(template.render(config))


