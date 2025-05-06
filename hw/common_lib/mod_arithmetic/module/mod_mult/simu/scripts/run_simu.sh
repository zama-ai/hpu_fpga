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

module="tb_mod_mult"

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
echo "" > $SEED_FILE

MULT_CORE=$((512+0))
MULT_KARATSUBA=$((512+1))
MULT_KARATSUBA_CASCADE=$((512+2))
MULT_GOLDILOCKS=$((512+3))
MULT_GOLDILOCKS_CASCADE=$((512+4))

MOD_MULT_SOLINAS2=$((768+0))
MOD_MULT_SOLINAS3=$((768+1))
MOD_MULT_MERSENNE=$((768+2))
MOD_MULT_GOLDILOCKS=$((768+3))
MOD_MULT_BARRETT=$((768+4))

MOD_MULT_TYPE_L=($MOD_MULT_MERSENNE $MOD_MULT_BARRETT $MOD_MULT_SOLINAS2 $MOD_MULT_SOLINAS3 $MOD_MULT_GOLDILOCKS)

for mod_mult_type in "${MOD_MULT_TYPE_L[@]}"; do
  if [ $mod_mult_type -eq $MOD_MULT_GOLDILOCKS ] ; then
    MOD_W_L=(64)
    MULT_TYPE_L=($MULT_GOLDILOCKS $MULT_GOLDILOCKS_CASCADE)
  else
    MOD_W_L=(8 12 32)
    MULT_TYPE_L=($MULT_CORE $MULT_KARATSUBA)
  fi
  for mod_w in "${MOD_W_L[@]}"; do
    if [ $mod_w -eq 32 ]; then
      MULT_TYPE_L+=($MULT_KARATSUBA_CASCASE)
    fi

    for mult_type in "${MULT_TYPE_L[@]}"; do
      v=0
      if [ $mod_mult_type = $MOD_MULT_MERSENNE ] ; then
        v=$((2**${mod_w}-1))
      else
        if [ $mod_mult_type = $MOD_MULT_SOLINAS2 ] ; then
          v=$((2**${mod_w}-2**(${mod_w}/2-1)+1))
        else
          if [ $mod_mult_type = $MOD_MULT_SOLINAS3 ] ; then
            v=$((2**${mod_w}-2**(${mod_w}/3*2)-2**(${mod_w}/3)+1))
          fi
        fi
      fi
      arg_mod_m="";
      if [ $v -gt 0 ]; then
        arg_mod_m="-P MOD_M int ${v}"
      fi

      cmd="$run_edalize -m ${module} -t $PROJECT_SIMU_TOOL $args -P MULT_TYPE_INT int $mult_type -P MOD_W int ${mod_w} -P MOD_MULT_TYPE_INT int ${mod_mult_type} ${arg_mod_m}"
      echo "==========================================================="
      echo "INFO> Running : $cmd"
      echo "==========================================================="
      $cmd | tee >(grep "Seed" >> $SEED_FILE) |  grep "> SUCCEED !"
      exit_status=$?
      if [ $exit_status -gt 0 ]; then
        echo -e "${RED}FAILURE>${NC} $cmd" 1>&2
        exit $exit_status
      else
        echo -e "${GREEN}SUCCEED>${NC} $cmd" 1>&2
      fi
    done
  done
done
