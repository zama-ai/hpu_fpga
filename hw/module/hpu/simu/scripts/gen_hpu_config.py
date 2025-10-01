#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Script used to create hw_hpu_config.ron file.
# ==============================================================================================

import os       # OS functions
import sys      # manage errors
import argparse # parse input argument
import pathlib  # Get current file path
import jinja2
import math

TEMPLATE_NAME = "hpu_config.toml.j2"

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a module directory structure.")
    parser.add_argument('-n',  dest='integer_w',    type=int, help="Integer size", default=8)
    parser.add_argument('--regmap_file',  dest='regmap_file',nargs='+', help="RegisterMap config filenames.", required=True)
    parser.add_argument('-o',  dest='outfile',      type=str, help="Output filename.", required=True)
    parser.add_argument('--cust_iop',  dest='cust_iop', action='append', type=str, help="Custom IOP", default=[])
    parser.add_argument('--min_batch_size',  dest='min_batch_size', type=int, help="Minimal batch size", default=4)
    parser.add_argument('--dop_implementation',  dest='dop_implementation', type=str, help="DOp implementation", choices=["Ilp", "Llt"], default="Ilp")
    parser.add_argument('-f',  dest='force',        help="Overwrite if file already exists", action="store_true", default=False)

    args = parser.parse_args()

#=====================================================
# Create files
#=====================================================
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)

# Convert list of iop file in dict of {iop_id: filename}
    cust_iop = {}
    for f in args.cust_iop:
        import re;
        match = re.match(r".*IOP_(?P<id>\d+)\.asm", f)
        if match is None:
            sys.exit("ERROR> File {:s} invalid name".format(f))
        else:
            cust_iop[match["id"]] = f

    config = dict(args.__dict__)
    config.update({ "cust_iop" : cust_iop, })

    template = template_env.get_template(TEMPLATE_NAME)
    file_path = args.outfile
    if (os.path.exists(file_path) and not(args.force)):
        sys.exit("ERROR> File {:s} already exists".format(file_path))
    else:
        if (os.path.exists(file_path)):
            print("INFO> File {:s} already exists. Overwrite it.".format(file_path))
        with open(file_path, 'w') as fp:
            fp.write(template.render(config))

