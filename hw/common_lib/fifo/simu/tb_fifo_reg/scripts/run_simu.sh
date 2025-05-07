#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity

run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py

RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'

module="tb_fifo_reg"

###################################################################################################
# Usage
###################################################################################################
function usage () {
echo "Usage : run_simu.sh runs all the simulations for ${module}."
echo "./run_simu.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-- <run_edalize options> : run_edalize options."
}


###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize your own variables here:
while getopts "h" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
  esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift
args=$@


###################################################################################################
# Run simulation
###################################################################################################
# Write simulation command lines here
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
mkdir -p ${PROJECT_DIR}/hw/output
SEED_FILE="${PROJECT_DIR}/hw/output/${module}.seed"
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._tmp"
echo -n "" > $SEED_FILE
echo -n "" > $TMP_FILE

DEPTH_LAT_PIPE_MH_L=("DEPTH32_LAT_PIPE_MH{1'b1,1'b1}" \
                     "DEPTH64_LAT_PIPE_MH{1'b1,1'b1}" \
                     "DEPTH13_LAT_PIPE_MH{1'b0,1'b1}" \
                     "DEPTH13_LAT_PIPE_MH{1'b1,1'b1}" \
                     "DEPTH2_LAT_PIPE_MH{1'b0,1'b1}" \
                     "DEPTH2_LAT_PIPE_MH{1'b1,1'b1}" \
                     "DEPTH1_LAT_PIPE_MH{1'b0,1'b1}" \
                     "DEPTH1_LAT_PIPE_MH{1'b1,1'b1}")
for depth_lat_pipe_mh in "${DEPTH_LAT_PIPE_MH_L[@]}"; do
  if [[ $depth_lat_pipe_mh =~ DEPTH([0-9]+)_LAT_PIPE_MH(\{1\'b[01],1\'b[01]\})$ ]]; then
    depth=${BASH_REMATCH[1]}
    lat_pipe_mh=${BASH_REMATCH[2]}
  fi

  cmd="$run_edalize -m ${module} -t $PROJECT_SIMU_TOOL  -P DEPTH int $depth \
                                          -P LAT_PIPE_MH str \"\"$lat_pipe_mh\"\" $args"
  echo "==========================================================="
  echo "INFO> Running : $cmd"
  echo "==========================================================="
  $cmd | tee >(grep "Seed" | head -1 >> $SEED_FILE) |  grep -c "> SUCCEED !" > $TMP_FILE
  exit_status=$?
  # In case of post processing, presence of several SUCCEED is necessary to be a real success
  succeed_cnt=$(cat $TMP_FILE)
  if [ $exit_status -gt 0 ] || [ $succeed_cnt -ne 1 ] ; then
    echo -e "${RED}FAILURE>${NC} $cmd" 1>&2
    rm -f $TMP_FILE
    exit $exit_status
  else
    echo -e "${GREEN}SUCCEED>${NC} $cmd" 1>&2
  fi
done
rm -f $TMP_FILE
