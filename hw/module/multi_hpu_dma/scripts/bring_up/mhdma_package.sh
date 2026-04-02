#!/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : MHDMA Debug Package
# ==============================================================================================
# This file contains debugging functions for the Multi-HPU DMA module.
# Source this file to make all functions available:
#   source mhdma_debug.sh
#
# Prerequisites:
#   - $hputil must be set to the hputil binary path
#   - V80_BOARDS_MAP, V80_BOARDS_NB defined (/etc/profile.d/v80_pcie_dev.sh)
#
# Usage: mhdma_help for list of all functions
# ==============================================================================

# ==============================================================================
# HARDWARE CONSTANTS (from pem_common_param_pkg.sv / mhdma_pkg.sv)
# ==============================================================================
# Production params: N=2048, GLWE_K=1, MOD_Q_W=64, AXI4_DATA_W=512, PEM_PC=2
CT_MEM_BYTES=12288          # 0x3000 — page-aligned CT stride
PC0_DATA_SIZE=8224          # 0x2040 = 129 AXI4 words * 64 bytes (AXI4_WORD_PER_PC0)
PC1_DATA_SIZE=8192          # 0x2000 = 128 AXI4 words * 64 bytes (AXI4_WORD_PER_PC)
PC0_ADDR=0x4400000000       # HBM base address for PC0
PC1_ADDR=0x4420000000       # HBM base address for PC1
HBM_PC_RANGE=0x40000000     # 1GB per PC
# Conservative max logical CT address (~half of theoretical max 0x15555)
HW_MAX_ADDR=0xAAAA

# req_id opcodes (mhdma_pkg.sv)
REQ_ID_NOTIFY=2
REQ_ID_NOTIFY_ACK=3
REQ_ID_READ=6
REQ_ID_EMISSION=7

# req_id register layout: iop_id[31:24] req_id[23:20] node_id[19:16] mode[15:14] flag[13:8] rsvd[7:0]
# req_addr register layout: dst_addr[31:16] src_addr[15:0]
build_req_id() {
    local opcode=$1 node=$2 mode=$3 flag=${4:-0} iop=${5:-0}
    printf "0x%08x" $(( (iop << 24) | (opcode << 20) | (node << 16) | (mode << 14) | (flag << 8) ))
}

# ==============================================================================
# BOARD UTILITIES
# ==============================================================================

# Check if a board is valid (not "x")
_mhdma_board_valid() {
  local board=$1
  [ "${V80_BOARDS_MAP[$board,pcie_id]}" != "x" ]
}

# Parse hputil output to extract just the value
# Input format: "@00050010 -> 00000000" or just "0x00000000"
# Output: the hex value (e.g., "00000000")
_mhdma_parse_value() {
  local raw="$1"
  local val
  # If output contains "->", extract the value after it
  if [[ "$raw" == *"->"* ]]; then
    val=$(echo "$raw" | awk -F'->' '{print $2}' | tr -d ' \t\n\r')
  else
    val=$(echo "$raw" | tr -d ' \t\n\r')
  fi
  # Return "0" if empty, otherwise return the value
  echo "${val:-0}"
}

# Get list of valid board indices
_mhdma_get_valid_boards() {
  local valid_boards=()
  for ((b=0; b<V80_BOARDS_NB; b++)); do
    if _mhdma_board_valid $b; then
      valid_boards+=($b)
    fi
  done
  echo "${valid_boards[@]}"
}

# ==============================================================================
# STATISTICS FUNCTIONS
# ==============================================================================

# Show all statistics counters for a given board
# Usage: mhdma_stats [board_idx]
mhdma_stats() {
  local board=${1:-0}
  if ! _mhdma_board_valid $board; then
    echo "[ERROR] Board $board is not valid (pcie_id=x)"
    return 1
  fi
  echo "=== MHDMA Statistics (Board $board, PCIe: ${V80_BOARDS_MAP[$board,pcie_id]}) ==="
  echo ""
  echo "--- Notify Statistics ---"
  echo "  Notify sent:              $($hputil -f $board register read mhdma_request::stat_notify)"
  echo "  Notify ACK received:      $($hputil -f $board register read mhdma_request::stat_notify_ack)"
  echo "  Notify timeout retries:   $($hputil -f $board register read mhdma_request::stat_notify_timeout_retry)"
  echo "  Notify timeouts:          $($hputil -f $board register read mhdma_request::stat_notify_timeout)"
  echo "  Notify received:          $($hputil -f $board register read mhdma_request::stat_nb_notify_received)"
  echo "  Notify ACK (nack) recv:   $($hputil -f $board register read mhdma_request::stat_nb_nack_received)"
  echo ""
  echo "--- Read Request Statistics ---"
  echo "  Read req timeout retries: $($hputil -f $board register read mhdma_request::stat_read_req_timeout_retry)"
  echo "  Read req received:        $($hputil -f $board register read mhdma_request::stat_nb_read_req_received)"
  echo ""
  echo "--- Ciphertext Statistics ---"
  echo "  CE received:              $($hputil -f $board register read mhdma_request::stat_nb_ce_received)"
  echo "  CE words received:        $($hputil -f $board register read mhdma_request::stat_nb_ce_words_received)"
  echo ""
  echo "--- HBM Statistics ---"
  echo "  HBM reads:                $($hputil -f $board register read mhdma_request::stat_nb_read_to_hbm)"
  echo "  Words received PC0:       $($hputil -f $board register read mhdma_request::stat_nb_words_received_pc_pc0)"
  echo "  Words received PC1:       $($hputil -f $board register read mhdma_request::stat_nb_words_received_pc_pc1)"
  echo "  Write complete count:     $($hputil -f $board register read mhdma_request::stat_cnt_nb_write_complete)"
}

