#!/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : MHDMA Parallel Read Request Test Script (Ring Topology)
# ==============================================================================================
# Performs one parallel read request per board in a ring topology.
# Board 0 → Board 1 → Board 2 → ... → Board N-1 → Board 0
#
# Address allocation:
#   A random base ciphertext address is picked. Each board i uses:
#     src_addr = BASE_ADDR + i                (on next board's HBM)
#     dst_addr = BASE_ADDR + NUM_CARDS + i    (on local board's HBM)
#   Physical spacing between consecutive ciphertexts is CT_MEM_BYTES (0x3000).
#
#   src range: [BASE_ADDR, BASE_ADDR + N - 1]
#   dst range: [BASE_ADDR + N, BASE_ADDR + 2N - 1]
#   These two ranges never overlap, and on any single board's HBM the
#   write (dst) and read (src) addresses fall in different ranges.
#
# Usage: ./mhdma_read_request_parallel.sh [OPTIONS]
#   -n, --num-cards     Number of cards in the ring (default: 2, minimum: 2)
#   -h, --help          Show this help message
# =================================================================================================

set -e
trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM

# =================================================================================================
# Source board configuration
# =================================================================================================
source /etc/profile.d/v80_pcie_dev.sh
source "$(dirname "$0")/mhdma_package.sh"

# =================================================================================================
# Default parameters
# =================================================================================================
NUM_CARDS=2

PC0_DATA_SIZE=8224   # 0x2020 bytes
PC1_DATA_SIZE=8192   # 0x2000 bytes
CT_MEM_BYTES=12288   # 0x3000

PC0_ADDR=0x4400000000
PC1_ADDR=0x4420000000
HW_MAX_ADDR=0xAAAA   # floor(HBM_PORT_RANGE / CT_MEM_BYTES)

TIMEOUT_ITER=1000

# =================================================================================================
# Parse command line arguments
# =================================================================================================
show_help() {
    echo "MHDMA Parallel Read Request Test (Ring Topology)"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n, --num-cards     Number of cards in the ring (default: $NUM_CARDS, min: 2)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Topology: Board 0 -> Board 1 -> ... -> Board N-1 -> Board 0"
    echo ""
    echo "Address: random base + i per board (sequential ciphertexts, CT_MEM_BYTES apart)"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--num-cards)
            NUM_CARDS="$2"
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

if [ "$NUM_CARDS" -lt 2 ]; then
    echo " [ERROR]: num-cards must be >= 2"
    exit 1
fi

# =================================================================================================
# Environment check
# =================================================================================================
if [ -z "$hputil" ]; then
    echo " [FAILURE]: you did not export variable for hputil"
    exit 1
fi

echo " [INFO]: using hputil at $hputil"

for ((b=0; b<NUM_CARDS; b++)); do
    if [ "${V80_BOARDS_MAP[$b,pcie_id]}" = "x" ]; then
        echo " [ERROR]: Board $b is not configured but required for $NUM_CARDS-card ring"
        exit 1
    fi
done

setup_check=$($hputil -f 0 register read mhdma_system::hpu_id_0)
if [ "$setup_check" == "0x0" ]; then
    echo " [FAILURE]: you did not run the setup (mhdma_setup.sh)"
    exit 1
fi

# =================================================================================================
# Generate random base address
# =================================================================================================
BASE_ADDR=$(( $(od -An -tu4 -N4 /dev/urandom | tr -d ' ') % (HW_MAX_ADDR - 2 * NUM_CARDS) ))

ring_str=""
for ((i=0; i<NUM_CARDS; i++)); do
    ring_str+="Board $i -> "
done
ring_str+="Board 0"

