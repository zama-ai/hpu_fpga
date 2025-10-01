#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

cli="$*"
set -e
export RUST_LOG=Debug

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

module="tb_hpu"

###################################################################################################
# Default values
###################################################################################################
SOFT_NAME=ucore_fw
SOFT_TARGET=microblaze
UCODE_DIR="default"

run_edalize_args=""
GEN_STIMULI=1

GLWE_K=1
PBS_L=1
PBS_B_W=23
R=2
PSI=8
S=9
MOD_NTT_W=-1 #MOD_NTT_W=64
MOD_NTT=-1 #MOD_NTT="2**64-2**32+1"
MOD_NTT_TYPE=-1 #MOD_NTT_TYPE="GOLDILOCKS"
NTT_GEN=-1 #NTT_GEN=7
MOD_Q="2**64"
MOD_Q_W=64
BATCH_PBS_NB=12
TOTAL_PBS_NB=16
LWE_K=20
BWD_PSI_DIV=1
NTT_CORE_ARCH="NONE"
NTT_RDX_CUT_S="$((($S+1)/2)) $(($S - $S/2))"
KS_L=7
KS_B_W=3
MOD_KSK_W=21
MOD_KSK="2**21"
LBX=2
LBY=16
LBZ=3
BSK_SLOT_NB=8
BSK_CUT_NB=1
BSK_PC=1
KSK_SLOT_NB=8
KSK_CUT_NB=1
KSK_PC=1
PEM_PC=1
SEED=-1
CLEAN=0
APPLICATION_NAME="APPLICATION_NAME_SIMU"
REGF_REG_NB=64
REGF_COEF_NB=32
REGF_SEQ=4

AXI_DATA_W=512
FPGA="u55c"

USE_MEAN_COMP=1

DOP_IMPLEM="Ilp"

GRAM_NB=4
TOP="hpu"
GLWE_PC=1
ISC_DEPTH=32
INT_SIZE=16
IOP="ADD"
REGIF_FILE_S="${PROJECT_DIR}/hw/module/hpu/module/hpu_regif/scripts/hpu_regif_core_cfg_1in3.toml \
              ${PROJECT_DIR}/hw/module/hpu/module/hpu_regif/scripts/hpu_regif_core_cfg_3in3.toml \
              ${PROJECT_DIR}/hw/module/hpu/module/hpu_regif/scripts/hpu_regif_core_prc_1in3.toml \
              ${PROJECT_DIR}/hw/module/hpu/module/hpu_regif/scripts/hpu_regif_core_prc_3in3.toml"

###################################################################################################
# usage
###################################################################################################
function usage () {
echo "Usage : run.sh runs the simulation for $module."
echo "./run.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-z                       : Do not generate stimuli."
echo "-C                       : Clean gen directory once the simulation is done."
echo "-g                       : GLWE_K (default $GLWE_K)"
echo "-l                       : PBS_L (default $PBS_L)"
echo "-b                       : PBS_B_W (default $PBS_B_W)"
echo "-R                       : R: Radix (default $R)"
echo "-P                       : PSI: Number of butterflies (default $PSI)"
echo "-S                       : S: Number of stages (default $S)"
echo "-w                       : MOD_NTT_W: NTT modulo width / NTT operand width (default 64)"
echo "-m                       : MOD_NTT: NTT modulo (default 'GOLDILOCK': 2**64-2**32+1)"
echo "-t                       : MOD_NTT_TYPE: NTT modulo type (default : GOLDILOCKS)"
echo "-G                       : NTT_GEN: NTT ring generator, if MOD_NTT_TYPE is unknown"
echo "-q                       : MOD_Q: modulo (default : 2**64)"
echo "-W                       : MOD_Q_W: modulo width (default 64)"
echo "-c                       : BATCH_PBS_NB (default : $BATCH_PBS_NB)"
echo "-H                       : TOTAL_PBS_NB (default : $TOTAL_PBS_NB)"
echo "-K                       : LWE_K (default : $LWE_K)"
echo "-e                       : BWD_PSI_DIV (default : $BWD_PSI_DIV) - used for unfold architecture"
echo "-A                       : NTT_CORE_ARCH (default : NTT_CORE_ARCH_wmm_unfold_pcg)"
echo "-J                       : NTT_RDX_CUT_S : NTT radix cut (default \"$NTT_RDX_CUT_S\"). Use several times to get all the cuts"
echo "-s                       : seed (if not given, random value.)"
echo "-I                       : APPLICATION_NAME. Should be an existing one. (default APPLICATION_NAME_SIMU)"
echo "-L                       : KS_L (default $KS_L)"
echo "-B                       : KS_B_W (default $KS_B_W)"
echo "-r                       : MOD_KSK: modulo (default $MOD_KSK)"
echo "-V                       : MOD_KSK_W: modulo width (default $MOD_KSK_W)"
echo "-o                       : BSK_SLOT_NB (default $BSK_SLOT_NB)"
echo "-u                       : BSK_CUT_NB (default $BSK_CUT_NB)"
echo "-f                       : BSK_PC (default $BSK_PC)"
echo "-O                       : KSK_SLOT_NB (default $KSK_SLOT_NB)"
echo "-U                       : KSK_CUT_NB (default $KSK_CUT_NB)"
echo "-F                       : KSK_PC (default $KSK_PC)"
echo "-E                       : PEM_PC : number of PC for the loading of BLWE from mem (default $PEM_PC)"
echo "-X                       : LBX: Number of coefficients columns processed in parallel (default $LBX)"
echo "-Y                       : LBY: Number of coefficients lines processed in parallel (default $LBY)"
echo "-Z                       : LBZ: Number of coefficients lines processed in parallel (default $LBZ)"
echo "-i                       : Regfile number of registers (default $REGF_REG_NB)"
echo "-j                       : Regfile number of coefficients (default $REGF_COEF_NB)"
echo "-k                       : Regfile number of sequences (default $REGF_SEQ)"
echo "-n                       : Integer size (default $INT_SIZE)"
echo "-x                       : software top file (default = \"${SOFT_NAME}\")"
echo "-y                       : directory containing microcode files. (default = \"${UCODE_DIR}\")"
echo "-a                       : default ucode IOP (default CUST_0)"
echo "-M                       : ISC depth (default $ISC_DEPTH)"
echo "-d                       : USE_MEAN_COMP (default 1)"
echo "-T                       : Toml regif definition file (default \"$REGIF_FILE_S\"). Use several times to give all the regfiles, if several."
echo "-p                       : Dop implementation (default Ilp)"
echo "-D                       : GRAM_NB (default: $GRAM_NB)"
echo "-- <run_edalize options> : run_edalize options."


}

