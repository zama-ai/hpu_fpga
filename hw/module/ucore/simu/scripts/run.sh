#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

cli="$*"

###################################################################################################
# This script deals with the testbench run.
# This testbench has specificities that cannot be handled by run_edalize alone.
# They are handled here.
###################################################################################################

###################################################################################################
# Register trap for SIGINT:
# Aims is to properly terminate the hpu_mockup backend task if launched
###################################################################################################
trap 'if [[ ! -z ${hpu_mockup_pid+x} ]]; then kill ${hpu_mockup_pid}; fi; exit' SIGINT

# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity
run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py

module="tb_ucore"

###################################################################################################
# Default values
###################################################################################################
SOFT_NAME=ucore_fw
SOFT_TARGET=microblaze

run_edalize_args=""
GEN_STIMULI=1

INT_SIZE=16
IOP="ADD"

SEED=-1
CLEAN=0


###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-s                       : seed (if not given, random value.)"
echo "-n                       : Integer size (default $INT_SIZE)"
echo "-x                       : software top file (default = \"${SOFT_NAME}\")"
echo "-a                       : default ucode IOP (default CUST_0)"
echo "-- <run_edalize options> : run_edalize options."
}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1 # Reset in case getopts has been used previously in the shell.

# Initialize your own variables here:
while getopts "hzCn:x:a:s:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    z)
      echo "Do not generate stimuli."
      GEN_STIMULI=0
      ;;
    C)
      echo "Clean gen directory at the end of the run."
      CLEAN=1
      ;;
    n)
      INT_SIZE=$OPTARG
      ;;
    x)
      echo "INFO> Embedded Software top file $OPTARG"
      SOFT_NAME=$OPTARG
      ;;
    a)
      IOP=$OPTARG
      ;;
    s)
      SEED=$OPTARG
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

[ "${1:-}" = "--" ] && shift
args=$@
echo "IOp selected are $IOP"
IOPS=""
for iop in ${IOP[@]}; do
    IOPS="${IOPS} --iop $iop"
done
echo "hpu_bench iop arg is $IOPS"

###################################################################################################
# SEED
###################################################################################################
# Check if a seed has been given in run_edalize option.
eda_args=""
if [[ ${args} =~ .*-s( +)([0-9]+) ]]; then
  if [ $SEED -ne -1 ]; then
    echo "WARNING> 2 seed values given, use the one defined for run_edalize."
  fi
  SEED=${BASH_REMATCH[2]}
  echo "INFO> Use seed from run_edalize arguments: $SEED"
else
  if [ $SEED -eq -1 ]; then
    SEED=$RANDOM$RANDOM
  fi
  eda_args="$eda_args -s $SEED"
fi

echo "INFO> SEED=$SEED"