echo ""
echo "=================================================================================================="
echo "  MHDMA Parallel Read Request Test (Ring Topology)"
echo "=================================================================================================="
echo "  Configuration:"
echo "    - Number of cards:    $NUM_CARDS"
echo "    - Base address:       $BASE_ADDR (0x$(printf '%04x' $BASE_ADDR))"
echo "    - CT_MEM_BYTES:       $CT_MEM_BYTES (0x$(printf '%x' $CT_MEM_BYTES))"
echo "    - Ring:               $ring_str"
echo "  Addresses:"
for ((i=0; i<NUM_CARDS; i++)); do
    start_address=$((BASE_ADDR + i))
    destination_address=$((BASE_ADDR + NUM_CARDS + i))
    echo "    Board $i: src=0x$(printf '%04x' $start_address) (phys 0x$(printf '%x' $((start_address * CT_MEM_BYTES)))), dst=0x$(printf '%04x' $destination_address) (phys 0x$(printf '%x' $((destination_address * CT_MEM_BYTES))))"
done
echo "=================================================================================================="

mkdir -p tmp

echo ""
echo "=================================================================================================="
echo "  Phase 0: Initializing HBM with random data"
echo "=================================================================================================="

INIT_OFFSET=$(( BASE_ADDR * CT_MEM_BYTES ))
INIT_SIZE=$(( 2 * NUM_CARDS * CT_MEM_BYTES ))
echo " [INFO]: Writing $INIT_SIZE bytes (0x$(printf '%x' $INIT_SIZE)) per PC at offset 0x$(printf '%x' $INIT_OFFSET) on each board"

for ((b=0; b<NUM_CARDS; b++)); do
    pcie_id=${V80_BOARDS_MAP[$b,pcie_id]}
    (
        dma-to-device -d /dev/qdma${pcie_id}001-MM-1 -s $INIT_SIZE -a $(printf "0x%x" $((PC0_ADDR + INIT_OFFSET))) -o 0x0 -c 1 -f /dev/random
        dma-to-device -d /dev/qdma${pcie_id}001-MM-1 -s $INIT_SIZE -a $(printf "0x%x" $((PC1_ADDR + INIT_OFFSET))) -o 0x0 -c 1 -f /dev/random
        echo " [INFO]: Board $b (PCIe: $pcie_id) HBM initialized"
    ) &
done
wait
echo " [INFO]: All boards HBM initialized"

echo ""
echo "=================================================================================================="
echo "  Phase 1: Sending read requests (parallel, ring topology)"
echo "=================================================================================================="

for ((card=0; card<NUM_CARDS; card++)); do
    next_card=$(( (card + 1) % NUM_CARDS ))
    src_addr=$((BASE_ADDR + card))
    dst_addr=$((BASE_ADDR + NUM_CARDS + card))
    # req_addr: {dst_addr[15:0], src_addr[15:0]}
    req_addr=$(printf "0x%08x" $(( ((dst_addr & 0xFFFF) << 16) | (src_addr & 0xFFFF) )))
    # req_id: iop_id=0, REQ_ID_READ=6, node_id=next_card, mode=1
    req_id=$(printf "0x%08x" $(( (6 << 20) | (next_card << 16) | (1 << 14) )))

    (
        $hputil -f $card register write mhdma_request::req_addr --value "$req_addr" > /dev/null
        $hputil -f $card register write mhdma_request::req_id   --value "$req_id" > /dev/null

        echo " [INFO]: Board $card -> Board $next_card: src=0x$(printf '%04x' $src_addr) dst=0x$(printf '%04x' $dst_addr) req_addr=$req_addr req_id=$req_id"

        # Wait for completion and pop FIFO
        for ((w=0; w<TIMEOUT_ITER; w++)); do
            rr_status=$($hputil -f $card register read mhdma_request::read_request)
            if [ "$rr_status" != "0x0" ]; then
                $hputil -f $card register read mhdma_request::read_request_req_id > /dev/null
                echo " [INFO]: Board $card: completion received"
                break
            fi
            sleep 0.01
        done

        if [ "$rr_status" == "0x0" ]; then
            echo " [FAIL]: Board $card: timed out waiting for completion"
        fi
    ) &
done

wait
echo " [INFO]: All requests completed"

echo ""
echo "=================================================================================================="
echo "  Phase 2: Checking data integrity"
echo "=================================================================================================="