###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1 # Reset in case getopts has been used previously in the shell.

echo "###################################################"
echo "INFO> Parse command line"
# Initialize your own variables here:
NTT_RDX_CUT_S_TMP=()
REGIF_FILE_S_TMP=()
while getopts "Chzg:l:R:P:S:w:t:m:c:H:K:s:e:b:q:W:A:J:I:L:B:r:V:X:Y:Z:G:o:u:f:O:U:F:i:j:k:x:E:y:n:a:M:T:p:d:D:" opt; do
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
    b)
      PBS_B_W=$OPTARG
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
      MOD_NTT_W=$OPTARG
      ;;
    m)
      MOD_NTT=$OPTARG
      ;;
    t)
      MOD_NTT_TYPE=$OPTARG
      ;;
    G)
      NTT_GEN=$OPTARG
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
    H)
      TOTAL_PBS_NB=$OPTARG
      ;;
    K)
      LWE_K=$OPTARG
      ;;
    s)
      SEED=$OPTARG
      ;;
    e)
      BWD_PSI_DIV=$OPTARG
      ;;
    A)
      NTT_CORE_ARCH=$OPTARG
      ;;
    J)
      NTT_RDX_CUT_S_TMP+=($OPTARG)
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
    o)
      BSK_SLOT_NB=$OPTARG
      ;;
    u)
      BSK_CUT_NB=$OPTARG
      ;;
    f)
      BSK_PC=$OPTARG
      ;;
    U)
      KSK_CUT_NB=$OPTARG
      ;;
    F)
      KSK_PC=$OPTARG
      ;;
    O)
      KSK_SLOT_NB=$OPTARG
      ;;
    E)
      PEM_PC=$OPTARG
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
    I)
      APPLICATION_NAME=$OPTARG
      echo "INFO> Use APPLICATION_NAME=${APPLICATION_NAME}."
      ;;
    i)
      REGF_REG_NB=$OPTARG
      ;;
    j)
      REGF_COEF_NB=$OPTARG
      ;;
    k)
      REGF_SEQ=$OPTARG
      ;;
    n)
      INT_SIZE=$OPTARG
      ;;
    x)
      echo "INFO> Embedded Software top file $OPTARG"
      SOFT_NAME=$OPTARG
      ;;
    y)
      UCODE_DIR=`realpath $OPTARG`
      echo "INFO> Microcode directory $UCODE_DIR"
      ;;
    a)
      IOP=$OPTARG
      ;;
    M)
      ISC_DEPTH=$OPTARG
      ;;
    T)
      REGIF_FILE_S_TMP+=($OPTARG)
      ;;
    p)
      DOP_IMPLEM=$OPTARG
      ;;
    d)
      USE_MEAN_COMP=$OPTARG
      ;;
    D)
      GRAM_NB=$OPTARG
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

N=$((${R}**${S}))

#--------------
# SEED
#--------------
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

#--------------
# NTT_CORE_ARCH
#--------------
# Check if a NTT_CORE_ARCH has been given in run_edalize option.
if [[ ${args} =~ .*-F( +)NTT_CORE_ARCH( +)([A-Za-z0-9_]+) ]]; then
  if [ $NTT_CORE_ARCH != "NONE" ]; then
    echo "ERROR> 2 NTT_CORE_ARCH values given. Define only one."
    exit 1
  fi
  NTT_CORE_ARCH=${BASH_REMATCH[2]}
  echo "INFO> Use NTT_CORE_ARCH from run_edalize arguments: $NTT_CORE_ARCH"
else
  if [ $NTT_CORE_ARCH = "NONE" ]; then
    NTT_CORE_ARCH="NTT_CORE_ARCH_wmm_unfold_pcg"
  fi
fi

#--------------
# BATCH_PBS_NB
#--------------
# Check that BATCH_PBS_NB and TOTAL_PBS_NB are multiple of GRAM_NB
if [ $(($BATCH_PBS_NB % $GRAM_NB)) -ne 0 ]; then
  echo "ERROR> BATCH_PBS_NB ($BATCH_PBS_NB) should be a multiple of GRAM_NB ($GRAM_NB)"
  exit 1
