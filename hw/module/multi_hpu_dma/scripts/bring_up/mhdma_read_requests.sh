#!/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : MHDMA Read Request Test Script with Random Addresses
# ==============================================================================================
# This script performs multiple read request tests with random source and destination addresses.
# Based on the testbench address space from tb_multi_hpu_dma.sv
#
# Address parameters (from mhdma_pkg.sv):
#   - SRC_ADDR_W = 16 bits (max value: 0xFFFF)
#   - DST_ADDR_W = 16 bits (max value: 0xFFFF)
#   - PC_STRIDE  = 0xB (11 bits), physical_addr = base + (logical_addr << 11)
#
# HBM Alignment requirement:
#   - HBM read addresses must be aligned to 4KB (0x1000) boundaries
#   - Since physical_addr = base + (logical_addr << 11), logical_addr must be EVEN
#     to ensure 4KB alignment: (even_addr << 11) = multiple of 2^12 = 4KB
#
# Usage: ./mhdma_read_requests.sh [OPTIONS]
#   -n, --num-loops     Number of read request loops (default: 10)
#   -m, --max-addr      Maximum logical address (default: 8, must account for alignment)
#   -s, --node-source   Source node ID (default: 24)
#   -r, --node-request  Request node ID (default: 01)
#   -h, --help          Show this help message
# =================================================================================================

set -e

# Trap SIGINT (Ctrl+C) and kill all child processes
trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM

source /etc/profile.d/v80_pcie_dev.sh
source "$(dirname "$0")/mhdma_package.sh"

# =================================================================================================
# Default parameters
# =================================================================================================
NUM_LOOPS=10

# Address space parameters:
HBM_INIT_SIZE=$((HBM_PC_RANGE / 8))       # 128MB subset for test init

NODE_SOURCE=${V80_BOARDS_MAP[1,pcie_id]}
NODE_REQUEST=${V80_BOARDS_MAP[0,pcie_id]}

# Statistics
PASS_COUNT=0
FAIL_COUNT=0

# =================================================================================================
# Parse command line arguments
# =================================================================================================
show_help() {
    echo "MHDMA Read Request Test Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n, --num-loops     Number of read request loops (default: $NUM_LOOPS)"
    echo "  -m, --max-addr      Maximum logical address (default: $HW_MAX_ADDR = 0x$(printf '%x' $HW_MAX_ADDR))"
    echo "  -s, --node-source   Source node ID (default: $NODE_SOURCE)"
    echo "  -r, --node-request  Request node ID (default: $NODE_REQUEST)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Address space info:"
    echo "  - HBM_PC_RANGE = 0x40000000 (1GB per PC)"
    echo "  - CT_MEM_BYTES = 0x3000"
    echo "  - Hardware limit: SRC_ADDR_W = DST_ADDR_W = 16 bits (max 0xFFFF)"
    echo "  - Physical address = base + (logical_addr << PC_STRIDE)"
    echo "  - PC0 data size: 0x2040 bytes (8256)"
    echo "  - PC1 data size: 0x2000 bytes (8192)"
    echo ""
    echo "Alignment:"
    echo "  - HBM addresses must be 4KB aligned"
    echo "  - Logical addresses are automatically forced to even values"
    echo "  - This ensures (logical_addr << 11) is a multiple of 4096"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--num-loops)
            NUM_LOOPS="$2"
            shift 2
            ;;
        -m|--max-addr)
            HW_MAX_ADDR="$2"
            shift 2
            ;;
        -s|--node-source)
            NODE_SOURCE="$2"
            shift 2
            ;;
        -r|--node-request)
            NODE_REQUEST="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo " [ERROR]: Unknown option: $1"
            show_help
            ;;
    esac
done

# =================================================================================================
# Environment check
# =================================================================================================
if ! mhdma_check_ami; then
  exit 1
fi

echo " [INFO]: using ami_tool at $(command -v "$MHDMA_AMI_TOOL")"

setup_check=$(mhdma_reg_read 1 mhdma_system::hpu_id_0)

