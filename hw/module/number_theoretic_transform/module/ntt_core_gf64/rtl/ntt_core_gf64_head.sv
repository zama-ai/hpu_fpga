// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core gf64 computes the NTT and INTT in goldilocks 64 domain.
// This prime = 2**64-2**32+1 has many properties. In particular :
// 1. We use the following one to simplify all the twiddle multiplications :
//    It exists a 64th root of unity in GF64 which value is 8=2**3 : w_64 = 2**3, so
//    a power of 2.
// 2. This prime is a solinas2, with the following pattern : 2**W-2**W/2+1.
//    The modular reduction can be done efficiently, especially if we do partial
//    modular reduction (PMR). Which means that we do not reduce completely,
//    and the data path contains additional bits.
//
// This module also performs the external multiplication with the BSK.
//
// This version is the head part of the NTT core gf64 : its input interface is formatted for
// the connection with the decomp.
// ==============================================================================================

module ntt_core_gf64_head
  import common_definition_pkg::*;
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
#(
  parameter  int               S_NB             = S, // Number of NTT stages.
  parameter  bit               USE_PP           = 1, // If this partition contains the entire FWD NTT,
                                                     // this parameter indicates if the PP is instantiated.
  parameter  arith_mult_type_e PHI_MULT_TYPE    = MULT_CORE, // PHI multiplier, when needed
  parameter  arith_mult_type_e PP_MULT_TYPE     = MULT_CORE, // Multiplier used in PP
  parameter  int               RAM_LATENCY      = 1,
  parameter  int               ROM_LATENCY      = 1,
  parameter  string            TWD_GF64_FILE_PREFIX  = $sformatf("memory_file/twiddle/NTT_CORE_ARCH_GF64/R%0d_PSI%0d/twd_phi",R,PSI),
  localparam int               ERROR_W          = 1    // pp
)
(
  input  logic                                                 clk,
  input  logic                                                 s_rst_n,

  // Data from decomposition
  input  logic [PSI-1:0][R-1:0][PBS_B_W:0]                     decomp_ntt_data, // 2s complement
  input  logic [PSI-1:0][R-1:0]                                decomp_ntt_data_vld,
  output logic [PSI-1:0][R-1:0]                                decomp_ntt_data_rdy,
  input  logic                                                 decomp_ntt_sob,
  input  logic                                                 decomp_ntt_eob,
  input  logic                                                 decomp_ntt_sol,
  input  logic                                                 decomp_ntt_eol,
  input  logic                                                 decomp_ntt_sog,
  input  logic                                                 decomp_ntt_eog,
  input  logic [BPBS_ID_W-1:0]                                 decomp_ntt_pbs_id,
  input  logic                                                 decomp_ntt_ctrl_vld,
  output logic                                                 decomp_ntt_ctrl_rdy,

  // To next ntt_core or output logic
  output logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0]                 next_data,
  output logic [PSI-1:0][R-1:0]                                next_avail,
  output logic                                                 next_sob,
  output logic                                                 next_eob,
  output logic                                                 next_sol,
  output logic                                                 next_eol,
  output logic                                                 next_sos,
  output logic                                                 next_eos,
  output logic [BPBS_ID_W-1:0]                                 next_pbs_id,

  // Matrix factors : BSK
  // Only used if the PP is in this part.
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][MOD_NTT_W-1:0]  bsk,
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                 bsk_vld,
  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                 bsk_rdy,

  // Error
  output logic [ERROR_W-1:0]                                   error
);

  // ============================================================================================ //
  // Signals
  // ============================================================================================ //
  logic  [PSI-1:0][R-1:0][MOD_NTT_W+1:0] prev_data;
  logic  [PSI-1:0][R-1:0]                prev_avail;
  logic                                  prev_sob;
  logic                                  prev_eob;
  logic                                  prev_sol;
  logic                                  prev_eol;
  logic                                  prev_sos;
  logic                                  prev_eos;
  logic [BPBS_ID_W-1:0]                  prev_pbs_id;

  // ============================================================================================ //
  // Format input
  // ============================================================================================ //
  always_comb
    for (int p=0; p<PSI; p=p+1)
      for (int r=0; r<R; r=r+1)
        prev_data[p][r] = {{MOD_NTT_W+2-PBS_B_W{decomp_ntt_data[p][r][PBS_B_W]}},decomp_ntt_data[p][r][PBS_B_W-1:0]}; // extend sign

  assign prev_avail  = decomp_ntt_data_vld;
  assign prev_sob    = decomp_ntt_sob;
  assign prev_eob    = decomp_ntt_eob;
  assign prev_sol    = decomp_ntt_sol;
  assign prev_eol    = decomp_ntt_eol;
  assign prev_sos    = decomp_ntt_sog;
  assign prev_eos    = decomp_ntt_eog;
  assign prev_pbs_id = decomp_ntt_pbs_id;

  assign decomp_ntt_data_rdy = '1;
  assign decomp_ntt_ctrl_rdy = 1'b1;

  // ============================================================================================ //
  // Instance
  // ============================================================================================ //
  ntt_core_gf64_middle
  #(
    .S_INIT           (S-1),
    .S_NB             (S_NB),
    .USE_PP           (USE_PP),
    .PHI_MULT_TYPE    (PHI_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE),
    .RAM_LATENCY      (RAM_LATENCY),
    .ROM_LATENCY      (ROM_LATENCY),
    .IN_PIPE          (1'b1),
    .TWD_GF64_FILE_PREFIX (TWD_GF64_FILE_PREFIX)
  ) ntt_core_gf64_middle (
    .clk         (clk),
    .s_rst_n     (s_rst_n),

    .prev_data   (prev_data),
    .prev_avail  (prev_avail),
    .prev_sob    (prev_sob),
    .prev_eob    (prev_eob),
    .prev_sol    (prev_sol),
    .prev_eol    (prev_eol),
    .prev_sos    (prev_sos),
    .prev_eos    (prev_eos),
    .prev_pbs_id (prev_pbs_id),

    .next_data   (next_data),
    .next_avail  (next_avail),
    .next_sob    (next_sob),
    .next_eob    (next_eob),
    .next_sol    (next_sol),
    .next_eol    (next_eol),
    .next_sos    (next_sos),
    .next_eos    (next_eos),
    .next_pbs_id (next_pbs_id),

    .bsk         (bsk),
    .bsk_vld     (bsk_vld),
    .bsk_rdy     (bsk_rdy),

    .error       (error)
  );
endmodule
