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

module="tb_ntt_core_wmm_post_process"

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
    # ntt_core_gf64_pmr needs :
    # with : OP_W = MOD_NTT_W + 2
    # OP_W + Log2((GLWE_K+1)*PBS_L) < MOD_NTT_W + MOD_NTT_W/2
    # Therefore with MID_MOD_NTT_W >= log2((GLWE_K+1)*PBS_L)+1 +2, the condition is satisfied.
    PBS_L=$((1+$RANDOM%4))
    GLWE_K=$((1+$RANDOM%3))
    PBS_L_x_GLWE_K_P1=$(($PBS_L * ($GLWE_K + 1)))
    LOGG2_PBS_L_x_GLWE_K_P1=`echo $PBS_L_x_GLWE_K_P1 | awk '{printf("%d\n",(log($1)/log(2)) > int(log($1)/log(2)) ? int(log($1)/log(2))+1: int(log($1)/log(2)))}'`
    MID_MOD_NTT_W=$(($LOGG2_PBS_L_x_GLWE_K_P1 + 1 + 2 + $RANDOM % 28))
    MOD_NTT_W=$(($MID_MOD_NTT_W * 2))

    cmd="${SCRIPT_DIR}/run.sh -l $PBS_L -g $GLWE_K -- -P MOD_NTT_W int $MOD_NTT_W $args"
    echo "==========================================================="
    echo "INFO> Running : $cmd"
    echo "==========================================================="
    $cmd | tee >(grep "Seed" | head -1 >> $SEED_FILE) |  grep -c "> SUCCEED !" > $TMP_FILE
    exit_status=$?
    succeed_cnt=$(cat $TMP_FILE)
    rm -f $TMP_FILE
    if [ $exit_status -gt 0 ] || [ $succeed_cnt -ne 1 ] ; then
      echo -e "${RED}FAILURE>${NC} $cmd" 1>&2
      exit $exit_status
    else
      echo -e "${GREEN}SUCCEED>${NC} $cmd" 1>&2
    fi
done