if [ "$setup_check" == "0x0" ]; then
    echo " [FAILURE]: you did not do the setup"
    exit 1
fi

# =================================================================================================
# Functions
# =================================================================================================

# Generate random address within valid range, aligned to 4KB boundaries
# Uses /dev/urandom for full 32-bit range (bash $RANDOM only gives 0-32767)
# Args: $1 = max_value
generate_random_addr() {
    local max_val=$1
    local rand=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
    local result=$(( rand % $HW_MAX_ADDR ))
    echo $result
}

# Perform a single read request and verify
# Args: $1 = iteration, $2 = src_addr, $3 = dst_addr
perform_read_request() {
    local iter=$1
    local src_addr=$2
    local dst_addr=$3
    local request_addr=$(( ((dst_addr & 0xFFFF) << 16) | (src_addr & 0xFFFF) ))

    echo "--------------------------------------------------------------------------------------------------"
    echo "  Loop $iter: src_addr=0x$(printf '%04x' $src_addr), dst_addr=0x$(printf '%04x' $dst_addr) request raw value : 0x$(printf '%04x' $request_addr)"
    echo "--------------------------------------------------------------------------------------------------"

    # Send read request
    mhdma_reg_write 0 mhdma_request::req_addr $request_addr
    mhdma_reg_write 0 mhdma_request::req_id   "$(build_req_id $REQ_ID_READ 1 1)"

    # Calculate physical addresses
    local src_addr_val=$((src_addr * CT_MEM_BYTES))
    local dst_addr_val=$((dst_addr * CT_MEM_BYTES))
    echo "src_addr_val $src_addr_val"
    echo "dst_addr_val $dst_addr_val"

    ADDR_PC0_SRC=$(printf "0x%x" "$((PC0_ADDR + src_addr_val))")
    ADDR_PC1_SRC=$(printf "0x%x" "$((PC1_ADDR + src_addr_val))")

    ADDR_PC0_DST=$(printf "0x%x" "$((PC0_ADDR + dst_addr_val))")
    ADDR_PC1_DST=$(printf "0x%x" "$((PC1_ADDR + dst_addr_val))")

    echo "ADDR_PC0_SRC $ADDR_PC0_SRC"
    echo "ADDR_PC1_SRC $ADDR_PC1_SRC"
    echo "ADDR_PC0_DST $ADDR_PC0_DST"
    echo "ADDR_PC1_DST $ADDR_PC1_DST"
    echo ""


    # Fetch data from HBM (PC0: 0x2020 bytes, PC1: 0x2000 bytes)
    dma-from-device -d /dev/qdma${NODE_SOURCE}001-MM-2 -s $PC0_DATA_SIZE -a $ADDR_PC0_SRC -o 0x0 -c 1 -f tmp/_hbm_${NODE_SOURCE}_pc0.mem
    dma-from-device -d /dev/qdma${NODE_SOURCE}001-MM-2 -s $PC1_DATA_SIZE -a $ADDR_PC1_SRC -o 0x0 -c 1 -f tmp/_hbm_${NODE_SOURCE}_pc1.mem

    dma-from-device -d /dev/qdma${NODE_REQUEST}001-MM-2 -s $PC0_DATA_SIZE -a $ADDR_PC0_DST -o 0x0 -c 1 -f tmp/_hbm_${NODE_REQUEST}_pc0.mem
    dma-from-device -d /dev/qdma${NODE_REQUEST}001-MM-2 -s $PC1_DATA_SIZE -a $ADDR_PC1_DST -o 0x0 -c 1 -f tmp/_hbm_${NODE_REQUEST}_pc1.mem

    echo ""
    # Wait for transfer completion
     echo "  Waiting for transfer to complete..."
     for ((wait=0; wait<1000; wait++)); do
         rr_status=$(mhdma_reg_read 0 mhdma_request::read_request)
         if [ "$rr_status" != "0x0" ]; then
             echo "  Transfer complete: $rr_status"
             break
         fi
         sleep 0.01
     done

     if [ "$rr_status" == "0x0" ]; then
         echo "  [FAIL]: Transfer timed out"
         return 1
     fi
    # Verify data
    local loop_pass=1
    for pc in 0 1; do
        if cmp -s tmp/_hbm_${NODE_SOURCE}_pc${pc}.mem tmp/_hbm_${NODE_REQUEST}_pc${pc}.mem; then
            echo "  [PASS]: PC${pc} data matches"
        else
            echo "  [FAIL]: PC${pc} data mismatch"
            hexdump -C tmp/_hbm_${NODE_SOURCE}_pc${pc}.mem > tmp/hex_hbm_${NODE_SOURCE}_pc${pc}_iter${iter}.mem
            hexdump -C tmp/_hbm_${NODE_REQUEST}_pc${pc}.mem > tmp/hex_hbm_${NODE_REQUEST}_pc${pc}_iter${iter}.mem
            loop_pass=0
        fi
    done

    return $((1 - loop_pass))
}

