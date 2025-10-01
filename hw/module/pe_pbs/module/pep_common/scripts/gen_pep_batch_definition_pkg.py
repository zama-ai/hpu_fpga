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

TEMPLATE_NAME = "pep_batch_definition_pkg.sv.j2"

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a module directory structure.")
    parser.add_argument('-g',  dest='gram_nb',      type=int, help="GRAM_NB: Number of parallel GRAMs.", default=None)
    parser.add_argument('-c',  dest='batch_pbs_nb', type=int, help="BATCH_PBS_NB: Maximal number of PBS per batch.", default=8)
    parser.add_argument('-H',  dest='total_pbs_nb', type=int, help="TOTAL_PBS_NB: Number of PBS locations.", default=32)
    parser.add_argument('-o',  dest='outfile',      type=str, help="Output filename.", required=True)
    parser.add_argument('-f',  dest='force',        help="Overwrite if file already exists", action="store_true", default=False)

    args = parser.parse_args()

#=====================================================
# Create files
#=====================================================
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)

    # In HPU there is 1 single batch that is running at a time.
    batch_nb = 1
    total_batch_nb = 1
    total_pbs_nb = args.total_pbs_nb
    # Check that total_pbs_nb >= batch_pbs_nb
    if (args.total_pbs_nb < args.batch_pbs_nb):
          sys.exit("ERROR> TOTAL_PBS_NB ({:0d}) should be greater or equal to BATCH_PBS_NB ({:0d}).".format(args.total_pbs_nb,args.batch_pbs_nb))

    if(args.gram_nb is None):
        args.gram_nb = 4 # The user doesn't care about gram_nb, set a sane default nevertheless
    elif (args.total_pbs_nb % args.gram_nb):
        sys.exit("ERROR> TOTAL_PBS_NB ({:0d}) should be a multiple of GRAM_NB ({:0d}).".format(args.total_pbs_nb,args.gram_nb))

    config = {"gram_nb" : args.gram_nb,
              "batch_nb" : batch_nb,
              "total_batch_nb" : total_batch_nb,
              "batch_pbs_nb" : args.batch_pbs_nb,
              "total_pbs_nb" : total_pbs_nb,}


    template = template_env.get_template(TEMPLATE_NAME)
    file_path = args.outfile
    if (os.path.exists(file_path) and not(args.force)):
        sys.exit("ERROR> File {:s} already exists".format(file_path))
    else:
        if (os.path.exists(file_path)):
            print("INFO> File {:s} already exists. Overwrite it.".format(file_path))
        with open(file_path, 'w') as fp:
            fp.write(template.render(config))

