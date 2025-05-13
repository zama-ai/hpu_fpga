#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  This script is EDAlize wrapper.
#  Works with EDAlize b3816793b9c0583ddd2184f696053d79f4edbca7
# ==============================================================================================

import argparse # parse input argument
import os       # OS functions
import sys      # manage errors
import shutil
import time     # seed
from edalize import *
import json
import re
import warnings
from pathlib import Path
import subprocess as sbprc

#=====================================================
# Global variables
#=====================================================
VERBOSE = False
PROJECT_DIR = ""
FILE_EXTENSION = {".asm"     : "asmSource",
                  ".c"       : "cSource",
                  ".cpp"     : "cppSource",
                  ".e"       : "eSource",
                  ".ova"     : "OVASource",
                  ".pl"      : "perlSource",
                  ".psl"     : "pslSource",
                  ".tcl"     : "tclSource",
                  ".vera"    : "veraSource",
                  ".systemC" : "systemCSource",
                  ".sv"      : "systemVerilogSource",
                  ".v"       : "verilogSource",
                  ".vh"      : "verilogSource",
                  ".vhd"     : "vhdlSource",
                  ".sdc"     : "SDC",
                  ".xci"     : "xci",
                  ".xdc"     : "xdc",
                  ".qip"     : "QIP",
                  ".ucf"     : "UCF",
                  ".sva"     : "SVASource"}
EDALIZE_STAGES = ["config", "build", "run"]
SUPPORTED_TOOL_OPTIONS = {"vivado"        : ["part"],
                          "xsim"          : [],
                          "modelsim"      : [],
                          "vcs"           : ["wave_hier"],
                          "veribleformat" : []}
SUPPORTED_TOOL_FEATURES = {"vivado"        : ["ooc"],
                           "xsim"          : ["wave", "cov"],
                           "modelsim"      : ["wave", "cov"],
                           "vcs"           : ["wave", "wave_dve", "cov", "lint"],
                           "veribleformat" : ["stdout", "rec"]}
ENV_OF_TOOLS = {"vivado"        : ["synth"],
                "tcl_dict"      : ["synth_xrt"],
                "xsim"          : ["simu"],
                "modelsim"      : ["simu"],
                "vcs"           : ["simu"],
                "veribleformat" : []}

VERIBLE_FORMAT_ARGS=[
    '--column_limit',                       '100',
    '--indentation_spaces',                 '2',
    '--line_break_penalty',                 '2',
    '--over_column_limit_penalty',          '100',
    '--wrap_spaces',                        '4',
    '--assignment_statement_alignment',     'align',
    '--case_items_alignment',               'align',
    '--class_member_variable_alignment',    'align',
    '--distribution_items_alignment',       'align',
    '--enum_assignment_statement_alignment','align',
    '--formal_parameters_alignment',        'align',
    '--formal_parameters_indentation',      'indent',
    '--module_net_variable_alignment',      'align',
    '--named_parameter_alignment',          'align',
    '--named_parameter_indentation',        'indent',
    '--named_port_alignment',               'align',
    '--named_port_indentation',             'indent',
    '--port_declarations_alignment',        'align',
    '--port_declarations_indentation',      'indent',
    '--struct_union_members_alignment',     'align',
    '--expand_coverpoints',
    '--port_declarations_right_align_packed_dimensions',
    '--port_declarations_right_align_unpacked_dimensions',
    '--compact_indexing_and_selections',
    '--try_wrap_long_lines'
]


# To ease stdout reading:
ERROR_PRINT = "\u001b[31;1mERROR>"
VALID_PRINT = "\u001b[32m"
BOLD_PRINT  = "\u001b[37;1m"
RESET_COLOR = "\u001b[0m"

#=====================================================
# print_severity
#=====================================================
def print_severity(severity_lvl, msg):
    '''
    According to the SEVERITY value, and current message severity level, the message is considered as an info, warning or an error.
    Note that if it is an error, we exit the program.
    '''
    print_lvl = severity_lvl
    if (SEVERITY == 'low'):
        print_lvl = severity_lvl
    elif (SEVERITY == 'high'):
        if (severity_lvl == "INFO"):
            print_lvl = severity_lvl
        elif (severity_lvl == "WARNING") or (severity_lvl == "ERROR"):
            print_lvl = "ERROR"

    if (print_lvl != "ERROR"):
        print("{:s}> {:s}".format(print_lvl, msg))
    else:
        sys.exit("ERROR> "+msg)

#=====================================================
# normalize_path
#=====================================================
def normalize_path (path, root_path):
    '''
    input :
        path      : user given path relative to root_path.
        root_path : root path from which to consider path.
    output :
        normalized path
    Output a global path, where project's env variables (if used) have been replaced.
    '''
    path = os.path.expandvars(path)
    root_path = os.path.expandvars(root_path)
    if (len(path) == 0):
        return path
    elif  (os.path.isabs(path)):
        return os.path.abspath(os.path.expandvars(path))
    else:
        return os.path.abspath(os.path.join(root_path, path))


#=====================================================
# get_file_type
#=====================================================
def get_file_type(file_name):
        # file_name_split[1] contains the file extension
        file_name_split = os.path.splitext(file_name)
        return FILE_EXTENSION[file_name_split[1]]


