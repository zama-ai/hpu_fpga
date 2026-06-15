#!/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Ring notify: card i notifies card (i+1)%N
# ==============================================================================================
# Usage: ./mhdma_notify.sh <num_cards> [num_requests (default 10)]

trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM

source /etc/profile.d/v80_pcie_dev.sh
source "$(dirname "$0")/mhdma_package.sh"

NUM_CARDS=$1
NUM_REQUESTS=${2:-10}

if ! mhdma_check_ami; then
  exit 1
fi

if [ -z "$NUM_CARDS" ] || [ "$NUM_CARDS" -lt 2 ]; then
  echo "Usage: $0 <num_cards> [num_requests]  (num_cards minimum 2, num_requests default 6)"
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

# Ring: card i notifies card (i+1)%N
for card in $(seq 0 $((NUM_CARDS - 1))); do
  dest=$(( (card + 1) % NUM_CARDS ))
  base_addr=$((card * 0x1000))
  req_id=$(build_req_id $REQ_ID_NOTIFY $dest 1)
  echo " [INFO]: Card $card -> Card $dest (req_id=$req_id)"
  (
    for i in $(seq 0 $((NUM_REQUESTS - 1))); do
      addr=$(printf "0x%x" $((base_addr + i)))
      mhdma_reg_write $card mhdma_request::req_addr "$addr" > /dev/null
      mhdma_reg_write $card mhdma_request::req_id $req_id > /dev/null

      echo "($((i + 1))) Card $card -> Card $dest"
    done
  ) &
done

wait

echo ""
echo "=================================================================================================="
echo "  Test Summary"
echo "=================================================================================================="
# Validation: receiver's notify_received must match sender's nack_received
all_pass=true
for card in $(seq 0 $((NUM_CARDS - 1))); do
  notify=$(mhdma_reg_read $card mhdma_request::stat_nb_notify_received | awk 'END {print $NF}')
  nack=$(mhdma_reg_read $card mhdma_request::stat_nb_nack_received | awk 'END {print $NF}')
  if [ "$notify" != "$nack" ]; then
    echo " [FAIL] Card $card : nack($card)=$nack != notify($card)=$notify"
    all_pass=false
  else
    echo " [PASS] Card $card : nack=$nack, notify=$notify"
  fi
done

if $all_pass; then
  echo " [SUCCESS] All cards passed!"
fi
