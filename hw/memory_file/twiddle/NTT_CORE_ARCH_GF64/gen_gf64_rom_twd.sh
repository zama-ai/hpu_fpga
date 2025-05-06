# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# This directory contains the ROM content for a NTT_CORE_ARCH_gf64.
# It is assumed that:
# - this ROM contains the twiddles for the ngc PHI multiplication.
# - the ngc radix is always the biggest possible one, i.e. up to 32 max.

for i in `seq 2 5`; do
    psi=$((2**$i))
    coef=$((2*$psi))
    ngc_rdx_log=$(($i+1))
    if [ $ngc_rdx_log -gt 5 ]; then
        ngc_rdx_log=5
    fi

    for s in `seq 10 11`; do
        N=$((2**$s))
 
        sage ${PROJECT_DIR}/sw/ntt/ntt_gf64.sage -dir ${PROJECT_DIR}/hw/memory_file/twiddle/NTT_CORE_ARCH_GF64/R2_PSI${psi} -coef $coef -gen_rom  -N $N -J $ngc_rdx_log -J $(($s - $ngc_rdx_log))
    done
done