#=====================================================
# parse_files
#=====================================================
def parse_files(file_list_path, files_d, recursive, tool_env, parse_flag_d, is_top, sva_l):
    '''
    Parse the json file_list, extract the file names of "rtl_files", and recursively retrieve the rtl_files
    of the dependencies.
    If tool_env is not empty, it is a list of string used to filter out rtl files with env different from tool_env
    If parse_flag_d is given, parse according to the given flags.
    If none of the flags is present, parse the file.
    If all the flags of the list are present, parse the file that matches all.
    If some of the flags of the list are present, parse the file for which the present flags match.
    '''

    # Open file_list.json
    try:
        with open(file_list_path) as file_list_fp:
            file_d = json.load(file_list_fp)
    except FileNotFoundError:
        sys.exit(ERROR_PRINT + " file_list not found: {:s}.".format(file_list_path) + RESET_COLOR)


    info_dir_path = os.path.dirname(os.path.abspath(file_list_path))

    if (VERBOSE):
        print("INFO> Parsing file_list : {:s}".format(file_list_path))


    # Normalize root paths
    if ("local_root_path" in file_d):
        local_root_path = normalize_path(file_d["local_root_path"], info_dir_path)
    else:
        # local_root_path is not used. Local file paths given in the file should be absolute
        local_root_path = ""

    if ("dep_root_path" in file_d):
        dep_root_path = normalize_path(file_d["dep_root_path"], info_dir_path)
    else:
        # dep_root_path is not used. Dependency paths given in the file should be absolute
        dep_root_path = ""

    if (VERBOSE):
        print("INFO>  local_root_path : {:s}".format(local_root_path))
        print("INFO>  dep_root_path   : {:s}".format(dep_root_path))

    # is_include_dir
    if ("is_include_dir" in file_d):
        is_include_dir = file_d["is_include_dir"]
    else:
        # current directory is not an include dir
        is_include_dir = False

    # use_flag
    # This entry defines the mandatory flags that define the current module.
    # Apply this flag on the current file and dependency selection.
    if ("use_flag" in file_d):
        use_flag_d = file_d["use_flag"][0]
        print("=========================================================== ")
        print("Module's defined Parse flags : {:s}".format(info_dir_path))
        for f,v in use_flag_d.items():
            print(" "+str(f)+" : "+str(v))
        print("=========================================================== ")

    else:
        # No use_flag defined
        use_flag_d = {}

    # Check flags
    flag_s = set(parse_flag_d.keys()).intersection(use_flag_d.keys()) # look among common flags
    cur_flag_d = parse_flag_d.copy()
    for flag in flag_s:
        if not (use_flag_d[flag] in parse_flag_d[flag]):
            print_severity("WARNING","Flag parsing conflict for flag={:s}: parse_flag={:s} does not contain use_flag={:s}".format(flag, str(parse_flag_d[flag]), use_flag_d[flag]))
            print("WARNING> For flag {:s}, the parsing will only take the following values into account : {:s}".format(flag, str(parse_flag_d[flag])))
    flag_s = set(use_flag_d.keys()).difference(parse_flag_d.keys()) # look at flags that are only in use_flag_d
    for flag in flag_s:
        cur_flag_d[flag] = []
        cur_flag_d[flag].append(use_flag_d[flag])

    if (VERBOSE):
        print("INFO> Do parsing with flags : {:s}".format(str(cur_flag_d)))

    # Include dir
    include_dir_l = []
    if (recursive):
        if ("include_dir" in file_d):
            for inc_item in file_d["include_dir"]:
                inc_flag_d = {}
                try:
                    for k in inc_item.keys():
                        if (k == "name"):
                            inc = inc_item[k]
                        else:
                            inc_flag_d[k] = inc_item[k]
                except AttributeError:
                    inc = inc_item

                # Look at the flags
                flag_s = set(cur_flag_d.keys())
                inc_flag_s = set(inc_flag_d.keys())
                do_parse = True
                for flag in flag_s.intersection(inc_flag_s):
                    if not(str(inc_flag_d[flag]) in cur_flag_d[flag]):
                        do_parse = False
                if (do_parse):
                    inc_path = normalize_path(inc, dep_root_path)
                    if (VERBOSE):
                        print("INFO> inc_path   : {:s}".format(inc_path))
                    include_dir_l.append(inc_path)


    # Parse dependencies
    if (recursive):
        if ("dependency_dir" in file_d):
            for dep_item in file_d["dependency_dir"]:
                dep_flag_d = {}
                try:
                    for k in dep_item.keys():
                        if (k == "name"):
                            dep = dep_item[k]
                        elif (k == "optional"):
                            dep_optional = dep_item[k]
                        else:
                            dep_flag_d[k] = dep_item[k]
                except AttributeError:
                    dep = dep_item
                    dep_optional = False

                # Look at the flags
                flag_s = set(cur_flag_d.keys())
                dep_flag_s = set(dep_flag_d.keys())
                do_parse = True
                for flag in flag_s.intersection(dep_flag_s):
                    if not(str(dep_flag_d[flag]) in cur_flag_d[flag]):
                        do_parse = False
                if (VERBOSE):
                    print("INFO> do_parse : {:b}, dep: {:s}".format(do_parse,dep))
                if (do_parse):
                    dep_path = normalize_path(dep, dep_root_path)
                    if (VERBOSE):
                        print("INFO>  dep_path   : {:s}".format(dep_path))
                    dep_file_list_path = os.path.join(dep_path, "info/file_list.json")
                    do_continue = True
                    if (dep_optional and not(Path(dep_file_list_path).is_file())):
                        # Check that the file exists
                        # If not do not parse
                        do_continue = False
                        if (VERBOSE):
                            print(f"INFO> Optional dependency, not present, not used : {dep}")
                    if (do_continue):
                        parse_files(dep_file_list_path, files_d, recursive, tool_env, cur_flag_d, False, sva_l)


    # Parse rtl_files
    for f in file_d["rtl_files"]:
        # Look at the flags
        flag_s = set(cur_flag_d.keys())
        file_flag_s = set(f.keys())
        do_parse = True
        for flag in flag_s.intersection(file_flag_s):
            if not(str(f[flag]) in cur_flag_d[flag]):
                do_parse = False
                if (VERBOSE):
                    print("INFO> Flag mismatches reject exp[{:s}]={:s}, seen={:s} : {:s}".format(flag, str(cur_flag_d[flag]), str(f[flag]), f["name"]))

        if ("env" in f) and ("all" not in f["env"]) and (len(tool_env) > 0):
            file_env_set = set(f["env"])
            tool_env_set = set(tool_env)
            if not (file_env_set & tool_env_set):
                if (VERBOSE):
                    print("INFO> file {} has been removed from list because tool env ({}) does not match with file env ({})".format(f["name"], tool_env, f["env"]))
                do_parse = False

        if ("sva" in f) and ("all" not in sva_l) and (f["sva"] not in sva_l):
            do_parse = False

        if (do_parse):
            file_path = normalize_path(f["name"], local_root_path)
            if (VERBOSE):
                print("INFO> rtl_file!! : {:s}".format(file_path))
            file_name = os.path.basename(f["name"])
            file_type = get_file_type(file_name)
            entry = {'name': file_path,
                 'file_type': file_type}
            try:
                entry['is_include_file'] = f['is_include_file']
            except KeyError:
                 entry['is_include_file'] = is_include_dir

            if (len(include_dir_l)>0):
                entry['include_path'] = include_dir_l

            if (file_type == "vhdlSource" or file_type == "systemVerilogSource"):
                entry["logical_name"] = f["library"]
            if file_name in files_d.keys():
                if (entry['name'] != files_d[file_name]['name']):
                    print("WARNING> Same file given several times: {:s}\n  use:\t\t{:s},\n  instead of:\t{:s}".format(file_name, entry['name'],files_d[file_name]['name']));
            files_d[file_name] = entry


    # Parse constraint_files
    if ("constraint_files" in file_d):
        for c in file_d["constraint_files"]:
            file_path = normalize_path(c, local_root_path)
            file_name = os.path.basename(c)
            file_type = get_file_type(file_name)
            entry = {'name': file_path,
                     'file_type': file_type}
            if (is_top or file_name.endswith("constraints_hier.xdc")):
              files_d[file_name] = entry
              if (VERBOSE):
                print("INFO> constraint_file : {:s}".format(file_path))

