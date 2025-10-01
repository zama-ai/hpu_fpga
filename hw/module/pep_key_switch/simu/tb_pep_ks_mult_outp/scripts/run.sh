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

module="tb_pep_ks_mult_outp"

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
echo "-S                       : S: Number of stages (default 8)"
echo "-q                       : MOD_Q: modulo (default : 2**32)"
echo "-W                       : MOD_Q_W: modulo width (default 32)"
echo "-c                       : BATCH_PBS_NB (default : 4)"
echo "-K                       : LWE_K (default : 12)"
echo "-L                       : KS_L (default 2)"
echo "-B                       : KS_B_W (default 16)"
echo "-r                       : MOD_KSK: modulo (default 2**16)"
echo "-V                       : MOD_KSK_W: modulo width (default 16)"
echo "-X                       : LBX: Number of coefficients columns processed in parallel (default 1)"
echo "-Y                       : LBY: Number of coefficients lines processed in parallel (default 48)"
echo "-Z                       : LBZ: Number of coefficients lines processed in parallel (default 1)"
echo "-d                       : USE_MEAN_COMP (default 1)"
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
PBS_L=2
R=2
S=8
MOD_Q="2**32"
MOD_Q_W=32
BATCH_PBS_NB=4
LWE_K=12
LBX=1
LBY=48
LBZ=1
KS_L=1
KS_B_W=31
MOD_KSK_W=16
MOD_KSK="2**16"
USE_MEAN_COMP=1
# Initialize your own variables here:
while getopts "hg:R:S:q:W:c:K:X:Y:Z:B:L:V:r:d:" opt; do
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
    K)
      LWE_K=$OPTARG
      ;;
    X)
      LBX=$OPTARG
      ;;
    Y)
      LBY=$OPTARG
      ;;
    Z)
      LBZ=$OPTARG
      ;;
    B)
      KS_B_W=$OPTARG
      ;;
    L)
      KS_L=$OPTARG
      ;;
    r)
      MOD_KSK=$OPTARG
      ;;
    V)
      MOD_KSK_W=$OPTARG
      ;;
    d)
      USE_MEAN_COMP=$OPTARG
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
                  -N $N -g $GLWE_K -K $LWE_K -q $MOD_Q -W $MOD_Q_W -L $KS_L -B $KS_B_W -r $MOD_KSK -V $MOD_KSK_W  \
                  -d $USE_MEAN_COMP \
                  -o ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> N=${N}, GLWE_K=${GLWE_K} MOD_Q=${MOD_Q} MOD_Q_W=${MOD_Q_W} LWE_K=${LWE_K} KS_L=${KS_L} KS_B_W=${KS_B_W} MOD_KSK=${MOD_KSK} MOD_KSK_W=${MOD_KSK_W} USE_MEAN_COMP=${USE_MEAN_COMP}"
  echo "INFO> Creating param_tfhe_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/pe_pbs/module/pep_common/scripts/gen_pep_batch_definition_pkg.py\
          -f -c $BATCH_PBS_NB -o ${RTL_DIR}/pep_batch_definition_pkg.sv"
  echo "INFO> BATCH_PBS_NB=$BATCH_PBS_NB"
  echo "INFO> pep_batch_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/pep_key_switch/module/pep_ks_common/scripts/gen_pep_ks_common_definition_pkg.py\
          -f -lbx $LBX -lby $LBY -lbz $LBZ -o ${RTL_DIR}/pep_ks_common_definition_pkg.sv"
  echo "INFO> LBX=$LBX LBY=$LBY LBZ=$LBZ"
  echo "INFO> pep_ks_common_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  # Create the associated file_list.json
  echo ""
  file_list_cmd="${PROJECT_DIR}/hw/scripts/create_module/create_file_list.py\
                -o ${INFO_DIR}/file_list.json \
                -p ${RTL_DIR} \
                -R param_tfhe_definition_pkg.sv simu 0 1 \
                -R pep_batch_definition_pkg.sv simu 0 1 \
                -R pep_ks_common_definition_pkg.sv simu 0 1 \
                -F pep_ks_common_definition_pkg.Sv KSLB KSLB_x${LBX}y${LBY}z${LBZ} \
                -F pep_batch_definition_pkg.sv PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB} \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu"
  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

  echo ""

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/pep_batch_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/pep_ks_common_definition_pkg.sv"
fi

###################################################################################################
# Process
###################################################################################################
mkdir -p ${PROJECT_DIR}/hw/output
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._info"
echo -n "" > $TMP_FILE

#################################################
# Config phase : create directory + scripts
#################################################

eda_args="$eda_args -F PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB} \
                    -F APPLICATION APPLI_simu \
                    -F KSLB KSLB_x${LBX}y${LBY}z${LBZ}"

# Get current working directory
cmd="$run_edalize -m ${module} -t ${PROJECT_SIMU_TOOL} -y run -y build \
    $eda_args \
    $args"
echo "Info> Running : $cmd"
$cmd | tee >(grep "Work directory :" >> $TMP_FILE)
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

