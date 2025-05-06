// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Define macros used in pep_mmacc_splitc_sxt.
// Mainly to share localparam that depend on parameters.
// ==============================================================================================

`ifndef PEP_MMACC_SPLITC_SXT_MACRO
`define PEP_MMACC_SPLITC_SXT_MACRO 1

`define PEP_MMACC_SPLITC_SXT_LOCALPARAM(R=2,PSI=8,DATA_LATENCY=6,REGF_COEF_NB=32,REGF_COEF_PER_URAM_WORD=1,REGF_BLWE_WORD_PER_RAM=16,DATA_THRESHOLD=8) \
 \
 \
 \
 \
  /* For Output Buffer                                                                            */ \
  /* Let's name RD_DEPTH_MIN, the minimal buffer depth of a buffer used to get the data read from */ \
  /* the GRAM, without introducing bubble (with the assumption that the GRAM access is always     */ \
  /* granted)                                                                                     */ \
  /* Let's name OUT_DEPTH_MIN, the minimal buffer depth of a buffer used to store the regfile     */ \
  /* words before sending them to the regfile.                                                    */ \
  /* We use a buffer that serves both purposes : smooth the gram data readings and ensure data availability */ \
  /* for the regfile.                                                                             */ \
  /* If REGF_COEF_NB > RD_COEF_NB                                                                 */ \
  /*    1 regfile word is composed of several gram data.                                          */ \
  /* Else if REGF_COEF_NB < RD_COEF_NB                                                            */ \
  /*    1 gram data is composed of several regfile words.                                         */ \
 \
  localparam int RD_DEPTH_MIN = DATA_LATENCY + 3 + 3 + PERM_CYCLE_NB + 2; \
                                            /* +3 is internal pipes before sending the request (s1, s2, s3)                                         */ \
                                            /* +3 is internal pipes once data received, before being stored in the buffer (x0 + x4 + fifo_reg delay)*/ \
                                            /* +2 : first perm + perm done in join                                                                  */ \
                                            /* in GRAM data unit (i.e. RxPSI coef)                                                                  */ \
 \
  localparam int RD_DEPTH_GUNIT     = gunit_depth(RD_DEPTH_MIN); \
  localparam int JOIN_FIFO_DEPTH    = RD_DEPTH_GUNIT > DATA_THRESHOLD_GUNIT ? RD_DEPTH_GUNIT : DATA_THRESHOLD_GUNIT; \
  localparam int JOIN_FIFO_DEPTH_WW = $clog2(JOIN_FIFO_DEPTH+1) == 0 ? 1 : $clog2(JOIN_FIFO_DEPTH+1);

`endif
