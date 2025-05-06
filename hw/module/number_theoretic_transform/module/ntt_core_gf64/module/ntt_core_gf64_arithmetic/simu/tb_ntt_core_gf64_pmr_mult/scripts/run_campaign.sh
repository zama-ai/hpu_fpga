#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'


module="ntt_core_gf64_pmr_mult"
DIR="${PROJECT_DIR}/hw/module/number_theoretic_transform/module/ntt_core_gf64/module/ntt_core_gf64_arithmetic/simu/tb_${module}"
TMP_FILE="/tmp/$module.tmp"
SEED_FILE="/tmp/$module.seed"

seed=123

MOD_NTT_W_L=("8" "10" "12" "16" "32" "64")
for m in "${MOD_NTT_W_L[@]}"; do
    for w in `seq $(($m + 2)) $(($m + 3))`; do
        cmd="${DIR}/scripts/run.sh -- -P MOD_NTT_W int $m -P OP_W int $w -s $seed"
        echo "============================================"
        echo "Run : $cmd"
        echo "============================================"
        $cmd | tee >(grep "Seed" | head -1 >> $SEED_FILE) |  grep -c "> SUCCEED !" > $TMP_FILE
        exit_status=$?
        succeed_cnt=$(cat $TMP_FILE)
        rm -f $TMP_FILE
        if [ $exit_status -gt 0 ] || [ $succeed_cnt -ne 1 ] ; then
            echo -e "${RED}FAILURE>${NC} $cmd" 1>&2
        else
            echo -e "${GREEN}SUCCEED>${NC} $cmd" 1>&2
        fi
    done
done
