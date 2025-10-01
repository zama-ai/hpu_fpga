#! /usr/bin/bash

# Find current script directory. This should be PROJECT_DIR
CUR_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
export PROJECT_DIR=$CUR_SCRIPT_DIR

# There are two Optional arguments available
# 1 - Argument CONFIG will load the corresponding configuration. By default = base
# 2 - Argument AWS_ZAMA_USER, for CONFIG=aws will set S3 bucket username
CONFIG=${1:-"base"}

export_str=""

echo "#################################################"
echo "-------------------------------------------------"
echo "| HPU project setup                             |"
echo "-------------------------------------------------"
echo "#################################################"

if [ -z ${XILINX_PATH+x} ] ; then
    echo "ERROR > \$XILINX_PATH is not defined."
    return 1
fi

# Edalize setup
edalize_path="$(realpath edalize)"
export PYTHONPATH=$PYTHONPATH:$edalize_path

SETUP_CONFIG="${PROJECT_DIR}/setup_config/setup_${CONFIG}.sh"

if [ -f "$SETUP_CONFIG" ]; then
  echo "INFO > source ${SETUP_CONFIG}  $2"
  source ${SETUP_CONFIG} || return 1
else
  echo "Configuration not found ($SETUP_CONFIG). Check name of configuration : ${CONFIG}"
  return 1
fi

# Set default tools
export PROJECT_SIMU_TOOL="vcs"
export PROJECT_SYN_TOOL="vivado"
export PROJECT_TOP_SYN_TOOL="vitis"

# Necessary for Xilinx tools to work correctly
export XILINX_VIVADO=${XILINX_VIVADO:-${XILINX_PATH}/${XILINX_TOOL_VERSION}/Vivado}
export XILINX_VITIS=${XILINX_VITIS:-${XILINX_PATH}/${XILINX_TOOL_VERSION}/Vitis}


# Microblaze configuration
export MICROBLAZE_CONF="ublaze"
# for compilation using Vitis
export LC_ALL="C"

# Vitis Setup
# on AWS setup.sh is sourced from their Toolset
export VITIS_TARGET=hw

# VCS setup
if [ $PROJECT_SIMU_TOOL = "vcs" ] ; then
    export VCS_ARCH_OVERRIDE=${VCS_ARCH_OVERRIDE:-"linux"}

    if [[ -z "$SNPS_VCS_PATH" ]]; then
      echo "INFO > SNPS_VCS_PATH does not exist, cannot add vcs tool path in \$PATH"
    else
      export VCS_HOME="$SNPS_VCS_PATH/$SNPS_TOOL_VERSION"
      # To use gcc delevered and tested by Synopsys
      #  export VG_GNU_PACKAGE="$VCS_HOME/gnu/linux"
      #  echo "INFO > source $VG_GNU_PACKAGE/source_me.sh"
      #  source $VG_GNU_PACKAGE/source_me.sh

      # Add Synopsys in path
      export PATH="$VCS_HOME/bin:$PATH"
      # export_str="${export_str}\n  VG_GNU_PACKAGE=$VG_GNU_PACKAGE"
      export_str="${export_str}\n  VCS_HOME=$VCS_HOME"
    fi

    if [[ -z "$SNPS_VERDI_PATH" ]]; then
      echo "INFO > SNPS_VERDI_PATH does not exist, cannot add <SNPS_VERDI_PATH>/<VERSION>/bin in \$PATH"
    else
      export FSDB_VARIANT_SIZE_ARRAY=1
      export VERDI_ENHANCE_DYNAMIC_OBJECT=1
      export VERDI_HOME="$SNPS_VERDI_PATH/$SNPS_TOOL_VERSION"
      export PATH="$VERDI_HOME/bin:$PATH"
      export_str="${export_str}\n  VERDI_HOME=$VERDI_HOME"
    fi

fi

# Simulation variables
# tv_hw version
export TV_HW_VERSION="split_v1.5"

# gtv version
export GTV_VERSION="v1.4.1"

# tfhe-rs version
export TFHERS_VERSION="v2.8"

# Complete PATH with Xilinx's tools
echo "INFO > Run $XILINX_VIVADO/settings64.sh"
source $XILINX_VIVADO/settings64.sh
echo "INFO > Run $XILINX_VITIS/settings64.sh"
source $XILINX_VITIS/settings64.sh

# VCS : always generate verdi db
export SNPS_VCS_UFE_KDB=1

echo "#################################################"
echo "# setup.sh"
echo "# Export global variables:"
echo "#################################################"
echo "  PROJECT_DIR=$PROJECT_DIR"
echo "  PROJECT_SIMU_TOOL=$PROJECT_SIMU_TOOL"
echo "  PROJECT_SYN_TOOL=$PROJECT_SYN_TOOL"
echo "  PROJECT_TOP_SYN_TOOL=$PROJECT_TOP_SYN_TOOL"
echo "  XILINX_VIVADO=$XILINX_VIVADO"
echo "  XILINX_VITIS=$XILINX_VITIS"
echo "  VITIS_TARGET=$VITIS_TARGET"
echo "  MICROBLAZE_CONF=$MICROBLAZE_CONF"
echo "  TV_HW_VERSION=${TV_HW_VERSION}"
echo "  GTV_VERSION=${GTV_VERSION}"
echo "  TFHERS_VERSION=${TFHERS_VERSION}"
echo "  SNPS_VCS_UFE_KDB=${SNPS_VCS_UFE_KDB}"
echo -e "$export_str"

# Check external resources are available
# TODO

# alias
alias run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py
echo "#################################################"
echo "# Create alias"
echo "#################################################"
echo "  run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py"

# link
rm -f ${PROJECT_DIR}/sw/bin/tv_hw/latest
ln -s ${PROJECT_DIR}/sw/bin/tv_hw/${TV_HW_VERSION} ${PROJECT_DIR}/sw/bin/tv_hw/latest
rm -f ${PROJECT_DIR}/sw/bin/gtv/latest
ln -s ${PROJECT_DIR}/sw/bin/gtv/${GTV_VERSION} ${PROJECT_DIR}/sw/bin/gtv/latest
rm -f ${PROJECT_DIR}/sw/bin/tfhe-rs/latest
ln -s ${PROJECT_DIR}/sw/bin/tfhe-rs/${TFHERS_VERSION} ${PROJECT_DIR}/sw/bin/tfhe-rs/latest
echo "#################################################"
echo "# Create link"
echo "#################################################"
echo "  ln -s ${PROJECT_DIR}/sw/bin/tv_hw/${TV_HW_VERSION} ${PROJECT_DIR}/sw/bin/tv_hw/latest"
echo "  ln -s ${PROJECT_DIR}/sw/bin/gtv/${GTV_VERSION} ${PROJECT_DIR}/sw/bin/gtv/latest"
echo "  ln -s ${PROJECT_DIR}/sw/bin/tfhe-rs/${TFHERS_VERSION} ${PROJECT_DIR}/sw/bin/tfhe-rs/latest"
