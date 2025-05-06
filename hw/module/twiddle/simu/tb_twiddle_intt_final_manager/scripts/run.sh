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

module="tb_twiddle_intt_final_manager"

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
SVAL=3
GEN_STIMULI=1

# Initialize your own variables here:
while getopts "hzP:R:S:" opt; do
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
  twd_cmd="python3 ${SCRIPT_DIR}/generate_rom.py -P $PVAL -R $RVAL -S $SVAL -o $INPUT_DIR"
  echo "INFO> Running : $twd_cmd"
  $twd_cmd || exit 1

fi

###################################################################################################
# Run simulation
###################################################################################################
#################################################
# Config phase : create directory + scripts
#################################################
eda_args="-P R int $RVAL  \
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
