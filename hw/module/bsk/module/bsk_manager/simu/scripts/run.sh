#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

cli="$*"

###################################################################################################
# This script deals with the testbench run.
# This testbench has specificities that cannot be handled by run_edalize alone.
# They are handled here.
###################################################################################################

# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity
run_edalize=${PROJECT_DIR}/hw/script/edalize/run_edalize.py

module="tb_bsk_manager"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-g                       : GLWE_K (default 2)"
echo "-l                       : PBS_L (default 2)"
echo "-R                       : R: Radix (default 8)"
echo "-P                       : PSI: Number of butterflies (default 8)"
echo "-S                       : S: Number of stages (default 3)"
echo "-K                       : LWE_K (default : 24)"
echo "-u                       : BSK_CUT_NB (default 1)"
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
PBS_L=2
R=8
PSI=8
S=3
LWE_K=24
BSK_CUT_NB=1
# Initialize your own variables here:
while getopts "hzg:l:n:R:P:S:K:u:" opt; do
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
    R)
      R=$OPTARG
      ;;
    P)
      PSI=$OPTARG
      ;;
    S)
      S=$OPTARG
      ;;
    K)
      LWE_K=$OPTARG
      ;;
    u)
      BSK_CUT_NB=$OPTARG
      ;;
    z)
      echo "Do not generate stimuli."
      GEN_STIMULI=0
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

N=$((R**S))
BSK_SLOT_NB=$LWE_K

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
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_tfhe_definition_pkg.py -f -N $N -g $GLWE_K -l $PBS_L -K $LWE_K -o ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> N=${N}, GLWE_K=${GLWE_K}, PBS_L=${PBS_L} LWE_K=$LWE_K"
  echo "INFO> Creating param_tfhe_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_common/scripts/gen_ntt_core_common_psi_definition_pkg.py\
          -f -P $PSI -o ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> PSI=${PSI}"
  echo "INFO> ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_common/scripts/gen_ntt_core_common_r_definition_pkg.py\
          -f -R $R -o ${RTL_DIR}/ntt_core_common_r_definition_pkg.sv"
  echo "INFO> R=${R}"
  echo "INFO> ntt_core_common_r_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/bsk/module/bsk_manager/module/bsk_mgr_common/scripts/gen_bsk_mgr_common_cut_definition_pkg.py\
          -f -bsk_cut $BSK_CUT_NB -o ${RTL_DIR}/bsk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> BSK_CUT=$BSK_CUT_NB"
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

  # Create the associated file_list.json
  echo ""
  file_list_cmd="${PROJECT_DIR}/hw/script/create_module/create_file_list.py\
                -o ${INFO_DIR}/file_list.json \
                -p ${RTL_DIR} \
                -R param_tfhe_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_psi_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_r_definition_pkg.sv simu 0 1 \
                -R bsk_mgr_common_cut_definition_pkg.sv simu 0 1 \
                -R bsk_mgr_common_slot_definition_pkg.sv simu 0 1 \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu \
                -F bsk_mgr_common_cut_definition_pkg.sv BSK_CUT BSK_CUT_${BSK_CUT_NB} \
                -F bsk_mgr_common_slot_definition_pkg.sv BSK_SLOT BSK_SLOT_${BSK_SLOT_NB} \
                -F ntt_core_common_psi_definition_pkg.sv NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                -F ntt_core_common_r_definition_pkg.sv NTT_CORE_R NTT_CORE_R_${R} "
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_r_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/bsk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/bsk_mgr_common_slot_definition_pkg.sv"
fi

eda_args=""

eda_args="$eda_args \
            -F APPLICATION APPLI_simu \
            -F NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
            -F NTT_CORE_R NTT_CORE_R_${R} \
            -F BSK_CUT BSK_CUT_${BSK_CUT_NB} \
            -F BSK_SLOT BSK_SLOT_${BSK_SLOT_NB}"

###################################################################################################
# Run_edalize configure
###################################################################################################
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" > $TMP_FILE

$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -y run -y build \
  $eda_args \
  $args | tee >(grep "Work directory :" >> $TMP_FILE)
sync
work_dir=$(cat ${TMP_FILE} | sed 's/Work directory : *//')

# Delete TMP_FILE
rm -f $TMP_FILE

# create output dir
echo "INFO> Creating output dir : ${work_dir}/output"
mkdir -p  ${work_dir}/output

# log command line
echo $cli > ${work_dir}/cli.log

###################################################################################################
# Run phase : simulation
###################################################################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args