#=====================================================
# Search for the file list
#=====================================================
def search_file_list(top_name):

    file_list = []
    extensions = ['.v', '.sv']

    ## Search for the file list from two directory above
    path_hw = os.getenv("PROJECT_DIR") + '/hw'
    path_fw = os.getenv("PROJECT_DIR") + '/fw/gen'

    # Fill the list with all the /info/ directories
    for root, directories, files in os.walk(path_hw, topdown=True):
        for file_name in files:
            for i in extensions:
                if (file_name == top_name + i):
                    file_list.append(os.path.join(root, file_name))

    for root, directories, files in os.walk(path_fw, topdown=True):
        for file_name in files:
            for i in extensions:
                if (file_name == top_name + i):
                    file_list.append(os.path.join(root, file_name))

    if (len(file_list) > 1 ):
        sys.exit(ERROR_PRINT + " Top name not explicit." + RESET_COLOR)
    elif (len(file_list) == 0 ):
        sys.exit(ERROR_PRINT + " File list not found." + RESET_COLOR)


    # Get the path and remove top name and the last directory
    work_path = str(file_list[0]).rsplit("/",2)

    # Return the path of the file list
    return work_path[0] + "/info/file_list.json"

#=====================================================
# Dump files list in a preformated tcl dictionary.
#=====================================================
def dump_config_as_tcl_dict(args):
    # Open tcl environment file
    tcl_path = Path(args.tcl_dict_out) if Path(args.tcl_dict_out).is_absolute() else Path.cwd() / args.tcl_dict_out
    tcl_dict = "Edalize_Dict"
    SEP_WoEol  = '\\\n\t'

    with tcl_path.open(mode='w') as tcl_f:
      # Tcl header, Global path and project name
      tcl_f.write('#!/bin/tclsh\n')
      tcl_f.write('\n')
      tcl_f.write('# Global path & Name {{{\n')
      tcl_f.write('set design_top %s\n'%(args.top_name))
      tcl_f.write('# }}} \n')

      # Git revision
      git_head = sbprc.check_output(['git', 'config', '--get', 'remote.origin.url']).decode('utf8').strip('\n')
      git_rev = sbprc.check_output(['git', 'rev-parse', 'HEAD']).decode('utf8').strip('\n')
      tcl_f.write('# Git repository and revision {{{\n')
      tcl_f.write('dict set %s rtl_origin "%s"\n'%(tcl_dict, git_head))
      tcl_f.write('dict set %s rtl_revision "%s"\n'%(tcl_dict, git_rev))
      tcl_f.write('# }}} \n')

      # Export design and lib Source files # {{{
      tcl_f.write('# List of design RTL file {{{\n')

      # Vlog
      vlog_files = [f['name'] for f in files_l if f['file_type'] == 'verilogSource']
      tcl_f.write('dict set %s vlog [ list %s %s\n]\n'%(tcl_dict, SEP_WoEol, SEP_WoEol.join(vlog_files)))

      # SystemVlog
      svlog_files = [f['name'] for f in files_l if f['file_type'] == 'systemVerilogSource']
      tcl_f.write('dict set %s svlog [ list %s %s\n]\n'%(tcl_dict, SEP_WoEol, SEP_WoEol.join(svlog_files)))
      # }}}

      # Constraint files
      tcl_f.write('# List of Constraints files {{{\n')
      xdc_files = [f['name'] for f in files_l if f['file_type'] == 'xdc']
      tcl_f.write('dict set %s xdc [ list %s %s\n]\n'%(tcl_dict, SEP_WoEol, SEP_WoEol.join(xdc_files)))

      # TODO extend dict with others properties

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Run EDAlize.")
    parser.add_argument('-m', dest='top_name', type=str, help="Top module's name.", required=True)
    parser.add_argument('-f', dest='file_list', type=str, help="File list.", default="__default__")
    parser.add_argument('-t', dest='tool', type=str, help="EDA tool.", required=True)
    parser.add_argument('-d', dest='work_root_dir', type=str, help="Work root directory. Results are in <work_root_dir>/<tool>/<top_name>. Default: ${PROJECT_DIR}/hw/output. ", default=os.path.expandvars("__default__"))
    parser.add_argument('-a', dest='tool_option_l', type=str, help='Tool additional options. Fields are separated with ":" : "option_name:option_value<:option_value>".', action='append')
    parser.add_argument('-e', dest='tool_feature_en_l', type=str, help='Enable tool features.', choices=['wave', 'wave_dve', 'ooc', 'cov', 'stdout', 'rec', 'lint'] , action='append')
    parser.add_argument('-r', dest='simulation_time', type=str, help='Simulation time given to run command.')
    parser.add_argument('-y', dest='skip_stage_l', type=str, help="EDAlize skipped stages. Default : []", choices=['config','build','run'] , action='append', default = [])
    parser.add_argument('-k', dest='work_directory_strategy', type=str, help="Indicate what the behavior in case the work directory already exists. Note that if 'keep' is chosen, the config phase is not done. Default : delete", choices=['delete','copy','keep'], default='delete')
    parser.add_argument('-s', dest='seed', type=int, help="Seed value. Default : current time", default=int(time.time()*1000000000000000) & 0xFFFFFFFFFFFF)
    parser.add_argument('-g', dest='gui', help="Run in gui mode.", action="store_true", default=False)
    parser.add_argument('-gv', dest='gui_verdi', help="Run in verdi gui mode.", action="store_true", default=False)
    parser.add_argument('-w', dest='wavetcl', help="Tcl file to be executed instead of the default one when processing wave. (define signals to log)")
    parser.add_argument('-F', dest='flag_l', type=str, help="User defined parsing flags. Needs 2 arguments, the flag name and its value. If several values are given for the same flag name, the parsing will do a OR. If different flags are present, the parser will do an AND.", nargs=2, action='append')
    parser.add_argument('-P', dest='param_l', type=str, help="Parameter taken into account at compile-time. Needs 3 arguments, the parameter name, its type (bool, file, int, str) its value. Note that 0b and 0x prefixes are supported for int.", nargs=3, action='append')
    parser.add_argument('-D', dest='define_l', type=str, help="Define taken into account at compile-time. Needs 3 arguments, the define name, its type (bool, file, int, str) its value. Note that 0b and 0x prefixes are supported for int.", nargs=3, action='append')
    parser.add_argument('-A', dest='tool_option_file', type=str, help='File containing tool additional options. In each line : option_name option_value <option_value>.', default="__default__")
    parser.add_argument('-S', dest="severity", type=str, help="Parsing severity level. low : flag parsing conflict are reported; high : flag parsing conflict are reported as error", choices=['low', 'high'], default='low')
    parser.add_argument('-sva', dest='sva_l', type=str, help='List of sva to activate. Less priority than flag, if any.', action='append', default = [])
    parser.add_argument('-v', dest='verbose', help="Run in verbose mode.", action="store_true", default=False)

    parser.add_argument('--tcl-dict-out', dest='tcl_dict_out', type=str, help="File path of the outputted tcl dictionary", default='edalize_file_list.tcl')

    args = parser.parse_args()

    VERBOSE = args.verbose
    SEVERITY = args.severity

