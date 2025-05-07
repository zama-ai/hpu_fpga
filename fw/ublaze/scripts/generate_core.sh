#!/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# Exit on first error

set -e

echo "------------------------------------------------------------------------------------------------"
echo "  Environment"
echo " -----------------------------------------------------------------------------------------------"
CURRENTDIR=$PWD

WORK_DIR=${PROJECT_DIR}/fw/gen/${MICROBLAZE_CONF}
SCRIPT_DIR=${PROJECT_DIR}/fw/ublaze/scripts
CONF_DIR=${PROJECT_DIR}/fw/ublaze/core_config/${MICROBLAZE_CONF}
RTL_DIR=${WORK_DIR}/rtl
SIMU_DIR=${WORK_DIR}/simu
UBLAZE_DIR=${WORK_DIR}/ip_${MICROBLAZE_CONF}
BSP_DIR=${UBLAZE_DIR}/bsp
SHELL_DIR=${UBLAZE_DIR}/shell
PRJ_DIR=${UBLAZE_DIR}/prj

# Vivado x Vitis project
if [ ! -d ${WORK_DIR} ]
then
    echo "  > Directory corresponding to the microblaze configuration doesn't exist"
    echo "      - Creating directory ..."
    mkdir -p ${WORK_DIR}
else
    echo "  > Directory corresponding to the microblaze configuration already exists" 
    echo "      - Deleting and re-creating it"
    rm -rf ${WORK_DIR}
    mkdir ${WORK_DIR}
fi

mkdir -p ${WORK_DIR}/info
mkdir -p ${BSP_DIR}
mkdir -p ${SHELL_DIR}
mkdir -p ${PRJ_DIR}

echo ""
echo " -----------------------------------------------------------------------------------------------"
echo "  Vivado : Generation of the shell archive"
echo " -----------------------------------------------------------------------------------------------"
cd ${PRJ_DIR}
# The scripts have been written with vivado 2024.1 for xcu55c-fsvh2892-2L-e. They are not compatible v80 target.
#vivado -mode batch -source ${SCRIPT_DIR}/setup_project.tcl -nojournal
echo "INFO > Using ${XILINX_VIVADO}/bin/vivado on xcu55c-fsvh2892-2L-e to generate the ublaze"
${XILINX_VIVADO}/bin/vivado -mode batch -source ${SCRIPT_DIR}/setup_project.tcl -nojournal -tclargs "xcu55c-fsvh2892-2L-e"

# Back to working dir
# cd ${WORK_DIR}

# We need to move some files/directory in order to reuse them
#  - xsa
mv -b ${PRJ_DIR}/ublaze_wrapper.xsa ${SHELL_DIR}
#  - smi
mv -b ${PRJ_DIR}/project_microblaze.ip_user_files/sim_scripts/ublaze/xsim/project_microblaze.smi ${SHELL_DIR}
#  - HDL sources
mv -b ${PRJ_DIR}/project_microblaze.srcs/sources_1/bd/ublaze/ip ${RTL_DIR}
#  - wrapper
mv -b ${PRJ_DIR}/project_microblaze.gen/sources_1/bd/ublaze/hdl/ublaze_wrapper.v ${RTL_DIR}
#  - Microblaze IP
mv -b ${PRJ_DIR}/project_microblaze.gen/sources_1/bd/ublaze/synth/ublaze.v ${RTL_DIR}
echo ""

echo " -----------------------------------------------------------------------------------------------"
echo "  Vitis : Generation of the board support package"
echo " -----------------------------------------------------------------------------------------------"
cd ${PRJ_DIR}
xsct ${SCRIPT_DIR}/xsct_script.tcl

# We need to move the board support package
#  - bsp/include
mv -b ${PRJ_DIR}/fw_platform/ublaze_0/fw_domain/bsp/ublaze_0/include ${BSP_DIR}
#  - bsp/lib
mv -b ${PRJ_DIR}/fw_platform/ublaze_0/fw_domain/bsp/ublaze_0/lib ${BSP_DIR}

# cd ${PROJECT_DIR}

# Sed the output path for xilinx core instances that we just created
#   without it we would generate output files outside this directory. 
find ${RTL_DIR}/ -type f -name '*.xci' -exec sed -i 's/RUNTIME_PARAM.OUTPUTDIR">..\/..\/..\/..\/..\/..\//RUNTIME_PARAM.OUTPUTDIR">..\/..\/..\/..\/output\/vivado\//' {} \;

# Let's change memory file path 
find ${PRJ_DIR} -type f -name 'ublaze_lmb_bram_0.v' -exec sed -i "s|ublaze_lmb_bram_0.mem|input/micro_code/ublaze_lmb_bram_0.mem|g" {} \;

# We need to add full path in order to include axi_infrastructure verilog header
AXI_INF_PATH=$(find ${WORK_DIR} -name "axi_infrastructure_v1_1_0.vh")
find ${PRJ_DIR} -type f -name "axi_register_slice_v2_1_vl_rfs.v" -exec sed -i "s|axi_infrastructure_v1_1_0.vh|$AXI_INF_PATH|g" {} \;

echo ""
echo " -----------------------------------------------------------------------------------------------"
echo "  Export Simulation files"
echo " -----------------------------------------------------------------------------------------------"
if [ -d ${CONF_DIR}/simu ]
then
    # Copy file from configuration template inside the generated IP to expose
    # consistent ip interface to the user
    cp -r $CONF_DIR/simu ${SIMU_DIR}
    # Create info folder for correct template expansion
fi

mkdir -p ${SIMU_DIR}/info

# Then let's Launch parser : must be launched with relative path
cd ${PROJECT_DIR}
python3 ${SCRIPT_DIR}/parser.py

cd ${CURRENTDIR}
