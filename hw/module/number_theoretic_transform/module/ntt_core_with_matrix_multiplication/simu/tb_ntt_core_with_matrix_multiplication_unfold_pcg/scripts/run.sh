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
run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py

ntt_arch="unfold_pcg"
module="tb_ntt_core_with_matrix_multiplication_${ntt_arch}"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module / _assembly."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-z                       : Do not generate stimuli."
echo "-C                       : Clean gen directory once the simulation is done."
echo "-g                       : GLWE_K (default 1)"
echo "-l                       : PBS_L (default 1)"
echo "-R                       : R: Radix (default 2)"
echo "-P                       : PSI: Number of butterflies (default 8)"
echo "-S                       : S: Number of stages (default 11)"
echo "-w                       : MOD_W: modulo width / operand width (default 64)"
echo "-m                       : MOD_M: modulo (default : 2**64-2**32+1)"
echo "-t                       : MOD_TYPE: modulo type (default : GOLDILOCKS)"
echo "-c                       : BATCH_PBS_NB (default : 10)"
echo "-a                       : BSK_DIST_COEF_NB (default : 32)"
echo "-K                       : LWE_K (default : 12)"
echo "-d                       : Maximum number of PBS per batch (default : BATCH_PBS_NB)"
echo "-D                       : Minimum number of PBS per batch (default : 1)"
echo "-n                       : Total number of PBS to be processed (default 15)"
echo "-e                       : BWD_PSI_DIV (default : 2)"
echo "-J                       : DELTA (default : 6)"
echo "-p                       : Test assembly version"
echo "-s                       : seed (if not given, random value.)"
echo "-- <run_edalize options> : run_edalize options."

}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

run_edalize_args=""
GEN_STIMULI=1
GLWE_K=1
PBS_L=1
R=2
PSI=8
S=11
MOD_W=64
MOD_M="2**64-2**32+1"
MOD_TYPE="GOLDILOCKS"
BATCH_PBS_NB=20
BATCH_MAX_PBS_NB=-1
BATCH_MIN_PBS_NB=-1
BSK_DIST_COEF_NB=32
LWE_K=12
BSK_SRV_NB=3
TOTAL_PBS_NB=15
BWD_PSI_DIV=1
DELTA=$(( ($S + 1) / 2 ))
ASSEMBLY=0
SEED=-1
CLEAN=0
# Initialize your own variables here:
while getopts "hzg:l:R:P:S:w:t:m:c:a:K:s:d:D:n:e:CJ:p" opt; do
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
    g)
      GLWE_K=$OPTARG
      ;;
    l)
      PBS_L=$OPTARG
      ;;
    R)
      R=$OPTARG
      ;;
    P)
      PSI=$OPTARG
      ;;
    S)
      S=$OPTARG
      ;;
    w)
      MOD_W=$OPTARG
      ;;
    m)
      MOD_M=$OPTARG
      ;;
    t)
      MOD_TYPE=$OPTARG
      ;;
    c)
      BATCH_PBS_NB=$OPTARG
      ;;
    a)
      BSK_DIST_COEF_NB=$OPTARG
      ;;
    K)
      LWE_K=$OPTARG
      ;;
    s)
      SEED=$OPTARG
      ;;
    d)
      BATCH_MIN_PBS_NB=$OPTARG
      ;;
    D)
      BATCH_MAX_PBS_NB=$OPTARG
      ;;
    n)
      TOTAL_PBS_NB=$OPTARG
      ;;
    e)
      BWD_PSI_DIV=$OPTARG
      ;;
    J)
      DELTA=$OPTARG
      ;;
    p)
      echo "Run assembly version."
      ASSEMBLY=1
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

N=$((${R}**${S}))

# Test version.
if [ $ASSEMBLY -ne 0 ]; then
  module=${module}_assembly
fi

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

# Check batch Number of PBS
if [ $BATCH_MAX_PBS_NB -eq -1 ]; then
  BATCH_MAX_PBS_NB=$BATCH_PBS_NB
fi
if [ $BATCH_MIN_PBS_NB -eq -1 ]; then
  BATCH_MIN_PBS_NB=1
fi
if [ $BATCH_PBS_NB -lt $BATCH_MAX_PBS_NB ]; then
  echo "ERROR> BATCH_MAX_PBS_NB ($BATCH_MAX_PBS_NB) must be less or equal to BATCH_PBS_NB ($BATCH_PBS_NB)"
  exit 1
fi
if [ $BATCH_MIN_PBS_NB -gt $BATCH_MAX_PBS_NB ]; then
  echo "ERROR> BATCH_MAX_PBS_NB ($BATCH_MAX_PBS_NB) must be greater or equal to BATCH_MIN_PBS_NB ($BATCH_MIN_PBS_NB)"
  exit 1
fi

# Use another format for MOD_M/ Replace ** with ^
MOD_M_BIS=$(echo $MOD_M | sed 's/\*\*/^/g')

echo "INFO> SEED=$SEED"

