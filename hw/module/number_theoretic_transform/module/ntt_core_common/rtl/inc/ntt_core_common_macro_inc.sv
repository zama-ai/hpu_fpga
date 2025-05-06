// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Define macros used in ntt_core_with_matrix_multiplication.
// ==============================================================================================

`ifndef NTT_CORE_WMM_MACRO
`define NTT_CORE_WMM_MACRO 1

// For localparam declaration inside the module
`define NTT_CORE_LOCALPARAM(R=8,S=3,PSI=8) \
  /* Number of BU per stage */ \
  localparam int STG_BU_NB   = R ** (S-1); \
  /* Number of stage-iteration per stage */ \
  localparam int STG_ITER_NB = STG_BU_NB / PSI; \
  \
  /*=== Counters size */ \
  /* Note : counters should be at least 1 bit. */ \
  /* stg_iter counter size */ \
  localparam int STG_ITER_W = ($clog2(STG_ITER_NB) == 0) ? 1 : $clog2(STG_ITER_NB); \
  /* stg counter size */ \
  localparam int STG_W      = ($clog2(S) == 0) ? 1 : $clog2(S); \
  \
  /* Counter from 0 to R-1 size */ \
  localparam int R_W        = ($clog2(R) == 0) ? 1 : $clog2(R); \
  /* Stage BU counter size */ \
  localparam int STG_BU_W   = ($clog2(STG_BU_NB) == 0) ? 1 : $clog2(STG_BU_NB); \
  /* Counter from 0 to PSI-1 size */ \
  localparam int PSI_W      = ($clog2(PSI) == 0) ? 1 : $clog2(PSI); \
  /* Vector size */ \
  localparam int PSI_SZ      = $clog2(PSI); \
  localparam int R_SZ        = $clog2(R); \
  localparam int STG_ITER_SZ = $clog2(STG_ITER_NB);


// For localparam declaration inside the header
`define NTT_CORE_LOCALPARAM_HEADER(R=8,S=3,PSI=8) \
  /* Number of BU per stage */ \
  localparam int STG_BU_NB   = R ** (S-1), \
  /* Number of stage-iteration per stage */ \
  localparam int STG_ITER_NB = STG_BU_NB / PSI, \
  \
  /*=== Counters size */ \
  /* Note : counters should be at least 1 bit. */ \
  /* stg_iter counter size */ \
  localparam int STG_ITER_W = ($clog2(STG_ITER_NB) == 0) ? 1 : $clog2(STG_ITER_NB), \
  /* stg counter size */ \
  localparam int STG_W      = ($clog2(S) == 0) ? 1 : $clog2(S), \
  \
  /* Counter from 0 to R-1 size */ \
  localparam int R_W        = ($clog2(R) == 0) ? 1 : $clog2(R), \
  /* Stage BU counter size */ \
  localparam int STG_BU_W   = ($clog2(STG_BU_NB) == 0) ? 1 : $clog2(STG_BU_NB), \
  /* Counter from 0 to PSI-1 size */ \
  localparam int PSI_W      = ($clog2(PSI) == 0) ? 1 : $clog2(PSI), \
  /* Vector size */ \
  localparam int PSI_SZ      = $clog2(PSI), \
  localparam int R_SZ        = $clog2(R), \
  localparam int STG_ITER_SZ = $clog2(STG_ITER_NB)



`endif