#=====================================================
# Check environment variables
#=====================================================
    if not(os.getenv("PROJECT_DIR")):
        sys.exit(ERROR_PRINT + " Environment variable $PROJECT_DIR not defined." + RESET_COLOR)
    else:
        PROJECT_DIR = os.getenv("PROJECT_DIR")

#=====================================================
# EDAlize stages
#=====================================================
    # By default run every stages
    run_stage_l = ['config','build','run']
    run_stage_l = list(set(run_stage_l) - set(args.skip_stage_l))

#=====================================================
# Flags
#=====================================================
    parse_flag_d = {}
    try:
        for l in args.flag_l:
            f = l[0]
            v = l[1]
            if not(f in parse_flag_d.keys()):
                parse_flag_d[f] = []
            parse_flag_d[f].append(v)
    except TypeError:
        None

    print("===========================================================")
    print("Parse flags")
    for f,v in parse_flag_d.items():
        print(" "+str(f)+" : "+str(v))
    print("===========================================================")

#=====================================================
# SVA
#=====================================================
    sva_l = args.sva_l;

    print("===========================================================")
    print("Parse sva")
    for f in sva_l:
        print(f"{f}")
    print("===========================================================")

#=====================================================
# Parameters
#=====================================================
    parse_param_d = {}
    try:
        for l in args.param_l:
            f = l[0]
            t = l[1]
            v = l[2]
            if not(f in parse_param_d.keys()):
                parse_param_d[f] = []
            else:
                print_severity("WARNING", "Parameter defined twice. %s will be taken into account.".format(str(l)))
                parse_param_d[f] = []

            if (t == "bool"):
                v = bool(v)
            elif (t == "int"):
                if (v.startswith("0x")):
                    v = int(v, base=16)
                elif (v.startswith("0b")):
                    v = int(v, base=2)
                else:
                    try:
                        v = int(v)
                    except ValueError:
                        sys.exit(ERROR_PRINT + " ERROR : Unknown int type. Should be in decimal format, or in hexa (0x), or binary (0b)" + RESET_COLOR)

            elif (t=="file"):
                v = os.path.abspath(v)
                print(v)

            parse_param_d[f].append(t)
            parse_param_d[f].append(v)
    except TypeError:
        None

    print("===========================================================")
    print("Parse params")
    for f,l_tv in parse_param_d.items():
        print(" "+str(f)+" : "+str(l_tv[0])+" : "+str(l_tv[1]))
    print("===========================================================")

