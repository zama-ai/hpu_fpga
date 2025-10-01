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

TEMPLATE_NAME = "hpu_mockup_config.toml.j2"

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a module directory structure.")
    parser.add_argument('-R',  dest='r',            type=int, help="R: radix.", default=2)
    parser.add_argument('-P',  dest='psi',          type=int, help="PSI: Number of butterflies.", default=8)
    parser.add_argument('-A',  dest='core_arch',    type=str, help="Ntt core architecture", default="NTT_CORE_ARCH_WMM_UNFOLD_PCG")
    parser.add_argument('-z',  dest='delta',        type=int, help="DELTA.", default=1)
    parser.add_argument('-J',  dest="cut_l",        type=int, action='append', help="NTT cut pattern. Given from input to output. The first one is the ngc", default=[])
    parser.add_argument('-N',  dest='poly_coef_nb', type=int, help="N: Number of coefficients in a polynomial.", default=512)
    parser.add_argument('-g',  dest='glwe_k',       type=int, help="GLWE_K", default=2)
    parser.add_argument('-l',  dest='pbs_l',        type=int, help="PBS_L: Number of decomposed levels for BR", default=2)
    parser.add_argument('-b',  dest='pbs_b_w',      type=int, help="PBS_B_W: Decomposition base width for BR", default=8)
    parser.add_argument('-L',  dest='ks_l',         type=int, help="KS_L: Number of decomposed levels for KS", default=5)
    parser.add_argument('-B',  dest='ks_b_w',       type=int, help="KS_B_W: Decomposition base width for KS", default=3)
    parser.add_argument('-K',  dest='lwe_k',        type=int, help="LWE_K: Number of blind rotation loop iteration", default=586)
    parser.add_argument('-W',  dest='mod_q_w',      type=int, help="MOD_Q_W.", default=32)
    parser.add_argument('-w',  dest='mod_ntt_w',    type=int, help="MOD_NTT_W: Modulo width.", default=32)
    parser.add_argument('-m',  dest='mod_ntt',      type=str, help="MOD_NTT", default="2**32-2**17-2**13+1")
    parser.add_argument('-V',  dest='mod_ksk_w',    type=int, help="MOD_KSK_W.", default=32)
    parser.add_argument('-lbx', dest='lbx',         type=int, help="LBX: Number of columns coefficients processed in parallel in the KS.", default=1)
    parser.add_argument('-lby', dest='lby',         type=int, help="LBX: Number of lines coefficients processed in parallel in the KS.", default=64)
    parser.add_argument('-lbz', dest='lbz',         type=int, help="LBZ: Number of lines coefficients processed in parallel in the KS.", default=1)
    parser.add_argument('-bpbs_nb', dest='bpbs_nb', type=int, help="BPBS_NB: Number PBS per batch", default=8)
    parser.add_argument('-tpbs_nb', dest='tpbs_nb', type=int, help="TPBS_NB: Total PBS number", default=16)
    parser.add_argument('-regf_reg_nb' , dest='regf_reg_nb', type=int, help="REGF_REG_NB: Number of registers in regfile.", default=64)
    parser.add_argument('-regf_coef_nb', dest='regf_coef_nb',type=int, help="REGF_COEF_NB: Number of coefficients in regfile.", default=32)
    parser.add_argument('-pem_pc',dest='pem_pc',    type=int, help="Number of PC for PEM", default=1)
    parser.add_argument('-pem_bytes_w',dest='pem_bytes_w',    type=int, help="PEM bus width [BYTES]", default=64)
    parser.add_argument('-glwe_pc',dest='glwe_pc',  type=int, help="Number of PC for GLWE", default=1)
    parser.add_argument('-glwe_bytes_w',dest='glwe_bytes_w',    type=int, help="GLWE bus width [BYTES]", default=64)
    parser.add_argument('-bsk_pc',dest='bsk_pc',    type=int, help="Number of PC for BSK", default=1)
    parser.add_argument('-bsk_bytes_w',dest='bsk_bytes_w',    type=int, help="bsk bus width [BYTES]", default=64)
    parser.add_argument('-ksk_pc',dest='ksk_pc',    type=int, help="Number of PC for KSK", default=1)
    parser.add_argument('-ksk_bytes_w',dest='ksk_bytes_w',    type=int, help="ksk bus width [BYTES]", default=64)
    parser.add_argument('-isc_depth',    dest='isc_depth',   type=int, help="ISC_POOL_SLOT_NB: ISC depth.", default=32)
    parser.add_argument('-use_mean_comp',    dest='use_mean_comp',   type=int, help="USE_MEAN_COMP.", default=1)
    parser.add_argument('-o',  dest='outfile',      type=str, help="Output filename.", required=True)
    parser.add_argument('-f',  dest='force',        help="Overwrite if file already exists", action="store_true", default=False)

    args = parser.parse_args()

