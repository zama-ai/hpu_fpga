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

module="tb_ntt_core_with_matrix_multiplication_unfold_pcg"

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

R_S_PSI_BC_L=("R2_S11_PSI1_BC4_D6" "R2_S11_PSI2_BC8_D4" "R2_S11_PSI4_BC16_D6" "R2_S11_PSI8_BC32_D6" "R2_S11_PSI16_BC64_D6")

for i in {1..3}; do
#for param in "${R_S_PSI_BC_L[@]}"; do
    size=${#R_S_PSI_BC_L[@]}
    index=$(($RANDOM % $size))
    param=${R_S_PSI_BC_L[$index]}
    if [[ $param =~ R([0-9]+)_S([0-9]+)_PSI([0-9]+)_BC([0-9]+)_D([0-9]+)$ ]]; then
        R=${BASH_REMATCH[1]}
        S=${BASH_REMATCH[2]}
        PSI=${BASH_REMATCH[3]}
        BSK_COEF=${BASH_REMATCH[4]}
        DELTA=${BASH_REMATCH[5]}
    fi

    #PBS_L=$((1+$RANDOM % 4)) # Random value from 1 to 4
    PBS_L=$((1+$RANDOM % 2)) # Random value from 1 to 2

    RAM_LATENCY=$((1+$RANDOM % 2))
    ASSEMBLY=$(($RANDOM % 2))

    if [ $ASSEMBLY -eq 1 ] && [ $(($S / $DELTA)) -gt 1 ]; then
      # The assembly test version does not support too small delta
      ASSEMBLY=0
    fi

    if [ $ASSEMBLY -eq 0 ]; then
      ASSEMBLY_OPTION=""
    else
      ASSEMBLY_OPTION="-p"
    fi

    if [ $PSI -gt 1 ] && [ $PBS_L -gt 1 ] ; then
        # Find a BWD_PSI_DIV that divides PSI and is smaller of equal to PBS_L
        PSI_W=`echo $PSI | awk '{print log($1)/log(2)}'`
        if [ $PSI_W -eq 1 ] ; then # PSI == 2
            BWD_PSI_DIV_TMP=1
        else
            BWD_PSI_DIV_TMP=$((1+ $RANDOM % $PSI_W))
            while [ $((2**$BWD_PSI_DIV_TMP)) -gt $PBS_L ] ; do
              BWD_PSI_DIV_TMP=$((1 + $RANDOM % $PSI_W))
            done
        fi
    else
      BWD_PSI_DIV_TMP=0
    fi
    BWD_PSI_DIV=$((2**$BWD_PSI_DIV_TMP))

    cmd="${SCRIPT_DIR}/run.sh \
                    -C \
                    $ASSEMBLY_OPTION \
                    -R $R \
                    -S $S \
                    -P $PSI \
                    -l $PBS_L \
                    -a $BSK_COEF \
                    -e $BWD_PSI_DIV \
                    -J $DELTA \
                    -- -P RAM_LATENCY int $RAM_LATENCY $args"
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
