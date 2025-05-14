#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Script used to a basic file_list.json for the given file list.
# ==============================================================================================

import sys      # manage errors
import argparse # parse input argument
import os
import json

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a module directory structure.")
    parser.add_argument('-o', dest='outfile', type=str, help="Output file name.", required=True)
    parser.add_argument('-R', dest='file_l', type=str, help="File name. Need 4 arguments : Module's path+name relative to PROJECT_DIR, env (simu/all), is_include_file (1/0), is_generated_file(1/0).", nargs=4, action='append', default=[])
    parser.add_argument('-r', dest='file_l', type=str, help="Module's path+name relative to PROJECT_DIR. Arguments are put to default values (env:all, is_include_file:0, is_generated_file:0)", nargs=1, action='append', default=[])
    parser.add_argument('-F', dest='flag_l', type=str, help="Flag. Need 3 arguments : Module's path+name relative to PROJECT_DIR (the same given in -r or -R), flag name, flag value.", nargs=3, action='append', default=[])
    parser.add_argument('-l', dest='library', type=str, help="Library.", default="work")
    parser.add_argument('-i', dest='is_include_dir', help="Is include dir.", action="store_true", default=False)
    parser.add_argument('-p', dest='local_root_path', type=str, help="local_root_path.", default="${PROJECT_DIR}")

    args = parser.parse_args()

    OUTFILE = args.outfile
    FILE_L = args.file_l
    FLAG_L = args.flag_l

    flag_d = {}
    for f in FLAG_L:
        if not(f[0] in flag_d.keys()):
            flag_d[f[0]] = {}
        flag_d[f[0]][f[1]] = f[2]

    json_d = {}

    json_d["local_root_path"] = args.local_root_path
    json_d["dep_root_path"] = "${PROJECT_DIR}"
    json_d["is_include_dir"] = args.is_include_dir
    json_d["rtl_files"] = []
    json_d["dependency_dir"] = ["hw/common_lib/common_package"]
    json_d["include_dir"] = []
    json_d["constraint_files"] = []

    print(FILE_L)

    for f in FILE_L:
        d = {}
        d["name"] = f[0]
        d["library"] = args.library
        d["target"] = ["all"]
        try:
            d["env"] = [f[1]]
            d["is_included_file"] = bool(int(f[2]))
            d["is_generated"] = bool(int(f[3]))
        except IndexError:
            d["env"] = ["all"]
            d["is_included_file"] = False
            d["is_generated"] = False
        try:
            for flag in flag_d[d["name"]]:
                d[flag] = flag_d[d["name"]][flag]
        except KeyError:
            None
        json_d["rtl_files"].append(d)

    json_formatted_str = json.dumps(json_d, indent=4)

    with open(OUTFILE, 'w') as json_file:
        json_file.write(json_formatted_str)

