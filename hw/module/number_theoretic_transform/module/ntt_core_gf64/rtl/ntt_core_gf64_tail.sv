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
// This version is the tail part of the NTT core gf64 : its output interface is formatted for
// the connection with the mmacc.
// ==============================================================================================

module ntt_core_gf64_tail
  import common_definition_pkg::*;
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
#(
  parameter  int               S_INIT           = S-1,// First stage ID
                                                      // Reverse numbering.
                                                      // FWD part : S-1 -> 0
                                                      // BWD part : 2S-1 -> S
  parameter  int               S_NB             = 2*S, // Number of NTT stages.
  parameter  bit               USE_PP           = 1, // If this partition contains the entire FWD NTT,
                                                     // this parameter indicates if the PP is instantiated.
  parameter  arith_mult_type_e PHI_MULT_TYPE    = MULT_KARATSUBA, // PHI multiplier, when needed
  parameter  arith_mult_type_e PP_MULT_TYPE     = MULT_KARATSUBA, // Multiplier used in PP
  parameter  int               RAM_LATENCY      = 1,
  parameter  int               ROM_LATENCY      = 1,
  parameter  bit               IN_PIPE          = 1'b1, // Recommended
  parameter  string            TWD_GF64_FILE_PREFIX  = $sformatf("memory_file/twiddle/NTT_CORE_ARCH_GF64/R%0d_PSI%0d/twd_phi",R,PSI),
  localparam int               ERROR_W          = 1    // pp
)
(
  input  logic                                                 clk,
  input  logic                                                 s_rst_n,

  // Data from previous ntt_core or input logic
  input  logic  [PSI-1:0][R-1:0][MOD_NTT_W+1:0]                prev_data,
  input  logic  [PSI-1:0][R-1:0]                               prev_avail,
  input  logic                                                 prev_sob,
  input  logic                                                 prev_eob,
  input  logic                                                 prev_sol,
  input  logic                                                 prev_eol,
  input  logic                                                 prev_sos,
  input  logic                                                 prev_eos,
  input  logic [BPBS_ID_W-1:0]                                 prev_pbs_id,

  // output logic data to acc
  output logic [PSI-1:0][R-1:0][MOD_NTT_W-1:0]                 ntt_acc_data,
  output logic [PSI-1:0][R-1:0]                                ntt_acc_data_avail,
  output logic                                                 ntt_acc_sob,
  output logic                                                 ntt_acc_eob,
  output logic                                                 ntt_acc_sol,
  output logic                                                 ntt_acc_eol,
  output logic                                                 ntt_acc_sog,
  output logic                                                 ntt_acc_eog,
  output logic [BPBS_ID_W-1:0]                                 ntt_acc_pbs_id,
  output logic                                                 ntt_acc_ctrl_avail,

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
  logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0] next_data;
  logic [PSI-1:0][R-1:0]                next_avail;
  logic                                 next_sob;
  logic                                 next_eob;
  logic                                 next_sol;
  logic                                 next_eol;
  logic                                 next_sos;
  logic                                 next_eos;
  logic [BPBS_ID_W-1:0]                 next_pbs_id;

  // ============================================================================================ //
  // Format output
  // ============================================================================================ //
  always_comb
    for (int p=0; p<PSI; p=p+1)
      for (int r=0; r<R; r=r+1)
        ntt_acc_data[p][r] = next_data[p][r][MOD_NTT_W-1:0]; // truncation

  assign ntt_acc_data_avail  = next_avail;
  assign ntt_acc_sob    = next_sob;
  assign ntt_acc_eob    = next_eob;
  assign ntt_acc_sol    = next_sol;
  assign ntt_acc_eol    = next_eol;
  assign ntt_acc_sog    = next_sos;
  assign ntt_acc_eog    = next_eos;
  assign ntt_acc_pbs_id = next_pbs_id;

  assign ntt_acc_ctrl_avail = next_avail[0][0];

// pragma translate_off
  always_ff @(posedge clk)
    if (next_avail[0])  begin
      for (int p=0; p<PSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          assert(next_data[p][r] < MOD_NTT)
          else begin
            $fatal(1,"%t > ERROR: NTT output [p=%0d][r=%0d] is not in MOD_NTT domain. MOD_NTT=0x%0x seen=0x%0x", $time, p,r,MOD_NTT, next_data[p][r]);
          end
    end
// pragma translate_on

  // ============================================================================================ //
  // Instance
  // ============================================================================================ //
  ntt_core_gf64_middle
  #(
    .S_INIT           (S_INIT),
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