fi
if [ $(($TOTAL_PBS_NB % $GRAM_NB)) -ne 0 ]; then
  echo "ERROR> TOTAL_PBS_NB ($TOTAL_PBS_NB) should be a multiple of GRAM_NB ($GRAM_NB)"
  exit 1
fi

# Artificial number. Not used by the HW, but for the DOp code generation.
MIN_PBS_NB=$(($BATCH_PBS_NB - 2))

#--------------
# NTT
#--------------
# Check if an NTT_MOD has been defined with run_edalize flags
if [[ ${args} =~ .*-F( +)NTT_MOD( +)([a-zA-Z_0-9]+) ]]; then
  flag=${BASH_REMATCH[3]}
  L=(`${PROJECT_DIR}/hw/scripts/simu/parse_flag_NTT_MOD.sh -f $flag`)
  MOD_NTT_W_TMP=${L[0]}
  MOD_NTT_TMP=${L[1]}
  MOD_NTT_TYPE_TMP=${L[2]}
  NTT_GEN_TMP=${L[3]}
  if [ $MOD_NTT -ne -1 ] && [ $MOD_NTT != $MOD_NTT_TMP ]; then
    echo "ERROR> 2 incoherent MOD_NTT values given: through run_edalize flags and in command line."
    exit 1
  fi
  if [ $MOD_NTT_W -ne -1 ] && [ $MOD_NTT_W -ne $MOD_NTT_W_TMP ]; then
    echo "ERROR> 2 incoherent MOD_NTT_W values given: through run_edalize flags and in command line."
    exit 1
  fi
  if [ $MOD_NTT_TYPE -ne -1 ] && [ $MOD_NTT_TYPE != $MOD_NTT_TYPE_TMP ]; then
    echo "ERROR> 2 incoherent MOD_NTT_TYPE values given: through run_edalize flags and in command line."
    exit 1
  fi

  echo "INFO> From NTT_MOD flag : MOD_NTT_W=$MOD_NTT_W_TMP MOD_NTT=$MOD_NTT_TMP MOD_NTT_TYPE=$MOD_NTT_TYPE_TMP NTT_GEN=$NTT_GEN_TMP"
else
  # default
  MOD_NTT_W_TMP=64
  MOD_NTT_TMP="2**64-2**32+1"
  MOD_NTT_TYPE_TMP="GOLDILOCKS"
  NTT_GEN=7
fi

if [ $MOD_NTT -eq -1 ]; then
  MOD_NTT=$MOD_NTT_TMP
fi
if [ $MOD_NTT_W -eq -1 ]; then
  MOD_NTT_W=$MOD_NTT_W_TMP
fi
if [ $MOD_NTT_TYPE -eq -1 ]; then
  MOD_NTT_TYPE=$MOD_NTT_TYPE_TMP
fi
if [ $NTT_GEN -eq -1 ]; then
  NTT_GEN=$NTT_GEN_TMP
fi

if [ $NTT_GEN -eq -1 ]; then
  echo "ERROR> NTT ring generator not given."
  exit 1
fi

# Use another format for MOD_M/ Replace ** with ^
MOD_NTT_BIS=$(echo $MOD_NTT | sed 's/\*\*/^/g')
MOD_NTT_TER=`python3 -c "print($MOD_NTT)"`

gtv_args="--generator $NTT_GEN"
if [ $MOD_NTT_TYPE = "GOLDILOCKS" ] && [ $N -ge 32 ] && [ $N -le 4096 ] ; then
  if [ $N -eq 32 ] ; then
    wn=64
    w2n=8
  elif [ $N -eq 64 ] ; then
    wn=8
    w2n=2198989700608
  elif [ $N -eq 128 ] ; then
    wn=2198989700608
    w2n=14041890976876060974
  elif [ $N -eq 256 ] ; then
    wn=14041890976876060974
    w2n=14430643036723656017
  elif [ $N -eq 512 ] ; then
    wn=14430643036723656017
    w2n=4440654710286119610
  elif [ $N -eq 1024 ] ; then
    wn=4440654710286119610
    w2n=8816101479115663336
  elif [ $N -eq 2048 ] ; then
    wn=8816101479115663336
    w2n=10974926054405199669
  elif [ $N -eq 4096 ] ; then
    wn=10974926054405199669
    w2n=1206500561358145487
  else
    echo "INFO> No friendly twiddles for Goldilocks"
    exit 1
  fi
  gtv_args="--omega-ru-n $wn --phi-ru-2n $w2n"
fi

#--------------
# NTT_RDX_CUT_S / DELTA
#--------------
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
echo "INFO> NTT rdx cut : ${NTT_RDX_CUT_S_TMP[@]}"

# Delta is the first element given through NTT_RDX_CUT_S_L
DELTA=${NTT_RDX_CUT_S_L[0]}

if [ $NTT_CORE_ARCH = "NTT_CORE_ARCH_wmm_unfold_pcg" ] ; then
  if [ $NTT_RDX_CUT_NB -ne 2 ] || [ ${NTT_RDX_CUT_S_L[0]} -lt ${NTT_RDX_CUT_S_L[1]} ]; then
    echo "ERROR> NTT_CORE_ARCH_wmm_unfold_pcg supports only 2 cuts, with the first one greater or equal to the second one."
    exit 1
  fi
fi


