#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import math

VERBOSE=False

MOD_Q_W=32
MOD_P_W=32
MOD_P = 2**32-2**17-2**13+1
PRECISION_W=MOD_P_W+18

MOD_Q=2**MOD_Q_W


cst = math.floor(2**PRECISION_W*MOD_Q/MOD_P)

error_cnt = 0

print("INFO> error = {:0d}/{:0d} = {:f}".format(error_cnt, MOD_P, error_cnt/MOD_P))
for i in range(MOD_P):
  ms=i*MOD_Q/MOD_P
  if (ms < math.floor(ms)+0.5):
    ref = math.floor(ms)
  else:
    ref = math.ceil(ms)

  val = i*cst
  res = val >> PRECISION_W
  if ((val >> (PRECISION_W-1) & 1) == 1):
    res = res + 1

  if (ref != res):
    error_cnt = error_cnt + 1
    if (VERBOSE):
      print("ERROR> Mismatch: i=0x{:0x} ref=0x{:0x} res=0x{:0x} mult=0x{:0x} cst=0x{:0x}".format(i,ref,res,val, cst))

  if (VERBOSE):
    if (i%100000==0):
      print("#{:d} OK".format(i))


print("INFO> error = {:0d}/{:0d} = {:f} (PRECISION_W={:0d})".format(error_cnt, MOD_P, error_cnt/MOD_P,PRECISION_W))
