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

module="tb_pep_ks_mult_outp"

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


gen_lb() {
    LBX=$((1+$RANDOM % 3))
    LBY=$((1+$RANDOM % ($S-3)))
    LBY=$(( $LBY * 8))
    LBZ=$((1+ $RANDOM % 3))
}

R=2

for i in `seq 1 5`; do
    BATCH_PBS_NB=$((1+$RANDOM % 10))
    USE_MEAN_COMPENSATION=$((0+$RANDOM % 2))
    LWE_K=$((12+$RANDOM % 15))
    MOD_Q_W=$((20+$RANDOM % 32))
    MOD_KSK_W=$((15+$RANDOM % 32))
    S=$((6+$RANDOM % 3))
    GLWE_K=$((1+$RANDOM % 3))
    KS_L=$((2+$RANDOM % 6))
    if [ $((${MOD_Q_W}/${KS_L})) -eq 2 ]; then
      KS_B_W=2
    else
      KS_B_W=$((2+$RANDOM % (${MOD_Q_W}/${KS_L} - 2)))
    fi

    gen_lb
    ${PROJECT_DIR}/hw/module/pep_key_switch/scripts/pep_ks_check_param.py \
      -R $R \
      -S $S \
      -g $GLWE_K \
      -L $KS_L \
      -X $LBX \
      -Y $LBY \
      -Z $LBZ \
      -B $KS_B_W \
      -W $MOD_Q_W \
      -dM $BATCH_PBS_NB
    while [ $? -ne 0 ] ; do
      gen_lb
      ${PROJECT_DIR}/hw/module/pep_key_switch/scripts/pep_ks_check_param.py \
        -R $R \
        -S $S \
        -g $GLWE_K \
        -L $KS_L \
        -X $LBX \
        -Y $LBY \
        -Z $LBZ \
        -B $KS_B_W \
        -W $MOD_Q_W \
      -dM $BATCH_PBS_NB
    done

    cmd="${SCRIPT_DIR}/run.sh \
          -g $GLWE_K \
          -R $R \
          -K $LWE_K \
          -S $S \
          -L $KS_L \
          -B $KS_B_W \
          -W $MOD_Q_W \
          -V $MOD_KSK_W \
          -q "2**$MOD_Q_W" \
          -r "2**$MOD_KSK_W" \
          -X $LBX \
          -Y $LBY \
          -Z $LBZ \
          -c $BATCH_PBS_NB \
          -d $USE_MEAN_COMPENSATION \
          -- \
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
