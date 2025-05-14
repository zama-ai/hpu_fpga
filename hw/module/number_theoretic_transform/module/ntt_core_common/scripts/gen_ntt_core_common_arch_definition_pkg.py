#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Script used to create a ntt_definition_pkg.sv file.
# ==============================================================================================

import os       # OS functions
import sys      # manage errors
import argparse # parse input argument
import pathlib  # Get current file path
import jinja2
import re       # regexp

TEMPLATE_NAME = "ntt_core_common_arch_definition_pkg.sv.j2"

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a module directory structure.")
    parser.add_argument('-a', dest='ntt_core_arch', type=str, help="NTT_CORE_ARCH: Architecture type.", default="NTT_CORE_ARCH_wmm_unfold", choices=["NTT_CORE_ARCH_wmm_compact","NTT_CORE_ARCH_wmm_pipeline","NTT_CORE_ARCH_wmm_unfold","NTT_CORE_ARCH_wmm_compact_pcg","NTT_CORE_ARCH_wmm_unfold_pcg", "NTT_CORE_ARCH_gf64"])
    parser.add_argument('-o', dest='outfile',        type=str, help="Output filename.", required=True)
    parser.add_argument('-f', dest='force',          help="Overwrite if file already exists", action="store_true", default=False)

    args = parser.parse_args()

#=====================================================
# Create files
#=====================================================
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)

    arch = args.ntt_core_arch

    config = {"ntt_core_arch" : arch.upper()}

    template = template_env.get_template(TEMPLATE_NAME)
    file_path = args.outfile
    if (os.path.exists(file_path) and not(args.force)):
        sys.exit("ERROR> File {:s} already exists".format(file_path))
    else:
        if (os.path.exists(file_path)):
            print("INFO> File {:s} already exists. Overwrite it.".format(file_path))
        with open(file_path, 'w') as fp:
            fp.write(template.render(config))


