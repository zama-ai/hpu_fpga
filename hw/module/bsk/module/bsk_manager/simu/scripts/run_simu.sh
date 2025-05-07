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

module="tb_bsk_manager"

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
echo -n "" > $SEED_FILE

R_S_PSI_L=("R2_S2_PSI2" "R4_S3_PSI8" "R4_S4_PSI16" "R8_S3_PSI1" "R8_S3_PSI16" "R8_S3_PSI8")

for param in "${R_S_PSI_L[@]}"; do
    if [[ $param =~ R([0-9]+)_S([0-9]+)_PSI([0-9]+)$ ]]; then
        R=${BASH_REMATCH[1]}
        S=${BASH_REMATCH[2]}
        PSI=${BASH_REMATCH[3]}
    fi

    GLWE_K=$((1+$RANDOM % 4))
    PBS_L=$((1+$RANDOM % 2))
    RAM_LATENCY=$((1+$RANDOM % 2))
    BSK_CUT_NB=$(($RANDOM % 3))
    BSK_CUT_NB=$((2**$BSK_CUT_NB))
    while [ $BSK_CUT_NB -gt $(($R * $PSI)) ]; do
      BSK_CUT_NB=$(($RANDOM % 3))
      BSK_CUT_NB=$((2**$BSK_CUT_NB))
    done

    cmd="$SCRIPT_DIR/run.sh -R $R -S $S -P $PSI -l $PBS_L -u $BSK_CUT_NB -g $GLWE_K -- -P RAM_LATENCY int $RAM_LATENCY $args"
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
