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

module="tb_pem_store"

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
AXI_DATA_W_L=("512" "256" "128")

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

    DIV=$(($RANDOM % 2))
    DIV=$((2**$DIV))
    while [ $DIV -gt $(( $REGF_COEF_NB / $REGF_SEQ)) ] ; do
      DIV=$(($RANDOM % 2))
      DIV=$((2**$DIV))
    done
    MOD_Q_W=$((64 / $DIV))



    PEM_PC=$(($RANDOM % 3))
    PEM_PC=$((2**$PEM_PC))
    while [ $PEM_PC -gt $REGF_COEF_NB ] || [ $PEM_PC -gt $REGF_SEQ ] ; do
      PEM_PC=$(($RANDOM % 3))
      PEM_PC=$((2**$PEM_PC))
    done

    # Choose AXI_DATA_W
    size=${#AXI_DATA_W_L[@]}
    index=$(($RANDOM % $size))
    AXI_DATA_W=${AXI_DATA_W_L[$index]}

    BLWE_COEF_PER_AXI4_WORD=$(( $AXI_DATA_W / $MOD_Q_W))

    PEP_PERIOD=1
    PEA_PERIOD=32
    PEM_PERIOD_TMP=$(( ($REGF_COEF_NB / $PEM_PC) / $BLWE_COEF_PER_AXI4_WORD ))
    PEM_PERIOD_TMP2=$(( $REGF_SEQ / $PEM_PC ))
    if [ $PEM_PERIOD_TMP -eq 0 ] ; then
      # The system is fast enough to accept all the data from the regfile
      PEM_PERIOD_TMP=1
    fi
    if [ $PEM_PERIOD_TMP2 -eq 0 ] ; then
      PEM_PERIOD_TMP2=1
    fi

    if [ $PEM_PERIOD_TMP -gt $PEM_PERIOD_TMP2 ] ; then
      PEM_PERIOD=$PEM_PERIOD_TMP
    else
      PEM_PERIOD=$PEM_PERIOD_TMP2
    fi

    PEM_PERIOD=$(( $PEM_PERIOD + +$RANDOM % 2 ))

    cmd="${SCRIPT_DIR}/run.sh \
          -g $GLWE_K \
          -R $R \
          -S $S \
          -W $MOD_Q_W \
          -i $REGF_REG_NB \
          -j $REGF_COEF_NB \
          -k $REGF_SEQ \
          -E $PEM_PC \
          -- $args \
          -P PEA_PERIOD int $PEA_PERIOD \
          -P PEM_PERIOD int $PEM_PERIOD \
          -P PEP_PERIOD int $PEP_PERIOD \
          -F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W}"

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
