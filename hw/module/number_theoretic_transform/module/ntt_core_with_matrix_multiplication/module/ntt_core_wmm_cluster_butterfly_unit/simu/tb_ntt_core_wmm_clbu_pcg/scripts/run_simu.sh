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

module="tb_ntt_core_wmm_clbu_pcg"

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

R_PSI=("R2_PSI1" "R2_PSI2" "R2_PSI4" "R2_PSI8" "R2_PSI16")
S_RSDELTA_LSDELTA=("S6_RSDELTA1_LSDELTA5" "S8_RSDELTA7_LSDELTA1" "S6_RSDELTA3_LSDELTA3" "S8_RSDELTA5_LSDELTA3")


for i in {1..5}; do

  size=${#R_PSI[@]}
  index=$(($RANDOM % $size))
  CUR_R_PSI=${R_PSI[$index]}

  size=${#S_RSDELTA_LSDELTA[@]}
  index=$(($RANDOM % $size))
  CUR_S_RSDELTA_LSDELTA=${S_RSDELTA_LSDELTA[$index]}

  if [[ $CUR_R_PSI =~ R([0-9]+)_PSI([0-9]+)$ ]]; then
    R=${BASH_REMATCH[1]}
    PSI=${BASH_REMATCH[2]}
  fi

  if [[ $CUR_S_RSDELTA_LSDELTA =~ S([0-9]+)_RSDELTA([0-9]+)_LSDELTA([0-9]+)$ ]]; then
    S=${BASH_REMATCH[1]}
    RS_DELTA=${BASH_REMATCH[2]}
    LS_DELTA=${BASH_REMATCH[3]}
  fi

  cmd="$run_edalize -m ${module} -t $PROJECT_SIMU_TOOL \
        -P R int $R \
        -P PSI int $PSI \
        -P S int $S \
        -P RS_DELTA int $RS_DELTA \
        -P LS_DELTA int $LS_DELTA \
        -F NTT_RADIX_COOLEY_TUKEY NTT_RADIX_COOLEY_TUKEY_bypass \
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