# NTT cut
NTT_RDX_CUT_S=()
TOTAL=$S
while [ $TOTAL -ge $DELTA ] ; do
    NTT_RDX_CUT_S+=($DELTA)
    TOTAL=$(($TOTAL - $DELTA))
done
if [ $TOTAL -gt 0 ] ; then
    NTT_RDX_CUT_S+=($TOTAL)
fi

ntt_cut_arg=""
ntt_cut_flag=""
for i in "${NTT_RDX_CUT_S[@]}" ; do
    ntt_cut_arg="$ntt_cut_arg -J $i"
    ntt_cut_flag="${ntt_cut_flag}c${i}"
done
#replace first occurance of c with n (cyclic -> negacyclic"
ntt_cut_flag=`echo $ntt_cut_flag | sed 's/c/n/'`

###################################################################################################
# Generate package
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

INFO_DIR=${SCRIPT_DIR}/../gen/info
mkdir -p $INFO_DIR
RTL_DIR=${SCRIPT_DIR}/../gen/rtl
mkdir -p $RTL_DIR

# Create packages
if [ $GEN_STIMULI -eq 1 ] ; then
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_tfhe_definition_pkg.py -f -N $N -g $GLWE_K -l $PBS_L -K $LWE_K -o ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> N=${N}, GLWE_K=${GLWE_K}, PBS_L=${PBS_L}"
  echo "INFO> Creating param_tfhe_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_ntt_definition_pkg.py -f -w $MOD_W -m $MOD_M -t $MOD_TYPE -o ${RTL_DIR}/param_ntt_definition_pkg.sv"
  echo "INFO> MOD_W=${MOD_W}, MOD_NTT=${MOD_M}, MOD_NTT_TYPE=${MOD_TYPE}"
  echo "INFO> Creating param_ntt_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_common/scripts/gen_ntt_core_common_psi_definition_pkg.py\
          -f -P $PSI -o ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> PSI=${PSI}"
  echo "INFO> ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_common/scripts/gen_ntt_core_common_div_definition_pkg.py\
          -f -e $BWD_PSI_DIV -o ${RTL_DIR}/ntt_core_common_div_definition_pkg.sv"
  echo "INFO> BWD_PSI_DIV=${BWD_PSI_DIV}"
  echo "INFO> ntt_core_common_div_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_common/scripts/gen_ntt_core_common_cut_definition_pkg.py\
          -f $ntt_cut_arg -o ${RTL_DIR}/ntt_core_common_cut_definition_pkg.sv"
  echo "INFO> NTT_RDX_CUT_S=${NTT_RDX_CUT_S[@]}"
  echo "INFO> ntt_core_common_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_common/scripts/gen_ntt_core_common_arch_definition_pkg.py\
          -f -a NTT_CORE_ARCH_wmm_${ntt_arch} -o ${RTL_DIR}/ntt_core_common_arch_definition_pkg.sv"
  echo "INFO> NTT_CORE_ARCH=NTT_CORE_ARCH_wmm_${ntt_arch}"
  echo "INFO> ntt_core_common_arch_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_with_matrix_multiplication/simu/tb_bsk_ntw_model/scripts/gen_bsk_ntw_common_definition_pkg.py\
          -f -a $BSK_DIST_COEF_NB  -o ${RTL_DIR}/bsk_ntw_common_definition_pkg.sv"
  echo "INFO> BSK_DIST_COEF_NB=$BSK_DIST_COEF_NB"
  echo "INFO> bsk_ntw_common_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/pe_pbs/module/pep_common/scripts/gen_pep_batch_definition_pkg.py\
          -f -c $BATCH_PBS_NB -o ${RTL_DIR}/pep_batch_definition_pkg.sv"
  echo "INFO> BATCH_PBS_NB=$BATCH_PBS_NB"
  echo "INFO> pep_batch_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  # Create the associated file_list.json
  echo ""
  file_list_cmd="${PROJECT_DIR}/hw/scripts/create_module/create_file_list.py\
                -o ${INFO_DIR}/file_list.json \
                -p ${RTL_DIR} \
                -R param_tfhe_definition_pkg.sv simu 0 1 \
                -R param_ntt_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_psi_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_div_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_cut_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_arch_definition_pkg.sv simu 0 1 \
                -R bsk_ntw_common_definition_pkg.sv simu 0 1 \
                -R pep_batch_definition_pkg.sv simu 0 1 \
                -F pep_batch_definition_pkg.sv PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB} \
                -F ntt_core_common_psi_definition_pkg.sv NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                -F ntt_core_common_div_definition_pkg.sv NTT_CORE_DIV NTT_CORE_DIV_${BWD_PSI_DIV} \
                -F ntt_core_common_cut_definition_pkg.sv NTT_CORE_RDX_CUT NTT_CORE_RDX_CUT_${ntt_cut_flag} \
                -F ntt_core_common_arch_definition_pkg.sv NTT_CORE_ARCH NTT_CORE_ARCH_wmm_${ntt_arch} \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu \
                -F param_ntt_definition_pkg.sv NTT_MOD NTT_MOD_simu \
                -F bsk_ntw_common_definition_pkg.sv BSK_NTW_DCOEF DCOEF${BSK_DIST_COEF_NB}"
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/param_ntt_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_div_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_cut_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_arch_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/bsk_ntw_common_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/pep_batch_definition_pkg.sv"
fi

