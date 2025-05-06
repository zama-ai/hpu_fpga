// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Define macros used in ntt_core_gf64_network.
// ==============================================================================================

`ifndef NTT_CORE_GF64_NTW_MACRO
`define NTT_CORE_GF64_NTW_MACRO 1

// For localparam declaration inside the module
`define NTT_CORE_GF64_NTW_LOCALPARAM(RDX_CUT_ID=0,BWD=0,R=2,PSI=4) \
  localparam int C                   = R*PSI; \
 \
  localparam int NEXT_RDX_CUT_ID     = BWD ? RDX_CUT_ID - 1 : RDX_CUT_ID + 1; \
  localparam int S_L                 = get_s_l(NEXT_RDX_CUT_ID,BWD); \
  localparam int N_L                 = 2**S_L; /* current working block size */ \
  localparam int ITER_NB             = get_iter_nb(NEXT_RDX_CUT_ID,BWD); \
  localparam int WB_NB               = N / N_L; \
 \
  localparam int A_NB                = get_a_nb(NEXT_RDX_CUT_ID,BWD); \
  localparam int L_NB                = get_l_nb(NEXT_RDX_CUT_ID,BWD); \
  localparam int R_A                 = get_rdx_a(NEXT_RDX_CUT_ID,BWD); \
  localparam int R_L                 = get_rdx_l(NEXT_RDX_CUT_ID,BWD); \
 \
  /* specific parameters needed for the network */ \
  localparam int CONS_NB             = (L_NB >= C) ? 1 : C / L_NB; \
  localparam bit DO_INTERLEAVE       = (L_NB < C); \
  localparam int TRG_RDX_NB          = (L_NB >= C) ? C : L_NB; \
 \
  localparam int SET_NB              = (R_L > C) ? 1 : C / R_L; \
  localparam int RD_ITER_NB          = (R_L > C) ? R_L / C : 1; \
  localparam bit DO_DISPATCH         = (R_L <= C); \
 \
  localparam int POS_ITER_NB         = L_NB / TRG_RDX_NB; \
  localparam int DSP_STRIDE          = SET_NB; \
  localparam int COMPLETE_RD_ITER_NB = C / (CONS_NB * SET_NB); \
  localparam int TRG_RD_ITER_NB      = TRG_RDX_NB / SET_NB; \
 \
  localparam int WB_W                = $clog2(WB_NB) == 0 ? 1 : $clog2(WB_NB); \
  localparam int ITER_Z              = $clog2(ITER_NB); \
  localparam int ITER_W              = $clog2(ITER_NB) == 0 ? 1 : $clog2(ITER_NB); \
  localparam int POS_W               = $clog2(R_L) == 0 ? 1 : $clog2(R_L); \
  localparam int COMPLETE_RD_ITER_Z  = $clog2(COMPLETE_RD_ITER_NB); \
  localparam int POS_ITER_Z          = $clog2(POS_ITER_NB); \
  localparam int C_Z                 = $clog2(C); \
  localparam int C_W                 = $clog2(C) == 0 ? 1 : $clog2(C); \
  localparam int R_L_Z               = $clog2(R_L); \
  localparam int R_L_W               = $clog2(R_L) == 0 ? 1 : $clog2(R_L); \
  localparam int L_NB_W              = $clog2(L_NB) == 0 ? 1 : $clog2(L_NB); \
  localparam int CONS_Z              = $clog2(CONS_NB); \
  localparam int SET_Z               = $clog2(SET_NB); \
  localparam int SET_W               = $clog2(SET_NB) == 0 ? 1 : $clog2(SET_NB); \

`endif