#=====================================================
# Create files
#=====================================================
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)

    S = int(math.log(args.poly_coef_nb,args.r))
    #delta = args.cut_l[0]
    delta = args.delta

    # Construct core_arch with embedded cut_l
    core_arch_short = args.core_arch.replace("NTT_CORE_ARCH_","")
    if core_arch_short == "gf64":
        core_arch = f"{{GF64={args.cut_l}}}"
    else:
        # Convert from snake_case to CamelCase
        # split underscore using split
        split = core_arch_short.split('_')
         # joining result
        core_arch = f"\"{''.join(word.title() for word in split)}\""

    # Construct name based mod_ntt
    mod_ntt = eval(args.mod_ntt)
    mode_ntt_enum = ""
    if mod_ntt == ((1 <<32) - (1 <<17) - (1<<13) +1):
        mod_ntt_enum="Solinas3_32_17_13"
    elif mod_ntt == ((1 <<44) - (1 <<14) +1):
        mod_ntt_enum="Solinas2_44_14"
    elif mod_ntt == ((1 <<64) - (1 <<32) +1):
        mod_ntt_enum="GF64"
    else:
        sys.exit(f"ERROR> Unsupported MOD_NTT {args.mod_ntt}")

    config = {"REGF_REG_NB"  : args.regf_reg_nb,
              "REGF_COEF_NB" : args.regf_coef_nb,
              "ISC_POOL_SLOT_NB" : args.isc_depth,
              "MOD_Q_W"      : args.mod_q_w,
              "LWE_K"        : args.lwe_k,
              "GLWE_K"       : args.glwe_k,
              "N"            : args.poly_coef_nb,
              "PBS_L"        : args.pbs_l,
              "PBS_B_W"      : args.pbs_b_w,
              "KS_L"         : args.ks_l,
              "KS_B_W"       : args.ks_b_w,
              "MOD_NTT"      : mod_ntt_enum,
              "MOD_NTT_W"    : args.mod_ntt_w,
              "R"            : args.r,
              "S"            : S,
              "PSI"          : args.psi,
              "DELTA"        : delta,
              "MOD_KSK_W"    : args.mod_ksk_w,
              "LBX"          : args.lbx,
              "LBY"          : args.lby,
              "LBZ"          : args.lbz,
              "BPBS_NB"      : args.bpbs_nb,
              "TPBS_NB"      : args.tpbs_nb,
              "ksk_pc"       : args.ksk_pc,
              "ksk_bytes_w"  : args.ksk_bytes_w,
              "bsk_pc"       : args.bsk_pc,
              "bsk_bytes_w"  : args.bsk_bytes_w,
              "glwe_pc"      : args.glwe_pc,
              "glwe_bytes_w" : args.glwe_bytes_w,
              "pem_pc"       : args.pem_pc,
              "pem_bytes_w"  : args.pem_bytes_w,
              "core_arch"    : core_arch,
              "USE_MEAN_COMP": args.use_mean_comp,
              "cut_l"        : f"{args.cut_l}"}


    template = template_env.get_template(TEMPLATE_NAME)
    file_path = args.outfile
    if (os.path.exists(file_path) and not(args.force)):
        sys.exit("ERROR> File {:s} already exists".format(file_path))
    else:
        if (os.path.exists(file_path)):
            print("INFO> File {:s} already exists. Overwrite it.".format(file_path))
        with open(file_path, 'w') as fp:
            fp.write(template.render(config))

