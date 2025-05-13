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

module="tb_ntt_core_gf64_without_pp"

###################################################################################################
# Default values
###################################################################################################
GEN_STIMULI=1
GLWE_K=2
R=2
PSI=16
S=10
NTT_RDX_CUT_S="$(($S/2)) $(($S - $S/2))"
NTT_SPLIT_S="$S $S"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-z                       : Do not generate stimuli."
echo "-g                       : GLWE_K (default $GLWE_K)"
echo "-R                       : R: Radix (default $R)"
echo "-P                       : PSI: Number of butterflies (default $PSI)"
echo "-S                       : S: Number of stages (default $S)"
echo "-J                       : NTT_RDX_CUT_S : NTT radix cut (default \"$NTT_RDX_CUT_S\"). Use several times to get all the cuts"
echo "-c                       : NTT_SPLIT_S : NTT physical split (default \"$NTT_SPLIT_S\"). Use several times to get all the cuts"
echo "-- <run_edalize options> : run_edalize options."
}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

run_edalize_args=""
NTT_RDX_CUT_S_TMP=()
NTT_SPLIT_S_TMP=()
# Initialize your own variables here:
while getopts "hzg:l:R:P:S:J:c:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
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
    J)
      NTT_RDX_CUT_S_TMP+=($OPTARG)
      ;;
    c)
      NTT_SPLIT_S_TMP+=($OPTARG)
      ;;
    z)
      echo "Do not generate stimuli."
      GEN_STIMULI=0
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

N=$((2**$S))

# Constants
BWD_PSI_DIV=1
DELTA=1
PBS_L=1

# Process NTT_RDX_CUT_S
# The user should give a list where elements are separated with a space
if [ ${#NTT_RDX_CUT_S_TMP[@]} -gt 0 ]; then
  NTT_RDX_CUT_S_L=(${NTT_RDX_CUT_S_TMP[@]})
else
  NTT_RDX_CUT_S_L=($NTT_RDX_CUT_S)
fi
NTT_RDX_CUT_NB=${#NTT_RDX_CUT_S_L[@]}

ntt_cut_arg=""
ntt_cut_flag=""
for i in "${NTT_RDX_CUT_S_L[@]}" ; do
    ntt_cut_arg="$ntt_cut_arg -J $i"
    ntt_cut_flag="${ntt_cut_flag}c${i}"
done
#replace first occurrence of c with n (cyclic -> negacyclic"
ntt_cut_flag=`echo $ntt_cut_flag | sed 's/c/n/'`

# Process NTT_SPLIT_S
if [ ${#NTT_SPLIT_S_TMP[@]} -gt 0 ]; then
  NTT_SPLIT_S_L=(${NTT_SPLIT_S_TMP[@]})
else
  NTT_SPLIT_S_L=($NTT_SPLIT_S)
fi
NTT_SPLIT_NB=${#NTT_SPLIT_S_L[@]}

split_arg=""
for n in "${NTT_SPLIT_S_L[@]}"; do
  v=`printf "%08x" $n`
  split_arg="$v$split_arg"
done
split_nb=${#NTT_SPLIT_S_L[@]}
split_size=$(( $split_nb * 32 ))

###################################################################################################
# Generate package
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

INFO_DIR=${SCRIPT_DIR}/../gen/info
mkdir -p $INFO_DIR
RTL_DIR=${SCRIPT_DIR}/../gen/rtl
mkdir -p $RTL_DIR
INPUT_DIR=${SCRIPT_DIR}/../gen/input
mkdir -p $INPUT_DIR

# Create package
if [ $GEN_STIMULI -eq 1 ] ; then
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_tfhe_definition_pkg.py -f -N $N -g $GLWE_K -l $PBS_L -o ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> N=${N}, GLWE_K=${GLWE_K}, PBS_L=${PBS_L}"
  echo "INFO> Creating param_tfhe_definition_pkg.sv"
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
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_common/scripts/gen_ntt_core_common_cut_definition_pkg.py\
          -f $ntt_cut_arg -o ${RTL_DIR}/ntt_core_common_cut_definition_pkg.sv"
  echo "INFO> NTT_RDX_CUT_S=${NTT_RDX_CUT_S[@]}"
  echo "INFO> ntt_core_common_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  # Create the associated file_list.json
  echo ""
  file_list_cmd="${PROJECT_DIR}/hw/scripts/create_module/create_file_list.py\
                -o ${INFO_DIR}/file_list.json \
                -p ${RTL_DIR} \
                -R param_tfhe_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_psi_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_cut_definition_pkg.sv simu 0 1 \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu \
                -F ntt_core_common_psi_definition_pkg.sv NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                -F ntt_core_common_cut_definition_pkg.sv NTT_CORE_RDX_CUT NTT_CORE_RDX_CUT_${ntt_cut_flag} "
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_cut_definition_pkg.sv"
fi

eda_args=""

escape_char=''
if [[ $PROJECT_SIMU_TOOL == "xsim" ]]; then
    escape_char='\'
fi

eda_args="$eda_args \
            -F NTT_CORE_R NTT_CORE_R_${R} \
            -F APPLICATION APPLI_simu \
            -F NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
            -F NTT_CORE_RDX_CUT NTT_CORE_RDX_CUT_${ntt_cut_flag} \
            -F NTT_MOD NTT_MOD_goldilocks \
            -P SPLIT_NB int $NTT_SPLIT_NB \
            -P S_NB_L str \"${split_size}${escape_char}'h$split_arg\" \
            "

###################################################################################################
# Twiddles
###################################################################################################
ntt_gf64_script="${PROJECT_DIR}/sw/ntt/ntt_gf64.sage"

echo "###################################################"
echo "INFO> Generate twiddles for GF64"
phi_cmd="sage ${ntt_gf64_script} \
        -gen_rom \
        -coef $(($R * $PSI)) \
        -N $N \
        $ntt_cut_arg \
        -dir ${INPUT_DIR}"
echo "INFO> Running : $phi_cmd"
$phi_cmd || exit 1
echo "###################################################"

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

# log command line
echo $cli > ${work_dir}/cli.log

# Link
echo "INFO> Link $INPUT_DIR to ${work_dir}/input"
if [ -d ${work_dir}/input ] ; then rm ${work_dir}/input ; fi
ln -s $INPUT_DIR ${work_dir}/input

###################################################################################################
# Run phase : simulation
###################################################################################################
$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -k keep $eda_args $args
