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

module="tb_hpu"

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
RUN_LOG="${PROJECT_DIR}/hw/output/${module}_run_sh.log"
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._tmp"
echo -n "" > $SEED_FILE
echo -n "" > $TMP_FILE

NTT_MOD_L=("NTT_MOD_goldilocks" "NTT_MOD_solinas2_44_14" )
IOP_L=("IOP[0]" "IOP[16]" "ADD" "ADDS" "SUB" "SUBS" "SSUB" "MUL" "MULS" "BW_AND" "BW_OR" "BW_XOR" "CMP_GT" "CMP_GTE" "CMP_LT" "CMP_LTE" "CMP_EQ" "CMP_NEQ")
INT_SIZE_L=("2" "4" "8")
AXI_DATA_W_L=("512" "256" "128")
FPGA_L=("v80")
MSPLIT_TYPE_L=("PEP_MSPLIT_main2_subs2" "PEP_MSPLIT_main1_subs3" "PEP_MSPLIT_main3_subs1")
INTER_PART_PIPE_L=("0" "1" "2")
DOP_IMPLEM_L=("Ilp" "Llt")

for ((j = 0; j < 1; j++)); do
  size=${#NTT_MOD_L[@]}
  index=$(($RANDOM % $size))
  NTT_MOD_FLAG=${NTT_MOD_L[$index]}
  if [[ $NTT_MOD_FLAG =~ NTT_MOD_goldilocks ]]; then
    run_args="-q 2**64 -W 64"
    MOD_NTT_W=64
  elif [[ $NTT_MOD_FLAG =~ NTT_MOD_solinas2_44_14 ]]; then
    run_args="-q 2**44 -W 44"
    MOD_NTT_W=44
  elif [[ $NTT_MOD_FLAG =~ NTT_MOD_solinas2_32_20 ]]; then
    run_args="-q 2**32 -W 32"
    MOD_NTT_W=32
  else
    echo "ERROR> Unknown NTT prime!"
    exit 1
  fi

  # Choose FPGA
  size=${#FPGA_L[@]}
  index=$(($RANDOM % $size))
  FPGA=${FPGA_L[$index]}

  # Choose IOP program
  size=${#IOP_L[@]}
  index=$(($RANDOM % $size))
  IOP=${IOP_L[$index]}

  # Choose AXI_DATA_W
  size=${#AXI_DATA_W_L[@]}
  index=$(($RANDOM % $size))
  AXI_DATA_W=${AXI_DATA_W_L[$index]}

  # Choose inter part pipe
  size=${#INTER_PART_PIPE_L[@]}
  index=$(($RANDOM % $size))
  INTER_PART_PIPE=${INTER_PART_PIPE_L[$index]}

  # Choose DOP implementation
  size=${#DOP_IMPLEM_L[@]}
  index=$(($RANDOM % $size))
  DOP_IMPLEM=${DOP_IMPLEM_L[$index]}

  if [[ $IOP =~ ^IOP\[([0-9]+)\]$ ]]; then
    # the custom code deals with a 2b word
    run_args="$run_args -a $IOP -n 2 -y ${PROJECT_DIR}/hw/module/hpu/simu/ucode"
  else
    # Choose INT size
    size=${#INT_SIZE_L[@]}
    index=$(($RANDOM % $size))
    INT_SIZE=${INT_SIZE_L[$index]}
    run_args="$run_args -a $IOP -n $INT_SIZE"
  fi



  # generate random parameters
  PARAM_FILE_BASE="${PROJECT_DIR}/hw/output/${module}_param_base.sh"
  PARAM_FILE_ORDER2="${PROJECT_DIR}/hw/output/${module}_param_order2.sh"
  PARAM_FILE_RDXCUT="${PROJECT_DIR}/hw/output/${module}_param_rdxcut.sh"

  cmd_gen="python3 ${SCRIPT_DIR}/gen_tb_hpu_param_base.py -w $MOD_NTT_W -out_bash $PARAM_FILE_BASE"
  echo "> INFO: generate tb_hpu parameters : base"
  echo "> INFO: run $cmd_gen"
  $cmd_gen \
        -D $AXI_DATA_W \
        || exit 1

  cat $PARAM_FILE_BASE
  source $PARAM_FILE_BASE

  cmd_gen="python3 ${SCRIPT_DIR}/gen_tb_hpu_param_order2.py -out_bash $PARAM_FILE_ORDER2"
  echo "> INFO: generate tb_hpu parameters : order2"
  echo "> INFO: run $cmd_gen"
  $cmd_gen -A $NTT_ARCH \
        -R $R \
        -P $PSI \
        -S $S \
        -g $GLWE_K \
        -V $MOD_KSK_W \
        -w $MOD_NTT_W \
        -c $BATCH_PBS_NB \
        -H $TOTAL_PBS_NB \
        -e $BWD_PSI_DIV \
        -l $PBS_L \
        -b $PBS_B_W \
        -L $KS_L \
        -B $KS_B_W \
        -X $LBX \
        -Y $LBY \
        -Z $LBZ \
        -i $REGF_REG_NB \
        -j $REGF_COEF_NB \
        -k $REGF_SEQ \
        -D $AXI_DATA_W \
        -FPGA $FPGA \
        || exit 1
  cat $PARAM_FILE_ORDER2
  source $PARAM_FILE_ORDER2


  cmd_gen="python3 ${SCRIPT_DIR}/gen_tb_hpu_param_rdxcut.py -out_bash $PARAM_FILE_RDXCUT"
  echo "> INFO: generate tb_hpu parameters : rdxcut"
  echo "> INFO: run $cmd_gen"
  $cmd_gen -A $NTT_ARCH \
        -R $R \
        -P $PSI \
        -S $S \
        || exit 1
  cat $PARAM_FILE_RDXCUT
  source $PARAM_FILE_RDXCUT

  NTT_RDX_CUT_S=($RDX_CUT_0)
  ntt_cut_arg="-J $RDX_CUT_0"
  if [ $RDX_CUT_1 -gt 0 ] ; then
    NTT_RDX_CUT_S+=($RDX_CUT_1)
    ntt_cut_arg="$ntt_cut_arg -J $RDX_CUT_1"
  fi
  if [ $RDX_CUT_2 -gt 0 ] ; then
    NTT_RDX_CUT_S+=($RDX_CUT_2)
    ntt_cut_arg="$ntt_cut_arg -J $RDX_CUT_2"
  fi
  if [ $RDX_CUT_3 -gt 0 ] ; then
    NTT_RDX_CUT_S+=($RDX_CUT_3)
    ntt_cut_arg="$ntt_cut_arg -J $RDX_CUT_3"
  fi

  # Choose an msplit_type
  size=${#MSPLIT_TYPE_L[@]}
  index=$(($RANDOM % $size))
  MSPLIT_TYPE=${MSPLIT_TYPE_L[$index]}

  if [ $USE_BPIP -eq 1 ] ; then
    USE_BPIP_OPPORTUNISM=$(($RANDOM % 2))
  else
    USE_BPIP_OPPORTUNISM=0
  fi

  # TODO : remove this, once the sw is ready
  USE_MEAN_COMP=1

  cmd="${SCRIPT_DIR}/run.sh \
                  -C \
                  -R $R \
                  -S $S \
                  -P $PSI \
                  -l $PBS_L \
                  -b $PBS_B_W \
                  -g $GLWE_K \
                  -e $BWD_PSI_DIV \
                  -A $NTT_ARCH \
                  -c $BATCH_PBS_NB\
                  -H $TOTAL_PBS_NB \
                  -K $LWE_K \
                  $ntt_cut_arg \
                  -X $LBX \
                  -Y $LBY \
                  -Z $LBZ \
                  -L $KS_L \
                  -B $KS_B_W \
                  -V $MOD_KSK_W \
                  -r "2**$MOD_KSK_W" \
                  -u $BSK_CUT_NB \
                  -f $BSK_PC \
                  -U $KSK_CUT_NB \
                  -F $KSK_PC \
                  -E $PEM_PC \
                  -i $REGF_REG_NB \
                  -j $REGF_COEF_NB \
                  -k $REGF_SEQ \
                  -p $DOP_IMPLEM \
                  -d $USE_MEAN_COMP \
                  $run_args \
                  -- -P RAM_LATENCY int $RAM_LATENCY \
                  -P USE_BPIP int $USE_BPIP \
                  -P INTER_PART_PIPE int $INTER_PART_PIPE \
                  -P USE_BPIP_OPPORTUNISM int $USE_BPIP_OPPORTUNISM \
                  -F NTT_MOD $NTT_MOD_FLAG \
                  -F PEP_MSPLIT $MSPLIT_TYPE \
                  -F AXI_DATA_W AXI_DATA_W_${AXI_DATA_W} \
                  -F FPGA FPGA_${FPGA} \
                  $args"
  echo "==========================================================="
  echo "INFO> Running : $cmd"
  echo "==========================================================="
  $cmd | tee $RUN_LOG >(grep "Seed" | head -1 >> $SEED_FILE) |  grep -c "> SUCCEED !" > $TMP_FILE
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

