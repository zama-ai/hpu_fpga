#!/bin/bash

# Trap SIGINT (Ctrl+C) and kill all child processes
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

  # Add slot index in upper byte [30:24]
  mac_int=$((mac_int | (slot_idx << 24)))

  # If this slot matches the FPGA index, set the "local" bit (bit 31)
  if [ "$fpga_idx" -eq "$slot_idx" ]; then
    mac_int=$((mac_int | 0x80000000))
  fi

  printf "0x%08X" $mac_int
}

# Configure a single FPGA
# Args: $1=fpga_index
configure_fpga() {
  local fpga_idx=$1

  echo "[INFO] Configuring FPGA $fpga_idx (PCIe: ${V80_BOARDS_MAP[$fpga_idx,pcie_id]})..."

  # Write MAC addresses for all HPU ID slots
  for ((slot=0; slot<8; slot++)); do
    local mac_value=$(get_mac_value $fpga_idx $slot)
    $hputil -f $fpga_idx register write mhdma_system::hpu_id_$slot --value $mac_value
  done

  # Write timeout values
  $hputil -f $fpga_idx register write mhdma_system::timeout_notify   --value 0xFFFFFFFF
  $hputil -f $fpga_idx register write mhdma_system::timeout_read_req --value 0xFFFFFFFF

  # Write HBM AXI4 addresses
  $hputil -f $fpga_idx register write mhdma_hbm_axi4_addr_2in3::ct_pc0_msb --value 0x00000046
  $hputil -f $fpga_idx register write mhdma_hbm_axi4_addr_2in3::ct_pc0_lsb --value 0x80000000
  $hputil -f $fpga_idx register write mhdma_hbm_axi4_addr_2in3::ct_pc1_msb --value 0x00000046
  $hputil -f $fpga_idx register write mhdma_hbm_axi4_addr_2in3::ct_pc1_lsb --value 0xA0000000

  echo "[INFO] FPGA $fpga_idx configured."
}

# Setup QDMA queues for a board
# Args: $1=board_index
setup_qdma() {
  local board_idx=$1
  local pcie_id=${V80_BOARDS_MAP[$board_idx,pcie_id]}

  if [ "$pcie_id" = "x" ]; then
    echo "[WARN] Board $board_idx not configured, skipping QDMA setup"
    return 1
  fi

  echo "[INFO] Setting up QDMA for board $board_idx (PCIe ID: $pcie_id)..."

  sudo bash -c "echo 100 > /sys/bus/pci/devices/0000:${pcie_id}:00.1/qdma/qmax"
  dma-ctl qdma${pcie_id}001 q add idx 1 dir h2c
  dma-ctl qdma${pcie_id}001 q start idx 1 dir h2c
  dma-ctl qdma${pcie_id}001 q add idx 2 dir c2h
  dma-ctl qdma${pcie_id}001 q start idx 2 dir c2h

  echo "[INFO] QDMA setup complete for board $board_idx."
}

# Print usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -n, --num-fpgas NUM    Number of FPGAs to configure (2, 4, or 8) [default: 2]"
  echo "  -q, --setup-qdma       Also setup QDMA queues"
  echo "  -l, --list-boards      Display configured boards and exit"
  echo "  -h, --help             Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 -n 2                # Configure 2 FPGAs"
  echo "  $0 -n 4                # Configure 4 FPGAs"
  echo "  $0 -n 8 -q             # Configure 8 FPGAs with QDMA setup"
}

###############################################################################
# MAIN
###############################################################################

# Default values
NUM_FPGAS=2
SETUP_QDMA=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--num-fpgas)
      NUM_FPGAS="$2"
      shift 2
      ;;
    -q|--setup-qdma)
      SETUP_QDMA=1
      shift
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

# Check hputil
if [ -z "$hputil" ]; then
  echo "[FAILURE] You did not export variable for hputil"
  exit 1
else
  echo "[INFO] Using hputil at $hputil"
fi

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

# Setup QDMA if requested
if [ "$SETUP_QDMA" -eq 1 ]; then
  echo "[INFO] Setting up QDMA queues..."
  for ((b=0; b<NUM_FPGAS; b++)); do
    setup_qdma $b &
  done
  wait
  echo "[INFO] QDMA setup complete."
fi

echo "[INFO] Setup complete for $NUM_FPGAS FPGAs."