# Show statistics for all valid boards
# Usage: mhdma_stats_all
mhdma_stats_all() {
  for board in $(_mhdma_get_valid_boards); do
    mhdma_stats $board
    echo ""
  done
}

# Show timing statistics
# Usage: mhdma_timing [board_idx]
mhdma_timing() {
  local board=${1:-0}
  if ! _mhdma_board_valid $board; then
    echo "[ERROR] Board $board is not valid"
    return 1
  fi
  echo "=== MHDMA Timing Statistics (Board $board, PCIe: ${V80_BOARDS_MAP[$board,pcie_id]}) ==="
  echo ""
  echo "  Notify to ACK:            $($hputil -f $board register read mhdma_request::stat_t_notify_to_ack) cycles"
  echo "  RR to CE received:        $($hputil -f $board register read mhdma_request::stat_t_rr_to_ce_received) cycles"
  echo "  CE first to last pkt:     $($hputil -f $board register read mhdma_request::stat_t_ce_first_to_last_pkt) cycles"
  echo "  RR wait words PC0:        $($hputil -f $board register read mhdma_request::stat_t_rr_wait_words_pc_pc0) cycles"
  echo "  RR wait words PC1:        $($hputil -f $board register read mhdma_request::stat_t_rr_wait_words_pc_pc1) cycles"
}

# Reset statistics counters (by reading them - ReadNotify behavior)
# Usage: mhdma_reset_stats [board_idx]
mhdma_reset_stats() {
  local board=${1:-0}
  if ! _mhdma_board_valid $board; then
    echo "[ERROR] Board $board is not valid"
    return 1
  fi
  echo "=== Resetting MHDMA Statistics (Board $board) ==="
  $hputil -f $board register read mhdma_request::stat_notify > /dev/null
  $hputil -f $board register read mhdma_request::stat_notify_ack > /dev/null
  $hputil -f $board register read mhdma_request::stat_notify_timeout_retry > /dev/null
  $hputil -f $board register read mhdma_request::stat_read_req_timeout_retry > /dev/null
  $hputil -f $board register read mhdma_request::stat_nb_nack_received > /dev/null
  $hputil -f $board register read mhdma_request::stat_nb_notify_received > /dev/null
  $hputil -f $board register read mhdma_request::stat_nb_read_req_received > /dev/null
  $hputil -f $board register read mhdma_request::stat_nb_ce_received > /dev/null
  $hputil -f $board register read mhdma_request::stat_nb_read_to_hbm > /dev/null
  $hputil -f $board register read mhdma_request::stat_nb_words_received_pc_pc0 > /dev/null
  $hputil -f $board register read mhdma_request::stat_nb_words_received_pc_pc1 > /dev/null
  $hputil -f $board register read mhdma_request::stat_nb_ce_words_received > /dev/null
  $hputil -f $board register read mhdma_request::stat_notify_timeout > /dev/null
  echo "Statistics reset complete"
}

# Reset statistics on all valid boards
# Usage: mhdma_reset_stats_all
mhdma_reset_stats_all() {
  for board in $(_mhdma_get_valid_boards); do
    mhdma_reset_stats $board
  done
}

# Usage: hpu_soft_reset [board_idx]
hpu_soft_reset() {
  local board=${1:-0}
  if ! _mhdma_board_valid $board; then
    echo "[ERROR] Board $board is not valid"
    return 1
  fi
  echo "=== HPU soft reset (Board $board, PCIe: ${V80_BOARDS_MAP[$board,pcie_id]}) ==="
  echo ""
  $hputil -f $board register write hpu_reset::trigger --value 0xFFFFFFFF
  $hputil -f $board register read hpu_reset::trigger
}

