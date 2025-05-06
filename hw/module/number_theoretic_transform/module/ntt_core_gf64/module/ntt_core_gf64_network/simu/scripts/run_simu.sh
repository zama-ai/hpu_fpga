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

module="tb_ntt_core_gf64_network"

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

GLWE_K=$((1 + $RANDOM%3))
PBS_L=$((1 + $RANDOM%3))

S=$(( 5 + $RANDOM % 8 ))
N=$((2**S))

for i in `seq 1 3`; do
  S_N=$(( 1 + $RANDOM % (S-1) ))
  S_C=$(( 1 + $RANDOM % ($S-$S_N) ))

  cut_arg="-J $S_N -J $S_C"
  cut_nb=2

  if [ $S -gt $(($S_N + $S_C)) ] ; then
    S_C2=$(( $S-$S_N-$S_C ))
    cut_arg="$cut_arg -J $S_C2"
    cut_nb=3
  fi

  for bwd in `seq 0 1`; do
    for c_idx in `seq 0 $(($cut_nb - 2))`; do # Do not process last col
      for psi_log in `seq 1 $(($S-1))`; do

        PSI=$((2**$psi_log))
        RDX_CUT_ID=$c_idx
        if [ $bwd -eq 1 ]; then
          RDX_CUT_ID=$(($cut_nb-1-$c_idx))
        fi

        cmd="${SCRIPT_DIR}/run.sh \
                  -g $GLWE_K -l $PBS_L -R $R -P $PSI -S $S $cut_arg \
                  -- -P RDX_CUT_ID int $RDX_CUT_ID  -P BWD int $bwd \
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
    done
  done
done
