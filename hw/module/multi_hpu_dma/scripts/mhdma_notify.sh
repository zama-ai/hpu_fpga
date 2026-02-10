#!/bin/bash

# Trap SIGINT (Ctrl+C) and kill all child processes
trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM

if [ -z "$hputil" ]; then
  echo " [FAILURE]: you did not export variable for hputil"
  exit 0
else
  echo " [INFO]: using hputil at $hputil"
fi

(
  # FPGA 01
  for i in $(seq 0 5)
  do
    $hputil -f 0 register write mhdma_request::req_addr --value "0x$i"
    $hputil -f 0 register write mhdma_request::req_id   --value 0x00214000
  done

) &

(
  # FPGA 24
  for i in $(seq 1000 1005);
  do
    $hputil -f 1 register write mhdma_request::req_addr  --value "0x$i"
    $hputil -f 1 register write mhdma_request::req_id   --value 0x00204000
  done
) &

wait

stat_nb_notify_received_1=$($hputil -f 1 register read mhdma_request::stat_nb_notify_received | awk 'END {print $NF}')
stat_nb_nack_received_0=$($hputil -f 0 register read mhdma_request::stat_nb_nack_received | awk 'END {print $NF}')

stat_nb_notify_received_0=$($hputil -f 0 register read mhdma_request::stat_nb_notify_received | awk 'END {print $NF}')
stat_nb_nack_received_1=$($hputil -f 1 register read mhdma_request::stat_nb_nack_received | awk 'END {print $NF}')

if [[ "$stat_nb_notify_received_1" != "$stat_nb_nack_received_0" ]] || [[ "$stat_nb_notify_received_0" != "$stat_nb_nack_received_1" ]]; then
  echo "stat_nb_notify_received_1 $stat_nb_notify_received_1"
  echo "stat_nb_nack_received_0   $stat_nb_nack_received_0"
  echo "stat_nb_notify_received_0 $stat_nb_notify_received_0"
  echo "stat_nb_nack_received_1   $stat_nb_nack_received_1"
else
  echo "Test passes for all hpu1=$stat_nb_notify_received_1 hpu0=$stat_nb_notify_received_0!"
fi
