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

module="tb_ntt_core_gf64_bu_radix"

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
# Initialize your own variables here:
while getopts "hg:R:P:" opt; do
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

# UNUSED
N=2048 # to be able to simulate up to 32NTT ngc, and 64-NTT cyc
GLWE_K=1
MOD_Q="2**64"
MOD_Q_W=64

S=`echo $N | awk '{print log($1)/log(2)}'`

NGC_S=$(($S/2))
CYC_S=$(($S - $NGC_S))

# NTT cut
NTT_RDX_CUT_S=($NGC_S $CYC_S)

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
  file_list_cmd="${PROJECT_DIR}/hw/script/create_module/create_file_list.py\
                -o ${INFO_DIR}/file_list.json \
                -p ${RTL_DIR} \
                -R param_tfhe_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_cut_definition_pkg.sv simu 0 1 \
                -R ntt_core_common_psi_definition_pkg.sv simu 0 1 \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu \
                -F ntt_core_common_psi_definition_pkg.sv NTT_CORE_PSI_DIV_DELTA PSI_${PSI}_DIV1_DELTA1 \
                -F ntt_core_common_cut_definition_pkg.sv NTT_CORE_RDX_CUT NTT_CORE_RDX_CUT_${ntt_cut_flag}"
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_cut_definition_pkg.sv"
fi

###################################################################################################
# Process
###################################################################################################
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" > $TMP_FILE

#################################################
# Config phase : create directory + scripts
#################################################
eda_args="$eda_args -F APPLICATION APPLI_simu \
                    -F NTT_CORE_R NTT_CORE_R_${R} \
                    -F NTT_MOD NTT_MOD_goldilocks \
                    -F NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                    -F NTT_CORE_RDX_CUT NTT_CORE_RDX_CUT_${ntt_cut_flag} "

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