# ==============================================================================
# ERROR AND STATUS FUNCTIONS
# ==============================================================================

# Show error register and decode bits
# Usage: mhdma_errors [board_idx]
mhdma_errors() {
  local board=${1:-0}
  if ! _mhdma_board_valid $board; then
    echo "[ERROR] Board $board is not valid"
    return 1
  fi
  local raw_errors=$($hputil -f $board register read mhdma_system::errors)
  local errors=$(_mhdma_parse_value "$raw_errors")
  echo "=== MHDMA Errors (Board $board, PCIe: ${V80_BOARDS_MAP[$board,pcie_id]}) ==="
  echo "  Raw error register: $errors"
}

# Show FSM state
# Usage: mhdma_fsm_state [board_idx]
mhdma_fsm_state() {
  local board=${1:-0}
  if ! _mhdma_board_valid $board; then
    echo "[ERROR] Board $board is not valid"
    return 1
  fi
  local raw_fsm=$($hputil -f $board register read mhdma_system::fsm_value)
  local fsm=$(_mhdma_parse_value "$raw_fsm")
  echo "=== MHDMA FSM State (Board $board) ==="
  echo "  FSM value: $fsm"
}

# Show overall status summary
# Usage: mhdma_status [board_idx]
mhdma_status() {
  local board=${1:-0}
  if ! _mhdma_board_valid $board; then
    echo "[ERROR] Board $board is not valid"
    return 1
  fi
  echo "============================================================"
  echo "=== MHDMA Status (Board $board, PCIe: ${V80_BOARDS_MAP[$board,pcie_id]}, S/N: ${V80_BOARDS_MAP[$board,serial_number]}) ==="
  echo "============================================================"
  echo ""
  mhdma_fsm_state $board
  echo ""
  mhdma_errors $board
  echo ""
  echo "--- Pending Requests ---"
  echo "  Notify register:       $($hputil -f $board register read mhdma_request::notify)"
  echo "  Read request register: $($hputil -f $board register read mhdma_request::read_request)"
  echo ""
  echo "--- Physical Addresses ---"
  echo "  PC0 addr LSB: $($hputil -f $board register read mhdma_request::stat_physical_addr_pc0_lsb)"
  echo "  PC0 addr MSB: $($hputil -f $board register read mhdma_request::stat_physical_addr_pc0_msb)"
  echo "  PC1 addr LSB: $($hputil -f $board register read mhdma_request::stat_physical_addr_pc1_lsb)"
  echo "  PC1 addr MSB: $($hputil -f $board register read mhdma_request::stat_physical_addr_pc1_msb)"
}

# Show status for all valid boards
# Usage: mhdma_status_all
mhdma_status_all() {
  for board in $(_mhdma_get_valid_boards); do
    mhdma_status $board
    echo ""
  done
}

# ==============================================================================
# CONFIGURATION FUNCTIONS
# ==============================================================================

# Show current HPU IDs configuration
# Usage: mhdma_show_hpu_ids [board_idx]
mhdma_show_hpu_ids() {
  local board=${1:-0}
  if ! _mhdma_board_valid $board; then
    echo "[ERROR] Board $board is not valid"
    return 1
  fi
  echo "=== HPU IDs (Board $board) ==="
  echo "  HPU 0: $($hputil -f $board register read mhdma_system::hpu_id_0)"
  echo "  HPU 1: $($hputil -f $board register read mhdma_system::hpu_id_1)"
  echo "  HPU 2: $($hputil -f $board register read mhdma_system::hpu_id_2)"
  echo "  HPU 3: $($hputil -f $board register read mhdma_system::hpu_id_3)"
  echo "  HPU 4: $($hputil -f $board register read mhdma_system::hpu_id_4)"
  echo "  HPU 5: $($hputil -f $board register read mhdma_system::hpu_id_5)"
  echo "  HPU 6: $($hputil -f $board register read mhdma_system::hpu_id_6)"
  echo "  HPU 7: $($hputil -f $board register read mhdma_system::hpu_id_7)"
}

