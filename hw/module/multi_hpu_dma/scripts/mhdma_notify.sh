#!/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Ring notify: card i notifies card (i+1)%N
# ==============================================================================================
# Usage: ./mhdma_notify.sh <num_cards> [num_requests (default 10)]

trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM

NUM_CARDS=$1
NUM_REQUESTS=${2:-10}

if [ -z "$hputil" ]; then
  echo " [FAILURE]: you did not export variable for hputil"
  exit 1
fi

if [ -z "$NUM_CARDS" ] || [ "$NUM_CARDS" -lt 2 ]; then
  echo "Usage: $0 <num_cards> [num_requests]  (num_cards minimum 2, num_requests default 6)"
  exit 1
fi

echo ""
echo " [INFO]: using hputil at $hputil"
echo ""

# Ring: card i notifies card (i+1)%N
for card in $(seq 0 $((NUM_CARDS - 1))); do
  dest=$(( (card + 1) % NUM_CARDS ))
  base_addr=$((card * 0x1000))
  req_id=$(printf "0x%08x" $(( (2 << 20) | (dest << 16) | (1 << 14) )))
  echo " [INFO]: Card $card -> Card $dest (req_id=$req_id)"
  (
    for i in $(seq 0 $((NUM_REQUESTS - 1))); do
      addr=$(printf "0x%x" $((base_addr + i)))
      $hputil -f $card register write mhdma_request::req_addr --value "$addr" > /dev/null
      $hputil -f $card register write mhdma_request::req_id   --value $req_id > /dev/null

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
  notify=$($hputil -f $card register read mhdma_request::stat_nb_notify_received | awk 'END {print $NF}')
  nack=$($hputil -f $card register read mhdma_request::stat_nb_nack_received | awk 'END {print $NF}')
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
