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

module="tb_pep_mmacc_sample_extract"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-g                       : GLWE_K (default 2)"
echo "-R                       : R: Radix (default 2)"
echo "-P                       : PSI: Number of butterflies (default 8)"
echo "-S                       : S: Number of stages (default 6)"
echo "-q                       : MOD_Q: modulo (default : 2**64)"
echo "-W                       : MOD_Q_W: modulo width (default 64)"
echo "-c                       : BATCH_PBS_NB (default : 12)"
echo "-H                       : TOTAL_PBS_NB (default : 18)"
echo "-G                       : GRAM_NB      (default : 4)"
echo "-w                       : MOD_NTT_W: NTT modulo width / NTT operand width (default 64)"
echo "-m                       : MOD_NTT: NTT modulo (default 'GOLDILOCK': 2**64-2**32+1)"
echo "-t                       : MOD_NTT_TYPE: NTT modulo type (default : GOLDILOCKS)"
echo "-- <run_edalize options> : run_edalize options."

}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

run_edalize_args=""
GEN_STIMULI=1
GLWE_K=2
R=2
PSI=8
S=6
MOD_Q="2**64"
MOD_Q_W=64
MOD_NTT_W=-1 #MOD_NTT_W=64
MOD_NTT=-1 #MOD_NTT="2**64-2**32+1"
MOD_NTT_TYPE=-1 #MOD_NTT_TYPE="GOLDILOCKS"
GRAM_NB=4
BATCH_PBS_NB=12
TOTAL_PBS_NB=16
NTT_CORE_ARCH="NTT_CORE_ARCH_wmm_unfold_pcg"
# Initialize your own variables here:
while getopts "hg:R:P:S:q:W:c:A:H:G:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    A)
      NTT_CORE_ARCH=$OPTARG
      ;;
    g)
      GLWE_K=$OPTARG
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
    q)
      MOD_Q=$OPTARG
      ;;
    W)
      MOD_Q_W=$OPTARG
      ;;
    c)
      BATCH_PBS_NB=$OPTARG
      ;;
    G)
      GRAM_NB=$OPTARG
      ;;
    H)
      TOTAL_PBS_NB=$OPTARG
      ;;
    w)
      MOD_NTT_W=$OPTARG
      ;;
    m)
      MOD_NTT=$OPTARG
      ;;
    t)
      MOD_NTT_TYPE=$OPTARG
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


###################################################################################################
# Build MOD_NTT
###################################################################################################
# In case not given by user
if [ $MOD_NTT -eq -1 ]; then
  if [ $MOD_Q_W -eq 64 ] ; then
    # use goldilocks
    MOD_NTT_W=64
    MOD_NTT="2**64-2**32+1"
    MOD_NTT_TYPE="GOLDILOCKS"
  else
    # Use a Solinas 2
    MOD_NTT_W=$MOD_Q_W
    MOD_NTT="2**${MOD_NTT_W}-2**$((${MOD_NTT_W}/2))+1"
    MOD_NTT_TYPE="SOLINAS2"
  fi
fi

echo "INFO> Using MOD_NTT=$MOD_NTT MOD_NTT_W=$MOD_NTT_W MOD_NTT_TYPE=$MOD_NTT_TYPE"

###################################################################################################
# Generate package
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

INFO_DIR=${SCRIPT_DIR}/../gen/info
mkdir -p $INFO_DIR
RTL_DIR=${SCRIPT_DIR}/../gen/rtl
mkdir -p $RTL_DIR

# Create package
if [ $GEN_STIMULI -eq 1 ] ; then
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_tfhe_definition_pkg.py -f \
                  -N $N -g $GLWE_K -q $MOD_Q -W $MOD_Q_W \
                  -o ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> N=${N} GLWE_K=${GLWE_K} MOD_Q=${MOD_Q} MOD_Q_W=${MOD_Q_W}"
  echo "INFO> Creating param_tfhe_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_ntt_definition_pkg.py -f \
            -w $MOD_NTT_W \
            -m $MOD_NTT \
            -t $MOD_NTT_TYPE \
            -o ${RTL_DIR}/param_ntt_definition_pkg.sv"
  echo "INFO> MOD_NTT_W=${MOD_NTT_W}, MOD_NTT=${MOD_NTT}, MOD_NTT_TYPE=${MOD_NTT_TYPE}"
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
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_common/scripts/gen_ntt_core_common_arch_definition_pkg.py\
          -f -a $NTT_CORE_ARCH -o ${RTL_DIR}/ntt_core_common_arch_definition_pkg.sv"
  echo "INFO> NTT_CORE_ARCH=$NTT_CORE_ARCH"
  echo "INFO> ntt_core_common_arch_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/pe_pbs/module/pep_common/scripts/gen_pep_batch_definition_pkg.py\
          -f -c $BATCH_PBS_NB -H $TOTAL_PBS_NB -g $GRAM_NB -o ${RTL_DIR}/pep_batch_definition_pkg.sv"
  echo "INFO> BATCH_PBS_NB=$BATCH_PBS_NB TOTAL_PBS_NB=$TOTAL_PBS_NB"
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
                -R ntt_core_common_arch_definition_pkg.sv simu 0 1 \
                -R pep_batch_definition_pkg.sv simu 0 1 \
                -F pep_batch_definition_pkg.sv PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB}_tpbs${TOTAL_PBS_NB} \
                -F ntt_core_common_arch_definition_pkg.sv NTT_CORE_ARCH $NTT_CORE_ARCH \
                -F ntt_core_common_psi_definition_pkg.sv NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu \
                -F param_ntt_definition_pkg.sv NTT_MOD NTT_MOD_simu "
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/param_ntt_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_arch_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/pep_batch_definition_pkg.sv"
fi

###################################################################################################
# Process
###################################################################################################
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" > $TMP_FILE

#################################################
# Config phase : create directory + scripts
#################################################
eda_args="$eda_args -F NTT_CORE_ARCH $NTT_CORE_ARCH \
                    -F NTT_CORE_R NTT_CORE_R_${R} \
                    -F NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                    -F PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB}_tpbs${TOTAL_PBS_NB} \
                    -F APPLICATION APPLI_simu \
                    -F NTT_MOD NTT_MOD_simu \
                    -P OP_W int $MOD_Q_W"

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

#################################################
# Run phase : simulation
#################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args