#=====================================================
# define
#=====================================================
    parse_define_d = {}
    try:
        for l in args.define_l:
            f = l[0]
            t = l[1]
            v = l[2]
            if not(f in parse_define_d.keys()):
                parse_define_d[f] = []
            else:
                print_severity("WARNING", "DEFINE defined twice. %s will be taken into account.".format(str(l)))
                parse_define_d[f] = []

            if (t == "bool"):
                v = bool(v)
            elif (t == "int"):
                if (v.startswith("0x")):
                    v = int(v, base=16)
                elif (v.startswith("0b")):
                    v = int(v, base=2)
                else:
                    try:
                        v = int(v)
                    except ValueError:
                        sys.exit(ERROR_PRINT + " ERROR : Unknown int type. Should be in decimal format, or in hexa (0x), or binary (0b)" + RESET_COLOR)

            elif (t=="file"):
                v = os.path.abspath(v)
                print(v)

            parse_define_d[f].append(t)
            parse_define_d[f].append(v)
    except TypeError:
        None

    print("===========================================================")
    print("Parse defines")
    for f,l_tv in parse_define_d.items():
        print(" "+str(f)+" : "+str(l_tv[0])+" : "+str(l_tv[1]))
    print("===========================================================")


#=====================================================
# Create work directory
#=====================================================

    work_root_dir = args.work_root_dir
    if (args.work_root_dir == "__default__"): # Use default directory
        work_root_dir = os.path.join(PROJECT_DIR,"hw","output")
    else:
        work_root_dir = os.path.abspath(work_root_dir)
    work_dir = os.path.join(work_root_dir, args.tool, args.top_name)

    if (os.path.exists(work_dir)):
        if (args.work_directory_strategy == 'delete'):
            print ("INFO> Previous work directory found : {:s}. Deleting it.".format(work_dir))
            shutil.rmtree(work_dir)
            os.makedirs(name=work_dir, exist_ok=True)
        elif (args.work_directory_strategy == 'copy'):
            # find a new name
            work_dir_base = dirname(work_dir)
            l = sorted(list(filter(lambda x : os.path.isdir(os.path.join(work_dir_base,x)) and re.search(r'\A{:s}_(\d+)'.format(args.top_name),x), os.listdir(work_dir_base))))
            if (VERBOSE):
                print ("INFO> Existing directories: "+str(l))
            # l should contain sorted dir name with this format : <args.top_name>_<\d+>
            if (len(l) == 0):
                idx = 1
            else:
                idx = int(l[-1].rsplit('_',1)[1])+1
            old_work_dir = os.path.join(work_root_dir, args.tool, args.top_name+"_"+str(idx))
            print ("INFO> Previous work directory found : {:s}. Moving it into {:s}.".format(work_dir,old_work_dir))
            shutil.move(work_dir, old_work_dir)
            os.makedirs(name=work_dir, exist_ok=True)
        else: # keep
            print ("INFO> Previous work directory found : {:s}. Keep it.".format(work_dir))
            print ("INFO> Config phase will not be run.")
            print ("INFO> Same seed will be used.")
            # Retrieve previous seed.
            with open(os.path.join(work_dir,"seed.txt")) as f:
              args.seed = int(f.readline().rstrip())

            try:
                run_stage_l.remove('config')
            except ValueError:
                # config was already removed
                None
    else:
        print ("INFO> Creating work directory : {:s}".format(work_dir))
        os.makedirs(name=work_dir, exist_ok=True)

    print("===========================================================")
    print("Work directory : {:s}".format(work_dir))
    print("===========================================================")

    # Create link to memory file dir
    memfile_dir = os.path.join(PROJECT_DIR,"hw","memory_file")
    link_memfile_dir = os.path.join(work_dir,"memory_file")
    try:
      os.remove(link_memfile_dir)
    except OSError:
      None
    os.symlink(memfile_dir, link_memfile_dir)
    print("===========================================================")
    print("Link to memory_file directory : {:s} -> {:s}".format(link_memfile_dir, memfile_dir))
    print("===========================================================")

