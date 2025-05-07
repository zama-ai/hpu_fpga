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
run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py

module="tb_bsk_ntw_srv_clt"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-c                       : BSK_CLT_NB (default 3)"
echo "-C                       : BSK_SRV_NB (default 3)"
echo "-b                       : BATCH_NB (default 2)"
echo "-d                       : BSK_DIST_COEF_NB (default 4)"
echo "-- <run_edalize options> : run_edalize options."

}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

run_edalize_args=""
GEN_STIMULI=1
BSK_CLT_NB=3
BSK_SRV_NB=3
BATCH_NB=2
BSK_DIST_COEF_NB=4
# Initialize your own variables here:
while getopts "hzc:b:d:C:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    c)
      BSK_CLT_NB=$OPTARG
      ;;
    C)
      BSK_SRV_NB=$OPTARG
      ;;
    b)
      BATCH_NB=$OPTARG
      ;;
    d)
      BSK_DIST_COEF_NB=$OPTARG
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
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_with_matrix_multiplication/simu/tb_bsk_ntw_model/scripts/gen_bsk_ntw_common_definition_pkg.py -f -a $BSK_DIST_COEF_NB -o ${RTL_DIR}/bsk_ntw_common_definition_pkg.sv"
  echo "INFO> BSK_DIST_COEF_NB=${BSK_DIST_COEF_NB}"
  echo "INFO> Creating bsk_ntw_common_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  # Create the associated file_list.json
  echo ""
  file_list_cmd="${PROJECT_DIR}/hw/scripts/create_module/create_file_list.py\
                -o ${INFO_DIR}/file_list.json \
                -p ${RTL_DIR} \
                -R bsk_ntw_common_definition_pkg.sv simu 0 1 \
                -F bsk_ntw_common_definition_pkg.sv BSK_NTW_DCOEF DCOEF${BSK_DIST_COEF_NB}"
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/bsk_ntw_common_definition_pkg.sv"
fi

###################################################################################################
# Run simulation
###################################################################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} \
            -P BATCH_NB int $BATCH_NB \
            -P BSK_CLT_NB int $BSK_CLT_NB \
            -P BSK_SRV_NB int $BSK_SRV_NB \
            -F BSK_NTW_DCOEF DCOEF${BSK_DIST_COEF_NB} \
            $args