# =================================================================================================
# Main execution
# =================================================================================================

echo "=================================================================================================="
echo "  MHDMA Read Request Test"
echo "=================================================================================================="
echo "  Configuration:"
echo "    - Number of loops:  $NUM_LOOPS"
echo "    - Max address:      $HW_MAX_ADDR (0x$(printf '%x' $HW_MAX_ADDR)) [HW limit: 0x$(printf '%x' $HW_MAX_ADDR)]"
echo "    - HBM PC range:     0x$(printf '%x' $HBM_PC_RANGE) (init size: 0x$(printf '%x' $HBM_INIT_SIZE))"
echo "    - stride in bytes   $CT_MEM_BYTES "
echo "    - Node source:      $NODE_SOURCE"
echo "    - Node request:     $NODE_REQUEST"
echo "    - PC0 base:         $PC0_ADDR"
echo "    - PC1 base:         $PC1_ADDR"
echo "    - PC0 data size:    $PC0_DATA_SIZE bytes (0x$(printf '%x' $PC0_DATA_SIZE))"
echo "    - PC1 data size:    $PC1_DATA_SIZE bytes (0x$(printf '%x' $PC1_DATA_SIZE))"
echo "=================================================================================================="


mkdir -p tmp

echo ""
echo "=================================================================================================="
echo "  Starting read request loops"
echo "=================================================================================================="

for ((i=1; i<=NUM_LOOPS; i++)); do

    # Generate random addresses within valid range (4KB aligned)
    src_addr=$(generate_random_addr $HW_MAX_ADDR)
    dst_addr=$(generate_random_addr $HW_MAX_ADDR)

    src_addr_val=$((src_addr * CT_MEM_BYTES))
    ADDR_PC0_SRC=$(printf "0x%x" "$((PC0_ADDR + src_addr_val))")
    ADDR_PC1_SRC=$(printf "0x%x" "$((PC1_ADDR + src_addr_val))")

    echo ""
    echo " Initializing HBM with random data (128MB test range: 0x$(printf '%x' $HBM_INIT_SIZE) bytes)"
    dma-to-device -d /dev/qdma${NODE_SOURCE}001-MM-1 -s $HBM_INIT_SIZE -a $ADDR_PC0_SRC -o 0x0 -c 1 -f /dev/random
    dma-to-device -d /dev/qdma${NODE_SOURCE}001-MM-1 -s $HBM_INIT_SIZE -a $ADDR_PC1_SRC -o 0x0 -c 1 -f /dev/random
    echo ""

    if perform_read_request $i $src_addr $dst_addr; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "=================================================================================================="
echo "  Test Summary"
echo "=================================================================================================="
echo "  Total loops:  $NUM_LOOPS"
echo "  Passed:       $PASS_COUNT"
echo "  Failed:       $FAIL_COUNT"
echo "=================================================================================================="

if [ $FAIL_COUNT -eq 0 ]; then
    echo " [SUCCESS]: All read requests passed!"
    exit 0
else
    echo " [FAILURE]: $FAIL_COUNT read requests failed"
    exit 1
fi
