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

module="tb_pep_key_switch"

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
    R=2
    S=$((7+$RANDOM % 4))
    GLWE_K=$((1+$RANDOM % 3))
    MOD_Q_W=$((32+$RANDOM % 32))
    KS_L=$((1+$RANDOM % 6))
    KS_B_W=$((2+$RANDOM % (${MOD_Q_W}/${KS_L} - 2)))

    LBX=$((1+$RANDOM % 3))
    LBY=$((1+$RANDOM % ($S-3)))
    LBY=$(( $LBY * 8))
    LBZ=$((1+ $RANDOM % 3))

    N=$(($R ** $S))
    ITER_CYCLE=$((($N*$GLWE_K)/($LBY*$LBX)))
    if [ $ITER_CYCLE -gt 32 ] ; then
      ITER_CYCLE=32
    fi

    LWE_K=$((2+$RANDOM % 32))
    while [ $(($LWE_K / $LBX)) -le 1 ] ; do
       LWE_K=$((2+$RANDOM % 32))
    done

    BATCH_PBS_NB=$((1+ $RANDOM % $ITER_CYCLE))
    TOTAL_PBS_NB=$(($BATCH_PBS_NB + 1 + $RANDOM % 16))
    KS_IF_SUBW_NB=$(($RANDOM %2))
    KS_IF_SUBW_NB=$((2**$KS_IF_SUBW_NB))
    KS_IF_COEF_NB=$(($LBY / $KS_IF_SUBW_NB))
    USE_MEAN_COMP=$(($RANDOM %2))

    cmd="${SCRIPT_DIR}/run.sh \
          -R $R \
          -S $S \
          -g $GLWE_K \
          -L $KS_L \
          -B $KS_B_W \
          -W $MOD_Q_W \
          -q "2**$MOD_Q_W" \
          -X $LBX \
          -Y $LBY \
          -Z $LBZ \
          -K $LWE_K \
          -c $BATCH_PBS_NB \
          -H $TOTAL_PBS_NB \
          -x $KS_IF_SUBW_NB \
          -y $KS_IF_COEF_NB \
          -d $USE_MEAN_COMP \
          -- $args "

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
