#!/bin/bash
# sprint_demo.sh — Step-by-step demo: notify (0), init HBM (1), read request (2)
# Usage: ./sprint_demo.sh <0|1|2>

trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM

HBM_PC_RANGE=0x40000000 # HBM_PC_RANGE = 0x40000000 (1GB per PC)
HBM_PC_RANGE_BYTE=$((HBM_PC_RANGE / 8))
CT_MEM_BYTES=12288

src_addr=0x2222
dst_addr=0x4444

src_addr_val=$((src_addr * CT_MEM_BYTES))
dst_addr_val=$((dst_addr * CT_MEM_BYTES))

PC0_ADDR=0x4400000000
PC1_ADDR=0x4420000000

ADDR_PC0_SRC=$(printf "0x%x" "$((PC0_ADDR + src_addr_val))")
ADDR_PC1_SRC=$(printf "0x%x" "$((PC1_ADDR + src_addr_val))")

ADDR_PC0_DST=$(printf "0x%x" "$((PC0_ADDR + dst_addr_val))")
ADDR_PC1_DST=$(printf "0x%x" "$((PC1_ADDR + dst_addr_val))")


arg=${1:-0}

if [ "$arg" -eq "0" ]; then
  echo ""
  echo "=================================================================================================="
  echo "  Notify HPU 0 (receiver) that on HPU 1 (sender) ct_id 0x$(printf '%04x' $src_addr) is ready"
  echo "=================================================================================================="

  $hputil -f 1 register write mhdma_request::req_addr --value $src_addr
  $hputil -f 1 register write mhdma_request::req_id   --value 0x00204000
fi

if [ "$arg" -eq "1" ]; then
  echo ""
  echo "=================================================================================================="
  echo "  Setting up data for read request writing at specific adresses src_addr=0x$(printf '%04x' $src_addr), dst_addr=0x$(printf '%04x' $dst_addr)"
  echo "=================================================================================================="

  echo "  Writing manifest onto src address in sender memory"
  dma-to-device -d /dev/qdma24001-MM-1 -s 56001 -a $ADDR_PC0_SRC -o 0x0 -c 1 -f manifest.txt
  dma-to-device -d /dev/qdma24001-MM-1 -s 56001 -a $ADDR_PC1_SRC -o 0x0 -c 1 -f manifest.txt


  echo "  Writing 1G of random from dst address in receiver memory"
  dma-to-device -d /dev/qdma01001-MM-1 -s $HBM_PC_RANGE_BYTE -a $ADDR_PC0_DST -o 0x0 -c 1 -f /dev/random
  dma-to-device -d /dev/qdma01001-MM-1 -s $HBM_PC_RANGE_BYTE -a $ADDR_PC1_DST -o 0x0 -c 1 -f /dev/random
  echo ""

  echo "  ------------- Guardrail : reading in destination to check that it is initialized ------------- "
  echo "RECEIVER/HBM: Zone 0"
  dma-from-device -d /dev/qdma01001-MM-2 -s 160 -a $ADDR_PC0_DST -o 0x0 -c 1 -f test_pc0.mem && hexdump -C test_pc0.mem
  echo ""
  echo "RECEIVER/HBM: Zone 1"
  dma-from-device -d /dev/qdma01001-MM-2 -s 160 -a $ADDR_PC1_DST -o 0x0 -c 1 -f test_pc1.mem && hexdump -C test_pc1.mem
fi

if [ "$arg" -eq "2" ]; then

  echo ""
  echo "=================================================================================================="
  echo "  Read request from HPU 0 (receiver) to 1 (sender) "
  echo "=================================================================================================="

  request_addr=$(( ((dst_addr & 0xFFFF) << 16) | (src_addr & 0xFFFF) ))

  $hputil -f 0 register write mhdma_request::req_addr --value $request_addr
  $hputil -f 0 register write mhdma_request::req_id   --value 0x00614000

  sleep 1

  echo "RECEIVER/HBM: Zone 0"
  dma-from-device -d /dev/qdma01001-MM-2 -s 160 -a $ADDR_PC0_DST -o 0x0 -c 1 -f test_pc0.mem && hexdump -C test_pc0.mem
  echo ""
  echo "RECEIVER/HBM: Zone 1"
  dma-from-device -d /dev/qdma01001-MM-2 -s 160 -a $ADDR_PC1_DST -o 0x0 -c 1 -f test_pc1.mem && hexdump -C test_pc1.mem
fi
