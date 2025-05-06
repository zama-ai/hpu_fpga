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

module="tb_ntt_core_gf64_without_pp"

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

# constant
R=2
PBS_L=1

GLWE_K=$((1 + $RANDOM%3))

for j in `seq 1 1`; do
  S=$(( 5 + $RANDOM % 7 ))
  N=$((2**S))

  for i in `seq 1 2`; do
    S_N=$(( 1 + $RANDOM % 5 )) # NGC up to 32
    S_C=$(( 1 + $RANDOM % 6 )) # Cyc up to 64
    S_C2=$(( $S - $S_N - $S_C ))

    while [ $S_C2 -lt 0 ] || [ $S_C2 -gt 6 ] ; do
      S_N=$(( 1 + $RANDOM % 5 ))
      S_C=$(( 1 + $RANDOM % 6 ))
      S_C2=$(( $S - $S_N - $S_C ))
    done

    cut_arg="-J $S_N -J $S_C"

    if [ $S_C2 -gt 0 ] ; then
      cut_arg="$cut_arg -J $S_C2"
    fi

    MAX_S_L=$S_N
    if [ $MAX_S_L -lt $S_C ]; then
      MAX_S_L=$S_C
    fi
    if [ $MAX_S_L -lt $S_C2 ]; then
      MAX_S_L=$S_C2
    fi

    PSI_LOG_MIN=$(($MAX_S_L-1))


    for psi_log in `seq $PSI_LOG_MIN $(($S-1))`; do

      PSI=$((2**$psi_log))

      SPLIT_0=$(( 1 + $RANDOM % (2*$S) ))
      SPLIT_1=$(( 0 + $RANDOM % (2*$S - $SPLIT_0 + 1) ))
      SPLIT_2=$(( 2*S - $SPLIT_0 - $SPLIT_1))
      while [ $SPLIT_2 -lt 0 ] ; do
        SPLIT_0=$(( 1 + $RANDOM % (2*$S) ))
        SPLIT_1=$(( 0 + $RANDOM % (2*$S - $SPLIT_0 + 1) ))
        SPLIT_2=$(( 2*S - $SPLIT_0 - $SPLIT_1))
      done

      split_arg="-c $SPLIT_0"
      if [ $SPLIT_1 -gt 0 ] ; then
        split_arg="$split_arg -c $SPLIT_1"
      fi
      if [ $SPLIT_2 -gt 0 ] ; then
        split_arg="$split_arg -c $SPLIT_2"
      fi

      cmd="${SCRIPT_DIR}/run.sh \
                -g $GLWE_K -R $R -P $PSI -S $S $cut_arg $split_arg \
                -- $args"
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
  done
done
