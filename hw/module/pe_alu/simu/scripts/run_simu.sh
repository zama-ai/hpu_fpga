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

module="tb_pe_alu"

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
PEM_PERIOD=2
PEP_PERIOD=1


for i in `seq 1 5`; do
    GLWE_K=$((1+$RANDOM % 3))
    S=$((6+$RANDOM % 5))

    REGF_REG_NB=$((1+$RANDOM % 9))
    REGF_REG_NB=$((8*REGF_REG_NB))

    REGF_COEF_NB=$((1+$RANDOM % 4))
    REGF_COEF_NB=$((2**$REGF_COEF_NB))
    while [ $REGF_COEF_NB -gt $REGF_REG_NB ] ; do
      REGF_COEF_NB=$((1+$RANDOM % 4))
      REGF_COEF_NB=$((2**$REGF_COEF_NB))
    done

    REGF_SEQ=$(($RANDOM % 4))
    REGF_SEQ=$((2**$REGF_SEQ))
    while [ $REGF_SEQ -gt $REGF_COEF_NB ] ; do
      REGF_SEQ=$(($RANDOM % 4))
      REGF_SEQ=$((2**$REGF_SEQ))
    done

    DIV=$(($RANDOM % 3))
    DIV=$((2**$DIV))
    while [ $DIV -gt $(( $REGF_COEF_NB / $REGF_SEQ)) ] ; do
      DIV=$(($RANDOM % 3))
      DIV=$((2**$DIV))
    done
    MOD_Q_W=$((64 / $DIV))

    REGF_SEQ_COEF_NB=$(($REGF_COEF_NB / $REGF_SEQ))
    ALU_NB=$((1+$RANDOM % 4))
    while [ $(($REGF_SEQ_COEF_NB % $ALU_NB)) -ne 0 ] ; do
      ALU_NB=$((1+$RANDOM % 4))
    done

    if [ $REGF_COEF_NB -eq $ALU_NB ]; then
      PEA_PERIOD=2
    else
      PEA_PERIOD=$(((($REGF_COEF_NB / $ALU_NB) +$RANDOM % 4 )))
    fi

    PADDING_BIT=$(($RANDOM % 2))
    PAYLOAD_BIT=$((4 + $RANDOM % (10-3)))

    cmd="${SCRIPT_DIR}/run.sh \
          -g $GLWE_K \
          -R $R \
          -S $S \
          -W $MOD_Q_W \
          -q "2**$MOD_Q_W" \
          -i $REGF_REG_NB \
          -j $REGF_COEF_NB \
          -k $REGF_SEQ \
          -a $ALU_NB \
          -Q $PAYLOAD_BIT \
          -D $PADDING_BIT \
          -- $args \
          -P PEA_PERIOD int $PEA_PERIOD \
          -P PEM_PERIOD int $PEM_PERIOD \
          -P PEP_PERIOD int $PEP_PERIOD"

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
