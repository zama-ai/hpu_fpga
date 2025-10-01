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
run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py

module="tb_pep_sequencer"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-g                       : GLWE_K (default 2)"
echo "-R                       : R: Radix (default 2)"
echo "-S                       : S: Number of stages (default 12). Should be big enough for this bench to work."
echo "-P                       : PSI: Number of butterflies (default 8)"
echo "-K                       : LWE_K: LWE dimension (default 12)"
echo "-c                       : BATCH_PBS_NB (default : 12)"
echo "-H                       : TOTAL_PBS_NB (default : 16)"
echo "-G                       : GRAM_NB      (default : 4)"
echo "-X                       : LBX (default 3)"

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
PBS_L=1 # UNUSED
R=2
S=12
PSI=8
LWE_K=12
GRAM_NB=4
BATCH_PBS_NB=12
TOTAL_PBS_NB=16
LBX=3
# Initialize your own variables here:
while getopts "hzg:R:S:P:c:H:K:X:G:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    g)
      GLWE_K=$OPTARG
      ;;
    R)
      R=$OPTARG
      ;;
    S)
      S=$OPTARG
      ;;
    P)
      PSI=$OPTARG
      ;;
    K)
      LWE_K=$OPTARG
      ;;
    c)
      BATCH_PBS_NB=$OPTARG
      ;;
    H)
      TOTAL_PBS_NB=$OPTARG
      ;;
    X)
      LBX=$OPTARG
      ;;
    z)
      echo "Do not generate stimuli."
      GEN_STIMULI=0
      ;;
    G)
      GRAM_NB=$OPTARG
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
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/pep_key_switch/module/pep_ks_common/scripts/gen_pep_ks_common_definition_pkg.py\
          -f -lbx $LBX -o ${RTL_DIR}/pep_ks_common_definition_pkg.sv"
  echo "INFO> LBX=$LBX"
  echo "INFO> pep_ks_common_definition_pkg.sv"
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
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/pe_pbs/module/pep_common/scripts/gen_pep_batch_definition_pkg.py\
          -f -c $BATCH_PBS_NB -H $TOTAL_PBS_NB -g $GRAM_NB -o ${RTL_DIR}/pep_batch_definition_pkg.sv"
  echo "INFO> BATCH_PBS_NB=$BATCH_PBS_NB TOTAL_PBS_NB=$TOTAL_PBS_NB"
  echo "INFO> pep_batch_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  # Create the associated file_list.json
  echo ""
  file_list_cmd="${PROJECT_DIR}/hw/scripts/create_module/create_file_list.py\
                -o ${INFO_DIR}/file_list.json \
                -p ${RTL_DIR} \
                -R param_tfhe_definition_pkg.sv simu 0 1 \
                -R pep_ks_common_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_psi_definition_pkg.sv simu 0 1 \
                -R pep_batch_definition_pkg.sv simu 0 1 \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu \
                -F pep_ks_common_definition_pkg.sv KSLB KSLB_x${LBX} \
                -F pep_batch_definition_pkg.sv PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB}_tpbs${TOTAL_PBS_NB} \
                -F ntt_core_common_psi_definition_pkg.sv NTT_CORE_PSI NTT_CORE_PSI_${PSI} "
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/pep_ks_common_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/pep_batch_definition_pkg.sv"
fi

eda_args=""

eda_args="$eda_args \
            -F NTT_CORE_R NTT_CORE_R_${R} \
            -F APPLICATION APPLI_simu \
            -F KSLB KSLB_x${LBX} \
            -F NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
            -F PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB}_tpbs${TOTAL_PBS_NB}"

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

