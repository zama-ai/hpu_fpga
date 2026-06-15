#!/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Ping notify: each card notifies all other cards
# ==============================================================================================
# Usage: ./mhdma_notify_ping.sh <num_cards>
#

trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM

source /etc/profile.d/v80_pcie_dev.sh
source "$(dirname "$0")/mhdma_package.sh"

NUM_CARDS=$1

if ! mhdma_check_ami; then
  exit 1
fi

if [ -z "$NUM_CARDS" ] || [ "$NUM_CARDS" -lt 2 ]; then
  echo "Usage: $0 <num_cards>  (num_cards minimum 2)"
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

echo "=================================================================================================="
echo "  Notify Ping: each card notifies all other cards (mode=2, flag increments)"
echo "=================================================================================================="

# Each card sends a notify to every other card, with increasing flag
for card in $(seq 0 $((NUM_CARDS - 1))); do
  flag=1
  (
    for dest in $(seq 0 $((NUM_CARDS - 1))); do
      if [ "$dest" -eq "$card" ]; then
        continue
      fi

      # mode=2 (bits 14-15), node_id=dest (bits 16-19), flag (bits 8-13)
      req_id=$(build_req_id $REQ_ID_NOTIFY $dest 2 $flag)
      addr=$(printf "0x%x" $((card * 0x1000 + flag)))

      echo " [INFO]: Card $card -> Card $dest (req_id=$req_id, flag=$flag)"

      mhdma_reg_write $card mhdma_request::req_addr "$addr" > /dev/null
      mhdma_reg_write $card mhdma_request::req_id $req_id > /dev/null

      flag=$((flag + 1))
    done
  ) &
done

wait

echo ""
echo "=================================================================================================="
echo "  Test Summary"
echo "=================================================================================================="

all_pass=true
expected=$((NUM_CARDS - 1))

# Read all cards' counters in parallel
while read -r card notify nack; do
  echo " Card $card : notify_received=$notify, nack_received=$nack (expected=$expected each)"

  notify_dec=$((16#$notify))
  nack_dec=$((16#$nack))

  if [ "$notify_dec" -ne "$expected" ]; then
    echo " [FAIL] Card $card : notify_received=$notify_dec != expected=$expected"
    all_pass=false
  elif [ "$nack_dec" -ne "$expected" ]; then
    echo " [FAIL] Card $card : nack_received=$nack_dec != expected=$expected"
    all_pass=false
  else
    echo " [PASS] Card $card : notify=$notify_dec, nack=$nack_dec"
  fi
done < <(
  for card in $(seq 0 $((NUM_CARDS - 1))); do
    (
      notify=$(mhdma_reg_read $card mhdma_request::stat_nb_notify_received | awk 'END {print $NF}')
      nack=$(mhdma_reg_read $card mhdma_request::stat_nb_nack_received     | awk 'END {print $NF}')
      echo "$card $notify $nack"
    ) &
  done
  wait
)

if $all_pass; then
  echo ""
  echo " [SUCCESS] Ping test passed! All cards received the expected notifies."
fi