PASS_COUNT=0
FAIL_COUNT=0

for ((card=0; card<NUM_CARDS; card++)); do
    next_card=$(( (card + 1) % NUM_CARDS ))
    src_addr=$((BASE_ADDR + card))
    dst_addr=$((BASE_ADDR + NUM_CARDS + card))
    src_phys=$((src_addr * CT_MEM_BYTES))
    dst_phys=$((dst_addr * CT_MEM_BYTES))

    pcie_src=${V80_BOARDS_MAP[$next_card,pcie_id]}  # source data lives on next board
    pcie_dst=${V80_BOARDS_MAP[$card,pcie_id]}        # destination data on local board

    SRC_PC0=$(printf "0x%x" $((PC0_ADDR + src_phys)))
    SRC_PC1=$(printf "0x%x" $((PC1_ADDR + src_phys)))
    DST_PC0=$(printf "0x%x" $((PC0_ADDR + dst_phys)))
    DST_PC1=$(printf "0x%x" $((PC1_ADDR + dst_phys)))

    # Read source data (from next board) and destination data (from local board)
    dma-from-device -d /dev/qdma${pcie_src}001-MM-2 -s $PC0_DATA_SIZE -a $SRC_PC0 -o 0x0 -c 1 -f tmp/src_b${next_card}_pc0.mem
    dma-from-device -d /dev/qdma${pcie_src}001-MM-2 -s $PC1_DATA_SIZE -a $SRC_PC1 -o 0x0 -c 1 -f tmp/src_b${next_card}_pc1.mem
    dma-from-device -d /dev/qdma${pcie_dst}001-MM-2 -s $PC0_DATA_SIZE -a $DST_PC0 -o 0x0 -c 1 -f tmp/dst_b${card}_pc0.mem
    dma-from-device -d /dev/qdma${pcie_dst}001-MM-2 -s $PC1_DATA_SIZE -a $DST_PC1 -o 0x0 -c 1 -f tmp/dst_b${card}_pc1.mem

    echo ""

    loop_pass=1
    for pc in 0 1; do
        if cmp -s tmp/src_b${next_card}_pc${pc}.mem tmp/dst_b${card}_pc${pc}.mem; then
            echo " [PASS]: Board $card PC${pc}: data matches (src Board $next_card @ 0x$(printf '%04x' $src_addr), dst Board $card @ 0x$(printf '%04x' $dst_addr))"
        else
            echo " [FAIL]: Board $card PC${pc}: mismatch (src Board $next_card @ 0x$(printf '%04x' $src_addr), dst Board $card @ 0x$(printf '%04x' $dst_addr))"
            hexdump -C tmp/src_b${next_card}_pc${pc}.mem > tmp/hex_src_b${next_card}_pc${pc}.mem
            hexdump -C tmp/dst_b${card}_pc${pc}.mem > tmp/hex_dst_b${card}_pc${pc}.mem
            loop_pass=0
        fi
    done

    if [ "$loop_pass" -eq 1 ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "=================================================================================================="
echo "  Statistics"
echo "=================================================================================================="

for ((card=0; card<NUM_CARDS; card++)); do
    (
        errors=$($hputil -f $card register read mhdma_system::errors | awk 'END {print $NF}')
        ce=$($hputil -f $card register read mhdma_request::stat_nb_ce_received | awk 'END {print $NF}')
        rr=$($hputil -f $card register read mhdma_request::stat_nb_read_req_received | awk 'END {print $NF}')
        echo " Board $card: errors=$errors ce_received=$ce rr_received=$rr"
    ) &
done
wait

echo ""
echo "=================================================================================================="
echo "  Test Summary"
echo "=================================================================================================="
echo "  Total boards: $NUM_CARDS"
echo "  Passed:       $PASS_COUNT"
echo "  Failed:       $FAIL_COUNT"
echo "=================================================================================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo " [SUCCESS]: All parallel read requests passed!"
    exit 0
else
    echo " [FAILURE]: $FAIL_COUNT boards failed data integrity check"
    exit 1
fi