###################################################################################################
# Process
###################################################################################################
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" > $TMP_FILE

#################################################
# Parameter
#################################################
bsk_arg_gen=""
bs_loop_per_server=$(( $LWE_K / $BSK_SRV_NB ))
last_bs_loop_per_server=$LWE_K
for i in $(seq 0 $(( $BSK_SRV_NB - 2 ))) ; do
  bsk_arg_gen="$bsk_arg_gen -bn $bs_loop_per_server"
  last_bs_loop_per_server=$(($last_bs_loop_per_server - $bs_loop_per_server))
done
bsk_arg_gen="$bsk_arg_gen -bn $last_bs_loop_per_server"

#################################################
# Build stimuli
#################################################
INPUT_DIR=${SCRIPT_DIR}/../gen/input

# Create input stimuli if necessary
if [ $GEN_STIMULI -eq 1 ] ; then

  mkdir -p  $INPUT_DIR
  rm -rf ${INPUT_DIR}/*
  ref_cmd="${PROJECT_DIR}/sw/bin/tv_hw/latest/tv_hw \
    --order pdrev-in-rev-out \
    --radix $R \
    --stg-nb $S \
    --lwe-dim $LWE_K \
    --glwe-dim $GLWE_K \
    --mod-p $(echo $MOD_M_BIS | bc -l) \
    --pbs-lc $PBS_L \
    --tv-bname ${INPUT_DIR}/test_vectors \
    --pbs-nb $TOTAL_PBS_NB \
    --seed $SEED"
  echo "INFO> Running : $ref_cmd"
  $ref_cmd || exit 1

  gen_cmd="python3 ${PROJECT_DIR}/hw/module/hpu/simu/scripts/gen_stimuli_pcg.py \
    -o $INPUT_DIR \
    -i $INPUT_DIR \
    -z mmacc_data \
    -A NTT_CORE_ARCH_wmm_${ntt_arch} \
    -R $R \
    -P $PSI \
    -S $S \
    -w $MOD_W \
    -bs $BSK_SRV_NB \
    -s $SEED \
    $bsk_arg_gen \
    -l $PBS_L \
    -K $LWE_K \
    -g $GLWE_K \
    -a $BSK_DIST_COEF_NB \
    -dM $BATCH_MAX_PBS_NB \
    -dm $BATCH_MIN_PBS_NB \
    -e $BWD_PSI_DIV \
    -delta $DELTA"
  echo "INFO> Running : $gen_cmd"
  $gen_cmd || exit 1
fi

if [[ `grep "SIMU_BATCH_NB=" ${INPUT_DIR}/info.txt` =~ SIMU_BATCH_NB=([0-9]+)$ ]]; then
  SIMU_BATCH_NB=${BASH_REMATCH[1]}
else
  echo "ERROR> info.txt file is not recognized."
  exit 1
fi

#################################################
# Config phase : create directory + scripts
#################################################
eda_args="$eda_args \
                    -F NTT_CORE_R NTT_CORE_R_${R} \
                    -F NTT_CORE_ARCH NTT_CORE_ARCH_wmm_${ntt_arch} \
                    -F NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                    -F NTT_CORE_DIV NTT_CORE_DIV_${BWD_PSI_DIV} \
                    -F NTT_CORE_RDX_CUT NTT_CORE_RDX_CUT_${ntt_cut_flag} \
                    -F PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB} \
                    -F BSK_NTW_DCOEF DCOEF${BSK_DIST_COEF_NB} \
                    -F APPLICATION APPLI_simu \
                    -F NTT_MOD NTT_MOD_simu \
                    -P BR_LOOP_NB int $LWE_K \
                    -P SIMU_BATCH_NB int $SIMU_BATCH_NB \
                    -P BWD_PSI_DIV int $BWD_PSI_DIV \
                    -P DELTA int $DELTA"

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

# create output dir
echo "INFO> Creating output dir : ${work_dir}/output"
mkdir -p  ${work_dir}/output

# Link
echo "INFO> Link $INPUT_DIR to ${work_dir}/input"
if [ -d ${work_dir}/input ] ; then rm ${work_dir}/input ; fi
ln -s $INPUT_DIR ${work_dir}/input

# log command line
echo $cli > ${work_dir}/cli.log

#################################################
# Run phase : simulation
#################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args

#################################################
# Post process
#################################################
# None

#################################################
# Clean gen directory
#################################################
if [ $CLEAN -eq 1 ] ; then
  echo "INFO> Cleaning gen directory."
  rm -rf ${SCRIPT_DIR}/../gen/*
fi
