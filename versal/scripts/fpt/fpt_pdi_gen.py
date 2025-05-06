#!/usr/bin/env python3

# (c) Copyright 2024, Advanced Micro Devices, Inc.
# 
# Permission is hereby granted, free of charge, to any person obtaining a 
# copy of this software and associated documentation files (the "Software"), 
# to deal in the Software without restriction, including without limitation 
# the rights to use, copy, modify, merge, publish, distribute, sublicense, 
# and/or sell copies of the Software, and to permit persons to whom the 
# Software is furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in 
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
# DEALINGS IN THE SOFTWARE.
############################################################


import sys
import os
import argparse

def roundup(x, y):
    x -= x % -y  # Round x up to next multiple of y
    return x


def doomed(msg):
    print("ERROR: " + msg)
    # sys.stderr.write("ERROR: " + msg)
    exit(1)


def dump_data_to_file(filename, data, permissions='w+'):
    try:
        f = open(filename, permissions)
        f.write(data)
        f.close()
    except:
        doomed(str(sys.exc_info()[1]))


def read_data_from_file(filename, permissions='r'):
    try:
        f = open(filename, permissions)
        data = f.read()
        f.close()
    except:
        doomed(str(sys.exc_info()[1]))

    return data

def cmd(string):
    print(string)
    os.system(string)



def do_fpt_pdi_generation(fpt_file, pdi_file, output_file_name):


    # FPT already binary, just read
    if fpt_file.endswith('.bin'):
        fpt_bin_data = bytearray(read_data_from_file(fpt_file, 'rb'))
    
    # only bin supported for FPT
    else:
        doomed("FPT file must be either be *.bin suffix - {}".format(
            fpt_file))

    # pad the binary file to 32KB to align to PMC boot search
    fpt_bin_data = fpt_bin_data.ljust(0x8000, b'\xff')

    # open the PDI and create FPT + PDI structure
    # 
    if fpt_file.endswith(('.json','.bin')):
        pdi_bin_data = bytearray(read_data_from_file(pdi_file, 'rb'))
    else:
        doomed("PDI file must be either be *.bin or *.pdi suffix - {}".format(
            pdi_file))

    # create metadata section (at present only size is populated)
    # struct fpt_pdi_meta {
    #         uint32_t        fpt_pdi_magic; (0x4d494450 == "PDIM")
    #         uint32_t        fpt_pdi_version;
    #         uint32_t        fpt_pdi_size;
    #         uint32_t        fpt_pdi_checksum;
    # };
    #pdi_meta = bytearray("PDIM", 'utf8') # magic = "PDIM"
    #pdi_meta.extend(b'\x00\x00\x00\x00') # version 0
    #pdi_meta.extend(len(pdi_bin_data).to_bytes(4,'little')) # size in bytes
    #pdi_meta.extend(b'\x00\x00\x00\x00') # checksum TODO
    # pad to 32KB (PDI must be on 32KB boundary
    #pdi_meta = pdi_meta.ljust(0x8000, b'\xff')
    
    combined_bin_data = fpt_bin_data + pdi_bin_data
    
    dump_data_to_file(output_file_name, combined_bin_data, 'wb')

    return


################################################################
# MAIN
################################################################

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Generate AVED FPT Setup PDI')
    parser.add_argument('--fpt', dest='fpt_file', metavar=('fpt_file'),
                        help='Pass an FPT Binary file to be combined with PDI')
    parser.add_argument('--pdi', dest='pdi_file', metavar=('pdi_file'),
                        help='PDI File, to be combined with FPT')
    parser.add_argument('--output', dest='outfile', default='-', metavar=('output_file'),
                        help='Destination file after an input file(s) processed')


    # If nothing is input to this script, print usage
    if len(sys.argv[1:]) == 0:
        parser.print_help()
        parser.exit()

    args = parser.parse_args()
    
 
  
    ################################################################
    # Generate FPT Setup PDI
    ################################################################

        
    # Both a PDI and FPT is required for this option
    if not args.fpt_file or not args.pdi_file :
        doomed("FPT Setup PDI Generation requires --fpt and --pdi to be specified")
            
    if args.outfile == '-':
        out_file_local = "fpt_setup.pdi"
    elif False == args.outfile.lower().endswith('.pdi'):
        doomed("Please provide an output filename with suffix '.pdi'")
    else:
        out_file_local = args.outfile


    print("Generating FPT Setup PDI :\t\t{}".format(out_file_local))       
    do_fpt_pdi_generation(args.fpt_file, args.pdi_file, out_file_local)
    print("FPT Setup PDI Generated ****************************************")
    sys.exit()


