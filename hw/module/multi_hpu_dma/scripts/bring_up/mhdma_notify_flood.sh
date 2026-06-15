#!/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : All cards notify one random target card
# ==============================================================================================
# Usage: ./mhdma_notify_flood.sh <num_cards> [num_requests (default 10)]

trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM

source /etc/profile.d/v80_pcie_dev.sh
source "$(dirname "$0")/mhdma_package.sh"

NUM_CARDS=$1
NUM_REQUESTS=${2:-10}

if ! mhdma_check_ami; then
  exit 1
fi

if [ -z "$NUM_CARDS" ] || [ "$NUM_CARDS" -lt 2 ]; then
  echo "Usage: $0 <num_cards> [num_requests]  (num_cards minimum 2, num_requests default 10)"
  exit 1
fi

echo ""
echo " [INFO]: using ami_tool at $(command -v "$MHDMA_AMI_TOOL")"
echo ""

for ((b=0; b<NUM_CARDS; b++)); do
    if ! _mhdma_board_valid $b; then
        echo " [ERROR]: Board $b not configured in V80_BOARDS_MAP"
        exit 1
    fi
done

# Pick one random target card
target=$((RANDOM % NUM_CARDS))
echo "=================================================================================================="
echo " [INFO]: Target card: $target — all other cards will notify it"
echo "=================================================================================================="

# Precompute req_id in parent shell
req_id=$(build_req_id $REQ_ID_NOTIFY $target 1)

# Launch all cards (except target) in parallel
for card in $(seq 0 $((NUM_CARDS - 1))); do
  if [ "$card" -eq "$target" ]; then
    continue
  fi
  base_addr=$((card * 0x1000))
  echo " [INFO]: Card $card -> Card $target (req_id=$req_id)"
  (
    for i in $(seq 0 $((NUM_REQUESTS - 1))); do
      addr=$(printf "0x%x" $((base_addr + i)))
      mhdma_reg_write $card mhdma_request::req_addr "$addr"
      mhdma_reg_write $card mhdma_request::req_id $req_id
    done
  ) &
done

wait

echo ""
echo "=================================================================================================="
echo "  Test Summary"
echo "=================================================================================================="

# Read all counters in parallel
all_pass=true
total_nack=0

while read -r type key val; do
  if [ "$type" = "NACK" ]; then
    echo " [INFO] Card $key: nack_received=$val"
    total_nack=$((total_nack + 16#$val))
  elif [ "$type" = "NOTIFY" ]; then
    notify=$key
  fi
done < <(
  for card in $(seq 0 $((NUM_CARDS - 1))); do
    if [ "$card" -eq "$target" ]; then continue; fi
    (mhdma_reg_read $card mhdma_request::stat_nb_nack_received | awk -v c=$card 'END {print "NACK", c, $NF}') &
  done
  (mhdma_reg_read $target mhdma_request::stat_nb_notify_received | awk 'END {print "NOTIFY", $NF}') &
  wait
)

echo " [INFO] Card $target (target): notify_received=$notify"
echo " [INFO] Sum of all senders' nack_received=$total_nack"

if [ "$((16#$notify))" -ne "$total_nack" ]; then
  echo " [FAIL] notify_received($target)=$((16#$notify)) != total_nack=$total_nack"
  all_pass=false
else
  echo " [PASS] notify_received=$((16#$notify)) matches total_nack=$total_nack"
fi

if $all_pass; then
  echo " [SUCCESS] Flood test passed!"
fi
