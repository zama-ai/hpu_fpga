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

module="tb_pep_sequencer"

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

R=2

RAND_RANGE=$((1024-1))
INST_THROUGHPUT_L=("0" "$(($RAND_RANGE/2))" "$((RAND_RANGE/10))" "$((RAND_RANGE/100))" "$RAND_RANGE")

for i in `seq 1 5`; do
    size=${#INST_THROUGHPUT_L[@]}
    index=$(($RANDOM % $size))
    INST_THROUGHPUT=${INST_THROUGHPUT_L[$index]}

    USE_BPIP=$(($RANDOM % 2))

    if [ $USE_BPIP -eq 1 ] ; then
      USE_OPPORTUNISM=$(($RANDOM % 2))
    else
      USE_OPPORTUNISM=0
    fi


    S=$((9 + $RANDOM % 4))

    PSI=$(($RANDOM % ($S-1)))
    PSI=$((2**$PSI))

    LBX=$((1+$RANDOM % 5))
    LWE_K=$((5*$LBX + $RANDOM % 30))

    GRAM_NB=$((3+$RANDOM%2))
    BATCH_PBS_NB=$((1+$RANDOM % 10))
    BATCH_PBS_NB=$(($GRAM_NB * $BATCH_PBS_NB))
    TOTAL_PBS_NB=$((1 + $RANDOM % 5))
    TOTAL_PBS_NB=$(($TOTAL_PBS_NB*$GRAM_NB + $BATCH_PBS_NB))

    cmd="${SCRIPT_DIR}/run.sh \
          -R $R \
          -S $S \
          -P $PSI \
          -K $LWE_K \
          -X $LBX \
          -c $BATCH_PBS_NB \
          -H $TOTAL_PBS_NB \
          -G $GRAM_NB \
          -- \
          -P USE_BPIP int $USE_BPIP \
          -P USE_OPPORTUNISM int $USE_OPPORTUNISM \
          -P INST_THROUGHPUT int $INST_THROUGHPUT \
          -P RAND_RANGE int $RAND_RANGE \
          $args"

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