#=====================================================
# Using Seed
#=====================================================
    print("===========================================================")
    print("Using Seed: {:d}".format(args.seed))
    print("===========================================================")
    # Create seed file
    with open(os.path.join(work_dir,"seed.txt"), 'w') as f:
      f.write('{:0d}'.format(args.seed))

#=====================================================
# Parse tool options : set default
#=====================================================
    # tool from args
    tool = args.tool

    # default options
    tool_options_d = {tool:{}}
    tool_options_d[tool]["rec"] = True # by default file_list are parsed recursively
    if (tool == "vivado"):
        tool_options_d[tool]["part"]=os.getenv("XILINX_PART")
        tool_options_d[tool]["ooc"]=False
    elif (tool == "xsim"):
        tool_options_d[tool]["xelab_options"]=["-debug typical"]
        tool_options_d[tool]["xsim_options"]=["-sv_seed {:d}".format(args.seed)]
        tool_options_d[tool]["xsim_options"].append("-ignore_coverage")
        tool_options_d[tool]["cov"] = False
        tool_options_d[tool]["wave"] = False
        try:
            if (args.wavetcl):
                tool_options_d[tool]["xsim_options"].append("-wavetcl {:s}".format(os.path.abspath( args.wavetcl)))
        except TypeError:
            None
    elif (tool == "modelsim"):
        tool_options_d[tool]["vsim_options"]=["-sv_seed {:d}".format(args.seed)]
        tool_options_d[tool]["vopt_options"]=[]
        tool_options_d[tool]["cov"] = False
        tool_options_d[tool]["wave"] = False
        try:
            if (args.wavetcl):
                tool_options_d[tool]["vsim_options"].append("-do \"do  {:s}\"".format(os.path.abspath( args.wavetcl)))
        except TypeError:
            None
    elif (tool == "vcs"):
        # other options tried:
        # -timescale=1ns/10ps' : set timescale but does not force it
        # -override_timescale=1ps/1ps : set same timescale on everything (not possible when using xilinx lib)
        # -noinherit_timescale=1ns/10ps : works along with `resetall in testbench file
        # -fgp (vcs_options) to get multi-thread simulation along with -fgp=num_threads:6 (run_options)
        tool_options_d[tool]["vcs_options"]=['-licwait 10 -diag timescale -noinherit_timescale=1ns/10ps -deraceclockdata +rad -Xkeyopt=rtopt -ntb_opts sensitive_dyn']
        tool_options_d[tool]["run_options"]=['-licwait 10 +ntb_random_seed={:d} -ucli'.format(args.seed)]
        tool_options_d[tool]["vlogan_options"]=['-timescale=1ns/10ps']
        tool_options_d[tool]["vhdlan_options"]=[]
        tool_options_d[tool]["cov"] = False
        tool_options_d[tool]["wave"] = False
        tool_options_d[tool]["wave_dve"] = False
        tool_options_d[tool]["run_simu_options"]=''
        try:
            if (args.simulation_time):
                tool_options_d[tool]["run_simu_options"]='{:s}'.format(args.simulation_time)
        except TypeError:
            None

    elif (tool == "veribleformat"):
        tool_options_d[tool]["inplace"] = True
        tool_options_d[tool]["rec"] = False # Stay at file_list explicitly listed files
        # Verible-verilog-format rules
        tool_options_d[tool]["verible_format_args"] = VERIBLE_FORMAT_ARGS + ['--inplace']


