#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity

run_edalize=${PROJECT_DIR}/hw/script/edalize/run_edalize.py

RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'

module="tb_bsk_ntw_server"

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
####################################################################################################
#Write simulation command lines here
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
mkdir -p ${PROJECT_DIR}/hw/output
SEED_FILE="${PROJECT_DIR}/hw/output/${module}.seed"
echo -n "" > $SEED_FILE

CLT_L=(1 2 3 4)
SRV_L=(2 3 6)
COEF_L=(8 16 32)
BATCH_L=(2 3 4)


for ((j = 0; j < 5; j++)); do
    size=${#CLT_L[@]}
    index=$(($RANDOM % $size))
    CLT=${CLT_L[$index]}

    size=${#SRV_L[@]}
    index=$(($RANDOM % $size))
    SRV=${SRV_L[$index]}

    size=${#COEF_L[@]}
    index=$(($RANDOM % $size))
    COEF=${COEF_L[$index]}

    size=${#BATCH_L[@]}
    index=$(($RANDOM % $size))
    BATCH=${BATCH_L[$index]}

    cmd="$SCRIPT_DIR/run.sh -c $CLT -C $SRV -b $BATCH -d $COEF -- $args"
    echo "==========================================================="
    echo "INFO> Running : $cmd"
    echo "==========================================================="
    $cmd | tee >(grep "Seed" >> $SEED_FILE) |  grep "> SUCCEED !"
    exit_status=$?
    if [ $exit_status -gt 0 ]; then
      echo -e "${RED}FAILURE>${NC} $cmd" 1>&2
      exit $exit_status
    else
      echo -e "${GREEN}SUCCEED>${NC} $cmd" 1>&2
    fi
done

