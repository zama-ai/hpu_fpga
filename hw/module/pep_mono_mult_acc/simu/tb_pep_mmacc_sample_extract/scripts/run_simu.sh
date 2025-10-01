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

module="tb_pep_mmacc_sample_extract"

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

PSI_MIN=2
MSPLIT_TYPE_L=("PEP_MSPLIT_main2_subs2" "PEP_MSPLIT_main1_subs3" "PEP_MSPLIT_main3_subs1")
SLR_LATENCY_L=(0 4 6)

for i in `seq 1 5`; do
    R=2
    S=$((6+$RANDOM % 6))
    GLWE_K=$((1+$RANDOM % 3)) # Random value from 1 to 3

    N=$((2**$S))


    PSI=$(($PSI_MIN+$RANDOM % 8))
    while [ $(( $R * 2**$PSI)) -ge $N ] ; do
      PSI=$(($PSI_MIN+$RANDOM % 5))
    done
    PSI=$(( 2**$PSI ))

    MOD_Q_W=$((32+$RANDOM % 33))

    GRAM_NB=$((3+$RANDOM % 2))
    BATCH_PBS_NB=$((1+$RANDOM % 10))
    BATCH_PBS_NB=$(($GRAM_NB * $BATCH_PBS_NB))
    TOTAL_PBS_NB=$((1 + $RANDOM % 5))
    TOTAL_PBS_NB=$(($TOTAL_PBS_NB*$GRAM_NB + $BATCH_PBS_NB))

    # Choose an msplit_type
    size=${#MSPLIT_TYPE_L[@]}
    index=$(($RANDOM % $size))
    MSPLIT_TYPE=${MSPLIT_TYPE_L[$index]}

    # Choose an slr_latency
    size=${#SLR_LATENCY_L[@]}
    index=$(($RANDOM % $size))
    SLR_LATENCY=${SLR_LATENCY_L[$index]}

    cmd="${SCRIPT_DIR}/run.sh \
                    -R $R \
                    -S $S \
                    -P $PSI \
                    -g $GLWE_K \
                    -W $MOD_Q_W \
                    -q 2**$MOD_Q_W \
                    -c $BATCH_PBS_NB \
                    -H $TOTAL_PBS_NB \
                    -G $GRAM_NB \
                    --  -F PEP_MSPLIT $MSPLIT_TYPE \
                        -P SLR_LATENCY int $SLR_LATENCY \
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
