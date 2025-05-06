#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import argparse # parse input argument
import os       # OS functions
import sys      # manage errors
import subprocess # run subprocess

#==================================================================================================
# This script run verible-verilog-format on Verilog and SystemVerilog files.
#==================================================================================================

#==============================================================================
# Global variables / constants
#==============================================================================
VERBOSE=False
VERIBLE_ARGS=[
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

#==============================================================================
# recursive_core
#==============================================================================

def recursive_core(name, use_recursion, in_place):
    '''
    Analyze input.
    If input is a file
      - check if the file is of correct type (.v or .sv)
      - apply verible formatter.
    If input is a directory
       - apply verible formatter on each files inside (see previous point).
       - if recursion is on, does the same in sub-directories, of current one.
    '''
 
    if os.path.exists(name):
       if os.path.isfile(name):
           # Check that it is a verilog or SystemVerilog file
           split_tup = os.path.splitext(name)
           file_extension = split_tup[1]
           if not(file_extension == '.v' or file_extension == '.sv'):
               print("WARNING> Not a Verilog or SystemVerilog file: {:s}. No process done on it.".format(name), file=sys.stderr)
           else:
               # Use verible
               cmd = ['verible-verilog-format',name]+VERIBLE_ARGS
               if (in_place):
                   cmd.append('--inplace')
               if (VERBOSE):
                   print(">> Processing file {:s}".format(name), file=sys.stdout)
               verible_proc = subprocess.run(cmd, capture_output=True, text=True)
 
               if not(in_place):
                   print(verible_proc.stdout, file=sys.stdout)
       elif os.path.isdir(name):
           if (VERBOSE):
               print(">> Processing directory {:s}".format(name), file=sys.stdout)
           dir_list = os.listdir(name)
           print(">> Processing list "+str(dir_list), file=sys.stdout)
           for f in dir_list:
               f_name = os.path.join(name,f)
               if os.path.isfile(f_name):
                   recursive_core(f_name, use_recursion, in_place)
               elif (os.path.isdir(name) and use_recursion):
                   recursive_core(f_name, use_recursion, in_place)
       else:
           sys.exit("ERROR> Unrecognized type: {:s}".format(name))
 
    else:
       sys.exit("ERROR> Unknown input : {:s}".format(name))

#==============================================================================
# Main
#==============================================================================
if __name__ == '__main__':

#==============================================================================
# Parse input arguments
#==============================================================================
    parser = argparse.ArgumentParser(description = "Run Verible.")
    parser.add_argument('-r', dest='recursion', help="Run recursively in the directories.", action="store_true", default=False)
    parser.add_argument('-o', dest='in_place', help="Print result in stdout. Default : format in place", action="store_false", default=True)
    parser.add_argument('-v', dest='verbose', help="Run in verbose mode.", action="store_true", default=False)
    parser.add_argument('names', metavar='file_or_dir', type=str, nargs='+', help='list of files or directories to be processed.')

    args = parser.parse_args()
 
    VERBOSE = args.verbose


#==============================================================================
# Apply verible
#==============================================================================
    for name in args.names:
        recursive_core(name, args.recursion, args.in_place)