#=====================================================
# Parse tool options
#=====================================================
    try:
        tool_option_l = [] + args.tool_option_l
    except TypeError:
        tool_option_l = []

    # Parse tool option file if any.
    if (args.tool_option_file != "__default__"):
        # Open the file, and parse line by line.
        with open(args.tool_option_file, 'r') as file:
            # Read each line in the file
            for line in file:
                # Ignore comment lines
                line = line.strip()
                if not line.startswith("#"):
                    tool_option_l.append(line)

    # tool options from args
    if (VERBOSE):
        print("===========================================================")
        print("Parsed tool options")
        print(tool_option_l)

    for opt_str in tool_option_l:
        arg_tool_options_split = opt_str.split(":")

        if len(arg_tool_options_split) < 2:
            sys.exit(ERROR_PRINT + ' Wrong tool option format. Should be "option_name:option_value<:option_value>", fields are separated with ":": {:s}'.format(opt_str) + RESET_COLOR)
        if not (arg_tool_options_split[0] in SUPPORTED_TOOL_OPTIONS[tool]):
            sys.exit(ERROR_PRINT + ' Unknown tool option": {:s}'.format(arg_tool_options_split[0]) + RESET_COLOR)
        try:
            tool_options_d[tool][arg_tool_options_split[0]].append(arg_tool_options_split[1:])
        except KeyError:
            tool_options_d[tool][arg_tool_options_split[0]] = [arg_tool_options_split[1:]]

    # tool options from "tool_feature_en"
    try:
        for f in args.tool_feature_en_l:
            if not(f in SUPPORTED_TOOL_FEATURES[tool]):
                sys.exit(ERROR_PRINT + ' Unknown tool feature": {:s}'.format(f) + RESET_COLOR)
            if (f == "ooc"):
                tool_options_d[tool]["ooc"] = True
            elif (f == "wave"):
                tool_options_d[tool]["wave"] = True
                if (tool == "modelsim"):
                    tool_options_d[tool]["vopt_options"].append("-debug")
                    tool_options_d[tool]["vsim_options"].append("-qwavedb=+signal+cell+queue+statictaskfunc+class+memory+maxbits=16000")
                elif (tool == "vcs"):
                    tool_options_d[tool]["vlogan_options"].append('-kdb')
                    tool_options_d[tool]["vhdlan_options"].append('-kdb')
                    tool_options_d[tool]["vcs_options"].append("-kdb -debug_access+all")
                    tool_options_d[tool]["run_options"].append("-lca +fsdb+functions")
            elif (f == "lint"):
                if tool == "vcs":
                    tool_options_d[tool]["vcs_options"].append("+lint=all +warn=all")

            elif (f == "wave_dve"):
                tool_options_d[tool]["wave_dve"] = True
                if (tool == "vcs"):
                    tool_options_d[tool]["vlogan_options"].append('')
                    tool_options_d[tool]["vhdlan_options"].append('')
                    tool_options_d[tool]["vcs_options"].append("-debug_access+all")
                else:
                    sys.exit(ERROR_PRINT + ' feature {:s} is supported only for VCS'.format(f) + RESET_COLOR)

            elif (f == "cov"):
                tool_options_d[tool]["cov"] = True
                tool_options_d[tool]["xsim_options"].remove("-ignore_coverage")
                tool_options_d[tool]["xelab_options"].append("-cc_type -bcst") # enable code coverage for branch, condition, statement, toggle
            elif (f == "stdout"):
                tool_options_d[tool]["inplace"] = False
                tool_options_d[tool]["verible_format_args"].remove('--inplace')
            elif (f == "rec"):
                tool_options_d[tool]["rec"] = True
            else:
                sys.exit(ERROR_PRINT + ' Unknown tool feature": {:s}'.format(f) + RESET_COLOR)
    except TypeError:
        None # no additional user tool feature

#=====================================================
# Parse file_list and build files[] needed by EDAlize
#=====================================================
    if (args.file_list == "__default__"):
        path_to_file_list = search_file_list(args.top_name)
    else:
        path_to_file_list = args.file_list
    files_d = {}
    parse_files(path_to_file_list, files_d, tool_options_d[tool]["rec"], ENV_OF_TOOLS[tool], parse_flag_d, True, sva_l)

    files_l = []
    for k,v in files_d.items():
        files_l.append(v)

    if (VERBOSE):
        print("===========================================================")
        print("Files:")
        for f in files_l:
            print(f['name'])
        print("===========================================================")
        print("Tool options:")
        print (tool_options_d)

#=====================================================
# Hooks
#=====================================================
    hooks_d = {"pre_configure"  : [],
               "post_configure" : [],
               "pre_build"      : [],
               "post_build"     : [],
               "pre_run"        : [],
               "post_run"       : []}

    if (tool == "tcl_dict"):
        dump_config_as_tcl_dict(args)
        print("EARLY_EXIT> Configuration dump as tcl dict")
        sys.exit(0)

    if (tool == "vivado"):
        # Modify <my_module>.tcl
        script = os.path.join(PROJECT_DIR,"hw","script","edalize","hook","hook_post_configure_vivado_compil.sh")
        arg_l = []
        arg_l.append(os.path.join(work_dir,"{:s}.tcl".format(args.top_name)))
        arg_l.append(os.path.join(PROJECT_DIR,"hw","syn","vivado","vivado_properties.tcl"))
        if (tool_options_d["vivado"]["ooc"]):
            arg_l.append(os.path.join(PROJECT_DIR,"hw","syn","vivado","vivado_properties_ooc.tcl"))
        # else set pin assignment
        else:
            arg_l.append(os.path.join(PROJECT_DIR,"hw","syn","vivado", os.environ["PROJECT_TARGET"]+"_pin_assignment.tcl"))
        hooks_d["post_configure"].append({"cmd" : [script]+arg_l,
                                          "name": "Modify Vivado build stage",
                                          "env" : {}})
        # Modify <my_module>_synth.tcl
        script = os.path.join(PROJECT_DIR,"hw","script","edalize","hook","hook_post_configure_vivado_synth.sh")
        arg_l = []
        arg_l.append(os.path.join(work_dir,"{:s}_synth.tcl".format(args.top_name)))
        arg_l.append(os.path.join(work_dir,"{:s}_syn.dcp".format(args.top_name)))
        hooks_d["post_configure"].append({"cmd" : [script]+arg_l,
                                          "name": "Modify Vivado synth stage",
                                          "env" : {}})
        # Modify <my_module>_run.tcl
        script = os.path.join(PROJECT_DIR,"hw","script","edalize","hook","hook_post_configure_vivado_run.sh")
        arg_l = []
        arg_l.append(os.path.join(work_dir,"{:s}_run.tcl".format(args.top_name)))
        arg_l.append(os.path.join(work_dir,"{:s}_impl.dcp".format(args.top_name)))
        hooks_d["post_configure"].append({"cmd" : [script]+arg_l,
                                          "name": "Modify Vivado run stage",
                                          "env" : {}})

    if (tool == "xsim"):
        # if coverage is enabled, run xcrg for the report generation
        if (tool_options_d[tool]["cov"]):
            script = os.path.join(PROJECT_DIR,"hw","script","edalize","hook","hook_post_run_xsim_coverage_report.sh")
            arg_l = []
            arg_l.append(work_dir)
            arg_l.append(args.top_name)
            hooks_d["post_run"].append({"cmd" : [script]+arg_l,
                                        "name": "Functional coverage report",
                                        "env" : {}})

    if (tool == "modelsim"):
        None
        #script = os.path.join(PROJECT_DIR,"hw","script","edalize","hook","hook_post_build_questa_vopt.sh")
        #arg_l = []
        #arg_l.append(work_dir)
        #arg_l.append(args.top_name)
        #hooks_d["post_run"].append({"cmd" : [script]+arg_l,
        #                            "name": "Functional coverage report",
        #                            "env" : {}})

    if (tool == "veribleformat"):
        None

    if (VERBOSE):
        print("===========================================================")
        print("Hooks:")
        print(hooks_d)
        print("===========================================================")