# Show all configuration
# Usage: mhdma_show_config [board_idx]
mhdma_show_config() {
  local board=${1:-0}
  if ! _mhdma_board_valid $board; then
    echo "[ERROR] Board $board is not valid"
    return 1
  fi
  echo "=== MHDMA Configuration (Board $board, PCIe: ${V80_BOARDS_MAP[$board,pcie_id]}) ==="
  echo ""
  echo "--- System Settings ---"
  echo "  Lane config:          $($hputil -f $board register read mhdma_system::lane)"
  echo "  Timeout notify:       $($hputil -f $board register read mhdma_system::timeout_notify)"
  echo "  Timeout read req:     $($hputil -f $board register read mhdma_system::timeout_read_req)"
  echo ""
  echo "--- HBM Addresses ---"
  echo "  CT PC0 LSB: $($hputil -f $board register read mhdma_hbm_axi4_addr_2in3::ct_pc0_lsb)"
  echo "  CT PC0 MSB: $($hputil -f $board register read mhdma_hbm_axi4_addr_2in3::ct_pc0_msb)"
  echo "  CT PC1 LSB: $($hputil -f $board register read mhdma_hbm_axi4_addr_2in3::ct_pc1_lsb)"
  echo "  CT PC1 MSB: $($hputil -f $board register read mhdma_hbm_axi4_addr_2in3::ct_pc1_msb)"
  echo ""
  mhdma_show_hpu_ids $board
}

# ==============================================================================
# DEBUGGING FUNCTIONS
# ==============================================================================
# Dump all registers for debugging
# Usage: mhdma_dump [board_idx]
mhdma_dump() {
  local board=${1:-0}
  if ! _mhdma_board_valid $board; then
    echo "[ERROR] Board $board is not valid"
    return 1
  fi
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local outfile="mhdma_dump_board${board}_pcie${V80_BOARDS_MAP[$board,pcie_id]}_${timestamp}.log"

  echo "=== MHDMA Register Dump (Board $board) ===" | tee $outfile
  echo "Timestamp: $(date)" | tee -a $outfile
  echo "PCIe ID: ${V80_BOARDS_MAP[$board,pcie_id]}" | tee -a $outfile
  echo "Serial: ${V80_BOARDS_MAP[$board,serial_number]}" | tee -a $outfile
  echo "" | tee -a $outfile

  mhdma_show_config $board | tee -a $outfile
  echo "" | tee -a $outfile
  mhdma_status $board | tee -a $outfile
  echo "" | tee -a $outfile
  mhdma_stats $board | tee -a $outfile
  echo "" | tee -a $outfile
  mhdma_timing $board | tee -a $outfile

  echo "" | tee -a $outfile
  echo "Dump saved to: $outfile"
}

# Dump all valid boards
# Usage: mhdma_dump_all
mhdma_dump_all() {
  for board in $(_mhdma_get_valid_boards); do
    mhdma_dump $board
    echo ""
  done
}

# ==============================================================================
# BOARD LISTING
# ==============================================================================

# List all boards with their status
# Usage: mhdma_list_boards
mhdma_list_boards() {
  echo "=== V80 Boards Configuration ==="
  echo ""
  for ((b=0; b<V80_BOARDS_NB; b++)); do
    local pcie="${V80_BOARDS_MAP[$b,pcie_id]}"
    local serial="${V80_BOARDS_MAP[$b,serial_number]}"
    if [ "$pcie" = "x" ]; then
      echo "  Board $b: [NOT CONFIGURED]"
    else
      echo "  Board $b: PCIe=$pcie, Serial=$serial"
    fi
  done
  echo ""
  echo "Valid boards: $(_mhdma_get_valid_boards)"
}

# ==============================================================================
# HELP FUNCTION
# ==============================================================================

mhdma_help() {
  local valid="$(_mhdma_get_valid_boards)"
  cat <<'EOF'
================================================================================
                           MHDMA Debug Package
================================================================================

BOARD MANAGEMENT
  mhdma_list_boards              List all boards and their configuration

STATISTICS
  mhdma_stats [board]            Show all statistics counters
  mhdma_stats_all                Show statistics for all valid boards
  mhdma_timing [board]           Show timing statistics (cycles)
  mhdma_reset_stats [board]      Reset all statistics counters
  mhdma_reset_stats_all          Reset statistics on all valid boards

STATUS & ERRORS
  mhdma_status [board]           Show overall status summary
  mhdma_status_all               Show status for all valid boards
  mhdma_errors [board]           Show and decode error register
  mhdma_fsm_state [board]        Show current FSM state

CONFIGURATION
  mhdma_show_config [board]      Show all configuration settings
  mhdma_show_hpu_ids [board]     Show HPU ID assignments

DEBUGGING
  mhdma_dump [board]             Dump all registers to timestamped file
  mhdma_dump_all                 Dump registers for all valid boards

--------------------------------------------------------------------------------
Arguments:
  [board]   Board index (default: 0)

EOF
  echo "Valid boards: ${valid:-none}"
  echo ""
}

# ==============================================================================
# PACKAGE LOAD MESSAGE
# ==============================================================================
echo "[INFO] MHDMA debug package loaded. Run 'mhdma_help' for available commands."
