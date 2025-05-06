#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Version    : 1.1
# ----------------------------------------------------------------------------------------------
#  Script used to create the directory structure of a module.
#  It also creates the files sketeton.
#  <my_module>
#        info
#                file_list.json
#        rtl
#                <my_module>.sv
#        constraint
#                <my_module>_timing_constraints_local.tcl
#        simu
#                info
#                        file_list.json
#                rtl
#                        tb_<my_module>.sv
#                scripts
#                        run_simu.sh
# ----------------------------------------------------------------------------------------------
#  Version 1.0 : initial version
#  Version 1.1 : Use tb_<my_module>.sv instead of tb.sv.
#                Create a scripts directory for the simulation scripts.
# ==============================================================================================

import os       # OS functions
import sys      # manage errors
import argparse # parse input argument
import warnings # manage warning
import pathlib  # Get current file path
import jinja2
import stat

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':


#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a module directory structure.")
    parser.add_argument('-m', dest='name', type=str, help="Module's name.", required=True)
    parser.add_argument('-p', dest='path', type=str, help="Path to the module root directory.", required=True)

    args = parser.parse_args()


#=====================================================
# Check input args
#=====================================================
# Check that the path exists.
    if not(os.path.exists(os.path.abspath(args.path))):
        sys.exit("ERROR> Unknown path {:s}.".format(os.path.abspath(args.path)))

    parent_dir = os.path.normpath(os.path.expanduser(args.path))


#=====================================================
# Create directories
#=====================================================

    # module directory
    module_path = os.path.join(parent_dir, args.name)
    try:
        os.mkdir(module_path)
    except FileExistsError:
        warnings.warn("WARNING> Directory {:s} already exists".format(module_path))

    # info directory
    info_path = os.path.join(module_path, "info")
    try:
        os.mkdir(info_path)
    except FileExistsError:
        warnings.warn("WARNING> Directory {:s} already exists".format(info_path))

    # rtl directory
    rtl_path = os.path.join(module_path, "rtl")
    try:
        os.mkdir(rtl_path)
    except FileExistsError:
        warnings.warn("WARNING> Directory {:s} already exists".format(rtl_path))

    # contraint directory
    constraint_path = os.path.join(module_path, "constraint")
    try:
        os.mkdir(constraint_path)
    except FileExistsError:
        warnings.warn("WARNING> Directory {:s} already exists".format(constraint_path))

    # simu directory
    simu_path = os.path.join(module_path, "simu")
    try:
        os.mkdir(simu_path)
    except FileExistsError:
        warnings.warn("WARNING> Directory {:s} already exists".format(simu_path))

    # simu/info directory
    simu_info_path = os.path.join(simu_path, "info")
    try:
        os.mkdir(simu_info_path)
    except FileExistsError:
        warnings.warn("WARNING> Directory {:s} already exists".format(simu_info_path))

    # simu/rtl directory
    simu_rtl_path = os.path.join(simu_path, "rtl")
    try:
        os.mkdir(simu_rtl_path)
    except FileExistsError:
        warnings.warn("WARNING> Directory {:s} already exists".format(simu_rtl_path))

    # simu/scripts directory
    simu_scripts_path = os.path.join(simu_path, "scripts")
    try:
        os.mkdir(simu_scripts_path)
    except FileExistsError:
        warnings.warn("WARNING> Directory {:s} already exists".format(simu_scripts_path))

#=====================================================
# Create files
#=====================================================
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)

    if not(os.getenv("PROJECT_DIR")):
        sys.exit("ERROR> Environment variable $PROJECT_DIR not defined.")


    module_path_rel = os.path.relpath(module_path, os.getenv("PROJECT_DIR"))


    config = {"name" : args.name,
              "module_path" : module_path_rel}


    # create_file_l contains tuple which associates the template name, the file name and the path.
    create_file_l = []
    create_file_l.append(("file_list.json.j2",
                          "file_list.json",
                          info_path))
    create_file_l.append(("my_module.sv.j2",
                          "{:s}.sv".format(args.name),
                          rtl_path))
    create_file_l.append(("my_module_timing_constraints_local.xdc.j2",
                          "{:s}_timing_constraints_local.xdc".format(args.name),
                          constraint_path))
    create_file_l.append(("simu_file_list.json.j2",
                          "file_list.json",
                          simu_info_path))
    create_file_l.append(("tb.sv.j2",
                          "tb_{:s}.sv".format(args.name),
                          simu_rtl_path))
    create_file_l.append(("run_simu.sh.j2",
                          "run_simu.sh",
                          simu_scripts_path))
    create_file_l.append(("run.sh.j2",
                          "run.sh",
                          simu_scripts_path))

    for t,n,p in create_file_l:
        template = template_env.get_template(t)

        file_path = os.path.join(p, n)
        if (os.path.exists(file_path)):
            warnings.warn("WARNING> File {:s} already exists".format(file_path))
        else:
            with open(file_path, 'w') as fp:
                fp.write(template.render(config))

    # Change permission of run_simu.sh file : into executable
    os.chmod(os.path.join(simu_scripts_path,"run_simu.sh"), stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH |
                                                            stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH |
                                                            stat.S_IWUSR | stat.S_IWGRP )
    os.chmod(os.path.join(simu_scripts_path,"run.sh"), stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH |
                                                       stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH |
                                                       stat.S_IWUSR | stat.S_IWGRP )
