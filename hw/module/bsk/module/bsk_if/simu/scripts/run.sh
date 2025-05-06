#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

cli="$*"

###################################################################################################
# This script deals with the testbench run.
# This testbench has specificities that cannot be handled by run_edealize alone.
# They are handled here.
###################################################################################################

# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity
run_edalize=${PROJECT_DIR}/hw/script/edalize/run_edalize.py

dut="bsk_if"
module="tb_${dut}"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-g                       : GLWE_K (default 2)"
echo "-l                       : PBS_L (default 1)"
echo "-b                       : PBS_B_W (default 23)"
echo "-R                       : R: Radix (default 2)"
echo "-P                       : PSI: Number of butterflies (default 4)"
echo "-S                       : S: Number of stages (default 8)"
echo "-w                       : MOD_NTT_W: NTT modulo width / NTT operand width (default 64)"
echo "-K                       : LWE_K (default : 24)"
echo "-o                       : BSK_SLOT_NB (default 8)"
echo "-u                       : BSK_CUT_NB (default 1)"
echo "-f                       : BSK_PC (default 1)"
echo "-- <run_edalize options> : run_edalize options."

}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

run_edalize_args=""
GEN_STIMULI=1
GLWE_K=2
PBS_L=1
PBS_B_W=23
R=2
PSI=4
S=8
MOD_NTT_W=64
LWE_K=24
BSK_SLOT_NB=8
BSK_CUT_NB=1
BSK_PC=1
BSK_PC_MAX=8
# Initialize your own variables here:
while getopts "hg:l:b:R:P:S:w:K:o:u:f:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    g)
      GLWE_K=$OPTARG
      ;;
    l)
      PBS_L=$OPTARG
      ;;
    b)
      PBS_B_W=$OPTARG
      ;;
    R)
      R=$OPTARG
      ;;
    P)
      PSI=$OPTARG
      ;;
    S)
      S=$OPTARG
      ;;
    w)
      MOD_NTT_W=$OPTARG
      ;;
    K)
      LWE_K=$OPTARG
      ;;
    o)
      BSK_SLOT_NB=$OPTARG
      ;;
    u)
      BSK_CUT_NB=$OPTARG
      ;;
    f)
      BSK_PC=$OPTARG
      ;;
    :)
      echo "$0: Must supply an argument to -$OPTARG." >&2
      exit 1
      ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))

# run_edalize additional arguments
[ "${1:-}" = "--" ] && shift
args=$@

N=$((${R}**${S}))
MOD_NTT=$(( 2**$MOD_NTT_W - 1))
MOD_NTT_TYPE="INT_SIMU"
MOD_NTT_INV_TYPE="INT_SIMU"

###################################################################################################
# Generate package
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

INFO_DIR=${SCRIPT_DIR}/../gen/info
mkdir -p $INFO_DIR
RTL_DIR=${SCRIPT_DIR}/../gen/rtl
mkdir -p $RTL_DIR

