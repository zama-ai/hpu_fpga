#! /usr/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# This script parse the NTT_MOD flag, and creates the following variables:
# MOD_NTT_W: NTT modulo width / NTT operand width"
# MOD_NTT: NTT modulo"
# MOD_NTT_TYPE: NTT modulo type"
#
# It recognizes:
# NTT_MOD_NTT_MOD_solinas3_32_17_13
# NTT_MOD_solinas2_32_20
# NTT_MOD_goldilocks
# NTT_MOD_solinas2_44_14
# ----------------------------------------------------------------------------------------------
# usage
# ==============================================================================================

function usage () {
  echo "Usage : parse_flag_NTT_MOD.sh parses the NTT_MOD flag"
  echo "./parse_flag_NTT_MOD.sh [options]"
  echo "Options are:"
  echo "-h                       : print this help."
  echo "-f                       : NTT_MOD flag."
}

FLAG=""
while getopts "hf:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    f)
      FLAG=$OPTARG
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


###################################################################################################
# usage
###################################################################################################

if [[ ${FLAG} =~ NTT_MOD_solinas3_([0-9]+)_([0-9]+)_([0-9]+)$ ]] ; then
  MOD_NTT_W=${BASH_REMATCH[1]}
  MOD_NTT="2**${BASH_REMATCH[1]}-2**${BASH_REMATCH[2]}-2**${BASH_REMATCH[3]}+1"
  MOD_NTT_TYPE="SOLINAS3"
  if [ ${FLAG} = "NTT_MOD_solinas3_32_17_13" ] ; then
    NTT_GEN=10
  else
    NTT_GEN=-1
  fi
elif [[ ${FLAG} =~ NTT_MOD_solinas2_([0-9]+)_([0-9]+)$ ]] ; then
  MOD_NTT_W=${BASH_REMATCH[1]}
  MOD_NTT="2**${BASH_REMATCH[1]}-2**${BASH_REMATCH[2]}+1"
  MOD_NTT_TYPE="SOLINAS2"
  if [ ${FLAG} = "NTT_MOD_solinas2_32_20" ] ; then
    NTT_GEN=19
  elif [ ${FLAG} = "NTT_MOD_solinas2_44_14" ] ; then
    NTT_GEN=5
  elif [ ${FLAG} = "NTT_MOD_solinas2_23_13" ] ; then
    NTT_GEN=10
  elif [ ${FLAG} = "NTT_MOD_solinas2_16_12" ] ; then
    NTT_GEN=17
  else
    NTT_GEN=-1
  fi
elif [ ${FLAG} = "NTT_MOD_goldilocks" ] ; then
  MOD_NTT_W=64
  MOD_NTT="2**64-2**32+1"
  MOD_NTT_TYPE="GOLDILOCKS"
  NTT_GEN=7
else
  echo "ERROR> Unknown NTT_MOD flag: ${FLAG}"
  exit 1
fi


echo $MOD_NTT_W
echo $MOD_NTT
echo $MOD_NTT_TYPE
echo $NTT_GEN
