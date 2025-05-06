#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

cli="$*"
## ============================================================================================== ##
## Description  : run
## ---------------------------------------------------------------------------------------------- ##
##
## Objective is to generate the roms according to the design parameters PSI, R, S_INIT, S_DEC
## This script generate PSI x R/2 rom memory files located in ${SCRIPT_DIR}/../input_gen/ with
## a template name such as "data_${p}_${r}.mem". Data is fetch from the twiddle.mem file,
## data is reordered according to the expectations from the testbench
##
## ============================================================================================== ##

# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity
run_edalize=${PROJECT_DIR}/hw/script/edalize/run_edalize.py

module="tb_twiddle_phi_ru_manager"

###################################################################################################
# usage
###################################################################################################
function usage() {
  echo "Usage : run.sh runs the simulation for $module."
  echo "./run.sh [options]"
  echo "Options are:"
  echo "-h                       : print this help."
  echo "-R                       : Radix - default 8"
  echo "-P                       : PSI - default 8"
  echo "-S                       : Stage number - default 3"
  echo "-i                       : S_INIT in 0..S-2 - default 2"
  echo "-d                       : S_DEC in 0..S - default 1"
  echo "-- <run_edalize options> : run_edalize options."
}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1 # Reset in case getopts has been used previously in the shell.

# Parameters default values #
PVAL=8
RVAL=8
SDEC=1
SVAL=3
SINIT=$(($SVAL-1))
GEN_STIMULI=1

# Initialize your own variables here:
while getopts "hzP:R:S:i:d:" opt; do
  case "$opt" in
  h)
    usage
    exit 0
    ;;
  z)
    echo "Do not generate stimuli."
    GEN_STIMULI=0
    ;;
  P)
    PVAL="$OPTARG"
    ;;
  R)
    RVAL="$OPTARG"
    ;;
  S)
    SVAL="$OPTARG"
    ;;
  i)
    SINIT="$OPTARG"
    ;;
  d)
    SDEC="$OPTARG"
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

shift $((OPTIND - 1))

# run_edalize additional arguments
[ "${1:-}" = "--" ] && shift
args=$@

###################################################################################################
# Generate RAM content
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
mkdir -p ${PROJECT_DIR}/hw/output

TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" >$TMP_FILE

INPUT_DIR=${SCRIPT_DIR}/../gen/input

if [ $GEN_STIMULI -eq 1 ]; then
  echo "INFO> Creating input dir : ${INPUT_DIR}"
  mkdir -p $INPUT_DIR
  rm -rf ${INPUT_DIR}/*

  # Creating twiddles
  twd_cmd="python3 ${SCRIPT_DIR}/generate_rom.py -P $PVAL -R $RVAL -S $SVAL -si $SINIT -sd $SDEC -o $INPUT_DIR"
  echo "INFO> Running : $twd_cmd"
  $twd_cmd || exit 1

fi

###################################################################################################
# Run simulation
###################################################################################################
#################################################
# Config phase : create directory + scripts
#################################################
eda_args="-P S_DEC int $SDEC \
          -P S_INIT int $SINIT \
          -P R int $RVAL  \
          -P PSI int $PVAL \
          -P S int $SVAL "

$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -y run -y build \
             $eda_args \
             $args | tee >(grep "Work directory :" >>$TMP_FILE)

sync
>&2 echo "INFO> Reading from $TMP_FILE: $(ls -l $TMP_FILE)"
work_dir=$(cat $TMP_FILE | sed 's/Work directory : *//')
>&2 echo "INFO> Extracted work_dir : ${work_dir}"
# Delete TMP_FILE
rm -f $TMP_FILE

# Linking the folder into the output directory
echo "INFO> Link ${INPUT_DIR} to ${work_dir}/input"
if [ -d ${work_dir}/input ]; then rm ${work_dir}/input; fi
ln -s ${INPUT_DIR} ${work_dir}/input

# log command line
echo $cli > ${work_dir}/cli.log

#################################################
# Run phase : simulation
#################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args

#################################################
# Post process
#################################################
# None