# Create package
if [ $GEN_STIMULI -eq 1 ] ; then
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_tfhe_definition_pkg.py -f \
                  -N $N -g $GLWE_K -K $LWE_K -l $PBS_L -b $PBS_B_W \
                  -o ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> N=${N}, GLWE_K=${GLWE_K} LWE_K=${LWE_K} PBS_L=${PBS_L} PBS_B_W=${PBS_B_W}"
  echo "INFO> Creating param_tfhe_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/bsk/module/bsk_manager/module/bsk_mgr_common/scripts/gen_bsk_mgr_common_cut_definition_pkg.py\
          -f -bsk_cut $BSK_CUT_NB -o ${RTL_DIR}/bsk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> BSK_CUT_NB=$BSK_CUT_NB"
  echo "INFO> bsk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/bsk/module/bsk_manager/module/bsk_mgr_common/scripts/gen_bsk_mgr_common_slot_definition_pkg.py\
          -f -bsk_slot $BSK_SLOT_NB -o ${RTL_DIR}/bsk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> BSK_SLOT_NB=$BSK_SLOT_NB"
  echo "INFO> bsk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/top_common/scripts/gen_top_common_pcmax_definition_pkg.py\
          -f -bsk_pc $BSK_PC_MAX -o ${RTL_DIR}/top_common_pcmax_definition_pkg.sv"
  echo "INFO> BSK_PC_MAX=$BSK_PC_MAX"
  echo "INFO> top_common_pcmax_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/top_common/scripts/gen_top_common_pc_definition_pkg.py\
          -f -bsk_pc $BSK_PC -o ${RTL_DIR}/top_common_pc_definition_pkg.sv"
  echo "INFO> BSK_PC=$BSK_PC"
  echo "INFO> top_common_pc_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_ntt_definition_pkg.py -f \
          -w $MOD_NTT_W -m $MOD_NTT -t $MOD_NTT_TYPE -T $MOD_NTT_INV_TYPE -o ${RTL_DIR}/param_ntt_definition_pkg.sv"
  echo "INFO> MOD_NTT_W=${MOD_NTT_W}, MOD_NTT=${MOD_NTT}, MOD_NTT_TYPE=${MOD_NTT_TYPE}"
  echo "INFO> Creating param_ntt_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_common/scripts/gen_ntt_core_common_psi_definition_pkg.py\
          -f -P $PSI -o ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> PSI=${PSI}"
  echo "INFO> ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  # Create the associated file_list.json
  echo ""
  file_list_cmd="${PROJECT_DIR}/hw/script/create_module/create_file_list.py\
                -o ${INFO_DIR}/file_list.json \
                -p ${RTL_DIR} \
                -R param_tfhe_definition_pkg.sv simu 0 1 \
                -R param_ntt_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_psi_definition_pkg.sv simu 0 1 \
                -R bsk_mgr_common_cut_definition_pkg.sv simu 0 1 \
                -R bsk_mgr_common_slot_definition_pkg.sv simu 0 1 \
                -R top_common_pcmax_definition_pkg.sv simu 0 1 \
                -R top_common_pc_definition_pkg.sv simu 0 1 \
                -F bsk_mgr_common_cut_definition_pkg.sv BSK_SLOT_CUT BSK_CUT_${BSK_CUT_NB} \
                -F bsk_mgr_common_slot_definition_pkg.sv BSK_SLOT BSK_SLOT_${BSK_SLOT_NB} \
                -F top_common_pcmax_definition_pkg.sv TOP_PCMAX TOP_PCMAX_bsk${BSK_PC_MAX} \
                -F top_common_pc_definition_pkg.sv TOP_PC TOP_PC_bsk${BSK_PC} \
                -F param_ntt_definition_pkg.sv NTT_MOD NTT_MOD_simu \
                -F ntt_core_common_psi_definition_pkg.sv NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu"
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/bsk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/bsk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/param_ntt_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/top_common_pcmax_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/top_common_pc_definition_pkg.sv"
fi

###################################################################################################
# Process
###################################################################################################
mkdir -p ${PROJECT_DIR}/hw/output
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" > $TMP_FILE

#################################################
# Config phase : create directory + scripts
#################################################
# Disable sva_axi end of simulation checks for the last data that are then not received.
# TODO : check last batch flush
eda_args="$eda_args -D AXI4PC_EOS_OFF int 1"
# X propagation not checked correctly. Disable it.
eda_args="$eda_args -D AXI4_XCHECK_OFF int 1"

eda_args="$eda_args -F APPLICATION APPLI_simu \
                    -F NTT_CORE_R NTT_CORE_R_${R} \
                    -F BSK_CUT BSK_CUT_${BSK_CUT_NB} \
                    -F BSK_SLOT BSK_SLOT_${BSK_SLOT_NB} \
                    -F TOP_PC TOP_PC_bsk${BSK_PC} \
                    -F TOP_PCMAX TOP_PCMAX_bsk${BSK_PC_MAX} \
                    -F NTT_MOD NTT_MOD_simu \
                    -F NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                    -sva ${dut}"

# Get current working directory
cmd="$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -y run -y build \
    $eda_args \
    $args"
echo "Info> Running : $cmd"
$cmd | tee >(grep "Work directory :" >> $TMP_FILE)
sync
>&2 echo "INFO> Reading from $TMP_FILE: $(ls -l $TMP_FILE)"
work_dir=$(cat $TMP_FILE | sed 's/Work directory : *//')
>&2 echo "INFO> Extracted work_dir : ${work_dir}"

# Delete TMP_FILE
rm -f $TMP_FILE

# log command line
echo $cli > ${work_dir}/cli.log

#################################################
# Run phase : simulation
#################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args

