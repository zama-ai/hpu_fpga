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

module="tb_stream_sink"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-- <run_edalize options> : run_edalize options."
}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

run_edalize_args=""

# Initialize your own variables here:
while getopts "h" opt; do
  case "$opt" in
    h)
      usage
      exit 0
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
# Run simulation
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)


TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo "" > $TMP_FILE

#################################################
# Config phase : create directory + scripts
#################################################
# Get current working directory
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -y run -y build $args | tee >(grep "Work directory :" >> $TMP_FILE)
sync
>&2 echo "INFO> Reading from $TMP_FILE: $(ls -l $TMP_FILE)"
work_dir=$(cat $TMP_FILE | sed 's/Work directory : *//')
>&2 echo "INFO> Extracted work_dir : ${work_dir}"

# Delete TMP_FILE
rm -f $TMP_FILE


#################################################
# Build stimuli
#################################################
# create output dir
echo "INFO> creating output dir : ${work_dir}/output"
mkdir -p  ${work_dir}/output

# Create input stimuli if necessary

# Link
echo "INFO> Link ${SCRIPT_DIR}/../input to ${work_dir}/input"
if [ -d ${work_dir}/input ] ; then rm ${work_dir}/input ; fi
ln -s ${SCRIPT_DIR}/../input ${work_dir}/input

# log command line
echo $cli > ${work_dir}/cli.log

#################################################
# Run simulation
#################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $args

#################################################
# Post process
#################################################
pp=$(diff -q ${work_dir}/output/stream_spy.dat ${work_dir}/input/wr_ref.dat)
exit_status=$?
if [ -z $pp ] && [ $exit_status -eq 0 ] ; then
  echo "> SUCCEED ! Post process OK."
  exit 0;
else
  echo "> FAILURE ! Post process KO."
  exit 1;
fi
