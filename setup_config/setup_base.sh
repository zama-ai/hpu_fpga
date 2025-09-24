#
# Setup for Versal flow
#

# Targeted board and FPGA
export PROJECT_TARGET=xcv80
export XILINX_PART=xcv80-lsva4737-2MHP-e-S
export SHELL_VER=hpu_plug

# Tool version
export XILINX_TOOL_VERSION=2025.1
export SNPS_TOOL_VERSION=V-2023.12-SP2

echo "#################################################"
echo "# setup_base.sh"
echo "# Export global variables:"
echo "#################################################"
echo "  PROJECT_TARGET=$PROJECT_TARGET"
echo "  XILINX_PART=$XILINX_PART"
echo "  XILINX_TOOL_VERSION=$XILINX_TOOL_VERSION"
echo "  SHELL_VER=$SHELL_VER"
echo "  SNPS_TOOL_VERSION=$SNPS_TOOL_VERSION"
