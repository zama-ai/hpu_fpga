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

module="tb_ksk_manager"

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
    KSK_SLOT_NB=$((8+$RANDOM % 8))
    R=2
    S=$((6+$RANDOM % 3))
    MOD_KSK_W=$((32+$RANDOM % 33))
    KS_L=$((2+$RANDOM % 6))
    KS_B_W=$((2+$RANDOM % (${MOD_KSK_W}/${KS_L} - 2)))
    LBX=$((1+$RANDOM % 3))
    LBY=$((1+$RANDOM % ($S-3)))
    LBY=$(( $LBY * 8))
    LBZ=$((1+ $RANDOM % 3))
    LWE_K=$((12+$RANDOM % 35))
    BATCH_PBS_NB=$((4+$RANDOM % 5))
    while [ $KSK_SLOT_NB -ge $(( $LWE_K / $LBX )) ]; do
      LWE_K=$((12+$RANDOM % 50))
    done

    KSK_CUT_NB=$(($RANDOM % 4))
    KSK_CUT_NB=$((2**$KSK_CUT_NB))
    if [ $(( $LBY % $KSK_CUT_NB )) -ne 0 ]; then
        KSK_CUT_NB=$(($RANDOM % 4))
        KSK_CUT_NB=$((2**$KSK_CUT_NB))
    fi

    cmd="${SCRIPT_DIR}/run.sh \
          -R $R \
          -S $S \
          -V $MOD_KSK_W \
          -r "2**$MOD_KSK_W" \
          -c $BATCH_PBS_NB \
          -K $LWE_K \
          -L $KS_L \
          -B $KS_B_W \
          -E $KSK_SLOT_NB \
          -U $KSK_CUT_NB \
          -X $LBX \
          -Y $LBY \
          -Z $LBZ \
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