#--------------
# REGIF_FILE
#--------------
if [ ${#REGIF_FILE_S_TMP[@]} -gt 0 ]; then
  REGIF_FILE_S_L=(${REGIF_FILE_S_TMP[@]})
else
  #REGIF_FILE_S_L=($REGIF_FILE_S)
  # TODO : Workaround : SW needs worq registers
  REGIF_FILE_S_L=($REGIF_FILE_S ${PROJECT_DIR}/hw/module/hpu/simu/scripts/tb_hpu_regif_dummy.toml)
fi
REGIF_FILE_NB=${#REGIF_FILE_S_L[@]}

regif_file_arg=""
for i in "${REGIF_FILE_S_L[@]}" ; do
    regif_file_arg="$regif_file_arg --regmap_file $i"
done


#--------------
# AXI_DATA_W
#--------------
# Is given by a flag
if [[ ${args} =~ .*-F( +)AXI_DATA_W( +)AXI_DATA_W_([0-9]+) ]]; then
  AXI_DATA_W=${BASH_REMATCH[3]}
fi
echo "INFO> AXI_DATA_W : $AXI_DATA_W"
AXI_DATA_BYTES=$(($AXI_DATA_W / 8))

#--------------
# FPGA
#--------------
# Is given by a flag
if [[ ${args} =~ .*-F( +)FPGA( +)FPGA_([a-zA-Z0-9_]+) ]]; then
  FPGA=${BASH_REMATCH[3]}
fi
echo "INFO> FPGA : $FPGA"

if [ $FPGA = "u55c" ] ; then
  BSK_PC_MAX=8
  KSK_PC_MAX=8
  PEM_PC_MAX=2
elif [ $FPGA = "v80" ] ; then
  BSK_PC_MAX=16
  KSK_PC_MAX=16
  PEM_PC_MAX=2
else
    echo "ERROR> Unsupported FPGA type $FPGA."
    exit 1
fi


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
TV_DIR=${INPUT_DIR}/test_vectors/latest
SOFT_OUTPUT_DIR=${PROJECT_DIR}/hw/output/micro_code
MEM_DIR=${PROJECT_DIR}/hw/memory_file/microblaze

gtv_bin="${PROJECT_DIR}/sw/bin/gtv/latest/gtv"
hpu_mockup_bin="${PROJECT_DIR}/sw/bin/tfhe-rs/latest/hpu_mockup"
hpu_bench_bin="${PROJECT_DIR}/sw/bin/tfhe-rs/latest/hpu_bench"
twd_script="${PROJECT_DIR}/hw/module/hpu/simu/scripts/gen_twd.py"
hpu_mockup_cfg_script="${PROJECT_DIR}/sw/bin/tfhe-rs/config/gen_hpu_mockup_config.py"
hpu_cfg_script="${SCRIPT_DIR}/gen_hpu_config.py"
ntt_gf64_script="${PROJECT_DIR}/sw/ntt/ntt_gf64.sage"

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
# Generate packages
###################################################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
mkdir -p ${PROJECT_DIR}/hw/output
INFO_DIR=${SCRIPT_DIR}/../gen/info
mkdir -p $INFO_DIR
RTL_DIR=${SCRIPT_DIR}/../gen/rtl
mkdir -p $RTL_DIR

# Create package {{{
if [ $GEN_STIMULI -eq 1 ] ; then
  echo "###################################################"

  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_tfhe_definition_pkg.py -f \
                  -N $N -g $GLWE_K -l $PBS_L -K $LWE_K -b $PBS_B_W -q $MOD_Q -W $MOD_Q_W \
                  -L $KS_L -B $KS_B_W -r $MOD_KSK -V $MOD_KSK_W -d $USE_MEAN_COMP \
                  -o ${RTL_DIR}/param_tfhe_definition_pkg.sv -n $APPLICATION_NAME"
  echo "INFO> N=${N}, GLWE_K=${GLWE_K}, PBS_L=${PBS_L} LWE_K=${LWE_K} PBS_B_W=${PBS_B_W} MOD_Q=${MOD_Q}\
  MOD_Q_W=${MOD_Q_W} APPLICATION_NAME=${APPLICATION_NAME} KS_L=${KS_L} KS_B_W=${KS_B_W} MOD_KSK=${MOD_KSK} MOD_KSK_W=${MOD_KSK_W} USE_MEAN_COMP=${USE_MEAN_COMP}"
  echo "INFO> Creating param_tfhe_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/param/scripts/gen_param_ntt_definition_pkg.py -f -w $MOD_NTT_W -m $MOD_NTT -t $MOD_NTT_TYPE -o ${RTL_DIR}/param_ntt_definition_pkg.sv"
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

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/pep_key_switch/module/pep_ks_common/scripts/gen_pep_ks_common_definition_pkg.py\
          -f -lbx $LBX -lby $LBY -lbz $LBZ -o ${RTL_DIR}/pep_ks_common_definition_pkg.sv"
  echo "INFO> LBX=$LBX LBY=$LBY LBZ=$LBZ"
  echo "INFO> pep_ks_common_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/bsk/module/bsk_manager/module/bsk_mgr_common/scripts/gen_bsk_mgr_common_cut_definition_pkg.py\
          -f -bsk_cut $BSK_CUT_NB -o ${RTL_DIR}/bsk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> BSK_CUT_NB=$BSK_CUT_NB"
  echo "INFO> bsk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/bsk/module/bsk_manager/module/bsk_mgr_common/scripts/gen_bsk_mgr_common_slot_definition_pkg.py\
          -f -bsk_slot $BSK_SLOT_NB -o ${RTL_DIR}/bsk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> BSK_SLOT_NB=$BSK_SLOT_NB"
  echo "INFO> bsk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/ksk/module/ksk_manager/module/ksk_mgr_common/scripts/gen_ksk_mgr_common_cut_definition_pkg.py\
          -f -ksk_cut $KSK_CUT_NB -o ${RTL_DIR}/ksk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> KSK_CUT_NB=$KSK_CUT_NB"
  echo "INFO> ksk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/ksk/module/ksk_manager/module/ksk_mgr_common/scripts/gen_ksk_mgr_common_slot_definition_pkg.py\
          -f -ksk_slot $KSK_SLOT_NB -o ${RTL_DIR}/ksk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> KSK_SLOT_NB=$KSK_SLOT_NB"
  echo "INFO> ksk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/top_common/scripts/gen_top_common_pc_definition_pkg.py\
          -f -ksk_pc $KSK_PC -bsk_pc $BSK_PC -pem_pc $PEM_PC -o ${RTL_DIR}/top_common_pc_definition_pkg.sv"
  echo "INFO> KSK_PC=$KSK_PC BSK_PC=$BSK_PC PEM_PC=$PEM_PC"
  echo "INFO> top_common_pc_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/top_common/scripts/gen_top_common_pcmax_definition_pkg.py\
          -f -ksk_pc $KSK_PC_MAX -bsk_pc $BSK_PC_MAX -pem_pc $PEM_PC_MAX -o ${RTL_DIR}/top_common_pcmax_definition_pkg.sv"
  echo "INFO> KSK_PC_MAX=$KSK_PC_MAX BSK_PC_MAX=$BSK_PC_MAX PEM_PC=$PEM_PC_MAX"
  echo "INFO> top_common_pcmax_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/regfile/module/regf_common/scripts/gen_regf_common_definition_pkg.py\
          -f -regf_reg_nb $REGF_REG_NB -regf_coef_nb $REGF_COEF_NB -regf_seq $REGF_SEQ -o ${RTL_DIR}/regf_common_definition_pkg.sv"
  echo "INFO> REGF_REG_NB=$REGF_REG_NB REGF_COEF_NB=$REGF_COEF_NB REGF_SEQ=$REGF_SEQ"
  echo "INFO> Creating regf_common_definition_pkg.sv"
  echo "INFO> Running : $pkg_cmd"
  $pkg_cmd || exit 1

  echo ""
  pkg_cmd="python3 ${PROJECT_DIR}/hw/module/hpu/module/hpu_common/scripts/gen_hpu_twdfile_definition_pkg.py\
          -f -ifnl input/test_vectors/latest/twd_ifnl -phru input/test_vectors/latest/twd_phru \
          -phi input/twd_phi \
          -o ${RTL_DIR}/hpu_twdfile_definition_pkg.sv"
  echo "INFO> TWD_IFNL='input/test_vectors/latest/twd_ifnl' TWD_PHRU='input/test_vectors/latest/twd_phru'"
  echo "INFO> Creating hpu_twdfile_definition_pkg.sv"
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
                -R pep_ks_common_definition_pkg.sv simu 0 1 \
                -R bsk_mgr_common_cut_definition_pkg.sv simu 0 1 \
                -R bsk_mgr_common_slot_definition_pkg.sv simu 0 1 \
                -R ksk_mgr_common_cut_definition_pkg.sv simu 0 1 \
                -R ksk_mgr_common_slot_definition_pkg.sv simu 0 1 \
                -R top_common_pc_definition_pkg.sv simu 0 1 \
                -R top_common_pcmax_definition_pkg.sv simu 0 1 \
                -R pep_batch_definition_pkg.sv simu 0 1 \
                -R regf_common_definition_pkg.sv simu 0 1 \
                -R hpu_twdfile_definition_pkg.sv simu 0 1 \
                -F bsk_mgr_common_cut_definition_pkg.sv BSK_CUT BSK_CUT_${BSK_CUT_NB} \
                -F bsk_mgr_common_slot_definition_pkg.sv BSK_SLOT BSK_SLOT_${BSK_SLOT_NB} \
                -F top_common_pc_definition_pkg.sv TOP_PC TOP_PC_bsk${BSK_PC}_ksk${KSK_PC}_pem${PEM_PC} \
                -F top_common_pcmax_definition_pkg.sv TOP_PCMAX TOP_PCMAX_bsk${BSK_PC_MAX}_ksk${KSK_PC_MAX}_pem${PEM_PC_MAX} \
                -F ksk_mgr_common_cut_definition_pkg.sv KSK_CUT KSK_CUT_${KSK_CUT_NB} \
                -F ksk_mgr_common_slot_definition_pkg.sv KSK_SLOT KSK_SLOT_${KSK_SLOT_NB} \
                -F pep_batch_definition_pkg.sv PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB}_tpbs${TOTAL_PBS_NB} \
                -F ntt_core_common_arch_definition_pkg.sv NTT_CORE_ARCH $NTT_CORE_ARCH \
                -F ntt_core_common_psi_definition_pkg.sv NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                -F ntt_core_common_div_definition_pkg.sv NTT_CORE_DIV NTT_CORE_DIV_${BWD_PSI_DIV} \
                -F ntt_core_common_cut_definition_pkg.sv NTT_CORE_RDX_CUT NTT_CORE_RDX_CUT_${ntt_cut_flag} \
                -F param_tfhe_definition_pkg.sv APPLICATION APPLI_simu \
                -F param_ntt_definition_pkg.sv NTT_MOD NTT_MOD_simu \
                -F pep_ks_common_definition_pkg.sv KSLB KSLB_x${LBX}y${LBY}z${LBZ} \
                -F regf_common_definition_pkg.sv REGF_STRUCT REGF_STRUCT_reg${REGF_REG_NB}_coef${REGF_COEF_NB}_seq${REGF_SEQ} \
                -F hpu_twdfile_definition_pkg.sv HPU_TWDFILE HPU_TWDFILE_simu "

  echo "INFO> Running : $file_list_cmd"
  $file_list_cmd || exit 1

else
  echo "INFO> Using existing ${RTL_DIR}/param_tfhe_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/param_ntt_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_arch_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_psi_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_div_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ntt_core_common_cut_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/pep_batch_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/pep_ks_common_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ksk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/ksk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/top_common_pcmax_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/top_common_pc_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/bsk_mgr_common_cut_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/bsk_mgr_common_slot_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/regf_common_definition_pkg.sv"
  echo "INFO> Using existing ${RTL_DIR}/hpu_twdfile_definition_pkg.sv"
fi

eda_args="$eda_args
                -F NTT_CORE_R NTT_CORE_R_${R} \
                -F BSK_CUT BSK_CUT_${BSK_CUT_NB} \
                -F BSK_SLOT BSK_SLOT_${BSK_SLOT_NB} \
                -F TOP_PC TOP_PC_bsk${BSK_PC}_ksk${KSK_PC}_pem${PEM_PC} \
                -F TOP_PCMAX TOP_PCMAX_bsk${BSK_PC_MAX}_ksk${KSK_PC_MAX}_pem${PEM_PC_MAX} \
                -F KSK_CUT KSK_CUT_${KSK_CUT_NB} \
                -F KSK_SLOT KSK_SLOT_${KSK_SLOT_NB} \
                -F PEP_BATCH PEP_BATCH_bpbs${BATCH_PBS_NB}_tpbs${TOTAL_PBS_NB} \
                -F NTT_CORE_ARCH $NTT_CORE_ARCH \
                -F NTT_CORE_PSI NTT_CORE_PSI_${PSI} \
                -F NTT_CORE_DIV NTT_CORE_DIV_${BWD_PSI_DIV} \
                -F NTT_CORE_RDX_CUT NTT_CORE_RDX_CUT_${ntt_cut_flag} \
                -F APPLICATION APPLI_simu \
                -F NTT_MOD NTT_MOD_simu \
                -F KSLB KSLB_x${LBX}y${LBY}z${LBZ} \
                -F REGF_STRUCT REGF_STRUCT_reg${REGF_REG_NB}_coef${REGF_COEF_NB}_seq${REGF_SEQ} \
                -F HPU_TWDFILE HPU_TWDFILE_simu"

###################################################################################################
# Check microcode
###################################################################################################
if [ $GEN_STIMULI -eq 1 ] ; then
  echo "###################################################"
  if [ $UCODE_DIR = "default" ] ; then
    echo "INFO> Use ucode generated by tfhe-rs in directory ${INPUT_DIR}/ucode, for IOP=$IOP"
    if [ -d $INPUT_DIR/ucode ] ; then rm -rf ${INPUT_DIR}/ucode ; fi
  else
    echo "INFO> Using existing ucode directory $UCODE_DIR."
    echo "INFO> Copy ${UCODE_DIR} to $INPUT_DIR/ucode"
    if [ -d $INPUT_DIR/ucode ] ; then rm -rf $INPUT_DIR/ucode ; fi
    cp -r $UCODE_DIR $INPUT_DIR/ucode
  fi
else
  if [ $UCODE_DIR = "default" ] ; then
    echo "INFO> Using existing ucode directory $INPUT_DIR/ucode."
  else
    echo "INFO> Using existing ucode directory $UCODE_DIR."
  fi
fi

###################################################################################################
# Build stimuli
###################################################################################################
# Create input stimuli if necessary
if [ $GEN_STIMULI -eq 1 ] ; then

  gtv_bin="${PROJECT_DIR}/sw/bin/gtv/latest/gtv"

  #== Generate twiddles
  echo "###################################################"
  if [ $NTT_CORE_ARCH = "NTT_CORE_ARCH_gf64" ]; then
    echo "INFO> Generate twiddles for GF64"
    phi_cmd="sage ${ntt_gf64_script} \
            -gen_rom \
            -coef $(($R * $PSI)) \
            -N $N \
            $ntt_cut_arg \
            -dir ${INPUT_DIR}"
    echo "INFO> Running : $phi_cmd"
    $phi_cmd || exit 1
  else # wmm
    echo "INFO> Generate twiddles for WMM"
    # TODO let carry-w/msg-w to be shell input
    ref_cmd="${gtv_bin} \
      --ntt-radix $R \
      --psi $PSI \
      --ntt-delta $DELTA \
      --poly-size $(python3 -c "print($R**$S)") \
      --lwe-dim $LWE_K \
      --glwe-dim $GLWE_K \
      --mod-p $(echo $MOD_NTT_BIS | bc -l) \
      --pbs-lc $PBS_L \
      --pbs-bl $PBS_B_W \
      --out-folder ${INPUT_DIR}/test_vectors \
      --pbs-batch 1 \
      --pbs-per-batch  1 \
      --ct-w $MOD_Q_W \
      --ks-lbx $LBX \
      --ks-lby $LBY \
      --ks-lbz $LBZ \
      --ks-lc $KS_L \
      --ks-w $MOD_KSK_W \
      --ks-bl $KS_B_W \
      --msg-w 2 \
      --carry-w 2 \
      --ksk-pc $KSK_PC \
      --bsk-pc $BSK_PC \
      $gtv_args \
      --seed $SEED"
    echo "INFO> Running : $ref_cmd"
    $ref_cmd || exit 1

    # Now python post-process is only used to generate twiddle files
    gen_cmd="python3 $twd_script \
      -o $TV_DIR \
      -i $TV_DIR \
      -delta $DELTA \
      -u \
      -A $NTT_CORE_ARCH \
      -R $R \
      -P $PSI \
      -S $S \
      -w $MOD_NTT_W \
      -W $MOD_Q_W \
      -s $SEED \
      -l $PBS_L \
      -K $LWE_K \
      -g $GLWE_K \
      -dM $BATCH_PBS_NB \
      -dm 1 \
      -e $BWD_PSI_DIV"
    echo "INFO> Running : $gen_cmd"
    $gen_cmd || exit 1
  fi

  #== Create hpu config
  echo "###################################################"
  echo "INFO> Generate hpu config file"
  # Extract list of custom operations
  gen_cfg_args=""
  if [[ $IOP =~ ^IOP\[([0-9]+)\]$ ]]; then
    if [ $UCODE_DIR == "default" ] ; then
      echo "ERROR> $IOP IOP is used, -y option should be given."
      exit 1
    elif [ ! -d $UCODE_DIR ] ; then
      echo "ERROR> Ucode directory $UCODE_DIR does not exit."
      exit 1
    fi

    idx=${BASH_REMATCH[1]}
    if [ ! -f ${UCODE_DIR}/IOP_${idx}.asm ]; then
      echo "ERROR> Ucode ${UCODE_DIR}/${idx}.asm does not exist."
      exit 1
    fi
    gen_cfg_args="$gen_cfg_args --cust_iop ${UCODE_DIR}/IOP_${idx}.asm"
  else
    if [ $UCODE_DIR != "default" ] ; then
      echo "WARNING> Ucode directory $UCODE_DIR given, but it won't be used, since the IOP is not a custom"
    fi
  fi

  gen_cfg_cmd="python3 ${hpu_cfg_script} \
                -n $INT_SIZE \
                --regmap_file ${REGIF_FILE_S_L[@]} \
                --min_batch_size $MIN_PBS_NB \
                --dop_implementation $DOP_IMPLEM \
                $gen_cfg_args \
                -o ${INPUT_DIR}/hpu_cfg.toml \
                -f"
  echo "INFO> Running $gen_cfg_cmd"
  $gen_cfg_cmd || exit 1

  #== Create hpu_mockup config
  echo "###################################################"
  echo "INFO> Generate hpu_mockup config file"
  gen_mockup_cfg_cmd="python3 ${hpu_mockup_cfg_script} \
                -R $R \
                -P $PSI \
                -N $N \
                -A $NTT_CORE_ARCH
                -g $GLWE_K \
                -l $PBS_L \
                -b $PBS_B_W \
                -L $KS_L \
                -B $KS_B_W \
                -K $LWE_K \
                -W $MOD_Q_W \
                -w $MOD_NTT_W \
                -m $MOD_NTT_TER \
                -V $MOD_KSK_W \
                -lbx $LBX \
                -lby $LBY \
                -lbz $LBZ \
                -bpbs_nb $BATCH_PBS_NB \
                -tpbs_nb $TOTAL_PBS_NB \
                -regf_reg_nb $REGF_REG_NB \
                -regf_coef_nb $REGF_COEF_NB \
                -pem_pc $PEM_PC \
                -glwe_pc $GLWE_PC \
                -bsk_pc $BSK_PC \
                -ksk_pc $KSK_PC \
                -pem_bytes_w $AXI_DATA_BYTES \
                -glwe_bytes_w $AXI_DATA_BYTES \
                -bsk_bytes_w $AXI_DATA_BYTES \
                -ksk_bytes_w $AXI_DATA_BYTES \
                -isc_depth $ISC_DEPTH \
                -use_mean_comp $USE_MEAN_COMP \
                $ntt_cut_arg \
                -z $DELTA \
                -o ${INPUT_DIR}/hpu_mockup_cfg.toml \
                -f"
  echo "INFO> Running $gen_mockup_cfg_cmd"
  $gen_mockup_cfg_cmd || exit 1

  #== Create stimuli
  echo "###################################################"
  echo "INFO> Create stimuli"

  # Start mockup in background
  hpu_mockup_cmd="$hpu_mockup_bin \
      --config ${INPUT_DIR}/hpu_cfg.toml\
      --params ${INPUT_DIR}/hpu_mockup_cfg.toml \
      --dump-out ${INPUT_DIR}/ucode"
  echo "INFO> Running $hpu_mockup_cmd in background"
  RUST_LOG="debug" $hpu_mockup_cmd &
  hpu_mockup_pid=$!
  # Let some time to hpu_mockup to init and configure Ipc
  sleep 1

  # In case of custom IOP check if it required a immediat
  # This should be describe in custom_iop header with a dedicated prototype file
  # Currently IOP 0-15 -> CTxCT
  #         IO0 16-31 -> CtxImm
  # TODO remove this hack when custom iop prototype is ready
  IOP_PROTO=""
  if [[ $IOP =~ ^IOP\[([0-9]+)\]$ ]]; then
    iop_id=${BASH_REMATCH[1]}
    if [ ${iop_id} -ge 16 ]; then
      IOP_PROTO="--user-proto <Native>::<Native,Native><0>"
      else
      IOP_PROTO="--user-proto <Native>::<Native><1>"
    fi
  fi

  hpu_bench_cmd="$hpu_bench_bin \
      --config ${INPUT_DIR}/hpu_cfg.toml\
      --integer-w ${INT_SIZE}\
      --io-dump ${INPUT_DIR}/ucode\
      --seed ${SEED}\
      ${IOP_PROTO} \
      --iop ${IOP}"
  echo "INFO> Running $hpu_bench_cmd"
  $hpu_bench_cmd || exit 1

  # Stop mockup background task
  kill_cmd="kill $hpu_mockup_pid"
  echo "INFO> Running $kill_cmd"
  $kill_cmd || exit 1

  #== Cleanup generated files
  # Replace comment sign # with slashes => supported by readmemh
  for f in `find ${INPUT_DIR}/ucode/blwe/input -name "*.hex"`; do
    sed -i 's/#/\/\//' $f
  done
  for f in `find ${INPUT_DIR}/ucode/glwe -name "*.hex"`; do
    sed -i 's/#/\/\//' $f
  done
  for f in `find ${INPUT_DIR}/ucode/key -name "*.hex"`; do
    sed -i 's/#/\/\//' $f
  done

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

# Find list of GLWE
GLWE_L=""
GLWE_NB=0
for f in `ls ${INPUT_DIR}/ucode/glwe/*.hex`; do
  name=`basename $f`
  if [[ $name =~ glwe_([0-9a-f][0-9a-f]).hex$ ]]; then
    n=${BASH_REMATCH[1]}
    GLWE_L="$n${GLWE_L}"
    GLWE_NB=$(( $GLWE_NB+1 ))
    echo "INFO> Use glwe_$n.hex"
  else
    echo "WARNING> GLWE file's name: $name not recognized. Should be of this form \"glwe_([0-9a-f][0-9a-f]).hex\""
  fi
done
echo "INFO> GLWE_NB=$GLWE_NB"
SIZE_GLWE_LIST=$(( $GLWE_NB * 8 ))

# Find list of BLWE
BLWE_L=""
BLWE_NB=0
for f in `ls ${INPUT_DIR}/ucode/blwe/input/*.hex`; do
  name=`basename $f`
  if [[ $name =~ blwe_([0-9a-f][0-9a-f][0-9a-f][0-9a-f])_([0-9a-f]).hex$ ]]; then
    n=${BASH_REMATCH[1]}
    pc=${BASH_REMATCH[2]}
    if [ $pc -eq 0 ]; then # Store only once
        BLWE_L="$n${BLWE_L}"
        BLWE_NB=$(( $BLWE_NB+1 ))
    fi
    echo "INFO> Use input/blwe_${n}_${pc}.hex"
  else
    echo "WARNING> BLWE file's name: $name not recognized. Should be of this form \"blwe_([0-9a-f][0-9a-f][0-9a-f][0-9a-f])_([0-9a-f]).hex\""
  fi
done
echo "INFO> BLWE_NB=$BLWE_NB"
SIZE_BLWE_LIST=$(( $BLWE_NB * 16 ))

# Find list of BLWE
OUT_BLWE_L=""
OUT_BLWE_NB=0
for f in `ls ${INPUT_DIR}/ucode/blwe/output/*.hex`; do
  name=`basename $f`
  if [[ $name =~ blwe_([0-9a-f][0-9a-f][0-9a-f][0-9a-f])_([0-9a-f]).hex$ ]]; then
    n=${BASH_REMATCH[1]}
    pc=${BASH_REMATCH[2]}
    if [ $pc -eq 0 ]; then # Store only once
        OUT_BLWE_L="$n${OUT_BLWE_L}"
        OUT_BLWE_NB=$(( $OUT_BLWE_NB+1 ))
    fi
    echo "INFO> Use output/blwe_${n}_${pc}.hex"
  else
    echo "WARNING> OUT_BLWE file's name: $name not recognized. Should be of this form \"blwe_([0-9a-f][0-9a-f][0-9a-f][0-9a-f])_([0-9a-f]).hex\""
  fi
done
echo "INFO> OUT_BLWE_NB=$OUT_BLWE_NB"
SIZE_OUT_BLWE_LIST=$(( $OUT_BLWE_NB * 16 ))

escape_char=''
if [[ $PROJECT_SIMU_TOOL == "xsim" ]]; then
    escape_char='\'
fi

eda_args="$eda_args \
            -P IOP_NB int $IOP_NB \
            -P IOP_INT_SIZE int $INT_SIZE \
            -P DOP_NB int $DOP_NB \
            -P DOP_LIST str \"$SIZE_DOP_L${escape_char}'h$DOP_L\" \
            -P GLWE_NB int $GLWE_NB \
            -P GLWE_LIST str \"$SIZE_GLWE_LIST${escape_char}'h$GLWE_L\" \
            -P BLWE_NB int $BLWE_NB \
            -P BLWE_LIST str \"$SIZE_BLWE_LIST${escape_char}'h$BLWE_L\" \
            -P OUT_BLWE_NB int $OUT_BLWE_NB \
            -P OUT_BLWE_LIST str \"$SIZE_OUT_BLWE_LIST${escape_char}'h$OUT_BLWE_L\" \
            "

# Need to initialize regfile
eda_args="$eda_args -D DEF_INIT_RAM int 1"

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
