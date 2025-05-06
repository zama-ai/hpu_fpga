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

module="tb_ksk_if"

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

KSK_W_L=("24" "27" "32")
AXI_DATA_W_L=("512" "256" "128")

for i in `seq 1 4`; do
    # Choose AXI_DATA_W
    size=${#AXI_DATA_W_L[@]}
    index=$(($RANDOM % $size))
    AXI_DATA_W=${AXI_DATA_W_L[$index]}

    KSK_SLOT_NB=$((8+$RANDOM % 8))
    R=2
    S=$((4+$RANDOM % 5))
    GLWE_K=$((1+$RANDOM % 3))
    KS_L=$((2+$RANDOM % 6))
    LWE_K=$((4+$RANDOM % 35))

    size=${#KSK_W_L[@]}
    index=$(($RANDOM % $size))
    MOD_KSK_W=${KSK_W_L[$index]}

    LBX=$((1+$RANDOM % 3))
    # Choose LBX such that LBX <= (LWE_K+1)
    while [ $LBX -ge $((($LWE_K+1)/2)) ] ; do
      LBX=$((1+$RANDOM % 3))
    done

    # Choose LBZ so that it KSK_ACS_W fits 64bits
    LBZ=$((1+ $RANDOM % 3))
    while [ $(( $MOD_KSK_W * $LBZ )) -gt 64 ]; do
      LBZ=$((1+ $RANDOM % 3))
    done

    KSK_ACS_W=64
    if [ $(( $MOD_KSK_W * $LBZ )) -le 32 ]; then
      KSK_ACS_W=32
    fi

    # Choose LBY and KSK_CUT_NB so that LBY/KSK_CUT_NB divides COEF_NB_PER_AXI_WORD
    # or COEF_NB_PER_AXI_WORD divides LBY
    COEF_NB_PER_AXI_WORD=$(( $AXI_DATA_W / $KSK_ACS_W ))
    LBY=$((1+$RANDOM % ((($R**$S / 2))) ))
    if [ $LBY -le $COEF_NB_PER_AXI_WORD ] ; then
      while [ $(( $COEF_NB_PER_AXI_WORD % $LBY )) -ne 0 ]; do
        LBY=$((1+$RANDOM % ($COEF_NB_PER_AXI_WORD)))
      done
    else
      while [ $(( $LBY % $COEF_NB_PER_AXI_WORD )) -ne 0 ]; do
        LBY=$((1+$RANDOM % ((($R**$S) * $GLWE_K)/$COEF_NB_PER_AXI_WORD) ))
        LBY=$(( $LBY * $COEF_NB_PER_AXI_WORD ))
      done
    fi
    if [ $LBY -ge 128 ] ; then
      LBY=$COEF_NB_PER_AXI_WORD
    fi

    KS_B_W=$((2+$RANDOM % (${MOD_KSK_W}/${KS_L} - 2)))

    KSK_CUT_NB=$(($RANDOM % 4))
    KSK_CUT_NB=$((2**$KSK_CUT_NB))
    if [ $LBY -le $COEF_NB_PER_AXI_WORD ] ; then
      while [ $(( $LBY % $KSK_CUT_NB )) -ne 0 ] || [ $(( $COEF_NB_PER_AXI_WORD % ($LBY/$KSK_CUT_NB) )) -ne 0 ]; do
        KSK_CUT_NB=$(($RANDOM % 4))
        KSK_CUT_NB=$((2**$KSK_CUT_NB))
      done
    else
      while [ $(( $LBY % $KSK_CUT_NB )) -ne 0 ] || [ $(( ($LBY/$KSK_CUT_NB) % $COEF_NB_PER_AXI_WORD )) -ne 0 ]; do
        KSK_CUT_NB=$(($RANDOM % 4))
        KSK_CUT_NB=$((2**$KSK_CUT_NB))
      done
    fi

    KSK_PC=$(($RANDOM % 3))
    KSK_PC=$((2**$KSK_PC))
    while [ $KSK_PC -gt $KSK_CUT_NB ]; do
      KSK_PC=$(($RANDOM % 3))
      KSK_PC=$((2**$KSK_PC))
    done

    HPU_FLAG="-F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W}"
    if [ $(($RANDOM % 2)) -eq 1 ] ; then
      HPU_FLAG="$HPU_FLAG -F TOP_BATCH TOP_BATCH_TOPhpu_BPBS8_TPBS16"
    fi

    cmd="${SCRIPT_DIR}/run.sh \
          -R $R \
          -S $S \
          -V $MOD_KSK_W \
          -r "2**$MOD_KSK_W" \
          -g $GLWE_K \
          -K $LWE_K \
          -L $KS_L \
          -B $KS_B_W \
          -O $KSK_SLOT_NB \
          -X $LBX \
          -Y $LBY \
          -Z $LBZ \
          -U $KSK_CUT_NB \
          -F $KSK_PC \
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
