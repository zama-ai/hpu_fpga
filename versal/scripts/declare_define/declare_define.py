#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Version    : 1.1
# ----------------------------------------------------------------------------------------------
#  Script used to create top level list of defines at synth time.
# ----------------------------------------------------------------------------------------------
#  Version 1.0 : initial version
#  Version 1.1 : Create file in output_dir/rtl/inc instead of output_dir
# ==============================================================================================

import os       # OS functions
import sys      # manage errors
import argparse # parse input argument
import warnings # manage warning
import pathlib  # Get current file path
import re
import jinja2

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':


#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a file with set of user define")
    parser.add_argument('-d', dest='output_dir', type=str, help="compilation output dir", required=True)
    parser.add_argument('-f', dest='output_file', type=str, help="name of file to be created (default: top_defines_inc.sv)", default="top_defines_inc.sv")
    parser.add_argument('-l', dest='define_list', type=str, help="List of defines to be added", required=True)

    args = parser.parse_args()

#=====================================================
# Create include file
#=====================================================
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)

    if not(os.getenv("PROJECT_DIR")):
        sys.exit("ERROR> Environment variable $PROJECT_DIR not defined.")

    split_define_list = args.define_list.split(' ')
    formatted_define_list = []

    p = re.compile("[DP]:([A-Za-z0-9_]*)=(.*)")
    for i in split_define_list:
        if len(i) > 0:
            if not p.match(i):
                sys.exit("ERROR> Unsupported element {} in list of parameters & defines which should only contain <D:DEFINE_NAME=VALUE> or <P:PARAM_NAME=VALUE>".format(i))
            elif i[0] == 'D':
                define_tuple = i[2:].split('=')
                formatted_define_list.append((define_tuple[0], define_tuple[1]))

    config = {"defines" : formatted_define_list}

    template = template_env.get_template("top_defines_inc.sv.j2")

    file_path = os.path.join(args.output_dir, "rtl/inc")
    pathlib.Path(file_path).mkdir(parents=True, exist_ok=True)
    file_path = os.path.join(file_path,args.output_file)

    with open(file_path, 'w', encoding="utf-8") as fp:
        fp.write(template.render(config))