###################################################################################################
# Define and Create directories
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
OUTDIR=${PROJECT_DIR}/hw/output
mkdir -p ${OUTDIR}
INFO_DIR=${SCRIPT_DIR}/../gen/info
mkdir -p $INFO_DIR
RTL_DIR=${SCRIPT_DIR}/../gen/rtl
mkdir -p $RTL_DIR
INPUT_DIR=${SCRIPT_DIR}/../gen/input
mkdir -p  $INPUT_DIR
if [ $GEN_STIMULI -eq 1 ] ; then
  rm -rf ${INPUT_DIR}/*
fi
SOFT_OUTPUT_DIR=${PROJECT_DIR}/hw/output/micro_code
MEM_DIR=${PROJECT_DIR}/hw/memory_file/microblaze

hpu_mockup_bin="${PROJECT_DIR}/sw/bin/tfhe-rs/latest/hpu_mockup"
hpu_mockup_cfg_script="${PROJECT_DIR}/sw/bin/tfhe-rs/config/gen_hpu_mockup_config.py"
hpu_bin_path="${PROJECT_DIR}/sw/bin/tfhe-rs/latest"
hpu_bench_bin="${hpu_bin_path}/hpu_bench"
hpu_bench_cfg="${hpu_bin_path}/config"

###################################################################################################
# Software compilation
###################################################################################################
if [ $GEN_STIMULI -eq 1 ] ; then
  echo "###################################################"
  echo "INFO> Compiling softprocessor code"
  echo ""
  make -C ${PROJECT_DIR}/fw/ublaze/src/ target=$SOFT_TARGET srcf=$SOFT_NAME

  # Link
  echo ""
  echo "INFO> Link $SOFT_OUTPUT_DIR to ${INPUT_DIR}/micro_code"
  if [ -d ${INPUT_DIR}/micro_code ] ; then rm -f ${INPUT_DIR}/micro_code ; fi
  ln -s $SOFT_OUTPUT_DIR ${INPUT_DIR}/micro_code
fi

###################################################################################################
# Check microcode
###################################################################################################
echo "###################################################"
if [ $GEN_STIMULI -eq 1 ]; then
  echo "INFO> Use ucode generated by tfhe-rs in directory ${INPUT_DIR}/ucode, for IOP=$IOP"
  if [ -d $INPUT_DIR/ucode ] ; then rm -rf ${INPUT_DIR}/ucode ; fi
else
  echo "INFO> Using existing ucode directory $INPUT_DIR/ucode."
fi

###################################################################################################
# Build stimuli
###################################################################################################
# Create input stimuli if necessary
if [ $GEN_STIMULI -eq 1 ] ; then
  #== Create hpu_mockup config
  echo "###################################################"
  echo "INFO> Generate hpu_mockup config file"
  gen_mockup_cfg_cmd="python3 ${hpu_mockup_cfg_script} \
                -o ${INPUT_DIR}/hpu_mockup_cfg.toml \
                -f"
  echo "INFO> Running $gen_mockup_cfg_cmd"
  $gen_mockup_cfg_cmd || exit 1

  #== Create stimuli
  echo "###################################################"
  echo "INFO> Create stimuli"

  # NB: Force execution from PROJECT_DIR
  # Prevent issue with pre-generated config file
  cd ${PROJECT_DIR}

  # Start mockup in background
  hpu_mockup_cmd="$hpu_mockup_bin \
      --config ${hpu_bench_cfg}/dflt_cfg.toml\
      --params ${INPUT_DIR}/hpu_mockup_cfg.toml \
      --dump-out ${INPUT_DIR}/ucode"
  echo "INFO> Running $hpu_mockup_cmd in background"
  $hpu_mockup_cmd &
  hpu_mockup_pid=$!
  # Let some time to hpu_mockup to init and configure Ipc
  sleep 1

  hpu_bench_cmd="$hpu_bench_bin \
      --config ${hpu_bench_cfg}/dflt_cfg.toml\
      --integer-w ${INT_SIZE}\
      --seed ${SEED}\
      ${IOPS}"
  echo "INFO> Running $hpu_bench_cmd"
  $hpu_bench_cmd || $(cd -; exit 1)

  # Stop mockup background task
  kill_cmd="kill $hpu_mockup_pid"
  echo "INFO> Running $kill_cmd"
  $kill_cmd || $(cd -; exit 1)

  # Return in user directory
  cd -
fi

###################################################################################################
# Get microcode info
###################################################################################################
# Get ucode info
IOP_NB=0
for f in `ls ${INPUT_DIR}/ucode/iop/*.hex`; do
  name=`basename $f`
  if [[ $name =~ iop_([0-9]+).hex$ ]]; then
    n=${BASH_REMATCH[1]}
    if [ $n -ne $IOP_NB ]; then
      echo "ERROR> iop_${IOP_NB}.hex not found. iop_*.hex files should be named consecutively, since they are executed in order."
      exit 1
    fi
    IOP_NB=$(( $IOP_NB+1 ))
    echo "INFO> Use iop_$n.hex"
  else
    echo "WARNING> iop file's name: $name not recognized. Should be of this form \"iop_([0-9]+).hex\""
  fi
done
echo "INFO> IOP_NB=$IOP_NB"

# Find list of DOP
# TODO: to fix based on IOp order, at this point only works if IOp are in increasing opcode order
DOP_L=""
DOP_NB=0
for f in `ls ${INPUT_DIR}/ucode/dop/*.hex`; do
  name=`basename $f`
  if [[ $name =~ dop_([0-9a-f][0-9a-f]).hex$ ]]; then
    n=${BASH_REMATCH[1]}
    DOP_L="$n${DOP_L}"
    DOP_NB=$(( $DOP_NB+1 ))
    echo "INFO> Use dop_$n.hex"
  else
    echo "WARNING> dop file's name: $name not recognized. Should be of this form \"dop_([0-9a-f][0-9a-f]).hex\""
  fi
done
echo "INFO> DOP_NB=$DOP_NB"
SIZE_DOP_L=$(( $DOP_NB * 8 ))

escape_char=''
if [[ $PROJECT_SIMU_TOOL == "xsim" ]]; then
    escape_char='\'
fi

if [[ $IOP_NB -eq 0 ]]; then
    echo "ERROR> no iop to test, something failed in stimulus generation"
    exit 1
fi

eda_args="$eda_args \
            -P IOP_NB int $IOP_NB \
            -P IOP_INT_SIZE int $INT_SIZE \
            -P DOP_NB int $DOP_NB \
            -P DOP_LIST str \"$SIZE_DOP_L${escape_char}'h$DOP_L\" \
            "

###################################################################################################
# Run_edalize configure
###################################################################################################
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" > $TMP_FILE

$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -y run -y build \
  $eda_args \
  $args | tee >(grep "Work directory :" >> $TMP_FILE)
sync
work_dir=$(cat ${TMP_FILE} | sed 's/Work directory : *//')

# Delete TMP_FILE
rm -f $TMP_FILE

# create output dir
echo "INFO> Creating output dir : ${work_dir}/output"
mkdir -p  ${work_dir}/output

# Link
echo "INFO> Link $INPUT_DIR to ${work_dir}/input"
if [ -d ${work_dir}/input ] ; then rm ${work_dir}/input ; fi
ln -s $INPUT_DIR ${work_dir}/input

# log command line
echo $cli > ${work_dir}/cli.log

###################################################################################################
echo "INFO> Compiling softprocessor code"
echo ""
make -C ${PROJECT_DIR}/fw/ublaze/src/ target=$SOFT_TARGET srcf=$SOFT_NAME > ${PROJECT_DIR}/fw/ublaze/ublaze_fw_compil.log 2>&1 || exit 1

# Create INPUT_DIR
INPUT_DIR=${work_dir}/input
mkdir -p $INPUT_DIR

# Link
echo ""
echo "INFO> Link $SOFT_OUTPUT_DIR to ${INPUT_DIR}/micro_code"
if [ -d ${INPUT_DIR}/micro_code ] ; then rm -f ${INPUT_DIR}/micro_code ; fi
ln -s $SOFT_OUTPUT_DIR ${INPUT_DIR}/micro_code

###################################################################################################
# Run phase : simulation
###################################################################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args

###################################################################################################
# Post process
###################################################################################################
# None

###################################################################################################
# Clean gen directory
###################################################################################################
if [ $CLEAN -eq 1 ] ; then
  echo "INFO> Cleaning gen directory."
  rm -rf ${SCRIPT_DIR}/../gen/*
fi
