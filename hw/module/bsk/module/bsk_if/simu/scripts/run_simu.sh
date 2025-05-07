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

module="tb_bsk_if"

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

NTT_W_L=("32" "48" "64")
AXI_DATA_W_L=("512" "256" "128")


for i in `seq 1 4`; do
    # Choose AXI_DATA_W
    size=${#AXI_DATA_W_L[@]}
    index=$(($RANDOM % $size))
    AXI_DATA_W=${AXI_DATA_W_L[$index]}

    BSK_SLOT_NB=$((8+$RANDOM % 8))
    R=2
    S=$((4+$RANDOM % 5))
    GLWE_K=$((1+$RANDOM % 3))
    PBS_L=$((2+$RANDOM % 3))
    LWE_K=$((4+$RANDOM % 35))
    BSK_SLOT_NB=$((2+$RANDOM % 15))

    size=${#NTT_W_L[@]}
    index=$(($RANDOM % $size))
    MOD_NTT_W=${NTT_W_L[$index]}

    BSK_ACS_W=64
    if [ $MOD_NTT_W -le 32 ]; then
      BSK_ACS_W=32
    fi
    AXI_COEF=$(( $AXI_DATA_W / $BSK_ACS_W ))


    PSI=$((0+$RANDOM % 5))
    while [ $(($R*(2**$PSI))) -gt $(( $R**$S )) ]; do
      PSI=$((0+$RANDOM % 5))
    done
    PSI=$(( 2**$PSI ))

    PBS_B_W=$((2+$RANDOM % (${MOD_NTT_W}/${PBS_L} - 2)))

    BSK_CUT_NB=$(($RANDOM % 4))
    BSK_CUT_NB=$((2**$BSK_CUT_NB))
    while [ $BSK_CUT_NB -gt $(($R*$PSI)) ]; do
      BSK_CUT_NB=$(($RANDOM % 4))
      BSK_CUT_NB=$((2**$BSK_CUT_NB))
    done

    N=$(($R ** $S))
    SLICE_COEF_NB=$(($N * ($GLWE_K+1) * $PBS_L))

    BSK_PC=$(($RANDOM % 3))
    BSK_PC=$((2**$BSK_PC))
    # BSK_PC should be less or equal to BSK_CUT_NB
    # BSK_PC*AXI_COEF should divide SLICE_COEF_NB
    while [ $BSK_PC -gt $BSK_CUT_NB ] || [ $((($SLICE_COEF_NB / ($BSK_PC*$AXI_COEF)) * ($BSK_PC*$AXI_COEF))) -ne $SLICE_COEF_NB ]; do
      BSK_PC=$(($RANDOM % 3))
      BSK_PC=$((2**$BSK_PC))
    done

    HPU_FLAG="-F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W}"
    if [ $(($RANDOM % 2)) -eq 1 ] ; then
      HPU_FLAG="$HPU_FLAG -F TOP_BATCH TOP_BATCH_TOPhpu_BPBS8_TPBS16"
    fi

    cmd="${SCRIPT_DIR}/run.sh \
          -g $GLWE_K \
          -l $PBS_L \
          -b $PBS_B_W \
          -R $R \
          -S $S \
          -P $PSI \
          -w $MOD_NTT_W \
          -K $LWE_K \
          -o $BSK_SLOT_NB \
          -f $BSK_PC \
          -u $BSK_CUT_NB \
          -- $HPU_FLAG \
          $args "

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
