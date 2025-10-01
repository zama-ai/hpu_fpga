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

module="tb_pep_mmacc_body_ram"

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

for i in `seq 1 5`; do
  LWE_K=$((2+$RANDOM % 50))
  USE_MEAN_COMP=$(($RANDOM %2))

  cmd="${SCRIPT_DIR}/run.sh -K $LWE_K \
          -d $USE_MEAN_COMP \
          -- $args"

  echo "==========================================================="
  echo "INFO> Running : $cmd"
  echo "==========================================================="
  $cmd | tee >(grep "Seed" | head -1 >> $SEED_FILE) |  grep -c "> SUCCEED !" > $TMP_FILE
  exit_status=$?
  # In case of post processing, presence of several SUCCEED is necessary to be a real success
  succeed_cnt=$(cat $TMP_FILE)
  rm -f $TMP_FILE
  if [ $exit_status -gt 0 ] || [ $succeed_cnt -ne 1 ] ; then
    echo -e "${RED}FAILURE>${NC} $cmd" 1>&2
    exit $exit_status
  else
    echo -e "${GREEN}SUCCEED>${NC} $cmd" 1>&2
  fi
done
