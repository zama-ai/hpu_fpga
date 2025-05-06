#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

cli="$*"

###################################################################################################
# This script deals with the testbench run.
# This testbench has specificities that cannot be handled by run_edealize alone.
# They are handled here.
###################################################################################################

# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity
run_edalize=${PROJECT_DIR}/hw/script/edalize/run_edalize.py

module="tb_ntt_core_gf64_phi_rom"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-R                       : R: Radix (default 2)"
echo "-P                       : PSI: Number of butterflies (default 8)"
echo "-N                       : N_L: local block size (default 128)"
echo "-W                       : OP_W: phi size (default 16)"
echo "-- <run_edalize options> : run_edalize options."

}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

run_edalize_args=""
GEN_STIMULI=1
R=2
PSI=8
N_L=128
OP_W=16
# Initialize your own variables here:
while getopts "hg:R:P:N:W:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    R)
      R=$OPTARG
      ;;
    P)
      PSI=$OPTARG
      ;;
    N)
      N_L=$OPTARG
      ;;
    W)
      OP_W=$OP_ARG
      ;;
    :)
      echo "$0: Must supply an argument to -$OPTARG." >&2
      exit 1
      ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))

# run_edalize additional arguments
[ "${1:-}" = "--" ] && shift
args=$@

ITER_NB=$(($N_L/($PSI*$R)))

###################################################################################################
# Generate twiddles
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

INPUT_DIR=${SCRIPT_DIR}/../gen/input
mkdir -p  $INPUT_DIR
rm -rf ${INPUT_DIR}/*

# Need PSI files, each containing p*R*PSI .. (p+1)*R*PSI-1
char_nb=$((($OP_W+3)/4))
format="%0${char_nb}x"
for p in `seq 0 $(($PSI-1))`; do
  echo -n "" > $INPUT_DIR/twd_phi_${p}.mem
  for s in `seq 0 $(($ITER_NB-1))`; do
    for r in 0 1; do
      printf "${format}\n" $(( $s*$PSI*$R + $p*$R + $r)) >> $INPUT_DIR/twd_phi_${p}.mem
    done
  done
done

###################################################################################################
# Process
###################################################################################################
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" > $TMP_FILE

#################################################
# Config phase : create directory + scripts
#################################################
eda_args="$eda_args -P R int $R \
                    -P PSI int $PSI \
                    -P N_L int $N_L \
                    -P OP_W int $OP_W \
                    -P TWD_GF64_FILE_PREFIX str $INPUT_DIR/twd_phi"

# Get current working directory
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -y run -y build \
  $eda_args \
  $args | tee >(grep "Work directory :" >> $TMP_FILE)
sync
>&2 echo "INFO> Reading from $TMP_FILE: $(ls -l $TMP_FILE)"
work_dir=$(cat $TMP_FILE | sed 's/Work directory : *//')
>&2 echo "INFO> Extracted work_dir : ${work_dir}"

# Delete TMP_FILE
rm -f $TMP_FILE

# log command line
echo $cli > ${work_dir}/cli.log

# Link
echo "INFO> Link $INPUT_DIR to ${work_dir}/input"
if [ -d ${work_dir}/input ] ; then rm ${work_dir}/input ; fi
ln -s $INPUT_DIR ${work_dir}/input

#################################################
# Run phase : simulation
#################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args

