#! /usr/bin/bash
# =============================================================================================== #
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# Goal of this script is to test some parameters and launch testbenches for the MHDMA module.
#
# Parameter sweep:
#   - AXI_DATA_W : 128, 256, 512
#   - GLWE_K     : 1, 2 (drives BLWE_K = GLWE_K * N)
#   - PEM_PC     : 1, 2 for unit tests ; 2 only for top-level & scenario tests
#
# Top module of MHDMA supports only PEM_PC=1 & 2
#   - Main reason is that regfile must be re generated for the address
#   - For PEM_PC >= 4: CDC FIFO are overflowing and we will need to split them
#   - Efforts has been put to try top testbench with PEM_PC = 1 not with other top-scenarios
#
# -> AXI data size could be 128; 256 or 512 (even though in FPGA it's fixed to 256)
#
# All unit testbenches must be launched as well as specific and the main one
# =============================================================================================== #

run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py

RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'

# Unit test modules (not constrained by regfile: can vary PEM_PC)
UNIT_TESTS=("tb_mhdma_decoder" "tb_mhdma_formatter" "tb_mhdma_master" "tb_mhdma_slave")

# Scenario tests (use top-level, PEM_PC=2 only)
SCENARIO_TESTS=("tb_mhdma_errors" "tb_mhdma_notify_insertion" "tb_mhdma_parallel_read" "tb_mhdma_parallel_notify" "tb_mhdma_pkt_loss")

# top module scenario
module="tb_multi_hpu_dma"

###################################################################################################
# Usage
###################################################################################################
function usage () {
echo "Usage : run_simu.sh runs all the simulations for ${module}."
echo "./run_simu.sh [options]"
echo "Options are:"
echo "-s                       : full parameter sweep (all PEM_PC x GLWE_K x AXI_DATA_W combos)."
echo "-h                       : print this help."
echo "-- <run_edalize options> : run_edalize options."
}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize your own variables here:
FULL_SWEEP=0

while getopts "sh" opt; do
  case "$opt" in
    s)
      FULL_SWEEP=1
      ;;
    h)
      usage
      exit 0
      ;;
  esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift
args="$@"

###################################################################################################
# Run simulation
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
mkdir -p ${PROJECT_DIR}/hw/output
SEED_FILE="${PROJECT_DIR}/hw/output/${module}.seed"
echo -n "" > $SEED_FILE

###################################################################################################
# Helper: run one test, exit on failure
###################################################################################################
function run_test () {
  local cmd="$1"
  local TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._tmp"
  echo -n "" > $TMP_FILE

  echo "==========================================================="
  echo "INFO> Running : $cmd"
  echo "==========================================================="
  $cmd | tee >(grep "Seed" | head -1 >> $SEED_FILE) | grep -c "> SUCCEED !" > $TMP_FILE
  local cmd_exit=${PIPESTATUS[0]}
  # In case of post processing, presence of several SUCCEED is necessary to be a real success
  local succeed_cnt=$(cat $TMP_FILE)
  rm -f $TMP_FILE
  if [ $cmd_exit -gt 0 ] || [ $succeed_cnt -ne 1 ] ; then
    echo -e "${RED}FAILURE>${NC} $cmd" 1>&2
    exit $cmd_exit
  else
    echo -e "${GREEN}SUCCEED>${NC} $cmd" 1>&2
  fi
}

###################################################################################################
# Parameter sweep definitions
###################################################################################################
AXI_DATA_W_LIST=("128" "256" "512")
GLWE_K_LIST=("1" "2")

# PEM_PC values for unit tests (top-level & scenarios are locked to PEM_PC=2)
PEM_PC_LIST_UNIT=("1" "2")

index=$(($RANDOM % 3))
AXI_DATA_W=${AXI_DATA_W_LIST[$index]}
index=$(($RANDOM % 2))
GLWE_K=${GLWE_K_LIST[$index]}
index=$(($RANDOM % 2))
PEM_PC=${PEM_PC_LIST_UNIT[$index]}

###################################################################################################
# 1) Unit tests: sweep PEM_PC x GLWE_K x AXI_DATA_W
###################################################################################################
echo "================================================================"
echo "INFO> Running unit tests with selected parameters"
echo "================================================================"

if [ $FULL_SWEEP -eq 1 ]; then
  for PEM_PC in "${PEM_PC_LIST_UNIT[@]}"; do
    for GLWE_K in "${GLWE_K_LIST[@]}"; do
      for AXI_DATA_W in "${AXI_DATA_W_LIST[@]}"; do
        for TB in "${UNIT_TESTS[@]}"; do
          run_test "${SCRIPT_DIR}/run.sh \
            -g $GLWE_K \
            -E $PEM_PC \
            -- $args \
            -m $TB \
            -F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W}"
        done
      done
    done
  done
else
  for TB in "${UNIT_TESTS[@]}"; do
    run_test "${SCRIPT_DIR}/run.sh \
      -g $GLWE_K \
      -E $PEM_PC \
      -- $args \
      -m $TB \
      -F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W}"
  done
fi

# ###################################################################################################
# # 2) Top-level test: sweep PEM_PC x GLWE_K x AXI_DATA_W
# ###################################################################################################
# echo "================================================================"
# echo "INFO> Running top-level ${module} with selected parameters"
# echo "================================================================"

if [ $FULL_SWEEP -eq 1 ]; then
  for PEM_PC in "${PEM_PC_LIST_UNIT[@]}"; do
    for GLWE_K in "${GLWE_K_LIST[@]}"; do
      for AXI_DATA_W in "${AXI_DATA_W_LIST[@]}"; do
        run_test "${SCRIPT_DIR}/run.sh \
          -g $GLWE_K \
          -E $PEM_PC \
          -- $args \
          -F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W}"
      done
    done
  done
else
  run_test "${SCRIPT_DIR}/run.sh \
    -g $GLWE_K \
    -E $PEM_PC \
    -- $args \
    -F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W}"
fi

###################################################################################################
# 3) Scenario tests: PEM_PC=2, sweep GLWE_K x AXI_DATA_W
###################################################################################################
echo "================================================================"
echo "INFO> Running scenario tests with selected parameters"
echo "================================================================"

if [ $FULL_SWEEP -eq 1 ]; then
  for GLWE_K in "${GLWE_K_LIST[@]}"; do
    for AXI_DATA_W in "${AXI_DATA_W_LIST[@]}"; do
      for TB in "${SCENARIO_TESTS[@]}"; do
        run_test "${SCRIPT_DIR}/run.sh \
          -g $GLWE_K \
          -E 2 \
          -- $args \
          -m $TB \
          -F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W}"
      done
    done
  done
else
  for TB in "${SCENARIO_TESTS[@]}"; do
    run_test "${SCRIPT_DIR}/run.sh \
      -g $GLWE_K \
      -E 2 \
      -- $args \
      -m $TB \
      -F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W}"
  done
fi

echo -e "${GREEN}ALL TESTS PASSED${NC}" 1>&2
