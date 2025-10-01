#! /usr/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# This script deals with the testbench run when specifics cannot be handled by run_edalize alone.
# run_edalize is called twice.
# * The first time to create the working directory (which could be given by the user), and the default
# scripts.
# * The second time to run the simulation.
# If the user needs to modify run_edalize scripts, or add some files to the project,
# it should be done between the 2 steps.
# ==============================================================================================

cli="$*"

# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity
run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py

module="tb_pep_mmacc_body_ram"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-z                       : Do not generate stimuli."
echo "-C                       : Clean gen directory once the simulation is done."
echo "-K                       : LWE_K."
echo "-s                       : seed (if not given, random value.)"
echo "-d                       : USE_MEAN_COMP (default 1)"
echo "-- <run_edalize options> : run_edalize options."

}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

run_edalize_args=""
GEN_STIMULI=1
SEED=-1
CLEAN=0
LWE_K=30
USE_MEAN_COMP=1
# Initialize your own variables here:
while getopts "hzs:K:Cd:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    z)
      echo "Do not generate stimuli."
      GEN_STIMULI=0
      ;;
    C)
      echo "Clean gen directory at the end of the run."
      CLEAN=1
      ;;
    s)
      SEED=$OPTARG
      ;;
    K)
      LWE_K=$OPTARG
      ;;
    d)
      USE_MEAN_COMP=$OPTARG
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

# Check if a seed has been given in run_edalize option.
eda_args=""
if [[ ${args} =~ .*-s( +)([0-9]+) ]]; then
  if [ $SEED -ne -1 ]; then
    echo "WARNING> 2 seed values given, use the one defined for run_edalize."
  fi
  SEED=${BASH_REMATCH[2]}
  echo "INFO> Use seed from run_edalize arguments: $SEED"
else
  if [ $SEED -eq -1 ]; then
    SEED=$RANDOM$RANDOM
  fi
  eda_args="$eda_args -s $SEED"
fi

echo "INFO> SEED=$SEED"

###################################################################################################
# Directories
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

HW_OUTPUT_DIR=${PROJECT_DIR}/hw/output
mkdir -p $HW_OUTPUT_DIR
INFO_DIR=${SCRIPT_DIR}/../gen/info
mkdir -p $INFO_DIR
RTL_DIR=${SCRIPT_DIR}/../gen/rtl
mkdir -p $RTL_DIR
INPUT_DIR=${SCRIPT_DIR}/../gen/input
mkdir -p $INPUT_DIR

# Used to catch the working directory.
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" > $TMP_FILE

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
                  -K $LWE_K -d $USE_MEAN_COMP \
                  -o ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> LWE_K=${LWE_K} USE_MEAN_COMP=$USE_MEAN_COMP"
  echo "INFO> Creating param_tfhe_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  # Create the associated file_list.json
  echo ""
  file_list_cmd="${PROJECT_DIR}/hw/scripts/create_module/create_file_list.py\
                -o ${INFO_DIR}/file_list.json \
                -p ${RTL_DIR} \
                -R param_tfhe_definition_pkg.sv simu 0 1 \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu"
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
fi

eda_args="$eda_args -F APPLICATION APPLI_simu"

###################################################################################################
# Generate stimuli
###################################################################################################

###################################################################################################
# Flags, Parameters, Define
###################################################################################################

###################################################################################################
# Config phase : create directory + scripts
###################################################################################################
# Get current working directory
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -y run -y build \
  $eda_args \
  $args | tee >(grep "Work directory :" >> $TMP_FILE)
sync
>&2 echo "INFO> Reading from $TMP_FILE: $(ls -l $TMP_FILE)"
work_dir=$(cat $TMP_FILE | sed 's/Work directory : *//')
>&2 echo "INFO> work_dir extracted from TMP_FILE: '$work_dir'"

# Delete TMP_FILE
rm -f $TMP_FILE

# Keep command line
echo $cli > ${work_dir}/cli.log

# create output dir
echo "INFO> Creating output dir : ${work_dir}/output"
mkdir -p  ${work_dir}/output

# Link
echo "INFO> Link $INPUT_DIR to ${work_dir}/input"
if [ -d ${work_dir}/input ] ; then rm ${work_dir}/input ; fi
ln -s $INPUT_DIR ${work_dir}/input

#################################################
# Run phase : simulation
#################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args

#################################################
# Post process
#################################################
# None

#################################################
# Clean gen directory
#################################################
if [ $CLEAN -eq 1 ] ; then
  echo "INFO> Cleaning gen directory."
  rm -rf ${SCRIPT_DIR}/../gen/*
fi

