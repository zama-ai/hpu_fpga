#!/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : MHDMA Bitstream Validation — runs all bring-up scripts in sequence
# ==============================================================================================
# Usage: ./mhdma_validate.sh -n <2|4|8>
#
# Boards are always 0..N-1.
# Scripts that only support 2 FPGAs (mhdma_read_requests.sh) will use boards 0 & 1.
#
# The script stops on the first failure.
# ==============================================================================================

set -e
trap 'kill $(jobs -p) 2>/dev/null; exit 1' SIGINT SIGTERM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

###############################################################################
# USAGE
###############################################################################
usage() {
    echo "Usage: $0 -n <2|4|8>"
    echo ""
    echo "  Bitstream validation script"
    echo ""
    echo "  -n, --num-fpgas NUM    Number of FPGAs to validate (2, 4, or 8)"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "  Boards are always 0..N-1."
    echo "  Scripts that only support 2 FPGAs will use boards 0 & 1."
    echo ""
    echo "Examples:"
    echo "  $0 -n 2    # Validate with 2 FPGAs (boards 0-1)"
    echo "  $0 -n 4    # Validate with 4 FPGAs (boards 0-3)"
    echo "  $0 -n 8    # Validate with 8 FPGAs (boards 0-7)"
    exit 1
}

###############################################################################
# PARSE ARGUMENTS
###############################################################################
NUM_FPGAS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--num-fpgas)
            NUM_FPGAS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "[ERROR] Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$NUM_FPGAS" ]; then
    echo "[ERROR] -n <2|4|8> is required"
    usage
fi

if [[ ! "$NUM_FPGAS" =~ ^(2|4|8)$ ]]; then
    echo "[ERROR] Number of FPGAs must be 2, 4, or 8 (got $NUM_FPGAS)"
    usage
fi

echo "=================================================================================================="
echo "  MHDMA Bitstream Validation"
echo "=================================================================================================="
echo "  Boards:    0..$((NUM_FPGAS - 1))"
echo "  Count:     $NUM_FPGAS"
echo "=================================================================================================="

###############################################################################
# HELPERS
###############################################################################
STEP=0
TOTAL_STEPS=7

AMI_SYSFS_BASE="/sys/bus/pci/drivers/ami"

run_step() {
    local name="$1"
    shift
    STEP=$((STEP + 1))
    echo ""
    echo "################################################################################"
    echo "  Step $STEP/$TOTAL_STEPS: $name"
    echo "################################################################################"
    echo "  Command: $*"
    echo ""
    if "$@"; then
        echo ""
        echo "  [PASS] Step $STEP/$TOTAL_STEPS: $name"
    else
        echo ""
        echo "  [FAIL] Step $STEP/$TOTAL_STEPS: $name"
        echo "  Aborting validation."
        exit 1
    fi
}

###############################################################################
# SOURCE BOARD CONFIGURATION
###############################################################################
source /etc/profile.d/v80_pcie_dev.sh

# Resolve the sysfs BDF path for a given board index.
# V80_BOARDS_MAP[b,pcie_id] holds the PCIe bus number (e.g. "01", "a1").
# We glob for a matching AMI sysfs entry: 0000:<bus>:*.*/logic_uuid
get_board_sysfs() {
    local board=$1
    local pcie_id=${V80_BOARDS_MAP[$board,pcie_id]}
    local match
    match=$(ls -d ${AMI_SYSFS_BASE}/0000:${pcie_id}:* 2>/dev/null | head -1)
    if [ -z "$match" ]; then
        echo ""
    else
        echo "$match"
    fi
}

###############################################################################
# VALIDATION SEQUENCE
###############################################################################

# Step 1: Verify all boards carry the same bitstream (logic_uuid)
run_step "Bitstream UUID check ($NUM_FPGAS boards)" bash -c '
    AMI_SYSFS_BASE="'"$AMI_SYSFS_BASE"'"
    NUM_FPGAS='"$NUM_FPGAS"'
    source /etc/profile.d/v80_pcie_dev.sh

    ref_uuid=""
    ref_board=""
    all_match=true

    for ((b=0; b<NUM_FPGAS; b++)); do
        pcie_id=${V80_BOARDS_MAP[$b,pcie_id]}
        sysfs_dir=$(ls -d ${AMI_SYSFS_BASE}/0000:${pcie_id}:* 2>/dev/null | head -1)

        if [ -z "$sysfs_dir" ]; then
            echo "  [ERROR] Board $b (PCIe bus $pcie_id): no AMI sysfs entry found"
            exit 1
        fi

        uuid_file="${sysfs_dir}/logic_uuid"
        if [ ! -r "$uuid_file" ]; then
            echo "  [ERROR] Board $b (PCIe bus $pcie_id): cannot read $uuid_file"
            exit 1
        fi

        uuid=$(cat "$uuid_file")
        echo "  Board $b (PCIe bus $pcie_id): logic_uuid=$uuid"

        if [ -z "$ref_uuid" ]; then
            ref_uuid="$uuid"
            ref_board=$b
        elif [ "$uuid" != "$ref_uuid" ]; then
            echo "  [FAIL] Board $b UUID ($uuid) != Board $ref_board UUID ($ref_uuid)"
            all_match=false
        fi
    done

    if ! $all_match; then
        echo "  [ERROR] Bitstream mismatch — not all boards have the same logic_uuid"
        exit 1
    fi

    echo "  [OK] All $NUM_FPGAS boards share logic_uuid=$ref_uuid"
'

# Step 2: Setup — configure MAC addresses, timeouts, HBM addresses
run_step "Setup (configure $NUM_FPGAS FPGAs)" \
    "$SCRIPT_DIR/mhdma_setup.sh" -n "$NUM_FPGAS"

# Step 3: Ring notify — card i notifies card (i+1)%N
run_step "Ring Notify ($NUM_FPGAS cards)" \
    "$SCRIPT_DIR/mhdma_notify.sh" "$NUM_FPGAS"

# Step 4: Ping notify — each card notifies all other cards
run_step "Ping Notify ($NUM_FPGAS cards)" \
    "$SCRIPT_DIR/mhdma_notify_ping.sh" "$NUM_FPGAS"

# Step 5: Flood notify — all cards flood one random target
run_step "Flood Notify ($NUM_FPGAS cards)" \
    "$SCRIPT_DIR/mhdma_notify_flood.sh" "$NUM_FPGAS"

# Step 6: Read requests (2-FPGA only) — always uses boards 0 & 1
run_step "Read Requests (2 FPGAs only: boards 0 & 1)" \
    "$SCRIPT_DIR/mhdma_read_requests.sh"

# Step 7: Parallel read requests — ring topology with all cards
run_step "Parallel Read Requests ($NUM_FPGAS cards, ring)" \
    "$SCRIPT_DIR/mhdma_read_request_parallel.sh" -n "$NUM_FPGAS"

###############################################################################
# FINAL RESULT
###############################################################################
echo ""
echo "################################################################################"
echo "  VALIDATION COMPLETE — ALL $TOTAL_STEPS/$TOTAL_STEPS STEPS PASSED"
echo "################################################################################"
exit 0
