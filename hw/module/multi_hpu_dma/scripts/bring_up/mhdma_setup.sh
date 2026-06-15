#!/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Configure FPGA MAC addresses, timeouts and HBM addresses
# ==============================================================================================
# Usage: ./mhdma_setup.sh -n <2|4|8> [-l] [-h]

trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM

###############################################################################
# SOURCE BOARD CONFIGURATION
###############################################################################
source /etc/profile.d/v80_pcie_dev.sh
source "$(dirname "$0")/mhdma_package.sh"

###############################################################################
# UTILITY FUNCTIONS
###############################################################################

# Get MAC value for a given FPGA and HPU ID
# Format: [31] local bit | [30:24] index | [23:0] board mac_address
# For the current FPGA, set bit 31 (0x80000000)
# Args: $1=fpga_index, $2=hpu_slot_index
get_mac_value() {
  local fpga_idx=$1
  local slot_idx=$2

  # Get base MAC address for this slot's board (lower 24 bits)
  local base_mac=${V80_BOARDS_MAP[$slot_idx,mac_address]}
  local mac_int=$((base_mac))

  # If this slot matches the FPGA index, set the "local" bit (bit 31)
  if [ "$fpga_idx" -eq "$slot_idx" ]; then
    mac_int=$((mac_int | 0x80000000))
  fi

  printf "0x%08X" $mac_int
}

# Configure a single FPGA
# Args: $1=board_index (index into V80_BOARDS_MAP)
configure_fpga() {
  local board_idx=$1
  local pcie_id=${V80_BOARDS_MAP[$board_idx,pcie_id]}

  echo "[INFO] Configuring board $board_idx (PCIe: $pcie_id)..."

  # Write MAC addresses for all HPU ID slots
  for ((slot=0; slot<8; slot++)); do
    local mac_value=$(get_mac_value $board_idx $slot)
    mhdma_reg_write $board_idx mhdma_system::hpu_id_$slot $mac_value
  done

  # Write timeout values
  mhdma_reg_write $board_idx mhdma_system::timeout_notify 0xFFFFFFFF
  mhdma_reg_write $board_idx mhdma_system::timeout_read_req 0xFFFFFFFF

  # Write HBM AXI4 addresses
  mhdma_reg_write $board_idx mhdma_hbm_axi4_addr_2in3::ct_pc0_msb 0x00000044
  mhdma_reg_write $board_idx mhdma_hbm_axi4_addr_2in3::ct_pc0_lsb 0x00000000
  mhdma_reg_write $board_idx mhdma_hbm_axi4_addr_2in3::ct_pc1_msb 0x00000044
  mhdma_reg_write $board_idx mhdma_hbm_axi4_addr_2in3::ct_pc1_lsb 0x20000000

  echo "[INFO] Board $board_idx (PCIe: $pcie_id) configured."
}

# Print usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -n, --num-fpgas NUM    Number of FPGAs to configure (2, 4, or 8) [default: 2]"
  echo "  -l, --list-boards      Display configured boards and exit"
  echo "  -h, --help             Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 -n 2                # Configure 2 FPGAs"
  echo "  $0 -n 4                # Configure 4 FPGAs"
  echo "  $0 -n 8                # Configure 8 FPGAs"
}

###############################################################################
# MAIN
###############################################################################

# Default values
NUM_FPGAS=2

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--num-fpgas)
      NUM_FPGAS="$2"
      shift 2
      ;;
    -l|--list-boards)
      echo "Configured V80 Boards:"
      display_v80_board_map
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate NUM_FPGAS
if [[ ! "$NUM_FPGAS" =~ ^(2|4|8)$ ]]; then
  echo "[ERROR] Number of FPGAs must be 2, 4, or 8"
  exit 1
fi

# Check ami_tool
if ! mhdma_check_ami; then
  exit 1
fi
echo "[INFO] Using ami_tool at $(command -v "$MHDMA_AMI_TOOL")"

# Validate that required boards are configured
for ((b=0; b<NUM_FPGAS; b++)); do
  if [ "${V80_BOARDS_MAP[$b,pcie_id]}" = "x" ]; then
    echo "[ERROR] Board $b is not configured in V80_BOARDS_MAP but is required for $NUM_FPGAS FPGA setup"
    exit 1
  fi
  if [ -z "${V80_BOARDS_MAP[$b,mac_address]}" ]; then
    echo "[ERROR] Board $b has no mac_address configured in V80_BOARDS_MAP"
    exit 1
  fi
done

echo "[INFO] Configuring $NUM_FPGAS FPGAs..."

# Configure FPGAs in parallel
for ((b=0; b<NUM_FPGAS; b++)); do
  (
    configure_fpga $b
  ) &
done

wait
echo "[INFO] All FPGAs configured."

echo "[INFO] Setup complete for $NUM_FPGAS FPGAs."
