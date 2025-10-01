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

module="tb_pep_load_blwe"

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
S=12
N=$(($R ** $S))

RAND_RANGE=$((1024-1))
INST_THROUGHPUT_L=("0" "$(($RAND_RANGE/2))" "$((RAND_RANGE/10))" "$((RAND_RANGE/100))" "$RAND_RANGE")
for i in `seq 1 5`; do
    size=${#INST_THROUGHPUT_L[@]}
    index=$(($RANDOM % $size))
    INST_THROUGHPUT=${INST_THROUGHPUT_L[$index]}

    PSI=$(($RANDOM % ($S-1)))
    PSI=$((2**$PSI))

    GLWE_K=$((1+$RANDOM % 3))
    S=$((6+$RANDOM % 5))

    # Maximum value supported by the instruction
    REGF_REG_NB=128

    REGF_COEF_NB=$((1+$RANDOM % 6))
    REGF_COEF_NB=$((2**$REGF_COEF_NB))

    REGF_SEQ=$(($RANDOM % 4))
    REGF_SEQ=$((2**$REGF_SEQ))
    while [ $REGF_SEQ -gt $REGF_COEF_NB ] ; do
      REGF_SEQ=$(($RANDOM % 4))
      REGF_SEQ=$((2**$REGF_SEQ))
    done

    DIV=$(($RANDOM % 2))
    DIV=$((2**$DIV))
    while [ $DIV -gt $(( $REGF_COEF_NB / $REGF_SEQ)) ] ; do
      DIV=$(($RANDOM % 3))
      DIV=$((2**$DIV))
    done
    MOD_Q_W=$((64 / $DIV))

    LBY=$((1+$RANDOM % 5))
    LBY=$(( $LBY * ($REGF_COEF_NB / $REGF_SEQ) ))
    while [ $LBY -gt $REGF_COEF_NB ] && [ $(($LBY % $REGF_COEF_NB)) -ne 0 ] ; do
      LBY=$((1+$RANDOM % 5))
      LBY=$(($LBY * $REGF_COEF_NB))
    done
    while [ $LBY -lt $REGF_COEF_NB ] && [ $(($REGF_COEF_NB % $LBY)) -ne 0 ] ; do
      LBY=$((1+$RANDOM % 2))
      LBY=$(($LBY * ($REGF_COEF_NB / $REGF_SEQ)))
    done

    GRAM_NB=$((3+$RANDOM%2))
    BATCH_PBS_NB=$((1+$RANDOM % 10))
    BATCH_PBS_NB=$(($GRAM_NB * $BATCH_PBS_NB))
    TOTAL_PBS_NB=$((1 + $RANDOM % 5))
    TOTAL_PBS_NB=$(($TOTAL_PBS_NB*$GRAM_NB + $BATCH_PBS_NB))

    cmd="${SCRIPT_DIR}/run.sh \
          -g $GLWE_K \
          -R $R \
          -S $S \
          -P $PSI \
          -W $MOD_Q_W \
          -Y $LBY \
          -i $REGF_REG_NB \
          -j $REGF_COEF_NB \
          -k $REGF_SEQ \
          -c $BATCH_PBS_NB \
          -H $TOTAL_PBS_NB \
          -G $GRAM_NB \
          -- \
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