#=====================================================
# Parameters
#=====================================================
    parameters_d = {} # EDAlize parameters

    if (tool == "xsim"):
        if (args.gui):
            parameters_d['mode'] = {'datatype' : 'string', 'default' : 'gui','paramtype' : 'cmdlinearg'}
        elif (tool_options_d[tool]["wave"]):
            parameters_d['mode'] = {'datatype' : 'string', 'default' : 'wave','paramtype' : 'cmdlinearg'}

    if (tool == "vcs"):
        if (args.gui):
            tool_options_d[tool]["vcs_options"].append("-debug_access+all")
            tool_options_d[tool]["run_options"]=['+ntb_random_seed={:d} -gui=dve'.format(args.seed)]
        elif (args.gui_verdi):
            tool_options_d[tool]["vlogan_options"].append('-kdb')
            tool_options_d[tool]["vhdlan_options"].append('-kdb')
            tool_options_d[tool]["vcs_options"].append("-kdb -debug_access+all")
            tool_options_d[tool]["run_options"]=['-lca +ntb_random_seed={:d} +fsdb+functions -gui=base'.format(args.seed)]
        elif (tool_options_d[tool]["wave"]):
            ucli_cmd = ['fsdbDumpfile wave.fsdb']

            if ("wave_hier" in tool_options_d[tool]):
                ucli_cmd.extend([f'fsdbDumpvars {i} {x}'
                     for (i,x) in tool_options_d[tool]["wave_hier"]])
            else:
                ucli_cmd.append(f'fsdbDumpvars 0 {args.top_name} +all')

            ucli_cmd.append(f'run {tool_options_d[tool]["run_simu_options"]}')
            ucli_cmd = 'echo \"{}\" |'.format(';'.join(ucli_cmd))

            parameters_d['before'] = {'datatype' : 'string', 'default' : ucli_cmd, 'paramtype' : 'plusarg'}

        elif (tool_options_d[tool]["wave_dve"]):
            ucli_cmd = 'echo \"dump -type vpd -file wave.vpd; dump -add {} -fid VPD0; run {}\" |'.format(args.top_name, tool_options_d[tool]["run_simu_options"])
            parameters_d['before'] = {'datatype' : 'string', 'default' : ucli_cmd,'paramtype' : 'plusarg'}
        else:
            ucli_cmd = 'echo \"run {}\" |'.format(tool_options_d[tool]["run_simu_options"])
            parameters_d['before'] = {'datatype' : 'string', 'default' : ucli_cmd,'paramtype' : 'plusarg'}

    # User parameters
    for p in parse_param_d.keys():
        param_type = parse_param_d[p][0]
        param_val  = parse_param_d[p][1]
        parameters_d[p] = {'datatype' : param_type, 'default' : param_val,'paramtype' : 'vlogparam'}


#=====================================================
# Defines
#=====================================================
    # User defines
    for p in parse_define_d.keys():
        param_type = parse_define_d[p][0]
        param_val  = parse_define_d[p][1]
        parameters_d[p] = {'datatype' : param_type, 'default' : param_val,'paramtype' : 'vlogdefine'}


#=====================================================
# Build EDAM
#=====================================================

    # EDA metadata
    edam = {
        'files'        : files_l,
        'name'         : args.top_name,
        'toplevel'     : args.top_name,
        'parameters'   : parameters_d,
        'tool_options' : tool_options_d,
        'hooks'        : hooks_d}


    # EDAlize backend object
    backend = get_edatool(tool)(edam=edam,
                                work_root=work_dir)

    if ('config' in run_stage_l):
        # Create project scripts
        print("===========================================================")
        print("-----------------------------------------------------------")
        print("| EDAlize Configure                                       |")
        print("-----------------------------------------------------------")
        print("===========================================================")
        backend.configure()

    if ('build' in run_stage_l):
        print("===========================================================")
        print("-----------------------------------------------------------")
        print("| EDAlize Build                                           |")
        print("-----------------------------------------------------------")
        print("===========================================================")
        # Build the model
        backend.build_pre()
        backend.build_main('-B')
        backend.build_post()

    if ('run' in run_stage_l):
        print("===========================================================")
        print("-----------------------------------------------------------")
        print("| EDAlize Run                                             |")
        print("-----------------------------------------------------------")
        print("===========================================================")
        #arguments
        tool_args = {}
        # Run
        backend.run(tool_args)
