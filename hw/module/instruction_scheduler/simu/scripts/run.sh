#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

cli="$*"
set -e

###################################################################################################
# This script deals with the testbench run.
# This testbench has specificities that cannot be handled by run_edealize alone.
# They are handled here.
###################################################################################################

# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity
run_edalize=${PROJECT_DIR}/hw/script/edalize/run_edalize.py

module="tb_instruction_scheduler"

###################################################################################################
# Default values
###################################################################################################
TARGET_IOP="MUL @[0]0x00 @[0]0x40 @[0]0x80"
TARGET_IOP_WIDTH=64
TARGET_PBS_WIDTH=16
USE_BPIP=1

SEED=-1
CLEAN=0
GEN_STIMULI=1

###################################################################################################
# Usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-z                       : Do not generate stimuli."
echo "-I                       : IOp to schedule"
echo "-W                       : IOp width"
echo "-P                       : PBS width"
echo "-B                       : Use BPIP"
echo "-- <run_edalize options> : run_edalize options."
}


###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize your own variables here:
while getopts "ChzI:W:P:B:" opt; do
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

    I)
      TARGET_IOP=$OPTARG
      ;;
    W)
      TARGET_IOP_WIDTH=$OPTARG
      ;;
    P)
      TARGET_PBS_WIDTH=$OPTARG
      ;;
    B)
      USE_BPIP=$OPTARG
      ;;
  esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift
args=$@

#--------------
# SEED
#--------------
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
# Define parameters at compile time
###################################################################################################

eda_args="$eda_args -P USE_BPIP int $USE_BPIP"

###################################################################################################
# Define and Create directories
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
OUTDIR=${PROJECT_DIR}/hw/output
mkdir -p ${OUTDIR}
INFO_DIR=${SCRIPT_DIR}/../gen/info
mkdir -p $INFO_DIR
RTL_DIR=${SCRIPT_DIR}/../gen/rtl
mkdir -p $RTL_DIR
INPUT_DIR=${SCRIPT_DIR}/../gen/input
mkdir -p  $INPUT_DIR
if [ $GEN_STIMULI -eq 1 ] ; then
  rm -rf ${INPUT_DIR}/*
fi
TV_DIR=${INPUT_DIR}/test_vectors/latest
SOFT_OUTPUT_DIR=${PROJECT_DIR}/hw/output/micro_code
MEM_DIR=${PROJECT_DIR}/hw/memory_file/microblaze

###################################################################################################
# Generate packages
###################################################################################################
# TODO Move POOL_SLOT_NB in a generated package

###################################################################################################
# Build DOp stream
###################################################################################################
# Create input stimuli if necessary
if [ $GEN_STIMULI -eq 1 ] ; then
  fw_cfg_script="${PROJECT_DIR}/sw/bin/tfhe-rs/config/gen_hpu_mockup_config.py"
  fw_bin_path="${PROJECT_DIR}/sw/bin/tfhe-rs/latest"
  fw_bin="${fw_bin_path}/fw"
  fw_cfg="${fw_bin_path}/config"

  #== Create fw config
  echo "###################################################"
  echo "INFO> Generate fw config file"
  gen_cfg_cmd="python3 ${fw_cfg_script} \
                -bpbs_nb $TARGET_PBS_WIDTH \
                -o ${INPUT_DIR}/fw_cfg.toml \
                -f"
  echo "INFO> Running $gen_cfg_cmd"
  $gen_cfg_cmd || exit 1

  #== Create stimuli
  echo "###################################################"
  echo "INFO> Create stimuli"
  fw_cmd="${fw_bin} \
    --config ${fw_cfg}/dflt_cfg.toml \
    --params ${INPUT_DIR}/fw_cfg.toml \
    --kogge-cfg \"\" \
    --integer-w ${TARGET_IOP_WIDTH} \
    --heap 4096 \
    --expand \"${TARGET_IOP}\" \
    --out-folder ${INPUT_DIR}"

  echo "INFO> Running : $fw_cmd"
  echo $fw_cmd | sh

  # Link generated dop file to `dop_stream`
  link_cmd="ln -s -T $(ls ${INPUT_DIR}/*.dop.hex) ${INPUT_DIR}/dop_stream.hex"
  echo "INFO> Running : $link_cmd"
  echo $link_cmd | sh
  
fi

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

# Link
echo "INFO> Link $INPUT_DIR to ${work_dir}/input"
if [ -d ${work_dir}/input ] ; then rm ${work_dir}/input ; fi
ln -s $INPUT_DIR ${work_dir}/input

# log command line
echo $cli > ${work_dir}/cli.log

###################################################################################################
# Run phase : simulation
###################################################################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args

###################################################################################################
# Post process
###################################################################################################
# None

###################################################################################################
# Clean gen directory
###################################################################################################
if [ $CLEAN -eq 1 ] ; then
  echo "INFO> Cleaning gen directory."
  rm -rf ${SCRIPT_DIR}/../gen/*
fi
