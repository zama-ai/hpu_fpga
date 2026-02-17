#!/bin/bash
# mhdma_notify_ping.sh — Ping notify: each card notifies all other cards
# Usage: ./mhdma_notify_ping.sh <num_cards>
#
# req_id bitfield:
#   [7:0]   rsvd    (8b)
#   [13:8]  flag    (6b) — incremented per destination
#   [15:14] mode    (2b) — set to 2
#   [19:16] node_id (4b) — destination card
#   [23:20] req_id  (4b)
#   [31:24] iop_id  (8b)

trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM

NUM_CARDS=$1

if [ -z "$hputil" ]; then
  echo " [FAILURE]: you did not export variable for hputil"
  exit 1
fi

if [ -z "$NUM_CARDS" ] || [ "$NUM_CARDS" -lt 2 ]; then
  echo "Usage: $0 <num_cards>  (num_cards minimum 2)"
  exit 1
fi

echo ""
echo " [INFO]: using hputil at $hputil"
echo ""
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
      req_id=$(printf "0x%08x" $(( (2 << 20) | (dest << 16) | (2 << 14) | (flag << 8) )))
      addr=$(printf "0x%x" $((card * 0x1000 + flag)))

      echo " [INFO]: Card $card -> Card $dest (req_id=$req_id, flag=$flag)"

      $hputil -f $card register write mhdma_request::req_addr --value "$addr" > /dev/null
      $hputil -f $card register write mhdma_request::req_id   --value $req_id > /dev/null

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
      notify=$($hputil -f $card register read mhdma_request::stat_nb_notify_received | awk 'END {print $NF}')
      nack=$($hputil -f $card register read mhdma_request::stat_nb_nack_received     | awk 'END {print $NF}')
      echo "$card $notify $nack"
    ) &
  done
  wait
)

if $all_pass; then
  echo ""
  echo " [SUCCESS] Ping test passed! All cards received the expected notifies."
fi
