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

module="tb_pep_load_glwe"

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
PSI_MIN=2
AXI_DATA_W_L=("512" "256" "128")
MSPLIT_TYPE_L=("PEP_MSPLIT_main2_subs2" "PEP_MSPLIT_main1_subs3" "PEP_MSPLIT_main3_subs1")
SLR_LATENCY_L=(0 4 6)

for i in `seq 1 5`; do
  # Choose AXI_DATA_W
  size=${#AXI_DATA_W_L[@]}
  index=$(($RANDOM % $size))
  AXI_DATA_W=${AXI_DATA_W_L[$index]}

  S=$((4+$RANDOM % 8))
  GLWE_K=$((1+$RANDOM % 3))

  N=$((2**$S))

  PSI=$(($PSI_MIN+$RANDOM % 5))
  while [ $(( $R * 2**$PSI)) -gt $N ] ; do
    PSI=$(($PSI_MIN+$RANDOM % 5))
  done
  PSI=$(( 2**$PSI ))

  MOD_Q_W=$((32+$RANDOM % 33))

  ACS_W=64
  if [ $MOD_Q_W -le 32 ]; then
    ACS_W=32
  fi
  COEF_NB=$(($AXI_DATA_W / $ACS_W))

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
        -P $PSI \
        -S $S \
        -g $GLWE_K \
        -W $MOD_Q_W \
        -- -F PEP_MSPLIT $MSPLIT_TYPE \
        -F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W}  \
        -P SLR_LATENCY int $SLR_LATENCY \
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
